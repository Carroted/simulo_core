local audio = require('core/assets/sounds/gun.ogg');

local hash = Scene:add_component_def({
    id = "wanda",
    name = "Bullet",
    version = "0.1.0",
    code = [[
        local audio = require('core/assets/sounds/collision.wav');
        function on_hit(data)
            data.other:send_event("activate", {
                power = 100,
            });
            Scene:add_audio({
                position = self:get_position(),
                asset = audio,
                volume = 0.8,
            });
            self:destroy();
        end;
    ]],
});

function on_event(id, data)
    if id == "activate" then
        Scene:add_circle({
            position = self:get_world_point(vec2(0.3, 0)),
            radius = 0.05,
            linear_velocity = self:get_right_direction() * 10,
            density = 10,
        }):add_component({ hash = hash });
        Scene:add_audio({
            position = self:get_world_point(vec2(0.3, 0)),
            asset = audio,
            volume = 0.15,
        });
        return {
            recoil = 0.5,
        };
    end;
end;