local fluid_density;

local horizontal_drag_coeff = 0.4;
local vertical_drag_coeff = 0.3;
local angular_drag_coeff = 0.3;

local target_exposed = false;

--[[
function on_event(id, data)
    if id == "activate" then
        for i inself:get_sensed();
end;]]

function on_step(dt)
    fluid_density = self:get_density();
    
    -- Get objects in the sensor area
    local objects = self:get_sensed();

    local water_level = self:get_position().y;
    local ocean_shape = self:get_shape();
    
    if ocean_shape.shape_type == "box" then
        -- Assuming the top of the box is the water level
        -- and the box's position is at its center
        water_level += ocean_shape.size.y / 2;
    end;
    
    -- Get gravity from the scene instead of using a fixed value
    local gravity = Scene:get_gravity();
    
    -- Process each object
    for _, object in ipairs(objects) do
        --[[object:send_event("core/report_connections", {
            id = self.id,
            connections = objects,
            resistance = 5,
            object = self,
        });]]

        apply_buoyancy(object, water_level, fluid_density, gravity)
    end
end

function apply_buoyancy(object, water_level, fluid_density, gravity)
    -- Safety check
    if not object then return end
    
    local shape = object:get_shape()
    if not shape or not shape.shape_type then return end
    
    local pos = object:get_position()
    
    -- Determine if object is submerged at all
    if not is_submerged(shape, pos, water_level, object) then
        return -- Skip if not submerged
    end
    
    -- Calculate buoyancy based on shape type
    if shape.shape_type == "box" then
        apply_box_buoyancy(object, shape, pos, water_level, fluid_density, gravity)
    elseif shape.shape_type == "circle" then
        apply_circle_buoyancy(object, shape, pos, water_level, fluid_density, gravity)
    elseif shape.shape_type == "capsule" then
        apply_capsule_buoyancy(object, shape, pos, water_level, fluid_density, gravity)
    elseif shape.shape_type == "polygon" then
        apply_polygon_buoyancy(object, shape, pos, water_level, fluid_density, gravity)
    end
    
    -- Apply additional global damping for stability
    --apply_global_damping(object)
end

-- Modified function to apply additional damping to all submerged objects
function apply_global_damping(object)
    -- Add extra linear damping
    local velocity = object:get_linear_velocity()
    local speed = math.sqrt(velocity.x^2 + velocity.y^2)
    
    -- Proportional damping based on speed
    local damping_factor = 0.05
    if speed > 0.1 then
        local extra_damping = vec2(-velocity.x * damping_factor, -velocity.y * damping_factor)
        object:apply_force_to_center(extra_damping)
    end
    
    -- Add extra angular damping that scales with angular velocity
    local angular_velocity = object:get_angular_velocity()
    local abs_angular_vel = math.abs(angular_velocity)
    
    -- Progressive damping - more damping for faster rotation
    local dynamic_angular_coeff = angular_drag_coeff
    if abs_angular_vel > 3.0 then
        dynamic_angular_coeff = dynamic_angular_coeff * (1.0 + abs_angular_vel / 10.0)
    end
    
    local angular_damping = -angular_velocity * dynamic_angular_coeff
    object:apply_torque(angular_damping)
end

function is_submerged(shape, pos, water_level, object)
    -- Check if any part of the object is below water level
    if shape.shape_type == "box" then
        -- Get all four corners of the box in world space to handle rotation properly
        local half_width = shape.size.x / 2
        local half_height = shape.size.y / 2
        local corners = {
            object:get_world_point(vec2(-half_width, -half_height)),
            object:get_world_point(vec2(half_width, -half_height)),
            object:get_world_point(vec2(half_width, half_height)),
            object:get_world_point(vec2(-half_width, half_height))
        }
        
        -- Check if any corner is below water
        for _, corner in ipairs(corners) do
            if corner.y < water_level then
                return true
            end
        end
        return false
    elseif shape.shape_type == "circle" then
        return pos.y - shape.radius < water_level
    elseif shape.shape_type == "capsule" then
        local point_a = vec2(shape.local_point_a.x, shape.local_point_a.y)
        local point_b = vec2(shape.local_point_b.x, shape.local_point_b.y)
        return math.min(pos.y + point_a.y, pos.y + point_b.y) - shape.radius < water_level
    elseif shape.shape_type == "polygon" then
        -- Check if any vertex is below water level
        for _, point in ipairs(shape.points) do
            local world_point = object:get_world_point(point)
            if world_point.y < water_level then
                return true
            end
        end
        return false
    end
    return false
