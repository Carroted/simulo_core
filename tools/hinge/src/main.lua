-- State variables to track dragging
local dragging = false;
local initial_point = nil;
local initial_local_point = nil; -- Used for the connection overlay
local initial_object_id = nil;
local original_object_position = nil;
local original_object_angle = nil;  -- Track the original angle
local overlay = nil;
local connection_overlay = nil;
local start_attachment_overlay = nil; -- For the start attachment point
local end_attachment_overlay = nil; -- For the end attachment point
local object_shape = nil;
local object_color = nil;
local object_angle = nil;

local attachment_radius = 0.1 * 0.3 * 2;

function on_update()
    if self:pointer_just_pressed() then
        on_pointer_down(self:pointer_pos());
    elseif self:pointer_just_released() then
        on_pointer_up(self:pointer_pos());
    elseif dragging and self:pointer_pressed() then
        on_pointer_drag(self:pointer_pos());
    end;
end;

function on_pointer_down(point)
    initial_point = point;
    
    RemoteScene:run({
        input = point,
        code = [[
            local objs = Scene:get_objects_in_circle({
                position = input,
                radius = 0,
            });
            
            table.sort(objs, function(a, b)
                return a:get_z_index() > b:get_z_index()
            end);
            
            local result = {
                object_id = nil,
                position = nil,
                shape = nil,
                color = nil,
                angle = nil
            };
            
            if #objs > 0 then
                local obj = objs[1];
                result.object_id = obj.id;
                result.local_point = obj:get_local_point(input);
                result.position = obj:get_position();
                result.shape = obj:get_shape();
                result.color = obj:get_color();
                result.angle = obj:get_angle();
                
                Scene:add_audio({
                    asset = require("core/tools/hinge/assets/up.wav"),
                    position = input,
                    pitch = 1.8 + (-0.1 + (0.1 - -0.1) * math.random()),
                    volume = 0.5,
                });
            end;
            
            return result;
        ]],
        callback = function(output)
            if output and output.object_id then
                initial_object_id = output.object_id;
                initial_local_point = output.local_point;
                original_object_position = output.position;
                original_object_angle = output.angle;  -- Store the original angle
                object_shape = output.shape;
                object_color = output.color;
                object_angle = output.angle;
                
                dragging = true;
                
                -- Create shape overlay if move_object is enabled
                if self:get_property("move_object").value then
                    overlay = Overlays:add();
                    if overlay then
                        update_overlay(original_object_position, original_object_angle);
                    end;
                end;
            end;
        end,
    });
end;

-- Helper function to update the overlay based on object shape and angle
function update_overlay(position, angle)
    if not overlay or not object_shape then
        return;
    end;
    
    -- Set semi-transparent color for ghost object
    local ghost_color;
    if object_color then
        ghost_color = Color:rgba(object_color.r, object_color.g, object_color.b, 0.66);
    else
        ghost_color = Color:rgba(1, 1, 1, 0.66); -- Default to semi-transparent white
    end;
    
    -- Update overlay based on shape type
    if object_shape.shape_type == "box" then
        -- For rectangles, we'll rotate the corners
        local half_width = object_shape.size.x / 2;
        local half_height = object_shape.size.y / 2;
        
        -- Create rotated rectangle corners
        local corners = {
            vec2(-half_width, -half_height):rotate(angle),
            vec2(half_width, -half_height):rotate(angle),
            vec2(half_width, half_height):rotate(angle),
            vec2(-half_width, half_height):rotate(angle)
        };
        
        -- Translate corners to the current position
        local points = {};
        for i, corner in ipairs(corners) do
            points[i] = position + corner;
        end;
        
        -- Use polygon to represent the rotated box
        overlay:set_polygon({
            points = points,
            fill = ghost_color,
            color = object_color,
        });
    elseif object_shape.shape_type == "circle" then
        -- Circles don't need rotation
        overlay:set_circle({
            center = position,
            radius = object_shape.radius,
            fill = ghost_color,
            color = object_color,
        });
    elseif object_shape.shape_type == "polygon" then
        -- Transform the polygon points based on new position and current angle
        local transformed_points = {};
        for i, point in ipairs(object_shape.points) do
            -- Keep the original shape's rotation and add our current rotation
            local rotated_point = point:rotate(angle);
            transformed_points[i] = position + rotated_point;
        end;
        
        overlay:set_polygon({
            points = transformed_points,
            fill = ghost_color,
            color = object_color,
        });
    elseif object_shape.shape_type == "capsule" then
        -- Rotate the capsule endpoints
        local point_a = object_shape.local_point_a:rotate(angle);
        local point_b = object_shape.local_point_b:rotate(angle);
        
        overlay:set_capsule({
            point_a = position + point_a,
            point_b = position + point_b,
            radius = object_shape.radius,
            fill = ghost_color,
            color = object_color,
        });
    end;
end;

