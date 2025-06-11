--[[
    Character Controller Script

    Handles:
    - Walking & Jumping
    - Picking up & Dropping objects
    - Static arms aiming held object towards pointer
    - Activation of held object components via pointer click
    - Smooth recoil effect on pointer aiming (scaled by distance, consistently upward)
    - Drop velocity calculation based on recent movement history
    - Many more! (todo: update this)
]]

-- SUBMODULES --
local Controller = {} -- Primary class.
local Animation = { -- Handles all animations and player holding logic.
    Legs = {}, -- Handles leg animations and movement.
    Arms = {}, -- Handles arm animations and holding logic.
    Recoil = {}, -- Handles recoil effects when firing weapons.
    Holding = { -- Handles picking up and dropping objects.
        History = {}, -- Keeps track of holding history for dropped objects.
    },
}
local Movement = { -- Applies player force changes and contains logic for special moves.
    Ground = {}, -- Handles ground-related logic like friction and surface normals.
}
local Physics = {} -- How the player moves through the world and accelerates.
local Input = require("core/lib/player/controller/input.lua") -- Handles input polling and key mappings.
local Utils = require("core/lib/player/controller/utils.lua") -- Utility functions for vector math and other helpers.
local Body = {} -- Handles the player's body parts and their properties.
local Camera = require("core/lib/player/controller/camera.lua") -- Handles camera position and movement.

if Utils == nil then
    print("Error: Utils module not found. Ensure it is correctly required.")
    return
end

-- Animation
Animation.Legs.params = {
    WALK_CYCLE_SPEED = 30.0;
    WALK_SWING_AMPLITUDE = math.rad(35);
    JUMP_TUCK_ANGLE = math.rad(20);
    NEUTRAL_ANGLE = math.rad(0);
    LEG_ANGLE_CONTROL_KP = 50.0;
    MAX_MOTOR_SPEED_FOR_LEG_CONTROL = 15.0;
    WALK_TORQUE = 200.0;
    JUMP_TORQUE = 250.0;
    IDLE_TORQUE = 5.0;
}
Animation.Legs.State = {
    walk_cycle_time = 0;
}
Animation.Legs.set_leg_hinge_motor = function(self, hinge, speed, torque)
    if not hinge then return end;
    local speed_prop = hinge:get_property("motor_speed");
    if speed_prop then
        speed_prop.value = -speed;
        hinge:set_property("motor_speed", speed_prop);
    else
         print("Warning: motor_speed property not found for leg hinge")
    end;
    local torque_prop = hinge:get_property("max_motor_torque");
    if torque_prop then
        torque_prop.value = torque;
        hinge:set_property("max_motor_torque", torque_prop);
    else
         print("Warning: max_motor_torque property not found for leg hinge")
    end;
end;

Animation.Legs.get_current_leg_hinge_angle = function(self, hinge_component)
    if not hinge_component then return nil end
    local joint = hinge_component:send_event("core/hinge/get");
    if not joint then return nil end
    local obj_a = joint:get_object_a();
    local obj_b = joint:get_object_b();
    if not obj_a or not obj_b then return nil end
    local angle_a = obj_a:get_angle();
    local angle_b = obj_b:get_angle();
    local relative_angle = angle_b - angle_a;
    relative_angle = math.atan2(math.sin(relative_angle), math.cos(relative_angle));
    return relative_angle;
end

Animation.Legs.calculate_motor_speed_for_leg_angle = function(self, current_angle, target_angle, kp, max_speed)
    if current_angle == nil then return 0 end
    local angle_error = target_angle - current_angle;
    angle_error = math.atan2(math.sin(angle_error), math.cos(angle_error));
    local desired_speed = kp * angle_error;
    desired_speed = math.clamp(desired_speed, -max_speed, max_speed);
    return -desired_speed;
end


Animation.Arms.params = {
    NEUTRAL_ARM_ANGLE_REL = math.rad(58);
    JUMP_TUCK_ARM_ANGLE_REL = math.rad(10);
}
Animation.Arms.pivots = {
    left_arm_pivot = vec2(0, 0);
    right_arm_pivot = vec2(0, 0);
}
Animation.Recoil.params = {
    FIRE_COOLDOWN_DURATION = 0.3;
    RECOIL_APPLICATION_SPEED = 40.0; -- Updated Constant
    RECOIL_DECAY_SPEED = 10.0;   -- Updated Constant
    MIN_RECOIL_DISTANCE_CLAMP = 0.1;
    MAX_HOLD_DISTANCE = 0.4;
}
Animation.Recoil.state = {
    target_pointer_recoil_offset = vec2(0, 0);
    current_pointer_recoil_offset = vec2(0, 0);
}
Animation.Recoil.timers = {
    fire_cooldown_timer = 0;
}
Animation.Holding.state = {
    holding = nil;
    holding_point_left = nil;  -- Local point on object for LEFT arm when NOT flipped
    holding_point_right = nil; -- Local point on object for RIGHT arm when NOT flipped
    original_holding_layers = nil;
    original_holding_bodytype = nil;
}
Animation.Holding.History.state = {
    max_history_frames = 10;
    holding_history_buffer = {};
    history_index = 0;
    holding_cumulative_time = 0;
}
-- Helper to clear holding history and reset cumulative time
Animation.Holding.History.clear_holding_history = function(self)
    self.state.holding_history_buffer = {}
    self.state.history_index = 0
    self.state.holding_cumulative_time = 0
end
Animation.Holding.pick_up = function(self, object_to_hold, local_left_hold_point, local_right_hold_point)
    if self.state.holding or not object_to_hold then
        return
    end
    if not local_left_hold_point or not local_right_hold_point then
         print("Cannot pick up: Missing local hold points.")
        return
    end

    self.state.holding = object_to_hold;
    self.state.holding_point_left = local_left_hold_point;
    self.state.holding_point_right = local_right_hold_point;

    self.state.original_holding_layers = self.state.holding:get_collision_layers();
    self.state.original_holding_bodytype = self.state.holding:get_body_type();

    self.state.holding:set_body_type(BodyType.Static);
    self.state.holding:set_collision_layers({}); -- No collision

    self:clear_holding_history();
