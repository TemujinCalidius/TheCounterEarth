-- AnimalService.server.luau
-- Manages animal NPCs (deer). Spawns them in AnimalZones, runs AI state machines,
-- and spawns carcasses on death for the ButcherService.
--
-- Movement: anchored root + PivotTo (no Humanoid physics). Eliminates jitter/flinging.
-- Each deer runs its own coroutine for AI + Heartbeat drives smooth stepping.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local RunService         = game:GetService("RunService")
local Workspace          = game:GetService("Workspace")

local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local EventBridge    = require(script.Parent:WaitForChild("EventBridge"))

local animalCfg = GameplayConfig.Animal or {}
local DEER_HEALTH        = animalCfg.DeerHealth or 30
local DEER_WALK_SPEED    = animalCfg.DeerWalkSpeed or 8
local DEER_FLEE_SPEED    = animalCfg.DeerFleeSpeed or 32
local DEER_FLEE_RADIUS   = animalCfg.DeerFleeRadius or 25
local DEER_IDLE_DUR      = animalCfg.DeerIdleDuration or { 3, 8 }
local DEER_WANDER_RADIUS = animalCfg.DeerWanderRadius or 20
local DEER_RESPAWN       = animalCfg.DeerRespawnSeconds or { 180, 300 }
local MAX_DEER_PER_ZONE  = animalCfg.MaxDeerPerZone or 6
local CARCASS_DESPAWN    = animalCfg.CarcassDespawnSeconds or 300
local DEER_BODY_HALF_H   = 0.9 -- half the body height, used for ground offset

-- ── Deer state types ────────────────────────────────────────────────────
type DeerState = "idle" | "wander" | "flee" | "dead"

type DeerData = {
	model: Model,
	humanoid: Humanoid,
	state: DeerState,
	spawnPoint: Vector3,
	zone: BasePart,
	lastDamageBy: Player?,
	damageFlee: boolean,
	-- CFrame movement
	moveTarget: Vector3?,   -- nil = standing still
	moveSpeed: number,      -- studs/sec for current movement
}

local activeDeer: { DeerData } = {}

-- ── Animals folder (holds all deer models, excluded from raycasts) ─────
local animalsFolder = Workspace:FindFirstChild("Animals")
if not animalsFolder then
	animalsFolder = Instance.new("Folder")
	animalsFolder.Name = "Animals"
	animalsFolder.Parent = Workspace
end

-- ── Raycast filter (exclude zones, scatter, and animal models) ─────────
local animalRayParams: RaycastParams = nil :: any

local function buildRayParams()
	animalRayParams = RaycastParams.new()
	animalRayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = { animalsFolder }
	local scatterZones = Workspace:FindFirstChild("ScatterZones")
	if scatterZones then table.insert(filterList, scatterZones) end
	local animalZones = Workspace:FindFirstChild("AnimalZones")
	if animalZones then table.insert(filterList, animalZones) end
	local scatterFolder = Workspace:FindFirstChild("Scatter")
	if scatterFolder then table.insert(filterList, scatterFolder) end
	animalRayParams.FilterDescendantsInstances = filterList
end

-- ── Terrain helpers ─────────────────────────────────────────────────────

local VOXEL_RES = 4 -- Terrain voxel resolution (always 4 studs)

-- Snap a position to terrain ground, returning ground-level Y for the body center
local function groundSnapY(x: number, z: number): number?
	if not animalRayParams then buildRayParams() end
	local rayResult = Workspace:Raycast(
		Vector3.new(x, 500, z),
		Vector3.new(0, -1000, 0),
		animalRayParams
	)
	if rayResult then
		return rayResult.Position.Y + DEER_BODY_HALF_H + 0.5
	end
	return nil
end

-- Returns true if the Terrain voxel at `pos` is water (same pattern as ScatterSpawnService)
local function isWaterAt(pos: Vector3): boolean
	local corner = Vector3.new(
		math.floor(pos.X / VOXEL_RES) * VOXEL_RES,
		math.floor(pos.Y / VOXEL_RES) * VOXEL_RES,
		math.floor(pos.Z / VOXEL_RES) * VOXEL_RES
	)
	local region = Region3.new(corner, corner + Vector3.new(VOXEL_RES, VOXEL_RES, VOXEL_RES))
	local ok, materials = pcall(function()
		return Workspace.Terrain:ReadVoxels(region, VOXEL_RES)
	end)
	if not ok or not materials then return false end
	return materials[1][1][1] == Enum.Material.Water
end

-- Check if a position is in or near water
local function isNearWater(x: number, z: number): boolean
	local groundY = groundSnapY(x, z)
	if not groundY then return false end -- no ground ≠ water, just void
	local pos = Vector3.new(x, groundY, z)
	-- Check column below, at, and above ground
	for yOff = -4, 8, 4 do
		if isWaterAt(pos + Vector3.new(0, yOff, 0)) then return true end
	end
	return false
