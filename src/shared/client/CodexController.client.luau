-- CodexController.client.luau
-- Codex panel: browse discovered lore entries by area, read full text.
-- Opened via HUD button bar or K key. Managed by PanelManager.

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local LoreConfig   = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("LoreConfig"))
local PanelManager = require(script.Parent:WaitForChild("PanelManager"))

local remotes             = ReplicatedStorage:WaitForChild("Remotes")
local loreDataSyncRemote  = remotes:WaitForChild("LoreDataSync", 10)
local loreInteractRemote  = remotes:FindFirstChild("LoreInteract")
local loreDiscoveredRemote = remotes:FindFirstChild("LoreDiscovered")
local loreAlreadyReadRemote = remotes:FindFirstChild("LoreAlreadyRead")

-- ── State ─────────────────────────────────────────────────────────────────
local discoveredSet: { [string]: boolean } = {}
local selectedArea: string = LoreConfig.AreaOrder[1] or "The Ward"

-- ── Style ─────────────────────────────────────────────────────────────────
local BG     = Color3.fromRGB(20, 22, 30)
local BG2    = Color3.fromRGB(32, 36, 50)
local BG3    = Color3.fromRGB(42, 48, 66)
local ACCENT = Color3.fromRGB(59, 165, 181)
local TEXT   = Color3.fromRGB(220, 225, 240)
local MUTED  = Color3.fromRGB(120, 132, 158)
local FONTB  = Enum.Font.GothamBold
local FONT   = Enum.Font.Gotham

-- Parchment reading view
local PARCHMENT_BG   = Color3.fromRGB(245, 230, 200)
local PARCHMENT_TEXT = Color3.fromRGB(42, 42, 42)

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

-- ── Build ScreenGui ───────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name           = "CodexGui"
gui.ResetOnSpawn   = false
gui.DisplayOrder   = 5
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = playerGui

-- Panel frame
local panel = Instance.new("Frame")
panel.Name                 = "CodexPanel"
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
titleBar.Size                    = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundTransparency  = 1
titleBar.Parent                  = panel

