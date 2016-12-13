local craftguide, datas = {}, {}
local progressive_mode = minetest.setting_getbool("craftguide_progressive_mode")
local min, max, ceil = math.min, math.max, math.ceil
local iX, iY = (minetest.setting_get("craftguide_size") or "8x3"):match(
		"([%d]+)[.%d+]*[^%d]*x[^%d]*([%d]+)[.%d+]*")
iX, iY = max(8, iX or 8), max(1, iY or 3)
local ipp = iX * iY
local offset_X = (iX / 2) + (iX % 2 == 0 and 0.5 or 0)

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
		local short_itemstr = item:sub(7)
		if group_stereotypes[short_itemstr] then
			item = group_stereotypes[short_itemstr]
		elseif minetest.registered_items["default:"..item:sub(7)] then
			item = item:gsub("group:", "default:")
		else for node, def in pairs(minetest.registered_items) do
			 if def.groups[item:match("[^,:]+$")] then item = node end
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
	return minetest.colorize("#FFFF00", str)
end

function craftguide:get_tooltip(item, recipe_type, cooktime, groups)
	local tooltip = "tooltip["..item..";"
	local fueltime = minetest.get_craft_result({
		method="fuel", width=1, items={item}}).time
	local has_extras = groups or recipe_type == "cooking" or fueltime > 0
	local item_desc = groups and "" or minetest.registered_items[item].description

	if groups then
		local groupstr = "Any item belonging to the "
		for i=1, #groups do
			groupstr = groupstr..colorize(groups[i])..
				(groups[i+1] and " and " or "")
		end
		tooltip = tooltip..groupstr.." group(s)"
	end
	if recipe_type == "cooking" then
		tooltip = tooltip..item_desc.."\nCooking time: "..colorize(cooktime)
	end
	if fueltime > 0 then
		tooltip = tooltip..item_desc.."\nBurning time: "..colorize(fueltime)
	end

	return has_extras and tooltip.."]" or ""
end

