-- InventoryService.server.luau
-- Manages slot-based inventory carried by players.
--
-- Items are stored as pairs of player attributes:
--   InvSlot_N  (string) -- itemId at slot N, or nil if empty
--   InvQty_N   (number) -- quantity at slot N
-- MaxInvSlots  (number) -- set on the player to cap how many slots exist
-- Weight is tracked via CarryWeight and MaxCarryWeight attributes.
--
-- Scatter items in Workspace are Models with a "_ScatterItem" attribute set
-- to their itemId. This service adds ProximityPrompts to them automatically.
--
-- Remotes created here (inside the Remotes folder PlayerStateService owns):
--   UseItem           (RemoteEvent) -- client requests consume of one stack item
--   CraftItem         (RemoteEvent) -- client requests a hand-craft recipe
--   SplitStack        (RemoteEvent) -- client requests splitting a slot into two
--   SwapSlots         (RemoteEvent) -- client swaps two inventory slots (drag-and-drop)
--   DropItem          (RemoteEvent) -- client drops items from a slot to the world
--   PinToSpecificSlot (RemoteEvent) -- client pins an item to a specific hotbar slot
--   SwapHotbarSlots   (RemoteEvent) -- client reorders two hotbar slots

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local ServerStorage     = game:GetService("ServerStorage")
local Workspace         = game:GetService("Workspace")

local ItemRegistry   = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))
local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local CraftingConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CraftingConfig"))

local BASE_MAX_WEIGHT: number   = (GameplayConfig.Inventory and GameplayConfig.Inventory.BasePocketWeight) or 5
local BASE_POCKET_SLOTS: number = (GameplayConfig.Inventory and GameplayConfig.Inventory.PocketSlots) or 5

-- ── Remotes ───────────────────────────────────────────────────────────────
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local function makeRemote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name   = name
	r.Parent = remotesFolder
	return r
end

local useItemRemote           = makeRemote("UseItem")
local craftItemRemote         = makeRemote("CraftItem")
local pinToHotbarRemote       = makeRemote("PinToHotbar")
local pinToSpecificSlotRemote = makeRemote("PinToSpecificSlot")
local unpinFromHotbarRemote   = makeRemote("UnpinFromHotbar")
local splitStackRemote        = makeRemote("SplitStack")
local swapSlotsRemote         = makeRemote("SwapSlots")
local swapHotbarSlotsRemote   = makeRemote("SwapHotbarSlots")
local dropItemRemote          = makeRemote("DropItem")
local placeItemRemote         = makeRemote("PlaceItem")
local openLootBagRemote       = makeRemote("OpenLootBag")
local lootBagStateRemote      = makeRemote("LootBagState")
local takeLootBagItemRemote   = makeRemote("TakeLootBagItem")

-- ── Loot bag viewer tracking ────────────────────────────────────────────
local lootBagViewers: { [Model]: { Player } } = {}

local LOOT_BAG_RANGE = 10

local function serializeBagContents(bag: Model): { { itemId: string, qty: number, displayName: string } }
	local result = {}
	for _, child in ipairs(bag:GetChildren()) do
		if child:IsA("IntValue") and child.Value > 0 then
			local def = ItemRegistry.get(child.Name)
			table.insert(result, {
				itemId = child.Name,
				qty = child.Value,
				displayName = def and def.displayName or child.Name,
			})
		end
	end
	return result
end

local function isBagInRange(plr: Player, bag: Model): boolean
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local bagPart = bag.PrimaryPart or bag:FindFirstChildWhichIsA("BasePart")
	if not bagPart then return false end
	return (root.Position - bagPart.Position).Magnitude <= LOOT_BAG_RANGE
end

local function addBagViewer(bag: Model, plr: Player)
	if not lootBagViewers[bag] then
		lootBagViewers[bag] = {}
	end
	for _, p in ipairs(lootBagViewers[bag]) do
		if p == plr then return end
	end
	table.insert(lootBagViewers[bag], plr)
end

local function broadcastBagState(bag: Model)
	local viewers = lootBagViewers[bag]
	if not viewers then return end
	local data = serializeBagContents(bag)
	for i = #viewers, 1, -1 do
		local p = viewers[i]
		if not p.Parent or not isBagInRange(p, bag) then
			table.remove(viewers, i)
		else
			lootBagStateRemote:FireClient(p, bag, data)
		end
	end
end

local function notifyBagDestroyed(bag: Model)
	local viewers = lootBagViewers[bag]
	if viewers then
		for _, p in ipairs(viewers) do
			lootBagStateRemote:FireClient(p, bag, nil)
		end
	end
	lootBagViewers[bag] = nil
end

-- ── Publish ghost-ready templates to ReplicatedStorage for client preview ──

local function publishPlaceableGhosts()
	local ghostsFolder = Instance.new("Folder")
	ghostsFolder.Name = "PlaceableGhosts"
	ghostsFolder.Parent = ReplicatedStorage

	local itemToolsFolder = ServerStorage:FindFirstChild("ItemTools")
	if not itemToolsFolder then return end

	for _, template in ipairs(itemToolsFolder:GetChildren()) do
		if template:IsA("Model") then
			local def = ItemRegistry.get(template.Name)
			if def and def.category == "placeable" then
				local ghost = template:Clone()
				for _, desc in ipairs(ghost:GetDescendants()) do
					if desc:IsA("Fire") or desc:IsA("Smoke") or desc:IsA("ParticleEmitter") then
						desc.Enabled = false
					elseif desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
						desc.Enabled = false
					elseif desc:IsA("Sound") then
						desc.Playing = false
						desc.PlayOnRemove = false
					end
				end
				ghost.Parent = ghostsFolder
			end
		end
	end
end
publishPlaceableGhosts()

-- ── Consume-effect BindableEvent (created by PlayerStateService) ──────────
local consumeEffectEvent: BindableEvent =
	ServerStorage:WaitForChild("ServerBindables"):WaitForChild("ConsumeEffect") :: BindableEvent

-- ── Helpers ───────────────────────────────────────────────────────────────

local function sanitizeItemId(value: any): string
	if type(value) ~= "string" then return "" end
	local s = string.sub(value, 1, 40)
	if s == "" or not s:match("^[%w_%-%s]+$") then return "" end
	return s
end

-- ── Slot helpers ──────────────────────────────────────────────────────────

local function getMaxSlots(player: Player): number
	return math.max(1, math.floor(tonumber(player:GetAttribute("MaxInvSlots")) or BASE_POCKET_SLOTS))
end

local function getSlotItemId(player: Player, n: number): string
	return sanitizeItemId(player:GetAttribute("InvSlot_" .. n) or "")
end

local function getSlotQty(player: Player, n: number): number
	return math.max(0, math.floor(tonumber(player:GetAttribute("InvQty_" .. n)) or 0))
end

local function setSlot(player: Player, n: number, itemId: string, qty: number)
	if qty <= 0 then
		player:SetAttribute("InvSlot_" .. n, nil)
		player:SetAttribute("InvQty_" .. n, nil)
		player:SetAttribute("InvExpires_" .. n, nil)
		player:SetAttribute("InvDurability_" .. n, nil)
	else
		player:SetAttribute("InvSlot_" .. n, itemId)
		player:SetAttribute("InvQty_" .. n, math.floor(qty + 0.5))
	end
end

-- ── Per-item expiry helpers ──────────────────────────────────────────────

