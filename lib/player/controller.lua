--[[
    Character Controller Script

    Handles:
    - Walking & Jumping
    - Picking up & Dropping objects
    - Static arms aiming held object towards pointer
    - Activation of held object components via pointer click
    - Smooth recoil effect on pointer aiming (scaled by distance, consistently upward)
    - Drop velocity calculation based on recent movement history
]]

-- Component Handles & References
local left_hinge = nil;
local right_hinge = nil;
local body = nil;
local left_foot = nil;
local right_foot = nil;
local left_arm = nil;
local right_arm = nil;

local player = Scene:get_host();

-- Holding State Variables
local holding = nil;
local holding_point_left = nil;  -- Local point on object for LEFT arm when NOT flipped
local holding_point_right = nil; -- Local point on object for RIGHT arm when NOT flipped
local original_holding_layers = nil;
local original_holding_bodytype = nil;

-- Arm Configuration
local left_arm_pivot = vec2(0, 0);
local right_arm_pivot = vec2(0, 0);
local NEUTRAL_ARM_ANGLE_REL = math.rad(58);
local JUMP_TUCK_ARM_ANGLE_REL = math.rad(10);

-- Camera & Movement Configuration
local cam_pos = vec2(0, 0);

local WALK_CYCLE_SPEED = 30.0;
local WALK_SWING_AMPLITUDE = math.rad(35);
local JUMP_TUCK_ANGLE = math.rad(20);
local NEUTRAL_ANGLE = math.rad(0);
local LEG_ANGLE_CONTROL_KP = 50.0;
local MAX_MOTOR_SPEED_FOR_LEG_CONTROL = 15.0;
local WALK_TORQUE = 200.0;
local JUMP_TORQUE = 250.0;
local IDLE_TORQUE = 5.0;
local NUDGE_IMPULSE = 0.04;
local HORIZONTAL_DAMPING_FACTOR = 0.2;
local MAX_HOLD_DISTANCE = 0.4;

-- Velocity History Tracking (for Drops)
local max_history_frames = 10;
local holding_history_buffer = {};
local history_index = 0;
local holding_cumulative_time = 0;

-- Ground State & Jumping
local on_ground = false;
local ground_friction = 0.1;
local ground_surface_normal = vec2(0, 1);
local jumping = false;
local jump_end_timer = 0;

-- Activation & Recoil State
local FIRE_COOLDOWN_DURATION = 0.3;
local fire_cooldown_timer = 0;
local target_pointer_recoil_offset = vec2(0, 0);
local current_pointer_recoil_offset = vec2(0, 0);
local RECOIL_APPLICATION_SPEED = 40.0; -- Updated Constant
local RECOIL_DECAY_SPEED = 10.0;   -- Updated Constant
local MIN_RECOIL_DISTANCE_CLAMP = 0.1;

-- General State & Helpers
local walk_cycle_time = 0;
local NO_COLLISION_LAYERS = {};

-- Helper to clear holding history and reset cumulative time
local function clear_holding_history()
    holding_history_buffer = {}
    history_index = 0
    holding_cumulative_time = 0
    -- print("Cleared holding history and cumulative time.")
end

-- Initialization Function
function on_start(saved_data)
    left_hinge = saved_data.left_hinge;
    right_hinge = saved_data.right_hinge;
    body = saved_data.body;
    left_foot = saved_data.left_foot;
    right_foot = saved_data.right_foot;
    left_arm = saved_data.left_arm;
    right_arm = saved_data.right_arm;

    left_arm_pivot = saved_data.left_arm_pivot or vec2(-0.1, 0.15);
    right_arm_pivot = saved_data.right_arm_pivot or vec2(0.1, 0.15);

    holding = saved_data.holding;
    holding_point_left = saved_data.holding_point_left;
    holding_point_right = saved_data.holding_point_right;
    original_holding_layers = saved_data.original_holding_layers;
    original_holding_bodytype = saved_data.original_holding_bodytype;

    walk_cycle_time = saved_data.walk_cycle_time or 0;

    clear_holding_history()
    fire_cooldown_timer = 0;
    target_pointer_recoil_offset = vec2(0, 0);
    current_pointer_recoil_offset = vec2(0, 0);

    if body then
        cam_pos = body:get_position();
    else
        cam_pos = vec2(0,0)
         print("Warning: Body component not found on start.")
    end

    if left_arm then
        left_arm:set_body_type(BodyType.Static);
        left_arm:set_collision_layers(NO_COLLISION_LAYERS);
    end
    if right_arm then
        right_arm:set_body_type(BodyType.Static);
        right_arm:set_collision_layers(NO_COLLISION_LAYERS);
    end

    if holding then
         if holding:get_body_type() ~= BodyType.Static then
              print("Warning: Held object was not static on load, forcing static.")
              holding:set_body_type(BodyType.Static)
         end
         holding:set_collision_layers(NO_COLLISION_LAYERS);
    end

    if player and body then player:set_camera_position(cam_pos + vec2(0, 0.6)) end
