local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local StatsConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StatsConfig"))

local ItemRegistry = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))

local PROFILE_VERSION = 5
local LEGACY_CREDITS_STORE_NAME = "CreditsV1"

local useDataStore = (not RunService:IsStudio()) or Config.Credits.UseDataStoreInStudio
local autoSaveSeconds = math.max(15, tonumber(Config.Credits.AutoSaveSeconds) or 60)
local hotbarSlotCount = math.clamp(math.floor(tonumber(Config.Hotbar and Config.Hotbar.Slots) or 9), 1, 9)

local profileStore: GlobalDataStore? = nil
local legacyCreditsStore: GlobalDataStore? = nil

if useDataStore then
	profileStore = DataStoreService:GetDataStore(Config.Credits.DataStoreName)
	if Config.Credits.DataStoreName ~= LEGACY_CREDITS_STORE_NAME then
		legacyCreditsStore = DataStoreService:GetDataStore(LEGACY_CREDITS_STORE_NAME)
	end
end

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if remotesFolder and not remotesFolder:IsA("Folder") then
	remotesFolder:Destroy()
	remotesFolder = nil
end

if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local function ensureRemoteEvent(name: string): RemoteEvent
	local remote = remotesFolder:FindFirstChild(name)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end

	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotesFolder
	end

	return remote :: RemoteEvent
end

local sprintIntentRemote = ensureRemoteEvent("SprintIntent")
ensureRemoteEvent("HotbarEquipRequest")
ensureRemoteEvent("HotbarAttackRequest")

-- ── Server bindables (InventoryService fires consume effects here) ─────────
local bindablesFolder = ServerStorage:FindFirstChild("ServerBindables")
if not bindablesFolder then
	bindablesFolder = Instance.new("Folder")
	bindablesFolder.Name = "ServerBindables"
	bindablesFolder.Parent = ServerStorage
end

local consumeEffectEvent = Instance.new("BindableEvent")
consumeEffectEvent.Name = "ConsumeEffect"
consumeEffectEvent.Parent = bindablesFolder

local applyStatusEvent = Instance.new("BindableEvent")
applyStatusEvent.Name = "ApplyStatusEffect"
applyStatusEvent.Parent = bindablesFolder

type PlayerState = {
	energy: number,
	savedHealth: number,
	sprintRequested: boolean,
	lastEnergyUseTime: number,
	lastJumpDrainTime: number,
	humanoid: Humanoid?,
	currentWalkSpeed: number,
	jumpEnabled: boolean,
	charConnections: { RBXScriptConnection },
	playerConnections: { RBXScriptConnection },
	profileDirty: boolean,
	lastSaveTime: number,
	-- Survival stats
	hunger: number,
	thirst: number,
	fatigue: number,
	blood: number,
	poison: number,
	bleedStacks: number,       -- number of active bleed wounds (0 = not bleeding)
	bleedStartTime: number?,   -- os.time() when most recent stack was added; nil = not bleeding
	poisonStartTime: number?,  -- os.time() when poisoned started; nil = not poisoned
	campfireIdleTime: number,  -- seconds standing still (resets on movement)
	sittingAtCampfire: boolean, -- true while auto-sitting near a campfire
	bedrollSpawnCFrame: CFrame?,   -- CFrame of player's bedroll (set on placement, cleared on destroy)
	deathRespawnCFrame: CFrame?,   -- snapshot of bedrollSpawnCFrame at time of death
	lastPosition: { x: number, y: number, z: number }?,  -- saved logout position for relog teleport
}

local playerStates: { [Player]: PlayerState } = {}

-- ── Campfire config ─────────────────────────────────────────────────────────
local CAMPFIRE_SIT_RADIUS      = (Config.Campfire and Config.Campfire.SitRadius) or 10
local CAMPFIRE_IDLE_TO_SIT     = (Config.Campfire and Config.Campfire.IdleTimeToSit) or 3
local CAMPFIRE_HEALTH_REGEN    = (Config.Campfire and Config.Campfire.HealthRegenPerSecond) or 2
local CAMPFIRE_ENERGY_REGEN    = (Config.Campfire and Config.Campfire.EnergyRegenPerSecond) or 5
local CAMPFIRE_INACTIVE_LIFE   = (Config.Campfire and Config.Campfire.InactiveLifetimeSeconds) or 600

local function isNearPlacedCampfire(position: Vector3): boolean
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Model") and obj:GetAttribute("_PlacedItem") then
			local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
			if primary and (primary.Position - position).Magnitude <= CAMPFIRE_SIT_RADIUS then
				return true
			end
		end
	end
	return false
end

local function round1(value: number): number
	return math.round(value * 10) / 10
end

local function clampEnergy(value: number): number
	return math.clamp(value, 0, Config.Energy.Max)
end

local function clampHealthForStorage(value: number): number
	return math.max(0, value)
end

local function getProfileKey(userId: number): string
	return string.format("player_%d", userId)
end

local function getLegacyCreditsKey(userId: number): string
	return string.format("credits_%d", userId)
end

local function slotAttributeName(slot: number): string
	return "HotbarSlot" .. tostring(slot)
end

local function sanitizeItemId(value: any): string
	if type(value) ~= "string" then
		return ""
	end

	local normalized = string.sub(value, 1, 40)
	if normalized == "" then
		return ""
	end

	if not normalized:match("^[%w_%-%s]+$") then
		return ""
	end

	return normalized
end

-- Maps old item IDs to new ones for DataStore migration.
-- Add entries here when renaming items; old saves will load with the new ID.
local ITEM_RENAMES: { [string]: string } = {
	pebble        = "rock",
	fiber         = "reed",
	twig_axe      = "stone_axe",
	twig_knife    = "stone_knife",
	satchel_cloth = "satchel_reed",
	raw_fish      = "spoiled_food",
	cooked_fish   = "spoiled_food",
	raw_meat      = "spoiled_food",
	cooked_meat   = "spoiled_food",
}

local function migrateItemId(id: string): string
	return ITEM_RENAMES[id] or id
end

local function emptyInventory(): { slots: { string }, equippedSlot: number }
	local slots = table.create(hotbarSlotCount)
	for slot = 1, hotbarSlotCount do
		slots[slot] = ""
	end

	return {
		slots = slots,
		equippedSlot = 0,
	}
end

local function decodeInventory(raw: any): { slots: { string }, equippedSlot: number }
	local inventory = emptyInventory()
	if type(raw) ~= "table" then
		return inventory
	end

	local slotsRaw = raw.slots
	if type(raw.Slots) == "table" then
		slotsRaw = raw.Slots
	end

	if type(slotsRaw) == "table" then
		for slot = 1, hotbarSlotCount do
			local value = slotsRaw[slot]
			if value == nil then
				value = slotsRaw[tostring(slot)]
			end
			inventory.slots[slot] = migrateItemId(sanitizeItemId(value))
		end
	end

	local equippedSlotRaw = raw.equippedSlot
	if raw.EquippedSlot ~= nil then
		equippedSlotRaw = raw.EquippedSlot
	end

	local equippedSlot = math.floor(tonumber(equippedSlotRaw) or 0)
	if equippedSlot < 1 or equippedSlot > hotbarSlotCount or inventory.slots[equippedSlot] == "" then
		equippedSlot = 0
	end
	inventory.equippedSlot = equippedSlot

	return inventory
