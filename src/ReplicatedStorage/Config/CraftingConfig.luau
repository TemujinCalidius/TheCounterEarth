-- CraftingConfig.luau
-- Hand-crafting recipes that require no station.
-- All are visible in the craft panel; the client greys out ones the player
-- can't currently afford.
--
-- ingredients: list of { itemId, qty } consumed on craft
-- output:      { itemId, qty } produced on craft
-- requiresStation: nil = anywhere, string = station tag required (future)

return {
	Recipes = {
		{
			id          = "twig_axe",
			displayName = "Twig Axe",
			description = "A crude axe. Needed to chop wood.",
			ingredients = {
				{ itemId = "twig",   qty = 3 },
				{ itemId = "pebble", qty = 2 },
			},
			output = { itemId = "twig_axe", qty = 1 },
		},
		{
			id          = "stone_pickaxe",
			displayName = "Stone Pickaxe",
			description = "A rough pickaxe. Mines soft rock.",
			ingredients = {
				{ itemId = "twig",   qty = 2 },
				{ itemId = "pebble", qty = 4 },
			},
			output = { itemId = "stone_pickaxe", qty = 1 },
		},
		{
			id          = "twig_knife",
			displayName = "Twig Knife",
			description = "A shard bound to a twig. Harvests fiber and hide.",
			ingredients = {
				{ itemId = "twig",   qty = 2 },
				{ itemId = "pebble", qty = 2 },
			},
			output = { itemId = "twig_knife", qty = 1 },
		},
		{
			id          = "campfire",
			displayName = "Campfire",
			description = "A basic campfire. Cook food and rest nearby.",
			ingredients = {
				{ itemId = "twig",   qty = 5 },
				{ itemId = "pebble", qty = 3 },
			},
			output = { itemId = "campfire", qty = 1 },
		},
		{
			id          = "bedroll",
			displayName = "Bedroll",
			description = "A rough bedroll. Sets your respawn point.",
			ingredients = {
				{ itemId = "fiber",  qty = 8 },
			},
			output = { itemId = "bedroll", qty = 1 },
		},
		{
			id          = "satchel_cloth",
			displayName = "Cloth Satchel",
			description = "A small cloth bag. Basic backpack storage.",
			ingredients = {
				{ itemId = "fiber",  qty = 12 },
				{ itemId = "twig",   qty = 2 },
			},
			output = { itemId = "satchel_cloth", qty = 1 },
		},
	},
}
