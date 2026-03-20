-- TooltipModule.luau
-- Shared tooltip/floater system for hover info across all UI panels.
-- Desktop: follows mouse (0.3s delay). Mobile: long-press (0.5s hold).
--
-- Usage:
--   local Tooltip = require(ReplicatedStorage:WaitForChild("TooltipModule"))
--   Tooltip.register(btn, { kind = "text", title = "Hello", body = "World" })
--   Tooltip.update(btn, { kind = "text", title = "New", body = "Data" })
--   Tooltip.unregister(btn)

local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local ItemRegistry      = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AchievementConfig"))

-- ── Constants ─────────────────────────────────────────────────────────────

local SHOW_DELAY   = 0.3   -- seconds before tooltip appears (desktop)
local LONG_PRESS   = 0.5   -- seconds for mobile long-press
local MOVE_THRESH  = 5     -- px movement cancels mobile long-press
local OFFSET_X     = 12
local OFFSET_Y     = 8
local MAX_WIDTH    = 260
local TOPBAR_INSET = 36

local BG     = Color3.fromRGB(16, 18, 26)
local BG2    = Color3.fromRGB(32, 36, 50)
local BG3    = Color3.fromRGB(42, 48, 66)
local TEXT   = Color3.fromRGB(220, 225, 240)
local MUTED  = Color3.fromRGB(120, 132, 158)
local ACCENT = Color3.fromRGB(70, 130, 200)
local GOLD   = Color3.fromRGB(255, 200, 60)
local OK     = Color3.fromRGB(80, 195, 110)
local BAD    = Color3.fromRGB(215, 80, 75)
local WARN   = Color3.fromRGB(220, 160, 40)
local FONTB  = Enum.Font.GothamBold
local FONTM  = Enum.Font.GothamMedium
local FONT   = Enum.Font.Gotham

-- ── State ─────────────────────────────────────────────────────────────────

local player = Players.LocalPlayer
local screenGui: ScreenGui?
local tooltipFrame: Frame?
local currentElement: GuiObject? = nil
local hoverTimer   = 0
local isShowing    = false
local isMobile     = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

-- Registry: element → { data, conns }
local registry: { [GuiObject]: { data: any, conns: { RBXScriptConnection } } } = {}

-- ── Build tooltip GUI ─────────────────────────────────────────────────────

local function ensureGui()
	if screenGui and screenGui.Parent then return end
	local pg = player:WaitForChild("PlayerGui")

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TooltipGui"
	screenGui.DisplayOrder = 200
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = pg

	tooltipFrame = Instance.new("Frame")
	tooltipFrame.Name = "Tooltip"
	tooltipFrame.Size = UDim2.fromOffset(MAX_WIDTH, 0)
	tooltipFrame.AutomaticSize = Enum.AutomaticSize.Y
	tooltipFrame.BackgroundColor3 = BG
	tooltipFrame.BackgroundTransparency = 0.05
	tooltipFrame.BorderSizePixel = 0
	tooltipFrame.Visible = false
	tooltipFrame.ZIndex = 100
	tooltipFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = tooltipFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = MUTED
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = tooltipFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = tooltipFrame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = tooltipFrame
end

-- ── Helper: create labels ─────────────────────────────────────────────────

local function clearContent()
	if not tooltipFrame then return end
	for _, child in tooltipFrame:GetChildren() do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") and not child:IsA("UIPadding") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function addLabel(text: string, color: Color3, font: Enum.Font, size: number, order: number, wrapped: boolean?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.Font = font
	lbl.TextSize = size
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextWrapped = if wrapped ~= nil then wrapped else true
	lbl.LayoutOrder = order
	lbl.RichText = true
	lbl.Parent = tooltipFrame
	return lbl
end

local function addDivider(order: number)
	local div = Instance.new("Frame")
	div.Size = UDim2.new(1, 0, 0, 1)
	div.BackgroundColor3 = MUTED
	div.BackgroundTransparency = 0.7
	div.BorderSizePixel = 0
	div.LayoutOrder = order
	div.Parent = tooltipFrame
