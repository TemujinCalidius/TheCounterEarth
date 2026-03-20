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

local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── Screen-level notification GUI (for error messages) ──────────────

local notifyScreenGui = Instance.new("ScreenGui")
notifyScreenGui.Name = "GatherNotifications"
notifyScreenGui.DisplayOrder = 15
notifyScreenGui.ResetOnSpawn = false
notifyScreenGui.IgnoreGuiInset = true
notifyScreenGui.Parent = playerGui

-- ── Notify (floating text near player head, or centered screen for errors) ──

local function showNotify(message: string, isError: boolean?)
	if isError then
		-- Screen-center notification — impossible to miss
		local label = Instance.new("TextLabel")
		label.Name = "ErrorNotify"
		label.Size = UDim2.new(0, 400, 0, 40)
		label.Position = UDim2.new(0.5, 0, 0.35, 0)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.BackgroundColor3 = Color3.fromRGB(30, 20, 20)
		label.BackgroundTransparency = 0.3
		label.Text = message
		label.TextColor3 = Color3.fromRGB(215, 80, 75)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.TextStrokeTransparency = 0.3
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.Parent = notifyScreenGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = label

		-- Fade out after 1.5s
		task.delay(1.5, function()
			if not label.Parent then return end
			local tween = TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			})
			tween:Play()
			tween.Completed:Wait()
			if label.Parent then label:Destroy() end
		end)
		return
	end

	-- Normal: BillboardGui above player head
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then return end

	local bb = Instance.new("BillboardGui")
	bb.Name              = "GatherNotify"
	bb.Adornee           = head
	bb.Size              = UDim2.new(0, 250, 0, 30)
	bb.StudsOffset       = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop       = true
	bb.Parent            = playerGui

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text                  = message
	label.TextColor3            = Color3.fromRGB(255, 200, 80)
	label.Font                  = Enum.Font.GothamBold
	label.TextSize              = 14
	label.TextStrokeTransparency = 0.3
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

	-- Trees and boulders are heavier — scale shake down for more realistic mass feel
	local isTree = model:GetAttribute("_IsTree") == true
	local isCutPoint = model:GetAttribute("_CutPoint") == true
	local isBoulder = model:GetAttribute("_ScatterItem") == "boulder"
	local shakeScale = if isTree or isCutPoint or isBoulder then 0.6 else 1.0

	-- For cut points, shake the trunk model instead (via TrunkRef ObjectValue)
	local shakeTarget = model
	if isCutPoint then
		local trunkRef = model:FindFirstChild("TrunkRef")
		if trunkRef and trunkRef:IsA("ObjectValue") and trunkRef.Value and trunkRef.Value.Parent then
			shakeTarget = trunkRef.Value
		end
	end

	local shakeRoot = shakeTarget.PrimaryPart or shakeTarget:FindFirstChildWhichIsA("BasePart")
	if not shakeRoot or not shakeTarget.Parent then return end

	local originalCFrame = shakeTarget:GetPivot()
	task.spawn(function()
		for i = 1, 6 do
			if not shakeTarget.Parent then return end
			-- Shake intensity decreases over time (strong hit → settle)
			local intensity = (1 - (i - 1) / 6) * shakeScale
			local offset = Vector3.new(
				(math.random() - 0.5) * 0.4 * intensity,
				(math.random() - 0.5) * 0.15 * intensity,
				(math.random() - 0.5) * 0.4 * intensity
			)
			shakeTarget:PivotTo(originalCFrame + offset)
			task.wait(0.04)
		end
		if shakeTarget.Parent then
			shakeTarget:PivotTo(originalCFrame)
		end
	end)
end

-- ── Particle bursts (trees / cut points) ────────────────────────────

local function emitLeafParticles(model: Model)
	local emitter = model:FindFirstChild("LeafParticles", true)
	if emitter and emitter:IsA("ParticleEmitter") then
		emitter:Emit(8)
	end
end

local function emitWoodChips(model: Model)
	local emitter = model:FindFirstChild("WoodChipParticles", true)
	if emitter and emitter:IsA("ParticleEmitter") then
		emitter:Emit(12)
	end
end

local function emitStoneChips(model: Model)
	local emitter = model:FindFirstChild("StoneChipParticles", true)
	if emitter and emitter:IsA("ParticleEmitter") then
		emitter:Emit(10)
	end
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
	reed     = "HarvestReed",
	oak_tree = "ChopWood",
	boulder  = "MineRock",
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

