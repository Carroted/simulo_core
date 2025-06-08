local player = require("core/lib/player.lua");
Scene:reset();
Scene:add_box({
    position = vec2(-5, -10),
    size = vec2(1, 1),
    color = Color:hsva(0, 0, 0.5, 1),
});
local slope_height = 5;
Scene:add_circle({
    position = vec2(15, -10+(slope_height/2)),
    radius = slope_height/2,
    color = Color:hsva(120, 0.5, 0.5, 1),
});
Scene:add_capsule({
    position = vec2(10, -10),
    radius = 0.2, -- meters
    local_point_a = vec2(-5, 0),
    local_point_b = vec2(5, slope_height + 0.2),
    body_type = BodyType.Dynamic, -- doesnt move
    color = Color:rgb(1, 0.1, 0.1), -- red
    friction = 1,
});
player({position = vec2(0,-10)});