end

-- IMPROVED BOX BUOYANCY --
function apply_box_buoyancy(object, shape, pos, water_level, fluid_density, gravity)
    -- Get all four corners of the box in world space to handle rotation properly
    local half_width = shape.size.x / 2
    local half_height = shape.size.y / 2
    local corners = {
        object:get_world_point(vec2(-half_width, -half_height)),
        object:get_world_point(vec2(half_width, -half_height)),
        object:get_world_point(vec2(half_width, half_height)),
        object:get_world_point(vec2(-half_width, half_height))
    }
    
    -- Find submerged polygon by clipping box against water line
    local submerged_polygon = clip_polygon_against_water(corners, water_level)
    
    -- If we have a valid submerged polygon
    if #submerged_polygon > 2 then
        -- Calculate submerged area and centroid
        local submerged_area = calculate_polygon_area(submerged_polygon)
        
        -- Safety check for very small areas
        if submerged_area < 0.0001 then
            return
        end
        
        local centroid = calculate_polygon_centroid(submerged_polygon, submerged_area)
        
        -- Calculate buoyancy force
        local buoyancy_force_magnitude = fluid_density * math.abs(gravity.y) * submerged_area
        
        -- Add a tiny random perturbation to break perfect symmetry 
        -- (helps with squares finding stability at all angles)
        local random_x = (math.random() - 0.5) * 0.001 * buoyancy_force_magnitude
        local buoyancy_force = vec2(random_x, buoyancy_force_magnitude * 0.2)
        
        -- Apply buoyancy force at the centroid of the submerged area
        object:apply_linear_impulse(buoyancy_force, centroid)
        
        -- Calculate velocity at centroid for proper drag
        local velocity = object:get_linear_velocity()
        local angular_velocity = object:get_angular_velocity()
        local r = centroid - pos
        local centroid_velocity = velocity + vec2(
            -r.y * angular_velocity,
            r.x * angular_velocity
        )
        
        -- Calculate submersion ratio for the whole box
        local total_area = shape.size.x * shape.size.y
        local submersion_ratio = submerged_area / total_area
        
        -- Apply drag forces based on actual velocity direction, not just horizontal/vertical
        local velocity_magnitude = math.sqrt(centroid_velocity.x^2 + centroid_velocity.y^2)
        
        if velocity_magnitude > 0.001 then -- Avoid division by near-zero
            -- Normalized velocity direction
            local norm_vel_x = centroid_velocity.x / velocity_magnitude
            local norm_vel_y = centroid_velocity.y / velocity_magnitude
            
            -- Calculate drag magnitude
            local drag_magnitude = velocity_magnitude * (
                (math.abs(norm_vel_x) * horizontal_drag_coeff) + 
                (math.abs(norm_vel_y) * vertical_drag_coeff)
            ) * submerged_area * submersion_ratio
            
            -- Apply drag in the direction opposite to velocity
            local drag_force = vec2(
                -norm_vel_x * drag_magnitude,
                -norm_vel_y * drag_magnitude
            )
            
            object:apply_linear_impulse(drag_force * 0.8, centroid)
        end
    end
end