end
Animation.Holding.drop_object = function(self)
    local dropped_object = self.state.holding
    if not dropped_object then
        return
    end


    if self.state.original_holding_bodytype ~= nil then
         dropped_object:set_body_type(self.state.original_holding_bodytype);
    else
         dropped_object:set_body_type(BodyType.Dynamic);
         print("Warning: Could not restore original body type for held object.")
    end

    if type(self.state.original_holding_layers) == "table" then
        dropped_object:set_collision_layers(self.state.original_holding_layers);
    else
        dropped_object:set_collision_layers({1})
         print("Warning: Could not restore original collision layers for held object.")
    end

    self.History:drop_object(dropped_object)

    self.state.holding = nil;
    self.state.holding_point_left = nil;
    self.state.holding_point_right = nil;
    self.state.original_holding_layers = nil;
    self.state.original_holding_bodytype = nil;
end
Animation.Holding.History.drop_object = function(self, dropped_object)
    local linear_velocity = vec2(0, 0)
    local angular_velocity = 0
    local current_buffer_size = #self.state.holding_history_buffer
    if current_buffer_size >= 5 then
        local index_now = self.state.history_index
        local index_prev = (self.state.history_index - 4 + self.state.max_history_frames) % self.state.max_history_frames + 1
        local data_now = self.state.holding_history_buffer[index_now]
        local data_prev = self.state.holding_history_buffer[index_prev]
        if data_now and data_prev then
            local time_diff = data_now.time - data_prev.time
            if time_diff > 0.001 then
                local pos_diff = data_now.pos - data_prev.pos
                linear_velocity = pos_diff / time_diff
                local angle_diff = data_now.angle - data_prev.angle
                angle_diff = math.atan2(math.sin(angle_diff), math.cos(angle_diff))
                angular_velocity = angle_diff / time_diff
            end
        end
    end

    dropped_object:set_linear_velocity(linear_velocity);
    dropped_object:set_angular_velocity(angular_velocity);
end



Animation.Recoil.update_timers = function(self, dt)
    self.timers.fire_cooldown_timer = math.max(0, self.timers.fire_cooldown_timer - dt)
end

Animation.Recoil.update_recoil = function(self, dt, lerp_vec2)
    self.state.current_pointer_recoil_offset = lerp_vec2(self.state.current_pointer_recoil_offset, self.state.target_pointer_recoil_offset, dt * self.params.RECOIL_APPLICATION_SPEED)
    self.state.target_pointer_recoil_offset = lerp_vec2(self.state.target_pointer_recoil_offset, vec2(0, 0), dt * self.params.RECOIL_DECAY_SPEED)
    if self.state.target_pointer_recoil_offset:length() ^ 2 < 0.00001 then
        self.state.target_pointer_recoil_offset = vec2(0, 0)
        if self.state.current_pointer_recoil_offset:length() ^ 2 < 0.00001 then
            self.state.current_pointer_recoil_offset = vec2(0, 0)
        end
    end
end

Animation.update_timers = function(self, dt)
    self.Recoil:update_timers(dt)
end

-- Body
Body.parts = {
    body = nil;
    left_foot = nil;
    right_foot = nil;
    left_arm = nil;
    right_arm = nil;
    head = nil;
}
Body.hinges = {
    left_hinge = nil; -- Hinge for left leg
    right_hinge = nil; -- Hinge for right leg
}
Body.get_body_mass = function(self)
    local b = self.parts
    if b.body and b.left_foot and b.right_foot and 
       b.left_arm and b.right_arm and b.head then
        return b.body:get_mass() + b.left_foot:get_mass() + b.right_foot:get_mass() +
               b.left_arm:get_mass() + b.right_arm:get_mass() + b.head:get_mass()
    else
        print("Physics Error: Body parts not initialized correctly at Physics.get_body_mass."
        .. "The missing body parts are: "
        .. (b.body and "" or "body, ")
        .. (b.left_foot and "" or "left_foot, ")
        .. (b.right_foot and "" or "right_foot, ")
        .. (b.left_arm and "" or "left_arm, ")
        .. (b.right_arm and "" or "right_arm, ")
        .. (b.head and "" or "head, "))

        return 1.0
    end
end

local player = Scene:get_host();



Movement.params = {
    acceleration_time = 10; -- Multiplies the time it takes to reach a given speed
    air_acceleration_time = 20; -- Multiplies the time it takes to reach a given speed in air
    max_speed = 5; -- Asymptote of the velocity curve
    damping_base = 0.8; -- Velocity is multiplied by this every frame when button is released
    air_damping_base = 0.9; -- Damping in air
    jump_input_time = 0.2; -- How long the jump button can be held before it is ignored
    jump_impulse = 1; -- Impulse applied when jumping
    current_speed_factor = 0.05; -- How much to add to jump force based on current speed
    max_jump_impulse_bonus = 0; -- Maximum impulse that can be added via bounce jumping and from current speed
    jump_hold_force = 25.0; -- Force applied while holding jump button
    jump_time = 0.5; -- Time in seconds the jump button can be held for
    coyote_time = 0.2; -- Time in seconds to allow jumping after leaving ground
    bhop_max_speed_factor = 1.5; -- How much to multiply the max speed by when bhopping
    bhop_speedup_factor = 0.75; -- Distance to bhop_max_speed_factor is multiplied by this every jump (higher = slower)
    bhop_time = 0.2; -- How long bhop boost lasts after touching floor
    backflip_speed = 20.0; -- Speed multiplier for backflip
    landing_window = 0.2; -- Time window to do tricks after landing
    roll_time = 0.5; -- How long the roll lasts
    roll_input_time = 0.2; -- How long the roll input is valid
    roll_speed_threshold = 2; -- Minimum speed to allow rolling
    roll_max_speed_increase = 5; -- Maximum speed increase from rolling
    bounce_cancellation_threshold = 3; -- Speed threshold to cancel bounces on landing
};

Movement.timers = {
    coyote = 0; -- Coyote time for jump forgiveness
    bhop = 0; -- Timer for bhop boost
    jump_end = 0; -- Timer for jump hold during the jump
    jump_input = 0; -- Timer for jump input hold before the jump
    landing = 0; -- Timer for right after touching ground
    rolling = 0; -- Timer for rolls
    roll_input = 0; -- Timer for roll input
}
Movement.state = {
    on_ground = false; -- Whether the player is currently on the ground
    jumping = false; -- Whether the player is currently jumping
    just_jumped = false; -- Whether the player just jumped this frame
    roll_direction = 0; -- Direction of the roll, 1 for right, -1 for left, 0 for no roll
    bhop_speedup = 1; -- Speed multiplier for bhop boost, cannot exceed bhop_max_speed_factor
    spin_angle = 0; -- Angle for spinning the player around
    last_velocity = vec2(0, 0); -- Last velocity of the player
}