end;

-- Save Function
function on_save()
    return {
        left_hinge = left_hinge, right_hinge = right_hinge,
        body = body, left_foot = left_foot, right_foot = right_foot,
        left_arm = left_arm, right_arm = right_arm,
        left_arm_pivot = left_arm_pivot, right_arm_pivot = right_arm_pivot,
        walk_cycle_time = walk_cycle_time,
        holding_cumulative_time = holding_cumulative_time,
        holding = holding,
        holding_point_left = holding_point_left, holding_point_right = holding_point_right,
        original_holding_layers = original_holding_layers, original_holding_bodytype = original_holding_bodytype,
    };
end;

-- Helper Functions

local function set_leg_hinge_motor(hinge, speed, torque)
    if not hinge then return end;
    local speed_prop = hinge:get_property("motor_speed");
    if speed_prop then
        speed_prop.value = -speed;
        hinge:set_property("motor_speed", speed_prop);
    else
         print("Warning: motor_speed property not found for leg hinge")
    end;
    local torque_prop = hinge:get_property("max_motor_torque");
    if torque_prop then
        torque_prop.value = torque;
        hinge:set_property("max_motor_torque", torque_prop);
    else
         print("Warning: max_motor_torque property not found for leg hinge")
    end;
end;

local function get_current_leg_hinge_angle(hinge_component)
    if not hinge_component then return nil end
    local joint = hinge_component:send_event("core/hinge/get");
    if not joint then return nil end
    local obj_a = joint:get_object_a();
    local obj_b = joint:get_object_b();
    if not obj_a or not obj_b then return nil end
    local angle_a = obj_a:get_angle();
    local angle_b = obj_b:get_angle();
    local relative_angle = angle_b - angle_a;
    relative_angle = math.atan2(math.sin(relative_angle), math.cos(relative_angle));
    return relative_angle;
end

local function calculate_motor_speed_for_leg_angle(current_angle, target_angle, kp, max_speed)
    if current_angle == nil then return 0 end
    local angle_error = target_angle - current_angle;
    angle_error = math.atan2(math.sin(angle_error), math.cos(angle_error));
    local desired_speed = kp * angle_error;
    desired_speed = math.clamp(desired_speed, -max_speed, max_speed);
    return -desired_speed;
end

local function lerp_vec2(v1, v2, t)
    t = math.clamp(t, 0, 1)
    return vec2(
        v1.x * (1 - t) + v2.x * t,
        v1.y * (1 - t) + v2.y * t
    )
end

local function pick_up(object_to_hold, local_left_hold_point, local_right_hold_point)
    if holding or not object_to_hold then
        return
    end
    if not local_left_hold_point or not local_right_hold_point then
         print("Cannot pick up: Missing local hold points.")
        return
    end

    holding = object_to_hold;
    holding_point_left = local_left_hold_point;
    holding_point_right = local_right_hold_point;

    original_holding_layers = holding:get_collision_layers();
    original_holding_bodytype = holding:get_body_type();

    holding:set_body_type(BodyType.Static);
    holding:set_collision_layers(NO_COLLISION_LAYERS);

    clear_holding_history();
end

