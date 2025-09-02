local Physics = {}

Physics.init = function(self, dependencies)
    self.Body = dependencies.Body
    self.Ground = dependencies.Ground
    self.Utils = dependencies.Utils
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
    local force = acceleration * self.Body:get_body_mass()
    return force
end


Physics.get_jump_force = function(self, dt, multiplier, movement_parameters)
    local relative_velocity = self:rotate_vector_down(self:get_velocity_relative_to_ground(self.Body.parts.body), self.Ground.state.ground_surface_normal)

    -- Current velocity cancellation
    local force_to_cancel_vertical_speed
    if relative_velocity.y < 0 then
        force_to_cancel_vertical_speed = math.abs(relative_velocity.y) * self.Body:get_body_mass()
    else
        force_to_cancel_vertical_speed = math.min(math.abs(relative_velocity.y) * self.Body:get_body_mass(), movement_parameters.max_jump_impulse_bonus)
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

Physics.calculate_straightening_forces = function(self, body_parts, spin_angle)
    local time = 1
    local body = body_parts.body

    local target_vector = self.Ground.state.ground_surface_normal
    target_vector = target_vector:rotate(spin_angle)

    local current_angle = body:get_angle() + math.pi/2
    local target_angle = math.atan2(target_vector.y, target_vector.x)
    local current_angular_velocity = body:get_angular_velocity()
    local angular_velocity_rotation = current_angular_velocity * time
    local angle_diff = target_angle - current_angle + angular_velocity_rotation
    local angle_diff_clamped = math.atan2(math.sin(angle_diff), math.cos(angle_diff))
    local straightening_force_magnitude = math.abs(angle_diff_clamped*(spin_angle == 0 and 10 or 20))

    local straightening_force = target_vector * straightening_force_magnitude

    local gravity_countering_force = -self.Utils.reflect(self:get_gravity_force(), -self.Ground.state.ground_surface_normal)

    return straightening_force, gravity_countering_force
end

Physics.get_bounce_cancelling_force = function(self, dt, last_velocity, threshold)
    local relative_velocity = self:get_velocity_relative_to_ground(self.Body.parts.body)
    local relative_last_velocity = self:make_velocity_relative_to_ground(self.Body.parts.body, last_velocity)
    if relative_last_velocity.y < -threshold and relative_velocity.y > 0 then
        local cancelling_velocity = self:rotate_vector_down(vec2(0, -relative_velocity.y)/dt*self.Body:get_body_mass(), self.Ground.state.ground_surface_normal) -- No bounce cancelling force if bouncing up
        return cancelling_velocity
    end
    return vec2(0, 0)
end


Physics.get_gravity = function(self)
    return Scene:get_gravity() or vec2(0, -9.81) -- Default to Earth gravity if not set
end
Physics.get_gravity_force = function(self)
    return self:get_gravity() * self.Body:get_body_mass()
end
Physics.down = function(self)
    return self:get_gravity():normalize()
end
Physics.up = function(self)
    return -self:down()
end
Physics.make_velocity_relative_to_ground = function(self, body, velocity)
    if not body or not velocity then return vec2(0, 0) end
    local ground_surface_velocity = self.Ground.state.ground_surface_velocity
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

return Physics
