-- ToolPlaceholders.server.luau
-- Creates placeholder Tool instances in ServerStorage/ItemTools for tools
-- that don't have Studio-placed models yet. These are simple geometric shapes
-- that let the equip system work until real meshes are added.
-- Once a real model is placed in Studio, the placeholder is skipped.

local ServerStorage = game:GetService("ServerStorage")

local itemToolsFolder = ServerStorage:FindFirstChild("ItemTools")
if not itemToolsFolder then
	itemToolsFolder = Instance.new("Folder")
	itemToolsFolder.Name = "ItemTools"
	itemToolsFolder.Parent = ServerStorage
end

-- Each entry: { name, handleSize, handleColor, headSize?, headColor?, headOffset? }
local PLACEHOLDERS = {
	{
		name = "stone_axe",
		-- Shaft
		handleSize  = Vector3.new(0.3, 0.3, 3.2),
		handleColor = Color3.fromRGB(101, 67, 33),   -- brown wood
		-- Axe head
		headSize    = Vector3.new(0.3, 1.2, 0.8),
		headColor   = Color3.fromRGB(140, 140, 140),  -- grey stone
		headOffset  = Vector3.new(0, 0.45, -1.2),     -- near top of shaft
	},
	{
		name = "stone_pickaxe",
		-- Shaft
		handleSize  = Vector3.new(0.3, 0.3, 3.2),
		handleColor = Color3.fromRGB(101, 67, 33),
		-- Pick head
		headSize    = Vector3.new(0.25, 0.25, 1.6),
		headColor   = Color3.fromRGB(140, 140, 140),
		headOffset  = Vector3.new(0, 0, -1.2),
	},
	{
		name = "stone_knife",
		-- Handle + blade as one piece
		handleSize  = Vector3.new(0.2, 0.2, 1.6),
		handleColor = Color3.fromRGB(101, 67, 33),
		-- Blade
		headSize    = Vector3.new(0.08, 0.5, 0.9),
		headColor   = Color3.fromRGB(160, 160, 160),
		headOffset  = Vector3.new(0, 0.15, -0.9),
	},
}

for _, info in ipairs(PLACEHOLDERS) do
	-- Skip if a real model already exists
	if itemToolsFolder:FindFirstChild(info.name) then continue end

	local tool = Instance.new("Tool")
	tool.Name = info.name
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	-- Handle (the part Roblox attaches to the hand)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = info.handleSize
	handle.Color = info.handleColor
	handle.Material = Enum.Material.SmoothPlastic
	handle.Anchored = false
	handle.CanCollide = false
	handle.Parent = tool

	-- Optional head piece (axe blade, pick point, knife blade)
	if info.headSize then
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = info.headSize
		head.Color = info.headColor
		head.Material = Enum.Material.SmoothPlastic
		head.Anchored = false
		head.CanCollide = false
		head.Parent = tool

		-- Weld head to handle
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = head
		weld.Parent = head

		-- Position the head relative to the handle
		head.CFrame = handle.CFrame * CFrame.new(info.headOffset)
	end

	tool.Parent = itemToolsFolder
end
