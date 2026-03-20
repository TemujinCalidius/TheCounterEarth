-- EventBridgeWorker.server.luau
-- Initializes EventBridge, runs the periodic flush loop, and flushes on shutdown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameplayConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameplayConfig"))

local EventBridge = require(script.Parent:WaitForChild("EventBridge"))
EventBridge.init()

-- Flush remaining events on server shutdown
game:BindToClose(function()
	EventBridge.flush()
end)

-- Periodic flush loop
local interval = (GameplayConfig.EventBridge and GameplayConfig.EventBridge.FlushIntervalSeconds) or 5
while true do
	task.wait(interval)
	EventBridge.flush()
end
