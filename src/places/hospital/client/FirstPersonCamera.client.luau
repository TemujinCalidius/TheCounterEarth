-- FirstPersonCamera.client.luau (Hospital)
-- Forces first-person camera for indoor levels.
-- Hides default cursor and shows a crosshair instead.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

player.CameraMinZoomDistance = 0.5
player.CameraMaxZoomDistance = 0.5
player.CameraMode = Enum.CameraMode.LockFirstPerson
UserInputService.MouseIconEnabled = false

-- ── Crosshair UI ─────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CrosshairGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5
screenGui.Parent = player:WaitForChild("PlayerGui")

local SIZE = 20
local THICKNESS = 2
local COLOR = Color3.fromRGB(200, 200, 200)
local TRANSPARENCY = 0.3

-- Horizontal line
local hLine = Instance.new("Frame")
hLine.Name = "H"
hLine.Size = UDim2.fromOffset(SIZE, THICKNESS)
hLine.Position = UDim2.new(0.5, -SIZE / 2, 0.5, -THICKNESS / 2)
hLine.BackgroundColor3 = COLOR
hLine.BackgroundTransparency = TRANSPARENCY
hLine.BorderSizePixel = 0
hLine.Parent = screenGui

-- Vertical line
local vLine = Instance.new("Frame")
vLine.Name = "V"
vLine.Size = UDim2.fromOffset(THICKNESS, SIZE)
vLine.Position = UDim2.new(0.5, -THICKNESS / 2, 0.5, -SIZE / 2)
vLine.BackgroundColor3 = COLOR
vLine.BackgroundTransparency = TRANSPARENCY
vLine.BorderSizePixel = 0
vLine.Parent = screenGui

-- Center dot
local dot = Instance.new("Frame")
dot.Name = "Dot"
dot.Size = UDim2.fromOffset(THICKNESS + 2, THICKNESS + 2)
dot.Position = UDim2.new(0.5, -(THICKNESS + 2) / 2, 0.5, -(THICKNESS + 2) / 2)
dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
dot.BackgroundTransparency = 0.1
dot.BorderSizePixel = 0
dot.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = dot
