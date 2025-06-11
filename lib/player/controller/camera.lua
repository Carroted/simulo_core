local Camera = {}

Camera.cam_pos = vec2(0, 0);

Camera.on_start = function(self, Body, player)
    self.player = player
    if Body then
        self.Body = Body
        player:set_camera_position(self.cam_pos + vec2(0, 0.6))
    else
        self.cam_pos = vec2(0, 0)
        print("Warning: Body component not found on start.")
    end
end

Camera.on_save = function(self)
    return {}  -- Camera position doesn't need to be saved
end

Camera.update_camera = function(self)
    if self.player and self.cam_pos then
        self.player:set_camera_position(self.cam_pos)
    end
end
Camera.move_camera = function(self, velocity, dt, lerp_vec2)
    local target_cam_pos = self.Body:get_position() + vec2(0, 0.6)
    self.cam_pos = self.cam_pos + velocity * dt
    self.cam_pos = lerp_vec2(self.cam_pos, target_cam_pos, dt * 4)
    self.player:set_camera_position(self.cam_pos)
end

return Camera