local function getSlotExpiries(player: Player, n: number): { number }
	local str = player:GetAttribute("InvExpires_" .. n)
	if type(str) ~= "string" or str == "" then return {} end
	local result = {}
	for ts in string.gmatch(str, "[^,]+") do
		local num = tonumber(ts)
		if num then table.insert(result, num) end
	end
	table.sort(result)
	return result
end

local function setSlotExpiries(player: Player, n: number, expiries: { number }?)
	if not expiries or #expiries == 0 then
		player:SetAttribute("InvExpires_" .. n, nil)
	else
		local parts = {}
		for _, ts in ipairs(expiries) do
			table.insert(parts, tostring(math.floor(ts)))
		end
		player:SetAttribute("InvExpires_" .. n, table.concat(parts, ","))
	end
end

-- ── Per-item durability helpers ────────────────────────────────────────────

local function getSlotDurabilities(player: Player, n: number): { number }
	local str = player:GetAttribute("InvDurability_" .. n)
	if type(str) ~= "string" or str == "" then return {} end
	local result = {}
	for d in string.gmatch(str, "[^,]+") do
		local num = tonumber(d)
		if num then table.insert(result, num) end
	end
	return result
end

local function setSlotDurabilities(player: Player, n: number, durabilities: { number }?)
	if not durabilities or #durabilities == 0 then
		player:SetAttribute("InvDurability_" .. n, nil)
	else
		local parts = {}
		for _, d in ipairs(durabilities) do
			table.insert(parts, tostring(math.floor(d)))
		end
		player:SetAttribute("InvDurability_" .. n, table.concat(parts, ","))
	end
end

local function getTotalQty(player: Player, itemId: string): number
	local total = 0
	for n = 1, getMaxSlots(player) do
		if getSlotItemId(player, n) == itemId then
			total += getSlotQty(player, n)
		end
	end
	return total
end

-- ── Weight ────────────────────────────────────────────────────────────────

local function computeWeight(player: Player): number
	local total = 0
	for n = 1, getMaxSlots(player) do
		local itemId = getSlotItemId(player, n)
		if itemId ~= "" then
			local def = ItemRegistry.get(itemId)
			if def then
				total += def.weight * getSlotQty(player, n)
			end
		end
	end
	return total
end

local function refreshWeight(player: Player)
	player:SetAttribute("CarryWeight", math.floor(computeWeight(player) * 100 + 0.5) / 100)
end

-- ── Add / Remove ──────────────────────────────────────────────────────────

local function addQty(player: Player, itemId: string, amount: number): boolean
	local def = ItemRegistry.get(itemId)
	if not def then return false end

	local maxWeight = tonumber(player:GetAttribute("MaxCarryWeight")) or BASE_MAX_WEIGHT
	if computeWeight(player) + def.weight * amount > maxWeight + 0.001 then
		return false
	end

	local maxSlots  = getMaxSlots(player)
	local remaining = amount
	local perishSec = def.perishSeconds  -- nil if not perishable
	local durMax    = def.durabilityMax  -- nil if no durability

	-- Fill partial stacks first
	for n = 1, maxSlots do
		if remaining <= 0 then break end
		if getSlotItemId(player, n) == itemId then
			local qty    = getSlotQty(player, n)
			local canAdd = math.min(remaining, def.stackMax - qty)
			if canAdd > 0 then
				setSlot(player, n, itemId, qty + canAdd)
				if perishSec then
					local expiries = getSlotExpiries(player, n)
					local now = os.time()
					for _ = 1, canAdd do
						table.insert(expiries, now + perishSec)
					end
					table.sort(expiries)
					setSlotExpiries(player, n, expiries)
				end
				if durMax then
					local durs = getSlotDurabilities(player, n)
					for _ = 1, canAdd do
						table.insert(durs, durMax)
					end
					setSlotDurabilities(player, n, durs)
				end
				remaining -= canAdd
			end
		end
	end

	-- Fill empty slots
	for n = 1, maxSlots do
		if remaining <= 0 then break end
		if getSlotItemId(player, n) == "" then
			local take = math.min(remaining, def.stackMax)
			setSlot(player, n, itemId, take)
			if perishSec then
				local now = os.time()
				local expiries = {}
				for _ = 1, take do
					table.insert(expiries, now + perishSec)
				end
				setSlotExpiries(player, n, expiries)
			end
			if durMax then
				local durs = {}
				for _ = 1, take do
					table.insert(durs, durMax)
				end
				setSlotDurabilities(player, n, durs)
			end
			remaining -= take
		end
	end

	refreshWeight(player)
	return remaining == 0
end

local function removeQty(player: Player, itemId: string, amount: number): boolean
	if getTotalQty(player, itemId) < amount then return false end

	local maxSlots  = getMaxSlots(player)
	local remaining = amount
	for n = maxSlots, 1, -1 do
		if remaining <= 0 then break end
		if getSlotItemId(player, n) == itemId then
			local qty  = getSlotQty(player, n)
			local take = math.min(remaining, qty)
			local newQty = qty - take
			-- Trim oldest expiry timestamps (consumed first)
			if newQty > 0 then
				local expiries = getSlotExpiries(player, n)
				if #expiries > 0 then
					local trimmed = {}
					for i = take + 1, #expiries do
						table.insert(trimmed, expiries[i])
					end
					setSlotExpiries(player, n, trimmed)
				end
				-- Trim durability values from front (first items consumed first)
				local durs = getSlotDurabilities(player, n)
				if #durs > 0 then
					local trimmedDurs = {}
					for i = take + 1, #durs do
						table.insert(trimmedDurs, durs[i])
					end
					setSlotDurabilities(player, n, trimmedDurs)
				end
			end
			setSlot(player, n, itemId, newQty)
			remaining -= take
		end
	end

	refreshWeight(player)
	return true
end

-- ── Hotbar helpers ────────────────────────────────────────────────────────

local HOTBAR_SIZE       = 9
local ITEM_TOOLS_FOLDER = "ItemTools"

local function slotAttrName(slot: number): string
	return "HotbarSlot" .. tostring(slot)
end

local function findFreeHotbarSlot(player: Player): number?
	for slot = 1, HOTBAR_SIZE do
		local v = player:GetAttribute(slotAttrName(slot))
		if type(v) ~= "string" or v == "" then return slot end
	end
	return nil
end

-- Looks for a Studio-placed Model or MeshPart in ServerStorage > ScatterModels.
local function findScatterTemplate(itemId: string): Instance?
	local folder = ServerStorage:FindFirstChild("ScatterModels")
	if not folder then return nil end
	local tmpl = folder:FindFirstChild(itemId)
	if tmpl and (tmpl:IsA("Model") or tmpl:IsA("BasePart")) then return tmpl end
	return nil
end

