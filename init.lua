craftguide = {
	custom_crafts = {},
	craft_types = {},
}

local mt = minetest
local player_data = {}
local init_items = {}
local recipes_cache = {}
local fuel_cache = {}
local searches = {}

local progressive_mode = mt.settings:get_bool("craftguide_progressive_mode")
local sfinv_only = mt.settings:get_bool("craftguide_sfinv_only") and rawget(_G, "sfinv")

local colorize = mt.colorize
local fs_esc = mt.formspec_escape
local reg_items = mt.registered_items
local get_result = mt.get_craft_result
local show_formspec = mt.show_formspec
local get_player_by_name = mt.get_player_by_name
local serialize, deserialize = mt.serialize, mt.deserialize

local S = mt.get_translator("craftguide")

-- Lua 5.3 removed `table.maxn`, use this alternative in case of breakage:
-- https://github.com/kilbith/xdecor/blob/master/handlers/helpers.lua#L1
local maxn, sort, concat = table.maxn, table.sort, table.concat
local vector_add, vector_mul = vector.add, vector.multiply
local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil
local fmt, pairs, next = string.format, pairs, next

local DEFAULT_SIZE = 10
local MIN_LIMIT, MAX_LIMIT = 10, 12
DEFAULT_SIZE = min(MAX_LIMIT, max(MIN_LIMIT, DEFAULT_SIZE))

local GRID_LIMIT = 5

local fmt_label   = "label[%f,%f;%s]"
local fmt_image   = "image[%f,%f;%f,%f;%s]"
local fmt_tooltip = "tooltip[%f,%f;%f,%f;%s]"

local group_stereotypes = {
	wool         = "wool:white",
	dye          = "dye:white",
	water_bucket = "bucket:bucket_water",
	vessel       = "vessels:glass_bottle",
	coal         = "default:coal_lump",
	flower       = "flowers:dandelion_yellow",
	mesecon_conductor_craftable = "mesecons:wire_00000000_off",
}

local item_lists = {
	"main",
	"craft",
	"craftpreview",
}

local function table_merge(t, t2)
	t, t2 = t or {}, t2 or {}
	local c = #t

	for i = 1, #t2 do
		c = c + 1
		t[c] = t2[i]
	end

	return t
end

local function table_diff(t, t2)
	local hash = {}

	for i = 1, #t do
		local v = t[i]
		hash[v] = true
	end

	for i = 1, #t2 do
		local v = t2[i]
		hash[v] = nil
	end

	local ret, c = {}, 0

	for i = 1, #t do
		local v = t[i]
		if hash[v] then
			c = c + 1
			ret[c] = v
		end
	end

	return ret
end

local function __func()
	return debug.getinfo(2, "n").name
end

function craftguide.register_craft_type(name, def)
	local func = "craftguide." .. __func() .. "(): "
	assert(name, func .. "'name' field missing")
	assert(def.description, func .. "'description' field missing")
	assert(def.icon, func .. "'icon' field missing")

	if not craftguide.craft_types[name] then
		craftguide.craft_types[name] = def
	end
end

