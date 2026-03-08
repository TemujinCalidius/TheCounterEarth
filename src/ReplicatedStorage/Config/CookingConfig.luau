-- CookingConfig.luau
-- Station-based cooking recipes. Key = raw input itemId.
-- The campfire (and future stations) look up recipes by input item.
--
-- station:     which station type processes this recipe
-- cookSeconds: time per unit to cook
-- skillLevel:  minimum skill level required (future skill system; 1 = no requirement)
-- displayName: shown in Recipe Book UI

return {
	Recipes = {
		BrownMushroom = {
			output      = "cooked_mushroom",
			cookSeconds = 4,
			station     = "campfire",
			skillLevel  = 1,
			displayName = "Cooked Mushroom",
		},
		raw_meat = {
			output      = "cooked_meat",
			cookSeconds = 6,
			station     = "campfire",
			skillLevel  = 1,
			displayName = "Cooked Meat",
		},
		raw_fish = {
			output      = "cooked_fish",
			cookSeconds = 5,
			station     = "campfire",
			skillLevel  = 1,
			displayName = "Cooked Fish",
		},
	},
}
