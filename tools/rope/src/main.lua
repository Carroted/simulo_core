local start = nil;
local overlay = nil;
local capsule_color = 0x000000;
local last_capsule = nil;
local first = true;

-- sounds
local audio = nil;
local current_volume = 0;
local prev_fixed_pointer_pos = vec2(0, 0);
local accumulated_move = vec2(0, 0);

function on_update()
    if self:pointer_just_pressed() then
        on_pointer_down(self:pointer_pos());
    end;
    if self:pointer_just_released() then
        on_pointer_up(self:pointer_pos());
    end;
    
    on_pointer_move(self:pointer_pos());
end;

function lerp(a, b, t)
    return a + (b - a) * t
end;

function on_fixed_update()
    accumulated_move += self:pointer_pos() - prev_fixed_pointer_pos;
    current_volume = lerp(current_volume, math.min(0.04, math.max(0, accumulated_move:magnitude() * 10)), 0.5);

    if audio ~= nil then
        RemoteScene:run({
            input = { audio = audio, pitch = current_volume },
            code = [[
                input.audio:set_volume(input.pitch);
            ]],
        });
    end;

    accumulated_move = vec2(0, 0);
    prev_fixed_pointer_pos = self:pointer_pos();
end;

function get_capsule_color()
    return Color:hex(capsule_color);
end;

function get_fill_color()
    local color = get_capsule_color():clone();
    color.a = 30.0 / 255.0;
    return color;
end;

function on_pointer_down(point)
    first = true;
    accumulated_move = vec2(0, 0);
    prev_fixed_pointer_pos = self:pointer_pos();

    print("Pointer down at " .. point.x .. ", " .. point.y);
    start = point;
    -- random rgb color
    local r = math.random(0x50, 0xff);
    local g = math.random(0x50, 0xff);
    local b = math.random(0x50, 0xff);
    -- put it together to form single color value, like 0xRRGGBB
    capsule_color = r * 0x10000 + g * 0x100 + b;
    
    -- Create overlay for preview
    if overlay == nil then
        overlay = Overlays:add();
    end;
    
    -- Play start sound
    RemoteScene:run({
        input = { point = point, old_audio = audio },
        code = [[
            if input.old_audio ~= nil then input.old_audio:destroy(); end;

            Scene:add_audio({
                asset = require('core/assets/sounds/shape_start.wav'),
                position = input.point,
                volume = 0.1,
            });

            return Scene:add_audio({
                asset = require('core/assets/sounds/shape.wav'),
                position = input.point,
                volume = 0.05,
                pitch = 1,
                looping = true,
            });
        ]],
        callback = function(output)
            audio = output;
        end,
    });
end;

function on_pointer_move(point)
    if start then
        local start_point = self:snap_if_preferred(start);
        local end_point = self:snap_if_preferred(point);
        local shift_pressed = self:key_pressed("ShiftLeft");
        local shift_just_released = self:key_just_released("ShiftLeft");
        
        -- Update overlay preview
        if overlay then
            overlay:set_capsule({
                point_a = start_point,
                point_b = end_point,
                radius = self:get_property("radius").value,
                color = get_capsule_color(),
                fill = get_fill_color(),
            });
        end;
        
        local distance = (end_point - start_point):magnitude();
        local split_distance = self:get_property("segment_length").value;
        
        -- Create new segment if we've moved far enough or released shift
        if distance >= split_distance and not shift_pressed then
            RemoteScene:run({
                input = {
                    start_point = start_point,
                    end_point = end_point,
                    color = capsule_color,
                    last_capsule = last_capsule,
                    radius = self:get_property("radius").value,
                    first = first,
                    split_distance = split_distance,
                },
                code = [[
                    local remaining_distance = (input.end_point - input.start_point):magnitude();
                    local direction = (input.end_point - input.start_point):normalize();

                    local new_capsule = nil;
                    local first_local = input.first;
                    local last_cap = input.last_capsule;
                    local current_start = input.start_point;
                    local final_start = current_start;
                    local final_capsule = last_cap;

                    -- Create multiple segments if we've moved far enough
                    while remaining_distance >= input.split_distance do
                        local segment_end = current_start + direction * input.split_distance;
                        
                        local capsule_color = Color:hex(input.color);
                        
                        -- Calculate the position as the midpoint between start and end
                        local position = (current_start + segment_end) / 2;
                        
                        -- Calculate relative points from the center position
                        local relative_point_a = current_start - position;
                        local relative_point_b = segment_end - position;

                        local start_objs = nil;
                        if first_local then
                            start_objs = Scene:get_objects_in_circle({
                                position = current_start,
                                radius = 0,
                            });
                        end;
                        
                        new_capsule = Scene:add_capsule({
                            position = position,
                            local_point_a = relative_point_a,
                            local_point_b = relative_point_b,
                            radius = input.radius,
                            body_type = BodyType.Static,
                            color = capsule_color,
                        });

                        local hinge = require('core/lib/hinge.lua');

                        if last_cap then
                            hinge({
                                object_a = new_capsule,
                                object_b = last_cap,
                                point = current_start,
                                size = 0.3,
                                sound = false,
                                color = Color:rgba(1, 1, 1, 0),
                            });
                        end;

                        if first_local then
                            if start_objs and #start_objs > 0 then
                                table.sort(start_objs, function(a, b)
                                    return a:get_z_index() > b:get_z_index()
                                end);

                                if start_objs[1] ~= nil then
                                    hinge({
                                        object_a = new_capsule,
                                        object_b = start_objs[1],
                                        point = current_start,
                                        size = 0.3,
                                    });
                                end;
                            end;
                            first_local = false;
                        end;

                        -- Update for next iteration
                        last_cap = new_capsule;
                        final_capsule = new_capsule;
                        current_start = segment_end;
                        final_start = segment_end;
                        
                        -- Recalculate the remaining distance
                        remaining_distance = (input.end_point - current_start):magnitude();
                    end;
                        
                    -- Play grid sound when creating a new segment
                    if final_capsule ~= input.last_capsule then
                        Scene:add_audio({
                            asset = require('core/assets/sounds/grid.wav'),
                            position = final_start,
                            volume = 0.5,
                            pitch = 1.2,
                        });
                    end;

                    return {
                        new_start = final_start,
                        last_capsule = final_capsule,
                        first = first_local
                    };
                ]],
                callback = function(output)
                    if output ~= nil then
                        start = output.new_start;
                        last_capsule = output.last_capsule;
                        first = output.first;
                    end;
                end,
            });
        end;
    end;
