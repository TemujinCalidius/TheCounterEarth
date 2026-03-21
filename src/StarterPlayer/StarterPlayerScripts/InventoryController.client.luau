-- InventoryController.client.luau
-- Open/close the character-sheet / inventory panel via:
--   The persistent bag button on the right edge of the screen (mobile + PC)
--   The I key on PC
--
-- ITEMS tab  -- icon grid of InvSlot_N stacks (64x64 slots, icon + qty).
--               Click a slot to select it; detail strip shows name/desc/buttons.
--               USE / -> HOTBAR / SPLIT / DROP actions.
--               Drag a slot onto another to swap; drag outside the panel to drop.
-- RECIPES tab -- all recipes (hand-craft + cooking) with station badges and filters.
-- CHARACTER tab -- equipment slots and RPG stat block.

local Players               = game:GetService("Players")
local ReplicatedStorage     = game:GetService("ReplicatedStorage")
local SoundService          = game:GetService("SoundService")
local ContextActionService  = game:GetService("ContextActionService")
local UserInputService      = game:GetService("UserInputService")

local ItemRegistry   = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))
local AssetIds       = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AssetIds"))
local CraftingConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CraftingConfig"))
local CookingConfig      = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CookingConfig"))
local AchievementConfig  = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AchievementConfig"))
local TooltipModule      = require(ReplicatedStorage:WaitForChild("TooltipModule"))

-- Mobile / touch detection helpers
local function isClickOrTap(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMoveInput(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

-- Chewing sound for food consumption from inventory UI
local chewingSound = Instance.new("Sound")
chewingSound.Name = "InvChewingSound"
chewingSound.SoundId = AssetIds.Sounds.Chewing
chewingSound.Looped = true
chewingSound.Volume = 0.5
chewingSound.Parent = SoundService

-- Crafting sound for hand-craft channeling
local craftingSound = Instance.new("Sound")
craftingSound.Name = "InvCraftingSound"
craftingSound.SoundId = AssetIds.Sounds.Crafting
craftingSound.Looped = true
craftingSound.Volume = 0.6
craftingSound.Parent = SoundService

local remotes               = ReplicatedStorage:WaitForChild("Remotes")
local useItemRemote         = remotes:WaitForChild("UseItem")            :: RemoteEvent
local craftItemRemote       = remotes:WaitForChild("CraftItem")          :: RemoteEvent
local pinToHotbarRemote     = remotes:WaitForChild("PinToHotbar")        :: RemoteEvent
local splitStackRemote      = remotes:WaitForChild("SplitStack")         :: RemoteEvent
local swapSlotsRemote       = remotes:WaitForChild("SwapSlots")          :: RemoteEvent
local dropItemRemote        = remotes:WaitForChild("DropItem")           :: RemoteEvent
local pinToSpecificSlotRemote = remotes:WaitForChild("PinToSpecificSlot") :: RemoteEvent
local campfireAddRemote     = remotes:WaitForChild("CampfireAddItem")    :: RemoteEvent
local campfireTakeRemote    = remotes:WaitForChild("CampfireTakeItem")   :: RemoteEvent
local takeLootBagItemRemote = remotes:WaitForChild("TakeLootBagItem")    :: RemoteEvent
local tradeUpdateOfferRemote = remotes:WaitForChild("TradeUpdateOffer")  :: RemoteEvent
local tradeInitiateRemote    = remotes:WaitForChild("TradeInitiate")     :: RemoteEvent
local craftFailedRemote      = remotes:WaitForChild("CraftFailed")       :: RemoteEvent
local saveUIPosRemote        = remotes:WaitForChild("SaveUIPosition")    :: RemoteEvent
local equipBackpackRemote    = remotes:WaitForChild("EquipBackpack")     :: RemoteEvent
local unequipBackpackRemote  = remotes:WaitForChild("UnequipBackpack")   :: RemoteEvent
local equipQuiverRemote      = remotes:WaitForChild("EquipQuiver")       :: RemoteEvent
local unequipQuiverRemote    = remotes:WaitForChild("UnequipQuiver")     :: RemoteEvent
local achieveSyncRemote      = remotes:WaitForChild("AchievementSync", 10)
local achieveRequestRemote   = remotes:WaitForChild("AchievementRequest", 10)
local achieveUnlockedRemote  = remotes:WaitForChild("AchievementUnlocked", 10)

local startPlacementEvent = ReplicatedStorage
	:WaitForChild("ClientBindables"):WaitForChild("StartPlacement") :: BindableEvent

local player = Players.LocalPlayer

-- ── Style ─────────────────────────────────────────────────────────────────
local BG     = Color3.fromRGB(20, 22, 30)
local BG2    = Color3.fromRGB(32, 36, 50)
local BG3    = Color3.fromRGB(42, 48, 66)
local ACCENT = Color3.fromRGB(70, 130, 200)
local TEXT   = Color3.fromRGB(220, 225, 240)
local MUTED  = Color3.fromRGB(120, 132, 158)
local OK     = Color3.fromRGB(80, 195, 110)
local BAD    = Color3.fromRGB(215, 80, 75)
local WARN   = Color3.fromRGB(220, 160, 40)
local FONTB  = Enum.Font.GothamBold
local FONT   = Enum.Font.Gotham
local PW, PH = 540, 430

-- ── Helpers ───────────────────────────────────────────────────────────────

local function addCorner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function makeLabel(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3             = TEXT
	l.Font                   = FONT
	l.TextSize               = 13
	local a: any = l
	for k, v in pairs(props) do a[k] = v end
	l.Parent = parent
	return l
end

local function makeButton(parent: Instance, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.BorderSizePixel = 0
	b.TextColor3      = TEXT
	b.Font            = FONTB
	b.TextSize        = 13
	local a: any = b
	for k, v in pairs(props) do a[k] = v end
	b.Parent = parent
	return b
end

-- Destroys ImageButton and TextLabel children of a grid scroll frame.
local function clearSlots(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("ImageButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

-- ── Build ScreenGui ───────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name           = "InventoryGui"
gui.ResetOnSpawn   = false
gui.DisplayOrder   = 5
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = player.PlayerGui

-- Overlay for drag ghosts — IgnoreGuiInset so ghost tracks the cursor exactly.
local dragOverlay = Instance.new("ScreenGui")
dragOverlay.Name             = "DragOverlay"
dragOverlay.ResetOnSpawn     = false
dragOverlay.IgnoreGuiInset   = true
dragOverlay.DisplayOrder     = 100
dragOverlay.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
dragOverlay.Parent           = player.PlayerGui

-- ── Persistent bag button (right edge) ───────────────────────────────────
local bagBtn = Instance.new("ImageButton")
bagBtn.Name              = "BagButton"
bagBtn.Size              = UDim2.new(0, 52, 0, 52)
bagBtn.Position          = UDim2.new(1, -64, 0.5, -26)
bagBtn.BackgroundColor3  = BG2
bagBtn.BorderSizePixel   = 0
bagBtn.Image             = AssetIds.Images.BagIcon
bagBtn.ScaleType         = Enum.ScaleType.Fit
bagBtn.Parent            = gui
addCorner(bagBtn, 10)

local bagStroke = Instance.new("UIStroke")
bagStroke.Color     = Color3.fromRGB(55, 65, 95)
bagStroke.Thickness = 1
bagStroke.Parent    = bagBtn

local bagLabel = Instance.new("TextLabel")
bagLabel.Size               = UDim2.new(1, 0, 0, 12)
bagLabel.Position           = UDim2.new(0, 0, 1, -14)
bagLabel.BackgroundTransparency = 1
bagLabel.Text               = "BAG"
bagLabel.TextColor3         = TEXT
bagLabel.Font               = Enum.Font.GothamBold
bagLabel.TextSize           = 9
bagLabel.Parent             = bagBtn

-- Main panel (centered, or restored from saved position)
local panel = Instance.new("Frame")
panel.Name            = "Panel"
panel.Size            = UDim2.new(0, PW, 0, PH)
panel.Position        = UDim2.new(0.5, -PW / 2, 0.5, -PH / 2)
panel.BackgroundColor3 = BG
panel.BorderSizePixel = 0
panel.Visible         = false
panel.Parent          = gui
addCorner(panel, 8)

-- Panel visual depth: gradient + accent line + inner glow
do
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 42, 56)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(22, 24, 34)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 13, 20)),
	})
	grad.Parent = panel

	local accent = Instance.new("Frame")
	accent.Name = "AccentLine"
	accent.Size = UDim2.new(1, -24, 0, 2)
	accent.Position = UDim2.new(0, 12, 0, 3)
	accent.BackgroundColor3 = Color3.fromRGB(160, 130, 80)
	accent.BackgroundTransparency = 0.4
	accent.BorderSizePixel = 0
	accent.ZIndex = 2
	accent.Parent = panel
	addCorner(accent, 1)

	local glow = Instance.new("Frame")
	glow.Name = "InnerGlow"
	glow.Size = UDim2.new(1, 0, 0, 40)
	glow.Position = UDim2.new(0, 0, 0, 0)
	glow.BackgroundColor3 = Color3.fromRGB(160, 130, 80)
	glow.BorderSizePixel = 0
	glow.ZIndex = 0
	glow.Parent = panel
	addCorner(glow, 8)
	local glowGrad = Instance.new("UIGradient")
	glowGrad.Rotation = 90
	glowGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	glowGrad.Parent = glow

	local shadow = Instance.new("Frame")
	shadow.Name = "BottomShadow"
	shadow.Size = UDim2.new(1, 0, 0, 20)
	shadow.Position = UDim2.new(0, 0, 1, -20)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 0
	shadow.Parent = panel
	addCorner(shadow, 8)
	local shadowGrad = Instance.new("UIGradient")
	shadowGrad.Rotation = 90
	shadowGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.75),
	})
	shadowGrad.Parent = shadow
end

-- Clamp panel position so it stays within the visible screen area.
local function clampPanelPosition()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		or Vector2.new(1920, 1080)
	local maxX = math.max(0, vp.X - PW)
	local maxY = math.max(0, vp.Y - PH)
	local ap = panel.AbsolutePosition
	local cx = math.clamp(ap.X, 0, maxX)
	local cy = math.clamp(ap.Y, 0, maxY)
	panel.Position = UDim2.new(0, cx, 0, cy)
end

-- Restore saved position if available (clamped to current screen)
do
	local posStr = player:GetAttribute("_UIPos_Inventory")
	if type(posStr) == "string" then
		local x, y = string.match(posStr, "^(-?%d+),(-?%d+)$")
		if x and y then
			panel.Position = UDim2.new(0, tonumber(x) :: number, 0, tonumber(y) :: number)
			clampPanelPosition()
		end
	end
end

local panelStroke = Instance.new("UIStroke")
panelStroke.Color     = Color3.fromRGB(55, 65, 95)
panelStroke.Thickness = 1
panelStroke.Parent    = panel

-- Craft progress bar (shown during hand-craft channeling)
local craftBarBg = Instance.new("Frame")
craftBarBg.Name              = "CraftBarBg"
craftBarBg.Size              = UDim2.new(1, -24, 0, 14)
craftBarBg.Position          = UDim2.new(0, 12, 1, -22)
craftBarBg.BackgroundColor3  = Color3.fromRGB(28, 32, 42)
craftBarBg.BorderSizePixel   = 0
craftBarBg.Visible           = false
craftBarBg.ZIndex            = 10
craftBarBg.Parent            = panel
addCorner(craftBarBg, 6)

local craftBarFill = Instance.new("Frame")
craftBarFill.Name              = "CraftBarFill"
craftBarFill.Size              = UDim2.fromScale(0, 1)
craftBarFill.BackgroundColor3  = ACCENT
craftBarFill.BorderSizePixel   = 0
craftBarFill.ZIndex            = 11
craftBarFill.Parent            = craftBarBg
addCorner(craftBarFill, 6)

local craftBarLabel = Instance.new("TextLabel")
craftBarLabel.Name              = "CraftBarLabel"
craftBarLabel.Size              = UDim2.fromScale(1, 1)
craftBarLabel.BackgroundTransparency = 1
craftBarLabel.Text              = "Crafting..."
craftBarLabel.TextColor3        = TEXT
craftBarLabel.TextSize          = 9
craftBarLabel.Font              = Enum.Font.GothamBold
craftBarLabel.ZIndex            = 12
craftBarLabel.Parent            = craftBarBg

