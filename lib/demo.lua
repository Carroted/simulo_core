Scene:reset();

local function add_textured_box(params)
	local box_ratio = params.texture_width / params.texture_height;
	local box_size = vec2(params.box_height * box_ratio, params.box_height);

	local box = Scene:add_box({
		position = params.position + vec2(0, -10),
		size = box_size,
		color = Color:rgba(0, 0, 0, 0),
	});

	local image_scale = params.box_height / params.texture_height;

	Scene:add_attachment({
		parent = box,
		images = {
			{
				texture = require(params.texture),
				scale = vec2(image_scale, image_scale),
                filtering = "linear",
			},
		},
	});
end;

-- Box 1
local box_1_height = 1;
add_textured_box({
	texture_width = 557.309,
	texture_height = 317.163,
	box_height = box_1_height,
	position = vec2(0.2, 4 / 2),
	texture = 'core/assets/demo/tutorial_box.png',
});

-- Box 2
add_textured_box({
	texture_width = 557.309,
	texture_height = 317.163,
	box_height = box_1_height,
	position = vec2(-0.7, box_1_height / 2),
	texture = 'core/assets/demo/tutorial_box2.png',
});

-- Box 3
local box_2_height = box_1_height * (341.176 / 317.163);
add_textured_box({
	texture_width = 420.947,
	texture_height = 341.176,
	box_height = box_2_height,
	position = vec2(1.6 - 0.7, box_2_height / 2),
	texture = 'core/assets/demo/tutorial_box3.png',
});

-- Box 4
local box_3_height = box_1_height * (579.704 / 317.163);
add_textured_box({
	texture_width = 420.947,
	texture_height = 579.704,
	box_height = box_3_height,
	position = vec2(-2.4, box_3_height / 2),
	texture = 'core/assets/demo/tutorial_box4.png',
});

-- Box 5
local box_4_height = box_1_height * (588.270 / 317.163);
add_textured_box({
	texture_width = 631,
	texture_height = 882,
	box_height = box_4_height,
	position = vec2(2.4, box_4_height / 2),
	texture = 'core/assets/demo/tutorial_box5.png',
});
