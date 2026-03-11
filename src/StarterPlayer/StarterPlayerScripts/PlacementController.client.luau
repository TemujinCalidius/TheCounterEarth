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

		-- Raycast from mouse position
		local mouseLocation = UserInputService:GetMouseLocation()
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

-- ── Input handling ──────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, _gameProcessed)
	if not isPlacing then return end

	-- R key: rotate ghost
	if input.KeyCode == Enum.KeyCode.R then
		ghostRotation = ghostRotation + ROTATE_INCREMENT
		return
	end

	-- Left click: confirm placement
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isValidPlacement and ghostModel and ghostModel.PrimaryPart then
			local placementCFrame = ghostModel:GetPivot()
			placeItemRemote:FireServer(currentItemId, placementCFrame)
		end
		cleanupGhost()
		return
	end

	-- Right click or Escape: cancel
	if input.UserInputType == Enum.UserInputType.MouseButton2
		or input.KeyCode == Enum.KeyCode.Escape then
		cleanupGhost()
		return
	end
end)

-- ── Listen for placement requests from other client scripts ─────────────────

startPlacementEvent.Event:Connect(function(itemId)
	if type(itemId) == "string" and itemId ~= "" then
		startPlacement(itemId)
	end
end)
