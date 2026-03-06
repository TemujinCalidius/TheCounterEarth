local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config        = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local AssetIds      = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AssetIds"))
local StatsConfig   = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StatsConfig"))
local ItemRegistry  = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))

local remotesFolder           = ReplicatedStorage:WaitForChild("Remotes")
local sprintIntentRemote      = remotesFolder:WaitForChild("SprintIntent")
local hotbarEquipRemote       = remotesFolder:WaitForChild("HotbarEquipRequest")
local hotbarAttackRemote      = remotesFolder:WaitForChild("HotbarAttackRequest")
local unpinFromHotbarRemote   = remotesFolder:WaitForChild("UnpinFromHotbar")
local swapHotbarSlotsRemote   = remotesFolder:WaitForChild("SwapHotbarSlots")
local hotbarSlotCount = math.clamp(math.floor(tonumber(Config.Hotbar and Config.Hotbar.Slots) or 9), 1, 9)

-- Expanded survival panel dimensions
local PANEL_WIDTH = 352
local EXPANDED_HEIGHT = 156  -- 3 bars x 40px + status row 28px + 8px padding
local EXPAND_TWEEN  = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local COLLAPSE_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function normalizeAssetId(value: any): string
	if type(value) == "number" then
		return "rbxassetid://" .. tostring(value)
	end
	if type(value) ~= "string" or value == "" then
		return ""
	end
	if value:match("^%d+$") then
		return "rbxassetid://" .. value
	end
	return value
end

local function createRoundedCorner(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function smooth(current: number, target: number, speed: number, dt: number): number
	return current + (target - current) * math.clamp(dt * speed, 0, 1)
end

-- ---------------------------------------------------------------------------
-- Chat + CoreGui config
-- ---------------------------------------------------------------------------

local function configureChatWindow()
	local chatPosition = UDim2.new(0, 12, 1, -280)
	local chatSize = UDim2.new(0, 420, 0, 240)

	local function applyLegacyChatCore()
		pcall(function() StarterGui:SetCore("ChatWindowPosition", chatPosition) end)
		pcall(function() StarterGui:SetCore("ChatWindowSize", chatSize) end)
	end

	local function applyTextChatConfig()
		local windowConfig = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
		if not windowConfig then return end
		pcall(function() windowConfig.HorizontalAlignment = Enum.HorizontalAlignment.Left end)
		pcall(function() windowConfig.VerticalAlignment = Enum.VerticalAlignment.Bottom end)
		pcall(function() windowConfig.Position = chatPosition end)
		pcall(function() windowConfig.Size = chatSize end)
	end

	task.spawn(function()
		for _ = 1, 10 do
			applyLegacyChatCore()
			applyTextChatConfig()
			task.wait(1)
		end
	end)
end

local function configureCoreGui()
	task.spawn(function()
		for _ = 1, 10 do
			pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false) end)
			pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)
			task.wait(1)
		end
	end)
end

configureChatWindow()
configureCoreGui()

-- ---------------------------------------------------------------------------
-- UI construction helpers
-- ---------------------------------------------------------------------------

local function createBarRow(
	parent: Instance,
	title: string,
	iconId: string,
	fallbackIconText: string,
	yOffset: number,
	fillColor: Color3
): { BarFill: Frame, ValueLabel: TextLabel, BarBackground: Frame }

	local row = Instance.new("Frame")
	row.Name = title .. "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(332, 40)
	row.Position = UDim2.fromOffset(10, yOffset)
	row.Parent = parent

	local iconFrame = Instance.new("Frame")
	iconFrame.Name = "IconFrame"
	iconFrame.Size = UDim2.fromOffset(32, 32)
	iconFrame.Position = UDim2.fromOffset(4, 4)
	iconFrame.BackgroundColor3 = Color3.fromRGB(26, 30, 40)
	iconFrame.BorderSizePixel = 0
	iconFrame.Parent = row
	createRoundedCorner(iconFrame, UDim.new(0, 8))

	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "IconImage"
	iconImage.BackgroundTransparency = 1
	iconImage.Size = UDim2.fromScale(0.72, 0.72)
	iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
	iconImage.Position = UDim2.fromScale(0.5, 0.5)
	iconImage.Image = iconId
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.Parent = iconFrame

	local fallbackText = Instance.new("TextLabel")
	fallbackText.Name = "FallbackText"
	fallbackText.BackgroundTransparency = 1
	fallbackText.Size = UDim2.fromScale(1, 1)
	fallbackText.Font = Enum.Font.GothamBold
	fallbackText.TextColor3 = Color3.fromRGB(245, 245, 245)
	fallbackText.TextScaled = true
	fallbackText.Text = fallbackIconText
	fallbackText.Visible = iconId == ""
	fallbackText.Parent = iconFrame

	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Size = UDim2.fromOffset(200, 16)
	barBackground.Position = UDim2.fromOffset(44, 8)
	barBackground.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = row
	createRoundedCorner(barBackground, UDim.new(0, 8))

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = fillColor
	barFill.BorderSizePixel = 0
	barFill.Parent = barBackground
	createRoundedCorner(barFill, UDim.new(0, 8))

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "ValueLabel"
	valueLabel.BackgroundTransparency = 1
	valueLabel.Position = UDim2.fromOffset(248, 4)
	valueLabel.Size = UDim2.fromOffset(80, 24)
	valueLabel.Font = Enum.Font.GothamMedium
	valueLabel.TextColor3 = Color3.fromRGB(225, 230, 240)
	valueLabel.TextSize = 14
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = "0 / 0"
	valueLabel.Parent = row

	return { BarFill = barFill, ValueLabel = valueLabel, BarBackground = barBackground }
