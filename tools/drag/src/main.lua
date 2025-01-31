local spring = nil;
local cursor = "default"; -- What to set the cursor to each update
local overlay = nil;

function get_line_color()
    local color = Color:hex(0xffffff);
    if spring == nil then
        color.a = 0.5;
    end;
    return color;
end;

local point_a = vec2(0, 0);

-- Track last cursor position to know if it moved
local prev_pointer_pos = vec2(0, 0);

function on_update()
    -- Here we call our functions (on_pointer_down, on_pointer_up, on_pointer_move)

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

                return #hover_objects > 0;
            ]],

            reliable = false, -- This is something we are sending nonstop, and so we need it to go faster.

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

    if self:pointer_just_pressed() then
        on_pointer_down(point);
    end;
    if self:pointer_just_released() then
        on_pointer_up(point);
    end;
    if point ~= prev_pointer_pos then
        on_pointer_move(point);
    end;

    prev_pointer_pos = point;

    self:set_cursor(cursor);
end;

-- Called when user starts holding leftclick
function on_pointer_down(point)

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

                if #hover_objects > 0 then
                    local strength = input.strength;
                    if input.scale_strength_with_mass then
                        strength *= hover_objects[1]:get_mass();
                    end;

                    spring = Scene:add_spring({
                        object_a = hover_objects[1],
                        local_anchor_a = hover_objects[1]:get_local_point(input.point),
                        stiffness = strength,
                        damping = input.damping,
                    });
                end;

                return spring;
            ]],

            reliable = true, -- Makes sure this gets delivered, but is slower.

            callback = function(output)
                -- If we created a spring
                if output then
                    spring = output; -- Store spring, we will move it with cursor and destroy it when release leftclick
                    cursor = "grabbing"; -- Closed hand
                    if overlay == nil then
                        overlay = Overlays:add();
                        point_a = point;
                    end;
                end;
            end,

        });

    end;

end;

function on_pointer_move(point)
    if overlay ~= nil then
        overlay:set_line({
            points = {point_a, self:pointer_pos()},
            color = get_line_color(),
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
end;

function on_pointer_up(point)
    cursor = "default";

    if spring ~= nil then
        RemoteScene:run({
            input = {
                spring = spring,
            },
            reliable = true, -- needs to be destroyed for Real
            code = [[
                input.spring:destroy();
            ]],
        });

        spring = nil;
        overlay:destroy();
        overlay = nil;
    end;
end;