end

local function writeInventoryAttributes(player: Player, inventory: { slots: { string }, equippedSlot: number })
	for slot = 1, hotbarSlotCount do
		player:SetAttribute(slotAttributeName(slot), inventory.slots[slot] or "")
	end
	player:SetAttribute("HotbarEquippedSlot", inventory.equippedSlot)
end

local function readInventoryFromPlayer(player: Player): { slots: { string }, equippedSlot: number }
	local inventory = emptyInventory()

	for slot = 1, hotbarSlotCount do
		local value = player:GetAttribute(slotAttributeName(slot))
		inventory.slots[slot] = sanitizeItemId(value)
	end

	local equippedSlot = math.floor(tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0)
	if equippedSlot < 1 or equippedSlot > hotbarSlotCount or inventory.slots[equippedSlot] == "" then
		equippedSlot = 0
	end
	inventory.equippedSlot = equippedSlot

	return inventory
end

local function makeDefaultProfile(): { [string]: any }
	return {
		version = PROFILE_VERSION,
		credits = Config.Credits.StartingCredits,
		survival = {
			Energy  = Config.Energy.Max,
			Health  = 100,
			Hunger  = StatsConfig.Hunger.StartValue,
			Thirst  = StatsConfig.Thirst.StartValue,
			Fatigue = StatsConfig.Fatigue.StartValue,
			Blood   = StatsConfig.Blood.StartValue,
			Poison  = StatsConfig.Poison.StartValue,
			IsBleeding = false,
			BleedStacks = 0,
			IsPoisoned = false,
		},
		inventory = emptyInventory(),
		invSlots = {},
	}
end

-- Parses invSlots from saved data, migrating from the old items dict if needed.
local function decodeInvSlots(raw: any): { { itemId: string, qty: number, expiries: { number }?, durabilities: { number }? } }
	local result: { { itemId: string, qty: number, expiries: { number }?, durabilities: { number }? } } = {}
	if type(raw) ~= "table" then return result end

	if type(raw.invSlots) == "table" then
		for _, entry in ipairs(raw.invSlots) do
			if type(entry) == "table"
				and type(entry.itemId) == "string"
				and type(entry.qty) == "number"
			then
				local clean = migrateItemId(sanitizeItemId(entry.itemId))
				if clean ~= "" and entry.qty > 0 then
					local qty = math.floor(entry.qty + 0.5)
					local expiries: { number }? = nil
					if type(entry.expiries) == "table" then
						expiries = {}
						for _, ts in ipairs(entry.expiries) do
							if type(ts) == "number" then
								table.insert(expiries, ts)
							end
						end
						table.sort(expiries)
						if #expiries == 0 then expiries = nil end
					end
					local durabilities: { number }? = nil
					if type(entry.durabilities) == "table" then
						durabilities = {}
						for _, d in ipairs(entry.durabilities) do
							if type(d) == "number" then
								table.insert(durabilities, math.floor(d))
							end
						end
						if #durabilities == 0 then durabilities = nil end
					end
					-- Migration: tools with durabilityMax but no saved durabilities get max
					if not durabilities then
						local def = ItemRegistry.get(clean)
						if def and def.durabilityMax then
							durabilities = {}
							for _ = 1, qty do
								table.insert(durabilities, def.durabilityMax)
							end
						end
					end
					table.insert(result, { itemId = clean, qty = qty, expiries = expiries, durabilities = durabilities })
				end
			end
		end
	elseif type(raw.items) == "table" then
		-- Migrate old Inv_<itemId> dict format.
		for itemId, qty in pairs(raw.items) do
			if type(itemId) == "string" and type(qty) == "number" and qty > 0 then
				local clean = migrateItemId(sanitizeItemId(itemId))
				if clean ~= "" then
					local floorQty = math.floor(qty + 0.5)
					local durabilities: { number }? = nil
					local def = ItemRegistry.get(clean)
					if def and def.durabilityMax then
						durabilities = {}
						for _ = 1, floorQty do
							table.insert(durabilities, def.durabilityMax)
						end
					end
					table.insert(result, { itemId = clean, qty = floorQty, durabilities = durabilities })
				end
			end
		end
	end

	return result
end

local function decodeProfile(raw: any): { [string]: any }?
	if type(raw) ~= "table" then
		return nil
	end

	local credits = tonumber(raw.credits)
	if type(raw.Credits) == "number" then
		credits = raw.Credits
	end
	if type(credits) ~= "number" then
		return nil
	end

	local survivalRaw = raw.survival
	if type(raw.Survival) == "table" then
		survivalRaw = raw.Survival
	end
	if type(survivalRaw) ~= "table" then
		survivalRaw = {}
	end

	local energy = tonumber(survivalRaw.Energy)
	if type(survivalRaw.energy) == "number" then
		energy = survivalRaw.energy
	end

	local health = tonumber(survivalRaw.Health)
	if type(survivalRaw.health) == "number" then
		health = survivalRaw.health
	end

	if type(energy) ~= "number" then energy = Config.Energy.Max end
	if type(health) ~= "number" then health = 100 end

	local hunger  = tonumber(survivalRaw.Hunger)  or tonumber(survivalRaw.hunger)
	local thirst  = tonumber(survivalRaw.Thirst)  or tonumber(survivalRaw.thirst)
	local fatigue = tonumber(survivalRaw.Fatigue) or tonumber(survivalRaw.fatigue)
	local blood   = tonumber(survivalRaw.Blood)   or tonumber(survivalRaw.blood)
	local poison  = tonumber(survivalRaw.Poison)  or tonumber(survivalRaw.poison)
	if type(hunger)  ~= "number" then hunger  = StatsConfig.Hunger.StartValue  end
	if type(thirst)  ~= "number" then thirst  = StatsConfig.Thirst.StartValue  end
	if type(fatigue) ~= "number" then fatigue = StatsConfig.Fatigue.StartValue end
	if type(blood)   ~= "number" then blood   = StatsConfig.Blood.StartValue   end
	if type(poison)  ~= "number" then poison  = StatsConfig.Poison.StartValue  end

	local wasBleeding   = survivalRaw.IsBleeding == true
	local savedStacks   = math.max(0, math.floor(tonumber(survivalRaw.BleedStacks) or (wasBleeding and 1 or 0)))
	local wasPoisoned   = survivalRaw.IsPoisoned == true

	local inventoryRaw = raw.inventory
	if type(raw.Inventory) == "table" then
		inventoryRaw = raw.Inventory
	end

	local lastPosition: { x: number, y: number, z: number }? = nil
	if type(raw.lastPosition) == "table" then
		local lp = raw.lastPosition
		if type(lp.x) == "number" and type(lp.y) == "number" and type(lp.z) == "number" then
			lastPosition = { x = lp.x, y = lp.y, z = lp.z }
		end
	end

	return {
		version = tonumber(raw.version) or tonumber(raw.Version) or PROFILE_VERSION,
		credits = math.floor(credits + 0.5),
		survival = {
			Energy  = clampEnergy(energy),
			Health  = clampHealthForStorage(health),
			Hunger  = math.clamp(hunger,  0, StatsConfig.Hunger.Max),
			Thirst  = math.clamp(thirst,  0, StatsConfig.Thirst.Max),
			Fatigue = math.clamp(fatigue, 0, StatsConfig.Fatigue.Max),
			Blood   = math.clamp(blood,   0, StatsConfig.Blood.Max),
			Poison  = math.clamp(poison,  0, StatsConfig.Poison.Max),
			IsBleeding = wasBleeding,
			BleedStacks = savedStacks,
			IsPoisoned = wasPoisoned,
		},
		inventory = decodeInventory(inventoryRaw),
		invSlots  = decodeInvSlots(raw),
		lastPosition = lastPosition,
	}