Movement.Ground.state = {
    ground_friction = 0.1;
    ground_surface_normal = vec2(0,1); -- Normal of the ground surface
    ground_surface_velocity = vec2(0,0); -- For moving surfaces like cars
    ground_object = nil; -- The object the player is currently standing on
}

Movement.Ground.check_ground = function(self, body, parts)
    local center_offset = vec2(0, -0.2)
    local left_offset = vec2(-0.2, -0.2)
    local right_offset = vec2(0.2, -0.2)
    local ray_offsets = {center_offset, left_offset, right_offset}
    
    local found_ground = false
    local current_ground_normal = vec2(0, 1)
    local current_ground_velocity = vec2(0, 0)
    local current_ground_friction = 0.1
    local current_ground_object = nil
    
    -- Check each ray position
    for _, offset in ipairs(ray_offsets) do
        local ground_check_origin = body:get_world_point(offset)
        if ground_check_origin then
            local hits = Scene:raycast({
                origin = ground_check_origin, 
                direction = Physics:down(),
                distance = 0.2, 
                closest_only = false,
            })
            
            for i = 1, #hits do
                local visited = {}
                local found = {}
                local function scan_connected(obj)
                    if obj == nil or visited[obj.id] then return end
                    visited[obj.id] = true
                    table.insert(found, obj)
                    local connected_objs = obj:get_direct_connected()
                    for _, next_obj in ipairs(connected_objs) do scan_connected(next_obj) end
                end
                scan_connected(hits[i].object)
                
                local connected_to_self = false
                for _, obj in ipairs(found) do
                    if obj.id == body.id or obj.id == parts.left_arm.id or obj.id == parts.right_arm.id then
                        connected_to_self = true
                        break
                    end
                end
                
                if not connected_to_self then
                    found_ground = true
                    if Movement.state.on_ground == false then
                        Movement.timers.landing = Movement.params.landing_window
                    end
                    Movement.state.on_ground = true
                    current_ground_normal = hits[i].normal
                    current_ground_velocity = hits[i].object:get_linear_velocity()
                    current_ground_friction = hits[i].object:get_friction()
                    current_ground_object = hits[i].object
                    if Movement.timers.jump_end <= 0 then
                        Movement.timers.coyote = Movement.params.coyote_time
                        Movement.state.jumping = false
                    end
                    break
                end
            end
            
            -- If we found ground with this ray, no need to check others
            if found_ground then break end
        end
    end
    
    -- If no ground found across any rays
    if not found_ground then
        Movement.state.on_ground = false
        Movement.state.jumping = true
        self.state.ground_surface_normal = Physics:up()
        self.state.ground_surface_velocity = self.state.ground_surface_velocity -- Velocity is retained from last surface
        self.state.ground_friction = 0.1
        self.state.ground_object = nil
    else
        self.state.ground_surface_normal = current_ground_normal
        self.state.ground_surface_velocity = current_ground_velocity
        self.state.ground_friction = current_ground_friction
        self.state.ground_object = current_ground_object
    end
end

Movement.Ground.try_apply_force_to_ground = function(self, force)
    if self.state.ground_object then
        local ground_point = self.state.ground_object:get_world_point(Body:get_position())
        if ground_point then
            self.state.ground_object:apply_force(force, ground_point)
        else
            print("Error: Failed to get world point for ground object in Movement.Ground.try_apply_force_to_ground")
        end
    end
end

Movement.update_last_velocity = function(self, body)
    if not body then
        print("Error: Body component not found in Movement.update_last_velocity")
        return
    end
    local current_velocity = body:get_linear_velocity()
    if not current_velocity then
        print("Error: Failed to get linear velocity in Movement.update_last_velocity")
        return
    end
    self.state.last_velocity = current_velocity
end

Physics.get_gravity = function(self)
    return Scene:get_gravity() or vec2(0, -9.81) -- Default to Earth gravity if not set
end
Physics.on_start = function(self, bodyparts, movement_parameters)
    if not bodyparts or not bodyparts.body then
        print("Physics Error: Body parts not initialized correctly. at Physics.on_start")
        return
    end

    self.movement_parameters = movement_parameters or Movement.params

    -- -- Set up the physics properties for the body parts
    -- for _, part in pairs(bodyparts) do
    --     if part then
    --         part:set_body_type(BodyType.Dynamic)
    --         part:set_collision_layers({1}) -- Default collision layer
    --         part:set_friction(0.5) -- Default friction
    --     end
    -- end
end
Physics.get_gravity_force = function(self)
    return self:get_gravity() * Body:get_body_mass()
end
Physics.down = function(self)
    return self:get_gravity():normalize()
end
Physics.up = function(self)
    return -self:down()
end
Physics.make_velocity_relative_to_ground = function(self, body, velocity)
    if not body or not velocity then return vec2(0, 0) end
    local ground_surface_velocity = Movement.Ground.state.ground_surface_velocity
    return velocity - ground_surface_velocity
end
Physics.get_velocity_relative_to_ground = function(self, body)
    if not body then return vec2(0, 0) end
    local current_velocity = body:get_linear_velocity()
    if not current_velocity then return vec2(0, 0) end
    return self:make_velocity_relative_to_ground(body, current_velocity)
end
Physics.rotate_vector_down = function(self, vector, ground_surface_normal)
    local ground_angle = math.atan2(ground_surface_normal.y, ground_surface_normal.x) - math.pi/2
    local rotated_vector = vector:rotate(-ground_angle)
    return rotated_vector
end

Body.get_position = function(self)
    local body = self.parts.body
    if body then
        return body:get_position() or vec2(0, 0)
    else
        print("Error: Body component not found.")
        return vec2(0, 0)
    end
end

Body.get_world_point = function(self, vector)
    local body = self.parts.body
    if body then
        return body:get_world_point(vector) or vec2(0, 0)
    else
        print("Error: Body component not found.")
        return vec2(0, 0)
    end
end

Body.get_angular_velocity = function(self)
    local body = self.parts.body
    if body then
        return body:get_angular_velocity() or 0
    else
        print("Error: Body component not found.")
        return 0
    end
end

Body.calculate_arm_pivots = function(self, left_arm_pivot, right_arm_pivot)
    local body = self.parts.body
    local left_pivot_world = self:get_world_point(left_arm_pivot)
    local right_pivot_world = self:get_world_point(right_arm_pivot)
    if not left_pivot_world or not right_pivot_world then
        print("Error: Failed to get world pivot points.")
        left_pivot_world = self:get_position()
        right_pivot_world = self:get_position()
    end
    return left_pivot_world, right_pivot_world
end

