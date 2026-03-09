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
	-- Builds up over hours of play. Sleeping at a bedroll clears it.
	-- -------------------------------------------------------------------------
	Fatigue = {
		Max        = 100,
		StartValue = 100, -- players start fully rested

		-- Accumulates while the player is active (not resting)
		-- Target: fully fatigued after ~1 hour of continuous play
		DrainPerSecond = 100 / (60 * 60),

		-- Restores while resting (sleeping at bedroll near campfire)
		-- Target: fully restored in ~5 minutes of rest
		RestorePerSecond = 100 / (5 * 60),

		OnEmpty = {
			EnergyRegenMultiplier = 0.25,  -- energy regen 4× slower when exhausted
			SpeedMultiplier       = 0.85,  -- slight movement penalty
		},

		WarningThreshold = 20,
	},

	-- -------------------------------------------------------------------------
	-- Blood  (persistent bar, 100 → 0)
	--
	-- Drains while IsBleeding is true.  Slowly regenerates when not bleeding.
	-- Triggered by weapon hits / environmental hazards.
	--   Attribute "Blood"     (number 0-100)
	--   Attribute "IsBleeding"  (boolean — active wound)
	--
	-- Bleeding stops when:
	--   • Player uses a Bandage item  (clears IsBleeding immediately)
	--   • NaturalStopSeconds elapses  (wound clots on its own)
	-- Blood bar continues to regen once the wound is closed.
	-- -------------------------------------------------------------------------
	Blood = {
		Max        = 100,
		StartValue = 100,

		-- Blood lost per second per bleed stack while IsBleeding is active
		DrainPerSecond = 100 / (2 * 60),   -- per stack; 2 stacks = empty in ~1 min

		-- Blood recovered per second when NOT bleeding
		-- Requires hunger AND thirst above RegenMinStat to regen at full rate.
		-- Below that threshold, regen is halved. At 0 hunger or thirst, regen stops.
		RegenPerSecond = 100 / (5 * 60),   -- full recovery in ~5 minutes
		RegenMinStat   = 50,               -- hunger/thirst must be above this for full regen

		-- How long until one bleed stack clots on its own (per stack)
		NaturalStopSeconds = 120,

		-- What happens when blood reaches 0
		OnEmpty = {
			HealthDrainPerSecond = 3.0,    -- severe — no blood = dying fast
		},

		WarningThreshold = 30,
	},

	-- -------------------------------------------------------------------------
	-- Poison  (persistent bar, 0 → 100)
	--
	-- Fills while IsPoisoned is true.  Slowly decays when not being poisoned.
	--   Attribute "Poison"      (number 0-100)
	--   Attribute "IsPoisoned"  (boolean — actively being poisoned)
	--
	-- IsPoisoned clears when:
	--   • Player uses an Antidote item  (clears IsPoisoned immediately)
	--   • NaturalClearSeconds elapses
	-- Poison level still decays naturally after the source is removed.
	--
	-- Effects SCALE with the poison level:
	--   Health drain = (Poison / 100) * HealthDrainPerSecondAtMax
	-- -------------------------------------------------------------------------
	Poison = {
		Max        = 100,
		StartValue = 0,

		-- Poison accumulated per second while IsPoisoned is active
		FillPerSecond = 100 / (3 * 60),   -- reaches 100 in ~3 minutes

		-- Poison removed per second when NOT being poisoned
		DecayPerSecond = 100 / (4 * 60),  -- clears fully in ~4 minutes

		-- How long until IsPoisoned clears on its own
		NaturalClearSeconds = 180,

		-- Health drain at max poison (100).  Scales linearly with level.
		HealthDrainPerSecondAtMax = 2.0,

		-- Energy regen penalty while any poison is present (Poison > 0)
		EnergyRegenMultiplier = 0.5,

		WarningThreshold = 30,
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
		FatigueRestorePerSecond = 0,    -- campfire doesn't restore fatigue; need a bedroll
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

		Blood           = "Blood",
		MaxBlood        = "MaxBlood",
		IsBleeding      = "IsBleeding",
		BleedStacks     = "BleedStacks",
		BleedStartTime  = "BleedStartTime",
		Poison          = "Poison",
		MaxPoison       = "MaxPoison",
		IsPoisoned      = "IsPoisoned",
		PoisonStartTime = "PoisonStartTime",

		IsResting       = "IsResting",   -- true while sleeping on bedroll near campfire
	},
}