end

local function getLegacyCredits(userId: number): number?
	local oldKey = getLegacyCreditsKey(userId)

	if profileStore then
		local okSame, oldSame = pcall(function()
			return profileStore:GetAsync(oldKey)
		end)
		if okSame and type(oldSame) == "number" then
			return oldSame
		end
		if not okSame then
			warn(string.format("Failed to read legacy credits key for %d: %s", userId, tostring(oldSame)))
		end
	end

	if legacyCreditsStore then
		local okLegacy, oldLegacy = pcall(function()
			return legacyCreditsStore:GetAsync(oldKey)
		end)
		if okLegacy and type(oldLegacy) == "number" then
			return oldLegacy
		end
		if not okLegacy then
			warn(string.format("Failed to read legacy credits store for %d: %s", userId, tostring(oldLegacy)))
		end
	end

	return nil
end

local function loadProfile(userId: number): { [string]: any }
	local profile = makeDefaultProfile()

	if not profileStore then
		return profile
	end

	local key = getProfileKey(userId)
	local success, result = pcall(function()
		return profileStore:GetAsync(key)
	end)

	if not success then
		warn(string.format("Failed to load profile for %d: %s", userId, tostring(result)))
		return profile
	end

	local decoded = decodeProfile(result)
	if decoded then
		return decoded
	end

	if type(result) == "number" then
		profile.credits = math.floor(result + 0.5)
		return profile
	end

	local legacyCredits = getLegacyCredits(userId)
	if type(legacyCredits) == "number" then
		profile.credits = math.floor(legacyCredits + 0.5)
	end

	return profile
end

local function clearCharacterConnections(state: PlayerState)
	for _, connection in ipairs(state.charConnections) do
		connection:Disconnect()
	end
	table.clear(state.charConnections)
end

local function clearPlayerConnections(state: PlayerState)
	for _, connection in ipairs(state.playerConnections) do
		connection:Disconnect()
	end
	table.clear(state.playerConnections)
end

local function updateLeaderstatsCredits(player: Player, credits: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	local creditsStat = leaderstats:FindFirstChild("Credits")
	if creditsStat and creditsStat:IsA("IntValue") then
		creditsStat.Value = math.floor(credits)
	end
end

local function setWalkSpeed(state: PlayerState, speed: number)
	local humanoid = state.humanoid
	if not humanoid then
		return
	end

	if state.currentWalkSpeed ~= speed or humanoid.WalkSpeed ~= speed then
		state.currentWalkSpeed = speed
		humanoid.WalkSpeed = speed
	end
end

-- Returns a 0–1 multiplier based on how overloaded the player is.
local function computeWeightSpeedMult(player: Player): number
	local carryWeight    = tonumber(player:GetAttribute("CarryWeight"))    or 0
	local maxCarryWeight = tonumber(player:GetAttribute("MaxCarryWeight")) or 8
	if maxCarryWeight <= 0 then return 1 end

	local ratio = carryWeight / maxCarryWeight
	local WP    = Config.Inventory and Config.Inventory.WeightPenalty
	if not WP then return 1 end

	if ratio >= WP.StopThreshold then
		return 0
	elseif ratio >= WP.CrawlThreshold then
		-- ExhaustedSpeed down to 0 between CrawlThreshold and StopThreshold
		local t = (ratio - WP.CrawlThreshold) / (WP.StopThreshold - WP.CrawlThreshold)
		local crawlMult = Config.Movement.ExhaustedSpeed / Config.Movement.WalkSpeed
		return math.max(0, crawlMult * (1 - t))
	elseif ratio >= WP.SlowThreshold then
		-- Full speed down to ExhaustedSpeed between SlowThreshold and CrawlThreshold
		local t = (ratio - WP.SlowThreshold) / (WP.CrawlThreshold - WP.SlowThreshold)
		local crawlMult = Config.Movement.ExhaustedSpeed / Config.Movement.WalkSpeed
		return 1 - t * (1 - crawlMult)
	end
	return 1
end

local function setJumpEnabled(state: PlayerState, enabled: boolean)
	local humanoid = state.humanoid
	if not humanoid then
		return
	end

	local desiredJumpPower = enabled and Config.Movement.JumpPower or 0
	if state.jumpEnabled ~= enabled or humanoid.JumpPower ~= desiredJumpPower then
		state.jumpEnabled = enabled
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
		humanoid.UseJumpPower = true
		humanoid.JumpPower = desiredJumpPower
		if not enabled and humanoid.Jump then
			humanoid.Jump = false
		end
	end
end

local function setSurvivalStat(player: Player, state: PlayerState, field: string, attrName: string, newValue: number, max: number)
	local clamped = math.clamp(newValue, 0, max)
	local s: any = state
	local prev = s[field]
	s[field] = clamped  -- always accumulate (small per-frame deltas must not be lost)
	if math.abs(prev - clamped) > 0.01 then
		state.profileDirty = true
	end
	local rounded = round1(clamped)
	if player:GetAttribute(attrName) ~= rounded then
		player:SetAttribute(attrName, rounded)
	end
end

local function setHunger(player: Player, state: PlayerState, value: number)
	setSurvivalStat(player, state, "hunger", StatsConfig.AttributeNames.Hunger, value, StatsConfig.Hunger.Max)
end

local function setThirst(player: Player, state: PlayerState, value: number)
	setSurvivalStat(player, state, "thirst", StatsConfig.AttributeNames.Thirst, value, StatsConfig.Thirst.Max)
end

local function setFatigue(player: Player, state: PlayerState, value: number)
	setSurvivalStat(player, state, "fatigue", StatsConfig.AttributeNames.Fatigue, value, StatsConfig.Fatigue.Max)
end

local function setBlood(player: Player, state: PlayerState, value: number)
	setSurvivalStat(player, state, "blood", StatsConfig.AttributeNames.Blood, value, StatsConfig.Blood.Max)
end

local function setPoison(player: Player, state: PlayerState, value: number)
	setSurvivalStat(player, state, "poison", StatsConfig.AttributeNames.Poison, value, StatsConfig.Poison.Max)
end

-- ── Particle effects (server-side so all players can see them) ───────────

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function attachBleedEffect(player: Player)
	local root = getCharacterRoot(player)
	if not root or root:FindFirstChild("BleedEffect") then return end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "BleedEffect"
	emitter.Texture = "rbxassetid://88336007519071"  -- BloodIcon
	emitter.Color = ColorSequence.new(Color3.fromRGB(180, 20, 20))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Rate = 8
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Acceleration = Vector3.new(0, -8, 0)
	emitter.RotSpeed = NumberRange.new(-30, 30)
	emitter.Parent = root
end

local function removeBleedEffect(player: Player)
	local root = getCharacterRoot(player)
	if not root then return end
	local existing = root:FindFirstChild("BleedEffect")
	if existing then existing:Destroy() end
end

local function attachPoisonEffect(player: Player)
	local root = getCharacterRoot(player)
	if not root or root:FindFirstChild("PoisonEffect") then return end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "PoisonEffect"
	emitter.Color = ColorSequence.new(
		Color3.fromRGB(40, 180, 40),
		Color3.fromRGB(80, 255, 80)
	)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.5, 0.25),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.7, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Rate = 6
	emitter.Speed = NumberRange.new(0.3, 1.0)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 2, 0)
	emitter.RotSpeed = NumberRange.new(-60, 60)
	emitter.Parent = root
