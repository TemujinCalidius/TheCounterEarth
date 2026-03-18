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
local scatterModels = ServerStorage:FindFirstChild("ScatterModels")
local scatterFolder = Workspace:FindFirstChild("Scatter")

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

-- Forward declaration (defined after regrowTree)
local setupCutPointWatcher: (Model) -> ()

local function createCutPointMarker(offset: CFrame, index: number, trunkModel: Model): Model
	local marker = Instance.new("Model")
	marker.Name = "CutPoint_" .. index
	marker:SetAttribute("_CutPoint", true)
	marker:SetAttribute("_CutPointIndex", index)
	marker:SetAttribute("_NodeHealth", CUT_POINT_HITS)
	marker:SetAttribute("_NodeMaxHealth", CUT_POINT_HITS)
	marker:SetAttribute("_HitCooldown", 1.2)
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

-- ── Log Segment creation ─────────────────────────────────────────────────

local function createLogSegment(position: Vector3)
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
		-- Fallback: small brown log block
		model = Instance.new("Model")
		local part = Instance.new("Part")
		part.Name = "Body"
		part.Size = Vector3.new(2, 0.8, 0.8)
		part.Color = Color3.fromRGB(120, 80, 40)
		part.Material = Enum.Material.SmoothPlastic
		part.Parent = model
		model.PrimaryPart = part
	end

	model.Name = "Oak Log"
	model:SetAttribute("_TrunkSegment", true)
	model:SetAttribute("_LogItemId", "oak_log")

	-- Anchor and position
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = true
		end
	end

	-- Raycast to ground for placement
	local rayResult = Workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -20, 0), RaycastParams.new())
	local groundY = rayResult and rayResult.Position.Y or position.Y
	local _, modelSize = model:GetBoundingBox()
	model:PivotTo(CFrame.new(position.X, groundY + modelSize.Y * 0.5, position.Z)
		* CFrame.Angles(0, math.random() * math.pi * 2, 0))

	-- ProximityPrompt for pickup
	local rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
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
			local logItemId = model:GetAttribute("_LogItemId") or "oak_log"
			if invAdd:Invoke(pickupPlayer, logItemId, 1) then
				model:Destroy()
			end
		end)
	end

	model.Parent = scatterFolder or Workspace

	-- Auto-despawn
	task.delay(LOG_DESPAWN_SECS, function()
		if model and model.Parent then model:Destroy() end
	end)

	return model
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

	-- Get the tree's bounding box to calculate pivot at base
	local _, treeSize = treeModel:GetBoundingBox()
	local treeHeight = treeSize.Y

	-- Tween the tree falling: rotate 90° around base
	-- We'll do this by moving the PrimaryPart in steps via Heartbeat
	local rootPart = treeModel.PrimaryPart or treeModel:FindFirstChildWhichIsA("BasePart")
	if not rootPart then return end

	local startTime = os.clock()
	local damagedPlayers: { [Player]: boolean } = {}

	-- Calculate the axis of rotation (perpendicular to fall direction, horizontal)
	-- We want to rotate the tree so it tips over in the fallDir direction.
	-- The hinge axis is perpendicular to fallDir and horizontal.
	local rotAxis = Vector3.new(0, 1, 0):Cross(fallDir).Unit

	-- Base pivot point (bottom of tree)
	local basePivot = originalPos - Vector3.new(0, treeHeight * 0.5, 0)

	-- Preserve original Y rotation
	local _, origYRot, _ = originalCFrame:ToEulerAnglesYXZ()

	local fallConnection: RBXScriptConnection
	fallConnection = RunService.Heartbeat:Connect(function()
		if not treeModel.Parent then
			fallConnection:Disconnect()
			return
		end

		local elapsed = os.clock() - startTime
		local t = math.min(elapsed / FALL_DURATION, 1)

		-- Ease-in for acceleration (gravity feel)
		local easedT = t * t

		-- Rotate around base pivot: hinge at base, tip over away from player
		local angle = easedT * math.rad(90)
		local pivotCFrame = CFrame.new(basePivot)
			* CFrame.fromAxisAngle(rotAxis, angle)
			* CFrame.new(0, treeHeight * 0.5, 0)
			* CFrame.Angles(0, origYRot, 0)

		treeModel:PivotTo(pivotCFrame)

		-- Check for fall damage during the fall
		checkFallDamage(treeModel, damagedPlayers)

		if t >= 1 then
			fallConnection:Disconnect()

			-- Fall complete — transition to stump + trunk phase
			task.defer(function()
				onTreeLanded(treeModel, basePivot, scatterItemId, originalCFrame, fellingPlayer)
			end)
		end
	end)
end

-- ── Post-fall: create stump + set up trunk with cut points ───────────────

