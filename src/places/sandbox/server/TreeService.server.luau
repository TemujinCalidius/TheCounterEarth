-- TreeService.server.luau
-- Manages multi-phase tree lifecycle:
--   Standing tree → fell (tween) → stump + trunk → cut points → log segments → regrowth
-- Listens for TreeFelled BindableEvent from InventoryService when a tree's HP reaches 0.

local Players           = game:GetService("Players")
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local AssetIds       = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AssetIds"))

local TreeConfig = GameplayConfig.Tree or {}
local FALL_DURATION    = TreeConfig.FallDurationSeconds   or 2.0
local FALL_DAMAGE      = TreeConfig.FallDamage            or 20
local FALL_DAMAGE_RAD  = TreeConfig.FallDamageRadius      or 3
local CUT_POINT_HITS   = TreeConfig.Tier0CutPointHits     or 2
local LOGS_PER_TREE    = TreeConfig.Tier0LogsPerTree       or 3
local LOG_DESPAWN_SECS = TreeConfig.LogSegmentDespawnSecs or 600
local RESPAWN_MIN      = TreeConfig.RespawnMinSeconds      or 3600
local RESPAWN_MAX      = TreeConfig.RespawnMaxSeconds      or 5400

-- ── Bindables ────────────────────────────────────────────────────────────
local bindables = ServerStorage:WaitForChild("ServerBindables")

-- Create TreeFelled bindable if it doesn't exist
local treeFelledEvent: BindableEvent = bindables:FindFirstChild("TreeFelled")
if not treeFelledEvent then
	treeFelledEvent = Instance.new("BindableEvent")
	treeFelledEvent.Name = "TreeFelled"
	treeFelledEvent.Parent = bindables
end

-- Inventory access
local invAdd = bindables:WaitForChild("InventoryAdd") :: BindableFunction


-- ── Template lookup ──────────────────────────────────────────────────────
local scatterModels = ServerStorage:WaitForChild("ScatterModels", 10)
local scatterFolder = Workspace:WaitForChild("Scatter", 10)
local scatterZones = Workspace:FindFirstChild("ScatterZones")  -- invisible zone Parts, must exclude from raycasts

local function findTemplate(name: string): Instance?
	if not scatterModels then return nil end
	local tmpl = scatterModels:FindFirstChild(name)
	if tmpl and (tmpl:IsA("Model") or tmpl:IsA("BasePart")) then return tmpl end
	return nil
end

-- ── Helpers ──────────────────────────────────────────────────────────────

local function getModelPosition(model: Model): Vector3?
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	return part and part.Position
end

local function getModelCFrame(model: Model): CFrame?
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	return part and part.CFrame
end


-- ── Cut Point handling ───────────────────────────────────────────────────
-- Cut points are placed in the Scatter folder as standalone Models so the
-- client harvest scan can find them. Each has a TrunkRef ObjectValue linking
-- back to the trunk model.

-- Forward declarations (defined later in file)
local setupCutPointWatcher: (Model, { Model }, Vector3) -> ()
local measureSegment: (Vector3) -> (number, number)