makeLabel(titleBar, {
	Size           = UDim2.new(1, -60, 0, 24),
	Position       = UDim2.new(0, 16, 0, 10),
	Text           = "CODEX",
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

-- Content area
local content = Instance.new("Frame")
content.Size                    = UDim2.new(1, -24, 1, -56)
content.Position                = UDim2.new(0, 12, 0, 50)
content.BackgroundTransparency  = 1
content.Parent                  = panel

-- ── Left sidebar (area list) ──────────────────────────────────────────────

local sidebar = Instance.new("Frame")
sidebar.Size                    = UDim2.new(0, 200, 1, 0)
sidebar.BackgroundTransparency  = 1
sidebar.Parent                  = content

makeLabel(sidebar, {
	Size           = UDim2.new(1, 0, 0, 16),
	Text           = "AREAS",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3     = MUTED,
	Font           = FONTB,
	TextSize       = 10,
})

local areaScroll = Instance.new("ScrollingFrame")
areaScroll.Size                  = UDim2.new(1, 0, 1, -20)
areaScroll.Position              = UDim2.new(0, 0, 0, 20)
areaScroll.BackgroundTransparency = 1
areaScroll.BorderSizePixel       = 0
areaScroll.ScrollBarThickness    = 3
areaScroll.ScrollBarImageColor3  = ACCENT
areaScroll.CanvasSize            = UDim2.new(0, 0, 0, 0)
areaScroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
areaScroll.Parent                = sidebar

local areaLayout = Instance.new("UIListLayout")
areaLayout.SortOrder = Enum.SortOrder.LayoutOrder
areaLayout.Padding   = UDim.new(0, 4)
areaLayout.Parent    = areaScroll

type AreaBtn = { btn: TextButton, countLabel: TextLabel, area: string }
local areaBtns: { AreaBtn } = {}

-- ── Right content (entry list) ────────────────────────────────────────────

local entrySection = Instance.new("Frame")
entrySection.Size                    = UDim2.new(1, -210, 1, 0)
entrySection.Position                = UDim2.new(0, 210, 0, 0)
entrySection.BackgroundTransparency  = 1
entrySection.Parent                  = content

local entriesTitle = makeLabel(entrySection, {
	Size           = UDim2.new(1, 0, 0, 16),
	Text           = "ENTRIES",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3     = MUTED,
	Font           = FONTB,
	TextSize       = 10,
})

local entryScroll = Instance.new("ScrollingFrame")
entryScroll.Size                  = UDim2.new(1, 0, 1, -40)
entryScroll.Position              = UDim2.new(0, 0, 0, 20)
entryScroll.BackgroundTransparency = 1
entryScroll.BorderSizePixel       = 0
entryScroll.ScrollBarThickness    = 3
entryScroll.ScrollBarImageColor3  = ACCENT
entryScroll.CanvasSize            = UDim2.new(0, 0, 0, 0)
entryScroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
entryScroll.Parent                = entrySection

local entryLayout = Instance.new("UIListLayout")
entryLayout.SortOrder = Enum.SortOrder.LayoutOrder
entryLayout.Padding   = UDim.new(0, 4)
entryLayout.Parent    = entryScroll

-- Total count at bottom
local totalLabel = makeLabel(entrySection, {
	Size           = UDim2.new(1, 0, 0, 16),
	Position       = UDim2.new(0, 0, 1, -16),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3     = MUTED,
	TextSize       = 10,
	Text           = "0 / 0 discovered",
})

-- ── Reading view overlay ──────────────────────────────────────────────────

local readingOverlay = Instance.new("Frame")
readingOverlay.Name                    = "ReadingOverlay"
readingOverlay.Size                    = UDim2.new(1, 0, 1, 0)
readingOverlay.BackgroundColor3        = Color3.new(0, 0, 0)
readingOverlay.BackgroundTransparency  = 0.4
readingOverlay.BorderSizePixel         = 0
readingOverlay.Visible                 = false
readingOverlay.ZIndex                  = 10
readingOverlay.Parent                  = panel

local readingFrame = Instance.new("Frame")
readingFrame.Name                 = "ReadingFrame"
readingFrame.Size                 = UDim2.new(0, 600, 0, 450)
readingFrame.Position             = UDim2.new(0.5, 0, 0.5, 0)
readingFrame.AnchorPoint          = Vector2.new(0.5, 0.5)
readingFrame.BackgroundColor3     = PARCHMENT_BG
readingFrame.BorderSizePixel      = 0
readingFrame.ZIndex               = 11
readingFrame.Parent               = readingOverlay
addCorner(readingFrame, 8)

local readingStroke = Instance.new("UIStroke")
readingStroke.Color     = Color3.fromRGB(180, 165, 140)
readingStroke.Thickness = 2
readingStroke.Parent    = readingFrame

-- Reading close button
local readCloseBtn = Instance.new("TextButton")
readCloseBtn.Size             = UDim2.new(0, 30, 0, 30)
readCloseBtn.Position         = UDim2.new(1, -38, 0, 8)
readCloseBtn.BackgroundColor3 = Color3.fromRGB(220, 205, 180)
readCloseBtn.BorderSizePixel  = 0
readCloseBtn.Text             = "X"
readCloseBtn.TextColor3       = PARCHMENT_TEXT
readCloseBtn.Font             = FONTB
readCloseBtn.TextSize         = 14
readCloseBtn.ZIndex           = 12
readCloseBtn.Parent           = readingFrame
addCorner(readCloseBtn, 5)

-- Reading title
local readTitleLabel = makeLabel(readingFrame, {
	Size           = UDim2.new(1, -60, 0, 24),
	Position       = UDim2.new(0, 20, 0, 16),
	Text           = "",
	Font           = FONTB,
	TextSize       = 18,
	TextColor3     = PARCHMENT_TEXT,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex         = 12,
})

-- Reading subtitle (category + area)
local readSubLabel = makeLabel(readingFrame, {
	Size           = UDim2.new(1, -60, 0, 16),
	Position       = UDim2.new(0, 20, 0, 44),
	Text           = "",
	Font           = FONT,
	TextSize       = 11,
	TextColor3     = Color3.fromRGB(120, 100, 80),
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex         = 12,
})

-- Divider
local readDivider = Instance.new("Frame")
readDivider.Size                    = UDim2.new(1, -40, 0, 1)
readDivider.Position                = UDim2.new(0, 20, 0, 66)
readDivider.BackgroundColor3        = Color3.fromRGB(200, 185, 160)
readDivider.BorderSizePixel         = 0
readDivider.ZIndex                  = 12
readDivider.Parent                  = readingFrame

-- Reading body (scrollable)
local readBodyScroll = Instance.new("ScrollingFrame")
readBodyScroll.Size                  = UDim2.new(1, -40, 1, -86)
readBodyScroll.Position              = UDim2.new(0, 20, 0, 76)
readBodyScroll.BackgroundTransparency = 1
readBodyScroll.BorderSizePixel       = 0
readBodyScroll.ScrollBarThickness    = 4
readBodyScroll.ScrollBarImageColor3  = Color3.fromRGB(180, 165, 140)
readBodyScroll.CanvasSize            = UDim2.new(0, 0, 0, 0)
readBodyScroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
readBodyScroll.ZIndex                = 12
readBodyScroll.Parent                = readingFrame

local readBodyLabel = Instance.new("TextLabel")
readBodyLabel.Size                    = UDim2.new(1, 0, 0, 0)
readBodyLabel.AutomaticSize           = Enum.AutomaticSize.Y
readBodyLabel.BackgroundTransparency  = 1
readBodyLabel.Text                    = ""
readBodyLabel.TextColor3              = PARCHMENT_TEXT
readBodyLabel.Font                    = FONT
readBodyLabel.TextSize                = 14
readBodyLabel.TextWrapped             = true
readBodyLabel.TextXAlignment          = Enum.TextXAlignment.Left
readBodyLabel.TextYAlignment          = Enum.TextYAlignment.Top
readBodyLabel.LineHeight              = 1.4
readBodyLabel.RichText                = false
readBodyLabel.ZIndex                  = 12
readBodyLabel.Parent                  = readBodyScroll

-- ── Reading view logic ────────────────────────────────────────────────────

local function openReading(loreId: string)
	local loreDef = LoreConfig.ById[loreId]
	if not loreDef then return end

	readTitleLabel.Text = loreDef.icon .. "  " .. loreDef.title
	readSubLabel.Text   = loreDef.category .. " \194\183 " .. loreDef.area
	readBodyLabel.Text  = loreDef.text
	readBodyScroll.CanvasPosition = Vector2.new(0, 0)
	readingOverlay.Visible = true
end

local function closeReading()
	readingOverlay.Visible = false
end

readCloseBtn.Activated:Connect(closeReading)

-- Click overlay background to close reading
local readOverlayBtn = Instance.new("TextButton")
readOverlayBtn.Size                    = UDim2.new(1, 0, 1, 0)
readOverlayBtn.BackgroundTransparency  = 1
readOverlayBtn.Text                    = ""
readOverlayBtn.ZIndex                  = 10
readOverlayBtn.Parent                  = readingOverlay
readOverlayBtn.Activated:Connect(closeReading)

-- ── Build area buttons ────────────────────────────────────────────────────

for i, area in ipairs(LoreConfig.AreaOrder) do
	local btn = Instance.new("TextButton")
	btn.Size               = UDim2.new(1, 0, 0, 40)
	btn.LayoutOrder        = i
	btn.BackgroundColor3   = BG3
	btn.BorderSizePixel    = 0
	btn.Text               = ""
	btn.AutoButtonColor    = false
	btn.Parent             = areaScroll
	addCorner(btn, 5)

	local nameL = makeLabel(btn, {
		Size           = UDim2.new(1, -50, 0, 18),
		Position       = UDim2.new(0, 8, 0, 4),
		Text           = area,
		Font           = FONTB,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize       = 12,
	})

	local countL = makeLabel(btn, {
		Size           = UDim2.new(1, -8, 0, 14),
		Position       = UDim2.new(0, 8, 0, 22),
		Text           = "0 / 0",
		TextColor3     = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize       = 10,
	})

	table.insert(areaBtns, { btn = btn, countLabel = countL, area = area })

	btn.Activated:Connect(function()
		selectedArea = area
		refreshCodex()
	end)
end

-- ── Entry row cache ───────────────────────────────────────────────────────

local entryRows: { Frame } = {}

local function clearEntryRows()
	for _, row in ipairs(entryRows) do
		row:Destroy()
	end
	table.clear(entryRows)
end

local function makeEntryRow(loreDef: LoreConfig.LoreDef, isDiscovered: boolean, layoutOrder: number)
	local row = Instance.new("TextButton")
	row.Size             = UDim2.new(1, 0, 0, 50)
	row.LayoutOrder      = layoutOrder
	row.BackgroundColor3 = BG3
	row.BorderSizePixel  = 0
	row.Text             = ""
	row.AutoButtonColor  = false
	row.Parent           = entryScroll
	addCorner(row, 5)

	if isDiscovered then
		-- Icon
		makeLabel(row, {
			Size           = UDim2.new(0, 30, 1, 0),
			Position       = UDim2.new(0, 8, 0, 0),
			Text           = loreDef.icon,
			TextSize       = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
		})

		-- Title
		makeLabel(row, {
			Size           = UDim2.new(1, -100, 0, 18),
			Position       = UDim2.new(0, 42, 0, 6),
			Text           = loreDef.title,
			Font           = FONTB,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize       = 12,
		})

		-- Subtitle
		makeLabel(row, {
			Size           = UDim2.new(1, -100, 0, 14),
			Position       = UDim2.new(0, 42, 0, 26),
			Text           = loreDef.subtitle,
			TextColor3     = MUTED,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize       = 10,
		})

		-- Category tag
		makeLabel(row, {
			Size           = UDim2.new(0, 80, 0, 14),
			Position       = UDim2.new(1, -88, 0.5, 0),
			AnchorPoint    = Vector2.new(0, 0.5),
			Text           = loreDef.category,
			TextColor3     = ACCENT,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize       = 9,
			Font           = FONTB,
		})

		row.Activated:Connect(function()
			openReading(loreDef.id)
		end)

		-- Hover effect
		row.MouseEnter:Connect(function()
			row.BackgroundColor3 = Color3.fromRGB(52, 58, 78)
		end)
		row.MouseLeave:Connect(function()
			row.BackgroundColor3 = BG3
		end)
	else
		-- Locked entry
		makeLabel(row, {
			Size           = UDim2.new(0, 30, 1, 0),
			Position       = UDim2.new(0, 8, 0, 0),
			Text           = "\u{1F512}",
			TextSize       = 16,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3     = MUTED,
		})
		makeLabel(row, {
			Size           = UDim2.new(1, -50, 1, 0),
			Position       = UDim2.new(0, 42, 0, 0),
			Text           = "???",
			TextColor3     = MUTED,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize       = 12,
		})
	end

	table.insert(entryRows, row)
end

-- ── Refresh ───────────────────────────────────────────────────────────────

function refreshCodex()
	-- Update area buttons
	local totalDiscovered = 0
	local totalAvailable  = 0

	for _, ab in ipairs(areaBtns) do
		local entries = LoreConfig.ByArea[ab.area] or {}
		local areaTotal = #entries
		local areaFound = 0
		for _, entry in ipairs(entries) do
			if discoveredSet[entry.id] then
				areaFound += 1
			end
		end
		ab.countLabel.Text = areaFound .. " / " .. areaTotal
		totalDiscovered += areaFound
		totalAvailable  += areaTotal

		-- Highlight selected area
		if ab.area == selectedArea then
			ab.btn.BackgroundColor3 = Color3.fromRGB(50, 58, 78)
			local stroke = ab.btn:FindFirstChildOfClass("UIStroke")
			if not stroke then
				stroke = Instance.new("UIStroke")
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Thickness = 1
				stroke.Parent = ab.btn
			end
			stroke.Color = ACCENT
		else
			ab.btn.BackgroundColor3 = BG3
			local stroke = ab.btn:FindFirstChildOfClass("UIStroke")
			if stroke then stroke:Destroy() end
		end
	end

	totalLabel.Text = totalDiscovered .. " / " .. totalAvailable .. " discovered"

	-- Update entry list for selected area
	clearEntryRows()
	local entries = LoreConfig.ByArea[selectedArea] or {}
	for _, entry in ipairs(entries) do
		makeEntryRow(entry, discoveredSet[entry.id] == true, entry.sortOrder)
	end
end

-- ── Register with PanelManager ────────────────────────────────────────────

PanelManager.register("codex", {
	open = function()
		closeReading()
		refreshCodex()
	end,
	close = function()
		closeReading()
	end,
	frame = panel,
	screenGui = gui,
})

-- Hotkey: K to toggle codex
ContextActionService:BindActionAtPriority(
	"ToggleCodex",
	function(_name, state, _obj)
		if state == Enum.UserInputState.Begin then
			PanelManager.toggle("codex")
		end
		return Enum.ContextActionResult.Sink
	end,
	false,
	Enum.ContextActionPriority.High.Value,
	Enum.KeyCode.K
)

-- ── Lore data sync (on join) ──────────────────────────────────────────────

if loreDataSyncRemote then
	loreDataSyncRemote.OnClientEvent:Connect(function(discoveredList: any)
		if type(discoveredList) ~= "table" then return end
		table.clear(discoveredSet)
		for _, loreId in ipairs(discoveredList) do
			if type(loreId) == "string" then
				discoveredSet[loreId] = true
			end
		end
		if PanelManager.getActive() == "codex" then
			refreshCodex()
		end
	end)
end

-- ── Listen for new discoveries ────────────────────────────────────────────

if loreDiscoveredRemote then
	loreDiscoveredRemote.OnClientEvent:Connect(function(loreId: any)
		if type(loreId) ~= "string" then return end
		discoveredSet[loreId] = true
		-- Auto-open reading view if codex is open
		if PanelManager.getActive() == "codex" then
			refreshCodex()
			openReading(loreId)
		end
	end)
end

if loreAlreadyReadRemote then
	loreAlreadyReadRemote.OnClientEvent:Connect(function(loreId: any)
		if type(loreId) ~= "string" then return end
		-- Open reading view (re-read)
		if PanelManager.getActive() == "codex" then
			openReading(loreId)
		else
			PanelManager.open("codex")
			task.wait(0.2)
			openReading(loreId)
		end
	end)
end
