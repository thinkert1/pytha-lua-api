local DOOR_TYPES = {"Hinged", "Sliding"}
local MATERIALS = {"Melamine White", "Oak Veneer", "Walnut Veneer", "Raw MDF"}
local HARDWARES = {"Standard", "Soft-Close", "Premium"}

local function clamp(value, min_value)
	if value == nil then return min_value end
	if value < min_value then return min_value end
	return value
end

local function remove_existing_geometry(data)
	if data.main_group == nil then return end
	local descendants = pytha.get_group_descendants(data.main_group)
	if descendants ~= nil and #descendants > 0 then
		pytha.delete_element(descendants)
	end
	pytha.delete_element(data.main_group)
	data.main_group = nil
end

local function add_part(data, element, part_name, l, w, t)
	table.insert(data.current_parts, {
		name = part_name,
		length = l,
		width = w,
		thickness = t,
		material = data.material_name,
		hardware = data.hardware_name
	})
	return element
end

local function compartment_height(data)
	return data.height - data.kick_height - 2 * data.panel_thickness
end

local function internal_width(data)
	return data.width - 2 * data.panel_thickness - data.partition_count * data.panel_thickness
end

local function section_width(data)
	local n_sections = data.partition_count + 1
	return internal_width(data) / n_sections
end

local function build_carcass(data)
	local elements = {}
	local t = data.panel_thickness
	local origin = data.origin
	local z0 = origin[3]

	local left = pytha.create_block(t, data.depth, data.height, {origin[1], origin[2], z0}, {name = "Side Left"})
	table.insert(elements, add_part(data, left, "Side Left", data.height, data.depth, t))

	local right = pytha.create_block(t, data.depth, data.height, {origin[1] + data.width - t, origin[2], z0}, {name = "Side Right"})
	table.insert(elements, add_part(data, right, "Side Right", data.height, data.depth, t))

	local bottom = pytha.create_block(data.width - 2 * t, data.depth, t,
		{origin[1] + t, origin[2], z0 + data.kick_height}, {name = "Bottom"})
	table.insert(elements, add_part(data, bottom, "Bottom", data.width - 2 * t, data.depth, t))

	local top = pytha.create_block(data.width - 2 * t, data.depth, t,
		{origin[1] + t, origin[2], z0 + data.height - t}, {name = "Top"})
	table.insert(elements, add_part(data, top, "Top", data.width - 2 * t, data.depth, t))

	local back = pytha.create_block(data.width - 2 * t, t, data.height - data.kick_height,
		{origin[1] + t, origin[2] + data.depth - t, z0 + data.kick_height}, {name = "Back"})
	table.insert(elements, add_part(data, back, "Back", data.width - 2 * t, data.height - data.kick_height, t))

	local kick = pytha.create_block(data.width, t, data.kick_height,
		{origin[1], origin[2] + data.depth - t, z0}, {name = "Kick"})
	table.insert(elements, add_part(data, kick, "Kick", data.width, data.kick_height, t))

	return elements
end

local function build_partitions(data, elements)
	local t = data.panel_thickness
	local sw = section_width(data)
	for i = 1, data.partition_count do
		local x = data.origin[1] + t + i * sw + (i - 1) * t
		local part = pytha.create_block(t, data.depth, data.height - data.kick_height - t,
			{x, data.origin[2], data.origin[3] + data.kick_height + t}, {name = "Partition " .. i})
		table.insert(elements, add_part(data, part, "Partition", data.height - data.kick_height - t, data.depth, t))
	end
end

local function build_shelves(data, elements)
	local t = data.panel_thickness
	if data.shelf_count <= 0 then return end
	local sw = section_width(data)
	local n_sections = data.partition_count + 1
	local usable_h = compartment_height(data)
	for s = 1, n_sections do
		local x_start = data.origin[1] + t + (s - 1) * (sw + t)
		for i = 1, data.shelf_count do
			local z = data.origin[3] + data.kick_height + t + i * usable_h / (data.shelf_count + 1)
			local shelf = pytha.create_block(sw, data.depth - t, t, {x_start, data.origin[2], z}, {name = "Shelf " .. s .. "-" .. i})
			table.insert(elements, add_part(data, shelf, "Shelf", sw, data.depth - t, t))
		end
	end
end

local function build_drawers(data, elements)
	if data.drawer_count <= 0 then return end
	local t = data.panel_thickness
	local sw = section_width(data)
	local drawer_box_depth = data.depth * 0.85
	local usable_h = compartment_height(data)
	local drawer_h = usable_h / (data.drawer_count + 1)
	local x = data.origin[1] + t
	for i = 1, data.drawer_count do
		local z = data.origin[3] + data.kick_height + t + (i - 1) * drawer_h
		local front = pytha.create_block(sw, t, drawer_h * 0.9,
			{x, data.origin[2] - t, z}, {name = "Drawer Front " .. i})
		table.insert(elements, add_part(data, front, "Drawer Front", sw, drawer_h * 0.9, t))

		local box = pytha.create_block(sw - 2 * t, drawer_box_depth, drawer_h * 0.7,
			{x + t, data.origin[2] + t, z}, {name = "Drawer Box " .. i})
		table.insert(elements, add_part(data, box, "Drawer Box", sw - 2 * t, drawer_box_depth, drawer_h * 0.7))
	end
