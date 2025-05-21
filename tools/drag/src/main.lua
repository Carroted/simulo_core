local spring = nil;
local cursor = "default"; -- What to set the cursor to each update
local overlay = nil;
local start = nil; -- track click start point for select if we dont move

function get_line_color()
    local color = Color:hex(0xffffff);
    if spring == nil then
        color.a = 0.5;
    end;
    return color;
end;

local point_a = vec2(0, 0);
local last_point = self:pointer_pos();

function on_update()
    -- Here we call our functions (on_pointer_down, on_pointer_up, on_pointer_move)

    local point = self:pointer_pos();
    if (point - last_point):magnitude() > 0.02 then
        if overlay ~= nil then
            overlay:set_line({
                points = {point_a, self:pointer_pos()},
                color = get_line_color(),
            });
        end;
    end;
    last_point = point;

    if self:pointer_just_pressed() then
        on_pointer_down(point);
    end;
    if self:pointer_just_released() then
        on_pointer_up(point);
    end;

    local point = self:pointer_pos();

    if (spring == nil) and (not self:pointer_pressed()) then
        -- Send Lua for the host to run
        RemoteScene:run({

            input = point,

            -- The code in this string is ran on the server.
            -- It has the above `input` as a variable.

            code = [[
                -- Here are objects the cursor is over

                local hover_objects = Scene:get_objects_in_circle({
                    position = input,
                    radius = 0,
                });

                local dynamic_objects = {};
                for _, obj in ipairs(hover_objects) do
                    if obj:get_body_type() == BodyType.Dynamic then
                        table.insert(dynamic_objects, obj);
                    end;
                end;

                return #dynamic_objects > 0;
            ]],

            unreliable = true, -- This is something we are sending nonstop, and so we need it to go faster.

            -- This function is called when the host sent back result of our code.
            -- The `output` parameter will be whatever we `return`ed in the above Lua.

            callback = function(output)
                -- Callback can be called some time later because of networking delays, so we check again if pointer pressed

                if not self:pointer_pressed() then
                    -- If we had any objects below the cursor
                    if output then
                        cursor = "grab"; -- Hand opened, showing we can grab but aren't currently doing it
                    else
                        cursor = "default";
                    end;
                else
                    cursor = "default";
                end;
            end,

        });
    end;

    if spring ~= nil then
        RemoteScene:run({
            input = {
                pointer_pos = point,
                spring = spring,
            },
            -- Spring is nil if destroyed
            code = [[
                if input.spring == nil then return nil; end;

                input.spring:set_local_anchor_b(input.pointer_pos);
                return input.spring:get_world_anchor_a();
            ]],
            unreliable = true,
            callback = function(output)
                if output == nil then return; end;

                point_a = output;

                if overlay ~= nil then
                    overlay:set_line({
                        points = {point_a, self:pointer_pos()},
                        color = get_line_color(),
                    });
                end;
            end,
        });
    end;

    self:set_cursor(cursor);
end;

-- Called when user starts holding leftclick
function on_pointer_down(point)

    start = point;

    -- If we don't have an existing spring, add a new one
    if spring == nil then
        overlay = Overlays:add();
        point_a = point;
        
        -- Send Lua for the host to run
        RemoteScene:run({

            input = {
                point = point,
                strength = self:get_property("strength").value,
                damping = self:get_property("damping").value,
                scale_strength_with_mass = self:get_property("scale_strength_with_mass").value,
            },

            code = [[
                local spring = nil;

                -- Here are objects the cursor is over

                local hover_objects = Scene:get_objects_in_circle({
                    position = input.point,
                    radius = 0,
                });

                local dynamic_objects = {};
                for _, obj in ipairs(hover_objects) do
                    if obj:get_body_type() == BodyType.Dynamic then
                        table.insert(dynamic_objects, obj);
                    end;
                end;

                table.sort(dynamic_objects, function(a, b)
                    return a:get_z_index() > b:get_z_index()
                end);

                if #dynamic_objects > 0 then
                    local strength = input.strength;
                    if input.scale_strength_with_mass then
                        strength *= dynamic_objects[1]:get_mass();
                    end;

                    spring = Scene:add_spring({
                        object_a = dynamic_objects[1],
                        local_anchor_a = dynamic_objects[1]:get_local_point(input.point),
                        local_anchor_b = input.point,
                        stiffness = strength,
                        damping = input.damping,
                    });
                end;

                return spring;
            ]],

            unreliable = false, -- Makes sure this gets delivered, but is slower.

            callback = function(output)
                -- If we created a spring
                if output then
                    spring = output; -- Store spring, we will move it with cursor and destroy it when release leftclick
                    cursor = "grabbing"; -- Closed hand
                    if overlay == nil then
                        overlay = Overlays:add();
                        point_a = point;
                    end;
                else
                    if overlay ~= nil then
                        overlay:destroy();
                        overlay = nil;
                    end;
                end;
            end,

        });

    end;

end;

function toggle_value(t, value)
    -- check if value exists in table
    for i, v in pairs(t) do
        if v == value then
            table.remove(t, i); -- remove the value if found
            return;
        end;
    end;
    -- value not found, add it
    table.insert(t, value);
end;

function on_pointer_up(point)
    cursor = "default";

    if spring ~= nil then
        RemoteScene:run({
            input = {
                spring = spring,
            },
            unreliable = false, -- needs to be destroyed for Real
            code = [[
                input.spring:destroy();
            ]],
        });

        spring = nil;
        overlay:destroy();
        overlay = nil;
    end;

    if start ~= nil then
        if (start - point):magnitude() < 0.01 then -- our pointer is at almost same spot as start
            -- we will now select
            local shift = self:key_pressed("ShiftLeft");

            RemoteScene:run({
                input = point,
                code = [[
                    local objs = Scene:get_objects_in_circle({
                        position = input,
                        radius = 0,
                    });

                    local atchs = Scene:get_attachments_in_circle({
                        position = input,
                        radius = 0.1 * 0.3,
                    });

                    -- put them all in one table
                    local all = {};
                    for _, obj in ipairs(objs) do
                        table.insert(all, obj);
                    end;
                    for _, atch in ipairs(atchs) do
                        table.insert(all, atch);
                    end;

                    -- sort by :get_z_index
                    table.sort(all, function(a, b)
                        return a:get_z_index() > b:get_z_index()
                    end);

                    return all[1];
                ]],
                unreliable = false, -- Makes sure this gets delivered, but is slower.
                callback = function(output)
                    if output then
                        if shift then
                            if output:get_type() == "attachment" then
                                local sel = self:get_selected_attachments();
                                toggle_value(sel, output);
                                self:set_selected_attachments(sel);
                            else
                                local sel = self:get_selected_objects();
                                toggle_value(sel, output);
                                self:set_selected_objects(sel);
                            end;
                        else
                            if output:get_type() == "attachment" then
                                self:set_selected_attachments({output});
                                self:set_selected_objects({});
                            else
                                self:set_selected_objects({output});
                                self:set_selected_attachments({});
                            end;
                        end;
                    else
                        if not shift then
                            self:set_selected_attachments({});
                            self:set_selected_objects({});
                        end;
                    end;
                end,
            });
        end;
    end;

    start = nil;
end;