-- IMPROVED CIRCLE BUOYANCY --
function apply_circle_buoyancy(object, shape, pos, water_level, fluid_density, gravity)
    local radius = shape.radius
    local circle_bottom = pos.y - radius
    
    -- Calculate submersion depth
    local submersion_depth = water_level - circle_bottom
    if submersion_depth <= 0 then return end
    
    -- Clamp submersion to diameter
    submersion_depth = math.min(submersion_depth, 2 * radius)
    
    -- Calculate the angle from vertical to the water intersection points
    -- Avoid division by zero or invalid acos input
    local normalized_depth = submersion_depth / radius
    normalized_depth = math.max(0, math.min(2, normalized_depth)) -- Clamp between 0 and 2
    
    local theta = 0
    if normalized_depth < 2 then
        theta = math.acos(1 - normalized_depth)
    else
        theta = math.pi -- Fully submerged
    end
    
    -- Calculate submerged area
    local submerged_area = 0
    if normalized_depth >= 2 then
        -- Fully submerged
        submerged_area = math.pi * radius * radius
    else
        -- Partially submerged
        submerged_area = radius * radius * (theta - math.sin(2 * theta) / 2)
    end
    
    -- Calculate centroid of the submerged portion
    local centroid_offset = 0
    if normalized_depth < 2 and normalized_depth > 0 then
        -- Avoid division by zero
        local denominator = (theta - math.sin(2 * theta) / 2)
        if math.abs(denominator) > 0.0001 then -- Small threshold to avoid division by near-zero
            centroid_offset = (4 * radius * math.sin(theta)^3) / (3 * denominator)
        end
    end
    
    -- Transform the centroid offset based on object rotation
    local angle = object:get_angle()
    local centroid = vec2(
        math.sin(angle) * -centroid_offset, 
        math.cos(angle) * -centroid_offset
    )
    local world_centroid = object:get_world_point(centroid)
    
    -- Apply buoyancy force with tiny random perturbation
    local buoyancy_force_magnitude = fluid_density * math.abs(gravity.y) * submerged_area
    local random_x = (math.random() - 0.5) * 0.001 * buoyancy_force_magnitude
    local buoyancy_force = vec2(random_x, buoyancy_force_magnitude * 0.2)
    object:apply_linear_impulse(buoyancy_force, world_centroid)
    
    -- Apply drag forces with depth-based resistance
    local velocity = object:get_linear_velocity()
    local depth_factor = submersion_depth / (2 * radius) -- Normalized depth (0-1)
    
    -- Calculate velocity at the centroid point
    local angular_velocity = object:get_angular_velocity()
    local r = world_centroid - pos
    local centroid_velocity = velocity + vec2(
        -r.y * angular_velocity,
        r.x * angular_velocity
    )
    
    -- Calculate velocity magnitude
    local velocity_magnitude = math.sqrt(centroid_velocity.x^2 + centroid_velocity.y^2)
    
    if velocity_magnitude > 0.001 then -- Avoid division by near-zero
        -- Normalized velocity direction
        local norm_vel_x = centroid_velocity.x / velocity_magnitude
        local norm_vel_y = centroid_velocity.y / velocity_magnitude
        
        -- Calculate drag magnitude
        local drag_magnitude = velocity_magnitude * (
            (math.abs(norm_vel_x) * horizontal_drag_coeff) + 
            (math.abs(norm_vel_y) * vertical_drag_coeff)
        ) * submerged_area * depth_factor
        
        -- Apply drag in the direction opposite to velocity
        local drag_force = vec2(
            -norm_vel_x * drag_magnitude,
            -norm_vel_y * drag_magnitude
        )
        
        object:apply_linear_impulse(drag_force * 0.8, world_centroid)
    end
    
    -- Apply angular damping
    if math.abs(angular_velocity) > 0.01 then
        local angular_drag = -angular_velocity * angular_drag_coeff * submerged_area * 0.8
        object:apply_torque(angular_drag)
    end
end

