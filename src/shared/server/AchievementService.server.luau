-- AchievementService.server.luau
-- Tracks per-player achievement counters and unlocks.
-- Listens to EventBridge.onFire for automatic counter increments.
-- Persists via PlayerStateService (BindableFunctions for load/save).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local AchievementConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AchievementConfig"))
local EventBridge       = require(script.Parent:WaitForChild("EventBridge"))

-- ── Remotes ─────────────────────────────────────────────────────────────
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local achieveUnlockedRemote = Instance.new("RemoteEvent")
achieveUnlockedRemote.Name = "AchievementUnlocked"
achieveUnlockedRemote.Parent = remotesFolder

local achieveSyncRemote = Instance.new("RemoteEvent")
achieveSyncRemote.Name = "AchievementSync"
achieveSyncRemote.Parent = remotesFolder

local achieveRequestRemote = Instance.new("RemoteEvent")
achieveRequestRemote.Name = "AchievementRequest"
achieveRequestRemote.Parent = remotesFolder

-- ── BindableFunctions (for PlayerStateService integration) ──────────────
local bindablesFolder = ServerStorage:WaitForChild("ServerBindables")

local achLoadFunc = Instance.new("BindableFunction")
achLoadFunc.Name = "AchievementLoad"
achLoadFunc.Parent = bindablesFolder

local achSaveFunc = Instance.new("BindableFunction")
achSaveFunc.Name = "AchievementSave"
achSaveFunc.Parent = bindablesFolder

local achGetStateFunc = Instance.new("BindableFunction")
achGetStateFunc.Name = "AchievementGetState"
achGetStateFunc.Parent = bindablesFolder

-- ── Per-player state ────────────────────────────────────────────────────

type AchievementState = {
	counters: { [string]: number },
	unlocked: { [string]: number },  -- key → os.time() of unlock
	loginStreak: {
		lastLoginDate: string,
		currentStreak: number,
		longestStreak: number,
	},
}

local playerStates: { [Player]: AchievementState } = {}
local playerLoaded: { [Player]: boolean } = {}  -- gates notifications until load complete

-- ── Helpers ─────────────────────────────────────────────────────────────

local function getCounter(state: AchievementState, counter: string): number
	return state.counters[counter] or 0
end

local function getUnlockedCount(state: AchievementState): number
	local count = 0
	for _ in pairs(state.unlocked) do
		count += 1
	end
	return count
end

local function getMostRecentAchievement(state: AchievementState): string?
	local bestKey: string? = nil
	local bestTime = 0
	for key, t in pairs(state.unlocked) do
		if t > bestTime then
			bestTime = t
			bestKey = key
		end
	end
	return bestKey
end

local function checkAndUnlock(player: Player, state: AchievementState, counterName: string, suppressNotify: boolean?)
	local achievements = AchievementConfig.ByCounter[counterName]
	if not achievements then return end

	local currentValue = getCounter(state, counterName)
	for _, ach in ipairs(achievements) do
		if not state.unlocked[ach.key] and currentValue >= ach.threshold then
			-- Unlock!
			state.unlocked[ach.key] = os.time()

			if not suppressNotify then
				-- Notify client (toast)
				achieveUnlockedRemote:FireClient(player, {
					key      = ach.key,
					name     = ach.name,
					icon     = ach.icon,
					category = ach.category,
				})

				-- Notify web/Discord
				EventBridge.fire("achievement_unlocked", player, {
					key               = ach.key,
					name              = ach.name,
					icon              = ach.icon,
					category          = ach.category,
					counterValue      = currentValue,
					totalUnlocked     = getUnlockedCount(state),
					totalAchievements = AchievementConfig.TotalCount,
				})
			end
		end
	end
end

local function incrementCounter(player: Player, state: AchievementState, counterName: string, amount: number?, suppressNotify: boolean?)
	local prev = state.counters[counterName] or 0
	state.counters[counterName] = prev + (amount or 1)
	checkAndUnlock(player, state, counterName, suppressNotify)
end

local function setCounterMax(player: Player, state: AchievementState, counterName: string, value: number, suppressNotify: boolean?)
	local prev = state.counters[counterName] or 0
	if value > prev then
		state.counters[counterName] = value
		checkAndUnlock(player, state, counterName, suppressNotify)
	end
end

-- ── EventBridge listener ────────────────────────────────────────────────

EventBridge.onFire(function(eventType: string, player: Player?, data: { [string]: any })
	if not player then return end

	local mappings = AchievementConfig.EventMappings[eventType]
	if not mappings then return end

	for _, mapping in ipairs(mappings) do
		-- Check condition
		if mapping.condition and not mapping.condition(data) then continue end

		-- Determine which player gets credit
		local targetPlayer = player
		if mapping.playerFrom == "killer" then
			local killerId = data.killerUserId
			if type(killerId) == "number" then
				targetPlayer = Players:GetPlayerByUserId(killerId)
			else
				continue  -- no killer info, skip
			end
		end
		if not targetPlayer then continue end

		local state = playerStates[targetPlayer]
		if not state then continue end
		if not playerLoaded[targetPlayer] then continue end

		-- Determine value
		local value = 1
		if mapping.valueFrom then
			value = mapping.valueFrom(data)
		end

		-- Apply
		if mapping.mode == "max" then
			setCounterMax(targetPlayer, state, mapping.counter, value)
		else
			incrementCounter(targetPlayer, state, mapping.counter, value)
		end
	end
end)

-- ── Login streak logic ──────────────────────────────────────────────────