end

local function createStatusBadge(parent: Instance, xOffset: number, label: string, color: Color3): { Frame: Frame, Visible: (boolean) -> () }
	local badge = Instance.new("Frame")
	badge.Name = label .. "Badge"
	badge.Size = UDim2.fromOffset(90, 22)
	badge.Position = UDim2.fromOffset(xOffset, 3)
	badge.BackgroundColor3 = color
	badge.BackgroundTransparency = 0.4
	badge.BorderSizePixel = 0
	badge.Visible = false
	badge.Parent = parent
	createRoundedCorner(badge, UDim.new(0, 6))

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextSize = 12
	text.Text = label
	text.Parent = badge

	local function setVisible(v: boolean)
		badge.Visible = v
	end

	return { Frame = badge, Visible = setVisible }
end

-- ---------------------------------------------------------------------------
-- Vignette
-- ---------------------------------------------------------------------------

local vignetteGui = Instance.new("ScreenGui")
vignetteGui.Name = "GameplayVignette"
vignetteGui.ResetOnSpawn = false
vignetteGui.IgnoreGuiInset = true
vignetteGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
vignetteGui.DisplayOrder = 1
vignetteGui.Parent = playerGui

local vignetteImageId = normalizeAssetId(AssetIds.Images.Vignette)
local vignetteOverlay = Instance.new("ImageLabel")
vignetteOverlay.Name = "EnergyVignette"
vignetteOverlay.BackgroundTransparency = 1
vignetteOverlay.Size = UDim2.fromScale(1, 1)
vignetteOverlay.Position = UDim2.fromScale(0, 0)
vignetteOverlay.Image = vignetteImageId
vignetteOverlay.ImageColor3 = Color3.fromRGB(255, 255, 255)
vignetteOverlay.ImageTransparency = 1
vignetteOverlay.ScaleType = Enum.ScaleType.Stretch
vignetteOverlay.ZIndex = 1
vignetteOverlay.Visible = vignetteImageId ~= ""
vignetteOverlay.Parent = vignetteGui

-- ---------------------------------------------------------------------------
-- Main HUD ScreenGui
-- ---------------------------------------------------------------------------

local hud = Instance.new("ScreenGui")
hud.Name = "GameplayHud"
hud.ResetOnSpawn = false
hud.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hud.DisplayOrder = 2
hud.Parent = playerGui

-- Overlay for drag ghosts — IgnoreGuiInset so ghost tracks the cursor exactly.
local hudDragOverlay = Instance.new("ScreenGui")
hudDragOverlay.Name             = "HudDragOverlay"
hudDragOverlay.ResetOnSpawn     = false
hudDragOverlay.IgnoreGuiInset   = true
hudDragOverlay.DisplayOrder     = 100
hudDragOverlay.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
hudDragOverlay.Parent           = playerGui

-- Main panel (Health / Energy / Credits)
local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromOffset(PANEL_WIDTH, 126)
root.Position = UDim2.fromOffset(18, 18)
root.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
root.BackgroundTransparency = 0.2
root.BorderSizePixel = 0
root.Parent = hud
createRoundedCorner(root, UDim.new(0, 12))

local rootStroke = Instance.new("UIStroke")
rootStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
rootStroke.Thickness = 1
rootStroke.Transparency = 0.6
rootStroke.Color = Color3.fromRGB(210, 220, 245)
rootStroke.Parent = root

-- Expand/collapse chevron hint (bottom-right of main panel)
local chevron = Instance.new("TextLabel")
chevron.Name = "Chevron"
chevron.BackgroundTransparency = 1
chevron.Size = UDim2.fromOffset(20, 14)
chevron.Position = UDim2.fromOffset(326, 108)
chevron.Font = Enum.Font.GothamBold
chevron.TextColor3 = Color3.fromRGB(160, 170, 195)
chevron.TextSize = 10
chevron.Text = "v"
chevron.Parent = root

local healthRow = createBarRow(root, "Health", normalizeAssetId(AssetIds.Images.HealthIcon), "H", 8,  Color3.fromRGB(232, 70, 70))
local energyRow = createBarRow(root, "Energy", normalizeAssetId(AssetIds.Images.EnergyIcon), "E", 46, Color3.fromRGB(90, 205, 120))

