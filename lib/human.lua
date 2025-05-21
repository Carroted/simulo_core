local bolt = require('core/lib/bolt.lua')
local hinge = require('core/lib/hinge.lua')

local conductor = require('core/components/conductor');
local biotics = require('core/components/biotics');

local function set_property_value(component, key, value)
    local prop = component:get_property(key);
    prop.value = value;
    component:set_property(key, prop);
end;

local circle_hash = Scene:add_component_def({
    name = "Blood",
    id = "core/components/blood", -- Example ID, you can change 'user/example'
    version = "0.1.0",

    properties = {
        {
            id = "amount",
            name = "Amount",
            input_type = "slider",
            default_value = 20,
            min_value = 1,
            max_value = 100,
        },
        {
            id = "color",
            name = "Color",
            input_type = "color",
            default_value = 0x7f2025,
        },
        {
            id = "radius",
            name = "Radius",
            input_type = "slider",
            default_value = 0.044,
            min_value = 0.01,
            max_value = 2.0,
        },
        {
            id = "density",
            name = "Density",
            input_type = "slider",
            default_value = 0.2,
            min_value = 0.1,
            max_value = 1.0,
        },
    },

    -- The actual Luau code for the component's logic
    code = [[
        function on_destroy()
            local amount = self_component:get_property("amount").value;
            local circle_color = self_component:get_property("color").value;
            local circle_radius = self_component:get_property("radius").value;
            local circle_density = self_component:get_property("density").value;

            -- Get the position of the object this component is attached to
            -- This is where the circles will spawn
            local spawn_position = self:get_position();

            -- Loop 'amount' times to spawn the circles
            for i=1,amount do
                Scene:add_circle({
                    position = spawn_position,
                    radius = circle_radius,
                    color = circle_color,
                    density = circle_density,
                    friction = 0,
                    restitution = 0,
                });
            end;
        end;
    ]],
});