local function drop_object()
    if not holding then
        return
    end

    local dropped_object = holding

    if original_holding_bodytype ~= nil then
         dropped_object:set_body_type(original_holding_bodytype);
    else
         dropped_object:set_body_type(BodyType.Dynamic);
         print("Warning: Could not restore original body type for held object.")
    end

    if type(original_holding_layers) == "table" then
        dropped_object:set_collision_layers(original_holding_layers);
    else
        dropped_object:set_collision_layers({1})
         print("Warning: Could not restore original collision layers for held object.")
    end

    local linear_velocity = vec2(0, 0)
    local angular_velocity = 0
    local current_buffer_size = #holding_history_buffer
    if current_buffer_size >= 5 then
        local index_now = history_index
        local index_prev = (history_index - 4 + max_history_frames) % max_history_frames + 1
        local data_now = holding_history_buffer[index_now]
        local data_prev = holding_history_buffer[index_prev]
        if data_now and data_prev then
            local time_diff = data_now.time - data_prev.time
            if time_diff > 0.001 then
                local pos_diff = data_now.pos - data_prev.pos
                linear_velocity = pos_diff / time_diff
                local angle_diff = data_now.angle - data_prev.angle
                angle_diff = math.atan2(math.sin(angle_diff), math.cos(angle_diff))
                angular_velocity = angle_diff / time_diff
            end
        end
    end

    dropped_object:set_linear_velocity(linear_velocity);
    dropped_object:set_angular_velocity(angular_velocity);

    holding = nil;
    holding_point_left = nil;
    holding_point_right = nil;
    original_holding_layers = nil;
    original_holding_bodytype = nil;
end

-- Update Function (Input polling)
function on_update(dt)
    local function handle_jump()
        if player:key_just_pressed("W") and on_ground then
            if body then body:apply_linear_impulse_to_center(vec2(0, 2)); end
            jumping = true;
            jump_end_timer = 0.5;
        end
    end

    local function handle_pick_up()
        if player:key_just_pressed("E") then
            if holding then
                drop_object()
            end
            local objs = Scene:get_objects_in_circle({ position = player:pointer_pos(), radius = 0 });
            for i = 1, #objs do
                if (objs[i]:get_body_type() == BodyType.Dynamic) and (objs[i]:get_mass() < 1) then
                    pick_up(objs[i], vec2(-0.075, 0), vec2(0.075, 0));
                    break;
                end
            end
        end
    end

    local function handle_drop()
        if player:key_just_pressed("Q") then
            if holding then
                drop_object()
            end
        end
    end

    local function update_camera()
        if player and cam_pos then
            player:set_camera_position(cam_pos)
        end
    end

    handle_jump()
    handle_pick_up()
    handle_drop()
    update_camera()
end

