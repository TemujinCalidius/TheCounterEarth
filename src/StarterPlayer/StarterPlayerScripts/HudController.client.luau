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

-- Mobile / touch detection helpers
local isMobile = UserInputService.TouchEnabled

local function isClickOrTap(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMoveInput(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

-- Remote for saving UI panel positions across sessions
local saveUIPosRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SaveUIPosition")

-- Restore a saved panel position from player attribute, returns true if restored
local function restorePanelPosition(panel: Frame, panelName: string)
	local posStr = player:GetAttribute("_UIPos_" .. panelName)
	if type(posStr) == "string" then
		local x, y = string.match(posStr, "^(-?%d+),(-?%d+)$")
		if x and y then
			panel.Position = UDim2.new(0, tonumber(x) :: number, 0, tonumber(y) :: number)
			return true
		end
	end
	return false
end

-- Make a panel draggable via its title bar area (top 30px).
-- panelName is used to persist position across sessions.
local function makeDraggable(panel: Frame, panelName: string?)
	local dragging    = false
	local dragStart   = Vector2.new(0, 0)
	local posStart    = Vector2.new(0, 0)

	panel.InputBegan:Connect(function(input)
		if not isClickOrTap(input) then return end
		-- Only drag from top 30px (title area)
		local localY = input.Position.Y - panel.AbsolutePosition.Y
		if localY > 30 then return end
		dragging   = true
		dragStart  = Vector2.new(input.Position.X, input.Position.Y)
		posStart   = Vector2.new(panel.AbsolutePosition.X, panel.AbsolutePosition.Y)
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if not isMoveInput(input) then return end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
		panel.Position = UDim2.new(0, posStart.X + delta.X, 0, posStart.Y + delta.Y)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if isClickOrTap(input) and dragging then
			dragging = false
			if panelName then
				saveUIPosRemote:FireServer(panelName, panel.AbsolutePosition.X, panel.AbsolutePosition.Y)
			end
		end
	end)
end

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
local useItemRemote           = remotesFolder:WaitForChild("UseItem")
local harvestHitRemote        = remotesFolder:WaitForChild("HarvestHit")
local HARVEST_HIT_COOLDOWN    = 1.5
local lastHarvestHitTime      = 0
local lastHarvestTarget: Model? = nil
local startPlacementEvent     = ReplicatedStorage
	:WaitForChild("ClientBindables"):WaitForChild("StartPlacement") :: BindableEvent
local CookingConfig   = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CookingConfig"))
local openCampfireRemote   = remotesFolder:WaitForChild("OpenCampfire")
local campfireStateRemote  = remotesFolder:WaitForChild("CampfireState")
local campfireAddRemote    = remotesFolder:WaitForChild("CampfireAddItem")
local campfireTakeRemote   = remotesFolder:WaitForChild("CampfireTakeItem")
local openLootBagRemote    = remotesFolder:WaitForChild("OpenLootBag")
local lootBagStateRemote   = remotesFolder:WaitForChild("LootBagState")
local takeLootBagItemRemote = remotesFolder:WaitForChild("TakeLootBagItem")
local tradeRequestRemote     = remotesFolder:WaitForChild("TradeRequest")
local tradeResponseRemote    = remotesFolder:WaitForChild("TradeResponse")
local tradeStateRemote       = remotesFolder:WaitForChild("TradeState")
local tradeUpdateOfferRemote = remotesFolder:WaitForChild("TradeUpdateOffer")
local tradeConfirmRemote     = remotesFolder:WaitForChild("TradeConfirm")
local tradeCancelRemote      = remotesFolder:WaitForChild("TradeCancel")
local hotbarSlotCount = math.clamp(math.floor(tonumber(Config.Hotbar and Config.Hotbar.Slots) or 9), 1, 9)

-- Expanded survival panel dimensions
local PANEL_WIDTH = 352
local EXPANDED_HEIGHT = 236  -- 5 bars x 40px + status row 28px + 8px padding
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

local function createStatusBadge(parent: Instance, xOffset: number, label: string, color: Color3, iconAssetId: string?): { Frame: Frame, Visible: (boolean) -> () }
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

	local iconId = iconAssetId and normalizeAssetId(iconAssetId) or ""
	if iconId ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(16, 16)
		icon.Position = UDim2.fromOffset(4, 3)
		icon.Image = iconId
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = badge
	end

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, iconId ~= "" and -22 or 0, 1, 0)
	text.Position = UDim2.fromOffset(iconId ~= "" and 22 or 0, 0)
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextSize = 11
	text.Text = label
	text.TextXAlignment = Enum.TextXAlignment.Left
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
local chevron = Instance.new("TextButton")
chevron.Name = "Chevron"
chevron.BackgroundTransparency = 1
chevron.AutoButtonColor = false
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
local hungerRow  = createBarRow(expandedPanel, "Hunger",  normalizeAssetId(AssetIds.Images.HungerIcon),  "HG", 4,   Color3.fromRGB(220, 140, 40))
local thirstRow  = createBarRow(expandedPanel, "Thirst",  normalizeAssetId(AssetIds.Images.ThirstIcon),  "TH", 44,  Color3.fromRGB(60, 160, 230))
local fatigueRow = createBarRow(expandedPanel, "Fatigue", normalizeAssetId(AssetIds.Images.FatigueIcon), "FT", 84,  Color3.fromRGB(160, 100, 220))
local bloodRow   = createBarRow(expandedPanel, "Blood",   normalizeAssetId(AssetIds.Images.BloodIcon),   "BL", 124, Color3.fromRGB(180, 40, 40))
local poisonRow  = createBarRow(expandedPanel, "Poison",  normalizeAssetId(AssetIds.Images.PoisonIcon),  "PS", 164, Color3.fromRGB(60, 150, 60))

-- Status effect badges row
local statusRow = Instance.new("Frame")
statusRow.Name = "StatusRow"
statusRow.BackgroundTransparency = 1
statusRow.Size = UDim2.fromOffset(332, 28)
statusRow.Position = UDim2.fromOffset(10, 204)
statusRow.Parent = expandedPanel

local bleedBadge  = createStatusBadge(statusRow, 0,   "Bleeding", Color3.fromRGB(180, 40,  40), AssetIds.Images.BloodIcon)
local poisonBadge = createStatusBadge(statusRow, 96,  "Poisoned", Color3.fromRGB(60,  150, 60), AssetIds.Images.PoisonIcon)

-- ---------------------------------------------------------------------------
-- Panel expand / collapse logic
-- ---------------------------------------------------------------------------

local panelOpen = false
local isPinned = false
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

chevron.MouseButton1Click:Connect(function()
	isPinned = not isPinned
	setPanelOpen(isPinned)
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
hotbarRoot.Active = true  -- Sink touch input so it doesn't trigger Roblox's thumbstick
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
local hotbarDragOverlayFrame: Frame? = nil

local function cleanupHotbarDrag()
	hotbarDragSlot   = 0
	hotbarIsDragging = false
	if hotbarDragGhost then
		hotbarDragGhost:Destroy()
		hotbarDragGhost = nil
	end
	if hotbarDragOverlayFrame then
		hotbarDragOverlayFrame:Destroy()
		hotbarDragOverlayFrame = nil
	end
end

type HotbarSlotUI = {
	frame:       Frame,
	stroke:      UIStroke,
	iconImage:   ImageLabel,
	abbrevLabel: TextLabel,
	unpinBtn:    TextButton,
	qtyLabel:    TextLabel,
	spoilBarBg:  Frame,
	spoilBarFill: Frame,
	durBarBg:    Frame,
	durBarFill:  Frame,
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

	-- Spoil bar (thin bar at bottom, hidden by default)
	local spoilBarBg = Instance.new("Frame")
	spoilBarBg.Name                  = "SpoilBarBg"
	spoilBarBg.Size                  = UDim2.new(1, -6, 0, 3)
	spoilBarBg.Position              = UDim2.new(0, 3, 1, -5)
	spoilBarBg.BackgroundColor3      = Color3.fromRGB(20, 20, 20)
	spoilBarBg.BorderSizePixel       = 0
	spoilBarBg.Visible               = false
	spoilBarBg.ZIndex                = 4
	spoilBarBg.Parent                = slotFrame
	createRoundedCorner(spoilBarBg, UDim.new(0, 2))

	local spoilBarFill = Instance.new("Frame")
	spoilBarFill.Name                = "SpoilBarFill"
	spoilBarFill.Size                = UDim2.new(1, 0, 1, 0)
	spoilBarFill.BackgroundColor3    = Color3.fromRGB(0, 255, 0)
	spoilBarFill.BorderSizePixel     = 0
	spoilBarFill.ZIndex              = 5
	spoilBarFill.Parent              = spoilBarBg
	createRoundedCorner(spoilBarFill, UDim.new(0, 2))

	-- Durability bar (thin bar above spoil bar, hidden by default)
	local durBarBg = Instance.new("Frame")
	durBarBg.Name                    = "DurBarBg"
	durBarBg.Size                    = UDim2.new(1, -6, 0, 3)
	durBarBg.Position                = UDim2.new(0, 3, 1, -5)
	durBarBg.BackgroundColor3        = Color3.fromRGB(20, 20, 20)
	durBarBg.BorderSizePixel         = 0
	durBarBg.Visible                 = false
	durBarBg.ZIndex                  = 4
	durBarBg.Parent                  = slotFrame
	createRoundedCorner(durBarBg, UDim.new(0, 2))

	local durBarFill = Instance.new("Frame")
	durBarFill.Name                  = "DurBarFill"
	durBarFill.Size                  = UDim2.new(1, 0, 1, 0)
	durBarFill.BackgroundColor3      = Color3.fromRGB(0, 200, 0)
	durBarFill.BorderSizePixel       = 0
	durBarFill.ZIndex                = 5
	durBarFill.Parent                = durBarBg
	createRoundedCorner(durBarFill, UDim.new(0, 2))

	-- Drag to reorder hotbar slots + tap to equip.
	slotFrame.InputBegan:Connect(function(input)
		if not isClickOrTap(input) then return end
		hotbarDragSlot     = capturedSlot
		hotbarDragStartPos = UserInputService:GetMouseLocation()
	end)

	-- Tap-to-equip on the slot. Drags are handled by the full-screen overlay
	-- created in InputChanged, so we skip if dragging is active.
	slotFrame.InputEnded:Connect(function(input)
		if not isClickOrTap(input) then return end
		if hotbarIsDragging then return end
		if hotbarDragSlot ~= capturedSlot then return end
		if hotbarDragSlot == 0 then return end
		cleanupHotbarDrag()
		hotbarEquipRemote:FireServer(capturedSlot)
		local slotItem = player:GetAttribute(getSlotAttributeName(capturedSlot))
		if type(slotItem) == "string" and slotItem ~= "" then
			local slotDef = ItemRegistry.get(slotItem)
			if slotDef and slotDef.category == "placeable" then
				startPlacementEvent:Fire(slotItem)
			end
		end
	end)

	hotbarSlotUIs[slot] = {
		frame        = slotFrame,
		stroke       = slotStroke,
		iconImage    = iconImage,
		abbrevLabel  = abbrevLabel,
		unpinBtn     = unpinBtn,
		qtyLabel     = qtyLabel,
		spoilBarBg   = spoilBarBg,
		spoilBarFill = spoilBarFill,
		durBarBg     = durBarBg,
		durBarFill   = durBarFill,
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

-- Chewing sound — plays briefly when eating food (not drinks)
local chewingSound = Instance.new("Sound")
chewingSound.Name = "ChewingSound"
chewingSound.SoundId = AssetIds.Sounds.Chewing
chewingSound.Looped = true
chewingSound.Volume = 0.5
chewingSound.Parent = SoundService

-- ── Eating state ─────────────────────────────────────────────────────────
local EAT_CHANNEL_TIME = 2.0   -- seconds to eat
local isEating = false

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

-- Double-tap W to toggle sprint (alternative for players whose Shift is intercepted)
local DOUBLE_TAP_WINDOW = 0.3 -- seconds
local lastWTapTime = 0
local doubleTapSprint = false

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
		if itemId ~= "" then
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

		-- Spoil bar: find the earliest expiry across all matching inventory slots
		if itemId ~= "" then
			local def2 = ItemRegistry.get(itemId)
			if def2 and def2.perishSeconds then
				local maxSlots = math.max(1, math.floor(tonumber(player:GetAttribute("MaxInvSlots")) or 5))
				local earliest = math.huge
				for n = 1, maxSlots do
					if tostring(player:GetAttribute("InvSlot_" .. n) or "") == itemId then
						local expiryStr = player:GetAttribute("InvExpires_" .. n)
						if expiryStr and expiryStr ~= "" then
							for ts in string.gmatch(expiryStr, "[^,]+") do
								local t = tonumber(ts)
								if t and t < earliest then earliest = t end
							end
						end
					end
				end
				if earliest < math.huge then
					local remaining = math.max(0, earliest - os.time())
					local ratio = math.clamp(remaining / def2.perishSeconds, 0, 1)
					ui.spoilBarFill.Size = UDim2.new(ratio, 0, 1, 0)
					ui.spoilBarFill.BackgroundColor3 = Color3.fromRGB(
						math.floor(255 * math.clamp((1 - ratio) * 2, 0, 1)),
						math.floor(255 * math.clamp(ratio * 2, 0, 1)),
						0
					)
					ui.spoilBarBg.Visible = true
				else
					ui.spoilBarBg.Visible = false
				end
			else
				ui.spoilBarBg.Visible = false
			end
		else
			ui.spoilBarBg.Visible = false
		end

		-- Durability bar: find the first durability value for the active item
		if itemId ~= "" then
			local durDef = ItemRegistry.get(itemId)
			if durDef and durDef.durabilityMax then
				local maxSlots = math.max(1, math.floor(tonumber(player:GetAttribute("MaxInvSlots")) or 5))
				local firstDur: number? = nil
				for n = 1, maxSlots do
					if tostring(player:GetAttribute("InvSlot_" .. n) or "") == itemId then
						local durStr = player:GetAttribute("InvDurability_" .. n)
						if type(durStr) == "string" and durStr ~= "" then
							local first = string.match(durStr, "^([^,]+)")
							if first then
								firstDur = tonumber(first)
								break
							end
						end
					end
				end
				if firstDur then
					local ratio = math.clamp(firstDur / durDef.durabilityMax, 0, 1)
					ui.durBarFill.Size = UDim2.new(ratio, 0, 1, 0)
					-- Green > 50%, Yellow 25-50%, Red < 25%
					local r = math.floor(255 * math.clamp((1 - ratio) * 2, 0, 1))
					local g = math.floor(255 * math.clamp(ratio * 2, 0, 1))
					ui.durBarFill.BackgroundColor3 = Color3.fromRGB(r, g, 0)
					ui.durBarBg.Visible = true
				else
					ui.durBarBg.Visible = false
				end
			else
				ui.durBarBg.Visible = false
			end
		else
			ui.durBarBg.Visible = false
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
	if attrName:sub(1, 8) == "InvSlot_" or attrName:sub(1, 7) == "InvQty_" or attrName:sub(1, 11) == "InvExpires_" or attrName:sub(1, 15) == "InvDurability_" then
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
	if player:GetAttribute("IsPlacementMode") == true then return end
	if equippedSlot < 1 or equippedSlot > hotbarSlotCount then return end
	local itemValue = player:GetAttribute(getSlotAttributeName(equippedSlot))
	if type(itemValue) ~= "string" or itemValue == "" then return end

	local def = ItemRegistry.get(itemValue)

	-- Placeable: enter placement mode instead of attacking
	if def and def.category == "placeable" then
		startPlacementEvent:Fire(itemValue)
		return
	end

	if def and def.onConsume then
		if isEating then return end
		isEating = true

		-- Start chewing sound (not for drinks)
		if not ItemRegistry.hasTag(def, "drink") then
			chewingSound:Play()
		end

		-- Play eating animation
		local eatTrack: AnimationTrack? = nil
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			local animator = hum:FindFirstChildOfClass("Animator")
			if animator then
				local anim = Instance.new("Animation")
				anim.AnimationId = AssetIds.Animations.Eating
				local ok, track = pcall(function()
					return animator:LoadAnimation(anim)
				end)
				if ok and track then
					eatTrack = track
					eatTrack.Priority = Enum.AnimationPriority.Action
					eatTrack:Play()
				end
			end
		end

		-- Wait the full eat duration, then consume
		task.spawn(function()
			task.wait(EAT_CHANNEL_TIME)
			if not isEating then return end

			useItemRemote:FireServer(itemValue)
			chewingSound:Stop()
			if eatTrack then eatTrack:Stop() end
			isEating = false
		end)
		return
	end

	-- Proximity harvest: left-click anywhere while near a harvest node.
	-- Locks onto one target at a time — won't switch to a nearby node mid-harvest.
	do
		-- Client-side cooldown (1.5s) — lets the animation play out
		local now = os.clock()
		if (now - lastHarvestHitTime) < HARVEST_HIT_COOLDOWN then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			-- If we have a locked target, keep hitting it until it's gone or out of range
			if lastHarvestTarget and lastHarvestTarget.Parent then
				local hp = tonumber(lastHarvestTarget:GetAttribute("_NodeHealth")) or 0
				local part = lastHarvestTarget.PrimaryPart or lastHarvestTarget:FindFirstChildWhichIsA("BasePart")
				if hp > 0 and part and (root.Position - part.Position).Magnitude < 8 then
					lastHarvestHitTime = now
					harvestHitRemote:FireServer(lastHarvestTarget)
					return
				end
				-- Target dead or out of range — release lock
				lastHarvestTarget = nil
			end

			-- Find the closest harvest node within range
			local scatterFolder = Workspace:FindFirstChild("Scatter")
			if scatterFolder then
				local bestDist = 8
				local bestNode: Model? = nil
				for _, child in scatterFolder:GetChildren() do
					if child:IsA("Model") and child:GetAttribute("_ScatterItem") then
						local hp = tonumber(child:GetAttribute("_NodeHealth")) or 0
						if hp > 0 then
							local part = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
							if part then
								local dist = (root.Position - part.Position).Magnitude
								if dist < bestDist then
									bestDist = dist
									bestNode = child
								end
							end
						end
					end
				end
				if bestNode then
					lastHarvestTarget = bestNode
					lastHarvestHitTime = now
					-- Send to server even if wrong/no tool — server sends proper rejection message
					harvestHitRemote:FireServer(bestNode)
					return
				end
			end
		end
	end

	hotbarAttackRemote:FireServer()
end

-- Wrapper that also checks for nearby harvest nodes when nothing is equipped
local function onPlayerClick()
	local eqSlot = tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0
	local itemValue = ""
	if eqSlot >= 1 and eqSlot <= hotbarSlotCount then
		itemValue = player:GetAttribute(getSlotAttributeName(eqSlot))
		if type(itemValue) ~= "string" then itemValue = "" end
	end

	-- If player has something useful equipped, use normal attack flow
	if itemValue ~= "" then
		tryAttackWithEquippedItem()
		return
	end

	-- Nothing equipped (or empty slot) — still check for nearby harvest nodes
	-- so server can send "You need a knife" feedback
	local now = os.clock()
	if (now - lastHarvestHitTime) < HARVEST_HIT_COOLDOWN then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local scatterFolder = Workspace:FindFirstChild("Scatter")
	if not scatterFolder then return end

	local bestDist = 8
	local bestNode: Model? = nil
	for _, child in scatterFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("_ScatterItem") then
			local hp = tonumber(child:GetAttribute("_NodeHealth")) or 0
			if hp > 0 then
				local part = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
				if part then
					local dist = (root.Position - part.Position).Magnitude
					if dist < bestDist then
						bestDist = dist
						bestNode = child
					end
				end
			end
		end
	end

	if bestNode then
		lastHarvestHitTime = now
		harvestHitRemote:FireServer(bestNode)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if player:GetAttribute("IsPlacementMode") == true then return end

	if isClickOrTap(input) then
		-- On mobile, don't attack when tapping UI elements (hotbar, inventory, etc.)
		if input.UserInputType == Enum.UserInputType.Touch and gameProcessed then
			return
		end
		onPlayerClick()
		return
	end
	-- Sprint: accept both Shift keys regardless of gameProcessed
	-- (Roblox shift-lock or Windows accessibility can mark LeftShift as processed)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(true)
		return
	end

	-- Double-tap W to toggle sprint
	if input.KeyCode == Enum.KeyCode.W then
		local now = os.clock()
		if now - lastWTapTime < DOUBLE_TAP_WINDOW then
			doubleTapSprint = not doubleTapSprint
			setSprint(doubleTapSprint)
			lastWTapTime = 0 -- reset so triple-tap doesn't re-toggle
		else
			lastWTapTime = now
		end
	end

	if gameProcessed then return end

	local numKeys = {
		[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
		[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
	}
	local slotNum = numKeys[input.KeyCode]
	if slotNum then
		hotbarEquipRemote:FireServer(slotNum)

		-- Placeables: immediately enter placement mode on key press
		local slotItem = player:GetAttribute(getSlotAttributeName(slotNum))
		if type(slotItem) == "string" and slotItem ~= "" then
			local slotDef = ItemRegistry.get(slotItem)
			if slotDef and slotDef.category == "placeable" then
				startPlacementEvent:Fire(slotItem)
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		doubleTapSprint = false -- Shift release always clears double-tap state
		setSprint(false)
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	doubleTapSprint = false
	setSprint(false)
end)

-- Auto-cancel double-tap sprint when player stops moving
do
	local function watchRunning(humanoid: Humanoid)
		humanoid.Running:Connect(function(speed)
			if doubleTapSprint and speed < 0.1 then
				doubleTapSprint = false
				setSprint(false)
			end
		end)
	end
	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then watchRunning(hum) end
	end
	player.CharacterAdded:Connect(function(c)
		local hum = c:WaitForChild("Humanoid", 10)
		if hum then watchRunning(hum) end
	end)
end

-- ---------------------------------------------------------------------------
-- Mobile sprint toggle button
-- ---------------------------------------------------------------------------

if isMobile then
	local sprintBtn = Instance.new("ImageButton")
	sprintBtn.Name                   = "SprintToggle"
	sprintBtn.Size                   = UDim2.new(0, 56, 0, 56)
	sprintBtn.Position               = UDim2.new(1, -160, 1, -200)
	sprintBtn.AnchorPoint            = Vector2.new(1, 1)
	sprintBtn.BackgroundColor3       = Color3.fromRGB(42, 48, 66)
	sprintBtn.BackgroundTransparency = 0.3
	sprintBtn.Image                  = ""
	sprintBtn.ZIndex                 = 20
	sprintBtn.Parent                 = hud

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 10)
	btnCorner.Parent = sprintBtn

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color     = Color3.fromRGB(70, 130, 200)
	btnStroke.Thickness = 1.5
	btnStroke.Parent    = sprintBtn

	local btnLabel = Instance.new("TextLabel")
	btnLabel.Size                   = UDim2.new(1, 0, 1, 0)
	btnLabel.BackgroundTransparency = 1
	btnLabel.Text                   = "RUN"
	btnLabel.Font                   = Enum.Font.GothamBold
	btnLabel.TextSize               = 14
	btnLabel.TextColor3             = Color3.fromRGB(200, 210, 230)
	btnLabel.ZIndex                 = 21
	btnLabel.Parent                 = sprintBtn

	local mobileSprintActive = false

	sprintBtn.Activated:Connect(function()
		mobileSprintActive = not mobileSprintActive
		setSprint(mobileSprintActive)
		sprintBtn.BackgroundColor3 = mobileSprintActive
			and Color3.fromRGB(70, 130, 200)
			or Color3.fromRGB(42, 48, 66)
		btnLabel.Text = mobileSprintActive and "WALK" or "RUN"
	end)

	-- Auto-disable sprint when player stops moving (thumbstick released)
	local char = player.Character or player.CharacterAdded:Wait()
	local hum = char:WaitForChild("Humanoid")

	local function watchHumanoid(humanoid: Humanoid)
		humanoid.Running:Connect(function(speed)
			if mobileSprintActive and speed < 0.1 then
				mobileSprintActive = false
				setSprint(false)
				sprintBtn.BackgroundColor3 = Color3.fromRGB(42, 48, 66)
				btnLabel.Text = "RUN"
			end
		end)
	end

	watchHumanoid(hum)
	player.CharacterAdded:Connect(function(newChar)
		local newHum = newChar:WaitForChild("Humanoid")
		watchHumanoid(newHum)
	end)
end

-- ---------------------------------------------------------------------------
-- Hotbar drag-to-reorder input handlers
-- ---------------------------------------------------------------------------

UserInputService.InputChanged:Connect(function(input)
	if not isMoveInput(input) then return end
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

			-- Full-screen overlay to capture release (InputEnded on a GuiObject
			-- fires when cursor/finger leaves bounds, but this overlay covers the
			-- whole screen so it only fires on actual release).
			local overlay = Instance.new("Frame")
			overlay.Name                   = "HotbarDragCatcher"
			overlay.Size                   = UDim2.new(1, 0, 1, 0)
			overlay.BackgroundTransparency = 1
			overlay.ZIndex                 = 99
			overlay.Active                 = true
			overlay.Parent                 = hudDragOverlay
			hotbarDragOverlayFrame         = overlay

			overlay.InputEnded:Connect(function(endInput)
				if not isClickOrTap(endInput) then return end
				if hotbarDragSlot == 0 then return end
				local fromSlot = hotbarDragSlot
				cleanupHotbarDrag()
				local dropPos = Vector2.new(endInput.Position.X, endInput.Position.Y)
				for slotNum = 1, hotbarSlotCount do
					local ui = hotbarSlotUIs[slotNum]
					if ui then
						local ap = ui.frame.AbsolutePosition
						local as = ui.frame.AbsoluteSize
						if dropPos.X >= ap.X and dropPos.X <= ap.X + as.X
							and dropPos.Y >= ap.Y and dropPos.Y <= ap.Y + as.Y
						then
							if slotNum ~= fromSlot then
								swapHotbarSlotsRemote:FireServer(fromSlot, slotNum)
							end
							break
						end
					end
				end
			end)
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
	if not isClickOrTap(input) then return end
	if hotbarDragSlot == 0 then return end
	if hotbarIsDragging then return end -- overlay handles drag-drop

	-- Tap fallback
	local fromSlot = hotbarDragSlot
	cleanupHotbarDrag()
	hotbarEquipRemote:FireServer(fromSlot)
	local slotItem = player:GetAttribute(getSlotAttributeName(fromSlot))
	if type(slotItem) == "string" and slotItem ~= "" then
		local slotDef = ItemRegistry.get(slotItem)
		if slotDef and slotDef.category == "placeable" then
			startPlacementEvent:Fire(slotItem)
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
local COLOR_NORMAL_BLOOD   = Color3.fromRGB(180,  40,  40)
local COLOR_WARN_BLOOD     = Color3.fromRGB(100,  10,  10)
local COLOR_NORMAL_POISON  = Color3.fromRGB( 60, 150,  60)
local COLOR_WARN_POISON    = Color3.fromRGB(180, 200,  40)

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
	local maxBlood   = StatsConfig.Blood.Max
	local maxPoison  = StatsConfig.Poison.Max

	local hunger  = player:GetAttribute(StatsConfig.AttributeNames.Hunger)
	local thirst  = player:GetAttribute(StatsConfig.AttributeNames.Thirst)
	local fatigue = player:GetAttribute(StatsConfig.AttributeNames.Fatigue)
	local blood   = player:GetAttribute(StatsConfig.AttributeNames.Blood)
	local poison  = player:GetAttribute(StatsConfig.AttributeNames.Poison)

	if type(hunger)  ~= "number" then hunger  = maxHunger  end
	if type(thirst)  ~= "number" then thirst  = maxThirst  end
	if type(fatigue) ~= "number" then fatigue = maxFatigue end
	if type(blood)   ~= "number" then blood   = maxBlood   end
	if type(poison)  ~= "number" then poison  = 0          end

	local hungerRatio  = math.clamp(hunger  / maxHunger,  0, 1)
	local thirstRatio  = math.clamp(thirst  / maxThirst,  0, 1)
	local fatigueRatio = math.clamp(fatigue / maxFatigue, 0, 1)
	local bloodRatio   = math.clamp(blood   / maxBlood,   0, 1)
	local poisonRatio  = math.clamp(poison  / maxPoison,  0, 1)

	hungerRow.BarFill.Size  = UDim2.new(hungerRatio,  0, 1, 0)
	thirstRow.BarFill.Size  = UDim2.new(thirstRatio,  0, 1, 0)
	fatigueRow.BarFill.Size = UDim2.new(fatigueRatio, 0, 1, 0)
	bloodRow.BarFill.Size   = UDim2.new(bloodRatio,   0, 1, 0)
	poisonRow.BarFill.Size  = UDim2.new(poisonRatio,  0, 1, 0)

	hungerRow.ValueLabel.Text  = string.format("%d%%", math.floor(hungerRatio  * 100 + 0.5))
	thirstRow.ValueLabel.Text  = string.format("%d%%", math.floor(thirstRatio  * 100 + 0.5))
	fatigueRow.ValueLabel.Text = string.format("%d%%", math.floor(fatigueRatio * 100 + 0.5))
	bloodRow.ValueLabel.Text   = string.format("%d%%", math.floor(bloodRatio   * 100 + 0.5))
	poisonRow.ValueLabel.Text  = string.format("%d%%", math.floor(poisonRatio  * 100 + 0.5))

	-- Warning colour tint
	local bloodWarn  = StatsConfig.Blood.WarningThreshold  / maxBlood
	local poisonWarn = StatsConfig.Poison.WarningThreshold / maxPoison

	hungerRow.BarFill.BackgroundColor3  = hungerRatio  < WARN       and COLOR_WARN_HUNGER  or COLOR_NORMAL_HUNGER
	thirstRow.BarFill.BackgroundColor3  = thirstRatio  < WARN       and COLOR_WARN_THIRST  or COLOR_NORMAL_THIRST
	fatigueRow.BarFill.BackgroundColor3 = fatigueRatio < WARN       and COLOR_WARN_FATIGUE or COLOR_NORMAL_FATIGUE
	bloodRow.BarFill.BackgroundColor3   = bloodRatio   < bloodWarn  and COLOR_WARN_BLOOD   or COLOR_NORMAL_BLOOD
	poisonRow.BarFill.BackgroundColor3  = poisonRatio  > poisonWarn and COLOR_WARN_POISON  or COLOR_NORMAL_POISON

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

	-- Auto-expand logic (warnings force-open, click-pin keeps open, otherwise close)

	local isWarning = hungerRatio  < WARN
		or thirstRatio  < WARN
		or fatigueRatio < WARN
		or bloodRatio   < bloodWarn
		or poisonRatio  > poisonWarn
		or isBleeding
		or isPoisoned

	if isWarning or isPinned then
		setPanelOpen(true)
	else
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

-- ---------------------------------------------------------------------------
-- Campfire cooking UI — opens via ProximityPrompt on placed campfires
-- ---------------------------------------------------------------------------

local cookingPanel: Frame? = nil
local activeCampfireModel: Model? = nil
local cookingState: { [string]: any }? = nil
local cookingInputBtn: TextButton? = nil
local cookingOutputBtn: TextButton? = nil
local cookingProgressBar: Frame? = nil
local cookingTimerLabel: TextLabel? = nil
local cookingInputIcon: ImageLabel? = nil
local cookingInputQty: TextLabel? = nil
local cookingOutputIcon: ImageLabel? = nil
local cookingOutputQty: TextLabel? = nil
local foodPickerFrame: Frame? = nil

local function getItemAbbrev(itemId: string): string
	local def = ItemRegistry.get(itemId)
	if def then return string.sub(def.displayName, 1, 3):upper() end
	return string.sub(itemId, 1, 3):upper()
end

local function getItemIcon(itemId: string): string
	local def = ItemRegistry.get(itemId)
	return def and def.icon or ""
end

local function updateSlotVisual(btn: TextButton, iconLabel: ImageLabel, qtyLabel: TextLabel, slotData: { itemId: string, qty: number }?)
	if slotData and slotData.qty > 0 then
		local icon = getItemIcon(slotData.itemId)
		if icon ~= "" then
			iconLabel.Image = icon
			iconLabel.Visible = true
			btn.Text = ""
		else
			iconLabel.Visible = false
			btn.Text = getItemAbbrev(slotData.itemId)
		end
		qtyLabel.Text = tostring(slotData.qty)
		qtyLabel.Visible = true
	else
		iconLabel.Visible = false
		btn.Text = ""
		qtyLabel.Visible = false
	end
end

local function refreshCookingUI()
	if not cookingPanel or not cookingState then return end

	updateSlotVisual(cookingInputBtn :: TextButton, cookingInputIcon :: ImageLabel, cookingInputQty :: TextLabel, cookingState.input)
	updateSlotVisual(cookingOutputBtn :: TextButton, cookingOutputIcon :: ImageLabel, cookingOutputQty :: TextLabel, cookingState.output)

	-- Expose output item ID for InventoryController drag system
	local outBtn = cookingOutputBtn :: TextButton
	if cookingState.output and cookingState.output.qty > 0 then
		outBtn:SetAttribute("_ItemId", cookingState.output.itemId)
	else
		outBtn:SetAttribute("_ItemId", "")
	end

	-- Progress bar
	local bar = cookingProgressBar :: Frame
	local timer = cookingTimerLabel :: TextLabel
	if cookingState.input and cookingState.cookDuration > 0 then
		local ratio = math.clamp(cookingState.cookProgress / cookingState.cookDuration, 0, 1)
		bar.Size = UDim2.new(ratio, 0, 1, 0)
		bar.Visible = true
		local remaining = math.max(0, cookingState.cookDuration - cookingState.cookProgress)
		timer.Text = string.format("%.1fs", remaining)
		timer.Visible = true
	else
		bar.Size = UDim2.new(0, 0, 1, 0)
		bar.Visible = false
		timer.Visible = false
	end
end

local function closeFoodPicker()
	if foodPickerFrame then
		foodPickerFrame:Destroy()
		foodPickerFrame = nil
	end
end

local function openFoodPicker()
	closeFoodPicker()
	if not activeCampfireModel then return end

	-- Gather food items from player inventory
	local maxSlots = math.floor(tonumber(player:GetAttribute("MaxInvSlots")) or 5)
	local foodItems: { { itemId: string, qty: number } } = {}
	for i = 1, maxSlots do
		local slotItem = player:GetAttribute("InvSlot_" .. i)
		local slotQty  = tonumber(player:GetAttribute("InvQty_" .. i)) or 0
		if type(slotItem) == "string" and slotItem ~= "" and slotQty > 0 then
			local def = ItemRegistry.get(slotItem)
			if def and def.category == "food" then
				-- Check if already in list (merge stacks)
				local found = false
				for _, entry in ipairs(foodItems) do
					if entry.itemId == slotItem then
						entry.qty = entry.qty + slotQty
						found = true
						break
					end
				end
				if not found then
					table.insert(foodItems, { itemId = slotItem, qty = slotQty })
				end
			end
		end
	end

	if #foodItems == 0 then return end

	local pickerHeight = math.min(#foodItems * 32 + 8, 168)
	local picker = Instance.new("Frame")
	picker.Name = "FoodPicker"
	picker.Size = UDim2.fromOffset(180, pickerHeight)
	picker.Position = UDim2.new(0, 12, 0, -pickerHeight - 4)
	picker.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
	picker.BackgroundTransparency = 0.05
	picker.BorderSizePixel = 0
	picker.ClipsDescendants = true
	picker.Parent = cookingPanel

	local pickerCorner = Instance.new("UICorner")
	pickerCorner.CornerRadius = UDim.new(0, 8)
	pickerCorner.Parent = picker

	local pickerStroke = Instance.new("UIStroke")
	pickerStroke.Color = Color3.fromRGB(210, 220, 245)
	pickerStroke.Transparency = 0.6
	pickerStroke.Thickness = 1
	pickerStroke.Parent = picker

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = picker

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = picker

	for idx, entry in ipairs(foodItems) do
		local def = ItemRegistry.get(entry.itemId)
		local displayName = def and def.displayName or entry.itemId
		local recipe = CookingConfig.Recipes[entry.itemId]
		local cookable = recipe ~= nil

		local row = Instance.new("TextButton")
		row.Name = "Food_" .. idx
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundColor3 = cookable and Color3.fromRGB(35, 45, 30) or Color3.fromRGB(35, 35, 42)
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.Text = string.format("%s x%d%s", displayName, entry.qty, cookable and "" or " (raw)")
		row.TextColor3 = cookable and Color3.fromRGB(180, 220, 160) or Color3.fromRGB(160, 160, 170)
		row.TextSize = 13
		row.Font = Enum.Font.GothamMedium
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.AutoButtonColor = true
		row.LayoutOrder = idx
		row.Parent = picker

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 4)
		rowCorner.Parent = row

		local rowPad = Instance.new("UIPadding")
		rowPad.PaddingLeft = UDim.new(0, 6)
		rowPad.Parent = row

		row.MouseButton1Click:Connect(function()
			if not activeCampfireModel then return end
			-- Add 1 item at a time (can click repeatedly)
			local addQty = 1
			campfireAddRemote:FireServer(activeCampfireModel, entry.itemId, addQty)
			closeFoodPicker()
		end)
	end

	foodPickerFrame = picker
end

local function buildCookingPanel()
	if cookingPanel then return end

	local panel = Instance.new("Frame")
	panel.Name = "CookingPanel"
	panel.Size = UDim2.fromOffset(280, 90)
	panel.Position = UDim2.new(0.5, -140, 0.5, -45)
	panel.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = hud

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(210, 220, 245)
	panelStroke.Transparency = 0.6
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 20)
	title.Position = UDim2.fromOffset(0, 4)
	title.BackgroundTransparency = 1
	title.Text = "CAMPFIRE"
	title.TextColor3 = Color3.fromRGB(210, 180, 120)
	title.TextSize = 12
	title.Font = Enum.Font.GothamBold
	title.Parent = panel

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.Size = UDim2.fromOffset(20, 20)
	closeBtn.Position = UDim2.new(1, -24, 0, 4)
	closeBtn.BackgroundColor3 = Color3.fromRGB(120, 35, 35)
	closeBtn.BackgroundTransparency = 0.4
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextSize = 11
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = panel

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 4)
	closeBtnCorner.Parent = closeBtn

	-- Input slot (left)
	local inputBtn = Instance.new("TextButton")
	inputBtn.Name = "InputSlot"
	inputBtn.Size = UDim2.fromOffset(56, 56)
	inputBtn.Position = UDim2.fromOffset(16, 28)
	inputBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
	inputBtn.BackgroundTransparency = 0.1
	inputBtn.BorderSizePixel = 0
	inputBtn.Text = ""
	inputBtn.TextColor3 = Color3.fromRGB(200, 200, 210)
	inputBtn.TextSize = 11
	inputBtn.Font = Enum.Font.GothamMedium
	inputBtn.AutoButtonColor = true
	inputBtn.Parent = panel

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 6)
	inputCorner.Parent = inputBtn

	local inputStroke = Instance.new("UIStroke")
	inputStroke.Color = Color3.fromRGB(95, 105, 125)
	inputStroke.Transparency = 0.4
	inputStroke.Thickness = 1
	inputStroke.Parent = inputBtn

	local inputIcon = Instance.new("ImageLabel")
	inputIcon.Name = "Icon"
	inputIcon.Size = UDim2.fromOffset(40, 40)
	inputIcon.Position = UDim2.fromOffset(8, 6)
	inputIcon.BackgroundTransparency = 1
	inputIcon.ScaleType = Enum.ScaleType.Fit
	inputIcon.Visible = false
	inputIcon.Parent = inputBtn

	local inputQtyLabel = Instance.new("TextLabel")
	inputQtyLabel.Name = "Qty"
	inputQtyLabel.Size = UDim2.fromOffset(20, 14)
	inputQtyLabel.Position = UDim2.new(1, -22, 1, -16)
	inputQtyLabel.BackgroundTransparency = 1
	inputQtyLabel.Text = ""
	inputQtyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	inputQtyLabel.TextSize = 11
	inputQtyLabel.Font = Enum.Font.GothamBold
	inputQtyLabel.TextXAlignment = Enum.TextXAlignment.Right
	inputQtyLabel.Visible = false
	inputQtyLabel.Parent = inputBtn

	local inputLabel = Instance.new("TextLabel")
	inputLabel.Size = UDim2.fromOffset(56, 12)
	inputLabel.Position = UDim2.fromOffset(16, 84)
	inputLabel.BackgroundTransparency = 1
	inputLabel.Text = "INPUT"
	inputLabel.TextColor3 = Color3.fromRGB(140, 140, 155)
	inputLabel.TextSize = 9
	inputLabel.Font = Enum.Font.GothamMedium
	inputLabel.Parent = panel

	-- Progress bar area (center)
	local progressBg = Instance.new("Frame")
	progressBg.Name = "ProgressBg"
	progressBg.Size = UDim2.fromOffset(100, 10)
	progressBg.Position = UDim2.fromOffset(90, 50)
	progressBg.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
	progressBg.BorderSizePixel = 0
	progressBg.Parent = panel

	local progressBgCorner = Instance.new("UICorner")
	progressBgCorner.CornerRadius = UDim.new(0, 4)
	progressBgCorner.Parent = progressBg

	local progressFill = Instance.new("Frame")
	progressFill.Name = "Fill"
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.BackgroundColor3 = Color3.fromRGB(220, 160, 50)
	progressFill.BorderSizePixel = 0
	progressFill.Visible = false
	progressFill.Parent = progressBg

	local progressFillCorner = Instance.new("UICorner")
	progressFillCorner.CornerRadius = UDim.new(0, 4)
	progressFillCorner.Parent = progressFill

	local timerText = Instance.new("TextLabel")
	timerText.Name = "Timer"
	timerText.Size = UDim2.fromOffset(100, 14)
	timerText.Position = UDim2.fromOffset(90, 62)
	timerText.BackgroundTransparency = 1
	timerText.Text = ""
	timerText.TextColor3 = Color3.fromRGB(220, 180, 100)
	timerText.TextSize = 10
	timerText.Font = Enum.Font.GothamMedium
	timerText.Visible = false
	timerText.Parent = panel

	-- Arrow indicators
	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.fromOffset(100, 16)
	arrow.Position = UDim2.fromOffset(90, 34)
	arrow.BackgroundTransparency = 1
	arrow.Text = ">>>"
	arrow.TextColor3 = Color3.fromRGB(180, 150, 90)
	arrow.TextSize = 14
	arrow.Font = Enum.Font.GothamBold
	arrow.Parent = panel

	-- Output slot (right)
	local outputBtn = Instance.new("TextButton")
	outputBtn.Name = "OutputSlot"
	outputBtn.Size = UDim2.fromOffset(56, 56)
	outputBtn.Position = UDim2.fromOffset(208, 28)
	outputBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 30)
	outputBtn.BackgroundTransparency = 0.1
	outputBtn.BorderSizePixel = 0
	outputBtn.Text = ""
	outputBtn.TextColor3 = Color3.fromRGB(200, 200, 210)
	outputBtn.TextSize = 11
	outputBtn.Font = Enum.Font.GothamMedium
	outputBtn.AutoButtonColor = true
	outputBtn.Parent = panel

	local outputCorner = Instance.new("UICorner")
	outputCorner.CornerRadius = UDim.new(0, 6)
	outputCorner.Parent = outputBtn

	local outputStroke = Instance.new("UIStroke")
	outputStroke.Color = Color3.fromRGB(80, 120, 80)
	outputStroke.Transparency = 0.4
	outputStroke.Thickness = 1
	outputStroke.Parent = outputBtn

	local outputIcon = Instance.new("ImageLabel")
	outputIcon.Name = "Icon"
	outputIcon.Size = UDim2.fromOffset(40, 40)
	outputIcon.Position = UDim2.fromOffset(8, 6)
	outputIcon.BackgroundTransparency = 1
	outputIcon.ScaleType = Enum.ScaleType.Fit
	outputIcon.Visible = false
	outputIcon.Parent = outputBtn

	local outputQtyLabel = Instance.new("TextLabel")
	outputQtyLabel.Name = "Qty"
	outputQtyLabel.Size = UDim2.fromOffset(20, 14)
	outputQtyLabel.Position = UDim2.new(1, -22, 1, -16)
	outputQtyLabel.BackgroundTransparency = 1
	outputQtyLabel.Text = ""
	outputQtyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	outputQtyLabel.TextSize = 11
	outputQtyLabel.Font = Enum.Font.GothamBold
	outputQtyLabel.TextXAlignment = Enum.TextXAlignment.Right
	outputQtyLabel.Visible = false
	outputQtyLabel.Parent = outputBtn

	local outputLabel = Instance.new("TextLabel")
	outputLabel.Size = UDim2.fromOffset(56, 12)
	outputLabel.Position = UDim2.fromOffset(208, 84)
	outputLabel.BackgroundTransparency = 1
	outputLabel.Text = "OUTPUT"
	outputLabel.TextColor3 = Color3.fromRGB(140, 140, 155)
	outputLabel.TextSize = 9
	outputLabel.Font = Enum.Font.GothamMedium
	outputLabel.Parent = panel

	-- ObjectValue so InventoryController can find the active campfire for drag-drop
	local campfireRef = Instance.new("ObjectValue")
	campfireRef.Name = "ActiveCampfire"
	campfireRef.Parent = panel

	-- Store refs
	cookingPanel      = panel
	cookingInputBtn   = inputBtn
	cookingOutputBtn  = outputBtn
	restorePanelPosition(panel, "Cooking")
	makeDraggable(panel, "Cooking")
	cookingProgressBar = progressFill
	cookingTimerLabel = timerText
	cookingInputIcon  = inputIcon
	cookingInputQty   = inputQtyLabel
	cookingOutputIcon = outputIcon
	cookingOutputQty  = outputQtyLabel

	-- Click handlers
	inputBtn.MouseButton1Click:Connect(function()
		-- If input slot has items, take them back; otherwise toggle food picker
		if activeCampfireModel and cookingState and cookingState.input and cookingState.input.qty > 0 then
			campfireTakeRemote:FireServer(activeCampfireModel, "input", cookingState.input.qty)
		elseif foodPickerFrame then
			closeFoodPicker()
		else
			openFoodPicker()
		end
	end)

	outputBtn.MouseButton1Click:Connect(function()
		if not activeCampfireModel or not cookingState then return end
		if cookingState.output and cookingState.output.qty > 0 then
			campfireTakeRemote:FireServer(activeCampfireModel, "output", cookingState.output.qty)
		end
	end)

	closeBtn.MouseButton1Click:Connect(function()
		closeCookingPanel()
	end)
end

local function openCookingPanel(campfireModel: Model)
	if activeCampfireModel == campfireModel and cookingPanel and cookingPanel.Visible then
		return -- already open for this campfire
	end

	buildCookingPanel()
	activeCampfireModel = campfireModel
	cookingState = nil
	local ref = cookingPanel:FindFirstChild("ActiveCampfire")
	if ref then ref.Value = campfireModel end
	cookingPanel.Visible = true
	closeFoodPicker()

	-- Request state from server
	openCampfireRemote:FireServer(campfireModel)
end

function closeCookingPanel()
	closeFoodPicker()
	if cookingPanel then
		cookingPanel.Visible = false
		local ref = cookingPanel:FindFirstChild("ActiveCampfire")
		if ref then ref.Value = nil end
	end
	activeCampfireModel = nil
	cookingState = nil
end

-- Listen for server state updates
campfireStateRemote.OnClientEvent:Connect(function(campfireModel, data)
	if campfireModel ~= activeCampfireModel then return end

	if data == nil then
		-- Campfire destroyed
		closeCookingPanel()
		return
	end

	cookingState = data
	refreshCookingUI()
end)

-- Close panel if player walks too far from campfire
local COOK_RANGE_CHECK_INTERVAL = 0.5
local cookRangeCheckTimer = 0

RunService.Heartbeat:Connect(function(dt)
	if not activeCampfireModel or not cookingPanel or not cookingPanel.Visible then return end

	cookRangeCheckTimer = cookRangeCheckTimer + dt
	if cookRangeCheckTimer < COOK_RANGE_CHECK_INTERVAL then return end
	cookRangeCheckTimer = 0

	local campfirePos = nil
	local primary = activeCampfireModel.PrimaryPart or activeCampfireModel:FindFirstChildWhichIsA("BasePart")
	if primary then campfirePos = primary.Position end

	if not campfirePos then
		closeCookingPanel()
		return
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local interactRange = (Config.Campfire and Config.Campfire.InteractRange) or 10
	if (root.Position - campfirePos).Magnitude > interactRange + 2 then
		closeCookingPanel()
	end
end)

-- Also interpolate progress bar locally for smoothness
RunService.RenderStepped:Connect(function(dt)
	if not cookingState or not cookingPanel or not cookingPanel.Visible then return end
	if not cookingState.input or cookingState.cookDuration <= 0 then return end

	-- Locally advance progress for smooth bar
	cookingState.cookProgress = math.min(cookingState.cookProgress + dt, cookingState.cookDuration)
	refreshCookingUI()
end)

-- Listen for ProximityPrompt triggers on campfires
Workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("ProximityPrompt") then
		local parent = inst.Parent
		local model = parent and parent.Parent
		if not model then
			model = parent and parent:FindFirstAncestorWhichIsA("Model")
		end
		if model and model:IsA("Model") and model:GetAttribute("_PlacedItem") == "campfire" then
			inst.Triggered:Connect(function(triggerPlayer)
				if triggerPlayer == player then
					openCookingPanel(model)
				end
			end)
		end
	end
end)

