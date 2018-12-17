## ![Preview1](http://i.imgur.com/fIPNYkb.png) Crafting Guide ##

#### `craftguide` is the most comprehensive crafting guide on Minetest. ####
#### Consult the [Minetest Wiki](http://wiki.minetest.net/Crafting_guide) for more details. ####

This crafting guide is a blue book named *"Crafting Guide"* or a wooden sign.

This crafting guide features a **progressive mode**.
The progressive mode is a Terraria-like system that only shows recipes you can craft from items in inventory.
The progressive mode can be enabled with `craftguide_progressive_mode = true` in `minetest.conf`.

`craftguide` is also integrated in `sfinv` (Minetest Game inventory) when you enable it with
`craftguide_sfinv_only = true` in `minetest.conf`.

Use the command `/craft` to show the recipe(s) of the pointed node.

---

`craftguide` has an API to register **custom recipes**. Demos:
#### Registering a custom crafting type ####
```Lua
craftguide.register_craft_type("digging", {
	description = S("Digging"),
	icon  = "default_tool_steelpick.png",
	width = 1,
})
```

#### Registering a custom crafting recipe ####
```Lua
craftguide.register_craft({
	type   = "digging",
	output = "default:cobble 2",
	items  = {"default:stone"},
})
```

![Preview2](https://i.imgur.com/bToFH38.png)
