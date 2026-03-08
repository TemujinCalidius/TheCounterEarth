local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config       = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local ItemRegistry = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))

local HOTBAR_SIZE = math.clamp(math.floor(tonumber(Config.Hotbar and Config.Hotbar.Slots) or 9), 1, 9)
local TEMPLATE_FOLDER_NAME = "ItemTools"
local PICKUP_PROMPT_NAME = "InteractPrompt"
local PICKUP_ACTION_TEXT = "Pick Up"

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local hotbarEquipRemote = remotesFolder:WaitForChild("HotbarEquipRequest")

local templateFolder = ServerStorage:FindFirstChild(TEMPLATE_FOLDER_NAME)
if templateFolder and not templateFolder:IsA("Folder") then
	templateFolder:Destroy()
	templateFolder = nil
end

if not templateFolder then
	templateFolder = Instance.new("Folder")
	templateFolder.Name = TEMPLATE_FOLDER_NAME
	templateFolder.Parent = ServerStorage
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

-- Adds `qty` of `itemId` to a player's InvSlot_N/InvQty_N attributes.
-- Returns true if all items were placed (false = no space).
local function addToInventorySlots(player: Player, itemId: string, qty: number): boolean
	local def      = ItemRegistry.get(itemId)
	local stackMax = (def and def.stackMax) or 1
	local maxSlots = math.max(1, math.floor(tonumber(player:GetAttribute("MaxInvSlots")) or 5))
	local remaining = qty

	-- Pass 1: fill partial stacks.
	for n = 1, maxSlots do
		if remaining <= 0 then break end
		if tostring(player:GetAttribute("InvSlot_" .. n) or "") == itemId then
			local current = math.max(0, math.floor(tonumber(player:GetAttribute("InvQty_" .. n)) or 0))
			local canAdd  = math.min(remaining, stackMax - current)
			if canAdd > 0 then
				player:SetAttribute("InvQty_" .. n, current + canAdd)
				remaining -= canAdd
			end
		end
	end

	-- Pass 2: use empty slots.
	for n = 1, maxSlots do
		if remaining <= 0 then break end
		if tostring(player:GetAttribute("InvSlot_" .. n) or "") == "" then
			local take = math.min(remaining, stackMax)
			player:SetAttribute("InvSlot_" .. n, itemId)
			player:SetAttribute("InvQty_" .. n, take)
			remaining -= take
		end
	end

	return remaining == 0
end

local function hasTool(player: Player, toolName: string): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack and backpack:FindFirstChild(toolName) then
		return true
	end

	local character = player.Character
	if character and character:FindFirstChild(toolName) then
		return true
	end

	return false
end

local function findToolInstance(player: Player, toolName: string): Tool?
	local character = player.Character
	if character then
		local tool = character:FindFirstChild(toolName)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		local tool = backpack:FindFirstChild(toolName)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end

	return nil
end

local function ensureToolTemplate(tool: Tool): Tool?
	local itemId = sanitizeItemId(tool.Name)
	if itemId == "" then
		return nil
	end

	local existing = templateFolder:FindFirstChild(itemId)
	if existing and existing:IsA("Tool") then
		return existing
	end

	local template = tool:Clone()
	template.Name = itemId
	template.Parent = templateFolder
	return template
end

local function isUnderPlayerCharacter(tool: Tool): boolean
	local character = tool:FindFirstAncestorOfClass("Model")
	return character ~= nil and Players:GetPlayerFromCharacter(character) ~= nil
end

local function firstAvailableHotbarSlot(player: Player, itemId: string): number?
	for slot = 1, HOTBAR_SIZE do
		if player:GetAttribute(slotAttributeName(slot)) == itemId then
			return slot
		end
	end

	for slot = 1, HOTBAR_SIZE do
		local current = sanitizeItemId(player:GetAttribute(slotAttributeName(slot)))
		if current == "" then
			return slot
		end
	end

	return nil
end

local function setEquippedSlot(player: Player, slot: number)
	player:SetAttribute("HotbarEquippedSlot", slot)
end

local function assignItemToHotbar(player: Player, itemId: string): number?
	local slot = firstAvailableHotbarSlot(player, itemId)
	if not slot then
		return nil
	end

	if player:GetAttribute(slotAttributeName(slot)) ~= itemId then
		player:SetAttribute(slotAttributeName(slot), itemId)
	end

	local equippedSlot = math.floor(tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0)
	if equippedSlot < 1 or equippedSlot > HOTBAR_SIZE then
		setEquippedSlot(player, slot)
	end

	return slot
end

local function findTemplate(itemId: string): Tool?
	local template = templateFolder:FindFirstChild(itemId)
	if template and template:IsA("Tool") then
		return template
	end
	return nil
end

local function grantItemFromTemplate(player: Player, itemId: string): Tool?
	local template = findTemplate(itemId)
	if not template then
		return nil
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end

	local clone = template:Clone()
	clone.Name = itemId
	clone.Parent = backpack
	return clone
end

