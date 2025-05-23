local start = nil;
local prev_shape = nil;
local capsule_color = 0x000000;
local last_capsule = nil;
local split_distance = 0.2;
local past_parts = nil;
local first = false;

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
    past_parts = {};
    first = true;
end;

function on_pointer_move(point)
    if start then
        local remaining_distance = (point - start):magnitude();
        local direction = (point - start):normalize();
        
        -- create multiple capsules if moving more than split_distance
        while remaining_distance >= split_distance do
            local end_point = start + direction * split_distance;

            local output = runtime_eval({
                input = {
                    start_point = start,
                    end_point = end_point,
                    prev_shape = prev_shape,
                    color = capsule_color,
                    split_distance = split_distance,
                    last_capsule = last_capsule,
                    first = first,
                },
                code = [[
                    if input.prev_shape ~= nil then
                        input.prev_shape:destroy();
                    end;

                    local start_point = Input:snap_if_preferred(input.start_point);
                    local end_point = Input:snap_if_preferred(input.end_point);

                    local capsule_color = Color:hex(input.color);

                    local distance = (end_point - start_point):magnitude();

                    if distance > 0 then
                        local start_stuff = Scene:get_objects_in_circle({
                            position = start_point,
                            radius = 0,
                        });

                        local new_capsule_omg = Scene:add_capsule({
                            position = vec2(0, 0),
                            local_point_a = start_point,
                            local_point_b = end_point,
                            radius = 0.05,
                            is_static = true,
                            color = capsule_color,
                        });

                        if input.last_capsule then
                            Scene:add_hinge_at_world_point({
                                object_a = new_capsule_omg,
                                object_b = input.last_capsule,
                                point = start_point,
                            });
                        end;

                        if input.first then
                            if start_stuff[1] ~= nil then
                                Scene:add_hinge_at_world_point({
                                    object_a = new_capsule_omg,
                                    object_b = start_stuff[1],
                                    point = start_point,
                                });
                            end;
                        end;

                        return {
                            new_start = end_point,
                            last_capsule = new_capsule_omg,
                        };
                    end;
                ]]
            });

            prev_shape = nil;
            if output ~= nil then
                if output.new_start ~= nil then
                    start = output.new_start;
                    last_capsule = output.last_capsule;
                    table.insert(past_parts, output.last_capsule);
                    first = false;
                end;
            end;

            -- Update remaining distance and loop if needed
            remaining_distance = (point - start):magnitude();
        end;

        -- if the remaining distance is less than split_distance, create a temp preview
        if remaining_distance > 0 then
            local end_point = point;  -- since this is a preview, it's wherever the pointer is

            local output = runtime_eval({
                input = {
                    start_point = start,
                    end_point = end_point,
                    prev_shape = prev_shape,
                    color = capsule_color,
                    split_distance = split_distance,
                    last_capsule = last_capsule,
                    first = first,
                },
                code = [[
                    if input.prev_shape ~= nil then
                        input.prev_shape:destroy();
                    end;

                    local start_point = Input:snap_if_preferred(input.start_point);
                    local end_point = Input:snap_if_preferred(input.end_point);

                    local capsule_color = Color:hex(input.color);
                    capsule_color.a = 77;  -- transparency to indicate preview

                    local new_capsule_omg = Scene:add_capsule({
                        position = vec2(0, 0),
                        local_point_a = start_point,
                        local_point_b = end_point,
                        radius = 0.05,
                        is_static = true,
                        color = capsule_color,
                    });
                    new_capsule_omg:temp_set_collides(false);

                    return {
                        shape = new_capsule_omg
                    };
                ]]
            });

            prev_shape = nil;
            if output ~= nil and output.shape ~= nil then
                prev_shape = output.shape;
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
            prev_shape = prev_shape,
            color = capsule_color,
            last_capsule = last_capsule,
            past_parts = past_parts,
        },
        code = [[
            if input.prev_shape ~= nil then
                input.prev_shape:destroy();
            end;

            local start_point = Input:snap_if_preferred(input.start_point);
            local end_point = Input:snap_if_preferred(input.end_point);

            local capsule_color = Color:hex(input.color);

            local distance = (end_point - start_point):magnitude();

           local end_stuff = Scene:get_objects_in_circle({
                position = end_point,
                radius = 0,
            });
            local filtered_stuff = {};
            for _, obj in ipairs(end_stuff) do
                if not obj:is_destroyed() then
                    table.insert(filtered_stuff, obj);
                end;
            end;

            if distance > 0 then
                local new_capsule_omg = Scene:add_capsule({
                    position = vec2(0, 0),
                    local_point_a = start_point,
                    local_point_b = end_point,
                    radius = 0.05,
                    is_static = true,
                    color = capsule_color,
                });

                if input.last_capsule ~= nil then
                    Scene:add_hinge_at_world_point({
                        object_a = new_capsule_omg,
                        object_b = input.last_capsule,
                        point = start_point,
                    });
                end;

                if filtered_stuff[1] ~= nil then
                    Scene:add_hinge_at_world_point({
                        object_a = new_capsule_omg,
                        object_b = filtered_stuff[1],
                        point = end_point,
                    });
                end;

                --if Input:key_pressed("ShiftLeft") then
                    new_capsule_omg:set_body_type(BodyType.Dynamic);
                --end;
            else
                if filtered_stuff[1] ~= nil then
                    Scene:add_hinge_at_world_point({
                        object_a = input.last_capsule,
                        object_b = filtered_stuff[1],
                        point = end_point,
                    });
                end;
            end;

            --if (input.last_capsule ~= nil) and (Input:key_pressed("ShiftLeft")) then
                input.last_capsule:set_body_type(BodyType.Dynamic);
                
            --end;

            if input.past_parts ~= nil then
                for i=1,#input.past_parts do
                    input.past_parts[i]:set_body_type(BodyType.Dynamic);
                end;
            end;
        ]]
    });
    prev_shape = nil;
    start = nil;
    last_capsule = nil;
    past_parts = nil;
    first = false;
end;
