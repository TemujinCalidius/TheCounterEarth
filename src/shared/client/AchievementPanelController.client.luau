-- AchievementPanelController.client.luau
-- Standalone achievements panel: category filter, achievement grid, progress tracking.
-- Opened via HUD button bar or J key. Managed by PanelManager.

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local AchievementConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AchievementConfig"))
local AssetIds          = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AssetIds"))
local TooltipModule     = require(ReplicatedStorage:WaitForChild("TooltipModule"))
local PanelManager      = require(script.Parent:WaitForChild("PanelManager"))

local remotes                = ReplicatedStorage:WaitForChild("Remotes")
local achieveSyncRemote      = remotes:WaitForChild("AchievementSync", 10)
local achieveRequestRemote   = remotes:WaitForChild("AchievementRequest", 10)
local achieveUnlockedRemote  = remotes:WaitForChild("AchievementUnlocked", 10)

-- ── Style (matches InventoryController palette) ─────────────────────────
local BG     = Color3.fromRGB(20, 22, 30)
local BG2    = Color3.fromRGB(32, 36, 50)
local BG3    = Color3.fromRGB(42, 48, 66)
local ACCENT = Color3.fromRGB(200, 181, 92)  -- amber accent for achievements
local TEXT   = Color3.fromRGB(220, 225, 240)
local MUTED  = Color3.fromRGB(120, 132, 158)
local GOLD   = Color3.fromRGB(255, 200, 60)
local FONTB  = Enum.Font.GothamBold
local FONT   = Enum.Font.Gotham

-- ── Helpers ─────────────────────────────────────────────────────────────
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

-- ── Build ScreenGui ─────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name           = "AchievementGui"
gui.ResetOnSpawn   = false
gui.DisplayOrder   = 5
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = playerGui

-- Panel frame (shared sizing with other panels)
local panel = Instance.new("Frame")
panel.Name                 = "AchievementPanel"
panel.Size                 = UDim2.new(0.7, 0, 0.75, 0)
panel.Position             = UDim2.new(0.5, 0, 0.5, 0)
panel.AnchorPoint          = Vector2.new(0.5, 0.5)
panel.BackgroundColor3     = BG
panel.BorderSizePixel      = 0
panel.Parent               = gui
addCorner(panel, 12)

local panelStroke = Instance.new("UIStroke")
panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
panelStroke.Thickness       = 1
panelStroke.Color           = Color3.fromRGB(60, 60, 70)
panelStroke.Parent          = panel

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size                 = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundTransparency = 1
titleBar.Parent               = panel

makeLabel(titleBar, {
	Size           = UDim2.new(1, -60, 0, 24),
	Position       = UDim2.new(0, 16, 0, 10),
	Text           = "ACHIEVEMENTS",
	Font           = FONTB,
	TextSize       = 16,
	TextColor3     = TEXT,
	TextXAlignment = Enum.TextXAlignment.Left,
})

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Name               = "CloseBtn"
closeBtn.Size               = UDim2.new(0, 30, 0, 30)
closeBtn.Position           = UDim2.new(1, -40, 0, 7)
closeBtn.BackgroundColor3   = BG2
closeBtn.BorderSizePixel    = 0
closeBtn.Text               = "X"
closeBtn.TextColor3         = TEXT
closeBtn.Font               = FONTB
closeBtn.TextSize           = 14
closeBtn.Parent             = panel
addCorner(closeBtn, 5)

closeBtn.Activated:Connect(function()
	PanelManager.close()
end)

-- Content area (below title bar)
local content = Instance.new("Frame")
content.Size                 = UDim2.new(1, -24, 1, -56)
content.Position             = UDim2.new(0, 12, 0, 50)
content.BackgroundTransparency = 1
content.Parent               = panel

-- ── Achievement state (synced from server) ──────────────────────────────
local achCounters: { [string]: number } = {}
local achUnlocked: { [string]: number } = {}
local achTotalCount = AchievementConfig.TotalCount

-- Summary header
local achSummary = makeLabel(content, {
	Size           = UDim2.new(1, 0, 0, 20),
	Position       = UDim2.new(0, 0, 0, 0),
	Text           = "0/" .. achTotalCount .. " Achievements Unlocked",
	TextColor3     = GOLD,
	Font           = FONTB,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize       = 12,
})

