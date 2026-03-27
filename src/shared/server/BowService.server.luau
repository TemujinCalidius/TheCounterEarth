-- BowService.server.luau
-- Handles bow firing, arrow projectile physics, hit detection, damage,
-- arrow sticking, and arrow pickup via ProximityPrompt.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local RunService         = game:GetService("RunService")
local Workspace          = game:GetService("Workspace")

local ItemRegistry   = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))
local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local EventBridge    = require(script.Parent:WaitForChild("EventBridge"))

local bowCfg = GameplayConfig.Combat and GameplayConfig.Combat.Bow or {}
local DRAW_TIME_MIN   = bowCfg.DrawTimeMin or 0.3
local DRAW_TIME_MAX   = bowCfg.DrawTimeMax or 1.5
local MIN_DAMAGE_RATIO = bowCfg.MinDamageRatio or 0.4
local ARROW_SPEED     = bowCfg.ArrowSpeed or 150
local ARROW_GRAVITY   = bowCfg.ArrowGravity or 50
local ARROW_LIFETIME  = bowCfg.ArrowLifetime or 300
local BASE_DRAW_CYCLE = bowCfg.BaseDrawCycle or 2.5

-- ── Remotes ─────────────────────────────────────────────────────────────
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local bowFireRemote = Instance.new("RemoteEvent")
bowFireRemote.Name = "BowFireRequest"
bowFireRemote.Parent = remotesFolder

local bowArrowSpawnRemote = Instance.new("RemoteEvent")
bowArrowSpawnRemote.Name = "BowArrowSpawn"
bowArrowSpawnRemote.Parent = remotesFolder

-- ── BindableFunctions ───────────────────────────────────────────────────
local bindables = ServerStorage:WaitForChild("ServerBindables")
local invRemove: BindableFunction = bindables:WaitForChild("InventoryRemove") :: BindableFunction
local invAdd: BindableFunction = bindables:WaitForChild("InventoryAdd") :: BindableFunction
local invGetQty: BindableFunction = bindables:WaitForChild("InventoryGetQty") :: BindableFunction
local durabilityDeduct: BindableFunction = bindables:WaitForChild("DurabilityDeduct") :: BindableFunction
local pvpDamageTag: BindableEvent = bindables:WaitForChild("PvPDamageTag") :: BindableEvent

-- ── Active arrows ───────────────────────────────────────────────────────
type ActiveArrow = {
	part: BasePart,
	model: Model?,  -- set when using mesh arrow (for PivotTo)
	velocity: Vector3,
	owner: Player,
	damage: number,
	spawnTime: number,
	stuck: boolean,
}

local activeArrows: { ActiveArrow } = {}

-- ── Per-player cooldown ─────────────────────────────────────────────────
local lastFireTime: { [Player]: number } = {}

-- ── Arrow model ─────────────────────────────────────────────────────────
local scatterModels = ServerStorage:FindFirstChild("ScatterModels")
local arrowTemplate = scatterModels and scatterModels:FindFirstChild("stone_arrow") :: Model?

-- Publish arrow template to ReplicatedStorage so clients can show nocked arrow
if arrowTemplate then
	local clientCopy = arrowTemplate:Clone()
	clientCopy.Name = "stone_arrow"
	clientCopy.Parent = ReplicatedStorage
end

local function createPlaceholderArrow(origin: CFrame, direction: Vector3): BasePart
	local arrow = Instance.new("Part")
	arrow.Name = "Arrow"
	arrow.Size = Vector3.new(0.1, 0.1, 2.0)
	arrow.Color = Color3.fromRGB(101, 67, 33)
	arrow.Material = Enum.Material.SmoothPlastic
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CastShadow = false

	-- Stone tip
	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Size = Vector3.new(0.15, 0.15, 0.3)
	tip.Color = Color3.fromRGB(140, 140, 140)
	tip.Material = Enum.Material.SmoothPlastic
	tip.Anchored = false
	tip.CanCollide = false
	tip.CastShadow = false
	tip.Parent = arrow

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = arrow
	weld.Part1 = tip
	weld.Parent = tip
	tip.CFrame = arrow.CFrame * CFrame.new(0, 0, -1.15)

	-- Orient arrow along direction
	arrow.CFrame = CFrame.lookAt(origin.Position, origin.Position + direction)
	arrow.Parent = Workspace

	return arrow
end

-- Rotation offset to align Y-up mesh along -Z (flight direction)
local ARROW_MESH_ROTATION = CFrame.Angles(math.rad(-90), 0, 0)

local function createArrowPart(origin: CFrame, direction: Vector3): (BasePart, Model?)
	if arrowTemplate then
		local model = arrowTemplate:Clone()
		model.Name = "Arrow"

		local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if not root then
			model:Destroy()
			return createPlaceholderArrow(origin, direction), nil
		end

		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CastShadow = false
			end
		end

		local cf = CFrame.lookAt(origin.Position, origin.Position + direction) * ARROW_MESH_ROTATION
		model:PivotTo(cf)
		model.Parent = Workspace

		return root, model
	end

	return createPlaceholderArrow(origin, direction), nil
