-- Robust electricity system with complete connection mapping
Scene:reset();

-- Plus Terminal
local plus_hash = Scene:add_component_def({
    name = "Plus",
    id = "core/plus",
    version = "0.1.0",
    code = [[
        local target_exposed = false;

        -- Get all connections
        function get_all_connections()
            local connections = {};
            
            -- Add touching components
            for _, obj in ipairs(self:get_touching()) do
                -- To ask each object if they're exposed, we send an event.
                target_exposed = false;
                obj:send_event("core/request_exposed", self_component);
                if target_exposed then
                    table.insert(connections, obj);
                end;
            end;
            
            -- Add direct connections
            for _, obj in ipairs(self:get_direct_connected()) do
                table.insert(connections, obj);
            end;
            
            return connections;
        end;
        
        function on_event(id, data)
            if id == "core/request_exposed" then
                data:send_event("core/report_exposed");
            elseif id == "core/report_exposed" then
                target_exposed = true;
            elseif id == "core/request_connections" then
                -- Skip if already processed
                if data.visited[self.id] then
                    return;
                end
                
                -- Mark as visited
                data.visited[self.id] = true;
                
                -- Get all connections
                local connections = get_all_connections();
                local connection_ids = {};
                
                for _, obj in ipairs(connections) do
                    table.insert(connection_ids, obj.id);
                end;
                
                -- Report back to minus terminal WITH PLUS FLAG
                data.source:send_event("core/report_connections", {
                    id = self.id,
                    connections = connection_ids,
                    is_plus = true
                });
                
                -- Forward request to all connections
                for _, obj in ipairs(connections) do
                    obj:send_event("core/request_connections", data);
                end;
            elseif id == "activate" then
                -- Plus terminal just receives power
            end;
        end;
    ]],
});

local plus = Scene:add_box({
    name = "Plus",
    position = vec2(0, 0.43),
    size = vec2(0.15, 0.25),
    color = 0xafacaf,
});
plus:add_component({ hash = plus_hash });

