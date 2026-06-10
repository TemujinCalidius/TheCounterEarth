-- CharacterAppearanceService.server.luau
-- Server-side character spawning with gender + skin tone.
-- Disables default character auto-loading and provides:
--   - SpawnPlayerAvatar (BindableFunction): clone template, apply skin, assign to player
--   - PromptCharacterCreator (BindableEvent): fire ShowCharacterCreator remote to client
--   - AppearanceChosen (RemoteEvent): client confirms choice, server spawns and saves
--
-- Templates live at ServerStorage/AvatarTemplates/<Male|Female>.
-- Player attributes AppearanceGender and AppearanceSkinTone hold current state
-- and are persisted by PlayerStateService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local AppearanceConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AppearanceConfig"))

Players.CharacterAutoLoads = false

-- ── Remotes ──────────────────────────────────────────────────────
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local function getOrCreateRemoteEvent(name: string): RemoteEvent
	local r = remotesFolder:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = remotesFolder
	end
	return r
end

local showCreatorRemote = getOrCreateRemoteEvent("ShowCharacterCreator")
local appearanceChosenRemote = getOrCreateRemoteEvent("AppearanceChosen")

-- ── Bindables ────────────────────────────────────────────────────
local bindablesFolder = ServerStorage:FindFirstChild("ServerBindables")
if not bindablesFolder then
	bindablesFolder = Instance.new("Folder")
	bindablesFolder.Name = "ServerBindables"
	bindablesFolder.Parent = ServerStorage
end

local function getOrCreateBindableFunction(name: string): BindableFunction
	local b = bindablesFolder:FindFirstChild(name)
	if not b then
		b = Instance.new("BindableFunction")
		b.Name = name
		b.Parent = bindablesFolder
	end
	return b
end

local function getOrCreateBindableEvent(name: string): BindableEvent
	local b = bindablesFolder:FindFirstChild(name)
	if not b then
		b = Instance.new("BindableEvent")
		b.Name = name
		b.Parent = bindablesFolder
	end
	return b
end

local spawnAvatarBindable = getOrCreateBindableFunction("SpawnPlayerAvatar")
local promptCreatorBindable = getOrCreateBindableEvent("PromptCharacterCreator")

