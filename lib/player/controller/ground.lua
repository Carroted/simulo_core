local Ground = {}

Ground.init = function(self, dependencies)
    self.Movement = dependencies.Movement
    self.Physics = dependencies.Physics
    self.Body = dependencies.Body
end

Ground.state = {
    ground_friction = 0.1;
    ground_surface_normal = vec2(0,1); -- Normal of the ground surface
    ground_surface_velocity = vec2(0,0); -- For moving surfaces like cars
    ground_object = nil; -- The object the player is currently standing on
}

Ground.check_ground = function(self, body, parts)
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
                direction = self.Physics:down(),
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
                    if self.Movement.state.on_ground == false then
                        self.Movement.timers.landing = self.Movement.params.landing_window
                    end
                    self.Movement.state.on_ground = true
                    current_ground_normal = hits[i].normal
                    current_ground_velocity = hits[i].object:get_linear_velocity()
                    current_ground_friction = hits[i].object:get_friction()
                    current_ground_object = hits[i].object
                    if self.Movement.timers.jump_end <= 0 then
                        self.Movement.timers.coyote = self.Movement.params.coyote_time
                        self.Movement.state.jumping = false
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
        self.Movement.state.on_ground = false
        self.Movement.state.jumping = true
        self.state.ground_surface_normal = self.Physics:up()
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

Ground.try_apply_force_to_ground = function(self, force)
    if self.state.ground_object then
        local ground_point = self.state.ground_object:get_world_point(self.Body:get_position())
        if ground_point then
            self.state.ground_object:apply_force(force, ground_point)
        else
            print("Error: Failed to get world point for ground object in Ground.try_apply_force_to_ground")
        end
    end
end

return Ground
