craftguide = {}

-- Caches
local pdata         = {}
local init_items    = {}
local searches      = {}
local recipes_cache = {}
local usages_cache  = {}
local fuel_cache    = {}
local replacements  = {fuel = {}}
local toolrepair

local progressive_mode = core.settings:get_bool "craftguide_progressive_mode"

local http = core.request_http_api()
local singleplayer = core.is_singleplayer()

local reg_items = core.registered_items
local reg_nodes = core.registered_nodes
local reg_craftitems = core.registered_craftitems
local reg_tools = core.registered_tools
local reg_entities = core.registered_entities
local reg_aliases = core.registered_aliases

local log = core.log
local after = core.after
local clr = core.colorize
local parse_json = core.parse_json
local write_json = core.write_json
local chat_send = core.chat_send_player
local show_formspec = core.show_formspec
local globalstep = core.register_globalstep
local on_shutdown = core.register_on_shutdown
local get_players = core.get_connected_players
local get_craft_result = core.get_craft_result
local translate = minetest.get_translated_string
local on_joinplayer = core.register_on_joinplayer
local get_all_recipes = core.get_all_craft_recipes
local register_command = core.register_chatcommand
local get_player_by_name = core.get_player_by_name
local slz, dslz = core.serialize, core.deserialize
local on_mods_loaded = core.register_on_mods_loaded
local on_leaveplayer = core.register_on_leaveplayer
local get_player_info = core.get_player_information
local on_receive_fields = core.register_on_player_receive_fields

local ESC = core.formspec_escape
local S = core.get_translator "craftguide"

local ES = function(...)
	return ESC(S(...))
end

local maxn, sort, concat, copy, insert, remove =
	table.maxn, table.sort, table.concat, table.copy,
	table.insert, table.remove

local sprintf, find, gmatch, match, sub, split, upper, lower =
	string.format, string.find, string.gmatch, string.match,
	string.sub, string.split, string.upper, string.lower

local min, max, floor, ceil, abs = math.min, math.max, math.floor, math.ceil, math.abs
local pairs, ipairs, next, type, setmetatable, tonum =
	pairs, ipairs, next, type, setmetatable, tonumber

local vec_add, vec_mul = vector.add, vector.multiply

local ROWS = 9
local LINES = 10
local IPP = ROWS * LINES
local MAX_FAVS = 6
local ITEM_BTN_SIZE = 1.1

-- Progressive mode
local POLL_FREQ = 0.25
local HUD_TIMER_MAX = 1.5

local MIN_FORMSPEC_VERSION = 4

local PNG = {
	bg = "craftguide_bg.png",
	bg_full = "craftguide_bg_full.png",
	search = "craftguide_search.png",
	prev = "craftguide_next.png^\\[transformFX",
	next = "craftguide_next.png",
	arrow = "craftguide_arrow.png",
	trash = "craftguide_trash.png",
	sort_az = "craftguide_sort.png",
	sort_za = "craftguide_sort2.png",
	compress = "craftguide_compress.png",
	fire = "craftguide_fire.png",
	fire_anim = "craftguide_fire_anim.png",
	book = "craftguide_book.png",
	sign = "craftguide_sign.png",
	cancel = "craftguide_cancel.png",
	export = "craftguide_export.png",
	slot = "craftguide_slot.png",
	tab = "craftguide_tab.png",
	furnace_anim = "craftguide_furnace_anim.png",

	cancel_hover = "craftguide_cancel.png^\\[brighten",
	search_hover = "craftguide_search.png^\\[brighten",
	export_hover = "craftguide_export.png^\\[brighten",
	trash_hover = "craftguide_trash.png^\\[brighten",
	compress_hover = "craftguide_compress.png^\\[brighten",
	sort_az_hover = "craftguide_sort.png^\\[brighten",
	sort_za_hover = "craftguide_sort2.png^\\[brighten",
	prev_hover = "craftguide_next_hover.png^\\[transformFX",
	next_hover = "craftguide_next_hover.png",
	tab_hover = "craftguide_tab_hover.png",
}

local fs_elements = {
	box = "box[%f,%f;%f,%f;%s]",
	label = "label[%f,%f;%s]",
	image = "image[%f,%f;%f,%f;%s]",
	button = "button[%f,%f;%f,%f;%s;%s]",
	tooltip = "tooltip[%f,%f;%f,%f;%s]",
	item_image = "item_image[%f,%f;%f,%f;%s]",
	bg9 = "background9[%f,%f;%f,%f;%s;false;%u]",
	model = "model[%f,%f;%f,%f;%s;%s;%s;%s;%s;true;%s]",
	image_button = "image_button[%f,%f;%f,%f;%s;%s;%s]",
	animated_image = "animated_image[%f,%f;%f,%f;;%s;%u;%u]",
	scrollbar = "scrollbar[%f,%f;%f,%f;horizontal;%s;%u]",
	item_image_button = "item_image_button[%f,%f;%f,%f;%s;%s;%s]",
}

local styles = sprintf([[
	style_type[label,field;font_size=16]
	style_type[image_button;border=false;sound=craftguide_click]
	style_type[item_image_button;border=false;bgimg_hovered=%s;sound=craftguide_click]

	style[filter;border=false]
	style[cancel;fgimg=%s;fgimg_hovered=%s;content_offset=0]
	style[search;fgimg=%s;fgimg_hovered=%s;content_offset=0]
	style[trash;fgimg=%s;fgimg_hovered=%s;content_offset=0;sound=craftguide_delete]
	style[sort_az;fgimg=%s;fgimg_hovered=%s;content_offset=0]
	style[sort_za;fgimg=%s;fgimg_hovered=%s;content_offset=0]
	style[compress;fgimg=%s;fgimg_hovered=%s;content_offset=0]
	style[prev_page;fgimg=%s;fgimg_hovered=%s]
	style[next_page;fgimg=%s;fgimg_hovered=%s]
	style[prev_recipe;fgimg=%s;fgimg_hovered=%s]
	style[next_recipe;fgimg=%s;fgimg_hovered=%s]
	style[prev_usage;fgimg=%s;fgimg_hovered=%s]
	style[next_usage;fgimg=%s;fgimg_hovered=%s]
	style[guide_mode,inv_mode;fgimg_hovered=%s;noclip=true;content_offset=0;sound=craftguide_tab]
	style[pagenum,no_item,no_rcp;border=false;font=bold;font_size=18;content_offset=0]
	style[craft_rcp,craft_usg;border=false;noclip=true;font_size=16;sound=craftguide_craft;
	      bgimg=craftguide_btn9.png;bgimg_hovered=craftguide_btn9_hovered.png;
	      bgimg_pressed=craftguide_btn9_pressed.png;bgimg_middle=4,6]
]],
PNG.slot,
PNG.cancel, PNG.cancel_hover,
PNG.search, PNG.search_hover,
PNG.trash, PNG.trash_hover,
PNG.sort_az, PNG.sort_az_hover,
PNG.sort_za, PNG.sort_za_hover,
PNG.compress, PNG.compress_hover,
PNG.prev, PNG.prev_hover,
PNG.next, PNG.next_hover,
PNG.prev, PNG.prev_hover,
PNG.next, PNG.next_hover,
PNG.prev, PNG.prev_hover,
PNG.next, PNG.next_hover,
PNG.tab_hover)

local function get_lang_code(info)
	return info and info.lang_code
end

local function get_formspec_version(info)
	return info and info.formspec_version or 1
end

local function outdated(name)
	local fs = sprintf([[
		size[7.1,1.3]
		image[0,0;1,1;%s]
		label[1,0;%s]
		button_exit[3.1,0.8;1,1;;OK]
	]],
	PNG.book,
	"Your Minetest client is outdated.\n" ..
	"Get the latest version on minetest.net to use the Crafting Guide.")

	return show_formspec(name, "craftguide", fs)
end

