local Legs = {}

Legs.on_start = function(self, saved_data)
    self.State.walk_cycle_time = saved_data.walk_cycle_time or 0
end

Legs.on_save = function(self)
    return {
        walk_cycle_time = self.State.walk_cycle_time
    }
end


Legs.init = function(self, dependencies)
    self.Input = dependencies.Input
    self.Body = dependencies.Body
end
Legs.params = {
    WALK_CYCLE_SPEED = 30.0;
    WALK_SWING_AMPLITUDE = math.rad(35); -- same as Arms.WALK_SWING_AMPLITUDE
    JUMP_TUCK_ANGLE = math.rad(20);
    NEUTRAL_ANGLE = math.rad(0);
    LEG_ANGLE_CONTROL_KP = 50.0;
    MAX_MOTOR_SPEED_FOR_LEG_CONTROL = 15.0;
    WALK_TORQUE = 200.0;
    JUMP_TORQUE = 250.0;
    IDLE_TORQUE = 5.0;
}
Legs.State = {
    walk_cycle_time = 0;
}
Legs.set_leg_hinge_motor = function(self, hinge, speed, torque)
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

Legs.get_current_leg_hinge_angle = function(self, hinge_component)
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

Legs.calculate_motor_speed_for_leg_angle = function(self, current_angle, target_angle, kp, max_speed)
    if current_angle == nil then return 0 end
    local angle_error = target_angle - current_angle;
    angle_error = math.atan2(math.sin(angle_error), math.cos(angle_error));
    local desired_speed = kp * angle_error;
    desired_speed = math.clamp(desired_speed, -max_speed, max_speed);
    return -desired_speed;
end

Legs.handle_locomotion = function(self, dt, is_jumping)
    local move_left = self.Input:move_left();
    local move_right = self.Input:move_right();
    local target_left_leg_angle = self.params.NEUTRAL_ANGLE
    local target_right_leg_angle = self.params.NEUTRAL_ANGLE
    local target_leg_torque = self.params.IDLE_TORQUE

    if is_jumping then
        target_left_leg_angle = self.params.JUMP_TUCK_ANGLE
        target_right_leg_angle = -self.params.JUMP_TUCK_ANGLE
        target_leg_torque = self.params.JUMP_TORQUE
    elseif move_left or move_right then
        local body_vel = self.Body.parts.body:get_linear_velocity()
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

    if self.Body.hinges.left_hinge and self.Body.hinges.right_hinge then
        local current_left_leg_angle = self:get_current_leg_hinge_angle(self.Body.hinges.left_hinge)
        local current_right_leg_angle = self:get_current_leg_hinge_angle(self.Body.hinges.right_hinge)
        local desired_left_leg_speed = self:calculate_motor_speed_for_leg_angle(current_left_leg_angle, target_left_leg_angle, self.params.LEG_ANGLE_CONTROL_KP, self.params.MAX_MOTOR_SPEED_FOR_LEG_CONTROL)
        local desired_right_leg_speed = self:calculate_motor_speed_for_leg_angle(current_right_leg_angle, target_right_leg_angle, self.params.LEG_ANGLE_CONTROL_KP, self.params.MAX_MOTOR_SPEED_FOR_LEG_CONTROL)
        self:set_leg_hinge_motor(self.Body.hinges.left_hinge, desired_left_leg_speed, target_leg_torque)
        self:set_leg_hinge_motor(self.Body.hinges.right_hinge, desired_right_leg_speed, target_leg_torque)
    end
end

return Legs
