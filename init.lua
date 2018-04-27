local craftguide, datas, mt = {}, {searches = {}}, minetest
local progressive_mode = mt.settings:get_bool("craftguide_progressive_mode")
local get_recipe, get_recipes = mt.get_craft_recipe, mt.get_all_craft_recipes
local get_result, show_formspec = mt.get_craft_result, mt.show_formspec
local reg_items = mt.registered_items

craftguide.path = minetest.get_modpath("craftguide")

-- Intllib
local S = dofile(craftguide.path .. "/intllib.lua")
craftguide.intllib = S

-- Lua 5.3 removed `table.maxn`, use this alternative in case of breakage:
-- https://github.com/kilbith/xdecor/blob/master/handlers/helpers.lua#L1
local remove, maxn, sort = table.remove, table.maxn, table.sort
local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil

local DEFAULT_SIZE = 10
local MIN_LIMIT, MAX_LIMIT = 9, 12
DEFAULT_SIZE = min(MAX_LIMIT, max(MIN_LIMIT, DEFAULT_SIZE))

local GRID_LIMIT = 5

local group_stereotypes = {
	wool	     = "wool:white",
	dye	     = "dye:white",
	water_bucket = "bucket:bucket_water",
	vessel	     = "vessels:glass_bottle",
	coal	     = "default:coal_lump",
	flower	     = "flowers:dandelion_yellow",
	mesecon_conductor_craftable = "mesecons:wire_00000000_off",
}

function craftguide:group_to_item(item)
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

local function extract_groups(str)
	if str:sub(1,6) ~= "group:" then return end
	return str:sub(7):split(",")
end

local function colorize(str)
	-- If client <= 0.4.14, don't colorize for compatibility.
	return mt.colorize and mt.colorize("#FFFF00", str) or str
end

local function get_fueltime(item)
	return get_result({method = "fuel", width = 1, items = {item}}).time
end

function craftguide:get_tooltip(item, recipe_type, cooktime, groups)
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

		tooltip = tooltip .. S("Any item belonging to the group(s)") .. ": " .. groupstr
	end

	if recipe_type == "cooking" then
		tooltip = tooltip .. item_desc .. "\n"
				.. S("Cooking time") .. ": " .. colorize(cooktime)
	end

	if fueltime > 0 then
		tooltip = tooltip .. item_desc .. "\n"
				.. S("Burning time") .. ": " .. colorize(fueltime)
	end

	return has_extras and tooltip .. "]" or ""
end