function on_pointer_drag(point)
    if not dragging or not initial_object_id or not original_object_position then return; end;
    
    -- Calculate delta from initial point
    local delta = self:snap_if_preferred(point) - self:snap_if_preferred(initial_point);
    
    RemoteScene:run({
        input = {
            local_point = initial_local_point,
            initial_object_id = initial_object_id,
        },
        code = [[
            local obj = Scene:get_object(input.initial_object_id);
            if obj then
                return obj:get_world_point(input.local_point);
            end;
            return input.point; -- Fallback to the pointer position
            ]],
        callback = function(connection_start)
            if connection_start then
                draw_connection(connection_start, point);
            end;
        end,
    });
    
    -- Update the overlay's position if move_object is enabled
    if self:get_property("move_object").value and overlay then
        update_overlay(original_object_position + delta, original_object_angle);
    end;
end;

function draw_connection(connection_start, point)
    if not connection_start or not point then return; end;

    if self:get_property("move_object").value then -- Don't show if attachment won't go there
        if start_attachment_overlay then
            start_attachment_overlay:destroy();
            start_attachment_overlay = nil;
        end;
        start_attachment_overlay = Overlays:add();
        start_attachment_overlay:set_circle({
            center = self:snap_if_preferred(connection_start),
            radius = attachment_radius,
            color = Color:hex(0xFFFFFF),
        });
    end;

    if end_attachment_overlay then
        end_attachment_overlay:destroy();
        end_attachment_overlay = nil;
    end;
    end_attachment_overlay = Overlays:add();
    end_attachment_overlay:set_circle({
            center = point,
            radius = attachment_radius,
            color = Color:hex(0xFFFFFF),
        });

    -- Clean up any existing connection overlay
    if connection_overlay then
        connection_overlay:destroy();
        connection_overlay = nil;
    end;
    -- Add the connection line
    connection_overlay = Overlays:add();
    connection_overlay:set_line({
        points = {self:snap_if_preferred(connection_start), self:snap_if_preferred(point)},
        color = Color:hex(0xFFFFFF)
    });
end;

function on_pointer_up(point)
    if not dragging then return; end;
    
    -- Clean up overlays
    if overlay then
        overlay:destroy();
        overlay = nil;
    end;
    
    if connection_overlay then
        connection_overlay:destroy();
        connection_overlay = nil;
    end;

    if start_attachment_overlay then
        start_attachment_overlay:destroy();
        start_attachment_overlay = nil;
    end;
    if end_attachment_overlay then
        end_attachment_overlay:destroy();
        end_attachment_overlay = nil;
    end;
    
    -- Calculate angle delta (for future use - currently 0)
    local angle_delta = 0;
    
    -- Check if we should move the object
    local should_move_object = self:get_property("move_object").value;
    
    -- Use self:snap_if_preferred to respect grid settings
    local snapped_point = self:snap_if_preferred(point);
    local snapped_initial_point = self:snap_if_preferred(initial_point);
    
    RemoteScene:run({
        input = {
            point = snapped_point,
            initial_object_id = initial_object_id,
            original_position = original_object_position,
            original_angle = original_object_angle,
            angle_delta = angle_delta,
            delta = snapped_point - snapped_initial_point,
            should_move_object = should_move_object,
            motor_enabled = self:get_property("motor_enabled").value,
            add_to_center = self:get_property("add_to_center").value,
        },
        code = [[
            local objs = Scene:get_objects_in_circle({
                position = input.point,
                radius = 0,
            });

            table.sort(objs, function(a, b)
                return a:get_z_index() > b:get_z_index()
            end);
            
            local object_a = Scene:get_object(input.initial_object_id);
            local object_b = nil;
            
            -- Find the second object (not the one we're dragging)
            if #objs > 0 then
                -- Check if we have another object under the pointer
                if object_a and objs[1].id == input.initial_object_id and #objs > 1 then
                    object_b = objs[2];
                elseif object_a and objs[1].id ~= input.initial_object_id then
                    object_b = objs[1];
                end;
            end;
            
            -- Create hinge if we have the first object (object_a)
            -- object_b can be nil, which the API will interpret as connecting to the background
            if object_a then
                -- Only move the object if should_move_object is true
                if input.should_move_object then
                    -- Move the object to its final position before creating the hinge
                    object_a:set_position(input.original_position + input.delta);
                    
                    -- Set the angle (original + any delta)
                    object_a:set_angle(input.original_angle + input.angle_delta);
                end;
                
                local hinge = require('core/lib/hinge.lua');
                local point = input.add_to_center and object_a:get_position() or input.point;
                hinge({
                    object_a = object_a,
                    object_b = object_b, -- Can be nil for background
                    point = point,
                    size = 0.3,
                    motor_enabled = input.motor_enabled,
                    collide_connected = false,
                });

                Scene:push_undo();
            end;
        ]],
    });
    
    -- Reset state
    dragging = false;
    initial_point = nil;
    initial_local_point = nil;
    initial_object_id = nil;
    original_object_position = nil;
    original_object_angle = nil;
    object_shape = nil;
    object_color = nil;
    object_angle = nil;
end;
