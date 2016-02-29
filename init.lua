local craftguide, datas = {}, {}

function craftguide:get_recipe(item)
	if item:sub(1,6) == "group:" then
		if item:sub(-4) == "wool" or item:sub(-3) == "dye" then
			item = item:sub(7)..":white"
		elseif minetest.registered_items["default:"..item:sub(7)] then
			item = item:gsub("group:", "default:")
		else for node, def in pairs(minetest.registered_items) do
			 if def.groups[item:match("[^,:]+$")] then item = node end
		     end
		end
	end
	return item
end

function craftguide:get_formspec(stack, pagenum, item, recipe_num, filter, player_name)
	local inv_size = datas[player_name].size
	local npp, i, s = 8*3, 0, 0
	local pagemax = math.floor((inv_size - 1) / npp + 1)

	if     pagenum > pagemax then pagenum = 1
	elseif pagenum == 0      then pagenum = pagemax end

	local formspec = [[ size[8,6.6;]
			tablecolumns[color;text;color;text]
			tableoptions[background=#00000000;highlight=#00000000;border=false]
			button[5.4,0;0.8,0.95;prev;<]
			button[7.2,0;0.8,0.95;next;>]
			button[2.5,0.2;0.8,0.5;search;?]
			button[3.2,0.2;0.8,0.5;clear;X]
			tooltip[search;Search]
			tooltip[clear;Reset] ]]
			.."table[6,0.18;1.1,0.5;pagenum;#FFFF00,"..tostring(pagenum)..
			",#FFFFFF,/ "..tostring(pagemax).."]"..
			"field[0.3,0.32;2.6,1;filter;;"..filter.."]"..
			default.gui_bg..default.gui_bg_img

	for _, name in pairs(self:get_items(filter, player_name)) do
		if s < (pagenum - 1) * npp then
			s = s + 1
		else if i >= npp then break end
			local X = i % 8
			local Y = math.floor(i/8) + 1

			formspec = formspec.."item_image_button["..X..","..Y..";1,1;"..
					     name..";"..name..";]"
			i = i + 1
		end
	end

	if item and minetest.registered_items[item] then
		local recipes = minetest.get_all_craft_recipes(item)
		if recipe_num > #recipes then recipe_num = 1 end

		if #recipes > 1 then formspec = formspec..
			"button[0,6;1.6,1;alternate;Alternate]"..
			"label[0,5.5;Recipe "..recipe_num.." of "..#recipes.."]"
		end
		
		local type = recipes[recipe_num].type
		if type == "cooking" then formspec = formspec..
			"image[3.75,4.6;0.5,0.5;default_furnace_fire_fg.png]"
		end

		local items = recipes[recipe_num].items
		local width = recipes[recipe_num].width
		if width == 0 then width = math.min(3, #items) end
		-- Lua 5.3 removed `table.maxn`, use this alternative in case of breakage:
		-- https://github.com/kilbith/xdecor/blob/master/handlers/helpers.lua#L1
		local rows = math.ceil(table.maxn(items) / width)

		for i, v in pairs(items) do
			local X = (i-1) % width + 4.5
			local Y = math.floor((i-1) / width + (6 - math.min(2, rows)))
			local label = ""
			if v:sub(1,6) == "group:" then label = "\nG" end

			formspec = formspec.."item_image_button["..X..","..Y..";1,1;"..
					     self:get_recipe(v)..";"..self:get_recipe(v)..";"..label.."]"
		end

		local output = recipes[recipe_num].output
		formspec = formspec.."item_image_button[2.5,5;1,1;"..output..";"..item..";]"..
				     "image[3.5,5;1,1;gui_furnace_arrow_bg.png^[transformR90]"
	end
	
	stack:set_metadata(formspec)
	datas[player_name].formspec = stack:get_metadata()
	minetest.show_formspec(player_name, "xdecor:crafting_guide", formspec)
end

function craftguide:get_items(filter, player_name)
	local items_list = {}
	for name, def in pairs(minetest.registered_items) do
		if not (def.groups.not_in_creative_inventory == 1) and
				minetest.get_craft_recipe(name).items and
				def.description and def.description ~= "" and
				(not filter or def.name:find(filter, 1, true) or
					def.description:lower():find(filter, 1, true)) then
			items_list[#items_list+1] = name
		end
	end

	datas[player_name].size = #items_list
	table.sort(items_list)
	return items_list
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "xdecor:crafting_guide" then return end
	local player_name = player:get_player_name()
	local stack = player:get_wielded_item()
	local formspec = datas[player_name].formspec
	local filter = formspec:match("filter;;([%w_:]+)") or ""
	local pagenum = tonumber(formspec:match("#FFFF00,(%d+)")) or 1

	if fields.clear then
		craftguide:get_items(nil, player_name)
		craftguide:get_formspec(stack, 1, nil, 1, "", player_name)
	elseif fields.alternate then
		local item = formspec:match("item_image_button%[.*;([%w_:]+);") or 1
		local recipe_num = tonumber(formspec:match("Recipe%s(%d+)")) or 1
		recipe_num = recipe_num + 1
		craftguide:get_formspec(stack, pagenum, item, recipe_num, filter, player_name)
	elseif fields.search then
		local lowstr = fields.filter:lower()
		craftguide:get_items(lowstr, player_name)
		craftguide:get_formspec(stack, 1, nil, 1, lowstr, player_name)
	elseif fields.prev or fields.next then
		if fields.prev then pagenum = pagenum - 1
		else pagenum = pagenum + 1 end
		craftguide:get_formspec(stack, pagenum, nil, 1, filter, player_name)
	else for item in pairs(fields) do
		 if minetest.get_craft_recipe(item).items then
			craftguide:get_formspec(stack, pagenum, item, 1, filter, player_name)
		 end
	     end
	end
end)

minetest.register_craftitem(":xdecor:crafting_guide", {
	description = "Crafting Guide",
	inventory_image = "crafting_guide.png",
	wield_image = "crafting_guide.png",
	stack_max = 1,
	groups = {book=1},
	on_use = function(itemstack, user)
		local player_name = user:get_player_name()
		datas[player_name] = {}

		craftguide:get_items(nil, player_name)
		craftguide:get_formspec(itemstack, 1, nil, 1, "", player_name)
	end
})

minetest.register_craft({ 
	output = "xdecor:crafting_guide",
	type = "shapeless",
	recipe = {"default:book"}
})

