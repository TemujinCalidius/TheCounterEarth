-- CraftingConfig.luau
-- Hand-crafting recipes that require no station.
-- All are visible in the Recipe Book; the client greys out ones the player
-- can't currently afford.
--
-- ingredients: list of { itemId, qty } consumed on craft
-- output:      { itemId, qty } produced on craft
-- station:     "hand" = no station required (crafted anywhere)
-- skillLevel:  minimum skill level required (future skill system; 1 = no req)

return {
	Recipes = {
		{
			id          = "stone_axe",
			displayName = "Stone Axe",
			description = "A crude axe. Needed to chop wood.",
			station     = "hand",
			skillLevel  = 1,
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
			station     = "hand",
			skillLevel  = 1,
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
			station     = "hand",
			skillLevel  = 1,
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
			station     = "hand",
			skillLevel  = 1,
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
			station     = "hand",
			skillLevel  = 1,
			ingredients = {
				{ itemId = "reed",   qty = 8 },
			},
			output = { itemId = "bedroll", qty = 1 },
		},
		{
			id          = "satchel_reed",
			displayName = "Reed Satchel",
			description = "A woven reed satchel. Basic backpack storage.",
			station     = "hand",
			skillLevel  = 1,
			ingredients = {
				{ itemId = "reed",   qty = 12 },
				{ itemId = "twig",   qty = 2 },
			},
			output = { itemId = "satchel_reed", qty = 1 },
		},
		{
			id          = "stone_spear",
			displayName = "Stone Spear",
			description = "A long stone-tipped staff for combat.",
			station     = "hand",
			skillLevel  = 1,
			ingredients = {
				{ itemId = "twig",   qty = 2 },
				{ itemId = "rock",   qty = 1 },
			},
			output = { itemId = "stone_spear", qty = 1 },
		},
		{
			id          = "primitive_bow",
			displayName = "Primitive Bow",
			description = "A crude bow for ranged combat.",
			station     = "hand",
			skillLevel  = 1,
			ingredients = {
				{ itemId = "twig",   qty = 2 },
				{ itemId = "reed",   qty = 3 },
			},
			output = { itemId = "primitive_bow", qty = 1 },
		},
		{
			id          = "stone_arrow",
			displayName = "Stone Arrows",
			description = "Five crude stone-tipped arrows.",
			station     = "hand",
			skillLevel  = 1,
			ingredients = {
				{ itemId = "twig",   qty = 1 },
				{ itemId = "rock",   qty = 1 },
			},
			output = { itemId = "stone_arrow", qty = 5 },
		},
		{
			id          = "reed_quiver",
			displayName = "Reed Quiver",
			description = "A woven reed quiver. Speeds up arrow nocking.",
			station     = "hand",
			skillLevel  = 1,
			ingredients = {
				{ itemId = "reed",   qty = 5 },
			},
			output = { itemId = "reed_quiver", qty = 1 },
		},
	},
}