local function createCutPointMarker(offset: CFrame, index: number, trunkModel: Model): Model
	local marker = Instance.new("Model")
	marker.Name = "CutPoint_" .. index
	marker:SetAttribute("_CutPoint", true)
	marker:SetAttribute("_CutPointIndex", index)
	marker:SetAttribute("_NodeHealth", CUT_POINT_HITS)
	marker:SetAttribute("_NodeMaxHealth", CUT_POINT_HITS)
	marker:SetAttribute("_HitCooldown", TreeConfig.Tier0HitCooldown or 1.0)
	marker:SetAttribute("_RequireTool", "tree")
	marker:SetAttribute("_ScatterItem", "oak_tree")  -- for sound mapping
	marker:SetAttribute("_HarvestYieldMin", 0)
	marker:SetAttribute("_HarvestYieldMax", 0)

	-- ObjectValue linking back to the trunk (for watcher)
	local trunkRef = Instance.new("ObjectValue")
	trunkRef.Name = "TrunkRef"
	trunkRef.Value = trunkModel
	trunkRef.Parent = marker

	-- Wood chip particle emitter (burst on chop hit)
	local woodChips = Instance.new("ParticleEmitter")
	woodChips.Name = "WoodChipParticles"
	woodChips.Enabled = false
	woodChips.Color = ColorSequence.new(Color3.fromRGB(160, 110, 50), Color3.fromRGB(120, 80, 40))
	woodChips.Size = NumberSequence.new(0.15, 0.05)
	woodChips.Lifetime = NumberRange.new(0.5, 1.2)
	woodChips.Speed = NumberRange.new(4, 10)
	woodChips.SpreadAngle = Vector2.new(80, 80)
	woodChips.Rate = 0
	woodChips.RotSpeed = NumberRange.new(-180, 180)
	woodChips.Acceleration = Vector3.new(0, -15, 0)

	-- Invisible hit target (only the BillboardGui is visible to the player)
	local part = Instance.new("Part")
	part.Name = "HitTarget"
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.CFrame = offset
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = marker
	marker.PrimaryPart = part
	woodChips.Parent = part

	-- BillboardGui with axe icon + "Chop Here" label
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CutMarker"
	billboard.Size = UDim2.new(0, 80, 0, 60)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 25
	billboard.Parent = part

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, 0, 0.6, 0)
	icon.Position = UDim2.new(0, 0, 0, 0)
	icon.BackgroundTransparency = 1
	icon.Text = "⚒"
	icon.TextSize = 32
	icon.Font = Enum.Font.GothamBold
	icon.TextColor3 = Color3.fromRGB(255, 200, 60)
	icon.TextStrokeTransparency = 0.3
	icon.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	icon.Parent = billboard

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0.4, 0)
	label.Position = UDim2.new(0, 0, 0.6, 0)
	label.BackgroundTransparency = 1
	label.Text = "Chop Here"
	label.TextSize = 14
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 200, 60)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = billboard

	-- Parent to Scatter folder so client harvest scan finds it
	marker.Parent = scatterFolder or Workspace
	return marker
end

-- ── Fall damage check ────────────────────────────────────────────────────

local function checkFallDamage(treeModel: Model, damagedPlayers: { [Player]: boolean })
	local treePos = getModelPosition(treeModel)
	if not treePos then return end

	-- Get bounding box for more accurate collision
	local _, treeSize = treeModel:GetBoundingBox()
	local checkRadius = math.max(treeSize.X, treeSize.Z) * 0.5 + FALL_DAMAGE_RAD

	for _, plr in Players:GetPlayers() do
		if damagedPlayers[plr] then continue end
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			-- Check horizontal distance (tree falls in a direction, check trunk sweep)
			local dist = (Vector3.new(root.Position.X, 0, root.Position.Z)
				- Vector3.new(treePos.X, 0, treePos.Z)).Magnitude
			if dist <= checkRadius then
				-- Also check vertical proximity (player should be near ground level of tree)
				local yDiff = math.abs(root.Position.Y - treePos.Y)
				if yDiff < treeSize.Y + 3 then
					humanoid:TakeDamage(FALL_DAMAGE)
					damagedPlayers[plr] = true
				end
			end
		end
	end
end

-- ── Stump creation ─────────────────────────────────────────────────────