-- IMPROVED CAPSULE BUOYANCY --
function apply_capsule_buoyancy(object, shape, pos, water_level, fluid_density, gravity)
    local point_a = object:get_world_point(vec2(shape.local_point_a.x, shape.local_point_a.y))
    local point_b = object:get_world_point(vec2(shape.local_point_b.x, shape.local_point_b.y))
    local radius = shape.radius
    
    -- Sort points by y-coordinate for easier calculations
    if point_a.y > point_b.y then
        point_a, point_b = point_b, point_a
    end
    
    -- Check different submersion cases
    local total_buoyancy_force = vec2(0, 0)
    local buoyancy_center = vec2(0, 0)
    local total_area = 0
    
    -- Case 1: Capsule completely above water
    if point_a.y - radius >= water_level then
        return
    end
    
    -- Case 2: Bottom hemisphere partially or fully submerged
    if point_a.y + radius > water_level then
        -- Calculate submersion for bottom hemisphere
        local submersion_depth = water_level - (point_a.y - radius)
        submersion_depth = math.min(submersion_depth, 2 * radius)
        
        -- Calculate submerged area and centroid (similar to circle)
        local theta = math.acos(1 - submersion_depth / radius)
        local area = radius * radius * (theta - math.sin(2 * theta) / 2)
        
        local centroid_offset = 0
        if submersion_depth < 2 * radius then
            local denominator = (theta - math.sin(2 * theta) / 2)
            if math.abs(denominator) > 0.0001 then
                centroid_offset = (4 * radius * math.sin(theta)^3) / (3 * denominator)
            end
        end
        local centroid = vec2(point_a.x, point_a.y - radius + centroid_offset)
        
        total_area = total_area + area
        buoyancy_center = buoyancy_center + centroid * area
    else
        -- Bottom hemisphere fully submerged
        local area = math.pi * radius * radius
        total_area = total_area + area
        buoyancy_center = buoyancy_center + vec2(point_a.x, point_a.y) * area
    end
    
    -- Case 3: Rectangle part between hemispheres
    local rect_height = (point_b.y - point_a.y)
    if rect_height > 0 then
        local rect_top = point_b.y - radius
        local rect_bottom = point_a.y + radius
        
        -- Check if rectangle part is submerged
        if rect_bottom < water_level then
            local submersion_depth = math.min(water_level - rect_bottom, rect_height)
            if submersion_depth > 0 then
                local rect_area = 2 * radius * submersion_depth
                local rect_centroid = vec2(
                    (point_a.x + point_b.x) / 2,
                    rect_bottom + submersion_depth / 2
                )
                
                total_area = total_area + rect_area
                buoyancy_center = buoyancy_center + rect_centroid * rect_area
            end
        end
    end
    
    -- Case 4: Top hemisphere
    if point_b.y - radius < water_level then
        -- Top hemisphere at least partially submerged
        local submersion_depth = water_level - (point_b.y - radius)
        submersion_depth = math.min(submersion_depth, 2 * radius)
        
        -- Calculate submerged area and centroid (similar to circle)
        local theta = math.acos(1 - submersion_depth / radius)
        local area = radius * radius * (theta - math.sin(2 * theta) / 2)
        
        local centroid_offset = 0
        if submersion_depth < 2 * radius then
            local denominator = (theta - math.sin(2 * theta) / 2)
            if math.abs(denominator) > 0.0001 then
                centroid_offset = (4 * radius * math.sin(theta)^3) / (3 * denominator)
            end
        end
        local centroid = vec2(point_b.x, point_b.y - radius + centroid_offset)
        
        total_area = total_area + area
        buoyancy_center = buoyancy_center + centroid * area
    end
    
    -- Calculate final buoyancy force and center
    if total_area > 0.0001 then
        buoyancy_center = buoyancy_center / total_area
        local buoyancy_force_magnitude = fluid_density * math.abs(gravity.y) * total_area
        
        -- Add tiny random perturbation for stability
        local random_x = (math.random() - 0.5) * 0.001 * buoyancy_force_magnitude
        local buoyancy_force = vec2(random_x, buoyancy_force_magnitude * 0.2)
        
        -- Apply buoyancy force
        object:apply_linear_impulse(buoyancy_force, buoyancy_center)
        
        -- Calculate velocity at the buoyancy center
        local velocity = object:get_linear_velocity()
        local angular_velocity = object:get_angular_velocity()
        local r = buoyancy_center - pos
        local centroid_velocity = velocity + vec2(
            -r.y * angular_velocity,
            r.x * angular_velocity
        )
        
        -- Calculate submersion ratio
        local capsule_height = (point_b.y - point_a.y) + 2 * radius
        local submersion_ratio = math.min(water_level - (point_a.y - radius), capsule_height) / capsule_height
        
        -- Apply velocity-based drag (not just horizontal/vertical)
        local velocity_magnitude = math.sqrt(centroid_velocity.x^2 + centroid_velocity.y^2)
        
        if velocity_magnitude > 0.001 then -- Avoid division by near-zero
            -- Normalized velocity direction
            local norm_vel_x = centroid_velocity.x / velocity_magnitude
            local norm_vel_y = centroid_velocity.y / velocity_magnitude
            
            -- Calculate drag magnitude
            local drag_magnitude = velocity_magnitude * (
                (math.abs(norm_vel_x) * horizontal_drag_coeff) + 
                (math.abs(norm_vel_y) * vertical_drag_coeff)
            ) * total_area * submersion_ratio
            
            -- Apply drag in the direction opposite to velocity
            local drag_force = vec2(
                -norm_vel_x * drag_magnitude,
                -norm_vel_y * drag_magnitude
            )
            
            object:apply_linear_impulse(drag_force * 0.8, buoyancy_center)
        end
        
        -- Add angular damping
        if math.abs(angular_velocity) > 0.01 then
            local angular_drag = -angular_velocity * angular_drag_coeff * total_area * 0.8
            object:apply_torque(angular_drag)
        end
    end
