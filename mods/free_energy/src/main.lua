function on_update()
    if self:key_just_pressed("F") then
        RemoteScene:run({
            input = self:pointer_pos(),
            code = [[
                local hover_objects = Scene:get_objects_in_circle({
                    position = input,
                    radius = 0,
                });

                table.sort(hover_objects, function(a, b)
                    return a:get_z_index() > b:get_z_index()
                end);

                if #hover_objects > 0 then
                    local hash = Scene:add_component_def({
                        id = "core/single_use_free_energy_detector",
                        name = "Single Use Free Energy Detector",
                        version = "0.1.0",
                        
                        code = [==[
                            local target_exposed = false;

                            local circuit_graph = {};
                            local circuit_objs = {};

                            circuit_graph[self.id] = {};
                            circuit_objs[self.id] = self;

                            function on_event(id, data)
                                if id == "core/report_exposed" then
                                    target_exposed = true;
                                elseif id == "core/report_connections" then
                                    -- Add this component and its connections to our graph
                                    circuit_graph[data.id] = data.connections;

                                    -- Add object to our list of objects in the circuit
                                    circuit_objs[data.id] = data.object or Scene:get_object(data.id);
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

                            function on_start()
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

                                local removed = false;

                                for id, obj in pairs(circuit_objs) do
                                    local c = obj:get_components();
                                    for i=1,#c do
                                        local this_removed = c[i]:send_event("core/free_energy_toggle");
                                        if this_removed then
                                            removed = true;
                                            -- we could break here, imo its best to remove them all
                                        end;
                                    end;
                                end;

                                if not removed then
                                    for id, obj in pairs(circuit_objs) do
                                        obj:add_component({ hash = require("core/components/free_energy") });
                                        break;
                                    end;
                                end;

                                self_component:destroy();
                            end;
                        ]==],
                    });
                    
                    hover_objects[1]:add_component({ hash = hash });
                end;
            ]],
        });
    end;
end;
