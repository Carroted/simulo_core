local prev_line = nil;
local ground_body = nil;
local dragging = nil;
local drag_local_point = nil;

function on_pointer_down(point)
    local output = runtime_eval({
        input = {
            point = point,
        },
        code = [[
            local objects_in_circle = Scene:get_objects_in_circle({
                position = input.point,
                radius = 0,
            });

            if objects_in_circle[1] ~= nil then
                local obj = objects_in_circle[1];
                local ground = Scene:add_circle({
                    position = input.point,
                    radius = 0.02,
                    is_static = true,
                    color = 0xffffff,
                });
                ground:temp_set_collides(false);
                return {
                    success = true,
                    dragging = obj.guid,
                    ground_body = ground.guid,
                    drag_local_point = obj:get_local_point(input.point),
                };
            else
                return { success = false };
            end;
        ]]
    });
    if output ~= nil and output.success then
        dragging = output.dragging;
        ground_body = output.ground_body;
        drag_local_point = output.drag_local_point;
    end;
end;

function on_pointer_move(point)
    if ground_body ~= nil and dragging ~= nil then
        local output = runtime_eval({
            input = {
                point = point,
                ground_body = ground_body,
                dragging = dragging,
                prev_line = prev_line,
                drag_local_point = drag_local_point,
            },
            code = [[
                if input.prev_line ~= nil then
                    Scene:get_object_by_guid(input.prev_line):destroy();
                end;

                function line(line_start,line_end,thickness,color,static)
                    local pos = (line_start+line_end)/2
                    local sx = (line_start-line_end):magnitude()
                    local relative_line_end = line_end-pos
                    local rotation = math.atan(relative_line_end.y/relative_line_end.x)
                    local line = Scene:add_box({
                        position = pos,
                        size = vec2(sx, thickness),
                        is_static = static,
                        color = color
                    });

                    line:temp_set_collides(false);
                    line:set_angle(rotation);
                    
                    return line;
                end;

                local ground = Scene:get_object_by_guid(input.ground_body);
                local dragging = Scene:get_object_by_guid(input.dragging);
                ground:set_position(input.point);

                local prev_line = line(input.point, dragging:get_world_point(input.drag_local_point),0.04,0xffffff,true);

                return {
                    prev_line = prev_line.guid,
                };
            ]]
        });
        if output ~= nil and output.prev_line ~= nil then
            prev_line = output.prev_line;
        end;
    end;
end;

function on_pointer_up(point)
    if ground_body ~= nil and dragging ~= nil then
        local output = runtime_eval({
            input = {
                point = point,
                ground_body = ground_body,
                dragging = dragging,
                prev_line = prev_line,
                drag_local_point = drag_local_point,
            },
            code = [[
                if input.prev_line ~= nil then
                    Scene:get_object_by_guid(input.prev_line):destroy();
                end;

                if input.ground_body ~= nil then
                    Scene:get_object_by_guid(input.ground_body):destroy();
                end;

                local dragging = Scene:get_object_by_guid(input.dragging);
                local vec = dragging:get_world_point(input.drag_local_point) - input.point;
                dragging:apply_force(vec * 75, dragging:get_world_point(input.drag_local_point));
            ]]
        });
        prev_line = nil;
        ground_body = nil;
        dragging = nil;
    end;
end;

local prev_pointer_pos = vec2(0, 0);

-- Our on_pointer_down, on_pointer_up etc aren't called by Simulo itself but instead manually in here when we detect changes
function on_update()
    local pointer_pos = Input:pointer_pos();

    if Input:pointer_just_pressed() then
        on_pointer_down(pointer_pos);
    end;

    if Input:pointer_just_released() then
        on_pointer_up(pointer_pos);
    end;

    -- If the pointer moved
    if pointer_pos ~= prev_pointer_pos then
        on_pointer_move(pointer_pos);
    end;

    -- Update previous pointer pos at the end
    prev_pointer_pos = pointer_pos;
end;