-- Individual module initialization functions
Body.on_start = function(self, saved_data)
    self.hinges.left_hinge = saved_data.left_hinge
    self.hinges.right_hinge = saved_data.right_hinge
    self.parts.body = saved_data.body
    self.parts.left_foot = saved_data.left_foot
    self.parts.right_foot = saved_data.right_foot
    self.parts.left_arm = saved_data.left_arm
    self.parts.right_arm = saved_data.right_arm
    self.parts.head = saved_data.head
    
    -- Configure arms
    if self.parts.left_arm then
        self.parts.left_arm:set_body_type(BodyType.Static)
        self.parts.left_arm:set_collision_layers({}) -- No collision
    end
    if self.parts.right_arm then
        self.parts.right_arm:set_body_type(BodyType.Static)
        self.parts.right_arm:set_collision_layers({}) -- No collision
    end
end

Body.on_save = function(self)
    return {
        left_hinge = self.hinges.left_hinge,
        right_hinge = self.hinges.right_hinge,
        body = self.parts.body,
        left_foot = self.parts.left_foot,
        right_foot = self.parts.right_foot,
        left_arm = self.parts.left_arm,
        right_arm = self.parts.right_arm,
        head = self.parts.head
    }
end

Animation.Arms.on_start = function(self, saved_data)
    self.pivots.left_arm_pivot = saved_data.left_arm_pivot or vec2(-0.1, 0.15)
    self.pivots.right_arm_pivot = saved_data.right_arm_pivot or vec2(0.1, 0.15)
end

Animation.Arms.on_save = function(self)
    return {
        left_arm_pivot = self.pivots.left_arm_pivot,
        right_arm_pivot = self.pivots.right_arm_pivot
    }
end

Animation.Legs.on_start = function(self, saved_data)
    self.State.walk_cycle_time = saved_data.walk_cycle_time or 0
end

Animation.Legs.on_save = function(self)
    return {
        walk_cycle_time = self.State.walk_cycle_time
    }
end

Animation.Holding.History.on_start = function(self, saved_data)
    self:clear_holding_history()
    self.state.holding_cumulative_time = saved_data.holding_cumulative_time or 0
end

Animation.Holding.History.on_save = function(self)
    return {
        holding_cumulative_time = self.state.holding_cumulative_time
    }
end

Animation.Holding.on_start = function(self, saved_data)
    self.state.holding = saved_data.holding
    self.state.holding_point_left = saved_data.holding_point_left
    self.state.holding_point_right = saved_data.holding_point_right
    self.state.original_holding_layers = saved_data.original_holding_layers
    self.state.original_holding_bodytype = saved_data.original_holding_bodytype
    
    self.History:on_start(saved_data)
    
    if self.state.holding then
        if self.state.holding:get_body_type() ~= BodyType.Static then
            print("Warning: Held object was not static on load, forcing static.")
            self.state.holding:set_body_type(BodyType.Static)
        end
        self.state.holding:set_collision_layers({}) -- No collision
    end
end

Animation.Holding.on_save = function(self)
    local history_data = self.History:on_save()
    return {
        holding = self.state.holding,
        holding_point_left = self.state.holding_point_left,
        holding_point_right = self.state.holding_point_right,
        original_holding_layers = self.state.original_holding_layers,
        original_holding_bodytype = self.state.original_holding_bodytype,
        holding_cumulative_time = history_data.holding_cumulative_time
    }
end

Animation.Recoil.on_start = function(self)
    self.timers.fire_cooldown_timer = 0
    self.state.target_pointer_recoil_offset = vec2(0, 0)
    self.state.current_pointer_recoil_offset = vec2(0, 0)
end

Animation.Recoil.on_save = function(self)
    return {}  -- No persistent data needed for recoil
end

Animation.on_start = function(self, saved_data)
    self.Arms:on_start(saved_data)
    self.Legs:on_start(saved_data)
    self.Holding:on_start(saved_data)
    self.Recoil:on_start() -- No saved data needed for recoil
end

Animation.on_save = function(self)
    local arms_data = self.Arms:on_save()
    local legs_data = self.Legs:on_save()
    local holding_data = self.Holding:on_save()
    
    -- Merge the tables
    local result = {}
    for k, v in pairs(arms_data) do result[k] = v end
    for k, v in pairs(legs_data) do result[k] = v end
    for k, v in pairs(holding_data) do result[k] = v end
    
    return result
end

-- Initialization Function
function on_start(saved_data)
    Controller:on_start(saved_data)
end

Controller.on_start = function(self, saved_data)
    Body:on_start(saved_data)
    Animation:on_start(saved_data)
    Camera:on_start(Body, player)
    Physics:on_start(Body.parts, Movement.params)
    Input:on_start(player)
end

-- Save Function
function on_save()
    return Controller:on_save()
end

Controller.on_save = function(self)
    local body_data = Body:on_save()
    local animation_data = Animation:on_save()
    
    -- Merge the data tables
    local result = {}
    for k, v in pairs(body_data) do result[k] = v end
    for k, v in pairs(animation_data) do result[k] = v end
    
    return result
end



Movement.begin_spin = function(self)
    local current_velocity = Physics:get_velocity_relative_to_ground(Body.parts.body)
    local movement_direction = current_velocity.x < 0 and -1 or 1
    self.state.spin_angle = math.pi/4 * -movement_direction
end

Movement.roll = function(self)
    self.timers.rolling = self.params.roll_time;
    local velocity = Physics:get_velocity_relative_to_ground(Body.parts.body);
    if velocity.x > 0 then
        self.state.roll_direction = 1; -- Roll right
    elseif velocity.x < 0 then
        self.state.roll_direction = -1; -- Roll left
    else
        self.state.roll_direction = 0; -- No roll direction
    end
    self:begin_spin()
end

Movement.is_roll_possible = function(self)
    if self.timers.landing == 0 then
        return false;
    end
    if self.timers.rolling > 0 then
        return false; -- Already rolling
    end
    local velocity = Physics:get_velocity_relative_to_ground(Body.parts.body);
    if math.abs(velocity.x) < self.params.roll_speed_threshold then
        return false; -- Not moving enough to roll
    end
    return true;
end

Movement.handle_roll = function(self)
    if Input.get.roll() then
        self.timers.roll_input = self.params.roll_input_time; -- Reset roll input timer
    end
    if self.timers.roll_input > 0 and self:is_roll_possible() then
        self:roll()
    end
end

