--[[
    Character Controller Script

    Handles:
    - Walking & Jumping
    - Picking up & Dropping objects
    - Static arms aiming held object towards pointer
    - Activation of held object components via pointer click
    - Smooth recoil effect on pointer aiming (scaled by distance, consistently upward)
    - Drop velocity calculation based on recent movement history
    - Many more! (todo: update this)
]]

-- SUBMODULES --
local Controller = {} -- Primary class.
local Legs = require("core/lib/player/controller/legs.lua") -- Handles leg animations and movement.
local Arms = require("core/lib/player/controller/arms.lua") -- Handles arm animations and holding logic.
local Recoil = require("core/lib/player/controller/recoil.lua") -- Handles recoil effects when firing weapons.

local Holding = require("core/lib/player/controller/holding.lua") -- Handles picking up and dropping objects.
    Holding.History = require("core/lib/player/controller/holding_history.lua") -- Keeps track of holding history for dropped objects.

local Movement = require("core/lib/player/controller/movement.lua") -- Applies player force changes and contains logic for special moves.
local Ground = require("core/lib/player/controller/ground.lua") -- Handles ground-related logic like friction and surface normals.
local Physics = require("core/lib/player/controller/physics.lua") -- How the player moves through the world and accelerates.
local Input = require("core/lib/player/controller/input.lua") -- Handles input polling and key mappings.
local Utils = require("core/lib/player/controller/utils.lua") -- Utility functions for vector math and other helpers.
local Body = require("core/lib/player/controller/body.lua") -- Handles the player's body parts and their properties.
local Camera = require("core/lib/player/controller/camera.lua") -- Handles camera position and movement.

local player = Scene:get_host()

Controller.init = function(self)
    -- Initialize submodules
    Legs:init({Input = Input, Body = Body})
    Arms:init({Input = Input, Holding = Holding, Recoil = Recoil, Body = Body, player = player})
    Recoil:init()
    Holding:init({})
    Holding.History:init({})
    Body:init({Ground = Ground})
    Movement:init({Input = Input, Body = Body, Physics = Physics, Ground = Ground})
    Physics:init({Body = Body, Ground = Ground, Utils = Utils})
    Ground:init({Movement = Movement, Physics = Physics, Body = Body})

    -- Others here once they get moved

    Input:init({player = player})
    Camera:init({Body = Body, player = player})
end

-- Initialization Function
function on_start(saved_data)
    Controller:init()
    Controller:on_start(saved_data)
end

Controller.on_start = function(self, saved_data)
    Body:on_start(saved_data)
    Arms:on_start(saved_data)
    Legs:on_start(saved_data)
    Recoil:on_start() -- No saved data needed for recoil
    Holding:on_start(saved_data)
end

-- Save Function
function on_save()
    return Controller:on_save()
end

Controller.on_save = function(self)
    local body_data = Body:on_save()
    local arms_data = Arms:on_save()
    local legs_data = Legs:on_save()
    local holding_data = Holding:on_save()
    
    -- Merge the data tables
    local result = {}
    for k, v in pairs(body_data) do result[k] = v end
    for k, v in pairs(arms_data) do result[k] = v end
    for k, v in pairs(legs_data) do result[k] = v end
    for k, v in pairs(holding_data) do result[k] = v end
    
    return result
end

-- Update Function (Input polling)
function on_update(dt)
    Controller:on_update(dt)
end
Controller.on_update = function(self, dt)
    Movement:handle_jump(Input:jump())
    Movement:handle_roll(Input:roll())
    Holding:handle_pick_up(Input:pick_up(), player:pointer_pos())
    Holding:handle_drop(Input:drop())
    Camera:update_camera()
end
Controller.update_timers = function(self, dt)
    -- Movement timers
    Movement:update_movement_timers(dt)
    -- Animation timers
    Recoil:update_timers(dt)
end
    
-- Step Function (Physics and main logic)
function on_step(dt)
    dt = dt or (1.0 / 60.0)
    Controller:on_step(dt)
end
function Controller.check_required_parts(self)
    local body = Body.parts.body
    local left_arm = Body.parts.left_arm
    local right_arm = Body.parts.right_arm

    if not player or not body or not left_arm or not right_arm then
        print("Error: Missing essential components (player, body, arms).\n"
    .. "The missing parts are:\n"
    .. "Player: " .. tostring(player) .. "\n"
    .. "Body: " .. tostring(body) .. "\n"
    .. "Left Arm: " .. tostring(left_arm) .. "\n"
    .. "Right Arm: " .. tostring(right_arm))
        return false
    end

    return true
end
function Controller.on_step(self, dt)
    if not self:check_required_parts() then
        return
    end

    Camera:move_camera(
        Physics:get_velocity_relative_to_ground(Body.parts.body),
        dt,
        Utils.lerp_vec2
    )

    Ground:check_ground(Body.parts.body, Body.parts)

    -- Use the Recoil.update_recoil function instead

    local left_pivot_world, right_pivot_world = Body:calculate_arm_pivots(Arms.pivots.left_arm_pivot, Arms.pivots.right_arm_pivot)

    -- Update animations and visual effects
    Recoil:update_recoil(dt, Utils.lerp_vec2)
    
    -- Calculate arm pivot positions
    local left_pivot_world, right_pivot_world = Body:calculate_arm_pivots(Arms.pivots.left_arm_pivot, Arms.pivots.right_arm_pivot)
    
    -- Handle leg animation and movement
    Legs:handle_locomotion(dt, Movement.state.jumping)
    
    -- Handle arm positioning and holding objects
    Arms:handle(left_pivot_world, right_pivot_world, Body.parts, Movement.state.jumping, Legs.State.walk_cycle_time, dt, Input.get)
    
    -- Calculate and apply physics forces
    local force, angular_force, straightening_force, gravity_countering_force = Movement:get_all_forces(dt)
    Body:apply_all_forces(force, angular_force, straightening_force, gravity_countering_force)
    
    -- Update all timers
    self:update_timers(dt)

    Movement:update_last_velocity(Body.parts.body)
    
    -- Debug controls
    -- if player:key_pressed("B") then
    --     Movement:begin_spin()
    -- end
end
