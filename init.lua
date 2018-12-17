craftguide = {
	custom_crafts = {},
	craft_types = {},
}

local mt = minetest
local datas = {searches = {}}

local progressive_mode = mt.settings:get_bool("craftguide_progressive_mode")
local sfinv_only       = mt.settings:get_bool("craftguide_sfinv_only")

local get_recipe, get_recipes = mt.get_craft_recipe, mt.get_all_craft_recipes
local get_result, show_formspec = mt.get_craft_result, mt.show_formspec
local reg_items = mt.registered_items

craftguide.path = mt.get_modpath("craftguide")

-- Intllib
local S = dofile(craftguide.path .. "/intllib.lua")
craftguide.intllib = S

-- Lua 5.3 removed `table.maxn`, use this alternative in case of breakage:
-- https://github.com/kilbith/xdecor/blob/master/handlers/helpers.lua#L1
local remove, maxn, sort = table.remove, table.maxn, table.sort
local vector_add, vector_mul = vector.add, vector.multiply
local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil

local DEFAULT_SIZE = 10
local MIN_LIMIT, MAX_LIMIT = 10, 12
DEFAULT_SIZE = min(MAX_LIMIT, max(MIN_LIMIT, DEFAULT_SIZE))

local GRID_LIMIT = 5
local BUTTON_SIZE = 1.1

local group_stereotypes = {
	wool	     = "wool:white",
	dye	     = "dye:white",
	water_bucket = "bucket:bucket_water",
	vessel	     = "vessels:glass_bottle",
	coal	     = "default:coal_lump",
	flower	     = "flowers:dandelion_yellow",
	mesecon_conductor_craftable = "mesecons:wire_00000000_off",
}

local function extract_groups(str)
	if str:sub(1,6) ~= "group:" then return end
	return str:sub(7):split(",")
end

function craftguide.register_craft_type(name, def)
	if not craftguide.craft_types[name] then
		craftguide.craft_types[name] = def
	end
end

craftguide.register_craft_type("digging", {
	description = S("Digging"),
	icon  = "default_tool_steelpick.png",
	width = 1,
})

