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
local Animation = {} -- Handles all animations and player holding logic.
local Movement = {} -- Applies player force changes and contains logic for special moves.
local Physics = {} -- How the player moves through the world and accelerates.
local Input = {} -- Handles input polling and key mappings.
local ObjectInteraction = {}
local Utils = {} -- Utility functions for vector math and other helpers.
local Body = {} -- Handles the player's body parts and their properties.
local Camera = {} -- Handles camera position and movement.

-- Animation
Animation.Legs = {}
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
    MAX_HOLD_DISTANCE = 0.4;
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


Animation.Arms = {}
Animation.Arms.params = {
    NEUTRAL_ARM_ANGLE_REL = math.rad(58);
    JUMP_TUCK_ARM_ANGLE_REL = math.rad(10);
}
Animation.Arms.pivots = {
    left_arm_pivot = vec2(0, 0);
    right_arm_pivot = vec2(0, 0);
}
Animation.Recoil = {}
Animation.Recoil.params = {
    FIRE_COOLDOWN_DURATION = 0.3;
    target_pointer_recoil_offset = vec2(0, 0);
    current_pointer_recoil_offset = vec2(0, 0);
    RECOIL_APPLICATION_SPEED = 40.0; -- Updated Constant
    RECOIL_DECAY_SPEED = 10.0;   -- Updated Constant
    MIN_RECOIL_DISTANCE_CLAMP = 0.1;
}
Animation.Recoil.Timers = {
    fire_cooldown_timer = 0;
}
Animation.Holding = {}
Animation.Holding.state = {
    holding = nil;
    holding_point_left = nil;  -- Local point on object for LEFT arm when NOT flipped
    holding_point_right = nil; -- Local point on object for RIGHT arm when NOT flipped
    original_holding_layers = nil;
    original_holding_bodytype = nil;
}
Animation.Holding.History = {}
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
    local current_buffer_size = #self.holding_history_buffer
    if current_buffer_size >= 5 then
        local index_now = history_index
        local index_prev = (history_index - 4 + self.state.max_history_frames) % self.state.max_history_frames + 1
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
    self.Timers.fire_cooldown_timer = math.max(0, self.Timers.fire_cooldown_timer - dt)
end
Animation.update_timers = function(self, dt)
    self.Recoil:update_timers(dt)
end

-- Body
Body.parts = {
    left_hinge = nil;
    right_hinge = nil;
    body = nil;
    left_foot = nil;
    right_foot = nil;
    left_arm = nil;
    right_arm = nil;
    head = nil;
}

local player = Scene:get_host();


Utils.dot = function(v1, v2)
    return v1.x * v2.x + v1.y * v2.y
end
Utils.reflect = function(v, normal)
    local v_mag = v:magnitude()
    v = v:normalize()
    normal = normal:normalize()
    local dot_product = Utils.dot(v, normal)
    return vec2(v.x - 2 * dot_product * normal.x, v.y - 2 * dot_product * normal.y) * v_mag
end
Utils.lerp_vec2 = function(v1, v2, t)
    t = math.clamp(t, 0, 1)
    return vec2(
        v1.x * (1 - t) + v2.x * t,
        v1.y * (1 - t) + v2.y * t
    )
end

Camera.cam_pos = vec2(0, 0);

Input.keymap = {
    jump = "W"; -- Jump
    move_left = "A"; -- Move left
    move_right = "D"; -- Move right
    pick_up = "E"; -- Pick up object
    drop = "Q"; -- Drop object
    roll = "S"; -- Roll (left/right movement)
}
Input.get = {
    jump = function() return player:key_just_pressed(Input.keymap.jump) end, -- Only works in on_update()
    hold_jump = function() return player:key_pressed(Input.keymap.jump) end,
    move_left = function() return player:key_pressed(Input.keymap.move_left) end,
    move_right = function() return player:key_pressed(Input.keymap.move_right) end,
    pick_up = function() return player:key_just_pressed(Input.keymap.pick_up) end, -- Only works in on_update()
    drop = function() return player:key_just_pressed(Input.keymap.drop) end, -- Only works in on_update()
    roll = function() return player:key_just_pressed(Input.keymap.roll) end, -- Only works in on_update()
}