local function spawnStump(basePos: Vector3, scatterItemId: string, originalCFrame: CFrame): Model
	local stumpTemplate = findTemplate("oak_tree_stump")
	local stump: Model
	if stumpTemplate then
		if stumpTemplate:IsA("Model") then
			stump = stumpTemplate:Clone()
		else
			stump = Instance.new("Model")
			local p = stumpTemplate:Clone()
			p.Parent = stump
			stump.PrimaryPart = p
		end
	else
		-- Fallback: short upright block (placeholder stump)
		stump = Instance.new("Model")
		local p = Instance.new("Part")
		p.Name = "Body"
		p.Size = Vector3.new(2, 1.5, 2)
		p.Color = Color3.fromRGB(100, 70, 35)
		p.Anchored = true
		p.CanCollide = true
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = stump
		stump.PrimaryPart = p
	end

	stump.Name = "Oak Stump"
	stump:SetAttribute("_TreeStump", true)
	stump:SetAttribute("_StumpVariant", scatterItemId)
	stump:SetAttribute("_ScatterItem", scatterItemId)

	-- Position stump at original tree base (upright, only Y rotation from original tree)
	if stump.PrimaryPart then
		local bbCFrame, stumpSize = stump:GetBoundingBox()
		local pivotY = stump:GetPivot().Position.Y
		local bbBottomY = bbCFrame.Position.Y - stumpSize.Y * 0.5
		local pivotAboveBottom = pivotY - bbBottomY

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local stumpExcludeList = { scatterFolder }
		if scatterZones then table.insert(stumpExcludeList, scatterZones) end
		rayParams.FilterDescendantsInstances = stumpExcludeList
		local groundRay = Workspace:Raycast(
			basePos + Vector3.new(0, 5, 0), Vector3.new(0, -30, 0), rayParams
		)
		local groundY = groundRay and groundRay.Position.Y or basePos.Y

		local _, origYRot, _ = originalCFrame:ToEulerAnglesYXZ()
		stump:PivotTo(CFrame.new(basePos.X, groundY + pivotAboveBottom, basePos.Z)
			* CFrame.Angles(0, origYRot, 0))
	end

	for _, desc in stump:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = true
		end
	end

	stump.Parent = scatterFolder or Workspace
	return stump
end

-- ── Tree Fell sequence ───────────────────────────────────────────────────

local function fellTree(treeModel: Model, fellingPlayer: Player)
	-- Save original state before manipulation
	local originalCFrame = getModelCFrame(treeModel)
	if not originalCFrame then return end
	local originalPos = originalCFrame.Position
	local scatterItemId = treeModel:GetAttribute("_ScatterItem") or "oak_tree"

	-- Mark as falling (prevents further harvest hits)
	treeModel:SetAttribute("_TreePhase", "falling")
	treeModel:SetAttribute("_NodeHealth", 0)

	-- Calculate fall direction (away from player)
	local playerPos = fellingPlayer.Character
		and fellingPlayer.Character:FindFirstChild("HumanoidRootPart")
		and fellingPlayer.Character.HumanoidRootPart.Position
	local fallDir: Vector3
	if playerPos then
		fallDir = (originalPos - playerPos)
		fallDir = Vector3.new(fallDir.X, 0, fallDir.Z)
		if fallDir.Magnitude < 0.1 then
			fallDir = Vector3.new(1, 0, 0)
		end
		fallDir = fallDir.Unit
	else
		local angle = math.random() * math.pi * 2
		fallDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	end

	-- Play tree fall sound
	local fallSoundId = AssetIds.Sounds and AssetIds.Sounds.TreeFall or ""
	if fallSoundId ~= "" then
		local rootPart = treeModel.PrimaryPart or treeModel:FindFirstChildWhichIsA("BasePart")
		if rootPart then
			local sound = Instance.new("Sound")
			sound.SoundId = fallSoundId
			sound.Volume = 1.0
			sound.RollOffMaxDistance = 60
			sound.Parent = rootPart
			sound:Play()
			sound.Ended:Once(function() sound:Destroy() end)
		end
	end

	-- Get the tree's bounding box to calculate hinge at base
	local bbCFrame, treeSize = treeModel:GetBoundingBox()
	local treeHeight = treeSize.Y

	local rootPart = treeModel.PrimaryPart or treeModel:FindFirstChildWhichIsA("BasePart")
	if not rootPart then return end

	-- Save the tree's actual current pivot so t=0 matches exactly (no jump)
	local originalPivot = treeModel:GetPivot()

	-- Hinge point: bottom of bounding box
	local basePos = Vector3.new(bbCFrame.Position.X, bbCFrame.Position.Y - treeHeight * 0.5, bbCFrame.Position.Z)

	-- Rotation axis: perpendicular to fall direction, horizontal
	local rotAxis = Vector3.new(0, 1, 0):Cross(fallDir).Unit

	-- Offset from hinge to the model's pivot (rotated during tween)
	local pivotOffsetFromBase = originalPivot.Position - basePos

	-- Spawn stump immediately (visible as tree starts tipping)
	local stump = spawnStump(basePos, scatterItemId, originalCFrame)

	-- Stump clearance for trunk placement
	local stumpClearance = 1.5
	if stump then
		local _, stumpSize = stump:GetBoundingBox()
		stumpClearance = math.max(stumpSize.X, stumpSize.Z) * 0.5 + 0.5
	end

	-- Measure segment length
	local segLength, _ = measureSegment(fallDir)

	-- Raycast ground Y at each segment position from tree-top height.
	-- Tree top is guaranteed to be above terrain at any nearby position.
	local rayOriginY = basePos.Y + treeHeight + 5  -- a bit above tree top for safety
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList = { scatterFolder }
	if scatterZones then table.insert(excludeList, scatterZones) end
	rayParams.FilterDescendantsInstances = excludeList

	local groundYValues: { number } = {}
	for i = 1, 3 do
		local segOffset = stumpClearance + (i - 0.5) * segLength
		local segXZ = basePos + fallDir * segOffset
		local ray = Workspace:Raycast(
			Vector3.new(segXZ.X, rayOriginY, segXZ.Z),
			Vector3.new(0, -60, 0), rayParams
		)
		local groundY = ray and ray.Position.Y or basePos.Y
		table.insert(groundYValues, groundY)
		warn(("[TreeService] Raycast seg %d: origin Y=%.1f, hit=%s, groundY=%.1f, hitInstance=%s"):format(
			i, rayOriginY, tostring(ray ~= nil), groundY,
			ray and ray.Instance and ray.Instance:GetFullName() or "nil"
		))
	end
	warn(("[TreeService] basePos Y=%.1f, treeHeight=%.1f, segLength=%.1f, stumpClearance=%.1f"):format(
		basePos.Y, treeHeight, segLength, stumpClearance
	))

	local startTime = os.clock()
	local damagedPlayers: { [Player]: boolean } = {}
	local DAMAGE_DELAY = 1.0

	local fallConnection: RBXScriptConnection
	fallConnection = RunService.Heartbeat:Connect(function()
		if not treeModel.Parent then
			fallConnection:Disconnect()
			return
		end

		local elapsed = os.clock() - startTime
		local t = math.min(elapsed / FALL_DURATION, 1)

		local easedT = t * t
		local angle = easedT * math.rad(90)
		local fallRotation = CFrame.fromAxisAngle(rotAxis, angle)
		local rotatedOffset = fallRotation:VectorToWorldSpace(pivotOffsetFromBase)
		local newPivotPos = basePos + rotatedOffset
		local pivotCFrame = CFrame.new(newPivotPos) * fallRotation * originalPivot.Rotation

		treeModel:PivotTo(pivotCFrame)

		if elapsed >= DAMAGE_DELAY then
			checkFallDamage(treeModel, damagedPlayers)
		end

		if t >= 1 then
			fallConnection:Disconnect()

			task.defer(function()
				onTreeLanded(treeModel, basePos, scatterItemId, originalCFrame, stump, groundYValues)
			end)
		end
	end)