local function syncEquippedSlotFromCharacter(player: Player)
	local character = player.Character
	if not character then
		setEquippedSlot(player, 0)
		return
	end

	local equippedTool = character:FindFirstChildOfClass("Tool")
	if not equippedTool then
		-- Keep the slot selected if it's a placeable (no physical tool)
		local currentSlot = math.floor(tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0)
		if currentSlot >= 1 and currentSlot <= HOTBAR_SIZE then
			local slotItem = sanitizeItemId(player:GetAttribute(slotAttributeName(currentSlot)))
			if slotItem ~= "" then
				local def = ItemRegistry.get(slotItem)
				if def and def.category == "placeable" then
					return -- keep placeable slot selected
				end
			end
		end
		setEquippedSlot(player, 0)
		return
	end

	local equippedItem = sanitizeItemId(equippedTool.Name)
	if equippedItem == "" then
		setEquippedSlot(player, 0)
		return
	end

	for slot = 1, HOTBAR_SIZE do
		if sanitizeItemId(player:GetAttribute(slotAttributeName(slot))) == equippedItem then
			setEquippedSlot(player, slot)
			return
		end
	end

	setEquippedSlot(player, 0)
end

local function pickupToolForPlayer(player: Player, tool: Tool)
	local itemId = sanitizeItemId(tool.Name)
	if itemId == "" then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	if hasTool(player, itemId) then
		-- Player already holds this tool — route the extra copy into inventory slots.
		if addToInventorySlots(player, itemId, 1) then
			tool:Destroy()
		end
		-- If no inventory slot available the tool stays in the world.
		return
	end

	-- First pickup: add to inventory slots AND auto-pin to hotbar.
	local invAdded = addToInventorySlots(player, itemId, 1)

	local hotbarSlot = assignItemToHotbar(player, itemId)
	if not hotbarSlot then
		-- Hotbar full; item is still in inventory if invAdded.
		if invAdded then tool:Destroy() end
		return
	end

	local template = ensureToolTemplate(tool)
	if not template then
		return
	end

	local granted = template:Clone()
	granted.Name = itemId
	granted.Parent = backpack

	tool:Destroy()
end

local function setupWorldTool(tool: Tool)
	if tool:GetAttribute("_ManagedPickup") then
		return
	end
	if tool.Parent == nil then
		return
	end
	if not tool:IsDescendantOf(Workspace) then
		return
	end
	if isUnderPlayerCharacter(tool) then
		return
	end

	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end

	local itemId = sanitizeItemId(tool.Name)
	if itemId == "" then
		return
	end

	ensureToolTemplate(tool)

	tool:SetAttribute("_ManagedPickup", true)
	handle.CanTouch = false

	local prompt = handle:FindFirstChild(PICKUP_PROMPT_NAME)
	if prompt and not prompt:IsA("ProximityPrompt") then
		prompt:Destroy()
		prompt = nil
	end

	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = PICKUP_PROMPT_NAME
		prompt.Parent = handle
	end

	prompt.ActionText = PICKUP_ACTION_TEXT
	prompt.ObjectText = itemId
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false

	prompt.Triggered:Connect(function(player)
		if not tool.Parent or not tool:IsDescendantOf(Workspace) then
			return
		end
		pickupToolForPlayer(player, tool)
	end)
end

local function ensurePersistedTools(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	for slot = 1, HOTBAR_SIZE do
		local itemId = sanitizeItemId(player:GetAttribute(slotAttributeName(slot)))
		if itemId ~= "" and not hasTool(player, itemId) then
			grantItemFromTemplate(player, itemId)
		end
	end
end

local function setupCharacterObservers(player: Player, character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			task.defer(function()
				syncEquippedSlotFromCharacter(player)
			end)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			task.defer(function()
				syncEquippedSlotFromCharacter(player)
			end)
		end
	end)
end

hotbarEquipRemote.OnServerEvent:Connect(function(player, slot)
	if type(slot) ~= "number" then
		return
	end

	slot = math.floor(slot)
	if slot < 1 or slot > HOTBAR_SIZE then
		return
	end

	local itemId = sanitizeItemId(player:GetAttribute(slotAttributeName(slot)))
	if itemId == "" then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local equippedSlot = math.floor(tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0)
	if equippedSlot == slot then
		humanoid:UnequipTools()
		setEquippedSlot(player, 0)
		return
	end

	-- Placeables: just select the slot, don't equip a physical tool
	local def = ItemRegistry.get(itemId)
	if def and def.category == "placeable" then
		humanoid:UnequipTools()
		setEquippedSlot(player, slot)
		return
	end

	local tool = findToolInstance(player, itemId)
	if not tool then
		tool = grantItemFromTemplate(player, itemId)
	end
	if not tool then
		return
	end

	humanoid:EquipTool(tool)
	setEquippedSlot(player, slot)
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		setupCharacterObservers(player, character)
		task.defer(function()
			ensurePersistedTools(player)
			syncEquippedSlotFromCharacter(player)
		end)
	end)

	task.defer(function()
		ensurePersistedTools(player)
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		setupCharacterObservers(player, player.Character)
	end
	task.defer(function()
		ensurePersistedTools(player)
		syncEquippedSlotFromCharacter(player)
	end)
end

for _, descendant in ipairs(Workspace:GetDescendants()) do
	if descendant:IsA("Tool") then
		setupWorldTool(descendant)
	end
end

Workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Tool") then
		setupWorldTool(instance)
	end
end)
