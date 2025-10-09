local Holding = {}

Holding.init = function(self, dependencies)
    -- Do nothing
end
Holding.state = {
    holding = nil;
    holding_point_left = nil;  -- Local point on object for LEFT arm when NOT flipped
    holding_point_right = nil; -- Local point on object for RIGHT arm when NOT flipped
    original_holding_layers = nil;
    original_holding_bodytype = nil;
}
Holding.on_start = function(self, saved_data)
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

Holding.on_save = function(self)
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

Holding.pick_up = function(self, object_to_hold, local_left_hold_point, local_right_hold_point)
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

    self.History:clear_holding_history();
end
Holding.drop_object = function(self)
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





Holding.handle_pick_up = function(self, pick_up_input, pointer_pos)
    if pick_up_input then
        if self.state.holding then
            self:drop_object()
        end
        local objs = Scene:get_objects_in_circle({ position = pointer_pos, radius = 0 });
        for i = 1, #objs do
            if (objs[i]:get_body_type() == BodyType.Dynamic) and (objs[i]:get_mass() < 1) then
                self:pick_up(objs[i], vec2(-0.075, 0), vec2(0.075, 0));
                break;
            end
        end
    end
end

Holding.handle_drop = function(self, drop_input)
    if drop_input then
        if self.state.holding then
            self:drop_object()
        end
    end
end

Holding.handle_holding = function(self, target_holding_pos, target_holding_angle, is_flipped, dt)


    -- Set the held object's final transform
    Holding.state.holding:set_position(target_holding_pos);
    Holding.state.holding:set_angle(target_holding_angle);

    -- Update drop velocity history buffer
    Holding.History.state.holding_cumulative_time = Holding.History.state.holding_cumulative_time + dt
    Holding.History.state.history_index = (Holding.History.state.history_index % Holding.History.state.max_history_frames) + 1
    Holding.History.state.holding_history_buffer[Holding.History.state.history_index] = {
            pos = target_holding_pos, angle = target_holding_angle, time = Holding.History.state.holding_cumulative_time
    }

    -- Position the static arms - **CRITICAL CHANGE HERE**
    local target_left_hand_world = nil
    local target_right_hand_world = nil

    -- Determine which local points on the held object the arms should connect to
    -- This ensures arms connect correctly regardless of the object's visual flip
    local effective_left_hold_point = Holding.state.holding_point_left   -- Default: left arm connects to left point
    local effective_right_hold_point = Holding.state.holding_point_right -- Default: right arm connects to right point

    if is_flipped then
        -- If visually flipped, swap the effective points
        effective_left_hold_point = Holding.state.holding_point_right -- Left arm connects to what *was* the right point
        effective_right_hold_point = Holding.state.holding_point_left  -- Right arm connects to what *was* the left point
    end

    -- Get the world coordinates of these effective connection points
    target_left_hand_world = Holding.state.holding:get_world_point(effective_left_hold_point);
    target_right_hand_world = Holding.state.holding:get_world_point(effective_right_hold_point);

    return target_left_hand_world, target_right_hand_world
end

return Holding