end

local function build_doors(data, elements)
	local t = data.panel_thickness
	local z = data.origin[3] + data.kick_height
	local door_h = data.height - data.kick_height
	if data.door_type_index == 1 then
		local n_doors = math.max(2, data.partition_count + 1)
		local door_w = data.width / n_doors
		for i = 1, n_doors do
			local x = data.origin[1] + (i - 1) * door_w
			local door = pytha.create_block(door_w, t, door_h, {x, data.origin[2] - t, z}, {name = "Hinge Door " .. i})
			table.insert(elements, add_part(data, door, "Hinged Door", door_w, door_h, t))
		end
	else
		local overlap = data.width * 0.05
		local panel_w = data.width / 2 + overlap
		local door_a = pytha.create_block(panel_w, t, door_h,
			{data.origin[1], data.origin[2] - t * 2.5, z}, {name = "Sliding Door A"})
		local door_b = pytha.create_block(panel_w, t, door_h,
			{data.origin[1] + data.width - panel_w, data.origin[2] - t, z}, {name = "Sliding Door B"})
		table.insert(elements, add_part(data, door_a, "Sliding Door", panel_w, door_h, t))
		table.insert(elements, add_part(data, door_b, "Sliding Door", panel_w, door_h, t))
	end
end

local function compute_production_summary(data)
	local summary = {}
	summary.total_parts = #data.current_parts
	summary.total_panel_area = 0
	summary.part_counts = {}

	for _, part in pairs(data.current_parts) do
		local area = (part.length * part.width) / 1000000.0
		summary.total_panel_area = summary.total_panel_area + area
		summary.part_counts[part.name] = (summary.part_counts[part.name] or 0) + 1
	end

	local hardware_map = {
		["Standard"] = {hinge = 2, slide = 1, handle = 1},
		["Soft-Close"] = {hinge = 3, slide = 1, handle = 1},
		["Premium"] = {hinge = 4, slide = 1, handle = 1}
	}
	local hw = hardware_map[data.hardware_name] or hardware_map["Standard"]
	local section_count = data.partition_count + 1
	local door_count = (data.door_type_index == 1) and math.max(2, section_count) or 2
	summary.hardware = {
		hinges = (data.door_type_index == 1) and door_count * hw.hinge or 0,
		slides = data.drawer_count * hw.slide,
		handles = door_count * hw.handle + data.drawer_count * hw.handle
	}
	return summary
end

local function refresh_report(report_box, data)
	local summary = compute_production_summary(data)
	local text = ""
	text = text .. "Material: " .. data.material_name .. "\n"
	text = text .. "Hardware Pack: " .. data.hardware_name .. "\n"
	text = text .. "Total Parts: " .. summary.total_parts .. "\n"
	text = text .. "Panel Area (m2): " .. string.format("%.2f", summary.total_panel_area) .. "\n"
	text = text .. "Hinges: " .. summary.hardware.hinges .. ", Slides: " .. summary.hardware.slides .. ", Handles: " .. summary.hardware.handles
	report_box:set_control_text(text)
	data.production_report = {
		parameters = {
			width = data.width,
			height = data.height,
			depth = data.depth,
			partition_count = data.partition_count,
			shelf_count = data.shelf_count,
			drawer_count = data.drawer_count,
			door_type = data.door_type_index,
			panel_thickness = data.panel_thickness,
			kick_height = data.kick_height,
			material = data.material_name,
			hardware = data.hardware_name
		},
		parts = data.current_parts,
		summary = summary
	}
end

function regenerate_wardrobe(data, report_box)
	remove_existing_geometry(data)
	data.current_parts = {}

	local elements = build_carcass(data)
	build_partitions(data, elements)
	build_shelves(data, elements)
	build_drawers(data, elements)
	build_doors(data, elements)
	data.main_group = pytha.create_group(elements, {name = "Wardrobe"})
	pytha.set_element_history(data.main_group, data, "wardrobe_generator_history")
	if report_box ~= nil then
		refresh_report(report_box, data)
	end
end

