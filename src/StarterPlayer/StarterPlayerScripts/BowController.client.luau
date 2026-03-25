-- BowController.client.luau
-- Client-side bow aiming, draw mechanic, camera control, and mobile buttons.
-- Hold right-click to aim (over-the-shoulder camera), hold left-click to draw,
-- release left-click to fire.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local Workspace          = game:GetService("Workspace")

local player    = Players.LocalPlayer
local camera    = Workspace.CurrentCamera

local ItemRegistry   = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))
local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))

local bowCfg = GameplayConfig.Combat and GameplayConfig.Combat.Bow or {}
local DRAW_TIME_MIN  = bowCfg.DrawTimeMin or 0.3
local DRAW_TIME_MAX  = bowCfg.DrawTimeMax or 1.5
local AIM_WALK_SPEED = bowCfg.AimWalkSpeed or 8
local AIM_FOV        = bowCfg.AimFOV or 60
local SHOULDER_OFFSET = bowCfg.AimShoulderOffset or Vector3.new(2, 0.5, 0)

local remotesFolder      = ReplicatedStorage:WaitForChild("Remotes")
local bowFireRemote      = remotesFolder:WaitForChild("BowFireRequest")
local bowArrowSpawnRemote = remotesFolder:WaitForChild("BowArrowSpawn")

-- ── Nocked arrow visual ──────────────────────────────────────────────────
local activeNockedArrow: Model? = nil

local function showNockedArrow()
	if activeNockedArrow then return end
	local template = ReplicatedStorage:FindFirstChild("stone_arrow")
	if not template or not template:IsA("Model") then return end

	local char = player.Character
	if not char then return end
	-- Find the bow tool's Handle in the character
	local bowTool: Tool? = nil
	for _, child in char:GetChildren() do
		if child:IsA("Tool") then
			local def = ItemRegistry.get(child.Name)
			if def and def.weapon and def.weapon.kind == "bow" then
				bowTool = child
				break
			end
		end
	end
	if not bowTool then return end
	local handle = bowTool:FindFirstChild("Handle") :: BasePart?
	if not handle then return end

	local arrow = template:Clone()
	arrow.Name = "NockedArrow"
	for _, part in arrow:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CastShadow = false
			part.Massless = true
		end
	end

	-- Weld arrow to bow handle
	local root = arrow.PrimaryPart or arrow:FindFirstChildWhichIsA("BasePart")
	if not root then arrow:Destroy() return end

	arrow:PivotTo(handle.CFrame * CFrame.Angles(math.rad(-90), 0, 0))
	arrow.Parent = char

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = root
	weld.Parent = root

	activeNockedArrow = arrow
end

local function hideNockedArrow()
	if activeNockedArrow then
		activeNockedArrow:Destroy()
		activeNockedArrow = nil
	end
end

-- ── State ───────────────────────────────────────────────────────────────
local isAiming    = false
local isDrawing   = false
local drawStartTime = 0
local normalFOV   = 70
local normalOffset = Vector3.zero

-- ── UI Elements ─────────────────────────────────────────────────────────
local playerGui = player:WaitForChild("PlayerGui")

-- Crosshair UI
local crosshairGui = Instance.new("ScreenGui")
crosshairGui.Name = "BowCrosshair"
crosshairGui.DisplayOrder = 50
crosshairGui.IgnoreGuiInset = true
crosshairGui.ResetOnSpawn = false
crosshairGui.Enabled = false
crosshairGui.Parent = playerGui

local crosshairFrame = Instance.new("Frame")
crosshairFrame.Name = "Crosshair"
crosshairFrame.Size = UDim2.fromOffset(40, 40)
crosshairFrame.Position = UDim2.fromScale(0.5, 0.5)
crosshairFrame.AnchorPoint = Vector2.new(0.5, 0.5)
crosshairFrame.BackgroundTransparency = 1
crosshairFrame.Parent = crosshairGui

-- Center dot
local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(4, 4)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
dot.BorderSizePixel = 0
dot.Parent = crosshairFrame
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

-- Power ring (grows as you draw)
local powerRing = Instance.new("Frame")
powerRing.Name = "PowerRing"
powerRing.Size = UDim2.fromOffset(20, 20)
powerRing.Position = UDim2.fromScale(0.5, 0.5)
powerRing.AnchorPoint = Vector2.new(0.5, 0.5)
powerRing.BackgroundTransparency = 1
powerRing.Parent = crosshairFrame

local ringStroke = Instance.new("UIStroke")
ringStroke.Thickness = 2
ringStroke.Color = Color3.fromRGB(255, 200, 100)
ringStroke.Transparency = 0.3
ringStroke.Parent = powerRing
Instance.new("UICorner", powerRing).CornerRadius = UDim.new(1, 0)