end

-- ── Placeholder deer model ──────────────────────────────────────────────
local function createDeerModel(position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Deer"

	-- Body (root, anchored — we move it via PivotTo; children follow via welds)
	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Size = Vector3.new(1.5, 1.8, 3.0)
	body.Color = Color3.fromRGB(139, 90, 43)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model

	-- Head (unanchored, welded to body — follows automatically)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(0.8, 0.8, 1.0)
	head.Color = Color3.fromRGB(160, 110, 60)
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = false
	head.CanCollide = false
	head.Parent = model

	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = body
	headWeld.Part1 = head
	headWeld.Parent = head
	head.CFrame = body.CFrame * CFrame.new(0, 0.5, -1.8)

	-- Legs (unanchored, welded to body)
	local legPositions = {
		Vector3.new(-0.5, -0.9, -0.8),
		Vector3.new(0.5, -0.9, -0.8),
		Vector3.new(-0.5, -0.9, 0.8),
		Vector3.new(0.5, -0.9, 0.8),
	}
	for i, offset in ipairs(legPositions) do
		local leg = Instance.new("Part")
		leg.Name = "Leg" .. i
		leg.Size = Vector3.new(0.3, 1.5, 0.3)
		leg.Color = Color3.fromRGB(120, 80, 40)
		leg.Material = Enum.Material.SmoothPlastic
		leg.Anchored = false
		leg.CanCollide = false
		leg.Parent = model

		local legWeld = Instance.new("WeldConstraint")
		legWeld.Part0 = body
		legWeld.Part1 = leg
		legWeld.Parent = leg
		leg.CFrame = body.CFrame * CFrame.new(offset)
	end

	-- Humanoid (for health tracking + damage reception only, NOT for movement)
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = DEER_HEALTH
	humanoid.Health = DEER_HEALTH
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	-- Name billboard
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(100, 30)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 40
	billboard.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "Deer"
	nameLabel.TextColor3 = Color3.fromRGB(200, 180, 140)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Parent = billboard

	-- Health bar
	local hpBar = Instance.new("Frame")
	hpBar.Name = "HealthBar"
	hpBar.Size = UDim2.new(0.6, 0, 0, 4)
	hpBar.Position = UDim2.new(0.2, 0, 1, 2)
	hpBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBar.BorderSizePixel = 0
	hpBar.Parent = billboard

	local hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBar

	model.PrimaryPart = body

	-- Place at ground level
	local groundY = groundSnapY(position.X, position.Z) or (position.Y + DEER_BODY_HALF_H)
	body.CFrame = CFrame.new(position.X, groundY, position.Z)
	model.Parent = animalsFolder

	return model
end

-- ── Carcass spawning ────────────────────────────────────────────────────
local function spawnCarcass(position: Vector3, killerPlayer: Player?)
	local carcass = Instance.new("Model")
	carcass.Name = "DeerCarcass"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(1.5, 1.0, 3.0)
	body.Color = Color3.fromRGB(100, 65, 30)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = true
	body.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	body.Parent = carcass

	carcass.PrimaryPart = body

	carcass:SetAttribute("_IsCarcass", true)
	carcass:SetAttribute("_AnimalType", "deer")
	carcass:SetAttribute("_Skinned", false)
	carcass:SetAttribute("_Butchered", false)
	carcass:SetAttribute("_SpawnTime", os.time())
	if killerPlayer then
		carcass:SetAttribute("_KillerUserId", killerPlayer.UserId)
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 30)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 30
	billboard.Parent = body

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "Deer Carcass"
	label.TextColor3 = Color3.fromRGB(180, 140, 100)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextStrokeTransparency = 0.5
	label.Parent = billboard

	carcass.Parent = Workspace

	task.delay(CARCASS_DESPAWN, function()
		if carcass.Parent then carcass:Destroy() end
	end)

	return carcass
end

-- ── AI helpers ──────────────────────────────────────────────────────────
local function randomInZone(zone: BasePart): Vector3
	if not animalRayParams then buildRayParams() end

	local size = zone.Size
	local cf = zone.CFrame
	local rx = (math.random() - 0.5) * size.X
	local rz = (math.random() - 0.5) * size.Z
	local worldPos = cf:PointToWorldSpace(Vector3.new(rx, 0, rz))

	local groundY = groundSnapY(worldPos.X, worldPos.Z)
	if groundY then
		return Vector3.new(worldPos.X, groundY, worldPos.Z)
	end
	return worldPos
end