-- Minus Terminal
local minus_hash = Scene:add_component_def({
    name = "Minus",
    id = "core/minus",
    version = "0.1.0",
    code = [[
        local target_exposed = false;

        local circuit_graph = {};
        local circuit_objs = {};
        local circuit_resistances = {};
        local has_plus = false;
        local has_matching_plus = false;
        local paired_plus_id = nil;

        function on_save()
            -- we use table for forward compatibility if we add more data
            return {
                paired_plus_id = paired_plus_id,
            };
        end;

        function on_start(saved_data)
            if saved_data then
                if saved_data.paired_plus_id then
                    paired_plus_id = saved_data.paired_plus_id;
                end;
            end;

            if paired_plus_id == nil then
                self:set_color(0xe73e28);
            end;
        end;
        
        -- Get all connections
        function get_all_connections()
            local connections = {};
            
            -- Add touching components
            for _, obj in ipairs(self:get_touching()) do
                -- To ask each object if they're exposed, we send an event.
                target_exposed = false;
                obj:send_event("core/request_exposed", self_component);
                if target_exposed then
                    table.insert(connections, obj);
                end;
            end;
            
            -- Add direct connections
            for _, obj in ipairs(self:get_direct_connected()) do
                table.insert(connections, obj);
            end;
            
            return connections;
        end;
        
        -- Calculate power at each node based on resistance
        function calculate_power_levels(initial_power)
            local power_at_node = {};
            local visited = {};
            
            -- Breadth-first traversal for power calculation
            local function calculate_from_source(source_id, current_power, path)
                -- Terminal condition
                if visited[source_id] and power_at_node[source_id] >= current_power then
                    return;
                end
                
                -- Update power at this node
                power_at_node[source_id] = power_at_node[source_id] or 0;
                if current_power > power_at_node[source_id] then
                    power_at_node[source_id] = current_power;
                end
                
                -- Mark as visited
                visited[source_id] = true;
                
                -- Get the resistance of the CURRENT node (applies to outgoing connections)
                local source_resistance = circuit_resistances[source_id] or 0;
                local outgoing_power = math.max(0, current_power - source_resistance);
                
                -- Visit connected nodes with reduced power
                for _, target_id in ipairs(circuit_graph[source_id] or {}) do
                    -- Avoid loops in the path
                    if not path[target_id] then
                        -- Copy path and add this node
                        local new_path = {};
                        for k, v in pairs(path) do new_path[k] = v; end
                        new_path[target_id] = true;
                        
                        -- Calculate power for connected node - resistance already applied
                        calculate_from_source(target_id, outgoing_power, new_path);
                    end
                end
            end
            
            -- Start calculation from the minus terminal
            calculate_from_source(self.id, initial_power, {[self.id] = true});
            
            return power_at_node;
        end;
        
        function on_event(id, data)
            if id == "core/request_exposed" then
                data:send_event("core/report_exposed");
            elseif id == "core/report_exposed" then
                target_exposed = true;
            elseif id == "core/report_connections" then
                -- Add this component and its connections to our graph
                circuit_graph[data.id] = data.connections;
                
                -- Add object to our list of objects in the circuit
                circuit_objs[data.id] = data.object or Scene:get_object(data.id);
                
                -- Store resistance if provided
                if data.resistance then
                    circuit_resistances[data.id] = data.resistance;
                end
                
                -- Check if this is the plus terminal
                if data.is_plus then
                    has_plus = true;
                    -- Check if it's our paired plus terminal
                    if data.id == paired_plus_id then
                        has_matching_plus = true;
                    end;
                end;
            end;
        end;

        function on_step()            
            -- Add self to graph
            circuit_graph[self.id] = {};
            circuit_objs[self.id] = self;
            circuit_resistances[self.id] = 0;  -- No resistance for minus terminal
            
            -- Get all connections
            local connections = get_all_connections();
            for _, obj in ipairs(connections) do
                table.insert(circuit_graph[self.id], obj.id);
            end;
            
            -- Request connections from all connected components
            for _, obj in ipairs(connections) do
                obj:send_event("core/request_connections", {
                    source = self,
                    visited = {[self.id] = true}
                });
            end;
            
            -- If we found our matching plus terminal, activate the circuit
            if has_matching_plus then
                local initial_power = 40;
                
                -- Calculate power at each node
                local power_levels = calculate_power_levels(initial_power);
                
                -- Activate all components with calculated power
                for id, obj in pairs(circuit_objs) do
                    if obj and power_levels[id] then
                        obj:send_event("activate", {
                            power = power_levels[id],
                            points = {self:get_position()}, -- will be better later maybe, ideally actually figuring out power sources
                        });
                    end;
                end;
            end;

            -- Reset circuit data for this frame
            circuit_graph = {};
            circuit_objs = {};
            circuit_resistances = {};
            has_plus = false;
            has_matching_plus = false;
        end;
    ]],
});

local minus = Scene:add_box({
    name = "Minus",
    position = vec2(0, -0.5),
    size = vec2(0.32, 0.08),
    color = 0xafacaf,
});
minus:add_component({ hash = minus_hash, saved_data = { paired_plus_id = plus.id } });

local battery = Scene:add_box({
    size = vec2(0.4, 1),
    color = 0x1b191b
});

function bolt_to_battery(b)
    local p = battery:get_position();
    Scene:add_bolt({
        object_a = battery,
        object_b = b,
        local_anchor_a = battery:get_local_point(p),
        local_anchor_b = b:get_local_point(p),
    });
end;

bolt_to_battery(Scene:add_box({
    size = vec2(0.4, 0.6),
    position = vec2(0, -0.2),
    color = 0x8d898d,
    density = 0.05,
}));

bolt_to_battery(Scene:add_box({
    size = vec2(0.14, 0.03),
    position = vec2(0, -0.4),
    color = 0xdcd9dd,
    density = 0.05,
}));

bolt_to_battery(Scene:add_box({
    size = vec2(0.03, 0.12),
    position = vec2(0, 0.365),
    color = 0xdcd9dd,
    density = 0.05,
}));

