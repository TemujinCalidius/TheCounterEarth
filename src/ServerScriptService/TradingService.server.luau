-- TradingService.server.luau
-- Manages player-to-player trading: drag-to-initiate, accept/decline,
-- offer updates, mutual confirmation, execution with weight/capacity overflow.
--
-- Initiation: Player A opens inventory, drags an item onto Player B's
-- character model → sends TradeInitiate → Player B sees accept/decline popup.
-- On accept, trade window opens with A's initial item already offered.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local ServerStorage     = game:GetService("ServerStorage")

local ItemRegistry   = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))
local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local EventBridge    = require(script.Parent:WaitForChild("EventBridge"))

local TradingConfig = GameplayConfig.Trading or {}
local INTERACT_RANGE       = TradingConfig.InteractRange or 15
local REQUEST_TIMEOUT      = TradingConfig.RequestTimeoutSeconds or 15

-- ── Remotes ─────────────────────────────────────────────────────────────
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local function makeRemote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name   = name
	r.Parent = remotesFolder
	return r
end

local tradeInitiateRemote    = makeRemote("TradeInitiate")    -- client→server: drag-to-player initiation
local tradeRequestRemote     = makeRemote("TradeRequest")     -- server→client: incoming request popup
local tradeResponseRemote    = makeRemote("TradeResponse")    -- client→server: accept/decline
local tradeStateRemote       = makeRemote("TradeState")       -- server→client: current trade state
local tradeUpdateOfferRemote = makeRemote("TradeUpdateOffer") -- client→server: add/remove item
local tradeConfirmRemote     = makeRemote("TradeConfirm")     -- client→server: confirm trade
local tradeCancelRemote      = makeRemote("TradeCancel")      -- client→server: cancel trade

-- ── Cross-service inventory access ──────────────────────────────────────
local bindables      = ServerStorage:WaitForChild("ServerBindables")
local invAdd         = bindables:WaitForChild("InventoryAdd")       :: BindableFunction
local invRemove      = bindables:WaitForChild("InventoryRemove")    :: BindableFunction
local invGetQty      = bindables:WaitForChild("InventoryGetQty")    :: BindableFunction
local createLootBag  = bindables:WaitForChild("CreateLootBag")      :: BindableFunction

-- ── Helpers ─────────────────────────────────────────────────────────────

local function sanitizeItemId(value: any): string
	if type(value) ~= "string" then return "" end
	local s = string.sub(value, 1, 40)
	if s == "" or not s:match("^[%w_%-%s]+$") then return "" end
	return s
end

local function getPlayerRoot(plr: Player): BasePart?
	local char = plr.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart
end

local function distanceBetween(a: Player, b: Player): number
	local rootA = getPlayerRoot(a)
	local rootB = getPlayerRoot(b)
	if not rootA or not rootB then return math.huge end
	return (rootA.Position - rootB.Position).Magnitude
end

-- ── Trade state ─────────────────────────────────────────────────────────

type OfferEntry = { itemId: string, qty: number }

type TradeSession = {
	playerA: Player,
	playerB: Player,
	offerA: { OfferEntry },
	offerB: { OfferEntry },
	confirmedA: boolean,
	confirmedB: boolean,
}

-- Pending requests store the initial offer item so it's added on accept.
type PendingRequest = {
	from: Player,
	time: number,
	initialItemId: string,
	initialQty: number,
}

local activeTrades: { [Player]: TradeSession } = {} -- keyed by BOTH players
local pendingRequests: { [Player]: PendingRequest } = {}

-- ── Session helpers ─────────────────────────────────────────────────────

local function getSession(plr: Player): TradeSession?
	return activeTrades[plr]
end

local function isPlayerA(session: TradeSession, plr: Player): boolean
	return session.playerA == plr
end

local function getPartner(session: TradeSession, plr: Player): Player
	return if isPlayerA(session, plr) then session.playerB else session.playerA
end

local function getOwnOffer(session: TradeSession, plr: Player): { OfferEntry }
	return if isPlayerA(session, plr) then session.offerA else session.offerB
end

local function serializeState(session: TradeSession, forPlayer: Player): {
	partnerName: string,
	partnerUserId: number,
	myOffer: { OfferEntry },
	theirOffer: { OfferEntry },
	iConfirmed: boolean,
	theyConfirmed: boolean,
}
	local imA = isPlayerA(session, forPlayer)
	return {
		partnerName    = getPartner(session, forPlayer).Name,
		partnerUserId  = getPartner(session, forPlayer).UserId,
		myOffer        = if imA then session.offerA else session.offerB,
		theirOffer     = if imA then session.offerB else session.offerA,
		iConfirmed     = if imA then session.confirmedA else session.confirmedB,
		theyConfirmed  = if imA then session.confirmedB else session.confirmedA,
	}