local function getNearestPlayerDist(position: Vector3): (number, Player?)
	local best = math.huge
	local bestPlayer: Player? = nil
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local dist = (root.Position - position).Magnitude
			if dist < best then
				best = dist
				bestPlayer = p
			end
		end
	end
	return best, bestPlayer
end

local function getFleeDirection(deerPos: Vector3, threatPos: Vector3): Vector3
	local away = (deerPos - threatPos)
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
	end
	return away.Unit
end

-- Pick a safe (non-water) target position. Tries up to 5 directions before giving up.
local function pickSafeTarget(origin: Vector3, direction: Vector3, dist: number): Vector3?
	-- Try the requested direction first
	for attempt = 1, 5 do
		local dir = direction
		if attempt > 1 then
			-- Rotate the direction by random offset
			local angle = (math.random() - 0.5) * math.pi
			dir = CFrame.Angles(0, angle, 0) * direction
		end
		local tx = origin.X + dir.X * dist
		local tz = origin.Z + dir.Z * dist
		if not isNearWater(tx, tz) then
			local gy = groundSnapY(tx, tz)
			if gy then
				return Vector3.new(tx, gy, tz)
			end
		end
	end
	return nil -- all attempts hit water or void
end

-- ── Heartbeat: smooth CFrame stepping + health bar ─────────────────────
RunService.Heartbeat:Connect(function(dt: number)
	local i = 1
	while i <= #activeDeer do
		local deer = activeDeer[i]
		if not deer.model.Parent or deer.state == "dead" then
			table.remove(activeDeer, i)
			continue
		end

		local root = deer.model.PrimaryPart
		if not root then
			i += 1
			continue
		end

		-- ── Move toward target via PivotTo ──
		local target = deer.moveTarget
		if target then
			local pos = root.Position
			local dx = target.X - pos.X
			local dz = target.Z - pos.Z
			local flatDist = math.sqrt(dx * dx + dz * dz)

			if flatDist < 0.5 then
				-- Arrived
				deer.moveTarget = nil
			else
				local step = math.min(deer.moveSpeed * dt, flatDist)
				local dirX = dx / flatDist
				local dirZ = dz / flatDist
				local newX = pos.X + dirX * step
				local newZ = pos.Z + dirZ * step

				-- Ground snap
				local newY = groundSnapY(newX, newZ) or pos.Y

				-- Face movement direction
				local newPos = Vector3.new(newX, newY, newZ)
				local lookAt = Vector3.new(newX + dirX, newY, newZ + dirZ)
				deer.model:PivotTo(CFrame.lookAt(newPos, lookAt))
			end
		end

		-- ── Update health bar ──
		local hum = deer.humanoid
		local head = deer.model:FindFirstChild("Head")
		if head then
			local bg = head:FindFirstChild("BillboardGui")
			if bg then
				local hpBar = bg:FindFirstChild("HealthBar")
				if hpBar then
					local fill = hpBar:FindFirstChild("Fill")
					if fill then
						fill.Size = UDim2.fromScale(math.clamp(hum.Health / hum.MaxHealth, 0, 1), 1)
					end
				end
			end
		end

		i += 1
	end
end)

