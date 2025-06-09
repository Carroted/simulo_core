-- player is unfinished and will change
-- if you want you can back up the core of each simu version incase you dont like newer players

local hinge = require('core/lib/hinge.lua');
local bolt = require('core/lib/bolt.lua');
local conductor = require('core/components/conductor');

local biotics = Scene:add_component_def({
    id = "core/components/player_part",
    name = "Player Part",
    version = "0.1.0",
    code = require('core/lib/player/part.lua', 'string'),
    properties = {
        {
            id = "natural_color",
            name = "Natural Color",
            input_type = "color",
        },
        {
            id = "motor_enabled",
            name = "Motor Enabled",
            input_type = "toggle",
        },
        {
            id = "vitality",
            name = "Vitality",
            input_type = "slider",
            min_value = 0,
            max_value = 1,
            default_value = 1,
        }
    },
});

local controller = Scene:add_component_def({
    id = "core/components/player_controller",
    name = "Player Controller",
    version = "0.1.0",
    code = require('core/lib/player/controller.lua', 'string'),
});

local function player(tbl)
    local position = tbl.position or vec2(0, 0);
    local color = tbl.color or Color.SIMULO_GREEN;
    local density = tbl.density or 1;
    local size = ((tbl.size or 1) * 0.83279) / 2.0;

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
            vec2(-realer, -realer / 3),
            vec2(realer, -realer / 3),
            vec2(realer, realer / 1.13356164384),
            vec2(-realer, realer / 1.13356164384),
        },
        radius = 0.07854984894 * size,
        color = color or Color:rgb(0.0, 1.0, 0.0),
        name = "Simulon Body Part 2",
    });

    local left_leg = Scene:add_capsule({
        position = position + vec2(-realer + (realer * 0.35), (-realer * 0.4) * 1.4),
        local_point_a = vec2(0, realer * 0.4),
        local_point_b = vec2(0, -realer * 0.4),
        radius = (0.07854984894 * size) + (realer * 0.35),
        color = color or Color:rgb(0.0, 1.0, 0.0),
        name = "Simulon Body Part 2",
        density = 0.1,
        friction = 0.2,
        restitution = 0,
    });

    local left_foot = Scene:add_polygon({
        position = position + vec2(-realer + (realer * 0.35), (-realer) * 1.15),
        points = {
            vec2(-realer * 0.35, -realer * 0.2),
            vec2(realer * 0.35, -realer * 0.2),
            vec2(realer * 0.35, realer * 0.2),
            vec2(-realer * 0.35, realer * 0.2),
        },
        radius = 0.07854984894 * size,
        color = color or Color:rgb(0.0, 1.0, 0.0),
        name = "Simulon Body Part 2",
        density = 2,
        friction = 0,
        restitution = 0,
    });

    Scene:add_bolt({
        object_a = left_leg,
        object_b = left_foot,
        local_anchor_a = vec2(0, 0),
        local_anchor_b = left_foot:get_local_point(left_leg:get_position()),
    });

    local left_hinge = hinge({
        object_a = simulon_box,
        object_b = left_leg,
        point = left_leg:get_world_point(vec2(0, 0.07)),
        motor_enabled = true,
        motor_speed = 0,
        max_motor_torque = 100,
        size = 0.3,
        color = Color:rgba(1, 1, 1, 0),
    });

    Scene:add_phaser({
        object_a = simulon_body,
        object_b = left_leg,
    });

    local right_leg = Scene:add_capsule({
        position = position + vec2(realer - (realer * 0.35), (-realer * 0.4) * 1.4),
        local_point_a = vec2(0, realer * 0.4),
        local_point_b = vec2(0, -realer * 0.4),
        radius = (0.07854984894 * size) + (realer * 0.35),
        color = color or Color:rgb(0.0, 1.0, 0.0),
        name = "Simulon Body Part 2",
        density = 0.1,
        friction = 0.2,
        restitution = 0,
    });

    local right_foot = Scene:add_polygon({
        position = position + vec2(realer - (realer * 0.35), (-realer) * 1.15),
        points = {
            vec2(-realer * 0.35, -realer * 0.2),
            vec2(realer * 0.35, -realer * 0.2),
            vec2(realer * 0.35, realer * 0.2),
            vec2(-realer * 0.35, realer * 0.2),
        },
        radius = 0.07854984894 * size,
        color = color or Color:rgb(0.0, 1.0, 0.0),
        name = "Simulon Body Part 2",
        density = 2,
        friction = 0,
        restitution = 0,
    });

    Scene:add_bolt({
        object_a = right_leg,
        object_b = right_foot,
        local_anchor_a = vec2(0, 0),
        local_anchor_b = right_foot:get_local_point(right_leg:get_position()),
    });

    local right_hinge = hinge({
        object_a = simulon_box,
        object_b = right_leg,
        point = right_leg:get_world_point(vec2(0, 0.07)),
        motor_enabled = true,
        motor_speed = 0,
        max_motor_torque = 100,
        size = 0.3,
        color = Color:rgba(1, 1, 1, 0),
    });

    Scene:add_phaser({
        object_a = simulon_body,
        object_b = right_leg,
    });
    Scene:add_phaser({
        object_a = simulon_box,
        object_b = right_leg,
    });
    Scene:add_phaser({
        object_a = simulon_box,
        object_b = left_leg,
    });
    Scene:add_phaser({
        object_a = left_leg,
        object_b = right_leg,
    });

    local right_arm = Scene:add_capsule({
        position = position + vec2(realer * 0.7, (realer * 0.45) * 3),
        local_point_a = vec2(-realer * 0.13, 0),
        local_point_b = vec2(realer * 1.4, 0),
        radius = (realer * 0.4),
        color = color or Color:rgb(0.0, 1.0, 0.0),
        name = "Simulon Body Part 2",
        density = 0.1,
        friction = 0.2,
        restitution = 0,
    });
    local left_arm = Scene:add_capsule({
        position = position + vec2(-realer * 0.7, (realer * 0.45) * 3),
        local_point_a = vec2(realer * 0.13, 0),
        local_point_b = vec2(-realer * 1.4, 0),
        radius = (realer * 0.4),
        color = color or Color:rgb(0.0, 1.0, 0.0),
        name = "Simulon Body Part 2",
        density = 0.1,
        friction = 0.2,
        restitution = 0,
    });
