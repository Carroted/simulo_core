local History = {}
History.init = function(self, dependencies)
    -- Do nothing
end
History.state = {
    max_history_frames = 10;
    holding_history_buffer = {};
    history_index = 0;
    holding_cumulative_time = 0;
}
History.on_start = function(self, saved_data)
    self:clear_holding_history()
    self.state.holding_cumulative_time = saved_data.holding_cumulative_time or 0
end

History.on_save = function(self)
    return {
        holding_cumulative_time = self.state.holding_cumulative_time
    }
end
-- Helper to clear holding history and reset cumulative time
History.clear_holding_history = function(self)
    self.state.holding_history_buffer = {}
    self.state.history_index = 0
    self.state.holding_cumulative_time = 0
end
History.drop_object = function(self, dropped_object)
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

return History
