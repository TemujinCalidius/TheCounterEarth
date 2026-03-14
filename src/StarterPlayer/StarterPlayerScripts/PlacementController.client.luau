-- PlacementController.client.luau
-- Handles ghost-preview placement mode for placeable items (campfire, bedroll, etc).
--
-- Other client scripts fire the BindableEvent "StartPlacement" with an itemId
-- to enter placement mode. Left-click confirms, right-click / Escape cancels.
-- R key rotates the ghost in 15° increments.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")

local Config       = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local ItemRegistry = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local isMobile = UserInputService.TouchEnabled

local remotes        = ReplicatedStorage:WaitForChild("Remotes")
local placeItemRemote = remotes:WaitForChild("PlaceItem") :: RemoteEvent

-- ── BindableEvent for cross-script communication ────────────────────────────

local clientBindables = ReplicatedStorage:FindFirstChild("ClientBindables")
if not clientBindables then
	clientBindables = Instance.new("Folder")
	clientBindables.Name = "ClientBindables"
	clientBindables.Parent = ReplicatedStorage
end

local startPlacementEvent = Instance.new("BindableEvent")
startPlacementEvent.Name = "StartPlacement"
startPlacementEvent.Parent = clientBindables

-- ── Config ──────────────────────────────────────────────────────────────────

local GHOST_TRANSPARENCY = 0.5
local VALID_COLOR        = Color3.fromRGB(80, 220, 100)
local INVALID_COLOR      = Color3.fromRGB(220, 60, 60)
local MAX_RANGE          = (Config.Campfire and Config.Campfire.PlacementMaxRange) or 20
local RAYCAST_DISTANCE   = 200
local ROTATE_INCREMENT   = math.rad(15) -- 15° per R press
local BEDROLL_CAMPFIRE_RADIUS = (Config.Bedroll and Config.Bedroll.RequiredCampfireRadius) or 25

-- ── State ───────────────────────────────────────────────────────────────────

local isPlacing        = false
local currentItemId    = ""
local ghostModel: Model? = nil
local ghostParts: { BasePart } = {}
local originalColors: { [BasePart]: Color3 } = {}
local isValidPlacement = false
local renderConnection: RBXScriptConnection? = nil
local ghostRotation: number = 0
local needsCampfire: boolean = false  -- true when bedroll is too far from campfire

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

-- ── Hint label (shows "Requires Campfire nearby") ───────────────────────────

local hintGui = Instance.new("ScreenGui")
hintGui.Name            = "PlacementHint"
hintGui.ResetOnSpawn    = false
hintGui.IgnoreGuiInset  = true
hintGui.Parent          = player.PlayerGui

local hintLabel = Instance.new("TextLabel")
hintLabel.Size                  = UDim2.new(0, 300, 0, 30)
hintLabel.Position              = UDim2.new(0.5, -150, 0.75, 0)
hintLabel.BackgroundTransparency = 0.4
hintLabel.BackgroundColor3      = Color3.fromRGB(30, 30, 30)
hintLabel.TextColor3            = Color3.fromRGB(255, 100, 100)
hintLabel.Font                  = Enum.Font.GothamBold
hintLabel.TextSize              = 14
hintLabel.Text                  = "Requires Campfire nearby"
hintLabel.Visible               = false
hintLabel.ZIndex                = 10
hintLabel.Parent                = hintGui

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 6)
hintCorner.Parent       = hintLabel

-- ── Mobile placement crosshair ────────────────────────────────────────────
-- On mobile, the ghost follows the center of the screen (camera forward raycast)
-- instead of finger position. Player moves & rotates camera to aim.
-- A small crosshair dot shows the aim point.

local crosshairGui: ScreenGui? = nil
local crosshairDot: Frame? = nil

