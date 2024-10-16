local prev_shape = nil;
local polygon_color = get_random_color();
local points = {};
local prev_pointer_pos = vec2(0, 0);

function get_random_color()
    local r = math.random(0x50, 0xff);
    local g = math.random(0x50, 0xff);
    local b = math.random(0x50, 0xff);
    return r * 0x10000 + g * 0x100 + b;
end;

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
    if Input:key_just_pressed("Enter") then
        runtime_eval({
            input = {
                prev_shape = prev_shape,
                color = polygon_color,
                points = points,
            },
            code = [[
                if input.prev_shape ~= nil then
                    input.prev_shape:destroy();
                end;

                local polygon_color = Color:hex(input.color);

                if #input.points > 2 then
                    local center = vec2(0, 0);
                    for _, point in ipairs(input.points) do
                        center = center + point;
                    end;
                    center = center / #input.points;

                    local adjusted_points = {};
                    for _, point in ipairs(input.points) do
                        table.insert(adjusted_points, point - center);
                    end;

                    local new_polygon_omg = Scene:add_polygon({
                        position = center,
                        points = adjusted_points,
                        radius = 0,
                        is_static = Input:key_pressed("ShiftLeft"),
                        color = polygon_color,
                    });
                end;
            ]]
        });
        prev_shape = nil;
        points = {};
        polygon_color = get_random_color();
    end;
    prev_pointer_pos = Input:pointer_pos();
end;

function on_pointer_down(point)
    point = Input:snap_if_preferred(point);
    if #points >= 8 then
        table.remove(points, 1); -- remove the oldest point
    end;
    table.insert(points, point);
    print("Pointer down at " .. point.x .. ", " .. point.y);
end;

function on_pointer_move(point)
    if #points > 1 then
        local output = runtime_eval({
            input = {
                prev_shape = prev_shape,
                color = polygon_color,
                points = points,
                now_point = Input:snap_if_preferred(point),
            },
            code = [[
                if input.prev_shape ~= nil then
                    input.prev_shape:destroy();
                end;

                local polygon_color = Color:hex(input.color);
                polygon_color.a = 77;

                if #input.points > 1 then
                    local adjusted_points = {};
                    for _, point in ipairs(input.points) do
                        table.insert(adjusted_points, point);
                    end;
                    table.insert(adjusted_points, input.now_point);

                    -- useless to have right center in preview poly goner but boo hoo hoo hoo hoo hoo hoo hoo hoo hoo hoo hoo hoo hoo for i=1,math.huge do Console:write('hoo '); end;
                    local center = vec2(0, 0);
                    for _, point in ipairs(adjusted_points) do
                        center = center + point;
                    end;
                    center = center / #adjusted_points;

                    for i, point in ipairs(adjusted_points) do
                        adjusted_points[i] = point - center;
                    end;

                    local new_polygon_omg = Scene:add_polygon({
                        position = center,
                        points = adjusted_points,
                        radius = 0,
                        is_static = Input:key_pressed("ShiftLeft"),
                        color = polygon_color,
                    });
                    new_polygon_omg:temp_set_collides(false);

                    return { object = new_polygon_omg };
                end;
            ]]
        });
        if output ~= nil then
            prev_shape = output.object;
        end;
    end;
end;

function on_pointer_up(point)
    print("Pointer up!");
end;
