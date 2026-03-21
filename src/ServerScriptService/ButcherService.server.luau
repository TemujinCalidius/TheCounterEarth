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
			{ itemId = "crude_hide", qty = 1, chance = 1.0 },
		},
		butcher = {
			{ itemId = "raw_venison", qtyMin = 2, qtyMax = 3, chance = 1.0 },
			{ itemId = "bone",        qtyMin = 1, qtyMax = 2, chance = 1.0 },
			{ itemId = "sinew",       qtyMin = 1, qtyMax = 1, chance = 0.3 },
		},
	},
}

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

	-- Create the ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Skin"
	prompt.ObjectText = "Deer Carcass"
	prompt.MaxActivationDistance = INTERACT_RANGE
	prompt.HoldDuration = SKIN_CHANNEL
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	prompt.Triggered:Connect(function(triggerPlayer: Player)
		if activeChannels[triggerPlayer] then return end

		-- Check knife equipped
		local knifeId = getEquippedKnifeId(triggerPlayer)
		if not knifeId then
			butcherNotifyRemote:FireClient(triggerPlayer, "You need a knife equipped to do this")
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

			-- Give skin yields (quality based on knife tier)
			local given = giveYields(triggerPlayer, yields.skin)
			carcass:SetAttribute("_Skinned", true)

			-- Update prompt for butcher step
			prompt.ActionText = "Butcher"
			prompt.HoldDuration = BUTCHER_CHANNEL

			-- Notify player
			local msg = "Skinned: " .. table.concat(given, ", ")
			butcherNotifyRemote:FireClient(triggerPlayer, msg)

			EventBridge.fire("animal_skinned", triggerPlayer, {
				animalType = animalType,
				knifeItemId = knifeId,
				knifeTier = getKnifeTier(triggerPlayer),
			})

			activeChannels[triggerPlayer] = nil

		elseif not butchered then
			-- BUTCHER step
			activeChannels[triggerPlayer] = true

			-- Re-check knife (might have broken during skinning)
			knifeId = getEquippedKnifeId(triggerPlayer)
			if not knifeId then
				butcherNotifyRemote:FireClient(triggerPlayer, "You need a knife equipped to do this")
				activeChannels[triggerPlayer] = nil
				return
			end

			-- Deduct knife durability
			durabilityDeduct:Invoke(triggerPlayer, knifeId, BUTCHER_DUR_COST)

			-- Give butcher yields
			local given = giveYields(triggerPlayer, yields.butcher)
			carcass:SetAttribute("_Butchered", true)

			-- Remove prompt and update billboard
			prompt:Destroy()

			local billboard = body:FindFirstChildOfClass("BillboardGui")
			if billboard then
				local label = billboard:FindFirstChildOfClass("TextLabel")
				if label then
					label.Text = "Remains"
					label.TextColor3 = Color3.fromRGB(120, 100, 80)
				end
			end

			-- Notify player
			local msg = "Butchered: " .. table.concat(given, ", ")
			butcherNotifyRemote:FireClient(triggerPlayer, msg)

			EventBridge.fire("butcher_complete", triggerPlayer, {
				animalType = animalType,
				knifeItemId = knifeId,
			})

			activeChannels[triggerPlayer] = nil

			-- Destroy carcass after a few seconds
			task.delay(5, function()
				if carcass.Parent then carcass:Destroy() end
			end)
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
