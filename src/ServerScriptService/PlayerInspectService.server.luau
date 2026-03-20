-- PlayerInspectService.server.luau
-- Handles inspect requests: validates range, reads target player's live
-- attributes, and returns a data payload to the requesting client.
--
-- Remotes created here (inside the Remotes folder):
--   InspectRequest  (RemoteEvent) -- client requests inspect of another player
--   InspectData     (RemoteEvent) -- server sends inspect payload to client

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameplayConfig    = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local StatsConfig       = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StatsConfig"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AchievementConfig"))
local ServerStorage     = game:GetService("ServerStorage")

local INTERACT_RANGE = GameplayConfig.Trading.InteractRange

-- ── Remotes ─────────────────────────────────────────────────────────────

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local function ensureRemote(name: string): RemoteEvent
	local existing = remotesFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing :: RemoteEvent
	end
	if existing then existing:Destroy() end
	local r = Instance.new("RemoteEvent")
	r.Name   = name
	r.Parent = remotesFolder
	return r
end

local inspectRequestRemote = ensureRemote("InspectRequest")
local inspectDataRemote    = ensureRemote("InspectData")

-- ── Wealth tiers ────────────────────────────────────────────────────────

local WEALTH_TIERS = {
	{ threshold = 1000, label = "Elite" },
	{ threshold = 500,  label = "Wealthy" },
	{ threshold = 200,  label = "Comfortable" },
	{ threshold = 50,   label = "Poor" },
	{ threshold = 0,    label = "Destitute" },
}

local function getWealthTier(credits: number): string
	for _, tier in ipairs(WEALTH_TIERS) do
		if credits >= tier.threshold then
			return tier.label
		end
	end
	return "Destitute"
end

-- ── Format session time ────────────────────────────────────────────────

local function formatSessionTime(seconds: number): string
	if seconds < 60 then
		return tostring(math.floor(seconds)) .. "s"
	elseif seconds < 3600 then
		return tostring(math.floor(seconds / 60)) .. "m"
	else
		local h = math.floor(seconds / 3600)
		local m = math.floor((seconds % 3600) / 60)
		return tostring(h) .. "h " .. tostring(m) .. "m"
	end
end

-- ── Cooldown ────────────────────────────────────────────────────────────

local inspectCooldowns: { [Player]: number } = {}
local COOLDOWN_SECONDS = 1

-- ── Request handler ─────────────────────────────────────────────────────

inspectRequestRemote.OnServerEvent:Connect(function(player: Player, targetArg: any)
	-- Accept Player instance or UserId number
	local target: Player? = nil
	if typeof(targetArg) == "Instance" and targetArg:IsA("Player") then
		target = targetArg :: Player
	elseif type(targetArg) == "number" then
		for _, p in ipairs(Players:GetPlayers()) do
			if p.UserId == targetArg then
				target = p
				break
			end
		end
	else
		return
	end

	-- Cooldown
	local now = os.clock()
	if inspectCooldowns[player] and now - inspectCooldowns[player] < COOLDOWN_SECONDS then
		return
	end
	inspectCooldowns[player] = now

	if not target or target == player then return end

	-- Range check
	local myChar = player.Character
	local theirChar = target.Character
	if not myChar or not theirChar then return end
	local myRoot = myChar:FindFirstChild("HumanoidRootPart")
	local theirRoot = theirChar:FindFirstChild("HumanoidRootPart")
	if not myRoot or not theirRoot then return end

	local dist = (myRoot.Position - theirRoot.Position).Magnitude
	if dist > INTERACT_RANGE then return end

	-- Build payload from live attributes
	local credits = tonumber(target:GetAttribute("Credits")) or 0
	local survivalSeconds = tonumber(target:GetAttribute("_SurvivalSeconds")) or 0

	-- Equipped item
	local equippedSlot = tonumber(target:GetAttribute("HotbarEquippedSlot")) or 0
	local equippedItem = ""
	if equippedSlot > 0 then
		equippedItem = target:GetAttribute("HotbarSlot" .. tostring(equippedSlot)) or ""
	end

	local payload = {
		name = target.DisplayName,
		userId = target.UserId,
		health = tonumber(target:GetAttribute("Health")) or 100,
		maxHealth = tonumber(target:GetAttribute("MaxHealth")) or 100,
		hunger = tonumber(target:GetAttribute(StatsConfig.AttributeNames.Hunger)) or 100,
		maxHunger = tonumber(target:GetAttribute(StatsConfig.AttributeNames.MaxHunger)) or 100,
		thirst = tonumber(target:GetAttribute(StatsConfig.AttributeNames.Thirst)) or 100,
		maxThirst = tonumber(target:GetAttribute(StatsConfig.AttributeNames.MaxThirst)) or 100,
		fatigue = tonumber(target:GetAttribute(StatsConfig.AttributeNames.Fatigue)) or 100,
		maxFatigue = tonumber(target:GetAttribute(StatsConfig.AttributeNames.MaxFatigue)) or 100,
		wealthTier = getWealthTier(credits),
		survivalTime = formatSessionTime(survivalSeconds),
		equippedItem = equippedItem,
		title = "Survivor",  -- placeholder for future title system
	}

	-- Read Health from Humanoid (more reliable than attribute)
	local humanoid = theirChar:FindFirstChildOfClass("Humanoid")
	if humanoid then
		payload.health = math.floor(humanoid.Health)
		payload.maxHealth = math.floor(humanoid.MaxHealth)
	end

	-- Achievement summary
	local bindables = ServerStorage:FindFirstChild("ServerBindables")
	local achGetState = bindables and bindables:FindFirstChild("AchievementGetState")
	if achGetState and achGetState:IsA("BindableFunction") then
		local ok, achData = pcall(achGetState.Invoke, achGetState, target)
		if ok and type(achData) == "table" then
			payload.achievementCount = achData.unlockedCount or 0
			payload.achievementTotal = achData.totalCount or AchievementConfig.TotalCount
			local recentKey = achData.mostRecentKey
			if recentKey then
				local ach = AchievementConfig.ByKey[recentKey]
				payload.recentAchievement = ach and ach.name or nil
			end
		end
	end

	inspectDataRemote:FireClient(player, payload)
end)

-- Cleanup cooldown on leave
Players.PlayerRemoving:Connect(function(player)
	inspectCooldowns[player] = nil
end)