-- Also hook existing campfire ProximityPrompts
for _, desc in ipairs(Workspace:GetDescendants()) do
	if desc:IsA("ProximityPrompt") then
		local parent = desc.Parent
		local model = parent and parent.Parent
		if not model then
			model = parent and parent:FindFirstAncestorWhichIsA("Model")
		end
		if model and model:IsA("Model") and model:GetAttribute("_PlacedItem") == "campfire" then
			desc.Triggered:Connect(function(triggerPlayer)
				if triggerPlayer == player then
					openCookingPanel(model)
				end
			end)
		end
	end
end

-- Close cooking panel on Escape
-- ---------------------------------------------------------------------------
-- Loot Bag UI — popup panel showing bag contents with click/drag-to-take
-- ---------------------------------------------------------------------------

local lootBagPanel: Frame? = nil
local activeLootBag: Model? = nil
local lootBagContents: { { itemId: string, qty: number, displayName: string } }? = nil

local LOOT_SLOT_SIZE = 56
local LOOT_COLUMNS = 4
local LOOT_PADDING = 6

local function refreshLootBagUI()
	if not lootBagPanel or not lootBagContents then return end

	local scroll = lootBagPanel:FindFirstChild("ItemScroll") :: ScrollingFrame
	if not scroll then return end

	-- Clear existing slots
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end

	for idx, entry in ipairs(lootBagContents) do
		local btn = Instance.new("TextButton")
		btn.Name = "LootSlot_" .. idx
		btn.Size = UDim2.fromOffset(LOOT_SLOT_SIZE, LOOT_SLOT_SIZE)
		btn.LayoutOrder = idx
		btn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
		btn.BackgroundTransparency = 0.1
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.AutoButtonColor = true
		btn.Parent = scroll

		btn:SetAttribute("_LootItemId", entry.itemId)
		btn:SetAttribute("_LootQty", entry.qty)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(95, 105, 125)
		stroke.Transparency = 0.4
		stroke.Thickness = 1
		stroke.Parent = btn

		local icon = getItemIcon(entry.itemId)
		if icon ~= "" then
			local img = Instance.new("ImageLabel")
			img.Name = "Icon"
			img.Size = UDim2.fromOffset(40, 40)
			img.Position = UDim2.fromOffset(8, 6)
			img.BackgroundTransparency = 1
			img.ScaleType = Enum.ScaleType.Fit
			img.Image = icon
			img.Parent = btn
		else
			btn.Text = getItemAbbrev(entry.itemId)
			btn.TextColor3 = Color3.fromRGB(200, 200, 210)
			btn.TextSize = 11
			btn.Font = Enum.Font.GothamMedium
		end

		if entry.qty > 1 then
			local qtyLabel = Instance.new("TextLabel")
			qtyLabel.Name = "Qty"
			qtyLabel.Size = UDim2.fromOffset(24, 14)
			qtyLabel.Position = UDim2.new(1, -26, 1, -16)
			qtyLabel.BackgroundTransparency = 1
			qtyLabel.Text = tostring(entry.qty)
			qtyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			qtyLabel.TextSize = 11
			qtyLabel.Font = Enum.Font.GothamBold
			qtyLabel.TextXAlignment = Enum.TextXAlignment.Right
			qtyLabel.TextStrokeTransparency = 0.5
			qtyLabel.Parent = btn
		end

		-- Item name tooltip below icon
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, 0, 0, 10)
		nameLabel.Position = UDim2.new(0, 0, 1, -12)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = entry.displayName
		nameLabel.TextColor3 = Color3.fromRGB(160, 165, 180)
		nameLabel.TextSize = 8
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = btn

		-- Click to take entire stack
		btn.MouseButton1Click:Connect(function()
			if not activeLootBag or not activeLootBag.Parent then return end
			takeLootBagItemRemote:FireServer(activeLootBag, entry.itemId, entry.qty)
		end)
	end

	-- Resize scroll canvas
	local rows = math.ceil(#lootBagContents / LOOT_COLUMNS)
	scroll.CanvasSize = UDim2.fromOffset(0, rows * (LOOT_SLOT_SIZE + LOOT_PADDING) + LOOT_PADDING)
end

local function buildLootBagPanel()
	if lootBagPanel then return end

	local panel = Instance.new("Frame")
	panel.Name = "LootBagPanel"
	panel.Size = UDim2.fromOffset(260, 300)
	panel.Position = UDim2.new(0.5, -130, 0.5, -150)
	panel.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = hud

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(210, 180, 120)
	panelStroke.Transparency = 0.5
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Position = UDim2.fromOffset(0, 6)
	title.BackgroundTransparency = 1
	title.Text = "LOOT BAG"
	title.TextColor3 = Color3.fromRGB(210, 180, 120)
	title.TextSize = 13
	title.Font = Enum.Font.GothamBold
	title.Parent = panel

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.Size = UDim2.fromOffset(20, 20)
	closeBtn.Position = UDim2.new(1, -24, 0, 6)
	closeBtn.BackgroundColor3 = Color3.fromRGB(120, 35, 35)
	closeBtn.BackgroundTransparency = 0.4
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextSize = 11
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = panel

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 4)
	closeBtnCorner.Parent = closeBtn

	-- Scrolling frame for items
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ItemScroll"
	scroll.Size = UDim2.new(1, -16, 1, -70)
	scroll.Position = UDim2.fromOffset(8, 32)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 140)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = panel

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(LOOT_SLOT_SIZE, LOOT_SLOT_SIZE)
	grid.CellPadding = UDim2.fromOffset(LOOT_PADDING, LOOT_PADDING)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	-- Take All button
	local takeAllBtn = Instance.new("TextButton")
	takeAllBtn.Name = "TakeAll"
	takeAllBtn.Size = UDim2.new(1, -16, 0, 26)
	takeAllBtn.Position = UDim2.new(0, 8, 1, -32)
	takeAllBtn.BackgroundColor3 = Color3.fromRGB(40, 65, 40)
	takeAllBtn.BackgroundTransparency = 0.2
	takeAllBtn.Text = "TAKE ALL"
	takeAllBtn.TextColor3 = Color3.fromRGB(180, 220, 180)
	takeAllBtn.TextSize = 11
	takeAllBtn.Font = Enum.Font.GothamBold
	takeAllBtn.BorderSizePixel = 0
	takeAllBtn.Parent = panel

	local takeAllCorner = Instance.new("UICorner")
	takeAllCorner.CornerRadius = UDim.new(0, 6)
	takeAllCorner.Parent = takeAllBtn

	-- ObjectValue for bag reference (used by InventoryController drag system)
	local bagRef = Instance.new("ObjectValue")
	bagRef.Name = "ActiveBag"
	bagRef.Parent = panel

	-- Handlers
	closeBtn.MouseButton1Click:Connect(function()
		closeLootBagPanel()
	end)

	takeAllBtn.MouseButton1Click:Connect(function()
		if not activeLootBag or not activeLootBag.Parent or not lootBagContents then return end
		for _, entry in ipairs(lootBagContents) do
			takeLootBagItemRemote:FireServer(activeLootBag, entry.itemId, entry.qty)
		end
	end)

	lootBagPanel = panel
	restorePanelPosition(panel, "LootBag")
	makeDraggable(panel, "LootBag")
