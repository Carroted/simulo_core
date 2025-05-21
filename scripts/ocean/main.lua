local hash = require('core/components/buoyancy');

Scene:reset():destroy();
--Scene:set_background_color(0xabc2d9);
Scene:set_background_color(0x90b0cf);
Scene:set_background_color_secondary(0xc3d2e1);

local c = Color:hex(0x285f9a);
c.a = 0.85;

--local c = Color:hex(0x87b1ff);
--c.a = 0.3;

Scene:add_box({
    name = "Ocean",
    color = c,
    size = vec2(1000, 100),
    position = vec2(0, -60),
    body_type = BodyType.Static,
    is_sensor = true,
    z_index = 100000,
    density = 0.5,
}):add_component({ hash = hash });

local simulon = require('core/lib/simulon.lua');

simulon({
    color = 0x8b975e,
    position = vec2(-0.8, -9),
});

simulon({
    color = 0x906ead,
    position = vec2(0.8, -9),
});

--Scene:get_host():set_camera_position(vec2(0, -8.93));
--Scene:get_host():set_camera_zoom(0.006)