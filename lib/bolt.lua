local function bolt(tbl)
    local object_a = tbl.object_a;
    local object_b = tbl.object_b;
    local point = tbl.point;
    local size = tbl.size or 1;
    local sound = tbl.sound;
    local color = tbl.color or Color:hex(0xffffff);

    if sound == nil then
        sound = true;
    end;

    local anchor_a = point;
    local anchor_b = point;
    local attachment_parent = nil;
    local reference_angle = 0;

    if object_a ~= nil then
        anchor_a = object_a:get_local_point(point);
        reference_angle = object_a:get_angle();
        attachment_parent = object_a;
    end;

    if object_b ~= nil then
        anchor_b = object_b:get_local_point(point);
        reference_angle = object_b:get_angle();
        attachment_parent = object_b;
    end;

    if (object_a ~= nil) and (object_b ~= nil) then
        reference_angle = object_a:get_angle() - object_b:get_angle();
    end;

    local atch = Scene:add_attachment({
        name = "Bolt",
        component = {
            name = "Bolt",
            version = "0.1.0",
            id = "core/bolt",
            icon = require("core/tools/bolt/icon.png"),
            code = [==[
                local bolt = nil;

                function on_event(id, data)
                    if id == "core/bolt/init" then
                        bolt = data;
                    elseif id == "property_changed" then
                        if data == "color" then
                            local imgs = self:get_images();
                            for i = 1, #imgs do
                                imgs[i].color = self:get_property("color").value;
                            end;
                            self:set_images(imgs);
                        end;
                    end;
                end;

                function on_start(data)
                    if data ~= nil then
                        if data.bolt ~= nil then
                            bolt = data.bolt;
                        end;
                    end;
                end;

                function on_save()
                    return { bolt = bolt };
                end;

                function on_update()
                    if bolt:is_destroyed() then self:destroy(); end;
                end;
            ]==],
            properties = {
                {
                    id = "color",
                    name = "Color",
                    input_type = "color",
                    default_value = color,
                },
            },
        },
        parent = attachment_parent,
        local_position = attachment_parent:get_local_point(point),
        local_angle = 0,
        images = {
            {
                texture = require("core/tools/bolt/assets/bolt.png"),
                scale = vec2(0.0007, 0.0007) * size,
                color = color,
            },
        },
        collider = { shape_type = "circle", radius = 0.1 * size, }
    });

    local bolt = Scene:add_bolt({
        object_a = object_a,
        object_b = object_b,
        local_anchor_a = anchor_a,
        local_anchor_b = anchor_b,
        reference_angle = reference_angle,
        attachment = atch,
    });

    atch:send_event("core/bolt/init", bolt);
    
    if sound then
        Scene:add_audio({
            asset = require('core/tools/bolt/assets/up.wav'),
            position = point,
            pitch = 0.85 + (-0.1 + (0.1 - -0.1) * math.random()),
            volume = 0.05,
        });
    end;

    return atch;
end;

return bolt;
