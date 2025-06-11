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
local Legs = require("core/lib/player/controller/legs.lua") -- Handles leg animations and movement.
local Arms = require("core/lib/player/controller/arms.lua") -- Handles arm animations and holding logic.
local Recoil = require("core/lib/player/controller/recoil.lua") -- Handles recoil effects when firing weapons.

local Holding = require("core/lib/player/controller/holding.lua") -- Handles picking up and dropping objects.
    Holding.History = require("core/lib/player/controller/holding_history.lua") -- Keeps track of holding history for dropped objects.

local Movement = {} -- Applies player force changes and contains logic for special moves.
local Ground = require("core/lib/player/controller/ground.lua") -- Handles ground-related logic like friction and surface normals.
local Physics = {} -- How the player moves through the world and accelerates.
local Input = require("core/lib/player/controller/input.lua") -- Handles input polling and key mappings.
local Utils = require("core/lib/player/controller/utils.lua") -- Utility functions for vector math and other helpers.
local Body = require("core/lib/player/controller/body.lua") -- Handles the player's body parts and their properties.
local Camera = require("core/lib/player/controller/camera.lua") -- Handles camera position and movement.

local player = Scene:get_host()

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
    local ground_surface_velocity = Ground.state.ground_surface_velocity
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

Controller.init = function(self)
    -- Initialize submodules
    Legs:init({Input = Input, Body = Body})
    Arms:init({Input = Input, Holding = Holding, Recoil = Recoil, Body = Body, player = player})
    Recoil:init()
    Holding:init({})
    Holding.History:init({})
    Body:init({Ground = Ground})
    Ground:init({Movement = Movement, Physics = Physics, Body = Body})

    -- Others here once they get moved

    Input:init({player = player})
    Camera:init({Body = Body, player = player})
end

-- Initialization Function
function on_start(saved_data)
    Controller:init()
    Controller:on_start(saved_data)
end

Controller.on_start = function(self, saved_data)
    Body:on_start(saved_data)
    Arms:on_start(saved_data)
    Legs:on_start(saved_data)
    Recoil:on_start() -- No saved data needed for recoil
    Holding:on_start(saved_data)
    Camera:on_start(Body, player)
    Physics:on_start(Body.parts, Movement.params)
    Input:on_start()
end

-- Save Function
function on_save()
    return Controller:on_save()
end

Controller.on_save = function(self)
    local body_data = Body:on_save()
    local arms_data = Arms:on_save()
    local legs_data = Legs:on_save()
    local holding_data = Holding:on_save()
    
    -- Merge the data tables
    local result = {}
    for k, v in pairs(body_data) do result[k] = v end
    for k, v in pairs(arms_data) do result[k] = v end
    for k, v in pairs(legs_data) do result[k] = v end
    for k, v in pairs(holding_data) do result[k] = v end
    
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
    if Input:roll() then
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



-- Update Function (Input polling)
function on_update(dt)
    Controller:on_update(dt)
end
Controller.on_update = function(self, dt)
    Movement:handle_jump(Input:jump())
    Movement:handle_roll(Input:roll())
    Holding:handle_pick_up(Input:pick_up(), player:pointer_pos())
    Holding:handle_drop(Input:drop())
    Camera:update_camera()
end

Movement.calculate_nudge_direction = function(self)
    if self.timers.rolling > 0 then
        return self.state.roll_direction
    end
    local move_left = Input:move_left();
    local move_right = Input:move_right();
    if move_left and not move_right then
        return -1;
    elseif move_right and not move_left then
        return 1;
    else
        return 0;
    end;
end

Movement.straighten = function(self, body_parts)
    local time = 1
    local body = body_parts.body

    local target_vector = Ground.state.ground_surface_normal
    target_vector = target_vector:rotate(self.state.spin_angle)

    local current_angle = body:get_angle() + math.pi/2
    local target_angle = math.atan2(target_vector.y, target_vector.x)
    local current_angular_velocity = body:get_angular_velocity()
    local angular_velocity_rotation = current_angular_velocity * time
    local angle_diff = target_angle - current_angle + angular_velocity_rotation
    local angle_diff_clamped = math.atan2(math.sin(angle_diff), math.cos(angle_diff))
    local straightening_force_magnitude = math.abs(angle_diff_clamped*(self.state.spin_angle == 0 and 10 or 20))

    local straightening_force = target_vector * straightening_force_magnitude

    local gravity_countering_force = -Utils.reflect(Physics:get_gravity_force(), -Ground.state.ground_surface_normal)

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
    local ground_tangent = Ground.state.ground_surface_normal:rotate(-math.pi/2)

    local tangent_velocity = self:rotate_vector_down(self:get_velocity_relative_to_ground(Body.parts.body), Ground.state.ground_surface_normal)
    
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
    local relative_velocity = self:rotate_vector_down(self:get_velocity_relative_to_ground(Body.parts.body), Ground.state.ground_surface_normal)

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
        if not Input:hold_jump() then
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

Physics.get_angular_forces = function(self)
    return Body:get_angular_velocity() * -0.5 -- Damping angular velocity
end

Physics.get_bounce_cancelling_force = function(self, dt, last_velocity, threshold)
    local relative_velocity = self:get_velocity_relative_to_ground(Body.parts.body)
    local relative_last_velocity = self:make_velocity_relative_to_ground(Body.parts.body, last_velocity)
    if relative_last_velocity.y < -threshold and relative_velocity.y > 0 then
        local cancelling_velocity = self:rotate_vector_down(vec2(0, -relative_velocity.y)/dt*Body:get_body_mass(), Ground.state.ground_surface_normal) -- No bounce cancelling force if bouncing up
        print(Movement.state.just_jumped)
        return cancelling_velocity
    end
    return vec2(0, 0)
end

Physics.get_all_forces = function(self, dt)
    local force = vec2(0, 0)
    force = force + self:get_horizontal_forces(dt, Movement.params)
    force = force + self:get_vertical_forces(dt, Movement.params)
    if (not Input:hold_jump()) then
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
    Recoil:update_timers(dt)
end
    
Movement.update_movement_timers = function(self, dt)
    -- Update jump timers
    if self.timers.jump_end > 0 then
        self.timers.jump_end = math.max(0, self.timers.jump_end - dt)
    end
    
    if not Input:hold_jump() then
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
    
    if not Input:hold_roll() then
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
        print("Error: Missing essential components (player, body, arms).\n"
    .. "The missing parts are:\n"
    .. "Player: " .. tostring(player) .. "\n"
    .. "Body: " .. tostring(body) .. "\n"
    .. "Left Arm: " .. tostring(left_arm) .. "\n"
    .. "Right Arm: " .. tostring(right_arm))
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

    Ground:check_ground(Body.parts.body, Body.parts)

    -- Use the Recoil.update_recoil function instead

    local left_pivot_world, right_pivot_world = Body:calculate_arm_pivots(Arms.pivots.left_arm_pivot, Arms.pivots.right_arm_pivot)

    -- Update animations and visual effects
    Recoil:update_recoil(dt, Utils.lerp_vec2)
    
    -- Calculate arm pivot positions
    local left_pivot_world, right_pivot_world = Body:calculate_arm_pivots(Arms.pivots.left_arm_pivot, Arms.pivots.right_arm_pivot)
    
    -- Handle leg animation and movement
    Legs:handle_locomotion(dt, Movement.state.jumping)
    
    -- Handle arm positioning and holding objects
    Arms:handle(left_pivot_world, right_pivot_world, Body.parts, Movement.state.jumping, Legs.State.walk_cycle_time, dt, Input.get)
    
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