function onTreeLanded(treeModel: Model, basePos: Vector3, scatterItemId: string, originalCFrame: CFrame, _fellingPlayer: Player)
	if not treeModel.Parent then return end

	-- 1. Spawn stump at original position
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
		local _, stumpSize = stump:GetBoundingBox()
		local _, origYRot, _ = originalCFrame:ToEulerAnglesYXZ()
		stump:PivotTo(CFrame.new(basePos + Vector3.new(0, stumpSize.Y * 0.5, 0))
			* CFrame.Angles(0, origYRot, 0))
	end

	for _, desc in stump:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = true
		end
	end

	stump.Parent = scatterFolder or Workspace

	-- 2. Destroy the original tree model and replace it with a brown trunk
	local trunkBBCF, trunkSize = treeModel:GetBoundingBox()
	local trunkLength = math.max(trunkSize.X, trunkSize.Y, trunkSize.Z)

	-- Determine trunk direction (longest axis of bounding box)
	local trunkDir: Vector3
	if trunkSize.X >= trunkSize.Y and trunkSize.X >= trunkSize.Z then
		trunkDir = trunkBBCF.RightVector
	elseif trunkSize.Y >= trunkSize.X and trunkSize.Y >= trunkSize.Z then
		trunkDir = trunkBBCF.UpVector
	else
		trunkDir = trunkBBCF.LookVector
	end
	local trunkCenter = trunkBBCF.Position

	-- Destroy old tree model
	treeModel:Destroy()

	-- Create a new brown trunk lying on the ground
	local TRUNK_COLOR = Color3.fromRGB(120, 80, 40)
	local trunkDiameter = 1.8
	local trunk = Instance.new("Model")
	trunk.Name = "Fallen Oak"
	trunk:SetAttribute("_TreePhase", "trunk")
	trunk:SetAttribute("_ScatterItem", scatterItemId)

	local trunkPart = Instance.new("Part")
	trunkPart.Name = "Trunk"
	-- Size.Z = length (aligns with LookVector from CFrame.lookAt)
	trunkPart.Size = Vector3.new(trunkDiameter, trunkDiameter, trunkLength * 0.75)
	trunkPart.Color = TRUNK_COLOR
	trunkPart.Material = Enum.Material.SmoothPlastic
	trunkPart.Anchored = true
	trunkPart.CanCollide = true
	trunkPart.Parent = trunk
	trunk.PrimaryPart = trunkPart

	-- Raycast to find ground at trunk center
	local groundRay = Workspace:Raycast(
		trunkCenter + Vector3.new(0, 5, 0),
		Vector3.new(0, -30, 0),
		RaycastParams.new()
	)
	local groundY = groundRay and groundRay.Position.Y or (trunkCenter.Y - 2)

	-- Orient trunk along the fall direction, lying flat on ground
	local lookAt = trunkCenter + trunkDir
	trunkPart.CFrame = CFrame.lookAt(
		Vector3.new(trunkCenter.X, groundY + trunkDiameter * 0.5, trunkCenter.Z),
		Vector3.new(lookAt.X, groundY + trunkDiameter * 0.5, lookAt.Z)
	)

	trunk.Parent = scatterFolder or Workspace

	-- 3. Add cut point markers along the trunk (LookVector = Z axis = trunk length)
	local trunkAxis = trunkPart.CFrame.LookVector
	local trunkPos = trunkPart.CFrame.Position
	local cpOffset = trunkPart.Size.Z * 0.3  -- offset along trunk length (Z)
	local cpYOffset = trunkPart.Size.Y * 0.5  -- sit on top of trunk
	local cp1Pos = trunkPos - trunkAxis * cpOffset + Vector3.new(0, cpYOffset, 0)
	local cp2Pos = trunkPos + trunkAxis * cpOffset + Vector3.new(0, cpYOffset, 0)

	createCutPointMarker(CFrame.new(cp1Pos), 1, trunk)
	createCutPointMarker(CFrame.new(cp2Pos), 2, trunk)

	-- 4. Set up cut point watcher (shrinks trunk on first cut, destroys on second)
	setupCutPointWatcher(trunk)

	-- 5. Schedule regrowth on the stump
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

setupCutPointWatcher = function(trunkModel: Model)
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

	local cutPointCount = #cutPoints
	local cutPointsDestroyed = 0

	-- Watch each cut point for destruction (InventoryService destroys them when HP=0)
	for _, cp in cutPoints do
		-- Capture the position and index before AncestryChanged fires
		local savedPos: Vector3? = nil
		local savedIndex: number = cp:GetAttribute("_CutPointIndex") or 0
		local hitTarget = cp:FindFirstChild("HitTarget")
		if hitTarget and hitTarget:IsA("BasePart") then
			savedPos = hitTarget.Position
		end

		cp.AncestryChanged:Connect(function()
			if cp.Parent then return end -- only care about removal
			cutPointsDestroyed += 1

			local cpPos = savedPos or (getModelPosition(trunkModel) or Vector3.zero)

			if cutPointsDestroyed < cutPointCount then
				-- First cut: shrink trunk from the chopped end and spawn 1 log
				local trunkPart = trunkModel.PrimaryPart
				if trunkPart and trunkPart:IsA("BasePart") then
					local oldSize = trunkPart.Size
					local newLength = oldSize.Z * 0.6
					local shrinkAmount = oldSize.Z - newLength
					trunkPart.Size = Vector3.new(oldSize.X, oldSize.Y, newLength)

					-- Shift trunk away from the cut side so it shrinks from that end
					-- Cut point 1 is at negative LookVector end, cut point 2 at positive
					local shiftDir = trunkPart.CFrame.LookVector
					if savedIndex == 1 then
						-- Chopped the negative end → shift trunk toward positive end
						shiftDir = shiftDir
					else
						-- Chopped the positive end → shift trunk toward negative end
						shiftDir = -shiftDir
					end
					trunkPart.CFrame = trunkPart.CFrame + shiftDir * (shrinkAmount * 0.5)
				end

				local offset = Vector3.new(
					(math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3
				)
				createLogSegment(cpPos + offset)
			else
				-- Final cut: destroy trunk, spawn 2 logs
				for _ = 1, 2 do
					local offset = Vector3.new(
						(math.random() - 0.5) * 4, 0, (math.random() - 0.5) * 4
					)
					createLogSegment(cpPos + offset)
				end

				task.delay(0.5, function()
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
