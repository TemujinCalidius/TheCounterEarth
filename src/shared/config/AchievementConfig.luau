-- AchievementConfig.luau
-- Defines all achievements, counter names, and event-to-counter mappings.
-- Shared between server (AchievementService) and client (UI display).

export type AchievementDef = {
	key: string,
	name: string,
	icon: string,
	category: string,
	counter: string,
	threshold: number,
	desc: string,
}

export type EventMapping = {
	counter: string,
	condition: ((data: { [string]: any }) -> boolean)?,
	playerFrom: string?,   -- "killer" = attribute credit to killer, not victim
	mode: string?,         -- "max" = store highest value, not increment
	valueFrom: ((data: { [string]: any }) -> number)?,
}

local AchievementConfig = {}

-- ── All 53 achievements ─────────────────────────────────────────────────

AchievementConfig.Achievements = {
	-- Deaths (4)
	{ key = "first_death",  name = "Welcome to the Wasteland", icon = "\u{1F480}", category = "Deaths",      counter = "deaths_total",       threshold = 1,   desc = "Die for the first time. Everyone starts somewhere." },
	{ key = "deaths_10",    name = "Getting Used to It",       icon = "\u{2620}",  category = "Deaths",      counter = "deaths_total",       threshold = 10,  desc = "Die 10 times. The wasteland is unforgiving." },
	{ key = "deaths_50",    name = "Death Wish",               icon = "\u{1FAA6}", category = "Deaths",      counter = "deaths_total",       threshold = 50,  desc = "Die 50 times. Are you even trying to survive?" },
	{ key = "deaths_100",   name = "Undying Spirit",           icon = "\u{1F47B}", category = "Deaths",      counter = "deaths_total",       threshold = 100, desc = "Die 100 times. Death is just a minor inconvenience." },

	-- Death Causes (5)
	{ key = "death_starvation",  name = "Empty Stomach",             icon = "\u{1F37D}",  category = "Death Causes", counter = "deaths_starvation",  threshold = 1, desc = "Starve to death. Remember to eat." },
	{ key = "death_dehydration", name = "Parched",                   icon = "\u{1F3DC}",  category = "Death Causes", counter = "deaths_dehydration", threshold = 1, desc = "Die of thirst. Find a water source." },
	{ key = "death_poison",      name = "Shouldn't Have Eaten That", icon = "\u{2620}",   category = "Death Causes", counter = "deaths_poison",      threshold = 1, desc = "Die from food poisoning. Cook your food properly." },
	{ key = "death_bleeding",    name = "Flesh Wound",               icon = "\u{1FA78}",  category = "Death Causes", counter = "deaths_bleeding",    threshold = 1, desc = "Bleed out from wounds. Keep bandages handy." },
	{ key = "death_pvp_5",       name = "Punching Bag",              icon = "\u{1F94A}",  category = "Death Causes", counter = "deaths_pvp",         threshold = 5, desc = "Be killed by other players 5 times." },

	-- Survival (4)
	{ key = "survive_5m",   name = "Baby Steps",          icon = "\u{1F423}", category = "Survival", counter = "survival_best", threshold = 300,   desc = "Survive for 5 minutes in a single life." },
	{ key = "survive_30m",  name = "Getting Comfortable", icon = "\u{1F6E1}", category = "Survival", counter = "survival_best", threshold = 1800,  desc = "Survive for 30 minutes in a single life." },
	{ key = "survive_1h",   name = "Survivor",            icon = "\u{2694}",  category = "Survival", counter = "survival_best", threshold = 3600,  desc = "Survive for 1 hour in a single life." },
	{ key = "survive_3h",   name = "Wasteland Veteran",   icon = "\u{1F3C5}", category = "Survival", counter = "survival_best", threshold = 10800, desc = "Survive for 3 hours in a single life." },

	-- Playtime (4)
	{ key = "playtime_1h",   name = "Getting Started", icon = "\u{23F0}",  category = "Playtime", counter = "playtime_total", threshold = 3600,   desc = "Play for a total of 1 hour." },
	{ key = "playtime_10h",  name = "Dedicated",       icon = "\u{1F550}", category = "Playtime", counter = "playtime_total", threshold = 36000,  desc = "Play for a total of 10 hours." },
	{ key = "playtime_50h",  name = "No Life",         icon = "\u{1F570}", category = "Playtime", counter = "playtime_total", threshold = 180000, desc = "Play for a total of 50 hours." },
	{ key = "playtime_100h", name = "Touched Grass?",  icon = "\u{1F30D}", category = "Playtime", counter = "playtime_total", threshold = 360000, desc = "Play for a total of 100 hours across all sessions." },

	-- PvP Kills (3)
	{ key = "first_kill", name = "Blood on Your Hands", icon = "\u{1F5E1}", category = "PvP Kills", counter = "kills_pvp", threshold = 1,  desc = "Defeat another player in combat." },
	{ key = "kills_10",   name = "Dangerous",           icon = "\u{2694}",  category = "PvP Kills", counter = "kills_pvp", threshold = 10, desc = "Defeat 10 players in combat." },
	{ key = "kills_50",   name = "Warlord",             icon = "\u{1FA78}", category = "PvP Kills", counter = "kills_pvp", threshold = 50, desc = "Defeat 50 players. You are feared." },

	-- Trading (3)
	{ key = "first_trade", name = "Deal Maker",   icon = "\u{1F91D}", category = "Trading", counter = "trades_complete", threshold = 1,  desc = "Complete your first trade with another player." },
	{ key = "trades_10",   name = "Merchant",     icon = "\u{1F3EA}", category = "Trading", counter = "trades_complete", threshold = 10, desc = "Complete 10 trades with other players." },
	{ key = "trades_50",   name = "Trade Mogul",  icon = "\u{1F3E6}", category = "Trading", counter = "trades_complete", threshold = 50, desc = "Complete 50 trades. Master of the deal." },

	-- Harvesting (3)
	{ key = "first_harvest",  name = "Green Thumb",     icon = "\u{1F331}", category = "Harvesting", counter = "harvests_total", threshold = 1,   desc = "Harvest your first resource from the wild." },
	{ key = "harvests_100",   name = "Gatherer",        icon = "\u{1F9FA}", category = "Harvesting", counter = "harvests_total", threshold = 100, desc = "Harvest 100 resources from the wild." },
	{ key = "harvests_500",   name = "Master Gatherer", icon = "\u{1F33F}", category = "Harvesting", counter = "harvests_total", threshold = 500, desc = "Harvest 500 resources. The land provides." },

	-- Crafting (3)
	{ key = "first_craft", name = "Tinkerer",         icon = "\u{1F527}", category = "Crafting", counter = "crafts_total", threshold = 1,   desc = "Craft your first item by hand or at a station." },
	{ key = "crafts_50",   name = "Craftsman",        icon = "\u{2692}",  category = "Crafting", counter = "crafts_total", threshold = 50,  desc = "Craft 50 items total." },
	{ key = "crafts_200",  name = "Master Craftsman", icon = "\u{1F3D7}", category = "Crafting", counter = "crafts_total", threshold = 200, desc = "Craft 200 items. A true artisan." },

	-- Cooking (3)
	{ key = "first_cook", name = "Kitchen Duty", icon = "\u{1F373}", category = "Cooking", counter = "cooks_total", threshold = 1,   desc = "Cook your first meal at a campfire." },
	{ key = "cooks_50",   name = "Sous Chef",    icon = "\u{1F468}\u{200D}\u{1F373}", category = "Cooking", counter = "cooks_total", threshold = 50,  desc = "Cook 50 meals at campfires." },
	{ key = "cooks_200",  name = "Master Chef",  icon = "\u{1F9D1}\u{200D}\u{1F373}", category = "Cooking", counter = "cooks_total", threshold = 200, desc = "Cook 200 meals. The camp chef everyone relies on." },

	-- Wealth (3)
	{ key = "credits_1k",   name = "First Thousand", icon = "\u{1FA99}", category = "Wealth", counter = "credits_peak", threshold = 1000,   desc = "Hold 1,000 credits at one time." },
	{ key = "credits_10k",  name = "Money Bags",     icon = "\u{1F4B0}", category = "Wealth", counter = "credits_peak", threshold = 10000,  desc = "Hold 10,000 credits at one time." },
	{ key = "credits_100k", name = "The 1%",         icon = "\u{1F48E}", category = "Wealth", counter = "credits_peak", threshold = 100000, desc = "Hold 100,000 credits. The wealthiest survivor." },

	-- Login Streaks (3)
	{ key = "streak_3",  name = "Regular",          icon = "\u{1F4C6}", category = "Login Streaks", counter = "login_streak", threshold = 3,  desc = "Log in 3 days in a row." },
	{ key = "streak_7",  name = "Dedicated Player", icon = "\u{1F525}", category = "Login Streaks", counter = "login_streak", threshold = 7,  desc = "Log in 7 days in a row." },
	{ key = "streak_30", name = "Addicted",         icon = "\u{1F525}", category = "Login Streaks", counter = "login_streak", threshold = 30, desc = "Log in 30 days in a row. True dedication." },

	-- Tool Breaking (3)
	{ key = "tool_broken_1",  name = "Butterfingers",  icon = "\u{1F528}", category = "Tool Breaking", counter = "tools_broken", threshold = 1,  desc = "Break your first tool from overuse." },
	{ key = "tool_broken_10", name = "Tool Destroyer",  icon = "\u{1F4A5}", category = "Tool Breaking", counter = "tools_broken", threshold = 10, desc = "Break 10 tools. Try to be gentler." },
	{ key = "tool_broken_50", name = "The Breaker",     icon = "\u{1F525}", category = "Tool Breaking", counter = "tools_broken", threshold = 50, desc = "Break 50 tools. Nothing lasts in your hands." },

	-- Close Calls (3)
	{ key = "close_call_1",  name = "Living on the Edge", icon = "\u{1F630}", category = "Close Calls", counter = "close_calls", threshold = 1,  desc = "Survive with less than 5% of a vital stat." },
	{ key = "close_call_10", name = "Adrenaline Junkie",  icon = "\u{1F493}", category = "Close Calls", counter = "close_calls", threshold = 10, desc = "Have 10 near-death experiences." },
	{ key = "close_call_25", name = "Nine Lives",         icon = "\u{1F431}", category = "Close Calls", counter = "close_calls", threshold = 25, desc = "Cheat death 25 times. Luck or skill?" },

	-- Campfire Sessions (3)
	{ key = "campfire_1",  name = "Campfire Stories",   icon = "\u{1F3D5}", category = "Campfire", counter = "campfire_sessions", threshold = 1,  desc = "Sit at a campfire and rest." },
	{ key = "campfire_10", name = "Social Butterfly",   icon = "\u{1F98B}", category = "Campfire", counter = "campfire_sessions", threshold = 10, desc = "Sit at campfires 10 times." },
	{ key = "campfire_50", name = "Community Leader",   icon = "\u{1F465}", category = "Campfire", counter = "campfire_sessions", threshold = 50, desc = "Sit at campfires 50 times. The social heart of camp." },

	-- Food Spoilage (2)
	{ key = "spoilage_10",  name = "Bad Fridge",   icon = "\u{1F922}", category = "Spoilage", counter = "spoilage_lost", threshold = 10,  desc = "Let 10 food items spoil in your inventory." },
	{ key = "spoilage_100", name = "Food Waster",  icon = "\u{1F5D1}", category = "Spoilage", counter = "spoilage_lost", threshold = 100, desc = "Let 100 food items spoil. Wasteful." },

	-- Bedroll Community (2)
	{ key = "bedroll_community", name = "Good Neighbor",     icon = "\u{1F3D8}", category = "Bedroll", counter = "bedroll_near_others", threshold = 1,  desc = "Place a bedroll near another player's camp." },
	{ key = "bedroll_10",        name = "Settlement Founder", icon = "\u{1F3D7}", category = "Bedroll", counter = "bedroll_near_others", threshold = 10, desc = "Place bedrolls near other camps 10 times." },

	-- Item Consumption (2)
	{ key = "consume_50",  name = "Hungry Hungry",   icon = "\u{1F356}", category = "Consumption", counter = "items_consumed", threshold = 50,  desc = "Consume 50 food or drink items." },
	{ key = "consume_200", name = "Bottomless Pit",  icon = "\u{1F573}", category = "Consumption", counter = "items_consumed", threshold = 200, desc = "Consume 200 items. An insatiable appetite." },

	-- Hunting (3)
	{ key = "first_hunt",  name = "First Blood",     icon = "\u{1F3AF}", category = "Hunting", counter = "animals_killed",  threshold = 1,  desc = "Kill your first animal." },
	{ key = "hunter_10",   name = "Hunter",           icon = "\u{1F98C}", category = "Hunting", counter = "animals_killed",  threshold = 10, desc = "Kill 10 animals." },
	{ key = "hunter_50",   name = "Apex Predator",    icon = "\u{1F43A}", category = "Hunting", counter = "animals_killed",  threshold = 50, desc = "Kill 50 animals. Top of the food chain." },

	-- Butchering (2)
	{ key = "first_skin",   name = "Skinning 101",    icon = "\u{1FA93}", category = "Butchering", counter = "skins_total",    threshold = 1,  desc = "Skin your first animal carcass." },
	{ key = "butcher_25",   name = "Master Butcher",   icon = "\u{1F356}", category = "Butchering", counter = "butcher_total",  threshold = 25, desc = "Butcher 25 carcasses. Nothing goes to waste." },

	-- Ranged Combat (3)
	{ key = "first_bow_kill", name = "Marksman",       icon = "\u{1F3F9}", category = "Ranged", counter = "bow_kills",       threshold = 1,  desc = "Kill something with a bow for the first time." },
	{ key = "bow_kills_25",   name = "Sharpshooter",   icon = "\u{1F3AF}", category = "Ranged", counter = "bow_kills",       threshold = 25, desc = "Get 25 bow kills. A deadly aim." },
	{ key = "arrows_100",     name = "Quiver Full of Stories", icon = "\u{27B0}", category = "Ranged", counter = "arrows_fired", threshold = 100, desc = "Fire 100 arrows total." },

	-- Melee Combat (2)
	{ key = "first_spear_kill", name = "Stick 'Em",    icon = "\u{1F531}", category = "Melee", counter = "spear_kills",     threshold = 1,  desc = "Kill something with a spear." },
	{ key = "spear_kills_25",   name = "Phalanx",      icon = "\u{2694}",  category = "Melee", counter = "spear_kills",     threshold = 25, desc = "Get 25 spear kills. A true warrior." },
}

