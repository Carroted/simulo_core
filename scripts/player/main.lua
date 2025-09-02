local player = require("core/lib/player.lua");
Scene:reset();
Scene:set_gravity(vec2(0,-10)); -- gravity in m/s^2
Scene:add_box({
    position = vec2(-5, -10),
    size = vec2(1, 1),
    color = Color:hsva(0, 0, 0.5, 1),
});
local slope_height = 5;
Scene:add_circle({
    position = vec2(15, -8+(slope_height/2)),
    radius = slope_height/2,
    color = Color:hsva(120, 0.5, 0.5, 1),
    body_type = BodyType.Static,
});
Scene:add_capsule({
    position = vec2(10, -8),
    radius = 0.2, -- meters
    local_point_a = vec2(-5, -0.2),
    local_point_b = vec2(5, slope_height + 0.2),
    body_type = BodyType.Static,
    color = Color:rgb(1, 0.1, 0.1), -- red
    friction = 1,
});

-- raft
local raft = Scene:add_capsule({
    position = vec2(60, -9.8),
    radius = 0.2, -- meters
    local_point_a = vec2(-5, 0),
    local_point_b = vec2(5, 0),
    body_type = BodyType.Dynamic,
    color = Color:hsva(30, 0.5, 0.5, 1), -- orange

})
local raft_component = Scene:add_component_def({
        name = "Player",
    id = "@amytimed/test/player",
    version = "0.2.0",
    code = "local a = 0; function on_step() self:set_linear_velocity(vec2(-(6+a), 0)); end",
})
raft:add_component({hash = raft_component})


player({position = vec2(60,-8)});


-- Generate a variety of platforms to the left for platforming
local platform_count = 20;
local extra_extension = 0
for i = 1, platform_count do
    local x = -5 - (i * 2) - extra_extension;
    local y = -10 + (math.random() * 2) + i*0.8;
    local width = 1 + (math.random() * 0.1 * math.sqrt(i));
    extra_extension = extra_extension + width
    Scene:add_box({
        position = vec2(x, y),
        size = vec2(width, 0.2),
        color = Color:hsva(math.random(0, 360), 0.5, 0.5, 1),
        body_type = BodyType.Static,
    });
end

-- Generate platforms to the right for jumping over
local platform_count = 20;
for i = 1, platform_count do
    local x = 5 + (i * 8);
    local y = -9.5 + (math.random() * 1);
    local width = 1 + (math.random() * 0.1 * math.sqrt(i));
    Scene:add_box({
        position = vec2(x, y),
        size = vec2(width, 0.2),
        color = Color:hsva(math.random(0, 360), 0.5, 0.5, 1),
        body_type = BodyType.Static,
    });
end
