local prev_shape_guid = nil;

function on_update()
    do_explode(Input:pointer_pos());
end;

function do_explode(point)
    local shift = Input:key_pressed("ShiftLeft");
    local output = runtime_eval({
        input = {
            point = point,
            shift = shift,
            prev_shape_guid = prev_shape_guid,
            pressed = Input:pointer_pressed() or Input:key_pressed("E"),
            neg_pressed = Input:key_pressed("Q"),
            just_shift = Input:key_just_pressed("ShiftLeft") or Input:key_just_released("ShiftLeft") or Input:key_just_pressed("Q") or Input:key_just_released("Q") or Input:key_just_pressed("E") or Input:key_just_released("E") or Input:pointer_just_pressed() or Input:pointer_just_released(),
        },
        code = [[
            local prev_shape_guid = input.prev_shape_guid;
            if (prev_shape_guid ~= nil) and (((not input.pressed) and (not input.neg_pressed)) or (input.just_shift)) then
                Scene:get_object_by_guid(input.prev_shape_guid):destroy();
                prev_shape_guid = nil;
                return { removed = true };
            end;
            if (prev_shape_guid ~= nil) and (input.pressed or input.neg_pressed) then
                Scene:get_object_by_guid(prev_shape_guid):set_position(input.point);
            end;

            if (not input.pressed) and (not input.neg_pressed) then return { removed = true }; end;

            function normalize(vec)
                local mag = vec:magnitude()
                if mag ~= 0 and mag ~= 1 then
                    vec = vec / mag;
                end;
                return vec;
            end

            local radius = 50;
            if input.shift then radius = 500; end;

            local impulse = 5;
            if input.neg_pressed then impulse = -5; end;
            
            Scene:explode({ position = input.point, radius = radius, impulse = impulse });
            if input.neg_pressed then
                local objects = Scene:get_objects_in_circle({
                    position = input.point,
                    radius = radius,
                });
                for i=1,#objects do
                    local vel = objects[i]:get_linear_velocity();
                    if vel:magnitude() > 120 then
                        objects[i]:set_linear_velocity(normalize(vel) * 120);
                    end;
                end;
            end;

            if input.prev_shape_guid == nil then
                local color = Color:rgba(111, 157, 255, 64);
                if not input.neg_pressed then
                    color = Color:rgba(255, 102, 102, 64);
                end;
                local new_shape = Scene:add_circle({
                    position = input.point,
                    radius = radius,
                    is_static = true,
                    color = color,
                });
                new_shape:temp_set_collides(false);
                return {
                    new_shape = new_shape.guid
                };
            end;
        ]]
    });
    if output ~= nil then
        if output.new_shape ~= nil then
            prev_shape_guid = output.new_shape;
        end;
        if (output.removed ~= nil) and output.removed then
            prev_shape_guid = nil;
        end;
    end;
end;