end

local function openLootBagPanel(bagModel: Model)
	if activeLootBag == bagModel and lootBagPanel and lootBagPanel.Visible then return end

	buildLootBagPanel()
	activeLootBag = bagModel
	lootBagContents = nil
	local ref = lootBagPanel:FindFirstChild("ActiveBag")
	if ref then (ref :: ObjectValue).Value = bagModel end
	lootBagPanel.Visible = true
end

function closeLootBagPanel()
	if lootBagPanel then
		lootBagPanel.Visible = false
		local ref = lootBagPanel:FindFirstChild("ActiveBag")
		if ref then (ref :: ObjectValue).Value = nil end
	end
	activeLootBag = nil
	lootBagContents = nil
end

-- Listen for server state updates
lootBagStateRemote.OnClientEvent:Connect(function(bagModel, data)
	if bagModel ~= activeLootBag then
		-- Server opened a bag for us (from ProximityPrompt trigger)
		if data ~= nil then
			openLootBagPanel(bagModel)
			lootBagContents = data
			refreshLootBagUI()
		end
		return
	end

	if data == nil then
		closeLootBagPanel()
		return
	end

	lootBagContents = data
	refreshLootBagUI()
end)

-- Close panel if player walks too far from bag
local LOOT_RANGE_CHECK_INTERVAL = 0.5
local lootRangeCheckTimer = 0