-- ── Build lookup tables ─────────────────────────────────────────────────

-- Achievements grouped by counter name for fast threshold checks
AchievementConfig.ByCounter = {}
for _, ach in ipairs(AchievementConfig.Achievements) do
	if not AchievementConfig.ByCounter[ach.counter] then
		AchievementConfig.ByCounter[ach.counter] = {}
	end
	table.insert(AchievementConfig.ByCounter[ach.counter], ach)
end

-- Achievement by key for quick lookups
AchievementConfig.ByKey = {}
for _, ach in ipairs(AchievementConfig.Achievements) do
	AchievementConfig.ByKey[ach.key] = ach
end

-- Total count
AchievementConfig.TotalCount = #AchievementConfig.Achievements

-- Ordered category list for UI filter bar
AchievementConfig.Categories = {
	"Deaths", "Death Causes", "Survival", "Playtime", "PvP Kills",
	"Hunting", "Butchering", "Ranged", "Melee",
	"Trading", "Harvesting", "Crafting", "Cooking", "Wealth",
	"Login Streaks", "Tool Breaking", "Close Calls", "Campfire",
	"Spoilage", "Bedroll", "Consumption",
}

-- ── Event-to-counter mappings ───────────────────────────────────────────
-- AchievementService registers an EventBridge.onFire hook and uses these
-- to auto-increment counters when game events fire.

