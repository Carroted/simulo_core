function on_update()
    if self:pointer_just_pressed() then
        on_pointer_down(self:pointer_pos());
    end;
    if self:pointer_just_released() then
        on_pointer_up(self:pointer_pos());
    end;
end;

function on_pointer_down(point)
    print("Pointer down at " .. point.x .. ", " .. point.y);
    RemoteScene:run({
        input = point,
        code = [[
            local objs = Scene:get_objects_in_circle({
                position = input,
                radius = 0,
            });
            if #objs > 0 then
                Scene:add_audio({
                    asset = require('core/tools/bolt/assets/down.wav'),
                    position = input,
                    pitch = 0.85 + (-0.1 + (0.1 - -0.1) * math.random()),
                    volume = 0.05,
                });
            end;
        ]],
    })
end;

function on_pointer_up(point)
    RemoteScene:run({
        input = point,
        code = [[
            local objs = Scene:get_objects_in_circle({
                position = input,
                radius = 0,
            });

            table.sort(objs, function(a, b)
                return a:get_z_index() > b:get_z_index()
            end);

            if (objs[1] ~= nil) or (objs[2] ~= nil) then
                local bolt = require('core/lib/bolt.lua');
                bolt({
                    object_a = objs[1],
                    object_b = objs[2],
                    point = input,
                    size = 0.3,
                });

                Scene:push_undo();
            end;
        ]],
    });
end;
