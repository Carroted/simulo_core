function on_update()
    if Input:pointer_just_pressed() then
        on_pointer_down(Input:pointer_pos());
    end;
end;

function on_pointer_down(point)
    print("Pointer down at " .. point.x .. ", " .. point.y);
    runtime_eval({
        input = {
            point = point,
        },
        code = [[
            local point = Input:snap_if_preferred(input.point);

            local objs = Scene:get_objects_in_circle({
                position = point,
                radius = 0,
            });
            if (objs[1] ~= nil) and (objs[2] ~= nil) then
                local hinge = Scene:add_hinge_at_world_point({
                    object_a = objs[1],
                    object_b = objs[2],
                    point = point,
                });
                Scene:add_attachment({
                    name = "Hinge",
                    component = {
                        name = "Hinge",
                        code = require('./packages/core/attachments/hinge/attachment.lua', 'string'),
                    },
                    parent = objs[1],
                    local_position = objs[1]:get_local_point(point),
                    local_angle = 0,
                    image = "./packages/core/attachments/hinge/attachment.png",
                    size = 0.0007,
                    color = Color:hex(0xffffff),
                    saved_data = {
                        hinge = hinge,
                    }
                });
            end;
        ]]
    })
end;