-- ── Node health bar ──────────────────────────────────────────────────
-- Shows a health bar above nodes being harvested (trees, cut points, etc.)

local activeHealthBars: { [Model]: BillboardGui } = {}

local function updateNodeHealthBar(model: Model)
	if not model or not model.Parent then return end
	local hp = tonumber(model:GetAttribute("_NodeHealth")) or 0
	local maxHp = tonumber(model:GetAttribute("_NodeMaxHealth")) or 1
	if maxHp <= 0 then maxHp = 1 end
	local ratio = math.clamp(hp / maxHp, 0, 1)

	-- Remove bar if node is dead
	if hp <= 0 then
		local existing = activeHealthBars[model]
		if existing and existing.Parent then existing:Destroy() end
		activeHealthBars[model] = nil
		return
	end

	-- Create or reuse bar
	local bb = activeHealthBars[model]
	if not bb or not bb.Parent then
		local adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if not adornee then return end

		bb = Instance.new("BillboardGui")
		bb.Name = "NodeHealthBar"
		bb.Adornee = adornee
		bb.Size = UDim2.new(0, 120, 0, 12)
		bb.StudsOffset = Vector3.new(0, 3, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 35
		bb.Parent = playerGui

		-- Background
		local bg = Instance.new("Frame")
		bg.Name = "Bg"
		bg.Size = UDim2.new(1, 0, 1, 0)
		bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		bg.BackgroundTransparency = 0.3
		bg.BorderSizePixel = 0
		bg.Parent = bb

		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(0, 4)
		bgCorner.Parent = bg

		-- Fill bar
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(80, 180, 80)
		fill.BorderSizePixel = 0
		fill.Parent = bg

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 4)
		fillCorner.Parent = fill

		-- Stroke
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(60, 60, 60)
		stroke.Thickness = 1
		stroke.Transparency = 0.5
		stroke.Parent = bg

		activeHealthBars[model] = bb
	end

	-- Update fill width
	local bg = bb:FindFirstChild("Bg")
	if bg then
		local fill = bg:FindFirstChild("Fill")
		if fill then
			fill.Size = UDim2.new(ratio, 0, 1, 0)
			-- Color: green → yellow → red
			if ratio > 0.5 then
				fill.BackgroundColor3 = Color3.fromRGB(80, 180, 80)
			elseif ratio > 0.25 then
				fill.BackgroundColor3 = Color3.fromRGB(200, 180, 50)
			else
				fill.BackgroundColor3 = Color3.fromRGB(200, 60, 50)
			end
		end
	end

	-- Auto-hide after 4 seconds of no updates
	task.delay(4, function()
		local bar = activeHealthBars[model]
		if bar and bar == bb and bar.Parent then
			bar:Destroy()
			activeHealthBars[model] = nil
		end
	end)
end

-- ── HarvestResult handler ────────────────────────────────────────────

harvestResult.OnClientEvent:Connect(function(targetModel: Model, qty: number, displayName: string, _nodeDestroyed: boolean, isHarvester: boolean?)
	-- Shake, sound, and particles are visible/audible to everyone nearby
	if targetModel and targetModel.Parent then
		shakeModel(targetModel)
		playHarvestSound(targetModel)
		emitLeafParticles(targetModel)
		emitWoodChips(targetModel)
		emitStoneChips(targetModel)
	end

	-- Animation plays for the harvesting player (even with 0 yield, e.g. chopping trees)
	if isHarvester then
		playHarvestAnim()
		-- Update health bar on the node being harvested
		if targetModel and targetModel.Parent then
			updateNodeHealthBar(targetModel)
		end
	end

	-- Yield text only when items were actually received
	if qty > 0 then
		if targetModel and targetModel.Parent then
			showYieldText(targetModel, qty, displayName)
		else
			showNotify("+" .. tostring(qty) .. " " .. displayName)
		end
	end
end)

-- ── HarvestNotify handler ────────────────────────────────────────────

harvestNotify.OnClientEvent:Connect(function(message: string)
	local isError = string.find(message, "full") ~= nil or string.find(message, "need") ~= nil
	showNotify(message, isError)
	if string.find(message, "broke") then
		toolBreakSound:Play()
	end
end)
