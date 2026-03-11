-- GatherController.client.luau
-- Hit-to-harvest feedback: model shake, floating yield text, harvest animation.
-- Listens for HarvestResult / HarvestNotify remotes from InventoryService.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local AssetIds     = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AssetIds"))
local ItemRegistry = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))

-- Tool break sound
local toolBreakSound = Instance.new("Sound")
toolBreakSound.SoundId = AssetIds.Sounds.ToolBreak or ""
toolBreakSound.Volume  = 0.7
toolBreakSound.Parent  = SoundService

local remotesFolder   = ReplicatedStorage:WaitForChild("Remotes")
local harvestResult   = remotesFolder:WaitForChild("HarvestResult")
local harvestNotify   = remotesFolder:WaitForChild("HarvestNotify")

local player = Players.LocalPlayer

-- ── Notify (floating text near player head) ───────────────────────────

local function showNotify(message: string)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then return end

	local bb = Instance.new("BillboardGui")
	bb.Name              = "GatherNotify"
	bb.Adornee           = head
	bb.Size              = UDim2.new(0, 200, 0, 30)
	bb.StudsOffset       = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop       = true
	bb.Parent            = player.PlayerGui

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text                  = message
	label.TextColor3            = Color3.fromRGB(255, 200, 80)
	label.Font                  = Enum.Font.GothamBold
	label.TextSize              = 14
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3      = Color3.fromRGB(0, 0, 0)
	label.Parent                = bb

	task.delay(2, function()
		if bb.Parent then bb:Destroy() end
	end)
end

-- ── Model shake effect ────────────────────────────────────────────────

local function shakeModel(model: Model)
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root or not model.Parent then return end

	local originalCFrame = root.CFrame
	task.spawn(function()
		for i = 1, 6 do
			if not model.Parent then return end
			-- Shake intensity decreases over time (strong hit → settle)
			local intensity = 1 - (i - 1) / 6
			local offset = Vector3.new(
				(math.random() - 0.5) * 0.4 * intensity,
				(math.random() - 0.5) * 0.15 * intensity,
				(math.random() - 0.5) * 0.4 * intensity
			)
			model:PivotTo(originalCFrame + offset)
			task.wait(0.04)
		end
		if model.Parent then
			model:PivotTo(originalCFrame)
		end
	end)
end

-- ── Floating yield text on the node ──────────────────────────────────

local function showYieldText(model: Model, qty: number, displayName: string)
	local adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not adornee then return end

	local bb = Instance.new("BillboardGui")
	bb.Name              = "YieldText"
	bb.Adornee           = adornee
	bb.Size              = UDim2.new(0, 160, 0, 30)
	bb.StudsOffset       = Vector3.new(0, 3.5, 0)
	bb.AlwaysOnTop       = true
	bb.Parent            = player.PlayerGui

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text                  = "+" .. tostring(qty) .. " " .. displayName
	label.TextColor3            = Color3.fromRGB(120, 255, 120)
	label.Font                  = Enum.Font.GothamBold
	label.TextSize              = 16
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3      = Color3.fromRGB(0, 0, 0)
	label.Parent                = bb

	-- Float upward and fade out
	task.spawn(function()
		local startOffset = bb.StudsOffset
		local steps = 20
		for i = 1, steps do
			if not bb.Parent then return end
			local t = i / steps
			bb.StudsOffset = startOffset + Vector3.new(0, t * 1.5, 0)
			label.TextTransparency = t
			label.TextStrokeTransparency = 0.3 + t * 0.7
			task.wait(0.03)
		end
		if bb.Parent then bb:Destroy() end
	end)
end

-- ── Harvest sound effects ────────────────────────────────────────────
-- Maps scatter item IDs to their harvest sound asset key in AssetIds.Sounds.

local ITEM_HARVEST_SOUND: { [string]: string } = {
	reed = "HarvestReed",
}

local function playHarvestSound(model: Model)
	local itemId = model and model:GetAttribute("_ScatterItem")
	if not itemId then return end
	local soundKey = ITEM_HARVEST_SOUND[itemId]
	if not soundKey then return end
	local soundId = AssetIds.Sounds[soundKey]
	if not soundId or soundId == "" then return end

	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not part then return end

	-- Play sound at the node's position
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.8
	sound.RollOffMaxDistance = 30
	sound.Parent = part
	sound:Play()
	-- Auto-cleanup after playback
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

-- ── Play single harvest animation ────────────────────────────────────
-- Picks the animation based on equipped tool kind (knife, pickaxe, axe).

local TOOL_KIND_TO_ANIM: { [string]: string } = {
	knife   = "HarvestKnife",
	pickaxe = "HarvestPickaxe",
	axe     = "HarvestAxe",
}

local function playHarvestAnim()
	-- Figure out which animation to play from equipped tool kind
	local eqSlot = math.floor(tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0)
	local animKey = "HarvestKnife" -- fallback
	if eqSlot >= 1 then
		local slotAttr = "HotbarSlot" .. tostring(eqSlot)
		local itemId = tostring(player:GetAttribute(slotAttr) or "")
		if itemId ~= "" then
			local def = ItemRegistry.get(itemId)
			if def and def.tool and def.tool.kind then
				animKey = TOOL_KIND_TO_ANIM[def.tool.kind] or "HarvestKnife"
			end
		end
	end

	local animId = AssetIds.Animations[animKey] or ""
	if animId == "" then return end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		track:Play()
	end
end

-- ── HarvestResult handler ────────────────────────────────────────────

harvestResult.OnClientEvent:Connect(function(targetModel: Model, qty: number, displayName: string, _nodeDestroyed: boolean)
	local isObserver = qty <= 0

	-- Shake and sound are visible/audible to everyone nearby
	if targetModel and targetModel.Parent then
		shakeModel(targetModel)
		playHarvestSound(targetModel)
	end

	-- Yield text and animation only for the harvesting player
	if not isObserver then
		playHarvestAnim()
		if targetModel and targetModel.Parent then
			showYieldText(targetModel, qty, displayName)
		else
			-- Node was destroyed on this hit — show text near player instead
			showNotify("+" .. tostring(qty) .. " " .. displayName)
		end
	end
end)

-- ── HarvestNotify handler ────────────────────────────────────────────

harvestNotify.OnClientEvent:Connect(function(message: string)
	showNotify(message)
	if string.find(message, "broke") then
		toolBreakSound:Play()
	end
end)