-- ── Category dropdown filter ────────────────────────────────────────────
local achFilterCategory = "ALL"

local allCategories = { "ALL" }
for _, cat in ipairs(AchievementConfig.Categories) do
	table.insert(allCategories, cat)
end

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
achDropdownBtn.Parent           = content
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
achDropdownPopup.Parent             = content
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

-- Category count labels
local achCatCountLabels: { [string]: TextLabel } = {}

local refreshAchievements: () -> ()

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
		if refreshAchievements then refreshAchievements() end
	end)

	row.MouseEnter:Connect(function()
		row.BackgroundTransparency = 0
	end)
	row.MouseLeave:Connect(function()
		row.BackgroundTransparency = 0.2
	end)
end

achDropdownBtn.Activated:Connect(function()
	achDropdownPopup.Visible = not achDropdownPopup.Visible
end)

-- ── Achievement card grid ───────────────────────────────────────────────

local achScroll = Instance.new("ScrollingFrame")
achScroll.Size               = UDim2.new(1, 0, 1, -54)
achScroll.Position           = UDim2.new(0, 0, 0, 52)
achScroll.BackgroundTransparency = 1
achScroll.ScrollBarThickness = 4
achScroll.ScrollBarImageColor3 = MUTED
achScroll.CanvasSize         = UDim2.new(0, 0, 0, 0)
achScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
achScroll.Parent             = content

local achGrid = Instance.new("UIGridLayout")
achGrid.CellSize     = UDim2.new(0, 96, 0, 90)
achGrid.CellPadding  = UDim2.new(0, 6, 0, 6)
achGrid.SortOrder    = Enum.SortOrder.LayoutOrder
achGrid.Parent       = achScroll

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

	TooltipModule.register(card, {
		kind = "achievement",
		key = ach.key,
		counter = 0,
		unlocked = false,
	})
end

-- ── Refresh ─────────────────────────────────────────────────────────────

refreshAchievements = function()
	local unlockedCount = 0
	for _ in pairs(achUnlocked) do unlockedCount += 1 end
	achSummary.Text = unlockedCount .. "/" .. achTotalCount .. " Achievements Unlocked"

	for i, card in ipairs(achCards) do
		local ach = AchievementConfig.Achievements[i]
		local isUnlocked = achUnlocked[ach.key] ~= nil
		local counter = achCounters[ach.counter] or 0
		local progress = math.min(counter, ach.threshold)

		local matchesFilter = achFilterCategory == "ALL" or card.category == achFilterCategory
		card.frame.Visible = matchesFilter

		card.progressLabel.Text = progress .. "/" .. ach.threshold

		TooltipModule.update(card.frame, {
			kind = "achievement",
			key = ach.key,
			counter = counter,
			unlocked = isUnlocked,
		})

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

	-- Update category count badges
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

-- Close dropdown when clicking on the achievement grid
achScroll.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		achDropdownPopup.Visible = false
	end
end)

-- ── Server sync ─────────────────────────────────────────────────────────

if achieveSyncRemote then
	achieveSyncRemote.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then return end
		if type(data.counters) == "table" then achCounters = data.counters end
		if type(data.unlocked) == "table" then achUnlocked = data.unlocked end
		refreshAchievements()
	end)
end

if achieveUnlockedRemote then
	achieveUnlockedRemote.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then return end
		if data.key then
			achUnlocked[data.key] = os.time()
			refreshAchievements()
		end
	end)
end

-- ── Register with PanelManager ──────────────────────────────────────────

PanelManager.register("achievements", {
	open = function()
		if achieveRequestRemote then achieveRequestRemote:FireServer() end
		refreshAchievements()
	end,
	close = function()
		achDropdownPopup.Visible = false
	end,
	frame = panel,
	screenGui = gui,
})

-- Hotkey: J to toggle achievements panel
ContextActionService:BindActionAtPriority(
	"ToggleAchievements",
	function(_name, state, _obj)
		if state == Enum.UserInputState.Begin then
			PanelManager.toggle("achievements")
		end
		return Enum.ContextActionResult.Sink
	end,
	false,
	Enum.ContextActionPriority.High.Value,
	Enum.KeyCode.J
)
