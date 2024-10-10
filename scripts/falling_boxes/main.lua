
-- This is the Simulo Lua scripting environment!
-- https://docs.simulo.org/api/intro

-- This script creates a giant container and puts a bunch of 1x1m boxes in it.

print("Welcome to Simulo!");

-- Reset Simulo scene to default by deleting all objects and restoring the default ground plane

Scene:reset();

local random_colors = false; -- Enable this to get random colors for each box

local ground_size = 40.0;
local grounds = {
    {0.0, 0.0, ground_size, 0.1},
    {-ground_size / 2, ground_size / 2, 0.1, ground_size},
    {ground_size / 2, ground_size / 2, 0.1, ground_size},
};

for i, ground in ipairs(grounds) do
    local box = Scene:add_box({
		position = vec2(ground[1], ground[2]),
		size = vec2(ground[3], ground[4]),
		is_static = true,
		color = 0xb9a1c4
	});
end;

local num = 20;
local num_y = 50;
local rad = 1.0;

local shift = rad * 2.0 + rad;
local center_x = shift * (num / 2);
local center_y = shift / 2.0;

for j = 0, num_y - 1 do
    for i = 0, num - 1 do
        local x = i * shift - center_x;
        local y = j * shift + center_y + 3.0;

        local color = 0xe5d3b9;
        
        if random_colors then
            -- random rgb color
            local r = math.random(0x40, 0xff);
            local g = math.random(0x40, 0xff);
            local b = math.random(0x40, 0xff);

            -- put it together to form single color value, like 0xRRGGBB
            color = r * 0x10000 + g * 0x100 + b;
        end;

        local box = Scene:add_box({
			position = vec2(x / 2, y / 2),
			size = vec2(1, 1),
			is_static = false,
			color = color
		});
    end;
end;