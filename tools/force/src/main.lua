function on_update()
    if self:pointer_just_pressed() then
        on_pointer_down(self:pointer_pos());
    end;
end;

function on_pointer_down(point)
    print("Pointer down at " .. point.x .. ", " .. point.y);
    RemoteScene:run({
        input = self:snap_if_preferred(point),
        code = [[
            local objs = Scene:get_objects_in_circle({
                position = input,
                radius = 0,
            });

            table.sort(objs, function(a, b)
                return a:get_z_index() > b:get_z_index()
            end);
            
            local obj = objs[1];
            if obj == nil then
                obj = Scene:add_box({
                    position = input,
                    size = vec2(0.5, 0.4) * 0.5,
                    color = 0x9285bd,
                });
            end;

            -- im reusing pointlight sound and you cant stop me
            Scene:add_audio({
                asset = require('core/tools/point_light/assets/light.wav'),
                position = input,
                pitch = 1 + (-0.02 + (0.02 - -0.02) * math.random()),
                volume = 0.6,
            });

            Scene:add_attachment({
                name = "Force",
                component = {
                    name = "Force",
                    version = "0.1.0",
                    id = "core/camera",
                    code = require('core/attachments/force/attachment.lua', 'string'),
                    properties = {
                        {
                            id = "force",
                            name = "Force",
                            input_type = "slider",
                            default_value = 0.5,
                            min_value = 0.05,
                            max_value = 10,
                        },
                    },
                },
                parent = obj,
                local_position = obj:get_local_point(input),
                local_angle = -obj:get_angle(),
                images = {
                    {
                        texture = require("core/attachments/force/attachment.png"),
                        scale = vec2(0.0007, 0.0007) * 0.3,
                    }
                },
                color = Color:hex(0xffffff),
                collider = { shape_type = "circle", radius = 0.1 * 0.6, }
            });

            Scene:push_undo();
        ]]
    })
end;
