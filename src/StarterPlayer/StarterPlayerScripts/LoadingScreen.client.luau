-- LoadingScreen.client.luau
-- Black overlay with "Loading..." text. Dismissed when the server fires ScatterReady.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── Build the loading screen ────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name               = "LoadingScreen"
screenGui.DisplayOrder        = 999 -- on top of everything
screenGui.IgnoreGuiInset      = true
screenGui.ResetOnSpawn        = false
screenGui.Parent              = playerGui

local bg = Instance.new("Frame")
bg.Name                    = "Background"
bg.Size                    = UDim2.new(1, 0, 1, 0)
bg.BackgroundColor3        = Color3.fromRGB(0, 0, 0)
bg.BackgroundTransparency  = 0
bg.BorderSizePixel         = 0
bg.Parent                  = screenGui

local title = Instance.new("TextLabel")
title.Name                    = "Title"
title.Size                    = UDim2.new(1, 0, 0, 60)
title.Position                = UDim2.new(0, 0, 0.4, 0)
title.AnchorPoint             = Vector2.new(0, 0.5)
title.BackgroundTransparency  = 1
title.Text                    = "The Counter Earth"
title.TextColor3              = Color3.fromRGB(220, 200, 160)
title.Font                    = Enum.Font.GothamBold
title.TextSize                = 36
title.Parent                  = bg

local statusLabel = Instance.new("TextLabel")
statusLabel.Name                    = "Status"
statusLabel.Size                    = UDim2.new(1, 0, 0, 30)
statusLabel.Position                = UDim2.new(0, 0, 0.48, 0)
statusLabel.AnchorPoint             = Vector2.new(0, 0)
statusLabel.BackgroundTransparency  = 1
statusLabel.Text                    = "Loading world..."
statusLabel.TextColor3              = Color3.fromRGB(180, 170, 150)
statusLabel.Font                    = Enum.Font.Gotham
statusLabel.TextSize                = 18
statusLabel.Parent                  = bg

-- Dots animation
local dots = 0
local animConn: RBXScriptConnection? = nil
animConn = task.spawn(function()
	while screenGui.Parent do
		dots = (dots % 3) + 1
		statusLabel.Text = "Loading world" .. string.rep(".", dots)
		task.wait(0.4)
	end
end)

-- ── Wait for server signal ──────────────────────────────────────────────

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
local scatterReady  = remotesFolder and remotesFolder:WaitForChild("ScatterReady", 30)

if scatterReady then
	scatterReady.OnClientEvent:Wait()
else
	-- Fallback: if remote never appears, dismiss after 15s
	task.wait(15)
end

-- ── Dismiss ─────────────────────────────────────────────────────────────

statusLabel.Text = "Ready!"

local fadeOut = TweenService:Create(bg, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
	BackgroundTransparency = 1,
})
local fadeTitle = TweenService:Create(title, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
	TextTransparency = 1,
})
local fadeStatus = TweenService:Create(statusLabel, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
	TextTransparency = 1,
})

fadeOut:Play()
fadeTitle:Play()
fadeStatus:Play()
fadeOut.Completed:Wait()

screenGui:Destroy()