function craftguide:get_recipe(player_name, tooltip_l, item, recipe_num, recipes)
	local formspec, recipe_type = "", recipes[recipe_num].type
	if progressive_mode then
		local T = self:recipe_in_inv(player_name, item)
		for i=#T, 1, -1 do
			if not T[i] then table.remove(recipes, i) end
		end
	end
	if #recipes > 1 then formspec = formspec..
		"button[0,"..(iY+3)..";2,1;alternate;Alternate]"..
		"label[0,"..(iY+2)..".5;Recipe "..recipe_num.." of "..#recipes.."]"
	end
	if recipe_type == "cooking" then
		formspec = formspec.."image["..(offset_X-0.8)..","..(iY+1)..
				     ".5;0.5,0.5;default_furnace_front.png]"
	end

	local items = recipes[recipe_num].items
	local width = recipes[recipe_num].width
	if width == 0 then width = min(3, #items) end
	-- Lua 5.3 removed `table.maxn`, use this alternative in case of breakage:
	-- https://github.com/kilbith/xdecor/blob/master/handlers/helpers.lua#L1
	local rows = ceil(table.maxn(items) / width)

	if #items > 9 then
		formspec = formspec.."label["..(offset_X)..","..(iY+2)..
					 ";Recipe is too big to\nbe displayed ("..
					 width.."x"..rows..")]"
	else for i, v in pairs(items) do
		local X = (i-1) % width + offset_X
		local Y = ceil(i / width + ((iY + 2) - min(2, rows)))
		local groups = extract_groups(v)
		local label = groups and "\nG" or ""
		local item = self:group_to_item(v)
		local tooltip = self:get_tooltip(item, recipe_type, width, groups)

		formspec = formspec.."item_image_button["..X..","..Y..";1,1;"..
				      item..";"..item..";"..label.."]"..tooltip
	     end
	end
	local output = recipes[recipe_num].output
	return formspec.."image["..(offset_X-1)..","..(iY+2)..
				".12;0.9,0.7;craftguide_arrow.png]"..
			 "item_image_button["..(offset_X-2)..","..(iY+2)..";1,1;"..
				output..";"..item..";]"..tooltip_l
end

function craftguide:get_formspec(player_name)
	local data = datas[player_name]
	local formspec = "size["..iX..","..(iY+3)..".6;]"..[[
			background[1,1;1,1;craftguide_bg.png;true]
			button[2.5,0.2;0.8,0.5;search;?]
			button[3.2,0.2;0.8,0.5;clear;X]
			tooltip[search;Search]
			tooltip[clear;Reset]
			field_close_on_enter[craftguide_filter, false] ]]..
			"button["..(iX-3)..".4,0;0.8,0.95;prev;<]"..
			"label["..(iX-2)..".1,0.18;"..
				colorize(data.pagenum).." / "..data.pagemax.."]"..
			"button["..(iX-1)..".2,0;0.8,0.95;next;>]"..
			"field[0.3,0.32;2.6,1;craftguide_filter;;"..
				minetest.formspec_escape(data.filter).."]"

	if not next(data.items) then
		formspec = formspec.."label[2.9,2;No item to show]"
	end

	local first_item = (data.pagenum - 1) * ipp
	for i = first_item, first_item + ipp - 1 do
		local name = data.items[i+1]
		if not name then break end
		local X = i % iX
		local Y = ((i % ipp - X) / iX) + 1

		formspec = formspec.."item_image_button["..X..","..Y..";1,1;"..
				      name..";"..name.."_inv;]"
	end

	if data.item and minetest.registered_items[data.item] then
		local is_fuel = minetest.get_craft_result({
			method="fuel", width=1, items={data.item}}).time > 0
		local tooltip = self:get_tooltip(data.item)

		if is_fuel and not minetest.get_craft_recipe(data.item).items then
			formspec = formspec..
				"image["..(offset_X-1)..","..(iY+2)..
					".12;0.9,0.7;craftguide_arrow.png]"..
				"item_image_button["..offset_X..","..(iY+2)..";1,1;"..
					data.item..";"..data.item..";]"..
				tooltip.."image["..(offset_X-2)..","..
					(iY+2)..";1,1;craftguide_none.png]"
		else
			formspec = formspec..
				self:get_recipe(player_name, tooltip, data.item,
						data.recipe_num, data.recipes_item)
		end
	end

	data.formspec = formspec
	minetest.show_formspec(player_name, "craftguide:book", formspec)
end

local function player_has_item(T)
	for i=1, #T do if T[i] then return true end end
end

local function group_to_items(group)
	local items_with_group = {}
	for name, def in pairs(minetest.registered_items) do
		if def.groups[group:sub(7)] then
			items_with_group[#items_with_group+1] = name
		end
	end
	return items_with_group
end

function craftguide:recipe_in_inv(player_name, item_name)
	local player = minetest.get_player_by_name(player_name)
	local inv = player:get_inventory()
	local recipes = minetest.get_all_craft_recipes(item_name) or {}
	local show_item_recipes = {}

	for i=1, #recipes do
		show_item_recipes[i] = true
		for _, item in pairs(recipes[i].items) do
			local group_in_inv = false
			if item:sub(1,6) == "group:" then
				local groups = group_to_items(item)
				for j=1, #groups do
					if inv:contains_item("main", groups[j]) then
						group_in_inv = true
					end
				end
			end
			if not group_in_inv and not inv:contains_item("main", item) then
				show_item_recipes[i] = false
			end
		end
	end
	return show_item_recipes, player_has_item(show_item_recipes)
end

function craftguide:get_items(player_name)
	local items_list, data, list_size = {}, datas[player_name]
	for name, def in pairs(minetest.registered_items) do
		local is_fuel = minetest.get_craft_result({
			method="fuel", width=1, items={name}}).time > 0
		if not (def.groups.not_in_creative_inventory == 1) and
		       (minetest.get_craft_recipe(name).items or is_fuel) and
			def.description and def.description ~= "" and
		       (def.name:find(data.filter, 1, true) or
			def.description:lower():find(data.filter, 1, true)) then

			list_size = #items_list
			if progressive_mode then
				local _, player_has_item =
					self:recipe_in_inv(player_name, name)
				if player_has_item then
					items_list[list_size+1] = name
				end
			else
				items_list[list_size+1] = name
			end
		end
	end

	table.sort(items_list)
	data.items = items_list
	data.size = list_size or 0
	data.pagemax = max(1, ceil(data.size / ipp))
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "craftguide:book" then return end
	local player_name = player:get_player_name()
	local data = datas[player_name]

	if fields.clear then
		data.filter, data.item, data.pagenum, data.recipe_num = "", nil, 1, 1
		craftguide:get_items(player_name)
		craftguide:get_formspec(player_name)
	elseif fields.alternate then
		local recipe = data.recipes_item[data.recipe_num + 1]
		data.recipe_num = recipe and data.recipe_num + 1 or 1
		craftguide:get_formspec(player_name)
	elseif fields.search or fields.key_enter_field == "craftguide_filter" then
		data.filter = fields.craftguide_filter:lower()
		data.pagenum = 1
		craftguide:get_items(player_name)
		craftguide:get_formspec(player_name)
	elseif fields.prev or fields.next then
		data.pagenum = data.pagenum - (fields.prev and 1 or -1)
		if data.pagenum > data.pagemax then
			data.pagenum = 1
		elseif data.pagenum == 0 then
			data.pagenum = data.pagemax
		end
		craftguide:get_formspec(player_name)
	else for item in pairs(fields) do
		if not item:find(":") then return end
		if item:sub(-4) == "_inv" then item = item:sub(1,-5) end

		if progressive_mode then
			local _, player_has_item =
				craftguide:recipe_in_inv(player_name, item)
			if not player_has_item then return end
		end

		data.item = item
		data.recipe_num = 1
		data.recipes_item = minetest.get_all_craft_recipes(item)
		craftguide:get_formspec(player_name)
	     end
	end
end)

minetest.register_craftitem("craftguide:book", {
	description = "Crafting Guide",
	inventory_image = "craftguide_book.png",
	wield_image = "craftguide_book.png",
	stack_max = 1,
	groups = {book=1},
	on_use = function(itemstack, user)
		local player_name = user:get_player_name()
		if progressive_mode or not datas[player_name] then
			datas[player_name] = {filter="", pagenum=1}
			craftguide:get_items(player_name)
			craftguide:get_formspec(player_name)
		else
			minetest.show_formspec(player_name, "craftguide:book",
					       datas[player_name].formspec)
		end
	end
})

minetest.register_craft({
	output = "craftguide:book",
	type = "shapeless",
	recipe = {"default:book"}
})

minetest.register_craft({
	type = "fuel",
	recipe = "craftguide:book",
	burntime = 3
})

minetest.register_alias("xdecor:crafting_guide", "craftguide:book")