-- Header (also acts as drag handle for moving the panel)
local header = Instance.new("Frame")
header.Name             = "Header"
header.Size             = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = BG2
header.BorderSizePixel  = 0
header.Active           = true
header.Parent           = panel
addCorner(header, 8)
local hMask = Instance.new("Frame")
hMask.Size             = UDim2.new(1, 0, 0, 8)
hMask.Position         = UDim2.new(0, 0, 1, -8)
hMask.BackgroundColor3 = BG2
hMask.BorderSizePixel  = 0
hMask.Parent           = header

-- Panel dragging via header
local panelDragging  = false
local panelDragStart = Vector2.new(0, 0)
local panelPosStart  = Vector2.new(0, 0)

header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		panelDragging  = true
		panelDragStart = Vector2.new(input.Position.X, input.Position.Y)
		-- Snapshot the actual screen position (AbsolutePosition) so Scale doesn't cause a jump.
		local ap = panel.AbsolutePosition
		panelPosStart  = Vector2.new(ap.X, ap.Y)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not panelDragging then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local delta = Vector2.new(input.Position.X, input.Position.Y) - panelDragStart
	panel.Position = UDim2.new(0, panelPosStart.X + delta.X, 0, panelPosStart.Y + delta.Y)
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		if panelDragging then
			panelDragging = false
			clampPanelPosition()
			saveUIPosRemote:FireServer("Inventory", panel.AbsolutePosition.X, panel.AbsolutePosition.Y)
		end
	end
end)

makeLabel(header, {
	Size             = UDim2.new(1, -50, 1, 0),
	Position         = UDim2.new(0, 14, 0, 0),
	Text             = "CHARACTER SHEET",
	Font             = FONTB,
	TextSize         = 14,
	TextXAlignment   = Enum.TextXAlignment.Left,
	TextColor3       = TEXT,
})

local closeBtn = makeButton(header, {
	Size             = UDim2.new(0, 30, 0, 30),
	Position         = UDim2.new(1, -36, 0.5, -15),
	BackgroundColor3 = Color3.fromRGB(55, 28, 28),
	Text             = "X",
	TextColor3       = BAD,
	TextSize         = 14,
})
addCorner(closeBtn, 5)

-- Tab bar
local tabBar = Instance.new("Frame")
tabBar.Size               = UDim2.new(1, -20, 0, 28)
tabBar.Position           = UDim2.new(0, 10, 0, 44)
tabBar.BackgroundTransparency = 1
tabBar.Parent             = panel

local function makeTabBtn(label: string, xOff: number): TextButton
	local b = makeButton(tabBar, {
		Size             = UDim2.new(0, 90, 1, 0),
		Position         = UDim2.new(0, xOff, 0, 0),
		BackgroundColor3 = BG2,
		Text             = label,
		TextColor3       = MUTED,
		TextSize         = 11,
	})
	addCorner(b, 6)
	return b
end

local itemsTabBtn = makeTabBtn("ITEMS",     0)
local craftTabBtn = makeTabBtn("RECIPES",  95)
local charTabBtn  = makeTabBtn("CHAR",    190)
local achTabBtn   = makeTabBtn("ACHIEVE", 285)

-- Content area (520 x 350 px usable)
local content = Instance.new("Frame")
content.Size               = UDim2.new(1, -20, 1, -80)
content.Position           = UDim2.new(0, 10, 0, 74)
content.BackgroundTransparency = 1
content.Parent             = panel

-- ── ITEMS PANE ────────────────────────────────────────────────────────────

local itemsPane = Instance.new("Frame")
itemsPane.Size               = UDim2.new(1, 0, 1, 0)
itemsPane.BackgroundTransparency = 1
itemsPane.Parent             = content

-- Icon grid
local gridScroll = Instance.new("ScrollingFrame")
gridScroll.Name                 = "GridScroll"
gridScroll.Size                 = UDim2.new(1, 0, 0, 220)
gridScroll.BackgroundColor3     = BG2
gridScroll.BorderSizePixel      = 0
gridScroll.ScrollBarThickness   = 4
gridScroll.ScrollBarImageColor3 = ACCENT
gridScroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
gridScroll.AutomaticCanvasSize  = Enum.AutomaticSize.Y
gridScroll.Parent               = itemsPane
addCorner(gridScroll, 6)

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize    = UDim2.new(0, 64, 0, 64)
gridLayout.CellPadding = UDim2.new(0, 4, 0, 4)
gridLayout.SortOrder   = Enum.SortOrder.LayoutOrder
gridLayout.Parent      = gridScroll

local gridPad = Instance.new("UIPadding")
gridPad.PaddingTop    = UDim.new(0, 6)
gridPad.PaddingLeft   = UDim.new(0, 6)
gridPad.PaddingRight  = UDim.new(0, 6)
gridPad.PaddingBottom = UDim.new(0, 6)
gridPad.Parent        = gridScroll

-- Detail strip (74px tall)
local detailStrip = Instance.new("Frame")
detailStrip.Size             = UDim2.new(1, 0, 0, 74)
detailStrip.Position         = UDim2.new(0, 0, 0, 224)
detailStrip.BackgroundColor3 = BG2
detailStrip.BorderSizePixel  = 0
detailStrip.Parent           = itemsPane
addCorner(detailStrip, 6)

local detailIcon = Instance.new("ImageLabel")
detailIcon.Size             = UDim2.new(0, 54, 0, 54)
detailIcon.Position         = UDim2.new(0, 8, 0.5, -27)
detailIcon.BackgroundColor3 = BG3
detailIcon.BorderSizePixel  = 0
detailIcon.Image            = ""
detailIcon.ScaleType        = Enum.ScaleType.Fit
detailIcon.Parent           = detailStrip
addCorner(detailIcon, 6)

local detailName = makeLabel(detailStrip, {
	Size           = UDim2.new(1, -290, 0, 22),
	Position       = UDim2.new(0, 70, 0, 8),
	Text           = "Select an item",
	TextColor3     = MUTED,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font           = FONTB,
	TextSize       = 13,
})

local detailDesc = makeLabel(detailStrip, {
	Size        = UDim2.new(1, -290, 0, 18),
	Position    = UDim2.new(0, 70, 0, 32),
	Text        = "",
	TextColor3  = MUTED,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize    = 10,
	TextWrapped = true,
})

local detailSlotLabel = makeLabel(detailStrip, {
	Size        = UDim2.new(1, -290, 0, 12),
	Position    = UDim2.new(0, 70, 0, 54),
	Text        = "",
	TextColor3  = Color3.fromRGB(80, 90, 115),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize    = 9,
})

-- Action buttons (right side of detail strip): USE | ->HOTBAR | SPLIT | DROP
local detailUseBtn = makeButton(detailStrip, {
	Size             = UDim2.new(0, 46, 0, 26),
	Position         = UDim2.new(1, -326, 0.5, -13),
	BackgroundColor3 = Color3.fromRGB(45, 80, 45),
	Text             = "USE",
	TextColor3       = OK,
	TextSize         = 12,
	Visible          = false,
})
addCorner(detailUseBtn, 5)

local detailEquipBtn = makeButton(detailStrip, {
	Size             = UDim2.new(0, 52, 0, 26),
	Position         = UDim2.new(1, -268, 0.5, -13),
	BackgroundColor3 = Color3.fromRGB(30, 60, 80),
	Text             = "EQUIP",
	TextColor3       = ACCENT,
	TextSize         = 11,
	Visible          = false,
})
addCorner(detailEquipBtn, 5)

local detailHotbarBtn = makeButton(detailStrip, {
	Size             = UDim2.new(0, 84, 0, 26),
	Position         = UDim2.new(1, -210, 0.5, -13),
	BackgroundColor3 = ACCENT,
	Text             = "-> HOTBAR",
	TextColor3       = TEXT,
	TextSize         = 11,
	Visible          = false,
})
addCorner(detailHotbarBtn, 5)

local detailSplitBtn = makeButton(detailStrip, {
	Size             = UDim2.new(0, 52, 0, 26),
	Position         = UDim2.new(1, -126, 0.5, -13),
	BackgroundColor3 = Color3.fromRGB(60, 55, 30),
	Text             = "SPLIT",
	TextColor3       = Color3.fromRGB(220, 200, 80),
	TextSize         = 11,
	Visible          = false,
})
addCorner(detailSplitBtn, 5)

local detailDropBtn = makeButton(detailStrip, {
	Size             = UDim2.new(0, 46, 0, 26),
	Position         = UDim2.new(1, -68, 0.5, -13),
	BackgroundColor3 = Color3.fromRGB(70, 35, 20),
	Text             = "DROP",
	TextColor3       = WARN,
	TextSize         = 11,
	Visible          = false,
})
addCorner(detailDropBtn, 5)

-- Split overlay (appears over the detail strip when SPLIT is clicked)
local splitOverlay = Instance.new("Frame")
splitOverlay.Size             = UDim2.new(1, 0, 1, 0)
splitOverlay.BackgroundColor3 = BG2
splitOverlay.BorderSizePixel  = 0
splitOverlay.Visible          = false
splitOverlay.ZIndex           = 10
splitOverlay.Parent           = detailStrip
addCorner(splitOverlay, 6)

makeLabel(splitOverlay, {
	Size           = UDim2.new(0, 140, 1, 0),
	Position       = UDim2.new(0, 10, 0, 0),
	Text           = "Split how many?",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3     = TEXT,
	Font           = FONTB,
	TextSize       = 12,
	ZIndex         = 11,
})

local splitBox = Instance.new("TextBox")
splitBox.Size                  = UDim2.new(0, 60, 0, 30)
splitBox.Position              = UDim2.new(0, 155, 0.5, -15)
splitBox.BackgroundColor3      = BG3
splitBox.BorderSizePixel       = 0
splitBox.Font                  = FONTB
splitBox.TextColor3            = TEXT
splitBox.TextSize              = 14
splitBox.PlaceholderText       = "1"
splitBox.PlaceholderColor3     = MUTED
splitBox.Text                  = ""
splitBox.ClearTextOnFocus      = true
splitBox.ZIndex                = 11
splitBox.Parent                = splitOverlay
addCorner(splitBox, 5)

local splitConfirmBtn = makeButton(splitOverlay, {
	Size             = UDim2.new(0, 60, 0, 30),
	Position         = UDim2.new(0, 225, 0.5, -15),
	BackgroundColor3 = ACCENT,
	Text             = "OK",
	TextSize         = 13,
	ZIndex           = 11,
})
addCorner(splitConfirmBtn, 5)

local splitCancelBtn = makeButton(splitOverlay, {
	Size             = UDim2.new(0, 60, 0, 30),
	Position         = UDim2.new(0, 295, 0.5, -15),
	BackgroundColor3 = Color3.fromRGB(55, 28, 28),
	Text             = "Cancel",
	TextColor3       = BAD,
	TextSize         = 12,
	ZIndex           = 11,
})
addCorner(splitCancelBtn, 5)

-- ── Trade quantity picker (centered modal) ──────────────────────────────────
-- Shown when dragging a stack (qty > 1) onto the trade panel or another player.

local tradeQtyCallback: ((qty: number) -> ())? = nil

local tradeQtyOverlay = Instance.new("TextButton") -- full-screen click blocker
tradeQtyOverlay.Size               = UDim2.new(1, 0, 1, 0)
tradeQtyOverlay.BackgroundColor3   = Color3.new(0, 0, 0)
tradeQtyOverlay.BackgroundTransparency = 0.5
tradeQtyOverlay.BorderSizePixel    = 0
tradeQtyOverlay.Text               = ""
tradeQtyOverlay.AutoButtonColor    = false
tradeQtyOverlay.ZIndex             = 50
tradeQtyOverlay.Visible            = false
tradeQtyOverlay.Active             = false
tradeQtyOverlay.Parent             = gui

local tradeQtyPopup = Instance.new("Frame")
tradeQtyPopup.Size               = UDim2.new(0, 220, 0, 150)
tradeQtyPopup.Position           = UDim2.new(0.5, -110, 0.5, -75)
tradeQtyPopup.BackgroundColor3   = BG2
tradeQtyPopup.BorderSizePixel    = 0
tradeQtyPopup.ZIndex             = 51
tradeQtyPopup.Parent             = tradeQtyOverlay
addCorner(tradeQtyPopup, 8)

local tradeQtyTitle = makeLabel(tradeQtyPopup, {
	Size           = UDim2.new(1, -20, 0, 22),
	Position       = UDim2.new(0, 10, 0, 10),
	Text           = "How many to offer?",
	Font           = FONTB,
	TextSize       = 13,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex         = 52,
})