local function spawnToolInBackpack(player: Player, itemId: string)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end
	if backpack:FindFirstChild(itemId) or
		(player.Character and player.Character:FindFirstChild(itemId)) then return end

	local def = ItemRegistry.get(itemId)

	-- Clear any stale cached template so we always use the latest build
	local toolsFolder = ServerStorage:FindFirstChild(ITEM_TOOLS_FOLDER)
	local stale = toolsFolder and toolsFolder:FindFirstChild(itemId)
	if stale and stale:GetAttribute("_autoBuild") then
		stale:Destroy()
		stale = nil
	end

	-- Use an existing hand-placed template (e.g. swords from ToolInventoryService)
	local template = toolsFolder and toolsFolder:FindFirstChild(itemId)
	if template and template:IsA("Tool") then
		local clone = template:Clone()
		clone.Name  = itemId
		clone:SetAttribute("_fromInv", true)
		clone.Parent = backpack
		return
	end

	-- Build a Tool from a Studio-placed scatter template (ServerStorage/ScatterModels)
	local scatterTemplate = findScatterTemplate(itemId)
	if scatterTemplate then
		-- Template can be a bare MeshPart or a Model containing one
		local meshSource: BasePart? = nil
		if scatterTemplate:IsA("BasePart") then
			meshSource = scatterTemplate
		else
			meshSource = scatterTemplate:FindFirstChildWhichIsA("MeshPart", true)
				or scatterTemplate:FindFirstChildWhichIsA("BasePart", true)
		end

		if meshSource then
			local tool = Instance.new("Tool")
			tool.Name    = itemId
			tool.ToolTip = def and def.displayName or itemId
			tool:SetAttribute("_fromInv", true)
			tool.CanBeDropped         = false
			tool.ManualActivationOnly = true

			-- Use the mesh itself as the Handle (no weld, no second part)
			local handle     = meshSource:Clone()
			handle.Name      = "Handle"
			handle.Size      = (def and def.meshSize) or Vector3.new(0.5, 0.5, 0.5)
			handle.Anchored  = false
			handle.CanCollide = false
			handle.CanTouch  = false
			handle.CanQuery  = false
			handle.Massless  = true
			handle.Parent    = tool

			tool.Grip = CFrame.new(0, -0.4, 0)

			-- Cache for future spawns (marked so we can clear stale versions)
			tool:SetAttribute("_autoBuild", true)
			if toolsFolder then
				local tmpl  = tool:Clone()
				tmpl.Parent = toolsFolder
			end

			tool.Parent = backpack
			return
		end
	end

	-- Fallback: handle-less tool
	local tool = Instance.new("Tool")
	tool.Name           = itemId
	tool.RequiresHandle = false
	tool.ToolTip        = def and def.displayName or itemId
	tool:SetAttribute("_fromInv", true)
	tool.Parent = backpack
end

local function clearHotbarSlot(player: Player, slot: number)
	local itemId = tostring(player:GetAttribute(slotAttrName(slot)) or "")
	player:SetAttribute(slotAttrName(slot), nil)
	if itemId == "" then return end
	local function tryDestroy(container: Instance?)
		if not container then return end
		local t = container:FindFirstChild(itemId)
		if t and t:IsA("Tool") and t:GetAttribute("_fromInv") then t:Destroy() end
	end
	if player.Character then
		local h = player.Character:FindFirstChildOfClass("Humanoid")
		if h then h:UnequipTools() end
		tryDestroy(player.Character)
	end
	tryDestroy(player:FindFirstChildOfClass("Backpack"))
end

-- ── Hotbar orphan cleanup ────────────────────────────────────────────────
-- Call after any operation that removes items from inventory.
-- Clears hotbar pins whose itemId no longer exists in any inventory slot.
local function cleanOrphanedHotbarPins(player: Player)
	for slot = 1, HOTBAR_SIZE do
		local pinned = tostring(player:GetAttribute(slotAttrName(slot)) or "")
		if pinned ~= "" and getTotalQty(player, pinned) == 0 then
			clearHotbarSlot(player, slot)
		end
	end
end

-- ── Loot bag ──────────────────────────────────────────────────────────────

local LOOT_BAG_MERGE_RADIUS = 4 -- studs: merge into existing bag if within this range

local function findNearbyLootBag(position: Vector3, excludeDeathBags: boolean): Model?
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("_isLootBag") then
			if excludeDeathBags and obj:GetAttribute("_isDeathBag") then continue end
			local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
			if part and (part.Position - position).Magnitude <= LOOT_BAG_MERGE_RADIUS then
				return obj
			end
		end
	end
	return nil
end

local function createLootBag(player: Player, items: { { itemId: string, qty: number } })
	local character = player.Character
	local rootPart  = character and character:FindFirstChild("HumanoidRootPart")
	local origin    = rootPart and rootPart.CFrame or CFrame.new(0, 5, 0)
	local dropCFrame = origin * CFrame.new(0, -2.5, -3.5)

	-- Try to merge into an existing nearby non-death loot bag
	local existing = findNearbyLootBag(dropCFrame.Position, true)
	if existing then
		for _, entry in ipairs(items) do
			local child = existing:FindFirstChild(entry.itemId)
			if child and child:IsA("IntValue") then
				child.Value = child.Value + entry.qty
			else
				local v = Instance.new("IntValue")
				v.Name   = entry.itemId
				v.Value  = entry.qty
				v.Parent = existing
			end
		end
		-- Update any viewers currently looking at this bag
		broadcastBagState(existing)
		return
	end

	local lifetime = (GameplayConfig.Inventory and GameplayConfig.Inventory.DeathBagLifetimeSeconds) or 300

	local bag = Instance.new("Model")
	bag.Name = "LootBag"
	bag:SetAttribute("_isLootBag", true)
	bag:SetAttribute("_SpawnTime", os.time())
	bag:SetAttribute("_Lifetime", lifetime)

	local handle = Instance.new("Part")
	handle.Name          = "Handle"
	handle.Size          = Vector3.new(1.2, 1.2, 1.2)
	handle.CFrame        = dropCFrame
	handle.Anchored      = true
	handle.BrickColor    = BrickColor.new("Reddish brown")
	handle.Material      = Enum.Material.Fabric
	handle.Shape         = Enum.PartType.Ball
	handle.TopSurface    = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent        = bag
	bag.PrimaryPart      = handle

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
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = handle
	bag.Parent = Workspace

	prompt.Triggered:Connect(function(lootingPlayer)
		if not bag.Parent then return end
		addBagViewer(bag, lootingPlayer)
		lootBagStateRemote:FireClient(lootingPlayer, bag, serializeBagContents(bag))
	end)

	task.delay(lifetime, function()
		if bag and bag.Parent then
			notifyBagDestroyed(bag)
			bag:Destroy()
		end
	end)
end

-- ── Player init ───────────────────────────────────────────────────────────

local function initPlayer(player: Player)
	player:SetAttribute("CarryWeight",    0)
	player:SetAttribute("MaxCarryWeight", BASE_MAX_WEIGHT)

	-- Refresh weight whenever any slot attribute changes (handles writes from
	-- other services like ToolInventoryService that bypass addQty).
	player.AttributeChanged:Connect(function(attrName)
		if attrName:sub(1, 9) == "InvSlot_" or attrName:sub(1, 7) == "InvQty_" then
			refreshWeight(player)
		end
	end)

	task.defer(function()
		if player.Parent then refreshWeight(player) end
	end)

	-- On respawn, re-grant Tool instances for all pinned hotbar slots.
	player.CharacterAdded:Connect(function()
		task.defer(function()
			if not player.Parent then return end
			for slot = 1, HOTBAR_SIZE do
				local itemId = tostring(player:GetAttribute(slotAttrName(slot)) or "")
				if itemId ~= "" then
					spawnToolInBackpack(player, itemId)
				end
			end
		end)
	end)
end

-- ── Scatter item pickup ───────────────────────────────────────────────────

local SCATTER_ATTR    = "_ScatterItem"
local SCATTER_MANAGED = "_ScatterManaged"

-- ── Hit-to-harvest system ───────────────────────────────────────────────
-- Each left-click = one hit.  Server validates tool, range, cooldown,
-- deducts node HP, gives yield, destroys node at 0 HP.

