function on_step()
    self:get_object():apply_force(self:get_up_direction() * 8, self:get_position());
end;