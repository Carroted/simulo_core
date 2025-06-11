local Utils = {}

Utils.dot = function(v1, v2)
    return v1.x * v2.x + v1.y * v2.y
end
Utils.reflect = function(v, normal)
    local v_mag = v:magnitude()
    v = v:normalize()
    normal = normal:normalize()
    local dot_product = Utils.dot(v, normal)
    return vec2(v.x - 2 * dot_product * normal.x, v.y - 2 * dot_product * normal.y) * v_mag
end
Utils.lerp_vec2 = function(v1, v2, t)
    t = math.clamp(t, 0, 1)
    return vec2(
        v1.x * (1 - t) + v2.x * t,
        v1.y * (1 - t) + v2.y * t
    )
end

return Utils