local harvestHitRemote     = makeRemote("HarvestHit")
local harvestResultRemote  = makeRemote("HarvestResult")
local harvestNotifyRemote  = makeRemote("HarvestNotify")

-- Returns the harvestTags of the player's currently equipped tool, or nil.
local function getEquippedHarvestTags(player: Player): { string }?
	local eqSlot = math.floor(tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0)
	if eqSlot < 1 or eqSlot > HOTBAR_SIZE then return nil end
	local eqItemId = tostring(player:GetAttribute(slotAttrName(eqSlot)) or "")
	if eqItemId == "" then return nil end
	local eqDef = ItemRegistry.get(eqItemId)
	if not eqDef or not eqDef.tool or not eqDef.tool.harvestTags then return nil end
	return eqDef.tool.harvestTags
end

local function hasHarvestTag(player: Player, tag: string): boolean
	local tags = getEquippedHarvestTags(player)
	if not tags then return false end
	for _, t in tags do
		if t == tag then return true end
	end
	return false
end

local HARVEST_MAX_DIST = 8
local lastHitTime: { [Player]: number } = {}

harvestHitRemote.OnServerEvent:Connect(function(player, targetModel)
	-- Validate target
	if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end
	if not targetModel.Parent or not targetModel:IsDescendantOf(Workspace) then return end

	local itemId = sanitizeItemId(targetModel:GetAttribute(SCATTER_ATTR) or "")
	if itemId == "" then return end

	local nodeHP = tonumber(targetModel:GetAttribute("_NodeHealth")) or 0
	if nodeHP <= 0 then return end

	-- Range check
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local modelPart = targetModel.PrimaryPart or targetModel:FindFirstChildWhichIsA("BasePart")
	if not root or not modelPart then return end
	if (root.Position - modelPart.Position).Magnitude > HARVEST_MAX_DIST then return end

	-- Server-side cooldown (prevent fast-fire exploits)
	local cooldown = tonumber(targetModel:GetAttribute("_HitCooldown")) or 0.8
	local now = os.clock()
	if lastHitTime[player] and (now - lastHitTime[player]) < cooldown * 0.9 then return end
	lastHitTime[player] = now

	-- Tool check
	local requireTool = targetModel:GetAttribute("_RequireTool")
	if requireTool and not hasHarvestTag(player, requireTool) then
		harvestNotifyRemote:FireClient(player, "You need a knife to harvest this")
		return
	end

	-- Player must be alive
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Calculate yield
	local yieldMin = tonumber(targetModel:GetAttribute("_HarvestYieldMin")) or 1
	local yieldMax = tonumber(targetModel:GetAttribute("_HarvestYieldMax")) or 1
	local yield = math.random(yieldMin, yieldMax)

	-- Give items (block hit if inventory full — node keeps its HP)
	local added = addQty(player, itemId, yield)
	if not added then
		harvestNotifyRemote:FireClient(player, "Inventory full!")
		return
	end

	-- Deduct node HP
	local newHP = nodeHP - 1
	targetModel:SetAttribute("_NodeHealth", newHP)

	-- Decrement equipped tool durability
	local eqSlot = math.floor(tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0)
	if eqSlot >= 1 and eqSlot <= HOTBAR_SIZE then
		local toolItemId = tostring(player:GetAttribute(slotAttrName(eqSlot)) or "")
		local toolDef = toolItemId ~= "" and ItemRegistry.get(toolItemId) or nil
		if toolDef and toolDef.durabilityMax then
			-- Find inventory slot holding this tool
			local toolInvSlot: number? = nil
			for n = 1, getMaxSlots(player) do
				if getSlotItemId(player, n) == toolItemId then
					toolInvSlot = n
					break
				end
			end
			if toolInvSlot then
				local durs = getSlotDurabilities(player, toolInvSlot)
				if #durs > 0 then
					durs[1] -= 1
					if durs[1] <= 0 then
						-- First item in stack broke
						table.remove(durs, 1)
						local toolQty = getSlotQty(player, toolInvSlot)
						if toolQty <= 1 then
							-- Last one in stack — clear slot and unequip
							setSlot(player, toolInvSlot, toolItemId, 0)
							player:SetAttribute(slotAttrName(eqSlot), nil)
							player:SetAttribute("HotbarEquippedSlot", nil)
							-- Destroy held tool model
							local char = player.Character
							if char then
								local toolInstance = char:FindFirstChild(toolItemId)
								if toolInstance then toolInstance:Destroy() end
							end
							local bp = player:FindFirstChildOfClass("Backpack")
							if bp then
								local toolInBp = bp:FindFirstChild(toolItemId)
								if toolInBp then toolInBp:Destroy() end
							end
						else
							setSlot(player, toolInvSlot, toolItemId, toolQty - 1)
							setSlotDurabilities(player, toolInvSlot, durs)
						end
						refreshWeight(player)
						harvestNotifyRemote:FireClient(player, "Your " .. toolDef.displayName .. " broke!")
					else
						setSlotDurabilities(player, toolInvSlot, durs)
					end
				end
			end
		end
	end

	-- Get display name for floating text
	local def = ItemRegistry.get(itemId)
	local displayName = def and def.displayName or itemId

	-- Notify harvesting player of successful hit (yield text + shake + sound)
	local nodeDestroyed = newHP <= 0
	harvestResultRemote:FireClient(player, targetModel, yield, displayName, nodeDestroyed)

	-- Notify nearby players (shake + sound only, no yield text)
	local nodeRoot = targetModel.PrimaryPart or targetModel:FindFirstChildWhichIsA("BasePart")
	if nodeRoot then
		local nodePos = nodeRoot.Position
		for _, other in Players:GetPlayers() do
			if other ~= player then
				local otherChar = other.Character
				local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
				if otherRoot and (otherRoot.Position - nodePos).Magnitude <= 40 then
					harvestResultRemote:FireClient(other, targetModel, 0, "", nodeDestroyed)
				end
			end
		end
	end

	-- Destroy node if HP depleted (AncestryChanged in ScatterSpawnService triggers respawn)
	-- Delay slightly so client can play final hit feedback (shake, sound, floating text)
	if nodeDestroyed then
		-- Disable further interaction immediately
		for _, desc in ipairs(targetModel:GetDescendants()) do
			if desc:IsA("ProximityPrompt") then desc.Enabled = false end
		end
		task.delay(1.4, function()
			if targetModel and targetModel.Parent then
				targetModel:Destroy()
			end
		end)
	end
end)

-- Clean up cooldown tracking on leave
Players.PlayerRemoving:Connect(function(player)
	lastHitTime[player] = nil
end)

-- ── Setup scatter items ─────────────────────────────────────────────────

