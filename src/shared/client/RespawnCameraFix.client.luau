-- RespawnCameraFix.client.luau
-- Re-points the camera at the new character after respawn.
--
-- Characters are spawned by assigning player.Character directly
-- (CharacterAppearanceService), and Roblox's camera module misses the
-- CameraSubject swap on that path — after death the camera stays on the
-- destroyed character, which looks like "respawn is broken".

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraSubject = humanoid
		camera.CameraType = Enum.CameraType.Custom
	end
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end
