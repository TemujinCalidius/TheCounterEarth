-- AvatarRigService.server.luau
-- Creates a Motor6D between HumanoidRootPart and the Studio-placed transparent
-- RightHand Part so that Roblox's built-in tool equip system works with
-- single-mesh custom avatars. Visual bone tracking is handled client-side
-- (AvatarSetup.client.luau) for zero-lag rendering.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local AvatarCfg = Config.Avatar

local function setupRightHand(character: Model)
	local rootPart = character:WaitForChild("HumanoidRootPart", 5)
	if not rootPart then return end

	-- Look for the Studio-placed transparent RightHand Part
	local rightHand = character:FindFirstChild("RightHand")
	if not rightHand or not rightHand:IsA("BasePart") then return end

	-- Only set up for custom avatars (standard R15 rigs already have Motor6Ds)
	local meshPart = character:FindFirstChild(AvatarCfg.MeshPartName)
	if not meshPart or not meshPart:IsA("MeshPart") then return end

	-- Connect RightHand to HumanoidRootPart via Motor6D so EquipTool works
	local motor = Instance.new("Motor6D")
	motor.Name = "RightHandJoint"
	motor.Part0 = rootPart
	motor.Part1 = rightHand
	motor.Parent = rightHand
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Run synchronously (not deferred) so RightHand is ready before
		-- ToolInventoryService's task.defer'd EquipTool calls.
		setupRightHand(character)
	end)

	if player.Character then
		setupRightHand(player.Character)
	end
end)

-- Handle players already in game (Studio quick-start)
for _, player in Players:GetPlayers() do
	if player.Character then
		setupRightHand(player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		setupRightHand(character)
	end)
end
