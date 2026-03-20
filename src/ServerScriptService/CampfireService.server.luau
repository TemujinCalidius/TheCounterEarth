-- CampfireService.server.luau
-- Manages campfire inventories and autonomous cooking.
-- Each placed campfire has an input slot and an output slot.
-- Raw food placed in the input cooks over time; cooked items accumulate in output.
-- Campfires are shared stations — any player nearby can add/take items.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local CookingConfig  = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CookingConfig"))
local ItemRegistry   = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))
local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local EventBridge    = require(script.Parent:WaitForChild("EventBridge"))

local CampfireConfig = GameplayConfig.Campfire or {}
local MAX_INPUT_STACK  = CampfireConfig.MaxInputStack  or 10
local MAX_OUTPUT_STACK = CampfireConfig.MaxOutputStack  or 10
local INTERACT_RANGE   = CampfireConfig.InteractRange   or 10
local DEFAULT_COOK_SEC = CampfireConfig.DefaultCookSeconds or 4

-- ── Remotes ─────────────────────────────────────────────────────────────
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local function makeRemote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name   = name
	r.Parent = remotesFolder
	return r
end

local openCampfireRemote   = makeRemote("OpenCampfire")
local campfireStateRemote  = makeRemote("CampfireState")
local campfireAddRemote    = makeRemote("CampfireAddItem")
local campfireTakeRemote   = makeRemote("CampfireTakeItem")

-- ── Inventory cross-service access ──────────────────────────────────────
local bindables    = ServerStorage:WaitForChild("ServerBindables")
local invAdd       = bindables:WaitForChild("InventoryAdd")    :: BindableFunction
local invRemove    = bindables:WaitForChild("InventoryRemove") :: BindableFunction

-- ── Campfire state tracking ─────────────────────────────────────────────

type SlotData = { itemId: string, qty: number }

type CampfireState = {
	input:        SlotData?,
	output:       SlotData?,
	cookProgress: number,
	cookDuration: number,
	lastAddedBy:  Player?,  -- player who last added input (gets cook_complete credit)
}

local campfireStates: { [Model]: CampfireState } = {}
local campfireViewers: { [Model]: { Player } } = {} -- players with UI open

-- ── Helpers ─────────────────────────────────────────────────────────────

local function sanitizeItemId(value: any): string
	if type(value) ~= "string" then return "" end
	local s = string.sub(value, 1, 40)
	if s == "" or not s:match("^[%w_%-%s]+$") then return "" end
	return s
end

local function getCampfirePosition(model: Model): Vector3?
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	return primary and primary.Position
end

local function isPlayerInRange(player: Player, model: Model): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local pos = getCampfirePosition(model)
	if not pos then return false end
	return (root.Position - pos).Magnitude <= INTERACT_RANGE
end

local function getOrCreateState(model: Model): CampfireState
	if campfireStates[model] then return campfireStates[model] end
	local state: CampfireState = {
		input        = nil,
		output       = nil,
		cookProgress = 0,
		cookDuration = 0,
	}
	campfireStates[model] = state
	return state
end

local function serializeState(state: CampfireState): { [string]: any }
	return {
		input        = state.input,
		output       = state.output,
		cookProgress = state.cookProgress,
		cookDuration = state.cookDuration,
	}
end

local function broadcastState(model: Model, state: CampfireState)
	local data = serializeState(state)
	local viewers = campfireViewers[model]
	if viewers then
		for i = #viewers, 1, -1 do
			local plr = viewers[i]
			if plr.Parent and isPlayerInRange(plr, model) then
				campfireStateRemote:FireClient(plr, model, data)
			else
				table.remove(viewers, i)
			end
		end
	end
end

local function addViewer(model: Model, player: Player)
	if not campfireViewers[model] then campfireViewers[model] = {} end
	local viewers = campfireViewers[model]
	for _, p in ipairs(viewers) do
		if p == player then return end
	end
	table.insert(viewers, player)
end

-- ── Loot bag on campfire destroy ────────────────────────────────────────
-- Creates a simple loot bag at the given position with the specified items.

