-- StatsConfig.luau
-- Configuration for all survival stats beyond Health and Energy.
--
-- Drain/restore rates are per-second unless stated otherwise.
-- All stat values are on a 0–100 scale.
--
-- STAT TYPES
--   Persistent bars — Hunger, Thirst, Fatigue
--     These are saved to DataStore and tick while the server is running.
--   Status effects  — Bleeding, Poison
--     These are active debuffs with a start timestamp; they resolve over
--     time or when treated. Not full bars — stored as boolean + timestamp.

return {

	-- -------------------------------------------------------------------------
	-- Hunger
	-- -------------------------------------------------------------------------
	Hunger = {
		Max         = 100,
		StartValue  = 80,

		-- Passive drain while alive (target: empty over ~30 real minutes)
		DrainPerSecond = 100 / (30 * 60),

		-- Extra drain per second while sprinting
		SprintExtraDrainPerSecond = 100 / (90 * 60),

		-- Effects when the bar hits 0
		OnEmpty = {
			HealthDrainPerSecond = 0.5,
		},

		-- HUD warning colour kicks in below this value
		WarningThreshold = 20,
	},

	-- -------------------------------------------------------------------------
	-- Thirst
	-- -------------------------------------------------------------------------
	Thirst = {
		Max        = 100,
		StartValue = 80,

		-- Drains faster than hunger (target: empty over ~20 real minutes)
		DrainPerSecond = 100 / (20 * 60),

		SprintExtraDrainPerSecond = 100 / (45 * 60),

		OnEmpty = {
			EnergyRegenDisabled   = true,   -- energy stops regenerating
			HealthDrainPerSecond  = 1.0,    -- dehydration is more dangerous than starvation
		},

		WarningThreshold = 20,
	},

	-- -------------------------------------------------------------------------
	-- Fatigue  (long-term tiredness — separate from short-term Energy)
	-- Builds up over hours of play. Sleeping at a bedroll or campfire clears it.
	-- -------------------------------------------------------------------------
	Fatigue = {
		Max        = 100,
		StartValue = 100, -- players start fully rested

		-- Accumulates while the player is active (not resting)
		-- Target: fully fatigued after ~1 hour of continuous play
		DrainPerSecond = 100 / (60 * 60),

		-- Restores while resting (sleeping at campfire/bedroll)
		-- Target: fully restored in ~5 minutes of rest
		RestorePerSecond = 100 / (5 * 60),

		OnEmpty = {
			EnergyRegenMultiplier = 0.25,  -- energy regen 4× slower when exhausted
			SpeedMultiplier       = 0.85,  -- slight movement penalty
		},

		WarningThreshold = 20,
	},

	-- -------------------------------------------------------------------------
	-- Bleeding  (status effect — NOT a persistent bar)
	--
	-- Triggered by certain weapon hits. Stored as:
	--   player attribute "IsBleeding"     (boolean)
	--   player attribute "BleedStartTime" (os.time() timestamp)
	--
	-- Stops when:
	--   • Player uses a Bandage item  (immediate)
	--   • NaturalStopSeconds elapses  (slow natural clot)
	-- -------------------------------------------------------------------------
	Bleeding = {
		HealthDrainPerSecond = 2.0,

		-- How long until bleeding stops on its own without treatment
		NaturalStopSeconds = 120,
	},

	-- -------------------------------------------------------------------------
	-- Poison  (status effect — NOT a persistent bar)
	--
	-- Stored as:
	--   player attribute "IsPoisoned"      (boolean)
	--   player attribute "PoisonStartTime" (os.time() timestamp)
	--
	-- Weakens over time (damage falls off). Clears with Antidote or after
	-- NaturalClearSeconds.
	-- -------------------------------------------------------------------------
	Poison = {
		-- Starting health drain per second (reduces as poison weakens)
		HealthDrainPerSecond = 1.0,

		-- Poison potency decays at this rate per second (multiplicative)
		-- e.g. 0.02 → after 50 s the drain is ~37% of original
		DecayRate = 0.02,

		-- Clears entirely without antidote after this long
		NaturalClearSeconds = 180,

		-- Energy regen penalty while poisoned
		EnergyRegenMultiplier = 0.5,
	},

	-- -------------------------------------------------------------------------
	-- Campfire rest bonuses
	-- (applied while the player is standing within campfire range)
	-- -------------------------------------------------------------------------
	CampfireRest = {
		-- Radius in studs the player must be within
		Radius = 12,

		HealthRestorePerSecond  = 0.5,
		HungerRestorePerSecond  = 0,    -- campfire doesn't feed you; cook food for that
		ThirstRestorePerSecond  = 0,    -- campfire doesn't hydrate you
		FatigueRestorePerSecond = 100 / (8 * 60), -- resting at fire restores fatigue in ~8 min
		EnergyCooldownReduction = true, -- energy regen delay is halved near a fire
	},

	-- -------------------------------------------------------------------------
	-- Player attribute names
	-- Centralised so server and client always agree on the key strings.
	-- -------------------------------------------------------------------------
	AttributeNames = {
		Hunger          = "Hunger",
		MaxHunger       = "MaxHunger",
		Thirst          = "Thirst",
		MaxThirst       = "MaxThirst",
		Fatigue         = "Fatigue",
		MaxFatigue      = "MaxFatigue",

		IsBleeding      = "IsBleeding",
		BleedStartTime  = "BleedStartTime",
		IsPoisoned      = "IsPoisoned",
		PoisonStartTime = "PoisonStartTime",

		IsResting       = "IsResting",   -- true while near campfire / on bedroll
	},
}