end

local function removePoisonEffect(player: Player)
	local root = getCharacterRoot(player)
	if not root then return end
	local existing = root:FindFirstChild("PoisonEffect")
	if existing then existing:Destroy() end
end

-- ── Bleed / Poison state management ─────────────────────────────────────

local function startBleeding(player: Player, state: PlayerState)
	state.bleedStacks += 1
	state.bleedStartTime = os.time()  -- reset clot timer on new wound
	player:SetAttribute(StatsConfig.AttributeNames.IsBleeding, true)
	player:SetAttribute(StatsConfig.AttributeNames.BleedStacks, state.bleedStacks)
	player:SetAttribute(StatsConfig.AttributeNames.BleedStartTime, state.bleedStartTime)
	attachBleedEffect(player)
end

local function removeBleedStack(player: Player, state: PlayerState)
	state.bleedStacks = math.max(0, state.bleedStacks - 1)
	if state.bleedStacks <= 0 then
		state.bleedStacks = 0
		state.bleedStartTime = nil
		player:SetAttribute(StatsConfig.AttributeNames.IsBleeding, false)
		removeBleedEffect(player)
	else
		state.bleedStartTime = os.time()  -- reset clot timer for remaining stacks
	end
	player:SetAttribute(StatsConfig.AttributeNames.BleedStacks, state.bleedStacks)
	player:SetAttribute(StatsConfig.AttributeNames.BleedStartTime, state.bleedStartTime or 0)
end

local function stopBleeding(player: Player, state: PlayerState)
	state.bleedStacks = 0
	state.bleedStartTime = nil
	player:SetAttribute(StatsConfig.AttributeNames.IsBleeding, false)
	player:SetAttribute(StatsConfig.AttributeNames.BleedStacks, 0)
	player:SetAttribute(StatsConfig.AttributeNames.BleedStartTime, 0)
	removeBleedEffect(player)
end

local function startPoison(player: Player, state: PlayerState)
	state.poisonStartTime = os.time()
	player:SetAttribute(StatsConfig.AttributeNames.IsPoisoned, true)
	player:SetAttribute(StatsConfig.AttributeNames.PoisonStartTime, state.poisonStartTime)
	attachPoisonEffect(player)
end

local function stopPoison(player: Player, state: PlayerState)
	state.poisonStartTime = nil
	player:SetAttribute(StatsConfig.AttributeNames.IsPoisoned, false)
	player:SetAttribute(StatsConfig.AttributeNames.PoisonStartTime, 0)
	removePoisonEffect(player)
end

local function setEnergy(player: Player, state: PlayerState, newEnergy: number)
	local clamped = clampEnergy(newEnergy)
	if math.abs(state.energy - clamped) > 0.01 then
		state.energy = clamped
		state.profileDirty = true
	end

	local roundedEnergy = round1(state.energy)
	if player:GetAttribute("Energy") ~= roundedEnergy then
		player:SetAttribute("Energy", roundedEnergy)
	end
end

local function setSavedHealth(player: Player, state: PlayerState, health: number, maxHealth: number)
	local clamped = math.clamp(health, 0, math.max(maxHealth, 1))
	if math.abs(state.savedHealth - clamped) > 0.01 then
		state.savedHealth = clamped
		state.profileDirty = true
	end

	local roundedHealth = round1(clamped)
	if player:GetAttribute("Health") ~= roundedHealth then
		player:SetAttribute("Health", roundedHealth)
	end
end

local function buildProfileFromState(player: Player, state: PlayerState): { [string]: any }
	local credits = player:GetAttribute("Credits")
	if type(credits) ~= "number" then
		credits = Config.Credits.StartingCredits
	end

	local healthForSave = state.savedHealth
	local humanoid = state.humanoid
	if humanoid and humanoid.Parent and humanoid.Health > 0 then
		healthForSave = humanoid.Health
	end

	-- Collect slot-based inventory from player attributes.
	local maxSlots = math.max(1, math.floor(tonumber(player:GetAttribute("MaxInvSlots")) or 5))
	local invSlots: { { itemId: string, qty: number, expiries: { number }?, durabilities: { number }? } } = {}
	for n = 1, maxSlots do
		local itemId = tostring(player:GetAttribute("InvSlot_" .. n) or "")
		local qty    = math.floor(tonumber(player:GetAttribute("InvQty_" .. n)) or 0)
		if itemId ~= "" and qty > 0 then
			local entry: { itemId: string, qty: number, expiries: { number }?, durabilities: { number }? } = { itemId = itemId, qty = qty }
			-- Save per-item expiry timestamps
			local expiryStr = player:GetAttribute("InvExpires_" .. n)
			if type(expiryStr) == "string" and expiryStr ~= "" then
				local expiries: { number } = {}
				for ts in string.gmatch(expiryStr, "[^,]+") do
					local num = tonumber(ts)
					if num then table.insert(expiries, num) end
				end
				if #expiries > 0 then
					table.sort(expiries)
					entry.expiries = expiries
				end
			end
			-- Save per-item durability values
			local durStr = player:GetAttribute("InvDurability_" .. n)
			if type(durStr) == "string" and durStr ~= "" then
				local durabilities: { number } = {}
				for d in string.gmatch(durStr, "[^,]+") do
					local num = tonumber(d)
					if num then table.insert(durabilities, num) end
				end
				if #durabilities > 0 then
					entry.durabilities = durabilities
				end
			end
			table.insert(invSlots, entry)
		end
	end

	-- Capture player position for relog teleport
	local lastPosition: { x: number, y: number, z: number }? = nil
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		local pos = rootPart.Position
		lastPosition = {
			x = math.round(pos.X * 10) / 10,
			y = math.round(pos.Y * 10) / 10,
			z = math.round(pos.Z * 10) / 10,
		}
	end

	return {
		version = PROFILE_VERSION,
		credits = math.floor(credits + 0.5),
		survival = {
			Energy  = round1(clampEnergy(state.energy)),
			Health  = round1(clampHealthForStorage(healthForSave)),
			Hunger  = round1(math.clamp(state.hunger,  0, StatsConfig.Hunger.Max)),
			Thirst  = round1(math.clamp(state.thirst,  0, StatsConfig.Thirst.Max)),
			Fatigue = round1(math.clamp(state.fatigue, 0, StatsConfig.Fatigue.Max)),
			Blood   = round1(math.clamp(state.blood,   0, StatsConfig.Blood.Max)),
			Poison  = round1(math.clamp(state.poison,  0, StatsConfig.Poison.Max)),
			IsBleeding = state.bleedStartTime ~= nil,
			BleedStacks = state.bleedStacks,
			IsPoisoned = state.poisonStartTime ~= nil,
		},
		inventory = readInventoryFromPlayer(player),
		invSlots  = invSlots,
		lastPosition = lastPosition,
	}
