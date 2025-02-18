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
            if objs[1] ~= nil then
                Scene:add_attachment({
                    name = "Point Light",
                    component = {
                        name = "Point Light",
                        code = nil,
                    },
                    parent = objs[1],
                    local_position = objs[1]:get_local_point(point),
                    local_angle = -objs[1]:get_angle(),
                    image = "./packages/core/assets/textures/point_light.png",
                    size = 0.0007,
                    color = Color:hex(0xffffff),
                    light = {
                        color = 0xffffff,
                        intensity = 1.2,
                        radius = 10,
                    }
                });
            end;
        ]]
    })
end;
