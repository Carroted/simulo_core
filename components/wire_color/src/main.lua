local current_power = 0;
local was_activated = false;

function on_event(id, data)
    if id == "activate" then
        was_activated = true;
        if data.power then
            current_power += data.power;
        else
            current_power += 1;
        end;
    end;
end;

function get_gradient_color(current_voltage, max_voltage)
    local ratio = current_voltage / max_voltage;
    
    -- Define our color points in the gradient
    local color_points = {
        {pos = 0.0, color = Color:hex(0x964b40)}, -- Starting color (dark brown)
        {pos = 0.5, color = Color:hex(0xffa287)}, -- Mid color (light orange)
        {pos = 0.8, color = Color:hex(0xffc6b8)}, -- Later color (light peach)
        {pos = 1.0, color = Color:hex(0xffffff)}  -- Final color (white)
    };
    
    -- Find the two color points we're between
    local lower_point, upper_point
    for i = 1, #color_points - 1 do
        if ratio >= color_points[i].pos and ratio <= color_points[i+1].pos then
            lower_point = color_points[i];
            upper_point = color_points[i+1];
            break;
        end;
    end;
    
    -- If we're at or beyond the max voltage, return the final color
    if not lower_point then
        return color_points[#color_points].color;
    end;
    
    -- Calculate the blend ratio between the two points
    local blend_ratio = (ratio - lower_point.pos) / (upper_point.pos - lower_point.pos);
    
    -- Mix the two colors based on our position between them
    return Color:mix(lower_point.color, upper_point.color, blend_ratio);
end;

function on_step()
    if was_activated then
        -- Update color based on power
        self:set_color(get_gradient_color(current_power, 50));
    else
        self:set_color(0x89463d);
    end;
    
    -- Reset for next frame
    was_activated = false;
    current_power = 0;
end;