end

local function addProgressBar(current: number, max: number, color: Color3, order: number)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 8)
	container.BackgroundColor3 = BG2
	container.BorderSizePixel = 0
	container.LayoutOrder = order
	container.Parent = tooltipFrame

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 3)
	barCorner.Parent = container

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(math.clamp(current / math.max(max, 1), 0, 1), 0, 1, 0)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = container

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill
end

local function addStatRow(label: string, value: string, color: Color3, order: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 14)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = tooltipFrame

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.5, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = label
	lbl.TextColor3 = MUTED
	lbl.Font = FONTM
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local val = Instance.new("TextLabel")
	val.Size = UDim2.new(0.5, 0, 1, 0)
	val.Position = UDim2.new(0.5, 0, 0, 0)
	val.BackgroundTransparency = 1
	val.Text = value
	val.TextColor3 = color
	val.Font = FONTB
	val.TextSize = 11
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Parent = row
end

-- ── Content builders per kind ─────────────────────────────────────────────

local function buildItemTooltip(data)
	local def = ItemRegistry.get(data.itemId)
	if not def then
		addLabel(data.itemId, TEXT, FONTB, 13, 1)
		return
	end

	-- Title
	addLabel(def.displayName, TEXT, FONTB, 13, 1)

	-- Category
	addLabel(def.category:sub(1, 1):upper() .. def.category:sub(2), MUTED, FONTM, 10, 2)

	-- Description
	if def.description and def.description ~= "" then
		addDivider(3)
		addLabel(def.description, MUTED, FONT, 11, 4)
	end

	local order = 10

	-- Weight
	if def.weight then
		addStatRow("Weight", string.format("%.1f kg", def.weight * (data.qty or 1)), TEXT, order)
		order += 1
	end

	-- Stack
	if data.qty and data.qty > 1 then
		addStatRow("Quantity", tostring(data.qty) .. "/" .. tostring(def.stackMax), TEXT, order)
		order += 1
	end

	-- Durability
	if data.durability and data.durabilityMax then
		addStatRow("Durability", tostring(data.durability) .. "/" .. tostring(data.durabilityMax), (data.durability / data.durabilityMax < 0.25) and BAD or TEXT, order)
		order += 1
		addProgressBar(data.durability, data.durabilityMax, (data.durability / data.durabilityMax < 0.25) and BAD or ACCENT, order)
		order += 1
	end

	-- Spoil timer
	if data.expiresIn and data.expiresIn > 0 then
		local mins = math.floor(data.expiresIn / 60)
		local secs = data.expiresIn % 60
		local timeStr = string.format("%d:%02d", mins, secs)
		local color = if data.expiresIn < 300 then WARN elseif data.expiresIn < 60 then BAD else MUTED
		addStatRow("Spoils in", timeStr, color, order)
		order += 1
	end

	-- Consume effects
	if def.onConsume then
		local effects = {}
		local statNames = { health = "Health", hunger = "Hunger", thirst = "Thirst", energy = "Energy", fatigue = "Fatigue", poison = "Poison" }
		local statColors = {
			health = Color3.fromRGB(232, 70, 70),
			hunger = Color3.fromRGB(220, 140, 40),
			thirst = Color3.fromRGB(60, 160, 230),
			energy = Color3.fromRGB(90, 205, 120),
			fatigue = Color3.fromRGB(160, 100, 220),
			poison = Color3.fromRGB(60, 150, 60),
		}
		for stat, val in pairs(def.onConsume) do
			if val ~= 0 then
				local sign = if val > 0 then "+" else ""
				local name = statNames[stat] or stat
				table.insert(effects, { name = name, text = sign .. tostring(val), color = statColors[stat] or TEXT })
			end
		end
		if #effects > 0 then
			addDivider(order)
			order += 1
			for _, eff in ipairs(effects) do
				addStatRow(eff.name, eff.text, eff.color, order)
				order += 1
			end
		end
	end

	-- Tool info
	if def.tool then
		addDivider(order)
		order += 1
		addStatRow("Tool type", def.tool.kind, ACCENT, order)
		order += 1
		addStatRow("Tier", tostring(def.tool.tier), TEXT, order)
		order += 1
		if def.tool.damage then
			addStatRow("Damage", tostring(def.tool.damage), BAD, order)
			order += 1
		end
	end
