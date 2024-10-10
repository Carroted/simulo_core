local start = nil;
local prev_shape = nil;
local capsule_color = 0x000000;
local last_capsule = nil;
local split_distance = 0.2;

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
                prev_shape = prev_shape,
                color = capsule_color,
                split_distance = split_distance,
                last_capsule = last_capsule,
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
                    if ((distance > input.split_distance) and (not Input:key_pressed("ShiftLeft"))) or (Input:key_just_released("ShiftLeft")) then
                        local new_capsule_omg = Scene:add_capsule({
                            position = vec2(0, 0),
                            local_point_a = start_point,
                            local_point_b = end_point,
                            radius = 0.1,
                            is_static = true,
                            color = capsule_color,
                        });

                        if input.last_capsule then
                            new_capsule_omg:bolt_to(input.last_capsule);
                        end;

                        return {
                            new_start = end_point,
                            last_capsule = new_capsule_omg,
                        };
                    else
                        capsule_color.a = 77;

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
                            shape = new_capsule_omg
                        };
                    end;
                end;
            ]]
        });
        prev_shape = nil;
        if output ~= nil then
            if output.shape ~= nil then
                prev_shape = output.shape;
            end;
            if output.new_start ~= nil then
                start = output.new_start;
                last_capsule = output.last_capsule;
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
                local new_capsule_omg = Scene:add_capsule({
                    position = vec2(0, 0),
                    local_point_a = start_point,
                    local_point_b = end_point,
                    radius = 0.1,
                    is_static = true,
                    color = capsule_color,
                });

                if input.last_capsule ~= nil then
                    new_capsule_omg:bolt_to(input.last_capsule);
                end;

                --if Input:key_pressed("ShiftLeft") then
                    new_capsule_omg:set_body_type(BodyType.Dynamic);
                --end;
            end;

            --if (input.last_capsule ~= nil) and (Input:key_pressed("ShiftLeft")) then
                input.last_capsule:set_body_type(BodyType.Dynamic);
            --end;
        ]]
    });
    prev_shape = nil;
    start = nil;
    last_capsule = nil;
end;