end

local function broadcastState(session: TradeSession)
	tradeStateRemote:FireClient(session.playerA, serializeState(session, session.playerA))
	tradeStateRemote:FireClient(session.playerB, serializeState(session, session.playerB))
end

local function cancelTrade(session: TradeSession)
	activeTrades[session.playerA] = nil
	activeTrades[session.playerB] = nil
	tradeStateRemote:FireClient(session.playerA, nil)
	tradeStateRemote:FireClient(session.playerB, nil)
end

local function createSession(playerA: Player, playerB: Player, initialOffer: OfferEntry?)
	local session: TradeSession = {
		playerA    = playerA,
		playerB    = playerB,
		offerA     = {},
		offerB     = {},
		confirmedA = false,
		confirmedB = false,
	}

	-- Seed A's offer with the initial item they dragged
	if initialOffer then
		table.insert(session.offerA, initialOffer)
	end

	activeTrades[playerA] = session
	activeTrades[playerB] = session
	broadcastState(session)
end

-- ── Execute trade ───────────────────────────────────────────────────────

local function executeTrade(session: TradeSession)
	-- Verify both players still have offered items
	for _, entry in ipairs(session.offerA) do
		local has = invGetQty:Invoke(session.playerA, entry.itemId)
		if has < entry.qty then
			cancelTrade(session)
			return
		end
	end
	for _, entry in ipairs(session.offerB) do
		local has = invGetQty:Invoke(session.playerB, entry.itemId)
		if has < entry.qty then
			cancelTrade(session)
			return
		end
	end

	-- Remove items from both players first
	for _, entry in ipairs(session.offerA) do
		invRemove:Invoke(session.playerA, entry.itemId, entry.qty)
	end
	for _, entry in ipairs(session.offerB) do
		invRemove:Invoke(session.playerB, entry.itemId, entry.qty)
	end

	-- Give A's items to B (overflow → loot bag at B's feet)
	local overflowB: { OfferEntry } = {}
	for _, entry in ipairs(session.offerA) do
		local ok = invAdd:Invoke(session.playerB, entry.itemId, entry.qty)
		if not ok then
			table.insert(overflowB, entry)
		end
	end
	if #overflowB > 0 then
		createLootBag:Invoke(session.playerB, overflowB)
	end

	-- Give B's items to A (overflow → loot bag at A's feet)
	local overflowA: { OfferEntry } = {}
	for _, entry in ipairs(session.offerB) do
		local ok = invAdd:Invoke(session.playerA, entry.itemId, entry.qty)
		if not ok then
			table.insert(overflowA, entry)
		end
	end
	if #overflowA > 0 then
		createLootBag:Invoke(session.playerA, overflowA)
	end

	-- Clean up
	activeTrades[session.playerA] = nil
	activeTrades[session.playerB] = nil
	tradeStateRemote:FireClient(session.playerA, nil)
	tradeStateRemote:FireClient(session.playerB, nil)

	EventBridge.fire("trade_complete", session.playerA, {
		partnerUserId = session.playerB.UserId,
		partnerDisplayName = session.playerB.DisplayName,
		offerA = session.offerA,
		offerB = session.offerB,
	})
end

-- ── Remote: TradeInitiate (drag-to-player) ──────────────────────────────

tradeInitiateRemote.OnServerEvent:Connect(function(requester: Player, targetUserId: any, itemId: any, qty: any)
	if typeof(targetUserId) ~= "number" then return end

	local targetPlayer = nil
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.UserId == targetUserId then
			targetPlayer = plr
			break
		end
	end
	if not targetPlayer or targetPlayer == requester then return end

	-- Validate neither is already trading
	if activeTrades[requester] or activeTrades[targetPlayer] then return end

	-- Validate no duplicate pending request
	if pendingRequests[targetPlayer] and pendingRequests[targetPlayer].from == requester then return end

	-- Range check
	if distanceBetween(requester, targetPlayer) > INTERACT_RANGE then return end

	-- Validate the offered item (empty initiation allowed from inspect screen)
	local id = sanitizeItemId(itemId)
	local amount = math.floor(tonumber(qty) or 0)
	if id ~= "" and amount >= 1 then
		local def = ItemRegistry.get(id)
		if not def then return end
		local inInventory = invGetQty:Invoke(requester, id)
		if inInventory < amount then return end
	else
		-- Empty initiation — no initial offer
		id = ""
		amount = 0
	end

	-- Store pending request with initial offer
	pendingRequests[targetPlayer] = {
		from = requester,
		time = os.time(),
		initialItemId = id,
		initialQty = amount,
	}

	-- Notify target player with requester info + offered item preview
	tradeRequestRemote:FireClient(targetPlayer, requester.Name, requester.UserId, id, amount)

	-- Auto-expire after timeout
	task.delay(REQUEST_TIMEOUT, function()
		local pending = pendingRequests[targetPlayer]
		if pending and pending.from == requester then
			pendingRequests[targetPlayer] = nil
		end
	end)
end)

