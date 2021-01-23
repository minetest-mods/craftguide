## API

### Custom recipes

Custom recipes are nonconventional crafts outside the main crafting grid.
They can be registered in-game dynamically and have a size beyond 3x3 items.

**Note:** the registration format differs from the default registration format in everything.
The width is automatically calculated depending where you place the commas. Look at the examples attentively.

#### Registering a custom crafting type (example)

```Lua
craftguide.register_craft_type("digging", {
	description = "Digging",
	icon = "default_tool_steelpick.png",
})
```

#### Registering a custom crafting recipe (examples)

```Lua
craftguide.register_craft({
	type   = "digging",
	result = "default:cobble 2",
	items  = {"default:stone"},
})
```

```Lua
craftguide.register_craft({
	result = "default:cobble 16",
	items = {
		"default:stone, default:stone, default:stone",
		"default:stone,              , default:stone",
		"default:stone, default:stone, default:stone",
	}
})
```

Recipes can be registered in a Minecraft-like way:

```Lua
craftguide.register_craft({
	grid = {
		"X  #",
		" ## ",
		"X#X#",
		"X  X",
	},
	key = {
		['#'] = "default:wood",
		['X'] = "default:glass",
	},
	result = "default:mese 3",
})
```

Multiples recipes can also be registered:

```Lua
craftguide.register_craft({
	{
		result = "default:mese",
		items = {
			"default:mese_crystal, default:mese_crystal",
			"default:mese_crystal, default:mese_crystal",
		}
	},

	big = {
		result = "default:mese 4",
		items = {
			"default:mese_crystal, default:mese_crystal",
			"default:mese_crystal, default:mese_crystal",
			"default:mese_crystal, default:mese_crystal",
			"default:mese_crystal, default:mese_crystal",
		}
	},
})
```

Recipes can be registered from a given URL containing a JSON file (HTTP support is required¹):

```Lua
craftguide.register_craft({
	url = "https://raw.githubusercontent.com/minetest-mods/craftguide/master/test.json"
})
```

---

### Recipe filters

Recipe filters can be used to filter the recipes shown to players. Progressive
mode is implemented as a recipe filter.

#### `craftguide.add_recipe_filter(name, function(recipes, player))`

Adds a recipe filter with the given `name`. The filter function returns the
recipes to be displayed, given the available recipes and an `ObjectRef` to the
user. Each recipe is a table of the form returned by
`minetest.get_craft_recipe`.

Example function to hide recipes for items from a mod called "secretstuff":

```lua
craftguide.add_recipe_filter("Hide secretstuff", function(recipes)
	local filtered = {}
	for _, recipe in ipairs(recipes) do
		if recipe.output:sub(1,12) ~= "secretstuff:" then
			filtered[#filtered + 1] = recipe
		end
	end

	return filtered
end)
```

#### `craftguide.set_recipe_filter(name, function(recipe, player))`

Removes all recipe filters and adds a new one.

#### `craftguide.remove_recipe_filter(name)`

Removes the recipe filter with the given `name`.

#### `craftguide.get_recipe_filters()`

Returns a map of recipe filters, indexed by name.

---

### Search filters

Search filters are used to perform specific searches inside the search field.
You can cumulate several filters to perform a specific search.
They can be used like so: `<optional_name> +<filter name>=<value1>,<value2>,<...>`

Example usages:

- `+groups=cracky,crumbly`: search for groups `cracky` and `crumbly` in all items.
- `wood +groups=flammable +type=node`: search for group `flammable` amongst items which contain
  `wood` in their names AND have a `node` drawtype.

Notes:
- If `optional_name` is omitted, the search filter will apply to all items, without pre-filtering.
- The `groups` and `type` filters are currently implemented by default.

#### `craftguide.add_search_filter(name, function(item, values))`

Adds a search filter with the given `name`.
The search function must return a boolean value (whether the given item should be listed or not).

Example function sorting items by drawtype:

```lua
craftguide.add_search_filter("type", function(item, drawtype)
	if drawtype == "node" then
		return reg_nodes[item]
	elseif drawtype == "item" then
		return reg_craftitems[item]
	elseif drawtype == "tool" then
		return reg_tools[item]
	end
end)
```

#### `craftguide.remove_search_filter(name)`

Removes the search filter with the given `name`.

#### `craftguide.get_search_filters()`

Returns a map of search filters, indexed by name.

---

### Miscellaneous

#### `craftguide.show(player_name, item, show_usages)`

Opens the Crafting Guide with the current filter applied.

   * `player_name`: string param.
   * `item`: optional, string param. If set, this item is pre-selected. If the item does not exist or has no recipe, use the player's previous selection. By default, player's previous selection is used
   * `show_usages`: optional, boolean param. If true, show item usages.

#### `craftguide.group_stereotypes`

This is the table indexing the item groups by stereotypes.
You can add a stereotype like so:

```Lua
craftguide.group_stereotypes.radioactive = "mod:item"
```

#### `craftguide.export_url`

If set, the mod will export all the cached recipes and usages in a JSON format
to the given URL (HTTP support is required¹).

---

**¹** Add `craftguide` to the `secure.http_mods` or `secure.trusted_mods` setting in `minetest.conf`.