Movement.jump = function(self)
    self.timers.jump_input = 0;
    self.timers.coyote = 0; -- Reset coyote timer on jump
    self.state.jumping = true;
    self.state.just_jumped = true;
    self.timers.jump_end = self.params.jump_time;
end

Movement.is_jump_possible = function(self)
    return self.state.on_ground or self.timers.coyote > 0
end

Movement.handle_jump = function(self, jump_input)
    if jump_input then
        self.timers.jump_input = self.params.jump_input_time;
    end
    if self.timers.jump_input > 0 and self:is_jump_possible() then
        self:jump()
    end
end

Animation.Holding.handle_pick_up = function(self, pick_up_input)
    if pick_up_input then
        if self.state.holding then
            self:drop_object()
        end
        local objs = Scene:get_objects_in_circle({ position = player:pointer_pos(), radius = 0 });
        for i = 1, #objs do
            if (objs[i]:get_body_type() == BodyType.Dynamic) and (objs[i]:get_mass() < 1) then
                self:pick_up(objs[i], vec2(-0.075, 0), vec2(0.075, 0));
                break;
            end
        end
    end
end

Animation.Holding.handle_drop = function(self, drop_input)
    if drop_input then
        if self.state.holding then
            self:drop_object()
        end
    end
end


-- Update Function (Input polling)
function on_update(dt)
    Controller:on_update(dt)
end
Controller.on_update = function(self, dt)
    Movement:handle_jump(Input.get.jump())
    Movement:handle_roll(Input.get.roll())
    Animation.Holding:handle_pick_up(Input.get.pick_up())
    Animation.Holding:handle_drop(Input.get.drop())
    Camera:update_camera()
end

Movement.calculate_nudge_direction = function(self)
        if self.timers.rolling > 0 then
            return self.state.roll_direction
        end
        local move_left = Input.get.move_left();
        local move_right = Input.get.move_right();
        if move_left and not move_right then
            return -1;
        elseif move_right and not move_left then
            return 1;
        else
            return 0;
        end;
    end

Animation.Legs.handle_locomotion = function(self, dt, is_jumping, input)
        local move_left = input.move_left();
        local move_right = input.move_right();
        local target_left_leg_angle = self.params.NEUTRAL_ANGLE
        local target_right_leg_angle = self.params.NEUTRAL_ANGLE
        local target_leg_torque = self.params.IDLE_TORQUE

        if is_jumping then
            target_left_leg_angle = self.params.JUMP_TUCK_ANGLE
            target_right_leg_angle = -self.params.JUMP_TUCK_ANGLE
            target_leg_torque = self.params.JUMP_TORQUE
        elseif move_left or move_right then
            local body_vel = Body.parts.body:get_linear_velocity()
            local horizontal_vel_mag = (body_vel and math.abs(body_vel.x)) or 0
            local vel_scale = math.min(math.max(horizontal_vel_mag, 0.4), 1.0)
            self.State.walk_cycle_time = self.State.walk_cycle_time + (dt * self.params.WALK_CYCLE_SPEED * vel_scale)
            local swing_offset = math.sin(self.State.walk_cycle_time) * self.params.WALK_SWING_AMPLITUDE
            target_left_leg_angle = self.params.NEUTRAL_ANGLE + swing_offset * vel_scale
            target_right_leg_angle = self.params.NEUTRAL_ANGLE - swing_offset * vel_scale
            target_leg_torque = self.params.WALK_TORQUE
        else
            target_left_leg_angle = self.params.NEUTRAL_ANGLE
            target_right_leg_angle = self.params.NEUTRAL_ANGLE
            target_leg_torque = self.params.IDLE_TORQUE
        end

        if Body.hinges.left_hinge and Body.hinges.right_hinge then
            local current_left_leg_angle = self:get_current_leg_hinge_angle(Body.hinges.left_hinge)
            local current_right_leg_angle = self:get_current_leg_hinge_angle(Body.hinges.right_hinge)
            local desired_left_leg_speed = self:calculate_motor_speed_for_leg_angle(current_left_leg_angle, target_left_leg_angle, self.params.LEG_ANGLE_CONTROL_KP, self.params.MAX_MOTOR_SPEED_FOR_LEG_CONTROL)
            local desired_right_leg_speed = self:calculate_motor_speed_for_leg_angle(current_right_leg_angle, target_right_leg_angle, self.params.LEG_ANGLE_CONTROL_KP, self.params.MAX_MOTOR_SPEED_FOR_LEG_CONTROL)
            self:set_leg_hinge_motor(Body.hinges.left_hinge, desired_left_leg_speed, target_leg_torque)
            self:set_leg_hinge_motor(Body.hinges.right_hinge, desired_right_leg_speed, target_leg_torque)
        end
    end

    Animation.Arms.handle_holding = function(self, left_pivot_world, right_pivot_world, dt)
        if not Animation.Holding.state.holding then
            return;
        end;
        -- Currently Holding an Object

        local hold_center = (left_pivot_world + right_pivot_world) / 2.0;

        -- Calculate effective pointer position including scaled, smoothed recoil
        local raw_pointer_pos = player:pointer_pos()
        local distance_to_pointer = (raw_pointer_pos - hold_center):length()
        local scale_factor = math.max(Animation.Recoil.params.MIN_RECOIL_DISTANCE_CLAMP, distance_to_pointer)
        local effective_recoil_offset = Animation.Recoil.state.current_pointer_recoil_offset * scale_factor
        local pointer_world = raw_pointer_pos + effective_recoil_offset;

        -- Calculate aiming direction vector and distance
        local hold_direction_vec = pointer_world - hold_center;
        local current_aim_dist = hold_direction_vec:length();
        local effective_hold_dist = math.min(current_aim_dist, Animation.Recoil.params.MAX_HOLD_DISTANCE);

        -- Calculate normalized aiming direction
        local hold_direction_normalized;
        if current_aim_dist < 0.001 then
             hold_direction_normalized = Body.parts.body:get_right_direction() or vec2(1,0);
             effective_hold_dist = 0;
        else
             hold_direction_normalized = hold_direction_vec:normalize();
        end

        -- Calculate target position and base angle
        local target_holding_pos = hold_center + hold_direction_normalized * effective_hold_dist;
        local target_holding_angle = math.atan2(hold_direction_normalized.y, hold_direction_normalized.x);

        -- Determine if the object should be visually flipped
        local is_flipped = (pointer_world.x < hold_center.x);

        -- Apply visual flip to angle if needed
        if false then
            target_holding_angle = target_holding_angle + math.pi
            target_holding_angle = math.atan2(math.sin(target_holding_angle), math.cos(target_holding_angle))
        end

        -- Set the held object's final transform
        Animation.Holding.state.holding:set_position(target_holding_pos);
        Animation.Holding.state.holding:set_angle(target_holding_angle);

        -- Update drop velocity history buffer
        Animation.Holding.History.state.holding_cumulative_time = Animation.Holding.History.state.holding_cumulative_time + dt
        Animation.Holding.History.state.history_index = (Animation.Holding.History.state.history_index % Animation.Holding.History.state.max_history_frames) + 1
        Animation.Holding.History.state.holding_history_buffer[Animation.Holding.History.state.history_index] = {
             pos = target_holding_pos, angle = target_holding_angle, time = Animation.Holding.History.state.holding_cumulative_time
        }

        -- Position the static arms - **CRITICAL CHANGE HERE**
        local target_left_hand_world = nil
        local target_right_hand_world = nil

        -- Determine which local points on the held object the arms should connect to
        -- This ensures arms connect correctly regardless of the object's visual flip
        local effective_left_hold_point = Animation.Holding.state.holding_point_left   -- Default: left arm connects to left point
        local effective_right_hold_point = Animation.Holding.state.holding_point_right -- Default: right arm connects to right point

        if is_flipped then
            -- If visually flipped, swap the effective points
            effective_left_hold_point = Animation.Holding.state.holding_point_right -- Left arm connects to what *was* the right point
            effective_right_hold_point = Animation.Holding.state.holding_point_left  -- Right arm connects to what *was* the left point
        end

        -- Get the world coordinates of these effective connection points
        target_left_hand_world = Animation.Holding.state.holding:get_world_point(effective_left_hold_point);
        target_right_hand_world = Animation.Holding.state.holding:get_world_point(effective_right_hold_point);


        -- Calculate arm angles based on the determined target points
        if not target_left_hand_world or not target_right_hand_world then
             print("Holding logic error: Cannot get world points on held object.")
        else
             local left_arm_full_vector = target_left_hand_world - left_pivot_world;
             local right_arm_full_vector = target_right_hand_world - right_pivot_world;
             -- Keep the Pi offset for the left arm assuming its sprite points rightwards initially
             local left_arm_angle = math.atan2(left_arm_full_vector.y, left_arm_full_vector.x) + math.pi;
             local right_arm_angle = math.atan2(right_arm_full_vector.y, right_arm_full_vector.x);
             left_arm_angle = math.atan2(math.sin(left_arm_angle), math.cos(left_arm_angle));
             right_arm_angle = math.atan2(math.sin(right_arm_angle), math.cos(right_arm_angle));
             Body.parts.left_arm:set_position(left_pivot_world); Body.parts.left_arm:set_angle(left_arm_angle);
             Body.parts.right_arm:set_position(right_pivot_world); Body.parts.right_arm:set_angle(right_arm_angle);
        end

        -- Activation Check
        if player:pointer_pressed() and Animation.Recoil.timers.fire_cooldown_timer <= 0 then
            Animation.Recoil.timers.fire_cooldown_timer = Animation.Recoil.params.FIRE_COOLDOWN_DURATION;
            local total_recoil_this_frame = 0;
            local holding_components = Animation.Holding.state.holding:get_components();
            for i=1,#holding_components do
                local output = holding_components[i]:send_event("activate");
                if type(output) == "table" and type(output.recoil) == "number" then
                    total_recoil_this_frame = total_recoil_this_frame + output.recoil;
                end
            end;

            if total_recoil_this_frame > 0 then
                if hold_direction_normalized then
                    local perp_recoil_dir = vec2(-hold_direction_normalized.y, hold_direction_normalized.x)
                    if perp_recoil_dir.y < 0 then
                        perp_recoil_dir = perp_recoil_dir * -1 -- Ensure upward recoil
                    end
                    local recoil_impulse_vector = perp_recoil_dir * total_recoil_this_frame;
                    Animation.Recoil.state.target_pointer_recoil_offset = Animation.Recoil.state.target_pointer_recoil_offset + recoil_impulse_vector;
                else
                    print("Warning: Cannot calculate recoil direction because aim direction is degenerate.")
                end
            end
        end -- End of activation check
    end