bolt_to_battery(Scene:add_box({
    size = vec2(0.12, 0.03),
    position = vec2(0, 0.365),
    color = 0xdcd9dd,
    density = 0.05,
}));

bolt_to_battery(plus);
bolt_to_battery(minus);

-- lightbulb base is a conductor
local base = Scene:add_box({
    size = vec2(0.5, 0.12),
    position = vec2(0.5, 0.5),
    color = 0xafacaf,
});

local function set_property_value(component, key, value)
    local prop = component:get_property(key);
    prop.value = value;
    component:set_property(key, prop);
end;

local bulb_color = Color:hex(0xffb973);
bulb_color.a = 0.7;

local bulb = Scene:add_capsule({
    position = vec2(0.5, 0.775),
    color = Color:rgba(0,0,0,0),
    radius = 0.15,
    local_point_a = vec2(0, 0.115 - 0.05),
    local_point_b = vec2(0, -0.115 - 0.02),
});
local conductor = require ('core/components/conductor');
local bulb_component = bulb:add_component({ hash = conductor });
set_property_value(bulb_component, "exposed", false);
set_property_value(bulb_component, "resistance", 100);

function bolt_to_base(b)
    local p = base:get_position();
    Scene:add_bolt({
        object_a = base,
        object_b = b,
        local_anchor_a = base:get_local_point(p),
        local_anchor_b = b:get_local_point(p),
    });
end;

bolt_to_base(bulb);

local base_component = base:add_component({ hash = conductor });
set_property_value(base_component, "exposed", true);
set_property_value(base_component, "resistance", 0);

Scene:add_attachment({
    name = "Point Light",
    component = {
        name = "Point Light",
        version = "0.1.0",
        id = "core/electric_point_light",
        code = [==[
            local current_power = 0;
            local last_power = 1;

            function prop_changed()
                local radius = self:get_property("radius").value;
                local color = self:get_property("color").value;

                local lights = self:get_lights();
                lights[1].radius = radius;
                lights[1].color = color;

                self:set_lights(lights);

                local imgs = self:get_images();
                local h,s,v = color:get_hsv();
                s = math.min(s * 2, 0.5);
                local new_color = Color:hsva(h,s,v,math.max(0.5, current_power / 10));
                imgs[1].color = new_color;
                self:set_images(imgs);
            end;

            prop_changed();

            function on_event(id, data)
                if id == "activate" then
                    if data.power then
                        current_power = current_power + data.power;
                    else
                        current_power = current_power + 1;
                    end;
                elseif id == "property_changed" then
                    prop_changed();
                end;
            end;

            function on_step()
                -- If power difference is enough, we set light intensity, and our image alpha
                if math.abs(current_power - last_power) > 0.1 then
                    local lights = self:get_lights();
                    lights[1].intensity = current_power * 0.1;
                    self:set_lights(lights);

                    local imgs = self:get_images();
                    imgs[1].color.a = math.max(0.5, current_power / 10);
                    self:set_images(imgs);
                end;

                last_power = current_power;
                current_power = 0;
            end;
        ]==],
        properties = {
            {
                id = "radius",
                name = "Radius",
                input_type = "slider",
                default_value = 5 * 0.6,
                min_value = 0,
                max_value = 100,
            },
            {
                id = "color",
                name = "Color",
                input_type = "color",
                default_value = 0xffe3c8,
            },
        },
    },
    parent = bulb,
    local_position = vec2(0, 0),
    local_angle = 0,
    images = {
        {
            texture = require('core/assets/textures/point_light.png'),

            -- these have defaults, but we can specify
            scale = vec2(0.0007, 0.0007) * 1.2,
            color = bulb_color,
        },
    },
    lights = {
        {
            color = 0xffe3c8,
            intensity = 0,
            radius = 5 * 0.6,
        },
    },
    collider = { shape_type = "circle", radius = 0.1 * 0.6, }
});

local solenoid = Scene:add_box({
    size = vec2(2.0, 0.5),
    position = vec2(-0.5, 0.5),
});

local wire_color = require ('core/components/wire_color');
solenoid:add_component({
    hash = wire_color,
});
local solenoid_component = solenoid:add_component({ hash = conductor });
set_property_value(solenoid_component, "exposed", false);
set_property_value(solenoid_component, "resistance", 0);

