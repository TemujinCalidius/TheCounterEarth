-- CharacterCreatorController.client.luau
-- Full-screen modal for first-time character creation: gender + skin tone.
-- Listens for ShowCharacterCreator remote from server, displays the UI,
-- fires AppearanceChosen back with the player's selections.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AppearanceConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AppearanceConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local showCreatorRemote = remotesFolder:WaitForChild("ShowCharacterCreator")
local appearanceChosenRemote = remotesFolder:WaitForChild("AppearanceChosen")

-- ── Current selection state ──────────────────────────────────────
local selectedGender = AppearanceConfig.Defaults.gender
local selectedSkinTone = AppearanceConfig.Defaults.skin_tone

local currentGui: ScreenGui? = nil

-- ── UI builders ──────────────────────────────────────────────────
local function makeButton(parent: Instance, name: string, layoutOrder: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.LayoutOrder = layoutOrder
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
	btn.TextColor3 = Color3.fromRGB(220, 225, 235)
	btn.Font = Enum.Font.GothamSemibold
	btn.TextScaled = true
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 90, 110)
	stroke.Thickness = 1
	stroke.Parent = btn

	return btn
end

local function setButtonSelected(btn: TextButton, isSelected: boolean)
	local stroke = btn:FindFirstChildWhichIsA("UIStroke")
	if isSelected then
		btn.BackgroundColor3 = Color3.fromRGB(75, 130, 195)
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		if stroke then
			stroke.Color = Color3.fromRGB(140, 200, 255)
			stroke.Thickness = 2
		end
	else
		btn.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
		btn.TextColor3 = Color3.fromRGB(220, 225, 235)
		if stroke then
			stroke.Color = Color3.fromRGB(80, 90, 110)
			stroke.Thickness = 1
		end
	end
end

