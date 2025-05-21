local hinge = require('core/lib/hinge.lua');
local bolt = require('core/lib/bolt.lua');
local conductor = require('core/components/conductor');

local biotics = require('core/components/biotics');

local function simulon(tbl)
    local position = tbl.position or vec2(0, 0);
    local color = tbl.color or Color.SIMULO_GREEN;
    local density = tbl.density or 1;
    local size = (tbl.size or 1) / 2.0;

    local y = (0.7 / 2.0) * size;
    
    -- Simulon Body Part 1 (UNCHANGED)
    local simulon_body = Scene:add_circle({
        position = position + vec2(0, y),
        radius = size / 2,
        body_type = BodyType.Dynamic,
        color = color or Color:rgb(0.0, 1.0, 0.0),
        name = "Simulon Body Part 1",
    });

    local c = simulon_body:add_component({ hash = biotics });
    local p = c:get_property("natural_color");
    p.value = color;
    c:set_property("natural_color", p);
    simulon_body:add_component({ hash = conductor });
    
    -- Simulon Body Part 2 (UNCHANGED)
    local realer = (0.5 - 0.07854984894) * size;
    local simulon_box = Scene:add_polygon({
        position = position,
        points = {
            vec2(-realer, -realer / 1.13356164384),
            vec2(realer, -realer / 1.13356164384),
            vec2(realer, realer / 1.13356164384),
            vec2(-realer, realer / 1.13356164384),
        },
        radius = 0.07854984894 * size,
        color = color or Color:rgb(0.0, 1.0, 0.0),
        name = "Simulon Body Part 2",
    });

    c = simulon_box:add_component({ hash = biotics });
    p = c:get_property("natural_color");
    p.value = color;
    c:set_property("natural_color", p);
    simulon_box:add_component({ hash = conductor });
    
    -- CORRECTED HEAD POSITION to align naturally with where the hinge would pull it
    local head_body = Scene:add_circle({
        position = position + vec2(0, 1.235 * size),  -- Calculated natural resting position
        radius = 0.51656626506 * size,
        body_type = BodyType.Dynamic,
        color = color or Color:rgb(0.0, 1.0, 0.0),
        name = "Simulon Head",
    });

    c = head_body:add_component({ hash = biotics });
    p = c:get_property("natural_color");
    p.value = color;
    c:set_property("natural_color", p);
    head_body:add_component({ hash = conductor });

    local skeleton_scale_num = 0.00086;
    local skeleton_scale = vec2(skeleton_scale_num,skeleton_scale_num);

    local skeleton_1 = Scene:add_attachment({
        name = "Skeleton",
        parent = simulon_box,
        images = {{
            texture = require('core/assets/textures/skeleton_1.png'),
            scale = skeleton_scale,
            offset = vec2(0, -0.04),
            color = Color:rgba(1,1,1,0),
        }}
    });

    local skeleton_2 = Scene:add_attachment({
        name = "Skeleton",
        parent = simulon_body,
        images = {{
            texture = require('core/assets/textures/skeleton_2.png'),
            scale = skeleton_scale,
            offset = vec2(0, 0.06),
            color = Color:rgba(1,1,1,0),
        }}
    });

    local skeleton_3 = Scene:add_attachment({
        name = "Skeleton Skull",
        parent = head_body,
        images = {{
            texture = require('core/assets/textures/skeleton_3.png'),
            scale = skeleton_scale,
            offset = vec2(0, 0.02),
            color = Color:rgba(1,1,1,0),
        }}
    });
    
    -- Hinge joint - KEPT AT SAME POSITION
    local hinge = hinge({
        object_a = simulon_body,
        object_b = head_body,
        point = position + vec2(0, 0.8 * size),  -- UNCHANGED
        motor_enabled = false,
        motor_speed = 0.3,
        max_motor_torque = 100,
        size = 0.3,
        color = Color:rgba(1, 1, 1, 0),
    });
    
    local atch = Scene:add_attachment({
        name = "Spring",
        component = {
            name = "Spring",
            version = "0.1.0",
            id = "core/simulon/spring_temporary_attachment_thing",
            code = [==[
                local hinge = nil;
                local spring = nil;

                function on_event(id, data)
                    if id == "core/spring/init" then
                        spring = data.spring;
                        hinge = data.hinge;
                    end;
                end;

                function on_start(data)
                    if data ~= nil then
                        if data.spring ~= nil then
                            spring = data.spring;
                        end;
                        if data.hinge ~= nil then
                            hinge = data.hinge;
                        end;
                    end;
                end;

                function on_save()
                    return { spring = spring, hinge = hinge };
                end;

                function on_update()
                    if (spring:is_destroyed()) or (hinge:is_destroyed()) then
                        self:destroy();
                    end;
                end;
            ]==],
        },
        parent = simulon_body,
        local_position = vec2(0, (1.7 * size) - ((0.7 / 2.0) * size)),
        local_angle = 0,
        images = {},
        collider = { shape_type = "circle", radius = 0.1 * 0.3, }
    });

    -- Add spring joint between body and head (unchanged)
    local spring = Scene:add_spring({
        object_a = simulon_body,
        object_b = head_body,
        local_anchor_a = vec2(0, (1.7 * size) - ((0.7 / 2.0) * size)),
        local_anchor_b = vec2(0, (0.8 * size) - ((0.7 / 2.0) * size)),
        length = 0.005,
        stiffness = 100.0 * size,
        damping = 0.0,
        attachment = atch,
    });

    atch:send_event("core/spring/init", {
        spring = spring,
        hinge = hinge,
    });
    
    -- Bolt (UNCHANGED from last version)
    bolt({
        object_a = simulon_box,
        object_b = simulon_body,
        point = position + vec2(0, 0.5 * size),
        size = 0.3,
        color = Color:rgba(1, 1, 1, 0),
    });
    
    -- Return the created simulon as an object
    return {
        body = simulon_body,
        box = simulon_box,
        head = head_body,
    };
end;

return simulon;
--Scene:reset()
--for i=1,10 do
--simulon({position = vec2(i, 0)})
--end;