end

-- ── Trunk helpers ────────────────────────────────────────────────────────

-- Clone an oak_log_segment template for visual use or physics pickup.
local function cloneLogSegment(index: number): Model
	local template = findTemplate("oak_log_segment")
	local model: Model
	if template then
		if template:IsA("Model") then
			model = template:Clone()
		else
			model = Instance.new("Model")
			local part = template:Clone()
			part.Parent = model
			model.PrimaryPart = part
		end
	else
		model = Instance.new("Model")
		local part = Instance.new("Part")
		part.Name = "Body"
		part.Size = Vector3.new(2, 0.8, 0.8)
		part.Color = Color3.fromRGB(120, 80, 40)
		part.Material = Enum.Material.Wood
		part.Parent = model
		model.PrimaryPart = part
	end
	model.Name = "Log Segment " .. index
	return model
end

-- Measure a log segment's PrimaryPart dimensions.
-- Returns segLength (along trunk = PrimaryPart Z) and segHeight (vertical = PrimaryPart Y).
-- Uses PrimaryPart size directly to avoid bounding-box inflation from decorative parts.
measureSegment = function(_direction: Vector3): (number, number)
	local model = cloneLogSegment(0)
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local segLen = 2
	local segH = 1
	if primary then
		-- Log segments are oriented so Z = length, Y = height (lying on ground)
		segLen = primary.Size.Z
		segH = primary.Size.Y
		if segLen < 0.5 then segLen = 2 end
		if segH < 0.2 then segH = 1 end
	end
	model:Destroy()
	return segLen, segH
