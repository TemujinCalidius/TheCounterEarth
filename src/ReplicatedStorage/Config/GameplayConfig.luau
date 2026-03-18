return {
	Energy = {
		Max = 100,
		SprintDrainPerSecond = 16,
		JumpCost = 10,
		RegenPerSecond = 14,
		RegenDelaySeconds = 0.75,
		MinToJump = 10,
	},
	Movement = {
		WalkSpeed = 16,
		SprintSpeed = 24,
		ExhaustedSpeed = 6,
		JumpPower = 80,
	},
	Health = {
		HeartbeatStartRatio = 0.4,
	},
	Credits = {
		DataStoreName = "PlayerProfileV2",
		StartingCredits = 0,
		UseDataStoreInStudio = true,
		AutoSaveSeconds = 60,
	},
	Audio = {
		BreathingMaxVolume = 0.9,
		BreathingMinSpeed = 0.9,
		BreathingMaxSpeed = 1.5,
		HeartbeatMaxVolume = 1,
		HeartbeatMinSpeed = 0.9,
		HeartbeatMaxSpeed = 1.8,
	},
	Hotbar = {
		Slots = 9,
	},

	Campfire = {
		SitRadius = 25,                -- studs: auto-sit detection range (matches bedroll placement range)
		IdleTimeToSit = 3,             -- seconds standing still before auto-sit
		HealthRegenPerSecond = 2,
		EnergyRegenPerSecond = 5,
		PlacementMaxRange = 20,        -- studs from player
		InactiveLifetimeSeconds = 600, -- 10 min with no player nearby → auto-delete
		DefaultCookSeconds = 4,        -- fallback if recipe omits cookSeconds
		MaxInputStack = 10,            -- max items in campfire input slot
		MaxOutputStack = 10,           -- max items in campfire output slot
		InteractRange = 25,            -- studs to open campfire UI
	},

	Bedroll = {
		RequiredCampfireRadius = 25,   -- must place within this range of a campfire
		KeepCampfireAliveRadius = 25,  -- bedroll↔campfire pairing range
		FatigueRegenPerSecond = 1.5,   -- fatigue restored while lying on bedroll
		InteractRange = 6,             -- studs to trigger lie-down prompt
	},

	LootBag = {
		InteractRange = 8,         -- studs: ProximityPrompt activation distance
		UICloseRange = 12,         -- studs: auto-close UI if player walks away
	},

	Avatar = {
		HipHeight = 2.6,
		JumpAnimHoldSeconds = 1.9,   -- suppress freefall state after jump (match jump animation length)
		HandBoneName = "mixamorig:RightHand",
		MeshPartName = "Base_Avatar",
	},

	Trading = {
		InteractRange = 15,            -- studs: ProximityPrompt range and max trade distance
		RequestTimeoutSeconds = 15,    -- pending request expires after this
	},

	Inventory = {
		-- Base carry weight with no backpack equipped (just pockets), in kg.
		BasePocketWeight = 5,

		-- Default inventory slot count with no backpack equipped (just pockets).
		PocketSlots = 5,

		-- Belt quick-slots: small items only (1x1), accessible without opening inventory.
		-- Separate from the 9-slot hotbar (which is drag-assigned, not physical slots).
		BeltSlots = 3,

		-- Weight limits per backpack tier (must match backpack ItemDef.backpack.maxWeight).
		-- Listed here for reference; the authoritative value is in ItemRegistry.
		BackpackWeightTiers = {
			[0] = 10,   -- Reed Satchel
			[1] = 30,   -- Leather Pack
		},

		-- How often (seconds) the server sweeps open containers for expired items.
		PerishSweepInterval = 60,

		-- Maximum weight of the loot bag dropped on death, in kg.
		-- Items are packed in descending weight order until this is reached;
		-- overflow stays in the world at reduced value (future: ragdoll scatter).
		DeathBagMaxWeight = 999, -- effectively no limit for now

		-- How long (seconds) a death loot bag persists before disappearing.
		DeathBagLifetimeSeconds = 300, -- 5 minutes

		-- Walk-speed penalty thresholds based on CarryWeight / MaxCarryWeight ratio.
		--   0 - SlowThreshold   -> full WalkSpeed
		--   SlowThreshold  - CrawlThreshold -> lerp down to ExhaustedSpeed
		--   CrawlThreshold - StopThreshold  -> lerp ExhaustedSpeed down to 0
		--   >= StopThreshold                -> WalkSpeed = 0 (cannot move)
		WeightPenalty = {
			SlowThreshold  = 0.8,  -- 80% of max weight
			CrawlThreshold = 1.0,  -- 100%
			StopThreshold  = 1.5,  -- 150%
		},
	},

	Tree = {
		Tier0NodeHealth       = 8,        -- hits to fell the standing tree
		Tier0HitCooldown      = 1.8,      -- seconds between chops
		Tier0CutPointHits     = 2,        -- hits per cut point on fallen trunk
		Tier0CutPoints        = 2,        -- number of cut points on trunk
		Tier0LogsPerTree      = 3,        -- total log segments (1 per first cut, 2 on final cut)
		FallDurationSeconds   = 2.0,
		FallDamage            = 20,
		FallDamageRadius      = 3,        -- studs from trunk center
		LogSegmentDespawnSecs = 600,      -- 10 min despawn for uncollected logs
		RespawnMinSeconds     = 3600,     -- 1 hour
		RespawnMaxSeconds     = 5400,     -- 1.5 hours
		MinTreeSpacing        = 12,       -- studs between trees
		TwigSpawnRadius       = 8,        -- studs: how close twigs spawn to trees
		MaxTier0Trees         = 8,        -- per server
	},

	EventBridge = {
		Enabled = true,
		EnableInStudio = false,
		EndpointUrl = "https://thecounterearth.com/api/game/events",
		FlushIntervalSeconds = 5,
		MaxBatchSize = 25,
		MaxQueueSize = 200,
		ImmediateEventTypes = {
			"player_death",
			"trade_complete",
			"player_join",
			"player_leave",
			"achievement_unlocked",
		},
	},
}
