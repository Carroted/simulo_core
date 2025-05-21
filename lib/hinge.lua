local function hinge(tbl)
    local object_a = tbl.object_a;
    local object_b = tbl.object_b;
    local point = tbl.point;
    local size = tbl.size or 1;
    local sound = tbl.sound;
    local motor_enabled = tbl.motor_enabled;
    local motor_speed = tbl.motor_speed;
    local max_motor_torque = tbl.max_motor_torque;
    local limit = tbl.limit;
    local lower_limit_angle = tbl.lower_limit_angle;
    local upper_limit_angle = tbl.upper_limit_angle;
    local breakable = tbl.breakable;
    local break_force = tbl.break_force;
    local collide_connected = tbl.collide_connected;

    local color = tbl.color or Color:hex(0xffffff);

    if motor_enabled == nil then
        motor_enabled = false;
    end;
    if motor_speed == nil then
        motor_speed = 10;
    end;
    if max_motor_torque == nil then
        max_motor_torque = 10;
    end;
    if lower_limit_angle == nil then
        lower_limit_angle = math.rad(-45);
    end;
    if upper_limit_angle == nil then
        upper_limit_angle = math.rad(45);
    end;
    if limit == nil then
        limit = false;
    end;
    if breakable == nil then
        breakable = false;
    end;
    if break_force == nil then
        break_force = 50;
    end;

    if sound == nil then
        sound = true;
    end;

    local attachment_parent = nil;

    local anchor_a = point;
    local anchor_b = point;

    if object_a ~= nil then
        anchor_a = object_a:get_local_point(point);
        attachment_parent = object_a;
    end;

    if object_b ~= nil then
        anchor_b = object_b:get_local_point(point);
        attachment_parent = object_b;
    end;

    local atch = Scene:add_attachment({
        name = "Hinge",
        component = {
            name = "Hinge",
            version = "0.1.0",
            id = "core/hinge",
            icon = require("core/tools/hinge/icon.png"),
            code = [==[
                local hinge = nil;

                function on_event(id, data)
                    if id == "core/hinge/init" then
                        hinge = data;
                    elseif id == "core/hinge/get" then
                        return hinge;
                    elseif id == "property_changed" then
                        hinge:set_motor_enabled(self:get_property("motor_enabled").value);
                        hinge:set_motor_speed(self:get_property("motor_speed").value);
                        hinge:set_max_motor_torque(self:get_property("max_motor_torque").value);
                        hinge:set_limit(self:get_property("limit").value);
                        hinge:set_lower_limit_angle(math.rad(self:get_property("lower_limit_angle").value));
                        hinge:set_upper_limit_angle(math.rad(self:get_property("upper_limit_angle").value));
                        
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
                        if data.hinge ~= nil then
                            hinge = data.hinge;
                        end;
                    end;
                end;

                function on_save()
                    return { hinge = hinge };
                end;

                function on_update()
                    if hinge:is_destroyed() then self:destroy(); end;
                end;

                function on_step()
                    local breakable = self:get_property("breakable").value;
                    if breakable then
                        local break_force = self:get_property("break_force").value;
                        if hinge:get_force():magnitude() > break_force then
                            hinge:destroy();
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
                    default_value = color,
                },
                {
                    id = "motor_enabled",
                    name = "Enable Motor",
                    input_type = "toggle",
                    default_value = motor_enabled or false,
                },
                {
                    id = "motor_speed",
                    name = "Motor Speed (0 for brake)",
                    input_type = "slider",
                    default_value = motor_speed,
                    min_value = -50,
                    max_value = 50,
                },
                {
                    id = "max_motor_torque",
                    name = "Max Motor Torque",
                    input_type = "slider",
                    default_value = max_motor_torque,
                    min_value = 1,
                    max_value = 100,
                },
                {
                    id = "limit",
                    name = "Limit",
                    input_type = "toggle",
                    default_value = limit,
                },
                {
                    id = "lower_limit_angle",
                    name = "Lower Limit Angle",
                    input_type = "slider",
                    default_value = math.deg(lower_limit_angle),
                    min_value = -180,
                    max_value = 180,
                },
                {
                    id = "upper_limit_angle",
                    name = "Upper Limit Angle",
                    input_type = "slider",
                    default_value = math.deg(upper_limit_angle),
                    min_value = -180,
                    max_value = 180,
                },
                {
                    id = "breakable",
                    name = "Breakable",
                    input_type = "toggle",
                    default_value = breakable,
                },
                {
                    id = "break_force",
                    name = "Break Force",
                    input_type = "slider",
                    default_value = break_force,
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
                texture = require("core/attachments/hinge/attachment.png"),
                scale = vec2(0.0007, 0.0007) * size,
                color = color,
            },
        },
        collider = { shape_type = "circle", radius = 0.1 * size }
    });

    local hinge = Scene:add_hinge({
        object_a = object_a,
        object_b = object_b,
        point = point,
        local_anchor_a = anchor_a,
        local_anchor_b = anchor_b,
        attachment = atch,
        limit = limit,
        lower_limit_angle = lower_limit_angle,
        upper_limit_angle = upper_limit_angle,
        motor_enabled = motor_enabled,
        motor_speed = motor_speed,
        max_motor_torque = max_motor_torque,
        collide_connected = collide_connected,
    });

    atch:send_event("core/hinge/init", hinge);
    
    if sound then
        Scene:add_audio({
            asset = require("core/tools/hinge/assets/up.wav"),
            position = point,
            pitch = 1 + (-0.1 + (0.1 - -0.1) * math.random()),
            volume = 0.5,
        });
    end;

    return atch;
end;

return hinge;