local tradeQtyItemLabel = makeLabel(tradeQtyPopup, {
	Size           = UDim2.new(1, -20, 0, 18),
	Position       = UDim2.new(0, 10, 0, 36),
	Text           = "",
	TextSize       = 11,
	TextColor3     = MUTED,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex         = 52,
})

local tradeQtyMinus = makeButton(tradeQtyPopup, {
	Size             = UDim2.new(0, 30, 0, 30),
	Position         = UDim2.new(0.5, -65, 0, 60),
	BackgroundColor3 = BG3,
	Text             = "-",
	TextSize         = 16,
	ZIndex           = 52,
})
addCorner(tradeQtyMinus, 5)

local tradeQtyBox = Instance.new("TextBox")
tradeQtyBox.Size                  = UDim2.new(0, 60, 0, 30)
tradeQtyBox.Position              = UDim2.new(0.5, -30, 0, 60)
tradeQtyBox.BackgroundColor3      = BG3
tradeQtyBox.BorderSizePixel       = 0
tradeQtyBox.Font                  = FONTB
tradeQtyBox.TextColor3            = TEXT
tradeQtyBox.TextSize              = 14
tradeQtyBox.PlaceholderText       = "1"
tradeQtyBox.PlaceholderColor3     = MUTED
tradeQtyBox.Text                  = ""
tradeQtyBox.ClearTextOnFocus      = true
tradeQtyBox.ZIndex                = 52
tradeQtyBox.Parent                = tradeQtyPopup
addCorner(tradeQtyBox, 5)

local tradeQtyPlus = makeButton(tradeQtyPopup, {
	Size             = UDim2.new(0, 30, 0, 30),
	Position         = UDim2.new(0.5, 35, 0, 60),
	BackgroundColor3 = BG3,
	Text             = "+",
	TextSize         = 16,
	ZIndex           = 52,
})
addCorner(tradeQtyPlus, 5)

local tradeQtyConfirm = makeButton(tradeQtyPopup, {
	Size             = UDim2.new(0, 90, 0, 30),
	Position         = UDim2.new(0.5, -95, 0, 105),
	BackgroundColor3 = ACCENT,
	Text             = "Offer",
	TextSize         = 13,
	ZIndex           = 52,
})
addCorner(tradeQtyConfirm, 5)

local tradeQtyCancel = makeButton(tradeQtyPopup, {
	Size             = UDim2.new(0, 90, 0, 30),
	Position         = UDim2.new(0.5, 5, 0, 105),
	BackgroundColor3 = Color3.fromRGB(55, 28, 28),
	Text             = "Cancel",
	TextColor3       = BAD,
	TextSize         = 12,
	ZIndex           = 52,
})
addCorner(tradeQtyCancel, 5)

local tradeQtyMaxQty = 1

local function hideTradeQtyPicker()
	tradeQtyOverlay.Visible = false
	tradeQtyOverlay.Active  = false
	tradeQtyCallback = nil
end

local function showTradeQtyPicker(itemId: string, maxQty: number, callback: (number) -> ())
	local def = ItemRegistry[itemId]
	local displayName = (def and def.displayName) or itemId
	tradeQtyItemLabel.Text = displayName .. "  (max " .. tostring(maxQty) .. ")"
	tradeQtyBox.Text = tostring(maxQty)
	tradeQtyMaxQty = maxQty
	tradeQtyCallback = callback
	tradeQtyOverlay.Visible = true
	tradeQtyOverlay.Active  = true
	tradeQtyBox:CaptureFocus()
end

local function clampTradeQty(v: number): number
	return math.clamp(math.floor(v), 1, tradeQtyMaxQty)
end

tradeQtyMinus.Activated:Connect(function()
	local cur = tonumber(tradeQtyBox.Text) or 1
	tradeQtyBox.Text = tostring(clampTradeQty(cur - 1))
end)

tradeQtyPlus.Activated:Connect(function()
	local cur = tonumber(tradeQtyBox.Text) or 1
	tradeQtyBox.Text = tostring(clampTradeQty(cur + 1))
end)

tradeQtyConfirm.Activated:Connect(function()
	local qty = clampTradeQty(tonumber(tradeQtyBox.Text) or 1)
	local cb = tradeQtyCallback
	hideTradeQtyPicker()
	if cb then cb(qty) end
end)

tradeQtyCancel.Activated:Connect(function()
	hideTradeQtyPicker()
end)

tradeQtyOverlay.Activated:Connect(function()
	hideTradeQtyPicker()
end)

-- Weight bar
local weightSection = Instance.new("Frame")
weightSection.Size               = UDim2.new(1, 0, 0, 42)
weightSection.Position           = UDim2.new(0, 0, 0, 302)
weightSection.BackgroundTransparency = 1
weightSection.Parent             = itemsPane

local weightLabel = makeLabel(weightSection, {
	Size           = UDim2.new(1, 0, 0, 14),
	Text           = "Weight: 0.00 / 5.00 kg",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3     = MUTED,
	TextSize       = 11,
})

local wBarBg = Instance.new("Frame")
wBarBg.Size             = UDim2.new(1, 0, 0, 8)
wBarBg.Position         = UDim2.new(0, 0, 0, 18)
wBarBg.BackgroundColor3 = Color3.fromRGB(38, 45, 65)
wBarBg.BorderSizePixel  = 0
wBarBg.Parent           = weightSection
addCorner(wBarBg, 4)

local wBar = Instance.new("Frame")
wBar.Size             = UDim2.new(0, 0, 1, 0)
wBar.BackgroundColor3 = ACCENT
wBar.BorderSizePixel  = 0
wBar.Parent           = wBarBg
addCorner(wBar, 4)

local refreshRecipeBook -- forward declaration; assigned after helpers

-- ── RECIPES PANE ──────────────────────────────────────────────────────────

local craftPane = Instance.new("Frame")
craftPane.Size               = UDim2.new(1, 0, 1, 0)
craftPane.BackgroundTransparency = 1
craftPane.Visible            = false
craftPane.Parent             = content

-- Filter bar
local filterBar = Instance.new("Frame")
filterBar.Size               = UDim2.new(1, 0, 0, 22)
filterBar.BackgroundTransparency = 1
filterBar.Parent             = craftPane

local recipeFilter = "all"

local function makeFilterBtn(label: string, xOff: number): TextButton
	local b = makeButton(filterBar, {
		Size             = UDim2.new(0, 72, 0, 20),
		Position         = UDim2.new(0, xOff, 0, 0),
		BackgroundColor3 = BG2,
		Text             = label,
		TextSize         = 10,
		TextColor3       = MUTED,
	})
	addCorner(b, 4)
	return b
end

local filterAllBtn  = makeFilterBtn("ALL",       0)
local filterHandBtn = makeFilterBtn("HAND",     76)
local filterCampBtn = makeFilterBtn("CAMPFIRE", 152)

-- Initial highlight
filterAllBtn.TextColor3       = TEXT
filterAllBtn.BackgroundColor3 = BG3

local craftScroll = Instance.new("ScrollingFrame")
craftScroll.Size                = UDim2.new(1, 0, 1, -26)
craftScroll.Position            = UDim2.new(0, 0, 0, 26)
craftScroll.BackgroundColor3    = BG2
craftScroll.BorderSizePixel     = 0
craftScroll.ScrollBarThickness  = 4
craftScroll.ScrollBarImageColor3 = ACCENT
craftScroll.CanvasSize          = UDim2.new(0, 0, 0, 0)
craftScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
craftScroll.Parent              = craftPane
addCorner(craftScroll, 6)

local craftLayout = Instance.new("UIListLayout")
craftLayout.SortOrder  = Enum.SortOrder.LayoutOrder
craftLayout.Padding    = UDim.new(0, 3)
craftLayout.Parent     = craftScroll

local craftPad = Instance.new("UIPadding")
craftPad.PaddingTop   = UDim.new(0, 4)
craftPad.PaddingLeft  = UDim.new(0, 6)
craftPad.PaddingRight = UDim.new(0, 6)
craftPad.Parent       = craftScroll

-- ── Unified recipe list (hand-craft + cooking) ──────────────────────────

type UnifiedRecipe = {
	id: string,
	displayName: string,
	station: string,
	ingredients: { { itemId: string, qty: number } }?,
	inputId: string?,
	output: { itemId: string, qty: number },
	cookSeconds: number?,
}

local allRecipes: { UnifiedRecipe } = {}

for _, recipe in ipairs(CraftingConfig.Recipes) do
	table.insert(allRecipes, {
		id          = recipe.id,
		displayName = recipe.displayName,
		station     = recipe.station or "hand",
		ingredients = recipe.ingredients,
		output      = recipe.output,
	})
end

for inputId, recipe in pairs(CookingConfig.Recipes) do
	table.insert(allRecipes, {
		id          = inputId .. "_cook",
		displayName = recipe.displayName,
		station     = recipe.station or "campfire",
		inputId     = inputId,
		output      = { itemId = recipe.output, qty = 1 },
		cookSeconds = recipe.cookSeconds,
	})
end

table.sort(allRecipes, function(a, b)
	if a.station ~= b.station then
		if a.station == "hand" then return true end
		if b.station == "hand" then return false end
		return a.station < b.station
	end
	return a.displayName < b.displayName
end)

-- ── Craft channel state ──────────────────────────────────────────────────

local CRAFT_DURATION = 5 -- seconds
local isCrafting   = false
local craftRecipeId = ""
local craftAnimTrack: AnimationTrack? = nil
local setOpen: (boolean) -> ()  -- forward declaration

local function stopCraftAnimation()
	if craftAnimTrack then
		craftAnimTrack:Stop()
		craftAnimTrack = nil
	end
end

local function playCraftAnimation()
	stopCraftAnimation()
	local animId = AssetIds.Animations.Crafting
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
		craftAnimTrack = track
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play()
	end
end

local function cancelCraft()
	if not isCrafting then return end
	isCrafting = false
	craftRecipeId = ""
	craftBarBg.Visible = false
	craftBarFill.Size = UDim2.fromScale(0, 1)
	craftBarLabel.TextColor3 = TEXT
	craftingSound:Stop()
	stopCraftAnimation()
	-- Reparent bar back to inventory panel
	craftBarBg.Parent = panel
	craftBarBg.Position = UDim2.new(0, 12, 1, -22)
	craftBarBg.Size = UDim2.new(1, -24, 0, 14)
end

-- ── Craft rejection notification (centered on screen) ────────────────────

local function showCraftRejection(message: string)
	local hudGui = player.PlayerGui:FindFirstChild("GameplayHud")
	local parent = hudGui or player.PlayerGui
	local notify = Instance.new("Frame")
	notify.Name                  = "CraftRejectNotify"
	notify.Size                  = UDim2.fromOffset(300, 36)
	notify.Position              = UDim2.new(0.5, -150, 0.4, 0)
	notify.AnchorPoint           = Vector2.new(0, 0)
	notify.BackgroundColor3      = Color3.fromRGB(28, 32, 42)
	notify.BackgroundTransparency = 0.15
	notify.BorderSizePixel       = 0
	notify.ZIndex                = 50
	notify.Parent                = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent       = notify

	local stroke = Instance.new("UIStroke")
	stroke.Color        = BAD
	stroke.Transparency = 0.4
	stroke.Thickness    = 1.5
	stroke.Parent       = notify

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text                   = message
	label.TextColor3             = BAD
	label.TextSize               = 16
	label.Font                   = Enum.Font.GothamBold
	label.ZIndex                 = 51
	label.Parent                 = notify

	task.delay(2.5, function()
		if notify.Parent then notify:Destroy() end
	end)
end

