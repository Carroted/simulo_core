local start = nil;
local prev_shape_guid = nil;
local circle_color = 0x000000;

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
    circle_color = r * 0x10000 + g * 0x100 + b;
end;

function on_pointer_move(point)
    if start then
        local output = runtime_eval({
            input = {
                start_point = start,
                end_point = point,
                prev_shape_guid = prev_shape_guid,
                color = circle_color,
            },
            code = [[
                if input.prev_shape_guid ~= nil then
                    Scene:get_object_by_guid(input.prev_shape_guid):destroy();
                end;

                local between = Input:key_pressed("ShiftLeft");
                local start_point = Input:snap_if_preferred(input.start_point);
                local end_point = Input:snap_if_preferred(input.end_point);

                local diff = end_point - start_point;

                local radius = math.max(math.abs(diff.x), math.abs(diff.y)) / 2;
                local pos = vec2((end_point.x + start_point.x) / 2, (end_point.y + start_point.y) / 2);

                if not between then
                    local size = math.max(math.abs(diff.x), math.abs(diff.y));
                    local new_pos = start_point + vec2(size, size);
                    if diff.x < 0 then
                        new_pos.x = start_point.x - size;
                    end;
                    if diff.y < 0 then
                        new_pos.y = start_point.y - size;
                    end;
                    end_point = new_pos;
                    radius = math.max(math.abs(diff.x), math.abs(diff.y)) / 2;
                    pos = vec2((end_point.x + start_point.x) / 2, (end_point.y + start_point.y) / 2);
                else
                    pos = (start_point + end_point) / 2;
                    radius = math.abs((end_point - pos):magnitude());
                end;

                local circle_color = Color:hex(input.color);
                circle_color.a = 77;

                if radius > 0 then
                    local new_circle_omg = Scene:add_circle({
                        position = pos,
                        radius = radius,
                        is_static = true,
                        color = circle_color,
                    });
                    new_circle_omg:temp_set_collides(false);

                    return {
                        guid = new_circle_omg.guid
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
            color = circle_color,
        },
        code = [[
            print("hi im in remote eval for the Epic Finale!!");

            if input.prev_shape_guid ~= nil then
                print('about to destroy prev_shape_guid ' .. tostring(input.prev_shape_guid));
                Scene:get_object_by_guid(input.prev_shape_guid):destroy();
            end;

            local between = Input:key_pressed("ShiftLeft");
            local start_point = Input:snap_if_preferred(input.start_point);
            local end_point = Input:snap_if_preferred(input.end_point);

            local diff = end_point - start_point;

            local radius = math.max(math.abs(diff.x), math.abs(diff.y)) / 2;
            local pos = vec2((end_point.x + start_point.x) / 2, (end_point.y + start_point.y) / 2);

            if not between then
                local size = math.max(math.abs(diff.x), math.abs(diff.y));
                local new_pos = start_point + vec2(size, size);
                if diff.x < 0 then
                    new_pos.x = start_point.x - size;
                end;
                if diff.y < 0 then
                    new_pos.y = start_point.y - size;
                end;
                end_point = new_pos;
                radius = math.max(math.abs(diff.x), math.abs(diff.y)) / 2;
                pos = vec2((end_point.x + start_point.x) / 2, (end_point.y + start_point.y) / 2);
            else
                pos = (start_point + end_point) / 2;
                radius = math.abs((end_point - pos):magnitude());
            end;

            local circle_color = Color:hex(input.color);

            if radius > 0 then
                local new_circle_omg = Scene:add_circle({
                    position = pos,
                    radius = radius,
                    is_static = false,
                    color = circle_color,
                });
            end;
        ]]
    });
    prev_shape_guid = nil;
    start = nil;
end;