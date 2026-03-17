-- InspectController.client.luau
-- Adds "Inspect" ProximityPrompt to other players' characters.
-- On trigger: requests inspect data from server, shows profile panel.
-- Panel includes stat bars, wealth tier, session time, and a TRADE button.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local AssetIds       = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AssetIds"))
local TooltipModule  = require(ReplicatedStorage:WaitForChild("TooltipModule"))

local player  = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not remotes then
	warn("[InspectController] Remotes folder not found, aborting")
	return
end
local inspectRequestRemote  = remotes:WaitForChild("InspectRequest", 30)  :: RemoteEvent
local inspectDataRemote     = remotes:WaitForChild("InspectData", 30)     :: RemoteEvent
local tradeInitiateRemote   = remotes:WaitForChild("TradeInitiate", 30)   :: RemoteEvent
local saveUIPosRemote       = remotes:WaitForChild("SaveUIPosition", 30)  :: RemoteEvent

if not inspectRequestRemote or not inspectDataRemote or not tradeInitiateRemote then
	warn("[InspectController] Missing remotes, aborting")
	return
end

local INTERACT_RANGE = GameplayConfig.Trading.InteractRange

-- ── Helpers ─────────────────────────────────────────────────────────────

local function isClickOrTap(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMoveInput(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

local function restorePanelPosition(frame: Frame, panelName: string)
	local posStr = player:GetAttribute("_UIPos_" .. panelName)
	if type(posStr) == "string" then
		local x, y = string.match(posStr, "^(-?%d+),(-?%d+)$")
		if x and y then
			frame.Position = UDim2.new(0, tonumber(x) :: number, 0, tonumber(y) :: number)
			return true
		end
	end
	return false
end

local function makeDraggable(frame: Frame, panelName: string?)
	local dragging    = false
	local dragStart   = Vector2.new(0, 0)
	local posStart    = Vector2.new(0, 0)

	frame.InputBegan:Connect(function(input)
		if not isClickOrTap(input) then return end
		local localY = input.Position.Y - frame.AbsolutePosition.Y
		if localY > 30 then return end
		dragging   = true
		dragStart  = Vector2.new(input.Position.X, input.Position.Y)
		posStart   = Vector2.new(frame.AbsolutePosition.X, frame.AbsolutePosition.Y)
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if not isMoveInput(input) then return end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
		frame.Position = UDim2.new(0, posStart.X + delta.X, 0, posStart.Y + delta.Y)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if isClickOrTap(input) and dragging then
			dragging = false
			if panelName then
				saveUIPosRemote:FireServer(panelName, frame.AbsolutePosition.X, frame.AbsolutePosition.Y)
			end
		end
	end)
end

-- ── Colors (match existing UI theme) ────────────────────────────────────

local BG      = Color3.fromRGB(16, 18, 26)
local BG2     = Color3.fromRGB(32, 36, 50)
local STROKE  = Color3.fromRGB(120, 180, 210)
local ACCENT  = Color3.fromRGB(70, 130, 200)
local TEXT    = Color3.fromRGB(220, 230, 240)
local DIM     = Color3.fromRGB(140, 150, 170)

local BAR_COLORS = {
	health  = Color3.fromRGB(200, 50, 50),
	hunger  = Color3.fromRGB(200, 160, 60),
	thirst  = Color3.fromRGB(60, 140, 200),
	fatigue = Color3.fromRGB(160, 120, 200),
}

-- ── ProximityPrompt management ─────────────────────────────────────────

local activePrompts: { [Model]: ProximityPrompt } = {}

local function addInspectPrompt(character: Model, targetPlayer: Player)
	if targetPlayer == player then return end
	-- Use Head if available (more reliable with mesh avatars), fall back to HumanoidRootPart
	local attachPart = character:FindFirstChild("Head") or character:WaitForChild("HumanoidRootPart", 10)
	if not attachPart then
		warn("[InspectController] No attach part for " .. targetPlayer.Name)
		return
	end

	-- Remove any existing inspect prompt (respawn edge case)
	for _, child in ipairs(attachPart:GetChildren()) do
		if child:IsA("ProximityPrompt") and child.Name == "InspectPrompt" then
			child:Destroy()
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name                  = "InspectPrompt"
	prompt.ActionText            = "Inspect"
	prompt.ObjectText            = targetPlayer.DisplayName
	prompt.MaxActivationDistance  = INTERACT_RANGE
	prompt.KeyboardKeyCode       = Enum.KeyCode.G
	prompt.RequiresLineOfSight   = false
	prompt.HoldDuration          = 0
	prompt.Exclusivity           = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.Parent                = attachPart

	activePrompts[character] = prompt

	prompt.Triggered:Connect(function()
		inspectRequestRemote:FireServer(targetPlayer)
	end)
end

local function removeInspectPrompt(character: Model)
	local prompt = activePrompts[character]
	if prompt then
		prompt:Destroy()
		activePrompts[character] = nil
	end
end

-- Wire existing and future players
for _, p in ipairs(Players:GetPlayers()) do
	if p ~= player and p.Character then
		addInspectPrompt(p.Character, p)
	end
	p.CharacterAdded:Connect(function(char)
		addInspectPrompt(char, p)
	end)
	p.CharacterRemoving:Connect(function(char)
		removeInspectPrompt(char)
	end)
end

Players.PlayerAdded:Connect(function(p)
	if p == player then return end
	if p.Character then
		addInspectPrompt(p.Character, p)
	end
	p.CharacterAdded:Connect(function(char)
		addInspectPrompt(char, p)
	end)
	p.CharacterRemoving:Connect(function(char)
		removeInspectPrompt(char)
	end)
end)

Players.PlayerRemoving:Connect(function(p)
	if p.Character then
		removeInspectPrompt(p.Character)
	end
end)

-- ── Inspect Panel UI ───────────────────────────────────────────────────

local PANEL_W = 280
local PANEL_H = 364

local screenGui = Instance.new("ScreenGui")
screenGui.Name                = "InspectGui"
screenGui.ResetOnSpawn        = false
screenGui.IgnoreGuiInset      = false
screenGui.DisplayOrder        = 15
screenGui.Parent              = playerGui

-- Main panel frame
local panel = Instance.new("Frame")
panel.Name                  = "InspectPanel"
panel.Size                  = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.Position              = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2)
panel.BackgroundColor3      = BG
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel       = 0
panel.Visible               = false
panel.Parent                = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent       = panel

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
	accent.BackgroundColor3 = Color3.fromRGB(120, 180, 210)
	accent.BackgroundTransparency = 0.4
	accent.BorderSizePixel = 0
	accent.ZIndex = 2
	accent.Parent = panel
	local acCorner = Instance.new("UICorner")
	acCorner.CornerRadius = UDim.new(0, 1)
	acCorner.Parent = accent

	local glow = Instance.new("Frame")
	glow.Name = "InnerGlow"
	glow.Size = UDim2.new(1, 0, 0, 40)
	glow.Position = UDim2.new(0, 0, 0, 0)
	glow.BackgroundColor3 = Color3.fromRGB(120, 180, 210)
	glow.BorderSizePixel = 0
	glow.ZIndex = 0
	glow.Parent = panel
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(0, 12)
	glowCorner.Parent = glow
	local glowGrad = Instance.new("UIGradient")
	glowGrad.Rotation = 90
	glowGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	glowGrad.Parent = glow
end

local panelStroke = Instance.new("UIStroke")
panelStroke.Color        = STROKE
panelStroke.Transparency = 0.5
panelStroke.Thickness    = 1
panelStroke.Parent       = panel
restorePanelPosition(panel, "Inspect")
makeDraggable(panel, "Inspect")

-- ── Header ──────────────────────────────────────────────────────────────

local nameLabel = Instance.new("TextLabel")
nameLabel.Name                  = "PlayerName"
nameLabel.Size                  = UDim2.new(1, -40, 0, 28)
nameLabel.Position              = UDim2.fromOffset(12, 10)
nameLabel.BackgroundTransparency = 1
nameLabel.Text                  = ""
nameLabel.TextColor3            = TEXT
nameLabel.TextSize              = 18
nameLabel.Font                  = Enum.Font.GothamBold
nameLabel.TextXAlignment        = Enum.TextXAlignment.Left
nameLabel.TextTruncate          = Enum.TextTruncate.AtEnd
nameLabel.Parent                = panel

local titleLabel = Instance.new("TextLabel")
titleLabel.Name                  = "Title"
titleLabel.Size                  = UDim2.new(1, -24, 0, 18)
titleLabel.Position              = UDim2.fromOffset(12, 38)
titleLabel.BackgroundTransparency = 1
titleLabel.Text                  = ""
titleLabel.TextColor3            = ACCENT
titleLabel.TextSize              = 12
titleLabel.Font                  = Enum.Font.GothamMedium
titleLabel.TextXAlignment        = Enum.TextXAlignment.Left
titleLabel.Parent                = panel

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Name                  = "CloseBtn"
closeBtn.Size                  = UDim2.fromOffset(28, 28)
closeBtn.Position              = UDim2.new(1, -34, 0, 8)
closeBtn.BackgroundColor3      = BG2
closeBtn.BackgroundTransparency = 0.3
closeBtn.Text                  = "X"
closeBtn.TextColor3            = TEXT
closeBtn.TextSize              = 14
closeBtn.Font                  = Enum.Font.GothamBold
closeBtn.BorderSizePixel       = 0
closeBtn.Parent                = panel

local closeBtnCorner = Instance.new("UICorner")
closeBtnCorner.CornerRadius = UDim.new(0, 6)
closeBtnCorner.Parent       = closeBtn

closeBtn.Activated:Connect(function()
	panel.Visible = false
end)

-- ── Divider ─────────────────────────────────────────────────────────────

local divider = Instance.new("Frame")
divider.Name                  = "Divider"
divider.Size                  = UDim2.new(1, -24, 0, 1)
divider.Position              = UDim2.fromOffset(12, 62)
divider.BackgroundColor3      = STROKE
divider.BackgroundTransparency = 0.6
divider.BorderSizePixel       = 0
divider.Parent                = panel

-- ── Stat bars ───────────────────────────────────────────────────────────

type StatBarUI = {
	fill: Frame,
	valueLabel: TextLabel,
}

local statBars: { [string]: StatBarUI } = {}

local STAT_Y_START = 72
local STAT_ROW_H   = 28
local STAT_ORDER   = { "health", "hunger", "thirst", "fatigue" }
local STAT_ICONS   = {
	health  = AssetIds.Images.HealthIcon,
	hunger  = AssetIds.Images.HungerIcon,
	thirst  = AssetIds.Images.ThirstIcon,
	fatigue = AssetIds.Images.FatigueIcon,
}
local STAT_LABELS = {
	health  = "Health",
	hunger  = "Hunger",
	thirst  = "Thirst",
	fatigue = "Fatigue",
}

for i, statKey in ipairs(STAT_ORDER) do
	local y = STAT_Y_START + (i - 1) * STAT_ROW_H

	-- Icon
	local icon = Instance.new("ImageLabel")
	icon.Name                  = statKey .. "Icon"
	icon.Size                  = UDim2.fromOffset(16, 16)
	icon.Position              = UDim2.fromOffset(14, y + 4)
	icon.BackgroundTransparency = 1
	icon.Image                 = STAT_ICONS[statKey]
	icon.Parent                = panel

	-- Label
	local lbl = Instance.new("TextLabel")
	lbl.Name                  = statKey .. "Label"
	lbl.Size                  = UDim2.fromOffset(52, 20)
	lbl.Position              = UDim2.fromOffset(34, y + 2)
	lbl.BackgroundTransparency = 1
	lbl.Text                  = STAT_LABELS[statKey]
	lbl.TextColor3            = DIM
	lbl.TextSize              = 11
	lbl.Font                  = Enum.Font.GothamMedium
	lbl.TextXAlignment        = Enum.TextXAlignment.Left
	lbl.Parent                = panel

	-- Bar background
	local barBg = Instance.new("Frame")
	barBg.Name                  = statKey .. "BarBg"
	barBg.Size                  = UDim2.fromOffset(140, 12)
	barBg.Position              = UDim2.fromOffset(90, y + 6)
	barBg.BackgroundColor3      = BG2
	barBg.BorderSizePixel       = 0
	barBg.Parent                = panel

	local barBgCorner = Instance.new("UICorner")
	barBgCorner.CornerRadius = UDim.new(0, 4)
	barBgCorner.Parent       = barBg

	-- Bar fill
	local barFill = Instance.new("Frame")
	barFill.Name                  = "Fill"
	barFill.Size                  = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3      = BAR_COLORS[statKey]
	barFill.BorderSizePixel       = 0
	barFill.Parent                = barBg

	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(0, 4)
	barFillCorner.Parent       = barFill

	-- Value text
	local valLabel = Instance.new("TextLabel")
	valLabel.Name                  = statKey .. "Value"
	valLabel.Size                  = UDim2.fromOffset(36, 20)
	valLabel.Position              = UDim2.fromOffset(236, y + 2)
	valLabel.BackgroundTransparency = 1
	valLabel.Text                  = "100%"
	valLabel.TextColor3            = TEXT
	valLabel.TextSize              = 11
	valLabel.Font                  = Enum.Font.GothamMedium
	valLabel.TextXAlignment        = Enum.TextXAlignment.Right
	valLabel.Parent                = panel

	statBars[statKey] = {
		fill = barFill,
		valueLabel = valLabel,
		barBg = barBg,
	}

	local STAT_DESCS = {
		health  = "Their current health. Zero means death.",
		hunger  = "How full they are. Low hunger drains health.",
		thirst  = "Their hydration level. Low thirst drains health.",
		fatigue = "How rested they are. Low fatigue slows them down.",
	}
	TooltipModule.register(barBg, {
		kind = "stat",
		statName = STAT_LABELS[statKey],
		value = 100, max = 100,
		barColor = BAR_COLORS[statKey],
		description = STAT_DESCS[statKey] or "",
	})
end

-- ── Info rows (below stat bars) ────────────────────────────────────────

local INFO_Y_START = STAT_Y_START + #STAT_ORDER * STAT_ROW_H + 8

local function makeInfoRow(name: string, labelText: string, yOffset: number): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name                  = name .. "Label"
	lbl.Size                  = UDim2.fromOffset(80, 18)
	lbl.Position              = UDim2.fromOffset(14, yOffset)
	lbl.BackgroundTransparency = 1
	lbl.Text                  = labelText
	lbl.TextColor3            = DIM
	lbl.TextSize              = 11
	lbl.Font                  = Enum.Font.GothamMedium
	lbl.TextXAlignment        = Enum.TextXAlignment.Left
	lbl.Parent                = panel

	local val = Instance.new("TextLabel")
	val.Name                  = name .. "Value"
	val.Size                  = UDim2.new(1, -100, 0, 18)
	val.Position              = UDim2.fromOffset(96, yOffset)
	val.BackgroundTransparency = 1
	val.Text                  = ""
	val.TextColor3            = TEXT
	val.TextSize              = 11
	val.Font                  = Enum.Font.GothamMedium
	val.TextXAlignment        = Enum.TextXAlignment.Left
	val.TextTruncate          = Enum.TextTruncate.AtEnd
	val.Parent                = panel

	return val
end

local wealthValue  = makeInfoRow("Wealth",  "Wealth",   INFO_Y_START)
local survivalValue = makeInfoRow("Survival", "Survived", INFO_Y_START + 22)
local equippedValue = makeInfoRow("Equipped", "Holding", INFO_Y_START + 44)
local achieveValue  = makeInfoRow("Achievements", "Achievements", INFO_Y_START + 66)

-- ── TRADE button ───────────────────────────────────────────────────────

local tradeBtn = Instance.new("TextButton")
tradeBtn.Name                  = "TradeBtn"
tradeBtn.Size                  = UDim2.new(1, -24, 0, 34)
tradeBtn.Position              = UDim2.new(0, 12, 1, -46)
tradeBtn.BackgroundColor3      = ACCENT
tradeBtn.BackgroundTransparency = 0.1
tradeBtn.Text                  = "TRADE"
tradeBtn.TextColor3            = Color3.fromRGB(255, 255, 255)
tradeBtn.TextSize              = 14
tradeBtn.Font                  = Enum.Font.GothamBold
tradeBtn.BorderSizePixel       = 0
tradeBtn.Parent                = panel

local tradeBtnCorner = Instance.new("UICorner")
tradeBtnCorner.CornerRadius = UDim.new(0, 8)
tradeBtnCorner.Parent       = tradeBtn

local inspectTargetUserId: number? = nil

tradeBtn.Activated:Connect(function()
	if not inspectTargetUserId then return end
	tradeInitiateRemote:FireServer(inspectTargetUserId, "", 0)
	panel.Visible = false
end)

-- ── Populate panel on data received ────────────────────────────────────

local function updateStatBar(key: string, value: number, maxValue: number)
	local bar = statBars[key]
	if not bar then return end
	local pct = if maxValue > 0 then math.clamp(value / maxValue, 0, 1) else 0
	bar.fill.Size = UDim2.fromScale(pct, 1)
	bar.valueLabel.Text = tostring(math.floor(pct * 100)) .. "%"
end

inspectDataRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end

	inspectTargetUserId = data.userId

	nameLabel.Text  = data.name or "Unknown"
	titleLabel.Text = data.title or "Survivor"

	updateStatBar("health",  data.health  or 100, data.maxHealth  or 100)
	updateStatBar("hunger",  data.hunger  or 100, data.maxHunger  or 100)
	updateStatBar("thirst",  data.thirst  or 100, data.maxThirst  or 100)
	updateStatBar("fatigue", data.fatigue or 100, data.maxFatigue or 100)

	-- Update inspect stat tooltips with live values
	for _, statKey in ipairs(STAT_ORDER) do
		local bar = statBars[statKey]
		if bar and bar.barBg then
			local val = data[statKey] or 100
			local maxVal = data["max" .. statKey:sub(1, 1):upper() .. statKey:sub(2)] or 100
			TooltipModule.update(bar.barBg, {
				kind = "stat",
				statName = STAT_LABELS[statKey],
				value = val, max = maxVal,
				barColor = BAR_COLORS[statKey],
				description = statKey == "health" and "Their current health. Zero means death."
					or statKey == "hunger" and "How full they are. Low hunger drains health."
					or statKey == "thirst" and "Their hydration level. Low thirst drains health."
					or "How rested they are. Low fatigue slows them down.",
			})
		end
	end

	wealthValue.Text   = data.wealthTier or "Unknown"
	survivalValue.Text  = data.survivalTime or "0m"

	local itemId = data.equippedItem or ""
	if itemId ~= "" then
		local ItemRegistry = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))
		local def = ItemRegistry.get(itemId)
		equippedValue.Text = if def then def.displayName else itemId
	else
		equippedValue.Text = "Nothing"
	end

	-- Achievements row
	local achCount = data.achievementCount or 0
	local achTotal = data.achievementTotal or 53
	local achRecent = data.recentAchievement
	if achRecent then
		achieveValue.Text = achCount .. "/" .. achTotal .. " \u{2014} " .. achRecent
	else
		achieveValue.Text = achCount .. "/" .. achTotal
	end

	panel.Visible = true
end)