-- Mobile buttons
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local mobileGui = Instance.new("ScreenGui")
mobileGui.Name = "BowMobileButtons"
mobileGui.DisplayOrder = 51
mobileGui.IgnoreGuiInset = true
mobileGui.ResetOnSpawn = false
mobileGui.Enabled = false
mobileGui.Parent = playerGui

local aimButton = Instance.new("TextButton")
aimButton.Name = "AimButton"
aimButton.Size = UDim2.fromOffset(70, 70)
aimButton.Position = UDim2.new(1, -90, 1, -200)
aimButton.AnchorPoint = Vector2.new(0.5, 0.5)
aimButton.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
aimButton.BackgroundTransparency = 0.3
aimButton.Text = "AIM"
aimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
aimButton.Font = Enum.Font.GothamBold
aimButton.TextSize = 16
aimButton.Parent = mobileGui
Instance.new("UICorner", aimButton).CornerRadius = UDim.new(1, 0)

local fireButton = Instance.new("TextButton")
fireButton.Name = "FireButton"
fireButton.Size = UDim2.fromOffset(70, 70)
fireButton.Position = UDim2.new(1, -90, 1, -290)
fireButton.AnchorPoint = Vector2.new(0.5, 0.5)
fireButton.BackgroundColor3 = Color3.fromRGB(180, 60, 40)
fireButton.BackgroundTransparency = 0.3
fireButton.Text = "FIRE"
fireButton.TextColor3 = Color3.fromRGB(255, 255, 255)
fireButton.Font = Enum.Font.GothamBold
fireButton.TextSize = 16
fireButton.Visible = false
fireButton.Parent = mobileGui
Instance.new("UICorner", fireButton).CornerRadius = UDim.new(1, 0)

-- ── Helpers ─────────────────────────────────────────────────────────────

local function hasBowEquipped(): boolean
	local eqSlot = tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0
	if eqSlot < 1 or eqSlot > 9 then return false end
	local itemId = player:GetAttribute("HotbarSlot" .. eqSlot)
	if type(itemId) ~= "string" or itemId == "" then return false end
	local def = ItemRegistry.get(itemId)
	return def ~= nil and def.weapon ~= nil and def.weapon.kind == "bow"
end

local function getAimDirection(): (Vector3, Vector3)
	-- Raycast from camera through crosshair to find the world target point,
	-- then compute direction from the character's shoot origin to that point.
	-- This corrects for the shoulder camera offset (parallax).
	local ray = camera:ScreenPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		local farPoint = ray.Origin + ray.Direction * 500
		return ray.Direction.Unit, farPoint
	end

	-- Raycast to find what the crosshair is pointing at (up to 500 studs)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = { char }
	local scatter = Workspace:FindFirstChild("Scatter")
	if scatter then table.insert(filterList, scatter) end
	local scatterZones = Workspace:FindFirstChild("ScatterZones")
	if scatterZones then table.insert(filterList, scatterZones) end
	local animalZones = Workspace:FindFirstChild("AnimalZones")
	if animalZones then table.insert(filterList, animalZones) end
	params.FilterDescendantsInstances = filterList

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	local targetPoint: Vector3
	if result then
		targetPoint = result.Position
	else
		-- Nothing hit — aim at a far point along the camera ray
		targetPoint = ray.Origin + ray.Direction * 500
	end

	-- Approximate direction for validation (server recomputes from targetPoint)
	local approxSpawn = root.Position + Vector3.new(0, 1, 0)
	local dir = (targetPoint - approxSpawn).Unit
	return dir, targetPoint
end

-- ── Aim mode ────────────────────────────────────────────────────────────

local function enterAimMode()
	if isAiming then return end
	if not hasBowEquipped() then return end
	isAiming = true

	-- Save normal camera state
	normalFOV = camera.FieldOfView

	-- Show crosshair
	crosshairGui.Enabled = true

	-- Tween camera FOV
	TweenService:Create(camera, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = AIM_FOV,
	}):Play()

	-- Apply shoulder offset via Humanoid camera offset
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		TweenService:Create(hum, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
			CameraOffset = SHOULDER_OFFSET,
		}):Play()
	end

	-- Show fire button on mobile
	if isMobile then
		fireButton.Visible = true
	end
end

