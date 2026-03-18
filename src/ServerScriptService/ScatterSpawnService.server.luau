-- ScatterSpawnService.server.luau
-- Spawns floor-scatter items (twig, rock, mushroom) in the
-- world as Models tagged with _ScatterItem = itemId.
-- InventoryService handles the pickup prompts automatically.
--
-- SPAWN ZONES
--   Place invisible BasePart(s) named anything inside a Folder called
--   "ScatterZones" in Workspace.  Items will only spawn inside those parts.
--   If the folder doesn't exist, a default 60×60 area around the origin
--   is used as a fallback.
--
-- Each item type has:
--   maxCount     — max simultaneous world instances
--   respawnMin/Max — seconds before a picked-up item respawns
--   color/size   — placeholder visuals (replace with real models later)

local Players          = game:GetService("Players")
local ServerStorage    = game:GetService("ServerStorage")
local Workspace        = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemRegistry   = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))
local AssetIds       = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AssetIds"))
local ScatterSeed    = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ScatterSeed"))

-- ── Scatter type definitions ──────────────────────────────────────────────

local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))

type ScatterDef = {
	itemId:     string,
	maxCount:   number,
	respawnMin: number,
	respawnMax: number,
	color:      Color3,
	size:       Vector3,
	templates:  { string }?,  -- optional list of ScatterModel names to pick from randomly
	nearWater:    boolean?,   -- spawn only near water edges (on land, water within ~6 studs)
	nodeHealth:    number?,  -- HP of resource node; each hit deducts 1 (nil/0 = instant pickup)
	harvestYield:  { min: number, max: number }?,  -- items per hit
	hitCooldown:   number?,  -- seconds between hits (client + server enforced)
	requireTool:   string?,  -- harvestTag required on equipped tool (e.g. "reed")
	groundSink:    number?,  -- studs to sink into ground (hides floating on slopes)
	alignToSlope:  boolean?, -- tilt model to match terrain surface normal
	-- Tree system
	isTree:          boolean?,  -- multi-phase tree (fell → trunk → logs → stump → regrow)
	minSpacing:      number?,   -- min studs between this item and other scatter items
	-- Proximity spawning
	spawnNear:       string?,   -- itemId to spawn near (e.g. "oak_tree")
	spawnNearRadius: number?,   -- max distance from the anchor item
	-- Init ordering
	initPhase:       number?,   -- 1 = spawn first (default), 2 = spawn after phase 1 completes
}

local SCATTER: { ScatterDef } = {
	{
		itemId     = "twig",
		maxCount   = 25,
		respawnMin = 20,
		respawnMax = 60,
		color      = Color3.fromRGB(101, 67, 33),
		size       = Vector3.new(0.15, 0.15, 1.4),
		templates  = { "twig_1" },
		spawnNear     = "oak_tree",
		spawnNearRadius = GameplayConfig.Tree and GameplayConfig.Tree.TwigSpawnRadius or 12,
		initPhase     = 2,  -- spawn after trees
	},
	{
		itemId     = "rock",
		maxCount   = 60,
		respawnMin = 300,
		respawnMax = 600,
		color      = Color3.fromRGB(140, 140, 140),
		size       = Vector3.new(0.42, 0.3, 0.46),
		templates  = { "rock_1", "rock_2", "rock_3" },
	},
	{
		itemId     = "BrownMushroom",
		maxCount   = 30,
		respawnMin = 90,
		respawnMax = 240,
		color      = Color3.fromRGB(200, 140, 60),
		size       = Vector3.new(0.8, 0.8, 0.8),
	},
	{
		itemId        = "reed",
		maxCount      = 15,
		respawnMin    = 300,
		respawnMax    = 600,
		color         = Color3.fromRGB(120, 160, 80),
		size          = Vector3.new(0.3, 1.2, 0.3),
		templates     = { "reed_1" },
		nearWater     = true,
		nodeHealth    = 3,
		harvestYield  = { min = 1, max = 2 },
		hitCooldown   = 1.5,
		requireTool   = "reed",
		groundSink    = 0.3,
		alignToSlope  = true,
	},
	{
		itemId        = "oak_tree",
		maxCount      = GameplayConfig.Tree and GameplayConfig.Tree.MaxTier0Trees or 8,
		respawnMin    = GameplayConfig.Tree and GameplayConfig.Tree.RespawnMinSeconds or 3600,
		respawnMax    = GameplayConfig.Tree and GameplayConfig.Tree.RespawnMaxSeconds or 5400,
		color         = Color3.fromRGB(60, 100, 40),
		size          = Vector3.new(2, 14, 2),
		templates     = { "oak_tree_1", "oak_tree_2", "oak_tree_3" },
		nodeHealth    = GameplayConfig.Tree and GameplayConfig.Tree.Tier0NodeHealth or 8,
		harvestYield  = { min = 0, max = 0 },  -- no yield while standing (felling only)
		hitCooldown   = GameplayConfig.Tree and GameplayConfig.Tree.Tier0HitCooldown or 1.8,
		requireTool   = "tree",
		groundSink    = 0.5,
		alignToSlope  = false,
		isTree        = true,
		minSpacing    = GameplayConfig.Tree and GameplayConfig.Tree.MinTreeSpacing or 12,
		initPhase     = 1,
	},
}