local solenoid_start = Scene:add_box({
    size = vec2(0.05, 0.1),
});
Scene:add_bolt({
    object_a = solenoid,
    object_b = solenoid_start,
    local_anchor_a = vec2(-0.9, 0.3),
    local_anchor_b = vec2(0, 0),
});
local solenoid_end = Scene:add_box({
    size = vec2(0.05, 0.1),
});
Scene:add_bolt({
    object_a = solenoid,
    object_b = solenoid_end,
    local_anchor_a = vec2(0.9, -0.3),
    local_anchor_b = vec2(0, 0),
});

-- now we make custom component for solenoid. we will do get_objects_in_circle on each end (with self:get_local_point to get both solenoid ends)
-- then we can umm yeah

local solenoid_hash = Scene:add_component_def({
    name = "Solenoid",
    id = "core/solenoid",
    version = "0.1.0",
    code = [[
        local current_power = 0
        local MAGNETIC_FORCE = 0.001 -- adjust this constant to control strength
        local RADIUS = 2 -- detection radius, adjust as needed

        function on_event(id, data)
            if id == "activate" then
                current_power = current_power + (data.power or 1)
            end
        end

        function on_step()
            if current_power <= 0 then
                current_power = 0
                print("im");
                return
            end
            print("Holy toledo")

            -- Get top and bottom points of solenoid
            local top = self:get_world_point(vec2(0.8, 0))
            local bottom = self:get_world_point(vec2(-0.8, 0))

            -- Check for objects near both poles
            local top_objects = Scene:get_objects_in_circle({position = top, radius = RADIUS});
            local bottom_objects = Scene:get_objects_in_circle({position = bottom, radius = RADIUS});

            -- Apply forces to nearby objects
            for _, obj in ipairs(top_objects) do
                if obj.id ~= self.id then
                    local obj_pos = obj:get_position()
                    local dist = (top - obj_pos):length()
                    -- Inverse square law
                    local force = (MAGNETIC_FORCE * current_power) / (dist * dist)
                    -- Direction from pole to object
                    local dir = (obj_pos - top):normalize()
                    obj:apply_linear_impulse_to_center(dir * -force)
                end
                print("woo");
            end

            for _, obj in ipairs(bottom_objects) do
                if obj.id ~= self.id then
                    local obj_pos = obj:get_position()
                    local dist = (bottom - obj_pos):length()
                    local force = (MAGNETIC_FORCE * current_power) / (dist * dist)
                    local dir = (obj_pos - bottom):normalize()
                    obj:apply_linear_impulse_to_center(dir * force)
                end
            end

            -- Reset power for next frame
            current_power = 0
        end
    ]],
})

-- Add the component to the solenoid
solenoid:add_component({ hash = solenoid_hash });

-- now Wheels.
base = Scene:add_box({
    size = vec2(0.5, 0.12),
    position = vec2(0.5, 0.5),
    color = 0xafacaf,
});
base_component = base:add_component({ hash = conductor });
set_property_value(base_component, "resistance", 0);
set_property_value(base_component, "exposed", true);

local wheel_pos = base:get_world_point(vec2(0, -0.5));
local wheel = Scene:add_circle({
    color = 0x8d898d,
    radius = 0.25,
    position = wheel_pos,
});
local wheel_component = wheel:add_component({ hash = conductor });
set_property_value(wheel_component, "resistance", 100);
set_property_value(wheel_component, "exposed", false);

local hinge = require('core/lib/hinge.lua');
local atch = hinge({
    object_a = base,
    object_b = wheel,
    point = wheel_pos,
    motor_enabled = true,
});

-- now we make a new component for the attachment. it will do `self:set_property("motor_speed", current_power)` and `self:set_property("max_motor_torque", current_power * 10)`
local wheel_hash = Scene:add_component_def({
    name = "Wheel",
    id = "core/wheel",
    version = "0.1.0",
    code = [[
        local current_power = 0

        function on_event(id, data)
            if id == "activate" then
                current_power = current_power + (data.power or 1)
            end
        end

        function on_step()
            local prop = self:get_property("motor_speed");
            prop.value = current_power;
            self:set_property("motor_speed", prop);
            prop = self:get_property("max_motor_torque");
            prop.value = current_power * 10;
            self:set_property("max_motor_torque", prop);
            current_power = 0
        end
    ]],
});