-- Credits row
local creditsRow = Instance.new("Frame")
creditsRow.Name = "CreditsRow"
creditsRow.BackgroundTransparency = 1
creditsRow.Size = UDim2.fromOffset(332, 28)
creditsRow.Position = UDim2.fromOffset(10, 88)
creditsRow.Parent = root

local creditsIconFrame = Instance.new("Frame")
creditsIconFrame.Name = "IconFrame"
creditsIconFrame.Size = UDim2.fromOffset(32, 24)
creditsIconFrame.Position = UDim2.fromOffset(4, 2)
creditsIconFrame.BackgroundColor3 = Color3.fromRGB(26, 30, 40)
creditsIconFrame.BorderSizePixel = 0
creditsIconFrame.Parent = creditsRow
createRoundedCorner(creditsIconFrame, UDim.new(0, 8))

local creditsIcon = Instance.new("ImageLabel")
creditsIcon.Name = "IconImage"
creditsIcon.BackgroundTransparency = 1
creditsIcon.Size = UDim2.fromScale(0.72, 0.72)
creditsIcon.AnchorPoint = Vector2.new(0.5, 0.5)
creditsIcon.Position = UDim2.fromScale(0.5, 0.5)
creditsIcon.Image = normalizeAssetId(AssetIds.Images.CreditIcon)
creditsIcon.ScaleType = Enum.ScaleType.Fit
creditsIcon.Parent = creditsIconFrame

local creditsFallback = Instance.new("TextLabel")
creditsFallback.Name = "FallbackText"
creditsFallback.BackgroundTransparency = 1
creditsFallback.Size = UDim2.fromScale(1, 1)
creditsFallback.Font = Enum.Font.GothamBold
creditsFallback.TextColor3 = Color3.fromRGB(255, 230, 120)
creditsFallback.TextScaled = true
creditsFallback.Text = "$"
creditsFallback.Visible = creditsIcon.Image == ""
creditsFallback.Parent = creditsIconFrame

local creditsTitle = Instance.new("TextLabel")
creditsTitle.Name = "Title"
creditsTitle.BackgroundTransparency = 1
creditsTitle.Position = UDim2.fromOffset(44, 3)
creditsTitle.Size = UDim2.fromOffset(120, 22)
creditsTitle.Font = Enum.Font.GothamMedium
creditsTitle.TextColor3 = Color3.fromRGB(225, 230, 240)
creditsTitle.TextSize = 14
creditsTitle.TextXAlignment = Enum.TextXAlignment.Left
creditsTitle.Text = "Credits"
creditsTitle.Parent = creditsRow

local creditsValue = Instance.new("TextLabel")
creditsValue.Name = "Value"
creditsValue.BackgroundTransparency = 1
creditsValue.Position = UDim2.fromOffset(168, 3)
creditsValue.Size = UDim2.fromOffset(160, 22)
creditsValue.Font = Enum.Font.GothamBold
creditsValue.TextColor3 = Color3.fromRGB(255, 230, 120)
creditsValue.TextSize = 16
creditsValue.TextXAlignment = Enum.TextXAlignment.Right
creditsValue.Text = "0"
creditsValue.Parent = creditsRow

-- ---------------------------------------------------------------------------
-- Expanded survival panel (slides down from main panel)
-- ---------------------------------------------------------------------------

local expandedPanel = Instance.new("Frame")
expandedPanel.Name = "SurvivalPanel"
expandedPanel.Size = UDim2.fromOffset(PANEL_WIDTH, 0)   -- starts collapsed
expandedPanel.Position = UDim2.fromOffset(18, 148)      -- sits right below root (18+126+4 gap)
expandedPanel.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
expandedPanel.BackgroundTransparency = 0.2
expandedPanel.BorderSizePixel = 0
expandedPanel.ClipsDescendants = true
expandedPanel.Parent = hud
createRoundedCorner(expandedPanel, UDim.new(0, 12))

local expandedStroke = Instance.new("UIStroke")
expandedStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
expandedStroke.Thickness = 1
expandedStroke.Transparency = 0.6
expandedStroke.Color = Color3.fromRGB(210, 220, 245)
expandedStroke.Parent = expandedPanel

-- Survival stat bars inside the expanded panel
local hungerRow  = createBarRow(expandedPanel, "Hunger",  "", "HG", 4,  Color3.fromRGB(220, 140, 40))
local thirstRow  = createBarRow(expandedPanel, "Thirst",  "", "TH", 44, Color3.fromRGB(60, 160, 230))
local fatigueRow = createBarRow(expandedPanel, "Fatigue", "", "FT", 84, Color3.fromRGB(160, 100, 220))

-- Status effect badges row
local statusRow = Instance.new("Frame")
statusRow.Name = "StatusRow"
statusRow.BackgroundTransparency = 1
statusRow.Size = UDim2.fromOffset(332, 28)
statusRow.Position = UDim2.fromOffset(10, 124)
statusRow.Parent = expandedPanel