if isMobile then
	crosshairGui = Instance.new("ScreenGui")
	crosshairGui.Name           = "PlacementCrosshair"
	crosshairGui.ResetOnSpawn   = false
	crosshairGui.IgnoreGuiInset = true
	crosshairGui.DisplayOrder   = 5
	crosshairGui.Parent         = player.PlayerGui

	crosshairDot = Instance.new("Frame")
	crosshairDot.Name                   = "Dot"
	crosshairDot.Size                   = UDim2.new(0, 12, 0, 12)
	crosshairDot.Position               = UDim2.new(0.5, -6, 0.5, -6)
	crosshairDot.BackgroundColor3       = Color3.fromRGB(220, 220, 220)
	crosshairDot.BackgroundTransparency = 0.3
	crosshairDot.Visible                = false
	crosshairDot.ZIndex                 = 10
	crosshairDot.Parent                 = crosshairGui

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0) -- circle
	dotCorner.Parent = crosshairDot

	local dotStroke = Instance.new("UIStroke")
	dotStroke.Color       = Color3.fromRGB(40, 40, 40)
	dotStroke.Thickness   = 1
	dotStroke.Transparency = 0.3
	dotStroke.Parent      = crosshairDot
end

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function setGhostColor(color: Color3)
	for _, part in ipairs(ghostParts) do
		part.Color = color
	end
end

-- Check if any placed campfire is within radius of a world position.
local function isCampfireNearby(pos: Vector3): boolean
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("_PlacedItem") == "campfire" then
			local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
			if primary and (primary.Position - pos).Magnitude <= BEDROLL_CAMPFIRE_RADIUS then
				return true
			end
		end
	end
	return false
end

local function cleanupGhost()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if ghostModel then
		ghostModel:Destroy()
		ghostModel = nil
	end
	ghostParts = {}
	originalColors = {}
	isPlacing = false
	currentItemId = ""
	ghostRotation = 0
	needsCampfire = false
	hintLabel.Visible = false
	player:SetAttribute("IsPlacementMode", false)
	if crosshairDot then crosshairDot.Visible = false end
end

-- ── Placement mode ──────────────────────────────────────────────────────────