-- ── Skin tone application ────────────────────────────────────────
local BODY_PART_NAMES = {
	"Head",
	"UpperTorso", "LowerTorso",
	"LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local function applySkinTone(character: Model, skinToneId: string)
	local skinTone = AppearanceConfig.SkinTones[skinToneId]
	if not skinTone then return end
	local color: Color3 = skinTone.color

	local bc = character:FindFirstChildWhichIsA("BodyColors")
	if bc then
		bc.HeadColor3 = color
		bc.TorsoColor3 = color
		bc.LeftArmColor3 = color
		bc.RightArmColor3 = color
		bc.LeftLegColor3 = color
		bc.RightLegColor3 = color
	end

	for _, partName in BODY_PART_NAMES do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Color = color
		end
	end
end

-- ── Starter accessories ─────────────────────────────────────────
-- Everything inside ServerStorage.StarterAccessories is cloned and attached
-- to every freshly-spawned character (hospital gown, slippers, etc.).
-- Humanoid:AddAccessory uses the Accessory's Attachment to weld it to the
-- matching body-part Attachment.
local function attachStarterAccessories(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local folder = ServerStorage:FindFirstChild("StarterAccessories")
	if not folder then return end

	for _, accessory in folder:GetChildren() do
		if accessory:IsA("Accessory") then
			humanoid:AddAccessory(accessory:Clone())
		end
	end
end

-- ── StarterCharacterScripts injection ────────────────────────────
-- Roblox auto-clones StarterCharacterScripts into characters spawned via
-- Player:LoadCharacter(), but NOT when we assign player.Character directly.
-- We do it manually so any custom character scripts run.
local function injectStarterCharacterScripts(character: Model)
	local scs = StarterPlayer:FindFirstChild("StarterCharacterScripts")
	if not scs then return end

	for _, child in scs:GetChildren() do
		local existing = character:FindFirstChild(child.Name)
		if existing then
			existing:Destroy()
		end
		local clone = child:Clone()
		clone.Parent = character
	end
end

-- ── Default R15 movement animations (driven server-side) ─────────
-- Driving from the server bypasses LocalScript timing/injection issues —
-- AnimationTrack:Play() replicates to every client automatically.
local DEFAULT_ANIMATIONS = {
	idle     = "rbxassetid://507766388",
	walk     = "rbxassetid://913402848",
	run      = "rbxassetid://913376220",
	jump     = "rbxassetid://507765000",
	fall     = "rbxassetid://507767968",
	climb    = "rbxassetid://507765644",
	sit      = "rbxassetid://2506281703",
	swim     = "rbxassetid://507784897",
	swimIdle = "rbxassetid://481825862",
}

local LOOPED_ANIMS: { [string]: boolean } = {
	idle = true, walk = true, run = true, climb = true,
	sit = true, swim = true, swimIdle = true,
}

local function setupCharacterAnimations(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local tracks: { [string]: AnimationTrack } = {}
	for name, id in DEFAULT_ANIMATIONS do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Movement
			track.Looped = LOOPED_ANIMS[name] == true
			tracks[name] = track
		end
	end

	local currentName: string? = nil
	local function play(name: string, fade: number?)
		if name == currentName then return end
		local track = tracks[name]
		if not track then return end
		local current = currentName and tracks[currentName] or nil
		if current and current.IsPlaying then
			current:Stop(fade or 0.15)
		end
		track:Play(fade or 0.15)
		currentName = name
	end

	local function update()
		if humanoid.Parent == nil or humanoid.Health <= 0 then return end
		local state = humanoid:GetState()
		local moving = humanoid.MoveDirection.Magnitude > 0.05

		if state == Enum.HumanoidStateType.Swimming then
			play(moving and "swim" or "swimIdle")
		elseif state == Enum.HumanoidStateType.Climbing then
			play("climb")
		elseif state == Enum.HumanoidStateType.Seated then
			play("sit")
		elseif state == Enum.HumanoidStateType.Jumping then
			play("jump", 0.1)
		elseif state == Enum.HumanoidStateType.Freefall then
			play("fall", 0.1)
		elseif moving then
			if humanoid.WalkSpeed > 18 then
				play("run")
			else
				play("walk")
			end
		else
			play("idle")
		end
	end

	humanoid.StateChanged:Connect(update)
	humanoid.Running:Connect(update)

	-- Poll at 10Hz to catch MoveDirection / WalkSpeed changes that don't
	-- fire a Roblox event (sprint toggle while already moving).
	task.spawn(function()
		while humanoid.Parent ~= nil do
			update()
			task.wait(0.1)
		end
	end)

	update()
end

-- ── Spawn helper ─────────────────────────────────────────────────
-- On death respawns, a SpawnLocation named "RespawnLocation" wins if one
-- exists (e.g. the Nurse's Station in The Ward). Initial joins use the
-- first other SpawnLocation found.
local function findSpawnLocation(isRespawn: boolean?): SpawnLocation?
	local firstSpawn: SpawnLocation? = nil
	local respawnSpawn: SpawnLocation? = nil
	for _, instance in Workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") then
			if instance.Name == "RespawnLocation" then
				respawnSpawn = respawnSpawn or instance
			else
				firstSpawn = firstSpawn or instance
			end
		end
	end
	if isRespawn and respawnSpawn then
		return respawnSpawn
	end
	return firstSpawn or respawnSpawn
end

local RESPAWN_DELAY_SECONDS = 4

local spawnAvatar  -- forward declaration (hookRespawn calls it)

-- Auto-respawn: with CharacterAutoLoads off, nothing else brings a player
-- back after death.
local function hookRespawn(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid.Died:Once(function()
		task.delay(RESPAWN_DELAY_SECONDS, function()
			if player.Parent ~= Players then return end
			if player.Character ~= character then return end -- already respawned elsewhere
			spawnAvatar(
				player,
				player:GetAttribute("AppearanceGender"),
				player:GetAttribute("AppearanceSkinTone"),
				true
			)
		end)
	end)
end

function spawnAvatar(player: Player, gender: string?, skinTone: string?, isRespawn: boolean?): Model?
	gender = AppearanceConfig.isValidGender(gender) and gender or AppearanceConfig.Defaults.gender
	skinTone = AppearanceConfig.isValidSkinTone(skinTone) and skinTone or AppearanceConfig.Defaults.skin_tone

	local templatesFolder = ServerStorage:FindFirstChild("AvatarTemplates")
	if not templatesFolder then
		warn("[CharacterAppearance] Missing ServerStorage.AvatarTemplates folder")
		return nil
	end

	local genderConfig = AppearanceConfig.Genders[gender]
	local template = templatesFolder:FindFirstChild(genderConfig.templateName)
	if not template then
		warn("[CharacterAppearance] Missing template: AvatarTemplates." .. genderConfig.templateName)
		return nil
	end

	if player.Character then
		player.Character:Destroy()
	end

	local character = template:Clone()
	character.Name = player.Name

	applySkinTone(character, skinTone)

	-- Position at SpawnLocation if found
	local spawn = findSpawnLocation(isRespawn)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		if spawn then
			hrp.CFrame = spawn.CFrame + Vector3.new(0, 5, 0)
		else
			hrp.CFrame = CFrame.new(0, 10, 0)
		end
	end

	-- Persist choice via player attributes
	player:SetAttribute("AppearanceGender", gender)
	player:SetAttribute("AppearanceSkinTone", skinTone)

	-- Inject any StarterCharacterScripts (Roblox doesn't do this
	-- automatically when we set player.Character instead of LoadCharacter)
	injectStarterCharacterScripts(character)

	character.Parent = Workspace
	player.Character = character

	-- Attach default starter clothing/accessories (hospital gown, slippers, etc.)
	attachStarterAccessories(character)

	-- Drive default R15 movement animations from the server. Replicates
	-- to all clients via the Animator, so no LocalScript needed.
	task.spawn(setupCharacterAnimations, character)

	hookRespawn(player, character)

	return character
end

spawnAvatarBindable.OnInvoke = spawnAvatar

-- ── Client choice handler ────────────────────────────────────────
appearanceChosenRemote.OnServerEvent:Connect(function(player: Player, gender: any, skinTone: any)
	if type(gender) ~= "string" or type(skinTone) ~= "string" then return end
	if not AppearanceConfig.isValidGender(gender) then return end
	if not AppearanceConfig.isValidSkinTone(skinTone) then return end

	spawnAvatar(player, gender, skinTone)
end)

-- ── Prompt creator UI ────────────────────────────────────────────
promptCreatorBindable.Event:Connect(function(player: Player)
	if player and player.Parent == Players then
		showCreatorRemote:FireClient(player)
	end
end)