Movement.params = {
    acceleration_time = 10; -- Multiplies the time it takes to reach a given speed
    air_acceleration_time = 20; -- Multiplies the time it takes to reach a given speed in air
    max_speed = 5; -- Asymptote of the velocity curve
    damping_base = 0.8; -- Velocity is multiplied by this every frame when button is released
    air_damping_base = 0.9; -- Damping in air
    jump_input_time = 0.5; -- How long the jump button can be held before it is ignored
    jump_impulse = 1.0; -- Impulse applied when jumping
    current_speed_factor = 0.1; -- How much to add to jump force based on current speed
    max_jump_bounce = 0.25; -- Maximum impulse that can be added via bounce jumping
    jump_hold_force = 25.0; -- Force applied while holding jump button
    jump_time = 0.5; -- Time in seconds the jump button can be held for
    coyote_time = 0.2; -- Time in seconds to allow jumping after leaving ground
    bhop_max_speed_factor = 1.5; -- How much to multiply the max speed by when bhopping
    bhop_speedup_factor = 0.75; -- Distance to bhop_max_speed_factor is multiplied by this every jump (higher = slower)
    bhop_time = 0.2; -- How long bhop boost lasts after touching floor
    backflip_speed = 20.0; -- Speed multiplier for backflip
    landing_window = 0.2; -- Time window to do tricks after landing
    roll_time = 0.5; -- How long the roll lasts
    roll_speed_threshold = 2; -- Minimum speed to allow rolling
    roll_max_speed_increase = 5; -- Maximum speed increase from rolling
};

Movement.timers = {
    coyote_timer = 0; -- Coyote time for jump forgiveness
    bhop_timer = 0; -- Timer for bhop boost
    jump_end_timer = 0; -- Timer for jump hold during the jump
    jump_input_timer = 0; -- Timer for jump input hold before the jump
    landing_timer = 0; -- Timer for right after touching ground
    rolling_timer = 0; -- Timer for rolls
}
Movement.state = {
    on_ground = false; -- Whether the player is currently on the ground
    jumping = false; -- Whether the player is currently jumping
    just_jumped = false; -- Whether the player just jumped this frame
    roll_direction = 0; -- Direction of the roll, 1 for right, -1 for left, 0 for no roll
    bhop_speedup = 1; -- Speed multiplier for bhop boost, cannot exceed bhop_max_speed_factor
    spin_angle = 0; -- Angle for spinning the player around
}
Movement.ground = {
    ground_friction = 0.1;
    ground_surface_normal = vec2(0,1); -- Normal of the ground surface
    ground_surface_velocity = vec2(0,0); -- For moving surfaces like cars
}

-- Shorthand
local NO_COLLISION_LAYERS = {};

Physics.get_body_mass = function(self, bodyparts)
    if bodyparts.body and bodyparts.left_foot and bodyparts.right_foot and 
       bodyparts.left_arm and bodyparts.right_arm and bodyparts.head then
        return bodyparts.body:get_mass() + bodyparts.left_foot:get_mass() + bodyparts.right_foot:get_mass() +
               bodyparts.left_arm:get_mass() + bodyparts.right_arm:get_mass() + bodyparts.head:get_mass()
    else
        return 1.0
    end
end
Physics.get_gravity_force = function(self)
    return Scene:get_gravity() * self:get_body_mass(Body.parts)
end
Physics.down = function(self)
    return Scene:get_gravity():normalize()
end
Physics.up = function(self)
    return -self:down()
end
Physics.get_velocity_relative_to_ground = function(self, body)
    if not body then return vec2(0, 0) end
    local current_velocity = body:get_linear_velocity()
    if not current_velocity then return vec2(0, 0) end
    return current_velocity - Movement.ground.ground_surface_velocity
