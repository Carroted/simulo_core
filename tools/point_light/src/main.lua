function on_update()
    if self:pointer_just_pressed() then
        on_pointer_down(self:pointer_pos());
    end;
end;

function on_pointer_down(point)
    print("Pointer down at " .. point.x .. ", " .. point.y);
    RemoteScene:run({
        input = self:snap_if_preferred(point),
        code = [[
            local objs = Scene:get_objects_in_circle({
                position = input,
                radius = 0,
            });

            table.sort(objs, function(a, b)
                return a:get_z_index() > b:get_z_index()
            end);

            local pos = input;
            local angle = 0;
            if objs[1] ~= nil then
                pos = objs[1]:get_local_point(input);
                angle = -objs[1]:get_angle();
            end;

            Scene:add_audio({
                asset = require('core/tools/point_light/assets/light.wav'),
                position = input,
                pitch = 1 + (-0.02 + (0.02 - -0.02) * math.random()),
                volume = 0.6,
            });

            Scene:add_attachment({
                name = "Point Light",
                component = {
                    name = "Point Light",
                    version = "0.1.0",
                    id = "core/point_light",
                    code = [==[
                        function on_event(id, data)
                            if id == "property_changed" then
                                local intensity = self:get_property("intensity").value;
                                local radius = self:get_property("radius").value;
                                local color = self:get_property("color").value;

                                local lights = self:get_lights();
                                lights[1].intensity = intensity;
                                lights[1].radius = radius;
                                lights[1].color = color;

                                self:set_lights(lights);

                                local imgs = self:get_images();
                                local h,s,v = color:get_hsv();
                                s = s * 0.5;
                                local new_color = Color:hsva(h,s,v,color.a);
                                imgs[1].color = new_color;
                                self:set_images(imgs);
                            end;
                        end;
                    ]==],
                    properties = {
                        {
                            id = "color",
                            name = "Color",
                            input_type = "color",
                            default_value = 0xffffff,
                        },
                        {
                            id = "intensity",
                            name = "Intensity",
                            input_type = "slider",
                            default_value = 1.2,
                            min_value = 0,
                            max_value = 10,
                        },
                        {
                            id = "radius",
                            name = "Radius",
                            input_type = "slider",
                            default_value = 5 * 0.6,
                            min_value = 0,
                            max_value = 100,
                        },
                    },
                },
                parent = objs[1],
                local_position = pos,
                local_angle = angle,
                images = {
                    {
                        texture = require('core/assets/textures/point_light.png'),

                        -- these have defaults, but we can specify
                        scale = vec2(0.0007, 0.0007) * 0.6,
                        color = Color:hex(0xffffff),
                    },
                },
                lights = {
                    {
                        color = 0xffffff,
                        intensity = 1.2,
                        radius = 5 * 0.6,
                    },
                },
                collider = { shape_type = "circle", radius = 0.1 * 0.6, }
            });

            Scene:push_undo();
        ]]
    })
end;
