-- AvatarSetup.client.luau
-- Adjusts HipHeight and suppresses premature freefall for single-mesh custom
-- avatars. RightHand bone tracking is in BoneTracker.client.luau.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local AvatarCfg = Config.Avatar

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart", 5)
	humanoid.HipHeight = AvatarCfg.HipHeight

	----------------------------------------------------------------
	-- Jump freefall suppression
	-- Single-mesh avatars trigger FreeFall almost instantly after a jump.
	-- Suppress freefall during ascent so the jump animation plays.
	-- Re-enable once the character starts descending (velocity.Y < 0)
	-- so the proper Freefall → Landed transition happens naturally.
	----------------------------------------------------------------
	local jumpConn: RBXScriptConnection? = nil

	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)

			-- Clean up any previous jump watcher
			if jumpConn then jumpConn:Disconnect() end

			-- Watch each frame: once descending, re-enable freefall
			jumpConn = RunService.Heartbeat:Connect(function()
				if not humanoid or not humanoid.Parent or not rootPart or not rootPart.Parent then
					if jumpConn then jumpConn:Disconnect(); jumpConn = nil end
					return
				end
				if rootPart.AssemblyLinearVelocity.Y < 0 then
					humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
					if jumpConn then jumpConn:Disconnect(); jumpConn = nil end
				end
			end)
		elseif newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running then
			-- Safety: always re-enable on landing
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
			if jumpConn then jumpConn:Disconnect(); jumpConn = nil end
		end
	end)

	-- NOTE: RightHand bone tracking moved to BoneTracker.client.luau
	-- (StarterPlayerScripts) so it runs for ALL characters, not just local.
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