atch:add_component({ hash = wheel_hash });

-- now, Input box. it has property for a keycode
-- and while the key is pressed, resistance 0. otherwise 100
local input = Scene:add_box({
    size = vec2(0.8, 0.5),
    position = vec2(-0.5, 0.5),
    color = 0xafacaf,
    name = "Input",
});
local input_component = input:add_component({ hash = conductor });
set_property_value(input_component, "resistance", 100);
set_property_value(input_component, "exposed", true);

-- now give it a dark box on it
local input_screen = Scene:add_box({
    size = vec2(0.6, 0.4),
    position = vec2(-0.5, 0.5),
    color = 0x020202, -- turns to 1b151b when on
});

Scene:add_bolt({
    object_a = input,
    object_b = input_screen,
    local_anchor_a = vec2(0, 0.08),
    local_anchor_b = vec2(0, 0),
});

local text = Scene:add_attachment({
    name = "Key",
    component = {
        name = "Key",
        version = "0.1.0",
        id = "core/input_text",
        code = "",
    },
    parent = input_screen,
    local_position = vec2(0, 0),
    local_angle = 0,
    --texts = {
    --    { content = input.text, color = 0xffffff, font_family = "this doest matter", font_size = 0.15, font_resolution = 200 }
    --},
    collider = { shape_type = "box", size = vec2(1, 1), }
});

local input_hash = Scene:add_component_def({
    name = "Input",
    id = "core/input",
    version = "0.1.0",
    properties = {
        {
            id = "key",
            name = "Key",
            input_type = "text",
            multi_line = false,
            default_value = "E",
        },
        {
            id = "hold",
            name = "Hold",
            input_type = "toggle",
            default_value = true,
        },
    },
    code = [[
        local conductor = nil;
        local screen = nil;
        local text = nil;

        function on_start(saved_data)
            if saved_data then
                if saved_data.conductor then
                    conductor = saved_data.conductor;
                end;
                if saved_data.screen then
                    screen = saved_data.screen;
                end;
                if saved_data.text then
                    text = saved_data.text;
                end;
            end;

            if (conductor == nil) or (screen == nil) or (text == nil) then
                self:set_color(0xe73e28);
            end
        end

        function on_save()
            return {
                conductor = conductor,
                screen = screen,
                text = text,
            };
        end;

        local current_power = 0;
        local was_activated = false;

        function on_event(id, data)
            if id == "activate" then
                current_power = current_power + (data.power or 1)
                was_activated = true;
            end
        end

        function on_step()
            if not was_activated then
                local prop = conductor:get_property("resistance");
                prop.value = 100;
                conductor:set_property("resistance", prop);
                screen:set_color(0x020202);
                if #(text:get_texts()) > 0 then
                    text:set_texts({}); -- clear text
                end;

                return;
            end;

            local prop = conductor:get_property("resistance");
            local pressed = false;

            if self_component:get_property("hold").value then
                pressed = Scene:get_host():key_pressed(self_component:get_property("key").value);
                prop.value = pressed and 0 or 100;
            else
                pressed = Scene:get_host():key_just_pressed(self_component:get_property("key").value);
                prop.value = pressed and 0 or 100;
            end
            conductor:set_property("resistance", prop);

            screen:set_color(0x1b151b);
            local off_color = Color:hex(0xffffff);
            off_color.a = 0.2;
            text:set_texts({{ content = self_component:get_property("key").value, color = pressed and Color:hex(0xffffff) or off_color, font_size = 0.15, font_resolution = 200 }});

            current_power = 0;
            was_activated = false;
        end
    ]],
});

input:add_component({
    hash = input_hash, 
    saved_data = {
        conductor = input_component,
        screen = input_screen,
        text = text,
    }
});