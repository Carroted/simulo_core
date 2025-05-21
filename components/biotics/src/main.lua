-- Biotics component has:
--   - Electrocution
--   - Can respond to vitals requests
--   - Natural healing
--   - Health declines if vitality too low

local current_power = 0;
local spark = false;

function show_skeleton()
    local atchs = self:get_attachments();
    for i=1,#atchs do
        if string.find(atchs[i]:get_name() or "", "Skeleton", 1, true) then
            local imgs = atchs[i]:get_images();
            for j=1,#imgs do
                imgs[i].color = Color:rgb(1,1,1);
            end;
            atchs[i]:set_images(imgs);
        end;
    end;
end;

function hide_skeleton()
    local atchs = self:get_attachments();
    for i=1,#atchs do
        if string.find(atchs[i]:get_name() or "", "Skeleton", 1, true) then
            local imgs = atchs[i]:get_images();
            for j=1,#imgs do
                imgs[i].color = Color:rgba(1,1,1,0);
            end;
            atchs[i]:set_images(imgs);
        end;
    end;
end;

function on_event(id, data)
    if id == "activate" then
        if data.power then
            current_power += data.power;
        else
            current_power += 1;
        end;
    elseif id == "core/request_vitals" then
        local vitality = self_component:get_property("vitality").value;

        if vitality >= 0.005 then
            data:send_event("core/vitals", {
                vitality = vitality,
            });
        end;
    elseif id == "core/spark" then
        spark = true;
    elseif id == "heal" then
        local prop = self_component:get_property("vitality");
        if data.amount then
            prop.value = math.min(math.max(prop.value + data.amount, 0), 1);
        else
            prop.value = math.min(1, prop.value + 0.1);
        end;
        self_component:set_property("vitality", prop);
    elseif id == "hurt" then
        local prop = self_component:get_property("vitality");
        if data.amount then
            prop.value = math.min(math.max(prop.value - data.amount, 0), 1);
        else
            prop.value = math.max(0, prop.value - 0.1);
        end;
        self_component:set_property("vitality", prop);
    end;
end;

function on_step()
    if current_power > 2 then
        local color = self:get_color();
        local h,s,v = color:get_hsv();
        v = math.max(0, v - ((current_power - 2) / 800));
        s = math.max(0, v - ((current_power - 2) / 3000));
        self:set_color(Color:hsva(h,s,v,color.a));

        local prop = self_component:get_property("vitality");
        prop.value = math.max(0, prop.value - ((current_power - 2) / 800));
        self_component:set_property("vitality", prop);
    end;

    if spark then
        show_skeleton();
    else
        hide_skeleton();
    end;
    spark = false;

    local hinges = self:get_hinges();
    for i=1,#hinges do
        local atch = hinges[i]:get_attachment();
        if atch ~= nil then
            local motor_enabled = atch:get_property("motor_enabled");
            local motor_speed = atch:get_property("motor_speed");

            if motor_enabled ~= nil then
                motor_enabled.value = (current_power > 0) or self_component:get_property("motor_enabled").value;
                atch:set_property("motor_enabled", motor_enabled);
            else
                hinges[i]:set_motor_enabled((current_power > 0) or self_component:get_property("motor_enabled").value);
            end;

            if motor_speed ~= nil then
                motor_speed.value = current_power * (math.random() - 0.5) * 2 * 2;
                atch:set_property("motor_speed", motor_speed);
            else
                hinges[i]:set_motor_speed(current_power * (math.random() - 0.5) * 2 * 2);
            end;
        else
            hinges[i]:set_motor_enabled((current_power > 0) or self_component:get_property("motor_enabled").value);
            hinges[i]:set_motor_speed(current_power * (math.random() - 0.5) * 2 * 2);
        end;
    end;

    current_power = 0;

    if self_component:get_property("vitality").value > 0.3 then
        -- Natural slow healing

        local current_color = self:get_color();
        local natural_color = self_component:get_property("natural_color").value;

        local diff = math.abs(current_color.r - natural_color.r) + 
                        math.abs(current_color.g - natural_color.g) + 
                        math.abs(current_color.b - natural_color.b) + 
                        math.abs(current_color.a - natural_color.a);

        if diff > 0.001 then
            self:set_color(Color:mix(current_color, natural_color, 0.00006));
        end;

        local prop = self_component:get_property("vitality");
        prop.value = math.min(1, prop.value + 0.0001 * (1 - prop.value));
        self_component:set_property("vitality", prop);
    end;

    local prop = self_component:get_property("vitality");

    if (prop.value >= 0.005) and (prop.value < 0.2) then
        -- It just gets worse and worse and worse and worse

        local current_color = self:get_color();
        local h,s,v = current_color:get_hsv();

        s = math.max(0, s * 0.995);

        local new_color = Color:hsva(h,s,v, current_color.a);

        local diff = math.abs(current_color.r - new_color.r) + 
                        math.abs(current_color.g - new_color.g) + 
                        math.abs(current_color.b - new_color.b) + 
                        math.abs(current_color.a - new_color.a);

        if diff > 0.001 then
            self:set_color(new_color);
        end;

        prop.value = prop.value * 0.995;
        self_component:set_property("vitality", prop);
    end;
end;