local function add_human(args)
    -- Default parameters
    local defaults = {
        position = vec2(0, 0),
        scale = 1.0,
        hue = 20,
        sat = true,
        torque = 1.0,
        feet_density = 1.0,
        attachment_color = nil,  -- If nil, uses default attachment color
        breakable = true,
        break_force = 250,
    }
    
    -- Apply defaults for any missing arguments
    args = args or {}
    for k, v in pairs(defaults) do
        if args[k] == nil then
            args[k] = v
        end
    end
    
    -- Extract parameters for convenience
    local position = args.position + vec2(0, -1.25);
    local scale = args.scale * 1.25;
    local hue = args.hue;
    local sat = args.sat;
    local torque = args.torque;
    local feet_density = args.feet_density;
    local attach_color = args.attachment_color;
    local breakable = args.breakable;
    local break_force = args.break_force;
    print("breakable", breakable);
    
    local s = scale
    local max_torque = 5 * s * torque
    local enable_motor = true
    local enable_limit = true
    
    -- Get color based on hue and saturation
    local function get_color(h, saturation, value)
        if not sat then saturation = 0 end
        return Color:hsv(h, saturation, value)
    end
    
    -- Add neck FIRST so it's behind everything else
    local neck = Scene:add_capsule({
        position = position + vec2(0, 1.45 * s),
        radius = 0.05 * s,
        local_point_a = vec2(0, -0.05 * s),
        local_point_b = vec2(0, 0.1 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 165/255, 230/255),
        friction = 0.2,
        name = "Human Neck",
    })
    neck:add_component({ hash = conductor });
    local b = neck:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 165/255, 230/255));
    
    -- Then left limbs (so they're behind)
    -- Upper left leg
    local upper_left_leg = Scene:add_capsule({
        position = position + vec2(0, 0.775 * s),
        radius = 0.06 * s,
        local_point_a = vec2(0, -0.125 * s),
        local_point_b = vec2(0, 0.125 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 133/255, 1),
        friction = 0.2,
        name = "Human Upper Left Leg",
    })
    upper_left_leg:add_component({ hash = conductor });
    local b = upper_left_leg:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 165/255, 230/255));
    
    -- Lower left leg
    local lower_left_leg = Scene:add_capsule({
        position = position + vec2(0, 0.475 * s),
        radius = 0.05 * s,
        local_point_a = vec2(0, -0.14 * s),
        local_point_b = vec2(0, 0.125 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 162/255, 1),
        friction = 0.2,
        name = "Human Lower Left Leg",
    })
    lower_left_leg:add_component({ hash = conductor });
    local b = lower_left_leg:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 162/255, 1));
    
    -- Left foot (horizontal capsule)
    local left_foot = Scene:add_capsule({
        position = position + vec2(0, 0.475 * s),
        radius = 0.03 * s,
        local_point_a = vec2(-0.02 * s, -0.175 * s),
        local_point_b = vec2(0.13 * s, -0.175 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 133/255, 1),
        friction = 0.05,
        density = feet_density,
        name = "Human Left Foot",
    })
    left_foot:add_component({ hash = conductor });
    local b = left_foot:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 133/255, 1));
    
    -- Upper left arm
    local upper_left_arm = Scene:add_capsule({
        position = position + vec2(0, 1.225 * s),
        radius = 0.035 * s,
        local_point_a = vec2(0, -0.125 * s),
        local_point_b = vec2(0, 0.125 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 155/255, 246/255),
        friction = 0.2,
        name = "Human Upper Left Arm",
    })
    upper_left_arm:add_component({ hash = conductor });
    local b = upper_left_arm:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 155/255, 246/255));
    
    -- Lower left arm
    local lower_left_arm = Scene:add_capsule({
        position = position + vec2(0, 0.975 * s),
        radius = 0.03 * s,
        local_point_a = vec2(0, -0.125 * s),
        local_point_b = vec2(0, 0.125 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 165/255, 242/255),
        friction = 0.2,
        name = "Human Lower Left Arm",
    })
    lower_left_arm:add_component({ hash = conductor });
    local b = lower_left_arm:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 165/255, 242/255));
    
    -- Hip
    local hip = Scene:add_capsule({
        position = position + vec2(0, 0.95 * s),
        radius = 0.095 * s,
        local_point_a = vec2(0, -0.02 * s),
        local_point_b = vec2(0, 0.02 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 151/255, 1),
        friction = 0.2,
        name = "Human Hip",
    })
    hip:add_component({ hash = conductor });
    local b = hip:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 151/255, 1));
    
    -- Torso
    local torso = Scene:add_capsule({
        position = position + vec2(0, 1.2 * s),
        radius = 0.09 * s,
        local_point_a = vec2(0, -0.135 * s),
        local_point_b = vec2(0, 0.135 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 133/255, 1),
        friction = 0.2,
        name = "Human Torso",
    })
    torso:add_component({ hash = conductor });
    local b = torso:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 133/255, 1));
    
    -- Head
    local head = Scene:add_capsule({
        position = position + vec2(0, 1.5 * s),
        radius = 0.08 * s,
        local_point_a = vec2(0, -0.0325 * s),
        local_point_b = vec2(0, 0.0325 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 162/255, 1),
        friction = 0.2,
        name = "Human Head",
    })
    head:add_component({ hash = conductor });
    local b = head:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 162/255, 1));
    
    -- Upper right leg
    local upper_right_leg = Scene:add_capsule({
        position = position + vec2(0, 0.775 * s),
        radius = 0.06 * s,
        local_point_a = vec2(0, -0.125 * s),
        local_point_b = vec2(0, 0.125 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 133/255, 1),
        friction = 0.2,
        name = "Human Upper Right Leg",
    })
    upper_right_leg:add_component({ hash = conductor });
    local b = upper_right_leg:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 133/255, 1));
    
    -- Lower right leg
    local lower_right_leg = Scene:add_capsule({
        position = position + vec2(0, 0.475 * s),
        radius = 0.05 * s,
        local_point_a = vec2(0, -0.14 * s),
        local_point_b = vec2(0, 0.125 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 162/255, 1),
        friction = 0.2,
        name = "Human Lower Right Leg",
    })
    lower_right_leg:add_component({ hash = conductor });
    local b = lower_right_leg:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 162/255, 1));
    
    -- Right foot (horizontal capsule)
    local right_foot = Scene:add_capsule({
        position = position + vec2(0, 0.475 * s),
        radius = 0.03 * s,
        local_point_a = vec2(-0.02 * s, -0.175 * s),
        local_point_b = vec2(0.13 * s, -0.175 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 133/255, 1),
        friction = 0.05,
        density = feet_density,
        name = "Human Right Foot",
    })
    right_foot:add_component({ hash = conductor });
    local b = right_foot:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 133/255, 1));
    
    -- Upper right arm
    local upper_right_arm = Scene:add_capsule({
        position = position + vec2(0, 1.225 * s),
        radius = 0.035 * s,
        local_point_a = vec2(0, -0.125 * s),
        local_point_b = vec2(0, 0.125 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 155/255, 246/255),
        friction = 0.2,
        name = "Human Upper Right Arm",
    })
    upper_right_arm:add_component({ hash = conductor });
    local b = upper_right_arm:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 155/255, 246/255));
    
    -- Lower right arm
    local lower_right_arm = Scene:add_capsule({
        position = position + vec2(0, 0.975 * s),
        radius = 0.03 * s,
        local_point_a = vec2(0, -0.125 * s),
        local_point_b = vec2(0, 0.125 * s),
        body_type = BodyType.Dynamic,
        color = get_color(hue, 165/255, 242/255),
        friction = 0.2,
        name = "Human Lower Right Arm",
    })
    lower_right_arm:add_component({ hash = conductor });
    local b = lower_right_arm:add_component({ hash = biotics });
    set_property_value(b, "motor_enabled", false);
    set_property_value(b, "natural_color", get_color(hue, 165/255, 242/255));
    
    -- Add phasers to prevent all body parts from colliding with each other
    local limbs = {
        neck, hip, torso, head,
        upper_left_leg, lower_left_leg, left_foot,
        upper_right_leg, lower_right_leg, right_foot,
        upper_left_arm, lower_left_arm,
        upper_right_arm, lower_right_arm
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
    
    -- Now create all the connections
    
    -- Connect hip to torso
    hinge({
        object_a = hip,
        object_b = torso,
        point = position + vec2(0, 1.0 * s),
        motor_enabled = enable_motor,
        motor_speed = 0,
        max_motor_torque = 0.5 * max_torque,
        lower_limit_angle = -0.25 * math.pi,
        upper_limit_angle = 0,
        limit = enable_limit,
        size = 0.3,
        color = attach_color,
        breakable = breakable,
        break_force = break_force,
    }):add_component({ hash = circle_hash });
    
    -- Connect torso to neck
    hinge({
        object_a = torso,
        object_b = neck,
        point = position + vec2(0, 1.4 * s),
        motor_enabled = enable_motor,
        motor_speed = 0,
        max_motor_torque = 0.25 * max_torque,
        lower_limit_angle = -0.3 * math.pi,
        upper_limit_angle = 0.1 * math.pi,
        limit = enable_limit,
        size = 0.3,
        color = attach_color,
        breakable = breakable,
        break_force = break_force,
    }):add_component({ hash = circle_hash });
    
    -- Bolt the neck to the head
    bolt({
        object_a = head,
        object_b = neck,
        point = position + vec2(0, 1.5 * s),
        size = 0.3,
        color = attach_color,
    })
    
    -- Connect hip to upper left leg
    hinge({
        object_a = hip,
        object_b = upper_left_leg,
        point = position + vec2(0, 0.9 * s),
        motor_enabled = enable_motor,
        motor_speed = 0,
        max_motor_torque = max_torque,
        lower_limit_angle = -0.05 * math.pi,
        upper_limit_angle = 0.4 * math.pi,
        limit = enable_limit,
        size = 0.3,
        color = attach_color,
        breakable = breakable,
        break_force = break_force,
    }):add_component({ hash = circle_hash });
    
    -- Connect upper left leg to lower left leg
    hinge({
        object_a = upper_left_leg,
        object_b = lower_left_leg,
        point = position + vec2(0, 0.625 * s),
        motor_enabled = enable_motor,
        motor_speed = 0,
        max_motor_torque = 0.5 * max_torque,
        lower_limit_angle = -0.5 * math.pi,
        upper_limit_angle = -0.02 * math.pi,
        limit = enable_limit,
        size = 0.3,
        color = attach_color,
        breakable = breakable,
        break_force = break_force,
    }):add_component({ hash = circle_hash });
    
    -- Bolt the left foot to the lower left leg
    bolt({
        object_a = lower_left_leg,
        object_b = left_foot,
        point = position + vec2(0.055 * s, 0.335 * s),
        size = 0.3,
        color = attach_color,
    })
    
    -- Connect hip to upper right leg
    hinge({
        object_a = hip,
        object_b = upper_right_leg,
        point = position + vec2(0, 0.9 * s),
        motor_enabled = enable_motor,
        motor_speed = 0,
        max_motor_torque = max_torque,
        lower_limit_angle = -0.05 * math.pi,
        upper_limit_angle = 0.4 * math.pi,
        limit = enable_limit,
        size = 0.3,
        color = attach_color,
        breakable = breakable,
        break_force = break_force,
    }):add_component({ hash = circle_hash });
    
    -- Connect upper right leg to lower right leg
    hinge({
        object_a = upper_right_leg,
        object_b = lower_right_leg,
        point = position + vec2(0, 0.625 * s),
        motor_enabled = enable_motor,
        motor_speed = 0,
        max_motor_torque = 0.5 * max_torque,
        lower_limit_angle = -0.5 * math.pi,
        upper_limit_angle = -0.02 * math.pi,
        limit = enable_limit,
        size = 0.3,
        color = attach_color,
        breakable = breakable,
        break_force = break_force,
    }):add_component({ hash = circle_hash });
    
    -- Bolt the right foot to the lower right leg
    bolt({
        object_a = lower_right_leg,
        object_b = right_foot,
        point = position + vec2(0.055 * s, 0.335 * s),
        size = 0.3,
        color = attach_color,
    })
    
    -- Connect torso to upper left arm
    hinge({
        object_a = torso,
        object_b = upper_left_arm,
        point = position + vec2(0, 1.35 * s),
        motor_enabled = enable_motor,
        motor_speed = 0,
        max_motor_torque = 0.5 * max_torque,
        lower_limit_angle = -0.78,
        upper_limit_angle = 0.8 * math.pi,
        limit = enable_limit,
        size = 0.3,
        color = attach_color,
        breakable = breakable,
        break_force = break_force,
    }):add_component({ hash = circle_hash });
    
    -- Connect upper left arm to lower left arm
    hinge({
        object_a = upper_left_arm,
        object_b = lower_left_arm,
        point = position + vec2(0, 1.1 * s),
        motor_enabled = enable_motor,
        motor_speed = 0,
        max_motor_torque = 0.1 * max_torque,
        lower_limit_angle = 0.01 * math.pi,
        upper_limit_angle = 0.5 * math.pi,
        limit = enable_limit,
        size = 0.3,
        color = attach_color,
        breakable = breakable,
        break_force = break_force,
    }):add_component({ hash = circle_hash });
    
    -- Connect torso to upper right arm
    hinge({
        object_a = torso,
        object_b = upper_right_arm,
        point = position + vec2(0, 1.35 * s),
        motor_enabled = enable_motor,
        motor_speed = 0,
        max_motor_torque = 0.5 * max_torque,
        lower_limit_angle = -0.78,
        upper_limit_angle = 0.8 * math.pi,
        limit = enable_limit,
        size = 0.3,
        color = attach_color,
        breakable = breakable,
        break_force = break_force,
    }):add_component({ hash = circle_hash });
    
    -- Connect upper right arm to lower right arm
    hinge({
        object_a = upper_right_arm,
        object_b = lower_right_arm,
        point = position + vec2(0, 1.1 * s),
        motor_enabled = enable_motor,
        motor_speed = 0,
        max_motor_torque = 0.1 * max_torque,
        lower_limit_angle = 0.01 * math.pi,
        upper_limit_angle = 0.5 * math.pi,
        limit = enable_limit,
        size = 0.3,
        color = attach_color,
        breakable = breakable,
        break_force = break_force,
    }):add_component({ hash = circle_hash });
    
    -- Return the created human parts
    return {
        hip = hip,
        torso = torso,
        head = head,
        neck = neck,
        upper_left_leg = upper_left_leg,
        lower_left_leg = lower_left_leg,
        left_foot = left_foot,
        upper_right_leg = upper_right_leg,
        lower_right_leg = lower_right_leg,
        right_foot = right_foot,
        upper_left_arm = upper_left_arm,
        lower_left_arm = lower_left_arm,
        upper_right_arm = upper_right_arm,
        lower_right_arm = lower_right_arm,
    }
end
--[[
-- Example usage
Scene:reset()
Scene:reset()

    local human = add_human({
        position = vec2(0, 20),
        scale = 1.0,
        hue = 20,  -- Orange-ish hue (without division)
        sat = true,
        torque = 1.0,
        feet_density = 1.5,
        attachment_color = Color:rgba(0, 0, 0, 0)  -- Invisible attachments
    })

-- Add the ground
Scene:add_box({
    position = vec2(0, -2),
    size = vec2(30, 1),
    body_type = BodyType.Static,
    color = Color:rgb(0.5, 0.5, 0.5),
})]]

return add_human;