end
Physics.rotate_vector_down = function(self, vector, ground_surface_normal)
    local ground_angle = math.atan2(ground_surface_normal.y, ground_surface_normal.x) - math.pi/2
    local rotated_vector = vector:rotate(-ground_angle)
    return rotated_vector
end

-- Individual module initialization functions
Body.on_start = function(self, saved_data)
    self.parts.left_hinge = saved_data.left_hinge
    self.parts.right_hinge = saved_data.right_hinge
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
        left_hinge = self.parts.left_hinge,
        right_hinge = self.parts.right_hinge,
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
    self.Timers.fire_cooldown_timer = 0
    self.params.target_pointer_recoil_offset = vec2(0, 0)
    self.params.current_pointer_recoil_offset = vec2(0, 0)
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

Camera.on_start = function(self, body)
    if body then
        self.cam_pos = body:get_position()
        player:set_camera_position(self.cam_pos + vec2(0, 0.6))
    else
        self.cam_pos = vec2(0, 0)
        print("Warning: Body component not found on start.")
    end
end

Camera.on_save = function(self)
    return {}  -- Camera position doesn't need to be saved
end

-- Initialization Function
function on_start(saved_data)
    Controller:on_start(saved_data)
end

Controller.on_start = function(self, saved_data)
    Body:on_start(saved_data)
    Animation:on_start(saved_data)
    Camera:on_start(Body.parts.body)
    Movement:on_start(Input, Physics, Body.parts.body)
    Physics:on_start(Body.parts)
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



local function begin_spin()
    local current_velocity = get_velocity_relative_to_ground()
    local movement_direction = current_velocity.x < 0 and -1 or 1
    spin_angle = math.pi/4 * -movement_direction
end

Movement.roll = function(self)
    self.timers.rolling_timer = movement_parameters.roll_time;
    local velocity = get_velocity_relative_to_ground();
    if velocity.x > 0 then
        self.state.roll_direction = 1; -- Roll right
    elseif velocity.x < 0 then
        self.state.roll_direction = -1; -- Roll left
    else
        self.state.roll_direction = 0; -- No roll direction
    end
    begin_spin()
    print("roll")
end

Movement.is_roll_possible = function(self)
    if self.timers.landing_timer == 0 then
        return false;
    end
    if self.timers.rolling_timer > 0 then
        return false; -- Already rolling
    end
    local velocity = get_velocity_relative_to_ground();
    if math.abs(velocity.x) < self.params.roll_speed_threshold then
        return false; -- Not moving enough to roll
    end
    return true;
end

Movement.handle_roll = function(self)
    if self.Input.roll() and self:is_roll_possible() then
        self:roll()
    end
end

local function handle_jump()
    if input.jump() then
        jump_input_timer = movement_parameters.jump_input_time;
    end
    if jump_input_timer > 0 and (on_ground or coyote_timer > 0) then
        jump_input_timer = 0;
        coyote_timer = 0; -- Reset coyote timer on jump
        jumping = true;
        just_jumped = true;
        jump_end_timer = movement_parameters.jump_time;
    end
end

local function handle_pick_up()
    if input.pick_up() then
        if holding then
            drop_object()
        end
        local objs = Scene:get_objects_in_circle({ position = player:pointer_pos(), radius = 0 });
        for i = 1, #objs do
            if (objs[i]:get_body_type() == BodyType.Dynamic) and (objs[i]:get_mass() < 1) then
                pick_up(objs[i], vec2(-0.075, 0), vec2(0.075, 0));
                break;
            end
        end
    end
end

local function handle_drop()
    if input.drop() then
        if holding then
            drop_object()
        end
    end
end

local function update_camera()
    if player and cam_pos then
        player:set_camera_position(cam_pos)
    end
end


