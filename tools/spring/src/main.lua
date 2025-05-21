local start = nil;
local overlay = nil;

-- sounds
local audio = nil;
local current_volume = 0;
local prev_fixed_pointer_pos = vec2(0, 0);
local accumulated_move = vec2(0, 0);

local should_play_snap = true;
local fixed_update = 0;
local last_grid_pointer_pos = self:preferred_pointer_pos();

function on_update()
    if self:pointer_just_pressed() then
        on_pointer_down(self:pointer_pos());
    end;
    if self:pointer_just_released() then
        on_pointer_up(self:pointer_pos());
    end;
    
    on_pointer_move(self:pointer_pos());
end;

function lerp(a, b, t)
    return a + (b - a) * t
end;

function on_fixed_update()
    accumulated_move += self:pointer_pos() - prev_fixed_pointer_pos;
    current_volume = lerp(current_volume, math.min(0.04, math.max(0, accumulated_move:magnitude() * 10)), 0.5);

    if audio ~= nil then
        RemoteScene:run({
            input = { audio = audio, pitch = current_volume },
            code = [[
                input.audio:set_volume(input.pitch);
            ]],
        });
    end;

    accumulated_move = vec2(0, 0);
    prev_fixed_pointer_pos = self:pointer_pos();

    fixed_update += 1;

    if fixed_update % 4 == 0 then
        should_play_snap = true;
    end;
end;

function on_pointer_down(point)
    accumulated_move = vec2(0, 0);
    prev_fixed_pointer_pos = self:pointer_pos();

    print("Pointer down at " .. point.x .. ", " .. point.y);
    start = point;
    
    -- Create overlay for preview
    if overlay == nil then
        overlay = Overlays:add();
    end;
    
    -- Play start sound
    RemoteScene:run({
        input = { point = point, old_audio = audio },
        code = [[
            if input.old_audio ~= nil then input.old_audio:destroy(); end;

            Scene:add_audio({
                asset = require('core/assets/sounds/shape_start.wav'),
                position = input.point,
                volume = 0.1,
            });

            return Scene:add_audio({
                asset = require('core/assets/sounds/shape.wav'),
                position = input.point,
                volume = 0.05,
                pitch = 1,
                looping = true,
            });
        ]],
        callback = function(output)
            audio = output;
        end,
    });
end;

function on_pointer_move(point)
    if start then
        if should_play_snap and self:grid_enabled() and ((self:grid_pointer_pos() - last_grid_pointer_pos):magnitude() > 0.0) then
            RemoteScene:run({
                input = point,
                code = [[
                    Scene:add_audio({
                        asset = require('core/assets/sounds/grid.wav'),
                        position = input,
                        volume = 0.7,
                        pitch = 1.2,
                    });
                ]],
            });
            should_play_snap = false;
        end;

        local start_point = self:snap_if_preferred(start);
        local end_point = self:snap_if_preferred(point);
        
        -- Update overlay preview
        overlay:set_capsule({
            point_a = start_point,
            point_b = end_point,
            radius = 0.05,
            color = 0xffffff,
        });
    end;

    last_grid_pointer_pos = self:preferred_pointer_pos();
end;

