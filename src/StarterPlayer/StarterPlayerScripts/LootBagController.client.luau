-- LootBagController.client.luau
-- Renders countdown timers on all loot bags (BillboardGui above bag).
-- For death bags owned by this player, also renders a glowing beacon beam.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local deathBagBeaconRemote = remotesFolder:WaitForChild("DeathBagBeacon")

-- ── State ─────────────────────────────────────────────────────────────────

type TrackedBag = {
	bag: Model,
	billboard: BillboardGui,
	label: TextLabel,
	beacon: Model?,         -- beacon container (only for death bags owned by this player)
}

local trackedBags: { TrackedBag } = {}

-- ── Beacon config ─────────────────────────────────────────────────────────

local BEACON_COLOR  = Color3.fromRGB(255, 220, 80)   -- golden glow
local BEACON_HEIGHT = 200                              -- studs tall
local BEACON_WIDTH  = 1.5                              -- wide enough to see from afar

-- ── Format time as M:SS ──────────────────────────────────────────────────

local function formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local mins = math.floor(s / 60)
	local secs = s % 60
	return string.format("%d:%02d", mins, secs)
end

-- ── Wait for a bag's Handle to be available ──────────────────────────────

local function waitForHandle(bag: Model, timeout: number): BasePart?
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local handle = bag.PrimaryPart or bag:FindFirstChildWhichIsA("BasePart")
		if handle then return handle end
		if not bag.Parent then return nil end
		task.wait(0.1)
	end
	return bag.PrimaryPart or bag:FindFirstChildWhichIsA("BasePart")
end

-- ── Create countdown BillboardGui on a loot bag ──────────────────────────

local function createCountdownBillboard(_bag: Model, handle: BasePart): (BillboardGui, TextLabel)
	local bb = Instance.new("BillboardGui")
	bb.Name              = "LootBagTimer"
	bb.Adornee           = handle
	bb.Size              = UDim2.new(0, 90, 0, 30)
	bb.StudsOffset       = Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop       = true
	bb.MaxDistance        = 100
	bb.Parent            = player.PlayerGui

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3      = Color3.fromRGB(30, 30, 30)
	label.TextColor3            = Color3.fromRGB(255, 255, 255)
	label.Font                  = Enum.Font.GothamBold
	label.TextSize              = 16
	label.Text                  = "5:00"
	label.Parent                = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent       = label

	return bb, label
end

-- ── Create beacon beam (owner-only, for death bags) ──────────────────────