local bleedBadge  = createStatusBadge(statusRow, 0,   "Bleeding", Color3.fromRGB(180, 40,  40))
local poisonBadge = createStatusBadge(statusRow, 96,  "Poisoned", Color3.fromRGB(60,  150, 60))

-- ---------------------------------------------------------------------------
-- Panel expand / collapse logic
-- ---------------------------------------------------------------------------

local panelOpen = false
local isHovered = false
local activeTween: Tween? = nil

local function setPanelOpen(open: boolean)
	if open == panelOpen then return end
	panelOpen = open

	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end

	local targetHeight = open and EXPANDED_HEIGHT or 0
	local tweenInfo = open and EXPAND_TWEEN or COLLAPSE_TWEEN
	chevron.Text = open and "^" or "v"

	activeTween = TweenService:Create(expandedPanel, tweenInfo, {
		Size = UDim2.fromOffset(PANEL_WIDTH, targetHeight),
	})
	activeTween:Play()
end

root.MouseEnter:Connect(function()
	isHovered = true
	setPanelOpen(true)
end)

root.MouseLeave:Connect(function()
	isHovered = false
	-- let RenderStepped decide based on warning state
end)

expandedPanel.MouseEnter:Connect(function()
	isHovered = true
end)

expandedPanel.MouseLeave:Connect(function()
	isHovered = false
end)

-- ---------------------------------------------------------------------------
-- Hotbar
-- ---------------------------------------------------------------------------

local hotbarRoot = Instance.new("Frame")
hotbarRoot.Name = "HotbarRoot"
hotbarRoot.AnchorPoint = Vector2.new(0.5, 1)
hotbarRoot.Position = UDim2.new(0.5, 0, 1, -18)
hotbarRoot.Size = UDim2.fromOffset((hotbarSlotCount * 58) + 14, 72)
hotbarRoot.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
hotbarRoot.BackgroundTransparency = 0.2
hotbarRoot.BorderSizePixel = 0
hotbarRoot.Parent = hud
createRoundedCorner(hotbarRoot, UDim.new(0, 12))

local hotbarStroke = Instance.new("UIStroke")
hotbarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
hotbarStroke.Thickness = 1
hotbarStroke.Transparency = 0.6
hotbarStroke.Color = Color3.fromRGB(210, 220, 245)
hotbarStroke.Parent = hotbarRoot

-- Hotbar drag-to-reorder state
local HOTBAR_DRAG_THRESHOLD = 8
local hotbarDragSlot        = 0
local hotbarDragStartPos    = Vector2.new(0, 0)
local hotbarIsDragging      = false
local hotbarDragGhost: Frame? = nil

local function cleanupHotbarDrag()
	hotbarDragSlot   = 0
	hotbarIsDragging = false
	if hotbarDragGhost then
		hotbarDragGhost:Destroy()
		hotbarDragGhost = nil
	end
end

type HotbarSlotUI = {
	frame:       Frame,
	stroke:      UIStroke,
	iconImage:   ImageLabel,
	abbrevLabel: TextLabel,
	unpinBtn:    TextButton,
	qtyLabel:    TextLabel,
}
local hotbarSlotUIs: { HotbarSlotUI } = {}