Animation.Arms.handle_neutral = function(self, left_pivot_world, right_pivot_world, body, left_arm, right_arm, is_jumping, walk_cycle_time, input)
    -- Handle logic for neutral arm positions
    local target_left_arm_rel_angle = self.params.NEUTRAL_ARM_ANGLE_REL
    local target_right_arm_rel_angle = -self.params.NEUTRAL_ARM_ANGLE_REL

    if is_jumping then
        target_left_arm_rel_angle = target_left_arm_rel_angle + self.params.JUMP_TUCK_ARM_ANGLE_REL
        target_right_arm_rel_angle = target_right_arm_rel_angle - self.params.JUMP_TUCK_ARM_ANGLE_REL
    elseif input.move_left() or input.move_right() then
        local body_vel = body:get_linear_velocity()
        local horizontal_vel_mag = (body_vel and math.abs(body_vel.x)) or 0
        local vel_scale = math.min(math.max(horizontal_vel_mag, 0.4), 1.0)
        local swing_offset = math.sin(walk_cycle_time) * Animation.Legs.params.WALK_SWING_AMPLITUDE
        target_left_arm_rel_angle = self.params.NEUTRAL_ARM_ANGLE_REL - (swing_offset * vel_scale * 0.6)
        target_right_arm_rel_angle = -self.params.NEUTRAL_ARM_ANGLE_REL + (swing_offset * vel_scale * 0.6)
    end

    local body_angle = body:get_angle()
    local final_world_left_arm_angle = body_angle + target_left_arm_rel_angle
    local final_world_right_arm_angle = body_angle + target_right_arm_rel_angle

    left_arm:set_position(left_pivot_world)
    left_arm:set_angle(final_world_left_arm_angle)
    right_arm:set_position(right_pivot_world)
    right_arm:set_angle(final_world_right_arm_angle)
end

Animation.Arms.handle = function(self, left_pivot_world, right_pivot_world, body_parts, is_jumping, walk_cycle_time, dt, input)
    if Animation.Holding.state.holding then
        -- Handle logic for holding an object
        self:handle_holding(left_pivot_world, right_pivot_world, dt)
    else
        -- Handle logic for neutral arm positions
        self:handle_neutral(left_pivot_world, right_pivot_world, 
            body_parts.body, 
            body_parts.left_arm, 
            body_parts.right_arm, 
            is_jumping,
            walk_cycle_time,
            input
        )
    end
