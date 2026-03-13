-- AvatarSetup.client.luau
-- Adjusts HipHeight for custom avatar mesh so feet sit on the ground correctly.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local HIP_HEIGHT = 2.55

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.HipHeight = HIP_HEIGHT
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
