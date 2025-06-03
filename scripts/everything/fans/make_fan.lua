local function set_property_value(component, key, value)
    local prop = component:get_property(key);
    prop.value = value;
    component:set_property(key, prop);
end;

local conductor = require ('core/components/conductor');
local fan_component = Scene:add_component_def{
    name = "Fan",
    id = "@interrobang/fans/fan",
    version = "0.2.0",

    code = require("./packages/@interrobang/fans/components/fan/src/main.lua", "string"),
    icon = require("@interrobang/fans/assets/textures/icon.png"),
    properties = {
        {
            id = "multiplier",
            name = "Multiplier",
            input_type = "slider",
            default_value = 1,
            min_value = 0.1,
            max_value = 10,
        },
        {
            id = "size_multiplier",
            name = "Size Multiplier",
            input_type = "slider",
            default_value = 1,
            min_value = 0.1,
            max_value = 10,
        },
        {
            id = "disable_particles",
            name = "Disable Particles",
            input_type = "toggle",
            default_value = false,

        }
    }
}

local function make_into_fan(thingy, multiplier, size_multiplier)
        
    -- Add conductor components to base
    local conductivity = thingy:add_component({ hash = conductor });
    set_property_value(conductivity, "resistance", 0);
    set_property_value(conductivity , "exposed", true);

    local fan = thingy:add_component({hash = fan_component})
    if multiplier then
        set_property_value(fan, "multiplier", multiplier);
    end
    if size_multiplier then
        set_property_value(fan, "size_multiplier", size_multiplier);
    end
end

local small_fan = Scene:add_box{
    position = vec2(0, 0),
    size = vec2(0.1, 1), -- meters
    body_type = BodyType.Dynamic,
    color = Color:hex(0xafacac),
}
small_fan:set_density(10)
make_into_fan(small_fan)


-- local big_fan = Scene:add_box{
--     position = vec2(1, 0),
--     size = vec2(1, 4), -- meters
--     body_type = BodyType.Dynamic,
--     color = Color:hex(0xafacac),
-- }

-- big_fan:set_density(10)
-- make_into_fan(big_fan, 2)
-- local mini_fan = Scene:add_box{
--     position = vec2(2, 0),
--     size = vec2(0.1, 0.1), -- meters
--     body_type = BodyType.Dynamic,
--     color = Color:hex(0xafacac),
-- }

-- mini_fan:set_density(10)
-- make_into_fan(mini_fan, 1, 10)
-- local uber_fan = Scene:add_box{
--     position = vec2(3, 0),
--     size = vec2(0.2, 1), -- meters
--     body_type = BodyType.Dynamic,
--     color = Color:hex(0x4b64b0),
-- }
-- uber_fan:set_density(1)
-- uber_fan:set_restitution(0.5)
-- local comp = uber_fan:add_component({hash=require("core/components/free_energy")})
-- set_property_value(comp, "power", 20)
-- make_into_fan(uber_fan, 10, 1)
-- local gargantuan_fan = Scene:add_box{
--     position = vec2(10, 10),
--     size = vec2(2.5, 20), -- meters
--     body_type = BodyType.Dynamic,
--     color = Color:hex(0x373636),
-- }
-- gargantuan_fan:set_density(20)
-- make_into_fan(gargantuan_fan, 4, 1)



-- small_fan:set_name("Fan")
-- big_fan:set_name("Big Fan")
-- mini_fan:set_name("Minifan")
-- uber_fan:set_name("Überfan")
-- gargantuan_fan:set_name("Gargantu-fan")





-- local block = Scene:add_box{
--     position = vec2(-10, 0),
--     size = vec2(1, 20),
--     body_type = BodyType.Static,
--     color = Color:rgb(0.1, 0.1, 0.1), -- grey
-- }