for slot = 1, hotbarSlotCount do
	local slotFrame = Instance.new("Frame")
	slotFrame.Name            = "Slot" .. tostring(slot)
	slotFrame.Size            = UDim2.fromOffset(52, 52)
	slotFrame.Position        = UDim2.fromOffset(9 + (slot - 1) * 58, 10)
	slotFrame.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
	slotFrame.BorderSizePixel = 0
	slotFrame.Parent          = hotbarRoot
	createRoundedCorner(slotFrame, UDim.new(0, 8))

	local slotStroke = Instance.new("UIStroke")
	slotStroke.Name             = "Stroke"
	slotStroke.ApplyStrokeMode  = Enum.ApplyStrokeMode.Border
	slotStroke.Thickness        = 1
	slotStroke.Transparency     = 0.5
	slotStroke.Color            = Color3.fromRGB(95, 105, 125)
	slotStroke.Parent           = slotFrame

	-- Slot number (top-left, tiny)
	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name               = "Key"
	keyLabel.BackgroundTransparency = 1
	keyLabel.Position           = UDim2.fromOffset(3, 2)
	keyLabel.Size               = UDim2.fromOffset(14, 10)
	keyLabel.Font               = Enum.Font.GothamBold
	keyLabel.TextColor3         = Color3.fromRGB(150, 162, 190)
	keyLabel.TextSize           = 10
	keyLabel.TextXAlignment     = Enum.TextXAlignment.Left
	keyLabel.Text               = tostring(slot)
	keyLabel.ZIndex             = 3
	keyLabel.Parent             = slotFrame

	-- Item icon (shown when def.icon exists)
	local iconImage = Instance.new("ImageLabel")
	iconImage.Name               = "Icon"
	iconImage.BackgroundTransparency = 1
	iconImage.Position           = UDim2.fromOffset(8, 10)
	iconImage.Size               = UDim2.fromOffset(36, 36)
	iconImage.ScaleType          = Enum.ScaleType.Fit
	iconImage.Image              = ""
	iconImage.Visible            = false
	iconImage.ZIndex             = 2
	iconImage.Parent             = slotFrame

	-- 3-letter abbreviation fallback (shown when no icon)
	local abbrevLabel = Instance.new("TextLabel")
	abbrevLabel.Name              = "Abbrev"
	abbrevLabel.BackgroundTransparency = 1
	abbrevLabel.Position          = UDim2.fromOffset(3, 14)
	abbrevLabel.Size              = UDim2.fromOffset(46, 32)
	abbrevLabel.Font              = Enum.Font.GothamBold
	abbrevLabel.TextColor3        = Color3.fromRGB(200, 210, 230)
	abbrevLabel.TextSize          = 11
	abbrevLabel.TextXAlignment    = Enum.TextXAlignment.Center
	abbrevLabel.TextWrapped       = true
	abbrevLabel.TextScaled        = false
	abbrevLabel.Text              = ""
	abbrevLabel.Visible           = false
	abbrevLabel.ZIndex            = 2
	abbrevLabel.Parent            = slotFrame

	-- x unpin button (top-right, visible only when slot occupied)
	local capturedSlot = slot
	local unpinBtn = Instance.new("TextButton")
	unpinBtn.Name               = "Unpin"
	unpinBtn.Size               = UDim2.fromOffset(14, 14)
	unpinBtn.Position           = UDim2.fromOffset(36, 1)
	unpinBtn.BackgroundColor3   = Color3.fromRGB(120, 35, 35)
	unpinBtn.BorderSizePixel    = 0
	unpinBtn.Text               = "x"
	unpinBtn.Font               = Enum.Font.GothamBold
	unpinBtn.TextColor3         = Color3.fromRGB(240, 120, 120)
	unpinBtn.TextSize           = 11
	unpinBtn.Visible            = false
	unpinBtn.ZIndex             = 4
	unpinBtn.Parent             = slotFrame
	createRoundedCorner(unpinBtn, UDim.new(0, 4))

	unpinBtn.Activated:Connect(function()
		unpinFromHotbarRemote:FireServer(capturedSlot)
	end)

	-- Stack count badge (bottom-right, shown for consumables with qty > 1)
	local qtyLabel = Instance.new("TextLabel")
	qtyLabel.Name               = "Qty"
	qtyLabel.BackgroundTransparency = 1
	qtyLabel.Position           = UDim2.fromOffset(32, 36)
	qtyLabel.Size               = UDim2.fromOffset(18, 14)
	qtyLabel.Font               = Enum.Font.GothamBold
	qtyLabel.TextColor3         = Color3.fromRGB(255, 255, 255)
	qtyLabel.TextSize           = 10
	qtyLabel.TextXAlignment     = Enum.TextXAlignment.Right
	qtyLabel.Text               = ""
	qtyLabel.Visible            = false
	qtyLabel.ZIndex             = 3
	qtyLabel.Parent             = slotFrame

	-- Drag to reorder hotbar slots.
	slotFrame.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		hotbarDragSlot     = capturedSlot
		hotbarDragStartPos = UserInputService:GetMouseLocation()
	end)

	hotbarSlotUIs[slot] = {
		frame       = slotFrame,
		stroke      = slotStroke,
		iconImage   = iconImage,
		abbrevLabel = abbrevLabel,
		unpinBtn    = unpinBtn,
		qtyLabel    = qtyLabel,
	}
end

-- ---------------------------------------------------------------------------
-- Audio
-- ---------------------------------------------------------------------------

local function createLoopedSound(name: string, soundIdValue: any): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = normalizeAssetId(soundIdValue)
	sound.Looped = true
	sound.Volume = 0
	sound.PlaybackSpeed = 1
	sound.Parent = SoundService
	if sound.SoundId ~= "" then
		sound:Play()
	end
	return sound
end

local breathingSound = createLoopedSound("BreathingLoop", AssetIds.Sounds.Breathing)
local heartbeatSound = createLoopedSound("HeartbeatLoop", AssetIds.Sounds.Heartbeat)

-- ---------------------------------------------------------------------------
-- Character reference
-- ---------------------------------------------------------------------------

local humanoid: Humanoid? = nil

local function onCharacterAdded(character: Model)
	humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

local sprintHeld = false
local equippedSlot = 0

local function getSlotAttributeName(slot: number): string
	return "HotbarSlot" .. tostring(slot)
end