end

local function saveProfile(player: Player, force: boolean)
	if not profileStore then
		return
	end

	local state = playerStates[player]
	if not state then
		return
	end

	if not force and not state.profileDirty then
		return
	end

	local now = os.clock()
	if not force and now - state.lastSaveTime < autoSaveSeconds then
		return
	end

	local key = getProfileKey(player.UserId)
	local payload = buildProfileFromState(player, state)
	state.lastSaveTime = now  -- update before pcall so throttle failures don't cause retry floods
	local success, err = pcall(function()
		profileStore:SetAsync(key, payload)
	end)

	if not success then
		warn(string.format("Failed to save profile for %d: %s", player.UserId, tostring(err)))
		return
	end

	state.profileDirty = false
end

local function drainJumpEnergy(player: Player, state: PlayerState)
	local now = os.clock()
	if now - state.lastJumpDrainTime < 0.15 then
		return
	end

	state.lastJumpDrainTime = now

	if state.energy < Config.Energy.MinToJump then
		setJumpEnabled(state, false)
		local humanoid = state.humanoid
		if humanoid and humanoid.Jump then
			humanoid.Jump = false
		end
		return
	end

	setEnergy(player, state, state.energy - Config.Energy.JumpCost)
	state.lastEnergyUseTime = now
end

local function setupCharacter(player: Player, character: Model)
	local state = playerStates[player]
	if not state then
		return
	end

	clearCharacterConnections(state)

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	local regenScript = character:FindFirstChild("Health")
	if regenScript and regenScript:IsA("Script") then
		regenScript:Destroy()
	end

	table.insert(state.charConnections, character.ChildAdded:Connect(function(child)
		if child.Name == "Health" and child:IsA("Script") then
			child:Destroy()
		end
	end))

	state.humanoid = humanoid
	state.currentWalkSpeed = Config.Movement.WalkSpeed
	state.jumpEnabled = true
	state.sprintRequested = false
	state.lastEnergyUseTime = os.clock()
	state.lastJumpDrainTime = 0
	state.campfireIdleTime = 0
	state.sittingAtCampfire = false
	player:SetAttribute("SittingAtCampfire", false)

	humanoid.UseJumpPower = true
	humanoid.WalkSpeed = Config.Movement.WalkSpeed
	humanoid.JumpPower = Config.Movement.JumpPower
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)

	setEnergy(player, state, state.energy)
	player:SetAttribute("MaxHealth", humanoid.MaxHealth)

	local spawnHealth = state.savedHealth
	if spawnHealth <= 0 then
		spawnHealth = humanoid.MaxHealth
	end
	spawnHealth = math.clamp(spawnHealth, 1, humanoid.MaxHealth)
	humanoid.Health = spawnHealth
	setSavedHealth(player, state, spawnHealth, humanoid.MaxHealth)

	table.insert(state.charConnections, humanoid.HealthChanged:Connect(function(newHealth)
		setSavedHealth(player, state, newHealth, humanoid.MaxHealth)
	end))

	table.insert(state.charConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		local maxHealth = humanoid.MaxHealth
		player:SetAttribute("MaxHealth", maxHealth)
		if state.savedHealth > maxHealth then
			setSavedHealth(player, state, maxHealth, maxHealth)
		end
	end))

	table.insert(state.charConnections, humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if humanoid.Jump then
			drainJumpEnergy(player, state)
		end
	end))

	table.insert(state.charConnections, humanoid.Jumping:Connect(function(isJumping)
		if isJumping then
			drainJumpEnergy(player, state)
		end
	end))

	table.insert(state.charConnections, humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			drainJumpEnergy(player, state)
		end
	end))

	table.insert(state.charConnections, humanoid.Died:Connect(function()
		state.sprintRequested = false
		state.energy = Config.Energy.Max
		state.savedHealth = humanoid.MaxHealth
		-- Reset ALL survival stats on death
		if state.bleedStacks > 0 then stopBleeding(player, state) end
		if state.poisonStartTime then stopPoison(player, state) end
		setBlood(player, state, StatsConfig.Blood.Max)
		setPoison(player, state, 0)
		setHunger(player, state, StatsConfig.Hunger.Max)
		setThirst(player, state, StatsConfig.Thirst.Max)
		setFatigue(player, state, StatsConfig.Fatigue.Max)
		-- Clear bedroll rest state on death
		if player:GetAttribute("LyingOnBedroll") == true then
			player:SetAttribute("IsResting", false)
			player:SetAttribute("LyingOnBedroll", false)
			for _, obj in ipairs(workspace:GetChildren()) do
				if obj:IsA("Model")
					and obj:GetAttribute("_PlacedItem") == "bedroll"
					and obj:GetAttribute("_OccupiedBy") == player.UserId
				then
					obj:SetAttribute("_OccupiedBy", nil)
					local bPart = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
					if bPart then
						local bp = bPart:FindFirstChildOfClass("ProximityPrompt")
						if bp then bp.Enabled = true end
					end
					break
				end
			end
		end
		-- Dump all inventory into a death loot bag
		local deathCFrame = (character and character:FindFirstChild("HumanoidRootPart"))
			and character.HumanoidRootPart.CFrame or CFrame.new(0, 5, 0)
		local dumpAllFn = ServerStorage:FindFirstChild("ServerBindables")
			and ServerStorage.ServerBindables:FindFirstChild("InventoryDumpAll")
		if dumpAllFn then
			dumpAllFn:Invoke(player, deathCFrame)
		end
		-- Snapshot bedroll for respawn teleport
		state.deathRespawnCFrame = state.bedrollSpawnCFrame
		state.profileDirty = true
	end))

	-- Reattach particle effects if player spawns while still bleeding/poisoned
	if state.bleedStartTime then attachBleedEffect(player) end
	if state.poisonStartTime then attachPoisonEffect(player) end

	-- Respawn teleport priority:
	-- 1. Death respawn → bedroll CFrame (if died with bedroll active)
	-- 2. Relog → lastPosition (saved logout position, one-time use)
	-- 3. Default Roblox spawn
	local teleportCFrame: CFrame? = nil
	if state.deathRespawnCFrame then
		teleportCFrame = state.deathRespawnCFrame
		state.deathRespawnCFrame = nil
	elseif state.lastPosition then
		local lp = state.lastPosition
		teleportCFrame = CFrame.new(lp.x, lp.y + 2, lp.z)  -- +2 studs Y to avoid clipping
		state.lastPosition = nil  -- one-time use
	end

	if teleportCFrame then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			task.defer(function()
				if root.Parent then
					root.CFrame = teleportCFrame
				end
			end)
		end
	end
end

