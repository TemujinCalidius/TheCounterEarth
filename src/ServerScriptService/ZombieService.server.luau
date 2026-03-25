-- ZombieService.server.luau
-- Manages hostile zombie NPCs. Spawns them in ZombieZones, runs AI state machines
-- (idle → wander → chase → attack → dead), and handles combat with players.
--
-- Movement: anchored root + PivotTo (no Humanoid physics). Same pattern as AnimalService.
-- Each zombie runs its own coroutine for AI + Heartbeat drives smooth stepping.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local EventBridge    = require(script.Parent:WaitForChild("EventBridge"))

-- ── Config ────────────────────────────────────────────────────────────────
local cfg              = GameplayConfig.Zombie or {}
local ZOMBIE_HEALTH    = cfg.Health or 50
local WALK_SPEED       = cfg.WalkSpeed or 4
local RUN_SPEED        = cfg.RunSpeed or 14
local DETECTION_RADIUS = cfg.DetectionRadius or 30
local ATTACK_RANGE     = cfg.AttackRange or 5
local ATTACK_DAMAGE    = cfg.AttackDamage or 15
local ATTACK_COOLDOWN  = cfg.AttackCooldown or 1.5
local ATTACK_DMG_DELAY = cfg.AttackDamageDelay or 0.4
local LEASH_RADIUS     = cfg.LeashRadius or 80
local IDLE_DUR         = cfg.IdleDuration or { 4, 10 }
local WANDER_RADIUS    = cfg.WanderRadius or 12
local RESPAWN_SECONDS  = cfg.RespawnSeconds or { 60, 120 }
local MAX_PER_ZONE     = cfg.MaxPerZone or 4
local CORPSE_PERSIST   = cfg.CorpsePersistSeconds or 8
local CORPSE_FADE      = cfg.CorpseFadeSeconds or 1
local IDLE_SOUND_INT   = cfg.IdleSoundInterval or { 30, 90 }
local SOUND_RANGE      = cfg.SoundRange or 50

-- ── Animation IDs ─────────────────────────────────────────────────────────
local ANIM_IDLE_REGULAR  = "rbxassetid://72095555693371"
local ANIM_IDLE_CRAWL    = "rbxassetid://133599561611763"
local ANIM_STANDUP       = "rbxassetid://87043118412010"
local ANIM_WALK          = "rbxassetid://92859087628907"
local ANIM_SCREAM        = "rbxassetid://103346483374885"
local ANIM_RUN           = "rbxassetid://105176148929312"
local ANIM_ATTACK        = "rbxassetid://112302726565019"
local ANIM_DEATH_1       = "rbxassetid://101611478582576"
local ANIM_DEATH_2       = "rbxassetid://116112178618319"

-- ── Sound IDs ─────────────────────────────────────────────────────────────
local SND_IDLE_1  = "rbxassetid://115837408499449"
local SND_IDLE_2  = "rbxassetid://128627346328916"
local SND_SCREAM  = "rbxassetid://74578730026810"
local SND_ATTACK  = "rbxassetid://93619904550741"
local SND_DEATH   = "rbxassetid://134436104238037"

-- ── Types ─────────────────────────────────────────────────────────────────
type ZombieState = "idle" | "wander" | "chase" | "attack" | "standup" | "dead"

type ZombieData = {
	model: Model,
	humanoid: Humanoid,
	animator: Animator,
	-- Animation tracks
	idleRegularTrack: AnimationTrack,
	idleCrawlTrack: AnimationTrack,
	standupTrack: AnimationTrack,
	walkTrack: AnimationTrack,
	runTrack: AnimationTrack,
	screamTrack: AnimationTrack,
	attackTrack: AnimationTrack,
	deathTrack1: AnimationTrack,
	deathTrack2: AnimationTrack,
	-- State
	state: ZombieState,
	spawnPoint: Vector3,
	zone: BasePart,
	halfHeight: number,
	moveTarget: Vector3?,
	moveSpeed: number,
	-- Zombie-specific
	hasScreamed: boolean,
	isCrawling: boolean,
	currentIdleAnim: AnimationTrack?,
	targetPlayer: Player?,
	lastAttackTime: number,
	lastDamageBy: Player?,
	zombieType: string,
}

local activeZombies: { ZombieData } = {}

