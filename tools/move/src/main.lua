local moving_guid = nil;
local last_positions = nil;
local offset = nil;
local body_type = nil;

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
    
    local output = runtime_eval({
        input = {
            point = point,
        },
        code = [[
            local objs = Scene:get_objects_in_circle({
                position = input.point,
                radius = 0,
            });

            if #objs > 0 then
                local body_type = objs[1]:get_body_type();
                objs[1]:set_body_type(BodyType.Static);
                return { guid = objs[1].guid, offset = input.point - objs[1]:get_position(), body_type = body_type, };
            end;
        ]]
    });

    moving_guid = nil;

    if output ~= nil then
        if output.guid ~= nil then 
            moving_guid = output.guid;

            last_positions = {};
            table.insert(last_positions, point);

            offset = output.offset;
            body_type = output.body_type;
        end;
    end;
end;

function on_pointer_move(point)
    if moving_guid then
        local output = runtime_eval({
            input = {
                point = point,
                guid = moving_guid,
                offset = offset,
            },
            code = [[
                local obj = Scene:get_object_by_guid(input.guid);

                if not obj:is_destroyed() then
                    obj:set_body_type(BodyType.Static);
                    obj:set_position(Input:snap_if_preferred(input.point - input.offset));
                end;
            ]]
        });
        table.insert(last_positions, point);
    end;
end;

function on_pointer_up(point)
    if moving_guid then
        print("Pointer up!");

        local function last_n_elements(tbl, n)
            local result = {}
            local length = #tbl
            local startIdx = math.max(length - n + 1, 1)
            
            for i = startIdx, length do
                table.insert(result, tbl[i])
            end
            
            return result
        end;

        local function get_table_average(vec2_table)
            local sum_x, sum_y = 0, 0
            local count = #vec2_table
        
            for _, vec2 in ipairs(vec2_table) do
                sum_x = sum_x + vec2.x
                sum_y = sum_y + vec2.y
            end
        
            if count == 0 then
                return vec2(0, 0);
            end
        
            return vec2(sum_x / count, sum_y / count);
        end;

        local last_2 = last_n_elements(last_positions, 2);
        local vel = last_2[2] - last_2[1];
        
        runtime_eval({
            input = {
                point = point,
                guid = moving_guid,
                offset = offset,
                vel = vel,
                body_type = body_type,
            },
            code = [[
                local obj = Scene:get_object_by_guid(input.guid);

                if not obj:is_destroyed() then
                    obj:set_body_type(input.body_type);
                    obj:set_linear_velocity(input.vel / ((1/60)*3));
                end;
            ]]
        });

        moving_guid = nil;
        offset = nil;
        last_positions = nil;
        body_type = nil;
    end;
end;