end

-- ── Raycast params ──────────────────────────────────────────────────────
local function makeRaycastParams(owner: Player): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}

	-- Exclude shooter's character
	local char = owner.Character
	if char then table.insert(filterList, char) end

	-- Exclude non-hittable folders (zones, scatter items, etc.)
	local scatter = Workspace:FindFirstChild("Scatter")
	if scatter then table.insert(filterList, scatter) end
	local scatterZones = Workspace:FindFirstChild("ScatterZones")
	if scatterZones then table.insert(filterList, scatterZones) end
	local animalZones = Workspace:FindFirstChild("AnimalZones")
	if animalZones then table.insert(filterList, animalZones) end

	params.FilterDescendantsInstances = filterList
	return params
end

-- ── Hit handling ────────────────────────────────────────────────────────
local function handleHit(arrowData: ActiveArrow, hitResult: RaycastResult)
	arrowData.stuck = true
	local arrow = arrowData.part

	-- Position arrow at hit point, embedded slightly
	local hitCFrame = CFrame.lookAt(hitResult.Position - arrowData.velocity.Unit * 0.3, hitResult.Position + arrowData.velocity.Unit)
	if arrowData.model then
		arrowData.model:PivotTo(hitCFrame * ARROW_MESH_ROTATION)
	else
		arrow.CFrame = hitCFrame
	end

	-- Check if we hit a character with Humanoid
	local hitPart = hitResult.Instance
	local hitModel = hitPart:FindFirstAncestorOfClass("Model")
	local hitHum = hitModel and hitModel:FindFirstChildOfClass("Humanoid")

	if hitHum and hitHum.Health > 0 then
		-- Apply damage
		hitHum:TakeDamage(arrowData.damage)

		-- Weld arrow to hit part (sticks in target)
		arrow.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = arrow
		weld.Part1 = hitPart
		weld.Parent = arrow

		-- PvP attribution
		local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
		if hitPlayer then
			pvpDamageTag:Fire(hitPlayer, arrowData.owner)
			if hitHum.Health <= 0 then
				EventBridge.fire("pvp_kill", arrowData.owner, {
					victimUserId = hitPlayer.UserId,
					victimName = hitPlayer.DisplayName,
					weaponKind = "bow",
					weaponItemId = "primitive_bow",
				})
				EventBridge.fire("bow_kill", arrowData.owner, {})
			end
		else
			-- NPC kill
			if hitHum.Health <= 0 then
				EventBridge.fire("animal_killed", arrowData.owner, {
					animalName = hitModel.Name,
					weaponKind = "bow",
					weaponItemId = "primitive_bow",
				})
				EventBridge.fire("bow_kill", arrowData.owner, {})
			end
		end

		-- Arrow in a character is NOT recoverable — despawn after 10s
		task.delay(10, function()
			if arrow.Parent then arrow:Destroy() end
		end)
	else
		-- Hit terrain or static part — arrow is recoverable
		-- Keep it anchored at impact position
		arrow.Anchored = true

		-- Add pickup ProximityPrompt
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pick up"
		prompt.ObjectText = "Arrow"
		prompt.MaxActivationDistance = 6
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = arrow

		prompt.Triggered:Connect(function(triggerPlayer: Player)
			if not arrow.Parent then return end
			local added = invAdd:Invoke(triggerPlayer, "stone_arrow", 1)
			if added then
				arrow:Destroy()
			end
		end)

		-- Auto-despawn after ARROW_LIFETIME
		task.delay(ARROW_LIFETIME, function()
			if arrow.Parent then arrow:Destroy() end
		end)
	end
end

-- ── Projectile update loop ──────────────────────────────────────────────
RunService.Heartbeat:Connect(function(dt: number)
	local i = 1
	while i <= #activeArrows do
		local arrowData = activeArrows[i]
		if arrowData.stuck then
			table.remove(activeArrows, i)
			continue
		end

		local arrow = arrowData.part
		if not arrow.Parent then
			table.remove(activeArrows, i)
			continue
		end

		-- Check if arrow has been flying too long (safety)
		if os.clock() - arrowData.spawnTime > 10 then
			arrow:Destroy()
			table.remove(activeArrows, i)
			continue
		end

		-- Apply gravity
		arrowData.velocity = arrowData.velocity + Vector3.new(0, -ARROW_GRAVITY * dt, 0)

		-- Move arrow
		local oldPos = arrow.Position
		local newPos = oldPos + arrowData.velocity * dt

		-- Raycast for hit detection
		local rayDir = newPos - oldPos
		local params = makeRaycastParams(arrowData.owner)
		local result = Workspace:Raycast(oldPos, rayDir, params)

		if result then
			handleHit(arrowData, result)
		else
			-- Update position and orientation
			if arrowData.model then
				arrowData.model:PivotTo(CFrame.lookAt(newPos, newPos + arrowData.velocity.Unit) * ARROW_MESH_ROTATION)
			else
				arrow.CFrame = CFrame.lookAt(newPos, newPos + arrowData.velocity.Unit)
			end
		end

		i += 1
	end
end)