-- Update Function (Input polling)
function on_update(dt)
    Controller:on_update(dt)
end
Controller.on_update = function(self, dt)    handle_jump()
    handle_pick_up()
    handle_drop()
    update_camera()
    handle_roll()
end

-- Step Function (Physics and main logic)
function on_step(dt)
    dt = dt or (1.0 / 60.0)

    if not body or not player or not left_arm or not right_arm then
        print("on_step Error: Missing essential components (body, player, arms).")
        return
    end

    local function update_camera()
        local target_cam_pos = body:get_position() + vec2(0, 0.6)
        cam_pos = cam_pos + get_velocity_relative_to_ground() * dt
        cam_pos = lerp_vec2(cam_pos, target_cam_pos, dt * 4)
        player:set_camera_position(cam_pos)
    end

    local function check_ground()
        local center_offset = vec2(0, -0.2)
        local left_offset = vec2(-0.2, -0.2)
        local right_offset = vec2(0.2, -0.2)
        local ray_offsets = {center_offset, left_offset, right_offset}
        
        local found_ground = false
        local current_ground_normal = vec2(0, 1)
        local current_ground_velocity = vec2(0, 0)
        local current_ground_friction = 0.1
        
        -- Check each ray position
        for _, offset in ipairs(ray_offsets) do
            local ground_check_origin = body:get_world_point(offset)
            if ground_check_origin then
                local hits = Scene:raycast({
                    origin = ground_check_origin, direction = down(),
                    distance = 0.2, closest_only = false,
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
                        if obj.id == body.id or obj.id == left_arm.id or obj.id == right_arm.id then
                            connected_to_self = true
                            break
                        end
                    end
                    
                    if not connected_to_self then
                        found_ground = true
                        if on_ground == false then
                            landing_timer = movement_parameters.landing_window
                        end
                        on_ground = true
                        current_ground_normal = hits[i].normal
                        current_ground_velocity = hits[i].object:get_linear_velocity()
                        current_ground_friction = hits[i].object:get_friction()
                        if jump_end_timer <= 0 then
                            coyote_timer = movement_parameters.coyote_time
                            jumping = false
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
            on_ground = false
            jumping = true
            ground_surface_normal = up()
            ground_friction = 0.1
        else
            ground_surface_normal = current_ground_normal
            ground_surface_velocity = current_ground_velocity
            ground_friction = current_ground_friction
        end
    end

    local function update_recoil()
        fire_cooldown_timer = math.max(0, fire_cooldown_timer - dt)
        current_pointer_recoil_offset = lerp_vec2(current_pointer_recoil_offset, target_pointer_recoil_offset, dt * RECOIL_APPLICATION_SPEED)
        target_pointer_recoil_offset = lerp_vec2(target_pointer_recoil_offset, vec2(0, 0), dt * RECOIL_DECAY_SPEED)
        if target_pointer_recoil_offset:length() ^ 2 < 0.00001 then
            target_pointer_recoil_offset = vec2(0, 0)
            if current_pointer_recoil_offset:length() ^ 2 < 0.00001 then
                current_pointer_recoil_offset = vec2(0, 0)
            end
        end
    end

    local function calculate_arm_pivots()
        local left_pivot_world = body:get_world_point(left_arm_pivot)
        local right_pivot_world = body:get_world_point(right_arm_pivot)
        if not left_pivot_world or not right_pivot_world then
            print("on_step Error: Failed to get world pivot points.")
            left_pivot_world = body:get_position()
            right_pivot_world = body:get_position()
        end
        return left_pivot_world, right_pivot_world
    end

    local function calculate_nudge_direction()
        if rolling_timer > 0 then
            return roll_direction
        end
        local move_left = input.move_left();
        local move_right = input.move_right();
        if move_left and not move_right then
            return -1;
        elseif move_right and not move_left then
            return 1;
        else
            return 0;
        end;
    end

    local function handle_locomotion(left_pivot_world, right_pivot_world)
        local move_left = input.move_left();
        local move_right = input.move_right();
        local target_left_leg_angle = NEUTRAL_ANGLE
        local target_right_leg_angle = NEUTRAL_ANGLE
        local target_leg_torque = IDLE_TORQUE

        if jumping then
            target_left_leg_angle = JUMP_TUCK_ANGLE
            target_right_leg_angle = -JUMP_TUCK_ANGLE
            target_leg_torque = JUMP_TORQUE
        elseif move_left or move_right then
            local body_vel = body:get_linear_velocity()
            local horizontal_vel_mag = (body_vel and math.abs(body_vel.x)) or 0
            local vel_scale = math.min(math.max(horizontal_vel_mag, 0.4), 1.0)
            walk_cycle_time = walk_cycle_time + (dt * WALK_CYCLE_SPEED * vel_scale)
            local swing_offset = math.sin(walk_cycle_time) * WALK_SWING_AMPLITUDE
            target_left_leg_angle = NEUTRAL_ANGLE + swing_offset * vel_scale
            target_right_leg_angle = NEUTRAL_ANGLE - swing_offset * vel_scale
            target_leg_torque = WALK_TORQUE
        else
            target_left_leg_angle = NEUTRAL_ANGLE
            target_right_leg_angle = NEUTRAL_ANGLE
            target_leg_torque = IDLE_TORQUE
        end

        if left_hinge and right_hinge then
            local current_left_leg_angle = get_current_leg_hinge_angle(left_hinge)
            local current_right_leg_angle = get_current_leg_hinge_angle(right_hinge)
            local desired_left_leg_speed = calculate_motor_speed_for_leg_angle(current_left_leg_angle, target_left_leg_angle, LEG_ANGLE_CONTROL_KP, MAX_MOTOR_SPEED_FOR_LEG_CONTROL)
            local desired_right_leg_speed = calculate_motor_speed_for_leg_angle(current_right_leg_angle, target_right_leg_angle, LEG_ANGLE_CONTROL_KP, MAX_MOTOR_SPEED_FOR_LEG_CONTROL)
            set_leg_hinge_motor(left_hinge, desired_left_leg_speed, target_leg_torque)
            set_leg_hinge_motor(right_hinge, desired_right_leg_speed, target_leg_torque)
        end
    end

    local function handle_arms_holding(left_pivot_world, right_pivot_world)
        if not holding then
            return;
        end;
        -- Currently Holding an Object

        local hold_center = (left_pivot_world + right_pivot_world) / 2.0;

        -- Calculate effective pointer position including scaled, smoothed recoil
        local raw_pointer_pos = player:pointer_pos()
        local distance_to_pointer = (raw_pointer_pos - hold_center):length()
        local scale_factor = math.max(MIN_RECOIL_DISTANCE_CLAMP, distance_to_pointer)
        local effective_recoil_offset = current_pointer_recoil_offset * scale_factor
        local pointer_world = raw_pointer_pos + effective_recoil_offset;

        -- Calculate aiming direction vector and distance
        local hold_direction_vec = pointer_world - hold_center;
        local current_aim_dist = hold_direction_vec:length();
        local effective_hold_dist = math.min(current_aim_dist, MAX_HOLD_DISTANCE);

        -- Calculate normalized aiming direction
        local hold_direction_normalized;
        if current_aim_dist < 0.001 then
             hold_direction_normalized = body:get_right_direction() or vec2(1,0);
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
        holding:set_position(target_holding_pos);
        holding:set_angle(target_holding_angle);

        -- Update drop velocity history buffer
        holding_cumulative_time = holding_cumulative_time + dt
        history_index = (history_index % max_history_frames) + 1
        holding_history_buffer[history_index] = {
             pos = target_holding_pos, angle = target_holding_angle, time = holding_cumulative_time
        }

        -- Position the static arms - **CRITICAL CHANGE HERE**
        local target_left_hand_world = nil
        local target_right_hand_world = nil

        -- Determine which local points on the held object the arms should connect to
        -- This ensures arms connect correctly regardless of the object's visual flip
        local effective_left_hold_point = holding_point_left   -- Default: left arm connects to left point
        local effective_right_hold_point = holding_point_right -- Default: right arm connects to right point

        if is_flipped then
            -- If visually flipped, swap the effective points
            effective_left_hold_point = holding_point_right -- Left arm connects to what *was* the right point
            effective_right_hold_point = holding_point_left  -- Right arm connects to what *was* the left point
        end

        -- Get the world coordinates of these effective connection points
        target_left_hand_world = holding:get_world_point(effective_left_hold_point);
        target_right_hand_world = holding:get_world_point(effective_right_hold_point);


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
             left_arm:set_position(left_pivot_world); left_arm:set_angle(left_arm_angle);
             right_arm:set_position(right_pivot_world); right_arm:set_angle(right_arm_angle);
        end

        -- Activation Check
        if player:pointer_pressed() and fire_cooldown_timer <= 0 then
            fire_cooldown_timer = FIRE_COOLDOWN_DURATION;
            local total_recoil_this_frame = 0;
            local holding_components = holding:get_components();
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
                    target_pointer_recoil_offset = target_pointer_recoil_offset + recoil_impulse_vector;
                else
                    print("Warning: Cannot calculate recoil direction because aim direction is degenerate.")
                end
            end
        end -- End of activation check
    end

    local function handle_arms_neutral(left_pivot_world, right_pivot_world)
            -- Handle logic for neutral arm positions
            local target_left_arm_rel_angle = NEUTRAL_ARM_ANGLE_REL
            local target_right_arm_rel_angle = -NEUTRAL_ARM_ANGLE_REL

            if jumping then
                target_left_arm_rel_angle = target_left_arm_rel_angle + JUMP_TUCK_ARM_ANGLE_REL
                target_right_arm_rel_angle = target_right_arm_rel_angle - JUMP_TUCK_ARM_ANGLE_REL
            elseif input.move_left() or input.move_right() then
                local body_vel = body:get_linear_velocity()
                local horizontal_vel_mag = (body_vel and math.abs(body_vel.x)) or 0
                local vel_scale = math.min(math.max(horizontal_vel_mag, 0.4), 1.0)
                local swing_offset = math.sin(walk_cycle_time) * WALK_SWING_AMPLITUDE
                target_left_arm_rel_angle = NEUTRAL_ARM_ANGLE_REL - (swing_offset * vel_scale * 0.6)
                target_right_arm_rel_angle = -NEUTRAL_ARM_ANGLE_REL + (swing_offset * vel_scale * 0.6)
            end

            local body_angle = body:get_angle()
            local final_world_left_arm_angle = body_angle + target_left_arm_rel_angle
            local final_world_right_arm_angle = body_angle + target_right_arm_rel_angle

            left_arm:set_position(left_pivot_world)
            left_arm:set_angle(final_world_left_arm_angle)
            right_arm:set_position(right_pivot_world)
            right_arm:set_angle(final_world_right_arm_angle)
    end

    local function handle_arms(left_pivot_world, right_pivot_world)
        if holding then
            -- Handle logic for holding an object
            handle_arms_holding(left_pivot_world, right_pivot_world)
        else
            -- Handle logic for neutral arm positions
            handle_arms_neutral(left_pivot_world, right_pivot_world)
        end
    end

    local function straighten()
        local time = 1

        local target_vector = ground_surface_normal
        target_vector = target_vector:rotate(spin_angle)

        local current_angle = body:get_angle() + math.pi/2
        local target_angle = math.atan2(target_vector.y, target_vector.x)
        local current_angular_velocity = body:get_angular_velocity()
        local angular_velocity_rotation = current_angular_velocity * time
        local angle_diff = target_angle - current_angle + angular_velocity_rotation
        local angle_diff_clamped = math.atan2(math.sin(angle_diff), math.cos(angle_diff))
        local straightening_force = math.abs(angle_diff_clamped*(spin_angle == 0 and 10 or 20))

        body:apply_force_to_center(target_vector * straightening_force)
        if left_foot then
            local fp_world = left_foot:get_world_point(vec2(0, -0.2))
            if fp_world then left_foot:apply_force(target_vector * -straightening_force/2, fp_world) end
        end
        if right_foot then
            local fp_world = right_foot:get_world_point(vec2(0, -0.2))
            if fp_world then right_foot:apply_force(target_vector * -straightening_force/2, fp_world) end
        end
        body:apply_force_to_center(-reflect(get_gravity_force(), -target_vector))
    end

    local function calculate_next_bhop_speedup(bhop_speedup_factor, bhop_max_speed_factor, bhop_time, current_speedup) -- Called every jump
        local new_speedup = bhop_max_speed_factor-((bhop_max_speed_factor-current_speedup)*bhop_speedup_factor)
        return math.min((new_speedup), bhop_max_speed_factor)
    end

    local function bhop_jump_update()
        if bhop_timer > 0 then
            bhop_speedup = calculate_next_bhop_speedup(
                movement_parameters.bhop_speedup_factor,
                movement_parameters.bhop_max_speed_factor,
                movement_parameters.bhop_time,
                bhop_speedup
            )
        end
        bhop_timer = movement_parameters.bhop_time
    end
    
    local function calculate_horizontal_velocity(max_speed, acceleration_time, damping_base, current_horizontal_velocity, is_moving)
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

    local function calculate_force(current_horizontal_velocity, target_velocity)
        -- Calculate the force needed to reach the target velocity
        local acceleration = (target_velocity - current_horizontal_velocity) / dt
        local force = acceleration * get_self_mass()
        return force
    end

    local function get_horizontal_forces()
        local nudge_direction = calculate_nudge_direction()
        
        -- Calculate the perpendicular vector to the ground normal (tangent to ground)
        local ground_tangent = ground_surface_normal:rotate(-math.pi/2)

        local tangent_velocity = rotate_vector_down(get_velocity_relative_to_ground(), ground_surface_normal)
        
        local is_moving = (nudge_direction ~= 0)
        local vel_x = tangent_velocity.x
        local is_slowing_down = (vel_x * nudge_direction < 0) and not (rolling_timer > 0) -- If trying to move in the opposite direction of current velocity
        if is_slowing_down then
            vel_x = vel_x * -0.01
        end
        local target_velocity = calculate_horizontal_velocity(
            movement_parameters.max_speed * bhop_speedup + (rolling_timer > 0 and movement_parameters.roll_max_speed_increase or 0),
            on_ground and movement_parameters.acceleration_time or movement_parameters.air_acceleration_time,
            on_ground and movement_parameters.damping_base or movement_parameters.air_damping_base,
            vel_x,
            is_moving
        )
        local force = calculate_force(vel_x, target_velocity)
        
        -- Calculate horizontal component along the ground
        local rotated_force = ground_tangent * force

        return rotated_force
    end

    local function get_jump_force(multiplier)
        just_jumped = false
        bhop_jump_update()
        if body then
            local relative_velocity = rotate_vector_down(get_velocity_relative_to_ground(), ground_surface_normal)

            -- Current velocity cancellation
            local impulse_to_cancel_vertical_speed
            if relative_velocity.y < 0 then
                impulse_to_cancel_vertical_speed = math.abs(relative_velocity.y) * get_self_mass()
            else
                impulse_to_cancel_vertical_speed = math.min(math.abs(relative_velocity.y) * get_self_mass(), movement_parameters.max_jump_bounce)
                -- Visually show boost
                -- if impulse_to_cancel_vertical_speed == movement_parameters.max_jump_bounce then
                --     print("nice!")
                --     begin_spin()
                -- end
            end

            -- Speed bonus to reward running jumps
            local current_speed_bonus = math.abs(relative_velocity.x) * movement_parameters.current_speed_factor
            

            local force = up() * (movement_parameters.jump_impulse * multiplier + current_speed_bonus + impulse_to_cancel_vertical_speed)
            local impulse = force / dt
            return impulse
        end
        return vec2(0, 0) -- No impulse if body is not defined
    end

    local function get_vertical_forces()
        if just_jumped then
            return get_jump_force(1)
        end
        if jump_end_timer > 0 then
            if not input.hold_jump() then
                jump_end_timer = 0 -- Cancel jump if W is released
                if body then
                    local force = down() * movement_parameters.jump_impulse * 0.5;
                    local impulse = force / dt;
                    return impulse;
                end
            end
            if body then
                return up() * movement_parameters.jump_hold_force * (jump_end_timer/movement_parameters.jump_time)^4;
            end
        end
        return vec2(0, 0)
    end
    
    local function apply_all_forces(force, angular_force)
        body:apply_force_to_center(force);
        body:apply_torque(angular_force);
    end

    local function get_angular_forces()
        return body:get_angular_velocity() * -0.5 -- Damping angular velocity
    end

    local function get_all_forces()
        local force = vec2(0, 0)
        force = force + get_horizontal_forces()
        force = force + get_vertical_forces()

        local angular_force = 0
        angular_force = angular_force + get_angular_forces()

        return force, angular_force
    end

    local function update_jump_end_timer(dt)
        if jump_end_timer > 0 then
            jump_end_timer = math.max(0, jump_end_timer - dt)
        end
    end

    local function update_jump_input_timer(dt)
        if not input.hold_jump() then
            jump_input_timer = 0 -- Reset timer if W is released
        end
        if jump_input_timer > 0 then
            jump_input_timer = math.max(0, jump_input_timer - dt)
        end
    end

    local function update_coyote_timer(dt)
        if coyote_timer > 0 then
            coyote_timer = math.max(0, coyote_timer - dt)
        end
    end

    local function update_bhop_timer(dt)
        if bhop_timer > 0 and on_ground then
            bhop_timer = math.max(0, bhop_timer - dt)
            if bhop_timer <= 0 then
                bhop_speedup = 1 -- Reset speedup when timer ends
            end
        end
    end

    local function update_landing_timer(dt)
        if landing_timer > 0 then
            landing_timer = math.max(0, landing_timer - dt)
        end
    end

    local function update_rolling_timer(dt)
        if rolling_timer > 0 then
            rolling_timer = math.max(0, rolling_timer - dt)
            if spin_angle == 0 then
                begin_spin()
            end
            if rolling_timer <= 0 then
                spin_angle = 0 -- Reset spin angle after roll ends
            end
        end
    end

    local function update_spin_angle(dt)
        if math.abs(spin_angle) > 0 then
            local sign = spin_angle < 0 and -1 or 1
            spin_angle = spin_angle + (dt * movement_parameters.backflip_speed * sign)
        end
        if math.abs(spin_angle) > math.pi*2 then
            spin_angle = 0 -- Reset spin angle after a full rotation
        end
    end

    local function update_timers(dt)
        update_jump_end_timer(dt)
        update_jump_input_timer(dt)
        update_coyote_timer(dt)
        update_bhop_timer(dt)
        update_landing_timer(dt)
        update_rolling_timer(dt)
        update_spin_angle(dt)
    end

    local debug = false

    update_camera()
    check_ground()
    update_recoil()
    local left_pivot_world, right_pivot_world = calculate_arm_pivots()
    if not debug then
        handle_locomotion(left_pivot_world, right_pivot_world)
    end
    handle_arms(left_pivot_world, right_pivot_world)
    straighten()
    apply_all_forces(get_all_forces())
    update_timers(dt)
    if player:key_pressed("B") then
        begin_spin()
    end
end
