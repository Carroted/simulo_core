local start = nil;
local prev_shape_guid = nil;
local capsule_color = 0x000000;

local prev_pointer_pos = vec2(0, 0);

function on_update()
    if Input:pointer_just_pressed() then
        on_pointer_down(Input:pointer_pos());
    end;
    if Input:pointer_just_released() then
        on_pointer_up(Input:pointer_pos());
    end;
    if Input:pointer_pos() ~= prev_pointer_pos then
        on_pointer_move(Input:pointer_pos());
    end;
    prev_pointer_pos = Input:pointer_pos();
end;

function on_pointer_down(point)
    print("Pointer down at " .. point.x .. ", " .. point.y);
    start = point;
    -- random rgb color
    local r = math.random(0x50, 0xff);
    local g = math.random(0x50, 0xff);
    local b = math.random(0x50, 0xff);
    -- put it together to form single color value, like 0xRRGGBB
    capsule_color = r * 0x10000 + g * 0x100 + b;
end;

function on_pointer_move(point)
    if start then
        local output = runtime_eval({
            input = {
                start_point = start,
                end_point = point,
                prev_shape_guid = prev_shape_guid,
                color = capsule_color,
            },
            code = [[
                if input.prev_shape_guid ~= nil then
                    Scene:get_object_by_guid(input.prev_shape_guid):destroy();
                end;

                local start_point = Input:snap_if_preferred(input.start_point);
                local end_point = Input:snap_if_preferred(input.end_point);

                local capsule_color = Color:hex(input.color);
                capsule_color.a = 77;

                local distance = (end_point - start_point):magnitude();

                if distance > 0 then
                    local new_capsule_omg = Scene:add_capsule({
                        position = vec2(0, 0),
                        local_point_a = start_point,
                        local_point_b = end_point,
                        radius = 0.1,
                        is_static = true,
                        color = capsule_color,
                    });
                    new_capsule_omg:temp_set_collides(false);

                    return {
                        guid = new_capsule_omg.guid
                    };
                end;
            ]]
        });
        prev_shape_guid = nil;
        if output ~= nil then
            if output.guid ~= nil then
                prev_shape_guid = output.guid;
            end;
        end;
    end;
end;

function on_pointer_up(point)
    print("Pointer up!");
    runtime_eval({
        input = {
            start_point = start,
            end_point = point,
            prev_shape_guid = prev_shape_guid,
            color = capsule_color,
        },
        code = [[
            if input.prev_shape_guid ~= nil then
                Scene:get_object_by_guid(input.prev_shape_guid):destroy();
            end;

            local start_point = Input:snap_if_preferred(input.start_point);
            local end_point = Input:snap_if_preferred(input.end_point);

            local capsule_color = Color:hex(input.color);

            local distance = (end_point - start_point):magnitude();

            if distance > 0 then
                local new_capsule_omg = Scene:add_capsule({
                    position = vec2(0, 0),
                    local_point_a = start_point,
                    local_point_b = end_point,
                    radius = 0.1,
                    is_static = not Input:key_pressed("ShiftLeft"),
                    color = capsule_color,
                });

                return {
                    guid = new_capsule_omg.guid
                };
            end;
        ]]
    });
    prev_shape_guid = nil;
    start = nil;
end;