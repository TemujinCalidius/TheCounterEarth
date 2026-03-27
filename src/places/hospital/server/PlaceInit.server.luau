-- PlaceInit.server.luau (Hospital)
-- Fires ScatterReady so LoadingScreen dismisses promptly in places without ScatterSpawnService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for PlayerStateService to create the Remotes folder
local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
if remotes then
	local ready = remotes:FindFirstChild("ScatterReady")
	if ready then
		-- Small delay so clients have time to connect their listener
		task.wait(2)
		ready:FireAllClients()
	end
end