-- ── Per-deer coroutine AI loop ──────────────────────────────────────────
local function runDeerAI(deer: DeerData)
	local model = deer.model

	while model.Parent and deer.state ~= "dead" do
		local root = model.PrimaryPart
		if not root then break end

		local pos = root.Position
		local nearDist, nearPlayer = getNearestPlayerDist(pos)

		-- ── Check for flee trigger ──
		local shouldFlee = deer.damageFlee or (nearDist < DEER_FLEE_RADIUS)
		if deer.damageFlee then deer.damageFlee = false end

		if shouldFlee and deer.state ~= "dead" then
			-- Flee
			deer.state = "flee"
			deer.moveSpeed = DEER_FLEE_SPEED

			-- Direction away from player
			local fleeDir: Vector3?
			if nearPlayer then
				local playerRoot = nearPlayer.Character and nearPlayer.Character:FindFirstChild("HumanoidRootPart")
				if playerRoot then
					fleeDir = getFleeDirection(pos, playerRoot.Position)
				end
			end
			if not fleeDir then
				fleeDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
			end

			-- Pick safe (non-water) target
			local safeTarget = pickSafeTarget(pos, fleeDir, math.random(80, 120))
			if safeTarget then
				deer.moveTarget = safeTarget
			else
				-- All directions blocked (surrounded by water?) — stay put
				deer.moveTarget = nil
			end

			-- Wait until arrived or timeout
			local waitStart = os.clock()
			while deer.moveTarget and (os.clock() - waitStart) < 4 do
				task.wait(0.2)
				if deer.state == "dead" or not model.Parent then break end
			end

			-- Brief pause
			task.wait(0.3 + math.random() * 0.5)

		elseif deer.state ~= "dead" then
			-- Idle
			deer.state = "idle"
			deer.moveTarget = nil
			deer.moveSpeed = DEER_WALK_SPEED

			-- Wait idle duration, check for flee interrupt
			local idleTime = math.random(DEER_IDLE_DUR[1], DEER_IDLE_DUR[2])
			local idleStart = os.clock()
			while (os.clock() - idleStart) < idleTime do
				task.wait(0.5)
				if deer.state == "dead" or not model.Parent then break end
				local d = getNearestPlayerDist(root.Position)
				if d < DEER_FLEE_RADIUS or deer.damageFlee then break end
			end

			if deer.state == "dead" or not model.Parent then break end

			-- Re-check flee before wandering
			local d2 = getNearestPlayerDist(root.Position)
			if d2 < DEER_FLEE_RADIUS or deer.damageFlee then continue end

			-- Wander: pick random point near spawn (avoiding water)
			deer.state = "wander"
			deer.moveSpeed = DEER_WALK_SPEED
			local wanderDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
			local wanderDist = math.random(5, DEER_WANDER_RADIUS)
			local safeTarget = pickSafeTarget(deer.spawnPoint, wanderDir, wanderDist)
			if safeTarget then
				deer.moveTarget = safeTarget
			end

			-- Wait until arrived or timeout, with flee interrupt
			local waitStart = os.clock()
			while deer.moveTarget and (os.clock() - waitStart) < 8 do
				task.wait(0.3)
				if deer.state == "dead" or not model.Parent then break end
				local d = getNearestPlayerDist(root.Position)
				if d < DEER_FLEE_RADIUS or deer.damageFlee then
					deer.moveTarget = nil
					break
				end
			end
		else
			task.wait(0.5)
		end
	end
end

-- ── Deer death handling ─────────────────────────────────────────────────
local function onDeerDied(deer: DeerData)
	deer.state = "dead"
	deer.moveTarget = nil
	local pos = deer.model.PrimaryPart and deer.model.PrimaryPart.Position or Vector3.zero

	spawnCarcass(pos, deer.lastDamageBy)

	task.delay(2, function()
		if deer.model.Parent then deer.model:Destroy() end
	end)

	local respawnTime = math.random(DEER_RESPAWN[1], DEER_RESPAWN[2])
	task.delay(respawnTime, function()
		if deer.zone.Parent then
			spawnDeerInZone(deer.zone)
		end
	end)
end

-- ── Spawn deer in a zone ────────────────────────────────────────────────
function spawnDeerInZone(zone: BasePart)
	local spawnPos = randomInZone(zone)
	-- Reject spawn if in deep water
	if isNearWater(spawnPos.X, spawnPos.Z) then
		-- Try a few more spots
		for _ = 1, 5 do
			spawnPos = randomInZone(zone)
			if not isNearWater(spawnPos.X, spawnPos.Z) then break end
		end
		if isNearWater(spawnPos.X, spawnPos.Z) then return end
	end

	local model = createDeerModel(spawnPos)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local deer: DeerData = {
		model = model,
		humanoid = humanoid,
		state = "idle",
		spawnPoint = spawnPos,
		zone = zone,
		lastDamageBy = nil,
		damageFlee = false,
		moveTarget = nil,
		moveSpeed = DEER_WALK_SPEED,
	}
	table.insert(activeDeer, deer)

	-- Track damage
	humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth <= 0 then
			onDeerDied(deer)
			return
		end
		if deer.state ~= "dead" then
			deer.damageFlee = true
		end
	end)

	-- Track who dealt damage (kill attribution)
	humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		if humanoid.Health < humanoid.MaxHealth then
			local _, nearPlayer = getNearestPlayerDist(
				model.PrimaryPart and model.PrimaryPart.Position or Vector3.zero
			)
			if nearPlayer then
				deer.lastDamageBy = nearPlayer
			end
		end
	end)

	-- Start per-deer AI coroutine
	task.spawn(runDeerAI, deer)
end

-- ── Initialize from AnimalZones ─────────────────────────────────────────
local function initAnimalZones()
	local zonesFolder = Workspace:FindFirstChild("AnimalZones")
	if not zonesFolder then
		warn("[AnimalService] No AnimalZones folder found in Workspace — no deer will spawn")
		return
	end

	for _, zone in zonesFolder:GetChildren() do
		if zone:IsA("BasePart") and zone.Name:lower():find("deer") then
			local count = zone:GetAttribute("MaxDeer") or MAX_DEER_PER_ZONE
			for _ = 1, math.min(count, MAX_DEER_PER_ZONE) do
				spawnDeerInZone(zone)
			end
		end
	end
end

task.delay(3, initAnimalZones)
