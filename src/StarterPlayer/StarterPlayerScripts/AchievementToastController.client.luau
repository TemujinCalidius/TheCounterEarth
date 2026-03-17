-- AchievementToastController.client.luau
-- Listens for AchievementUnlocked remote and shows a toast notification
-- that slides in from the right, holds, then fades out.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local unlockRemote  = remotesFolder:WaitForChild("AchievementUnlocked", 10)
if not unlockRemote then
	warn("[AchievementToast] AchievementUnlocked remote not found — toasts disabled")
	return
end

-- ── Style ────────────────────────────────────────────────────────────────
local BG       = Color3.fromRGB(20, 22, 30)
local GOLD     = Color3.fromRGB(255, 200, 60)
local TEXT_CLR  = Color3.fromRGB(220, 225, 240)
local DIM_CLR   = Color3.fromRGB(150, 160, 180)
local FONT_BOLD = Enum.Font.GothamBold
local FONT_MED  = Enum.Font.GothamMedium

local TOAST_W = 300
local TOAST_H = 70
local SLIDE_IN  = 0.3
local HOLD_TIME = 4.0
local FADE_OUT  = 0.5
local GAP       = 8

-- ── ScreenGui ────────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AchievementToasts"
screenGui.DisplayOrder = 20
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- ── Queue ────────────────────────────────────────────────────────────────
local queue: { { key: string, name: string, icon: string, category: string } } = {}
local showing = false

local function showToast(data: { key: string, name: string, icon: string, category: string })
	-- Create toast frame off-screen to the right
	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.Size = UDim2.new(0, TOAST_W, 0, TOAST_H)
	toast.Position = UDim2.new(1, GAP, 0, 60)  -- off-screen right
	toast.AnchorPoint = Vector2.new(0, 0)
	toast.BackgroundColor3 = BG
	toast.BackgroundTransparency = 0.05
	toast.BorderSizePixel = 0
	toast.ClipsDescendants = true
	toast.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = toast

	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = toast

	-- Gold accent bar on left
	local accentBar = Instance.new("Frame")
	accentBar.Size = UDim2.new(0, 4, 1, 0)
	accentBar.Position = UDim2.new(0, 0, 0, 0)
	accentBar.BackgroundColor3 = GOLD
	accentBar.BorderSizePixel = 0
	accentBar.Parent = toast

	-- Icon
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(0, 40, 0, 40)
	iconLabel.Position = UDim2.new(0, 14, 0.5, 0)
	iconLabel.AnchorPoint = Vector2.new(0, 0.5)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = data.icon
	iconLabel.TextSize = 28
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextColor3 = TEXT_CLR
	iconLabel.Parent = toast

	-- Achievement name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -64, 0, 22)
	nameLabel.Position = UDim2.new(0, 60, 0, 12)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = data.name
	nameLabel.TextSize = 14
	nameLabel.Font = FONT_BOLD
	nameLabel.TextColor3 = GOLD
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = toast

	-- Category subtitle
	local catLabel = Instance.new("TextLabel")
	catLabel.Size = UDim2.new(1, -64, 0, 18)
	catLabel.Position = UDim2.new(0, 60, 0, 36)
	catLabel.BackgroundTransparency = 1
	catLabel.Text = "Achievement Unlocked - " .. data.category
	catLabel.TextSize = 11
	catLabel.Font = FONT_MED
	catLabel.TextColor3 = DIM_CLR
	catLabel.TextXAlignment = Enum.TextXAlignment.Left
	catLabel.TextTruncate = Enum.TextTruncate.AtEnd
	catLabel.Parent = toast

	-- Slide in from right
	local slideIn = TweenService:Create(toast, TweenInfo.new(SLIDE_IN, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -(TOAST_W + GAP), 0, 60),
	})
	slideIn:Play()
	slideIn.Completed:Wait()

	-- Hold
	task.wait(HOLD_TIME)

	-- Fade out
	local fadeOut = TweenService:Create(toast, TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})
	-- Fade all children too
	local childFades = {}
	for _, child in toast:GetDescendants() do
		if child:IsA("TextLabel") then
			table.insert(childFades, TweenService:Create(child, TweenInfo.new(FADE_OUT), { TextTransparency = 1 }))
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
		local data = table.remove(queue, 1)
		showToast(data)
		if #queue > 0 then
			task.wait(0.5)  -- gap between multiple toasts
		end
	end

	showing = false
end

-- ── Listen for unlocks ───────────────────────────────────────────────────

unlockRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	table.insert(queue, data)
	task.spawn(processQueue)
end)
