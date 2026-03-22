-- ButcherService.server.luau
-- Handles carcass interaction: skinning and butchering.
-- Two-step ProximityPrompt flow: Skin → Butcher.
-- Requires stone_knife equipped. Quality depends on knife tier.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local Workspace          = game:GetService("Workspace")

local ItemRegistry   = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))
local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local EventBridge    = require(script.Parent:WaitForChild("EventBridge"))

local butcherCfg = GameplayConfig.Butcher or {}
local SKIN_CHANNEL    = butcherCfg.SkinChannelSeconds or 3
local BUTCHER_CHANNEL = butcherCfg.ButcherChannelSeconds or 4
local SKIN_DUR_COST   = butcherCfg.SkinDurabilityCost or 2
local BUTCHER_DUR_COST = butcherCfg.ButcherDurabilityCost or 2
local INTERACT_RANGE  = butcherCfg.InteractRange or 6

-- ── Bindables ───────────────────────────────────────────────────────────
local bindables = ServerStorage:WaitForChild("ServerBindables")
local invAdd: BindableFunction = bindables:WaitForChild("InventoryAdd") :: BindableFunction
local durabilityDeduct: BindableFunction = bindables:WaitForChild("DurabilityDeduct") :: BindableFunction

-- ── Remotes ─────────────────────────────────────────────────────────────
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local butcherProgressRemote = Instance.new("RemoteEvent")
butcherProgressRemote.Name = "ButcherProgress"
butcherProgressRemote.Parent = remotesFolder

local butcherNotifyRemote = Instance.new("RemoteEvent")
butcherNotifyRemote.Name = "ButcherNotify"
butcherNotifyRemote.Parent = remotesFolder

-- ── Yield tables per animal type ────────────────────────────────────────
local YIELDS = {
	deer = {
		skin = {
			{ itemId = "raw_crude_hide", qty = 1, chance = 1.0 },
		},
		butcher = {
			{ itemId = "raw_venison", qtyMin = 2, qtyMax = 3, chance = 1.0 },
			{ itemId = "bone",        qtyMin = 1, qtyMax = 2, chance = 1.0 },
			{ itemId = "sinew",       qtyMin = 1, qtyMax = 1, chance = 0.3 },
		},
	},
}

-- ── Model swap templates (lazy-loaded from ServerStorage/ScatterModels) ──
local function getSwapTemplate(name: string): Model?
	local folder = ServerStorage:WaitForChild("ScatterModels", 10)
	if not folder then return nil end
	local tmpl = folder:FindFirstChild(name)
	return tmpl and tmpl:IsA("Model") and tmpl or nil
end

-- Replace a carcass model with a new template clone at the same position.
-- Copies all attributes and re-creates the ProximityPrompt and billboard on the new model.
-- Returns the new model (caller must update any local references).
local function replaceCarcassModel(carcass: Model, template: Model): Model
	local pos = carcass:GetPivot().Position

	-- Copy attributes
	local attrs = carcass:GetAttributes()

	-- Destroy old carcass
	carcass:Destroy()

	-- Clone new model
	local newModel = template:Clone()
	newModel.Name = "DeerCarcass"

	-- Anchor all parts
	for _, part in newModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	-- Restore attributes
	for k, v in attrs do
		newModel:SetAttribute(k, v)
	end

	-- Position at ground level with sink
	newModel:PivotTo(CFrame.new(pos))
	newModel.Parent = Workspace

	return newModel
end

-- ── Active channels (prevent double-interaction) ────────────────────────
local activeChannels: { [Player]: boolean } = {}

-- ── Helpers ─────────────────────────────────────────────────────────────

local function getEquippedKnifeId(player: Player): string?
	local eqSlot = tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0
	if eqSlot < 1 or eqSlot > 9 then return nil end
	local itemId = player:GetAttribute("HotbarSlot" .. eqSlot)
	if type(itemId) ~= "string" or itemId == "" then return nil end
	local def = ItemRegistry.get(itemId)
	if not def or not def.tool or def.tool.kind ~= "knife" then return nil end
	return itemId
end

local function getKnifeTier(player: Player): number
	local itemId = getEquippedKnifeId(player)
	if not itemId then return -1 end
	local def = ItemRegistry.get(itemId)
	return def and def.tool and def.tool.tier or 0
end

local function isInRange(player: Player, carcass: Model): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local part = carcass.PrimaryPart or carcass:FindFirstChildWhichIsA("BasePart")
	if not part then return false end
	return (root.Position - part.Position).Magnitude <= INTERACT_RANGE
end