local function setupScatterItem(model: Model)
	if model:GetAttribute(SCATTER_MANAGED) then return end
	local itemId = sanitizeItemId(model:GetAttribute(SCATTER_ATTR) or "")
	if itemId == "" then return end
	local def = ItemRegistry.get(itemId)
	if not def then return end
	local rootPart = model.PrimaryPart or model:FindFirstChildOfClass("BasePart")
	if not rootPart then return end

	model:SetAttribute(SCATTER_MANAGED, true)

	local nodeHealth = tonumber(model:GetAttribute("_NodeHealth")) or 0

	-- Harvest nodes use left-click instead of ProximityPrompt.
	-- Add a floating name label so players can identify the resource.
	if nodeHealth > 0 then
		local bb = Instance.new("BillboardGui")
		bb.Name              = "GatherLabel"
		bb.Adornee           = rootPart
		bb.Size              = UDim2.new(0, 120, 0, 20)
		bb.StudsOffset       = Vector3.new(0, 2, 0)
		bb.AlwaysOnTop       = false
		bb.MaxDistance        = 15
		bb.Parent            = model

		local label = Instance.new("TextLabel")
		label.Size                  = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text                  = def.displayName
		label.TextColor3            = Color3.fromRGB(220, 230, 200)
		label.Font                  = Enum.Font.GothamBold
		label.TextSize              = 14
		label.TextStrokeTransparency = 0.4
		label.TextStrokeColor3      = Color3.fromRGB(0, 0, 0)
		label.Parent                = bb
		return
	end

	local prompt = rootPart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = rootPart
	end
	prompt.ObjectText            = def.displayName
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.HoldDuration          = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight   = false
	prompt.ActionText = "Pick Up"

	prompt.Triggered:Connect(function(player)
		if not model or not model.Parent then return end
		if addQty(player, itemId, 1) then model:Destroy() end
	end)
end

for _, desc in ipairs(Workspace:GetDescendants()) do
	if desc:IsA("Model") and desc:GetAttribute(SCATTER_ATTR) then
		setupScatterItem(desc)
	end
end
Workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") and inst:GetAttribute(SCATTER_ATTR) then
		task.defer(function() setupScatterItem(inst) end)
	end
end)

-- ── Cross-service inventory access (BindableFunctions) ───────────────────
-- Allows other server scripts (CampfireService, etc.) to add/remove items
-- from player inventories via ServerBindables.

local invBindables = ServerStorage:WaitForChild("ServerBindables")

local invAddFunc = Instance.new("BindableFunction")
invAddFunc.Name = "InventoryAdd"
invAddFunc.Parent = invBindables
invAddFunc.OnInvoke = function(player: Player, itemId: string, qty: number): boolean
	local id = sanitizeItemId(itemId)
	if id == "" or qty < 1 then return false end
	return addQty(player, id, qty)
end

local invRemoveFunc = Instance.new("BindableFunction")
invRemoveFunc.Name = "InventoryRemove"
invRemoveFunc.Parent = invBindables
invRemoveFunc.OnInvoke = function(player: Player, itemId: string, qty: number): boolean
	local id = sanitizeItemId(itemId)
	if id == "" or qty < 1 then return false end
	return removeQty(player, id, qty)
end

local invGetQtyFunc = Instance.new("BindableFunction")
invGetQtyFunc.Name = "InventoryGetQty"
invGetQtyFunc.Parent = invBindables
invGetQtyFunc.OnInvoke = function(player: Player, itemId: string): number
	local id = sanitizeItemId(itemId)
	if id == "" then return 0 end
	return getTotalQty(player, id)
end

-- ── Death loot bag (owner-only beacon, countdown timer) ──────────────────

local deathBagBeaconRemote = makeRemote("DeathBagBeacon")

local function createDeathLootBag(player: Player, items: { { itemId: string, qty: number } }, deathCFrame: CFrame)
	if #items == 0 then return end

	local dropCFrame = deathCFrame * CFrame.new(0, -2.5, -3.5)

	local bag = Instance.new("Model")
	bag.Name = "LootBag"
	bag:SetAttribute("_isLootBag", true)
	bag:SetAttribute("_isDeathBag", true)
	bag:SetAttribute("_OwnerUserId", player.UserId)
	bag:SetAttribute("_SpawnTime", os.time())

	local lifetime = (GameplayConfig.Inventory and GameplayConfig.Inventory.DeathBagLifetimeSeconds) or 300
	bag:SetAttribute("_Lifetime", lifetime)

	local handle = Instance.new("Part")
	handle.Name          = "Handle"
	handle.Size          = Vector3.new(1.2, 1.2, 1.2)
	handle.CFrame        = dropCFrame
	handle.Anchored      = true
	handle.BrickColor    = BrickColor.new("Reddish brown")
	handle.Material      = Enum.Material.Fabric
	handle.Shape         = Enum.PartType.Ball
	handle.TopSurface    = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent        = bag
	bag.PrimaryPart      = handle

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
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = handle
	bag.Parent = Workspace

	prompt.Triggered:Connect(function(lootingPlayer)
		if not bag.Parent then return end
		addBagViewer(bag, lootingPlayer)
		lootBagStateRemote:FireClient(lootingPlayer, bag, serializeBagContents(bag))
	end)

	task.delay(lifetime, function()
		if bag and bag.Parent then
			notifyBagDestroyed(bag)
			bag:Destroy()
		end
	end)

	-- Fire beacon to the owner client
	deathBagBeaconRemote:FireClient(player, bag, lifetime)
end

-- ── Cross-service loot bag creation (BindableFunction) ──────────────────
-- Allows other server scripts (TradingService, etc.) to drop loot bags.

local invCreateLootBagFunc = Instance.new("BindableFunction")
invCreateLootBagFunc.Name = "CreateLootBag"
invCreateLootBagFunc.Parent = invBindables
invCreateLootBagFunc.OnInvoke = function(plr: Player, items: { { itemId: string, qty: number } })
	createLootBag(plr, items)
end

-- ── Dump all inventory (called by PlayerStateService on death) ───────────

local invDumpAllFunc = Instance.new("BindableFunction")
invDumpAllFunc.Name = "InventoryDumpAll"
invDumpAllFunc.Parent = invBindables
invDumpAllFunc.OnInvoke = function(player: Player, deathCFrame: CFrame)
	local maxSlots = getMaxSlots(player)
	local items: { { itemId: string, qty: number } } = {}

	-- Collect all inventory contents
	for n = 1, maxSlots do
		local itemId = getSlotItemId(player, n)
		local qty    = getSlotQty(player, n)
		if itemId ~= "" and qty > 0 then
			table.insert(items, { itemId = itemId, qty = qty })
			setSlot(player, n, "", 0)
			setSlotExpiries(player, n, nil)
		end
	end

	-- Clear hotbar slots
	for slot = 1, HOTBAR_SIZE do
		player:SetAttribute(slotAttrName(slot), nil)
	end
	player:SetAttribute("HotbarEquippedSlot", nil)

	-- Destroy any equipped tool in character
	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
	end

	-- Clear backpack tools
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
	end

	-- Refresh weight to 0
	refreshWeight(player)

	-- Create death loot bag at death position
	createDeathLootBag(player, items, deathCFrame)
end

-- ── UseItem ───────────────────────────────────────────────────────────────

local EAT_COOLDOWN = 2.0  -- seconds; must finish channel before next use
local lastEatTime: { [Player]: number } = {}

