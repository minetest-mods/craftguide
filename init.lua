craftguide = {}

-- Caches
local pdata         = {}
local init_items    = {}
local searches      = {}
local recipes_cache = {}
local usages_cache  = {}
local fuel_cache    = {}

local toolrepair

local progressive_mode = core.settings:get_bool("craftguide_progressive_mode")
local sfinv_only = core.settings:get_bool("craftguide_sfinv_only") and rawget(_G, "sfinv")

local log = core.log
local after = core.after
local clr = core.colorize
local reg_tools = core.registered_tools
local reg_items = core.registered_items
local show_formspec = core.show_formspec
local globalstep = core.register_globalstep
local on_shutdown = core.register_on_shutdown
local get_players = core.get_connected_players
local get_craft_result = core.get_craft_result
local on_joinplayer = core.register_on_joinplayer
local get_all_recipes = core.get_all_craft_recipes
local register_command = core.register_chatcommand
local get_player_by_name = core.get_player_by_name
local on_mods_loaded = core.register_on_mods_loaded
local on_leaveplayer = core.register_on_leaveplayer
local serialize, deserialize = core.serialize, core.deserialize
local on_receive_fields = core.register_on_player_receive_fields

local ESC = core.formspec_escape
local S = core.get_translator("craftguide")

local maxn, sort, concat, copy, insert =
	table.maxn, table.sort, table.concat, table.copy, table.insert

local fmt, find, gmatch, match, sub, split, upper, lower =
	string.format, string.find, string.gmatch, string.match,
	string.sub, string.split, string.upper, string.lower

local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil
local pairs, next = pairs, next
local vec_add, vec_mul = vector.add, vector.multiply

local ROWS  = sfinv_only and 9 or 11
local LINES = 5
local IPP   = ROWS * LINES
local WH_LIMIT = 8

local XOFFSET = sfinv_only and 3.83 or 4.66
local YOFFSET = sfinv_only and 6 or 6.6

local DEV_CORE = sub(core.get_version().string, -3) == "dev"

craftguide.background = "craftguide_bg_full.png:10"

local PNG = {
	bg     = "craftguide_bg.png",
	search = "craftguide_search_icon.png",
	clear  = "craftguide_clear_icon.png",
	prev   = "craftguide_next_icon.png^\\[transformFX",
	next   = "craftguide_next_icon.png",
	arrow  = "craftguide_arrow.png",
	fire   = "craftguide_fire.png",
	book   = "craftguide_book.png",
	sign   = "craftguide_sign.png",
}

local FMT = {
	box = "box[%f,%f;%f,%f;%s]",
	label = "label[%f,%f;%s]",
	image = "image[%f,%f;%f,%f;%s]",
	button = "button[%f,%f;%f,%f;%s;%s]",
	tooltip = "tooltip[%f,%f;%f,%f;%s]",
	item_image = "item_image[%f,%f;%f,%f;%s]",
	image_button = "image_button[%f,%f;%f,%f;%s;%s;%s]",
	item_image_button = "item_image_button[%f,%f;%f,%f;%s;%s;%s]",
}

craftguide.group_stereotypes = {
	dye = "dye:white",
	wool = "wool:white",
	coal = "default:coal_lump",
	vessel = "vessels:glass_bottle",
	flower = "flowers:dandelion_yellow",
	water_bucket = "bucket:bucket_water",
	mesecon_conductor_craftable = "mesecons:wire_00000000_off",
}

local function table_merge(t1, t2, hash)
	t1 = t1 or {}
	t2 = t2 or {}

	if hash then
		for k, v in pairs(t2) do
			t1[k] = v
		end
	else
		local c = #t1

		for i = 1, #t2 do
			c = c + 1
			t1[c] = t2[i]
		end
	end

	return t1
end

local function table_replace(t, val, new)
	for k, v in pairs(t) do
		if v == val then
			t[k] = new
		end
	end
end

local function is_str(x)
	return type(x) == "string"
end

local function is_table(x)
	return type(x) == "table"
end

local function is_func(x)
	return type(x) == "function"
end

local function is_group(item)
	return sub(item, 1, 6) == "group:"
end

local craft_types = {}

function craftguide.register_craft_type(name, def)
	if not is_str(name) or name == "" then
		return log("error", "craftguide.register_craft_type(): name missing")
	end

	if not is_str(def.description) then
		def.description = ""
	end

	if not is_str(def.icon) then
		def.icon = ""
	end

	craft_types[name] = def
end

local function clean_name(item)
	return match(item, "%S*")
end