local function startCraft(recipeId: string)
	if isCrafting then return end

	-- Find the recipe
	local recipe = nil
	for _, r in ipairs(allRecipes) do
		if r.id == recipeId then recipe = r; break end
	end
	if not recipe or not recipe.ingredients then return end

	-- Check weight: net change = output weight - ingredient weight
	local ingredientWeight = 0
	for _, ing in ipairs(recipe.ingredients) do
		local def = ItemRegistry.get(ing.itemId)
		if def then ingredientWeight += def.weight * ing.qty end
	end
	local outputDef = ItemRegistry.get(recipe.output.itemId)
	local outputWeight = outputDef and (outputDef.weight * recipe.output.qty) or 0
	local netWeight = outputWeight - ingredientWeight

	if netWeight > 0 then
		local currentWeight = tonumber(player:GetAttribute("CarryWeight")) or 0
		local maxWeight = tonumber(player:GetAttribute("MaxCarryWeight")) or 5
		if currentWeight + netWeight > maxWeight + 0.001 then
			showCraftRejection("Too heavy to craft!")
			return
		end
	end

	-- Check slot capacity: will the output fit after ingredient removal?
	if outputDef then
		local maxSlots = getMaxSlots()
		local stackRoom = 0
		for n = 1, maxSlots do
			if getSlotItemId(n) == recipe.output.itemId then
				stackRoom += outputDef.stackMax - getSlotQty(n)
			end
		end
		if stackRoom < recipe.output.qty then
			local emptySlots = 0
			for n = 1, maxSlots do
				if getSlotItemId(n) == "" then emptySlots += 1 end
			end
			-- Count slots freed by consuming entire stacks of ingredients
			local freedSlots = 0
			local ingRemaining: { [string]: number } = {}
			for _, ing in ipairs(recipe.ingredients) do
				ingRemaining[ing.itemId] = (ingRemaining[ing.itemId] or 0) + ing.qty
			end
			for n = maxSlots, 1, -1 do
				local slotItem = getSlotItemId(n)
				if slotItem ~= "" and ingRemaining[slotItem] and ingRemaining[slotItem] > 0 then
					local qty  = getSlotQty(n)
					local take = math.min(ingRemaining[slotItem], qty)
					ingRemaining[slotItem] -= take
					if take >= qty then freedSlots += 1 end
				end
			end
			local totalRoom = stackRoom + (emptySlots + freedSlots) * outputDef.stackMax
			if totalRoom < recipe.output.qty then
				showCraftRejection("Inventory full!")
				return
			end
		end
	end

	isCrafting = true
	craftRecipeId = recipeId
	craftBarLabel.TextColor3 = TEXT

	-- Close inventory directly (bypass setOpen to avoid cancelCraft)
	isOpen = false
	panel.Visible = false

	-- Show progress bar in HUD (reparent to GameplayHud so it's visible with inventory closed)
	local hudGui = player.PlayerGui:FindFirstChild("GameplayHud")
	if hudGui then
		craftBarBg.Parent = hudGui
		craftBarBg.Position = UDim2.new(0.5, -150, 0.85, 0)
		craftBarBg.Size = UDim2.fromOffset(300, 16)
	end
	craftBarBg.Visible = true
	craftBarFill.Size = UDim2.fromScale(0, 1)
	craftBarLabel.Text = "Crafting..."
	craftingSound:Play()
	playCraftAnimation()

	task.spawn(function()
		local elapsed = 0
		local capturedId = recipeId
		while isCrafting and craftRecipeId == capturedId and elapsed < CRAFT_DURATION do
			local dt = task.wait()
			elapsed += dt
			local t = math.clamp(elapsed / CRAFT_DURATION, 0, 1)
			craftBarFill.Size = UDim2.fromScale(t, 1)
		end
		if isCrafting and craftRecipeId == capturedId then
			-- Channel complete — fire craft
			craftItemRemote:FireServer(capturedId)
			cancelCraft()
		end
	end)
end

-- ── Pre-build recipe rows ─────────────────────────────────────────────────

type RecipeRow = {
	row: Frame,
	ingLabel: TextLabel,
	craftBtn: TextButton?,
	station: string,
}

local recipeRows: { RecipeRow } = {}

for i, recipe in ipairs(allRecipes) do
	local row = Instance.new("Frame")
	row.Name             = recipe.id
	row.LayoutOrder      = i
	row.Size             = UDim2.new(1, 0, 0, 58)
	row.BackgroundColor3 = BG3
	row.BorderSizePixel  = 0
	row.Parent           = craftScroll
	addCorner(row, 6)

	-- Station badge (top-right)
	local badgeColor = recipe.station == "hand" and ACCENT or Color3.fromRGB(200, 120, 40)
	local badgeText  = recipe.station == "hand" and "HAND" or "CAMPFIRE"
	makeLabel(row, {
		Size           = UDim2.new(0, 68, 0, 16),
		Position       = UDim2.new(1, (recipe.station == "hand" and -148 or -80), 0, 4),
		Text           = badgeText,
		TextColor3     = badgeColor,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize       = 9,
		Font           = FONTB,
	})

	makeLabel(row, {
		Size           = UDim2.new(1, -150, 0, 22),
		Position       = UDim2.new(0, 8, 0, 4),
		Text           = recipe.displayName,
		Font           = FONTB,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize       = 13,
	})

	local ingLabel = makeLabel(row, {
		Name           = "Ingredients",
		Size           = UDim2.new(1, -90, 0, 28),
		Position       = UDim2.new(0, 8, 0, 26),
		Text           = "",
		TextColor3     = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize       = 11,
		TextWrapped    = true,
	})

	local craftBtn: TextButton? = nil
	if recipe.station == "hand" then
		craftBtn = makeButton(row, {
			Size             = UDim2.new(0, 72, 0, 30),
			Position         = UDim2.new(1, -80, 0.5, -15),
			BackgroundColor3 = ACCENT,
			Text             = "CRAFT",
			TextSize         = 12,
		})
		addCorner(craftBtn, 5)

		local capturedId = recipe.id
		craftBtn.Activated:Connect(function()
			if isCrafting then
				cancelCraft()
			else
				startCraft(capturedId)
			end
		end)
	end

	table.insert(recipeRows, {
		row      = row,
		ingLabel = ingLabel,
		craftBtn = craftBtn,
		station  = recipe.station,
	})
end

-- ── Filter handlers ──────────────────────────────────────────────────────

local function setRecipeFilter(filter: string)
	recipeFilter = filter
	filterAllBtn.TextColor3        = filter == "all"      and TEXT or MUTED
	filterAllBtn.BackgroundColor3  = filter == "all"      and BG3  or BG2
	filterHandBtn.TextColor3       = filter == "hand"     and TEXT or MUTED
	filterHandBtn.BackgroundColor3 = filter == "hand"     and BG3  or BG2
	filterCampBtn.TextColor3       = filter == "campfire" and TEXT or MUTED
	filterCampBtn.BackgroundColor3 = filter == "campfire" and BG3  or BG2
	if refreshRecipeBook then refreshRecipeBook() end
end

filterAllBtn.Activated:Connect(function()  setRecipeFilter("all") end)
filterHandBtn.Activated:Connect(function() setRecipeFilter("hand") end)
filterCampBtn.Activated:Connect(function() setRecipeFilter("campfire") end)

-- ── CHARACTER PANE ────────────────────────────────────────────────────────

local charPane = Instance.new("Frame")
charPane.Size               = UDim2.new(1, 0, 1, 0)
charPane.BackgroundTransparency = 1
charPane.Visible            = false
charPane.Parent             = content

local equipSection = Instance.new("Frame")
equipSection.Size             = UDim2.new(0, 255, 1, 0)
equipSection.BackgroundTransparency = 1
equipSection.Parent           = charPane

makeLabel(equipSection, {
	Size           = UDim2.new(1, 0, 0, 16),
	Text           = "EQUIPMENT",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3     = MUTED,
	Font           = FONTB,
	TextSize       = 10,
})

local SLOT_PAIRS = {
	{ "Head",       "Head",       "Neck",     "Neck"      },
	{ "Chest",      "Chest",      "Belt",     "Belt"      },
	{ "Legs",       "Legs",       "Feet",     "Feet"      },
	{ "RingL",      "Ring (L)",   "RingR",    "Ring (R)"  },
	{ "MainHand",   "Main Hand",  "Quiver",   "Quiver"    },
	{ "CoinPouch",  "Coin Pouch", "Backpack", "Backpack"  },
}

local SLOT_W, SLOT_H, SLOT_GAP = 118, 40, 6

type SlotRef = { nameLabel: TextLabel, valLabel: TextLabel, box: Frame? }
local slotRefs: { [string]: SlotRef } = {}

local function makeSlotBox(parent: Instance, slotId: string, labelText: string, xOff: number, yOff: number)
	local box = Instance.new("Frame")
	box.Size             = UDim2.new(0, SLOT_W, 0, SLOT_H)
	box.Position         = UDim2.new(0, xOff, 0, yOff)
	box.BackgroundColor3 = BG3
	box.BorderSizePixel  = 0
	box.Parent           = parent
	addCorner(box, 5)

	local nameLabel = makeLabel(box, {
		Size           = UDim2.new(1, -6, 0, 14),
		Position       = UDim2.new(0, 6, 0, 3),
		Text           = labelText,
		TextColor3     = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize       = 10,
	})
	local valLabel = makeLabel(box, {
		Size           = UDim2.new(1, -6, 0, 18),
		Position       = UDim2.new(0, 6, 0, 18),
		Text           = "--",
		TextColor3     = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font           = FONTB,
		TextSize       = 12,
	})
	slotRefs[slotId] = { nameLabel = nameLabel, valLabel = valLabel, box = box }
end

for row, pair in ipairs(SLOT_PAIRS) do
	local yOff = 20 + (row - 1) * (SLOT_H + SLOT_GAP)
	makeSlotBox(equipSection, pair[1], pair[2], 0,          yOff)
	makeSlotBox(equipSection, pair[3], pair[4], SLOT_W + 8, yOff)
end

-- Click Backpack slot to unequip
do
	local bpRef = slotRefs["Backpack"]
	if bpRef and bpRef.box then
		local btn = Instance.new("TextButton")
		btn.Size                    = UDim2.new(1, 0, 1, 0)
		btn.BackgroundTransparency  = 1
		btn.Text                    = ""
		btn.Parent                  = bpRef.box
		btn.Activated:Connect(function()
			local equipped = player:GetAttribute("EquipSlot_Backpack") or ""
			if equipped ~= "" then
				unequipBackpackRemote:FireServer()
			end
		end)
	end
end

-- Click Quiver slot to unequip
do
	local qRef = slotRefs["Quiver"]
	if qRef and qRef.box then
		local btn = Instance.new("TextButton")
		btn.Size                    = UDim2.new(1, 0, 1, 0)
		btn.BackgroundTransparency  = 1
		btn.Text                    = ""
		btn.Parent                  = qRef.box
		btn.Activated:Connect(function()
			local equipped = player:GetAttribute("EquipSlot_Quiver") or ""
			if equipped ~= "" then
				unequipQuiverRemote:FireServer()
			end
		end)
	end
end

local statsSection = Instance.new("Frame")
statsSection.Size             = UDim2.new(1, -265, 1, 0)
statsSection.Position         = UDim2.new(0, 265, 0, 0)
statsSection.BackgroundTransparency = 1
statsSection.Parent           = charPane

makeLabel(statsSection, {
	Size           = UDim2.new(1, 0, 0, 16),
	Text           = "ATTRIBUTES",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3     = MUTED,
	Font           = FONTB,
	TextSize       = 10,
})

local STAT_DEFS = {
	{ id = "STR", label = "Strength",     desc = "Physical power"           },
	{ id = "AGI", label = "Agility",      desc = "Speed & precision"        },
	{ id = "CON", label = "Constitution", desc = "Health & stamina"         },
	{ id = "WIS", label = "Wisdom",       desc = "Survival intuition"       },
	{ id = "INT", label = "Intellect",    desc = "Crafting & lore"          },
	{ id = "CHA", label = "Charisma",     desc = "NPC pricing & diplomacy"  },
}

type StatRef = { valLabel: TextLabel }
local statRefs: { [string]: StatRef } = {}

for i, stat in ipairs(STAT_DEFS) do
	local yOff = 20 + (i - 1) * 48
	local statBox = Instance.new("Frame")
	statBox.Size             = UDim2.new(1, 0, 0, 44)
	statBox.Position         = UDim2.new(0, 0, 0, yOff)
	statBox.BackgroundColor3 = BG3
	statBox.BorderSizePixel  = 0
	statBox.Parent           = statsSection
	addCorner(statBox, 5)

	makeLabel(statBox, {
		Size           = UDim2.new(1, -50, 0, 16),
		Position       = UDim2.new(0, 8, 0, 4),
		Text           = stat.label,
		Font           = FONTB,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize       = 12,
	})
	makeLabel(statBox, {
		Size           = UDim2.new(1, -50, 0, 16),
		Position       = UDim2.new(0, 8, 0, 22),
		Text           = stat.desc,
		TextColor3     = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize       = 10,
	})

	local valLabel = makeLabel(statBox, {
		Size           = UDim2.new(0, 40, 1, 0),
		Position       = UDim2.new(1, -48, 0, 0),
		Text           = "0",
		Font           = FONTB,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize       = 16,
		TextColor3     = ACCENT,
	})
	statRefs[stat.id] = { valLabel = valLabel }
end

-- ── ACHIEVEMENTS PANE ─────────────────────────────────────────────────────

local GOLD = Color3.fromRGB(255, 200, 60)

local achPane = Instance.new("Frame")
achPane.Size               = UDim2.new(1, 0, 1, 0)
achPane.BackgroundTransparency = 1
achPane.Visible            = false
achPane.Parent             = content

-- Achievement state (synced from server)
local achCounters: { [string]: number } = {}
local achUnlocked: { [string]: number } = {}
local achTotalCount = AchievementConfig.TotalCount

-- Summary header
local achSummary = makeLabel(achPane, {
	Size           = UDim2.new(1, 0, 0, 20),
	Position       = UDim2.new(0, 0, 0, 0),
	Text           = "0/" .. achTotalCount .. " Achievements Unlocked",
	TextColor3     = GOLD,
	Font           = FONTB,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize       = 12,
})

-- Category dropdown filter
local achFilterCategory = "ALL"

local allCategories = { "ALL" }
for _, cat in ipairs(AchievementConfig.Categories) do
	table.insert(allCategories, cat)
end

-- Dropdown trigger button
local achDropdownBtn = Instance.new("TextButton")
achDropdownBtn.Size             = UDim2.new(1, 0, 0, 26)
achDropdownBtn.Position         = UDim2.new(0, 0, 0, 22)
achDropdownBtn.BackgroundColor3 = BG2
achDropdownBtn.BorderSizePixel  = 0
achDropdownBtn.TextColor3       = TEXT
achDropdownBtn.TextSize         = 11
achDropdownBtn.Font             = FONTB
achDropdownBtn.TextXAlignment   = Enum.TextXAlignment.Left
achDropdownBtn.Text             = "  ALL  v"
achDropdownBtn.Parent           = achPane
addCorner(achDropdownBtn, 4)

local achDropdownStroke = Instance.new("UIStroke")
achDropdownStroke.Color       = Color3.fromRGB(55, 65, 95)
achDropdownStroke.Thickness   = 1
achDropdownStroke.Transparency = 0.4
achDropdownStroke.Parent      = achDropdownBtn

-- Dropdown popup (hidden by default)
local achDropdownPopup = Instance.new("ScrollingFrame")
achDropdownPopup.Size               = UDim2.new(1, 0, 0, 200)
achDropdownPopup.Position           = UDim2.new(0, 0, 0, 50)
achDropdownPopup.BackgroundColor3   = BG
achDropdownPopup.BackgroundTransparency = 0.05
achDropdownPopup.BorderSizePixel    = 0
achDropdownPopup.ScrollBarThickness = 3
achDropdownPopup.ScrollBarImageColor3 = MUTED
achDropdownPopup.AutomaticCanvasSize = Enum.AutomaticSize.Y
achDropdownPopup.CanvasSize         = UDim2.new(0, 0, 0, 0)
achDropdownPopup.Visible            = false
achDropdownPopup.ZIndex             = 10
achDropdownPopup.Parent             = achPane
addCorner(achDropdownPopup, 6)

local achDropdownPopupStroke = Instance.new("UIStroke")
achDropdownPopupStroke.Color       = Color3.fromRGB(55, 65, 95)
achDropdownPopupStroke.Thickness   = 1
achDropdownPopupStroke.Transparency = 0.3
achDropdownPopupStroke.Parent      = achDropdownPopup

local achDropdownLayout = Instance.new("UIListLayout")
achDropdownLayout.FillDirection = Enum.FillDirection.Vertical
achDropdownLayout.Padding       = UDim.new(0, 2)
achDropdownLayout.SortOrder     = Enum.SortOrder.LayoutOrder
achDropdownLayout.Parent        = achDropdownPopup

local achDropdownPadding = Instance.new("UIPadding")
achDropdownPadding.PaddingTop    = UDim.new(0, 4)
achDropdownPadding.PaddingBottom = UDim.new(0, 4)
achDropdownPadding.PaddingLeft   = UDim.new(0, 4)
achDropdownPadding.PaddingRight  = UDim.new(0, 4)
achDropdownPadding.Parent        = achDropdownPopup

-- Category count labels (updated in refreshAchievements)
local achCatCountLabels: { [string]: TextLabel } = {}

for i, cat in ipairs(allCategories) do
	local row = Instance.new("TextButton")
	row.Size             = UDim2.new(1, 0, 0, 24)
	row.BackgroundColor3 = if cat == "ALL" then BG3 else BG2
	row.BackgroundTransparency = 0.2
	row.BorderSizePixel  = 0
	row.TextColor3       = if cat == "ALL" then TEXT else MUTED
	row.TextSize         = 10
	row.Font             = FONTB
	row.TextXAlignment   = Enum.TextXAlignment.Left
	row.Text             = "  " .. cat
	row.LayoutOrder      = i
	row.ZIndex           = 11
	row.Parent           = achDropdownPopup
	addCorner(row, 4)

	-- Count badge on right side
	local countLabel = makeLabel(row, {
		Size           = UDim2.new(0, 40, 1, 0),
		Position       = UDim2.new(1, -44, 0, 0),
		TextColor3     = MUTED,
		TextSize       = 9,
		Font           = FONTB,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text           = "",
		ZIndex         = 12,
	})
	achCatCountLabels[cat] = countLabel

	local capturedCat = cat
	row.Activated:Connect(function()
		achFilterCategory = capturedCat
		achDropdownBtn.Text = "  " .. capturedCat .. "  v"
		achDropdownPopup.Visible = false
		refreshAchievements()
	end)

	-- Highlight on hover
	row.MouseEnter:Connect(function()
		row.BackgroundTransparency = 0
	end)
	row.MouseLeave:Connect(function()
		row.BackgroundTransparency = 0.2
	end)
end

-- Toggle dropdown on button click
achDropdownBtn.Activated:Connect(function()
	achDropdownPopup.Visible = not achDropdownPopup.Visible
end)

-- Scrolling grid of achievement cards
local achScroll = Instance.new("ScrollingFrame")
achScroll.Size               = UDim2.new(1, 0, 1, -54)
achScroll.Position           = UDim2.new(0, 0, 0, 52)
achScroll.BackgroundTransparency = 1
achScroll.ScrollBarThickness = 4
achScroll.ScrollBarImageColor3 = MUTED
achScroll.CanvasSize         = UDim2.new(0, 0, 0, 0)
achScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
achScroll.Parent             = achPane

local achGrid = Instance.new("UIGridLayout")
achGrid.CellSize     = UDim2.new(0, 96, 0, 90)
achGrid.CellPadding  = UDim2.new(0, 6, 0, 6)
achGrid.SortOrder    = Enum.SortOrder.LayoutOrder
achGrid.Parent       = achScroll

-- Build achievement card frames (once, then show/hide on filter)
type AchCard = { frame: Frame, category: string, key: string, iconLabel: GuiObject, nameLabel: TextLabel, progressLabel: TextLabel, checkLabel: TextLabel, stroke: UIStroke }
local achCards: { AchCard } = {}

for i, ach in ipairs(AchievementConfig.Achievements) do
	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 96, 0, 90)
	card.BackgroundColor3 = BG3
	card.BorderSizePixel  = 0
	card.LayoutOrder      = i
	card.Parent           = achScroll
	addCorner(card, 6)

	local achCardStroke = Instance.new("UIStroke")
	achCardStroke.Color       = MUTED
	achCardStroke.Thickness   = 1
	achCardStroke.Transparency = 0.7
	achCardStroke.Parent      = card

	-- Use ImageLabel if an achievement icon asset exists, otherwise fall back to emoji TextLabel
	local achIconAsset = AssetIds.AchievementIcons and AssetIds.AchievementIcons[ach.key]
	local iconLabel: GuiObject
	if achIconAsset and achIconAsset ~= "" then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(0, 32, 0, 32)
		img.Position = UDim2.new(0.5, 0, 0, 6)
		img.AnchorPoint = Vector2.new(0.5, 0)
		img.BackgroundTransparency = 1
		img.Image = achIconAsset
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = card
		iconLabel = img
	else
		iconLabel = makeLabel(card, {
			Size     = UDim2.new(1, 0, 0, 32),
			Position = UDim2.new(0, 0, 0, 6),
			Text     = ach.icon,
			TextSize = 24,
		})
	end

	local nameLabel = makeLabel(card, {
		Size           = UDim2.new(1, -6, 0, 24),
		Position       = UDim2.new(0, 3, 0, 38),
		Text           = ach.name,
		TextColor3     = TEXT,
		TextSize       = 9,
		Font           = FONTB,
		TextWrapped    = true,
		TextTruncate   = Enum.TextTruncate.AtEnd,
	})

	local progressLabel = makeLabel(card, {
		Size           = UDim2.new(1, 0, 0, 14),
		Position       = UDim2.new(0, 0, 1, -18),
		Text           = "0/" .. ach.threshold,
		TextColor3     = MUTED,
		TextSize       = 9,
	})

	local checkLabel = makeLabel(card, {
		Size           = UDim2.new(0, 20, 0, 20),
		Position       = UDim2.new(1, -22, 0, 2),
		Text           = "\u{2714}",
		TextColor3     = GOLD,
		TextSize       = 14,
		Font           = FONTB,
	})
	checkLabel.Visible = false

	table.insert(achCards, {
		frame = card,
		category = ach.category,
		key = ach.key,
		iconLabel = iconLabel,
		nameLabel = nameLabel,
		progressLabel = progressLabel,
		checkLabel = checkLabel,
		stroke = achCardStroke,
	})

	-- Register achievement tooltip
	TooltipModule.register(card, {
		kind = "achievement",
		key = ach.key,
		counter = 0,
		unlocked = false,
	})