AchievementConfig.EventMappings = {
	player_death = {
		{ counter = "deaths_total" },
		{ counter = "deaths_starvation",  condition = function(d) return d.cause == "starvation" end },
		{ counter = "deaths_dehydration", condition = function(d) return d.cause == "dehydration" end },
		{ counter = "deaths_poison",      condition = function(d) return d.cause == "poison" end },
		{ counter = "deaths_bleeding",    condition = function(d) return d.cause == "bleeding" end },
		{ counter = "deaths_pvp",         condition = function(d) return d.cause == "pvp" end },
		{ counter = "kills_pvp",  playerFrom = "killer", condition = function(d) return d.cause == "pvp" end },
		{ counter = "survival_best", mode = "max", valueFrom = function(d) return d.survivalSeconds or 0 end },
	},
	harvest_complete           = { { counter = "harvests_total" } },
	craft_complete             = { { counter = "crafts_total" } },
	cook_complete              = { { counter = "cooks_total" } },
	trade_complete             = { { counter = "trades_complete" } },
	item_consume               = { { counter = "items_consumed" } },
	tool_broken                = { { counter = "tools_broken" } },
	starvation_close_call      = { { counter = "close_calls" } },
	campfire_session           = { { counter = "campfire_sessions" } },
	spoilage_lost              = { { counter = "spoilage_lost", valueFrom = function(d) return d.totalSpoiled or 1 end } },
	bedroll_placed_near_others = { { counter = "bedroll_near_others" } },
	animal_killed              = { { counter = "animals_killed" } },
	animal_skinned             = { { counter = "skins_total" } },
	butcher_complete           = { { counter = "butcher_total" } },
	bow_kill                   = { { counter = "bow_kills" } },
	spear_kill                 = { { counter = "spear_kills" } },
	arrow_fired                = { { counter = "arrows_fired" } },
}

return AchievementConfig