end

-- FIXED POLYGON BUOYANCY --
function apply_polygon_buoyancy(object, shape, pos, water_level, fluid_density, gravity)
    -- Convert local polygon points to world coordinates
    local vertices = {}
    for _, point in ipairs(shape.points) do
        table.insert(vertices, object:get_world_point(vec2(point.x, point.y)))
    end
    
    -- Safety check for degenerate polygons
    if #vertices < 3 then
        return
    end
    
    -- Find the submerged portion of the polygon
    local submerged_polygon = clip_polygon_against_water(vertices, water_level)
    
    -- Make sure we have a valid polygon after clipping
    if #submerged_polygon < 3 then
        return
    end
    
    -- Calculate area of the submerged portion
    local submerged_area = calculate_polygon_area(submerged_polygon)
    
    -- Safety check for very small areas
    if submerged_area < 0.0001 then
        return
    end
    
    -- Calculate centroid of the submerged portion
    local centroid = calculate_polygon_centroid(submerged_polygon, submerged_area)
    
    -- Calculate buoyancy force
    local buoyancy_force_magnitude = fluid_density * math.abs(gravity.y) * submerged_area
    
    -- Limit maximum force to prevent instability with complex polygons
    local max_force = 200 -- Adjust based on your physics scale
    buoyancy_force_magnitude = math.min(buoyancy_force_magnitude, max_force)
    
    -- Add tiny random perturbation for stability
    local random_x = (math.random() - 0.5) * 0.001 * buoyancy_force_magnitude
    local buoyancy_force = vec2(random_x, buoyancy_force_magnitude * 0.2)
    
    -- Apply buoyancy force at the centroid
    object:apply_linear_impulse(buoyancy_force, centroid)
    
    -- Calculate velocity at the centroid
    local velocity = object:get_linear_velocity()
    local angular_velocity = object:get_angular_velocity()
    local r = centroid - pos
    local centroid_velocity = velocity + vec2(
        -r.y * angular_velocity,
        r.x * angular_velocity
    )
    
    -- Calculate total polygon area to determine submersion ratio
    local total_area = calculate_polygon_area(vertices)
    local submersion_ratio = math.min(submerged_area / total_area, 1.0)
    
    -- Apply velocity-based drag (not just horizontal/vertical)
    local velocity_magnitude = math.sqrt(centroid_velocity.x^2 + centroid_velocity.y^2)
    
    if velocity_magnitude > 0.001 then -- Avoid division by near-zero
        -- Normalized velocity direction
        local norm_vel_x = centroid_velocity.x / velocity_magnitude
        local norm_vel_y = centroid_velocity.y / velocity_magnitude
        
        -- Calculate drag magnitude
        local drag_magnitude = velocity_magnitude * (
            (math.abs(norm_vel_x) * horizontal_drag_coeff) + 
            (math.abs(norm_vel_y) * vertical_drag_coeff)
        ) * submerged_area * submersion_ratio
        
        -- Limit maximum drag force
        drag_magnitude = math.min(drag_magnitude, max_force)
        
        -- Apply drag in the direction opposite to velocity
        local drag_force = vec2(
            -norm_vel_x * drag_magnitude,
            -norm_vel_y * drag_magnitude
        )
        
        object:apply_linear_impulse(drag_force * 0.8, centroid)
    end
    
    -- Add angular damping
    if math.abs(angular_velocity) > 0.01 then
        -- Scale angular damping with submersion ratio
        local angular_drag = -angular_velocity * angular_drag_coeff * submerged_area * submersion_ratio
        object:apply_torque(angular_drag)
    end