RunService.Heartbeat:Connect(function(dt)
	if not activeLootBag or not lootBagPanel or not lootBagPanel.Visible then return end

	lootRangeCheckTimer = lootRangeCheckTimer + dt
	if lootRangeCheckTimer < LOOT_RANGE_CHECK_INTERVAL then return end
	lootRangeCheckTimer = 0

	local bagPart = activeLootBag.PrimaryPart or activeLootBag:FindFirstChildWhichIsA("BasePart")
	if not bagPart or not activeLootBag.Parent then
		closeLootBagPanel()
		return
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local closeRange = (Config.LootBag and Config.LootBag.UICloseRange) or 12
	if (root.Position - bagPart.Position).Magnitude > closeRange then
		closeLootBagPanel()
	end
end)

-- Hook ProximityPrompts on loot bags
local function hookLootBagPrompt(inst: ProximityPrompt)
	local parent = inst.Parent
	local model = parent and parent.Parent
	if not model then
		model = parent and parent:FindFirstAncestorWhichIsA("Model")
	end
	if model and model:IsA("Model") and model:GetAttribute("_isLootBag") then
		inst.Triggered:Connect(function(triggerPlayer)
			if triggerPlayer == player then
				openLootBagPanel(model)
			end
		end)
	end
end

Workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("ProximityPrompt") then
		hookLootBagPrompt(inst)
	end
