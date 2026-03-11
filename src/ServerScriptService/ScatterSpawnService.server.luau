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

local ServerStorage    = game:GetService("ServerStorage")
local Workspace        = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemRegistry = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))

-- ── Scatter type definitions ──────────────────────────────────────────────

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
}

local SCATTER: { ScatterDef } = {
	{
		itemId     = "twig",
		maxCount   = 15,
		respawnMin = 20,
		respawnMax = 60,
		color      = Color3.fromRGB(101, 67, 33),
		size       = Vector3.new(0.15, 0.15, 1.4),
		templates  = { "twig_1" },
	},
	{
		itemId     = "rock",
		maxCount   = 12,
		respawnMin = 30,
		respawnMax = 90,
		color      = Color3.fromRGB(140, 140, 140),
		size       = Vector3.new(0.42, 0.3, 0.46),
		templates  = { "rock_1", "rock_2", "rock_3" },
	},
	{
		itemId     = "BrownMushroom",
		maxCount   = 5,
		respawnMin = 90,
		respawnMax = 240,
		color      = Color3.fromRGB(200, 140, 60),
		size       = Vector3.new(0.8, 0.8, 0.8),
	},
	{
		itemId        = "reed",
		maxCount      = 10,
		respawnMin    = 60,
		respawnMax    = 180,
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

-- Returns true if any Terrain voxel within `radius` studs (4 cardinal
-- directions, checking ±4 Y) contains water — i.e. pos is a water edge.
local function hasWaterNearby(pos: Vector3, radius: number): boolean
	local offsets = {
		Vector3.new(radius, 0, 0),  Vector3.new(-radius, 0, 0),
		Vector3.new(0, 0, radius),  Vector3.new(0, 0, -radius),
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

-- Raycast to find ground at a random X,Z within the zone.
-- Returns (position, surfaceNormal) or nil.
local function raycastGround(): (Vector3?, Vector3?)
	local center, half = getZoneBounds()
	local x = center.X + (math.random() * 2 - 1) * half.X
	local z = center.Z + (math.random() * 2 - 1) * half.Z
	local origin = Vector3.new(x, center.Y + 500, z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -1200, 0))
	if not result then return nil, nil end
	return Vector3.new(x, result.Position.Y, z), result.Normal
end

-- Maximum slope angle (in radians) for scatter placement.
-- cos(25°) ≈ 0.906 — rejects surfaces steeper than ~25°.
local MIN_SURFACE_DOT = math.cos(math.rad(25))

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

-- Picks a random ground position on land near a water edge, rejecting steep slopes.
local function randomWaterEdgePosition(): (Vector3?, Vector3?)
	for _ = 1, 30 do
		local pos, normal = raycastGround()
		if pos and isFlatEnough(normal) and not isNearWaterAt(pos) and hasWaterNearby(pos, 12) then
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

local function createScatterModel(cfg: ScatterDef): Model?
	local itemDef = ItemRegistry.get(cfg.itemId)
	local displayName = itemDef and itemDef.displayName or cfg.itemId

	local pos: Vector3?
	local surfaceNormal: Vector3?
	if cfg.nearWater then
		pos, surfaceNormal = randomWaterEdgePosition()
	else
		pos, surfaceNormal = randomGroundPosition()
	end
	if not pos then return nil end

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

		-- Anchor all parts and disable collision (pickup items, not obstacles)
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored   = true
				desc.CanCollide = false
			end
		end

		local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if root then
			local _, modelSize = model:GetBoundingBox()
			model:PivotTo(spawnCFrame + Vector3.new(0, modelSize.Y * 0.5, 0))
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

	local part          = Instance.new("Part")
	part.Name           = "Body"
	part.Size           = cfg.size
	part.Color          = cfg.color
	part.Material       = Enum.Material.SmoothPlastic
	part.Anchored       = true
	part.CastShadow     = true
	part.CFrame         = spawnCFrame + Vector3.new(0, cfg.size.Y * 0.5, 0)
	part.Parent         = model
	model.PrimaryPart   = part

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

spawnOne = function(cfg: ScatterDef)
	if counts[cfg.itemId] >= cfg.maxCount then return end

	local model = createScatterModel(cfg)
	if not model then
		-- No valid position found (e.g. all attempts hit water); retry shortly.
		task.delay(5, function() spawnOne(cfg) end)
		return
	end
	counts[cfg.itemId] += 1

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

-- Initial population — staggered slightly so they don't all raycast at once.
for _, cfg in ipairs(SCATTER) do
	for i = 1, cfg.maxCount do
		task.delay((i - 1) * 0.05, function()
			spawnOne(cfg)
		end)
	end
end
