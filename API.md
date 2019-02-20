## API

### Custom recipes

#### Registering a custom crafting type (example)

```Lua
craftguide.register_craft_type("digging", {
	description = "Digging",
	icon = "default_tool_steelpick.png",
})
```

#### Registering a custom crafting recipe (example)

```Lua
craftguide.register_craft({
	type   = "digging",
	width  = 1,
	output = "default:cobble 2",
	items  = {"default:stone"},
})
```

### Recipe filters

Recipe filters can be used to filter the recipes shown to players. Progressive
mode is implemented as a recipe filter.

#### `craftguide.add_recipe_filter(name, function(recipes, player))`

Adds a recipe filter with the given name. The filter function should return the
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

#### `craftguide.remove_recipe_filter(name)`

Removes the recipe filter with the given name.

#### `craftguide.set_recipe_filter(name, function(recipe, player))`

Removes all recipe filters and adds a new one.

#### `craftguide.get_recipe_filters()`

Returns a map of recipe filters, indexed by name.

### Custom formspec elements

#### `craftguide.add_formspec_element(name, def)`

Adds a formspec element to the current formspec.
Supported types: `box`, `label`, `image`, `button`, `tooltip`, `item_image`, `image_button`, `item_image_button`

Example:

```lua
craftguide.add_formspec_element("export", {
	type = "button",
	element = function(data)
		-- Should return a table of parameters according to the formspec element type.
		-- Note: for all buttons, the 'name' parameter *must not* be specified!
		if data.recipes then
			return {
				data.iX - 3.7,   -- X
				sfinv_only and 7.9 or 8, -- Y
				1.6,             -- W
				1,               -- H
				ESC(S("Export")) -- label
			}
		end
	end,
	-- Optional.
	action = function(player, data)
		-- When the button is pressed.
		print("Exported!")
	end
})
```

#### `craftguide.remove_formspec_element(name)`

Removes the formspec element with the given name.

#### `craftguide.get_formspec_elements()`

Returns a map of formspec elements, indexed by name.

### Miscellaneous

#### `craftguide.show(player_name, item, show_usages)`

Opens the Crafting Guide with the current filter applied.

   * `player_name`: string param.
   * `item`: optional, string param. If set, this item is pre-selected. If the item does not exist or has no recipe, use the player's previous selection. By default, player's previous selection is used
   * `show_usages`: optional, boolean param. If true, show item usages.