end)

for _, desc in ipairs(Workspace:GetDescendants()) do
	if desc:IsA("ProximityPrompt") then
		hookLootBagPrompt(desc)
	end
end

-- ---------------------------------------------------------------------------
-- Trading UI — request popup + trade window
-- ---------------------------------------------------------------------------

local tradePanel: Frame? = nil
local tradeRequestPopup: Frame? = nil
local tradePartnerName: string = ""
local tradeState: {
	partnerName: string,
	partnerUserId: number,
	myOffer: { { itemId: string, qty: number } },
	theirOffer: { { itemId: string, qty: number } },
	iConfirmed: boolean,
	theyConfirmed: boolean,
}? = nil

local TRADE_SLOT_SIZE = 56
local TRADE_COLUMNS = 3
local TRADE_PADDING = 6

local function makeTradeSlot(parent: ScrollingFrame, entry: { itemId: string, qty: number }, idx: number, clickable: boolean)
	local btn = Instance.new("TextButton")
	btn.Name = "TradeSlot_" .. idx
	btn.Size = UDim2.fromOffset(TRADE_SLOT_SIZE, TRADE_SLOT_SIZE)
	btn.LayoutOrder = idx
	btn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
	btn.BackgroundTransparency = 0.1
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = clickable
	btn.Parent = parent

	btn:SetAttribute("_TradeItemId", entry.itemId)
	btn:SetAttribute("_TradeQty", entry.qty)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(95, 105, 125)
	stroke.Transparency = 0.4
	stroke.Thickness = 1
	stroke.Parent = btn

	local icon = getItemIcon(entry.itemId)
	if icon ~= "" then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.Size = UDim2.fromOffset(40, 40)
		img.Position = UDim2.fromOffset(8, 6)
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Fit
		img.Image = icon
		img.Parent = btn
	else
		btn.Text = getItemAbbrev(entry.itemId)
		btn.TextColor3 = Color3.fromRGB(200, 200, 210)
		btn.TextSize = 11
		btn.Font = Enum.Font.GothamMedium
	end

	if entry.qty > 1 then
		local qtyLabel = Instance.new("TextLabel")
		qtyLabel.Name = "Qty"
		qtyLabel.Size = UDim2.fromOffset(24, 14)
		qtyLabel.Position = UDim2.new(1, -26, 1, -16)
		qtyLabel.BackgroundTransparency = 1
		qtyLabel.Text = tostring(entry.qty)
		qtyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		qtyLabel.TextSize = 11
		qtyLabel.Font = Enum.Font.GothamBold
		qtyLabel.TextXAlignment = Enum.TextXAlignment.Right
		qtyLabel.TextStrokeTransparency = 0.5
		qtyLabel.Parent = btn
	end

	-- Item name
	local def = ItemRegistry.get(entry.itemId)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 10)
	nameLabel.Position = UDim2.new(0, 0, 1, -12)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = def and def.displayName or entry.itemId
	nameLabel.TextColor3 = Color3.fromRGB(160, 165, 180)
	nameLabel.TextSize = 8
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = btn

	return btn