local function createLootBagAtPosition(position: Vector3, items: { SlotData })
	if #items == 0 then return end

	local bag = Instance.new("Model")
	bag.Name = "LootBag"
	bag:SetAttribute("_isLootBag", true)

	local lootBagTemplate = ServerStorage:FindFirstChild("ItemTools") and ServerStorage.ItemTools:FindFirstChild("loot_bag")
	local handle
	if lootBagTemplate then
		local clone = lootBagTemplate:Clone()
		handle = clone:IsA("BasePart") and clone or clone:FindFirstChildWhichIsA("BasePart")
		if handle and handle ~= clone then
			handle.Parent = nil
			clone:Destroy()
		elseif not handle then
			clone:Destroy()
			handle = nil
		end
	end
	if not handle then
		handle = Instance.new("Part")
		handle.Color = Color3.fromRGB(139, 90, 43)
	end
	handle.Size     = Vector3.new(1.2, 1.2, 1.2)
	local rayResult = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -10, 0), RaycastParams.new())
	local groundY = rayResult and rayResult.Position.Y or position.Y
	handle.CFrame   = CFrame.new(position.X, groundY + 0.6, position.Z)
	handle.Anchored = true
	handle.CanCollide = false
	handle.Parent   = bag
	bag.PrimaryPart = handle

	for _, entry in ipairs(items) do
		local v = Instance.new("IntValue")
		v.Name   = entry.itemId
		v.Value  = entry.qty
		v.Parent = bag
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Loot"
	prompt.ObjectText            = "Bag"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.HoldDuration          = 0
	prompt.MaxActivationDistance  = 8
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = handle
	bag.Parent = Workspace

	prompt.Triggered:Connect(function(lootingPlayer)
		if not bag.Parent then return end
		local allAdded = true
		for _, child in ipairs(bag:GetChildren()) do
			if child:IsA("IntValue") then
				local id = sanitizeItemId(child.Name)
				if id ~= "" then
					if invAdd:Invoke(lootingPlayer, id, child.Value) then
						child:Destroy()
					else
						allAdded = false
					end
				end
			end
		end
		-- Check if bag is empty
		local hasItems = false
		for _, child in ipairs(bag:GetChildren()) do
			if child:IsA("IntValue") then hasItems = true; break end
		end
		if not hasItems then bag:Destroy() end
	end)

	-- Auto-destroy after 5 minutes
	local lifetime = (GameplayConfig.Inventory and GameplayConfig.Inventory.DeathBagLifetimeSeconds) or 300
	task.delay(lifetime, function()
		if bag and bag.Parent then bag:Destroy() end
	end)
end

-- ── Register/unregister campfires ───────────────────────────────────────

local function onCampfireDestroying(model: Model)
	local state = campfireStates[model]
	if not state then return end

	-- Drop remaining items as loot bag
	local items: { SlotData } = {}
	if state.input  and state.input.qty  > 0 then table.insert(items, state.input)  end
	if state.output and state.output.qty > 0 then table.insert(items, state.output) end

	if #items > 0 then
		local pos = getCampfirePosition(model) or Vector3.new(0, 5, 0)
		createLootBagAtPosition(pos, items)
	end

	-- Notify viewers that campfire is gone
	local viewers = campfireViewers[model]
	if viewers then
		for _, plr in ipairs(viewers) do
			if plr.Parent then
				campfireStateRemote:FireClient(plr, model, nil) -- nil = closed/destroyed
			end
		end
	end

	campfireStates[model] = nil
	campfireViewers[model] = nil
end

local function registerCampfire(model: Model)
	getOrCreateState(model)
	model.Destroying:Connect(function()
		onCampfireDestroying(model)
	end)
end

-- Scan for existing campfires at startup
for _, obj in ipairs(Workspace:GetDescendants()) do
	if obj:IsA("Model") and obj:GetAttribute("_PlacedItem") == "campfire" then
		registerCampfire(obj)
	end
end

-- Watch for newly placed campfires
Workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("Model") and obj:GetAttribute("_PlacedItem") == "campfire" then
		task.defer(function() registerCampfire(obj) end)
	end
end)

-- ── Remote handlers ─────────────────────────────────────────────────────

openCampfireRemote.OnServerEvent:Connect(function(player, campfireModel)
	if not campfireModel or not campfireModel:IsA("Model") then return end
	if not campfireModel:GetAttribute("_PlacedItem") then return end
	if not isPlayerInRange(player, campfireModel) then return end

	local state = getOrCreateState(campfireModel)
	addViewer(campfireModel, player)
	campfireStateRemote:FireClient(player, campfireModel, serializeState(state))
end)

