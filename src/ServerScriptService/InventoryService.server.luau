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
	else
		player:SetAttribute("InvSlot_" .. n, itemId)
		player:SetAttribute("InvQty_" .. n, math.floor(qty + 0.5))
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

	for n = 1, maxSlots do
		if remaining <= 0 then break end
		if getSlotItemId(player, n) == itemId then
			local qty    = getSlotQty(player, n)
			local canAdd = math.min(remaining, def.stackMax - qty)
			if canAdd > 0 then
				setSlot(player, n, itemId, qty + canAdd)
				remaining -= canAdd
			end
		end
	end

	for n = 1, maxSlots do
		if remaining <= 0 then break end
		if getSlotItemId(player, n) == "" then
			local take = math.min(remaining, def.stackMax)
			setSlot(player, n, itemId, take)
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
			setSlot(player, n, itemId, qty - take)
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

local function spawnToolInBackpack(player: Player, itemId: string)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end
	if backpack:FindFirstChild(itemId) or
		(player.Character and player.Character:FindFirstChild(itemId)) then return end

	local toolsFolder = ServerStorage:FindFirstChild(ITEM_TOOLS_FOLDER)
	local template    = toolsFolder and toolsFolder:FindFirstChild(itemId)
	if template and template:IsA("Tool") then
		local clone = template:Clone()
		clone.Name  = itemId
		clone:SetAttribute("_fromInv", true)
		clone.Parent = backpack
		return
	end

	local def  = ItemRegistry.get(itemId)
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

local function createLootBag(player: Player, items: { { itemId: string, qty: number } })
	local character = player.Character
	local rootPart  = character and character:FindFirstChild("HumanoidRootPart")
	local origin    = rootPart and rootPart.CFrame or CFrame.new(0, 5, 0)
	local dropCFrame = origin * CFrame.new(0, -2.5, -3.5)

	local bag = Instance.new("Model")
	bag.Name = "LootBag"
	bag:SetAttribute("_isLootBag", true)

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
		local allAdded = true
		for _, child in ipairs(bag:GetChildren()) do
			if child:IsA("IntValue") then
				local id = sanitizeItemId(child.Name)
				if id ~= "" and not addQty(lootingPlayer, id, child.Value) then
					allAdded = false
				end
			end
		end
		if allAdded then bag:Destroy() end
	end)

	local lifetime = (GameplayConfig.Inventory and GameplayConfig.Inventory.DeathBagLifetimeSeconds) or 300
	task.delay(lifetime, function()
		if bag and bag.Parent then bag:Destroy() end
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

local function setupScatterItem(model: Model)
	if model:GetAttribute(SCATTER_MANAGED) then return end
	local itemId = sanitizeItemId(model:GetAttribute(SCATTER_ATTR) or "")
	if itemId == "" then return end
	local def = ItemRegistry.get(itemId)
	if not def then return end
	local rootPart = model.PrimaryPart or model:FindFirstChildOfClass("BasePart")
	if not rootPart then return end

	model:SetAttribute(SCATTER_MANAGED, true)

	local prompt = rootPart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = rootPart
	end
	prompt.ActionText            = "Pick Up"
	prompt.ObjectText            = def.displayName
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.HoldDuration          = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight   = false

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

-- ── UseItem ───────────────────────────────────────────────────────────────

useItemRemote.OnServerEvent:Connect(function(player, rawItemId)
	local itemId = sanitizeItemId(rawItemId)
	if itemId == "" then return end
	local def = ItemRegistry.get(itemId)
	if not def or not def.onConsume then return end
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
	if def.category ~= "tool" and def.category ~= "weapon" and not def.onConsume then return end
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

	setSlot(player, slot, itemId, qty - splitQty)
	setSlot(player, freeSlot, itemId, splitQty)
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
			setSlot(player, slotB, itemIdB, qtyB + transfer)
			setSlot(player, slotA, itemIdA, qtyA - transfer)  -- clears slot if 0
		end
		return
	end

	-- Different items (or one is empty) → swap.
	setSlot(player, slotA, itemIdB, qtyB)
	setSlot(player, slotB, itemIdA, qtyA)
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

-- ── Player lifecycle ──────────────────────────────────────────────────────

Players.PlayerAdded:Connect(initPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	initPlayer(player)
end