end

local function buildAchievementTooltip(data)
	local ach = AchievementConfig.ByKey[data.key]
	if not ach then return end

	-- Icon + Name
	addLabel(ach.icon .. "  " .. ach.name, TEXT, FONTB, 13, 1)

	-- Category
	addLabel(ach.category, GOLD, FONTM, 10, 2)

	-- Description
	if ach.desc and ach.desc ~= "" then
		addDivider(3)
		addLabel(ach.desc, MUTED, FONT, 11, 4)
	end

	-- Progress
	local counter = data.counter or 0
	local progress = math.min(counter, ach.threshold)
	local isUnlocked = data.unlocked == true

	addDivider(10)
	addStatRow("Progress", progress .. " / " .. ach.threshold, isUnlocked and GOLD or TEXT, 11)
	addProgressBar(progress, ach.threshold, isUnlocked and GOLD or ACCENT, 12)

	if isUnlocked then
		addLabel("Unlocked!", GOLD, FONTB, 11, 13)
	end
end

local function buildStatTooltip(data)
	addLabel(data.statName, TEXT, FONTB, 13, 1)

	if data.description and data.description ~= "" then
		addDivider(2)
		addLabel(data.description, MUTED, FONT, 11, 3)
	end

	if data.value and data.max then
		addDivider(10)
		addStatRow("Current", tostring(math.floor(data.value)) .. " / " .. tostring(data.max), TEXT, 11)
		addProgressBar(data.value, data.max, data.barColor or ACCENT, 12)
	end
end

local function buildTextTooltip(data)
	if data.title then
		addLabel(data.title, TEXT, FONTB, 13, 1)
	end
	if data.body then
		if data.title then addDivider(2) end
		addLabel(data.body, MUTED, FONT, 11, 3)
	end
end

local BUILDERS = {
	item        = buildItemTooltip,
	achievement = buildAchievementTooltip,
	stat        = buildStatTooltip,
	text        = buildTextTooltip,
}

-- ── Position / Show / Hide ────────────────────────────────────────────────

local function positionTooltip(x: number, y: number)
	if not tooltipFrame or not screenGui then return end

	local viewSize = screenGui.AbsoluteSize
	local tipSize = tooltipFrame.AbsoluteSize

	-- Default: right and below cursor
	local px = x + OFFSET_X
	local py = y + OFFSET_Y

	-- Clamp right
	if px + tipSize.X > viewSize.X - 4 then
		px = x - tipSize.X - OFFSET_X
	end
	-- Clamp bottom
	if py + tipSize.Y > viewSize.Y - 4 then
		py = y - tipSize.Y - OFFSET_Y
	end
	-- Clamp left/top
	px = math.max(4, px)
	py = math.max(TOPBAR_INSET, py)

	tooltipFrame.Position = UDim2.fromOffset(px, py)
end

local function showTooltip(data, x: number, y: number)
	ensureGui()
	if not tooltipFrame then return end

	clearContent()

	local builder = BUILDERS[data.kind]
	if builder then
		builder(data)
	else
		addLabel(tostring(data.kind or "?"), TEXT, FONTB, 12, 1)
	end

	positionTooltip(x, y)
	tooltipFrame.Visible = true
	isShowing = true
end

local function hideTooltip()
	if tooltipFrame then
		tooltipFrame.Visible = false
	end
	isShowing = false
	hoverTimer = 0
	currentElement = nil
