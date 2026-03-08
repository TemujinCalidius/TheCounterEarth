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
			id          = "stone_axe",
			displayName = "Stone Axe",
			description = "A crude axe. Needed to chop wood.",
			ingredients = {
				{ itemId = "twig",   qty = 3 },
				{ itemId = "rock",   qty = 2 },
			},
			output = { itemId = "stone_axe", qty = 1 },
		},
		{
			id          = "stone_pickaxe",
			displayName = "Stone Pickaxe",
			description = "A rough pickaxe. Mines soft rock.",
			ingredients = {
				{ itemId = "twig",   qty = 2 },
				{ itemId = "rock",   qty = 4 },
			},
			output = { itemId = "stone_pickaxe", qty = 1 },
		},
		{
			id          = "stone_knife",
			displayName = "Stone Knife",
			description = "A shard bound to a twig. Harvests reed and hide.",
			ingredients = {
				{ itemId = "twig",   qty = 2 },
				{ itemId = "rock",   qty = 2 },
			},
			output = { itemId = "stone_knife", qty = 1 },
		},
		{
			id          = "campfire",
			displayName = "Campfire",
			description = "A basic campfire. Cook food and rest nearby.",
			ingredients = {
				{ itemId = "twig",   qty = 5 },
				{ itemId = "rock",   qty = 3 },
			},
			output = { itemId = "campfire", qty = 1 },
		},
		{
			id          = "bedroll",
			displayName = "Bedroll",
			description = "A rough bedroll. Sets your respawn point.",
			ingredients = {
				{ itemId = "reed",   qty = 8 },
			},
			output = { itemId = "bedroll", qty = 1 },
		},
		{
			id          = "satchel_reed",
			displayName = "Reed Satchel",
			description = "A woven reed satchel. Basic backpack storage.",
			ingredients = {
				{ itemId = "reed",   qty = 12 },
				{ itemId = "twig",   qty = 2 },
			},
			output = { itemId = "satchel_reed", qty = 1 },
		},
	},
}