-- ── Remote: TradeResponse (accept/decline) ──────────────────────────────

tradeResponseRemote.OnServerEvent:Connect(function(plr: Player, accepted: any)
	local pending = pendingRequests[plr]
	if not pending then return end
	pendingRequests[plr] = nil

	if typeof(accepted) ~= "boolean" then return end

	local requester = pending.from
	if not requester or not requester.Parent then return end

	if not accepted then return end

	-- Validate neither is already trading
	if activeTrades[plr] or activeTrades[requester] then return end

	-- Range check
	if distanceBetween(plr, requester) > INTERACT_RANGE then return end

	-- Re-validate the initial offer item (requester may have dropped it)
	local hasQty = invGetQty:Invoke(requester, pending.initialItemId)
	local offerQty = math.min(pending.initialQty, hasQty)
	local initialOffer = nil
	if offerQty > 0 then
		initialOffer = { itemId = pending.initialItemId, qty = offerQty }
	end

	createSession(requester, plr, initialOffer)
end)

-- ── Remote: TradeUpdateOffer ────────────────────────────────────────────

tradeUpdateOfferRemote.OnServerEvent:Connect(function(plr: Player, itemId: any, qty: any, action: any)
	local session = getSession(plr)
	if not session then return end

	local id = sanitizeItemId(itemId)
	if id == "" then return end
	local def = ItemRegistry.get(id)
	if not def then return end

	local amount = math.floor(tonumber(qty) or 0)
	if amount < 1 then return end

	if typeof(action) ~= "string" then return end

	local offer = getOwnOffer(session, plr)

	if action == "add" then
		-- Check player actually has enough
		local inInventory = invGetQty:Invoke(plr, id)
		-- Sum already offered
		local alreadyOffered = 0
		for _, e in ipairs(offer) do
			if e.itemId == id then
				alreadyOffered += e.qty
			end
		end
		if alreadyOffered + amount > inInventory then return end

		-- Merge into existing offer entry or add new
		local found = false
		for _, e in ipairs(offer) do
			if e.itemId == id then
				e.qty += amount
				found = true
				break
			end
		end
		if not found then
			table.insert(offer, { itemId = id, qty = amount })
		end
	elseif action == "remove" then
		for i, e in ipairs(offer) do
			if e.itemId == id then
				e.qty -= amount
				if e.qty <= 0 then
					table.remove(offer, i)
				end
				break
			end
		end
	else
		return
	end

	-- Reset both confirmations when offer changes
	session.confirmedA = false
	session.confirmedB = false

	broadcastState(session)
end)

-- ── Remote: TradeConfirm ────────────────────────────────────────────────

tradeConfirmRemote.OnServerEvent:Connect(function(plr: Player)
	local session = getSession(plr)
	if not session then return end

	if isPlayerA(session, plr) then
		session.confirmedA = true
	else
		session.confirmedB = true
	end

	if session.confirmedA and session.confirmedB then
		executeTrade(session)
	else
		broadcastState(session)
	end
end)

-- ── Remote: TradeCancel ─────────────────────────────────────────────────

tradeCancelRemote.OnServerEvent:Connect(function(plr: Player)
	local session = getSession(plr)
	if not session then return end
	cancelTrade(session)
end)

-- ── Cleanup on disconnect ───────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(plr: Player)
	-- Cancel active trade
	local session = activeTrades[plr]
	if session then
		cancelTrade(session)
	end

	-- Clear any pending request TO this player
	pendingRequests[plr] = nil

	-- Clear any pending requests FROM this player to others
	for target, pending in pairs(pendingRequests) do
		if pending.from == plr then
			pendingRequests[target] = nil
		end
	end
end)

-- ── Range enforcement — auto-cancel if too far apart ────────────────────

local RANGE_CHECK_INTERVAL = 1
local rangeCheckTimer = 0

RunService.Heartbeat:Connect(function(dt)
	rangeCheckTimer += dt
	if rangeCheckTimer < RANGE_CHECK_INTERVAL then return end
	rangeCheckTimer = 0

	-- Collect unique sessions (each session is keyed by both players)
	local checked: { [TradeSession]: boolean } = {}
	for _, session in pairs(activeTrades) do
		if not checked[session] then
			checked[session] = true
			if distanceBetween(session.playerA, session.playerB) > INTERACT_RANGE then
				cancelTrade(session)
			end
		end
	end
end)
