local target_exposed = false;

local circuit_graph = {};
local circuit_objs = {};
local circuit_resistances = {};

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
        end;
    elseif id == "core/free_energy_toggle" then
        self_component:destroy();
        return true; -- Tell it this got removed. Important so it knows not to add this component
    end;
end;

function on_step()
    -- Reset circuit data for this frame
    circuit_graph = {};
    circuit_objs = {};
    circuit_resistances = {};
    
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
    
    local initial_power = self_component:get_property("power").value;
    
    -- Calculate power at each node
    local power_levels = calculate_power_levels(initial_power);
    
    -- Activate all components with calculated power
    for id, obj in pairs(circuit_objs) do
        if obj and power_levels[id] then
            obj:send_event("activate", {
                power = power_levels[id],
                points = {self:get_position()} -- needs be changed later
            });
        end;
    end;
end;