function craftguide:get_recipe(iY, xoffset, tooltip, item, recipe_num, recipes)
	local formspec, recipes_total = "", #recipes
	if recipes_total > 1 then
		formspec = formspec ..
			"button[0," .. (iY + 3.3) .. ";2,1;alternate;" .. S("Alternate") .. "]" ..
			"label[0," .. (iY + 2.8) .. ";" ..
				S("Recipe @1 of @2", recipe_num, recipes_total) .. "]"
	end

	local recipe_type = recipes[recipe_num].type
	local items = recipes[recipe_num].items
	local width = recipes[recipe_num].width

	if recipe_type == "cooking" or (recipe_type == "normal" and width == 0) then
		local icon = recipe_type == "cooking" and "furnace" or "shapeless"
		formspec = formspec ..
			"image[" .. (xoffset - 0.8) .. "," .. (iY + 1.7)  ..
				".5;0.5,0.5;craftguide_" .. icon .. ".png]"
	end

	if width == 0 then
		width = min(3, #items)
	end

	local rows = ceil(maxn(items) / width)

	if recipe_type == "normal" and (width > GRID_LIMIT or rows > GRID_LIMIT) then
		formspec = formspec ..
			"label[" .. xoffset .. "," .. (iY + 2) .. ";" ..
				S("Recipe is too big to\nbe displayed (@1x@2)", width, rows) .. "]"
	else
		local btn_size = 1
		for i, v in pairs(items) do
			local X = (i - 1) % width + xoffset
			local Y = ceil(i / width + (iY + 2) - min(2, rows))

			if recipe_type == "normal" and (width > 3 or rows > 3) then
				btn_size = width > 3 and 3 / width or 3 / rows
				X = btn_size * (i % width) + xoffset
				Y = btn_size * floor((i - 1) / width) + (iY + 3) - min(2, rows)
			end

			local groups = extract_groups(v)
			local label = groups and "\nG" or ""
			local item_r = self:group_to_item(v)
			local tltip = self:get_tooltip(item_r, recipe_type, width, groups)

			formspec = formspec ..
				"item_image_button[" .. X .. "," .. (Y + 0.2) .. ";" ..
					btn_size .. "," .. btn_size .. ";" .. item_r ..
					";" .. item_r .. ";" .. label .. "]" .. tltip
		end
	end

	local output = recipes[recipe_num].output
	return formspec ..
		"image[" .. (xoffset - 1) .. "," .. (iY + 2.35) ..
			".12;0.9,0.7;craftguide_arrow.png]" ..
		"item_image_button[" .. (xoffset - 2) .. "," .. (iY + 2.2) .. ";1,1;" ..
			output .. ";" .. item .. ";]" .. tooltip
end

function craftguide:get_formspec(player_name, is_fuel)
	local data = datas[player_name]
	local iY = data.iX - 5
	local ipp = data.iX * iY

	if not data.items then
		data.items = datas.init_items
	end

	data.pagemax = max(1, ceil(#data.items / ipp))

	local formspec = "size[" .. (data.iX - 0.35) .. "," .. (iY + 4) .. ";]" .. [[
			background[1,1;1,1;craftguide_bg.png;true]
			button[2.4,0.23;0.8,0.5;search;?]
			button[3.05,0.23;0.8,0.5;clear;X]
			field_close_on_enter[filter;false]
		]] ..
			"tooltip[search;" .. S("Search") .. "]" ..
			"tooltip[clear;" .. S("Reset") .. "]" ..
			"tooltip[size_inc;" .. S("Increase window size") .. "]" ..
			"tooltip[size_dec;" .. S("Decrease window size") .. "]" ..
			"tooltip[prev;" .. S("Previous page") .. "]" ..
			"tooltip[next;" .. S("Next page") .. "]" ..
			"button[" .. (data.iX * 0.48) .. ",-0.02;0.7,1;size_inc;+]" ..
			"button[" .. ((data.iX * 0.48) + 0.5) ..
				",-0.02;0.7,1;size_dec;-]" ..
			"button[" .. (data.iX - 3.1) .. ".4,0;0.8,0.95;prev;<]" ..
			"label[" .. (data.iX - 2.2) .. ".1,0.18;" ..
				colorize(data.pagenum) .. " / " .. data.pagemax .. "]" ..
			"button[" .. (data.iX - 1.2) .. ".2,0;0.8,0.95;next;>]" ..
			"field[0.3,0.32;2.5,1;filter;;" ..
				mt.formspec_escape(data.filter) .. "]"

	local even_num = data.iX % 2 == 0
	local xoffset = data.iX / 2 + (even_num and 0.5 or 0)

	if not next(data.items) then
		formspec = formspec ..
			"label[" .. (xoffset - (even_num and 1.5 or 1)) .. ",2;" ..
				S("No item to show") .. "]"
	end

	local first_item = (data.pagenum - 1) * ipp
	for i = first_item, first_item + ipp - 1 do
		local name = data.items[i + 1]
		if not name then break end
		local X = i % data.iX
		local Y = (i % ipp - X) / data.iX + 1

		formspec = formspec ..
			"item_image_button[" .. (X - (X * 0.05)) .. "," .. Y .. ";1.1,1.1;" ..
				name .. ";" .. name .. "_inv;]"
	end

	if data.item and reg_items[data.item] then
		local tooltip = self:get_tooltip(data.item)
		if not data.recipes_item or (is_fuel and not get_recipe(data.item).items) then
			formspec = formspec ..
				"image[" .. (xoffset - 1) .. "," .. (iY + 2.35) ..
					".12;0.9,0.7;craftguide_arrow.png]" ..
				"item_image_button[" .. xoffset .. "," .. (iY + 2.2) ..
					";1,1;" .. data.item .. ";" .. data.item .. ";]" ..
				tooltip ..
				"image[" .. (xoffset - 2) .. "," ..
					(iY + 2.18) .. ";1,1;craftguide_fire.png]"
		else
			formspec = formspec ..
				self:get_recipe(iY, xoffset, tooltip, data.item,
						data.recipe_num, data.recipes_item)
		end
	end

	data.formspec = formspec
	show_formspec(player_name, "craftguide", formspec)
end

local function player_has_item(T)
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

function craftguide:recipe_in_inv(inv, item_name, recipes_f)
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

	return recipes, player_has_item(show_item_recipes)
end

function craftguide:get_init_items()
	local items_list, counter = {}, 0
	for name, def in pairs(reg_items) do
		local is_fuel = get_fueltime(name) > 0
		if not (def.groups.not_in_creative_inventory == 1) and
		       (get_recipe(name).items or is_fuel) and
			def.description and def.description ~= "" then

			counter = counter + 1
			items_list[counter] = name
		end
	end

	sort(items_list)
	datas.init_items = items_list
end

function craftguide:get_filter_items(data, player)
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
			local _, has_item = self:recipe_in_inv(inv, item)
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

mt.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "craftguide" then return end
	local player_name = player:get_player_name()
	local data = datas[player_name]

	if fields.clear then
		data.filter, data.item, data.pagenum, data.recipe_num = "", nil, 1, 1
		data.items = progressive_mode and data.init_filter_items or datas.init_items
		craftguide:get_formspec(player_name)

	elseif fields.alternate then
		local recipe = data.recipes_item[data.recipe_num + 1]
		data.recipe_num = recipe and data.recipe_num + 1 or 1
		craftguide:get_formspec(player_name)

	elseif (fields.key_enter_field == "filter" or fields.search) and
			fields.filter ~= "" then
		data.filter = fields.filter:lower()
		data.pagenum = 1
		craftguide:get_filter_items(data, player)
		craftguide:get_formspec(player_name)

	elseif fields.prev or fields.next then
		data.pagenum = data.pagenum - (fields.prev and 1 or -1)
		if data.pagenum > data.pagemax then
			data.pagenum = 1
		elseif data.pagenum == 0 then
			data.pagenum = data.pagemax
		end
		craftguide:get_formspec(player_name)

	elseif (fields.size_inc and data.iX < MAX_LIMIT) or
			(fields.size_dec and data.iX > MIN_LIMIT) then
		data.pagenum = 1
		data.iX = data.iX - (fields.size_dec and 1 or -1)
		craftguide:get_formspec(player_name)

	else for item in pairs(fields) do
		if item:find(":") then
			if item:sub(-4) == "_inv" then
				item = item:sub(1,-5)
			end

			local is_fuel = get_fueltime(item) > 0
			local recipes = get_recipes(item)
			if not recipes and not is_fuel then return end

			if item == data.item then
				if data.recipes_item and #data.recipes_item >= 2 then
					local recipe = data.recipes_item[data.recipe_num + 1]
					data.recipe_num = recipe and data.recipe_num + 1 or 1
					craftguide:get_formspec(player_name)
				end
			else
				if progressive_mode then
					local inv = player:get_inventory()
					local _, has_item = craftguide:recipe_in_inv(inv, item)

					if not has_item then return end
					recipes = craftguide:recipe_in_inv(inv, item, recipes)
				end

				data.item = item
				data.recipe_num = 1
				data.recipes_item = recipes
				craftguide:get_formspec(player_name, is_fuel)
			end
		end
	     end
	end
end)

function craftguide:on_use(itemstack, user)
	if not datas.init_items then
		self:get_init_items()
	end

	local player_name = user:get_player_name()
	local data = datas[player_name]

	if progressive_mode or not data then
		datas[player_name] = {filter = "", pagenum = 1, iX = DEFAULT_SIZE}
		if progressive_mode then
			self:get_filter_items(datas[player_name], user)
		end

		self:get_formspec(player_name)
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
		craftguide:on_use(itemstack, user)
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
		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", S("Crafting Guide Sign"))
	end,
	on_rightclick = function(pos, node, user, itemstack)
		craftguide:on_use(itemstack, user)
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
			craftguide:on_use(nil, player)
		end,
		image = "craftguide_book.png",
	})
end

mt.register_alias("xdecor:crafting_guide", "craftguide:book")

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