local function updateLoginStreak(player: Player, state: AchievementState, suppressNotify: boolean?)
	local today = os.date("!%Y-%m-%d") :: string
	local streak = state.loginStreak

	if streak.lastLoginDate == today then
		-- Already logged in today, no change
		return
	end

	-- Check if yesterday
	local yesterday = os.date("!%Y-%m-%d", os.time() - 86400) :: string
	if streak.lastLoginDate == yesterday then
		streak.currentStreak += 1
	else
		streak.currentStreak = 1
	end

	streak.lastLoginDate = today
	if streak.currentStreak > streak.longestStreak then
		streak.longestStreak = streak.currentStreak
	end

	-- Update the counter and check achievements
	state.counters["login_streak"] = streak.currentStreak
	checkAndUnlock(player, state, "login_streak", suppressNotify)
end

-- ── Playtime tracking ───────────────────────────────────────────────────

local PLAYTIME_TICK = 60  -- seconds between playtime increments

task.spawn(function()
	while true do
		task.wait(PLAYTIME_TICK)
		for player, state in pairs(playerStates) do
			if player.Parent then
				incrementCounter(player, state, "playtime_total", PLAYTIME_TICK)
			end
		end
	end
end)

-- ── Credits peak tracking ───────────────────────────────────────────────

local function watchCredits(player: Player)
	player:GetAttributeChangedSignal("Credits"):Connect(function()
		local state = playerStates[player]
		if not state then return end
		local credits = player:GetAttribute("Credits")
		if type(credits) == "number" then
			setCounterMax(player, state, "credits_peak", credits)
		end
	end)
end

-- ── BindableFunction handlers ───────────────────────────────────────────

achLoadFunc.OnInvoke = function(player: Player, savedData: any?)
	local state: AchievementState = {
		counters = {},
		unlocked = {},
		loginStreak = {
			lastLoginDate = "",
			currentStreak = 0,
			longestStreak = 0,
		},
	}

	if type(savedData) == "table" then
		if type(savedData.counters) == "table" then
			for k, v in pairs(savedData.counters) do
				if type(k) == "string" and type(v) == "number" then
					state.counters[k] = v
				end
			end
		end
		if type(savedData.unlocked) == "table" then
			for k, v in pairs(savedData.unlocked) do
				if type(k) == "string" and type(v) == "number" then
					state.unlocked[k] = v
				end
			end
		end
		if type(savedData.loginStreak) == "table" then
			local ls = savedData.loginStreak
			state.loginStreak.lastLoginDate = type(ls.lastLoginDate) == "string" and ls.lastLoginDate or ""
			state.loginStreak.currentStreak = type(ls.currentStreak) == "number" and ls.currentStreak or 0
			state.loginStreak.longestStreak = type(ls.longestStreak) == "number" and ls.longestStreak or 0
		end
	end

	playerStates[player] = state

	-- Silent retroactive sweep: if counters already meet thresholds but
	-- unlocked dict is missing entries (e.g. first load, incomplete save),
	-- mark them as unlocked without firing toasts or web events.
	local backfilled = 0
	for _, ach in ipairs(AchievementConfig.Achievements) do
		if not state.unlocked[ach.key] then
			local val = state.counters[ach.counter] or 0
			if val >= ach.threshold then
				state.unlocked[ach.key] = os.time()
				backfilled += 1
			end
		end
	end

	-- Debug: show what was restored
	local counterCount = 0
	for _ in pairs(state.counters) do counterCount += 1 end
	local unlockedCount = 0
	for _ in pairs(state.unlocked) do unlockedCount += 1 end
	print(string.format("[ACHIEVEMENTS] Loaded %d counters, %d unlocked (%d backfilled) for %s",
		counterCount, unlockedCount, backfilled, player.Name))

	-- Update login streak on load (suppress toasts — these are catch-up unlocks)
	updateLoginStreak(player, state, true)

	-- Initialize credits_peak from current credits if not set (suppress toasts)
	local credits = player:GetAttribute("Credits")
	if type(credits) == "number" then
		setCounterMax(player, state, "credits_peak", credits, true)
	end

	-- Start watching credits changes
	watchCredits(player)

	-- Mark player as fully loaded — EventBridge events will now fire toasts
	playerLoaded[player] = true

	-- Send full state to client
	task.defer(function()
		if player.Parent then
			achieveSyncRemote:FireClient(player, {
				counters = state.counters,
				unlocked = state.unlocked,
				totalAchievements = AchievementConfig.TotalCount,
			})
		end
	end)

	return true
end

achSaveFunc.OnInvoke = function(player: Player)
	local state = playerStates[player]
	if not state then return nil end
	return {
		counters = state.counters,
		unlocked = state.unlocked,
		loginStreak = state.loginStreak,
	}
end

achGetStateFunc.OnInvoke = function(player: Player)
	local state = playerStates[player]
	if not state then
		return { unlockedCount = 0, totalCount = AchievementConfig.TotalCount, mostRecentKey = nil }
	end
	return {
		unlockedCount = getUnlockedCount(state),
		totalCount = AchievementConfig.TotalCount,
		mostRecentKey = getMostRecentAchievement(state),
	}
end

-- ── Client sync request ─────────────────────────────────────────────────

achieveRequestRemote.OnServerEvent:Connect(function(player)
	local state = playerStates[player]
	if not state then return end
	achieveSyncRemote:FireClient(player, {
		counters = state.counters,
		unlocked = state.unlocked,
		totalAchievements = AchievementConfig.TotalCount,
	})
end)

-- ── Cleanup ─────────────────────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player)
	-- Defer cleanup so PlayerStateService can save achievement data first.
	-- buildProfileFromState invokes AchievementSave synchronously before
	-- yielding to SetAsync, so the state must remain alive until then.
	task.defer(function()
		playerStates[player] = nil
		playerLoaded[player] = nil
	end)
end)
