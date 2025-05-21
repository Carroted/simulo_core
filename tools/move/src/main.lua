local start = nil;
local overlay = nil;

local moving = nil;
local moving_objects = {}; -- Table to track all objects being moved
local moving_offsets = {}; -- Table to track offsets for each moving object
local moving_body_types = {}; -- Table to track original body types

local moving_attachments = {}; -- Table to track all attachments being moved
local moving_attachment_offsets = {}; -- Table to track offsets for each attachment
local moving_attachment_parents = {}; -- Track parents of moving attachments

local last_positions = nil;
local prev_pointer_pos = vec2(0, 0);

-- grid sounds
local should_play_snap = true;
local fixed_update = 0;

function on_update()
    if self:pointer_just_pressed() then
        on_pointer_down(self:pointer_pos());
    end;
    if self:pointer_just_released() then
        on_pointer_up(self:pointer_pos());
    end;
    if self:pointer_pos() ~= prev_pointer_pos then
        on_pointer_move(self:pointer_pos());
    end;
    prev_pointer_pos = self:pointer_pos();
end;

function on_pointer_down(point)
    print("Pointer down at " .. point.x .. ", " .. point.y);
    
    -- Check if shift is pressed for modifying selection
    local shift_pressed = self:key_pressed("ShiftLeft");
    
    -- Get current selections
    local current_objects = self:get_selected_objects();
    local current_attachments = self:get_selected_attachments();
    
    -- Function to look for objects or attachments under the pointer
    RemoteScene:run({
        input = point,
        code = [[
            -- Get objects under pointer
            local objs = Scene:get_objects_in_circle({
                position = input,
                radius = 0,
            });
            
            -- Get attachments under pointer
            local attachments = Scene:get_attachments_in_circle({
                position = input,
                radius = 0.1 * 0.3,
            });
            
            -- Create a combined list of all clickable items
            local all_items = {};
            
            -- Add objects with their z-index
            for _, obj in ipairs(objs) do
                table.insert(all_items, {
                    item = obj,
                    z_index = obj:get_z_index(),
                    type = "object"
                });
            end
            
            -- Add attachments with their z-index
            for _, att in ipairs(attachments) do
                table.insert(all_items, {
                    item = att,
                    z_index = att:get_z_index(),
                    type = "attachment"
                });
            end
            
            -- Sort by z-index, higher values first
            table.sort(all_items, function(a, b)
                return a.z_index > b.z_index
            end);
            
            -- Return the sorted list and the highest item
            local highest_item = nil;
            local highest_type = nil;
            
            if #all_items > 0 then
                highest_item = all_items[1].item;
                highest_type = all_items[1].type;
            end
            
            return { 
                all_items = all_items,
                highest_item = highest_item,
                highest_type = highest_type
            };
        ]],
        callback = function(output)
            if output == nil then return; end
            
            local clicked_object = nil;
            local clicked_attachment = nil;
            
            -- The highest item is what we consider "clicked"
            if output.highest_item then
                if output.highest_type == "object" then
                    clicked_object = output.highest_item;
                elseif output.highest_type == "attachment" then
                    clicked_attachment = output.highest_item;
                end
            end
            
            -- Check if anything was clicked
            if clicked_object == nil and clicked_attachment == nil then
                -- Start a new selection rectangle if no object was clicked
                start = point;
                if overlay == nil then
                    overlay = Overlays:add();
                end;
                
                moving = false;
                return;
            end
            
            -- Determine what was clicked
            local clicked_obj_in_selection = false;
            local clicked_attachment_in_selection = false;
            
            -- Check if clicked object is in current selection
            if clicked_object then
                for _, obj in ipairs(current_objects) do
                    if obj == clicked_object then
                        clicked_obj_in_selection = true;
                        break;
                    end
                end
                print("Object in selection?", clicked_obj_in_selection, "Shift pressed?", shift_pressed);
            end
            
            -- Check if clicked attachment is in current attachment selection
            if clicked_attachment then
                for _, att in ipairs(current_attachments) do
                    if att == clicked_attachment then
                        clicked_attachment_in_selection = true;
                        break;
                    end
                end
                print("Attachment in selection?", clicked_attachment_in_selection, "Shift pressed?", shift_pressed);
                
                -- Get parent of the clicked attachment
                RemoteScene:run({
                    input = { attachment = clicked_attachment },
                    code = [[
                        if input.attachment then
                            local parent = input.attachment:get_parent();
                            return { parent = parent };
                        end
                    ]],
                    callback = function(parent_result)
                        if parent_result and parent_result.parent then
                            print("Attachment has parent:", parent_result.parent);
                        else
                            print("Attachment has no parent (on background)");
                        end
                    end
                });
            end
            
            -- Handle selection logic
            -- SINGLE UNIFIED SELECTION LOGIC
            -- Since we have a single highest item from z-index sorting, we only need one selection logic path
            if clicked_object or clicked_attachment then
                local clicked_type = clicked_object and "object" or "attachment";
                local clicked_item = clicked_object or clicked_attachment;
                local is_in_selection = false;
                
                -- Check if the clicked item is already in selection
                if clicked_type == "object" then
                    is_in_selection = clicked_obj_in_selection;
                else
                    is_in_selection = clicked_attachment_in_selection; 
                end
                
                if shift_pressed then
                    if is_in_selection then
                        -- SHIFT+CLICK ON SELECTED ITEM: Remove from selection
                        if clicked_type == "object" then
                            -- Remove object from selection
                            local new_selection = {};
                            for _, obj in ipairs(current_objects) do
                                if obj ~= clicked_item then
                                    table.insert(new_selection, obj);
                                end
                            end
                            self:set_selected_objects(new_selection);
                            print("DESELECTED object. Now have", #new_selection, "objects");
                        else
                            -- Remove attachment from selection
                            local new_selection = {};
                            for _, att in ipairs(current_attachments) do
                                if att ~= clicked_item then
                                    table.insert(new_selection, att);
                                end
                            end
                            self:set_selected_attachments(new_selection);
                            print("DESELECTED attachment. Now have", #new_selection, "attachments");
                        end
                        
                        -- Don't start dragging when deselecting
                        moving = false;
                        return;
                    else
                        -- SHIFT+CLICK ON UNSELECTED ITEM: Add to selection
                        if clicked_type == "object" then
                            -- Add object to selection
                            local new_selection = {};
                            for _, obj in ipairs(current_objects) do
                                table.insert(new_selection, obj);
                            end
                            table.insert(new_selection, clicked_item);
                            self:set_selected_objects(new_selection);
                            current_objects = self:get_selected_objects();
                            clicked_obj_in_selection = true;
                            print("ADDED object to selection. Now have", #current_objects, "objects");
                        else
                            -- Add attachment to selection
                            local new_selection = {};
                            for _, att in ipairs(current_attachments) do
                                table.insert(new_selection, att);
                            end
                            table.insert(new_selection, clicked_item);
                            self:set_selected_attachments(new_selection);
                            current_attachments = self:get_selected_attachments();
                            clicked_attachment_in_selection = true;
                            print("ADDED attachment to selection. Now have", #current_attachments, "attachments");
                        end
                    end
                else if not is_in_selection then
                        -- REGULAR CLICK ON UNSELECTED ITEM: Replace selection
                        if clicked_type == "object" then
                            -- Select only this object
                            self:set_selected_objects({clicked_item});
                            self:set_selected_attachments({});  -- Clear attachment selection
                            current_objects = self:get_selected_objects();
                            current_attachments = {};
                            clicked_obj_in_selection = true;
                            clicked_attachment_in_selection = false;
                            print("SELECTED single object. Now have", #current_objects, "objects and 0 attachments");
                        else
                            -- Select only this attachment
                            self:set_selected_objects({});  -- Clear object selection
                            self:set_selected_attachments({clicked_item});
                            current_objects = {};
                            current_attachments = self:get_selected_attachments();
                            clicked_obj_in_selection = false;
                            clicked_attachment_in_selection = true;
                            print("SELECTED single attachment. Now have 0 objects and", #current_attachments, "attachments");
                        end
                    end
                    -- If it's already selected, do nothing to the selection
                end
            end
            
            -- DRAGGING LOGIC - Start dragging if we clicked on a selected object or attachment
            if clicked_obj_in_selection or clicked_attachment_in_selection then
                -- Get the current selections again to make sure they're up to date
                local drag_objects = self:get_selected_objects();
                local drag_attachments = self:get_selected_attachments();
                
                -- Set up for moving
                moving = true;
                moving_objects = {};
                moving_offsets = {};
                moving_body_types = {};
                moving_attachments = {};
                moving_attachment_offsets = {};
                moving_attachment_parents = {};
                
                -- Get a list of parents of selected objects for attachment filtering
                local selected_parents = {};
                for _, obj in ipairs(drag_objects) do
                    table.insert(selected_parents, obj);
                end
                
                -- Store objects for moving
                for _, obj in ipairs(drag_objects) do
                    RemoteScene:run({
                        input = {
                            object = obj,
                            point = point
                        },
                        code = [[
                            if input.object then
                                local body_type = input.object:get_body_type();
                                local position = input.object:get_position();
                                input.object:set_body_type(BodyType.Static);
                                return {
                                    object = input.object,
                                    offset = input.point - position,
                                    body_type = body_type
                                };
                            end;
                        ]],
                        callback = function(obj_data)
                            if obj_data ~= nil and obj_data.object ~= nil then
                                table.insert(moving_objects, obj_data.object);
                                table.insert(moving_offsets, obj_data.offset);
                                table.insert(moving_body_types, obj_data.body_type);
                            end;
                        end,
                    });
                end
                
                -- Store attachments for moving
                for _, att in ipairs(drag_attachments) do
                    RemoteScene:run({
                        input = {
                            attachment = att,
                            point = point,
                            selected_parents = selected_parents
                        },
                        code = [[
                            if input.attachment then
                                local parent = input.attachment:get_parent();
                                local parent_selected = false;
                                
                                -- Check if the parent is selected
                                if parent then
                                    for _, selected_obj in ipairs(input.selected_parents) do
                                        if parent == selected_obj then
                                            parent_selected = true;
                                            break;
                                        end
                                    end
                                end
                                
                                -- Only set up for direct moving if the parent is not selected
                                if parent == nil or not parent_selected then
                                    local position = input.attachment:get_position();
                                    return {
                                        attachment = input.attachment,
                                        offset = input.point - position,
                                        parent = parent,
                                        move_directly = true
                                    };
                                else
                                    -- Parent is selected, so it will be moved with parent
                                    return {
                                        attachment = input.attachment,
                                        parent = parent,
                                        move_directly = false
                                    };
                                end
                            end;
                        ]],
                        callback = function(att_data)
                            if att_data ~= nil and att_data.attachment ~= nil then
                                -- Only store for direct moving if needed
                                if att_data.move_directly then
                                    table.insert(moving_attachments, att_data.attachment);
                                    table.insert(moving_attachment_offsets, att_data.offset);
                                    table.insert(moving_attachment_parents, att_data.parent);
                                    print("Will move attachment directly");
                                else
                                    print("Attachment will move with its parent");
                                end
                            end;
                        end,
                    });
                end;
                
                print("Starting drag with", #drag_objects, "objects and", #drag_attachments, "attachments");
            else
                moving = false;
            end
            
            -- Cancel any active selection overlay
            if overlay ~= nil then
                overlay:destroy();
                overlay = nil;
            end;
            
            start = nil;
        end,
    });

    last_positions = {};
    table.insert(last_positions, point);
end;

function on_pointer_move(point)
    if moving then
        --[==[if should_play_snap and self:grid_enabled() and ((self:grid_pointer_pos() - last_grid_pointer_pos):magnitude() > 0.0) then
            RemoteScene:run({
                input = point,
                code = [[
                    Scene:add_audio({
                        asset = require('core/assets/sounds/grid.wav'),
                        position = input,
                        volume = 0.7,
                        pitch = 1.2,
                    });
                ]],
            });
            should_play_snap = false;
        end;]==]

        local obj_new_positions = {};

        -- Move all selected objects
        for i, obj in ipairs(moving_objects) do
            local offset = moving_offsets[i];
            local new_pos = self:snap_if_preferred(point - offset);

            table.insert(obj_new_positions, {
                obj = obj,
                pos = new_pos,
            });
        end;

        local atch_new_positions = {};
        
        -- Move attachments that need direct movement
        for i, att in ipairs(moving_attachments) do
            local offset = moving_attachment_offsets[i];
            local parent = moving_attachment_parents[i];
            local new_pos = self:snap_if_preferred(point - offset);

            table.insert(atch_new_positions, {
                atch = att,
                parent = parent,
                pos = new_pos,
            });
        end;
            
        RemoteScene:run({
            input = {
                objects = obj_new_positions,
                attachments = atch_new_positions,
            },
            code = [[
                for _, data in pairs(input.objects) do
                    data.obj:set_body_type(BodyType.Static);
                    data.obj:set_position(data.pos);
                end;

                for _, data in pairs(input.attachments) do
                    if data.parent then
                        -- Convert world position to local position for the parent
                        local parent_pos = data.parent:get_position();
                        local parent_angle = data.parent:get_angle();
                        
                        -- Calculate local position
                        local diff = data.pos - parent_pos;
                        local cos_angle = math.cos(-parent_angle);
                        local sin_angle = math.sin(-parent_angle);
                        local local_x = diff.x * cos_angle - diff.y * sin_angle;
                        local local_y = diff.x * sin_angle + diff.y * cos_angle;
                        
                        data.atch:set_local_position(vec2(local_x, local_y));
                    else
                        -- No parent, we can set local position directly
                        data.atch:set_local_position(data.pos);
                    end
                end;
            ]]
        });
        
        table.insert(last_positions, point);
    end;

    if start then
        local start_point = self:snap_if_preferred(start);
        local end_point = self:snap_if_preferred(point);
        local square = self:key_pressed("ShiftLeft");

        local color = Color:hex(0xfab7ff);
        color.a = 10.0 / 255.0;

        if square then
            local diff = end_point - start_point;

            local size = math.max(math.abs(diff.x), math.abs(diff.y));
            local pos = start_point + vec2(size, size);
            if diff.x < 0 then
                pos.x = start_point.x - size;
            end;
            if diff.y < 0 then
                pos.y = start_point.y - size;
            end;
            end_point = pos;
        end

        overlay:set_rect({
            point_a = start_point,
            point_b = end_point,
            color = Color:hex(0xfab7ff),
            fill = color,
        });
    end;

    last_grid_pointer_pos = self:preferred_pointer_pos();
end;

function on_fixed_update()
    fixed_update += 1;

    if fixed_update % 4 == 0 then
        should_play_snap = true;
    end;
end;

function on_pointer_up(point)
    if moving then
        print("Pointer up!");

        local function last_n_elements(tbl, n)
            local result = {}
            local length = #tbl
            local startIdx = math.max(length - n + 1, 1)
            
            for i = startIdx, length do
                table.insert(result, tbl[i])
            end
            
            return result
        end;

        local last_2 = last_n_elements(last_positions, 2);
        local vel = vec2(0, 0);
        
        if #last_2 >= 2 then
            vel = last_2[2] - last_2[1];
        end;
        
        -- Release all moving objects with velocity
        for i, obj in ipairs(moving_objects) do
            local body_type = moving_body_types[i];
            
            RemoteScene:run({
                input = {
                    obj = obj,
                    vel = vel / ((1/60)*3),
                    body_type = body_type,
                },
                code = [[
                    if input.obj then
                        input.obj:set_body_type(input.body_type);
                        input.obj:set_linear_velocity(input.vel);
                    end;
                ]]
            });
        end;

        RemoteScene:run({
            input = {
                attachments = moving_attachments,
                parents = moving_attachment_parents
            },
            code = [[
                local results = {};
                
                -- Loop through attachments inside the code block
                for i, att in ipairs(input.attachments) do
                    local current_parent = input.parents[i];
                    
                    if att then
                        -- Save current world position and angle before changing parent
                        local current_world_pos = att:get_position();
                        local current_world_angle = att:get_angle();
                        
                        -- Check if we're over an object using the attachment's current position
                        local objects_under_point = Scene:get_objects_in_circle({
                            position = current_world_pos,
                            radius = 0,
                        });
                        
                        if #objects_under_point > 0 then
                            local new_parent = objects_under_point[1];
                            
                            -- Only proceed if the parent would be different
                            if new_parent ~= current_parent then
                                print("Setting new parent for attachment");
                                
                                -- Calculate local position relative to new parent
                                local parent_pos = new_parent:get_position();
                                local parent_angle = new_parent:get_angle();
                                
                                -- Convert world position to local position
                                local diff = current_world_pos - parent_pos;
                                local cos_angle = math.cos(-parent_angle);
                                local sin_angle = math.sin(-parent_angle);
                                local local_x = diff.x * cos_angle - diff.y * sin_angle;
                                local local_y = diff.x * sin_angle + diff.y * cos_angle;
                                
                                -- Calculate local angle
                                local local_angle = current_world_angle - parent_angle;
                                
                                -- Set new parent and update local position/angle
                                att:set_parent(new_parent);
                                att:set_local_position(vec2(local_x, local_y));
                                att:set_local_angle(local_angle);
                                
                                table.insert(results, { 
                                    idx = i,
                                    success = true, 
                                    new_parent = new_parent 
                                });
                            end
                        else
                            -- Check if we need to remove parent (if current parent exists)
                            if current_parent then
                                print("Removing parent from attachment");
                                
                                -- Set local position and angle to match world position before removing parent
                                att:set_local_position(current_world_pos);
                                att:set_local_angle(current_world_angle);
                                att:set_parent(nil);
                                
                                table.insert(results, { 
                                    idx = i,
                                    success = true, 
                                    new_parent = nil 
                                });
                            end
                        end
                    end
                end

                Scene:push_undo();
                
                return { results = results };
            ]],
            callback = function(result)
                if result and result.results then
                    for _, res in ipairs(result.results) do
                        if res.success then
                            if res.new_parent then
                                print("Attachment " .. res.idx .. " parented to new object");
                            else
                                print("Attachment " .. res.idx .. " detached from parent");
                            end
                        end
                    end
                end
            end,
        });

        moving = nil;
        moving_objects = {};
        moving_offsets = {};
        moving_body_types = {};
        moving_attachments = {};
        moving_attachment_offsets = {};
        moving_attachment_parents = {};
        last_positions = nil;
    end;

    if start ~= nil then
        local shift_pressed = self:key_pressed("ShiftLeft");
        local start_point = self:snap_if_preferred(start);
        local end_point = self:snap_if_preferred(point);

        if shift_pressed then
            local diff = end_point - start_point;

            local size = math.max(math.abs(diff.x), math.abs(diff.y));
            local pos = start_point + vec2(size, size);
            if diff.x < 0 then
                pos.x = start_point.x - size;
            end;
            if diff.y < 0 then
                pos.y = start_point.y - size;
            end;
            end_point = pos;
        end;

        local width = math.abs(end_point.x - start_point.x);
        local height = math.abs(end_point.y - start_point.y);

        local size = vec2(width, height);
        local pos = vec2((end_point.x + start_point.x) / 2, (end_point.y + start_point.y) / 2);

        local fill = Color:hex(0xfab7ff);
        fill.a = 10.0 / 255.0;

        overlay:set_rect({
            point_a = start_point,
            point_b = end_point,
            fill = fill,
            color = Color:hex(0xfab7ff),
        });

        if size.x > 0 and size.y > 0 then
            RemoteScene:run({
                input = {
                    size = size,
                    pos = pos,
                    shift_pressed = shift_pressed,
                    current_objects = self:get_selected_objects(),
                    current_attachments = self:get_selected_attachments()
                },
                code = [[
                    -- Get objects in box
                    local objects = Scene:get_objects_in_box({
                        position = input.pos,
                        size = input.size
                    });
                    
                    -- Get attachments in box
                    local attachments = Scene:get_attachments_in_box({
                        position = input.pos,
                        size = input.size
                    });
                    
                    -- Handle selection logic inside the remote scene
                    local new_obj_selection = {};
                    local new_att_selection = {};
                    
                    if input.shift_pressed then
                        -- Copy current object selection
                        for _, obj in ipairs(input.current_objects) do
                            table.insert(new_obj_selection, obj);
                        end
                        
                        -- Add new objects not already in selection
                        for _, obj in ipairs(objects) do
                            local already_selected = false;
                            for _, sel_obj in ipairs(input.current_objects) do
                                if obj == sel_obj then
                                    already_selected = true;
                                    break;
                                end
                            end
                            
                            if not already_selected then
                                table.insert(new_obj_selection, obj);
                            end
                        end
                        
                        -- Copy current attachment selection
                        for _, att in ipairs(input.current_attachments) do
                            table.insert(new_att_selection, att);
                        end
                        
                        -- Add new attachments not already in selection
                        for _, att in ipairs(attachments) do
                            local already_selected = false;
                            for _, sel_att in ipairs(input.current_attachments) do
                                if att == sel_att then
                                    already_selected = true;
                                    break;
                                end
                            end
                            
                            if not already_selected then
                                table.insert(new_att_selection, att);
                            end
                        end
                    else
                        -- Replace selection with both objects and attachments
                        new_obj_selection = objects;
                        new_att_selection = attachments;
                    end
                    
                    return { 
                        objects = objects,
                        attachments = attachments,
                        new_obj_selection = new_obj_selection,
                        new_att_selection = new_att_selection
                    };
                ]],
                callback = function(output)
                    if (overlay ~= nil) and (start == nil) then
                        overlay:destroy();
                        overlay = nil;
                    end;
                    
                    if output == nil then return; end
                    
                    -- Apply the selection calculated in RemoteScene
                    if output.new_obj_selection then
                        self:set_selected_objects(output.new_obj_selection);
                    end
                    
                    if output.new_att_selection then
                        self:set_selected_attachments(output.new_att_selection);
                    end
                    
                    local obj_count = output.objects and #output.objects or 0;
                    local att_count = output.attachments and #output.attachments or 0;
                    print("BOX SELECT: Now selecting", #self:get_selected_objects(), "objects and", 
                          #self:get_selected_attachments(), "attachments");
                end,
            });
        else
            if overlay ~= nil then
                overlay:destroy();
                overlay = nil;
            end;
            
            -- Only clear selection if shift is not pressed
            if not shift_pressed then
                self:set_selected_objects({});
                self:set_selected_attachments({});
                print("CLEAR SELECT: Selected 0 objects and 0 attachments");
            end;
        end;
        start = nil;
    end;
end;