local function setupPlayer(player: Player)
	local profile = loadProfile(player.UserId)

	local state: PlayerState = {
		energy = clampEnergy(profile.survival.Energy),
		savedHealth = clampHealthForStorage(profile.survival.Health),
		sprintRequested = false,
		lastEnergyUseTime = os.clock(),
		lastJumpDrainTime = 0,
		humanoid = nil,
		currentWalkSpeed = Config.Movement.WalkSpeed,
		jumpEnabled = true,
		charConnections = {},
		playerConnections = {},
		profileDirty = false,
		lastSaveTime = os.clock(),
		hunger = math.clamp(profile.survival.Hunger,  0, StatsConfig.Hunger.Max),
		thirst = math.clamp(profile.survival.Thirst,  0, StatsConfig.Thirst.Max),
		fatigue = math.clamp(profile.survival.Fatigue, 0, StatsConfig.Fatigue.Max),
		blood = math.clamp(profile.survival.Blood,   0, StatsConfig.Blood.Max),
		poison = math.clamp(profile.survival.Poison,  0, StatsConfig.Poison.Max),
		bleedStacks = profile.survival.BleedStacks or 0,
		bleedStartTime = if profile.survival.IsBleeding then os.time() else nil,
		poisonStartTime = if profile.survival.IsPoisoned then os.time() else nil,
		campfireIdleTime = 0,
		sittingAtCampfire = false,
		bedrollSpawnCFrame = nil,
		deathRespawnCFrame = nil,
		lastPosition = profile.lastPosition,
	}

	playerStates[player] = state

	local pocketSlots = (Config.Inventory and Config.Inventory.PocketSlots) or 5
	player:SetAttribute("MaxInvSlots", pocketSlots)

	player:SetAttribute("MaxEnergy", Config.Energy.Max)
	player:SetAttribute("Energy", round1(state.energy))
	player:SetAttribute("Credits", profile.credits)
	player:SetAttribute(StatsConfig.AttributeNames.MaxHunger,  StatsConfig.Hunger.Max)
	player:SetAttribute(StatsConfig.AttributeNames.Hunger,     round1(state.hunger))
	player:SetAttribute(StatsConfig.AttributeNames.MaxThirst,  StatsConfig.Thirst.Max)
	player:SetAttribute(StatsConfig.AttributeNames.Thirst,     round1(state.thirst))
	player:SetAttribute(StatsConfig.AttributeNames.MaxFatigue, StatsConfig.Fatigue.Max)
	player:SetAttribute(StatsConfig.AttributeNames.Fatigue,    round1(state.fatigue))
	player:SetAttribute(StatsConfig.AttributeNames.MaxBlood,    StatsConfig.Blood.Max)
	player:SetAttribute(StatsConfig.AttributeNames.Blood,       round1(state.blood))
	player:SetAttribute("SittingAtCampfire", false)
	player:SetAttribute(StatsConfig.AttributeNames.MaxPoison,   StatsConfig.Poison.Max)
	player:SetAttribute(StatsConfig.AttributeNames.Poison,      round1(state.poison))
	-- Restore active status effects — prevents relog dodge
	player:SetAttribute(StatsConfig.AttributeNames.BleedStacks, state.bleedStacks)
	if state.bleedStartTime then
		player:SetAttribute(StatsConfig.AttributeNames.IsBleeding, true)
		player:SetAttribute(StatsConfig.AttributeNames.BleedStartTime, state.bleedStartTime)
	else
		player:SetAttribute(StatsConfig.AttributeNames.IsBleeding, false)
	end
	if state.poisonStartTime then
		player:SetAttribute(StatsConfig.AttributeNames.IsPoisoned, true)
		player:SetAttribute(StatsConfig.AttributeNames.PoisonStartTime, state.poisonStartTime)
	else
		player:SetAttribute(StatsConfig.AttributeNames.IsPoisoned, false)
	end
	player:SetAttribute(StatsConfig.AttributeNames.IsResting,   false)
	writeInventoryAttributes(player, decodeInventory(profile.inventory))

	-- Restore slot-based inventory from saved profile.
	local isUpgradeToV5 = (tonumber(profile.version) or 0) < 5
	if type(profile.invSlots) == "table" then
		for n, entry in ipairs(profile.invSlots) do
			if n > pocketSlots then break end
			if type(entry.itemId) == "string" and entry.itemId ~= "" and type(entry.qty) == "number" then
				local qty = math.floor(entry.qty + 0.5)
				player:SetAttribute("InvSlot_" .. n, entry.itemId)
				player:SetAttribute("InvQty_" .. n,  qty)

				-- Restore or assign per-item expiry timestamps
				if entry.expiries and #entry.expiries > 0 then
					-- Saved expiries exist — restore them
					local parts = {}
					for _, ts in ipairs(entry.expiries) do
						table.insert(parts, tostring(math.floor(ts)))
					end
					player:SetAttribute("InvExpires_" .. n, table.concat(parts, ","))
				elseif isUpgradeToV5 then
					-- v4→v5 migration: assign fresh timers to existing perishable items
					local def = ItemRegistry.get(entry.itemId)
					if def and def.perishSeconds then
						local now = os.time()
						local parts = {}
						for _ = 1, qty do
							table.insert(parts, tostring(now + def.perishSeconds))
						end
						player:SetAttribute("InvExpires_" .. n, table.concat(parts, ","))
					end
				end

				-- Restore per-item durability values
				if entry.durabilities and #entry.durabilities > 0 then
					local parts = {}
					for _, d in ipairs(entry.durabilities) do
						table.insert(parts, tostring(math.floor(d)))
					end
					player:SetAttribute("InvDurability_" .. n, table.concat(parts, ","))
				end
			end
		end
	end

	-- RPG stats (populated by SkillSystem in the future; initialize to 0)
	player:SetAttribute("Stat_STR", 0)
	player:SetAttribute("Stat_AGI", 0)
	player:SetAttribute("Stat_CON", 0)
	player:SetAttribute("Stat_WIS", 0)
	player:SetAttribute("Stat_INT", 0)
	player:SetAttribute("Stat_CHA", 0)

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local creditsStat = Instance.new("IntValue")
	creditsStat.Name = "Credits"
	creditsStat.Value = math.floor(profile.credits)
	creditsStat.Parent = leaderstats

	table.insert(state.playerConnections, player:GetAttributeChangedSignal("Credits"):Connect(function()
		local credits = player:GetAttribute("Credits")
		if type(credits) == "number" then
			updateLeaderstatsCredits(player, credits)
			state.profileDirty = true
		end
	end))

	for slot = 1, hotbarSlotCount do
		table.insert(state.playerConnections, player:GetAttributeChangedSignal(slotAttributeName(slot)):Connect(function()
			state.profileDirty = true
		end))
	end

	table.insert(state.playerConnections, player:GetAttributeChangedSignal("HotbarEquippedSlot"):Connect(function()
		state.profileDirty = true
	end))

	-- Mark dirty when any inventory slot changes.
	table.insert(state.playerConnections, player.AttributeChanged:Connect(function(attrName)
		if attrName:sub(1, 8) == "InvSlot_" or attrName:sub(1, 7) == "InvQty_" or attrName:sub(1, 11) == "InvExpires_" or attrName:sub(1, 15) == "InvDurability_" then
			state.profileDirty = true
		end
	end))

	table.insert(state.playerConnections, player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end))

	if player.Character then
		setupCharacter(player, player.Character)
	end
end

local function cleanupPlayer(player: Player)
	local state = playerStates[player]
	if not state then
		return
	end

	clearCharacterConnections(state)
	clearPlayerConnections(state)
	playerStates[player] = nil