end

local function refreshAchievements()
	local unlockedCount = 0
	for _ in pairs(achUnlocked) do unlockedCount += 1 end
	achSummary.Text = unlockedCount .. "/" .. achTotalCount .. " Achievements Unlocked"

	for i, card in ipairs(achCards) do
		local ach = AchievementConfig.Achievements[i]
		local isUnlocked = achUnlocked[ach.key] ~= nil
		local counter = achCounters[ach.counter] or 0
		local progress = math.min(counter, ach.threshold)

		-- Filter visibility
		local matchesFilter = achFilterCategory == "ALL" or card.category == achFilterCategory
		card.frame.Visible = matchesFilter

		-- Update progress
		card.progressLabel.Text = progress .. "/" .. ach.threshold

		-- Update achievement tooltip data
		TooltipModule.update(card.frame, {
			kind = "achievement",
			key = ach.key,
			counter = counter,
			unlocked = isUnlocked,
		})

		-- Unlocked state
		card.checkLabel.Visible = isUnlocked
		local iconAlpha = if isUnlocked then 0 else 0.5
		if card.iconLabel:IsA("ImageLabel") then
			(card.iconLabel :: ImageLabel).ImageTransparency = iconAlpha
		elseif card.iconLabel:IsA("TextLabel") then
			(card.iconLabel :: TextLabel).TextTransparency = iconAlpha
		end
		if isUnlocked then
			card.frame.BackgroundColor3 = Color3.fromRGB(32, 42, 36)
			card.progressLabel.TextColor3 = GOLD
			card.nameLabel.TextColor3 = TEXT
			card.stroke.Color = GOLD
			card.stroke.Transparency = 0.4
		else
			card.frame.BackgroundColor3 = BG3
			card.progressLabel.TextColor3 = MUTED
			card.nameLabel.TextColor3 = MUTED
			card.stroke.Color = MUTED
			card.stroke.Transparency = 0.7
		end
	end

	-- Update category count badges in dropdown
	local catTotal: { [string]: number } = {}
	local catUnlocked: { [string]: number } = {}
	for _, ach in ipairs(AchievementConfig.Achievements) do
		catTotal[ach.category] = (catTotal[ach.category] or 0) + 1
		if achUnlocked[ach.key] then
			catUnlocked[ach.category] = (catUnlocked[ach.category] or 0) + 1
		end
	end
	for cat, lbl in pairs(achCatCountLabels) do
		if cat == "ALL" then
			lbl.Text = unlockedCount .. "/" .. achTotalCount
		else
			lbl.Text = (catUnlocked[cat] or 0) .. "/" .. (catTotal[cat] or 0)
		end
	end