end

-- Spawn a pickup-able log segment with physics kick at a world position.
local function spawnPickupLog(position: Vector3, direction: Vector3, kickDir: Vector3, index: number)
	local model = cloneLogSegment(index)
	model:SetAttribute("_TrunkSegment", true)
	model:SetAttribute("_LogItemId", "oak_log")

	-- Orient and place
	local cf = CFrame.lookAt(position, position + Vector3.new(direction.X, 0, direction.Z))
	model:PivotTo(cf)

	-- All parts: unanchored, collidable, for physics
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = true
		end
	end

	model.Parent = scatterFolder or Workspace

	-- Kick it away
	local rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if rootPart then
		local impulse = kickDir * 6 + Vector3.new(0, 3, 0)
		rootPart:ApplyImpulse(impulse * rootPart.AssemblyMass)
		rootPart:ApplyAngularImpulse(Vector3.new(
			(math.random() - 0.5) * 3,
			(math.random() - 0.5) * 1,
			(math.random() - 0.5) * 3
		) * rootPart.AssemblyMass)
	end

	-- Re-anchor after physics settles
	task.delay(4, function()
		if model and model.Parent then
			for _, desc in model:GetDescendants() do
				if desc:IsA("BasePart") then desc.Anchored = true end
			end
		end
	end)

	-- ProximityPrompt for pickup
	if rootPart then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pick Up"
		prompt.ObjectText = "Oak Log"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = rootPart

		prompt.Triggered:Connect(function(pickupPlayer)
			if not model.Parent then return end
			if invAdd:Invoke(pickupPlayer, "oak_log", 1) then
				model:Destroy()
			end
		end)
	end

	-- Auto-despawn
	task.delay(LOG_DESPAWN_SECS, function()
		if model and model.Parent then model:Destroy() end
	end)
end

-- ── Post-fall: place anchored trunk at ground level ─────────────────────
-- No invisible core, no physics. Each segment is anchored to the terrain
-- using pivotAboveBottom (same technique as stump placement, which works).
-- On chop: visual segment vanishes, pickup log spawns with physics.