end

-- ── Input tracking ────────────────────────────────────────────────────────

local pendingElement: GuiObject? = nil
local pendingStart = 0
local pendingPos: Vector2? = nil

-- Desktop: track mouse position to update tooltip while visible
local mousePosConn: RBXScriptConnection?

local function startMouseTracking()
	if mousePosConn then return end
	mousePosConn = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement and isShowing then
			positionTooltip(input.Position.X, input.Position.Y)
		end
	end)
end

local function stopMouseTracking()
	if mousePosConn then
		mousePosConn:Disconnect()
		mousePosConn = nil
	end
end

-- Timer: check if hover delay has elapsed
local timerConn: RBXScriptConnection?

local function startTimer()
	if timerConn then return end
	timerConn = RunService.Heartbeat:Connect(function(dt)
		if not pendingElement then
			return
		end

		local entry = registry[pendingElement]
		if not entry then
			pendingElement = nil
			return
		end

		hoverTimer += dt

		local delay = if isMobile then LONG_PRESS else SHOW_DELAY
		if hoverTimer >= delay then
			-- Check mobile move threshold
			if isMobile and pendingPos then
				local mouse = UserInputService:GetMouseLocation()
				local dist = (mouse - pendingPos).Magnitude
				if dist > MOVE_THRESH then
					pendingElement = nil
					hoverTimer = 0
					return
				end
			end

			local pos = UserInputService:GetMouseLocation()
			showTooltip(entry.data, pos.X, pos.Y)
			currentElement = pendingElement
			pendingElement = nil
			startMouseTracking()
		end
	end)
end

-- ── Registration ──────────────────────────────────────────────────────────

local TooltipModule = {}

function TooltipModule.register(element: GuiObject, data: any)
	if registry[element] then
		TooltipModule.unregister(element)
	end

	local conns: { RBXScriptConnection } = {}

	-- Mouse enter
	table.insert(conns, element.MouseEnter:Connect(function()
		if isMobile then return end
		pendingElement = element
		hoverTimer = 0
		startTimer()
	end))

	-- Mouse leave
	table.insert(conns, element.MouseLeave:Connect(function()
		if pendingElement == element then
			pendingElement = nil
			hoverTimer = 0
		end
		if currentElement == element then
			hideTooltip()
			stopMouseTracking()
		end
	end))

	-- Mobile: long-press via InputBegan/InputEnded on the element
	if isMobile then
		table.insert(conns, element.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			pendingElement = element
			pendingPos = Vector2.new(input.Position.X, input.Position.Y)
			hoverTimer = 0
			startTimer()
		end))

		table.insert(conns, element.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			if pendingElement == element then
				pendingElement = nil
				hoverTimer = 0
			end
			-- Don't immediately hide on touch end — let user read it
			-- Hide on next tap elsewhere (handled globally)
		end))
	end

	registry[element] = { data = data, conns = conns }
end

function TooltipModule.update(element: GuiObject, data: any)
	local entry = registry[element]
	if entry then
		entry.data = data
		-- If currently showing this element, refresh content
		if currentElement == element and isShowing then
			local pos = UserInputService:GetMouseLocation()
			showTooltip(data, pos.X, pos.Y)
		end
	end
end

function TooltipModule.unregister(element: GuiObject)
	local entry = registry[element]
	if not entry then return end

	for _, conn in ipairs(entry.conns) do
		conn:Disconnect()
	end
	registry[element] = nil

	if currentElement == element then
		hideTooltip()
		stopMouseTracking()
	end
end

-- Global: dismiss tooltip on click/tap elsewhere (mobile)
UserInputService.InputBegan:Connect(function(input, processed)
	if not isShowing then return end
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- If the click is NOT on the current tooltip target, hide
		task.defer(function()
			if isShowing and currentElement then
				hideTooltip()
				stopMouseTracking()
			end
		end)
	end
end)

return TooltipModule
