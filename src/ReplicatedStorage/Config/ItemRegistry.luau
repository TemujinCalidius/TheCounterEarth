-- ItemRegistry.luau
-- Master item definition table. Every item type in the game has one entry here.
-- Instance data (qty, durability, expiresAt) is stored separately per item stack.

-- onConsume keys must match StatsConfig.AttributeNames:
--   health, hunger, thirst, energy, fatigue
--   Negative values mean the stat decreases (e.g. raw meat makes you more thirsty).

export type ToolInfo = {
	kind: string,            -- "axe" | "pickaxe" | "knife" | "weapon"
	tier: number,            -- 0 = primitive, 1 = basic, 2 = refined ...
	harvestTags: { string }?, -- resource node tags this tool can harvest
	damage: number?,         -- melee damage (weapons only)
}

export type CurrencyInfo = {
	economy: string,         -- e.g. "credits" | "standard" | "duchy"
	denomination: string,    -- e.g. "credit" | "copper" | "silver" | "gold"
	denominationValue: number, -- relative value within economy (copper=1, silver=100, gold=10000)
}

export type CoinPouchInfo = {
	acceptsEconomy: string,  -- which economy's coins this pouch can hold
}

export type BackpackInfo = {
	gridW: number,
	gridH: number,
	maxWeight: number,       -- kg this backpack can hold
}

export type ConsumeEffect = {
	health: number?,
	hunger: number?,
	thirst: number?,
	energy: number?,
	fatigue: number?,
	poison: number?,     -- 0-100 poison inflicted when consumed (raw/toxic food)
}

export type ItemDef = {
	id: string,
	displayName: string,
	description: string,
	stackMax: number,        -- 1 = not stackable
	weight: number,          -- kg per unit
	slotSize: { w: number, h: number }, -- grid cells this item occupies
	category: string,        -- "material"|"tool"|"food"|"currency"|"container"|"placeable"|"weapon"|"armor"
	durabilityMax: number?,  -- nil = no durability / indestructible
	perishSeconds: number?,  -- seconds until spoiled; nil = never expires
	onConsume: ConsumeEffect?,
	currency: CurrencyInfo?,
	coinPouch: CoinPouchInfo?,
	backpack: BackpackInfo?,
	tool: ToolInfo?,
	tags: { string },
	icon: string,            -- rbxassetid://... ; "" until uploaded
	meshId: string?,         -- rbxassetid://... for 3D mesh; nil = no mesh
	meshSize: Vector3?,      -- size for the mesh when held in hand; nil = default 0.5
}

local Items: { [string]: ItemDef } = {}

-- ---------------------------------------------------------------------------
-- TIER 0 FLOOR SCATTER — no tool required, just walk up and press E
-- ---------------------------------------------------------------------------

Items.twig = {
	id = "twig",
	displayName = "Twig",
	description = "A dry twig. Needed for any primitive tool.",
	stackMax = 20,
	weight = 0.05,
	slotSize = { w = 1, h = 1 },
	category = "material",
	tags = { "primitive", "wood", "scatter" },
	icon = "rbxassetid://107328542304066",
}

Items.rock = {
	id = "rock",
	displayName = "Rock",
	description = "A small stone. The other half of every primitive tool.",
	stackMax = 20,
	weight = 0.2,
	slotSize = { w = 1, h = 1 },
	category = "material",
	tags = { "primitive", "stone", "scatter" },
	icon = "rbxassetid://72036406518711",
}

Items.BrownMushroom = {
	id = "BrownMushroom",
	displayName = "Brown Mushroom",
	description = "A wild mushroom. Tastes better cooked.",
	stackMax = 10,
	weight = 0.1,
	slotSize = { w = 1, h = 1 },
	category = "food",
	perishSeconds = 2400,
	onConsume = { health = 5, hunger = 10, thirst = 0 },
	tags = { "food", "raw", "forage", "scatter" },
	icon = "rbxassetid://136772121686318",
	meshId = "rbxassetid://75194355299341",
	meshSize = Vector3.new(0.5, 0.5, 0.5),
}

-- ---------------------------------------------------------------------------
-- HAND CRAFTED TOOLS — no station, recipes use twigs + rocks
-- ---------------------------------------------------------------------------

Items.stone_axe = {
	id = "stone_axe",
	displayName = "Stone Axe",
	description = "A crude axe lashed together with twigs and rocks. Barely holds together.",
	stackMax = 5,
	weight = 0.4,
	slotSize = { w = 1, h = 2 },
	category = "tool",
	durabilityMax = 30,
	tool = {
		kind = "axe",
		tier = 0,
		harvestTags = { "wood", "tree" },
	},
	tags = { "tool", "axe", "tier0", "primitive" },
	gripCFrame = CFrame.new(0.093, -0.454, 0.078) * CFrame.Angles(math.rad(-9.6), math.rad(-171.5), math.rad(-82.6)),
	icon = "rbxassetid://83177613644634",
}