function wardrobe_dialog(dialog, data)
	dialog:set_window_title("Wardrobe Generator")

	dialog:create_label(1, "Wardrobe width")
	local width = dialog:create_text_box(2, pyui.format_length(data.width))
	dialog:create_label(3, "Height")
	local height = dialog:create_text_box(4, pyui.format_length(data.height))

	dialog:create_label(1, "Depth")
	local depth = dialog:create_text_box(2, pyui.format_length(data.depth))
	dialog:create_label(3, "Vertical partitions")
	local partition_count = dialog:create_text_spin(4, pyui.format_number(data.partition_count), {0, 10})

	dialog:create_label(1, "Shelves per section")
	local shelf_count = dialog:create_text_spin(2, pyui.format_number(data.shelf_count), {0, 12})
	dialog:create_label(3, "Drawer count")
	local drawer_count = dialog:create_text_spin(4, pyui.format_number(data.drawer_count), {0, 10})

	dialog:create_label(1, "Door type")
	local door_type = dialog:create_drop_list(2)
	for _, v in pairs(DOOR_TYPES) do door_type:insert_control_item(v) end
	door_type:set_control_selection(data.door_type_index)

	dialog:create_label(3, "Panel thickness")
	local panel_thickness = dialog:create_text_box(4, pyui.format_length(data.panel_thickness))

	dialog:create_label(1, "Kick height")
	local kick_height = dialog:create_text_box(2, pyui.format_length(data.kick_height))

	dialog:create_label(3, "Material")
	local material = dialog:create_drop_list(4)
	for _, v in pairs(MATERIALS) do material:insert_control_item(v) end
	material:set_control_selection(data.material_index)

	dialog:create_label(1, "Hardware")
	local hardware = dialog:create_drop_list(2)
	for _, v in pairs(HARDWARES) do hardware:insert_control_item(v) end
	hardware:set_control_selection(data.hardware_index)

	dialog:create_label({1,4}, "Production summary")
	local report_box = dialog:create_text_box({1,4}, "")
	report_box:disable_control()

	dialog:create_align({1,4})
	dialog:create_ok_button(3)
	dialog:create_cancel_button(4)
	dialog:equalize_column_widths({1,2,3,4})

	local function sanitize()
		data.width = clamp(data.width, 300)
		data.height = clamp(data.height, 500)
		data.depth = clamp(data.depth, 250)
		data.panel_thickness = clamp(data.panel_thickness, 12)
		data.kick_height = clamp(data.kick_height, 0)
		data.partition_count = math.floor(clamp(data.partition_count, 0))
		data.shelf_count = math.floor(clamp(data.shelf_count, 0))
		data.drawer_count = math.floor(clamp(data.drawer_count, 0))
		if data.panel_thickness * (2 + data.partition_count) >= data.width - 40 then
			data.partition_count = math.max(0, math.floor((data.width - 40) / data.panel_thickness) - 2)
		end
		if data.kick_height >= data.height - 2 * data.panel_thickness then
			data.kick_height = data.height * 0.1
		end
	end

	local function refresh()
		sanitize()
		regenerate_wardrobe(data, report_box)
	end

	width:set_on_change_handler(function(text)
		data.width = pyui.parse_length(text) or data.width
		refresh()
	end)
	height:set_on_change_handler(function(text)
		data.height = pyui.parse_length(text) or data.height
		refresh()
	end)
	depth:set_on_change_handler(function(text)
		data.depth = pyui.parse_length(text) or data.depth
		refresh()
	end)
	partition_count:set_on_change_handler(function(text)
		data.partition_count = pyui.parse_number(text) or data.partition_count
		refresh()
	end)
	shelf_count:set_on_change_handler(function(text)
		data.shelf_count = pyui.parse_number(text) or data.shelf_count
		refresh()
	end)
	drawer_count:set_on_change_handler(function(text)
		data.drawer_count = pyui.parse_number(text) or data.drawer_count
		refresh()
	end)
	door_type:set_on_change_handler(function(_, index)
		data.door_type_index = index
		refresh()
	end)
	panel_thickness:set_on_change_handler(function(text)
		data.panel_thickness = pyui.parse_length(text) or data.panel_thickness
		refresh()
	end)
	kick_height:set_on_change_handler(function(text)
		data.kick_height = pyui.parse_length(text) or data.kick_height
		refresh()
	end)
	material:set_on_change_handler(function(text, index)
		data.material_name = text
		data.material_index = index
		refresh()
	end)
	hardware:set_on_change_handler(function(text, index)
		data.hardware_name = text
		data.hardware_index = index
		refresh()
	end)

	refresh()
end

function main()
	local data = {
		origin = {0, 0, 0},
		width = 2400,
		height = 2400,
		depth = 600,
		partition_count = 2,
		shelf_count = 4,
		drawer_count = 3,
		door_type_index = 1,
		panel_thickness = 18,
		kick_height = 100,
		material_index = 1,
		hardware_index = 2,
		material_name = MATERIALS[1],
		hardware_name = HARDWARES[2],
		current_parts = {},
		main_group = nil,
		production_report = nil
	}

	local loaded = pyio.load_values("wardrobe_generator_defaults")
	if loaded ~= nil then
		for k, v in pairs(loaded) do data[k] = v end
		data.material_name = MATERIALS[data.material_index] or data.material_name
		data.hardware_name = HARDWARES[data.hardware_index] or data.hardware_name
	end

	regenerate_wardrobe(data)
	pyui.run_modal_dialog(wardrobe_dialog, data)
	pyio.save_values("wardrobe_generator_defaults", data)
	if data.production_report ~= nil then
		pyio.save_values("wardrobe_generator_last_report", data.production_report)
	end
end