end

-- Close dropdown when clicking on the achievement grid (click-outside dismissal)
achScroll.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		achDropdownPopup.Visible = false
	end
end)

-- Listen for achievement sync from server
if achieveSyncRemote then
	achieveSyncRemote.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then return end
		if type(data.counters) == "table" then achCounters = data.counters end
		if type(data.unlocked) == "table" then achUnlocked = data.unlocked end
		refreshAchievements()
	end)
end

-- Listen for individual unlocks (update local state immediately)
if achieveUnlockedRemote then
	achieveUnlockedRemote.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then return end
		if data.key then
			achUnlocked[data.key] = os.time()
			refreshAchievements()
		end
	end)
end

-- ── State ──────────────────────────────────────────────────────────────────

local isOpen       = false
local selectedSlot = 0  -- which InvSlot_N is selected (0 = none)

-- ── Drag state ─────────────────────────────────────────────────────────────

local DRAG_THRESHOLD  = 8
local isDragging      = false
local dragFromSlot    = 0
local dragStartPos    = Vector2.new(0, 0)
local dragGhost: Frame? = nil
local dragFromCookingOutput    = false
local dragCookingOutputItemId  = ""
local dragFromLootBag          = false
local dragLootBagItemId        = ""
local dragLootBagQty           = 0

local function cleanupDrag()
	isDragging  = false
	dragFromSlot = 0
	dragFromCookingOutput = false
	dragCookingOutputItemId = ""
	dragFromLootBag = false
	dragLootBagItemId = ""
	dragLootBagQty = 0
	if dragGhost then
		dragGhost:Destroy()
		dragGhost = nil
	end
end

local function createDragGhost(itemId: string, mousePos: Vector2): Frame
	local def   = ItemRegistry.get(itemId)
	local ghost = Instance.new("Frame")
	ghost.Size                 = UDim2.new(0, 56, 0, 56)
	ghost.Position             = UDim2.new(0, mousePos.X - 28, 0, mousePos.Y - 28)
	ghost.BackgroundColor3     = BG3
	ghost.BackgroundTransparency = 0.25
	ghost.BorderSizePixel      = 0
	ghost.ZIndex               = 100
	ghost.Parent               = dragOverlay
	addCorner(ghost, 6)

	local ghostStroke = Instance.new("UIStroke")
	ghostStroke.Color     = ACCENT
	ghostStroke.Thickness = 2
	ghostStroke.Parent    = ghost

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
		makeLabel(ghost, {
			Size           = UDim2.new(1, 0, 1, 0),
			Text           = def and def.displayName:sub(1, 3):upper() or "?",
			TextColor3     = MUTED,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font           = FONTB,
			TextSize       = 11,
			ZIndex         = 101,
		})
	end

	return ghost
end

-- Global drag tracking: move ghost, detect drop on release.
UserInputService.InputChanged:Connect(function(input)
	if not isMoveInput(input) then return end

	-- Loot bag drag
	if dragFromLootBag then
		local pos = UserInputService:GetMouseLocation()
		if not isDragging and (pos - dragStartPos).Magnitude > DRAG_THRESHOLD then
			isDragging = true
			dragGhost = createDragGhost(dragLootBagItemId, pos)
		end
		if isDragging and dragGhost then
			dragGhost.Position = UDim2.new(0, pos.X - 28, 0, pos.Y - 28)
		end
		return
	end

	-- Cooking output drag
	if dragFromCookingOutput then
		local pos = UserInputService:GetMouseLocation()
		if not isDragging and (pos - dragStartPos).Magnitude > DRAG_THRESHOLD then
			isDragging = true
			dragGhost = createDragGhost(dragCookingOutputItemId, pos)
		end
		if isDragging and dragGhost then
			dragGhost.Position = UDim2.new(0, pos.X - 28, 0, pos.Y - 28)
		end
		return
	end

	if dragFromSlot == 0 then return end

	local pos = UserInputService:GetMouseLocation()

	if not isDragging and (pos - dragStartPos).Magnitude > DRAG_THRESHOLD then
		local itemId = getSlotItemId(dragFromSlot)
		if itemId ~= "" then
			isDragging = true
			dragGhost  = createDragGhost(itemId, pos)
		else
			dragFromSlot = 0
		end
	end

	if isDragging and dragGhost then
		local pos2 = UserInputService:GetMouseLocation()
		dragGhost.Position = UDim2.new(0, pos2.X - 28, 0, pos2.Y - 28)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not isClickOrTap(input) then return end

	-- Loot bag drag drop
	if dragFromLootBag then
		local wasDragging = isDragging
		local itemId = dragLootBagItemId
		local qty = dragLootBagQty
		cleanupDrag()
		if wasDragging then
			local hudGui = player.PlayerGui:FindFirstChild("GameplayHud")
			local bagPanel = hudGui and hudGui:FindFirstChild("LootBagPanel")
			local bagRef = bagPanel and bagPanel:FindFirstChild("ActiveBag")
			local bagModel = bagRef and (bagRef :: ObjectValue).Value
			if bagModel and itemId ~= "" and qty > 0 then
				takeLootBagItemRemote:FireServer(bagModel, itemId, qty)
			end
		end
		return
	end

	-- Cooking output drag drop
	if dragFromCookingOutput then
		local wasDragging = isDragging
		cleanupDrag()
		if wasDragging then
			local hud = player.PlayerGui:FindFirstChild("GameplayHud")
			local cookPanel = hud and hud:FindFirstChild("CookingPanel")
			local campfireRef = cookPanel and cookPanel:FindFirstChild("ActiveCampfire")
			local campfireModel = campfireRef and (campfireRef :: ObjectValue).Value
			local outputSlot = cookPanel and cookPanel:FindFirstChild("OutputSlot")
			local qtyLabel = outputSlot and outputSlot:FindFirstChild("Qty")
			if campfireModel and qtyLabel then
				local qty = tonumber((qtyLabel :: TextLabel).Text) or 0
				if qty > 0 then
					campfireTakeRemote:FireServer(campfireModel, "output", qty)
				end
			end
		end
		return
	end

	if dragFromSlot == 0 then return end

	local fromSlot          = dragFromSlot
	local wasActuallyDragging = isDragging
	cleanupDrag()

	if not wasActuallyDragging then return end

	local pos = Vector2.new(input.Position.X, input.Position.Y)

	-- Find which inventory slot the cursor is over.
	local targetSlot = 0
	for _, child in ipairs(gridScroll:GetChildren()) do
		if child:IsA("ImageButton") then
			local ap = child.AbsolutePosition
			local as = child.AbsoluteSize
			if pos.X >= ap.X and pos.X <= ap.X + as.X
				and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y
			then
				local lo = child.LayoutOrder
				if lo >= 1 and lo <= getMaxSlots() then
					targetSlot = lo
					break
				end
			end
		end
	end

	if targetSlot > 0 and targetSlot ~= fromSlot then
		-- Drag to another inventory slot → swap.
		swapSlotsRemote:FireServer(fromSlot, targetSlot)
	elseif targetSlot == 0 then
		-- Check if dropped on a hotbar slot (lives in a different ScreenGui).
		local hud        = player.PlayerGui:FindFirstChild("GameplayHud")
		local hotbarRoot = hud and hud:FindFirstChild("HotbarRoot")
		local pinned     = false

		if hotbarRoot then
			for slotNum = 1, 9 do
				local slotFrame = hotbarRoot:FindFirstChild("Slot" .. slotNum)
				if slotFrame then
					local ap = slotFrame.AbsolutePosition
					local as = slotFrame.AbsoluteSize
					if pos.X >= ap.X and pos.X <= ap.X + as.X
						and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y
					then
						local itemId = getSlotItemId(fromSlot)
						if itemId ~= "" then
							pinToSpecificSlotRemote:FireServer(itemId, slotNum)
						end
						pinned = true
						break
					end
				end
			end
		end

		-- Check if dropped on campfire input slot.
		if not pinned then
			local cookPanel = hud and hud:FindFirstChild("CookingPanel")
			if cookPanel and cookPanel.Visible then
				local inputSlot = cookPanel:FindFirstChild("InputSlot")
				if inputSlot then
					local ap = inputSlot.AbsolutePosition
					local as = inputSlot.AbsoluteSize
					if pos.X >= ap.X and pos.X <= ap.X + as.X
						and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y
					then
						local campfireRef = cookPanel:FindFirstChild("ActiveCampfire")
						local campfireModel = campfireRef and campfireRef.Value
						if campfireModel then
							local itemId = getSlotItemId(fromSlot)
							local qty    = getSlotQty(fromSlot)
							if itemId ~= "" and qty > 0 then
								campfireAddRemote:FireServer(campfireModel, itemId, qty)
								pinned = true
							end
						end
					end
				end
			end
		end

		-- Check if dropped on trade panel "YOUR OFFER" area.
		if not pinned then
			local tradeP = hud and hud:FindFirstChild("TradePanel")
			if tradeP and tradeP.Visible then
				local myOfferScroll = tradeP:FindFirstChild("MyOfferScroll")
				if myOfferScroll then
					local ap = myOfferScroll.AbsolutePosition
					local as = myOfferScroll.AbsoluteSize
					if pos.X >= ap.X and pos.X <= ap.X + as.X
						and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y
					then
						local itemId = getSlotItemId(fromSlot)
						local qty    = getSlotQty(fromSlot)
						if itemId ~= "" and qty > 0 then
							if qty == 1 then
								tradeUpdateOfferRemote:FireServer(itemId, 1, "add")
							else
								showTradeQtyPicker(itemId, qty, function(selectedQty)
									tradeUpdateOfferRemote:FireServer(itemId, selectedQty, "add")
								end)
							end
							pinned = true
						end
					end
				end
			end
		end

		-- Check if dropped on another player's character → initiate trade.
		if not pinned then
			local camera = workspace.CurrentCamera
			if camera then
				local targetPlayer: Player? = nil

				-- Primary: raycast onto character mesh
				local ray = camera:ViewportPointToRay(pos.X, pos.Y)
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { player.Character }
				local result = workspace:Raycast(ray.Origin, ray.Direction * 50, params)
				if result and result.Instance then
					local model = result.Instance:FindFirstAncestorWhichIsA("Model")
					if model then
						targetPlayer = Players:GetPlayerFromCharacter(model)
					end
				end

				-- Fallback: check if drop is near any player's screen position (helps with mesh avatars)
				if not targetPlayer then
					local SCREEN_TOLERANCE = 80 -- pixels
					local bestDist = SCREEN_TOLERANCE
					for _, p in ipairs(Players:GetPlayers()) do
						if p == player then continue end
						local char = p.Character
						local root = char and char:FindFirstChild("HumanoidRootPart")
						if root then
							local screenPos, onScreen = camera:WorldToViewportPoint(root.Position)
							if onScreen then
								local dx = pos.X - screenPos.X
								local dy = pos.Y - screenPos.Y
								local dist = math.sqrt(dx * dx + dy * dy)
								if dist < bestDist then
									bestDist = dist
									targetPlayer = p
								end
							end
						end
					end
				end

				if targetPlayer and targetPlayer ~= player then
					local itemId = getSlotItemId(fromSlot)
					local qty    = getSlotQty(fromSlot)
					if itemId ~= "" and qty > 0 then
						if qty == 1 then
							tradeInitiateRemote:FireServer(targetPlayer.UserId, itemId, 1)
						else
							local capturedTarget = targetPlayer
							showTradeQtyPicker(itemId, qty, function(selectedQty)
								tradeInitiateRemote:FireServer(capturedTarget.UserId, itemId, selectedQty)
							end)
						end
						pinned = true
					end
				end
			end
		end

		if not pinned then
			-- Dragged outside everything → drop entire stack to world.
			local itemId = getSlotItemId(fromSlot)
			if itemId ~= "" then
				dropItemRemote:FireServer(fromSlot, getSlotQty(fromSlot))
			end
		end
	end
end)

-- ── Inventory slot readers ─────────────────────────────────────────────────

function getMaxSlots(): number
	return math.max(1, math.floor(tonumber(player:GetAttribute("MaxInvSlots")) or 5))
end

function getSlotItemId(n: number): string
	local v = player:GetAttribute("InvSlot_" .. n)
	return type(v) == "string" and v or ""
end

function getSlotQty(n: number): number
	return math.max(0, math.floor(tonumber(player:GetAttribute("InvQty_" .. n)) or 0))