function onTreeLanded(treeModel: Model, basePos: Vector3, scatterItemId: string, originalCFrame: CFrame, stump: Model, groundYValues: { number })
	if not treeModel.Parent then return end

	-- 1. Capture the fallen tree's direction before destroying it
	local trunkBBCF, trunkSize = treeModel:GetBoundingBox()

	local trunkDir: Vector3
	if trunkSize.X >= trunkSize.Y and trunkSize.X >= trunkSize.Z then
		trunkDir = trunkBBCF.RightVector
	elseif trunkSize.Y >= trunkSize.X and trunkSize.Y >= trunkSize.Z then
		trunkDir = trunkBBCF.UpVector
	else
		trunkDir = trunkBBCF.LookVector
	end

	treeModel:Destroy()

	local trunkDirFlat = Vector3.new(trunkDir.X, 0, trunkDir.Z)
	if trunkDirFlat.Magnitude < 0.1 then trunkDirFlat = Vector3.new(1, 0, 0) end
	trunkDirFlat = trunkDirFlat.Unit

	-- 2. Compute pivotAboveBottom from a reference segment
	--    Same technique as stump placement: measures actual pivot offset
	--    so PivotTo places the model's bounding box bottom exactly on terrain.
	local refSeg = cloneLogSegment(0)
	local refOrient = CFrame.lookAt(Vector3.zero, Vector3.new(trunkDirFlat.X, 0, trunkDirFlat.Z))
	refSeg:PivotTo(refOrient)
	local refBBCF, refBBSize = refSeg:GetBoundingBox()
	local refPivotY = refSeg:GetPivot().Position.Y
	local refBBBottomY = refBBCF.Position.Y - refBBSize.Y * 0.5
	local pivotAboveBottom = refPivotY - refBBBottomY
	local bbHalfHeight = refBBSize.Y * 0.5
	refSeg:Destroy()

	-- 3. Compute segment layout
	local segLength, _ = measureSegment(trunkDirFlat)
	local stumpClearance = 1.5
	if stump then
		local _, stumpSize = stump:GetBoundingBox()
		stumpClearance = math.max(stumpSize.X, stumpSize.Z) * 0.5 + 0.5
	end

	-- Use average ground Y so all 3 segments sit at the same height (joined trunk)
	local avgGroundY = (groundYValues[1] + groundYValues[2] + groundYValues[3]) / 3
	warn(("[TreeService] pivotAboveBottom=%.2f, bbHalfHeight=%.2f, avgGroundY=%.1f, placement Y=%.1f"):format(
		pivotAboveBottom, bbHalfHeight, avgGroundY, avgGroundY + pivotAboveBottom
	))

	-- 4. Build trunk container model
	local trunk = Instance.new("Model")
	trunk.Name = "Fallen Oak"
	trunk:SetAttribute("_TreePhase", "trunk")
	trunk:SetAttribute("_ScatterItem", scatterItemId)

	-- Place 3 visual log segments end-to-end at uniform height
	local visualSegments: { Model } = {}
	for i = 1, 3 do
		local seg = cloneLogSegment(i)
		local segOffset = stumpClearance + (i - 0.5) * segLength
		local segXZ = basePos + trunkDirFlat * segOffset

		seg:PivotTo(CFrame.lookAt(
			Vector3.new(segXZ.X, avgGroundY + pivotAboveBottom, segXZ.Z),
			Vector3.new(segXZ.X + trunkDirFlat.X, avgGroundY + pivotAboveBottom, segXZ.Z + trunkDirFlat.Z)
		))

		for _, desc in seg:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = true
			end
		end

		seg.Parent = trunk
		table.insert(visualSegments, seg)

		if i == 1 then
			trunk.PrimaryPart = seg.PrimaryPart or seg:FindFirstChildWhichIsA("BasePart")
		end
	end

	trunk.Parent = scatterFolder or Workspace

	-- 5. Place cut point markers between segments
	for cpIdx = 1, 2 do
		local cpOffset = stumpClearance + cpIdx * segLength
		local cpXZ = basePos + trunkDirFlat * cpOffset
		createCutPointMarker(CFrame.new(cpXZ.X, avgGroundY + bbHalfHeight + 1.5, cpXZ.Z), cpIdx, trunk)
	end

	-- 6. Set up cut point watcher
	setupCutPointWatcher(trunk, visualSegments, trunkDirFlat)

	-- 7. Schedule regrowth on the stump
	local respawnDelay = RESPAWN_MIN + math.random() * (RESPAWN_MAX - RESPAWN_MIN)
	task.delay(respawnDelay, function()
		regrowTree(stump, scatterItemId, originalCFrame)
	end)
end

-- ── Regrowth ─────────────────────────────────────────────────────────────

