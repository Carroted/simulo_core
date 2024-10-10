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
            local objs = Scene:get_objects_in_circle({
                position = input.point,
                radius = 0,
            });
            if Input:key_pressed("ShiftLeft") then
                if objs[1] ~= nil then
                    objs[1]:detach();
                end;
            else
                if (objs[1] ~= nil) and (objs[2] ~= nil) then
                    objs[1]:bolt_to(objs[2]);
                end;
            end;
        ]]
    })
end;