-- ── Spawn zone helpers ────────────────────────────────────────────────────

-- Returns the center and half-extents of a random spawn zone.
local function getZoneBounds(): (Vector3, Vector3)
	local zonesFolder = Workspace:FindFirstChild("ScatterZones")
	if zonesFolder then
		local zones = {}
		for _, child in ipairs(zonesFolder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(zones, child)
			end
		end
		if #zones > 0 then
			local zone = zones[math.random(1, #zones)]
			return zone.Position, zone.Size * 0.5
		end
	end
	-- Default: 60×60 around origin
	return Vector3.new(0, 0, 0), Vector3.new(30, 0, 30)
end

-- ── Terrain water detection ─────────────────────────────────────────────

local VOXEL_RES = 4 -- Terrain voxel resolution (always 4 studs)

-- Returns true if the Terrain voxel at `pos` is water.
local function isWaterAt(pos: Vector3): boolean
	local corner = Vector3.new(
		math.floor(pos.X / VOXEL_RES) * VOXEL_RES,
		math.floor(pos.Y / VOXEL_RES) * VOXEL_RES,
		math.floor(pos.Z / VOXEL_RES) * VOXEL_RES
	)
	local region = Region3.new(corner, corner + Vector3.new(VOXEL_RES, VOXEL_RES, VOXEL_RES))
	local materials = Workspace.Terrain:ReadVoxels(region, VOXEL_RES)
	return materials[1][1][1] == Enum.Material.Water
end

-- Returns true if any voxel near `pos` (±4 Y, plus 2-stud cardinal offsets)
-- contains water. Catches positions on the surface, just above, or at the
-- shoreline edge where the ground slopes into water.
local function isNearWaterAt(pos: Vector3): boolean
	-- Check the column at this position (below, at, and above)
	for yOff = -4, 8, 4 do
		if isWaterAt(pos + Vector3.new(0, yOff, 0)) then return true end
	end
	-- Check 2 studs out in each cardinal direction (catches shoreline)
	local SHORE_CHECK = 2
	for _, off in {
		Vector3.new(SHORE_CHECK, 0, 0),  Vector3.new(-SHORE_CHECK, 0, 0),
		Vector3.new(0, 0, SHORE_CHECK),  Vector3.new(0, 0, -SHORE_CHECK),
	} do
		for yOff = -4, 4, 4 do
			if isWaterAt(pos + off + Vector3.new(0, yOff, 0)) then return true end
		end
	end
	return false
end

-- Returns true if any Terrain voxel within `radius` studs (cardinal +
-- diagonal directions, checking ±4 Y) contains water — i.e. pos is near water.
local function hasWaterNearby(pos: Vector3, radius: number): boolean
	local diag = radius * 0.707 -- cos(45°)
	local offsets = {
		Vector3.new(radius, 0, 0),  Vector3.new(-radius, 0, 0),
		Vector3.new(0, 0, radius),  Vector3.new(0, 0, -radius),
		Vector3.new(diag, 0, diag),   Vector3.new(-diag, 0, diag),
		Vector3.new(diag, 0, -diag),  Vector3.new(-diag, 0, -diag),
	}
	for _, off in offsets do
		local checkPos = pos + off
		for yOff = -4, 4, 4 do
			if isWaterAt(checkPos + Vector3.new(0, yOff, 0)) then return true end
		end
	end
	return false
end

-- ── Ground position helpers ─────────────────────────────────────────────

-- RaycastParams placeholder — built after scatterFolder is created (see below).
local scatterRayParams: RaycastParams = nil :: any

-- Raycast to find ground at a random X,Z within the zone.
-- Returns (position, surfaceNormal) or nil.
local function raycastGround(): (Vector3?, Vector3?)
	local center, half = getZoneBounds()
	local x = center.X + (math.random() * 2 - 1) * half.X
	local z = center.Z + (math.random() * 2 - 1) * half.Z
	local origin = Vector3.new(x, center.Y + 500, z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -1200, 0), scatterRayParams)
	if not result then return nil, nil end
	return Vector3.new(x, result.Position.Y, z), result.Normal
end

-- Maximum slope angle (in radians) for scatter placement.
-- cos(25°) ≈ 0.906 — rejects surfaces steeper than ~25°.
local MIN_SURFACE_DOT = math.cos(math.rad(25))
-- Relaxed slope for water-edge items (shorelines are naturally steeper).
-- cos(40°) ≈ 0.766
local MIN_SURFACE_DOT_WATER = math.cos(math.rad(40))

local function isFlatEnough(normal: Vector3?): boolean
	if not normal then return false end
	return normal.Y >= MIN_SURFACE_DOT
end

-- Picks a random ground position, rejecting positions inside water or on steep slopes.
local function randomGroundPosition(): (Vector3?, Vector3?)
	for _ = 1, 20 do
		local pos, normal = raycastGround()
		if pos and isFlatEnough(normal) and not isNearWaterAt(pos) then return pos, normal end
	end
	return nil, nil
end

-- Picks a random ground position on land near a water edge.
-- Uses relaxed slope tolerance (40° vs 25°) because shorelines are naturally steeper.
local function randomWaterEdgePosition(): (Vector3?, Vector3?)
	for _ = 1, 60 do
		local pos, normal = raycastGround()
		if pos and normal and normal.Y >= MIN_SURFACE_DOT_WATER
			and not isNearWaterAt(pos) and hasWaterNearby(pos, 12) then
			return pos, normal
		end
	end
	return nil, nil
end

-- ── Scatter folder ────────────────────────────────────────────────────────

local scatterFolder = Workspace:FindFirstChild("Scatter")
if not scatterFolder then
	scatterFolder = Instance.new("Folder")
	scatterFolder.Name   = "Scatter"
	scatterFolder.Parent = Workspace
end

-- Build RaycastParams that ignores ScatterZones and existing scatter items
-- so the downward ray hits only Terrain and world geometry.
do
	scatterRayParams = RaycastParams.new()
	scatterRayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = { scatterFolder }
	local zonesFolder = Workspace:FindFirstChild("ScatterZones")
	if zonesFolder then table.insert(filterList, zonesFolder) end
	scatterRayParams.FilterDescendantsInstances = filterList
end

-- ── Template lookup ──────────────────────────────────────────────────────

-- Looks for a Studio-placed Model or MeshPart in ServerStorage > ScatterModels.
-- That folder has init.meta.json with ignoreUnknownInstances so Rojo
-- won't delete Studio-placed mesh models.
local function findTemplate(itemId: string): Instance?
	local folder = ServerStorage:FindFirstChild("ScatterModels")
	if not folder then return nil end
	local tmpl = folder:FindFirstChild(itemId)
	if tmpl and (tmpl:IsA("Model") or tmpl:IsA("BasePart")) then return tmpl end
	return nil
end

-- ── Model creation ────────────────────────────────────────────────────────

-- Picks a random ground position near an existing scatter model with the given itemId.
-- Falls back to randomGroundPosition() if no anchor found.
local function randomNearPosition(anchorItemId: string, radius: number): (Vector3?, Vector3?)
	local anchors: { Vector3 } = {}
	for _, m in ipairs(scatterFolder:GetChildren()) do
		if m:IsA("Model") then
			local sid = m:GetAttribute("_ScatterItem")
			local isStump = m:GetAttribute("_TreeStump")
			if sid == anchorItemId or isStump then
				local p = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
				if p then table.insert(anchors, p.Position) end
			end
		end
	end
	if #anchors == 0 then return randomGroundPosition() end

	local anchor = anchors[math.random(1, #anchors)]
	for _ = 1, 15 do
		local angle = math.random() * math.pi * 2
		local dist = 4 + math.random() * (radius - 4) -- at least 4 studs away (outside canopy)
		local x = anchor.X + math.cos(angle) * dist
		local z = anchor.Z + math.sin(angle) * dist
		local origin = Vector3.new(x, anchor.Y + 50, z)
		local result = Workspace:Raycast(origin, Vector3.new(0, -200, 0), scatterRayParams)
		if result then
			local pos = Vector3.new(x, result.Position.Y, z)
			if isFlatEnough(result.Normal) and not isNearWaterAt(pos) then
				return pos, result.Normal
			end
		end
	end
	return randomGroundPosition() -- fallback
end

-- Checks if a position is too close to any existing scatter model.
local function isTooCloseToExisting(pos: Vector3, minDist: number): boolean
	for _, m in ipairs(scatterFolder:GetChildren()) do
		if m:IsA("Model") then
			local p = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
			if p and (p.Position - pos).Magnitude < minDist then
				return true
			end
		end
	end
	return false
end

local function createScatterModel(cfg: ScatterDef): Model?
	local itemDef = ItemRegistry.get(cfg.itemId)
	local displayName = itemDef and itemDef.displayName or cfg.itemId

	local pos: Vector3?
	local surfaceNormal: Vector3?
	if cfg.spawnNear then
		pos, surfaceNormal = randomNearPosition(cfg.spawnNear, cfg.spawnNearRadius or 8)
	elseif cfg.nearWater then
		pos, surfaceNormal = randomWaterEdgePosition()
	else
		pos, surfaceNormal = randomGroundPosition()
	end
	if not pos then return nil end

	-- Minimum spacing check
	if cfg.minSpacing and cfg.minSpacing > 0 then
		if isTooCloseToExisting(pos, cfg.minSpacing) then return nil end
	end

	-- Sink into ground to hide floating on slopes
	local sink = cfg.groundSink or 0
	pos = pos - Vector3.new(0, sink, 0)

	-- Build spawn CFrame: random Y rotation, optionally tilted to match terrain slope
	local spawnCFrame: CFrame
	if cfg.alignToSlope and surfaceNormal and surfaceNormal.Y < 1 then
		-- Build a CFrame whose Y axis aligns with the surface normal
		local up = surfaceNormal
		local right = Vector3.new(0, 1, 0):Cross(up)
		if right.Magnitude < 0.001 then
			right = Vector3.new(1, 0, 0)
		else
			right = right.Unit
		end
		local forward = up:Cross(right).Unit
		spawnCFrame = CFrame.fromMatrix(pos, right, up, -forward)
			* CFrame.Angles(0, math.random() * math.pi * 2, 0)
	else
		spawnCFrame = CFrame.new(pos)
			* CFrame.Angles(0, math.random() * math.pi * 2, 0)
	end

	-- Try to clone a Studio-placed template from ServerStorage/ScatterModels
	-- If templates list is provided, pick a random variant; fall back to itemId
	local templateName = cfg.itemId
	if cfg.templates and #cfg.templates > 0 then
		templateName = cfg.templates[math.random(1, #cfg.templates)]
	end
	local template = findTemplate(templateName)
	if template then
		local model: Model

		if template:IsA("Model") then
			model = template:Clone()
		else
			-- Bare MeshPart/BasePart — wrap in a Model
			model = Instance.new("Model")
			local part = template:Clone()
			part.Parent = model
			model.PrimaryPart = part
		end

		model.Name = displayName
		model:SetAttribute("_ScatterItem", cfg.itemId)
		model:SetAttribute("_TemplateName", templateName)
		if cfg.nodeHealth and cfg.nodeHealth > 0 then
			model:SetAttribute("_NodeHealth", cfg.nodeHealth)
			model:SetAttribute("_NodeMaxHealth", cfg.nodeHealth)
			model:SetAttribute("_HarvestYieldMin", cfg.harvestYield and cfg.harvestYield.min or 1)
			model:SetAttribute("_HarvestYieldMax", cfg.harvestYield and cfg.harvestYield.max or 1)
			model:SetAttribute("_HitCooldown", cfg.hitCooldown or 0.8)
		end
		if cfg.requireTool then
			model:SetAttribute("_RequireTool", cfg.requireTool)
		end
		if cfg.isTree then
			model:SetAttribute("_IsTree", true)
			model:SetAttribute("_TreePhase", "standing")
		end

		-- Anchor all parts. For trees, preserve per-part CanCollide from the template
		-- (trunk=true, canopy=false) so players can walk through leaves but not trunk.
		-- For non-tree items, force CanCollide off.
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				if not cfg.isTree then
					desc.CanCollide = false
				end
			end
		end

		-- Add leaf particle emitter for trees (disabled, burst on hit by client)
		if cfg.isTree then
			local leafPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			if leafPart and not model:FindFirstChild("LeafParticles", true) then
				local emitter = Instance.new("ParticleEmitter")
				emitter.Name = "LeafParticles"
				emitter.Enabled = false
				emitter.Texture = AssetIds.Particles.Leaf
				emitter.Color = ColorSequence.new(Color3.fromRGB(90, 150, 60), Color3.fromRGB(50, 100, 25))
				emitter.Size = NumberSequence.new(0.4, 0.15)
				emitter.Lifetime = NumberRange.new(1.5, 3)
				emitter.Speed = NumberRange.new(1, 3)
				emitter.SpreadAngle = Vector2.new(60, 60)
				emitter.Rate = 0
				emitter.RotSpeed = NumberRange.new(-120, 120)
				emitter.Rotation = NumberRange.new(0, 360)
				emitter.Acceleration = Vector3.new(0, -4, 0)  -- leaves drift down
				emitter.Parent = leafPart
			end
			-- Wood chip particles (burst where axe hits the trunk)
			if leafPart and not model:FindFirstChild("WoodChipParticles", true) then
				local chips = Instance.new("ParticleEmitter")
				chips.Name = "WoodChipParticles"
				chips.Enabled = false
				chips.Texture = AssetIds.Particles.WoodChip
				chips.Color = ColorSequence.new(Color3.fromRGB(180, 130, 70), Color3.fromRGB(140, 95, 50))
				chips.Size = NumberSequence.new(0.2, 0.08)
				chips.Lifetime = NumberRange.new(0.5, 1.2)
				chips.Speed = NumberRange.new(4, 10)
				chips.SpreadAngle = Vector2.new(80, 80)
				chips.Rate = 0
				chips.RotSpeed = NumberRange.new(-180, 180)
				chips.Rotation = NumberRange.new(0, 360)
				chips.Acceleration = Vector3.new(0, -15, 0)
				chips.Parent = leafPart
			end
		end

		local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if root then
			local bbCFrame, modelSize = model:GetBoundingBox()
			-- Lift so bounding-box bottom sits on the ground (spawnCFrame).
			-- Works regardless of where the model pivot is (base or center).
			local pivotY = model:GetPivot().Position.Y
			local bbBottomY = bbCFrame.Position.Y - modelSize.Y * 0.5
			local pivotAboveBottom = pivotY - bbBottomY
			-- Per-template vertical offset (set _GroundOffset attribute in Studio)
			local extraOffset = model:GetAttribute("_GroundOffset") or 0
			model:PivotTo(spawnCFrame + Vector3.new(0, pivotAboveBottom + extraOffset, 0))
		end

		model.Parent = scatterFolder
		return model
	end

	-- Fallback: coloured placeholder Part (for items without templates)
	local model = Instance.new("Model")
	model.Name  = displayName
	model:SetAttribute("_ScatterItem", cfg.itemId)
	if cfg.gatherSeconds and cfg.gatherSeconds > 0 then
		model:SetAttribute("_GatherSeconds", cfg.gatherSeconds)
	end
	if cfg.requireTool then
		model:SetAttribute("_RequireTool", cfg.requireTool)
	end
	if cfg.nodeHealth and cfg.nodeHealth > 0 then
		model:SetAttribute("_NodeHealth", cfg.nodeHealth)
		model:SetAttribute("_NodeMaxHealth", cfg.nodeHealth)
		model:SetAttribute("_HarvestYieldMin", cfg.harvestYield and cfg.harvestYield.min or 1)
		model:SetAttribute("_HarvestYieldMax", cfg.harvestYield and cfg.harvestYield.max or 1)
		model:SetAttribute("_HitCooldown", cfg.hitCooldown or 0.8)
	end
	if cfg.isTree then
		model:SetAttribute("_IsTree", true)
		model:SetAttribute("_TreePhase", "standing")
	end

	local part          = Instance.new("Part")
	part.Name           = "Body"
	part.Size           = cfg.size
	part.Color          = cfg.color
	part.Material       = Enum.Material.SmoothPlastic
	part.Anchored       = true
	part.CanCollide     = cfg.isTree or false
	part.CastShadow     = true
	part.CFrame         = spawnCFrame + Vector3.new(0, cfg.size.Y * 0.5, 0)
	part.Parent         = model
	model.PrimaryPart   = part

	-- Add leaf particle emitter for placeholder trees
	if cfg.isTree then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "LeafParticles"
		emitter.Enabled = false
		emitter.Color = ColorSequence.new(Color3.fromRGB(80, 140, 50), Color3.fromRGB(60, 110, 30))
		emitter.Size = NumberSequence.new(0.3, 0.1)
		emitter.Lifetime = NumberRange.new(1.5, 3)
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(60, 60)
		emitter.Rate = 0
		emitter.RotSpeed = NumberRange.new(-90, 90)
		emitter.Acceleration = Vector3.new(0, -4, 0)
		emitter.Parent = part

		local chips = Instance.new("ParticleEmitter")
		chips.Name = "WoodChipParticles"
		chips.Enabled = false
		chips.Color = ColorSequence.new(Color3.fromRGB(160, 110, 50), Color3.fromRGB(120, 80, 40))
		chips.Size = NumberSequence.new(0.15, 0.05)
		chips.Lifetime = NumberRange.new(0.5, 1.2)
		chips.Speed = NumberRange.new(4, 10)
		chips.SpreadAngle = Vector2.new(80, 80)
		chips.Rate = 0
		chips.RotSpeed = NumberRange.new(-180, 180)
		chips.Acceleration = Vector3.new(0, -15, 0)
		chips.Parent = part
	end

	model.Parent = scatterFolder
	return model
end

-- ── Spawn management ──────────────────────────────────────────────────────

local counts: { [string]: number } = {}
for _, cfg in ipairs(SCATTER) do
	counts[cfg.itemId] = 0
end

-- Forward declaration required for self-reference inside the closure.
local spawnOne: (ScatterDef) -> ()

local spawnFailures: { [string]: number } = {}

spawnOne = function(cfg: ScatterDef)
	if counts[cfg.itemId] >= cfg.maxCount then return end

	local model = createScatterModel(cfg)
	if not model then
		-- No valid position found; retry shortly.
		local fails = (spawnFailures[cfg.itemId] or 0) + 1
		spawnFailures[cfg.itemId] = fails
		if fails % 20 == 0 then
			warn(("[ScatterSpawn] %s: %d consecutive spawn failures"):format(cfg.itemId, fails))
		end
		task.delay(0.5, function() spawnOne(cfg) end)
		return
	end
	spawnFailures[cfg.itemId] = 0
	counts[cfg.itemId] += 1

	-- Trees are managed by TreeService (fell → stump → regrow); skip auto-respawn.
	if cfg.isTree then return end

	-- When the model is removed (picked up or destroyed), schedule a respawn.
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			counts[cfg.itemId] = math.max(0, counts[cfg.itemId] - 1)
			local delay = cfg.respawnMin + math.random() * (cfg.respawnMax - cfg.respawnMin)
			task.delay(delay, function()
				spawnOne(cfg)
			end)
		end
	end)
end

-- Expose count helpers for TreeService to manage tree counts
local ScatterCounts = {}
function ScatterCounts.decrement(itemId: string)
	counts[itemId] = math.max(0, (counts[itemId] or 0) - 1)
end
function ScatterCounts.increment(itemId: string)
	counts[itemId] = (counts[itemId] or 0) + 1
end
function ScatterCounts.get(itemId: string): number
	return counts[itemId] or 0
end

-- Store in ServerStorage so TreeService can access it
local countsBindable = Instance.new("BindableFunction")
countsBindable.Name = "ScatterCountHelper"
countsBindable.OnInvoke = function(action: string, itemId: string): number?
	if action == "decrement" then ScatterCounts.decrement(itemId); return nil
	elseif action == "increment" then ScatterCounts.increment(itemId); return nil
	elseif action == "get" then return ScatterCounts.get(itemId)
	end
	return nil
end
countsBindable.Parent = ServerStorage:FindFirstChild("ServerBindables")
	or ServerStorage

-- ── Seeded spawn (instant load from baked positions) ────────────────────

-- Lookup table: itemId → ScatterDef
local scatterByItemId: { [string]: ScatterDef } = {}
for _, cfg in ipairs(SCATTER) do
	scatterByItemId[cfg.itemId] = cfg
end

-- Spawns a single item from a seed entry (no raycasting needed).
local function spawnFromSeed(entry: { id: string, tpl: string, px: number, py: number, pz: number, rx: number, ry: number, rz: number }): Model?
	local cfg = scatterByItemId[entry.id]
	if not cfg then
		warn(("[ScatterSeed] Unknown itemId in seed: %s"):format(entry.id))
		return nil
	end

	local template = findTemplate(entry.tpl)
	if not template then
		warn(("[ScatterSeed] Template not found: %s"):format(entry.tpl))
		return nil
	end

	local itemDef = ItemRegistry.get(cfg.itemId)
	local displayName = itemDef and itemDef.displayName or cfg.itemId

	local model: Model
	if template:IsA("Model") then
		model = template:Clone()
	else
		model = Instance.new("Model")
		local part = template:Clone()
		part.Parent = model
		model.PrimaryPart = part
	end

	model.Name = displayName
	model:SetAttribute("_ScatterItem", cfg.itemId)
	model:SetAttribute("_TemplateName", entry.tpl)
	if cfg.nodeHealth and cfg.nodeHealth > 0 then
		model:SetAttribute("_NodeHealth", cfg.nodeHealth)
		model:SetAttribute("_NodeMaxHealth", cfg.nodeHealth)
		model:SetAttribute("_HarvestYieldMin", cfg.harvestYield and cfg.harvestYield.min or 1)
		model:SetAttribute("_HarvestYieldMax", cfg.harvestYield and cfg.harvestYield.max or 1)
		model:SetAttribute("_HitCooldown", cfg.hitCooldown or 0.8)
	end
	if cfg.requireTool then
		model:SetAttribute("_RequireTool", cfg.requireTool)
	end
	if cfg.isTree then
		model:SetAttribute("_IsTree", true)
		model:SetAttribute("_TreePhase", "standing")
	end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			if not cfg.isTree then
				desc.CanCollide = false
			end
		end
	end

	-- Add particle emitters for trees
	if cfg.isTree then
		local leafPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if leafPart and not model:FindFirstChild("LeafParticles", true) then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "LeafParticles"
			emitter.Enabled = false
			emitter.Texture = AssetIds.Particles.Leaf
			emitter.Color = ColorSequence.new(Color3.fromRGB(90, 150, 60), Color3.fromRGB(50, 100, 25))
			emitter.Size = NumberSequence.new(0.4, 0.15)
			emitter.Lifetime = NumberRange.new(1.5, 3)
			emitter.Speed = NumberRange.new(1, 3)
			emitter.SpreadAngle = Vector2.new(60, 60)
			emitter.Rate = 0
			emitter.RotSpeed = NumberRange.new(-120, 120)
			emitter.Rotation = NumberRange.new(0, 360)
			emitter.Acceleration = Vector3.new(0, -4, 0)
			emitter.Parent = leafPart
		end
		if leafPart and not model:FindFirstChild("WoodChipParticles", true) then
			local chips = Instance.new("ParticleEmitter")
			chips.Name = "WoodChipParticles"
			chips.Enabled = false
			chips.Texture = AssetIds.Particles.WoodChip
			chips.Color = ColorSequence.new(Color3.fromRGB(180, 130, 70), Color3.fromRGB(140, 95, 50))
			chips.Size = NumberSequence.new(0.2, 0.08)
			chips.Lifetime = NumberRange.new(0.5, 1.2)
			chips.Speed = NumberRange.new(4, 10)
			chips.SpreadAngle = Vector2.new(80, 80)
			chips.Rate = 0
			chips.RotSpeed = NumberRange.new(-180, 180)
			chips.Rotation = NumberRange.new(0, 360)
			chips.Acceleration = Vector3.new(0, -15, 0)
			chips.Parent = leafPart
		end
	end

	-- Position from seed CFrame (no raycasting needed)
	local cf = CFrame.new(entry.px, entry.py, entry.pz)
		* CFrame.Angles(entry.rx, entry.ry, entry.rz)
	model:PivotTo(cf)
	model.Parent = scatterFolder
	return model
end

-- ── Initial population ──────────────────────────────────────────────────

local BATCH_SIZE = 5 -- items per frame during initial population

local function populatePhase(cfgs: { ScatterDef }, onComplete: (() -> ())?)
	local queue: { ScatterDef } = {}
	for _, cfg in ipairs(cfgs) do
		local remaining = cfg.maxCount - (counts[cfg.itemId] or 0)
		for _ = 1, remaining do
			table.insert(queue, cfg)
		end
	end
	if #queue == 0 then
		if onComplete then onComplete() end
		return
	end

	task.spawn(function()
		local i = 1
		while i <= #queue do
			for _ = 1, BATCH_SIZE do
				if i > #queue then break end
				spawnOne(queue[i])
				i += 1
			end
			task.wait()
		end
		if onComplete then onComplete() end
	end)
end

-- Phase separation
local phase1: { ScatterDef } = {}
local phase2: { ScatterDef } = {}
for _, cfg in ipairs(SCATTER) do
	if (cfg.initPhase or 1) >= 2 then
		table.insert(phase2, cfg)
	else
		table.insert(phase1, cfg)
	end
end

-- Try seeded spawn first (instant), then fill remaining with random
if #ScatterSeed > 0 then
	print(("[ScatterSpawn] Loading %d items from seed..."):format(#ScatterSeed))
	local seeded = 0
	for _, entry in ipairs(ScatterSeed) do
		local cfg = scatterByItemId[entry.id]
		if cfg and (counts[entry.id] or 0) < cfg.maxCount then
			local model = spawnFromSeed(entry)
			if model then
				counts[entry.id] = (counts[entry.id] or 0) + 1
				seeded += 1

				-- Hook up respawn for non-tree items
				if not cfg.isTree then
					model.AncestryChanged:Connect(function()
						if not model.Parent then
							counts[cfg.itemId] = math.max(0, counts[cfg.itemId] - 1)
							local delay = cfg.respawnMin + math.random() * (cfg.respawnMax - cfg.respawnMin)
							task.delay(delay, function()
								spawnOne(cfg)
							end)
						end
					end)
				end
			end
		end
	end
	print(("[ScatterSpawn] Seeded %d items. Filling remaining with random spawns..."):format(seeded))
end

-- Fill any remaining counts (new items added since last snapshot, or seed was empty)
populatePhase(phase1, function()
	task.delay(1, function()
		populatePhase(phase2)
	end)
end)

-- ── Snapshot chat command ────────────────────────────────────────────────
-- Type !scatter-snapshot in chat to capture all current scatter positions.
-- Output is a ready-to-paste Luau module for ScatterSeed.luau.

local GAME_OWNER_ID = game.CreatorId

local function captureSnapshot()
	local entries: { string } = {}
	for _, child in ipairs(scatterFolder:GetChildren()) do
		if not child:IsA("Model") then continue end
		local itemId = child:GetAttribute("_ScatterItem")
		if not itemId then continue end

		-- Skip non-natural items (cut points, log segments, stumps, fallen trunks)
		if child:GetAttribute("_CutPoint") then continue end
		if child:GetAttribute("_TrunkSegment") then continue end
		if child:GetAttribute("_TreeStump") then continue end
		local phase = child:GetAttribute("_TreePhase")
		if phase == "trunk" or phase == "falling" then continue end

		local tplName = child:GetAttribute("_TemplateName") or itemId
		local pivot = child:GetPivot()
		local px, py, pz = pivot.Position.X, pivot.Position.Y, pivot.Position.Z
		local rx, ry, rz = pivot:ToEulerAnglesYXZ()

		table.insert(entries, ("{id=%q,tpl=%q,px=%.2f,py=%.2f,pz=%.2f,rx=%.4f,ry=%.4f,rz=%.4f}"):format(
			itemId, tplName, px, py, pz, rx, ry, rz
		))
	end

	-- Print as a complete Luau module
	print("── SCATTER SEED START ──")
	print("-- Copy everything between START and END into ScatterSeed.luau")
	print("return {")
	for _, line in ipairs(entries) do
		print(line .. ",")
	end
	print("}")
	print(("── SCATTER SEED END ── (%d entries)"):format(#entries))
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		if message:lower() ~= "!scatter-snapshot" then return end
		-- Allow game owner or Studio testing (CreatorId 0 in local test)
		if player.UserId ~= GAME_OWNER_ID and GAME_OWNER_ID ~= 0 then
			warn("[ScatterSnapshot] Denied — not game owner")
			return
		end
		print(("[ScatterSnapshot] Capturing snapshot for %s..."):format(player.Name))
		captureSnapshot()
	end)
end)
