local prev_shape_guid = nil;
-- random rgb color
local r = math.random(0x50, 0xff);
local g = math.random(0x50, 0xff);
local b = math.random(0x50, 0xff);
-- put it together to form single color value, like 0xRRGGBB
local polygon_color = r * 0x10000 + g * 0x100 + b;
local point_count = 0;
local point_1 = nil;
local point_2 = nil;
local point_3 = nil;
local point_4 = nil;
local point_5 = nil;
local point_6 = nil;
local point_7 = nil;
local point_8 = nil;

local prev_pointer_pos = vec2(0, 0);

-- helper function to compute 2D cross product of vectors (p1 -> p2) and (p2 -> p3)
local function cross_product(p1, p2, p3)
    local dx1 = p2.x - p1.x
    local dy1 = p2.y - p1.y
    local dx2 = p3.x - p2.x
    local dy2 = p3.y - p2.y
    return dx1 * dy2 - dy1 * dx2
end;

-- check if polygon (with new point) remains convex
local function is_polygon_convex(polygon)
    local num_points = #polygon
    if num_points < 3 then return true end -- not enough points to form a polygon

    local sign = nil

    for i = 1, num_points do
        -- get three consecutive points (wrap around using modulo)
        local p1 = polygon[i]
        local p2 = polygon[(i % num_points) + 1]
        local p3 = polygon[((i + 1) % num_points) + 1]

        -- calculate cross product
        local cross = cross_product(p1, p2, p3)

        if cross ~= 0 then
            -- determine if all cross products have the same sign
            if sign == nil then
                sign = cross > 0
            elseif (cross > 0) ~= sign then
                return false -- convexity is broken
            end
        end
    end
    return true -- all cross products had the same sign, polygon is convex
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
                prev_shape_guid = prev_shape_guid,
                color = polygon_color,
                point_count = point_count,
                point_1 = point_1,
                point_2 = point_2,
                point_3 = point_3,
                point_4 = point_4,
                point_5 = point_5,
                point_6 = point_6,
                point_7 = point_7,
                point_8 = point_8,
            },
            code = [[
                if input.prev_shape_guid ~= nil then
                    Scene:get_object_by_guid(input.prev_shape_guid):destroy();
                end;

                local polygon_color = Color:hex(input.color);

                if input.point_count > 2 then
                    -- define `points` as being all the points in an array but only the ones that arent nil
                    local points = {};
                    for i = 1, 8 do
                        local point = input["point_" .. i];
                        if point ~= nil then
                            table.insert(points, point);
                        end;
                    end;

                    local new_polygon_omg = Scene:add_polygon({
                        position = vec2(0, 0),
                        points = points,
                        radius = 0,
                        is_static = Input:key_pressed("ShiftLeft"),
                        color = polygon_color,
                    });

                    return {
                        guid = new_polygon_omg.guid
                    };
                end;
            ]]
        });
        prev_shape_guid = nil;
        point_count = 0;
        point_1 = nil;
        point_2 = nil;
        point_3 = nil;
        point_4 = nil;
        point_5 = nil;
        point_6 = nil;
        point_7 = nil;
        point_8 = nil;
        -- random rgb color
        local r = math.random(0x50, 0xff);
        local g = math.random(0x50, 0xff);
        local b = math.random(0x50, 0xff);
        -- put it together to form single color value, like 0xRRGGBB
        polygon_color = r * 0x10000 + g * 0x100 + b;
    end;
    prev_pointer_pos = Input:pointer_pos();
end;

function on_pointer_down(point)
    point = Input:snap_if_preferred(point);
    local num = point_count;
    if num == 0 then
        point_1 = point;
    elseif num == 1 then
        point_2 = point;
    elseif num == 2 then
        point_3 = point;
    elseif num == 3 then
        point_4 = point;
    elseif num == 4 then
        point_5 = point;
    elseif num == 5 then
        point_6 = point;
    elseif num == 6 then
        point_7 = point;
    elseif num == 7 then
        point_8 = point;
    end;
    point_count += 1;
    print("Pointer down at " .. point.x .. ", " .. point.y);
end;

function on_pointer_move(point)
    if point_count > 1 then
        local output = runtime_eval({
            input = {
                prev_shape_guid = prev_shape_guid,
                color = polygon_color,
                point_count = point_count,
                point_1 = point_1,
                point_2 = point_2,
                point_3 = point_3,
                point_4 = point_4,
                point_5 = point_5,
                point_6 = point_6,
                point_7 = point_7,
                point_8 = point_8,
                now_point = Input:snap_if_preferred(point),
            },
            code = [[
                if input.prev_shape_guid ~= nil then
                    Scene:get_object_by_guid(input.prev_shape_guid):destroy();
                end;

                local polygon_color = Color:hex(input.color);
                polygon_color.a = 77;

                if input.point_count > 1 then
                    -- define `points` as being all the points in an array but only the ones that arent nil
                    local points = {};
                    for i = 1, 8 do
                        local point = input["point_" .. i];
                        if point ~= nil then
                            table.insert(points, point);
                        end;
                    end;
                    table.insert(points, input.now_point);

                    local new_polygon_omg = Scene:add_polygon({
                        position = vec2(0, 0),
                        points = points,
                        radius = 0,
                        is_static = Input:key_pressed("ShiftLeft"),
                        color = polygon_color,
                    });
                    new_polygon_omg:temp_set_collides(false);

                    return {
                        guid = new_polygon_omg.guid
                    };
                end;
            ]]
        });
        if output ~= nil then
            if output.guid ~= nil then
                prev_shape_guid = output.guid;
            end;
        end;
    end;
end;

function on_pointer_up(point)
    print("Pointer up!");
end;