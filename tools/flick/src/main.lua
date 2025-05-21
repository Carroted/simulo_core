local overlay = nil;          -- For visualizing the line
local dragging = nil;         -- The object being dragged
local drag_local_point = nil; -- Local point on the object where dragging started
local cursor = "default";     -- What to set the cursor to each update
local point_a = vec2(0, 0);   -- Start point of the line (object's position)
local last_point = vec2(0, 0);-- Last pointer position

function get_line_color()
    local color = Color:hex(0xffffff); -- White line
    if dragging == nil then
        color.a = 0.5; -- Semi-transparent when not dragging
    end;
    return color;
end;

function on_update()
    local point = self:pointer_pos();
    
    -- Update line when mouse moves
    if dragging ~= nil and (point - last_point):magnitude() > 0.02 then
        if overlay ~= nil then
            overlay:set_line({
                points = {point_a, point},
                color = get_line_color(),
            });
        end;
    end;
    last_point = point;

    -- Handle pointer events
    if self:pointer_just_pressed() then
        on_pointer_down(point);
    end;
    if self:pointer_just_released() then
        on_pointer_up(point);
    end;

    -- Set cursor style when hovering over objects
    if (dragging == nil) and (not self:pointer_pressed()) then
        RemoteScene:run({
            input = point,
            code = [[
                local hover_objects = Scene:get_objects_in_circle({
                    position = input,
                    radius = 0,
                });
                return #hover_objects > 0;
            ]],
            unreliable = true,
            callback = function(output)
                if not self:pointer_pressed() then
                    if output then
                        cursor = "grab"; -- Hand opened, showing we can grab
                    else
                        cursor = "default";
                    end;
                else
                    cursor = "default";
                end;
            end,
        });
    end;

    -- Update object position if dragging
    if dragging ~= nil then
        RemoteScene:run({
            input = {
                pointer_pos = point,
                dragging = dragging,
                drag_local_point = drag_local_point,
            },
            code = [[
                if input.dragging == nil then return nil; end;
                return input.dragging:get_world_point(input.drag_local_point);
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

function on_pointer_down(point)
    -- If we're not already dragging something
    if dragging == nil then
        overlay = Overlays:add();
        point_a = point;
        
        RemoteScene:run({
            input = {
                point = point,
            },
            code = [[
                local hover_objects = Scene:get_objects_in_circle({
                    position = input.point,
                    radius = 0,
                });

                table.sort(hover_objects, function(a, b)
                    return a:get_z_index() > b:get_z_index()
                end);

                if #hover_objects > 0 then
                    local obj = hover_objects[1];
                    local drag_local_point = obj:get_local_point(input.point);
                    return {
                        success = true,
                        dragging = obj,
                        drag_local_point = drag_local_point,
                    };
                else
                    return { success = false };
                end;
            ]],
            unreliable = false,
            callback = function(output)
                if output and output.success then
                    dragging = output.dragging;
                    drag_local_point = output.drag_local_point;
                    cursor = "grabbing"; -- Closed hand
                    if overlay == nil then
                        overlay = Overlays:add();
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

function on_pointer_up(point)
    cursor = "default";

    if dragging ~= nil then
        RemoteScene:run({
            input = {
                release_point = point,
                dragging = dragging,
                drag_local_point = drag_local_point,
                strength = self:get_property("strength").value,
                scale_strength_with_mass = self:get_property("scale_strength_with_mass").value,
            },
            code = [[
                if input.dragging ~= nil then
                    local strength = input.strength;
                    if input.scale_strength_with_mass then
                        strength *= input.dragging:get_mass();
                    end;

                    local world_point = input.dragging:get_world_point(input.drag_local_point);
                    local force_vector = world_point - input.release_point;
                    input.dragging:apply_force(force_vector * strength * 30, world_point);
                end;
            ]],
            unreliable = false,
        });

        dragging = nil;
        drag_local_point = nil;
        if overlay ~= nil then
            overlay:destroy();
            overlay = nil;
        end;
    end;
end;