-- ── Zombies folder ────────────────────────────────────────────────────────
local zombiesFolder = Workspace:FindFirstChild("Zombies")
if not zombiesFolder then
	zombiesFolder = Instance.new("Folder")
	zombiesFolder.Name = "Zombies"
	zombiesFolder.Parent = Workspace
end

-- ── NPC damage tag (for death cause attribution) ──────────────────────────
local bindablesFolder = ServerStorage:WaitForChild("ServerBindables")
local npcDamageTag = bindablesFolder:WaitForChild("NpcDamageTag") :: BindableEvent

-- ── Raycast filter ────────────────────────────────────────────────────────
local zombieRayParams: RaycastParams = nil :: any

local function buildRayParams()
	zombieRayParams = RaycastParams.new()
	zombieRayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = { zombiesFolder }
	for _, name in { "Animals", "ScatterZones", "AnimalZones", "ZombieZones", "Scatter" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then table.insert(filterList, folder) end
	end
	zombieRayParams.FilterDescendantsInstances = filterList
end

task.defer(function()
	Workspace:WaitForChild("ScatterZones", 15)
	Workspace:WaitForChild("Scatter", 15)
	buildRayParams()
end)

-- ── Terrain helpers ───────────────────────────────────────────────────────
local function groundSurfaceY(x: number, z: number): number?
	if not zombieRayParams then buildRayParams() end
	local rayResult = Workspace:Raycast(
		Vector3.new(x, 500, z),
		Vector3.new(0, -1000, 0),
		zombieRayParams
	)
	if rayResult then
		return rayResult.Position.Y
	end
	return nil
end

-- ── Model creation ────────────────────────────────────────────────────────
local scatterModels = ServerStorage:FindFirstChild("ScatterModels")

local function loadAnimation(animator: Animator, id: string, looped: boolean): AnimationTrack
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local track = animator:LoadAnimation(anim)
	track.Looped = looped
	return track
end

local function createSound(parent: BasePart, name: string, soundId: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMaxDistance = SOUND_RANGE
	sound.RollOffMinDistance = 5
	sound.Parent = parent
	return sound
end

local function createZombieModel(position: Vector3, zombieType: string): Model
	local template = scatterModels and scatterModels:FindFirstChild(zombieType)
	local model: Model

	if template then
		model = template:Clone()
		model.Name = "Zombie"
	else
		-- Fallback placeholder
		model = Instance.new("Model")
		model.Name = "Zombie"

		local body = Instance.new("Part")
		body.Name = "HumanoidRootPart"
		body.Size = Vector3.new(1.5, 4.0, 1.5)
		body.Color = Color3.fromRGB(85, 120, 75)
		body.Material = Enum.Material.SmoothPlastic
		body.Anchored = true
		body.CanCollide = false
		body.Parent = model
		model.PrimaryPart = body
	end

	local root = model.PrimaryPart :: BasePart
	root.Anchored = true
	root.CanCollide = false

	-- Non-root parts must be unanchored + welded to root (same as deer)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			part.Anchored = false
			part.CanCollide = false
			-- Auto-create weld if none exists
			local hasWeld = false
			for _, child in part:GetChildren() do
				if child:IsA("WeldConstraint") or child:IsA("Motor6D") then
					hasWeld = true
					break
				end
			end
			if not hasWeld then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end

	-- Humanoid (health + damage only, NOT movement)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
	end
	humanoid.MaxHealth = ZOMBIE_HEALTH
	humanoid.Health = ZOMBIE_HEALTH
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	-- Name billboard + health bar on Head
	local head = model:FindFirstChild("Head")
	if head and not head:FindFirstChildOfClass("BillboardGui") then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(120, 30)
		billboard.StudsOffset = Vector3.new(0, 2.5, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 30
		billboard.Parent = head

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.fromScale(1, 1)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = "Zombie"
		nameLabel.TextColor3 = Color3.fromRGB(180, 50, 50)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 14
		nameLabel.TextStrokeTransparency = 0.5
		nameLabel.Parent = billboard

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
		hpFill.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
		hpFill.BorderSizePixel = 0
		hpFill.Parent = hpBar
	end

	-- Sounds
	createSound(root, "Idle1",  SND_IDLE_1,  0.4)
	createSound(root, "Idle2",  SND_IDLE_2,  0.4)
	createSound(root, "Scream", SND_SCREAM,  0.8)
	createSound(root, "Attack", SND_ATTACK,  0.6)
	createSound(root, "Death",  SND_DEATH,   0.8)

	-- Place at ground level — use root's offset from model bottom (not half bounding box)
	local surfaceY = groundSurfaceY(position.X, position.Z) or position.Y
	local bbCF, modelSize = model:GetBoundingBox()
	local modelBottomY = bbCF.Position.Y - modelSize.Y / 2
	local rootOffsetFromBottom = root.Position.Y - modelBottomY
	model:PivotTo(CFrame.new(position.X, surfaceY + rootOffsetFromBottom, position.Z))
	model.Parent = zombiesFolder

	return model
end

-- ── Sound helper ──────────────────────────────────────────────────────────
local function playSound(root: BasePart, name: string)
	local sound = root:FindFirstChild(name) :: Sound?
	if sound and not sound.IsPlaying then
		sound:Play()
	end
end

-- ── AI helpers ────────────────────────────────────────────────────────────
local function randomInZone(zone: BasePart): Vector3
	if not zombieRayParams then buildRayParams() end
	local size = zone.Size
	local cf = zone.CFrame
	local rx = (math.random() - 0.5) * size.X
	local rz = (math.random() - 0.5) * size.Z
	local worldPos = cf:PointToWorldSpace(Vector3.new(rx, 0, rz))
	local groundY = groundSurfaceY(worldPos.X, worldPos.Z)
	if groundY then
		return Vector3.new(worldPos.X, groundY, worldPos.Z)
	end
	return worldPos
end

local function getNearestPlayerInRange(position: Vector3, radius: number): (number, Player?)
	local best = math.huge
	local bestPlayer: Player? = nil
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local dist = (root.Position - position).Magnitude
			if dist < best and dist <= radius then
				best = dist
				bestPlayer = p
			end
		end
	end
	return best, bestPlayer
end

local function pickSafeTarget(origin: Vector3, direction: Vector3, dist: number): Vector3?
	for attempt = 1, 5 do
		local dir = direction
		if attempt > 1 then
			local angle = (math.random() - 0.5) * math.pi
			dir = CFrame.Angles(0, angle, 0) * direction
		end
		local tx = origin.X + dir.X * dist
		local tz = origin.Z + dir.Z * dist
		local gy = groundSurfaceY(tx, tz)
		if gy then
			return Vector3.new(tx, gy, tz)
		end
	end
	return nil
end

local function stopAllAnimations(zombie: ZombieData)
	for _, track in {
		zombie.idleRegularTrack, zombie.idleCrawlTrack, zombie.standupTrack,
		zombie.walkTrack, zombie.runTrack, zombie.screamTrack, zombie.attackTrack,
		zombie.deathTrack1, zombie.deathTrack2,
	} do
		if track.IsPlaying then track:Stop(0) end
	end
end

-- ── Heartbeat: smooth CFrame stepping + health bar ───────────────────────
RunService.Heartbeat:Connect(function(dt: number)
	local i = 1
	while i <= #activeZombies do
		local zombie = activeZombies[i]
		if not zombie.model.Parent or zombie.state == "dead" then
			table.remove(activeZombies, i)
			continue
		end

		local root = zombie.model.PrimaryPart
		if not root then
			i += 1
			continue
		end

		-- Move toward target via PivotTo
		local target = zombie.moveTarget
		if target then
			local pos = root.Position
			local dx = target.X - pos.X
			local dz = target.Z - pos.Z
			local flatDist = math.sqrt(dx * dx + dz * dz)

			if flatDist < 0.5 then
				zombie.moveTarget = nil
			else
				local step = math.min(zombie.moveSpeed * dt, flatDist)
				local dirX = dx / flatDist
				local dirZ = dz / flatDist
				local newX = pos.X + dirX * step
				local newZ = pos.Z + dirZ * step

				local surfY = groundSurfaceY(newX, newZ)
				local newY = surfY and (surfY + zombie.halfHeight) or pos.Y

				local newPos = Vector3.new(newX, newY, newZ)
				local lookAt = Vector3.new(newX + dirX, newY, newZ + dirZ)
				zombie.model:PivotTo(CFrame.lookAt(newPos, lookAt))
			end
		end

		-- Update health bar
		local hum = zombie.humanoid
		local head = zombie.model:FindFirstChild("Head")
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

-- ── Idle sound loop (per-zombie coroutine) ────────────────────────────────
local function runZombieIdleSound(zombie: ZombieData)
	local model = zombie.model
	task.wait(math.random(10, IDLE_SOUND_INT[2]))
	while model.Parent and zombie.state ~= "dead" do
		if zombie.state == "idle" or zombie.state == "wander" then
			local root = model.PrimaryPart
			if root then
				local soundName = math.random(1, 2) == 1 and "Idle1" or "Idle2"
				playSound(root, soundName)
			end
		end
		task.wait(math.random(IDLE_SOUND_INT[1], IDLE_SOUND_INT[2]))
	end
end

-- ── Per-zombie coroutine AI loop ──────────────────────────────────────────
local function runZombieAI(zombie: ZombieData)
	local model = zombie.model

	while model.Parent and zombie.state ~= "dead" do
		local root = model.PrimaryPart
		if not root then break end
		local pos = root.Position

		-- ── Detection check ──
		local nearDist, nearPlayer = getNearestPlayerInRange(pos, DETECTION_RADIUS)
		local detected = nearPlayer ~= nil

		-- ── IDLE STATE ──
		if zombie.state == "idle" and not detected then
			zombie.moveTarget = nil
			zombie.moveSpeed = 0

			-- Pick random idle animation
			local useCrawl = math.random(1, 3) == 1  -- ~33% chance crawling
			zombie.isCrawling = useCrawl
			if useCrawl then
				zombie.currentIdleAnim = zombie.idleCrawlTrack
			else
				zombie.currentIdleAnim = zombie.idleRegularTrack
			end
			zombie.currentIdleAnim:Play()

			-- Wait idle duration, check for player every 0.5s
			local idleTime = math.random(IDLE_DUR[1], IDLE_DUR[2])
			local idleStart = os.clock()
			while (os.clock() - idleStart) < idleTime do
				task.wait(0.5)
				if zombie.state == "dead" or not model.Parent then break end
				local d = getNearestPlayerInRange(root.Position, DETECTION_RADIUS)
				if d < math.huge then break end  -- player detected
			end

			if zombie.currentIdleAnim then
				zombie.currentIdleAnim:Stop()
				zombie.currentIdleAnim = nil
			end

			if zombie.state == "dead" or not model.Parent then break end

			-- Transition to wander if no player detected
			local d2 = getNearestPlayerInRange(root.Position, DETECTION_RADIUS)
			if d2 >= math.huge then
				zombie.state = "wander"
			end

		-- ── WANDER STATE ──
		elseif zombie.state == "wander" and not detected then
			zombie.isCrawling = false
			zombie.moveSpeed = WALK_SPEED
			zombie.walkTrack:Play()

			local wanderDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
			local wanderDist = math.random(3, WANDER_RADIUS)
			local safeTarget = pickSafeTarget(zombie.spawnPoint, wanderDir, wanderDist)
			if safeTarget then
				zombie.moveTarget = safeTarget
			end

			-- Wait until arrived or timeout, check for player
			local waitStart = os.clock()
			while zombie.moveTarget and (os.clock() - waitStart) < 6 do
				task.wait(0.3)
				if zombie.state == "dead" or not model.Parent then break end
				local d = getNearestPlayerInRange(root.Position, DETECTION_RADIUS)
				if d < math.huge then break end
			end

			zombie.walkTrack:Stop()
			zombie.moveTarget = nil

			if zombie.state ~= "dead" then
				zombie.state = "idle"
			end

		-- ── DETECTION → CHASE TRANSITION ──
		elseif detected and (zombie.state == "idle" or zombie.state == "wander") then
			-- Stop current animations
			if zombie.currentIdleAnim and zombie.currentIdleAnim.IsPlaying then
				zombie.currentIdleAnim:Stop()
				zombie.currentIdleAnim = nil
			end
			if zombie.walkTrack.IsPlaying then zombie.walkTrack:Stop() end
			zombie.moveTarget = nil

			zombie.targetPlayer = nearPlayer

			-- If crawling, stand up first
			if zombie.isCrawling then
				zombie.state = "standup"
				zombie.standupTrack:Play()
				zombie.standupTrack.Stopped:Wait()
				zombie.isCrawling = false
				if zombie.state == "dead" or not model.Parent then break end
			end

			-- Scream on first detection
			if not zombie.hasScreamed then
				zombie.screamTrack:Play()
				playSound(root, "Scream")
				zombie.hasScreamed = true
				-- Wait partial scream before starting chase
				task.wait(math.min(zombie.screamTrack.Length * 0.6, 1.0))
				zombie.screamTrack:Stop()
				if zombie.state == "dead" or not model.Parent then break end
			end

			zombie.state = "chase"

		-- ── CHASE STATE ──
		elseif zombie.state == "chase" then
			zombie.runTrack:Play()
			zombie.moveSpeed = RUN_SPEED

			while zombie.state == "chase" and model.Parent do
				local target2 = zombie.targetPlayer
				local targetChar = target2 and target2.Character
				local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
				local targetHum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")

				if not targetRoot or not targetHum or targetHum.Health <= 0 then
					-- Target lost or dead
					zombie.state = "idle"
					zombie.hasScreamed = false
					zombie.targetPlayer = nil
					break
				end

				local dist = (targetRoot.Position - root.Position).Magnitude

				-- Leash check
				local distFromSpawn = (root.Position - zombie.spawnPoint).Magnitude
				if distFromSpawn > LEASH_RADIUS then
					zombie.state = "idle"
					zombie.hasScreamed = false
					zombie.targetPlayer = nil
					break
				end

				if dist <= ATTACK_RANGE then
					-- ── ATTACK ──
					zombie.state = "attack"
					zombie.moveTarget = nil
					zombie.runTrack:Stop()

					zombie.attackTrack:Play()
					playSound(root, "Attack")

					-- Damage window
					task.wait(ATTACK_DMG_DELAY)

					if zombie.state == "dead" or not model.Parent then break end

					-- Re-check range (player might have dodged)
					if targetRoot.Parent and targetHum.Health > 0 then
						local currentDist = (targetRoot.Position - root.Position).Magnitude
						if currentDist <= ATTACK_RANGE * 1.5 then
							targetHum:TakeDamage(ATTACK_DAMAGE)
							npcDamageTag:Fire(target2, "zombie")
						end
					end

					-- Wait for cooldown
					task.wait(math.max(ATTACK_COOLDOWN - ATTACK_DMG_DELAY, 0.1))
					zombie.attackTrack:Stop()

					if zombie.state == "dead" or not model.Parent then break end

					-- Return to chase if target still alive
					if targetHum.Health > 0 and targetRoot.Parent then
						zombie.state = "chase"
					else
						zombie.state = "idle"
						zombie.hasScreamed = false
						zombie.targetPlayer = nil
					end
				else
					-- Move toward player
					zombie.moveTarget = targetRoot.Position
					print("[ZombieService] Chase:", "dist=" .. math.floor(dist), "leash=" .. math.floor(distFromSpawn), "state=" .. zombie.state)
					task.wait(0.2)
				end
			end

			zombie.runTrack:Stop()
			zombie.moveTarget = nil

		else
			task.wait(0.5)
		end

		task.wait(0.1)
	end
end

-- ── Death handling ────────────────────────────────────────────────────────
local function onZombieDied(zombie: ZombieData)
	zombie.state = "dead"
	zombie.moveTarget = nil
	zombie.targetPlayer = nil
	stopAllAnimations(zombie)

	local root = zombie.model.PrimaryPart
	if not root then
		zombie.model:Destroy()
		return
	end

	-- Random death animation + death sound
	local deathTrack = math.random(1, 2) == 1 and zombie.deathTrack1 or zombie.deathTrack2
	deathTrack:Play()
	playSound(root, "Death")

	-- Fire kill event
	if zombie.lastDamageBy then
		EventBridge.fire("zombie_killed", zombie.lastDamageBy, {
			zombieType = zombie.zombieType,
		})
	end

	-- Corpse persists, then fades and is destroyed
	task.delay(CORPSE_PERSIST, function()
		if not zombie.model.Parent then return end

		-- Collect all visible parts for fade
		local parts: { BasePart } = {}
		for _, part in zombie.model:GetDescendants() do
			if part:IsA("BasePart") then
				table.insert(parts, part)
			end
		end

		-- Fade out
		local fadeStart = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function()
			local elapsed = os.clock() - fadeStart
			local alpha = math.clamp(elapsed / CORPSE_FADE, 0, 1)
			for _, part in parts do
				if part.Parent then
					part.Transparency = alpha
				end
			end
			if alpha >= 1 then
				conn:Disconnect()
				if zombie.model.Parent then zombie.model:Destroy() end
			end
		end)
	end)

	-- Respawn
	local respawnTime = math.random(RESPAWN_SECONDS[1], RESPAWN_SECONDS[2])
	task.delay(respawnTime, function()
		if zombie.zone.Parent then
			spawnZombieInZone(zombie.zone, zombie.zombieType)
		end
	end)
end

-- ── Spawn zombie in a zone ───────────────────────────────────────────────
function spawnZombieInZone(zone: BasePart, zombieType: string)
	local spawnPos = randomInZone(zone)

	local model = createZombieModel(spawnPos, zombieType)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Load all animations
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local bbCF, modelSize = model:GetBoundingBox()
	local modelBottomY = bbCF.Position.Y - modelSize.Y / 2
	local rootY = model.PrimaryPart and model.PrimaryPart.Position.Y or bbCF.Position.Y
	local rootOffsetFromBottom = rootY - modelBottomY
	local zombie: ZombieData = {
		model = model,
		humanoid = humanoid,
		animator = animator,
		-- Animation tracks
		idleRegularTrack = loadAnimation(animator, ANIM_IDLE_REGULAR, true),
		idleCrawlTrack   = loadAnimation(animator, ANIM_IDLE_CRAWL, true),
		standupTrack     = loadAnimation(animator, ANIM_STANDUP, false),
		walkTrack        = loadAnimation(animator, ANIM_WALK, true),
		runTrack         = loadAnimation(animator, ANIM_RUN, true),
		screamTrack      = loadAnimation(animator, ANIM_SCREAM, false),
		attackTrack      = loadAnimation(animator, ANIM_ATTACK, false),
		deathTrack1      = loadAnimation(animator, ANIM_DEATH_1, false),
		deathTrack2      = loadAnimation(animator, ANIM_DEATH_2, false),
		-- State
		state = "idle",
		spawnPoint = spawnPos,
		zone = zone,
		halfHeight = rootOffsetFromBottom,
		moveTarget = nil,
		moveSpeed = 0,
		-- Zombie-specific
		hasScreamed = false,
		isCrawling = false,
		currentIdleAnim = nil,
		targetPlayer = nil,
		lastAttackTime = 0,
		lastDamageBy = nil,
		zombieType = zombieType,
	}
	table.insert(activeZombies, zombie)

	-- Track damage
	humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth <= 0 then
			onZombieDied(zombie)
			return
		end
		-- Damage triggers chase if not already chasing
		if zombie.state == "idle" or zombie.state == "wander" then
			local _, nearPlayer = getNearestPlayerInRange(
				model.PrimaryPart and model.PrimaryPart.Position or Vector3.zero,
				math.huge
			)
			if nearPlayer then
				zombie.targetPlayer = nearPlayer
				zombie.state = "chase"
			end
		end
	end)

	-- Track who dealt damage (kill attribution)
	humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		if humanoid.Health < humanoid.MaxHealth then
			local _, nearPlayer = getNearestPlayerInRange(
				model.PrimaryPart and model.PrimaryPart.Position or Vector3.zero,
				math.huge
			)
			if nearPlayer then
				zombie.lastDamageBy = nearPlayer
			end
		end
	end)

	-- Start AI + idle sound coroutines
	task.spawn(runZombieAI, zombie)
	task.spawn(runZombieIdleSound, zombie)
end

-- ── Initialize from ZombieZones ──────────────────────────────────────────
local function initZombieZones()
	local zonesFolder = Workspace:FindFirstChild("ZombieZones")
	if not zonesFolder then
		warn("[ZombieService] No ZombieZones folder found in Workspace — no zombies will spawn")
		return
	end

	print("[ZombieService] Found ZombieZones folder with", #zonesFolder:GetChildren(), "children")
	for _, zone in zonesFolder:GetChildren() do
		print("[ZombieService] Zone:", zone.Name, "IsBasePart:", zone:IsA("BasePart"))
		if zone:IsA("BasePart") then
			local maxZombies = zone:GetAttribute("MaxZombies") or MAX_PER_ZONE
			local zombieType = zone:GetAttribute("ZombieType") or "zombie_1_hospital"
			print("[ZombieService] Spawning", maxZombies, "of type", zombieType, "in zone", zone.Name)
			local template = scatterModels and scatterModels:FindFirstChild(zombieType)
			print("[ZombieService] Template found:", template ~= nil, "PrimaryPart:", template and template.PrimaryPart)
			for _ = 1, math.min(maxZombies, MAX_PER_ZONE) do
				spawnZombieInZone(zone, zombieType)
			end
		end
	end
end

task.delay(3, initZombieZones)