end

-- Sum qty across all slots for a given itemId (used by craft list).
local function getTotalQty(itemId: string): number
	local total = 0
	local maxSlots = getMaxSlots()
	for n = 1, maxSlots do
		if getSlotItemId(n) == itemId then
			total += getSlotQty(n)
		end
	end
	return total
end

-- ── Refresh functions ─────────────────────────────────────────────────────

-- Updates the detail strip for the given slot (0 = deselect).
local function selectSlot(n: number)
	selectedSlot = n
	splitOverlay.Visible = false

	if n == 0 then
		detailIcon.Image        = ""
		detailName.Text         = "Select an item"
		detailName.TextColor3   = MUTED
		detailDesc.Text         = ""
		detailSlotLabel.Text    = ""
		detailUseBtn.Visible    = false
		detailEquipBtn.Visible  = false
		detailHotbarBtn.Visible = false
		detailSplitBtn.Visible  = false
		detailDropBtn.Visible   = false
		return
	end

	local itemId = getSlotItemId(n)
	local qty    = getSlotQty(n)
	local def    = itemId ~= "" and ItemRegistry.get(itemId) or nil

	if not def or itemId == "" then
		selectSlot(0)
		return
	end

	detailIcon.Image        = def.icon ~= "" and def.icon or ""
	detailName.Text         = def.displayName .. "  x" .. qty
	detailName.TextColor3   = TEXT
	detailDesc.Text         = def.description

	-- Build slot label with optional durability info
	local slotText = "Slot " .. n .. " of " .. getMaxSlots()
	if def.durabilityMax then
		local durStr = player:GetAttribute("InvDurability_" .. n)
		if type(durStr) == "string" and durStr ~= "" then
			local firstDur = tonumber(string.match(durStr, "^([^,]+)"))
			if firstDur then
				slotText = slotText .. "   |   Durability: " .. tostring(math.floor(firstDur)) .. "/" .. tostring(def.durabilityMax)
			end
		end
	end
	detailSlotLabel.Text    = slotText

	local isConsumable      = def.onConsume ~= nil
	local isPlaceable       = def.category == "placeable"
	local isTool            = def.category == "tool" or def.category == "weapon"
	local isBackpack        = def.backpack ~= nil
	local isQuiver          = def.equipment ~= nil and def.equipment.slot == "Quiver"
	local isEquippable      = isBackpack or isQuiver
	local hasEquippedBP     = (player:GetAttribute("EquipSlot_Backpack") or "") ~= ""
	local hasEquippedQuiver = (player:GetAttribute("EquipSlot_Quiver") or "") ~= ""
	detailUseBtn.Visible    = isConsumable or isPlaceable
	detailUseBtn.Text       = isPlaceable and "PLACE" or "USE"
	detailEquipBtn.Visible  = isEquippable
	local alreadyEquipped = (isBackpack and hasEquippedBP) or (isQuiver and hasEquippedQuiver)
	if alreadyEquipped then
		detailEquipBtn.Text             = "EQUIPPED"
		detailEquipBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		detailEquipBtn.TextColor3       = MUTED
	else
		detailEquipBtn.Text             = "EQUIP"
		detailEquipBtn.BackgroundColor3 = Color3.fromRGB(30, 60, 80)
		detailEquipBtn.TextColor3       = ACCENT
	end
	detailHotbarBtn.Visible = isTool or isConsumable or isPlaceable
	detailSplitBtn.Visible  = qty > 1
	detailDropBtn.Visible   = true
end

detailUseBtn.Activated:Connect(function()
	local itemId = getSlotItemId(selectedSlot)
	if itemId == "" then return end
	local def = ItemRegistry.get(itemId)
	if not def then return end

	if def.category == "placeable" then
		startPlacementEvent:Fire(itemId)
		setOpen(false)
		return
	end

	if def.onConsume then
		useItemRemote:FireServer(itemId)
		if not ItemRegistry.hasTag(def, "drink") then
			chewingSound:Play()
			task.delay(1.5, function()
				chewingSound:Stop()
			end)
		end
	end
end)

detailEquipBtn.Activated:Connect(function()
	if selectedSlot == 0 then return end
	local itemId = getSlotItemId(selectedSlot)
	if itemId == "" then return end
	local def = ItemRegistry.get(itemId)
	if not def then return end

	if def.backpack then
		local current = player:GetAttribute("EquipSlot_Backpack") or ""
		if current ~= "" then return end
		equipBackpackRemote:FireServer(selectedSlot)
	elseif def.equipment and def.equipment.slot == "Quiver" then
		local current = player:GetAttribute("EquipSlot_Quiver") or ""
		if current ~= "" then return end
		equipQuiverRemote:FireServer(selectedSlot)
	end
	selectSlot(0)
end)

detailHotbarBtn.Activated:Connect(function()
	local itemId = getSlotItemId(selectedSlot)
	if itemId ~= "" then
		pinToHotbarRemote:FireServer(itemId)
	end
end)

detailSplitBtn.Activated:Connect(function()
	if selectedSlot == 0 then return end
	splitBox.Text        = ""
	splitOverlay.Visible = true
	splitBox:CaptureFocus()
end)

detailDropBtn.Activated:Connect(function()
	if selectedSlot == 0 then return end
	local itemId = getSlotItemId(selectedSlot)
	local qty    = getSlotQty(selectedSlot)
	if itemId ~= "" and qty > 0 then
		dropItemRemote:FireServer(selectedSlot, qty)
		selectSlot(0)
	end
end)

splitCancelBtn.Activated:Connect(function()
	splitOverlay.Visible = false
end)

splitConfirmBtn.Activated:Connect(function()
	local qty      = getSlotQty(selectedSlot)
	local splitQty = math.floor(tonumber(splitBox.Text) or 0)
	if splitQty >= 1 and splitQty < qty then
		splitStackRemote:FireServer(selectedSlot, splitQty)
	end
	splitOverlay.Visible = false
end)

local function refreshItemList()
	clearSlots(gridScroll)
	selectSlot(0)

	local maxSlots = getMaxSlots()

	for n = 1, maxSlots do
		local itemId = getSlotItemId(n)
		local qty    = getSlotQty(n)

		local slot = Instance.new("ImageButton")
		slot.LayoutOrder      = n
		slot.Size             = UDim2.new(0, 64, 0, 64)
		slot.BackgroundColor3 = itemId ~= "" and BG3 or Color3.fromRGB(25, 28, 40)
		slot.BorderSizePixel  = 0
		slot.Image            = ""
		slot.ScaleType        = Enum.ScaleType.Fit
		slot.Parent           = gridScroll
		addCorner(slot, 6)

		local stroke = Instance.new("UIStroke")
		stroke.Color     = Color3.fromRGB(40, 47, 68)
		stroke.Thickness = 1
		stroke.Parent    = slot

		if itemId ~= "" then
			local def     = ItemRegistry.get(itemId)
			local hasIcon = def ~= nil and def.icon ~= ""

			if hasIcon then
				slot.Image = def.icon
			else
				makeLabel(slot, {
					Size           = UDim2.new(1, 0, 0.6, 0),
					Position       = UDim2.new(0, 0, 0.2, 0),
					Text           = def and def.displayName:sub(1, 3):upper() or "?",
					TextColor3     = MUTED,
					TextXAlignment = Enum.TextXAlignment.Center,
					Font           = FONTB,
					TextSize       = 11,
				})
			end

			-- Stack count badge
			if qty > 1 then
				local qtyLbl = Instance.new("TextLabel")
				qtyLbl.Size               = UDim2.new(1, -4, 0, 14)
				qtyLbl.Position           = UDim2.new(0, 0, 1, -16)
				qtyLbl.BackgroundTransparency = 1
				qtyLbl.Text               = tostring(qty)
				qtyLbl.TextColor3         = TEXT
				qtyLbl.Font               = FONTB
				qtyLbl.TextSize           = 11
				qtyLbl.TextXAlignment     = Enum.TextXAlignment.Right
				qtyLbl.ZIndex             = slot.ZIndex + 1
				qtyLbl.Parent             = slot
			end

			-- Weight badge (bottom-left)
			if def and def.weight and def.weight > 0 then
				local totalWeight = def.weight * qty
				local weightLbl = Instance.new("TextLabel")
				weightLbl.Size               = UDim2.new(1, -4, 0, 14)
				weightLbl.Position           = UDim2.new(0, 2, 1, -16)
				weightLbl.BackgroundTransparency = 1
				weightLbl.Text               = string.format("%.1fkg", totalWeight)
				weightLbl.TextColor3         = MUTED
				weightLbl.Font               = FONT
				weightLbl.TextSize           = 9
				weightLbl.TextXAlignment     = Enum.TextXAlignment.Left
				weightLbl.ZIndex             = slot.ZIndex + 1
				weightLbl.Parent             = slot
			end

			-- Spoil bar (thin bar at bottom for perishable items)
			if def and def.perishSeconds then
				local expiryStr = player:GetAttribute("InvExpires_" .. n)
				if expiryStr and expiryStr ~= "" then
					local earliest = math.huge
					for ts in string.gmatch(expiryStr, "[^,]+") do
						local t = tonumber(ts)
						if t and t < earliest then earliest = t end
					end
					if earliest < math.huge then
						local now = os.time()
						local remaining = math.max(0, earliest - now)
						local ratio = math.clamp(remaining / def.perishSeconds, 0, 1)
						-- Green → Yellow → Red
						local barColor = Color3.fromRGB(
							math.floor(255 * math.clamp((1 - ratio) * 2, 0, 1)),
							math.floor(255 * math.clamp(ratio * 2, 0, 1)),
							0
						)

						local barBg = Instance.new("Frame")
						barBg.Name                  = "SpoilBarBg"
						barBg.Size                  = UDim2.new(1, -6, 0, 3)
						barBg.Position              = UDim2.new(0, 3, 1, -5)
						barBg.BackgroundColor3      = Color3.fromRGB(20, 20, 20)
						barBg.BorderSizePixel       = 0
						barBg.ZIndex                = slot.ZIndex + 2
						barBg.Parent                = slot
						addCorner(barBg, 2)

						local barFill = Instance.new("Frame")
						barFill.Name                = "SpoilBarFill"
						barFill.Size                = UDim2.new(ratio, 0, 1, 0)
						barFill.BackgroundColor3    = barColor
						barFill.BorderSizePixel     = 0
						barFill.ZIndex              = slot.ZIndex + 3
						barFill.Parent              = barBg
						addCorner(barFill, 2)
					end
				end
			end

			-- Durability bar (thin bar at bottom for durable items)
			if def and def.durabilityMax then
				local durStr = player:GetAttribute("InvDurability_" .. n)
				if type(durStr) == "string" and durStr ~= "" then
					local firstDur = tonumber(string.match(durStr, "^([^,]+)"))
					if firstDur then
						local ratio = math.clamp(firstDur / def.durabilityMax, 0, 1)
						local r = math.floor(255 * math.clamp((1 - ratio) * 2, 0, 1))
						local g = math.floor(255 * math.clamp(ratio * 2, 0, 1))

						local durBg = Instance.new("Frame")
						durBg.Name                  = "DurBarBg"
						durBg.Size                  = UDim2.new(1, -6, 0, 3)
						durBg.Position              = UDim2.new(0, 3, 1, -5)
						durBg.BackgroundColor3      = Color3.fromRGB(20, 20, 20)
						durBg.BorderSizePixel       = 0
						durBg.ZIndex                = slot.ZIndex + 2
						durBg.Parent                = slot
						addCorner(durBg, 2)

						local durFill = Instance.new("Frame")
						durFill.Name                = "DurBarFill"
						durFill.Size                = UDim2.new(ratio, 0, 1, 0)
						durFill.BackgroundColor3    = Color3.fromRGB(r, g, 0)
						durFill.BorderSizePixel     = 0
						durFill.ZIndex              = slot.ZIndex + 3
						durFill.Parent              = durBg
						addCorner(durFill, 2)
					end
				end
			end
		else
			-- Slot number label for empty slots
			makeLabel(slot, {
				Size           = UDim2.new(1, 0, 1, 0),
				Text           = tostring(n),
				TextColor3     = Color3.fromRGB(40, 47, 68),
				TextXAlignment = Enum.TextXAlignment.Center,
				Font           = FONTB,
				TextSize       = 18,
			})
		end

		local capturedN = n

		-- Click to select; drag to swap or drop.
		slot.Activated:Connect(function()
			if isDragging then return end  -- activated can fire on drag end; ignore it
			-- Clear all selection highlights
			for _, child in ipairs(gridScroll:GetChildren()) do
				if child:IsA("ImageButton") then
					local s = child:FindFirstChildOfClass("UIStroke")
					if s then s.Color = Color3.fromRGB(40, 47, 68); s.Thickness = 1 end
				end
			end
			if getSlotItemId(capturedN) ~= "" then
				stroke.Color     = ACCENT
				stroke.Thickness = 2
				selectSlot(capturedN)
			else
				selectSlot(0)
			end
		end)

		-- Start of potential drag.
		slot.InputBegan:Connect(function(input)
			if not isClickOrTap(input) then return end
			if getSlotItemId(capturedN) == "" then return end
			dragFromSlot = capturedN
			dragStartPos = UserInputService:GetMouseLocation()
		end)

		-- Tooltip registration
		if itemId ~= "" then
			local tooltipData: any = { kind = "item", itemId = itemId, qty = qty }
			local def2 = ItemRegistry.get(itemId)
			if def2 and def2.durabilityMax then
				local durStr = player:GetAttribute("InvDurability_" .. n)
				if type(durStr) == "string" and durStr ~= "" then
					local firstDur = tonumber(string.match(durStr, "^([^,]+)"))
					if firstDur then
						tooltipData.durability = firstDur
						tooltipData.durabilityMax = def2.durabilityMax
					end
				end
			end
			if def2 and def2.perishSeconds then
				local expiryStr = player:GetAttribute("InvExpires_" .. n)
				if expiryStr and expiryStr ~= "" then
					local earliest = math.huge
					for ts in string.gmatch(expiryStr, "[^,]+") do
						local t = tonumber(ts)
						if t and t < earliest then earliest = t end
					end
					if earliest < math.huge then
						tooltipData.expiresIn = math.max(0, earliest - os.time())
					end
				end
			end
			TooltipModule.register(slot, tooltipData)
		end
	end
