-- EventBridge.luau
-- ModuleScript: centralized HTTP event dispatcher for pushing game events
-- to the external website/Discord bot.
--
-- Usage from any server script:
--   local EventBridge = require(script.Parent:WaitForChild("EventBridge"))
--   EventBridge.fire("player_death", player, { survivalSeconds = 3600 })
--
-- Events classified as "immediate" (death, trade, join, leave) are sent
-- instantly via task.spawn. All other events are queued and flushed in
-- batches every FlushIntervalSeconds by EventBridgeWorker.

local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local cfg = GameplayConfig.EventBridge or {}

local EventBridge = {}

-- ── Internal state ────────────────────────────────────────────────────

local queue: { any } = {}
local apiKey: string = ""
local enabled: boolean = cfg.Enabled ~= false
local endpointUrl: string = cfg.EndpointUrl or ""

-- Build immediate-event lookup set
local immediateSet: { [string]: boolean } = {}
for _, t in ipairs(cfg.ImmediateEventTypes or {}) do
	immediateSet[t] = true
end

-- ── Helpers ───────────────────────────────────────────────────────────

local function makePlayerInfo(player: Player): { [string]: any }
	return {
		robloxUserId = player.UserId,
		displayName  = player.DisplayName,
		username     = player.Name,
	}
end

local function makeEnvelope(events: { any }): { [string]: any }
	return {
		serverJobId = game.JobId,
		placeId     = game.PlaceId,
		timestamp   = os.time(),
		events      = events,
	}
end

local function sendPayload(payload: { [string]: any })
	local json = HttpService:JSONEncode(payload)
	local ok, err = pcall(function()
		HttpService:PostAsync(endpointUrl, json, Enum.HttpContentType.ApplicationJson, false, {
			["X-Api-Key"] = apiKey,
		})
	end)
	if not ok then
		warn("[EventBridge] HTTP send failed:", err)
	end
end

-- ── Public API ────────────────────────────────────────────────────────

--- Call once from EventBridgeWorker to read the API key and finalize setup.
function EventBridge.init()
	-- Disable in Studio unless explicitly enabled
	if RunService:IsStudio() and not cfg.EnableInStudio then
		enabled = false
		return
	end

	-- Read API key from ServerStorage.Secrets.WebHookApiKey
	local secrets = ServerStorage:FindFirstChild("Secrets")
	local keyValue = secrets and secrets:FindFirstChild("WebHookApiKey")
	if keyValue and keyValue:IsA("StringValue") and keyValue.Value ~= "" then
		apiKey = keyValue.Value
	else
		warn("[EventBridge] No API key found in ServerStorage.Secrets.WebHookApiKey — disabled")
		enabled = false
	end
end

--- Fire a game event. Immediate events are sent right away; others are queued.
--- @param eventType string — e.g. "player_death", "craft_item"
--- @param player Player? — the player involved (nil for server-wide events)
--- @param data table? — event-specific payload fields
function EventBridge.fire(eventType: string, player: Player?, data: { [string]: any }?)
	if not enabled or apiKey == "" then return end

	local event = {
		type      = eventType,
		timestamp = os.time(),
		player    = player and makePlayerInfo(player) or nil,
		data      = data or {},
	}

	if immediateSet[eventType] then
		task.spawn(sendPayload, makeEnvelope({ event }))
	else
		table.insert(queue, event)
		-- Drop oldest events if queue overflows
		local maxQueue = cfg.MaxQueueSize or 200
		while #queue > maxQueue do
			table.remove(queue, 1)
		end
	end
end

--- Flush the batch queue. Called periodically by EventBridgeWorker and on BindToClose.
function EventBridge.flush()
	if not enabled or #queue == 0 then return end

	local maxBatch = cfg.MaxBatchSize or 25
	local batch = {}
	for _ = 1, math.min(#queue, maxBatch) do
		table.insert(batch, table.remove(queue, 1))
	end

	task.spawn(sendPayload, makeEnvelope(batch))
end

return EventBridge