craftguide.group_stereotypes = {
	dye = "dye:white",
	wool = "wool:white",
	wood = "default:wood",
	tree = "default:tree",
	sand = "default:sand",
	glass = "default:glass",
	stick = "default:stick",
	stone = "default:stone",
	leaves = "default:leaves",
	coal = "default:coal_lump",
	vessel = "vessels:glass_bottle",
	flower = "flowers:dandelion_yellow",
	water_bucket = "bucket:bucket_water",
	mesecon_conductor_craftable = "mesecons:wire_00000000_off",
}

local group_names = {
	dye = S"Any dye",
	coal = S"Any coal",
	sand = S"Any sand",
	tree = S"Any tree",
	wool = S"Any wool",
	glass = S"Any glass",
	stick = S"Any stick",
	stone = S"Any stone",
	carpet = S"Any carpet",
	flower = S"Any flower",
	leaves = S"Any leaves",
	vessel = S"Any vessel",
	wood = S"Any wood planks",
	mushroom = S"Any mushroom",

	["color_red,flower"] = S"Any red flower",
	["color_blue,flower"] = S"Any blue flower",
	["color_black,flower"] = S"Any black flower",
	["color_white,flower"] = S"Any white flower",
	["color_green,flower"] = S"Any green flower",
	["color_orange,flower"] = S"Any orange flower",
	["color_yellow,flower"] = S"Any yellow flower",
	["color_violet,flower"] = S"Any violet flower",

	["color_red,dye"] = S"Any red dye",
	["color_blue,dye"] = S"Any blue dye",
	["color_grey,dye"] = S"Any grey dye",
	["color_pink,dye"] = S"Any pink dye",
	["color_cyan,dye"] = S"Any cyan dye",
	["color_black,dye"] = S"Any black dye",
	["color_white,dye"] = S"Any white dye",
	["color_brown,dye"] = S"Any brown dye",
	["color_green,dye"] = S"Any green dye",
	["color_orange,dye"] = S"Any orange dye",
	["color_yellow,dye"] = S"Any yellow dye",
	["color_violet,dye"] = S"Any violet dye",
	["color_magenta,dye"] = S"Any magenta dye",
	["color_dark_grey,dye"] = S"Any dark grey dye",
	["color_dark_green,dye"] = S"Any dark green dye",
}

craftguide.model_alias = {
	["boats:boat"] = {name = "boats:boat", drawtype = "entity"},
	["carts:cart"] = {name = "carts:cart", drawtype = "entity", frames = "0,0"},
	["default:chest"] = {name = "default:chest_open"},
	["default:chest_locked"] = {name = "default:chest_locked_open"},
	["doors:door_wood"] = {name = "doors:door_wood_a"},
	["doors:door_glass"] = {name = "doors:door_glass_a"},
	["doors:door_obsidian_glass"] = {name = "doors:door_obsidian_glass_a"},
	["doors:door_steel"] = {name = "doors:door_steel_a"},
	["xpanes:door_steel_bar"] = {name = "xpanes:door_steel_bar_a"},
}

local function err(str)
	return log("error", str)
end

local function msg(name, str)
	return chat_send(name, sprintf("[craftguide] %s", str))
end

local function is_num(x)
	return type(x) == "number"
end

local function is_str(x)
	return type(x) == "string"
end

local function true_str(str)
	return is_str(str) and str ~= ""
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

local function fmt(elem, ...)
	return sprintf(fs_elements[elem], ...)
end

local function clean_name(item)
	if sub(item, 1, 1) == ":" then
		item = sub(item, 2)
	end

	return item
end

local function array_diff(t1, t2)
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

local function table_eq(T1, T2)
	local avoid_loops = {}

	local function recurse(t1, t2)
		if type(t1) ~= type(t2) then return end

		if not is_table(t1) then
			return t1 == t2
		end

		if avoid_loops[t1] then
			return avoid_loops[t1] == t2
		end

		avoid_loops[t1] = t2
		local t2k, t2kv = {}, {}

		for k in pairs(t2) do
			if is_table(k) then
				insert(t2kv, k)
			end

			t2k[k] = true
		end

		for k1, v1 in pairs(t1) do
			local v2 = t2[k1]
			if type(k1) == "table" then
				local ok
				for i = 1, #t2kv do
					local tk = t2kv[i]
					if table_eq(k1, tk) and recurse(v1, t2[tk]) then
						remove(t2kv, i)
						t2k[tk] = nil
						ok = true
						break
					end
				end

				if not ok then return end
			else
				if v2 == nil then return end
				t2k[k1] = nil
				if not recurse(v1, v2) then return end
			end
		end

		if next(t2k) then return end
		return true
	end

	return recurse(T1, T2)
end

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

local craft_types = {}

function craftguide.register_craft_type(name, def)
	if not true_str(name) then
		return err "craftguide.register_craft_type(): name missing"
	end

	if not is_str(def.description) then
		def.description = ""
	end

	if not is_str(def.icon) then
		def.icon = ""
	end

	craft_types[name] = def
end

function craftguide.register_craft(def)
	local width, c = 0, 0

	if true_str(def.url) then
		if not http then
			return err(sprintf([[craftguide.register_craft(): Unable to reach %s.
				No HTTP support for this mod: add it to the `secure.http_mods` or
				`secure.trusted_mods` setting.]], def.url))
		end

		http.fetch({url = def.url}, function(result)
			if result.succeeded then
				local t = parse_json(result.data)
				if is_table(t) then
					return craftguide.register_craft(t)
				end
			end
		end)

		return
	end

	if not is_table(def) or not next(def) then
		return err "craftguide.register_craft(): craft definition missing"
	end

	if #def > 1 then
		for _, v in pairs(def) do
			craftguide.register_craft(v)
		end
		return
	end

	if def.result then
		def.output = def.result -- Backward compatibility
		def.result = nil
	end

	if not true_str(def.output) then
		return err "craftguide.register_craft(): output missing"
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

		width = #cp[1]

		for i = 1, #def.grid do
			while #def.grid[i] < width do
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

			if rlen > width then
				width = rlen
			end
		end

		for i = 1, len do
			while #split(items[i], ",") < width do
				items[i] = items[i] .. ", "
			end
		end

		for name in gmatch(concat(items, ","), "[%s%w_:]+") do
			c = c + 1
			def.items[c] = match(name, "%S+")
		end
	end

	local item = match(def.output, "%S+")
	recipes_cache[item] = recipes_cache[item] or {}

	def.custom = true
	def.width = width

	insert(recipes_cache[item], def)
end

local recipe_filters = {}

function craftguide.add_recipe_filter(name, f)
	if not true_str(name) then
		return err "craftguide.add_recipe_filter(): name missing"
	elseif not is_func(f) then
		return err "craftguide.add_recipe_filter(): function missing"
	end

	recipe_filters[name] = f
end

function craftguide.set_recipe_filter(name, f)
	if not is_str(name) then
		return err "craftguide.set_recipe_filter(): name missing"
	elseif not is_func(f) then
		return err "craftguide.set_recipe_filter(): function missing"
	end

	recipe_filters = {[name] = f}
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
	if not true_str(name) then
		return err "craftguide.add_search_filter(): name missing"
	elseif not is_func(f) then
		return err "craftguide.add_search_filter(): function missing"
	end

	search_filters[name] = f
end

function craftguide.remove_search_filter(name)
	search_filters[name] = nil
end

function craftguide.get_search_filters()
	return search_filters
end

local function weird_desc(str)
	return not true_str(str) or find(str, "\n") or not find(str, "%u")
end

local function toupper(str)
	return str:gsub("%f[%w]%l", upper):gsub("_", " ")
end

local function snip(str, limit)
	return #str > limit and sprintf("%s...", sub(str, 1, limit - 3)) or str
end

local function get_desc(item)
	if sub(item, 1, 1) == "_" then
		item = sub(item, 2)
	end

	local def = reg_items[item]

	if def then
		local desc = ItemStack(item):get_short_description()

		if true_str(desc) then
			desc = desc:trim()

			if not find(desc, "%u") then
				desc = toupper(desc)
			end

			return desc

		elseif true_str(item) then
			return toupper(match(item, ":(.*)"))
		end
	end

	return S("Unknown Item (@1)", item)