-- ── Build the modal ──────────────────────────────────────────────
local function buildModal(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "CharacterCreatorGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000  -- on top of everything

	-- Backdrop (full-screen dim)
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
	backdrop.BackgroundTransparency = 0.05
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	-- Centered panel
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(0, 460, 0, 540)
	panel.Position = UDim2.new(0.5, -230, 0.5, -270)
	panel.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	panel.BorderSizePixel = 0
	panel.Parent = backdrop

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(60, 70, 90)
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 28)
	padding.PaddingBottom = UDim.new(0, 24)
	padding.PaddingLeft = UDim.new(0, 28)
	padding.PaddingRight = UDim.new(0, 28)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 14)
	layout.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 38)
	title.BackgroundTransparency = 1
	title.Text = "CREATE YOUR SURVIVOR"
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(235, 240, 250)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Parent = panel

	-- Subtitle
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.LayoutOrder = 2
	subtitle.Size = UDim2.new(1, 0, 0, 18)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Choose your appearance — you can change skin tone later"
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(150, 160, 180)
	subtitle.Parent = panel

	-- Gender section
	local genderLabel = Instance.new("TextLabel")
	genderLabel.Name = "GenderLabel"
	genderLabel.LayoutOrder = 3
	genderLabel.Size = UDim2.new(1, 0, 0, 22)
	genderLabel.BackgroundTransparency = 1
	genderLabel.Text = "GENDER"
	genderLabel.Font = Enum.Font.GothamSemibold
	genderLabel.TextScaled = true
	genderLabel.TextColor3 = Color3.fromRGB(180, 190, 210)
	genderLabel.TextXAlignment = Enum.TextXAlignment.Left
	genderLabel.Parent = panel

	local genderRow = Instance.new("Frame")
	genderRow.Name = "GenderRow"
	genderRow.LayoutOrder = 4
	genderRow.Size = UDim2.new(1, 0, 0, 60)
	genderRow.BackgroundTransparency = 1
	genderRow.Parent = panel
	local genderRowLayout = Instance.new("UIListLayout")
	genderRowLayout.FillDirection = Enum.FillDirection.Horizontal
	genderRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	genderRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	genderRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	genderRowLayout.Padding = UDim.new(0, 12)
	genderRowLayout.Parent = genderRow

	local genderButtons = {}
	for i, genderId in AppearanceConfig.GenderOrder do
		local cfg = AppearanceConfig.Genders[genderId]
		local btn = makeButton(genderRow, "Gender_" .. genderId, i)
		btn.Size = UDim2.new(0, 180, 1, 0)
		btn.Text = cfg.name
		genderButtons[genderId] = btn

		btn.MouseButton1Click:Connect(function()
			selectedGender = genderId
			for id, b in genderButtons do
				setButtonSelected(b, id == genderId)
			end
		end)
	end

	-- Skin tone section
	local skinLabel = Instance.new("TextLabel")
	skinLabel.Name = "SkinLabel"
	skinLabel.LayoutOrder = 5
	skinLabel.Size = UDim2.new(1, 0, 0, 22)
	skinLabel.BackgroundTransparency = 1
	skinLabel.Text = "SKIN TONE"
	skinLabel.Font = Enum.Font.GothamSemibold
	skinLabel.TextScaled = true
	skinLabel.TextColor3 = Color3.fromRGB(180, 190, 210)
	skinLabel.TextXAlignment = Enum.TextXAlignment.Left
	skinLabel.Parent = panel

	local skinRow = Instance.new("Frame")
	skinRow.Name = "SkinRow"
	skinRow.LayoutOrder = 6
	skinRow.Size = UDim2.new(1, 0, 0, 80)
	skinRow.BackgroundTransparency = 1
	skinRow.Parent = panel
	local skinRowLayout = Instance.new("UIListLayout")
	skinRowLayout.FillDirection = Enum.FillDirection.Horizontal
	skinRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	skinRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	skinRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	skinRowLayout.Padding = UDim.new(0, 10)
	skinRowLayout.Parent = skinRow

	-- Helper to render the selected/unselected visual for a skin swatch
	local function setSkinSelected(btn: TextButton, isSelected: boolean)
		local stroke = btn:FindFirstChildWhichIsA("UIStroke")
		local check = btn:FindFirstChild("Check") :: TextLabel?
		local scale = btn:FindFirstChildWhichIsA("UIScale")
		if isSelected then
			if stroke then
				stroke.Color = Color3.fromRGB(255, 255, 255)
				stroke.Thickness = 4
			end
			if check then check.Visible = true end
			if scale then scale.Scale = 1.12 end
		else
			if stroke then
				stroke.Color = Color3.fromRGB(80, 90, 110)
				stroke.Thickness = 1
			end
			if check then check.Visible = false end
			if scale then scale.Scale = 1 end
		end
	end

	local skinButtons = {}
	for i, toneId in AppearanceConfig.SkinToneOrder do
		local tone = AppearanceConfig.SkinTones[toneId]
		local btn = Instance.new("TextButton")
		btn.Name = "Tone_" .. toneId
		btn.LayoutOrder = i
		btn.Size = UDim2.new(0, 56, 0, 56)
		btn.BackgroundColor3 = tone.color
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.Parent = skinRow

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = btn

		-- Border stroke rendered OUTSIDE the swatch so the selected ring is clear
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Color = Color3.fromRGB(80, 90, 110)
		stroke.Thickness = 1
		stroke.Parent = btn

		-- UIScale so the selected swatch pops slightly bigger
		local scale = Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = btn

		-- Check mark overlay (hidden until selected)
		local check = Instance.new("TextLabel")
		check.Name = "Check"
		check.Size = UDim2.new(1, 0, 1, 0)
		check.BackgroundTransparency = 1
		check.Text = "✓"
		check.Font = Enum.Font.GothamBold
		check.TextScaled = true
		check.TextColor3 = Color3.fromRGB(255, 255, 255)
		check.TextStrokeColor3 = Color3.new(0, 0, 0)
		check.TextStrokeTransparency = 0.2
		check.Visible = false
		check.Parent = btn

		-- Tooltip-style name label below swatch
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1.4, 0, 0, 18)
		nameLabel.Position = UDim2.new(-0.2, 0, 1, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = tone.name
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = Color3.fromRGB(160, 170, 190)
		nameLabel.Parent = btn

		skinButtons[toneId] = btn

		btn.MouseButton1Click:Connect(function()
			selectedSkinTone = toneId
			for id, b in skinButtons do
				setSkinSelected(b, id == toneId)
			end
		end)
	end

	-- Spacer
	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.LayoutOrder = 7
	spacer.Size = UDim2.new(1, 0, 0, 16)
	spacer.BackgroundTransparency = 1
	spacer.Parent = panel

	-- Confirm button
	local confirmBtn = makeButton(panel, "Confirm", 8)
	confirmBtn.Size = UDim2.new(1, 0, 0, 54)
	confirmBtn.Text = "CONFIRM"
	confirmBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 90)
	confirmBtn.TextColor3 = Color3.fromRGB(245, 250, 245)
	confirmBtn.Font = Enum.Font.GothamBold
	local cstroke = confirmBtn:FindFirstChildWhichIsA("UIStroke")
	if cstroke then
		cstroke.Color = Color3.fromRGB(100, 200, 130)
		cstroke.Thickness = 2
	end

	confirmBtn.MouseButton1Click:Connect(function()
		appearanceChosenRemote:FireServer(selectedGender, selectedSkinTone)
		if currentGui then
			currentGui:Destroy()
			currentGui = nil
		end
	end)

	-- Set initial selection visuals
	for id, b in genderButtons do
		setButtonSelected(b, id == selectedGender)
	end
	for id, b in skinButtons do
		setSkinSelected(b, id == selectedSkinTone)
	end

	return gui
end

-- ── Listen for server prompt ─────────────────────────────────────
showCreatorRemote.OnClientEvent:Connect(function()
	if currentGui then
		currentGui:Destroy()
	end
	currentGui = buildModal()
	currentGui.Parent = playerGui
end)