local function refreshHotbar()
	local equippedAttr = player:GetAttribute("HotbarEquippedSlot")
	equippedSlot = type(equippedAttr) == "number" and math.floor(equippedAttr) or 0

	for slot = 1, hotbarSlotCount do
		local ui = hotbarSlotUIs[slot]
		if not ui then continue end

		local item   = player:GetAttribute(getSlotAttributeName(slot))
		local itemId = type(item) == "string" and item or ""
		local def    = itemId ~= "" and ItemRegistry.get(itemId) or nil
		local hasIcon = def ~= nil and def.icon ~= ""

		-- Icon or abbreviation
		if itemId == "" then
			ui.iconImage.Visible   = false
			ui.abbrevLabel.Visible = false
			ui.unpinBtn.Visible    = false
			ui.qtyLabel.Visible    = false
		elseif hasIcon then
			ui.iconImage.Image     = def.icon
			ui.iconImage.Visible   = true
			ui.abbrevLabel.Visible = false
			ui.unpinBtn.Visible    = true
		else
			ui.iconImage.Visible   = false
			ui.abbrevLabel.Text    = def and def.displayName:sub(1, 3):upper() or itemId:sub(1, 3):upper()
			ui.abbrevLabel.Visible = true
			ui.unpinBtn.Visible    = true
		end

		-- Qty badge: sum across all InvSlot_N that match this item.
		if itemId ~= "" and def and def.onConsume ~= nil then
			local maxSlots = math.max(1, math.floor(tonumber(player:GetAttribute("MaxInvSlots")) or 5))
			local qty = 0
			for n = 1, maxSlots do
				if tostring(player:GetAttribute("InvSlot_" .. n) or "") == itemId then
					qty += math.max(0, math.floor(tonumber(player:GetAttribute("InvQty_" .. n)) or 0))
				end
			end
			if qty > 1 then
				ui.qtyLabel.Text    = tostring(qty)
				ui.qtyLabel.Visible = true
			else
				ui.qtyLabel.Visible = false
			end
		else
			ui.qtyLabel.Visible = false
		end

		-- Selection highlight
		local isEquipped = slot == equippedSlot
		ui.stroke.Color       = isEquipped and Color3.fromRGB(115, 230, 140) or Color3.fromRGB(95, 105, 125)
		ui.stroke.Thickness   = isEquipped and 2 or 1
		ui.stroke.Transparency = isEquipped and 0.1 or 0.5
	end
end

for slot = 1, hotbarSlotCount do
	player:GetAttributeChangedSignal(getSlotAttributeName(slot)):Connect(refreshHotbar)
end
player:GetAttributeChangedSignal("HotbarEquippedSlot"):Connect(refreshHotbar)
-- Refresh qty badges when consumable stacks are consumed/gained.
player.AttributeChanged:Connect(function(attrName)
	if attrName:sub(1, 8) == "InvSlot_" or attrName:sub(1, 7) == "InvQty_" then
		refreshHotbar()
	end
end)
refreshHotbar()

-- setSprint defined before any handler that calls it.
local function setSprint(value: boolean)
	if sprintHeld == value then return end
	sprintHeld = value
	sprintIntentRemote:FireServer(sprintHeld)
end

