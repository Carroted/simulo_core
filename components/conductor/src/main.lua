local target_exposed = false;

local spark = require("core/assets/sounds/spark.flac");

local object_hits = {};
local spark_attachments = {};

local current_power = 0;
local previously_was_activated = false;
local previously_previously_was_activated = false;
local was_activated = false;

function on_destroy()
    for i=1,#spark_attachments do
        spark_attachments[i]:destroy();
    end;
    spark_attachments = {};
end;

function on_hit(data)
    table.insert(object_hits, data);
end;

function on_step()
    for i=1,#spark_attachments do
        spark_attachments[i]:destroy();
    end;
    spark_attachments = {};

    if (current_power > 3) and ((not previously_was_activated) or (not previously_previously_was_activated)) and was_activated then
        for i=1,#object_hits do
            local found_match = false;

            for _, item in ipairs(get_all_connections()) do
                if item.id == object_hits[i].other.id then
                    found_match = true;
                    break;
                end;
            end;

            if found_match then
                table.insert(spark_attachments, Scene:add_attachment({
                    local_position = object_hits[i].point,
                    lights = {{ intensity = 4, color = 0xffffff, radius = 1.8 }}
                }));
                Scene:add_audio({
                    position = object_hits[i].point,
                    asset = spark,
                });
                object_hits[i].other:send_event("core/spark", {
                    point = object_hits[i].point,
                    forward = true,
                });
            end;
        end;
    end;
    object_hits = {};

    current_power = 0;
    previously_was_activated = was_activated;
    previously_previously_was_activated = previously_was_activated;
    was_activated = false;
end;
        
-- If the wire is insulated, this is just direct connections.
-- If the wire is exposed, this is both direct connections and things we're touching.
function get_all_connections()
    local connections = {};
    
    if self_component:get_property("exposed").value then
        -- Add objects we're touching
        for _, obj in ipairs(self:get_touching()) do
            -- To ask each object if they're exposed, we send an event.
            target_exposed = false;
            obj:send_event("core/request_exposed", self_component);
            if target_exposed then
                table.insert(connections, obj);
            end;
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
        if self_component:get_property("exposed").value then
            data:send_event("core/report_exposed");
        end;
    elseif id == "core/report_exposed" then
        target_exposed = true;
    elseif id == "core/request_connections" then
        -- Skip if already processed this request
        if data.visited[self.id] then
            return;
        end
        
        -- Mark as visited
        data.visited[self.id] = true;
        
        -- Get all my connections
        local connections = get_all_connections();
        local connection_ids = {};
        
        -- Create list of connection IDs
        for _, obj in ipairs(connections) do
            table.insert(connection_ids, obj.id);
        end;
        
        -- Get resistance value
        local resistance = self_component:get_property("resistance") and 
                          self_component:get_property("resistance").value or 0;
        
        -- Report back to minus terminal with resistance
        data.source:send_event("core/report_connections", {
            id = self.id,
            connections = connection_ids,
            resistance = resistance,
            object = self
        });
        
        -- Forward request to all my connections
        for _, obj in ipairs(connections) do
            obj:send_event("core/request_connections", data);
        end;
    elseif id == "core/spark" then
        if data.forward then
            for _, obj in ipairs(get_all_connections()) do
                obj:send_event("core/spark", {
                    point = data.point,
                    forward = false,
                });
            end;
        end;
    elseif id == "activate" then
        was_activated = true;
        if data.power then
            current_power += data.power;
        else
            current_power += 1;
        end;
    end;
end;