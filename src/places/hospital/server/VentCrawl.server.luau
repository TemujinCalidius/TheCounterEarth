-- VentCrawl.server.luau (Hospital)
-- Scripted crawl-through for air vents. R15 avatars are too tall to walk
-- through a 3-stud vent shaft, so instead the player triggers a prompt and
-- the server tweens their character through the shaft in a prone pose while
-- a swim animation plays (reads as crawling when the body is horizontal).
--
-- Studio setup — any Model/Folder with attribute `IsVentCrawl = true`:
--   VentEntry   (BasePart marker, invisible, floor level at side A)
--   VentExit    (BasePart marker, invisible, floor level at side B)
--   CrawlPoint1..N (BasePart markers, invisible, ordered path inside the
--                   shaft from A to B; at crawl height, i.e. ~1.5 studs up)
-- Both ends get a "Crawl Through" prompt; the path runs either direction.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CRAWL_SPEED = 6           -- studs per second through the shaft
local CRAWL_ANIM_ID = "rbxassetid://507784897"  -- default R15 swim (prone crawl look)
local PROMPT_DISTANCE = 8

local crawling: { [Player]: boolean } = {}

local function getWaypoints(vent: Instance, fromEntry: boolean): { BasePart }
	local entry = vent:FindFirstChild("VentEntry")
	local exit = vent:FindFirstChild("VentExit")
	if not (entry and entry:IsA("BasePart") and exit and exit:IsA("BasePart")) then
		return {}
	end

	local mids: { BasePart } = {}
	local i = 1
	while true do
		local p = vent:FindFirstChild("CrawlPoint" .. i)
		if p and p:IsA("BasePart") then
			table.insert(mids, p)
			i += 1
		else
			break
		end
	end

	local points: { BasePart } = { entry }
	for _, m in mids do table.insert(points, m) end
	table.insert(points, exit)

	if not fromEntry then
		local reversed: { BasePart } = {}
		for j = #points, 1, -1 do
			table.insert(reversed, points[j])
		end
		points = reversed
	end
	return points
end

local function crawlThrough(player: Player, vent: Instance, fromEntry: boolean)
	if crawling[player] then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and humanoid.Health > 0 and hrp and hrp:IsA("BasePart")) then
		return
	end

	local points = getWaypoints(vent, fromEntry)
	if #points < 2 then
		warn("[VentCrawl] Vent has no usable waypoint path: " .. vent:GetFullName())
		return
	end

	crawling[player] = true

	-- Prone crawl animation (swim track reads as a crawl when horizontal)
	local track: AnimationTrack? = nil
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local anim = Instance.new("Animation")
		anim.AnimationId = CRAWL_ANIM_ID
		local ok, result = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and result then
			track = result
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			track:Play(0.1)
		end
	end

	hrp.Anchored = true

	-- Move through each segment lying flat, facing the direction of travel
	for i = 1, #points - 1 do
		local from = points[i].Position
		local to = points[i + 1].Position
		local distance = (to - from).Magnitude
		if distance > 0.01 then
			local upright = CFrame.lookAt(from, to)
			-- Pitch forward 90° so the body lies flat along the travel direction
			local prone = upright * CFrame.Angles(-math.pi / 2, 0, 0)
			hrp.CFrame = CFrame.new(from) * prone.Rotation
			local goal = CFrame.new(to) * prone.Rotation
			local tween = TweenService:Create(
				hrp,
				TweenInfo.new(distance / CRAWL_SPEED, Enum.EasingStyle.Linear),
				{ CFrame = goal }
			)
			tween:Play()
			tween.Completed:Wait()
		end
	end

	if track then track:Stop(0.1) end

	-- Stand the character up at the far end
	local endMarker = points[#points]
	local standPos = endMarker.Position + Vector3.new(0, 3, 0)
	local lookDir = (endMarker.Position - points[#points - 1].Position) * Vector3.new(1, 0, 1)
	if lookDir.Magnitude < 0.01 then lookDir = Vector3.new(0, 0, -1) end
	hrp.CFrame = CFrame.lookAt(standPos, standPos + lookDir.Unit)
	hrp.Anchored = false
	hrp.AssemblyLinearVelocity = Vector3.zero

	crawling[player] = nil
end

local function setupVent(vent: Instance)
	if vent:GetAttribute("IsVentCrawl") ~= true then return end
	if vent:GetAttribute("_VentWired") then return end
	vent:SetAttribute("_VentWired", true)

	for _, markerName in { "VentEntry", "VentExit" } do
		local marker = vent:FindFirstChild(markerName)
		if marker and marker:IsA("BasePart") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "VentPrompt"
			prompt.ActionText = "Crawl Through"
			prompt.ObjectText = "Air Vent"
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.HoldDuration = 0.3
			prompt.MaxActivationDistance = PROMPT_DISTANCE
			prompt.RequiresLineOfSight = false
			prompt.Parent = marker

			local fromEntry = markerName == "VentEntry"
			prompt.Triggered:Connect(function(player)
				crawlThrough(player, vent, fromEntry)
			end)
		end
	end
end

for _, inst in ipairs(Workspace:GetDescendants()) do
	setupVent(inst)
end

Workspace.DescendantAdded:Connect(function(inst)
	-- Defer so children (markers) exist before wiring
	task.defer(setupVent, inst)
end)

Players.PlayerRemoving:Connect(function(player)
	crawling[player] = nil
end)
