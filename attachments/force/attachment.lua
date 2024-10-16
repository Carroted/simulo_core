function on_step()
    local parent = self:get_parent();
    if parent == nil then
        self:destroy();
    else
        parent:apply_force(self:get_up_direction() * 8, self:get_position());
    end;
end;