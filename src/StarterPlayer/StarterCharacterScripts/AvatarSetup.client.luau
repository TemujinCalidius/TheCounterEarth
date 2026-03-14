-- AvatarSetup.client.luau
-- Adjusts HipHeight, suppresses premature freefall, and tracks the RightHand
-- Part to the hand bone for single-mesh custom avatars.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))
local AvatarCfg = Config.Avatar

-- Find a Bone by name inside a MeshPart's descendant hierarchy.
local function findBone(meshPart: MeshPart, boneName: string): Bone?
	for _, desc in meshPart:GetDescendants() do
		if desc:IsA("Bone") and desc.Name == boneName then
			return desc
		end
	end
	return nil
end

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

	----------------------------------------------------------------
	-- RightHand bone tracking (client-side, zero visual lag)
	-- The server creates the Motor6D (AvatarRigService), we update its
	-- C0 each frame before rendering so the tool follows the hand bone.
	----------------------------------------------------------------
	local meshPart = character:FindFirstChild(AvatarCfg.MeshPartName)
	if not rootPart or not meshPart or not meshPart:IsA("MeshPart") then return end

	local bone = findBone(meshPart, AvatarCfg.HandBoneName)
	if not bone then return end

	local rightHand = character:FindFirstChild("RightHand")
	if not rightHand or not rightHand:IsA("BasePart") then return end

	-- Wait for the server-created Motor6D
	local motor = rightHand:WaitForChild("RightHandJoint", 5)
	if not motor then return end

	-- Update before each render frame — no visual lag
	local conn: RBXScriptConnection
	conn = RunService.PreRender:Connect(function()
		if not rootPart.Parent or not bone.Parent or not rightHand.Parent then
			conn:Disconnect()
			return
		end
		motor.C0 = rootPart.CFrame:ToObjectSpace(bone.TransformedWorldCFrame)
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