local function startPlacement(itemId: string)
	if isPlacing then cleanupGhost() end

	local def = ItemRegistry.get(itemId)
	if not def or def.category ~= "placeable" then return end

	local ghostsFolder = ReplicatedStorage:FindFirstChild("PlaceableGhosts")
	if not ghostsFolder then return end
	local template = ghostsFolder:FindFirstChild(itemId)
	if not template or not template:IsA("Model") then return end

	isPlacing = true
	currentItemId = itemId
	ghostRotation = 0
	player:SetAttribute("IsPlacementMode", true)

	ghostModel = template:Clone()

	-- Make all parts transparent and non-interactive
	ghostParts = {}
	originalColors = {}
	for _, desc in ipairs(ghostModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			originalColors[desc] = desc.Color
			desc.Transparency = GHOST_TRANSPARENCY
			desc.CanCollide   = false
			desc.CanTouch     = false
			desc.CanQuery     = false
			desc.Anchored     = true
			desc.CastShadow   = false
			table.insert(ghostParts, desc)
		end
	end

	ghostModel.Parent = workspace

	-- Show crosshair on mobile (ghost follows screen center)
	if crosshairDot then crosshairDot.Visible = true end

	-- Render loop: move ghost to mouse raycast position
	renderConnection = RunService.RenderStepped:Connect(function()
		if not ghostModel or not ghostModel.Parent then
			cleanupGhost()
			return
		end

		-- Build exclusion filter
		local filterList: { Instance } = { ghostModel }
		if player.Character then
			table.insert(filterList, player.Character)
		end
		raycastParams.FilterDescendantsInstances = filterList

		-- Raycast from mouse position (PC) or screen center (mobile)
		local mouseLocation: Vector2
		if isMobile then
			local vpSize = camera.ViewportSize
			mouseLocation = Vector2.new(vpSize.X * 0.5, vpSize.Y * 0.5)
		else
			mouseLocation = UserInputService:GetMouseLocation()
		end
		local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
		local result = workspace:Raycast(ray.Origin, ray.Direction * RAYCAST_DISTANCE, raycastParams)

		if result then
			local hitPos = result.Position

			-- Position ghost on the surface with rotation
			local primary = ghostModel.PrimaryPart
			if primary then
				local yOffset = primary.Size.Y * 0.5
				ghostModel:PivotTo(
					CFrame.new(hitPos + Vector3.new(0, yOffset, 0))
					* CFrame.Angles(0, ghostRotation, 0)
				)
			end

			-- Range check
			local rootPart = player.Character
				and player.Character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local dist = (hitPos - rootPart.Position).Magnitude
				isValidPlacement = dist <= MAX_RANGE
			else
				isValidPlacement = false
			end

			-- Bedroll: must be near a campfire
			needsCampfire = false
			if isValidPlacement and currentItemId == "bedroll" then
				if not isCampfireNearby(hitPos) then
					isValidPlacement = false
					needsCampfire = true
				end
			end
		else
			isValidPlacement = false
			needsCampfire = false
		end

		hintLabel.Visible = needsCampfire
		setGhostColor(isValidPlacement and VALID_COLOR or INVALID_COLOR)
	end)
end

-- ── Mobile placement buttons (rotate / cancel) ────────────────────────────

local rotateBtn: TextButton? = nil
local cancelBtn: TextButton? = nil
local placeBtn: TextButton? = nil

local function setMobileButtonsVisible(visible: boolean)
	if rotateBtn then rotateBtn.Visible = visible end
	if cancelBtn then cancelBtn.Visible = visible end
	if placeBtn then placeBtn.Visible = visible end
end

if isMobile then
	local placementGui = Instance.new("ScreenGui")
	placementGui.Name           = "PlacementButtons"
	placementGui.ResetOnSpawn   = false
	placementGui.IgnoreGuiInset = true
	placementGui.DisplayOrder   = 10
	placementGui.Parent         = player.PlayerGui

	local function makeBtn(name: string, text: string, posX: number): TextButton
		local btn = Instance.new("TextButton")
		btn.Name                    = name
		btn.Size                    = UDim2.new(0, 56, 0, 56)
		btn.Position                = UDim2.new(1, posX, 1, -280)
		btn.AnchorPoint             = Vector2.new(1, 1)
		btn.BackgroundColor3        = Color3.fromRGB(42, 48, 66)
		btn.BackgroundTransparency  = 0.3
		btn.Text                    = text
		btn.TextColor3              = Color3.fromRGB(200, 210, 230)
		btn.Font                    = Enum.Font.GothamBold
		btn.TextSize                = 16
		btn.Visible                 = false
		btn.ZIndex                  = 20
		btn.Parent                  = placementGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Color     = Color3.fromRGB(70, 130, 200)
		stroke.Thickness = 1.5
		stroke.Parent    = btn

		return btn
	end

	placeBtn  = makeBtn("PlaceBtn", "PLACE", -150)
	placeBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60) -- green = confirm
	placeBtn.Size = UDim2.new(0, 70, 0, 56) -- wider to fit text

	rotateBtn = makeBtn("RotateBtn", "R", -80)
	cancelBtn = makeBtn("CancelBtn", "X", -10)

	placeBtn.Activated:Connect(function()
		if isPlacing then
			if isValidPlacement and ghostModel and ghostModel.PrimaryPart then
				local placementCFrame = ghostModel:GetPivot()
				placeItemRemote:FireServer(currentItemId, placementCFrame)
			end
			cleanupGhost()
			setMobileButtonsVisible(false)
		end
	end)

	rotateBtn.Activated:Connect(function()
		if isPlacing then
			ghostRotation = ghostRotation + ROTATE_INCREMENT
		end
	end)

	cancelBtn.Activated:Connect(function()
		if isPlacing then
			cleanupGhost()
			setMobileButtonsVisible(false)
		end
	end)
end

-- ── Input handling ──────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, _gameProcessed)
	if not isPlacing then return end

	-- R key: rotate ghost
	if input.KeyCode == Enum.KeyCode.R then
		ghostRotation = ghostRotation + ROTATE_INCREMENT
		return
	end

	-- Left click: confirm placement (PC only — mobile uses PLACE button)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isValidPlacement and ghostModel and ghostModel.PrimaryPart then
			local placementCFrame = ghostModel:GetPivot()
			placeItemRemote:FireServer(currentItemId, placementCFrame)
		end
		cleanupGhost()
		setMobileButtonsVisible(false)
		return
	end

	-- Right click or Escape: cancel
	if input.UserInputType == Enum.UserInputType.MouseButton2
		or input.KeyCode == Enum.KeyCode.Escape then
		cleanupGhost()
		setMobileButtonsVisible(false)
		return
	end
end)

-- ── Listen for placement requests from other client scripts ─────────────────

startPlacementEvent.Event:Connect(function(itemId)
	if type(itemId) == "string" and itemId ~= "" then
		startPlacement(itemId)
		setMobileButtonsVisible(true)
	end
end)