end

local function item_has_groups(item_groups, groups)
	for i = 1, #groups do
		local group = groups[i]
		if (item_groups[group] or 0) == 0 then return end
	end

	return true
end

local function extract_groups(str)
	if sub(str, 1, 6) == "group:" then
		return split(sub(str, 7), ",")
	end
end

local function get_filtered_items(player, data)
	local items, known, c = {}, 0, 0

	for i = 1, #init_items do
		local item = init_items[i]
		local recipes = recipes_cache[item]
		local usages = usages_cache[item]

		recipes = #apply_recipe_filters(recipes or {}, player)
		usages = #apply_recipe_filters(usages or {}, player)

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

local function get_burntime(item)
	return get_craft_result{method = "fuel", items = {item}}.time
end

local function cache_fuel(item)
	local burntime = get_burntime(item)
	if burntime > 0 then
		fuel_cache[item] = {
			type = "fuel",
			items = {item},
			burntime = burntime,
			replacements = replacements.fuel[item],
		}
	end
end

local function show_item(def)
	return def and not (def.groups.not_in_craft_guide == 1 or
		def.groups.not_in_creative_inventory == 1) and
		def.description and def.description ~= ""
end

local function get_usages(recipe)
	local added = {}

	for _, item in pairs(recipe.items) do
		item = reg_aliases[item] or item
		if not added[item] then
			local groups = extract_groups(item)
			if groups then
				for name, def in pairs(reg_items) do
					if not added[name] and show_item(def) and
							item_has_groups(def.groups, groups) then
						local usage = copy(recipe)
						table_replace(usage.items, item, name)
						usages_cache[name] = usages_cache[name] or {}
						insert(usages_cache[name], 1, usage)
						added[name] = true
					end
				end
			elseif show_item(reg_items[item]) then
				usages_cache[item] = usages_cache[item] or {}
				insert(usages_cache[item], 1, recipe)
			end

			added[item] = true
		end
	end
end

local function cache_usages(item)
	local recipes = recipes_cache[item] or {}

	for i = 1, #recipes do
		get_usages(recipes[i])
	end

	if fuel_cache[item] then
		usages_cache[item] = table_merge(usages_cache[item] or {}, {fuel_cache[item]})
	end
end

local function drop_table(name, drop)
	local count_sure = 0
	local drop_items = drop.items or {}
	local max_items = drop.max_items

	for i = 1, #drop_items do
		local di = drop_items[i]
		local valid_rarity = di.rarity and di.rarity > 1

		if di.rarity or not max_items or
				(max_items and not di.rarity and count_sure < max_items) then
			for j = 1, #di.items do
				local dstack = ItemStack(di.items[j])
				local dname  = dstack:get_name()
				local dcount = dstack:get_count()
				local empty  = dstack:is_empty()

				if not empty and (dname ~= name or
						(dname == name and dcount > 1)) then
					local rarity = valid_rarity and di.rarity

					craftguide.register_craft{
						type   = rarity and "digging_chance" or "digging",
						items  = {name},
						output = sprintf("%s %u", dname, dcount),
						rarity = rarity,
						tools  = di.tools,
					}
				end
			end
		end

		if not di.rarity then
			count_sure = count_sure + 1
		end
	end
end

local function cache_drops(name, drop)
	if true_str(drop) then
		local dstack = ItemStack(drop)
		local dname  = dstack:get_name()
		local empty  = dstack:is_empty()

		if not empty and dname ~= name then
			craftguide.register_craft{
				type = "digging",
				items = {name},
				output = drop,
			}
		end
	elseif is_table(drop) then
		drop_table(name, drop)
	end
end