end

local function refreshTradeUI()
	if not tradePanel or not tradeState then return end

	-- Refresh MY OFFER column
	local myScroll = tradePanel:FindFirstChild("MyOfferScroll") :: ScrollingFrame
	if myScroll then
		for _, child in ipairs(myScroll:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		for idx, entry in ipairs(tradeState.myOffer) do
			local btn = makeTradeSlot(myScroll, entry, idx, true)
			btn.MouseButton1Click:Connect(function()
				tradeUpdateOfferRemote:FireServer(entry.itemId, entry.qty, "remove")
			end)
		end
		local rows = math.ceil(#tradeState.myOffer / TRADE_COLUMNS)
		myScroll.CanvasSize = UDim2.fromOffset(0, rows * (TRADE_SLOT_SIZE + TRADE_PADDING) + TRADE_PADDING)
	end

	-- Refresh THEIR OFFER column
	local theirScroll = tradePanel:FindFirstChild("TheirOfferScroll") :: ScrollingFrame
	if theirScroll then
		for _, child in ipairs(theirScroll:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		for idx, entry in ipairs(tradeState.theirOffer) do
			makeTradeSlot(theirScroll, entry, idx, false)
		end
		local rows = math.ceil(#tradeState.theirOffer / TRADE_COLUMNS)
		theirScroll.CanvasSize = UDim2.fromOffset(0, rows * (TRADE_SLOT_SIZE + TRADE_PADDING) + TRADE_PADDING)
	end

	-- Update confirm button and status
	local confirmBtn = tradePanel:FindFirstChild("ConfirmBtn") :: TextButton
	local statusLabel = tradePanel:FindFirstChild("StatusLabel") :: TextLabel

	if confirmBtn then
		if tradeState.iConfirmed then
			confirmBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 30)
			confirmBtn.Text = "CONFIRMED"
		else
			confirmBtn.BackgroundColor3 = Color3.fromRGB(40, 65, 40)
			confirmBtn.Text = "CONFIRM"
		end
	end

	if statusLabel then
		if tradeState.theyConfirmed then
			statusLabel.Text = tradeState.partnerName .. " confirmed"
			statusLabel.TextColor3 = Color3.fromRGB(120, 200, 120)
		elseif tradeState.iConfirmed then
			statusLabel.Text = "Waiting for " .. tradeState.partnerName .. "..."
			statusLabel.TextColor3 = Color3.fromRGB(180, 180, 140)
		else
			statusLabel.Text = ""
		end
	end

	-- Update partner name in title
	local theirTitle = tradePanel:FindFirstChild("TheirTitle") :: TextLabel
	if theirTitle then
		theirTitle.Text = tradeState.partnerName:upper() .. "'S OFFER"
	end
end

local function buildTradePanel()
	if tradePanel then return end

	local COLUMN_WIDTH = 210
	local PANEL_W = COLUMN_WIDTH * 2 + 24  -- 2 columns + padding
	local PANEL_H = 360

	local panel = Instance.new("Frame")
	panel.Name = "TradePanel"
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.Position = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2)
	panel.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = hud

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(120, 180, 210)
	panelStroke.Transparency = 0.5
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Position = UDim2.fromOffset(0, 6)
	title.BackgroundTransparency = 1
	title.Text = "TRADE"
	title.TextColor3 = Color3.fromRGB(120, 180, 210)
	title.TextSize = 13
	title.Font = Enum.Font.GothamBold
	title.Parent = panel

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.Size = UDim2.fromOffset(20, 20)
	closeBtn.Position = UDim2.new(1, -24, 0, 6)
	closeBtn.BackgroundColor3 = Color3.fromRGB(120, 35, 35)
	closeBtn.BackgroundTransparency = 0.4
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextSize = 11
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = panel
	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 4)
	closeBtnCorner.Parent = closeBtn

	-- ── Left column: YOUR OFFER ──
	local myTitle = Instance.new("TextLabel")
	myTitle.Name = "MyTitle"
	myTitle.Size = UDim2.fromOffset(COLUMN_WIDTH, 18)
	myTitle.Position = UDim2.fromOffset(8, 32)
	myTitle.BackgroundTransparency = 1
	myTitle.Text = "YOUR OFFER"
	myTitle.TextColor3 = Color3.fromRGB(180, 200, 140)
	myTitle.TextSize = 11
	myTitle.Font = Enum.Font.GothamBold
	myTitle.TextXAlignment = Enum.TextXAlignment.Center
	myTitle.Parent = panel

	local myScroll = Instance.new("ScrollingFrame")
	myScroll.Name = "MyOfferScroll"
	myScroll.Size = UDim2.fromOffset(COLUMN_WIDTH, PANEL_H - 110)
	myScroll.Position = UDim2.fromOffset(8, 52)
	myScroll.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
	myScroll.BackgroundTransparency = 0.5
	myScroll.BorderSizePixel = 0
	myScroll.ScrollBarThickness = 4
	myScroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 140)
	myScroll.CanvasSize = UDim2.fromOffset(0, 0)
	myScroll.Parent = panel
	local myScrollCorner = Instance.new("UICorner")
	myScrollCorner.CornerRadius = UDim.new(0, 6)
	myScrollCorner.Parent = myScroll

	local myGrid = Instance.new("UIGridLayout")
	myGrid.CellSize = UDim2.fromOffset(TRADE_SLOT_SIZE, TRADE_SLOT_SIZE)
	myGrid.CellPadding = UDim2.fromOffset(TRADE_PADDING, TRADE_PADDING)
	myGrid.SortOrder = Enum.SortOrder.LayoutOrder
	myGrid.Parent = myScroll

	-- ── Right column: THEIR OFFER ──
	local theirTitle = Instance.new("TextLabel")
	theirTitle.Name = "TheirTitle"
	theirTitle.Size = UDim2.fromOffset(COLUMN_WIDTH, 18)
	theirTitle.Position = UDim2.fromOffset(8 + COLUMN_WIDTH + 8, 32)
	theirTitle.BackgroundTransparency = 1
	theirTitle.Text = "THEIR OFFER"
	theirTitle.TextColor3 = Color3.fromRGB(210, 160, 120)
	theirTitle.TextSize = 11
	theirTitle.Font = Enum.Font.GothamBold
	theirTitle.TextXAlignment = Enum.TextXAlignment.Center
	theirTitle.Parent = panel

	local theirScroll = Instance.new("ScrollingFrame")
	theirScroll.Name = "TheirOfferScroll"
	theirScroll.Size = UDim2.fromOffset(COLUMN_WIDTH, PANEL_H - 110)
	theirScroll.Position = UDim2.fromOffset(8 + COLUMN_WIDTH + 8, 52)
	theirScroll.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
	theirScroll.BackgroundTransparency = 0.5
	theirScroll.BorderSizePixel = 0
	theirScroll.ScrollBarThickness = 4
	theirScroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 140)
	theirScroll.CanvasSize = UDim2.fromOffset(0, 0)
	theirScroll.Parent = panel
	local theirScrollCorner = Instance.new("UICorner")
	theirScrollCorner.CornerRadius = UDim.new(0, 6)
	theirScrollCorner.Parent = theirScroll

	local theirGrid = Instance.new("UIGridLayout")
	theirGrid.CellSize = UDim2.fromOffset(TRADE_SLOT_SIZE, TRADE_SLOT_SIZE)
	theirGrid.CellPadding = UDim2.fromOffset(TRADE_PADDING, TRADE_PADDING)
	theirGrid.SortOrder = Enum.SortOrder.LayoutOrder
	theirGrid.Parent = theirScroll

	-- ── Bottom bar: Confirm + Cancel + Status ──
	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Name = "ConfirmBtn"
	confirmBtn.Size = UDim2.fromOffset(120, 28)
	confirmBtn.Position = UDim2.new(0, 8, 1, -38)
	confirmBtn.BackgroundColor3 = Color3.fromRGB(40, 65, 40)
	confirmBtn.BackgroundTransparency = 0.2
	confirmBtn.Text = "CONFIRM"
	confirmBtn.TextColor3 = Color3.fromRGB(180, 220, 180)
	confirmBtn.TextSize = 11
	confirmBtn.Font = Enum.Font.GothamBold
	confirmBtn.BorderSizePixel = 0
	confirmBtn.Parent = panel
	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 6)
	confirmCorner.Parent = confirmBtn

	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Name = "CancelBtn"
	cancelBtn.Size = UDim2.fromOffset(80, 28)
	cancelBtn.Position = UDim2.new(0, 136, 1, -38)
	cancelBtn.BackgroundColor3 = Color3.fromRGB(120, 35, 35)
	cancelBtn.BackgroundTransparency = 0.3
	cancelBtn.Text = "CANCEL"
	cancelBtn.TextColor3 = Color3.fromRGB(220, 160, 160)
	cancelBtn.TextSize = 11
	cancelBtn.Font = Enum.Font.GothamBold
	cancelBtn.BorderSizePixel = 0
	cancelBtn.Parent = panel
	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 6)
	cancelCorner.Parent = cancelBtn

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(0, PANEL_W - 230, 0, 28)
	statusLabel.Position = UDim2.new(0, 224, 1, -38)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = ""
	statusLabel.TextColor3 = Color3.fromRGB(180, 180, 140)
	statusLabel.TextSize = 10
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right
	statusLabel.Parent = panel

	-- ObjectValue for partner reference (used by InventoryController drag system)
	local partnerRef = Instance.new("StringValue")
	partnerRef.Name = "TradePartner"
	partnerRef.Parent = panel

	-- Handlers
	closeBtn.MouseButton1Click:Connect(function()
		tradeCancelRemote:FireServer()
	end)
	cancelBtn.MouseButton1Click:Connect(function()
		tradeCancelRemote:FireServer()
	end)
	confirmBtn.MouseButton1Click:Connect(function()
		tradeConfirmRemote:FireServer()
	end)

	tradePanel = panel
	restorePanelPosition(panel, "Trade")
	makeDraggable(panel, "Trade")