end;

function on_pointer_up(point)
    print("Pointer up!");
    
    if start ~= nil then
        local start_point = self:snap_if_preferred(start);
        local end_point = self:snap_if_preferred(point);
        
        -- Create final segment
        RemoteScene:run({
            input = {
                start_point = start_point,
                end_point = end_point,
                color = capsule_color,
                last_capsule = last_capsule,
                audio = audio,
                radius = self:get_property("radius").value,
                first = first,
            },
            code = [[
                -- Stop the looping audio
                if input.audio ~= nil then 
                    input.audio:destroy();
                end;

                if input.last_capsule == nil then
                    return;
                end;

                local hinge = require('core/lib/hinge.lua');
                
                -- Find object to connect at end point
                local end_objs = Scene:get_objects_in_circle({
                    position = input.end_point,
                    radius = 0,
                });
                
                -- Make connection at end point if possible
                if #end_objs > 0 then
                    table.sort(end_objs, function(a, b)
                        return a:get_z_index() > b:get_z_index()
                    end);

                    if end_objs[1] ~= nil and end_objs[1].id ~= input.last_capsule.id then
                        hinge({
                            object_a = input.last_capsule,
                            object_b = end_objs[1],
                            point = input.end_point,
                            size = 0.3,
                        });
                    end;
                end;
                
                -- Make all connected segments dynamic
                local objects_to_make_dynamic = {};
                local visited = {};
                local found = {};

                function scan_connected(obj)
                    if obj == nil or visited[obj.id] then
                        return;
                    end;

                    visited[obj.id] = true;
                    table.insert(found, obj);

                    local connected = obj:get_direct_connected();

                    for _, next_obj in ipairs(connected) do
                        scan_connected(next_obj);
                    end;
                end;

                scan_connected(input.last_capsule);
                
                -- Make all collected objects dynamic
                for _, obj in ipairs(found) do
                    obj:set_body_type(BodyType.Dynamic);
                end;

                Scene:push_undo();
                
                -- Play completion sound
                Scene:add_audio({
                    asset = require('core/assets/sounds/shape_stop.wav'),
                    position = input.end_point,
                    volume = 0.1,
                });
            ]],
        });

        start = nil;
        last_capsule = nil;
        audio = nil;
        first = true;
        
        if overlay ~= nil then
            overlay:destroy();
            overlay = nil;
        end;
    else
        -- Clean up if no drag occurred
        if audio ~= nil then
            RemoteScene:run({
                input = { audio = audio },
                code = [[
                    if input.audio ~= nil then 
                        input.audio:destroy();
                    end;
                ]],
            });
            audio = nil;
        end;
        
        if overlay ~= nil then
            overlay:destroy();
            overlay = nil;
        end;
    end;
end;