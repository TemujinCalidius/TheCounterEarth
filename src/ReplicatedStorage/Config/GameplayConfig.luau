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
		JumpPower = 50,
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
			[0] = 12,   -- Cloth Satchel
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
}
