-- BoneTracker.client.luau
-- Tracks the RightHand bone for ALL characters (local + remote) so that
-- equipped tools follow the hand correctly on every client's screen.
-- Without this, remote players see tools stuck at the torso/shoulder because
-- AvatarSetup.client.luau (StarterCharacterScripts) only runs for the local
-- player's own character.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local AvatarCfg = Config.Avatar

local trackedCharacters: { [Model]: RBXScriptConnection } = {}

local function findBone(meshPart: MeshPart, boneName: string): Bone?
	for _, desc in meshPart:GetDescendants() do
		if desc:IsA("Bone") and desc.Name == boneName then
			return desc
		end
	end
	return nil
end

local function trackCharacter(character: Model)
	-- Clean up any existing tracking for this character
	if trackedCharacters[character] then
		trackedCharacters[character]:Disconnect()
		trackedCharacters[character] = nil
	end

	local rootPart = character:WaitForChild("HumanoidRootPart", 5)
	if not rootPart then return end

	local meshPart = character:FindFirstChild(AvatarCfg.MeshPartName)
	if not meshPart or not meshPart:IsA("MeshPart") then return end

	local bone = findBone(meshPart, AvatarCfg.HandBoneName)
	if not bone then return end

	local rightHand = character:FindFirstChild("RightHand")
	if not rightHand or not rightHand:IsA("BasePart") then return end

	local motor = rightHand:WaitForChild("RightHandJoint", 5)
	if not motor then return end

	local conn: RBXScriptConnection
	conn = RunService.PreRender:Connect(function()
		if not rootPart.Parent or not bone.Parent or not rightHand.Parent then
			conn:Disconnect()
			trackedCharacters[character] = nil
			return
		end
		motor.C0 = rootPart.CFrame:ToObjectSpace(bone.TransformedWorldCFrame)
	end)

	trackedCharacters[character] = conn
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(trackCharacter, character)
	end)

	if player.Character then
		task.spawn(trackCharacter, player.Character)
	end
end

-- Track all current and future players
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- Cleanup on player leave
Players.PlayerRemoving:Connect(function(player)
	if player.Character and trackedCharacters[player.Character] then
		trackedCharacters[player.Character]:Disconnect()
		trackedCharacters[player.Character] = nil
	end
end)