Items.stone_pickaxe = {
	id = "stone_pickaxe",
	displayName = "Stone Pickaxe",
	description = "A rough pickaxe good enough to chip away at soft rock.",
	stackMax = 5,
	weight = 0.8,
	slotSize = { w = 1, h = 2 },
	category = "tool",
	durabilityMax = 25,
	tool = {
		kind = "pickaxe",
		tier = 0,
		harvestTags = { "stone", "ore" },
	},
	tags = { "tool", "pickaxe", "tier0", "primitive" },
	icon = "rbxassetid://70659355065719",
}

Items.stone_knife = {
	id = "stone_knife",
	displayName = "Stone Knife",
	description = "A splintered rock bound to a twig. Barely a knife, but it works.",
	stackMax = 5,
	weight = 0.2,
	slotSize = { w = 1, h = 2 },
	category = "tool",
	durabilityMax = 20,
	tool = {
		kind = "knife",
		tier = 0,
		harvestTags = { "reed", "herb", "hide" },
		damage = 3,
	},
	tags = { "tool", "knife", "weapon", "tier0", "primitive" },
	icon = "rbxassetid://122399662411193",
}

-- ---------------------------------------------------------------------------
-- TIER 0 PLACEABLES — hand craftable, no station
-- ---------------------------------------------------------------------------

Items.campfire = {
	id = "campfire",
	displayName = "Campfire",
	description = "A simple campfire. Cook food and rest nearby to slowly recover stats.",
	stackMax = 1,
	weight = 1.5,
	slotSize = { w = 2, h = 2 },
	category = "placeable",
	tags = { "placeable", "crafting_station", "campfire", "tier0" },
	icon = "rbxassetid://79851233339992",
}

Items.bedroll = {
	id = "bedroll",
	displayName = "Bedroll",
	description = "A rough bedroll made from reed. Sets your respawn point.",
	stackMax = 1,
	weight = 1.0,
	slotSize = { w = 2, h = 3 },
	category = "placeable",
	tags = { "placeable", "respawn", "tier0" },
	icon = "rbxassetid://71441394289581",
}

-- ---------------------------------------------------------------------------
-- TIER 1 MATERIALS — gathered with primitive tools
-- ---------------------------------------------------------------------------

Items.oak_log = {
	id = "oak_log",
	displayName = "Oak Log",
	description = "A rough log from a felled oak tree.",
	stackMax = 10,
	weight = 1.5,
	slotSize = { w = 1, h = 2 },
	category = "material",
	tags = { "material", "wood", "tier0", "log" },
	icon = "rbxassetid://80881492393736",
}

Items.stone = {
	id = "stone",
	displayName = "Stone",
	description = "Solid stone chipped from a rock face.",
	stackMax = 10,
	weight = 2.0,
	slotSize = { w = 1, h = 1 },
	category = "material",
	tags = { "material", "stone", "tier1" },
	icon = "rbxassetid://140587989430036",
}

Items.reed = {
	id = "reed",
	displayName = "Reed",
	description = "Dried reed. Used in weaving, bedding, and binding.",
	stackMax = 20,
	weight = 0.1,
	slotSize = { w = 1, h = 1 },
	category = "material",
	tags = { "material", "reed", "tier1" },
	icon = "rbxassetid://99940535604564",
}

Items.iron_ore = {
	id = "iron_ore",
	displayName = "Iron Ore",
	description = "Raw iron ore. Needs smelting at a forge.",
	stackMax = 5,
	weight = 3.0,
	slotSize = { w = 1, h = 1 },
	category = "material",
	tags = { "material", "ore", "iron", "tier1" },
	icon = "rbxassetid://121339013867057",
}

-- ---------------------------------------------------------------------------
-- FOOD — campfire cooked
-- ---------------------------------------------------------------------------

Items.cooked_mushroom = {
	id = "cooked_mushroom",
	displayName = "Cooked Mushroom",
	description = "A roasted mushroom. Good energy food.",
	stackMax = 10,
	weight = 0.1,
	slotSize = { w = 1, h = 1 },
	category = "food",
	perishSeconds = 3600,
	onConsume = { health = 10, hunger = 18, thirst = 2 },
	tags = { "food", "cooked" },
	icon = "rbxassetid://116959815948177",
}

Items.spoiled_food = {
	id = "spoiled_food",
	displayName = "Spoiled Food",
	description = "Rotten remains. Useless as food, but an alchemist might find a use.",
	stackMax = 10,
	weight = 0.1,
	slotSize = { w = 1, h = 1 },
	category = "material",
	tags = { "junk", "alchemy" },
	icon = "rbxassetid://70694772297700",
}

Items.water_skin = {
	id = "water_skin",
	displayName = "Water Skin",
	description = "A skin filled with fresh water.",
	stackMax = 1,
	weight = 0.5,
	slotSize = { w = 1, h = 1 },
	category = "food",
	onConsume = { thirst = 40 },
	tags = { "food", "drink", "water" },
	icon = "rbxassetid://109433490537026",
}

-- ---------------------------------------------------------------------------
-- MEDICAL
-- ---------------------------------------------------------------------------

