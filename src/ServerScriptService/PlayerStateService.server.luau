local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local StatsConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StatsConfig"))

local PROFILE_VERSION = 4
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
	bleedStartTime: number?,   -- os.time() when bleeding started; nil = not bleeding
	poisonStartTime: number?,  -- os.time() when poisoned started; nil = not poisoned
}

local playerStates: { [Player]: PlayerState } = {}

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
			inventory.slots[slot] = sanitizeItemId(value)
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
		},
		inventory = emptyInventory(),
		invSlots = {},
	}
end

-- Parses invSlots from saved data, migrating from the old items dict if needed.
local function decodeInvSlots(raw: any): { { itemId: string, qty: number } }
	local result: { { itemId: string, qty: number } } = {}
	if type(raw) ~= "table" then return result end

	if type(raw.invSlots) == "table" then
		for _, entry in ipairs(raw.invSlots) do
			if type(entry) == "table"
				and type(entry.itemId) == "string"
				and type(entry.qty) == "number"
			then
				local clean = sanitizeItemId(entry.itemId)
				if clean ~= "" and entry.qty > 0 then
					table.insert(result, { itemId = clean, qty = math.floor(entry.qty + 0.5) })
				end
			end
		end
	elseif type(raw.items) == "table" then
		-- Migrate old Inv_<itemId> dict format.
		for itemId, qty in pairs(raw.items) do
			if type(itemId) == "string" and type(qty) == "number" and qty > 0 then
				local clean = sanitizeItemId(itemId)
				if clean ~= "" then
					table.insert(result, { itemId = clean, qty = math.floor(qty + 0.5) })
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
	if type(hunger)  ~= "number" then hunger  = StatsConfig.Hunger.StartValue  end
	if type(thirst)  ~= "number" then thirst  = StatsConfig.Thirst.StartValue  end
	if type(fatigue) ~= "number" then fatigue = StatsConfig.Fatigue.StartValue end

	local inventoryRaw = raw.inventory
	if type(raw.Inventory) == "table" then
		inventoryRaw = raw.Inventory
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
		},
		inventory = decodeInventory(inventoryRaw),
		invSlots  = decodeInvSlots(raw),
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
	if math.abs(s[field] - clamped) > 0.01 then
		s[field] = clamped
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

local function startBleeding(player: Player, state: PlayerState)
	state.bleedStartTime = os.time()
	player:SetAttribute(StatsConfig.AttributeNames.IsBleeding, true)
	player:SetAttribute(StatsConfig.AttributeNames.BleedStartTime, state.bleedStartTime)
end

local function stopBleeding(player: Player, state: PlayerState)
	state.bleedStartTime = nil
	player:SetAttribute(StatsConfig.AttributeNames.IsBleeding, false)
	player:SetAttribute(StatsConfig.AttributeNames.BleedStartTime, 0)
end

local function startPoison(player: Player, state: PlayerState)
	state.poisonStartTime = os.time()
	player:SetAttribute(StatsConfig.AttributeNames.IsPoisoned, true)
	player:SetAttribute(StatsConfig.AttributeNames.PoisonStartTime, state.poisonStartTime)
end

local function stopPoison(player: Player, state: PlayerState)
	state.poisonStartTime = nil
	player:SetAttribute(StatsConfig.AttributeNames.IsPoisoned, false)
	player:SetAttribute(StatsConfig.AttributeNames.PoisonStartTime, 0)
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
	local invSlots: { { itemId: string, qty: number } } = {}
	for n = 1, maxSlots do
		local itemId = tostring(player:GetAttribute("InvSlot_" .. n) or "")
		local qty    = math.floor(tonumber(player:GetAttribute("InvQty_" .. n)) or 0)
		if itemId ~= "" and qty > 0 then
			table.insert(invSlots, { itemId = itemId, qty = qty })
		end
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
		},
		inventory = readInventoryFromPlayer(player),
		invSlots  = invSlots,
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
		-- Status effects clear on death; hunger/thirst/fatigue persist
		if state.bleedStartTime then stopBleeding(player, state) end
		if state.poisonStartTime then stopPoison(player, state) end
		state.profileDirty = true
	end))
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
		bleedStartTime = nil,
		poisonStartTime = nil,
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
	player:SetAttribute(StatsConfig.AttributeNames.IsBleeding,  false)
	player:SetAttribute(StatsConfig.AttributeNames.IsPoisoned,  false)
	player:SetAttribute(StatsConfig.AttributeNames.IsResting,   false)
	writeInventoryAttributes(player, decodeInventory(profile.inventory))

	-- Restore slot-based inventory from saved profile.
	if type(profile.invSlots) == "table" then
		for n, entry in ipairs(profile.invSlots) do
			if n > pocketSlots then break end
			if type(entry.itemId) == "string" and entry.itemId ~= "" and type(entry.qty) == "number" then
				player:SetAttribute("InvSlot_" .. n, entry.itemId)
				player:SetAttribute("InvQty_" .. n,  math.floor(entry.qty + 0.5))
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
		if attrName:sub(1, 9) == "InvSlot_" or attrName:sub(1, 7) == "InvQty_" then
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
		local isGrounded = humanoid.FloorMaterial ~= Enum.Material.Air
		local canSpendEnergy = state.energy > 0
		local shouldSprint = state.sprintRequested and moving and canSpendEnergy

		-- ── Energy ────────────────────────────────────────────────────────────
		local thirstEmpty = state.thirst <= 0
		local fatigueEmpty = state.fatigue <= 0

		if shouldSprint then
			setEnergy(player, state, state.energy - Config.Energy.SprintDrainPerSecond * deltaTime)
			state.lastEnergyUseTime = now
		elseif isGrounded and not moving
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

		-- ── Bleeding ──────────────────────────────────────────────────────────
		if state.bleedStartTime then
			local bleedElapsed = os.time() - state.bleedStartTime
			if bleedElapsed >= StatsConfig.Bleeding.NaturalStopSeconds then
				stopBleeding(player, state)
			elseif humanoid.Health > 0 then
				humanoid:TakeDamage(StatsConfig.Bleeding.HealthDrainPerSecond * deltaTime)
			end
		end

		-- ── Poison ────────────────────────────────────────────────────────────
		if state.poisonStartTime then
			local poisonElapsed = os.time() - state.poisonStartTime
			if poisonElapsed >= StatsConfig.Poison.NaturalClearSeconds then
				stopPoison(player, state)
			elseif humanoid.Health > 0 then
				local potency = math.exp(-StatsConfig.Poison.DecayRate * poisonElapsed)
				humanoid:TakeDamage(StatsConfig.Poison.HealthDrainPerSecond * potency * deltaTime)
			end
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
	if effects.stopBleed  and state.bleedStartTime  then stopBleeding(player, state) end
	if effects.stopPoison and state.poisonStartTime then stopPoison(player, state)   end
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