useItemRemote.OnServerEvent:Connect(function(player, rawItemId)
	local itemId = sanitizeItemId(rawItemId)
	if itemId == "" then return end
	local def = ItemRegistry.get(itemId)
	if not def or not def.onConsume then return end

	-- Server-side cooldown (anti-spam)
	local now = os.clock()
	if lastEatTime[player] and now - lastEatTime[player] < EAT_COOLDOWN then return end
	lastEatTime[player] = now

	if not removeQty(player, itemId, 1) then return end

	local effects = def.onConsume
	if type(effects.health) == "number" and effects.health ~= 0 then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			if effects.health > 0 then
				humanoid.Health = math.min(humanoid.Health + effects.health, humanoid.MaxHealth)
			else
				humanoid:TakeDamage(-effects.health)
			end
		end
	end

	local payload: { [string]: any } = {}
	if type(effects.hunger)  == "number" then payload.hunger  = effects.hunger  end
	if type(effects.thirst)  == "number" then payload.thirst  = effects.thirst  end
	if type(effects.fatigue) == "number" then payload.fatigue = effects.fatigue end
	if type(effects.energy)  == "number" then payload.energy  = effects.energy  end
	if type(effects.poison)  == "number" and effects.poison > 0 then payload.poison = effects.poison end
	if def.tags then
		for _, tag in ipairs(def.tags) do
			if tag == "stops_bleed"   then payload.stopBleed  = true end
			if tag == "clears_poison" then payload.stopPoison = true end
		end
	end
	if next(payload) then consumeEffectEvent:Fire(player, payload) end

	cleanOrphanedHotbarPins(player)
end)

-- ── CraftItem ─────────────────────────────────────────────────────────────

craftItemRemote.OnServerEvent:Connect(function(player, rawRecipeId)
	local recipeId = sanitizeItemId(rawRecipeId)
	if recipeId == "" then return end
	local recipe = nil
	for _, r in ipairs(CraftingConfig.Recipes) do
		if r.id == recipeId then recipe = r; break end
	end
	if not recipe then return end
	if not ItemRegistry.get(recipe.output.itemId) then return end
	for _, ing in ipairs(recipe.ingredients) do
		if getTotalQty(player, ing.itemId) < ing.qty then return end
	end
	for _, ing in ipairs(recipe.ingredients) do
		removeQty(player, ing.itemId, ing.qty)
	end
	addQty(player, recipe.output.itemId, recipe.output.qty)
	cleanOrphanedHotbarPins(player)
end)

-- ── PinToHotbar (first free slot) ─────────────────────────────────────────

pinToHotbarRemote.OnServerEvent:Connect(function(player, rawItemId)
	local itemId = sanitizeItemId(rawItemId)
	if itemId == "" then return end
	local def = ItemRegistry.get(itemId)
	if not def then return end
	if def.category ~= "tool" and def.category ~= "weapon" and def.category ~= "placeable" and not def.onConsume then return end
	if getTotalQty(player, itemId) < 1 then return end

	local slot = findFreeHotbarSlot(player)
	if not slot then return end

	player:SetAttribute(slotAttrName(slot), itemId)
	spawnToolInBackpack(player, itemId)

	local equipped = math.floor(tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0)
	if equipped < 1 or equipped > HOTBAR_SIZE then
		player:SetAttribute("HotbarEquippedSlot", slot)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local backpack  = player:FindFirstChildOfClass("Backpack")
		if humanoid and backpack then
			local tool = backpack:FindFirstChild(itemId)
			if tool and tool:IsA("Tool") then humanoid:EquipTool(tool) end
		end
	end
end)

-- ── PinToSpecificSlot (drag to exact hotbar slot) ─────────────────────────

pinToSpecificSlotRemote.OnServerEvent:Connect(function(player, rawItemId, rawTargetSlot)
	local itemId     = sanitizeItemId(rawItemId)
	local targetSlot = math.floor(tonumber(rawTargetSlot) or 0)
	if itemId == "" or targetSlot < 1 or targetSlot > HOTBAR_SIZE then return end

	local def = ItemRegistry.get(itemId)
	if not def then return end
	-- No category gate: if the player explicitly drags an item to the hotbar, allow it.
	if getTotalQty(player, itemId) < 1 then return end

	local current = tostring(player:GetAttribute(slotAttrName(targetSlot)) or "")
	if current == itemId then return end  -- already pinned here

	-- Overwrite: clear old occupant (it stays in inventory, just unpinned visually).
	if current ~= "" then
		clearHotbarSlot(player, targetSlot)
	end

	player:SetAttribute(slotAttrName(targetSlot), itemId)
	spawnToolInBackpack(player, itemId)
end)

-- ── UnpinFromHotbar ───────────────────────────────────────────────────────

unpinFromHotbarRemote.OnServerEvent:Connect(function(player, rawSlot)
	local slot = math.floor(tonumber(rawSlot) or 0)
	if slot < 1 or slot > HOTBAR_SIZE then return end
	if tostring(player:GetAttribute(slotAttrName(slot)) or "") == "" then return end
	clearHotbarSlot(player, slot)
end)

-- ── SwapHotbarSlots (reorder within hotbar) ───────────────────────────────

swapHotbarSlotsRemote.OnServerEvent:Connect(function(player, rawSlotA, rawSlotB)
	local slotA = math.floor(tonumber(rawSlotA) or 0)
	local slotB = math.floor(tonumber(rawSlotB) or 0)
	if slotA < 1 or slotA > HOTBAR_SIZE then return end
	if slotB < 1 or slotB > HOTBAR_SIZE then return end
	if slotA == slotB then return end

	local itemA = tostring(player:GetAttribute(slotAttrName(slotA)) or "")
	local itemB = tostring(player:GetAttribute(slotAttrName(slotB)) or "")

	player:SetAttribute(slotAttrName(slotA), itemB ~= "" and itemB or nil)
	player:SetAttribute(slotAttrName(slotB), itemA ~= "" and itemA or nil)

	-- Keep equipped-slot tracking accurate.
	local equipped = math.floor(tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0)
	if equipped == slotA then
		player:SetAttribute("HotbarEquippedSlot", slotB)
	elseif equipped == slotB then
		player:SetAttribute("HotbarEquippedSlot", slotA)
	end
end)

-- ── SplitStack ────────────────────────────────────────────────────────────

splitStackRemote.OnServerEvent:Connect(function(player, rawSlot, rawSplitQty)
	local slot     = math.floor(tonumber(rawSlot) or 0)
	local maxSlots = getMaxSlots(player)
	if slot < 1 or slot > maxSlots then return end

	local itemId = getSlotItemId(player, slot)
	if itemId == "" then return end

	local qty      = getSlotQty(player, slot)
	local splitQty = math.floor(tonumber(rawSplitQty) or 0)
	if splitQty < 1 or splitQty >= qty then return end

	local freeSlot: number? = nil
	for n = 1, maxSlots do
		if n ~= slot and getSlotItemId(player, n) == "" then
			freeSlot = n
			break
		end
	end
	if not freeSlot then return end

	-- Split expiry list: oldest N go to new slot, rest stay
	local expiries = getSlotExpiries(player, slot)
	local splitExpiries = {}
	local remainExpiries = {}
	for i, ts in ipairs(expiries) do
		if i <= splitQty then
			table.insert(splitExpiries, ts)
		else
			table.insert(remainExpiries, ts)
		end
	end

	-- Split durability list: first N go to new slot, rest stay
	local durs = getSlotDurabilities(player, slot)
	local splitDurs = {}
	local remainDurs = {}
	for i, d in ipairs(durs) do
		if i <= splitQty then
			table.insert(splitDurs, d)
		else
			table.insert(remainDurs, d)
		end
	end

	setSlot(player, slot, itemId, qty - splitQty)
	setSlotExpiries(player, slot, remainExpiries)
	setSlotDurabilities(player, slot, remainDurs)
	setSlot(player, freeSlot, itemId, splitQty)
	setSlotExpiries(player, freeSlot, splitExpiries)
	setSlotDurabilities(player, freeSlot, splitDurs)
end)

-- ── SwapSlots (inventory drag-and-drop) ───────────────────────────────────

