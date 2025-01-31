local start = nil;
local overlay = nil;
local box_color = 0x000000;

local prev_pointer_pos = vec2(0, 0);

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
end;

function on_pointer_move(point)
    if start then
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
            },
            code = [[
                Scene:add_box({
                    position = input.pos,
                    size = input.size,
                    body_type = BodyType.Dynamic,
                    color = input.color,
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

    start = nil;
end;