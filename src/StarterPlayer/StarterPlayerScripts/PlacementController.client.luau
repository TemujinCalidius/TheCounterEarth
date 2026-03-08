-- PlacementController.client.luau
-- Handles ghost-preview placement mode for placeable items (campfire, bedroll, etc).
--
-- Other client scripts fire the BindableEvent "StartPlacement" with an itemId
-- to enter placement mode. Left-click confirms, right-click / Escape cancels.

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

-- ── State ───────────────────────────────────────────────────────────────────

local isPlacing        = false
local currentItemId    = ""
local ghostModel: Model? = nil
local ghostParts: { BasePart } = {}
local originalColors: { [BasePart]: Color3 } = {}
local isValidPlacement = false
local renderConnection: RBXScriptConnection? = nil

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function setGhostColor(color: Color3)
	for _, part in ipairs(ghostParts) do
		part.Color = color
	end
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

			-- Position ghost on the surface
			local primary = ghostModel.PrimaryPart
			if primary then
				local yOffset = primary.Size.Y * 0.5
				ghostModel:PivotTo(CFrame.new(hitPos + Vector3.new(0, yOffset, 0)))
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
		else
			isValidPlacement = false
		end

		setGhostColor(isValidPlacement and VALID_COLOR or INVALID_COLOR)
	end)
end

-- ── Input handling ──────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, _gameProcessed)
	if not isPlacing then return end

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
