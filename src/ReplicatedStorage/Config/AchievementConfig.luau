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
	{ key = "first_death",  name = "Welcome to the Wasteland", icon = "\u{1F480}", category = "Deaths",      counter = "deaths_total",       threshold = 1 },
	{ key = "deaths_10",    name = "Getting Used to It",       icon = "\u{2620}",  category = "Deaths",      counter = "deaths_total",       threshold = 10 },
	{ key = "deaths_50",    name = "Death Wish",               icon = "\u{1FAA6}", category = "Deaths",      counter = "deaths_total",       threshold = 50 },
	{ key = "deaths_100",   name = "Undying Spirit",           icon = "\u{1F47B}", category = "Deaths",      counter = "deaths_total",       threshold = 100 },

	-- Death Causes (5)
	{ key = "death_starvation",  name = "Empty Stomach",             icon = "\u{1F37D}",  category = "Death Causes", counter = "deaths_starvation",  threshold = 1 },
	{ key = "death_dehydration", name = "Parched",                   icon = "\u{1F3DC}",  category = "Death Causes", counter = "deaths_dehydration", threshold = 1 },
	{ key = "death_poison",      name = "Shouldn't Have Eaten That", icon = "\u{2620}",   category = "Death Causes", counter = "deaths_poison",      threshold = 1 },
	{ key = "death_bleeding",    name = "Flesh Wound",               icon = "\u{1FA78}",  category = "Death Causes", counter = "deaths_bleeding",    threshold = 1 },
	{ key = "death_pvp_5",       name = "Punching Bag",              icon = "\u{1F94A}",  category = "Death Causes", counter = "deaths_pvp",         threshold = 5 },

	-- Survival (4)
	{ key = "survive_5m",   name = "Baby Steps",          icon = "\u{1F423}", category = "Survival", counter = "survival_best", threshold = 300 },
	{ key = "survive_30m",  name = "Getting Comfortable", icon = "\u{1F6E1}", category = "Survival", counter = "survival_best", threshold = 1800 },
	{ key = "survive_1h",   name = "Survivor",            icon = "\u{2694}",  category = "Survival", counter = "survival_best", threshold = 3600 },
	{ key = "survive_3h",   name = "Wasteland Veteran",   icon = "\u{1F3C5}", category = "Survival", counter = "survival_best", threshold = 10800 },

	-- Playtime (4)
	{ key = "playtime_1h",   name = "Getting Started", icon = "\u{23F0}",  category = "Playtime", counter = "playtime_total", threshold = 3600 },
	{ key = "playtime_10h",  name = "Dedicated",       icon = "\u{1F550}", category = "Playtime", counter = "playtime_total", threshold = 36000 },
	{ key = "playtime_50h",  name = "No Life",         icon = "\u{1F570}", category = "Playtime", counter = "playtime_total", threshold = 180000 },
	{ key = "playtime_100h", name = "Touched Grass?",  icon = "\u{1F30D}", category = "Playtime", counter = "playtime_total", threshold = 360000 },

	-- PvP Kills (3)
	{ key = "first_kill", name = "Blood on Your Hands", icon = "\u{1F5E1}", category = "PvP Kills", counter = "kills_pvp", threshold = 1 },
	{ key = "kills_10",   name = "Dangerous",           icon = "\u{2694}",  category = "PvP Kills", counter = "kills_pvp", threshold = 10 },
	{ key = "kills_50",   name = "Warlord",             icon = "\u{1FA78}", category = "PvP Kills", counter = "kills_pvp", threshold = 50 },

	-- Trading (3)
	{ key = "first_trade", name = "Deal Maker",   icon = "\u{1F91D}", category = "Trading", counter = "trades_complete", threshold = 1 },
	{ key = "trades_10",   name = "Merchant",     icon = "\u{1F3EA}", category = "Trading", counter = "trades_complete", threshold = 10 },
	{ key = "trades_50",   name = "Trade Mogul",  icon = "\u{1F3E6}", category = "Trading", counter = "trades_complete", threshold = 50 },

	-- Harvesting (3)
	{ key = "first_harvest",  name = "Green Thumb",     icon = "\u{1F331}", category = "Harvesting", counter = "harvests_total", threshold = 1 },
	{ key = "harvests_100",   name = "Gatherer",        icon = "\u{1F9FA}", category = "Harvesting", counter = "harvests_total", threshold = 100 },
	{ key = "harvests_500",   name = "Master Gatherer", icon = "\u{1F33F}", category = "Harvesting", counter = "harvests_total", threshold = 500 },

	-- Crafting (3)
	{ key = "first_craft", name = "Tinkerer",         icon = "\u{1F527}", category = "Crafting", counter = "crafts_total", threshold = 1 },
	{ key = "crafts_50",   name = "Craftsman",        icon = "\u{2692}",  category = "Crafting", counter = "crafts_total", threshold = 50 },
	{ key = "crafts_200",  name = "Master Craftsman", icon = "\u{1F3D7}", category = "Crafting", counter = "crafts_total", threshold = 200 },

	-- Cooking (3)
	{ key = "first_cook", name = "Kitchen Duty", icon = "\u{1F373}", category = "Cooking", counter = "cooks_total", threshold = 1 },
	{ key = "cooks_50",   name = "Sous Chef",    icon = "\u{1F468}\u{200D}\u{1F373}", category = "Cooking", counter = "cooks_total", threshold = 50 },
	{ key = "cooks_200",  name = "Master Chef",  icon = "\u{1F9D1}\u{200D}\u{1F373}", category = "Cooking", counter = "cooks_total", threshold = 200 },

	-- Wealth (3)
	{ key = "credits_1k",   name = "First Thousand", icon = "\u{1FA99}", category = "Wealth", counter = "credits_peak", threshold = 1000 },
	{ key = "credits_10k",  name = "Money Bags",     icon = "\u{1F4B0}", category = "Wealth", counter = "credits_peak", threshold = 10000 },
	{ key = "credits_100k", name = "The 1%",         icon = "\u{1F48E}", category = "Wealth", counter = "credits_peak", threshold = 100000 },

	-- Login Streaks (3)
	{ key = "streak_3",  name = "Regular",          icon = "\u{1F4C6}", category = "Login Streaks", counter = "login_streak", threshold = 3 },
	{ key = "streak_7",  name = "Dedicated Player", icon = "\u{1F525}", category = "Login Streaks", counter = "login_streak", threshold = 7 },
	{ key = "streak_30", name = "Addicted",         icon = "\u{1F525}", category = "Login Streaks", counter = "login_streak", threshold = 30 },

	-- Tool Breaking (3)
	{ key = "tool_broken_1",  name = "Butterfingers",  icon = "\u{1F528}", category = "Tool Breaking", counter = "tools_broken", threshold = 1 },
	{ key = "tool_broken_10", name = "Tool Destroyer",  icon = "\u{1F4A5}", category = "Tool Breaking", counter = "tools_broken", threshold = 10 },
	{ key = "tool_broken_50", name = "The Breaker",     icon = "\u{1F525}", category = "Tool Breaking", counter = "tools_broken", threshold = 50 },

	-- Close Calls (3)
	{ key = "close_call_1",  name = "Living on the Edge", icon = "\u{1F630}", category = "Close Calls", counter = "close_calls", threshold = 1 },
	{ key = "close_call_10", name = "Adrenaline Junkie",  icon = "\u{1F493}", category = "Close Calls", counter = "close_calls", threshold = 10 },
	{ key = "close_call_25", name = "Nine Lives",         icon = "\u{1F431}", category = "Close Calls", counter = "close_calls", threshold = 25 },

	-- Campfire Sessions (3)
	{ key = "campfire_1",  name = "Campfire Stories",   icon = "\u{1F3D5}", category = "Campfire", counter = "campfire_sessions", threshold = 1 },
	{ key = "campfire_10", name = "Social Butterfly",   icon = "\u{1F98B}", category = "Campfire", counter = "campfire_sessions", threshold = 10 },
	{ key = "campfire_50", name = "Community Leader",   icon = "\u{1F465}", category = "Campfire", counter = "campfire_sessions", threshold = 50 },

	-- Food Spoilage (2)
	{ key = "spoilage_10",  name = "Bad Fridge",   icon = "\u{1F922}", category = "Spoilage", counter = "spoilage_lost", threshold = 10 },
	{ key = "spoilage_100", name = "Food Waster",  icon = "\u{1F5D1}", category = "Spoilage", counter = "spoilage_lost", threshold = 100 },

	-- Bedroll Community (2)
	{ key = "bedroll_community", name = "Good Neighbor",     icon = "\u{1F3D8}", category = "Bedroll", counter = "bedroll_near_others", threshold = 1 },
	{ key = "bedroll_10",        name = "Settlement Founder", icon = "\u{1F3D7}", category = "Bedroll", counter = "bedroll_near_others", threshold = 10 },

	-- Item Consumption (2)
	{ key = "consume_50",  name = "Hungry Hungry",   icon = "\u{1F356}", category = "Consumption", counter = "items_consumed", threshold = 50 },
	{ key = "consume_200", name = "Bottomless Pit",  icon = "\u{1F573}", category = "Consumption", counter = "items_consumed", threshold = 200 },
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
}

return AchievementConfig
