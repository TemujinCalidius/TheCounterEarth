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
	nodeHealthMin: number?,  -- if set, randomise nodeHealth between min and nodeHealth
	harvestYield:  { min: number, max: number }?,  -- items per hit
	hitCooldown:   number?,  -- seconds between hits (client + server enforced)
	requireTool:   string?,  -- harvestTag required on equipped tool (e.g. "reed")
	groundSink:    number?,  -- studs to sink into ground (hides floating on slopes)
	alignToSlope:  boolean?, -- tilt model to match terrain surface normal
	-- Yield override
	yieldItem:       string?,   -- item to add to inventory on harvest (defaults to itemId if nil)
	-- Collision & scale
	hasCollision:    boolean?,  -- keep CanCollide on parts (true for boulders; default false for non-trees)
	scaleVariance:   number?,   -- random scale ± this fraction (e.g. 0.2 = 80%-120% size)
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
		spawnNear     = "boulder",
		spawnNearRadius = GameplayConfig.Boulder and GameplayConfig.Boulder.RockSpawnRadius or 10,
		initPhase     = 2,  -- spawn after boulders
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
		scaleVariance = 0.15,
		initPhase     = 1,
	},
	-- ── Boulders — split per template, HP scales with size ───────────────
	-- Size order: boulder_3 (smallest) < boulder_2 < boulder_1 < boulder_4 (largest)
	{   -- boulder_4: jagged cracked rock (largest, toughest)
		itemId        = "boulder",
		maxCount      = 2,
		respawnMin    = GameplayConfig.Boulder and GameplayConfig.Boulder.RespawnMinSeconds or 1800,
		respawnMax    = GameplayConfig.Boulder and GameplayConfig.Boulder.RespawnMaxSeconds or 3600,
		color         = Color3.fromRGB(110, 105, 100),
		size          = Vector3.new(5, 4, 5),
		templates     = { "boulder_4" },
		nodeHealth    = 10,
		nodeHealthMin = 8,
		harvestYield  = {
			min = GameplayConfig.Boulder and GameplayConfig.Boulder.HarvestYieldMin or 1,
			max = GameplayConfig.Boulder and GameplayConfig.Boulder.HarvestYieldMax or 2,
		},
		hitCooldown   = GameplayConfig.Boulder and GameplayConfig.Boulder.HitCooldown or 1.5,
		requireTool   = "stone",
		yieldItem     = "stone",
		hasCollision  = true,
		scaleVariance = 0.2,
		groundSink    = 0.8,
		alignToSlope  = false,
		minSpacing    = GameplayConfig.Boulder and GameplayConfig.Boulder.MinBoulderSpacing or 20,
		initPhase     = 1,
	},
	{   -- boulder_1: weathered granite with moss (medium-large)
		itemId        = "boulder",
		maxCount      = 2,
		respawnMin    = GameplayConfig.Boulder and GameplayConfig.Boulder.RespawnMinSeconds or 1800,
		respawnMax    = GameplayConfig.Boulder and GameplayConfig.Boulder.RespawnMaxSeconds or 3600,
		color         = Color3.fromRGB(120, 115, 105),
		size          = Vector3.new(4, 3, 4),
		templates     = { "boulder_1" },
		nodeHealth    = 8,
		nodeHealthMin = 6,
		harvestYield  = {
			min = GameplayConfig.Boulder and GameplayConfig.Boulder.HarvestYieldMin or 1,
			max = GameplayConfig.Boulder and GameplayConfig.Boulder.HarvestYieldMax or 2,
		},
		hitCooldown   = GameplayConfig.Boulder and GameplayConfig.Boulder.HitCooldown or 1.5,
		requireTool   = "stone",
		yieldItem     = "stone",
		hasCollision  = true,
		scaleVariance = 0.2,
		groundSink    = 0.8,
		alignToSlope  = false,
		minSpacing    = GameplayConfig.Boulder and GameplayConfig.Boulder.MinBoulderSpacing or 20,
		initPhase     = 1,
	},
	{   -- boulder_2: flat-topped sandstone (medium-small)
		itemId        = "boulder",
		maxCount      = 2,
		respawnMin    = GameplayConfig.Boulder and GameplayConfig.Boulder.RespawnMinSeconds or 1800,
		respawnMax    = GameplayConfig.Boulder and GameplayConfig.Boulder.RespawnMaxSeconds or 3600,
		color         = Color3.fromRGB(130, 120, 100),
		size          = Vector3.new(3.5, 2.5, 3.5),
		templates     = { "boulder_2" },
		nodeHealth    = 7,
		nodeHealthMin = 4,
		harvestYield  = {
			min = GameplayConfig.Boulder and GameplayConfig.Boulder.HarvestYieldMin or 1,
			max = GameplayConfig.Boulder and GameplayConfig.Boulder.HarvestYieldMax or 2,
		},
		hitCooldown   = GameplayConfig.Boulder and GameplayConfig.Boulder.HitCooldown or 1.5,
		requireTool   = "stone",
		yieldItem     = "stone",
		hasCollision  = true,
		scaleVariance = 0.2,
		groundSink    = 0.6,
		alignToSlope  = false,
		minSpacing    = GameplayConfig.Boulder and GameplayConfig.Boulder.MinBoulderSpacing or 20,
		initPhase     = 1,
	},
	{   -- boulder_3: round river boulder (smallest, near water)
		itemId        = "boulder",
		maxCount      = 3,
		respawnMin    = GameplayConfig.Boulder and GameplayConfig.Boulder.RespawnMinSeconds or 1800,
		respawnMax    = GameplayConfig.Boulder and GameplayConfig.Boulder.RespawnMaxSeconds or 3600,
		color         = Color3.fromRGB(100, 105, 110),
		size          = Vector3.new(2.5, 2, 2.5),
		templates     = { "boulder_3" },
		nodeHealth    = 5,
		nodeHealthMin = 3,
		harvestYield  = {
			min = GameplayConfig.Boulder and GameplayConfig.Boulder.HarvestYieldMin or 1,
			max = GameplayConfig.Boulder and GameplayConfig.Boulder.HarvestYieldMax or 2,
		},
		hitCooldown   = GameplayConfig.Boulder and GameplayConfig.Boulder.HitCooldown or 1.5,
		requireTool   = "stone",
		yieldItem     = "stone",
		hasCollision  = true,
		scaleVariance = 0.2,
		nearWater     = true,
		groundSink    = 1.2,       -- deeper sink for semi-submerged look
		alignToSlope  = true,      -- follow shoreline contour
		minSpacing    = GameplayConfig.Boulder and GameplayConfig.Boulder.MinBoulderSpacing or 20,
		initPhase     = 1,
	},
}

