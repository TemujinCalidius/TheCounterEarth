-- LoreService.server.luau
-- Server-side lore discovery tracking.
-- Persists discovered lore IDs via PlayerStateService BindableFunctions.
-- Fires EventBridge events and increments achievement counters on discovery.

local Players           = game:GetService("Players")
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LoreConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("LoreConfig"))

local EventBridge = require(script.Parent:WaitForChild("EventBridge"))

-- ── Remotes ─────────────────────────────────────────────────────────────

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local loreInteractRemote = Instance.new("RemoteEvent")
loreInteractRemote.Name = "LoreInteract"
loreInteractRemote.Parent = remotesFolder

local loreDiscoveredRemote = Instance.new("RemoteEvent")
loreDiscoveredRemote.Name = "LoreDiscovered"
loreDiscoveredRemote.Parent = remotesFolder

local loreAlreadyReadRemote = Instance.new("RemoteEvent")
loreAlreadyReadRemote.Name = "LoreAlreadyRead"
loreAlreadyReadRemote.Parent = remotesFolder

local loreDataSyncRemote = Instance.new("RemoteEvent")
loreDataSyncRemote.Name = "LoreDataSync"
loreDataSyncRemote.Parent = remotesFolder

-- ── BindableFunctions (for PlayerStateService integration) ──────────────

local bindablesFolder = ServerStorage:WaitForChild("ServerBindables")

local loreLoadFunc = Instance.new("BindableFunction")
loreLoadFunc.Name = "LoreLoad"
loreLoadFunc.Parent = bindablesFolder

local loreSaveFunc = Instance.new("BindableFunction")
loreSaveFunc.Name = "LoreSave"
loreSaveFunc.Parent = bindablesFolder

-- ── Per-player state ─────────────────────────────────────────────────────

local playerDiscovered: { [Player]: { [string]: boolean } } = {}
local playerLoaded: { [Player]: boolean } = {}

-- ── Helpers ──────────────────────────────────────────────────────────────

local function getDiscoveredList(player: Player): { string }
	local disc = playerDiscovered[player]
	if not disc then return {} end
	local list = {}
	for id in pairs(disc) do
		table.insert(list, id)
	end
	return list
end

-- ── BindableFunction handlers ────────────────────────────────────────────

loreLoadFunc.OnInvoke = function(player: Player, savedData: any?)
	local discovered: { [string]: boolean } = {}

	if type(savedData) == "table" then
		for _, loreId in ipairs(savedData) do
			if type(loreId) == "string" and LoreConfig.ById[loreId] then
				discovered[loreId] = true
			end
		end
	end

	playerDiscovered[player] = discovered
	playerLoaded[player] = true

	local count = 0
	for _ in pairs(discovered) do count += 1 end
	print(string.format("[LORE] Loaded %d discovered entries for %s", count, player.Name))

	-- Sync discovered lore to client
	local list = getDiscoveredList(player)
	loreDataSyncRemote:FireClient(player, list)

	return discovered
end

loreSaveFunc.OnInvoke = function(player: Player)
	return getDiscoveredList(player)
end

-- ── Lore discovery ───────────────────────────────────────────────────────

local function discover(player: Player, loreId: string)
	if not playerLoaded[player] then return end

	-- Validate lore ID
	local loreDef = LoreConfig.ById[loreId]
	if not loreDef then return end

	local disc = playerDiscovered[player]
	if not disc then return end

	if disc[loreId] then
		-- Already discovered — let client re-read
		loreAlreadyReadRemote:FireClient(player, loreId)
		return
	end

	-- New discovery
	disc[loreId] = true

	-- Fire discovery event to client
	loreDiscoveredRemote:FireClient(player, loreId)

	-- Fire EventBridge event (AchievementService picks this up via EventMappings)
	local totalDiscovered = 0
	for _ in pairs(disc) do totalDiscovered += 1 end

	EventBridge.fire("lore_discovered", player, {
		loreId = loreId,
		loreTitle = loreDef.title,
		loreArea = loreDef.area,
		loreCategory = loreDef.category,
		totalDiscovered = totalDiscovered,
		totalAvailable = LoreConfig.TotalCount,
	})
end

loreInteractRemote.OnServerEvent:Connect(function(player: Player, loreId: unknown)
	if type(loreId) ~= "string" then return end
	discover(player, loreId)
end)

-- ── World lore props ─────────────────────────────────────────────────────
-- Any BasePart (or Model with a PrimaryPart) carrying a string attribute
-- `LoreId` gets a "Read" ProximityPrompt that discovers the entry on trigger.
-- Place a prop in Studio, set the attribute, done.

local Workspace = game:GetService("Workspace")

local function setupLoreProp(inst: Instance)
	local loreId = inst:GetAttribute("LoreId")
	if type(loreId) ~= "string" then return end

	local promptParent: BasePart? = nil
	if inst:IsA("BasePart") then
		promptParent = inst
	elseif inst:IsA("Model") then
		promptParent = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
	end
	if not promptParent then return end
	if promptParent:FindFirstChild("LorePrompt") then return end

	local loreDef = LoreConfig.ById[loreId]
	if not loreDef then
		warn("[LORE] Unknown LoreId attribute on " .. inst:GetFullName() .. ": " .. loreId)
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LorePrompt"
	prompt.ActionText = "Read"
	prompt.ObjectText = loreDef.title
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptParent

	prompt.Triggered:Connect(function(player)
		discover(player, loreId)
	end)
end

for _, inst in ipairs(Workspace:GetDescendants()) do
	setupLoreProp(inst)
end

Workspace.DescendantAdded:Connect(setupLoreProp)

-- ── Cleanup ──────────────────────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player: Player)
	playerDiscovered[player] = nil
	playerLoaded[player] = nil
end)
