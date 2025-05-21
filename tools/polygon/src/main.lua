local points = {};
local overlay = nil;
local polygon_color = 0x000000;
local audio = nil;
local current_volume = 0;
local prev_fixed_pointer_pos = vec2(0, 0);
local accumulated_move = vec2(0, 0);
local last_move_point = nil;

function on_update()
    if self:pointer_just_pressed() then
        on_pointer_down(self:pointer_pos());
    end;
    if self:pointer_just_released() then
        on_pointer_up(self:pointer_pos());
    end;
    
    on_pointer_move(self:pointer_pos());
    
    -- Check for Enter key to complete polygon explicitly
    if self:key_just_pressed("Enter") then
        complete_polygon();
    end;
end;

function get_random_color()
    local r = math.random(0x50, 0xff);
    local g = math.random(0x50, 0xff);
    local b = math.random(0x50, 0xff);
    return r * 0x10000 + g * 0x100 + b;
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

function get_polygon_color()
    return Color:hex(polygon_color);
end;

function get_fill_color()
    local color = get_polygon_color():clone();
    color.a = 30.0 / 255.0;
    return color;
end;

function on_pointer_down(point)
    accumulated_move = vec2(0, 0);
    prev_fixed_pointer_pos = self:pointer_pos();
    
    point = self:snap_if_preferred(point);
    
    -- Create overlay for preview if it doesn't exist
    if overlay == nil then
        overlay = Overlays:add();
    end;
    
    -- First point or click mode
    if #points == 0 or not self:get_property("hold").value then
        -- Generate new random color if starting fresh
        if #points == 0 then
            polygon_color = get_random_color();
        end;
        
        -- Add the point
        table.insert(points, point);
        
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
                    asset = require('core/assets/sounds/grid.wav'),
                    position = input.point,
                    volume = 0.5,
                    pitch = 1.2,
                });
            ]],
            callback = function(output)
                -- No need to store audio for click mode
                if self:get_property("hold").value then
                    audio = output;
                    
                    -- Start shape sound for hold mode
                    RemoteScene:run({
                        input = { point = point },
                        code = [[
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
            end,
        });
    end;
    
    last_move_point = point;
    update_preview();
end;

function on_pointer_move(point)
    if #points > 0 then
        point = self:snap_if_preferred(point);
        
        -- For hold mode, add points as we move far enough
        if self:get_property("hold").value and self:pointer_pressed() then
            if last_move_point and (point - last_move_point):magnitude() > self:get_property("min_distance").value then
                table.insert(points, point);
                last_move_point = point;
                
                -- Play grid sound for new point
                RemoteScene:run({
                    input = { point = point },
                    code = [[
                        Scene:add_audio({
                            asset = require('core/assets/sounds/grid.wav'),
                            position = input.point,
                            volume = 0.5,
                            pitch = 1.2,
                        });
                    ]],
                });
            end;
        end;
        
        update_preview(point);
    end;
end;

function update_preview(current_point)
    if #points > 0 and overlay then
        local preview_points = {};
        -- Copy all confirmed points
        for i, p in ipairs(points) do
            table.insert(preview_points, p);
        end;
        
        -- Add current mouse position as temporary point for preview
        if current_point and (self:get_property("hold").value == false or not self:pointer_pressed()) then
            table.insert(preview_points, current_point);
        end;
        
        -- Need at least 3 points to show a polygon
        if #preview_points >= 3 then
            overlay:set_polygon({
                points = preview_points,
                color = get_polygon_color(),
                fill = get_fill_color()
            });
        end;
    end;
end;

function on_pointer_up(point)
    point = self:snap_if_preferred(point);
    
    -- For hold mode, finalize the polygon on pointer up
    if self:get_property("hold").value then
        if #points >= 3 then
            complete_polygon();
        else
            -- Not enough points, clean up
            points = {};
            if overlay then
                overlay:destroy();
                overlay = nil;
            end;
        end;
        
        -- Clean up audio
        if audio ~= nil then
            RemoteScene:run({
                input = { audio = audio, point = point },
                code = [[
                    if input.audio ~= nil then input.audio:destroy(); end;
                    
                    Scene:add_audio({
                        asset = require('core/assets/sounds/shape_stop.wav'),
                        position = input.point,
                        volume = 0.1,
                    });
                ]],
            });
            audio = nil;
        end;
    elseif not self:get_property("hold").value then
        -- In click mode, just play sound to acknowledge the click
        RemoteScene:run({
            input = { point = point },
            code = [[
                Scene:add_audio({
                    asset = require('core/assets/sounds/grid.wav'),
                    position = input.point,
                    volume = 0.5,
                    pitch = 1.2,
                });
            ]],
        });
    end;
end;

function complete_polygon()
    if #points >= 3 then
        -- Create actual polygon in the scene
        RemoteScene:run({
            input = {
                points = points,
                color = polygon_color,
            },
            code = [[
                local polygon_color = Color:hex(input.color);
                
                -- Calculate center of polygon
                local center = vec2(0, 0);
                for _, point in ipairs(input.points) do
                    center = center + point;
                end;
                center = center / #input.points;
                
                -- Calculate relative points from center
                local relative_points = {};
                for _, point in ipairs(input.points) do
                    table.insert(relative_points, point - center);
                end;
                
                -- Create the actual polygon
                Scene:add_polygon({
                    position = center,
                    points = relative_points,
                    body_type = BodyType.Dynamic,
                    color = polygon_color,
                });
                
                Scene:push_undo();
                
                -- Play completion sound
                Scene:add_audio({
                    asset = require('core/assets/sounds/shape_stop.wav'),
                    position = center,
                    volume = 0.1,
                });
            ]],
            callback = function()
                -- Reset for new polygon
                points = {};
                if overlay then
                    overlay:destroy();
                    overlay = nil;
                end;
            end,
        });
    end;
end;
