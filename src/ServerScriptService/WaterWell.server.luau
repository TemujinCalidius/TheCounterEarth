-- WaterWell.server.luau
-- Adds a ProximityPrompt to any Part named "WaterWell" in Workspace.
-- Pressing E fully restores the player's thirst (and a bit of hunger).
-- Place a Part named "WaterWell" anywhere in your map to use this.

local ServerStorage = game:GetService("ServerStorage")
local Workspace     = game:GetService("Workspace")

local consumeEffect: BindableEvent =
	ServerStorage:WaitForChild("ServerBindables"):WaitForChild("ConsumeEffect") :: BindableEvent

local function setupWell(part: BasePart)
	if part:FindFirstChildOfClass("ProximityPrompt") then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Drink"
	prompt.ObjectText            = "Water Well"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.HoldDuration          = 0.5
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = part

	prompt.Triggered:Connect(function(player)
		consumeEffect:Fire(player, { thirst = 100 })
	end)
end

-- Find existing wells
for _, desc in ipairs(Workspace:GetDescendants()) do
	if desc:IsA("BasePart") and desc.Name == "WaterWell" then
		setupWell(desc)
	end
end

-- Watch for new ones
Workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("BasePart") and inst.Name == "WaterWell" then
		setupWell(inst)
	end
end)