--[[
    local right_hinge_arm = hinge({
        object_a = simulon_body,
        object_b = right_arm,
        point = right_arm:get_world_point(vec2(-realer * 1.3 * 0.1, 0)),
        motor_enabled = true,
        motor_speed = 0,
        max_motor_torque = 100,
        size = 0.3,
        color = Color:rgba(1, 1, 1, 0),
    });
    local left_hinge_arm = hinge({
        object_a = simulon_body,
        object_b = left_arm,
        point = left_arm:get_world_point(vec2(realer * 1.3 * 0.1, 0)),
        motor_enabled = true,
        motor_speed = 0,
        max_motor_torque = 100,
        size = 0.3,
        color = Color:rgba(1, 1, 1, 0),
    });]]

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
        density = 0.1,
    });

    head_body:add_component({ hash = controller, saved_data = {
        left_hinge = left_hinge,
        right_hinge = right_hinge,
        body = simulon_box,
        left_foot = left_foot,
        right_foot = right_foot,
        left_hinge_arm = left_hinge_arm,
        right_hinge_arm = right_hinge_arm,
        left_arm = left_arm,
        right_arm = right_arm,
        left_arm_pivot = simulon_box:get_local_point(left_arm:get_world_point(vec2(realer * 1.3 * 0.1, 0))),
        right_arm_pivot = simulon_box:get_local_point(right_arm:get_world_point(vec2(-realer * 1.3 * 0.1, 0))),
    } });

    c = head_body:add_component({ hash = biotics });
    p = c:get_property("natural_color");
    p.value = color;
    c:set_property("natural_color", p);
    head_body:add_component({ hash = conductor });
    
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
        damping = 0.5,
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

    local limbs = {
        simulon_body, simulon_box, left_leg, right_leg, left_foot, right_foot, head_body, left_arm,right_arm
    };
    
    -- Add phasers between all limbs (creates "no collision" pairs)
    for i = 1, #limbs do
        for j = i + 1, #limbs do
            Scene:add_phaser({
                object_a = limbs[i],
                object_b = limbs[j]
            })
        end
    end
    
    -- Return the created
    return limbs;
end;

return player;