end

Movement.straighten = function(self, body_parts)
    local time = 1
    local body = body_parts.body

    local target_vector = self.Ground.state.ground_surface_normal
    target_vector = target_vector:rotate(self.state.spin_angle)

    local current_angle = body:get_angle() + math.pi/2
    local target_angle = math.atan2(target_vector.y, target_vector.x)
    local current_angular_velocity = body:get_angular_velocity()
    local angular_velocity_rotation = current_angular_velocity * time
    local angle_diff = target_angle - current_angle + angular_velocity_rotation
    local angle_diff_clamped = math.atan2(math.sin(angle_diff), math.cos(angle_diff))
    local straightening_force_magnitude = math.abs(angle_diff_clamped*(self.state.spin_angle == 0 and 10 or 20))

    local straightening_force = target_vector * straightening_force_magnitude

    local gravity_countering_force = -Utils.reflect(Physics:get_gravity_force(), -self.Ground.state.ground_surface_normal)

    return straightening_force, gravity_countering_force
end

Movement.calculate_next_bhop_speedup = function(self, bhop_speedup_factor, bhop_max_speed_factor, bhop_time, current_speedup) -- Called every jump
    local new_speedup = bhop_max_speed_factor-((bhop_max_speed_factor-current_speedup)*bhop_speedup_factor)
    return math.min((new_speedup), bhop_max_speed_factor)
end

Movement.bhop_jump_update = function(self)
    if self.timers.bhop > 0 then
        self.state.bhop_speedup = self:calculate_next_bhop_speedup(
            self.params.bhop_speedup_factor,
            self.params.bhop_max_speed_factor,
            self.params.bhop_time,
            self.state.bhop_speedup
        )
    end
    self.timers.bhop = self.params.bhop_time
end
    
Physics.calculate_horizontal_velocity = function(self, max_speed, acceleration_time, damping_base, current_horizontal_velocity, is_moving)
    -- Formula for key pressed is (n-x)^2/t, where n is the max speed, x is the current speed, and t is the acceleration time
    -- Formula for key released is x * d, where d is the damping base
    local sign = current_horizontal_velocity < 0 and -1 or 1
    local x = math.abs(current_horizontal_velocity) -- Will be undone on return
    local calculated_velocity = x
    if is_moving and x <= max_speed then
        calculated_velocity = x + ((max_speed - x) ^ 2) / acceleration_time
    else
        calculated_velocity = x * damping_base
    end
    return calculated_velocity * sign
end

Physics.calculate_force = function(self, current_horizontal_velocity, target_velocity)
    -- Calculate the force needed to reach the target velocity
    local dt = 1.0 / 60.0 -- Default dt if not provided
    local acceleration = (target_velocity - current_horizontal_velocity) / dt
    local force = acceleration * Body:get_body_mass()
    return force
end

Physics.get_horizontal_forces = function(self, dt, movement_parameters)
    local nudge_direction = Movement:calculate_nudge_direction()
    
    -- Calculate the perpendicular vector to the ground normal (tangent to ground)
    local ground_tangent = Movement.Ground.state.ground_surface_normal:rotate(-math.pi/2)

    local tangent_velocity = self:rotate_vector_down(self:get_velocity_relative_to_ground(Body.parts.body), Movement.Ground.state.ground_surface_normal)
    
    local is_moving = (nudge_direction ~= 0)
    local vel_x = tangent_velocity.x
    local is_slowing_down = (vel_x * nudge_direction < 0) -- If trying to move in the opposite direction of current velocity
    if is_slowing_down then
        vel_x = vel_x * -0.01
    end
    local target_velocity = self:calculate_horizontal_velocity(
        Movement.params.max_speed * Movement.state.bhop_speedup + (Movement.timers.rolling > 0 and Movement.params.roll_max_speed_increase or 0),
        Movement.state.on_ground and Movement.params.acceleration_time or Movement.params.air_acceleration_time,
        Movement.state.on_ground and Movement.params.damping_base or Movement.params.air_damping_base,
        vel_x,
        is_moving
    )
    local force = self:calculate_force(vel_x, target_velocity)
    -- Calculate horizontal component along the ground
    local rotated_force = ground_tangent * force

    return rotated_force
end

Physics.get_jump_force = function(self, dt, multiplier, movement_parameters)
    Movement.state.just_jumped = false
    local relative_velocity = self:rotate_vector_down(self:get_velocity_relative_to_ground(Body.parts.body), Movement.Ground.state.ground_surface_normal)

    -- Current velocity cancellation
    local force_to_cancel_vertical_speed
    if relative_velocity.y < 0 then
        force_to_cancel_vertical_speed = math.abs(relative_velocity.y) * Body:get_body_mass()
    else
        force_to_cancel_vertical_speed = math.min(math.abs(relative_velocity.y) * Body:get_body_mass(), movement_parameters.max_jump_impulse_bonus)
        -- Visually show boost
        -- if impulse_to_cancel_vertical_speed == movement_parameters.max_jump_bounce then
        --     print("nice!")
        --     begin_spin()
        -- end
    end

    -- Speed bonus to reward running jumps
    local current_speed_bonus = math.min(math.abs(relative_velocity.x) * movement_parameters.current_speed_factor, movement_parameters.max_jump_impulse_bonus)

    local force = self:up() * (movement_parameters.jump_impulse * multiplier + current_speed_bonus + force_to_cancel_vertical_speed)
    local impulse = force / dt
    return impulse
end

Physics.get_vertical_forces = function(self, dt, movement_parameters)
    if Movement.state.just_jumped then
        Movement:bhop_jump_update()
        return self:get_jump_force(dt, 1, movement_parameters)
    end
    if Movement.timers.jump_end > 0 then
        if not Input.get.hold_jump() then
            Movement.timers.jump_end = 0 -- Cancel jump if W is released
            if Body.parts.body then
                local force = self:down() * movement_parameters.jump_impulse * 0.5;
                local impulse = force / dt;
                return impulse;
            end
        end
        if Body.parts.body then
            return self:up() * movement_parameters.jump_hold_force * (Movement.timers.jump_end/movement_parameters.jump_time)^4;
        end
    end
    return vec2(0, 0)
end

