local start = nil;
local overlay = nil;
local capsule_color = 0x89463d;

-- sounds
local audio = nil;
local current_volume = 0;
local prev_fixed_pointer_pos = vec2(0, 0);
local accumulated_move = vec2(0, 0);

local should_play_snap = true;
local fixed_update = 0;
local last_grid_pointer_pos = self:preferred_pointer_pos();

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

    fixed_update += 1;

    if fixed_update % 4 == 0 then
        should_play_snap = true;
    end;
end;

function get_fill_color()
    local color = capsule_color:clone();
    color.a = 30.0 / 255.0;
    return color;
end;

function on_pointer_down(point)
    exposed = self:get_property("exposed").value;

    accumulated_move = vec2(0, 0);
    prev_fixed_pointer_pos = self:pointer_pos();

    print("Pointer down at " .. point.x .. ", " .. point.y);
    start = point;

    capsule_color = Color:mix(0x89463d, 0xffb978, 0.6);
    
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
        if should_play_snap and self:grid_enabled() and ((self:grid_pointer_pos() - last_grid_pointer_pos):magnitude() > 0.0) then
            RemoteScene:run({
                input = point,
                code = [[
                    Scene:add_audio({
                        asset = require('core/assets/sounds/grid.wav'),
                        position = input,
                        volume = 0.7,
                        pitch = 1.2,
                    });
                ]],
            });
            should_play_snap = false;
        end;

        local start_point = self:snap_if_preferred(start);
        local end_point = self:snap_if_preferred(point);
        
        -- Update overlay preview
        overlay:set_capsule({
            point_a = start_point,
            point_b = end_point,
            radius = self:get_property("radius").value,
            color = capsule_color,
            fill = get_fill_color(),
        });
    end;

    last_grid_pointer_pos = self:preferred_pointer_pos();
end;