function on_pointer_up(point)
    print("Pointer up!");
    
    if start ~= nil then
        local start_point = self:snap_if_preferred(start);
        local end_point = self:snap_if_preferred(point);
        
        -- Create final segment
        RemoteScene:run({
            input = {
                start_point = start_point,
                end_point = end_point,
                color = 0xffffff,
                audio = audio,
                radius = 0.05,
            },
            code = [[
                -- Stop the looping audio
                if input.audio ~= nil then 
                    input.audio:destroy();
                end;
                
                local capsule_color = Color:hex(input.color);
                local new_capsule = nil;
                
                local start_objs = Scene:get_objects_in_circle({
                    position = input.start_point,
                    radius = 0,
                });

                table.sort(start_objs, function(a, b)
                    return a:get_z_index() > b:get_z_index()
                end);

                local end_objs = Scene:get_objects_in_circle({
                    position = input.end_point,
                    radius = 0,
                });

                table.sort(end_objs, function(a, b)
                    return a:get_z_index() > b:get_z_index()
                end);

                if (start_objs[1] ~= nil) or (end_objs[1] ~= nil) then
                    local a = start_objs[1];
                    local b = end_objs[1];
                    local anchor_a = input.start_point;
                    local anchor_b = input.end_point;
                    local point = nil;
                    local attachment_parent = nil;
                    if a and (not b) then
                        anchor_a = a:get_local_point(input.start_point);
                        anchor_b = input.end_point;
                        attachment_parent = a;
                        point = input.start_point;
                    elseif b and (not a) then
                        a,b = b,a;
                        anchor_a = a:get_local_point(input.end_point);
                        anchor_b = input.start_point;
                        attachment_parent = a;
                        point = input.end_point;
                    else
                        anchor_a = a:get_local_point(input.start_point);
                        anchor_b = b:get_local_point(input.end_point);
                        attachment_parent = a;
                        point = input.start_point;
                    end;

                    local atch = Scene:add_attachment({
                        name = "Spring",
                        component = {
                            name = "Spring",
                            version = "0.1.0",
                            id = "core/spring",
                            code = [==[
                                local spring = nil;

                                function on_event(id, data)
                                    if id == "core/spring/init" then
                                        spring = data;
                                    elseif id == "property_changed" then
                                        spring:set_damping(self:get_property("damping").value);
                                        spring:set_stiffness(self:get_property("stiffness").value);
                                        spring:set_rest_length(self:get_property("rest_length").value);
                                        
                                        if data == "color" then
                                            local imgs = self:get_images();
                                            for i = 1, #imgs do
                                                imgs[i].color = self:get_property("color").value;
                                            end;
                                            self:set_images(imgs);
                                        end;
                                    end;
                                end;

                                function on_start(data)
                                    if data ~= nil then
                                        if data.spring ~= nil then
                                            spring = data.spring;
                                        end;
                                    end;
                                end;

                                function on_save()
                                    return { spring = spring };
                                end;

                                function on_update()
                                    if spring:is_destroyed() then self:destroy(); end;

                                    local imgs = self:get_images();
                                    -- we will set `offset`, `scale` and `angle`, so the image is between spring:get_world_anchor_a() and spring:get_world_anchor_b()
                                    local anchor_a = vec2(0, 0);
                                    local anchor_b = self:get_local_point(spring:get_world_anchor_b());
                                    local offset = (anchor_b - anchor_a) / 2;
                                    local scale = (anchor_b - anchor_a):magnitude() / 512;
                                    local angle = math.atan2(offset.y, offset.x);
                                    
                                    imgs[1].offset = offset;
                                    imgs[1].scale = vec2(scale, 0.0007 * 0.8);
                                    imgs[1].angle = angle;

                                    self:set_images(imgs);
                                end;

                                function on_step()
                                    local breakable = self:get_property("breakable").value;
                                    if breakable then
                                        local break_force = self:get_property("break_force").value;
                                        if spring:get_force():magnitude() > break_force then
                                            spring:destroy();
                                            self:destroy();
                                        end;
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
                                    id = "stiffness",
                                    name = "Stiffness",
                                    input_type = "slider",
                                    default_value = 20,
                                    min_value = 1,
                                    max_value = 100,
                                },
                                {
                                    id = "damping",
                                    name = "Damping",
                                    input_type = "slider",
                                    default_value = 0.1,
                                    min_value = 0,
                                    max_value = 1,
                                },
                                {
                                    id = "rest_length",
                                    name = "Rest Length",
                                    input_type = "slider",
                                    default_value = (input.end_point - input.start_point):magnitude(),
                                    min_value = 0,
                                    max_value = 100,
                                },
                                {
                                    id = "breakable",
                                    name = "Breakable",
                                    input_type = "toggle",
                                    default_value = false,
                                },
                                {
                                    id = "break_force",
                                    name = "Break Force",
                                    input_type = "slider",
                                    default_value = 50,
                                    min_value = 1,
                                    max_value = 1000,
                                },
                            }
                        },
                        parent = attachment_parent,
                        local_position = attachment_parent:get_local_point(point),
                        local_angle = 0,
                        images = {
                            {
                                texture = require("core/tools/spring/assets/spring.png"),
                                scale = vec2(0.0007, 0.0007) * 0.3,
                                color = 0xffffff,
                            },
                        },
                        collider = { shape_type = "circle", radius = 0.1 * 0.3 }
                    });
                    
                    local spring = Scene:add_spring({
                        object_a = a,
                        object_b = b,
                        local_anchor_a = anchor_a,
                        local_anchor_b = anchor_b,
                        attachment = atch,
                        stiffness = 20,
                        damping = 0.1,
                        rest_length = (input.end_point - input.start_point):magnitude(),
                    });

                    atch:send_event("core/spring/init", spring);
                end;

                Scene:push_undo();
                
                -- Play completion sound
                Scene:add_audio({
                    asset = require('core/assets/sounds/shape_stop.wav'),
                    position = input.end_point,
                    volume = 0.1,
                });
            ]],
            callback = function(output)
                audio = nil;
                
                if overlay ~= nil then
                    overlay:destroy();
                    overlay = nil;
                end;
            end,
        });
    end;

    start = nil;
end;