local function tryAttackWithEquippedItem()
	if equippedSlot < 1 or equippedSlot > hotbarSlotCount then return end
	local itemValue = player:GetAttribute(getSlotAttributeName(equippedSlot))
	if type(itemValue) == "string" and itemValue ~= "" then
		hotbarAttackRemote:FireServer()
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		tryAttackWithEquippedItem()
		return
	end
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.LeftShift then setSprint(true); return end

	local numKeys = {
		[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
		[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
	}
	local slotNum = numKeys[input.KeyCode]
	if slotNum then
		hotbarEquipRemote:FireServer(slotNum)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then setSprint(false) end
end)

UserInputService.WindowFocusReleased:Connect(function()
	setSprint(false)
end)

-- ---------------------------------------------------------------------------
-- Hotbar drag-to-reorder input handlers
-- ---------------------------------------------------------------------------

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	if hotbarDragSlot == 0 then return end

	local pos = UserInputService:GetMouseLocation()

	if not hotbarIsDragging and (pos - hotbarDragStartPos).Magnitude > HOTBAR_DRAG_THRESHOLD then
		local itemId = tostring(player:GetAttribute(getSlotAttributeName(hotbarDragSlot)) or "")
		if itemId ~= "" then
			hotbarIsDragging = true
			local ghost = Instance.new("Frame")
			ghost.Size                 = UDim2.new(0, 44, 0, 44)
			ghost.Position             = UDim2.new(0, pos.X - 22, 0, pos.Y - 22)
			ghost.BackgroundColor3     = Color3.fromRGB(42, 48, 66)
			ghost.BackgroundTransparency = 0.25
			ghost.BorderSizePixel      = 0
			ghost.ZIndex               = 100
			ghost.Parent               = hudDragOverlay
			local gs = Instance.new("UIStroke")
			gs.Color     = Color3.fromRGB(70, 130, 200)
			gs.Thickness = 2
			gs.Parent    = ghost
			local gc = Instance.new("UICorner")
			gc.CornerRadius = UDim.new(0, 8)
			gc.Parent = ghost
			local def = ItemRegistry.get(itemId)
			if def and def.icon ~= "" then
				local img = Instance.new("ImageLabel")
				img.Size                 = UDim2.new(0.8, 0, 0.8, 0)
				img.Position             = UDim2.new(0.1, 0, 0.1, 0)
				img.BackgroundTransparency = 1
				img.Image                = def.icon
				img.ScaleType            = Enum.ScaleType.Fit
				img.ZIndex               = 101
				img.Parent               = ghost
			else
				local lbl = Instance.new("TextLabel")
				lbl.Size               = UDim2.new(1, 0, 1, 0)
				lbl.BackgroundTransparency = 1
				lbl.Font               = Enum.Font.GothamBold
				lbl.TextColor3         = Color3.fromRGB(200, 210, 230)
				lbl.TextSize           = 11
				lbl.TextXAlignment     = Enum.TextXAlignment.Center
				lbl.TextWrapped        = true
				lbl.Text               = def and def.displayName:sub(1, 3):upper() or "?"
				lbl.ZIndex             = 101
				lbl.Parent             = ghost
			end
			hotbarDragGhost = ghost
		else
			hotbarDragSlot = 0
		end
	end

	if hotbarIsDragging and hotbarDragGhost then
		local p2 = UserInputService:GetMouseLocation()
		hotbarDragGhost.Position = UDim2.new(0, p2.X - 22, 0, p2.Y - 22)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if hotbarDragSlot == 0 then return end

	local fromSlot    = hotbarDragSlot
	local wasDragging = hotbarIsDragging
	cleanupHotbarDrag()

	if not wasDragging then return end

	local pos = Vector2.new(input.Position.X, input.Position.Y)
	for slotNum = 1, hotbarSlotCount do
		local ui = hotbarSlotUIs[slotNum]
		if ui then
			local ap = ui.frame.AbsolutePosition
			local as = ui.frame.AbsoluteSize
			if pos.X >= ap.X and pos.X <= ap.X + as.X
				and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y
			then
				if slotNum ~= fromSlot then
					swapHotbarSlotsRemote:FireServer(fromSlot, slotNum)
				end
				break
			end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Warning colour thresholds (normalised 0-1)
-- ---------------------------------------------------------------------------
local WARN = StatsConfig.Hunger.WarningThreshold / StatsConfig.Hunger.Max  -- same ratio for all (all use 20/100)

local COLOR_NORMAL_HUNGER  = Color3.fromRGB(220, 140,  40)
local COLOR_WARN_HUNGER    = Color3.fromRGB(210,  60,  40)
local COLOR_NORMAL_THIRST  = Color3.fromRGB( 60, 160, 230)
local COLOR_WARN_THIRST    = Color3.fromRGB(210,  60,  40)
local COLOR_NORMAL_FATIGUE = Color3.fromRGB(160, 100, 220)
local COLOR_WARN_FATIGUE   = Color3.fromRGB(210,  60,  40)

-- Badge pulse timer
local badgePulseTime = 0

-- ---------------------------------------------------------------------------
-- RenderStepped -- update all HUD elements
-- ---------------------------------------------------------------------------

RunService.RenderStepped:Connect(function(deltaTime)
	-- Core stats

	local energy    = player:GetAttribute("Energy")
	local maxEnergy = player:GetAttribute("MaxEnergy")
	local credits   = player:GetAttribute("Credits")

	if type(energy) ~= "number" then energy = 0 end
	if type(maxEnergy) ~= "number" or maxEnergy <= 0 then maxEnergy = Config.Energy.Max end
	if type(credits) ~= "number" then credits = 0 end

	local health    = player:GetAttribute("Health")
	local maxHealth = player:GetAttribute("MaxHealth")
	if humanoid and humanoid.Parent then
		health    = humanoid.Health
		maxHealth = humanoid.MaxHealth
	end
	if type(health) ~= "number" then health = 100 end
	if type(maxHealth) ~= "number" or maxHealth <= 0 then maxHealth = 100 end

	local energyRatio = math.clamp(energy / maxEnergy, 0, 1)
	local healthRatio = math.clamp(health / maxHealth, 0, 1)

	healthRow.BarFill.Size = UDim2.new(healthRatio, 0, 1, 0)
	energyRow.BarFill.Size = UDim2.new(energyRatio, 0, 1, 0)
	healthRow.ValueLabel.Text = string.format("%d / %d", math.floor(health + 0.5), math.floor(maxHealth + 0.5))
	energyRow.ValueLabel.Text = string.format("%d / %d", math.floor(energy + 0.5), math.floor(maxEnergy + 0.5))
	creditsValue.Text = string.format("%d", math.floor(credits))

	-- Survival stats

	local maxHunger  = StatsConfig.Hunger.Max
	local maxThirst  = StatsConfig.Thirst.Max
	local maxFatigue = StatsConfig.Fatigue.Max

	local hunger  = player:GetAttribute(StatsConfig.AttributeNames.Hunger)
	local thirst  = player:GetAttribute(StatsConfig.AttributeNames.Thirst)
	local fatigue = player:GetAttribute(StatsConfig.AttributeNames.Fatigue)

	if type(hunger)  ~= "number" then hunger  = maxHunger  end
	if type(thirst)  ~= "number" then thirst  = maxThirst  end
	if type(fatigue) ~= "number" then fatigue = maxFatigue end

	local hungerRatio  = math.clamp(hunger  / maxHunger,  0, 1)
	local thirstRatio  = math.clamp(thirst  / maxThirst,  0, 1)
	local fatigueRatio = math.clamp(fatigue / maxFatigue, 0, 1)

	hungerRow.BarFill.Size  = UDim2.new(hungerRatio,  0, 1, 0)
	thirstRow.BarFill.Size  = UDim2.new(thirstRatio,  0, 1, 0)
	fatigueRow.BarFill.Size = UDim2.new(fatigueRatio, 0, 1, 0)

	hungerRow.ValueLabel.Text  = string.format("%d%%", math.floor(hungerRatio  * 100 + 0.5))
	thirstRow.ValueLabel.Text  = string.format("%d%%", math.floor(thirstRatio  * 100 + 0.5))
	fatigueRow.ValueLabel.Text = string.format("%d%%", math.floor(fatigueRatio * 100 + 0.5))

	-- Warning colour tint
	hungerRow.BarFill.BackgroundColor3  = hungerRatio  < WARN and COLOR_WARN_HUNGER  or COLOR_NORMAL_HUNGER
	thirstRow.BarFill.BackgroundColor3  = thirstRatio  < WARN and COLOR_WARN_THIRST  or COLOR_NORMAL_THIRST
	fatigueRow.BarFill.BackgroundColor3 = fatigueRatio < WARN and COLOR_WARN_FATIGUE or COLOR_NORMAL_FATIGUE

	-- Status effects

	local isBleeding = player:GetAttribute(StatsConfig.AttributeNames.IsBleeding) == true
	local isPoisoned = player:GetAttribute(StatsConfig.AttributeNames.IsPoisoned) == true

	bleedBadge.Visible(isBleeding)
	poisonBadge.Visible(isPoisoned)

	-- Pulse the badge backgrounds when active
	if isBleeding or isPoisoned then
		badgePulseTime += deltaTime
		local pulse = 0.3 + 0.3 * math.abs(math.sin(badgePulseTime * 3))
		if isBleeding then bleedBadge.Frame.BackgroundTransparency  = pulse end
		if isPoisoned then poisonBadge.Frame.BackgroundTransparency = pulse end
	else
		badgePulseTime = 0
	end

	-- Auto-expand logic

	local isWarning = hungerRatio  < WARN
		or thirstRatio  < WARN
		or fatigueRatio < WARN
		or isBleeding
		or isPoisoned

	if isWarning then
		setPanelOpen(true)
	elseif not isHovered and panelOpen then
		setPanelOpen(false)
	end

	-- Vignette

	if vignetteOverlay.Visible then
		local vignetteIntensity = math.clamp(1 - energyRatio, 0, 1) ^ 1.2
		local targetTransparency = 1 - (vignetteIntensity * 0.9)
		vignetteOverlay.ImageTransparency = smooth(vignetteOverlay.ImageTransparency, targetTransparency, 5, deltaTime)
	end

	-- Audio

	local breathingIntensity = math.clamp(1 - energyRatio, 0, 1)
	local breathingTargetVolume = breathingIntensity * Config.Audio.BreathingMaxVolume
	local breathingTargetSpeed  = Config.Audio.BreathingMinSpeed
		+ (Config.Audio.BreathingMaxSpeed - Config.Audio.BreathingMinSpeed) * breathingIntensity

	if breathingSound.SoundId ~= "" and not breathingSound.IsPlaying then breathingSound:Play() end
	breathingSound.Volume        = smooth(breathingSound.Volume,        breathingTargetVolume, 5, deltaTime)
	breathingSound.PlaybackSpeed = smooth(breathingSound.PlaybackSpeed, breathingTargetSpeed,  5, deltaTime)

	local heartbeatStart = math.clamp(Config.Health.HeartbeatStartRatio, 0.05, 1)
	local heartbeatIntensity = 0
	if health > 0 and healthRatio < heartbeatStart then
		heartbeatIntensity = math.clamp((heartbeatStart - healthRatio) / heartbeatStart, 0, 1)
	end

	local heartbeatTargetVolume = heartbeatIntensity * Config.Audio.HeartbeatMaxVolume
	local heartbeatTargetSpeed  = Config.Audio.HeartbeatMinSpeed
		+ (Config.Audio.HeartbeatMaxSpeed - Config.Audio.HeartbeatMinSpeed) * heartbeatIntensity

	if heartbeatSound.SoundId ~= "" and not heartbeatSound.IsPlaying then heartbeatSound:Play() end
	heartbeatSound.Volume        = smooth(heartbeatSound.Volume,        heartbeatTargetVolume, 7, deltaTime)
	heartbeatSound.PlaybackSpeed = smooth(heartbeatSound.PlaybackSpeed, heartbeatTargetSpeed,  7, deltaTime)
end)