end

-- ── Bedroll spawn tracking ────────────────────────────────────────────────
-- When a bedroll is placed, record its CFrame for the owning player.
-- When it's destroyed, clear the reference.

local function trackBedroll(model: Model)
	if model:GetAttribute("_PlacedItem") ~= "bedroll" then return end
	local ownerId = model:GetAttribute("_PlacedBy")
	if type(ownerId) ~= "number" then return end

	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not primary then return end

	-- Find owning player and set their bedroll spawn
	for player, state in pairs(playerStates) do
		if player.UserId == ownerId then
			state.bedrollSpawnCFrame = primary.CFrame
			break
		end
	end

	-- When bedroll is destroyed, clear the spawn
	model.Destroying:Connect(function()
		for player, state in pairs(playerStates) do
			if player.UserId == ownerId then
				state.bedrollSpawnCFrame = nil
				break
			end
		end
	end)
end

-- Scan existing bedrolls
for _, obj in ipairs(workspace:GetChildren()) do
	if obj:IsA("Model") then trackBedroll(obj) end
end
workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		task.defer(function() trackBedroll(child) end)
	end
end)

sprintIntentRemote.OnServerEvent:Connect(function(player, wantsToSprint)
	if type(wantsToSprint) ~= "boolean" then
		return
	end

	local state = playerStates[player]
	if not state then
		return
	end

	state.sprintRequested = wantsToSprint
end)

RunService.Heartbeat:Connect(function(deltaTime)
	local now = os.clock()

	for player, state in pairs(playerStates) do
		if state.profileDirty and profileStore and now - state.lastSaveTime >= autoSaveSeconds then
			saveProfile(player, false)
		end

		local humanoid = state.humanoid
		if not humanoid or humanoid.Parent == nil or humanoid.Health <= 0 then
			continue
		end

		local moving = humanoid.MoveDirection.Magnitude > 0.05
		local isSwimming = humanoid:GetState() == Enum.HumanoidStateType.Swimming
		local canSpendEnergy = state.energy > 0
		local shouldSprint = state.sprintRequested and moving and canSpendEnergy

		-- ── Energy ────────────────────────────────────────────────────────────
		local thirstEmpty = state.thirst <= 0
		local fatigueEmpty = state.fatigue <= 0

		if shouldSprint then
			setEnergy(player, state, state.energy - Config.Energy.SprintDrainPerSecond * deltaTime)
			state.lastEnergyUseTime = now
		elseif not isSwimming and not moving
			and now - state.lastEnergyUseTime >= Config.Energy.RegenDelaySeconds
			and not thirstEmpty
		then
			local regenMult = fatigueEmpty and StatsConfig.Fatigue.OnEmpty.EnergyRegenMultiplier or 1
			setEnergy(player, state, state.energy + Config.Energy.RegenPerSecond * regenMult * deltaTime)
		end

		local hasJumpEnergy = state.energy >= Config.Energy.MinToJump
		setJumpEnabled(state, hasJumpEnergy)
		if not hasJumpEnergy and humanoid.Jump then
			humanoid.Jump = false
		end

		local fatigueSpeedMult = fatigueEmpty and StatsConfig.Fatigue.OnEmpty.SpeedMultiplier or 1
		local weightSpeedMult  = computeWeightSpeedMult(player)
		if state.energy <= 0 then
			setWalkSpeed(state, Config.Movement.ExhaustedSpeed * fatigueSpeedMult * weightSpeedMult)
		elseif shouldSprint then
			setWalkSpeed(state, Config.Movement.SprintSpeed * fatigueSpeedMult * weightSpeedMult)
		else
			setWalkSpeed(state, Config.Movement.WalkSpeed * fatigueSpeedMult * weightSpeedMult)
		end

		-- ── Hunger ────────────────────────────────────────────────────────────
		local hungerDrain = StatsConfig.Hunger.DrainPerSecond * deltaTime
		if shouldSprint then
			hungerDrain += StatsConfig.Hunger.SprintExtraDrainPerSecond * deltaTime
		end
		setHunger(player, state, state.hunger - hungerDrain)
		if state.hunger <= 0 and humanoid.Health > 0 then
			humanoid:TakeDamage(StatsConfig.Hunger.OnEmpty.HealthDrainPerSecond * deltaTime)
		end

		-- ── Thirst ────────────────────────────────────────────────────────────
		local thirstDrain = StatsConfig.Thirst.DrainPerSecond * deltaTime
		if shouldSprint then
			thirstDrain += StatsConfig.Thirst.SprintExtraDrainPerSecond * deltaTime
		end
		setThirst(player, state, state.thirst - thirstDrain)
		if thirstEmpty and humanoid.Health > 0 then
			humanoid:TakeDamage(StatsConfig.Thirst.OnEmpty.HealthDrainPerSecond * deltaTime)
		end

		-- ── Fatigue ───────────────────────────────────────────────────────────
		local isResting = player:GetAttribute(StatsConfig.AttributeNames.IsResting) == true
		if isResting then
			setFatigue(player, state, state.fatigue + StatsConfig.Fatigue.RestorePerSecond * deltaTime)
		else
			setFatigue(player, state, state.fatigue - StatsConfig.Fatigue.DrainPerSecond * deltaTime)
		end

		-- ── Blood bar ─────────────────────────────────────────────────────────
		if state.bleedStacks > 0 and state.bleedStartTime then
			-- Active wound(s): drain blood scaled by stack count
			local bleedElapsed = os.time() - state.bleedStartTime
			if bleedElapsed >= StatsConfig.Blood.NaturalStopSeconds then
				removeBleedStack(player, state)  -- one stack clots naturally
			end
			if state.bleedStacks > 0 then
				local drain = StatsConfig.Blood.DrainPerSecond * state.bleedStacks * deltaTime
				setBlood(player, state, state.blood - drain)
			end
		else
			-- No wound: regenerate blood (gated by hunger + thirst)
			if state.blood < StatsConfig.Blood.Max then
				local regenRate = StatsConfig.Blood.RegenPerSecond
				local minStat  = StatsConfig.Blood.RegenMinStat
				local hungerOk = state.hunger >= minStat
				local thirstOk = state.thirst >= minStat
				if state.hunger <= 0 or state.thirst <= 0 then
					regenRate = 0  -- starving or dehydrated: no blood regen
				elseif not hungerOk or not thirstOk then
					regenRate = regenRate * 0.5  -- below threshold: half regen
				end
				if regenRate > 0 then
					setBlood(player, state, state.blood + regenRate * deltaTime)
				end
			end
		end

		-- Blood empty → heavy health drain
		if state.blood <= 0 and humanoid.Health > 0 then
			humanoid:TakeDamage(StatsConfig.Blood.OnEmpty.HealthDrainPerSecond * deltaTime)
		end

		-- ── Poison bar ────────────────────────────────────────────────────────
		if state.poisonStartTime then
			-- Active poison source: fill bar
			local poisonElapsed = os.time() - state.poisonStartTime
			if poisonElapsed >= StatsConfig.Poison.NaturalClearSeconds then
				stopPoison(player, state)
			else
				setPoison(player, state, state.poison + StatsConfig.Poison.FillPerSecond * deltaTime)
			end
		else
			-- No active source: decay poison
			if state.poison > 0 then
				setPoison(player, state, state.poison - StatsConfig.Poison.DecayPerSecond * deltaTime)
			end
		end

		-- Poison effects scale with level (0-100)
		if state.poison > 0 and humanoid.Health > 0 then
			local poisonRatio = state.poison / StatsConfig.Poison.Max
			humanoid:TakeDamage(StatsConfig.Poison.HealthDrainPerSecondAtMax * poisonRatio * deltaTime)
		end

		-- ── Campfire sit + regen ──────────────────────────────────────────────
		local rootPart = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local nearFire = isNearPlacedCampfire(rootPart.Position)

			if moving then
				state.campfireIdleTime = 0
			else
				state.campfireIdleTime += deltaTime
			end

			local shouldSit = nearFire and state.campfireIdleTime >= CAMPFIRE_IDLE_TO_SIT

			if shouldSit and not state.sittingAtCampfire then
				state.sittingAtCampfire = true
				player:SetAttribute("SittingAtCampfire", true)
			elseif not shouldSit and state.sittingAtCampfire then
				state.sittingAtCampfire = false
				player:SetAttribute("SittingAtCampfire", false)
			end

			if state.sittingAtCampfire then
				-- Health regen
				if humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = math.min(humanoid.Health + CAMPFIRE_HEALTH_REGEN * deltaTime, humanoid.MaxHealth)
				end
				-- Energy regen (overrides hunger/thirst penalty)
				setEnergy(player, state, state.energy + CAMPFIRE_ENERGY_REGEN * deltaTime)
			end
		end

		-- ── Bedroll lie-down: cancel on movement ─────────────────────────────
		if player:GetAttribute("LyingOnBedroll") == true then
			if moving then
				-- Stand up: restore movement
				player:SetAttribute("IsResting", false)
				player:SetAttribute("LyingOnBedroll", false)
				humanoid.WalkSpeed = shouldSprint and Config.Movement.SprintSpeed or Config.Movement.WalkSpeed
				humanoid.JumpPower = Config.Movement.JumpPower

				-- Clear bedroll occupancy
				for _, obj in ipairs(workspace:GetChildren()) do
					if obj:IsA("Model")
						and obj:GetAttribute("_PlacedItem") == "bedroll"
						and obj:GetAttribute("_OccupiedBy") == player.UserId
					then
						obj:SetAttribute("_OccupiedBy", nil)
						-- Re-enable prompt
						local bPart = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
						if bPart then
							local bp = bPart:FindFirstChildOfClass("ProximityPrompt")
							if bp then bp.Enabled = true end
						end
						break
					end
				end
			end
		end
	end

	-- ── Campsite auto-cleanup (runs once per Heartbeat, outside player loop) ──
	local bedrollRadius = (Config.Bedroll and Config.Bedroll.KeepCampfireAliveRadius) or 15

	for _, obj in ipairs(workspace:GetChildren()) do
		local placedItem = obj:IsA("Model") and obj:GetAttribute("_PlacedItem")
		if not placedItem then continue end
		if placedItem ~= "campfire" and placedItem ~= "bedroll" then continue end

		local lastOccupied = obj:GetAttribute("_lastOccupiedTime")
		if not lastOccupied then continue end

		local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
		if not primary then continue end

		local ownerId = obj:GetAttribute("_PlacedBy")

		-- Check if owner is still on server (keeps campsite alive regardless of distance)
		local ownerOnline = false
		if type(ownerId) == "number" then
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr.UserId == ownerId then
					ownerOnline = true
					break
				end
			end
		end

		-- Check if paired with a bedroll (campfire) or campfire (bedroll)
		local hasPair = false
		if placedItem == "campfire" then
			for _, other in ipairs(workspace:GetChildren()) do
				if other:IsA("Model") and other:GetAttribute("_PlacedItem") == "bedroll" then
					local otherPart = other.PrimaryPart or other:FindFirstChildWhichIsA("BasePart")
					if otherPart and (otherPart.Position - primary.Position).Magnitude <= bedrollRadius then
						hasPair = true
						break
					end
				end
			end
		elseif placedItem == "bedroll" then
			for _, other in ipairs(workspace:GetChildren()) do
				if other:IsA("Model") and other:GetAttribute("_PlacedItem") == "campfire" then
					local otherPart = other.PrimaryPart or other:FindFirstChildWhichIsA("BasePart")
					if otherPart and (otherPart.Position - primary.Position).Magnitude <= bedrollRadius then
						hasPair = true
						break
					end
				end
			end
		end

		-- Paired + owner online → keep alive
		if hasPair and ownerOnline then
			obj:SetAttribute("_lastOccupiedTime", now)
			continue
		end

		-- Check if any player is nearby
		local anyoneNear = false
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - primary.Position).Magnitude <= CAMPFIRE_SIT_RADIUS then
				anyoneNear = true
				break
			end
		end

		if anyoneNear then
			obj:SetAttribute("_lastOccupiedTime", now)
		elseif now - lastOccupied >= CAMPFIRE_INACTIVE_LIFE then
			obj:Destroy()
		end
	end