swapSlotsRemote.OnServerEvent:Connect(function(player, rawSlotA, rawSlotB)
	local maxSlots = getMaxSlots(player)
	local slotA    = math.floor(tonumber(rawSlotA) or 0)
	local slotB    = math.floor(tonumber(rawSlotB) or 0)
	if slotA < 1 or slotA > maxSlots then return end
	if slotB < 1 or slotB > maxSlots then return end
	if slotA == slotB then return end

	local itemIdA = getSlotItemId(player, slotA)
	local qtyA    = getSlotQty(player, slotA)
	local itemIdB = getSlotItemId(player, slotB)
	local qtyB    = getSlotQty(player, slotB)

	-- Same item → merge stacks up to stackMax; overflow stays in source slot.
	if itemIdA ~= "" and itemIdA == itemIdB then
		local def      = ItemRegistry.get(itemIdA)
		local stackMax = def and def.stackMax or 1
		local transfer = math.min(qtyA, stackMax - qtyB)
		if transfer > 0 then
			-- Merge expiry lists: oldest N from A move to B
			local expiresA = getSlotExpiries(player, slotA)
			local expiresB = getSlotExpiries(player, slotB)
			local keptA = {}
			if #expiresA > 0 then
				for i, ts in ipairs(expiresA) do
					if i <= transfer then
						table.insert(expiresB, ts)
					else
						table.insert(keptA, ts)
					end
				end
				table.sort(expiresB)
			end
			-- Merge durability lists: first N from A move to B
			local dursA = getSlotDurabilities(player, slotA)
			local dursB = getSlotDurabilities(player, slotB)
			local keptDursA = {}
			if #dursA > 0 then
				for i, d in ipairs(dursA) do
					if i <= transfer then
						table.insert(dursB, d)
					else
						table.insert(keptDursA, d)
					end
				end
			end
			setSlot(player, slotB, itemIdB, qtyB + transfer)
			setSlotExpiries(player, slotB, expiresB)
			setSlotDurabilities(player, slotB, dursB)
			local newQtyA = qtyA - transfer
			setSlot(player, slotA, itemIdA, newQtyA)
			if newQtyA > 0 then
				setSlotExpiries(player, slotA, keptA)
				setSlotDurabilities(player, slotA, keptDursA)
			end
		end
		return
	end

	-- Different items (or one is empty) → swap expiry and durability data too.
	local expiresA = getSlotExpiries(player, slotA)
	local expiresB = getSlotExpiries(player, slotB)
	local dursA    = getSlotDurabilities(player, slotA)
	local dursB    = getSlotDurabilities(player, slotB)
	setSlot(player, slotA, itemIdB, qtyB)
	setSlotExpiries(player, slotA, expiresB)
	setSlotDurabilities(player, slotA, dursB)
	setSlot(player, slotB, itemIdA, qtyA)
	setSlotExpiries(player, slotB, expiresA)
	setSlotDurabilities(player, slotB, dursA)
end)

-- ── DropItem ──────────────────────────────────────────────────────────────

dropItemRemote.OnServerEvent:Connect(function(player, rawSlot, rawQty)
	local maxSlots = getMaxSlots(player)
	local slot     = math.floor(tonumber(rawSlot) or 0)
	if slot < 1 or slot > maxSlots then return end

	local itemId  = getSlotItemId(player, slot)
	if itemId == "" then return end

	local slotQty = getSlotQty(player, slot)
	local qty     = math.min(math.max(1, math.floor(tonumber(rawQty) or slotQty)), slotQty)

	setSlot(player, slot, itemId, slotQty - qty)
	refreshWeight(player)
	cleanOrphanedHotbarPins(player)
	createLootBag(player, { { itemId = itemId, qty = qty } })
end)

-- ── PlaceItem ─────────────────────────────────────────────────────────────

local PLACE_MAX_RANGE = (GameplayConfig.Campfire and GameplayConfig.Campfire.PlacementMaxRange) or 20
local PLACE_COOLDOWN  = 1.0
local lastPlaceTime: { [Player]: number } = {}