local function giveYields(player: Player, yieldTable: { any })
	local given: { string } = {}
	for _, entry in ipairs(yieldTable) do
		if math.random() > (entry.chance or 1.0) then continue end
		local qty = entry.qty or math.random(entry.qtyMin or 1, entry.qtyMax or 1)
		invAdd:Invoke(player, entry.itemId, qty)
		local def = ItemRegistry.get(entry.itemId)
		local name = def and def.displayName or entry.itemId
		table.insert(given, qty .. "x " .. name)
	end
	return given
end

-- ── Set up ProximityPrompts on carcasses ─────────────────────────────────

local function setupCarcassPrompts(carcass: Model)
	local body = carcass.PrimaryPart or carcass:FindFirstChildWhichIsA("BasePart")
	if not body then return end

	local animalType = carcass:GetAttribute("_AnimalType") or "deer"
	local yields = YIELDS[animalType]
	if not yields then return end

	-- Already fully butchered — no prompt needed
	if carcass:GetAttribute("_Butchered") then return end

	-- Create the ProximityPrompt (start at correct step based on _Skinned)
	local alreadySkinned = carcass:GetAttribute("_Skinned") == true
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = alreadySkinned and "Butcher" or "Skin"
	prompt.ObjectText = "Deer Carcass"
	prompt.MaxActivationDistance = INTERACT_RANGE
	prompt.HoldDuration = alreadySkinned and BUTCHER_CHANNEL or SKIN_CHANNEL
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	prompt.Triggered:Connect(function(triggerPlayer: Player)
		if activeChannels[triggerPlayer] then return end

		-- Check knife equipped
		local knifeId = getEquippedKnifeId(triggerPlayer)
		if not knifeId then
			butcherNotifyRemote:FireClient(triggerPlayer, "error", carcass, "Equip a knife first")
			return
		end

		-- Check range
		if not isInRange(triggerPlayer, carcass) then return end

		local skinned = carcass:GetAttribute("_Skinned")
		local butchered = carcass:GetAttribute("_Butchered")

		if not skinned then
			-- SKIN step
			activeChannels[triggerPlayer] = true

			-- Deduct knife durability
			durabilityDeduct:Invoke(triggerPlayer, knifeId, SKIN_DUR_COST)

			-- Give skin yields
			local given = giveYields(triggerPlayer, yields.skin)
			carcass:SetAttribute("_Skinned", true)
			carcass:SetAttribute("_SpawnTime", os.time())

			-- Notify player with structured yield data
			butcherNotifyRemote:FireClient(triggerPlayer, "yield", carcass, given)

			EventBridge.fire("animal_skinned", triggerPlayer, {
				animalType = animalType,
				knifeItemId = knifeId,
				knifeTier = getKnifeTier(triggerPlayer),
			})

			activeChannels[triggerPlayer] = nil

			-- Replace with skinned model (ChildAdded watcher sets up new prompt)
			local skinTmpl = getSwapTemplate("deer_skinned")
			if skinTmpl then
				replaceCarcassModel(carcass, skinTmpl)
			else
				-- No template — just update prompt in place
				prompt.ActionText = "Butcher"
				prompt.HoldDuration = BUTCHER_CHANNEL
			end

		elseif not butchered then
			-- BUTCHER step
			activeChannels[triggerPlayer] = true

			-- Re-check knife (might have broken during skinning)
			knifeId = getEquippedKnifeId(triggerPlayer)
			if not knifeId then
				butcherNotifyRemote:FireClient(triggerPlayer, "error", carcass, "Equip a knife first")
				activeChannels[triggerPlayer] = nil
				return
			end

			-- Deduct knife durability
			durabilityDeduct:Invoke(triggerPlayer, knifeId, BUTCHER_DUR_COST)

			-- Give butcher yields
			local given = giveYields(triggerPlayer, yields.butcher)
			carcass:SetAttribute("_Butchered", true)
			carcass:SetAttribute("_SpawnTime", os.time())

			-- Remove prompt
			prompt:Destroy()

			-- Notify player
			butcherNotifyRemote:FireClient(triggerPlayer, "yield", carcass, given)

			EventBridge.fire("butcher_complete", triggerPlayer, {
				animalType = animalType,
				knifeItemId = knifeId,
			})

			activeChannels[triggerPlayer] = nil

			-- Replace with remains model (no prompt needed)
			local remainsTmpl = getSwapTemplate("deer_remains")
			if remainsTmpl then
				replaceCarcassModel(carcass, remainsTmpl)
			end
		end
	end)
end

-- ── Watch for new carcasses in Workspace ────────────────────────────────
Workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and child:GetAttribute("_IsCarcass") then
		setupCarcassPrompts(child)
	end
end)

-- Set up any carcasses that already exist (unlikely at startup, but safe)
for _, child in Workspace:GetChildren() do
	if child:IsA("Model") and child:GetAttribute("_IsCarcass") then
		setupCarcassPrompts(child)
	end
end

-- ── Cleanup ─────────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
	activeChannels[player] = nil
end)
