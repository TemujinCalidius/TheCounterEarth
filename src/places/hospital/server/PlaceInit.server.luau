-- PlaceInit.server.luau (Hospital)
-- Creates + fires ScatterReady so LoadingScreen dismisses promptly.
-- (Sandbox gets this remote from ScatterSpawnService; hospital has no scatter,
-- so this script owns the remote here.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for PlayerStateService to create the Remotes folder
local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
if not remotes then return end

local ready = remotes:FindFirstChild("ScatterReady")
if not ready then
	ready = Instance.new("RemoteEvent")
	ready.Name = "ScatterReady"
	ready.Parent = remotes
end

-- Fire once for anyone already connected...
task.wait(2)
ready:FireAllClients()

-- ...and once per player a moment after they join, so a client that wasn't
-- listening yet when the broadcast went out still gets the signal.
local function signalPlayer(player: Player)
	task.delay(3, function()
		if player.Parent == Players then
			ready:FireClient(player)
		end
	end)
end

Players.PlayerAdded:Connect(signalPlayer)
for _, player in Players:GetPlayers() do
	signalPlayer(player)
end