function craftguide.register_craft(def)
	def.custom = true
	def.width = 0
	local c = 0

	if not is_table(def) or not next(def) then
		return log("error", "craftguide.register_craft(): craft definition missing")
	end

	if def.result then
		def.output = def.result -- Backward compatibility
	end

	if not is_str(def.output) or def.output == "" then
		return log("error", "craftguide.register_craft(): output missing")
	end

	if not is_table(def.items) then
		def.items = {}
	end

	if def.grid then
		if not is_table(def.grid) then
			def.grid = {}
		end

		if not is_table(def.key) then
			def.key = {}
		end

		local cp = copy(def.grid)
		sort(cp, function(a, b)
			return #a > #b
		end)

		def.width = #cp[1]

		for i = 1, #def.grid do
			while #def.grid[i] < def.width do
				def.grid[i] = def.grid[i] .. " "
			end
		end

		for symbol in gmatch(concat(def.grid), ".") do
			c = c + 1
			def.items[c] = def.key[symbol]
		end
	else
		local items, len = def.items, #def.items
		def.items = {}

		for i = 1, len do
			items[i] = items[i]:gsub(",", ", ")
			local rlen = #split(items[i], ",")

			if rlen > def.width then
				def.width = rlen
			end
		end

		for i = 1, len do
			while #split(items[i], ",") < def.width do
				items[i] = items[i] .. ", "
			end
		end

		for name in gmatch(concat(items, ","), "[%s%w_:]+") do
			c = c + 1
			def.items[c] = clean_name(name)
		end
	end

	local output = clean_name(def.output)
	recipes_cache[output] = recipes_cache[output] or {}
	insert(recipes_cache[output], def)
end

local recipe_filters = {}

function craftguide.add_recipe_filter(name, f)
	if not is_str(name) or name == "" then
		return log("error", "craftguide.add_recipe_filter(): name missing")
	elseif not is_func(f) then
		return log("error", "craftguide.add_recipe_filter(): function missing")
	end

	recipe_filters[name] = f
end

function craftguide.remove_recipe_filter(name)
	recipe_filters[name] = nil
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

local search_filters = {}

function craftguide.add_search_filter(name, f)
	if not is_str(name) or name == "" then
		return log("error", "craftguide.add_search_filter(): name missing")
	elseif not is_func(f) then
		return log("error", "craftguide.add_search_filter(): function missing")
	end

	search_filters[name] = f
end

function craftguide.remove_search_filter(name)
	search_filters[name] = nil
end

function craftguide.get_search_filters()
	return search_filters
end

local function item_has_groups(item_groups, groups)
	for i = 1, #groups do
		local group = groups[i]
		if (item_groups[group] or 0) == 0 then return end
	end

	return true
end

local function extract_groups(str)
	return split(sub(str, 7), ",")
end

local function item_in_recipe(item, recipe)
	for _, recipe_item in pairs(recipe.items) do
		if recipe_item == item then
			return true
		end
	end
end

local function groups_item_in_recipe(item, recipe)
	local def = reg_items[item]
	local item_groups = def.groups

	for _, recipe_item in pairs(recipe.items) do
		if is_group(recipe_item) then
			local groups = extract_groups(recipe_item)

			if item_has_groups(item_groups, groups) then
				local usage = copy(recipe)
				table_replace(usage.items, recipe_item, item)
				return usage
			end
		end
	end
end

local function get_filtered_items(player, data)
	local items, known, c = {}, 0, 0

	for i = 1, #init_items do
		local item = init_items[i]
		local recipes = recipes_cache[item]
		local usages = usages_cache[item]

		recipes = #apply_recipe_filters(recipes or {}, player)
		usages  = #apply_recipe_filters(usages or {}, player)

		if recipes > 0 or usages > 0 then
			c = c + 1
			items[c] = item

			if data then
				known = known + recipes + usages
			end
		end
	end

	if data then
		data.known_recipes = known
	end

	return items
end

local function get_usages(item)
	local usages, c = {}, 0

	for _, recipes in pairs(recipes_cache) do
	for i = 1, #recipes do
		local recipe = recipes[i]
		if item_in_recipe(item, recipe) then
			c = c + 1
			usages[c] = recipe
		else
			recipe = groups_item_in_recipe(item, recipe)
			if recipe then
				c = c + 1
				usages[c] = recipe
			end
		end
	end
	end

	if fuel_cache[item] then
		usages[#usages + 1] = {
			type = "fuel",
			items = {item},
			replacements = fuel_cache.replacements[item],
		}
	end

	return usages
end

local function get_burntime(item)
	return get_craft_result({method = "fuel", items = {item}}).time
