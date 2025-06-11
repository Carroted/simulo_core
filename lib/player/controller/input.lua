local Input = {}

local player = nil

Input.on_start = function(self, input_player)
    player = input_player
    if not player then
        print("Warning: Player not found on Input start.")
    end
end
Input.keymap = {
    jump = "W"; -- Jump
    move_left = "A"; -- Move left
    move_right = "D"; -- Move right
    pick_up = "E"; -- Pick up object
    drop = "Q"; -- Drop object
    roll = "S"; -- Roll (left/right movement)
}
Input.get = {
    jump = function() return player:key_just_pressed(Input.keymap.jump) end, -- Only works in on_update()
    hold_jump = function() return player:key_pressed(Input.keymap.jump) end,
    move_left = function() return player:key_pressed(Input.keymap.move_left) end,
    move_right = function() return player:key_pressed(Input.keymap.move_right) end,
    pick_up = function() return player:key_just_pressed(Input.keymap.pick_up) end, -- Only works in on_update()
    drop = function() return player:key_just_pressed(Input.keymap.drop) end, -- Only works in on_update()
    roll = function() return player:key_just_pressed(Input.keymap.roll) end, -- Only works in on_update()
}

return Input