local function exitAimMode()
	if not isAiming then return end
	isAiming = false
	isDrawing = false
	hideNockedArrow()

	-- Hide crosshair
	crosshairGui.Enabled = false

	-- Reset camera FOV
	TweenService:Create(camera, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
		FieldOfView = normalFOV,
	}):Play()

	-- Reset shoulder offset
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		TweenService:Create(hum, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			CameraOffset = Vector3.zero,
		}):Play()
	end

	-- Reset power ring
	powerRing.Size = UDim2.fromOffset(20, 20)
	ringStroke.Color = Color3.fromRGB(255, 200, 100)

	-- Hide fire button on mobile
	if isMobile then
		fireButton.Visible = false
	end
end

-- ── Draw & fire ─────────────────────────────────────────────────────────

local function startDraw()
	if not isAiming then return end
	if isDrawing then return end
	isDrawing = true
	drawStartTime = os.clock()
	showNockedArrow()
end

local function releaseFire()
	if not isDrawing then return end
	isDrawing = false
	hideNockedArrow()

	local drawTime = os.clock() - drawStartTime
	if drawTime < DRAW_TIME_MIN then return end -- too quick, don't fire

	drawTime = math.min(drawTime, DRAW_TIME_MAX)
	local aimDir, targetPoint = getAimDirection()

	bowFireRemote:FireServer(aimDir, drawTime, targetPoint)

	-- Reset power ring
	powerRing.Size = UDim2.fromOffset(20, 20)
	ringStroke.Color = Color3.fromRGB(255, 200, 100)
end

-- ── Update loop (power ring) ────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
	-- Show/hide mobile buttons based on bow equipped
	if isMobile then
		mobileGui.Enabled = hasBowEquipped()
	end

	if not isDrawing then return end

	local elapsed = os.clock() - drawStartTime
	local ratio = math.clamp((elapsed - DRAW_TIME_MIN) / (DRAW_TIME_MAX - DRAW_TIME_MIN), 0, 1)

	-- Grow power ring from 20 to 38 pixels
	local ringSize = 20 + ratio * 18
	powerRing.Size = UDim2.fromOffset(ringSize, ringSize)

	-- Color: yellow → green at full draw
	ringStroke.Color = Color3.fromRGB(
		math.floor(255 * (1 - ratio)),
		math.floor(200 + 55 * ratio),
		math.floor(100 * (1 - ratio))
	)
end)

-- ── Input bindings (PC) ─────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not hasBowEquipped() then return end

	-- Right mouse = aim
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		enterAimMode()
		return
	end

	-- Left mouse = draw (while aiming)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isAiming then
			startDraw()
		end
		return
	end
end)

UserInputService.InputEnded:Connect(function(input)
	-- Release right mouse = exit aim
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if isDrawing then
			releaseFire()
		end
		exitAimMode()
		return
	end

	-- Release left mouse = fire
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isDrawing then
			releaseFire()
		end
		return
	end
end)

-- ── Mobile input ────────────────────────────────────────────────────────
if isMobile then
	aimButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			enterAimMode()
		end
	end)
	aimButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			if isDrawing then releaseFire() end
			exitAimMode()
		end
	end)

	fireButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			startDraw()
		end
	end)
	fireButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			releaseFire()
		end
	end)
end

-- ── Unequip detection ───────────────────────────────────────────────────
player:GetAttributeChangedSignal("HotbarEquippedSlot"):Connect(function()
	if not hasBowEquipped() then
		exitAimMode()
	end
end)

-- ── Client-side arrow visuals from other players ────────────────────────
bowArrowSpawnRemote.OnClientEvent:Connect(function(shooter: Player, spawnCFrame: CFrame, direction: Vector3, speed: number, drawRatio: number)
	-- Don't double-render our own arrows (server spawns the authoritative one)
	if shooter == player then return end

	-- Create a simple visual arrow that follows the same physics
	local arrow = Instance.new("Part")
	arrow.Name = "ArrowVisual"
	arrow.Size = Vector3.new(0.1, 0.1, 2.0)
	arrow.Color = Color3.fromRGB(101, 67, 33)
	arrow.Material = Enum.Material.SmoothPlastic
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CastShadow = false
	arrow.CFrame = spawnCFrame
	arrow.Parent = Workspace

	local velocity = direction * speed
	local gravity = bowCfg.ArrowGravity or 50
	local startTime = os.clock()

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not arrow.Parent then conn:Disconnect() return end
		if os.clock() - startTime > 10 then
			arrow:Destroy()
			conn:Disconnect()
			return
		end

		velocity = velocity + Vector3.new(0, -gravity * dt, 0)
		local newPos = arrow.Position + velocity * dt
		arrow.CFrame = CFrame.lookAt(newPos, newPos + velocity.Unit)
	end)

	-- Auto-cleanup after 3s (server handles authoritative arrow lifecycle)
	task.delay(3, function()
		if arrow.Parent then arrow:Destroy() end
		conn:Disconnect()
	end)
end)
