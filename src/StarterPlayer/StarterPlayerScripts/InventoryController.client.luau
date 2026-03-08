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
local CookingConfig  = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CookingConfig"))

-- Chewing sound for food consumption from inventory UI
local chewingSound = Instance.new("Sound")
chewingSound.Name = "InvChewingSound"
chewingSound.SoundId = AssetIds.Sounds.Chewing
chewingSound.Looped = true
chewingSound.Volume = 0.5
chewingSound.Parent = SoundService

local remotes               = ReplicatedStorage:WaitForChild("Remotes")
local useItemRemote         = remotes:WaitForChild("UseItem")            :: RemoteEvent
local craftItemRemote       = remotes:WaitForChild("CraftItem")          :: RemoteEvent
local pinToHotbarRemote     = remotes:WaitForChild("PinToHotbar")        :: RemoteEvent
local splitStackRemote      = remotes:WaitForChild("SplitStack")         :: RemoteEvent
local swapSlotsRemote       = remotes:WaitForChild("SwapSlots")          :: RemoteEvent
local dropItemRemote        = remotes:WaitForChild("DropItem")           :: RemoteEvent
local pinToSpecificSlotRemote = remotes:WaitForChild("PinToSpecificSlot") :: RemoteEvent
local campfireAddRemote     = remotes:WaitForChild("CampfireAddItem")    :: RemoteEvent

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
bagBtn.Image             = ""
bagBtn.Parent            = gui
addCorner(bagBtn, 10)

local bagStroke = Instance.new("UIStroke")
bagStroke.Color     = Color3.fromRGB(55, 65, 95)
bagStroke.Thickness = 1
bagStroke.Parent    = bagBtn

local bagLabel = Instance.new("TextLabel")
bagLabel.Size               = UDim2.new(1, 0, 1, 0)
bagLabel.BackgroundTransparency = 1
bagLabel.Text               = "BAG"
bagLabel.TextColor3         = TEXT
bagLabel.Font               = Enum.Font.GothamBold
bagLabel.TextSize           = 13
bagLabel.Parent             = bagBtn

-- Main panel (centered)
local panel = Instance.new("Frame")
panel.Name            = "Panel"
panel.Size            = UDim2.new(0, PW, 0, PH)
panel.Position        = UDim2.new(0.5, -PW / 2, 0.5, -PH / 2)
panel.BackgroundColor3 = BG
panel.BorderSizePixel = 0
panel.Visible         = false
panel.Parent          = gui
addCorner(panel, 8)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color     = Color3.fromRGB(55, 65, 95)
panelStroke.Thickness = 1
panelStroke.Parent    = panel

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
		panelDragging = false
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
		Size             = UDim2.new(0, 100, 1, 0),
		Position         = UDim2.new(0, xOff, 0, 0),
		BackgroundColor3 = BG2,
		Text             = label,
		TextColor3       = MUTED,
		TextSize         = 12,
	})
	addCorner(b, 6)
	return b
end

local itemsTabBtn = makeTabBtn("ITEMS",     0)
local craftTabBtn = makeTabBtn("RECIPES", 104)
local charTabBtn  = makeTabBtn("CHARACTER", 208)

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
	Position         = UDim2.new(1, -268, 0.5, -13),
	BackgroundColor3 = Color3.fromRGB(45, 80, 45),
	Text             = "USE",
	TextColor3       = OK,
	TextSize         = 12,
	Visible          = false,
})
addCorner(detailUseBtn, 5)

local detailHotbarBtn = makeButton(detailStrip, {
	Size             = UDim2.new(0, 84, 0, 26),
	Position         = UDim2.new(1, -216, 0.5, -13),
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
			craftItemRemote:FireServer(capturedId)
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
	{ "MainHand",   "Main Hand",  "OffHand",  "Off Hand"  },
	{ "CoinPouch",  "Coin Pouch", "Backpack", "Backpack"  },
}

local SLOT_W, SLOT_H, SLOT_GAP = 118, 40, 6

type SlotRef = { nameLabel: TextLabel, valLabel: TextLabel }
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
	slotRefs[slotId] = { nameLabel = nameLabel, valLabel = valLabel }
end

for row, pair in ipairs(SLOT_PAIRS) do
	local yOff = 20 + (row - 1) * (SLOT_H + SLOT_GAP)
	makeSlotBox(equipSection, pair[1], pair[2], 0,          yOff)
	makeSlotBox(equipSection, pair[3], pair[4], SLOT_W + 8, yOff)
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

-- ── State ──────────────────────────────────────────────────────────────────

local isOpen       = false
local selectedSlot = 0  -- which InvSlot_N is selected (0 = none)

-- ── Drag state ─────────────────────────────────────────────────────────────

local DRAG_THRESHOLD  = 8
local isDragging      = false
local dragFromSlot    = 0
local dragStartPos    = Vector2.new(0, 0)
local dragGhost: Frame? = nil

local function cleanupDrag()
	isDragging  = false
	dragFromSlot = 0
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
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
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
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
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
	detailSlotLabel.Text    = "Slot " .. n .. " of " .. getMaxSlots()

	local isConsumable      = def.onConsume ~= nil
	local isPlaceable       = def.category == "placeable"
	local isTool            = def.category == "tool" or def.category == "weapon"
	detailUseBtn.Visible    = isConsumable or isPlaceable
	detailUseBtn.Text       = isPlaceable and "PLACE" or "USE"
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
		panel.Visible = false
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
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			if getSlotItemId(capturedN) == "" then return end
			dragFromSlot = capturedN
			dragStartPos = UserInputService:GetMouseLocation()
		end)
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
	itemsTabBtn.TextColor3 = tab == "items" and TEXT or MUTED
	craftTabBtn.TextColor3 = tab == "craft" and TEXT or MUTED
	charTabBtn.TextColor3  = tab == "char"  and TEXT or MUTED
	itemsTabBtn.BackgroundColor3 = tab == "items" and BG3 or BG2
	craftTabBtn.BackgroundColor3 = tab == "craft" and BG3 or BG2
	charTabBtn.BackgroundColor3  = tab == "char"  and BG3 or BG2
	if tab == "char" then refreshCharacter() end
end

setTab("items")

itemsTabBtn.Activated:Connect(function() setTab("items") end)
craftTabBtn.Activated:Connect(function() setTab("craft") end)
charTabBtn.Activated:Connect(function() setTab("char") end)

-- ── Open / close ──────────────────────────────────────────────────────────

local function setOpen(open: boolean)
	isOpen        = open
	panel.Visible = open
	if open then
		refreshAll()
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

	if attrName:sub(1, 9) == "InvSlot_"
		or attrName:sub(1, 7) == "InvQty_"
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