end

local function openTradePanel()
	buildTradePanel()
	tradePanel.Visible = true
	refreshTradeUI()
end

function closeTradePanel()
	if tradePanel then
		tradePanel.Visible = false
	end
	tradeState = nil
end

-- ── Trade request popup (incoming) ──────────────────────────────────────

local function showTradeRequestPopup(fromName: string, fromUserId: number, offeredItemId: string?, offeredQty: number?)
	-- Dismiss any existing popup
	if tradeRequestPopup and tradeRequestPopup.Parent then
		tradeRequestPopup:Destroy()
	end

	-- Build offer text for the message
	local offerText = ""
	if offeredItemId and offeredQty and offeredQty > 0 then
		local def = ItemRegistry.get(offeredItemId)
		local name = def and def.displayName or offeredItemId
		offerText = " (offering " .. offeredQty .. "x " .. name .. ")"
	end

	local popup = Instance.new("Frame")
	popup.Name = "TradeRequestPopup"
	popup.Size = UDim2.fromOffset(320, 80)
	popup.Position = UDim2.new(0.5, -160, 0.3, 0)
	popup.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	popup.BackgroundTransparency = 0.1
	popup.BorderSizePixel = 0
	popup.Parent = hud

	local popupCorner = Instance.new("UICorner")
	popupCorner.CornerRadius = UDim.new(0, 10)
	popupCorner.Parent = popup

	local popupStroke = Instance.new("UIStroke")
	popupStroke.Color = Color3.fromRGB(120, 180, 210)
	popupStroke.Transparency = 0.4
	popupStroke.Thickness = 1
	popupStroke.Parent = popup

	local msgLabel = Instance.new("TextLabel")
	msgLabel.Size = UDim2.new(1, -16, 0, 30)
	msgLabel.Position = UDim2.fromOffset(8, 8)
	msgLabel.BackgroundTransparency = 1
	msgLabel.Text = fromName .. " wants to trade" .. offerText
	msgLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
	msgLabel.TextSize = 12
	msgLabel.Font = Enum.Font.GothamMedium
	msgLabel.TextTruncate = Enum.TextTruncate.AtEnd
	msgLabel.Parent = popup

	local acceptBtn = Instance.new("TextButton")
	acceptBtn.Size = UDim2.fromOffset(110, 28)
	acceptBtn.Position = UDim2.fromOffset(40, 44)
	acceptBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
	acceptBtn.BackgroundTransparency = 0.2
	acceptBtn.Text = "ACCEPT"
	acceptBtn.TextColor3 = Color3.fromRGB(180, 220, 180)
	acceptBtn.TextSize = 11
	acceptBtn.Font = Enum.Font.GothamBold
	acceptBtn.BorderSizePixel = 0
	acceptBtn.Parent = popup
	local acceptCorner = Instance.new("UICorner")
	acceptCorner.CornerRadius = UDim.new(0, 6)
	acceptCorner.Parent = acceptBtn

	local declineBtn = Instance.new("TextButton")
	declineBtn.Size = UDim2.fromOffset(110, 28)
	declineBtn.Position = UDim2.fromOffset(170, 44)
	declineBtn.BackgroundColor3 = Color3.fromRGB(120, 35, 35)
	declineBtn.BackgroundTransparency = 0.3
	declineBtn.Text = "DECLINE"
	declineBtn.TextColor3 = Color3.fromRGB(220, 160, 160)
	declineBtn.TextSize = 11
	declineBtn.Font = Enum.Font.GothamBold
	declineBtn.BorderSizePixel = 0
	declineBtn.Parent = popup
	local declineCorner = Instance.new("UICorner")
	declineCorner.CornerRadius = UDim.new(0, 6)
	declineCorner.Parent = declineBtn

	tradeRequestPopup = popup

	acceptBtn.MouseButton1Click:Connect(function()
		tradeResponseRemote:FireServer(true)
		if popup.Parent then popup:Destroy() end
	end)

	declineBtn.MouseButton1Click:Connect(function()
		tradeResponseRemote:FireServer(false)
		if popup.Parent then popup:Destroy() end
	end)

	-- Auto-dismiss after timeout
	local timeout = (Config.Trading and Config.Trading.RequestTimeoutSeconds) or 15
	task.delay(timeout, function()
		if popup and popup.Parent then
			popup:Destroy()
		end
	end)
