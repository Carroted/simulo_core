local Arms = {}

Arms.init = function(self, dependencies)
    self.Input = dependencies.Input
    self.Holding = dependencies.Holding
    self.Body = dependencies.Body
    self.Recoil = dependencies.Recoil
    self.player = dependencies.player
end

Arms.on_start = function(self, saved_data)
    self.pivots.left_arm_pivot = saved_data.left_arm_pivot or vec2(-0.1, 0.15)
    self.pivots.right_arm_pivot = saved_data.right_arm_pivot or vec2(0.1, 0.15)
end

Arms.on_save = function(self)
    return {
        left_arm_pivot = self.pivots.left_arm_pivot,
        right_arm_pivot = self.pivots.right_arm_pivot
    }
end
Arms.params = {
    NEUTRAL_ARM_ANGLE_REL = math.rad(58);
    JUMP_TUCK_ARM_ANGLE_REL = math.rad(10);
    WALK_SWING_AMPLITUDE = math.rad(35); -- same as Legs.WALK_SWING_AMPLITUDE
}
Arms.pivots = {
    left_arm_pivot = vec2(0, 0);
    right_arm_pivot = vec2(0, 0);
}

Arms.handle_holding = function(self, left_pivot_world, right_pivot_world, dt)
    if not self.Holding.state.holding then
        return;
    end;
    -- Currently Holding an Object

    local hold_center = (left_pivot_world + right_pivot_world) / 2.0;

    -- Calculate effective pointer position including scaled, smoothed recoil
    local raw_pointer_pos = self.player:pointer_pos()
    local distance_to_pointer = (raw_pointer_pos - hold_center):length()
    local scale_factor = math.max(self.Recoil.params.MIN_RECOIL_DISTANCE_CLAMP, distance_to_pointer)
    local effective_recoil_offset = self.Recoil.state.current_pointer_recoil_offset * scale_factor
    local pointer_world = raw_pointer_pos + effective_recoil_offset;

    -- Calculate aiming direction vector and distance
    local hold_direction_vec = pointer_world - hold_center;
    local current_aim_dist = hold_direction_vec:length();
    local effective_hold_dist = math.min(current_aim_dist, self.Recoil.params.MAX_HOLD_DISTANCE);

    -- Calculate normalized aiming direction
    local hold_direction_normalized;
    if current_aim_dist < 0.001 then
            hold_direction_normalized = self.Body.parts.body:get_right_direction() or vec2(1,0);
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

    local target_left_hand_world, target_right_hand_world = self.Holding:handle_holding(target_holding_pos, target_holding_angle, is_flipped, dt);

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
            self.Body.parts.left_arm:set_position(left_pivot_world); self.Body.parts.left_arm:set_angle(left_arm_angle);
            self.Body.parts.right_arm:set_position(right_pivot_world); self.Body.parts.right_arm:set_angle(right_arm_angle);
    end

    -- Activation Check
    if self.player:pointer_pressed() and self.Recoil.timers.fire_cooldown_timer <= 0 then
        self.Recoil.timers.fire_cooldown_timer = self.Recoil.params.FIRE_COOLDOWN_DURATION;
        local total_recoil_this_frame = 0;
        local holding_components = self.Holding.state.holding:get_components();
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
                self.Recoil.state.target_pointer_recoil_offset = self.Recoil.state.target_pointer_recoil_offset + recoil_impulse_vector;
            else
                print("Warning: Cannot calculate recoil direction because aim direction is degenerate.")
            end
        end
    end -- End of activation check
end

Arms.handle_neutral = function(self, left_pivot_world, right_pivot_world, body, left_arm, right_arm, is_jumping, walk_cycle_time)
    -- Handle logic for neutral arm positions
    local target_left_arm_rel_angle = self.params.NEUTRAL_ARM_ANGLE_REL
    local target_right_arm_rel_angle = -self.params.NEUTRAL_ARM_ANGLE_REL

    if is_jumping then
        target_left_arm_rel_angle = target_left_arm_rel_angle + self.params.JUMP_TUCK_ARM_ANGLE_REL
        target_right_arm_rel_angle = target_right_arm_rel_angle - self.params.JUMP_TUCK_ARM_ANGLE_REL
    elseif self.Input:move_left() or self.Input:move_right() then
        local body_vel = body:get_linear_velocity()
        local horizontal_vel_mag = (body_vel and math.abs(body_vel.x)) or 0
        local vel_scale = math.min(math.max(horizontal_vel_mag, 0.4), 1.0)
        local swing_offset = math.sin(walk_cycle_time) * self.params.WALK_SWING_AMPLITUDE
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

Arms.handle = function(self, left_pivot_world, right_pivot_world, body_parts, is_jumping, walk_cycle_time, dt, input)
    if self.Holding.state.holding then
        -- Handle logic for holding an object
        self:handle_holding(left_pivot_world, right_pivot_world, dt)
    else
        -- Handle logic for neutral arm positions
        self:handle_neutral(left_pivot_world, right_pivot_world, 
            body_parts.body, 
            body_parts.left_arm, 
            body_parts.right_arm, 
            is_jumping,
            walk_cycle_time
        )
    end
end

return Arms
