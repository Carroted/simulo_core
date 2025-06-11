local Input = {}
Input.player = Scene:get_host()
Input.init = function(self, dependencies)
    self.player = dependencies.player
end
Input.keymap = {
    jump = "W"; -- Jump
    move_left = "A"; -- Move left
    move_right = "D"; -- Move right
    pick_up = "E"; -- Pick up object
    drop = "Q"; -- Drop object
    roll = "S"; -- Roll (left/right movement)
}
Input.jump = function(self) return self.player:key_just_pressed(self.keymap.jump) end -- Only works in on_update()
Input.hold_jump = function(self) return self.player:key_pressed(self.keymap.jump) end
Input.move_left = function(self) return self.player:key_pressed(self.keymap.move_left) end
Input.move_right = function(self) return self.player:key_pressed(self.keymap.move_right) end
Input.pick_up = function(self) return self.player:key_just_pressed(self.keymap.pick_up) end -- Only works in on_update()
Input.drop = function(self) return self.player:key_just_pressed(self.keymap.drop) end -- Only works in on_update()
Input.roll = function(self) return self.player:key_just_pressed(self.keymap.roll) end -- Only works in on_update()
Input.hold_roll = function(self) return self.player:key_pressed(self.keymap.roll) end

return Input
