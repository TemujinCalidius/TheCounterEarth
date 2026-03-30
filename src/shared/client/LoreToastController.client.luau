-- LoreToastController.client.luau
-- Listens for LoreDiscovered remote and shows a blue-teal toast notification.
-- Modeled after AchievementToastController.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local LoreConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("LoreConfig"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder    = ReplicatedStorage:WaitForChild("Remotes")
local discoveredRemote = remotesFolder:WaitForChild("LoreDiscovered", 10)
if not discoveredRemote then
	warn("[LoreToast] LoreDiscovered remote not found — toasts disabled")
	return
end

-- ── Style ────────────────────────────────────────────────────────────────
local BG        = Color3.fromRGB(20, 22, 30)
local TEAL      = Color3.fromRGB(59, 165, 181)
local TEXT_CLR   = Color3.fromRGB(220, 225, 240)
local DIM_CLR    = Color3.fromRGB(150, 160, 180)
local FONT_BOLD  = Enum.Font.GothamBold
local FONT_MED   = Enum.Font.GothamMedium

local TOAST_W = 300
local TOAST_H = 90
local SLIDE_IN  = 0.3
local HOLD_TIME = 4.0
local FADE_OUT  = 0.5
local GAP       = 8

-- ── ScreenGui ────────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoreToasts"
screenGui.DisplayOrder = 21
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- ── Queue ────────────────────────────────────────────────────────────────
local queue: { string } = {}
local showing = false

local function showToast(loreId: string)
	local loreDef = LoreConfig.ById[loreId]
	if not loreDef then return end

	local toast = Instance.new("Frame")
	toast.Name = "LoreToast"
	toast.Size = UDim2.new(0, TOAST_W, 0, TOAST_H)
	toast.Position = UDim2.new(1, GAP, 0, 60)
	toast.AnchorPoint = Vector2.new(0, 0)
	toast.BackgroundColor3 = BG
	toast.BackgroundTransparency = 0.05
	toast.BorderSizePixel = 0
	toast.ClipsDescendants = true
	toast.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = toast

	local toastGrad = Instance.new("UIGradient")
	toastGrad.Rotation = 90
	toastGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 42, 50)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(18, 24, 32)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 16, 22)),
	})
	toastGrad.Parent = toast

	local toastGlow = Instance.new("Frame")
	toastGlow.Name = "InnerGlow"
	toastGlow.Size = UDim2.new(1, 0, 0, 30)
	toastGlow.BackgroundColor3 = TEAL
	toastGlow.BorderSizePixel = 0
	toastGlow.ZIndex = 0
	toastGlow.Parent = toast
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(0, 8)
	glowCorner.Parent = toastGlow
	local glowGrad = Instance.new("UIGradient")
	glowGrad.Rotation = 90
	glowGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	glowGrad.Parent = toastGlow

	local stroke = Instance.new("UIStroke")
	stroke.Color = TEAL
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = toast

	-- Teal accent bar on left
	local accentBar = Instance.new("Frame")
	accentBar.Size = UDim2.new(0, 4, 1, 0)
	accentBar.BackgroundColor3 = TEAL
	accentBar.BorderSizePixel = 0
	accentBar.Parent = toast

	-- Icon (emoji fallback)
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(0, 40, 0, 40)
	iconLabel.Position = UDim2.new(0, 14, 0.5, 0)
	iconLabel.AnchorPoint = Vector2.new(0, 0.5)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = loreDef.icon
	iconLabel.TextSize = 28
	iconLabel.Font = FONT_BOLD
	iconLabel.TextColor3 = TEXT_CLR
	iconLabel.Parent = toast

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -64, 0, 22)
	titleLabel.Position = UDim2.new(0, 60, 0, 12)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Lore Discovered"
	titleLabel.TextSize = 14
	titleLabel.Font = FONT_BOLD
	titleLabel.TextColor3 = TEAL
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Parent = toast

	-- Subtitle (lore entry title)
	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -64, 0, 16)
	subLabel.Position = UDim2.new(0, 60, 0, 34)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = loreDef.title
	subLabel.TextSize = 10
	subLabel.Font = FONT_MED
	subLabel.TextColor3 = DIM_CLR
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.TextTruncate = Enum.TextTruncate.AtEnd
	subLabel.Parent = toast

	-- Area line
	local areaLabel = Instance.new("TextLabel")
	areaLabel.Size = UDim2.new(1, -64, 0, 18)
	areaLabel.Position = UDim2.new(0, 60, 0, 52)
	areaLabel.BackgroundTransparency = 1
	areaLabel.Text = loreDef.category .. " \194\183 " .. loreDef.area
	areaLabel.TextSize = 10
	areaLabel.Font = FONT_MED
	areaLabel.TextColor3 = TEXT_CLR
	areaLabel.TextXAlignment = Enum.TextXAlignment.Left
	areaLabel.TextTruncate = Enum.TextTruncate.AtEnd
	areaLabel.Parent = toast

	-- Slide in
	local slideIn = TweenService:Create(toast, TweenInfo.new(SLIDE_IN, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -(TOAST_W + GAP), 0, 60),
	})
	slideIn:Play()
	slideIn.Completed:Wait()

	task.wait(HOLD_TIME)

	-- Fade out
	local fadeOut = TweenService:Create(toast, TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})
	local childFades = {}
	for _, child in toast:GetDescendants() do
		if child:IsA("TextLabel") then
			table.insert(childFades, TweenService:Create(child, TweenInfo.new(FADE_OUT), { TextTransparency = 1 }))
		elseif child:IsA("ImageLabel") then
			table.insert(childFades, TweenService:Create(child, TweenInfo.new(FADE_OUT), { ImageTransparency = 1 }))
		elseif child:IsA("Frame") then
			table.insert(childFades, TweenService:Create(child, TweenInfo.new(FADE_OUT), { BackgroundTransparency = 1 }))
		elseif child:IsA("UIStroke") then
			table.insert(childFades, TweenService:Create(child, TweenInfo.new(FADE_OUT), { Transparency = 1 }))
		end
	end

	fadeOut:Play()
	for _, t in childFades do t:Play() end
	fadeOut.Completed:Wait()

	toast:Destroy()
end

local function processQueue()
	if showing then return end
	showing = true

	while #queue > 0 do
		local loreId = table.remove(queue, 1)
		showToast(loreId)
		if #queue > 0 then
			task.wait(0.5)
		end
	end

	showing = false
end

-- ── Listen for discoveries ───────────────────────────────────────────────

discoveredRemote.OnClientEvent:Connect(function(loreId: unknown)
	if type(loreId) ~= "string" then return end
	table.insert(queue, loreId)
	task.spawn(processQueue)
end)
