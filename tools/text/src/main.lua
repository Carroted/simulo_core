function on_update()
    if self:pointer_just_pressed() then
        on_pointer_down(self:pointer_pos());
    end;
end;

function on_pointer_down(point)
    print("Pointer down at " .. point.x .. ", " .. point.y);
    RemoteScene:run({
        input = { point = self:snap_if_preferred(point), text = self:get_property("text").value },
        code = [[
            local objs = Scene:get_objects_in_circle({
                position = input.point,
                radius = 0,
            });

            table.sort(objs, function(a, b)
                return a:get_z_index() > b:get_z_index()
            end);

            local pos = input.point;
            local angle = 0;
            if objs[1] ~= nil then
                pos = objs[1]:get_local_point(input.point);
                angle = -objs[1]:get_angle();
            end;

            Scene:add_attachment({
                name = "Text",
                component = {
                    name = "Text",
                    version = "0.1.0",
                    id = "core/text",
                    icon = require("core/tools/text/icon.png"),
                    code = [==[
                        function on_event(id, data)
                            if id == "property_changed" then
                                local text = self:get_property("text").value;
                                local size = self:get_property("size").value;
                                local resolution = self:get_property("resolution").value;
                                local color = self:get_property("color").value;

                                local texts = self:get_texts();
                                texts[1].content = text;
                                texts[1].font_size = size;
                                texts[1].font_resolution = resolution;
                                texts[1].color = color;

                                self:set_texts(texts);
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
                            id = "text",
                            name = "Text",
                            input_type = "text",
                            default_value = input.text,
                            multi_line = true,
                        },
                        {
                            id = "size",
                            name = "Font Size",
                            input_type = "slider",
                            default_value = 0.2,
                            min_value = 0.1,
                            max_value = 3,
                        },
                        {
                            id = "resolution",
                            name = "Font Resolution",
                            input_type = "slider",
                            default_value = 200,
                            min_value = 1,
                            max_value = 1000,
                        },
                    },
                },
                parent = objs[1],
                local_position = pos,
                local_angle = angle,
                texts = {
                    { content = input.text, color = 0xffffff, font_family = "this doest matter", font_size = 0.2, font_resolution = 200 }
                },
                collider = { shape_type = "box", size = vec2(1, 1), }
            });

            Scene:push_undo();
        ]]
    })
end;