end)

-- ── Consume effect handler (fired by InventoryService) ───────────────────
-- Applies hunger/thirst/fatigue/energy deltas and clears status effects
-- when a player uses a consumable item.
consumeEffectEvent.Event:Connect(function(player: Player, effects: { [string]: any })
	local state = playerStates[player]
	if not state then return end
	if type(effects.hunger)  == "number" then setHunger(player,  state, state.hunger  + effects.hunger)  end
	if type(effects.thirst)  == "number" then setThirst(player,  state, state.thirst  + effects.thirst)  end
	if type(effects.fatigue) == "number" then setFatigue(player, state, state.fatigue + effects.fatigue) end
	if type(effects.energy)  == "number" then setEnergy(player,  state, state.energy  + effects.energy)  end
	if type(effects.blood)   == "number" then setBlood(player,   state, state.blood   + effects.blood)   end
	if type(effects.poison) == "number" and effects.poison > 0 then
		setPoison(player, state, state.poison + effects.poison)
		if not state.poisonStartTime then startPoison(player, state) end
	end
	if effects.stopBleed  and state.bleedStacks > 0  then stopBleeding(player, state) end
	if effects.stopPoison and state.poisonStartTime then stopPoison(player, state)   end
end)

-- ── Status effect trigger (fired by weapon scripts, test parts, etc.) ─────
-- Usage: applyStatusEvent:Fire(player, "bleed")  or  ("poison")  or  ("clearBleed") / ("clearPoison")
applyStatusEvent.Event:Connect(function(player: Player, effect: string)
	local state = playerStates[player]
	if not state then return end
	if effect == "bleed" then
		startBleeding(player, state)
	elseif effect == "poison" then
		if not state.poisonStartTime then
			startPoison(player, state)
		end
	elseif effect == "clearBleed" then
		if state.bleedStacks > 0 then stopBleeding(player, state) end
	elseif effect == "clearPoison" then
		if state.poisonStartTime then
			stopPoison(player, state)
			setPoison(player, state, 0)
		end
	end
end)

Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(player)
	saveProfile(player, true)
	cleanupPlayer(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveProfile(player, true)
	end
end)
