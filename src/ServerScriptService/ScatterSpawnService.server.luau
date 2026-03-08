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

local function createScatterModel(cfg: ScatterDef): Model
	local itemDef = ItemRegistry.get(cfg.itemId)
	local displayName = itemDef and itemDef.displayName or cfg.itemId
	local spawnCFrame = CFrame.new(randomGroundPosition())
		* CFrame.Angles(0, math.random() * math.pi * 2, 0)

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

		-- Anchor all parts and disable collision (pickup items, not obstacles)
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored   = true
				desc.CanCollide = false
			end
		end

		local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if root then
			model:PivotTo(spawnCFrame + Vector3.new(0, cfg.size.Y * 0.5, 0))
		end

		model.Parent = scatterFolder
		return model
	end

	-- Fallback: coloured placeholder Part (for items without templates)
	local model = Instance.new("Model")
	model.Name  = displayName
	model:SetAttribute("_ScatterItem", cfg.itemId)

	local part          = Instance.new("Part")
	part.Name           = "Body"
	part.Size           = cfg.size
	part.Color          = cfg.color
	part.Material       = Enum.Material.SmoothPlastic
	part.Anchored       = true
	part.CastShadow     = true
	part.CFrame         = spawnCFrame
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
