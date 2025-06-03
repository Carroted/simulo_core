--[[
Component for fan attachments (the blades that spin around)
--]]

function on_event(id, data)
    if id == "property_changed" then
        local color = self_component:get_property("color").value
        local images = self:get_images()
        images[1].color = color
        images[2].color = color
        self:set_images(images)
    end
end

function on_start()
    on_event("property_changed")
end

