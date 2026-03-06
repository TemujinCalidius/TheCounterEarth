-- ScatterSpawnService.server.luau
-- Spawns floor-scatter items (twig, pebble, wild_berry, mushroom) in the
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
}

local SCATTER: { ScatterDef } = {
	{
		itemId     = "twig",
		maxCount   = 15,
		respawnMin = 20,
		respawnMax = 60,
		color      = Color3.fromRGB(101, 67, 33),
		size       = Vector3.new(0.15, 0.15, 1.4),
	},
	{
		itemId     = "pebble",
		maxCount   = 12,
		respawnMin = 30,
		respawnMax = 90,
		color      = Color3.fromRGB(140, 140, 140),
		size       = Vector3.new(0.42, 0.3, 0.46),
	},
	{
		itemId     = "wild_berry",
		maxCount   = 6,
		respawnMin = 60,
		respawnMax = 180,
		color      = Color3.fromRGB(180, 40, 60),
		size       = Vector3.new(0.35, 0.35, 0.35),
	},
	{
		itemId     = "mushroom",
		maxCount   = 5,
		respawnMin = 90,
		respawnMax = 240,
		color      = Color3.fromRGB(200, 140, 60),
		size       = Vector3.new(0.5, 0.55, 0.5),
	},
}

-- ── Spawn zone helpers ────────────────────────────────────────────────────

-- Returns the center and half-extents of a random spawn zone.
local function getZoneBounds(): (Vector3, Vector3)
	local zonesFolder = Workspace:FindFirstChild("ScatterZones")
	if zonesFolder then
		local children = zonesFolder:GetChildren()
		if #children > 0 then
			local zone = children[math.random(1, #children)]
			if zone:IsA("BasePart") then
				return zone.Position, zone.Size * 0.5
			end
		end
	end
	-- Default: 60×60 around origin
	return Vector3.new(0, 0, 0), Vector3.new(30, 0, 30)
end

-- Picks a random X,Z in the zone and raycasts down to find ground level.
local function randomGroundPosition(): Vector3
	local center, half = getZoneBounds()
	local x = center.X + (math.random() * 2 - 1) * half.X
	local z = center.Z + (math.random() * 2 - 1) * half.Z
	local origin = Vector3.new(x, center.Y + 500, z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -1200, 0))
	local y = result and (result.Position.Y + 0.3) or (center.Y + 0.3)
	return Vector3.new(x, y, z)
end

-- ── Scatter folder ────────────────────────────────────────────────────────

local scatterFolder = Workspace:FindFirstChild("Scatter")
if not scatterFolder then
	scatterFolder = Instance.new("Folder")
	scatterFolder.Name   = "Scatter"
	scatterFolder.Parent = Workspace
end

-- ── Model creation ────────────────────────────────────────────────────────

local function createScatterModel(cfg: ScatterDef): Model
	local itemDef = ItemRegistry.get(cfg.itemId)
	local model   = Instance.new("Model")
	model.Name    = itemDef and itemDef.displayName or cfg.itemId
	model:SetAttribute("_ScatterItem", cfg.itemId)

	local part          = Instance.new("Part")
	part.Name           = "Body"
	part.Size           = cfg.size
	part.Color          = cfg.color
	part.Material       = Enum.Material.SmoothPlastic
	part.Anchored       = true
	part.CastShadow     = true
	part.CFrame         = CFrame.new(randomGroundPosition())
		* CFrame.Angles(0, math.random() * math.pi * 2, 0)
	part.Parent         = model
	model.PrimaryPart   = part
	model.Parent        = scatterFolder
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
