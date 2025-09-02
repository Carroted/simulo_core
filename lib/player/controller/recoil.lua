local Recoil = {}

Recoil.on_start = function(self)
    self.timers.fire_cooldown_timer = 0
    self.state.target_pointer_recoil_offset = vec2(0, 0)
    self.state.current_pointer_recoil_offset = vec2(0, 0)
end

Recoil.on_save = function(self)
    return {}  -- No persistent data needed for recoil
end

Recoil.init = function(self, dependencies)
    -- Do nothing
end
Recoil.params = {
    FIRE_COOLDOWN_DURATION = 0.3;
    RECOIL_APPLICATION_SPEED = 40.0; -- Updated Constant
    RECOIL_DECAY_SPEED = 10.0;   -- Updated Constant
    MIN_RECOIL_DISTANCE_CLAMP = 0.1;
    MAX_HOLD_DISTANCE = 0.4;
}
Recoil.state = {
    target_pointer_recoil_offset = vec2(0, 0);
    current_pointer_recoil_offset = vec2(0, 0);
}
Recoil.timers = {
    fire_cooldown_timer = 0;
}

Recoil.update_timers = function(self, dt)
    self.timers.fire_cooldown_timer = math.max(0, self.timers.fire_cooldown_timer - dt)
end

Recoil.update_recoil = function(self, dt, lerp_vec2)
    self.state.current_pointer_recoil_offset = lerp_vec2(self.state.current_pointer_recoil_offset, self.state.target_pointer_recoil_offset, dt * self.params.RECOIL_APPLICATION_SPEED)
    self.state.target_pointer_recoil_offset = lerp_vec2(self.state.target_pointer_recoil_offset, vec2(0, 0), dt * self.params.RECOIL_DECAY_SPEED)
    if self.state.target_pointer_recoil_offset:length() ^ 2 < 0.00001 then
        self.state.target_pointer_recoil_offset = vec2(0, 0)
        if self.state.current_pointer_recoil_offset:length() ^ 2 < 0.00001 then
            self.state.current_pointer_recoil_offset = vec2(0, 0)
        end
    end
end

return Recoil
