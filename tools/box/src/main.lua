local start = nil;
local overlay = nil;
local box_color = 0x000000;

local prev_pointer_pos = vec2(0, 0);
local prev_fixed_pointer_pos = vec2(0, 0);
local last_sound_pos = vec2(0, 0);
local accumulated_move = vec2(0, 0);
local last_grid_pointer_pos = self:preferred_pointer_pos();
local audio = nil;
local current_volume = 0;
local should_play_snap = true;
local fixed_update = 0;

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
    accumulated_move = vec2(0, 0);
    prev_fixed_pointer_pos = self:pointer_pos();
    print("Pointer down at " .. point.x .. ", " .. point.y);
    start = point;
    -- random rgb color
    local r = math.random(0x50, 0xff);
    local g = math.random(0x50, 0xff);
    local b = math.random(0x50, 0xff);
    box_color = Color:rgb(r / 0xff, g / 0xff, b / 0xff);

    if overlay == nil then
        overlay = Overlays:add();
    end;

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
                volume = 0,
                pitch = 1,
                looping = true,
            });
        ]],
        callback = function(output)
            audio = output;
        end,
    });

    last_sound_pos = point;
    audio = nil;
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
        local square = self:key_pressed("ShiftLeft");

        local color = box_color:clone();
        color.a = 30.0 / 255.0;

        if square then
            local diff = end_point - start_point;

            local size = math.max(math.abs(diff.x), math.abs(diff.y));
            local pos = start_point + vec2(size, size);
            if diff.x < 0 then
                pos.x = start_point.x - size;
            end;
            if diff.y < 0 then
                pos.y = start_point.y - size;
            end;
            end_point = pos;
        end

        overlay:set_rect({
            point_a = start_point,
            point_b = end_point,
            color = box_color,
            fill = color,
        });
    end;

    last_grid_pointer_pos = self:preferred_pointer_pos();
    
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

function on_pointer_up(point)
    print("Pointer up! at", point);

    local square = self:key_pressed("ShiftLeft");
    local start_point = self:snap_if_preferred(start);
    local end_point = self:snap_if_preferred(point);
    local color = box_color;

    if square then
        local diff = end_point - start_point;

        local size = math.max(math.abs(diff.x), math.abs(diff.y));
        local pos = start_point + vec2(size, size);
        if diff.x < 0 then
            pos.x = start_point.x - size;
        end;
        if diff.y < 0 then
            pos.y = start_point.y - size;
        end;
        end_point = pos;
    end;

    local width = math.abs(end_point.x - start_point.x);
    local height = math.abs(end_point.y - start_point.y);

    local size = vec2(width, height);
    local pos = vec2((end_point.x + start_point.x) / 2, (end_point.y + start_point.y) / 2);


    local fill = box_color:clone();
    fill.a = 30.0 / 255.0;

    overlay:set_rect({
        point_a = start_point,
        point_b = end_point,
        fill = fill,
    });

    if size.x > 0 and size.y > 0 then
        RemoteScene:run({
            input = {
                size = size,
                pos = pos,
                color = color,
                audio = audio,
            },
            code = [[
                if input.audio ~= nil then input.audio:destroy(); end;

                Scene:add_box({
                    position = input.pos,
                    size = input.size,
                    body_type = BodyType.Dynamic,
                    color = input.color,
                });

                Scene:push_undo();

                Scene:add_audio({
                    asset = require('core/assets/sounds/shape_stop.wav'),
                    position = input.pos,
                    volume = 0.1
                });
            ]],
            callback = function(output)
                if start == nil then
                    overlay:destroy();
                    overlay = nil;
                end;
            end,
        });
    else
        RemoteScene:run({
            input = {
                pos = pos,
                audio = audio,
            },
            code = [[
                if input.audio ~= nil then input.audio:destroy(); end;

                Scene:add_audio({
                    asset = require('core/assets/sounds/shape_stop.wav'),
                    position = input.pos,
                    volume = 0.1,
                    pitch = 0.6,
                });
            ]],
            callback = function(output)
                if start == nil then
                    overlay:destroy();
                    overlay = nil;
                end;
            end,
        });
    end;

    audio = nil;
    start = nil;
end;