function regrowTree(stump: Model, scatterItemId: string, originalCFrame: CFrame)
	if not stump or not stump.Parent then return end

	local stumpPos = getModelPosition(stump)
	if not stumpPos then
		stump:Destroy()
		return
	end

	-- Find a matching tree template
	local templates = { "oak_tree_1", "oak_tree_2", "oak_tree_3" }
	local templateName = templates[math.random(1, #templates)]
	local template = findTemplate(templateName)

	local newTree: Model
	if template then
		if template:IsA("Model") then
			newTree = template:Clone()
		else
			newTree = Instance.new("Model")
			local part = template:Clone()
			part.Parent = newTree
			newTree.PrimaryPart = part
		end
	else
		-- Fallback placeholder
		newTree = Instance.new("Model")
		local part = Instance.new("Part")
		part.Name = "Body"
		part.Size = Vector3.new(2, 14, 2)
		part.Color = Color3.fromRGB(60, 100, 40)
		part.Anchored = true
		part.CanCollide = true
		part.Material = Enum.Material.SmoothPlastic
		part.CFrame = CFrame.new(stumpPos + Vector3.new(0, 4, 0))
		part.Parent = newTree
		newTree.PrimaryPart = part
	end

	-- Set up as a new tree
	local treeCfg = GameplayConfig.Tree or {}
	newTree.Name = "Oak Tree"
	newTree:SetAttribute("_ScatterItem", scatterItemId)
	newTree:SetAttribute("_IsTree", true)
	newTree:SetAttribute("_TreePhase", "standing")
	newTree:SetAttribute("_NodeHealth", treeCfg.Tier0NodeHealth or 8)
	newTree:SetAttribute("_NodeMaxHealth", treeCfg.Tier0NodeHealth or 8)
	newTree:SetAttribute("_HarvestYieldMin", 0)
	newTree:SetAttribute("_HarvestYieldMax", 0)
	newTree:SetAttribute("_HitCooldown", treeCfg.Tier0HitCooldown or 1.8)
	newTree:SetAttribute("_RequireTool", "tree")

	for _, desc in newTree:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = true
		end
	end

	-- Position at stump location
	local _, treeSize = newTree:GetBoundingBox()
	newTree:PivotTo(CFrame.new(stumpPos.X, stumpPos.Y + treeSize.Y * 0.5 - 0.5, stumpPos.Z)
		* CFrame.Angles(0, math.random() * math.pi * 2, 0))

	newTree.Parent = scatterFolder or Workspace

	-- Destroy the stump
	stump:Destroy()
end

-- ── Cut Point hit handling ───────────────────────────────────────────────
-- Cut points live in the Scatter folder (so the client harvest scan finds them).
-- Each has a TrunkRef ObjectValue pointing at the trunk model.
-- When InventoryService destroys a cut point (HP reaches 0), we detect it here.

setupCutPointWatcher = function(
	trunkModel: Model,
	visualSegments: { Model },
	trunkDirFlat: Vector3
)
	-- Find cut points in Scatter folder that reference this trunk
	local targetFolder = scatterFolder or Workspace
	local cutPoints: { Model } = {}
	for _, child in targetFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("_CutPoint") then
			local ref = child:FindFirstChild("TrunkRef")
			if ref and ref:IsA("ObjectValue") and ref.Value == trunkModel then
				table.insert(cutPoints, child)
			end
		end
	end

	-- Perpendicular to trunk (for sideways kick on middle segment)
	local sideDir = Vector3.new(0, 1, 0):Cross(trunkDirFlat).Unit

	local cutPointsDestroyed = 0

	-- Watch each cut point for destruction (InventoryService destroys them when HP=0)
	for _, cp in cutPoints do
		local savedIndex: number = cp:GetAttribute("_CutPointIndex") or 0

		cp.AncestryChanged:Connect(function()
			if cp.Parent then return end -- only care about removal
			cutPointsDestroyed += 1

			-- Hide the visual segment + spawn a physics pickup log
			local segIndex: number
			local kickDir: Vector3

			if savedIndex == 1 then
				segIndex = 1
				kickDir = -trunkDirFlat  -- kick toward stump
			elseif savedIndex == 2 then
				segIndex = 3
				kickDir = trunkDirFlat   -- kick away from stump
			end

			if segIndex then
				-- Get spawn position from the visual segment's actual position
				local visSeg = visualSegments[segIndex]
				local visPos = visSeg and getModelPosition(visSeg)

				-- Hide visual segment
				if visSeg and visSeg.Parent then
					for _, desc in visSeg:GetDescendants() do
						if desc:IsA("BasePart") then desc.Transparency = 1 end
					end
				end

				-- Spawn pickup log at the visual segment's actual position
				if visPos then
					spawnPickupLog(visPos, trunkDirFlat, kickDir, segIndex)
				end
			end

			-- After both cut points are chopped, spawn middle log and destroy trunk
			if cutPointsDestroyed >= 2 then
				task.delay(0.3, function()
					-- Spawn middle segment from its actual position
					local midSeg = visualSegments[2]
					local midPos = midSeg and getModelPosition(midSeg)
					if midPos then
						spawnPickupLog(midPos, trunkDirFlat, sideDir, 2)
					end

					-- Destroy the entire trunk
					if trunkModel and trunkModel.Parent then
						trunkModel:Destroy()
					end
				end)
			end
		end)
	end
end

-- ── Event listener ───────────────────────────────────────────────────────

treeFelledEvent.Event:Connect(function(treeModel: Model, fellingPlayer: Player)
	if not treeModel or not treeModel.Parent then return end
	if not treeModel:GetAttribute("_IsTree") then return end

	fellTree(treeModel, fellingPlayer)
end)