function craftguide.register_craft(def)
	local func = "craftguide." .. __func() .. "(): "
	assert(def.type, func .. "'type' field missing")
	assert(def.width, func .. "'width' field missing")
	assert(def.output, func .. "'output' field missing")
	assert(def.items, func .. "'items' field missing")

	craftguide.custom_crafts[#craftguide.custom_crafts + 1] = def
end

local recipe_filters = {}

function craftguide.add_recipe_filter(name, func)
	recipe_filters[name] = func
end

function craftguide.remove_recipe_filter(name)
	recipe_filters[name] = nil
end

function craftguide.set_recipe_filter(name, func)
	recipe_filters = {[name] = func}
end

function craftguide.get_recipe_filters()
	return recipe_filters
end

local function apply_recipe_filters(recipes, player)
	for _, filter in pairs(recipe_filters) do
		recipes = filter(recipes, player)
	end

	return recipes
end

local function item_has_groups(item_groups, groups)
	for i = 1, #groups do
		local group = groups[i]
		if not item_groups[group] then
			return
		end
	end

	return true
end

local function extract_groups(str)
	return str:sub(7):split(",")
end

local function item_in_recipe(item, recipe)
	local item_groups = reg_items[item].groups
	for _, recipe_item in pairs(recipe.items) do
		if recipe_item == item then
			return true
		elseif recipe_item:sub(1,6) == "group:" then
			local groups = extract_groups(recipe_item)
			if item_has_groups(item_groups, groups) then
				return true
			end
		end
	end
end

local function get_item_usages(item)
	local usages, c = {}, 0

	for _, recipes in pairs(recipes_cache) do
	for i = 1, #recipes do
		local recipe = recipes[i]
		if item_in_recipe(item, recipe) then
			c = c + 1
			usages[c] = recipe
		end
	end
	end

	if fuel_cache[item] then
		usages[#usages + 1] = {type = "fuel", width = 1, items = {item}}
	end

	return usages
end

local function get_filtered_items(player)
	local items, c = {}, 0

	for i = 1, #init_items do
		local item = init_items[i]
		local recipes = recipes_cache[item]
		local fuel = fuel_cache[item]

		if recipes and #apply_recipe_filters(recipes, player) > 0 or
		   fuel and #apply_recipe_filters(get_item_usages(item), player) > 0 then
			c = c + 1
			items[c] = item
		end
	end

	return items
end

local function cache_recipes(output)
	local recipes = mt.get_all_craft_recipes(output) or {}
	local c = 0

	for i = 1, #craftguide.custom_crafts do
		local custom_craft = craftguide.custom_crafts[i]
		if custom_craft.output:match("%S*") == output then
			c = c + 1
			recipes[c] = custom_craft
		end
	end

	if #recipes > 0 then
		recipes_cache[output] = recipes
		return true
	end
end

local function get_recipes(item, data, player)
	local is_fuel = fuel_cache[item]
	local recipes = recipes_cache[item]

	if recipes then
		recipes = apply_recipe_filters(recipes, player)
	end

	local no_recipes = not recipes or #recipes == 0
	if no_recipes and not is_fuel then
		return
	elseif is_fuel and no_recipes then
		data.show_usages = true
	end

	if data.show_usages then
		recipes = apply_recipe_filters(get_item_usages(item), player)
		if #recipes == 0 then
			return
		end
	end

	return recipes
end

local function get_burntime(item)
	return get_result({method = "fuel", width = 1, items = {item}}).time
end

local function cache_fuel(item)
	local burntime = get_burntime(item)
	if burntime > 0 then
		fuel_cache[item] = burntime
		return true
	end
end

local function groups_to_item(groups)
	if #groups == 1 then
		local group = groups[1]
		if group_stereotypes[group] then
			return group_stereotypes[group]
		elseif reg_items["default:" .. group] then
			return "default:" .. group
		end
	end

	for name, def in pairs(reg_items) do
		if item_has_groups(def.groups, groups) then
			return name
		end
	end

	return ""
end

local function get_tooltip(item, groups, cooktime, burntime)
	local tooltip

	if groups then
		local groupstr = {}
		for i = 1, #groups do
			groupstr[#groupstr + 1] = colorize("yellow", groups[i])
		end

		groupstr = concat(groupstr, ", ")
		tooltip = S("Any item belonging to the group(s): @1", groupstr)
	else
		tooltip = reg_items[item].description
	end

	if cooktime then
		tooltip = tooltip .. "\n" ..
			S("Cooking time: @1", colorize("yellow", cooktime))
	end

	if burntime then
		tooltip = tooltip .. "\n" ..
			S("Burning time: @1", colorize("yellow", burntime))
	end

	return "tooltip[" .. item .. ";" .. fs_esc(tooltip) .. "]"
end

local function get_recipe_fs(data, iY)
	local fs = {}
	local recipe = data.recipes[data.rnum]
	local width = recipe.width
	local xoffset = data.iX / 2.15
	local cooktime, shapeless

	if recipe.type == "cooking" then
		cooktime, width = width, 1
	elseif width == 0 then
		shapeless = true
		width = min(3, #recipe.items)
	end

	local rows = ceil(maxn(recipe.items) / width)
	local rightest, btn_size, s_btn_size = 0, 1.1

	if width > GRID_LIMIT or rows > GRID_LIMIT then
		fs[#fs + 1] = fmt(fmt_label,
			(data.iX / 2) - 2,
			iY + 2.2,
			fs_esc(S("Recipe is too big to be displayed (@1x@2)", width, rows)))

		return concat(fs)
	end

	for i, item in pairs(recipe.items) do
		local X = ceil((i - 1) % width + xoffset - width) -
			(sfinv_only and 0 or 0.2)
		local Y = ceil(i / width + (iY + 2) - min(2, rows))

		if width > 3 or rows > 3 then
			btn_size = width > 3 and 3 / width or 3 / rows
			s_btn_size = btn_size
			X = btn_size * (i % width) + xoffset - 2.65
			Y = btn_size * floor((i - 1) / width) + (iY + 3) - min(2, rows)
		end

		if X > rightest then
			rightest = X
		end

		local groups
		if item:sub(1,6) == "group:" then
			groups = extract_groups(item)
			item = groups_to_item(groups)
		end

		local label = groups and "\nG" or ""

		fs[#fs + 1] = fmt("item_image_button[%f,%f;%f,%f;%s;%s;%s]",
			X,
			Y + (sfinv_only and 0.7 or 0.2),
			btn_size,
			btn_size,
			item,
			item:match("%S*"),
			fs_esc(label))

		local burntime = fuel_cache[item]

		if groups or cooktime or burntime then
			fs[#fs + 1] = get_tooltip(item, groups, cooktime, burntime)
		end
	end

	local custom_recipe = craftguide.craft_types[recipe.type]

	if custom_recipe or shapeless or recipe.type == "cooking" then
		local icon = custom_recipe and custom_recipe.icon or
			     shapeless and "shapeless" or "furnace"

		if not custom_recipe then
			icon = "craftguide_" .. icon .. ".png^[resize:16x16"
		end

		fs[#fs + 1] = fmt(fmt_image,
			rightest + 1.2,
			iY + (sfinv_only and 2.2 or 1.7),
			0.5,
			0.5,
			icon)

		local tooltip = custom_recipe and custom_recipe.description or
				shapeless and S("Shapeless") or S("Cooking")

		fs[#fs + 1] = fmt(fmt_tooltip,
			rightest + 1.2,
			iY + (sfinv_only and 2.2 or 1.7),
			0.5,
			0.5,
			fs_esc(tooltip))
	end

	local arrow_X  = rightest + (s_btn_size or 1.1)
	local output_X = arrow_X + 0.9

	fs[#fs + 1] = fmt(fmt_image,
		arrow_X,
		iY + (sfinv_only and 2.85 or 2.35),
		0.9,
		0.7,
		"craftguide_arrow.png")

	if recipe.type == "fuel" then
		fs[#fs + 1] = fmt(fmt_image,
			output_X,
			iY + (sfinv_only and 2.68 or 2.18),
			1.1,
			1.1,
			"craftguide_fire.png")
	else
		local output_name = recipe.output:match("%S+")
		local burntime = fuel_cache[output_name]

		fs[#fs + 1] = fmt("item_image_button[%f,%f;%f,%f;%s;%s;]",
			output_X,
			iY + (sfinv_only and 2.7 or 2.2),
			1.1,
			1.1,
			recipe.output,
			fs_esc(output_name))

		if burntime then
			fs[#fs + 1] = get_tooltip(output_name, nil, nil, burntime)

			fs[#fs + 1] = fmt(fmt_image,
				output_X + 1,
				iY + (sfinv_only and 2.83 or 2.33),
				0.6,
				0.4,
				"craftguide_arrow.png")

			fs[#fs + 1] = fmt(fmt_image,
				output_X + 1.6,
				iY + (sfinv_only and 2.68 or 2.18),
				0.6,
				0.6,
				"craftguide_fire.png")
		end
	end

	fs[#fs + 1] = fmt("button[%f,%f;%f,%f;%s;%s %u %s %u]",
		data.iX - (sfinv_only and 2.2 or 2.6),
		iY + (sfinv_only and 3.9 or 3.3),
		2.2,
		1,
		"alternate",
		data.show_usages and fs_esc(S("Usage")) or fs_esc(S("Recipe")),
		data.rnum,
		fs_esc(S("of")),
		#data.recipes)

	return concat(fs)
end

local function make_formspec(name)
	local data = player_data[name]
	local iY = sfinv_only and 4 or data.iX - 5
	local ipp = data.iX * iY

	data.pagemax = max(1, ceil(#data.items / ipp))

	local fs = {}

	if not sfinv_only then
		fs[#fs + 1] = fmt("size[%f,%f;]", data.iX - 0.35, iY + 4)
		fs[#fs + 1] = [[
			no_prepend[]
			background[1,1;1,1;craftguide_bg.png;true]
		]]

		fs[#fs + 1] = "tooltip[size_inc;" .. fs_esc(S("Increase window size")) .. "]"
		fs[#fs + 1] = "tooltip[size_dec;" .. fs_esc(S("Decrease window size")) .. "]"

		fs[#fs + 1] = "image_button[" .. (data.iX * 0.47) ..
				",0.12;0.8,0.8;craftguide_zoomin_icon.png;size_inc;]"
		fs[#fs + 1] = "image_button[" .. ((data.iX * 0.47) + 0.6) ..
				",0.12;0.8,0.8;craftguide_zoomout_icon.png;size_dec;]"
	end

	fs[#fs + 1] = [[
		image_button[2.4,0.12;0.8,0.8;craftguide_search_icon.png;search;]
		image_button[3.05,0.12;0.8,0.8;craftguide_clear_icon.png;clear;]
		field_close_on_enter[filter;false]
	]]

	fs[#fs + 1] = "tooltip[search;" .. fs_esc(S("Search")) .. "]"
	fs[#fs + 1] = "tooltip[clear;" .. fs_esc(S("Reset")) .. "]"
	fs[#fs + 1] = "tooltip[prev;" .. fs_esc(S("Previous page")) .. "]"
	fs[#fs + 1] = "tooltip[next;" .. fs_esc(S("Next page")) .. "]"

	fs[#fs + 1] = "image_button[" .. (data.iX - (sfinv_only and 2.6 or 3.1)) ..
			",0.12;0.8,0.8;craftguide_prev_icon.png;prev;]"

	fs[#fs + 1] = fmt(fmt_label,
			data.iX - (sfinv_only and 1.7 or 2.2),
			0.22,
			colorize("yellow", data.pagenum) .. " / " .. data.pagemax)

	fs[#fs + 1] = "image_button[" .. (data.iX -
			(sfinv_only and 0.7 or 1.2) - (data.iX >= 11 and 0.08 or 0)) ..
			",0.12;0.8,0.8;craftguide_next_icon.png;next;]"

	fs[#fs + 1] = "field[0.3,0.32;2.5,1;filter;;" .. fs_esc(data.filter) .. "]"

	if #data.items == 0 then
		local no_item = S("No item to show")
		local pos = (data.iX / 2) - 1

		if next(recipe_filters) and #init_items > 0 and data.filter == "" then
			no_item = S("Collect items to reveal more recipes")
			pos = pos - 1
		end

		fs[#fs + 1] = fmt(fmt_label, pos, 2, fs_esc(no_item))
	end

	local first_item = (data.pagenum - 1) * ipp
	for i = first_item, first_item + ipp - 1 do
		local item = data.items[i + 1]
		if not item then
			break
		end

		local X = i % data.iX
		local Y = (i % ipp - X) / data.iX + 1

		fs[#fs + 1] = fmt("item_image_button[%f,%f;%f,%f;%s;%s_inv;]",
			X - (sfinv_only and 0 or (X * 0.05)),
			Y,
			1.1,
			1.1,
			item,
			item)
	end

	if data.recipes and #data.recipes > 0 then
		fs[#fs + 1] = get_recipe_fs(data, iY)
	end

	return concat(fs)
end

local show_fs = function(player, name)
	if sfinv_only then
		sfinv.set_player_inventory_formspec(player)
	else
		show_formspec(name, "craftguide", make_formspec(name))
	end
end

local function search(data)
	local filter = data.filter

	if searches[filter] then
		data.items = searches[filter]
		return
	end

	local filtered_list, c = {}, 0

	for i = 1, #data.items_raw do
		local item = data.items_raw[i]
		local desc = reg_items[item].description:lower()

		if (item .. desc):find(filter, 1, true) then
			c = c + 1
			filtered_list[c] = item
		end
	end

	if not next(recipe_filters) then
		-- Cache the results only if searched 2 times
		if searches[filter] == nil then
			searches[filter] = false
		else
			searches[filter] = filtered_list
		end
	end

	data.items = filtered_list
end

local function get_inv_items(player)
	local inv = player:get_inventory()
	local stacks = {}

	for i = 1, #item_lists do
		stacks = table_merge(stacks, inv:get_list(item_lists[i]))
	end

	local inv_items, c = {}, 0

	for i = 1, #stacks do
		local stack = stacks[i]
		if not stack:is_empty() then
			local name = stack:get_name()
			if reg_items[name] then
				c = c + 1
				inv_items[c] = name
			end
		end
	end

	return inv_items
end

local function init_data(name)
	player_data[name] = {
		filter  = "",
		pagenum = 1,
		iX      = sfinv_only and 8 or DEFAULT_SIZE,
		items   = init_items,
		items_raw = init_items,
	}
end

local function reset_data(data)
	data.filter      = ""
	data.pagenum     = 1
	data.rnum        = 1
	data.query_item  = nil
	data.show_usages = nil
	data.recipes     = nil
	data.items       = data.items_raw
end

local function get_init_items()
	local c = 0
	for name, def in pairs(reg_items) do
		local is_fuel = cache_fuel(name)
		if not (def.groups.not_in_craft_guide == 1 or
				def.groups.not_in_creative_inventory == 1) and
				def.description and def.description ~= "" and
				(cache_recipes(name) or is_fuel) then
			c = c + 1
			init_items[c] = name
		end
	end

	sort(init_items)
end

local function on_receive_fields(player, fields)
	local name = player:get_player_name()
	local data = player_data[name]

	if fields.clear then
		reset_data(data)
		show_fs(player, name)

	elseif fields.alternate then
		if #data.recipes == 1 then
			return
		end

		local num_next = data.rnum + 1
		data.rnum = data.recipes[num_next] and num_next or 1
		show_fs(player, name)

	elseif (fields.key_enter_field == "filter" or fields.search) and
			fields.filter ~= "" then
		local fltr = fields.filter:lower()
		if data.filter == fltr then
			return
		end

		data.filter = fltr
		data.pagenum = 1
		search(data)
		show_fs(player, name)

	elseif fields.prev or fields.next then
		if data.pagemax == 1 then
			return
		end

		data.pagenum = data.pagenum - (fields.prev and 1 or -1)

		if data.pagenum > data.pagemax then
			data.pagenum = 1
		elseif data.pagenum == 0 then
			data.pagenum = data.pagemax
		end

		show_fs(player, name)

	elseif (fields.size_inc and data.iX < MAX_LIMIT) or
			(fields.size_dec and data.iX > MIN_LIMIT) then
		data.pagenum = 1
		data.iX = data.iX + (fields.size_inc and 1 or -1)
		show_fs(player, name)

	else
		local item
		for field in pairs(fields) do
			if field:find(":") then
				item = field
				break
			end
		end

		if not item then
			return
		elseif item:sub(-4) == "_inv" then
			item = item:sub(1,-5)
		end

		if item ~= data.query_item then
			data.show_usages = nil
		else
			data.show_usages = not data.show_usages
		end

		local recipes = get_recipes(item, data, player)
		if not recipes then
			return
		end

		data.query_item = item
		data.recipes    = recipes
		data.rnum       = 1

		show_fs(player, name)
	end
end

mt.register_on_mods_loaded(get_init_items)

mt.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	init_data(name)
end)

mt.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	player_data[name] = nil
end)

if sfinv_only then
	sfinv.register_page("craftguide:craftguide", {
		title = S("Craft Guide"),

		get = function(self, player, context)
			local name = player:get_player_name()
			local formspec = make_formspec(name)

			return sfinv.make_formspec(player, context, formspec)
		end,

		on_enter = function(self, player, context)
			if next(recipe_filters) then
				local name = player:get_player_name()
				local data = player_data[name]

				data.items_raw = get_filtered_items(player)
				search(data)
			end
		end,

		on_player_receive_fields = function(self, player, context, fields)
			on_receive_fields(player, fields)
		end,
	})
else
	mt.register_on_player_receive_fields(function(player, formname, fields)
		if formname == "craftguide" then
			on_receive_fields(player, fields)
		end
	end)

	local function on_use(user)
		local name = user:get_player_name()

		if next(recipe_filters) then
			local data = player_data[name]
			data.items_raw = get_filtered_items(user)
			search(data)
		end

		show_formspec(name, "craftguide", make_formspec(name))
	end

	mt.register_craftitem("craftguide:book", {
		description = S("Crafting Guide"),
		inventory_image = "craftguide_book.png",
		wield_image = "craftguide_book.png",
		stack_max = 1,
		groups = {book = 1},
		on_use = function(itemstack, user)
			on_use(user)
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
		groups = {oddly_breakable_by_hand = 1, flammable = 3},
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
			on_use(user)
		end
	})

	mt.register_craft({
		output = "craftguide:book",
		recipe = {
			{"default:book"}
		}
	})

	mt.register_craft({
		type = "fuel",
		recipe = "craftguide:book",
		burntime = 3
	})

	mt.register_craft({
		output = "craftguide:sign",
		recipe = {
			{"default:sign_wall_wood"}
		}
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
			image = "craftguide_book.png",
			action = function(player)
				on_use(player)
			end,
		})
	end
end

if progressive_mode then
	local function item_in_inv(item, inv_items)
		local inv_items_size = #inv_items

		if item:sub(1,6) == "group:" then
			local groups = extract_groups(item)
			for i = 1, inv_items_size do
				local item_groups = reg_items[inv_items[i]].groups
				if item_has_groups(item_groups, groups) then
					return true
				end
			end
		else
			for i = 1, inv_items_size do
				if inv_items[i] == item then
					return true
				end
			end
		end
	end

	local function recipe_in_inv(recipe, inv_items)
		for _, item in pairs(recipe.items) do
			if not item_in_inv(item, inv_items) then
				return
			end
		end

		return true
	end

	local function progressive_filter(recipes, player)
		local name = player:get_player_name()
		local data = player_data[name]

		if #data.inv_items == 0 then
			return {}
		end

		local filtered, c = {}, 0
		for i = 1, #recipes do
			local recipe = recipes[i]
			if recipe_in_inv(recipe, data.inv_items) then
				c = c + 1
				filtered[c] = recipe
			end
		end

		return filtered
	end

	mt.register_globalstep(function()
		local players = mt.get_connected_players()
		for i = 1, #players do
			local player = players[i]
			local name   = player:get_player_name()
			local data   = player_data[name]
			local inv_items = get_inv_items(player)
			local diff      = table_diff(inv_items, data.inv_items)

			if #diff > 0 then
				data.inv_items = table_merge(diff, data.inv_items)
			end
		end
	end)

	craftguide.add_recipe_filter("Default progressive filter", progressive_filter)

	mt.register_on_joinplayer(function(player)
		local meta = player:get_meta()
		local name = player:get_player_name()
		local data = player_data[name]

		data.inv_items = deserialize(meta:get_string("inv_items")) or {}
	end)

	local function save_meta(player)
		local meta = player:get_meta()
		local name = player:get_player_name()
		local data = player_data[name]

		meta:set_string("inv_items", serialize(data.inv_items))
	end

	mt.register_on_leaveplayer(save_meta)

	mt.register_on_shutdown(function()
		local players = mt.get_connected_players()
		for i = 1, #players do
			local player = players[i]
			save_meta(player)
		end
	end)
end

mt.register_chatcommand("craft", {
	description = S("Show recipe(s) of the pointed node"),
	func = function(name)
		local player = get_player_by_name(name)
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

		local red = colorize("red", "[craftguide] ")

		if not node_name then
			return false, red .. S("No node pointed")
		end

		local data = player_data[name]
		reset_data(data)

		local recipes = recipes_cache[node_name]
		local is_fuel = fuel_cache[node_name]

		if recipes then
			recipes = apply_recipe_filters(recipes, player)
		end

		if not recipes or #recipes == 0 then
			local ylw = colorize("yellow", node_name)
			local msg = red .. "%s: " .. ylw

			if is_fuel then
				recipes = get_item_usages(node_name)
				if #recipes > 0 then
					data.show_usages = true
				end
			elseif recipes_cache[node_name] then
				return false, fmt(msg, S("You don't know a recipe for this node"))
			else
				return false, fmt(msg, S("No recipe for this node"))
			end
		end

		data.query_item = node_name
		data.recipes    = recipes

		return true, show_fs(player, name)
	end,
})

function craftguide.show(name, item, show_usages)
	local func = "craftguide." .. __func() .. "(): "
	assert(name, func .. "player name missing")

	local data   = player_data[name]
	local player = get_player_by_name(name)
	local query_item = data.query_item

	reset_data(data)

	item = reg_items[item] and item or query_item

	data.query_item  = item
	data.show_usages = show_usages
	data.recipes     = get_recipes(item, data, player)

	show_fs(player, name)
end

--[[ Custom recipes (>3x3) test code

mt.register_craftitem(":secretstuff:custom_recipe_test", {
	description = "Custom Recipe Test",
})

local cr = {}
for x = 1, 6 do
	cr[x] = {}
	for i = 1, 10 - x do
		cr[x][i] = {}
		for j = 1, 10 - x do
			cr[x][i][j] = "group:sand"
		end
	end

	mt.register_craft({
		output = "secretstuff:custom_recipe_test",
		recipe = cr[x]
	})
end
]]