function craftguide.register_craft(def)
	craftguide.custom_crafts[#craftguide.custom_crafts + 1] = def
end

craftguide.register_craft({
	type   = "digging",
	output = "default:cobble",
	items  = {"default:stone"},
})

local function colorize(str)
	return mt.colorize("#FFFF00", str)
end

local function get_fueltime(item)
	return get_result({method = "fuel", width = 1, items = {item}}).time
end

local function reset_datas(data)
	data.show_usage = nil
	data.filter     = ""
	data.item       = nil
	data.pagenum    = 1
	data.rnum       = 1
	data.fuel       = nil
end

local function in_table(T)
	for i = 1, #T do
		if T[i] then
			return true
		end
	end
end

local function group_to_items(group)
	local items_with_group, counter = {}, 0
	for name, def in pairs(reg_items) do
		if def.groups[group:sub(7)] then
			counter = counter + 1
			items_with_group[counter] = name
		end
	end

	return items_with_group
end

local function item_in_inv(inv, item)
	return inv:contains_item("main", item)
end

local function group_to_item(item)
	if item:sub(1,6) == "group:" then
		local itemsub = item:sub(7)
		if group_stereotypes[itemsub] then
			item = group_stereotypes[itemsub]
		elseif reg_items["default:" .. itemsub] then
			item = item:gsub("group:", "default:")
		else
			for name, def in pairs(reg_items) do
				if def.groups[item:match("[^,:]+$")] then
					item = name
				end
			end
		end
	end

	return item:sub(1,6) == "group:" and "" or item
end

local function get_tooltip(item, recipe_type, cooktime, groups)
	local tooltip, item_desc = "tooltip[" .. item .. ";", ""
	local fueltime = get_fueltime(item)
	local has_extras = groups or recipe_type == "cooking" or fueltime > 0

	if reg_items[item] then
		if not groups then
			item_desc = reg_items[item].description
		end
	else
		return tooltip .. S("Unknown Item (@1)", item) .. "]"
	end

	if groups then
		local groupstr = ""
		for i = 1, #groups do
			groupstr = groupstr ..
				colorize(groups[i]) .. (groups[i + 1] and ", " or "")
		end

		tooltip = tooltip ..
			S("Any item belonging to the group(s)") .. ": " .. groupstr
	end

	if recipe_type == "cooking" then
		tooltip = tooltip .. item_desc .. "\n" ..
			S("Cooking time") .. ": " .. colorize(cooktime)
	end

	if fueltime > 0 then
		tooltip = tooltip .. item_desc .. "\n" ..
			S("Burning time") .. ": " .. colorize(fueltime)
	end

	return has_extras and tooltip .. "]" or ""
end

local function _get_recipe(iX, iY, xoffset, recipe_num, recipes, show_usage)
	local formspec, recipes_total = "", #recipes
	if recipes_total > 1 then
		formspec = formspec ..
			"button[" .. (iX - (sfinv_only and 2.2 or 2.6)) .. "," ..
				(iY + (sfinv_only and 3.9 or 3.3)) .. ";2.2,1;alternate;" ..
				(show_usage and S("Usage") or S("Recipe")) .. " " ..
				S("@1 of @2", recipe_num, recipes_total) .. "]"
	end

	local recipe_type = recipes[recipe_num].type
	local items = recipes[recipe_num].items
	local width = recipes[recipe_num].width

	local cooktime = width
	if recipe_type == "cooking" then
		width = 1
	elseif width == 0 then
		width = min(3, #items)
	end

	local rows = ceil(maxn(items) / width)
	local rightest, s_btn_size = 0

	if recipe_type ~= "fuel" and (width > GRID_LIMIT or rows > GRID_LIMIT) then
		formspec = formspec ..
			"label[" .. ((iX / 2) - 2) .. "," .. (iY + 2.2) .. ";" ..
				S("Recipe is too big to be displayed (@1x@2)", width, rows) .. "]"
		return formspec
	else
		for i, v in pairs(items) do
			local X = ceil((i - 1) % width + xoffset - width) -
				 (sfinv_only and 0 or 0.2)
			local Y = ceil(i / width + (iY + 2) - min(2, rows))

			if recipe_type ~= "fuel" and (width > 3 or rows > 3) then
				BUTTON_SIZE = width > 3 and 3 / width or 3 / rows
				s_btn_size = BUTTON_SIZE
				X = BUTTON_SIZE * (i % width) + xoffset - 2.65
				Y = BUTTON_SIZE * floor((i - 1) / width) + (iY + 3) - min(2, rows)
			end

			if X > rightest then
				rightest = X
			end

			local groups = extract_groups(v)
			local label = groups and "\nG" or ""
			local item_r = group_to_item(v)
			local tltip = get_tooltip(item_r, recipe_type, cooktime, groups)

			formspec = formspec ..
				"item_image_button[" .. X .. "," ..
					(Y + (sfinv_only and 0.7 or 0.2)) .. ";" ..
					BUTTON_SIZE .. "," .. BUTTON_SIZE .. ";" .. item_r ..
					";" .. item_r:match("%S*") .. ";" .. label .. "]" .. tltip
		end

		BUTTON_SIZE = 1.1
	end

	local custom_recipe = craftguide.craft_types[recipe_type]
	if recipe_type == "cooking" or (recipe_type == "normal" and width == 0) or
			custom_recipe then
		local icon   = recipe_type == "cooking" and "furnace" or "shapeless"
		local coords = (rightest + 1.2) .. "," ..
			       (iY + (sfinv_only and 2.2 or 1.7)) ..
			       ";0.5,0.5;"

		formspec = formspec ..
			"image[" .. coords ..
				(custom_recipe and custom_recipe.icon or
				 "craftguide_" .. icon .. ".png^[resize:16x16") .. "]" ..
			"tooltip[" .. coords ..
				(custom_recipe and custom_recipe.description or
					recipe_type:gsub("^%l", string.upper)) .. "]"
	end

	local output   = recipes[recipe_num].output
	local output_s = output:match("%S+")
	local output_is_fuel = get_fueltime(output) > 0

	local arrow_X  = rightest + (s_btn_size or BUTTON_SIZE)
	local output_X = arrow_X + 0.9

	formspec = formspec ..
		"image[" .. arrow_X .. "," ..
			(iY + (sfinv_only and 2.85 or 2.35)) ..
			";0.9,0.7;craftguide_arrow.png]" ..

		"item_image_button[" .. output_X .. "," ..
				(iY + (sfinv_only and 2.7 or 2.2)) .. ";" ..
				BUTTON_SIZE .. "," .. BUTTON_SIZE .. ";" ..
				output .. ";" .. output_s .. ";]" ..

		get_tooltip(output_s)

	if output_is_fuel then
		formspec = formspec ..
			"image[" .. (output_X + 1) .. "," ..
				(iY + (sfinv_only and 2.83 or 2.33)) ..
				";0.6,0.4;craftguide_arrow.png]" ..

			"image[" .. (output_X + 1.6) .. "," ..
				(iY + (sfinv_only and 2.68 or 2.18)) ..
				";0.6,0.6;craftguide_fire.png]"
	end

	return formspec
end

local function get_formspec(player_name)
	local data = datas[player_name]
	local iY = sfinv_only and 4 or data.iX - 5
	local ipp = data.iX * iY

	if not data.items then
		data.items = datas.init_items
	end

	data.pagemax = max(1, ceil(#data.items / ipp))

	local formspec = ""
	if not sfinv_only then
		formspec = formspec ..
			"size[" .. (data.iX - 0.35) .. "," .. (iY + 4) .. ";]" ..
			"background[1,1;1,1;craftguide_bg.png;true]" ..
			"tooltip[size_inc;" .. S("Increase window size") .. "]" ..
			"tooltip[size_dec;" .. S("Decrease window size") .. "]" ..
			"image_button[" .. (data.iX * 0.47) ..
				",0.12;0.8,0.8;craftguide_zoomin_icon.png;size_inc;]" ..
			"image_button[" .. ((data.iX * 0.47) + 0.6) ..
				",0.12;0.8,0.8;craftguide_zoomout_icon.png;size_dec;]"
	end

	formspec = formspec .. [[
			image_button[2.4,0.12;0.8,0.8;craftguide_search_icon.png;search;]
			image_button[3.05,0.12;0.8,0.8;craftguide_clear_icon.png;clear;]
			field_close_on_enter[filter;false]
		]] ..
			"tooltip[search;" .. S("Search") .. "]" ..
			"tooltip[clear;" .. S("Reset") .. "]" ..
			"tooltip[prev;" .. S("Previous page") .. "]" ..
			"tooltip[next;" .. S("Next page") .. "]" ..
			"image_button[" .. (data.iX - (sfinv_only and 2.6 or 3.1)) ..
				",0.12;0.8,0.8;craftguide_prev_icon.png;prev;]" ..
			"label[" .. (data.iX - (sfinv_only and 1.7 or 2.2)) .. ",0.22;" ..
				colorize(data.pagenum) .. " / " .. data.pagemax .. "]" ..
			"image_button[" .. (data.iX - (sfinv_only and 0.7 or 1.2) -
				(data.iX >= 11 and 0.08 or 0)) ..
				",0.12;0.8,0.8;craftguide_next_icon.png;next;]" ..
			"field[0.3,0.32;2.5,1;filter;;" .. mt.formspec_escape(data.filter) .. "]"

	local xoffset = data.iX / 2.15

	if not next(data.items) then
		formspec = formspec ..
			"label[" .. ((data.iX / 2) - 1) .. ",2;" .. S("No item to show") .. "]"
	end

	local first_item = (data.pagenum - 1) * ipp
	for i = first_item, first_item + ipp - 1 do
		local name = data.items[i + 1]
		if not name then break end
		local X = i % data.iX
		local Y = (i % ipp - X) / data.iX + 1

		formspec = formspec ..
			"item_image_button[" ..
				(X - (sfinv_only and 0 or (X * 0.05))) .. "," ..
				Y .. ";" .. BUTTON_SIZE .. "," .. BUTTON_SIZE .. ";" ..
				name .. ";" .. name .. "_inv;]"
	end

	if data.item and reg_items[data.item] then
		if not data.recipes_item or (data.fuel and not get_recipe(data.item).items) then
			local X = floor(xoffset) - (sfinv_only and 0 or 0.2)
			formspec = formspec ..
				"item_image_button[" .. X .. "," ..
					(iY + (sfinv_only and 2.7 or 2.2)) ..
					";" .. BUTTON_SIZE .. "," .. BUTTON_SIZE ..
					";" .. data.item .. ";" .. data.item .. ";]" ..

				"image[" .. (X + 1.1) .. "," ..
					(iY + (sfinv_only and 2.85 or 2.35)) ..
					";0.9,0.7;craftguide_arrow.png]" ..

				get_tooltip(data.item) ..

				"image[" .. (X + 2.1) .. "," ..
					(iY + (sfinv_only and 2.68 or 2.18)) ..
					";1.1,1.1;craftguide_fire.png]"
		else
			local show_usage = data.show_usage
			formspec = formspec ..
				_get_recipe(data.iX,
						iY,
						xoffset,
						data.rnum,
						(show_usage and data.usages or data.recipes_item),
						show_usage)
		end
	end

	data.formspec = formspec

	if sfinv_only then
		return formspec
	else
		show_formspec(player_name, "craftguide", formspec)
	end
end

local show_fs = function(player, player_name)
	if sfinv_only then
		local context = sfinv.get_or_create_context(player)
		sfinv.set_player_inventory_formspec(player, context)
	else
		get_formspec(player_name)
	end
end

local function recipe_in_inv(inv, item_name, recipes_f)
	local recipes = recipes_f or get_recipes(item_name) or {}
	local show_item_recipes = {}

	for i = 1, #recipes do
		show_item_recipes[i] = true
		for _, item in pairs(recipes[i].items) do
			local group_in_inv = false
			if item:sub(1,6) == "group:" then
				local groups = group_to_items(item)
				for j = 1, #groups do
					if item_in_inv(inv, groups[j]) then
						group_in_inv = true
					end
				end
			end
			if not group_in_inv and not item_in_inv(inv, item) then
				show_item_recipes[i] = false
			end
		end
	end

	for i = #show_item_recipes, 1, -1 do
		if not show_item_recipes[i] then
			remove(recipes, i)
		end
	end

	return recipes, in_table(show_item_recipes)
end

local function get_filter_items(data, player)
	local filter = data.filter
	if datas.searches[filter] then
		data.items = datas.searches[filter]
		return
	end

	local items_list = progressive_mode and data.init_filter_items or datas.init_items
	local inv = player:get_inventory()
	local filtered_list, counter = {}, 0

	for i = 1, #items_list do
		local item = items_list[i]
		local item_desc = reg_items[item].description:lower()

		if filter ~= "" then
			if item:find(filter, 1, true) or item_desc:find(filter, 1, true) then
				counter = counter + 1
				filtered_list[counter] = item
			end
		elseif progressive_mode then
			local _, has_item = recipe_in_inv(inv, item)
			if has_item then
				counter = counter + 1
				filtered_list[counter] = item
			end
		end
	end

	if progressive_mode then
		if not data.items then
			data.init_filter_items = filtered_list
		end
	elseif filter ~= "" then
		-- Cache the results only if searched 2 times
		if datas.searches[filter] == nil then
			datas.searches[filter] = false
		else
			datas.searches[filter] = filtered_list
		end
	end

	data.items = filtered_list
end

local function init_datas(user, name)
	datas[name] = {filter = "", pagenum = 1, iX = sfinv_only and 8 or DEFAULT_SIZE}
	if progressive_mode then
		get_filter_items(datas[name], user)
	end
end

local function add_custom_recipes(item, recipes)
	for j = 1, #craftguide.custom_crafts do
		local craft = craftguide.custom_crafts[j]
		if craft.output:match("%S*") == item then
			recipes[#recipes + 1] = {
				width  = craftguide.craft_types[craft.type].width,
				type   = craft.type,
				items  = craft.items,
				output = craft.output,
			}
		end
	end

	return recipes
end

local function get_init_items()
	local items_list, c = {}, 0
	local function list(name)
		c = c + 1
		items_list[c] = name
	end

	for name, def in pairs(reg_items) do
		local is_fuel = get_fueltime(name) > 0
		if (not (def.groups.not_in_craft_guide == 1 or
			 def.groups.not_in_creative_inventory == 1)) and
		        (get_recipe(name).items or is_fuel) and
			 def.description and def.description ~= "" then
				list(name)
		end
	end

	for i = 1, #craftguide.custom_crafts do
		local craft  = craftguide.custom_crafts[i]
		local output = craft.output:match("%S*")
		local listed

		for j = 1, #items_list do
			local listed_item = items_list[j]
			if output == listed_item then
				listed = true
				break
			end
		end

		if not listed then
			list(output)
		end
	end

	sort(items_list)
	datas.init_items = items_list
end

mt.register_on_mods_loaded(function()
	get_init_items()
end)

local function get_item_usages(item)
	local usages = {}
	for name, def in pairs(reg_items) do
		if not (def.groups.not_in_craft_guide == 1 or
			def.groups.not_in_creative_inventory == 1) and
		   get_recipe(name).items and def.description and def.description ~= "" then
			local recipes = get_recipes(name)
			for i = 1, #recipes do
				local recipe = recipes[i]
				local items = recipe.items

				for j = 1, #items do
					if items[j] == item then
						usages[#usages + 1] = {
							type = recipe.type,
							items = items,
							width = recipe.width,
							output = recipe.output,
						}
						break
					end
				end
			end
		end
	end

	return usages
end

local function get_fields(player, ...)
	local args, formname, fields = {...}
	if sfinv_only then
		fields = args[1]
	else
		formname, fields = args[1], args[2]
	end

	if not sfinv_only and formname ~= "craftguide" then return end
	local player_name = player:get_player_name()
	local data = datas[player_name]

	if fields.clear then
		reset_datas(data)
		data.items = progressive_mode and data.init_filter_items or datas.init_items
		show_fs(player, player_name)

	elseif fields.alternate then
		local num
		if data.show_usage then
			num = data.usages[data.rnum + 1]
		else
			num = data.recipes_item[data.rnum + 1]
		end

		data.rnum = num and data.rnum + 1 or 1
		show_fs(player, player_name)

	elseif (fields.key_enter_field == "filter" or fields.search) and
			fields.filter ~= "" then
		data.filter = fields.filter:lower()
		data.pagenum = 1
		get_filter_items(data, player)
		show_fs(player, player_name)

	elseif fields.prev or fields.next then
		data.pagenum = data.pagenum - (fields.prev and 1 or -1)

		if data.pagenum > data.pagemax then
			data.pagenum = 1
		elseif data.pagenum == 0 then
			data.pagenum = data.pagemax
		end

		show_fs(player, player_name)

	elseif (fields.size_inc and data.iX < MAX_LIMIT) or
			(fields.size_dec and data.iX > MIN_LIMIT) then
		data.pagenum = 1
		data.iX = data.iX - (fields.size_dec and 1 or -1)
		show_fs(player, player_name)

	else for item in pairs(fields) do
		if item:find(":") then
			if item:sub(-4) == "_inv" then
				item = item:sub(1,-5)
			elseif item:find("%s") then
				item = item:match("%S*")
			end

			local is_fuel = get_fueltime(item) > 0
			local recipes = get_recipes(item) or {}
			recipes = add_custom_recipes(item, recipes)
			if not next(recipes) and not is_fuel then return end

			if not data.show_usage and item == data.item and not progressive_mode then
				data.usages = get_item_usages(item)
				if next(data.usages) then
					data.show_usage = true
					data.rnum = 1
				end

				show_fs(player, player_name)
			else
				if progressive_mode then
					local inv = player:get_inventory()
					local has_item
					recipes, has_item = recipe_in_inv(inv, item, recipes)
					if not has_item then return end
				end

				data.item          = item
				data.recipes_item  = recipes
				data.rnum          = 1
				data.show_usage    = nil
				data.fuel          = is_fuel

				show_fs(player, player_name)
			end
		end
	     end
	end
end

if sfinv_only then
	sfinv.register_page("craftguide:craftguide", {
		title = "Craft Guide",
		get = function(self, player, context)
			local player_name = player:get_player_name()
			return sfinv.make_formspec(
				player,
				context,
				get_formspec(player_name)
			)
		end,
		on_enter = function(self, player, context)
			local player_name = player:get_player_name()
			local data = datas[player_name]

			if progressive_mode or not data then
				init_datas(player, player_name)
			end
		end,
		on_player_receive_fields = function(self, player, context, fields)
			get_fields(player, fields)
		end,
	})
else
	mt.register_on_player_receive_fields(get_fields)

	local function on_use(itemstack, user)
		local player_name = user:get_player_name()
		local data = datas[player_name]

		if progressive_mode or not data then
			init_datas(user, player_name)
			get_formspec(player_name)
		else
			show_formspec(player_name, "craftguide", data.formspec)
		end
	end

	mt.register_craftitem("craftguide:book", {
		description = S("Crafting Guide"),
		inventory_image = "craftguide_book.png",
		wield_image = "craftguide_book.png",
		stack_max = 1,
		groups = {book = 1},
		on_use = function(itemstack, user)
			on_use(itemstack, user)
		end
	})

	mt.register_node("craftguide:sign", {
		description = S("Crafting Guide Sign"),
		drawtype = "nodebox",
		tiles = {"craftguide_sign.png"},
		inventory_image = "craftguide_sign_inv.png",
		wield_image = "craftguide_sign_inv.png",
		paramtype = "light",
		paramtype2 = "wallmounted",
		sunlight_propagates = true,
		groups = {wood = 1, oddly_breakable_by_hand = 1, flammable = 3},
		node_box = {
			type = "wallmounted",
			wall_top    = {-0.4375, 0.4375, -0.3125, 0.4375, 0.5, 0.3125},
			wall_bottom = {-0.4375, -0.5, -0.3125, 0.4375, -0.4375, 0.3125},
			wall_side   = {-0.5, -0.3125, -0.4375, -0.4375, 0.3125, 0.4375}
		},
		on_construct = function(pos)
			local meta = mt.get_meta(pos)
			meta:set_string("infotext", S("Crafting Guide Sign"))
		end,
		on_rightclick = function(pos, node, user, itemstack)
			on_use(itemstack, user)
		end
	})

	mt.register_craft({
		output = "craftguide:book",
		type = "shapeless",
		recipe = {"default:book"}
	})

	mt.register_craft({
		type = "fuel",
		recipe = "craftguide:book",
		burntime = 3
	})

	mt.register_craft({
		output = "craftguide:sign",
		type = "shapeless",
		recipe = {"default:sign_wall_wood"}
	})

	mt.register_craft({
		type = "fuel",
		recipe = "craftguide:sign",
		burntime = 10
	})

	if rawget(_G, "sfinv_buttons") then
		sfinv_buttons.register_button("craftguide", {
			title = S("Crafting Guide"),
			tooltip = S("Shows a list of available crafting recipes, cooking recipes and fuels"),
			action = function(player)
				on_use(nil, player)
			end,
			image = "craftguide_book.png",
		})
	end
end

if not progressive_mode then
	mt.register_chatcommand("craft", {
		description = S("Show recipe(s) of the pointed node"),
		func = function(name)
			local player = mt.get_player_by_name(name)
			local ppos   = player:get_pos()
			local dir    = player:get_look_dir()
			local eye_h  = {x = ppos.x, y = ppos.y + 1.625, z = ppos.z}
			local node_name

			for i = 1, 10 do
				local look_at = vector_add(eye_h, vector_mul(dir, i))
				local node = mt.get_node(look_at)

				if node.name ~= "air" then
					node_name = node.name
					break
				end
			end

			if not node_name then
				return false, colorize("[craftguide] ") .. S("No node pointed")
			elseif not datas[name] then
				init_datas(player, name)
			end

			local data    = datas[name]
			local is_fuel = get_fueltime(node_name) > 0
			local recipes = get_recipes(node_name) or {}
			recipes = add_custom_recipes(node_name, recipes)

			if not next(recipes) and not is_fuel then
				return false, colorize("[craftguide] ") ..
					S("No recipe for this node:") .. " " ..
					colorize(node_name)
			end

			data.show_usage   = nil
			data.filter       = ""
			data.item         = node_name
			data.pagenum      = 1
			data.rnum         = 1
			data.recipes_item = recipes
			data.items        = datas.init_items
			data.fuel         = is_fuel

			return true, show_fs(player, name)
		end,
	})
end

--[[ Custom recipes (>3x3) test code

mt.register_craftitem("craftguide:custom_recipe_test", {
	description = "Custom Recipe Test",
})

local cr = {}
for x = 1, 6 do
	cr[x] = {}
	for i = 1, 10 - x do
		cr[x][i] = {}
		for j = 1, 10 - x do
			cr[x][i][j] = "group:wood"
		end
	end

	mt.register_craft({
		output = "craftguide:custom_recipe_test",
		recipe = cr[x]
	})
end
]]