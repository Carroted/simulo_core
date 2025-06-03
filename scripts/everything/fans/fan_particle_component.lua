local lifetime = 100
local time = 0
local base_scale = self_component:get_property("size_multiplier").value

function on_step()
    local images = self:get_images()
    local velocity = images[1].offset / 60
    self:set_local_position(self:get_local_position() + velocity)
    local scale = (lifetime-time)/lifetime---(time - 0) * (time - lifetime) * (1/(lifetime^2))
    images[1].scale = vec2(scale*base_scale, scale*base_scale)
    self:set_images(images)
    if time > lifetime then
        self:destroy()
    end
    time = time + 1
end