end

local function cache_fuel(item)
	local burntime = get_burntime(item)
	if burntime > 0 then
		fuel_cache[item] = burntime
	end
end

local function cache_usages(item)
	local usages = get_usages(item)
	if #usages > 0 then
		usages_cache[item] = table_merge(usages, usages_cache[item] or {})
	end
end

local function cache_recipes(output)
	local recipes = get_all_recipes(output) or {}
	if #recipes > 0 then
		recipes_cache[output] = recipes
	end
end

local function get_recipes(item, data, player)
	local recipes = recipes_cache[item]
	local usages = usages_cache[item]

	if recipes then
		recipes = apply_recipe_filters(recipes, player)
	end

	local no_recipes = not recipes or #recipes == 0

	if no_recipes and not usages then
		return
	elseif usages and no_recipes then
		data.show_usages = true
	end

	if data.show_usages then
		recipes = apply_recipe_filters(usages_cache[item], player)
		if recipes and #recipes == 0 then return end
	end

	return recipes
end

local function groups_to_items(groups, get_all)
	if not get_all and #groups == 1 then
		local group = groups[1]
		local def_gr = "default:" .. group
		local stereotypes = craftguide.group_stereotypes
		local stereotype = stereotypes and stereotypes[group]

		if stereotype then
			return stereotype
		elseif reg_items[def_gr] then
			return def_gr
		end
	end

	local names = {}
	for name, def in pairs(reg_items) do
		if item_has_groups(def.groups, groups) then
			names[#names + 1] = name
		end
	end

	return names
end

local function repairable(tool)
	local def = reg_tools[tool]
	return toolrepair and def and def.groups and def.groups.disable_repair ~= 1
end

local function get_tooltip(item, info)
	local tooltip

	if info.groups then
		local groupstr, c = {}, 0

		for i = 1, #info.groups do
			c = c + 1
			groupstr[c] = clr("yellow", info.groups[i])
		end

		groupstr = concat(groupstr, ", ")
		tooltip = S("Any item belonging to the group(s): @1", groupstr)

		return fmt("tooltip[%s;%s]", item, ESC(tooltip))
	end

	local function get_desc(def, name)
		name = name or item
		return def and def.description or
		      (def and match(name, ":.*"):gsub("%W%l", upper):sub(2):gsub("_", " ") or
		      S("Unknown Item (@1)", name))
	end

	tooltip = get_desc(reg_items[item])

	local function add(str)
		return fmt("%s\n%s", tooltip, str)
	end

	if info.cooktime then
		tooltip = add(S("Cooking time: @1", clr("yellow", info.cooktime)))
	end

	if info.burntime then
		tooltip = add(S("Burning time: @1", clr("yellow", info.burntime)))
	end

	if info.replace then
		local def = reg_items[info.replace]
		local desc = clr("yellow", get_desc(def, info.replace))

		if info.cooktime then
			tooltip = add(S("Replaced by @1 on smelting", desc))
		elseif info.burntime then
			tooltip = add(S("Replaced by @1 on burning", desc))
		else
			tooltip = add(S("Replaced by @1 on crafting", desc))
		end
	end

	if info.repair then
		tooltip = add(S("Repairable by step of @1", clr("yellow", toolrepair .. "%")))
	end

	return fmt("tooltip[%s;%s]", item, ESC(tooltip))
end

local function get_output_fs(fs, L)
	local custom_recipe = craft_types[L.recipe.type]

	if custom_recipe or L.shapeless or L.recipe.type == "cooking" then
		local icon = custom_recipe and custom_recipe.icon or
			     L.shapeless and "shapeless" or "furnace"

		if not custom_recipe then
			icon = fmt("craftguide_%s.png^[resize:16x16", icon)
		end

		local pos_x = L.rightest + L.btn_size + 0.1
		local pos_y = YOFFSET + (sfinv_only and 0.25 or -0.45)

		fs[#fs + 1] = fmt(FMT.image, pos_x, pos_y, 0.5, 0.5, icon)

		local tooltip = custom_recipe and custom_recipe.description or
				L.shapeless and S("Shapeless") or S("Cooking")

		fs[#fs + 1] = fmt("tooltip[%f,%f;%f,%f;%s]",
			pos_x, pos_y, 0.5, 0.5, ESC(tooltip))
	end

	local arrow_X = L.rightest + (L.s_btn_size or 1.1)
	local output_X = arrow_X + 0.9

	fs[#fs + 1] = fmt(FMT.image,
		arrow_X, YOFFSET + (sfinv_only and 0.9 or 0.2),
		0.9, 0.7, PNG.arrow)

	if L.recipe.type == "fuel" then
		fs[#fs + 1] = fmt(FMT.image,
			output_X, YOFFSET + (sfinv_only and 0.7 or 0),
			1.1, 1.1, PNG.fire)
	else
		local item = L.recipe.output
		local name = clean_name(item)

		fs[#fs + 1] = fmt(FMT.item_image_button,
			output_X, YOFFSET + (sfinv_only and 0.7 or 0),
			1.1, 1.1, item, ESC(name), "")

		local burntime = fuel_cache[name]
		local repair = repairable(name)

		if burntime or repair then
			fs[#fs + 1] = get_tooltip(name, {
				burntime = burntime,
				repair = repair,
			})
		end

		if burntime then
			fs[#fs + 1] = fmt(FMT.image,
				output_X + 1, YOFFSET + (sfinv_only and 0.7 or 0.1),
				0.6, 0.4, PNG.arrow)

			fs[#fs + 1] = fmt(FMT.image,
				output_X + 1.6, YOFFSET + (sfinv_only and 0.55 or 0),
				0.6, 0.6, PNG.fire)
		end
	end
end

local function get_recipe_fs(data, fs)
	local recipe = data.recipes[data.rnum]
	local width = recipe.width or 1
	local replacements = recipe.replacements
	local cooktime, shapeless

	if recipe.type == "cooking" then
		cooktime, width = width, 1
	elseif width == 0 and not recipe.custom then
		shapeless = true
		local n = #recipe.items
		width = (n < 5 and n > 1) and 2 or min(3, max(1, n))
	end

	local rows = ceil(maxn(recipe.items) / width)
	local rightest, btn_size, s_btn_size = 0, 1.1

	local btn_lab = data.show_usages and
		ESC(S("Usage @1 of @2", data.rnum, #data.recipes)) or
		ESC(S("Recipe @1 of @2", data.rnum, #data.recipes))

	fs[#fs + 1] = fmt(FMT.button,
		XOFFSET + (sfinv_only and 1.98 or 2.7),
		YOFFSET + (sfinv_only and 1.9 or 1.2),
		2.2, 1, "alternate", btn_lab)

	if width > WH_LIMIT or rows > WH_LIMIT then
		fs[#fs + 1] = fmt(FMT.label,
			sfinv_only and 2 or 3, 7,
			ESC(S("Recipe's too big to be displayed (@1x@2)", width, rows)))

		return concat(fs)
	end

	for i = 1, width * rows do
		local item = recipe.items[i] or ""
		local X = ceil((i - 1) % width - width) + XOFFSET
		local Y = ceil(i / width) + YOFFSET - min(2, rows)

		if width > 3 or rows > 3 then
			local xof = 1 - 4 / width
			local yof = 1 - 4 / rows
			local x_y = width > rows and xof or yof

			btn_size = width > rows and
				(3.5 + (xof * 2)) / width or (3.5 + (yof * 2)) / rows
			s_btn_size = btn_size

			X = (btn_size * ((i - 1) % width) + XOFFSET -
				(sfinv_only and 2.83 or (XOFFSET - 2))) * (0.83 - (x_y / 5))
			Y = (btn_size * floor((i - 1) / width) +
				(sfinv_only and 5.81 or 6.5) + x_y) * (0.86 - (x_y / 5))
		end

		if X > rightest then
			rightest = X
		end

		local groups

		if is_group(item) then
			groups = extract_groups(item)
			local items = groups_to_items(groups)
			item = items[1] or items
		end

		local label = groups and "\nG" or ""
		local replace

		if replacements then
			for j = 1, #replacements do
				local replacement = replacements[j]
				if replacement[1] == item then
					label = "\nR"
					replace = replacement[2]
				end
			end
		end

		fs[#fs + 1] = fmt(FMT.item_image_button,
			X, Y + (sfinv_only and 0.7 or 0),
			btn_size, btn_size, item, clean_name(item), ESC(label))

		local info = {
			unknown  = not reg_items[item],
			groups   = groups,
			burntime = fuel_cache[item],
			cooktime = cooktime,
			replace  = replace,
		}

		for _, v in pairs(info) do
			if v then
				fs[#fs + 1] = get_tooltip(item, info)
				break
			end
		end
	end

	get_output_fs(fs, {
		recipe     = recipe,
		shapeless  = shapeless,
		rightest   = rightest,
		btn_size   = btn_size,
		s_btn_size = s_btn_size,
	})
end

local function make_formspec(name)
	local data = pdata[name]
	data.pagemax = max(1, ceil(#data.items / IPP))

	local fs = {}

	if not sfinv_only then
		local bg, middle = match(craftguide.background, "(.-):(%d+)")
		bg = bg or ""
		middle = middle or "10"

		fs[#fs + 1] = fmt([[
			size[9.5,8.4]
			no_prepend[]
			bgcolor[#00000000;false]
			background[1,1;1,1;%s;true%s]
		]],
		bg, DEV_CORE and ";" .. middle or "")
	end

	fs[#fs + 1] = fmt([[
		field[0.25,0.2;%f,1;filter;;%s]
		field_close_on_enter[filter;false]
		]],
		sfinv_only and 2.76 or 2.72, ESC(data.filter))

	fs[#fs + 1] = fmt([[
		image_button[%f,-0.05;0.85,0.85;%s;search;;;false;%s^\[colorize:yellow:255]
		image_button[%f,-0.05;0.85,0.85;%s;clear;;;false;%s^\[colorize:red:255]
		]],
		sfinv_only and 2.6 or 2.54, PNG.search, PNG.search,
		sfinv_only and 3.3 or 3.25, PNG.clear, PNG.clear)

	fs[#fs + 1] = fmt([[
		image_button[%f,-0.05;0.8,0.8;%s;prev;;;false;%s^\[colorize:yellow:255]
		label[%f,%f;%u / %u]
		image_button[%f,-0.05;0.8,0.8;%s;next;;;false;%s^\[colorize:yellow:255]
		]],
		sfinv_only and 5.45 or 6.83, PNG.prev, PNG.prev,
		sfinv_only and 6.35 or 7.85, 0.06, data.pagenum, data.pagemax,
		sfinv_only and 7.2  or 8.75, PNG.next, PNG.next)

	if #data.items == 0 then
		local no_item = S("No item to show")
		local pos = sfinv_only and 3 or 3.8

		if next(recipe_filters) and #init_items > 0 and data.filter == "" then
			no_item = S("Collect items to reveal more recipes")
			pos = pos - 1
		end

		fs[#fs + 1] = fmt(FMT.label, pos, 2, ESC(no_item))
	end

	local first_item = (data.pagenum - 1) * IPP

	for i = first_item, first_item + IPP - 1 do
		local item = data.items[i + 1]
		if not item then break end

		local X = i % ROWS
		local Y = (i % IPP - X) / ROWS + 1

		fs[#fs + 1] = fmt("item_image_button[%f,%f;%f,%f;%s;%s_inv;]",
			X - (X * (sfinv_only and 0.12 or 0.14)) - 0.05,
			Y - (Y * 0.1) - 0.1,
			1, 1, item, item)
	end

	if data.recipes and #data.recipes > 0 then
		get_recipe_fs(data, fs)
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

craftguide.add_search_filter("groups", function(item, groups)
	local itemdef = reg_items[item]
	local has_groups = true

	for i = 1, #groups do
		local group = groups[i]
		if not itemdef.groups[group] then
			has_groups = nil
			break
		end
	end

	return has_groups
end)

local function search(data)
	local filter = data.filter

	if searches[filter] then
		data.items = searches[filter]
		return
	end

	local opt = "^(.-)%+([%w_]+)=([%w_,]+)"
	local search_filter = next(search_filters) and match(filter, opt)
	local filters = {}

	if search_filter then
		for filter_name, values in gmatch(filter, sub(opt, 6)) do
			if search_filters[filter_name] then
				values = split(values, ",")
				filters[filter_name] = values
			end
		end
	end

	local filtered_list, c = {}, 0

	for i = 1, #data.items_raw do
		local item = data.items_raw[i]
		local def  = reg_items[item]
		local desc = (def and def.description) and lower(def.description) or ""
		local search_in = fmt("%s %s", item, desc)
		local to_add

		if search_filter then
			for filter_name, values in pairs(filters) do
				local func = search_filters[filter_name]
				to_add = func(item, values) and (search_filter == "" or
					find(search_in, search_filter, 1, true))
			end
		else
			to_add = find(search_in, filter, 1, true)
		end

		if to_add then
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

local function init_data(name)
	pdata[name] = {
		filter    = "",
		pagenum   = 1,
		items     = init_items,
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

-- As `core.get_craft_recipe` and `core.get_all_craft_recipes` do not return the replacements,
-- we have to override `core.register_craft` and `core.register_alias` and do some reverse engineering.
-- See engine's issues #4901 and #8920.

fuel_cache.replacements = {}

local old_register_alias = core.register_alias
local current_alias = {}

core.register_alias = function(old, new)
	old_register_alias(old, new)
	current_alias = {old, new}
end

local old_register_craft = core.register_craft

core.register_craft = function(def)
	old_register_craft(def)

	if def.type == "toolrepair" then
		toolrepair = def.additional_wear * -100
	end

	local output = def.output or (is_str(def.recipe) and def.recipe or "")
	if output == "" then return end
	output = {clean_name(output)}

	local groups

	if is_group(output[1]) then
		groups = extract_groups(output[1])
		output = groups_to_items(groups, true)
	end

	for i = 1, #output do
		local name = output[i]
		if name == current_alias[1] then
			name = current_alias[2]
		end

		if def.type ~= "fuel" then
			def.items = {}
		end

		if def.type == "fuel" then
			fuel_cache[name] = def.burntime
			fuel_cache.replacements[name] = def.replacements

		elseif def.type == "cooking" then
			def.width = def.cooktime
			def.cooktime = nil
			def.items[1] = def.recipe

		elseif def.type == "shapeless" then
			def.width = 0
			for j = 1, #def.recipe do
				def.items[#def.items + 1] = def.recipe[j]
			end
		else
			def.width = #def.recipe[1]
			local c = 0

			for j = 1, #def.recipe do
				if def.recipe[j] then
					for h = 1, def.width do
						c = c + 1
						local it = def.recipe[j][h]

						if it and it ~= "" then
							def.items[c] = it
						end
					end
				end
			end
		end

		if def.type ~= "fuel" then
			def.recipe = nil
			recipes_cache[name] = recipes_cache[name] or {}
			insert(recipes_cache[name], 1, def)
		end
	end
end

local function show_item(def)
	return not (def.groups.not_in_craft_guide == 1 or
		def.groups.not_in_creative_inventory == 1) and
		def.description and def.description ~= ""
end

local function get_init_items()
	local c = 0
	for name, def in pairs(reg_items) do
		if show_item(def) then
			if not fuel_cache[name] then
				cache_fuel(name)
			end

			if not recipes_cache[name] then
				cache_recipes(name)
			end

			cache_usages(name)

			if recipes_cache[name] or usages_cache[name] then
				c = c + 1
				init_items[c] = name
			end
		end
	end

	sort(init_items)
end

on_mods_loaded(get_init_items)

on_joinplayer(function(player)
	local name = player:get_player_name()
	init_data(name)
end)

local function fields(player, _f)
	local name = player:get_player_name()
	local data = pdata[name]

	if _f.clear then
		reset_data(data)
		show_fs(player, name)
		return true

	elseif _f.alternate then
		if #data.recipes == 1 then return end
		local num_next = data.rnum + 1
		data.rnum = data.recipes[num_next] and num_next or 1

		show_fs(player, name)
		return true

	elseif (_f.key_enter_field == "filter" or _f.search) and _f.filter ~= "" then
		local str = lower(_f.filter)
		if data.filter == str then return end

		data.filter = str
		data.pagenum = 1
		search(data)

		show_fs(player, name)
		return true

	elseif _f.prev or _f.next then
		if data.pagemax == 1 then return end
		data.pagenum = data.pagenum - (_f.prev and 1 or -1)

		if data.pagenum > data.pagemax then
			data.pagenum = 1
		elseif data.pagenum == 0 then
			data.pagenum = data.pagemax
		end

		show_fs(player, name)
		return true
	else
		local item
		for field in pairs(_f) do
			if find(field, ":") then
				item = field
				break
			end
		end

		if not item then
			return
		elseif sub(item, -4) == "_inv" then
			item = sub(item, 1, -5)
		end

		if item ~= data.query_item then
			data.show_usages = nil
		else
			data.show_usages = not data.show_usages
		end

		local recipes = get_recipes(item, data, player)
		if not recipes then return end

		data.query_item = item
		data.recipes    = recipes
		data.rnum       = 1

		show_fs(player, name)
		return true
	end
end

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
				local data = pdata[name]

				data.items_raw = get_filtered_items(player)
				search(data)
			end
		end,

		on_player_receive_fields = function(self, player, context, _f)
			fields(player, _f)
		end,
	})
else
	on_receive_fields(function(player, formname, _f)
		if formname == "craftguide" then
			fields(player, _f)
		end
	end)

	local function on_use(user)
		local name = user:get_player_name()

		if next(recipe_filters) then
			local data = pdata[name]
			data.items_raw = get_filtered_items(user)
			search(data)
		end

		show_formspec(name, "craftguide", make_formspec(name))
	end

	core.register_craftitem("craftguide:book", {
		description = S("Crafting Guide"),
		inventory_image = PNG.book,
		wield_image = PNG.book,
		stack_max = 1,
		groups = {book = 1},
		on_use = function(itemstack, user)
			on_use(user)
		end
	})

	core.register_node("craftguide:sign", {
		description = S("Crafting Guide Sign"),
		drawtype = "nodebox",
		tiles = {PNG.sign},
		inventory_image = PNG.sign,
		wield_image = PNG.sign,
		paramtype = "light",
		paramtype2 = "wallmounted",
		sunlight_propagates = true,
		groups = {oddly_breakable_by_hand = 1, flammable = 3},
		node_box = {
			type = "wallmounted",
			wall_top    = {-0.5, 0.4375, -0.5, 0.5, 0.5, 0.5},
			wall_bottom = {-0.5, -0.5, -0.5, 0.5, -0.4375, 0.5},
			wall_side   = {-0.5, -0.5, -0.5, -0.4375, 0.5, 0.5}
		},

		on_construct = function(pos)
			local meta = core.get_meta(pos)
			meta:set_string("infotext", "Crafting Guide Sign")
		end,

		on_rightclick = function(pos, node, user, itemstack)
			on_use(user)
		end
	})

	core.register_craft({
		output = "craftguide:book",
		type   = "shapeless",
		recipe = {"default:book"}
	})

	core.register_craft({
		type = "fuel",
		recipe = "craftguide:book",
		burntime = 3
	})

	core.register_craft({
		output = "craftguide:sign",
		type   = "shapeless",
		recipe = {"default:sign_wall_wood"}
	})

	core.register_craft({
		type = "fuel",
		recipe = "craftguide:sign",
		burntime = 10
	})

	if rawget(_G, "sfinv_buttons") then
		sfinv_buttons.register_button("craftguide", {
			title = S("Crafting Guide"),
			tooltip = S("Shows a list of available crafting recipes, cooking recipes and fuels"),
			image = PNG.book,
			action = function(player)
				on_use(player)
			end,
		})
	end
end

if progressive_mode then
	local PLAYERS = {}
	local POLL_FREQ = 0.25
	local HUD_TIMER_MAX = 1.5

	local function table_diff(t1, t2)
		local hash = {}

		for i = 1, #t1 do
			local v = t1[i]
			hash[v] = true
		end

		for i = 1, #t2 do
			local v = t2[i]
			hash[v] = nil
		end

		local diff, c = {}, 0

		for i = 1, #t1 do
			local v = t1[i]
			if hash[v] then
				c = c + 1
				diff[c] = v
			end
		end

		return diff
	end

	local function item_in_inv(item, inv_items)
		local inv_items_size = #inv_items

		if is_group(item) then
			local groups = extract_groups(item)
			for i = 1, inv_items_size do
				local def = reg_items[inv_items[i]]

				if def then
					local item_groups = def.groups
					if item_has_groups(item_groups, groups) then
						return true
					end
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
			if not item_in_inv(item, inv_items) then return end
		end

		return true
	end

	local function progressive_filter(recipes, player)
		if not recipes then
			return {}
		end

		local name = player:get_player_name()
		local data = pdata[name]

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

	local item_lists = {
		"main",
		"craft",
		"craftpreview",
	}

	local function get_inv_items(player)
		local inv = player:get_inventory()
		local stacks = {}

		for i = 1, #item_lists do
			local list = inv:get_list(item_lists[i])
			table_merge(stacks, list)
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

	local function show_hud_success(player, data)
		-- It'd better to have an engine function `hud_move` to only need
		-- 2 calls for the notification's back and forth.

		local hud_info_bg = player:hud_get(data.hud.bg)
		local dt = 0.016

		if hud_info_bg.position.y <= 0.9 then
			data.show_hud = false
			data.hud_timer = (data.hud_timer or 0) + dt
		end

		if data.show_hud then
			for _, def in pairs(data.hud) do
				local hud_info = player:hud_get(def)

				player:hud_change(def, "position", {
					x = hud_info.position.x,
					y = hud_info.position.y - (dt / 5)
				})
			end

			player:hud_change(data.hud.text, "text",
				S("@1 new recipe(s) discovered!", data.discovered))

		elseif data.show_hud == false then
			if data.hud_timer >= HUD_TIMER_MAX then
				for _, def in pairs(data.hud) do
					local hud_info = player:hud_get(def)

					player:hud_change(def, "position", {
						x = hud_info.position.x,
						y = hud_info.position.y + (dt / 5)
					})
				end

				if hud_info_bg.position.y >= 1 then
					data.show_hud = nil
					data.hud_timer = nil
				end
			end
		end
	end

	-- Workaround. Need an engine call to detect when the contents of
	-- the player inventory changed, instead.
	local function poll_new_items()
		for i = 1, #PLAYERS do
			local player = PLAYERS[i]
			local name   = player:get_player_name()
			local data   = pdata[name]

			local inv_items = get_inv_items(player)
			local diff = table_diff(inv_items, data.inv_items)

			if #diff > 0 then
				data.inv_items = table_merge(diff, data.inv_items)

				local oldknown = data.known_recipes or 0
				local items = get_filtered_items(player, data)

				data.discovered = data.known_recipes - oldknown

				if data.show_hud == nil and data.discovered > 0 then
					data.show_hud = true
				end

				if sfinv_only then
					data.items_raw = items
					search(data)
					sfinv.set_player_inventory_formspec(player)
				end
			end
		end

		after(POLL_FREQ, poll_new_items)
	end

	poll_new_items()

	globalstep(function()
		for i = 1, #PLAYERS do
			local player = PLAYERS[i]
			local name   = player:get_player_name()
			local data   = pdata[name]

			if data.show_hud ~= nil then
				show_hud_success(player, data)
			end
		end
	end)

	craftguide.add_recipe_filter("Default progressive filter", progressive_filter)

	on_joinplayer(function(player)
		PLAYERS = get_players()

		local meta = player:get_meta()
		local name = player:get_player_name()
		local data = pdata[name]

		data.inv_items = deserialize(meta:get_string("inv_items")) or {}
		data.known_recipes = deserialize(meta:get_string("known_recipes")) or 0

		data.hud = {
			bg = player:hud_add({
				hud_elem_type = "image",
				position      = {x = 0.78, y = 1},
				alignment     = {x = 1,    y = 1},
				scale         = {x = 370,  y = 112},
				text          = PNG.bg,
			}),

			book = player:hud_add({
				hud_elem_type = "image",
				position      = {x = 0.79, y = 1.02},
				alignment     = {x = 1,    y = 1},
				scale         = {x = 4,    y = 4},
				text          = PNG.book,
			}),

			text = player:hud_add({
				hud_elem_type = "text",
				position      = {x = 0.84, y = 1.04},
				alignment     = {x = 1,    y = 1},
				number        = 0xFFFFFF,
				text          = "",
			}),
		}
	end)

	local to_save = {
		"inv_items",
		"known_recipes",
	}

	local function save_meta(player)
		local meta = player:get_meta()
		local name = player:get_player_name()
		local data = pdata[name]

		for i = 1, #to_save do
			local meta_name = to_save[i]
			meta:set_string(meta_name, serialize(data[meta_name]))
		end
	end

	on_leaveplayer(function(player)
		PLAYERS = get_players()
		save_meta(player)
	end)

	on_shutdown(function()
		for i = 1, #PLAYERS do
			local player = PLAYERS[i]
			save_meta(player)
		end
	end)
end

on_leaveplayer(function(player)
	local name = player:get_player_name()
	pdata[name] = nil
end)

register_command("craft", {
	description = S("Show recipe(s) of the pointed node"),
	func = function(name)
		local player = get_player_by_name(name)
		local dir    = player:get_look_dir()
		local ppos   = player:get_pos()
		      ppos.y = ppos.y + 1.625

		local node_name

		for i = 1, 10 do
			local look_at = vec_add(ppos, vec_mul(dir, i))
			local node = core.get_node(look_at)

			if node.name ~= "air" then
				node_name = node.name
				break
			end
		end

		local red = clr("red", "[craftguide] ")

		if not node_name then
			return false, red .. S("No node pointed")
		end

		local data = pdata[name]
		reset_data(data)

		local recipes = recipes_cache[node_name]
		local usages = usages_cache[node_name]

		if recipes then
			recipes = apply_recipe_filters(recipes, player)
		end

		if not recipes or #recipes == 0 then
			local ylw = clr("yellow", node_name)
			local msg = red .. "%s: " .. ylw

			if usages then
				recipes = usages_cache[node_name]
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
		data.recipes = recipes

		return true, show_fs(player, name)
	end,
})

function craftguide.show(name, item, show_usages)
	if not is_str(name) or name == "" then
		return log("error", "craftguide.show(): player name missing")
	end

	local data = pdata[name]
	local player = get_player_by_name(name)
	local query_item = data.query_item

	reset_data(data)

	item = reg_items[item] and item or query_item

	data.query_item  = item
	data.show_usages = show_usages
	data.recipes     = get_recipes(item, data, player)

	show_fs(player, name)
end