campfireAddRemote.OnServerEvent:Connect(function(player, campfireModel, rawItemId, rawQty)
	if not campfireModel or not campfireModel:IsA("Model") then return end
	if not campfireModel:GetAttribute("_PlacedItem") then return end
	if not isPlayerInRange(player, campfireModel) then return end

	local itemId = sanitizeItemId(rawItemId)
	if itemId == "" then return end
	local qty = math.floor(tonumber(rawQty) or 0)
	if qty < 1 then return end

	-- Reject items that have no cooking recipe
	if not CookingConfig.Recipes[itemId] then return end

	local state = getOrCreateState(campfireModel)

	-- Input slot: either empty, or must match the same item
	if state.input then
		if state.input.itemId ~= itemId then return end -- different item in input
		local space = MAX_INPUT_STACK - state.input.qty
		if space <= 0 then return end
		qty = math.min(qty, space)
	else
		qty = math.min(qty, MAX_INPUT_STACK)
	end

	-- Remove from player inventory
	if not invRemove:Invoke(player, itemId, qty) then return end

	-- Add to campfire input
	if state.input then
		state.input.qty = state.input.qty + qty
	else
		state.input = { itemId = itemId, qty = qty }
		-- Look up recipe to set cook duration
		local recipe = CookingConfig.Recipes[itemId]
		if recipe then
			state.cookDuration = recipe.cookSeconds or DEFAULT_COOK_SEC
			state.cookProgress = 0
		end
	end
	state.lastAddedBy = player  -- track who added input for cook_complete attribution

	broadcastState(campfireModel, state)
end)

campfireTakeRemote.OnServerEvent:Connect(function(player, campfireModel, rawSlot, rawQty)
	if not campfireModel or not campfireModel:IsA("Model") then return end
	if not campfireModel:GetAttribute("_PlacedItem") then return end
	if not isPlayerInRange(player, campfireModel) then return end

	local slot = rawSlot -- "input" or "output"
	if slot ~= "input" and slot ~= "output" then return end
	local qty = math.floor(tonumber(rawQty) or 0)
	if qty < 1 then return end

	local state = getOrCreateState(campfireModel)
	local slotData: SlotData? = if slot == "input" then state.input else state.output
	if not slotData or slotData.qty <= 0 then return end

	qty = math.min(qty, slotData.qty)

	-- Add to player inventory
	if not invAdd:Invoke(player, slotData.itemId, qty) then return end

	slotData.qty = slotData.qty - qty
	if slotData.qty <= 0 then
		if slot == "input" then
			state.input = nil
			state.cookProgress = 0
			state.cookDuration = 0
		else
			state.output = nil
		end
	end

	broadcastState(campfireModel, state)
end)

-- ── Cooking heartbeat ───────────────────────────────────────────────────

RunService.Heartbeat:Connect(function(dt: number)
	for model, state in pairs(campfireStates) do
		if not model.Parent then
			-- Campfire was destroyed externally
			campfireStates[model] = nil
			campfireViewers[model] = nil
			continue
		end

		-- Only cook if there's something in the input with a valid recipe
		if not state.input or state.input.qty <= 0 then continue end

		local recipe = CookingConfig.Recipes[state.input.itemId]
		if not recipe then continue end -- not a cookable item

		-- Check output slot capacity
		if state.output then
			if state.output.itemId ~= recipe.output then continue end -- mismatched output
			if state.output.qty >= MAX_OUTPUT_STACK then continue end -- output full, pause
		end

		-- Set cook duration if not set
		if state.cookDuration <= 0 then
			state.cookDuration = recipe.cookSeconds or DEFAULT_COOK_SEC
		end

		-- Tick cooking
		state.cookProgress = state.cookProgress + dt

		if state.cookProgress >= state.cookDuration then
			-- One item cooked
			state.cookProgress = state.cookProgress - state.cookDuration

			-- Move 1 from input to output
			state.input.qty = state.input.qty - 1
			if state.output then
				state.output.qty = state.output.qty + 1
			else
				state.output = { itemId = recipe.output, qty = 1 }
			end

			-- Clear input if empty
			if state.input.qty <= 0 then
				state.input = nil
				state.cookProgress = 0
				state.cookDuration = 0
			end

			-- Fire cook_complete for the player who added the input item
			local cookOutputDef = ItemRegistry.get(recipe.output)
			local cookPlayer: Player? = state.lastAddedBy
			if cookPlayer and not cookPlayer.Parent then cookPlayer = nil end
			-- Fallback to campfire placer if the adder left
			if not cookPlayer then
				local placedBy = tonumber(model:GetAttribute("_PlacedBy"))
				cookPlayer = placedBy and Players:GetPlayerByUserId(placedBy) or nil
			end
			EventBridge.fire("cook_complete", cookPlayer, {
				itemId = recipe.output,
				itemName = cookOutputDef and cookOutputDef.displayName or recipe.output,
				profession = "cooking",
				xpGained = 10,
			})

			-- Broadcast on item completion
			broadcastState(model, state)
		end
	end
end)

-- ── Player cleanup ──────────────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player)
	for _, viewers in pairs(campfireViewers) do
		for i = #viewers, 1, -1 do
			if viewers[i] == player then
				table.remove(viewers, i)
			end
		end
	end
end)
