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

-- ── Spawn helper ─────────────────────────────────────────────────
local function findSpawnLocation(): SpawnLocation?
	for _, instance in Workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") then
			return instance
		end
	end
	return nil
end

local function spawnAvatar(player: Player, gender: string?, skinTone: string?): Model?
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
	local spawn = findSpawnLocation()
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

	character.Parent = Workspace
	player.Character = character

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