-- Step Function (Physics and main logic)
function on_step(dt)
    dt = dt or (1.0 / 60.0)

    if not body or not player or not left_arm or not right_arm then
        print("on_step Error: Missing essential components (body, player, arms).")
        return
    end

    local function update_camera()
        local target_cam_pos = body:get_position() + vec2(0, 0.6)
        cam_pos = lerp_vec2(cam_pos, target_cam_pos, dt * 4)
        player:set_camera_position(cam_pos)
    end

    local function check_ground()
        local ground_check_origin = body:get_world_point(vec2(0, -0.2))
        if ground_check_origin then
            local hits = Scene:raycast({
                origin = ground_check_origin, direction = vec2(0, -1),
                distance = 0.2, closest_only = false,
            })
            on_ground = false
            local current_ground_normal = vec2(0, 1)
            local current_ground_friction = 0.1
            for i = 1, #hits do
                local visited = {}
                local found = {}
                local function scan_connected(obj)
                    if obj == nil or visited[obj.id] then return end
                    visited[obj.id] = true
                    table.insert(found, obj)
                    local connected_objs = obj:get_direct_connected()
                    for _, next_obj in ipairs(connected_objs) do scan_connected(next_obj) end
                end
                scan_connected(hits[i].object)
                local connected_to_self = false
                for _, obj in ipairs(found) do
                    if obj.id == body.id then
                        connected_to_self = true
                        break
                    end
                end
                if not connected_to_self then
                    on_ground = true
                    current_ground_normal = hits[i].normal
                    current_ground_friction = hits[i].object:get_friction()
                    if jump_end_timer <= 0 then jumping = false end
                    break
                end
            end
            ground_surface_normal = current_ground_normal
            ground_friction = current_ground_friction
        else
            on_ground = false
            jumping = true
            ground_surface_normal = vec2(0, 1)
            ground_friction = 0.1
        end
        jump_end_timer = math.max(0, jump_end_timer - dt)
    end

    local function update_recoil()
        fire_cooldown_timer = math.max(0, fire_cooldown_timer - dt)
        current_pointer_recoil_offset = lerp_vec2(current_pointer_recoil_offset, target_pointer_recoil_offset, dt * RECOIL_APPLICATION_SPEED)
        target_pointer_recoil_offset = lerp_vec2(target_pointer_recoil_offset, vec2(0, 0), dt * RECOIL_DECAY_SPEED)
        if target_pointer_recoil_offset:length() ^ 2 < 0.00001 then
            target_pointer_recoil_offset = vec2(0, 0)
            if current_pointer_recoil_offset:length() ^ 2 < 0.00001 then
                current_pointer_recoil_offset = vec2(0, 0)
            end
        end
    end

    local function calculate_arm_pivots()
        local left_pivot_world = body:get_world_point(left_arm_pivot)
        local right_pivot_world = body:get_world_point(right_arm_pivot)
        if not left_pivot_world or not right_pivot_world then
            print("on_step Error: Failed to get world pivot points.")
            left_pivot_world = body:get_position()
            right_pivot_world = body:get_position()
        end
        return left_pivot_world, right_pivot_world
    end

    local function calculate_nudge_direction()
        if jumping then
            return 0;
        end;
        local move_left = player:key_pressed("A");
        local move_right = player:key_pressed("D");
        if move_left and not move_right then
            return -1;
        elseif move_right and not move_left then
            return 1;
        else
            return 0;
        end;
    end

    local function handle_locomotion(left_pivot_world, right_pivot_world)
        local move_left = player:key_pressed("A")
        local move_right = player:key_pressed("D")
        local target_left_leg_angle = NEUTRAL_ANGLE
        local target_right_leg_angle = NEUTRAL_ANGLE
        local target_leg_torque = IDLE_TORQUE

        if jumping then
            target_left_leg_angle = JUMP_TUCK_ANGLE
            target_right_leg_angle = -JUMP_TUCK_ANGLE
            target_leg_torque = JUMP_TORQUE
        elseif move_left or move_right then
            local body_vel = body:get_linear_velocity()
            local horizontal_vel_mag = (body_vel and math.abs(body_vel.x)) or 0
            local vel_scale = math.min(math.max(horizontal_vel_mag, 0.4), 1.0)
            walk_cycle_time = walk_cycle_time + (dt * WALK_CYCLE_SPEED * vel_scale)
            local swing_offset = math.sin(walk_cycle_time) * WALK_SWING_AMPLITUDE
            target_left_leg_angle = NEUTRAL_ANGLE + swing_offset * vel_scale
            target_right_leg_angle = NEUTRAL_ANGLE - swing_offset * vel_scale
            target_leg_torque = WALK_TORQUE
        else
            target_left_leg_angle = NEUTRAL_ANGLE
            target_right_leg_angle = NEUTRAL_ANGLE
            target_leg_torque = IDLE_TORQUE
        end

        if left_hinge and right_hinge then
            local current_left_leg_angle = get_current_leg_hinge_angle(left_hinge)
            local current_right_leg_angle = get_current_leg_hinge_angle(right_hinge)
            local desired_left_leg_speed = calculate_motor_speed_for_leg_angle(current_left_leg_angle, target_left_leg_angle, LEG_ANGLE_CONTROL_KP, MAX_MOTOR_SPEED_FOR_LEG_CONTROL)
            local desired_right_leg_speed = calculate_motor_speed_for_leg_angle(current_right_leg_angle, target_right_leg_angle, LEG_ANGLE_CONTROL_KP, MAX_MOTOR_SPEED_FOR_LEG_CONTROL)
            set_leg_hinge_motor(left_hinge, desired_left_leg_speed, target_leg_torque)
            set_leg_hinge_motor(right_hinge, desired_right_leg_speed, target_leg_torque)
        end
    end

    local function apply_forces()
        nudge_direction = calculate_nudge_direction()

        body:apply_force_to_center(ground_surface_normal * 10)
        if left_foot then
            local fp_world = left_foot:get_world_point(vec2(0, -0.2))
            if fp_world then left_foot:apply_force(ground_surface_normal * -5, fp_world) end
        end
        if right_foot then
            local fp_world = right_foot:get_world_point(vec2(0, -0.2))
            if fp_world then right_foot:apply_force(ground_surface_normal * -5, fp_world) end
        end

        if math.abs(nudge_direction) > 0.05 then
            body:apply_linear_impulse_to_center(vec2(nudge_direction * NUDGE_IMPULSE, 0))
        elseif on_ground then
            local current_velocity = body:get_linear_velocity()
            if current_velocity then
                local damping_impulse_x = -HORIZONTAL_DAMPING_FACTOR * ground_friction * current_velocity.x
                body:apply_linear_impulse_to_center(vec2(damping_impulse_x, 0))
            end
        end
    end

    local function handle_arms_holding(left_pivot_world, right_pivot_world)
        if not holding then
            return;
        end;
        -- Currently Holding an Object

        local hold_center = (left_pivot_world + right_pivot_world) / 2.0;

        -- Calculate effective pointer position including scaled, smoothed recoil
        local raw_pointer_pos = player:pointer_pos()
        local distance_to_pointer = (raw_pointer_pos - hold_center):length()
        local scale_factor = math.max(MIN_RECOIL_DISTANCE_CLAMP, distance_to_pointer)
        local effective_recoil_offset = current_pointer_recoil_offset * scale_factor
        local pointer_world = raw_pointer_pos + effective_recoil_offset;

        -- Calculate aiming direction vector and distance
        local hold_direction_vec = pointer_world - hold_center;
        local current_aim_dist = hold_direction_vec:length();
        local effective_hold_dist = math.min(current_aim_dist, MAX_HOLD_DISTANCE);

        -- Calculate normalized aiming direction
        local hold_direction_normalized;
        if current_aim_dist < 0.001 then
             hold_direction_normalized = body:get_right_direction() or vec2(1,0);
             effective_hold_dist = 0;
        else
             hold_direction_normalized = hold_direction_vec:normalize();
        end

        -- Calculate target position and base angle
        local target_holding_pos = hold_center + hold_direction_normalized * effective_hold_dist;
        local target_holding_angle = math.atan2(hold_direction_normalized.y, hold_direction_normalized.x);

        -- Determine if the object should be visually flipped
        local is_flipped = (pointer_world.x < hold_center.x);

        -- Apply visual flip to angle if needed
        if false then
            target_holding_angle = target_holding_angle + math.pi
            target_holding_angle = math.atan2(math.sin(target_holding_angle), math.cos(target_holding_angle))
        end

        -- Set the held object's final transform
        holding:set_position(target_holding_pos);
        holding:set_angle(target_holding_angle);

        -- Update drop velocity history buffer
        holding_cumulative_time = holding_cumulative_time + dt
        history_index = (history_index % max_history_frames) + 1
        holding_history_buffer[history_index] = {
             pos = target_holding_pos, angle = target_holding_angle, time = holding_cumulative_time
        }

        -- Position the static arms - **CRITICAL CHANGE HERE**
        local target_left_hand_world = nil
        local target_right_hand_world = nil

        -- Determine which local points on the held object the arms should connect to
        -- This ensures arms connect correctly regardless of the object's visual flip
        local effective_left_hold_point = holding_point_left   -- Default: left arm connects to left point
        local effective_right_hold_point = holding_point_right -- Default: right arm connects to right point

        if is_flipped then
            -- If visually flipped, swap the effective points
            effective_left_hold_point = holding_point_right -- Left arm connects to what *was* the right point
            effective_right_hold_point = holding_point_left  -- Right arm connects to what *was* the left point
        end

        -- Get the world coordinates of these effective connection points
        target_left_hand_world = holding:get_world_point(effective_left_hold_point);
        target_right_hand_world = holding:get_world_point(effective_right_hold_point);


        -- Calculate arm angles based on the determined target points
        if not target_left_hand_world or not target_right_hand_world then
             print("Holding logic error: Cannot get world points on held object.")
        else
             local left_arm_full_vector = target_left_hand_world - left_pivot_world;
             local right_arm_full_vector = target_right_hand_world - right_pivot_world;
             -- Keep the Pi offset for the left arm assuming its sprite points rightwards initially
             local left_arm_angle = math.atan2(left_arm_full_vector.y, left_arm_full_vector.x) + math.pi;
             local right_arm_angle = math.atan2(right_arm_full_vector.y, right_arm_full_vector.x);
             left_arm_angle = math.atan2(math.sin(left_arm_angle), math.cos(left_arm_angle));
             right_arm_angle = math.atan2(math.sin(right_arm_angle), math.cos(right_arm_angle));
             left_arm:set_position(left_pivot_world); left_arm:set_angle(left_arm_angle);
             right_arm:set_position(right_pivot_world); right_arm:set_angle(right_arm_angle);
        end

        -- Activation Check
        if player:pointer_pressed() and fire_cooldown_timer <= 0 then
            fire_cooldown_timer = FIRE_COOLDOWN_DURATION;
            local total_recoil_this_frame = 0;
            local holding_components = holding:get_components();
            for i=1,#holding_components do
                local output = holding_components[i]:send_event("activate");
                if type(output) == "table" and type(output.recoil) == "number" then
                    total_recoil_this_frame = total_recoil_this_frame + output.recoil;
                end
            end;

            if total_recoil_this_frame > 0 then
                if hold_direction_normalized then
                    local perp_recoil_dir = vec2(-hold_direction_normalized.y, hold_direction_normalized.x)
                    if perp_recoil_dir.y < 0 then
                        perp_recoil_dir = perp_recoil_dir * -1 -- Ensure upward recoil
                    end
                    local recoil_impulse_vector = perp_recoil_dir * total_recoil_this_frame;
                    target_pointer_recoil_offset = target_pointer_recoil_offset + recoil_impulse_vector;
                else
                    print("Warning: Cannot calculate recoil direction because aim direction is degenerate.")
                end
            end
        end -- End of activation check
    end

    local function handle_arms_neutral(left_pivot_world, right_pivot_world)
            -- Handle logic for neutral arm positions
            local target_left_arm_rel_angle = NEUTRAL_ARM_ANGLE_REL
            local target_right_arm_rel_angle = -NEUTRAL_ARM_ANGLE_REL

            if jumping then
                target_left_arm_rel_angle = target_left_arm_rel_angle + JUMP_TUCK_ARM_ANGLE_REL
                target_right_arm_rel_angle = target_right_arm_rel_angle - JUMP_TUCK_ARM_ANGLE_REL
            elseif player:key_pressed("A") or player:key_pressed("D") then
                local body_vel = body:get_linear_velocity()
                local horizontal_vel_mag = (body_vel and math.abs(body_vel.x)) or 0
                local vel_scale = math.min(math.max(horizontal_vel_mag, 0.4), 1.0)
                local swing_offset = math.sin(walk_cycle_time) * WALK_SWING_AMPLITUDE
                target_left_arm_rel_angle = NEUTRAL_ARM_ANGLE_REL - (swing_offset * vel_scale * 0.6)
                target_right_arm_rel_angle = -NEUTRAL_ARM_ANGLE_REL + (swing_offset * vel_scale * 0.6)
            end

            local body_angle = body:get_angle()
            local final_world_left_arm_angle = body_angle + target_left_arm_rel_angle
            local final_world_right_arm_angle = body_angle + target_right_arm_rel_angle

            left_arm:set_position(left_pivot_world)
            left_arm:set_angle(final_world_left_arm_angle)
            right_arm:set_position(right_pivot_world)
            right_arm:set_angle(final_world_right_arm_angle)
    end

    local function handle_arms(left_pivot_world, right_pivot_world)
        if holding then
            -- Handle logic for holding an object
            handle_arms_holding(left_pivot_world, right_pivot_world)
        else
            -- Handle logic for neutral arm positions
            handle_arms_neutral(left_pivot_world, right_pivot_world)
        end
    end

    --local debug = player:key_pressed("T")

    update_camera()
    check_ground()
    update_recoil()
    local left_pivot_world, right_pivot_world = calculate_arm_pivots()
    --if not debug then
        handle_locomotion(left_pivot_world, right_pivot_world)
    --end
    apply_forces()
    handle_arms(left_pivot_world, right_pivot_world)
end