end

-- POLYGON HELPER FUNCTIONS --
-- Helper function to check if a point is inside a polygon using ray casting
function is_point_in_polygon(point, polygon)
    local inside = false
    local j = #polygon
    
    for i = 1, #polygon do
        if (polygon[i].y > point.y) ~= (polygon[j].y > point.y) and
           point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / (polygon[j].y - polygon[i].y) + polygon[i].x then
            inside = not inside
        end
        j = i
    end
    
    return inside
end

-- Calculate the area of a polygon
function calculate_polygon_area(polygon)
    local area = 0
    local n = #polygon
    local j = n
    
    for i = 1, n do
        area = area + (polygon[j].x + polygon[i].x) * (polygon[j].y - polygon[i].y)
        j = i
    end
    
    return math.abs(area) / 2
end

-- Calculate the centroid of a polygon
function calculate_polygon_centroid(polygon, area)
    -- Safety check for very small area
    if math.abs(area) < 0.0001 then
        -- If area is too small, just return center of mass of vertices
        local centroid = vec2(0, 0)
        for _, vertex in ipairs(polygon) do
            centroid = centroid + vertex
        end
        return centroid / #polygon
    end
    
    local centroid = vec2(0, 0)
    local n = #polygon
    local j = n
    
    for i = 1, n do
        local factor = polygon[j].x * polygon[i].y - polygon[i].x * polygon[j].y
        centroid.x = centroid.x + (polygon[j].x + polygon[i].x) * factor
        centroid.y = centroid.y + (polygon[j].y + polygon[i].y) * factor
        j = i
    end
    
    centroid.x = centroid.x / (6 * area)
    centroid.y = centroid.y / (6 * area)
    
    return centroid
end

-- Improved polygon clipping function with better safety checks
function clip_polygon_against_water(polygon, water_level)
    local result = {}
    local n = #polygon
    
    for i = 1, n do
        local current = polygon[i]
        local next = polygon[i % n + 1]
        
        -- Case 1: Current point is above water, next point is above water
        if current.y >= water_level and next.y >= water_level then
            -- No points added
        -- Case 2: Current point is above water, next point is below water
        elseif current.y >= water_level and next.y < water_level then
            -- Add intersection point (safely)
            local denominator = (next.y - current.y)
            if math.abs(denominator) > 0.0001 then -- Avoid division by near-zero
                local t = (water_level - current.y) / denominator
                t = math.max(0, math.min(1, t)) -- Clamp t between 0 and 1 for safety
                
                local intersection = vec2(
                    current.x + t * (next.x - current.x),
                    water_level
                )
                table.insert(result, intersection)
            end
            -- Add next point
            table.insert(result, next)
        -- Case 3: Current point is below water, next point is above water
        elseif current.y < water_level and next.y >= water_level then
            -- Add current point
            table.insert(result, current)
            -- Add intersection point (safely)
            local denominator = (next.y - current.y)
            if math.abs(denominator) > 0.0001 then -- Avoid division by near-zero
                local t = (water_level - current.y) / denominator
                t = math.max(0, math.min(1, t)) -- Clamp t between 0 and 1 for safety
                
                local intersection = vec2(
                    current.x + t * (next.x - current.x),
                    water_level
                )
                table.insert(result, intersection)
            end
        -- Case 4: Current point is below water, next point is below water
        else
            -- Add current point
            table.insert(result, current)
        end
    end
    
    return result
end