-- ── Scale variance helper ────────────────────────────────────────────────

-- Applies random uniform scale to a model (±variance fraction, e.g. 0.2 = 80-120%).
-- Multiplies against the model's current scale so it works with non-1.0 base scales.
local function applyScaleVariance(model: Model, variance: number)
	local baseScale = model:GetScale()
	local multiplier = 1 + (math.random() * 2 - 1) * variance  -- e.g. 0.8 to 1.2
	model:ScaleTo(baseScale * multiplier)
end

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

		-- Scale variance applied immediately after clone, before any positioning.
		-- The bounding-box ground-sit calc below will use the final scaled size.
		if cfg.scaleVariance and cfg.scaleVariance > 0 then
			applyScaleVariance(model, cfg.scaleVariance)
		end

		model:SetAttribute("_ScatterItem", cfg.itemId)
		model:SetAttribute("_TemplateName", templateName)
		if cfg.nodeHealth and cfg.nodeHealth > 0 then
			local hp = cfg.nodeHealthMin and math.random(cfg.nodeHealthMin, cfg.nodeHealth) or cfg.nodeHealth
			model:SetAttribute("_NodeHealth", hp)
			model:SetAttribute("_NodeMaxHealth", hp)
			model:SetAttribute("_HarvestYieldMin", cfg.harvestYield and cfg.harvestYield.min or 1)
			model:SetAttribute("_HarvestYieldMax", cfg.harvestYield and cfg.harvestYield.max or 1)
			model:SetAttribute("_HitCooldown", cfg.hitCooldown or 0.8)
			if cfg.yieldItem then
				model:SetAttribute("_YieldItemId", cfg.yieldItem)
			end
		end
		if cfg.requireTool then
			model:SetAttribute("_RequireTool", cfg.requireTool)
		end
		if cfg.isTree then
			model:SetAttribute("_IsTree", true)
			model:SetAttribute("_TreePhase", "standing")
		end

		-- Anchor all parts. For trees and items with hasCollision, preserve per-part
		-- CanCollide from the template. For other items, force CanCollide off.
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				if not cfg.isTree and not cfg.hasCollision then
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

		-- Add stone chip particles for boulders (burst on pickaxe hit)
		if cfg.hasCollision and cfg.requireTool == "stone" then
			local boulderPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			if boulderPart and not model:FindFirstChild("StoneChipParticles", true) then
				local stoneChips = Instance.new("ParticleEmitter")
				stoneChips.Name = "StoneChipParticles"
				stoneChips.Enabled = false
				stoneChips.Texture = AssetIds.Particles.StoneChip or ""
				stoneChips.Color = ColorSequence.new(Color3.fromRGB(160, 155, 145), Color3.fromRGB(110, 105, 95))
				stoneChips.Size = NumberSequence.new(0.15, 0.05)
				stoneChips.Lifetime = NumberRange.new(0.4, 1.0)
				stoneChips.Speed = NumberRange.new(6, 14)
				stoneChips.SpreadAngle = Vector2.new(90, 90)
				stoneChips.Rate = 0
				stoneChips.RotSpeed = NumberRange.new(-200, 200)
				stoneChips.Rotation = NumberRange.new(0, 360)
				stoneChips.Acceleration = Vector3.new(0, -20, 0)
				stoneChips.Parent = boulderPart
			end
		end

		-- Position model so its bounding-box bottom sits on the ground.
		-- Fresh raycast at spawn XZ ensures correct terrain contact after scaling.
		local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if root then
			-- Raycast down to get exact ground level at this XZ
			local spawnPos = spawnCFrame.Position
			local groundResult = Workspace:Raycast(
				Vector3.new(spawnPos.X, spawnPos.Y + 200, spawnPos.Z),
				Vector3.new(0, -500, 0),
				scatterRayParams
			)
			local groundY = if groundResult
				then groundResult.Position.Y - (cfg.groundSink or 0)
				else spawnPos.Y

			-- Measure how far the pivot is above the bounding-box bottom
			local bbCFrame, modelSize = model:GetBoundingBox()
			local pivotY = model:GetPivot().Position.Y
			local bbBottomY = bbCFrame.Position.Y - modelSize.Y * 0.5
			local pivotAboveBottom = pivotY - bbBottomY

			-- Per-template vertical offset (set _GroundOffset attribute in Studio)
			local extraOffset = model:GetAttribute("_GroundOffset") or 0

			-- Place: ground level (with sink applied) + lift so bottom touches ground
			local finalY = groundY + pivotAboveBottom + extraOffset
			local placeCFrame = CFrame.new(spawnPos.X, finalY, spawnPos.Z)
				* spawnCFrame.Rotation
			model:PivotTo(placeCFrame)
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
		local hp = cfg.nodeHealthMin and math.random(cfg.nodeHealthMin, cfg.nodeHealth) or cfg.nodeHealth
		model:SetAttribute("_NodeHealth", hp)
		model:SetAttribute("_NodeMaxHealth", hp)
		model:SetAttribute("_HarvestYieldMin", cfg.harvestYield and cfg.harvestYield.min or 1)
		model:SetAttribute("_HarvestYieldMax", cfg.harvestYield and cfg.harvestYield.max or 1)
		model:SetAttribute("_HitCooldown", cfg.hitCooldown or 0.8)
	end
	if cfg.isTree then
		model:SetAttribute("_IsTree", true)
		model:SetAttribute("_TreePhase", "standing")
	end

	-- Compute placeholder size (apply scale variance to the size directly)
	local placeholderSize = cfg.size
	if cfg.scaleVariance and cfg.scaleVariance > 0 then
		local multiplier = 1 + (math.random() * 2 - 1) * cfg.scaleVariance
		placeholderSize = cfg.size * multiplier
	end

	local part          = Instance.new("Part")
	part.Name           = "Body"
	part.Size           = placeholderSize
	part.Color          = cfg.color
	part.Material       = Enum.Material.SmoothPlastic
	part.Anchored       = true
	part.CanCollide     = cfg.isTree or cfg.hasCollision or false
	part.CastShadow     = true
	part.CFrame         = spawnCFrame + Vector3.new(0, placeholderSize.Y * 0.5, 0)
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

	-- Stone chip particles for placeholder boulders
	if cfg.hasCollision and cfg.requireTool == "stone" then
		local stoneChips = Instance.new("ParticleEmitter")
		stoneChips.Name = "StoneChipParticles"
		stoneChips.Enabled = false
		stoneChips.Color = ColorSequence.new(Color3.fromRGB(160, 155, 145), Color3.fromRGB(110, 105, 95))
		stoneChips.Size = NumberSequence.new(0.15, 0.05)
		stoneChips.Lifetime = NumberRange.new(0.4, 1.0)
		stoneChips.Speed = NumberRange.new(6, 14)
		stoneChips.SpreadAngle = Vector2.new(90, 90)
		stoneChips.Rate = 0
		stoneChips.RotSpeed = NumberRange.new(-200, 200)
		stoneChips.Rotation = NumberRange.new(0, 360)
		stoneChips.Acceleration = Vector3.new(0, -20, 0)
		stoneChips.Parent = part
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

-- ── Fire ScatterReady remote when all phases complete ───────────────────

local scatterReadyRemote = Instance.new("RemoteEvent")
scatterReadyRemote.Name = "ScatterReady"
scatterReadyRemote.Parent = ReplicatedStorage:FindFirstChild("Remotes")
	or ReplicatedStorage

populatePhase(phase1, function()
	task.delay(1, function()
		populatePhase(phase2, function()
			-- Notify all connected clients that the world is ready
			scatterReadyRemote:FireAllClients()
			-- Also notify any players who join later
			Players.PlayerAdded:Connect(function(player)
				task.delay(1, function()
					scatterReadyRemote:FireClient(player)
				end)
			end)
			print("[ScatterSpawn] All phases complete — world ready.")
		end)
	end)
end)