-- ── Fire request handler ────────────────────────────────────────────────
bowFireRemote.OnServerEvent:Connect(function(player: Player, direction: Vector3, drawTime: number, targetPoint: Vector3?)
	-- Validate player alive
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	-- Validate direction
	if typeof(direction) ~= "Vector3" then return end
	if direction.Magnitude < 0.1 then return end
	direction = direction.Unit

	-- Validate target point if provided
	if targetPoint ~= nil and typeof(targetPoint) ~= "Vector3" then
		targetPoint = nil
	end

	-- Validate draw time
	if type(drawTime) ~= "number" then return end
	drawTime = math.clamp(drawTime, DRAW_TIME_MIN, DRAW_TIME_MAX)

	-- Validate equipped bow
	local eqSlot = tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0
	if eqSlot < 1 or eqSlot > 9 then return end
	local itemId = player:GetAttribute("HotbarSlot" .. eqSlot)
	if type(itemId) ~= "string" then return end
	local bowDef = ItemRegistry.get(itemId)
	if not bowDef or not bowDef.weapon or bowDef.weapon.kind ~= "bow" then return end

	-- Check quiver for draw cycle speed
	local drawCycle = BASE_DRAW_CYCLE
	local quiverItemId = player:GetAttribute("EquipSlot_Quiver")
	if type(quiverItemId) == "string" and quiverItemId ~= "" then
		local quiverDef = ItemRegistry.get(quiverItemId)
		if quiverDef and quiverDef.equipment and quiverDef.equipment.drawSpeedMultiplier then
			drawCycle = drawCycle * quiverDef.equipment.drawSpeedMultiplier
		end
	end

	-- Cooldown (draw cycle = time between shots)
	local now = os.clock()
	local lastTime = lastFireTime[player] or 0
	if (now - lastTime) < drawCycle * 0.8 then return end -- 0.8 for latency tolerance
	lastFireTime[player] = now

	-- Check ammo
	local ammoId = bowDef.weapon.ammoItemId or "stone_arrow"
	local ammoQty = invGetQty:Invoke(player, ammoId)
	if ammoQty < 1 then return end

	-- Consume ammo
	local removed = invRemove:Invoke(player, ammoId, 1)
	if not removed then return end

	-- Deduct bow durability
	durabilityDeduct:Invoke(player, itemId, 1)

	-- Calculate damage based on draw time
	local drawRatio = (drawTime - DRAW_TIME_MIN) / (DRAW_TIME_MAX - DRAW_TIME_MIN)
	drawRatio = math.clamp(drawRatio, 0, 1)
	local damageMultiplier = MIN_DAMAGE_RATIO + (1 - MIN_DAMAGE_RATIO) * drawRatio
	local damage = math.floor(bowDef.weapon.damage * damageMultiplier + 0.5)

	-- Arrow speed scales with draw ratio too
	local speedMultiplier = MIN_DAMAGE_RATIO + (1 - MIN_DAMAGE_RATIO) * drawRatio
	local speed = ARROW_SPEED * speedMultiplier

	-- Spawn origin: slightly in front of character
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local spawnPos = root.Position + direction * 2 + Vector3.new(0, 1, 0)

	-- Recompute precise direction from actual spawn position to target point
	-- This eliminates parallax from the shoulder camera offset
	if targetPoint then
		local toTarget = targetPoint - spawnPos
		if toTarget.Magnitude > 1 then
			direction = toTarget.Unit
		end
	end

	local spawnCFrame = CFrame.lookAt(spawnPos, spawnPos + direction)

	-- Play bow fire sound from player's position
	local fireSound = Instance.new("Sound")
	fireSound.SoundId = "rbxassetid://111970753008354"
	fireSound.Volume = 0.8
	fireSound.RollOffMaxDistance = 60
	fireSound.Parent = root
	fireSound:Play()
	fireSound.Ended:Once(function() fireSound:Destroy() end)

	-- Create arrow
	local arrowPart, arrowModel = createArrowPart(spawnCFrame, direction)
	local arrowData: ActiveArrow = {
		part = arrowPart,
		model = arrowModel,
		velocity = direction * speed,
		owner = player,
		damage = damage,
		spawnTime = os.clock(),
		stuck = false,
	}
	table.insert(activeArrows, arrowData)

	-- Fire tracking event
	EventBridge.fire("arrow_fired", player, {})

	-- Notify all clients so they can see the arrow
	bowArrowSpawnRemote:FireAllClients(player, spawnCFrame, direction, speed, drawRatio)
end)

-- ── Cleanup ─────────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
	lastFireTime[player] = nil
end)
