local start = nil;
local overlay = nil;
local capsule_color = 0x000000;
local last_capsule = nil;

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
        overlay:set_capsule({
            point_a = start_point,
            point_b = end_point,
            radius = self:get_property("radius").value,
            color = get_capsule_color(),
            fill = get_fill_color(),
        });
        
        local distance = (end_point - start_point):magnitude();

        local split_distance = self:get_property("segment_length").value;
        
        -- Create new segment if we've moved far enough or released shift
        if distance > 0 and ((distance > split_distance and not shift_pressed) or shift_just_released) then
            RemoteScene:run({
                input = {
                    start_point = start_point,
                    end_point = end_point,
                    color = capsule_color,
                    last_capsule = last_capsule,
                    radius = self:get_property("radius").value,
                },
                code = [[
                    local capsule_color = Color:hex(input.color);
                    
                    -- Calculate the position as the midpoint between start and end
                    local position = (input.start_point + input.end_point) / 2;
                    
                    -- Calculate relative points from the center position
                    local relative_point_a = input.start_point - position;
                    local relative_point_b = input.end_point - position;
                    
                    local new_capsule = Scene:add_capsule({
                        position = position,
                        local_point_a = relative_point_a,
                        local_point_b = relative_point_b,
                        radius = input.radius,
                        body_type = BodyType.Static,
                        color = capsule_color,
                    });

                    if input.last_capsule then
                        Scene:add_bolt({
                            object_a = new_capsule,
                            object_b = input.last_capsule,
                            local_anchor_a = new_capsule:get_local_point(input.end_point),
                            local_anchor_b = input.last_capsule:get_local_point(input.end_point),
                        });
                    end;
                    
                    -- Play grid sound when creating a new segment
                    Scene:add_audio({
                        asset = require('core/assets/sounds/grid.wav'),
                        position = input.end_point,
                        volume = 0.5,
                        pitch = 1.2,
                    });

                    return new_capsule;
                ]],
                callback = function(output)
                    if output ~= nil then
                        start = end_point;
                        last_capsule = output;
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
            },
            code = [[
                -- Stop the looping audio
                if input.audio ~= nil then 
                    input.audio:destroy();
                end;
                
                local distance = (input.end_point - input.start_point):magnitude();
                local capsule_color = Color:hex(input.color);
                local new_capsule = nil;
                
                -- Only create if there's enough distance
                if distance > 0.05 then
                    -- Calculate the position as the midpoint between start and end
                    local position = (input.start_point + input.end_point) / 2;
                    
                    -- Calculate relative points from the center position
                    local relative_point_a = input.start_point - position;
                    local relative_point_b = input.end_point - position;
                    
                    new_capsule = Scene:add_capsule({
                        position = position,
                        local_point_a = relative_point_a,
                        local_point_b = relative_point_b,
                        radius = input.radius,
                        body_type = BodyType.Static,
                        color = capsule_color,
                    });

                    if input.last_capsule ~= nil then
                        Scene:add_bolt({
                            object_a = new_capsule,
                            object_b = input.last_capsule,
                            local_anchor_a = new_capsule:get_local_point(input.end_point),
                            local_anchor_b = input.last_capsule:get_local_point(input.end_point),
                        });
                    end;
                end;
                
                -- Make all connected segments dynamic
                local objects_to_make_dynamic = {};
                
                if new_capsule ~= nil then
                    table.insert(objects_to_make_dynamic, new_capsule);
                    -- Get all bolted objects and make them dynamic
                    for _, obj in ipairs(new_capsule:get_all_bolted()) do
                        table.insert(objects_to_make_dynamic, obj);
                    end;
                elseif input.last_capsule ~= nil then
                    table.insert(objects_to_make_dynamic, input.last_capsule);
                    -- Get all bolted objects and make them dynamic
                    for _, obj in ipairs(input.last_capsule:get_all_bolted()) do
                        table.insert(objects_to_make_dynamic, obj);
                    end;
                end;
                
                -- Make all collected objects dynamic
                for _, obj in ipairs(objects_to_make_dynamic) do
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
            callback = function(output)
                last_capsule = nil;
                audio = nil;
                
                if overlay ~= nil then
                    overlay:destroy();
                    overlay = nil;
                end;
            end,
        });
    end;

    start = nil;
end;