end

local function refreshWeight()
	local current = tonumber(player:GetAttribute("CarryWeight"))    or 0
	local max     = tonumber(player:GetAttribute("MaxCarryWeight")) or 5
	weightLabel.Text = string.format("Weight: %.2f / %.2f kg", current, max)
	local ratio = max > 0 and math.clamp(current / max, 0, 1.5) or 0
	wBar.Size             = UDim2.new(math.min(ratio, 1), 0, 1, 0)
	wBar.BackgroundColor3 = ratio > 1.0 and Color3.fromRGB(200, 50, 50)
		or ratio > 0.8 and BAD
		or ACCENT
end

local function refreshCharacter()
	for slotId, ref in pairs(slotRefs) do
		local raw: any
		if slotId == "MainHand" then
			local equippedSlot = tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0
			if equippedSlot >= 1 and equippedSlot <= 9 then
				raw = player:GetAttribute("HotbarSlot" .. equippedSlot)
			end
		else
			raw = player:GetAttribute("EquipSlot_" .. slotId)
		end

		local itemId = type(raw) == "string" and raw or ""
		if itemId ~= "" then
			local def = ItemRegistry.get(itemId)
			ref.valLabel.Text      = def and def.displayName or itemId
			ref.valLabel.TextColor3 = TEXT
		else
			ref.valLabel.Text      = "--"
			ref.valLabel.TextColor3 = MUTED
		end
	end

	for statId, ref in pairs(statRefs) do
		local val = tonumber(player:GetAttribute("Stat_" .. statId)) or 0
		ref.valLabel.Text = tostring(math.floor(val))
	end
end

refreshRecipeBook = function()
	for i, rowData in ipairs(recipeRows) do
		local recipe = allRecipes[i]

		-- Filter visibility
		rowData.row.Visible = (recipeFilter == "all") or (recipeFilter == recipe.station)

		if recipe.station == "hand" and recipe.ingredients then
			-- Hand-craft: show ingredient availability + CRAFT button
			local canCraft = true
			local parts: { string } = {}

			for _, ing in ipairs(recipe.ingredients) do
				local have    = getTotalQty(ing.itemId)
				local ingDef  = ItemRegistry.get(ing.itemId)
				local ingName = ingDef and ingDef.displayName or ing.itemId
				local enough  = have >= ing.qty
				if not enough then canCraft = false end
				local marker = enough and "[ok]" or "[need]"
				table.insert(parts, string.format("%dx %s %s", ing.qty, ingName, marker))
			end

			rowData.ingLabel.Text = table.concat(parts, "   ")
			if rowData.craftBtn then
				rowData.craftBtn.BackgroundColor3 = canCraft and ACCENT or Color3.fromRGB(45, 50, 70)
				rowData.craftBtn.TextColor3       = canCraft and TEXT   or MUTED
				rowData.craftBtn.Active           = canCraft
			end
		else
			-- Station recipe: input → output + cook time
			local inputDef  = ItemRegistry.get(recipe.inputId or "")
			local outputDef = ItemRegistry.get(recipe.output.itemId)
			local inputName  = inputDef and inputDef.displayName or (recipe.inputId or "?")
			local outputName = outputDef and outputDef.displayName or recipe.output.itemId
			local cookTime   = recipe.cookSeconds or 4
			rowData.ingLabel.Text = string.format(
				"1x %s → 1x %s (%ds)", inputName, outputName, cookTime
			)
		end
	end
end

local function refreshAll()
	refreshItemList()
	refreshWeight()
	refreshRecipeBook()
	refreshCharacter()
end

-- ── Tab switching ─────────────────────────────────────────────────────────

local function setTab(tab: string)
	itemsPane.Visible      = tab == "items"
	craftPane.Visible      = tab == "craft"
	charPane.Visible       = tab == "char"
	achPane.Visible        = tab == "achieve"
	itemsTabBtn.TextColor3 = tab == "items"   and TEXT or MUTED
	craftTabBtn.TextColor3 = tab == "craft"   and TEXT or MUTED
	charTabBtn.TextColor3  = tab == "char"    and TEXT or MUTED
	achTabBtn.TextColor3   = tab == "achieve" and TEXT or MUTED
	itemsTabBtn.BackgroundColor3 = tab == "items"   and BG3 or BG2
	craftTabBtn.BackgroundColor3 = tab == "craft"   and BG3 or BG2
	charTabBtn.BackgroundColor3  = tab == "char"    and BG3 or BG2
	achTabBtn.BackgroundColor3   = tab == "achieve" and BG3 or BG2
	if tab == "char" then refreshCharacter() end
	if tab == "achieve" then
		if achieveRequestRemote then achieveRequestRemote:FireServer() end
		refreshAchievements()
	end
end

setTab("items")

itemsTabBtn.Activated:Connect(function() setTab("items") end)
craftTabBtn.Activated:Connect(function() setTab("craft") end)
charTabBtn.Activated:Connect(function() setTab("char") end)
achTabBtn.Activated:Connect(function() setTab("achieve") end)

-- Hover effects on tab buttons
local TAB_HOVER = Color3.fromRGB(52, 58, 78)
for _, btn in ipairs({ itemsTabBtn, craftTabBtn, charTabBtn, achTabBtn }) do
	btn.MouseEnter:Connect(function()
		if btn.BackgroundColor3 ~= BG3 then -- not active tab
			btn.BackgroundColor3 = TAB_HOVER
		end
	end)
	btn.MouseLeave:Connect(function()
		if btn.BackgroundColor3 == TAB_HOVER then
			btn.BackgroundColor3 = BG2
		end
	end)
end

-- ── Open / close ──────────────────────────────────────────────────────────

setOpen = function(open: boolean)
	isOpen        = open
	panel.Visible = open
	if open then
		clampPanelPosition()
		refreshAll()
	else
		cancelCraft()
	end
end

closeBtn.Activated:Connect(function() setOpen(false) end)
bagBtn.Activated:Connect(function() setOpen(not isOpen) end)

ContextActionService:BindActionAtPriority(
	"ToggleInventory",
	function(_name, state, _obj)
		if state == Enum.UserInputState.Begin then
			setOpen(not isOpen)
		end
		return Enum.ContextActionResult.Sink
	end,
	false,
	Enum.ContextActionPriority.High.Value,
	Enum.KeyCode.I
)

-- ── Reactive attribute updates ────────────────────────────────────────────

player.AttributeChanged:Connect(function(attrName: string)
	if not isOpen then return end

	if attrName:sub(1, 8) == "InvSlot_"
		or attrName:sub(1, 7) == "InvQty_"
		or attrName:sub(1, 11) == "InvExpires_"
		or attrName == "CarryWeight"
		or attrName == "MaxCarryWeight"
		or attrName == "MaxInvSlots"
	then
		refreshItemList()
		refreshWeight()
		refreshRecipeBook()
	elseif attrName == "HotbarEquippedSlot"
		or attrName:sub(1, 10) == "HotbarSlot"
	then
		refreshCharacter()
	elseif attrName:sub(1, 5) == "Stat_"
		or attrName:sub(1, 10) == "EquipSlot_"
	then
		refreshCharacter()
	end
end)

-- ── Cooking output slot drag support ─────────────────────────────────────
-- Wire up drag-start on the OutputSlot once the CookingPanel is built.

local outputSlotWired = false

local function wireOutputSlotDrag()
	if outputSlotWired then return end
	local hud = player.PlayerGui:FindFirstChild("GameplayHud")
	local cookPanel = hud and hud:FindFirstChild("CookingPanel")
	local outputSlot = cookPanel and cookPanel:FindFirstChild("OutputSlot")
	if not outputSlot then return end

	outputSlotWired = true
	outputSlot.InputBegan:Connect(function(input)
		if not isClickOrTap(input) then return end
		local itemId = outputSlot:GetAttribute("_ItemId")
		if not itemId or itemId == "" then return end
		dragFromCookingOutput = true
		dragCookingOutputItemId = itemId
		dragFromSlot = 0
		dragStartPos = UserInputService:GetMouseLocation()
	end)
end

task.spawn(function()
	while not outputSlotWired do
		wireOutputSlotDrag()
		task.wait(1)
	end
end)

-- ── Loot bag slot drag support ──────────────────────────────────────────
-- Wire drag-start on loot bag item slots. The LootBagPanel is built on demand,
-- so we watch for new TextButton children inside its ItemScroll.

local lootBagPanelWired = false

local function wireLootBagSlotDrag(btn: TextButton)
	btn.InputBegan:Connect(function(input)
		if not isClickOrTap(input) then return end
		local itemId = btn:GetAttribute("_LootItemId")
		local qty = btn:GetAttribute("_LootQty")
		if not itemId or itemId == "" then return end
		dragFromLootBag = true
		dragLootBagItemId = itemId
		dragLootBagQty = tonumber(qty) or 0
		dragFromSlot = 0
		dragStartPos = UserInputService:GetMouseLocation()
	end)
end

local function wireLootBagPanel()
	if lootBagPanelWired then return end
	local hudGui = player.PlayerGui:FindFirstChild("GameplayHud")
	local bagPanel = hudGui and hudGui:FindFirstChild("LootBagPanel")
	local scroll = bagPanel and bagPanel:FindFirstChild("ItemScroll")
	if not scroll then return end

	lootBagPanelWired = true

	-- Wire existing slots
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("TextButton") then
			wireLootBagSlotDrag(child)
		end
	end

	-- Wire future slots (panel rebuilds on each state update)
	scroll.ChildAdded:Connect(function(child)
		if child:IsA("TextButton") then
			wireLootBagSlotDrag(child)
		end
	end)
end

task.spawn(function()
	while not lootBagPanelWired do
		wireLootBagPanel()
		task.wait(1)
	end
end)

-- ── Craft-failed notification ────────────────────────────────────────────

craftFailedRemote.OnClientEvent:Connect(function(reason: string)
	local character = player.Character
	if not character then return end
	local head = character:FindFirstChild("Head")
	if not head then return end

	local bb = Instance.new("BillboardGui")
	bb.Name              = "CraftFailNotify"
	bb.Adornee           = head
	bb.Size              = UDim2.new(0, 200, 0, 30)
	bb.StudsOffset       = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop       = true
	bb.Parent            = player.PlayerGui

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text                   = reason or "Craft failed!"
	label.TextColor3             = Color3.fromRGB(255, 80, 80)
	label.Font                   = Enum.Font.GothamBold
	label.TextSize               = 14
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	label.Parent                 = bb

	task.delay(2, function()
		if bb.Parent then bb:Destroy() end
	end)
end)