function on_pointer_up(point)
    print("Pointer up!");
    
    if start ~= nil then
        capsule_color = 0x89463d;

        local start_point = self:snap_if_preferred(start);
        local end_point = self:snap_if_preferred(point);
        
        -- Create final segment
        RemoteScene:run({
            input = {
                start_point = start_point,
                end_point = end_point,
                color = capsule_color,
                audio = audio,
                radius = self:get_property("radius").value,
                exposed = self:get_property("exposed").value,
                split_distance = 0.17,
            },
            code = [[
                -- Stop the looping audio
                if input.audio ~= nil then 
                    input.audio:destroy();
                end;

                local bolt = require('core/lib/bolt.lua');

                local conductor = require ('core/components/conductor');
                local wire_color = require ('core/components/wire_color');
                
                local distance = (input.end_point - input.start_point):magnitude();
                local capsule_color = Color:hex(input.color);
                
                -- Only create if there's enough distance
                if distance > 0.05 then
                    if input.exposed then
                        -- Calculate the position as the midpoint between start and end
                        local position = (input.start_point + input.end_point) / 2;
                        
                        -- Calculate relative points from the center position
                        local relative_point_a = input.start_point - position;
                        local relative_point_b = input.end_point - position;

                        local start_objs = Scene:get_objects_in_circle({
                            position = input.start_point,
                            radius = 0,
                        });

                        local end_objs = Scene:get_objects_in_circle({
                            position = input.end_point,
                            radius = 0,
                        });

                        local wire = Scene:add_capsule({
                            position = position,
                            local_point_a = relative_point_a,
                            local_point_b = relative_point_b,
                            radius = input.radius,
                            color = capsule_color,
                            name = "Wire",
                        });
                        
                        local wire_conductor = wire:add_component({ hash = conductor });
                        local prop = wire_conductor:get_property("exposed");
                        prop.value = true;
                        wire_conductor:set_property("exposed", prop);

                        wire:add_component({ hash = wire_color });

                        table.sort(start_objs, function(a, b)
                            return a:get_z_index() > b:get_z_index()
                        end);

                        table.sort(end_objs, function(a, b)
                            return a:get_z_index() > b:get_z_index()
                        end);

                        local bolt_color = Color:hex(0xffa081);
                        bolt_color.a = 0.28;

                        if start_objs[1] ~= nil then
                            bolt({
                                object_a = wire,
                                object_b = start_objs[1],
                                point = input.start_point,
                                size = input.radius * 6,
                                color = bolt_color,
                            });
                        end;

                        if end_objs[1] ~= nil then
                            bolt({
                                object_a = wire,
                                object_b = end_objs[1],
                                point = input.end_point,
                                size = input.radius * 6,
                                color = bolt_color,
                            });
                        end;
                    else

    
    -- Connect end terminal to any objects at the ending point
    local end_objs = Scene:get_objects_in_circle({
        position = input.end_point,
        radius = 0,
    });

    local remaining_distance = (input.end_point - input.start_point):magnitude();
    local direction = (input.end_point - input.start_point):normalize();
    local perpendicular = vec2(-direction.y, direction.x);
    
    local new_capsule = nil;
    local last_cap = input.last_capsule;
    local current_start = input.start_point;
    local final_start = current_start;
    local final_capsule = last_cap;
    local exposed_capsule_color = Color:hex(0x89463d);
    
    -- Calculate total number of segments we'll need
    local total_segments = math.floor(remaining_distance / input.split_distance);
    local segment_index = 0;
    
    -- Create start terminal (box)
    local start_objs = Scene:get_objects_in_circle({
        position = current_start,
        radius = 0,
    });
    
    local start_terminal = Scene:add_box({
        position = current_start,
        angle = math.atan2(direction.y, direction.x),
        size = vec2(input.radius * 7, input.radius * 1.6),
        color = exposed_capsule_color,
    });
    local start_conductor = start_terminal:add_component({ hash = conductor });
    local prop = start_conductor:get_property("exposed");
    prop.value = true;
    start_conductor:set_property("exposed", prop);

    start_terminal:add_component({ hash = wire_color });
    
    -- Create red box after start terminal
    local red_start_pos = current_start + direction * (input.radius * 3.5);
    local red_start_box = Scene:add_box({
        position = red_start_pos,
        angle = math.atan2(direction.y, direction.x),
        size = vec2(input.radius * 5, input.radius * 2.4),
        color = Color.RED,
    });
    local red_conductor = red_start_box:add_component({ hash = conductor });
    local prop = red_conductor:get_property("exposed");
    prop.value = false;
    red_conductor:set_property("exposed", prop);
    
    -- Bolt start terminal to red box
    local bolt_color = Color:hex(0xffd6b2);
    bolt_color.a = 0.3;
    bolt({
        object_a = start_terminal,
        object_b = red_start_box,
        point = red_start_pos - direction * (input.radius * 0.5),
        size = input.radius * 6,
        color = Color:rgba(1,1,1,0),
    });
    
    -- Connect start terminal to any objects at the starting point
    if start_objs and #start_objs > 0 then
        table.sort(start_objs, function(a, b)
            return a:get_z_index() > b:get_z_index()
        end);
        
        local hinge = require('core/lib/hinge.lua');
        if start_objs[1] ~= nil then
            hinge({
                object_a = start_terminal,
                object_b = start_objs[1],
                point = current_start,
                size = 0.3,
            });
        end;
    end;
    
    -- Update current_start to after the red box
    current_start = red_start_pos + direction * (input.radius * 2.4);
    last_cap = red_start_box;
    
    -- Recalculate remaining distance
    remaining_distance = (input.end_point - current_start):magnitude();
    
    -- Create middle segments
    while remaining_distance >= input.split_distance and segment_index < total_segments - 1 do
        local segment_end = current_start + direction * input.split_distance;
        
        -- Calculate the position as the midpoint between start and end
        local position = (current_start + segment_end) / 2;
        
        -- Calculate relative points from the center position
        local relative_point_a = current_start - position;
        local relative_point_b = segment_end - position;
        
        new_capsule = Scene:add_capsule({
            position = position,
            local_point_a = relative_point_a,
            local_point_b = relative_point_b,
            radius = input.radius,
            color = Color.RED,
            name = "Wire",
        });
        local capsule_conductor = new_capsule:add_component({ hash = conductor });
        local prop = capsule_conductor:get_property("exposed");
        prop.value = false;
        capsule_conductor:set_property("exposed", prop);
        
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
        
        -- Update for next iteration
        last_cap = new_capsule;
        final_capsule = new_capsule;
        current_start = segment_end;
        final_start = segment_end;
        segment_index = segment_index + 1;
        
        -- Recalculate the remaining distance
        remaining_distance = (input.end_point - current_start):magnitude();
    end;
    

    -- Create end terminal (box)
    local end_terminal = Scene:add_box({
        position = input.end_point,
        angle = math.atan2(direction.y, direction.x),
        size = vec2(input.radius * 7, input.radius * 1.6),
        color = exposed_capsule_color,
    });
    local end_conductor = end_terminal:add_component({ hash = conductor });
    local prop = end_conductor:get_property("exposed");
    prop.value = true;
    end_conductor:set_property("exposed", prop);

    end_terminal:add_component({ hash = wire_color });

    -- Create red box before end terminal
    local red_end_pos = input.end_point - direction * (input.radius * 1.1);
    local red_end_box = Scene:add_box({
        position = red_end_pos,
        angle = math.atan2(direction.y, direction.x),
        size = vec2(input.radius * 4, input.radius * 2.4),
        color = Color.RED,
    });
    local red_conductor = red_end_box:add_component({ hash = conductor });
    local prop = red_conductor:get_property("exposed");
    prop.value = false;
    red_conductor:set_property("exposed", prop);
    
    -- Connect last middle segment to red end box
    if final_capsule ~= nil then
        local hinge = require('core/lib/hinge.lua');
        hinge({
            object_a = red_end_box,
            object_b = final_capsule,
            point = red_end_pos - direction * (input.radius * 1.1),
            size = 0.3,
            sound = false,
            color = Color:rgba(1, 1, 1, 0),
        });
    else
        -- If no middle segments, connect red start box to red end box
        local hinge = require('core/lib/hinge.lua');
        hinge({
            object_a = red_end_box,
            object_b = red_start_box,
            point = red_end_pos - direction * (input.radius * 0.5),
            size = 0.3,
            sound = false,
            color = Color:rgba(1, 1, 1, 0),
        });
    end;
    
    
    -- Bolt end terminal to red box
    bolt({
        object_a = end_terminal,
        object_b = red_end_box,
        point = red_end_pos + direction * (input.radius * 0.5),
        size = input.radius * 6,
        color = Color:rgba(1,1,1,0),
    });
    
    if end_objs and #end_objs > 0 then
        table.sort(end_objs, function(a, b)
            return a:get_z_index() > b:get_z_index()
        end);
        
        local hinge = require('core/lib/hinge.lua');
        if end_objs[1] ~= nil then
            hinge({
                object_a = end_terminal,
                object_b = end_objs[1],
                point = input.end_point,
                size = 0.3,
            });
        end;
    end;
end;
                end;
                
                -- Play completion sound
                Scene:add_audio({
                    asset = require('core/assets/sounds/shape_stop.wav'),
                    position = input.end_point,
                    volume = 0.1,
                });
            ]],
            callback = function(output)
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