Body.apply_all_forces = function(self, force, angular_force, straightening_force, gravity_countering_force)
    local body = self.parts.body
    if body == nil then
        print("Error: Body component not found.")
        return
    end
    body:apply_force_to_center(force)
    body:apply_torque(angular_force)
    body:apply_force_to_center(straightening_force)
    body:apply_force_to_center(gravity_countering_force)

    local left_foot = self.parts.left_foot
    local right_foot = self.parts.right_foot
    if left_foot then
        local fp_world = left_foot:get_world_point(vec2(0, -0.2))
        if fp_world then left_foot:apply_force(-straightening_force/2, fp_world) end
    end
    if right_foot then
        local fp_world = right_foot:get_world_point(vec2(0, -0.2))
        if fp_world then right_foot:apply_force(-straightening_force/2, fp_world) end
    end
    Movement.Ground:try_apply_force_to_ground(force*0.01)
end

Physics.get_angular_forces = function(self)
    return Body:get_angular_velocity() * -0.5 -- Damping angular velocity
end

Physics.get_bounce_cancelling_force = function(self, dt, last_velocity, threshold)
    local relative_velocity = self:get_velocity_relative_to_ground(Body.parts.body)
    local relative_last_velocity = self:make_velocity_relative_to_ground(Body.parts.body, last_velocity)
    if relative_last_velocity.y < -threshold and relative_velocity.y > 0 then
        local cancelling_velocity = self:rotate_vector_down(vec2(0, -relative_velocity.y)/dt*Body:get_body_mass(), Movement.Ground.state.ground_surface_normal) -- No bounce cancelling force if bouncing up
        print(Movement.state.just_jumped)
        return cancelling_velocity
    end
    return vec2(0, 0)
end

Physics.get_all_forces = function(self, dt)
    local force = vec2(0, 0)
    force = force + self:get_horizontal_forces(dt, Movement.params)
    force = force + self:get_vertical_forces(dt, Movement.params)
    if (not Input.get.hold_jump()) then
        force = force + self:get_bounce_cancelling_force(dt, Movement.state.last_velocity, Movement.params.bounce_cancellation_threshold)
    end
    local straightening_force, gravity_countering_force = Movement:straighten(Body.parts)

    local angular_force = 0
    angular_force = angular_force + self:get_angular_forces()

    return force, angular_force, straightening_force, gravity_countering_force
end

Controller.update_timers = function(self, dt)
    -- Movement timers
    Movement:update_movement_timers(dt)
    -- Animation timers
    Animation.Recoil.timers.fire_cooldown_timer = math.max(0, Animation.Recoil.timers.fire_cooldown_timer - dt)
end
    
Movement.update_movement_timers = function(self, dt)
    -- Update jump timers
    if self.timers.jump_end > 0 then
        self.timers.jump_end = math.max(0, self.timers.jump_end - dt)
    end
    
    if not Input.get.hold_jump() then
        self.timers.jump_input = 0 -- Reset timer if jump is released
    end
    
    if self.timers.jump_input > 0 then
        self.timers.jump_input = math.max(0, self.timers.jump_input - dt)
    end
    
    -- Update coyote timer
    if self.timers.coyote > 0 then
        self.timers.coyote = math.max(0, self.timers.coyote - dt)
    end
    
    -- Update bhop timer
    if self.timers.bhop > 0 and self.state.on_ground then
        self.timers.bhop = math.max(0, self.timers.bhop - dt)
        if self.timers.bhop <= 0 then
            self.state.bhop_speedup = 1 -- Reset speedup when timer ends
        end
    end
    
    -- Update landing timer
    if self.timers.landing > 0 then
        self.timers.landing = math.max(0, self.timers.landing - dt)
    end
    
    -- Update rolling timer
    if self.timers.rolling > 0 then
        self.timers.rolling = math.max(0, self.timers.rolling - dt)
        if self.state.spin_angle == 0 then
            self:begin_spin()
        end
        if self.timers.rolling <= 0 then
            self.state.spin_angle = 0 -- Reset spin angle after roll ends
        end
    end

    -- Update roll input timer
    
    if not Input.get.hold_roll() then
        self.timers.roll_input = 0 -- Reset timer if jump is released
    end
    if self.timers.roll_input > 0 then
        self.timers.roll_input = math.max(0, self.timers.roll_input - dt)
    end
    
    -- Update spin angle
    if math.abs(self.state.spin_angle) > 0 then
        local sign = self.state.spin_angle < 0 and -1 or 1
        self.state.spin_angle = self.state.spin_angle + (dt * self.params.backflip_speed * sign)
    end
    if math.abs(self.state.spin_angle) > math.pi*2 then
        self.state.spin_angle = 0 -- Reset spin angle after a full rotation
    end
end

-- Step Function (Physics and main logic)
function on_step(dt)
    dt = dt or (1.0 / 60.0)
    Controller:on_step(dt)
end
function Controller.check_required_parts(self)
    local body = Body.parts.body
    local left_arm = Body.parts.left_arm
    local right_arm = Body.parts.right_arm

    if not player or not body or not left_arm or not right_arm then
        print("Error: Missing essential components (player, body, arms).")
        return false
    end

    return true
end
function Controller.on_step(self, dt)
    if not self:check_required_parts() then
        return
    end

    Camera:move_camera(
        Physics:get_velocity_relative_to_ground(Body.parts.body),
        dt,
        Utils.lerp_vec2
    )

    Movement.Ground:check_ground(Body.parts.body, Body.parts)

    -- Use the Animation.Recoil.update_recoil function instead

    local left_pivot_world, right_pivot_world = Body:calculate_arm_pivots(Animation.Arms.pivots.left_arm_pivot, Animation.Arms.pivots.right_arm_pivot)

    -- Update animations and visual effects
    Animation.Recoil:update_recoil(dt, Utils.lerp_vec2)
    
    -- Calculate arm pivot positions
    local left_pivot_world, right_pivot_world = Body:calculate_arm_pivots(Animation.Arms.pivots.left_arm_pivot, Animation.Arms.pivots.right_arm_pivot)
    
    -- Handle leg animation and movement
    Animation.Legs:handle_locomotion(dt, Movement.state.jumping, Input.get)
    
    -- Handle arm positioning and holding objects
    Animation.Arms:handle(left_pivot_world, right_pivot_world, Body.parts, Movement.state.jumping, Animation.Legs.State.walk_cycle_time, dt, Input.get)
    
    -- Calculate and apply physics forces
    local force, angular_force, straightening_force, gravity_countering_force = Physics:get_all_forces(dt)
    Body:apply_all_forces(force, angular_force, straightening_force, gravity_countering_force)
    
    -- Update all timers
    self:update_timers(dt)

    Movement:update_last_velocity(Body.parts.body)
    
    -- Debug controls
    -- if player:key_pressed("B") then
    --     Movement:begin_spin()
    -- end
end
