local rotating = nil;
local offset = nil;

function on_update()
    if self:pointer_just_pressed() then
        on_pointer_down(self:pointer_pos());
    end;
    if self:pointer_just_released() then
        on_pointer_up(self:pointer_pos());
    end;
    if self:pointer_pos() ~= prev_pointer_pos then
        on_pointer_move(self:pointer_pos());
    end;
    prev_pointer_pos = self:pointer_pos();
end;

function on_pointer_down(point)
    print("pointer down at " .. point.x .. ", " .. point.y);
    
    RemoteScene:run({
        input = point,
        code = [[
            local objs = Scene:get_objects_in_circle({
                position = input,
                radius = 0,
            });

            table.sort(objs, function(a, b)
                return a:get_z_index() > b:get_z_index()
            end);

            if #objs > 0 then
                local obj = objs[1];

                local obj_position = objs[1]:get_pivot();
                local angle = math.atan2(input.y - obj_position.y, input.x - obj_position.x);

                local offset = angle - objs[1]:get_angle();

                return { object = obj, offset = offset };
            end;
        ]],
        callback = function(output)
            if output and output.object then 
                rotating = output.object;
                offset = output.offset;
            end;
        end,
    });
end;

function on_pointer_move(point)
    if rotating then
        RemoteScene:run({
            input = {
                object = rotating,
                pointer = point,
                offset = offset,
            },
            code = [[
                if input.object then
                    local obj_position = input.object:get_pivot();
                    local angle = math.atan2(input.pointer.y - obj_position.y, input.pointer.x - obj_position.x);

                    input.object:set_angle(angle - input.offset);
                end;
            ]]
        });
    end;
end;

function on_pointer_up(point)
    if rotating then
        print("pointer up!");
        rotating = nil;
        initial_object_angle = nil;
        initial_pointer_angle = nil;

        RemoteScene:run({
            code = [[
                Scene:push_undo();
            ]]
        });
    end;
end;