end

-- ── Trade remote listeners ──────────────────────────────────────────────

tradeRequestRemote.OnClientEvent:Connect(function(fromName, fromUserId, offeredItemId, offeredQty)
	if type(fromName) ~= "string" then return end
	showTradeRequestPopup(fromName, fromUserId, offeredItemId, offeredQty)
end)

tradeStateRemote.OnClientEvent:Connect(function(data)
	if data == nil then
		closeTradePanel()
		return
	end
	tradeState = data
	tradePartnerName = data.partnerName or ""
	openTradePanel()
end)

-- ── Trade range check ───────────────────────────────────────────────────

local tradeRangeCheckTimer = 0

RunService.Heartbeat:Connect(function(dt)
	if not tradePanel or not tradePanel.Visible or not tradeState then return end

	tradeRangeCheckTimer += dt
	if tradeRangeCheckTimer < 0.5 then return end
	tradeRangeCheckTimer = 0

	-- Find partner character and check distance
	local partnerName = tradeState.partnerName
	local partner = Players:FindFirstChild(partnerName)
	if not partner then
		closeTradePanel()
		return
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local partnerChar = (partner :: Player).Character
	local partnerRoot = partnerChar and partnerChar:FindFirstChild("HumanoidRootPart")
	if not root or not partnerRoot then return end

	local tradeRange = (Config.Trading and Config.Trading.InteractRange) or 15
	if (root.Position - partnerRoot.Position).Magnitude > tradeRange + 2 then
		closeTradePanel()
	end
end)

-- Close panels on Escape
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		if tradePanel and tradePanel.Visible then
			tradeCancelRemote:FireServer()
		elseif lootBagPanel and lootBagPanel.Visible then
			closeLootBagPanel()
		elseif cookingPanel and cookingPanel.Visible then
			closeCookingPanel()
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Campfire sit animation — server sets SittingAtCampfire attribute
-- ---------------------------------------------------------------------------

local sitTrack: AnimationTrack? = nil

local function startSitAnimation()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return end

	local anim = Instance.new("Animation")
	anim.AnimationId = AssetIds.Animations.Sitting
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		sitTrack = track
		sitTrack.Priority = Enum.AnimationPriority.Action
		sitTrack.Looped = true
		sitTrack:Play()
	end
end

local function stopSitAnimation()
	if sitTrack then
		sitTrack:Stop()
		sitTrack = nil
	end
end

player:GetAttributeChangedSignal("SittingAtCampfire"):Connect(function()
	if player:GetAttribute("SittingAtCampfire") == true then
		startSitAnimation()
	else
		stopSitAnimation()
	end
end)

-- ---------------------------------------------------------------------------
-- Bedroll sleeping animation — server sets LyingOnBedroll attribute
-- ---------------------------------------------------------------------------

local sleepTrack: AnimationTrack? = nil

local function startSleepAnimation()
	if AssetIds.Animations.Sleeping == "" then return end -- no animation uploaded yet
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return end

	local anim = Instance.new("Animation")
	anim.AnimationId = AssetIds.Animations.Sleeping
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		sleepTrack = track
		sleepTrack.Priority = Enum.AnimationPriority.Action4
		sleepTrack.Looped = true
		sleepTrack:Play()
	end
end

local function stopSleepAnimation()
	if sleepTrack then
		sleepTrack:Stop()
		sleepTrack = nil
	end
end

player:GetAttributeChangedSignal("LyingOnBedroll"):Connect(function()
	if player:GetAttribute("LyingOnBedroll") == true then
		startSleepAnimation()
	else
		stopSleepAnimation()
	end
end)
