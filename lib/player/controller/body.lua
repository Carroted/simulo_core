local Body = {}

Body.init = function(self, dependencies)
    self.Ground = dependencies.Ground
end

Body.on_start = function(self, saved_data)
    self.hinges.left_hinge = saved_data.left_hinge
    self.hinges.right_hinge = saved_data.right_hinge
    self.parts.body = saved_data.body
    self.parts.left_foot = saved_data.left_foot
    self.parts.right_foot = saved_data.right_foot
    self.parts.left_arm = saved_data.left_arm
    self.parts.right_arm = saved_data.right_arm
    self.parts.head = saved_data.head
    
    -- Configure arms
    if self.parts.left_arm then
        self.parts.left_arm:set_body_type(BodyType.Static)
        self.parts.left_arm:set_collision_layers({}) -- No collision
    end
    if self.parts.right_arm then
        self.parts.right_arm:set_body_type(BodyType.Static)
        self.parts.right_arm:set_collision_layers({}) -- No collision
    end
end

Body.on_save = function(self)
    return {
        left_hinge = self.hinges.left_hinge,
        right_hinge = self.hinges.right_hinge,
        body = self.parts.body,
        left_foot = self.parts.left_foot,
        right_foot = self.parts.right_foot,
        left_arm = self.parts.left_arm,
        right_arm = self.parts.right_arm,
        head = self.parts.head
    }
end

Body.parts = {
    body = nil;
    left_foot = nil;
    right_foot = nil;
    left_arm = nil;
    right_arm = nil;
    head = nil;
}
Body.hinges = {
    left_hinge = nil; -- Hinge for left leg
    right_hinge = nil; -- Hinge for right leg
}
Body.get_body_mass = function(self)
    local b = self.parts
    if b.body and b.left_foot and b.right_foot and 
       b.left_arm and b.right_arm and b.head then
        return b.body:get_mass() + b.left_foot:get_mass() + b.right_foot:get_mass() +
               b.left_arm:get_mass() + b.right_arm:get_mass() + b.head:get_mass()
    else
        print("Physics Error: Body parts not initialized correctly at Physics.get_body_mass."
        .. "The missing body parts are: "
        .. (b.body and "" or "body, ")
        .. (b.left_foot and "" or "left_foot, ")
        .. (b.right_foot and "" or "right_foot, ")
        .. (b.left_arm and "" or "left_arm, ")
        .. (b.right_arm and "" or "right_arm, ")
        .. (b.head and "" or "head, "))

        return 1.0
    end
end

Body.get_position = function(self)
    local body = self.parts.body
    if body then
        return body:get_position() or vec2(0, 0)
    else
        print("Error: Body component not found.")
        return vec2(0, 0)
    end
end

Body.get_world_point = function(self, vector)
    local body = self.parts.body
    if body then
        return body:get_world_point(vector) or vec2(0, 0)
    else
        print("Error: Body component not found.")
        return vec2(0, 0)
    end
end

Body.get_angular_velocity = function(self)
    local body = self.parts.body
    if body then
        return body:get_angular_velocity() or 0
    else
        print("Error: Body component not found.")
        return 0
    end
end

Body.calculate_arm_pivots = function(self, left_arm_pivot, right_arm_pivot)
    local body = self.parts.body
    local left_pivot_world = self:get_world_point(left_arm_pivot)
    local right_pivot_world = self:get_world_point(right_arm_pivot)
    if not left_pivot_world or not right_pivot_world then
        print("Error: Failed to get world pivot points.")
        left_pivot_world = self:get_position()
        right_pivot_world = self:get_position()
    end
    return left_pivot_world, right_pivot_world
end

Body.apply_all_forces = function(self, force, angular_force, straightening_force, gravity_countering_force)
    local body = self.parts.body
    if body == nil then
        print("Error: Body component not found.")
        return
    end
    body:apply_force_to_center(force)
    body:apply_torque(angular_force)
    body:apply_force_to_center(straightening_force)
    body:apply_force_to_center(gravity_countering_force)

    local left_foot = self.parts.left_foot
    local right_foot = self.parts.right_foot
    if left_foot then
        local fp_world = left_foot:get_world_point(vec2(0, -0.2))
        if fp_world then left_foot:apply_force(-straightening_force/2, fp_world) end
    end
    if right_foot then
        local fp_world = right_foot:get_world_point(vec2(0, -0.2))
        if fp_world then right_foot:apply_force(-straightening_force/2, fp_world) end
    end
    self.Ground:try_apply_force_to_ground(force*0.01)
end

return Body
