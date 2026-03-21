-- CombatService.server.luau
-- Validates melee weapon attacks, applies damage, handles PvP attribution.
-- Only items with category == "weapon" can deal damage through this service.
-- Harvest tools (knife, axe, pickaxe) are NOT weapons and cannot attack.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local ItemRegistry  = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))
local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local EventBridge   = require(script.Parent:WaitForChild("EventBridge"))

local combatCfg = GameplayConfig.Combat or {}

-- ── Remotes ─────────────────────────────────────────────────────────────
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local combatAttackRemote = Instance.new("RemoteEvent")
combatAttackRemote.Name = "CombatAttackRequest"
combatAttackRemote.Parent = remotesFolder

local combatHitRemote = Instance.new("RemoteEvent")
combatHitRemote.Name = "CombatHitNotify"
combatHitRemote.Parent = remotesFolder

-- ── BindableEvents / Functions ──────────────────────────────────────────
local bindables = ServerStorage:WaitForChild("ServerBindables")
local pvpDamageTag: BindableEvent = bindables:WaitForChild("PvPDamageTag") :: BindableEvent
local durabilityDeduct: BindableFunction = bindables:WaitForChild("DurabilityDeduct") :: BindableFunction

-- ── Per-player cooldown tracking ────────────────────────────────────────
local lastAttackTime: { [Player]: number } = {}

-- ── Helpers ─────────────────────────────────────────────────────────────

local function getEquippedWeaponDef(player: Player): (ItemRegistry.ItemDef?, string?)
	local eqSlot = tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0
	if eqSlot < 1 or eqSlot > 9 then return nil, nil end
	local itemId = player:GetAttribute("HotbarSlot" .. eqSlot)
	if type(itemId) ~= "string" or itemId == "" then return nil, nil end
	local def = ItemRegistry.get(itemId)
	if not def or def.category ~= "weapon" then return nil, nil end
	return def, itemId
end

local function findNearestTarget(player: Player, maxRange: number): (Humanoid?, Player?, Model?)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return nil, nil, nil end

	local pos = root.Position
	local bestDist = maxRange
	local bestHum: Humanoid? = nil
	local bestPlayer: Player? = nil
	local bestModel: Model? = nil

	-- Check all characters (players + NPCs)
	for _, candidate in Workspace:GetChildren() do
		if not candidate:IsA("Model") then continue end
		if candidate == char then continue end

		local hum = candidate:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end

		local candidateRoot = candidate:FindFirstChild("HumanoidRootPart")
			or candidate.PrimaryPart
			or candidate:FindFirstChildWhichIsA("BasePart")
		if not candidateRoot then continue end

		local dist = (candidateRoot.Position - pos).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestHum = hum
			bestModel = candidate
			-- Check if this is a player character
			bestPlayer = Players:GetPlayerFromCharacter(candidate)
		end
	end

	return bestHum, bestPlayer, bestModel
end

-- ── Attack handler ──────────────────────────────────────────────────────

combatAttackRemote.OnServerEvent:Connect(function(player: Player)
	-- Validate player is alive
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	-- Validate equipped weapon
	local weaponDef, weaponId = getEquippedWeaponDef(player)
	if not weaponDef or not weaponDef.weapon then return end
	local weaponInfo = weaponDef.weapon

	-- Bows handled by BowService, not melee
	if weaponInfo.kind == "bow" then return end

	-- Cooldown check
	local now = os.clock()
	local cooldown = weaponInfo.attackCooldown or 0.8
	local lastTime = lastAttackTime[player] or 0
	if (now - lastTime) < cooldown * 0.9 then return end -- 0.9 for latency tolerance
	lastAttackTime[player] = now

	-- Find nearest target in range
	local attackRange = weaponInfo.attackRange or 6
	local targetHum, targetPlayer, targetModel = findNearestTarget(player, attackRange)
	if not targetHum or not targetModel then
		-- Swing and miss — still deduct durability and play animation
		combatHitRemote:FireClient(player, { hit = false, weaponKind = weaponInfo.kind })
		return
	end

	-- Apply damage
	local damage = weaponInfo.damage or 10
	targetHum:TakeDamage(damage)

	-- PvP attribution
	if targetPlayer then
		pvpDamageTag:Fire(targetPlayer, player)

		-- Track kill if target died
		if targetHum.Health <= 0 then
			local weaponKind = weaponInfo.kind or "unknown"
			EventBridge.fire("pvp_kill", player, {
				victimUserId = targetPlayer.UserId,
				victimName = targetPlayer.DisplayName,
				weaponKind = weaponKind,
				weaponItemId = weaponId,
			})
			-- Counter-specific kill event
			if weaponKind == "spear" then
				EventBridge.fire("spear_kill", player, {})
			end
		end
	else
		-- NPC kill
		if targetHum.Health <= 0 then
			EventBridge.fire("animal_killed", player, {
				animalName = targetModel.Name,
				weaponKind = weaponInfo.kind,
				weaponItemId = weaponId,
			})
			if weaponInfo.kind == "spear" then
				EventBridge.fire("spear_kill", player, {})
			end
		end
	end

	-- Deduct durability
	if weaponId then
		durabilityDeduct:Invoke(player, weaponId, 1)
	end

	-- Notify attacker of hit
	combatHitRemote:FireClient(player, {
		hit = true,
		weaponKind = weaponInfo.kind,
		damage = damage,
		targetName = targetModel.Name,
	})
end)

-- ── Cleanup ─────────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
	lastAttackTime[player] = nil
end)