local function createBeacon(handle: BasePart): Model
	local container = Instance.new("Model")
	container.Name = "DeathBeacon"

	-- Main beam pillar
	local beam = Instance.new("Part")
	beam.Name            = "Beam"
	beam.Size            = Vector3.new(BEACON_WIDTH, BEACON_HEIGHT, BEACON_WIDTH)
	beam.CFrame          = CFrame.new(handle.Position + Vector3.new(0, BEACON_HEIGHT / 2, 0))
	beam.Anchored        = true
	beam.CanCollide      = false
	beam.CanTouch        = false
	beam.CanQuery        = false
	beam.CastShadow      = false
	beam.Material        = Enum.Material.Neon
	beam.Color           = BEACON_COLOR
	beam.Transparency    = 0.3
	beam.Parent          = container

	-- Ground glow ring
	local ring = Instance.new("Part")
	ring.Name            = "GlowRing"
	ring.Shape           = Enum.PartType.Cylinder
	ring.Size            = Vector3.new(0.3, 6, 6)
	ring.CFrame          = CFrame.new(handle.Position + Vector3.new(0, 0.2, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored        = true
	ring.CanCollide      = false
	ring.CanTouch        = false
	ring.CanQuery        = false
	ring.CastShadow      = false
	ring.Material        = Enum.Material.Neon
	ring.Color           = BEACON_COLOR
	ring.Transparency    = 0.4
	ring.Parent          = container

	-- Point light at bag position for local glow
	local light = Instance.new("PointLight")
	light.Color     = BEACON_COLOR
	light.Brightness = 3
	light.Range      = 20
	light.Parent     = handle

	container.Parent = Workspace
	return container
end

-- ── Track a loot bag ─────────────────────────────────────────────────────

local function trackBag(bag: Model, isDeathBag: boolean)
	-- Avoid duplicates
	for _, tracked in ipairs(trackedBags) do
		if tracked.bag == bag then return end
	end

	-- Wait for the handle to replicate
	local handle = waitForHandle(bag, 3)
	if not handle or not bag.Parent then return end

	local bb, label = createCountdownBillboard(bag, handle)

	local beacon: Model? = nil
	if isDeathBag then
		beacon = createBeacon(handle)
	end

	local entry: TrackedBag = {
		bag = bag,
		billboard = bb,
		label = label,
		beacon = beacon,
	}
	table.insert(trackedBags, entry)

	-- Cleanup when bag is destroyed
	bag.AncestryChanged:Connect(function()
		if not bag.Parent then
			if bb.Parent then bb:Destroy() end
			if beacon and beacon.Parent then beacon:Destroy() end
			for i, t in ipairs(trackedBags) do
				if t.bag == bag then
					table.remove(trackedBags, i)
					break
				end
			end
		end
	end)
end

-- ── Death bag beacon from server ─────────────────────────────────────────

deathBagBeaconRemote.OnClientEvent:Connect(function(bag: Model, _lifetime: number)
	if not bag then return end
	-- Bag may not have replicated yet; wait briefly
	task.defer(function()
		if bag.Parent then
			trackBag(bag, true)
		else
			-- Wait for it to appear in workspace
			local conn
			conn = bag.AncestryChanged:Connect(function()
				if bag.Parent then
					conn:Disconnect()
					trackBag(bag, true)
				end
			end)
			-- Timeout cleanup
			task.delay(5, function()
				if conn.Connected then conn:Disconnect() end
			end)
		end
	end)
end)

-- ── Scan workspace for existing loot bags (handles late join) ────────────

local function scanForBags()
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("_isLootBag") then
			local isDeathBag = obj:GetAttribute("_isDeathBag") == true
				and obj:GetAttribute("_OwnerUserId") == player.UserId
			task.defer(function()
				trackBag(obj, isDeathBag)
			end)
		end
	end
end

-- Watch for new bags added to workspace
Workspace.ChildAdded:Connect(function(child)
	-- Defer so attributes have time to replicate
	task.defer(function()
		if not child.Parent then return end
		if not (child:IsA("Model") and child:GetAttribute("_isLootBag")) then return end

		local isOwnerDeathBag = child:GetAttribute("_isDeathBag") == true
			and child:GetAttribute("_OwnerUserId") == player.UserId

		if child:GetAttribute("_isDeathBag") and not isOwnerDeathBag then
			-- Other player's death bag: countdown only, no beacon
			trackBag(child, false)
		elseif not child:GetAttribute("_isDeathBag") then
			-- Regular drop bag: countdown only
			trackBag(child, false)
		end
		-- Owner's death bag is handled by DeathBagBeacon remote
	end)
end)

scanForBags()

-- ── Update countdown timers ──────────────────────────────────────────────

local lastUpdate = 0
RunService.Heartbeat:Connect(function()
	-- Only update once per second (no need for 60fps text updates)
	local now = os.clock()
	if now - lastUpdate < 1 then return end
	lastUpdate = now

	local currentTime = os.time()
	for _, tracked in ipairs(trackedBags) do
		local bag = tracked.bag
		if not bag.Parent then continue end

		local spawnTime = bag:GetAttribute("_SpawnTime")
		local lifetime  = bag:GetAttribute("_Lifetime")
		if not spawnTime or not lifetime then continue end

		local remaining = lifetime - (currentTime - spawnTime)
		tracked.label.Text = formatTime(remaining)

		-- Color: white → yellow → red as time runs low
		if remaining <= 30 then
			tracked.label.TextColor3 = Color3.fromRGB(255, 80, 80)
		elseif remaining <= 60 then
			tracked.label.TextColor3 = Color3.fromRGB(255, 200, 80)
		else
			tracked.label.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end
end)
