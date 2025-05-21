-- this is remake of the old electricity system
Scene:reset();

local wire_hash = Scene:add_component_def({
    name = "Wire",
    id = "core/wire",
    version = "0.1.0",
    code = [[
        local resistance = 0.01;

        local current_voltage = 0;
        local current_max = 1;
        
        local touching = {};
        local path_history = {};

        function count_table(table)
            local count = 0;
            for _ in pairs(table) do
                count = count + 1;
            end;
            return count;
        end;

        function contains(table, value)
            for _, v in pairs(table) do
                if v == value then
                    return true;
                end;
            end;
            return false;
        end;

        function copy(table)
            local u = {};
            for k, v in pairs(table) do u[k] = v end;
            return setmetatable(u, getmetatable(table));
        end;

        function on_collision_start(data)
            table.insert(touching, data.other);
        end;

        function on_collision_end(data)
            for i, comp in pairs(touching) do
                if comp == data.other then
                    table.remove(touching, i);
                    break;
                end;
            end;
        end;

function deepCopy(original)
    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = deepCopy(value)
        else
            copy[key] = Scene:get_object(value)
        end
    end
    return copy
end

        function on_event(id, data)
            if id == "core/scan" then
                -- Add this component to the history of the current power flow
                table.insert(data.history, self);

                -- Propagate power to all connected components
                for _, object in pairs(touching) do
                    -- Check if this component has already received power in the current path
                    if not contains(data.history, object) then
                        -- Send scan event to the next component, passing the history of the path
                        object:send_event("core/scan", {
                            input_voltage = data.input_voltage * (1 - resistance),
                            history = deepCopy(data.history),
                            total_resistance = data.total_resistance + resistance,
                        });
                    end;
                end;
                for _, object in pairs(self:get_direct_connected()) do
                    if not contains(data.history, object) then
                        object:send_event("core/scan", {
                            input_voltage = data.input_voltage * (1 - resistance),
                            history = deepCopy(data.history),
                        });
                    end;
                end;
            elseif id == "core/activate" then
                -- Only process this event if we haven't seen it before
                if not data.visited then
                    data.visited = {}
                end
                
                if not data.visited[self.id] then
                    data.visited[self.id] = true
                    
                    current_voltage = data.current * resistance;
                    current_max = data.max_voltage;

                    -- Send activate event to components like lightbulbs
                    for _, object in pairs(touching) do
                        object:send_event("activate", { voltage = current_voltage });
                    end;
                    
                    for _, object in pairs(self:get_direct_connected()) do
                        object:send_event("activate", { voltage = current_voltage });
                    end;
                end
            end;
        end;

        function on_step()
            -- Determine color based on the current power or state
            self:set_color(Color:mix(0x2b190f, 0xffb978, current_voltage / current_max));
            current_voltage = 0;

            if self:get_body_type() ~= BodyType.Dynamic then
                touching = {};
            end;
        end;
    ]],
});

for i=1,15 do
    local wire = Scene:add_box({
        name = "Wire " .. i,
        position = vec2(i + 2, 0),
        size = vec2(1.5, 0.2),
    });

    wire:add_component({ hash = wire_hash });
end;

local plus_hash = Scene:add_component_def({
    name = "Plus",
    id = "core/plus",
    version = "0.1.0",
    code = [[
        function on_event(id, data)
            if id == "core/scan" then
                table.insert(data.history, self);

                -- Check if the power flow has reached back to the source or a loop is detected=
                -- The circuit is closed, so activate power for all in the path
                for _, object in pairs(data.history) do
                    if object ~= nil then
                        object:send_event("core/activate", {
                            current = 10 / data.total_resistance,
                            max_voltage = 10,
                        });
                    end;
                end;
            end;
        end;
    ]],
});

local plus = Scene:add_box({
    name = "Plus",
    position = vec2(0.5, 0),
    size = vec2(0.1, 0.25),
    color = 0xff8080,
});

plus:add_component({ hash = plus_hash });

local minus_hash = Scene:add_component_def({
    name = "Minus",
    id = "core/minus",
    version = "0.1.0",
    code = [[
        local touching = {};

        function on_collision_start(data)
            table.insert(touching, data.other);
        end;

        function on_collision_end(data)
            for i, comp in pairs(touching) do
                if comp == data.other then
                    table.remove(touching, i);
                    break;
                end;
            end;
        end;

        function on_step()
            -- On each step, propagate power to all connected components
            for _, object in pairs(touching) do
                -- Initiate power flow scan from the source
                object:send_event("core/scan", {
                    input_voltage = 10,
                    history = {self},
                    total_resistance = 0,
                });
            end;

            for _, object in pairs(self:get_direct_connected()) do
                -- Initiate power flow scan from the source
                object:send_event("core/scan", {
                    input_voltage = 10,
                    history = {self},
                    total_resistance = 0,
                });
            end;

            if self:get_body_type() ~= BodyType.Dynamic then
                touching = {};
            end;
        end;
    ]],
});

local minus = Scene:add_box({
    name = "Minus",
    position = vec2(-0.5, 0),
    size = vec2(0.1, 0.25),
    color = 0x202020,
});

minus:add_component({ hash = minus_hash });

local lightbulb_hash = Scene:add_component_def({
    name = "Lightbulb",
    id = "core/lightbulb",
    version = "0.1.0",
    code = [[
        function voltageToTestLightColor(voltage)
  -- ensure that at 0v the light is off
  if voltage <= 0 then
    return 0, 0, 0
  end

  local minVoltage = 0
  local maxVoltage = 6
  -- adjust minTemp to 1000k so that at low voltages we get a proper red
  local minTemp = 1000
  local maxTemp = 6500

  -- map voltage to a temperature in kelvin
  local temp = ((voltage - minVoltage) / (maxVoltage - minVoltage)) * (maxTemp - minTemp) + minTemp
    temp = math.min(temp, maxTemp);

  local r, g, b = temperatureToRGB(temp)
  -- scale brightness with voltage so low voltage gives dim light
  local brightness = voltage / maxVoltage
  r = math.min(255, r * brightness)
  g = math.min(255, g * brightness)
  b = math.min(255, b * brightness)

  return r, g, b
end

function temperatureToRGB(kelvin)
  -- convert kelvin to the tanner helland scale (kelvin / 100)
  local temperature = kelvin / 100
  local red, green, blue

  if temperature <= 66 then
    red = 255
    green = 99.4708025861 * math.log(temperature) - 161.1195681661
    if temperature <= 19 then
      blue = 0
    else
      blue = 138.5177312231 * math.log(temperature - 10) - 305.0447927307
    end
  else
    red = 329.698727446 * math.pow(temperature - 60, -0.1332047592)
    green = 288.1221695283 * math.pow(temperature - 60, -0.0755148492)
    blue = 255
  end

  red = math.min(math.max(red, 0), 255)
  green = math.min(math.max(green, 0), 255)
  blue = math.min(math.max(blue, 0), 255)

  return red, green, blue
end

        local voltage = 0;

        function on_event(id, data)
            if id == "activate" then
                voltage = data.voltage;
            end;
        end;

        function on_step()
            local r, g, b = voltageToTestLightColor(voltage);
            self:set_color(Color:rgb(r, g, b));
            voltage = 0;
        end;

    ]],
});

local lightbulb = Scene:add_box({
    name = "Lightbulb",
    position = vec2(3, 1),
    size = vec2(0.2, 0.3),
    color = 0xff8080,
});

lightbulb:add_component({ hash = lightbulb_hash });