Items.bandage = {
	id = "bandage",
	displayName = "Bandage",
	description = "Stops bleeding immediately.",
	stackMax = 10,
	weight = 0.1,
	slotSize = { w = 1, h = 1 },
	category = "medical",
	onConsume = { health = 5 },
	tags = { "medical", "bandage", "stops_bleed" },
	icon = "rbxassetid://105711750453135",
}

Items.antidote = {
	id = "antidote",
	displayName = "Antidote",
	description = "Clears poison.",
	stackMax = 5,
	weight = 0.1,
	slotSize = { w = 1, h = 1 },
	category = "medical",
	onConsume = {},
	tags = { "medical", "antidote", "clears_poison" },
	icon = "rbxassetid://77121987674625",
}

-- ---------------------------------------------------------------------------
-- CURRENCY
-- ---------------------------------------------------------------------------

Items.coin_credits = {
	id = "coin_credits",
	displayName = "Credits",
	description = "The default currency.",
	stackMax = 9999,
	weight = 0.001,
	slotSize = { w = 1, h = 1 },
	category = "currency",
	currency = { economy = "credits", denomination = "credit", denominationValue = 1 },
	tags = { "currency", "credits" },
	icon = "rbxassetid://122571796115169",
}

Items.coin_copper = {
	id = "coin_copper",
	displayName = "Copper Coin",
	description = "The smallest standard denomination.",
	stackMax = 9999,
	weight = 0.005,
	slotSize = { w = 1, h = 1 },
	category = "currency",
	currency = { economy = "standard", denomination = "copper", denominationValue = 1 },
	tags = { "currency", "standard", "copper" },
	icon = "rbxassetid://127088174978840",
}

Items.coin_silver = {
	id = "coin_silver",
	displayName = "Silver Coin",
	description = "Worth 100 copper.",
	stackMax = 9999,
	weight = 0.01,
	slotSize = { w = 1, h = 1 },
	category = "currency",
	currency = { economy = "standard", denomination = "silver", denominationValue = 100 },
	tags = { "currency", "standard", "silver" },
	icon = "rbxassetid://108939641140967",
}

Items.coin_gold = {
	id = "coin_gold",
	displayName = "Gold Coin",
	description = "Worth 100 silver.",
	stackMax = 9999,
	weight = 0.02,
	slotSize = { w = 1, h = 1 },
	category = "currency",
	currency = { economy = "standard", denomination = "gold", denominationValue = 10000 },
	tags = { "currency", "standard", "gold" },
	icon = "rbxassetid://139295913122525",
}

-- ---------------------------------------------------------------------------
-- COIN POUCHES
-- ---------------------------------------------------------------------------

Items.pouch_credits = {
	id = "pouch_credits",
	displayName = "Credits Pouch",
	description = "A simple pouch for carrying credits.",
	stackMax = 1,
	weight = 0.05,
	slotSize = { w = 1, h = 1 },
	category = "container",
	coinPouch = { acceptsEconomy = "credits" },
	tags = { "container", "coin_pouch", "credits" },
	icon = "rbxassetid://105435561674307",
}

Items.pouch_standard = {
	id = "pouch_standard",
	displayName = "Coin Pouch",
	description = "A leather pouch for gold, silver and copper.",
	stackMax = 1,
	weight = 0.1,
	slotSize = { w = 1, h = 1 },
	category = "container",
	coinPouch = { acceptsEconomy = "standard" },
	tags = { "container", "coin_pouch", "standard" },
	icon = "rbxassetid://75831714361663",
}

-- ---------------------------------------------------------------------------
-- BACKPACKS
-- ---------------------------------------------------------------------------

Items.satchel_reed = {
	id = "satchel_reed",
	displayName = "Reed Satchel",
	description = "A woven reed satchel. Basic storage beyond your pockets.",
	stackMax = 1,
	weight = 0.3,
	slotSize = { w = 2, h = 2 },
	category = "container",
	backpack = { slots = 10, maxWeight = 10 },
	tags = { "container", "backpack", "tier0" },
	icon = "rbxassetid://109737374250301",
}

Items.pack_leather = {
	id = "pack_leather",
	displayName = "Leather Pack",
	description = "A sturdy leather pack. Much more room.",
	stackMax = 1,
	weight = 0.8,
	slotSize = { w = 2, h = 3 },
	category = "container",
	backpack = { slots = 20, maxWeight = 30 },
	tags = { "container", "backpack", "tier1" },
	icon = "rbxassetid://122038665945878",
}

-- ---------------------------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------------------------

local function get(id: string): ItemDef?
	return Items[id]
end

local function hasTag(def: ItemDef, tag: string): boolean
	for _, t in ipairs(def.tags) do
		if t == tag then
			return true
		end
	end
	return false
end

-- Returns all items whose tags include at least one of the given tags.
local function getByTag(tag: string): { ItemDef }
	local result = {}
	for _, def in pairs(Items) do
		if hasTag(def, tag) then
			table.insert(result, def)
		end
	end
	return result
end

return {
	Items  = Items,
	get    = get,
	hasTag = hasTag,
	getByTag = getByTag,
}
