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
        local paired_plus = nil;

        function on_save()
            -- we use table for forward compatibility if we add more data
            return {
                paired_plus = paired_plus,
            };
        end;

        function on_start(saved_data)
            if saved_data then
                if saved_data.paired_plus then
                    paired_plus = saved_data.paired_plus;
                end;
            end;

            if paired_plus == nil then
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
                    if data.id == paired_plus.id then
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
minus:add_component({ hash = minus_hash, saved_data = { paired_plus = plus } });

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










local function vital()
local extra = 0.048;
    -- now, Input box. it has property for a keycode
    -- and while the key is pressed, resistance 0. otherwise 100
    local input = Scene:add_box({
        size = vec2(0.8, 0.5 + extra),
        position = vec2(-0.5, 0.5),
        color = 0xafacaf,
        name = "Vitality Monitor",
    });

    Scene:add_bolt({
        object_a = input,
        object_b = Scene:add_box({
            size = vec2(0.8, 0.436 - 0.004),
            position = vec2(-0.5, 0.5),
            color = 0xdcd9dd, -- turns to 1b151b when on
            collision_layers = {},
            density = 0.01,
        }),
        local_anchor_a = vec2(0, 0.08 - (extra/2) + (0.004 / 2)),
        local_anchor_b = vec2(0, 0),
    });

    -- now give it a dark box on it
    local input_screen = Scene:add_box({
        size = vec2(0.6, 0.4),
        position = vec2(-0.5, 0.5),
        color = 0x1b151b, -- turns to 1b151b when on
        collision_layers = {},
        density = 0.01,
    });


    Scene:add_bolt({
        object_a = input,
        object_b = input_screen,
        local_anchor_a = vec2(0, 0.1 - (extra/2) - 0.002),
        local_anchor_b = vec2(0, 0),
    });


    Scene:add_attachment({
        name = "Text",
        component = {
            name = "Text",
            version = "0.1.0",
            id = "blank",
            code = "",
        },
        parent = input,
        local_position = vec2(-0.16, -0.19 - (extra/2)),
        local_angle = 0,
        texts = {
            { content = "Vitality Monitor", color = Color:rgba(0,0,0,0.7), font_size = 0.06, font_resolution = 800 }
        },
        collider = { shape_type = "box", size = vec2(1, 1), }
    });


    local text = Scene:add_attachment({
        name = "Vitality Text",
        component = {
            name = "Vitality Text",
            version = "0.1.0",
            id = "blank",
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
        name = "Vitality Monitor",
        id = "core/vitality_monitor",
        version = "0.1.0",
        icon = require("core/assets/textures/vitality.png"),
        code = [[
            local text = nil;
            local vitality = nil;
            local last_vitality = nil

            function on_event(id, data)
                if id == "core/vitals" then
                    vitality = data.vitality;
                end;
            end;

            function on_start(saved_data)
                if saved_data then
                    if saved_data.text then
                        text = saved_data.text;
                    end;
                end;
            end

            function on_save()
                return {
                    text = text,
                };
            end;

            function scan_connections(start_node, visited, is_start)
                -- Initialize visited table if not provided
                visited = visited or {}
                
                -- By default, consider this the start node if not specified
                if is_start == nil then
                    is_start = true
                end
                
                -- Create a results table to store all connections found
                local results = {}
                
                -- If we've already visited this node, return empty results to avoid loops
                if visited[start_node.id] then
                    return results
                end
                
                -- Mark current node as visited
                visited[start_node.id] = true
                
                -- Get direct connections
                local direct_connections = start_node:get_direct_connected()
                
                -- If this is the start node, also get touching connections
                if is_start then
                    local touching_connections = start_node:get_touching()
                    
                    -- Add touching connections to direct_connections, avoiding duplicates
                    for _, connection in ipairs(touching_connections) do
                        local is_duplicate = false
                        
                        -- Check if this connection is already in direct_connections
                        for _, direct_connection in ipairs(direct_connections) do
                            if direct_connection.id == connection.id then
                                is_duplicate = true
                                break
                            end
                        end
                        
                        -- If not a duplicate, add to direct_connections
                        if not is_duplicate then
                            table.insert(direct_connections, connection)
                        end
                    end
                end
                
                -- Add these connections to our results
                for _, connection in ipairs(direct_connections) do
                    results[#results + 1] = connection
                    
                    -- Recursively scan each connection's connections (marking them as not start nodes)
                    local sub_connections = scan_connections(connection, visited, false)
                    
                    -- Add all sub-connections to our results
                    for _, sub_connection in ipairs(sub_connections) do
                        results[#results + 1] = sub_connection
                    end
                end
                
                return results
            end

            function on_step()
                local t = scan_connections(self);

                for i=1,#t do
                    vitality = nil;
                    t[i]:send_event("core/request_vitals", self_component);
                    if vitality ~= nil then
                        if (last_vitality == nil) or (math.abs(last_vitality - vitality) > 0.001) then
                            text:set_texts({{ content = tostring(math.ceil(vitality * 100)) .. "%", color = 0xffffff, font_size = 0.05, font_resolution = 800 }});
                            last_vitality = vitality;
                        end;
                        return;
                    end;
                end;

                if last_vitality ~= nil then
                    text:set_texts({{ content = "No life detected", color = 0xf74e4e, font_size = 0.05, font_resolution = 800 }});
                end;

                last_vitality = nil;
            end
        ]],
    });

    input:add_component({
        hash = input_hash, 
        saved_data = {
            text = text,
        }
    });
end;
vital();

local function powery()

local extra = 0.048;
    -- now, Input box. it has property for a keycode
    -- and while the key is pressed, resistance 0. otherwise 100
    local input = Scene:add_box({
        size = vec2(0.8, 0.5 + extra),
        position = vec2(-0.5, 0.5),
        color = 0xafacaf,
        name = "Input",
    });

local function set_property_value(component, key, value)
    local prop = component:get_property(key);
    prop.value = value;
    component:set_property(key, prop);
end;

    local conductor = require ('core/components/conductor');
    local conductor_c = input:add_component({ hash = conductor });
    set_property_value(conductor_c, "exposed", true);
    set_property_value(conductor_c, "resistance", 100);

local light_part = Scene:add_box({
            size = vec2(0.8, 0.436 - 0.004),
            position = vec2(-0.5, 0.5),
            color = 0xdcd9dd, -- turns to 1b151b when on
            collision_layers = {},
            density = 0.01,
        });
local c = light_part:add_component({ hash = conductor });
set_property_value(c, "resistance", 100);
set_property_value(c, "exposed", true);
    Scene:add_bolt({
        object_a = input,
        object_b = light_part,
        local_anchor_a = vec2(0, 0.08 - (extra/2) + (0.004 / 2)),
        local_anchor_b = vec2(0, 0),
    });

    -- now give it a dark box on it
    local input_screen = Scene:add_box({
        size = vec2(0.6, 0.4),
        position = vec2(-0.5, 0.5),
        color = 0x020202, -- turns to 1b151b when on
        collision_layers = {},
        density = 0.01,
    });
local c = input_screen:add_component({ hash = conductor });
set_property_value(c, "resistance", 100);
set_property_value(c, "exposed", true);

    Scene:add_bolt({
        object_a = input,
        object_b = input_screen,
        local_anchor_a = vec2(0, 0.1 - (extra/2) - 0.002),
        local_anchor_b = vec2(0, 0),
    });


    Scene:add_attachment({
        name = "Text",
        component = {
            name = "Text",
            version = "0.1.0",
            id = "blank",
            code = "",
        },
        parent = input,
        local_position = vec2(-0.16, -0.19 - (extra/2)),
        local_angle = 0,
        texts = {
            { content = "Power Monitor", color = Color:rgba(0,0,0,0.7), font_size = 0.06, font_resolution = 800 }
        },
        collider = { shape_type = "box", size = vec2(1, 1), }
    });


    local text = Scene:add_attachment({
        name = "Power Text",
        component = {
            name = "Power Text",
            version = "0.1.0",
            id = "blank",
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
        name = "Power Monitor",
        id = "core/power_monitor",
        version = "0.1.0",
        code = [[
            local text = nil;
            local screen = nil;
            local current_power = 0;
            local last_power = 1;

            function on_event(id, data)
                if id == "activate" then
                    current_power = current_power + (data.power or 1);
                end;
            end;

            function on_start(saved_data)
                if saved_data then
                    if saved_data.text then
                        text = saved_data.text;
                    end;
                    if saved_data.screen then
                        screen = saved_data.screen;
                    end;
                end;

                if (screen == nil) or (text == nil) then
                    self:set_color(0xe73e28);
                end
            end

            function on_save()
                return {
                    text = text,
                    screen = screen,
                };
            end;

            function on_step()
                if current_power > 0.001 then
                    if (last_power == nil) or (math.abs(last_power - current_power) > 0.001) then
                        text:set_texts({{ content = string.format("%.1f", current_power) .. " W", color = 0xffffff, font_size = 0.05, font_resolution = 800 }});
                        screen:set_color(0x1b151b);
                        last_power = current_power;
                    end;
                else
                    if last_power ~= nil then
                        --text:set_texts({{ content = "0 W", color = 0xf74e4e, font_size = 0.05, font_resolution = 800 }});
                        text:set_texts({});
                        screen:set_color(0x020202);
                    end;

                    last_power = nil;
                end;
                current_power = 0;
            end
        ]],
    });

    input:add_component({
        hash = input_hash, 
        saved_data = {
            text = text,
            screen = input_screen,
        }
    });
end;
powery();


-- Define the center position of the triangle
local center = vec2(0, 0)

-- Define the radius (distance from center to any vertex)
local radius = 0.15

-- Calculate the three points of an equilateral triangle
local point1 = vec2(center.x + radius * math.cos(0), center.y + radius * math.sin(0))
local point2 = vec2(center.x + radius * math.cos(2*math.pi/3), center.y + radius * math.sin(2*math.pi/3))
local point3 = vec2(center.x + radius * math.cos(4*math.pi/3), center.y + radius * math.sin(4*math.pi/3))
local coloro = Color:hex(0xff4760);
coloro.a = 0.7;

local tringle = Scene:add_polygon({
    position = vec2(-2, 0),
    points = {
        point1,point2,point3,
    },
    color = coloro,
name = "Crystal",
});

local crystal_component = Scene:add_component_def({
    name = "Crystal",
    id = "core/crystal",
    version = "0.1.0",
    properties = {
        {
            id = "energy",
            name = "Energy",
            input_type = "slider",
            default_value = 1,
            min_value = 0,
            max_value = 1,
        }
    },
    code = [[
        local vitality = nil;
        local max = Color:hex(0xff4760);
        max.a = 0.7;
        local min = Color:hex(0xd8cacc);
        min.a = 0.3;

        function on_event(id, data)
            if id == "core/vitals" then
                vitality = data.vitality;
            elseif id == "property_changed" then
                local p = self_component:get_property("energy");
                self:set_color(Color:mix(min, max, p.value));
            end;
        end;

        function scan_connections(start_node, visited, is_start)
            -- Initialize visited table if not provided
            visited = visited or {}
            
            -- By default, consider this the start node if not specified
            if is_start == nil then
                is_start = true
            end
            
            -- Create a results table to store all connections found
            local results = {}
            
            -- If we've already visited this node, return empty results to avoid loops
            if visited[start_node.id] then
                return results
            end
            
            -- Mark current node as visited
            visited[start_node.id] = true
            
            -- Get direct connections
            local direct_connections = start_node:get_direct_connected()
            
            -- If this is the start node, also get touching connections
            if is_start then
                local touching_connections = start_node:get_touching()
                
                -- Add touching connections to direct_connections, avoiding duplicates
                for _, connection in ipairs(touching_connections) do
                    local is_duplicate = false
                    
                    -- Check if this connection is already in direct_connections
                    for _, direct_connection in ipairs(direct_connections) do
                        if direct_connection.id == connection.id then
                            is_duplicate = true
                            break
                        end
                    end
                    
                    -- If not a duplicate, add to direct_connections
                    if not is_duplicate then
                        table.insert(direct_connections, connection)
                    end
                end
            end
            
            -- Add these connections to our results
            for _, connection in ipairs(direct_connections) do
                results[#results + 1] = connection
                
                -- Recursively scan each connection's connections (marking them as not start nodes)
                local sub_connections = scan_connections(connection, visited, false)
                
                -- Add all sub-connections to our results
                for _, sub_connection in ipairs(sub_connections) do
                    results[#results + 1] = sub_connection
                end
            end
            
            return results
        end

        function on_step()
            local t = scan_connections(self);

            for i=1,#t do
                vitality = nil;
                t[i]:send_event("core/request_vitals", self_component);
                if vitality ~= nil then
                    local p = self_component:get_property("energy");
                    t[i]:send_event("heal", {
                        amount = math.min(1 / 64, p.value) * 1.1,
                    });
                    p.value = math.max(0, p.value - 1 / 64);
                    self_component:set_property("energy", p);
                    self:set_color(Color:mix(min, max, p.value));
                end;
            end;
        end;
    ]],
});
tringle:add_component({hash = crystal_component})

















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
    position = vec2(-5, 0),
});
Scene:add_bolt({
    object_a = solenoid,
    object_b = solenoid_start,
    local_anchor_a = vec2(-0.9, 0.3),
    local_anchor_b = vec2(0, 0),
});
local solenoid_end = Scene:add_box({
    size = vec2(0.05, 0.1),
    position = vec2(-5, 0)
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
                --print("im");
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

local box_behind = Scene:add_box({
    color = 0x8d898d,
    position = vec2(0.5, 0.3),
    size = vec2(0.1, 0.48),
    collision_layers = {},
});
-- now Wheels.
base = Scene:add_box({
    size = vec2(0.5, 0.12),
    position = vec2(0.5, 0.5),
    color = 0xafacaf,
});

bolt_to_base(box_behind)

-- Note: removed conductor component from base

local wheel_pos = base:get_world_point(vec2(0, -0.38));
local wheel = Scene:add_circle({
    color = 0x1b191b,
    radius = 0.25,
    position = wheel_pos,
    density = 2,
    friction = 1,
});

local wheel_hinge_c = Color:hex(0xf8f2ff);
wheel_hinge_c.a = 0.2;

local hinge = require('core/lib/hinge.lua');
local atch = hinge({
    object_a = base,
    object_b = wheel,
    point = wheel_pos,
    motor_enabled = true,
    color = wheel_hinge_c
});

-- Updated wheel component that can handle direction
local wheel_hash = Scene:add_component_def({
    name = "Wheel",
    id = "core/wheel",
    version = "0.1.0",
    code = [[
        local current_power = 0

        function on_event(id, data)
            if id == "activate" then
                -- Regular activation means positive direction
                current_power = current_power + (data.power or 1)
            elseif id == "activate_reverse" then
                -- Reverse activation means negative direction
                current_power = current_power - (data.power or 1)
            end
        end

        function on_step()
            local prop = self:get_property("motor_speed");
            prop.value = current_power;
            self:set_property("motor_speed", prop);
            
            prop = self:get_property("max_motor_torque");
            -- Use absolute value for torque strength
            prop.value = math.max(2, math.abs(current_power) * 0.8);
            self:set_property("max_motor_torque", prop);
            
            current_power = 0
        end
    ]],
});

atch:add_component({ hash = wheel_hash });

-- Create left control box (blue)
local left_box = Scene:add_box({
    size = vec2(0.06, 0.08),
    position = vec2(0.27, 0.5),  -- Left side of base
    color = 0x828cba,  -- Blue
});

-- Create right control box (red)
local right_box = Scene:add_box({
    size = vec2(0.06, 0.08),
    position = vec2(0.73, 0.5),  -- Right side of base
    color = 0xba7070,  -- Red
});

-- Bolt the control boxes to the base
bolt_to_base(left_box);
bolt_to_base(right_box);

-- Add conductor components to both boxes
local left_conductor = left_box:add_component({ hash = conductor });
set_property_value(left_conductor, "resistance", 0);
set_property_value(left_conductor, "exposed", true);

local right_conductor = right_box:add_component({ hash = conductor });
set_property_value(right_conductor, "resistance", 0);
set_property_value(right_conductor, "exposed", true);

-- Create the wheel control component
local control_hash = Scene:add_component_def({
    name = "Wheel Control",
    id = "core/wheel_control",
    version = "0.1.0",
    code = [[
        local wheel = nil
        local is_reverse = false

        function on_start(saved_data)
            if saved_data then
                if saved_data.wheel then
                    wheel = saved_data.wheel
                end
                if saved_data.is_reverse then
                    is_reverse = saved_data.is_reverse
                end
            end
        end

        function on_save()
            return {
                wheel = wheel,
                is_reverse = is_reverse
            }
        end

        function on_event(id, data)
            if id == "activate" and wheel then
                if is_reverse then
                    wheel:send_event("activate_reverse", data)
                else
                    wheel:send_event("activate", data)
                end
            end
        end
    ]],
});

-- Add the control component to the left box (forward direction)
left_box:add_component({
    hash = control_hash,
    saved_data = {
        wheel = atch,
        is_reverse = true
    }
});

-- Add the control component to the right box (reverse direction)
right_box:add_component({
    hash = control_hash,
    saved_data = {
        wheel = atch,
        is_reverse = false
    }
});

-- now, Input box. it has property for a keycode
-- and while the key is pressed, resistance 0. otherwise 100
local extra = 0.048;
    -- now, Input box. it has property for a keycode
    -- and while the key is pressed, resistance 0. otherwise 100
    local input = Scene:add_box({
        size = vec2(0.6, 0.5 + extra),
        position = vec2(-0.5, 0.5),
        color = 0xafacaf,
        name = "Key Input",
    });
local input_component = input:add_component({ hash = conductor });
set_property_value(input_component, "resistance", 100);
set_property_value(input_component, "exposed", true);

local light_part = Scene:add_box({
            size = vec2(0.6, 0.436 - 0.004),
            position = vec2(-0.5, 0.5),
            color = 0xdcd9dd, -- turns to 1b151b when on
            collision_layers = {},
            density = 0.01,
name = "Key Input"
        });
local c1 = light_part:add_component({ hash = conductor });
set_property_value(c1, "resistance", 100);
set_property_value(c1, "exposed", true);
    Scene:add_bolt({
        object_a = input,
        object_b = light_part,
        local_anchor_a = vec2(0, 0.08 - (extra/2) + (0.004 / 2)),
        local_anchor_b = vec2(0, 0),
    });

    -- now give it a dark box on it
    local input_screen = Scene:add_box({
        size = vec2(0.48, 0.4),
        position = vec2(-0.5, 0.5),
        color = 0x020202, -- turns to 1b151b when on
        collision_layers = {},
        density = 0.01,
name = "Screen"
    });

local c2 = input_screen:add_component({ hash = conductor });
set_property_value(c2, "resistance", 100);
set_property_value(c2, "exposed", true);


    Scene:add_bolt({
        object_a = input,
        object_b = input_screen,
        local_anchor_a = vec2(0, 0.1 - (extra/2) - 0.002),
        local_anchor_b = vec2(0, 0),
    }); 


Scene:add_attachment({
        name = "Text",
        component = {
            name = "Text",
            version = "0.1.0",
            id = "blank",
            code = "",
        },
        parent = input,
        local_position = vec2(-0.14, -0.19 - (extra/2)),
        local_angle = 0,
        texts = {
            { content = "Key Input", color = Color:rgba(0,0,0,0.7), font_size = 0.06, font_resolution = 800 }
        },
        collider = { shape_type = "box", size = vec2(1, 1), }
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
        local conductors = nil;
        local screen = nil;
        local text = nil;

        function on_start(saved_data)
            if saved_data then
                if saved_data.conductors then
                    conductors = saved_data.conductors;
                end;
                if saved_data.screen then
                    screen = saved_data.screen;
                end;
                if saved_data.text then
                    text = saved_data.text;
                end;
            end;

            if (conductors == nil) or (#conductors == 0) or (screen == nil) or (text == nil) then
                self:set_color(0xe73e28);
            end
        end

        function on_save()
            return {
                conductors = conductors,
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
                local prop = conductors[1]:get_property("resistance");
                prop.value = 100;
                for i=1,#conductors do
                    conductors[i]:set_property("resistance", prop);
                end;
                screen:set_color(0x020202);
                if #(text:get_texts()) > 0 then
                    text:set_texts({}); -- clear text
                end;

                return;
            end;

            local prop = conductors[1]:get_property("resistance");
            local pressed = false;

            if self_component:get_property("hold").value then
                pressed = Scene:get_host():key_pressed(self_component:get_property("key").value);
                prop.value = pressed and 0 or 100;
            else
                pressed = Scene:get_host():key_just_pressed(self_component:get_property("key").value);
                prop.value = pressed and 0 or 100;
            end
            for i=1,#conductors do
                conductors[i]:set_property("resistance", prop);
            end;

            screen:set_color(0x1b151b);
            local off_color = Color:hex(0xffffff);
            off_color.a = 0.1;
            text:set_texts({{ content = self_component:get_property("key").value, color = pressed and Color:hex(0xffffff) or off_color, font_size = 0.15, font_resolution = 200 }});

            current_power = 0;
            was_activated = false;
        end
    ]],
});

input:add_component({
    hash = input_hash, 
    saved_data = {
        conductors = {input_component, c1, c2},
        screen = input_screen,
        text = text,
    }
});























local function xray()
local extra = 0.048;
local scanner_height = (0.5 + extra) - 0.436 - 0.004;
    -- now, Input box. it has property for a keycode
    -- and while the key is pressed, resistance 0. otherwise 100
    local input = Scene:add_box({
        size = vec2(0.8 * 2.5, scanner_height),
        position = vec2(-10, 0.5),
        color = 0xafacaf,
        name = "X-Ray Scanner",
    });

    local tray = Scene:add_box({
        size = vec2(0.5, scanner_height),
        position = vec2(-8.95, 0.5),
        color = 0xdcd9dd,
        name = "X-Ray Print Tray",
    });

    local color = Color:hex(0xdcd9dd);
    color.a = 0.1;

    local tray_sensor = Scene:add_box({
        size = vec2(0.5, 0.5),
        position = vec2(-8.95, 0.5),
        color = color,
        name = "X-Ray Print Area",
        is_sensor = true,
    });

    Scene:add_attachment({
        name = "Text",
        component = {
            name = "Text",
            version = "0.1.0",
            id = "blank",
            code = "",
        },
        parent = tray,
        local_position = vec2(0, 0),
        local_angle = 0,
        texts = {
            { content = "Print Tray", color = Color:rgba(0,0,0,0.8), font_size = 0.06, font_resolution = 800 }
        },
        collider = { shape_type = "box", size = vec2(1, 1), }
    });

    Scene:add_bolt({
        object_a = input,
        object_b = tray,
        local_anchor_a = vec2(0, 0),
        local_anchor_b = vec2(-1.25, 0),
    });

    Scene:add_bolt({
        object_a = tray_sensor,
        object_b = tray,
        local_anchor_a = vec2(0, 0),
        local_anchor_b = vec2(0, 0.25+scanner_height/2),
    });

    local button = Scene:add_box({
        size = vec2(0.07, 0.2),
        position = vec2(-10-1-0.07*4, 0.5 - scanner_height/2 + 0.1),
        color = 0xe98484,
        name = "X-Ray Button",
    });

    local button_hinge = hinge({
        object_a = button,
        object_b = input,
        point = button:get_world_point(vec2(0.07/2, -0.1)),
        size = 0.1,
        collide_connected = true,
    });

    local start_p = button:get_world_point(vec2(0.07/2, 0.08));
    local end_p = button:get_world_point(vec2(((0.07/2)+0.1), 0.08));

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
                    default_value = (end_p - start_p):magnitude(),
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
        parent = button,
        local_position = vec2(0.07/2, 0.08),
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
        object_a = button,
        object_b = input,
        local_anchor_a = vec2(0.07/2, 0.08),
        local_anchor_b = input:get_local_point(button:get_world_point(vec2(((0.07/2)+0.1), 0.08))),
        attachment = atch,
        stiffness = 20,
        damping = 0.1,
        rest_length = (end_p - start_p):magnitude(),
    });

    atch:send_event("core/spring/init", spring);

    local color = Color:hex(0xdcd9dd);
    color.a = 0.2;

    local sensor = Scene:add_box({
        size = vec2(2, 2),
        position = vec2(-10, 0.5),
        color = color, -- turns to 1b151b when on
        --collision_layers = {},
        density = 0.01,
        is_sensor = true,
        name = "X-Ray Scan Area"
    });

    Scene:add_bolt({
        object_a = input,
        object_b = sensor,
        local_anchor_a = vec2(0, scanner_height/2 + 1),
        local_anchor_b = vec2(0, 0),
    });

    -- now give it a dark box on it
    local input_screen = Scene:add_box({
        size = vec2(0.6 * 2, scanner_height),
        position = vec2(-10, 0.5),
        color = 0x1b151b, -- turns to 1b151b when on
        collision_layers = {},
        density = 0.01,
        name = "X-Ray Screen"
    });


    Scene:add_bolt({
        object_a = input,
        object_b = input_screen,
        local_anchor_a = vec2(0.2, 0),
        local_anchor_b = vec2(0, 0),
    });


    Scene:add_attachment({
        name = "Text",
        parent = input,
        local_position = vec2(-0.16 * 4.7, 0),
        local_angle = 0,
        texts = {
            { content = "X-Ray Scanner", color = Color:rgba(0,0,0,0.7), font_size = 0.06, font_resolution = 800 }
        },
        collider = { shape_type = "box", size = vec2(1, 1), }
    });


    local text = Scene:add_attachment({
        name = "X-Ray Text",
        parent = input_screen,
        local_position = vec2(0, 0),
        local_angle = 0,
        texts = {
            { content = "Place a square on the print tray.", color = 0xffffff, font_size = 0.05, font_resolution = 800 }
        },
        collider = { shape_type = "box", size = vec2(1, 1), }
    });

    local input_hash = Scene:add_component_def({
        name = "X-Ray Scanner",
        id = "core/xray_xcanner",
        version = "0.1.0",
        icon = require("core/assets/textures/xray.png"),
        code = [[
            local text = nil;
            local sensor = nil;
            local tray_sensor = nil;
            local spring = nil;

            function on_start(saved_data)
                if saved_data then
                    if saved_data.text then
                        text = saved_data.text;
                        sensor = saved_data.sensor;
                        tray_sensor = saved_data.tray_sensor;
                        spring = saved_data.spring;
                    end;
                end;
            end;

            function on_save()
                return {
                    text = text,
                    tray_sensor = tray_sensor,
                    sensor = sensor,
                    spring = spring,
                };
            end;

            function on_step()
                local tray = tray_sensor:get_sensed();
                local paper = nil;

                for i=1,#tray do
                    if (not string.find(tray[i]:get_name() or "", "X-Ray", 1, true)) and (tray[i]:get_shape().shape_type == "box") and (tray[i]:get_body_type() == BodyType.Dynamic) then
                        paper = tray[i];
                        break;
                    end;
                end;

                if paper == nil then
                    text:set_texts({{ content = "Place a square box on the print tray.", color = 0xffffff, font_size = 0.05, font_resolution = 800 }});
                    return;
                end;

                local skeletons = {};
                local scan = sensor:get_sensed();

                for i=1,#scan do
                    if (not string.find(scan[i]:get_name() or "", "X-Ray", 1, true)) then
                        local atchs = scan[i]:get_attachments();
                        for i=1,#atchs do
                            if string.find(atchs[i]:get_name() or "", "Skeleton", 1, true) then
                                table.insert(skeletons, atchs[i]);
                            end;
                        end;
                    end;
                end;

                if #skeletons == 0 then
                    text:set_texts({{ content = "Position patient in scan area.", color = 0xffffff, font_size = 0.05, font_resolution = 800 }});
                    return;
                end;

                if spring:get_current_length() < (spring:get_rest_length() / 2) then
                    paper:set_name("Printed X-Ray Image");
                    local h,s,v = paper:get_color():get_hsv();
                    v = math.min(v, 0.2);
                    paper:set_color(Color:hsva(h,s,v,paper:get_color().a));

                    -- Get sizes for scaling calculations
                    local paper_shape_size = paper:get_shape().size;
                    local sensor_shape_size = sensor:get_shape().size;

                    -- Basic validation for sizes
                    if not paper_shape_size or not sensor_shape_size or paper_shape_size.x <= 0 or paper_shape_size.y <= 0 then
                        text:set_texts({{ content = "Error: Invalid paper/sensor size.", color = 0xff0000, font_size = 0.05, font_resolution = 800 }});
                        return; -- Can't proceed
                    end

                    local paper_min_dim = math.min(paper_shape_size.x, paper_shape_size.y);
                    local sensor_min_dim = math.min(sensor_shape_size.x, sensor_shape_size.y);

                    local multiplier = 1.0; -- Default scale
                    if sensor_min_dim > 0.0001 then -- Avoid division by zero or extreme scaling if sensor is tiny
                        multiplier = paper_min_dim / sensor_min_dim;
                    else
                        -- Sensor is effectively zero-sized in one dimension, resulting images would be tiny or calculations problematic.
                        -- You could opt to show an error or proceed with multiplier = 0 or 1.
                        -- For now, let's assume this means an error or images will be invisible.
                        -- If you want to show an error, uncomment the next two lines:
                        -- text:set_texts({{ content = "Error: Sensor scan area too small.", color = 0xff0000, font_size = 0.05, font_resolution = 800 }});
                        -- return;
                        multiplier = 0; -- Effectively makes images invisible if sensor is too small
                    end;

                    for i=1, #skeletons do
                        local skeleton_attach = skeletons[i];

                        -- Get skeleton attachment's world position and angle
                        local skel_world_pos = skeleton_attach:get_position();
                        local skel_world_angle = skeleton_attach:get_angle();

                        -- 1. Transform skeleton's world position to sensor's local space.
                        -- This gives the skeleton's position relative to the sensor's center, oriented along sensor's axes.
                        local skel_pos_in_sensor_local = sensor:get_local_point(skel_world_pos);

                        -- 2. Calculate skeleton's angle relative to the sensor's world angle.
                        local skel_angle_rel_sensor = skel_world_angle - sensor:get_angle();

                        -- 3. Map to paper's local space:
                        -- The local_position for the new attachment on paper is the scaled sensor-local position.
                        local new_attach_local_pos = skel_pos_in_sensor_local * multiplier;

                        -- The local_angle for the new attachment on paper is its angle relative to the sensor.
                        local new_attach_local_angle = skel_angle_rel_sensor;

                        -- 4. Process images from the skeleton attachment
                        local original_images = skeleton_attach:get_images();
                        local processed_images = {};

                        if original_images then
                            for img_idx=1, #original_images do
                                local original_img = original_images[img_idx];
                                
                                -- Create a new image table with modified properties
                                local new_img = original_img;
                                new_img.color = Color:rgb(1,1,1);
                                new_img.offset = original_img.offset * multiplier;
                                new_img.scale = original_img.scale * multiplier;
                                new_img.angle = original_img.angle;
                                
                                table.insert(processed_images, new_img);
                            end;
                        end;

                        -- 5. Add the new, transformed attachment to the paper
                        -- Only add if there are actual images to display
                        if #processed_images > 0 then
                            Scene:add_attachment({
                                parent = paper,
                                local_position = new_attach_local_pos,
                                local_angle = new_attach_local_angle,
                                images = processed_images,
                                name = "XRayImageContent_" .. i -- Optional: for debugging
                            });
                        end;
                    end;

                    -- Update text to show printing is done
                    text:set_texts({{ content = "X-Ray printed successfully!", color = 0xa1fdb2, font_size = 0.05, font_resolution = 800 }});
                else
                    text:set_texts({{ content = "Ready. Press the red button.", color = 0xa1fdb2, font_size = 0.05, font_resolution = 800 }});
                end;
            end
        ]],
    });

    input:add_component({
        hash = input_hash, 
        saved_data = {
            text = text,
            tray_sensor = tray_sensor,
            sensor = sensor,
            spring = spring,
        }
    });
end;
xray();


-- Fans
local make_fan = require('core/scripts/everything/fans/make_fan.lua');
make_fan()


local simulon = require('core/lib/simulon.lua');

simulon({position = vec2(-10, 2)})
simulon({color = Color:hex(0x9567bd)})
