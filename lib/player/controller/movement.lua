local Movement = {}

Movement.init = function(self, dependencies)
    self.Input = dependencies.Input
    self.Body = dependencies.Body
    self.Physics = dependencies.Physics
    self.Ground = dependencies.Ground
end

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
        print("Error: self.Body component not found in Movement.update_last_velocity")
        return
    end
    local current_velocity = body:get_linear_velocity()
    if not current_velocity then
        print("Error: Failed to get linear velocity in Movement.update_last_velocity")
        return
    end
    self.state.last_velocity = current_velocity
end

Movement.begin_spin = function(self)
    local current_velocity = self.Physics:get_velocity_relative_to_ground(self.Body.parts.body)
    local movement_direction = current_velocity.x < 0 and -1 or 1
    self.state.spin_angle = math.pi/4 * -movement_direction
end

Movement.roll = function(self)
    self.timers.rolling = self.params.roll_time;
    local velocity = self.Physics:get_velocity_relative_to_ground(self.Body.parts.body);
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
    local velocity = self.Physics:get_velocity_relative_to_ground(self.Body.parts.body);
    if math.abs(velocity.x) < self.params.roll_speed_threshold then
        return false; -- Not moving enough to roll
    end
    return true;
end

Movement.handle_roll = function(self)
    if self.Input:roll() then
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

Movement.calculate_nudge_direction = function(self)
    if self.timers.rolling > 0 then
        return self.state.roll_direction
    end
    local move_left = self.Input:move_left();
    local move_right = self.Input:move_right();
    if move_left and not move_right then
        return -1;
    elseif move_right and not move_left then
        return 1;
    else
        return 0;
    end;
end

Movement.get_straightening_forces = function(self, body_parts)
    return self.Physics:calculate_straightening_forces(body_parts, self.state.spin_angle)
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
    
Movement.update_movement_timers = function(self, dt)
    -- Update jump timers
    if self.timers.jump_end > 0 then
        self.timers.jump_end = math.max(0, self.timers.jump_end - dt)
    end
    
    if not self.Input:hold_jump() then
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
    
    if not self.Input:hold_roll() then
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

Movement.get_horizontal_forces = function(self, dt, movement_parameters)
    local nudge_direction = self:calculate_nudge_direction()
    
    -- Calculate the perpendicular vector to the ground normal (tangent to ground)
    local ground_tangent = self.Ground.state.ground_surface_normal:rotate(-math.pi/2)

    local tangent_velocity = self.Physics:rotate_vector_down(self.Physics:get_velocity_relative_to_ground(self.Body.parts.body), self.Ground.state.ground_surface_normal)
    
    local is_moving = (nudge_direction ~= 0)
    local vel_x = tangent_velocity.x
    local is_slowing_down = (vel_x * nudge_direction < 0) -- If trying to move in the opposite direction of current velocity
    if is_slowing_down then
        vel_x = vel_x * -0.01
    end
    local target_velocity = self.Physics:calculate_horizontal_velocity(
        self.params.max_speed * self.state.bhop_speedup + (self.timers.rolling > 0 and self.params.roll_max_speed_increase or 0),
        self.state.on_ground and self.params.acceleration_time or self.params.air_acceleration_time,
        self.state.on_ground and self.params.damping_base or self.params.air_damping_base,
        vel_x,
        is_moving
    )
    local force = self.Physics:calculate_force(vel_x, target_velocity)
    -- Calculate horizontal component along the ground
    local rotated_force = ground_tangent * force

    return rotated_force
end
Movement.get_vertical_forces = function(self, dt, movement_parameters)
    if self.state.just_jumped then
        self.state.just_jumped = false
        self:bhop_jump_update()
        return self.Physics:get_jump_force(dt, 1, movement_parameters)
    end
    if self.timers.jump_end > 0 then
        if not self.Input:hold_jump() then
            self.timers.jump_end = 0 -- Cancel jump if W is released
            if self.Body.parts.body then
                local force = self.Physics:down() * movement_parameters.jump_impulse * 0.5;
                local impulse = force / dt;
                return impulse;
            end
        end
        if self.Body.parts.body then
            return self.Physics:up() * movement_parameters.jump_hold_force * (self.timers.jump_end/movement_parameters.jump_time)^4;
        end
    end
    return vec2(0, 0)
end
Movement.get_angular_forces = function(self)
    return self.Body:get_angular_velocity() * -0.5 -- Damping angular velocity
end
Movement.get_all_forces = function(self, dt)
    local force = vec2(0, 0)
    force = force + self:get_horizontal_forces(dt, self.params)
    force = force + self:get_vertical_forces(dt, self.params)
    if (not self.Input:hold_jump()) then
        force = force + self.Physics:get_bounce_cancelling_force(dt, self.state.last_velocity, self.params.bounce_cancellation_threshold)
    end
    local straightening_force, gravity_countering_force = self:get_straightening_forces(self.Body.parts)

    local angular_force = 0
    angular_force = angular_force + self:get_angular_forces()

    return force, angular_force, straightening_force, gravity_countering_force
end

return Movement
