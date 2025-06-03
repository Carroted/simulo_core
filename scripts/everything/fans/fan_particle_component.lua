local lifetime = 100
local time = 0
local base_scale = self_component:get_property("size_multiplier").value
local velocity_x = self_component:get_property("velocity_x").value
local velocity_y = self_component:get_property("velocity_y").value

function on_step()
    local images = self:get_images()
    local velocity = vec2(velocity_x, velocity_y)
    self:set_local_position(self:get_local_position() + velocity)
    local scale = (lifetime-time)/lifetime---(time - 0) * (time - lifetime) * (1/(lifetime^2))
    images[1].scale = vec2(scale*base_scale, scale*base_scale)
    self:set_images(images)
    if time > lifetime then
        self:destroy()
    end
    time = time + 1
end