placeItemRemote.OnServerEvent:Connect(function(player, rawItemId, rawCFrame)
	local itemId = sanitizeItemId(rawItemId)
	if itemId == "" then return end
	if typeof(rawCFrame) ~= "CFrame" then return end

	local def = ItemRegistry.get(itemId)
	if not def or def.category ~= "placeable" then return end

	-- Cooldown
	local now = os.clock()
	if lastPlaceTime[player] and now - lastPlaceTime[player] < PLACE_COOLDOWN then return end
	lastPlaceTime[player] = now

	-- Range check
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	if (rawCFrame.Position - rootPart.Position).Magnitude > PLACE_MAX_RANGE then return end

	-- Bedroll: must be placed near a campfire
	if itemId == "bedroll" then
		local reqRadius = (GameplayConfig.Bedroll and GameplayConfig.Bedroll.RequiredCampfireRadius) or 15
		local nearCampfire = false
		for _, obj in ipairs(Workspace:GetChildren()) do
			if obj:IsA("Model") and obj:GetAttribute("_PlacedItem") == "campfire" then
				local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
				if part and (part.Position - rawCFrame.Position).Magnitude <= reqRadius then
					nearCampfire = true
					break
				end
			end
		end
		if not nearCampfire then return end

		-- One bedroll per player: destroy old one
		for _, obj in ipairs(Workspace:GetChildren()) do
			if obj:IsA("Model")
				and obj:GetAttribute("_PlacedItem") == "bedroll"
				and obj:GetAttribute("_PlacedBy") == player.UserId
			then
				obj:Destroy()
			end
		end
	end

	-- Remove from inventory
	if not removeQty(player, itemId, 1) then return end
	cleanOrphanedHotbarPins(player)

	-- Clone from ItemTools
	local itemToolsFolder = ServerStorage:FindFirstChild("ItemTools")
	local template = itemToolsFolder and itemToolsFolder:FindFirstChild(itemId)
	if not template or not template:IsA("Model") then return end

	local placed = template:Clone()
	placed:SetAttribute("_PlacedItem", itemId)
	placed:SetAttribute("_PlacedBy", player.UserId)
	placed:SetAttribute("_lastOccupiedTime", os.clock())

	-- Anchor all parts
	for _, part in ipairs(placed:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	-- Enable fire/sound effects
	for _, desc in ipairs(placed:GetDescendants()) do
		if desc:IsA("Fire") or desc:IsA("Smoke") or desc:IsA("ParticleEmitter") then
			desc.Enabled = true
		elseif desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
			desc.Enabled = true
		elseif desc:IsA("Sound") then
			desc:Play()
		end
	end

	-- Add ProximityPrompt for campfire cooking UI
	if itemId == "campfire" then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Cook"
		prompt.ObjectText = "Campfire"
		prompt.MaxActivationDistance = GameplayConfig.Campfire.InteractRange
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = placed.PrimaryPart or placed:FindFirstChildWhichIsA("BasePart")
	end

	-- Add ProximityPrompt for bedroll lie-down
	if itemId == "bedroll" then
		local bedrollRange = (GameplayConfig.Bedroll and GameplayConfig.Bedroll.InteractRange) or 6
		local bedrollPrompt = Instance.new("ProximityPrompt")
		bedrollPrompt.ActionText = "Lie Down"
		bedrollPrompt.ObjectText = "Bedroll"
		bedrollPrompt.MaxActivationDistance = bedrollRange
		bedrollPrompt.HoldDuration = 0
		bedrollPrompt.RequiresLineOfSight = false
		bedrollPrompt.Parent = placed.PrimaryPart or placed:FindFirstChildWhichIsA("BasePart")

		bedrollPrompt.Triggered:Connect(function(trigPlayer)
			-- One person at a time
			if placed:GetAttribute("_OccupiedBy") then return end
			-- Check player isn't already lying on another bedroll
			if trigPlayer:GetAttribute("LyingOnBedroll") == true then return end

			local character = trigPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not humanoid or not rootPart then return end

			-- Mark bedroll as occupied
			placed:SetAttribute("_OccupiedBy", trigPlayer.UserId)

			-- Set player state
			trigPlayer:SetAttribute("IsResting", true)
			trigPlayer:SetAttribute("LyingOnBedroll", true)

			-- Teleport player onto the bedroll
			local bedrollPart = placed.PrimaryPart or placed:FindFirstChildWhichIsA("BasePart")
			if bedrollPart then
				rootPart.CFrame = bedrollPart.CFrame * CFrame.Angles(0, math.rad(90), 0) + Vector3.new(0, 1, 0)
			end

			-- Disable movement
			humanoid.WalkSpeed = 0
			humanoid.JumpHeight = 0
			humanoid.JumpPower = 0

			-- Hide prompt while occupied
			bedrollPrompt.Enabled = false
		end)

		-- "Pick Up" prompt (owner only, F key to avoid conflict with E "Lie Down")
		local pickupPrompt = Instance.new("ProximityPrompt")
		pickupPrompt.ActionText = "Pick Up"
		pickupPrompt.ObjectText = "Bedroll"
		pickupPrompt.MaxActivationDistance = bedrollRange
		pickupPrompt.HoldDuration = 0.5
		pickupPrompt.RequiresLineOfSight = false
		pickupPrompt.KeyboardKeyCode = Enum.KeyCode.F
		pickupPrompt.Parent = placed.PrimaryPart or placed:FindFirstChildWhichIsA("BasePart")

		pickupPrompt.Triggered:Connect(function(trigPlayer)
			-- Owner only
			if trigPlayer.UserId ~= placed:GetAttribute("_PlacedBy") then return end

			-- Kick occupant off if someone is lying on it
			local occupantId = placed:GetAttribute("_OccupiedBy")
			if occupantId then
				for _, p in Players:GetPlayers() do
					if p.UserId == occupantId then
						p:SetAttribute("IsResting", false)
						p:SetAttribute("LyingOnBedroll", false)
						local oChar = p.Character
						local oHum = oChar and oChar:FindFirstChildOfClass("Humanoid")
						if oHum then
							oHum.WalkSpeed = GameplayConfig.Movement.WalkSpeed
							oHum.JumpPower = GameplayConfig.Movement.JumpPower
						end
						break
					end
				end
				placed:SetAttribute("_OccupiedBy", nil)
			end

			-- Return to inventory (fails if full — bedroll stays in world)
			if addQty(trigPlayer, "bedroll", 1) then
				placed:Destroy()
			end
		end)
	end

	placed:PivotTo(rawCFrame)
	placed.Parent = Workspace
end)

-- ── Spoilage loop ────────────────────────────────────────────────────────
-- Every 10 seconds, scan all players' inventory for expired per-item timestamps.
-- Expired items are removed and replaced with spoiled_food.

local SPOILAGE_TICK = 10
local spoilageTimer = 0

RunService.Heartbeat:Connect(function(dt)
	spoilageTimer += dt
	if spoilageTimer < SPOILAGE_TICK then return end
	spoilageTimer = 0

	local now = os.time()
	for _, player in ipairs(Players:GetPlayers()) do
		local maxSlots = getMaxSlots(player)
		local totalSpoiled = 0

		for n = 1, maxSlots do
			local itemId = getSlotItemId(player, n)
			if itemId == "" then continue end
			local expiries = getSlotExpiries(player, n)
			if #expiries == 0 then continue end

			-- Count expired timestamps (sorted ascending, so break on first valid)
			local expiredCount = 0
			for _, ts in ipairs(expiries) do
				if ts <= now then
					expiredCount += 1
				else
					break
				end
			end

			if expiredCount > 0 then
				local qty = getSlotQty(player, n)
				expiredCount = math.min(expiredCount, qty)  -- safety clamp
				local remaining = qty - expiredCount
				totalSpoiled += expiredCount

				if remaining > 0 then
					local newExpiries = {}
					for i = expiredCount + 1, #expiries do
						table.insert(newExpiries, expiries[i])
					end
					setSlotExpiries(player, n, newExpiries)
					-- Trim durabilities in case item has both perish + durability
					local durs = getSlotDurabilities(player, n)
					if #durs > 0 then
						local newDurs = {}
						for i = expiredCount + 1, #durs do
							table.insert(newDurs, durs[i])
						end
						setSlotDurabilities(player, n, newDurs)
					end
					setSlot(player, n, itemId, remaining)
				else
					setSlot(player, n, itemId, 0)  -- clears slot + expiries + durability
				end
			end
		end

		if totalSpoiled > 0 then
			addQty(player, "spoiled_food", totalSpoiled)
			refreshWeight(player)
			cleanOrphanedHotbarPins(player)
		end
	end
end)

-- ── Player lifecycle ──────────────────────────────────────────────────────

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(function(player)
	lastEatTime[player] = nil
	lastPlaceTime[player] = nil
	-- Clean up loot bag viewer lists
	for _, viewers in pairs(lootBagViewers) do
		for i = #viewers, 1, -1 do
			if viewers[i] == player then
				table.remove(viewers, i)
			end
		end
	end
end)
for _, player in ipairs(Players:GetPlayers()) do
	initPlayer(player)
end

-- ── Loot bag remotes ────────────────────────────────────────────────────

openLootBagRemote.OnServerEvent:Connect(function(player, bag)
	if not bag or not (typeof(bag) == "Instance" and bag:IsA("Model")) then return end
	if not bag:GetAttribute("_isLootBag") then return end
	if not bag.Parent then return end
	if not isBagInRange(player, bag) then return end
	addBagViewer(bag, player)
	lootBagStateRemote:FireClient(player, bag, serializeBagContents(bag))
end)

takeLootBagItemRemote.OnServerEvent:Connect(function(player, bag, rawItemId, rawQty)
	if not bag or not (typeof(bag) == "Instance" and bag:IsA("Model")) then return end
	if not bag:GetAttribute("_isLootBag") then return end
	if not bag.Parent then return end
	local itemId = sanitizeItemId(rawItemId)
	if itemId == "" then return end
	local qty = math.floor(tonumber(rawQty) or 0)
	if qty < 1 then return end
	if not isBagInRange(player, bag) then return end

	local child = bag:FindFirstChild(itemId)
	if not child or not child:IsA("IntValue") then return end

	local available = child.Value
	local take = math.min(qty, available)
	if take < 1 then return end

	if not addQty(player, itemId, take) then return end

	local remaining = available - take
	if remaining <= 0 then
		child:Destroy()
	else
		child.Value = remaining
	end

	-- Check if bag is empty
	local hasItems = false
	for _, c in ipairs(bag:GetChildren()) do
		if c:IsA("IntValue") then hasItems = true; break end
	end

	if not hasItems then
		notifyBagDestroyed(bag)
		bag:Destroy()
	else
		broadcastBagState(bag)
	end
end)