local function cache_recipes(item)
	local recipes = get_all_recipes(item)

	if replacements[item] then
		local _recipes = {}

		for k, v in ipairs(recipes or {}) do
			_recipes[#recipes + 1 - k] = v
		end

		local shift = 0
		local size_rpl = maxn(replacements[item])
		local size_rcp = #_recipes

		if size_rpl > size_rcp then
			shift = size_rcp - size_rpl
		end

		for k, v in pairs(replacements[item]) do
			k = k + shift

			if _recipes[k] then
				_recipes[k].replacements = v
			end
		end

		recipes = _recipes
	end

	if recipes then
		recipes_cache[item] = table_merge(recipes, recipes_cache[item] or {})
	end
end

local function get_recipes(player, item)
	local clean_item = reg_aliases[item] or item
	local recipes = recipes_cache[clean_item]
	local usages = usages_cache[clean_item]

	if recipes then
		recipes = apply_recipe_filters(recipes, player)
	end

	local no_recipes = not recipes or #recipes == 0
	if no_recipes and not usages then return end
	usages = apply_recipe_filters(usages, player)

	local no_usages = not usages or #usages == 0

	return not no_recipes and recipes or nil,
	       not no_usages  and usages  or nil
end

local function groups_to_items(groups, get_all)
	if not get_all and #groups == 1 then
		local group = groups[1]
		local stereotype = craftguide.group_stereotypes[group]
		local def = reg_items[stereotype]

		if def and show_item(def) then
			return stereotype
		end
	end

	local names = {}
	for name, def in pairs(reg_items) do
		if show_item(def) and item_has_groups(def.groups, groups) then
			if get_all then
				names[#names + 1] = name
			else
				return name
			end
		end
	end

	return get_all and names or ""
end

local function sort_itemlist(player, az)
	local inv = player:get_inventory()
	local list = inv:get_list("main")
	local size = inv:get_size("main")
	local new_inv, stack_meta = {}, {}

	for i = 1, size do
		local stack = list[i]
		local name = stack:get_name()
		local count = stack:get_count()
		local empty = stack:is_empty()
		local meta = stack:get_meta():to_table()

		if not empty then
			if next(meta.fields) then
				stack_meta[#stack_meta + 1] = stack
			else
				new_inv[#new_inv + 1] = sprintf("%s %u", name, count)
			end
		end
	end

	if az then
		sort(new_inv)
	else
		sort(new_inv, function(a, b) return a > b end)
	end

	inv:set_list("main", new_inv)

	for i = 1, #stack_meta do
		inv:set_stack("main", #new_inv + i, stack_meta[i])
	end
end

local function compress_items(player)
	local inv = player:get_inventory()
	local list = inv:get_list("main")
	local size = inv:get_size("main")
	local new_inv, _new_inv, stack_meta = {}, {}, {}

	for i = 1, size do
		local stack = list[i]
		local name = stack:get_name()
		local count = stack:get_count()
		local empty = stack:is_empty()
		local meta = stack:get_meta():to_table()

		if not empty then
			if next(meta.fields) then
				stack_meta[#stack_meta + 1] = stack
			else
				new_inv[name] = new_inv[name] or 0
				new_inv[name] = new_inv[name] + count
			end
		end
	end

	for name, count in pairs(new_inv) do
		local stackmax = ItemStack(name):get_stack_max()
		local iter = ceil(count / stackmax)
		local leftover = count

		for _ = 1, iter do
			_new_inv[#_new_inv + 1] = sprintf("%s %u", name, min(stackmax, leftover))
			leftover = leftover - stackmax
		end
	end

	sort(_new_inv)
	inv:set_list("main", _new_inv)

	for i = 1, #stack_meta do
		inv:set_stack("main", #_new_inv + i, stack_meta[i])
	end
end

local function get_stack_max(inv, data, is_recipe, rcp)
	local list = inv:get_list("main")
	local size = inv:get_size("main")
	local counts_inv, counts_rcp, counts = {}, {}, {}
	local rcp_usg = is_recipe and "recipe" or "usage"

	for _, it in pairs(rcp.items) do
		counts_rcp[it] = (counts_rcp[it] or 0) + 1
	end

	data.export_counts[rcp_usg] = {}
	data.export_counts[rcp_usg].rcp = counts_rcp

	for i = 1, size do
		local stack = list[i]

		if not stack:is_empty() then
			local item = stack:get_name()
			local count = stack:get_count()

			for name in pairs(counts_rcp) do
				if is_group(name) then
					local def = reg_items[item]

					if def then
						local groups = extract_groups(name)

						if item_has_groups(def.groups, groups) then
							counts_inv[name] = (counts_inv[name] or 0) + count
						end
					end
				end
			end

			counts_inv[item] = (counts_inv[item] or 0) + count
		end
	end

	data.export_counts[rcp_usg].inv = counts_inv

	for name in pairs(counts_rcp) do
		counts[name] = floor((counts_inv[name] or 0) / (counts_rcp[name] or 0))
	end

	local max_stacks = math.huge

	for _, count in pairs(counts) do
		if count < max_stacks then
			max_stacks = count
		end
	end

	return max_stacks
end

local function get_stack(player, pname, stack, message)
	local inv = player:get_inventory()

	if inv:room_for_item("main", stack) then
		inv:add_item("main", stack)
		msg(pname, sprintf("%s added in your inventory", message))
	else
		local dir     = player:get_look_dir()
		local ppos    = player:get_pos()
		      ppos.y  = ppos.y + 1.625
		local look_at = vec_add(ppos, vec_mul(dir, 1))

		core.add_item(look_at, stack)
		msg(pname, sprintf("%s spawned", message))
	end
end

local function craft_stack(player, pname, data, craft_rcp)
	local inv = player:get_inventory()
	local rcp_usg = craft_rcp and "recipe" or "usage"
	local output = craft_rcp and data.recipes[data.rnum].output or data.usages[data.unum].output
	output = ItemStack(output)
	local stackname, stackcount, stackmax = output:get_name(), output:get_count(), output:get_stack_max()
	local scrbar_val = data[sprintf("scrbar_%s", craft_rcp and "rcp" or "usg")] or 1

	for name, count in pairs(data.export_counts[rcp_usg].rcp) do
		local items = {[name] = count}

		if is_group(name) then
			items = {}
			local groups = extract_groups(name)
			local item_groups = groups_to_items(groups, true)
			local remaining = count

			for _, item in ipairs(item_groups) do
			for _name, _count in pairs(data.export_counts[rcp_usg].inv) do
				if item == _name and remaining > 0 then
					local c = min(remaining, _count)
					items[item] = c
					remaining = remaining - c
				end

				if remaining == 0 then break end
			end
			end
		end

		for k, v in pairs(items) do
			inv:remove_item("main", sprintf("%s %s", k, v * scrbar_val))
		end
	end

	local count = stackcount * scrbar_val
	local desc = get_desc(stackname)
	local iter = ceil(count / stackmax)
	local leftover = count

	for _ = 1, iter do
		local c = min(stackmax, leftover)
		local message

		if c > 1 then
			message = clr("#ff0", sprintf("%s x %s", c, desc))
		else
			message = clr("#ff0", sprintf("%s", desc))
		end

		local stack = ItemStack(sprintf("%s %s", stackname, c))
		get_stack(player, pname, stack, message)
		leftover = leftover - stackmax
	end
end

local function select_item(player, data, _f)
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
	elseif sub(item, 1, 1) == "_" then
		item = sub(item, 2)
	elseif sub(item, 1, 6) == "group|" then
		item = match(item, "([%w:_]+)$")
	end

	item = reg_aliases[item] or item

	if item == data.query_item then return end

	local recipes, usages = get_recipes(player, item)
	if not recipes and not usages then return end

	data.query_item = item
	data.recipes    = recipes
	data.usages     = usages
	data.rnum       = 1
	data.unum       = 1
	data.scrbar_rcp = 1
	data.scrbar_usg = 1
	data.export_rcp = nil
	data.export_usg = nil
end

local function repairable(tool)
	local def = reg_tools[tool]
	return toolrepair and def and def.groups and def.groups.disable_repair ~= 1
end

local function is_fav(favs, query_item)
	local fav, i
	for j = 1, #favs do
		if favs[j] == query_item then
			fav = true
			i = j
			break
		end
	end

	return fav, i
end

local function get_tooltip(item, info)
	local tooltip

	if info.groups then
		sort(info.groups)
		tooltip = group_names[concat(info.groups, ",")]

		if not tooltip then
			local groupstr = {}

			for i = 1, #info.groups do
				insert(groupstr, clr("#ff0", info.groups[i]))
			end

			groupstr = concat(groupstr, ", ")
			tooltip = S("Any item belonging to the group(s): @1", groupstr)
		end
	else
		tooltip = get_desc(item)
	end

	local function add(str)
		return sprintf("%s\n%s", tooltip, str)
	end

	if info.cooktime then
		tooltip = add(S("Cooking time: @1", clr("#ff0", info.cooktime)))
	end

	if info.burntime then
		tooltip = add(S("Burning time: @1", clr("#ff0", info.burntime)))
	end

	if info.replace then
		for i = 1, #info.replace.items do
			local rpl = match(info.replace.items[i], "%S+")
			local desc = clr("#ff0", get_desc(rpl))

			if info.replace.type == "cooking" then
				tooltip = add(S("Replaced by @1 on smelting", desc))
			elseif info.replace.type == "fuel" then
				tooltip = add(S("Replaced by @1 on burning", desc))
			else
				tooltip = add(S("Replaced by @1 on crafting", desc))
			end
		end
	end

	if info.repair then
		tooltip = add(S("Repairable by step of @1", clr("#ff0", toolrepair .. "%")))
	end

	if info.rarity then
		local chance = (1 / max(1, info.rarity)) * 100
		tooltip = add(S("@1 of chance to drop", clr("#ff0", chance .. "%")))
	end

	if info.tools then
		local several = #info.tools > 1
		local names = several and "\n" or ""

		if several then
			for i = 1, #info.tools do
				names = sprintf("%s\t\t- %s\n",
					names, clr("#ff0", get_desc(info.tools[i])))
			end

			tooltip = add(S("Only drop if using one of these tools: @1",
				sub(names, 1, -2)))
		else
			tooltip = add(S("Only drop if using this tool: @1",
				clr("#ff0", get_desc(info.tools[1]))))
		end
	end

	return sprintf("tooltip[%s;%s]", item, ESC(tooltip))
end

local function get_output_fs(fs, data, rcp, is_recipe, shapeless, right, btn_size, _btn_size)
	local custom_recipe = craft_types[rcp.type]

	if custom_recipe or shapeless or rcp.type == "cooking" then
		local icon = custom_recipe and custom_recipe.icon or
			     shapeless and "shapeless" or "furnace"

		if not custom_recipe then
			icon = sprintf("craftguide_%s.png^[resize:16x16", icon)
		end

		local pos_x = right + btn_size + 0.42
		local pos_y = data.yoffset + 0.9

		if sub(icon, 1, 18) == "craftguide_furnace" then
			fs(fmt("animated_image", pos_x, pos_y, 0.5, 0.5, PNG.furnace_anim, 8, 180))
		else
			fs(fmt("image", pos_x, pos_y, 0.5, 0.5, icon))
		end

		local tooltip = custom_recipe and custom_recipe.description or
				shapeless and S"Shapeless" or S"Cooking"

		fs(fmt("tooltip", pos_x, pos_y, 0.5, 0.5, ESC(tooltip)))
	end

	local arrow_X = right + 0.2 + (_btn_size or ITEM_BTN_SIZE)
	local X = arrow_X + 1.2
	local Y = data.yoffset + 1.4

	fs(fmt("image", arrow_X, Y + 0.06, 1, 1, PNG.arrow))

	if rcp.type == "fuel" then
		fs(fmt("animated_image", X + 0.05, Y, ITEM_BTN_SIZE, ITEM_BTN_SIZE, PNG.fire_anim, 8, 180))
	else
		local item = rcp.output
		item = ItemStack(clean_name(item))
		local name = item:get_name()
		local count = item:get_count()
		local bt_s = ITEM_BTN_SIZE * 1.2

		fs(fmt("image", X, Y - 0.11, bt_s, bt_s, PNG.slot))

		local _name = sprintf("_%s", name)

		fs(fmt("item_image_button",
			X + 0.11, Y, ITEM_BTN_SIZE, ITEM_BTN_SIZE,
			sprintf("%s %u", name, count * (is_recipe and data.scrbar_rcp or data.scrbar_usg or 1)),
			_name, ""))

		local def = reg_items[name]
		local unknown = not def or nil
		local desc = def and def.description
		local weird = name ~= "" and desc and weird_desc(desc) or nil
		local burntime = fuel_cache[name] and fuel_cache[name].burntime

		local infos = {
			unknown  = unknown,
			weird    = weird,
			burntime = burntime,
			repair   = repairable(name),
			rarity   = rcp.rarity,
			tools    = rcp.tools,
		}

		if next(infos) then
			fs(get_tooltip(_name, infos))
		end
	end
end

local function get_grid_fs(fs, data, rcp, is_recipe)
	local width = rcp.width or 1
	local right, btn_size, _btn_size = 0, ITEM_BTN_SIZE
	local cooktime, shapeless

	if rcp.type == "cooking" then
		cooktime, width = width, 1
	elseif width == 0 and not rcp.custom then
		shapeless = true
		local n = #rcp.items
		width = (n < 5 and n > 1) and 2 or min(3, max(1, n))
	end

	local rows = ceil(maxn(rcp.items) / width)
	local large_recipe = width > 3 or rows > 3

	if large_recipe then
		fs("style_type[item_image_button;border=true]")
	end

	for i = 1, width * rows do
		local item = rcp.items[i] or ""
		item = clean_name(item)
		local name = match(item, "%S*")

		local X = ceil((i - 1) % width - width)
		X = X + (X * 0.2) + data.xoffset + 3.9

		local Y = ceil(i / width) - min(2, rows)
		Y = Y + (Y * 0.15)  + data.yoffset + 1.4

		if large_recipe then
			btn_size = (3 / width) * (3 / rows) + 0.3
			_btn_size = btn_size

			local xi = (i - 1) % width
			local yi = floor((i - 1) / width)

			X = btn_size * xi + data.xoffset + 0.3 + (xi * 0.05)
			Y = btn_size * yi + data.yoffset + 0.2 + (yi * 0.05)
		end

		if X > right then
			right = X
		end

		local groups

		if is_group(name) then
			groups = extract_groups(name)
			item = groups_to_items(groups)
		end

		local label = groups and "\nG" or ""
		local replace

		for j = 1, #(rcp.replacements or {}) do
			local replacement = rcp.replacements[j]
			if replacement[1] == name then
				replace = replace or {type = rcp.type, items = {}}

				local added

				for _, v in ipairs(replace.items) do
					if replacement[2] == v then
						added = true
						break
					end
				end

				if not added then
					label = sprintf("%s%s\nR", label ~= "" and "\n" or "", label)
					replace.items[#replace.items + 1] = replacement[2]
				end
			end
		end

		if not large_recipe then
			fs(fmt("image", X, Y, btn_size, btn_size, PNG.slot))
		end

		local btn_name = groups and sprintf("group|%s|%s", groups[1], item) or item

		fs(fmt("item_image_button", X, Y, btn_size, btn_size,
			sprintf("%s %u", item, is_recipe and data.scrbar_rcp or data.scrbar_usg or 1),
			btn_name, label))

		local def = reg_items[name]
		local unknown = not def or nil
		unknown = not groups and unknown or nil
		local desc = def and def.description
		local weird = name ~= "" and desc and weird_desc(desc) or nil
		local burntime = fuel_cache[name] and fuel_cache[name].burntime

		local infos = {
			unknown  = unknown,
			weird    = weird,
			groups   = groups,
			burntime = burntime,
			cooktime = cooktime,
			replace  = replace,
		}

		if next(infos) then
			fs(get_tooltip(btn_name, infos))
		end
	end

	if large_recipe then
		fs("style_type[item_image_button;border=false]")
	end

	get_output_fs(fs, data, rcp, is_recipe, shapeless, right, btn_size, _btn_size)
end

local function get_rcp_lbl(fs, data, panel, rn, is_recipe)
	local lbl = ES("Usage @1 of @2", data.unum, rn)

	if is_recipe then
		lbl = ES("Recipe @1 of @2", data.rnum, rn)
	end

	local _lbl = translate(data.lang_code, lbl)
	local lbl_len = #_lbl:gsub("[\128-\191]", "") -- Count chars, not bytes in UTF-8 strings
	local shift = min(0.9, abs(12 - max(12, lbl_len)) * 0.15)

	fs(fmt("label", data.xoffset + 5.65 - shift, data.yoffset + 3.37, lbl))

	if rn > 1 then
		local btn_suffix = is_recipe and "recipe" or "usage"
		local prev_name = sprintf("prev_%s", btn_suffix)
		local next_name = sprintf("next_%s", btn_suffix)
		local x_arrow = data.xoffset + 5.09
		local y_arrow = data.yoffset + 3.2

		fs(fmt("image_button", x_arrow - shift, y_arrow, 0.3, 0.3, "", prev_name, ""),
		   fmt("image_button", x_arrow + 2.3,   y_arrow, 0.3, 0.3, "", next_name, ""))
	end

	local rcp = is_recipe and panel.rcp[data.rnum] or panel.rcp[data.unum]
	get_grid_fs(fs, data, rcp, is_recipe)
end

local function get_model_fs(fs, data, def, model_alias)
	if model_alias then
		if model_alias.drawtype == "entity" then
			def = reg_entities[model_alias.name]
			local init_props = def.initial_properties
			def.textures = init_props and init_props.textures or def.textures
			def.mesh = init_props and init_props.mesh or def.mesh
		else
			def = reg_items[model_alias.name]
		end
	end

	local tiles = def.tiles or def.textures or {}
	local t = {}

	for _, v in ipairs(tiles) do
		local _name

		if v.color then
			if is_num(v.color) then
				local hex = sprintf("%02x", v.color)

				while #hex < 8 do
					hex = "0" .. hex
				end

				_name = sprintf("%s^[multiply:%s", v.name,
					sprintf("#%s%s", sub(hex, 3), sub(hex, 1, 2)))
			else
				_name = sprintf("%s^[multiply:%s", v.name, v.color)
			end
		elseif v.animation then
			_name = sprintf("%s^[verticalframe:%u:0", v.name, v.animation.aspect_h)
		end

		t[#t + 1] = _name or v.name or v
	end

	while #t < 6 do
		t[#t + 1] = t[#t]
	end

	fs(fmt("model",
		data.xoffset + 6.6, data.yoffset + 0.05, 1.3, 1.3, "",
		def.mesh, concat(t, ","), "0,0", "true", model_alias and model_alias.frames or ""))
end

local function get_header(fs, data)
	local fav = is_fav(data.favs, data.query_item)
	local nfavs = #data.favs
	local star_x, star_y, star_size = data.xoffset + 0.4, data.yoffset + 0.5, 0.4

	if nfavs < MAX_FAVS or (nfavs == MAX_FAVS and fav) then
		local fav_marked = sprintf("craftguide_fav%s.png", fav and "_off" or "")

		fs(sprintf("style[fav;fgimg=%s;fgimg_hovered=%s;fgimg_pressed=%s]",
			sprintf("craftguide_fav%s.png", fav and "" or "_off"), fav_marked, fav_marked),
		   fmt("image_button", star_x, star_y, star_size, star_size, "", "fav", ""),
		   sprintf("tooltip[fav;%s]", fav and ES"Unmark this item" or ES"Mark this item"))
	else
		fs(sprintf("style[nofav;fgimg=%s;fgimg_hovered=%s;fgimg_pressed=%s]",
			"craftguide_fav_off.png", PNG.cancel, PNG.cancel),
		   fmt("image_button", star_x, star_y, star_size, star_size, "", "nofav", ""),
		   sprintf("tooltip[nofav;%s]", ES"Cannot mark this item. Bookmark limit reached."))
	end

	local desc_lim, name_lim = 32, 34
	local desc = ESC(get_desc(data.query_item))
	local tech_name = data.query_item
	local X = data.xoffset + 1.05
	local Y1 = data.yoffset + 0.47
	local Y2 = Y1 + 0.5

	if #desc > desc_lim then
		fs(fmt("tooltip", X, Y1 - 0.1, 5.7, 0.24, desc))
		desc = snip(desc, desc_lim)
	end

	if #tech_name > name_lim then
		fs(fmt("tooltip", X, Y2 - 0.1, 5.7, 0.24, tech_name))
		tech_name = snip(tech_name, name_lim)
	end

	fs("style_type[label;font=bold;font_size=22]",
	   fmt("label", X, Y1, desc), "style_type[label;font=mono;font_size=16]",
	   fmt("label", X, Y2, clr("#7bf", tech_name)), "style_type[label;font=normal;font_size=16]")

	local def = reg_items[data.query_item]
	local model_alias = craftguide.model_alias[data.query_item]

	if def.drawtype == "mesh" or model_alias then
		get_model_fs(fs, data, def, model_alias)
	else
		fs(fmt("item_image", data.xoffset + 6.8, data.yoffset + 0.17, 1.1, 1.1, data.query_item))
	end
end

local function get_export_fs(fs, data, is_recipe, is_usage, max_stacks_rcp, max_stacks_usg)
	local name = is_recipe and "rcp" or "usg"
	local show_export = (is_recipe and data.export_rcp) or (is_usage and data.export_usg)

	fs(sprintf("style[export_%s;fgimg=%s;fgimg_hovered=%s]",
		name, sprintf("%s", show_export and PNG.export_hover or PNG.export), PNG.export_hover),
	   fmt("image_button",
		data.xoffset + 7.35, data.yoffset + 0.2, 0.45, 0.45, "", sprintf("export_%s", name), ""),
	   sprintf("tooltip[export_%s;%s]", name, ES"Quick crafting"))

	if not show_export then return end

	local craft_max = is_recipe and max_stacks_rcp or max_stacks_usg
	local stack_fs = (is_recipe and data.scrbar_rcp) or (is_usage and data.scrbar_usg) or 1

	if stack_fs > craft_max then
		stack_fs = craft_max

		if is_recipe then
			data.scrbar_rcp = craft_max
		elseif is_usage then
			data.scrbar_usg = craft_max
		end
	end

	fs(sprintf("style[scrbar_%s;noclip=true]", name),
	   sprintf("scrollbaroptions[min=1;max=%u;smallstep=1]", craft_max),
	   fmt("scrollbar",
		data.xoffset + 8.1, data.yoffset, 3, 0.35, sprintf("scrbar_%s", name), stack_fs),
	   fmt("button", data.xoffset + 8.1, data.yoffset + 0.4, 3, 0.7, sprintf("craft_%s", name),
		ES("Craft (x@1)", stack_fs)))
end

local function get_rcp_extra(player, fs, data, panel, is_recipe, is_usage)
	local rn = panel.rcp and #panel.rcp

	if rn then
		local rcp_normal = is_recipe and panel.rcp[data.rnum].type == "normal"
		local usg_normal = is_usage and panel.rcp[data.unum].type == "normal"
		local max_stacks_rcp, max_stacks_usg = 0, 0
		local inv = player:get_inventory()

		if rcp_normal then
			max_stacks_rcp = get_stack_max(inv, data, is_recipe, panel.rcp[data.rnum])
		end

		if usg_normal then
			max_stacks_usg = get_stack_max(inv, data, is_recipe, panel.rcp[data.unum])
		end

		if is_recipe and max_stacks_rcp == 0 then
			data.export_rcp = nil
			data.scrbar_rcp = 1
		elseif is_usage and max_stacks_usg == 0 then
			data.export_usg = nil
			data.scrbar_usg = 1
		end

		if max_stacks_rcp > 0 or max_stacks_usg > 0 then
			get_export_fs(fs, data, is_recipe, is_usage, max_stacks_rcp, max_stacks_usg)
		end

		get_rcp_lbl(fs, data, panel, rn, is_recipe)
	else
		local lbl = is_recipe and ES"No recipes" or ES"No usages"
		fs(fmt("button",
			data.xoffset + 0.1, data.yoffset + (panel.height / 2) - 0.5,
			7.8, 1, "no_rcp", lbl))
	end
end

local function get_favs(fs, data)
	fs(fmt("label", data.xoffset + 0.4, data.yoffset + 0.4, ES"Bookmarks"))

	for i = 1, #data.favs do
		local item = data.favs[i]
		local X = data.xoffset - 0.7 + (i * 1.2)
		local Y = data.yoffset + 0.8

		if data.query_item == item then
			fs(fmt("image", X, Y, ITEM_BTN_SIZE, ITEM_BTN_SIZE, PNG.slot))
		end

		fs(fmt("item_image_button", X, Y, ITEM_BTN_SIZE, ITEM_BTN_SIZE, item, item, ""))
	end
end

local function get_panels(player, fs, data)
	local _title   = {name = "title", height = 1.4}
	local _favs    = {name = "favs",  height = 2.23}
	local _recipes = {name = "recipes", rcp = data.recipes, height = 3.9}
	local _usages  = {name = "usages",  rcp = data.usages,  height = 3.9}
	local panels   = {_title, _recipes, _usages, _favs}

	for idx = 1, #panels do
		local panel = panels[idx]
		data.yoffset = 0

		if idx > 1 then
			for _idx = idx - 1, 1, -1 do
				data.yoffset = data.yoffset + panels[_idx].height + 0.1
			end
		end

		fs(fmt("bg9", data.xoffset + 0.1, data.yoffset, 7.9, panel.height, PNG.bg_full, 10))

		local is_recipe, is_usage = panel.name == "recipes", panel.name == "usages"

		if is_recipe or is_usage then
			get_rcp_extra(player, fs, data, panel, is_recipe, is_usage)
		elseif panel.name == "title" then
			get_header(fs, data)
		elseif panel.name == "favs" then
			get_favs(fs, data)
		end
	end
end

local function get_item_list(fs, data, full_height)
	fs(fmt("bg9", 0, 0, data.xoffset, full_height, PNG.bg_full, 10))

	local filtered = data.filter ~= ""

	fs("box[0.2,0.2;4.55,0.6;#bababa25]", "set_focus[filter]")
	fs(sprintf("field[0.3,0.2;%f,0.6;filter;;%s]", filtered and 3.45 or 3.9, ESC(data.filter)))
	fs("field_close_on_enter[filter;false]")

	if filtered then
		fs(fmt("image_button", 3.75, 0.35, 0.3, 0.3, "", "cancel", ""))
	end

	fs(fmt("image_button", 4.25, 0.32, 0.35, 0.35, "", "search", ""))

	fs(fmt("image_button", data.xoffset - 2.73, 0.3, 0.35, 0.35, "", "prev_page", ""),
	   fmt("image_button", data.xoffset - 0.55, 0.3, 0.35, 0.35, "", "next_page", ""))

	data.pagemax = max(1, ceil(#data.items / IPP))

	fs(fmt("button",
		data.xoffset - 2.4, 0.14, 1.88, 0.7, "pagenum",
		sprintf("%s / %u", clr("#ff0", data.pagenum), data.pagemax)))

	if #data.items == 0 then
		local lbl = ES"No item to show"

		if next(recipe_filters) and #init_items > 0 and data.filter == "" then
			lbl = ES"Collect items to reveal more recipes"
		end

		fs(fmt("button", 0, 3, data.xoffset, 1, "no_item", lbl))
	end

	local first_item = (data.pagenum - 1) * IPP

	for i = first_item, first_item + IPP - 1 do
		local item = data.items[i + 1]
		if not item then break end

		local X = i % ROWS
		X = X + (X * 0.1) + 0.2

		local Y = floor((i % IPP - X) / ROWS + 1)
		Y = Y + (Y * 0.06) + 1

		if data.query_item == item then
			fs(fmt("image", X, Y, 1, 1, PNG.slot))
		end

		fs[#fs + 1] = fmt("item_image_button", X, Y, 1, 1, item, sprintf("%s_inv", item), "")
	end
end

local function make_fs(player, data)
	local fs = setmetatable({}, {
		__call = function(t, ...)
			t[#t + 1] = concat({...})
		end
	})

	data.xoffset = ROWS + 1.2
	local full_height = LINES + 1.73

	fs(sprintf("formspec_version[%u]size[%f,%f]no_prepend[]bgcolor[#0000]",
		MIN_FORMSPEC_VERSION, data.xoffset + (data.query_item and 8 or 0), full_height), styles)

	get_item_list(fs, data, full_height)

	if data.query_item then
		get_panels(player, fs, data)
	end

	return concat(fs)
end

local function show_fs(player, name)
	local data = pdata[name]
	local fs = make_fs(player, data)

	show_formspec(name, "craftguide", fs)
end

craftguide.register_craft_type("digging", {
	description = ES"Digging",
	icon = "craftguide_steelpick.png",
})

craftguide.register_craft_type("digging_chance", {
	description = ES"Digging (by chance)",
	icon = "craftguide_mesepick.png",
})

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
		local def = reg_items[item]
		local desc = lower(translate(data.lang_code, def and def.description)) or ""
		local search_in = sprintf("%s %s", item, desc)
		local temp, j, to_add = {}, 1

		if search_filter then
			for filter_name, values in pairs(filters) do
				if values then
					local func = search_filters[filter_name]
					to_add = (j > 1 and temp[item] or j == 1) and
						func(item, values) and (search_filter == "" or
						find(search_in, search_filter, 1, true))

					if to_add then
						temp[item] = true
					end

					j = j + 1
				end
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

craftguide.add_search_filter("groups", function(item, groups)
	local def = reg_items[item]
	local has_groups = true

	for i = 1, #groups do
		local group = groups[i]
		if not def.groups[group] then
			has_groups = nil
			break
		end
	end

	return has_groups
end)

craftguide.add_search_filter("type", function(item, drawtype)
	if drawtype == "node" then
		return reg_nodes[item]
	elseif drawtype == "item" then
		return reg_craftitems[item]
	elseif drawtype == "tool" then
		return reg_tools[item]
	end
end)

--[[	As `core.get_craft_recipe` and `core.get_all_craft_recipes` do not
	return the fuel, replacements and toolrepair recipes, we have to
	override `core.register_craft` and do some reverse engineering.
	See engine's issues #4901, #5745 and #8920.	]]

local old_register_craft = core.register_craft
local rcp_num = {}

core.register_craft = function(def)
	old_register_craft(def)

	if def.type == "toolrepair" then
		toolrepair = def.additional_wear * -100
	end

	local output = def.output or (true_str(def.recipe) and def.recipe) or nil
	if not output then return end
	output = {match(output, "%S+")}

	local groups

	if is_group(output[1]) then
		groups = extract_groups(output[1])
		output = groups_to_items(groups, true)
	end

	for i = 1, #output do
		local item = output[i]
		rcp_num[item] = (rcp_num[item] or 0) + 1

		if def.replacements then
			if def.type == "fuel" then
				replacements.fuel[item] = def.replacements
			else
				replacements[item] = replacements[item] or {}
				replacements[item][rcp_num[item]] = def.replacements
			end
		end
	end
end

local old_clear_craft = core.clear_craft

core.clear_craft = function(def)
	old_clear_craft(def)

	if true_str(def) then
		return -- TODO
	elseif is_table(def) then
		return -- TODO
	end
end

local function resolve_aliases(hash)
	for oldname, newname in pairs(reg_aliases) do
		cache_recipes(oldname)
		local recipes = recipes_cache[oldname]

		if recipes then
			if not recipes_cache[newname] then
				recipes_cache[newname] = {}
			end

			local similar

			for i = 1, #recipes_cache[oldname] do
				local rcp_old = recipes_cache[oldname][i]

				for j = 1, #recipes_cache[newname] do
					local rcp_new = copy(recipes_cache[newname][j])
					rcp_new.output = oldname

					if table_eq(rcp_old, rcp_new) then
						similar = true
						break
					end
				end

				if not similar then
					insert(recipes_cache[newname], rcp_old)
				end
			end
		end

		if newname ~= "" and recipes_cache[oldname] and not hash[newname] then
			init_items[#init_items + 1] = newname
		end
	end
end

local function get_init_items()
	local _select, _preselect = {}, {}

	for name, def in pairs(reg_items) do
		if name ~= "" and show_item(def) then
			cache_drops(name, def.drop)
			cache_fuel(name)
			cache_recipes(name)

			_preselect[name] = true
		end
	end

	for name in pairs(_preselect) do
		cache_usages(name)

		if recipes_cache[name] or usages_cache[name] then
			init_items[#init_items + 1] = name
			_select[name] = true
		end
	end

	resolve_aliases(_select)
	sort(init_items)

	if http and true_str(craftguide.export_url) then
		local post_data = {
			recipes = recipes_cache,
			usages  = usages_cache,
		}

		http.fetch_async{
			url = craftguide.export_url,
			post_data = write_json(post_data),
		}
	end
end

local function init_data(name)
	local info = get_player_info(name)

	pdata[name] = {
		filter        = "",
		pagenum       = 1,
		items         = init_items,
		items_raw     = init_items,
		favs          = {},
		export_counts = {},
		lang_code     = get_lang_code(info),
		fs_version    = get_formspec_version(info),
	}
end

local function reset_data(data)
	data.filter      = ""
	data.pagenum     = 1
	data.rnum        = 1
	data.unum        = 1
	data.scrbar_rcp  = 1
	data.scrbar_usg  = 1
	data.query_item  = nil
	data.recipes     = nil
	data.usages      = nil
	data.export_rcp  = nil
	data.export_usg  = nil
	data.items       = data.items_raw
end

on_mods_loaded(get_init_items)

on_joinplayer(function(player)
	local name = player:get_player_name()
	init_data(name)
	local data = pdata[name]

	if data.fs_version < MIN_FORMSPEC_VERSION then
		outdated(name)
	end
end)

on_receive_fields(function(player, formname, _f)
	if formname ~= "craftguide" then
		return false
	end

	local name = player:get_player_name()
	local data = pdata[name]
	local sb_rcp, sb_usg = _f.scrbar_rcp, _f.scrbar_usg

	if _f.quit then
		-- Neither the vignette nor hud_flags are available when /craft is used
		if data.vignette then
			player:hud_change(data.vignette, "text", "")
			data.vignette = nil
		end

		if data.hud_flags then
			data.hud_flags.crosshair = true
			player:hud_set_flags(data.hud_flags)
			data.hud_flags = nil
		end

		return false

	elseif _f.cancel then
		reset_data(data)

	elseif _f.prev_recipe or _f.next_recipe then
		local num = data.rnum + (_f.prev_recipe and -1 or 1)
		data.rnum = data.recipes[num] and num or (_f.prev_recipe and #data.recipes or 1)
		data.export_rcp = nil
		data.scrbar_rcp = 1

	elseif _f.prev_usage or _f.next_usage then
		local num = data.unum + (_f.prev_usage and -1 or 1)
		data.unum = data.usages[num] and num or (_f.prev_usage and #data.usages or 1)
		data.export_usg = nil
		data.scrbar_usg = 1

	elseif _f.key_enter_field == "filter" or _f.search then
		if _f.filter == "" then
			reset_data(data)
			return true, show_fs(player, name)
		end

		local str = lower(_f.filter)
		if data.filter == str then return end

		data.filter = str
		data.pagenum = 1

		search(data)

	elseif _f.prev_page or _f.next_page then
		if data.pagemax == 1 then return end
		data.pagenum = data.pagenum - (_f.prev_page and 1 or -1)

		if data.pagenum > data.pagemax then
			data.pagenum = 1
		elseif data.pagenum == 0 then
			data.pagenum = data.pagemax
		end

	elseif _f.fav then
		local fav, i = is_fav(data.favs, data.query_item)
		local total = #data.favs

		if total < MAX_FAVS and not fav then
			data.favs[total + 1] = data.query_item
		elseif fav then
			remove(data.favs, i)
		end

	elseif _f.export_rcp or _f.export_usg then
		if _f.export_rcp then
			data.export_rcp = not data.export_rcp

			if not data.export_rcp then
				data.scrbar_rcp = 1
			end
		else
			data.export_usg = not data.export_usg

			if not data.export_usg then
				data.scrbar_usg = 1
			end
		end

	elseif _f.trash then
		local inv = player:get_inventory()
		if not inv:is_empty("main") then
			inv:set_list("main", {})
		end

	elseif _f.compress then
		compress_items(player)

	elseif _f.sort_az or _f.sort_za then
		sort_itemlist(player, _f.sort_az)

	elseif _f.scrbar_inv then
		data.scrbar_inv = tonumber(match(_f.scrbar_inv, "%d+"))
		return true

	elseif (sb_rcp and sub(sb_rcp, 1, 3) == "CHG") or (sb_usg and sub(sb_usg, 1, 3) == "CHG") then
		data.scrbar_rcp = sb_rcp and tonum(match(sb_rcp, "%d+"))
		data.scrbar_usg = sb_usg and tonum(match(sb_usg, "%d+"))

	elseif _f.craft_rcp or _f.craft_usg then
		craft_stack(player, name, data, _f.craft_rcp)
	else
		select_item(player, data, _f)
	end

	return true, show_fs(player, name)
end)

local function on_use(user)
	local name = user:get_player_name()
	local data = pdata[name]
	if not data then return end

	if data.fs_version < MIN_FORMSPEC_VERSION then
		return outdated(name)
	end

	if next(recipe_filters) then
		data.items_raw = get_filtered_items(user)
		search(data)
	end

	show_fs(user, name)

	data.vignette = user:hud_add({
		hud_elem_type = "image",
		position = {x = 0.5,  y = 0.5},
		scale = {x = -100, y = -100},
		text = "craftguide_vignette.png",
		z_index = -0xB00B,
	})

	data.hud_flags = user:hud_get_flags()
	data.hud_flags.crosshair = false
	user:hud_set_flags(data.hud_flags)
end

core.register_craftitem("craftguide:book", {
	description = S"Crafting Guide",
	inventory_image = PNG.book,
	wield_image = PNG.book,
	stack_max = 1,
	groups = {book = 1},
	on_use = function(_, user)
		on_use(user)
	end
})

core.register_node("craftguide:sign", {
	description = S"Crafting Guide Sign",
	drawtype = "nodebox",
	tiles = {PNG.sign},
	inventory_image = PNG.sign,
	wield_image = PNG.sign,
	paramtype = "light",
	paramtype2 = "wallmounted",
	sunlight_propagates = true,
	groups = {
		choppy = 1,
		attached_node = 1,
		oddly_breakable_by_hand = 1,
		flammable = 3,
	},
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

	on_rightclick = function(_, _, user)
		on_use(user)
	end
})

core.register_craft{
	output = "craftguide:book",
	type   = "shapeless",
	recipe = {"default:book"}
}

core.register_craft{
	type = "fuel",
	recipe = "craftguide:book",
	burntime = 3
}

core.register_craft{
	output = "craftguide:sign",
	type   = "shapeless",
	recipe = {"default:sign_wall_wood"}
}

core.register_craft{
	type = "fuel",
	recipe = "craftguide:sign",
	burntime = 10
}

if progressive_mode then
	local function item_in_inv(item, inv_items)
		local inv_items_size = #inv_items

		if is_group(item) then
			local groups = extract_groups(item)
			for i = 1, inv_items_size do
				local def = reg_items[inv_items[i]]

				if def then
					if item_has_groups(def.groups, groups) then
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

	local function recipe_in_inv(rcp, inv_items)
		for _, item in pairs(rcp.items) do
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

	local item_lists = {"main", "craft", "craftpreview"}

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

	local function init_hud(player, data)
		data.hud = {
			bg = player:hud_add{
				hud_elem_type = "image",
				position      = {x = 0.78, y = 1},
				alignment     = {x = 1,    y = 1},
				scale         = {x = 370,  y = 112},
				text          = PNG.bg,
				z_index       = 0xDEAD,
			},

			book = player:hud_add{
				hud_elem_type = "image",
				position      = {x = 0.79, y = 1.02},
				alignment     = {x = 1,    y = 1},
				scale         = {x = 4,    y = 4},
				text          = PNG.book,
				z_index       = 0xDEAD,
			},

			text = player:hud_add{
				hud_elem_type = "text",
				position      = {x = 0.84, y = 1.04},
				alignment     = {x = 1,    y = 1},
				number        = 0xffffff,
				text          = "",
				z_index       = 0xDEAD,
			},
		}
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
		local players = get_players()
		for i = 1, #players do
			local player = players[i]
			local name = player:get_player_name()
			local data = pdata[name]

			local inv_items = get_inv_items(player)
			local diff = array_diff(inv_items, data.inv_items)

			if #diff > 0 then
				data.inv_items = table_merge(diff, data.inv_items)
				local oldknown = data.known_recipes or 0
				get_filtered_items(player, data)
				data.discovered = data.known_recipes - oldknown

				if data.show_hud == nil and data.discovered > 0 then
					data.show_hud = true
				end
			end
		end

		after(POLL_FREQ, poll_new_items)
	end

	poll_new_items()

	globalstep(function()
		local players = get_players()
		for i = 1, #players do
			local player = players[i]
			local name = player:get_player_name()
			local data = pdata[name]

			if data.show_hud ~= nil and singleplayer then
				show_hud_success(player, data)
			end
		end
	end)

	craftguide.add_recipe_filter("Default progressive filter", progressive_filter)

	on_joinplayer(function(player)
		local name = player:get_player_name()
		local data = pdata[name]

		local meta = player:get_meta()
		data.inv_items = dslz(meta:get_string "inv_items") or {}
		data.known_recipes = dslz(meta:get_string "known_recipes") or 0

		if singleplayer then
			init_hud(player, data)
		end
	end)

	local to_save = {"inv_items", "known_recipes"}

	local function save_meta(player)
		local meta = player:get_meta()
		local name = player:get_player_name()
		local data = pdata[name]

		for i = 1, #to_save do
			local meta_name = to_save[i]
			meta:set_string(meta_name, slz(data[meta_name]))
		end
	end

	on_leaveplayer(save_meta)

	on_shutdown(function()
		local players = get_players()
		for i = 1, #players do
			local player = players[i]
			save_meta(player)
		end
	end)
end

on_leaveplayer(function(player)
	local name = player:get_player_name()
	pdata[name] = nil
end)

function craftguide.show(name, item)
	if not true_str(name) then
		return err "craftguide.show(): player name missing"
	end

	local data = pdata[name]
	local player = get_player_by_name(name)
	local query_item = data.query_item

	reset_data(data)

	item = reg_items[item] and item or query_item
	local recipes, usages = get_recipes(item, data, player)

	if not recipes and not usages then
		if not recipes_cache[item] and not usages_cache[item] then
			return false, msg(name, sprintf("%s: %s",
				S"No recipe or usage for this node", clr("#ff0", get_desc(item))))
		end

		return false, msg(name, sprintf("%s: %s",
			S"You don't know a recipe or usage for this item", get_desc(item)))
	end

	data.query_item = item
	data.recipes    = recipes
	data.usages     = usages

	show_fs(player, name)
end

register_command("craft", {
	description = S"Show recipe(s) of the pointed node",
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
				local def = reg_items[node.name]

				if def then
					node_name = node.name
					break
				end
			end
		end

		if not node_name then
			return false, msg(name, S"No node pointed")
		end

		return true, craftguide.show(name, node_name)
	end,
})
