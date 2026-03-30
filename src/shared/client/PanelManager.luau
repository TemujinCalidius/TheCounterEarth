--[[
	PanelManager — centralised open/close manager for all full-screen UI panels.

	Each panel controller calls PanelManager.register() once at startup, then
	uses PanelManager.toggle() / .close() for all open/close logic.

	Provides:
	  • Mutual exclusivity — only one panel open at a time
	  • Open/close animations (scale + fade)
	  • Mouse unlock in first-person mode (continuous RenderStepped override)
	  • Crosshair hide/show
	  • Click-outside-to-close overlay
	  • Escape key integration (called from HudController)
	  • onActiveChanged callbacks for HUD button bar highlights
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── Types ────────────────────────────────────────────────────────────────

export type PanelCallbacks = {
	open: () -> (),       -- called when the panel should show its content / refresh
	close: () -> (),      -- called when the panel should hide / clean up
	frame: GuiObject,     -- the top-level panel Frame (used for animation)
	screenGui: ScreenGui, -- the ScreenGui containing the panel
}

-- ── State ────────────────────────────────────────────────────────────────

local PanelManager = {}

local panels: { [string]: PanelCallbacks } = {}
local activePanel: string? = nil
local changeCallbacks: { (name: string?) -> () } = {}

-- Mouse override connection (fights first-person camera re-lock)
local mouseOverrideConn: RBXScriptConnection? = nil

-- Click-outside overlay (transparent full-screen button behind panel)
local clickOutsideOverlay: ScreenGui? = nil

-- ── Animation constants ──────────────────────────────────────────────────

local OPEN_INFO  = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- ── Crosshair helper ─────────────────────────────────────────────────────

local function setCrosshairVisible(visible: boolean)
	local gui = playerGui:FindFirstChild("CrosshairGui")
	if gui then
		gui.Enabled = visible
	end
end

-- ── Mouse lock/unlock ────────────────────────────────────────────────────

local function startMouseOverride()
	if mouseOverrideConn then return end
	mouseOverrideConn = RunService.RenderStepped:Connect(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
end

local function stopMouseOverride()
	if mouseOverrideConn then
		mouseOverrideConn:Disconnect()
		mouseOverrideConn = nil
	end
	-- Restore first-person mouse lock if applicable
	if player.CameraMode == Enum.CameraMode.LockFirstPerson then
		UserInputService.MouseIconEnabled = false
		setCrosshairVisible(true)
	end
end

-- ── Click-outside overlay ────────────────────────────────────────────────

local function showClickOutside()
	if clickOutsideOverlay then return end

	local overlay = Instance.new("ScreenGui")
	overlay.Name = "PanelClickOutside"
	overlay.ResetOnSpawn = false
	overlay.DisplayOrder = 4  -- below panel ScreenGuis (DisplayOrder 5)
	overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local btn = Instance.new("TextButton")
	btn.Name = "Overlay"
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Parent = overlay

	btn.Activated:Connect(function()
		PanelManager.close()
	end)

	overlay.Parent = playerGui
	clickOutsideOverlay = overlay
end

local function hideClickOutside()
	if clickOutsideOverlay then
		clickOutsideOverlay:Destroy()
		clickOutsideOverlay = nil
	end
end

-- ── Fire change callbacks ────────────────────────────────────────────────

local function fireChanged()
	for _, fn in ipairs(changeCallbacks) do
		task.spawn(fn, activePanel)
	end
end

-- ── Animation helpers ────────────────────────────────────────────────────

local function animateOpen(frame: GuiObject)
	-- Start slightly scaled down and transparent
	local targetSize = frame.Size
	local smallSize = UDim2.new(
		targetSize.X.Scale * 0.95, targetSize.X.Offset * 0.95,
		targetSize.Y.Scale * 0.95, targetSize.Y.Offset * 0.95
	)
	frame.Size = smallSize

	-- Use GroupTransparency if available (CanvasGroup), otherwise just tween size
	if frame:IsA("CanvasGroup") then
		frame.GroupTransparency = 1
		TweenService:Create(frame, OPEN_INFO, {
			Size = targetSize,
			GroupTransparency = 0,
		}):Play()
	else
		TweenService:Create(frame, OPEN_INFO, {
			Size = targetSize,
		}):Play()
	end
end

local function animateClose(frame: GuiObject, callback: () -> ())
	local currentSize = frame.Size
	local smallSize = UDim2.new(
		currentSize.X.Scale * 0.95, currentSize.X.Offset * 0.95,
		currentSize.Y.Scale * 0.95, currentSize.Y.Offset * 0.95
	)

	local tween
	if frame:IsA("CanvasGroup") then
		tween = TweenService:Create(frame, CLOSE_INFO, {
			Size = smallSize,
			GroupTransparency = 1,
		})
	else
		tween = TweenService:Create(frame, CLOSE_INFO, {
			Size = smallSize,
		})
	end

	tween.Completed:Once(function()
		-- Reset size for next open
		frame.Size = currentSize
		callback()
	end)
	tween:Play()
end

-- ── Public API ───────────────────────────────────────────────────────────

--- Register a panel with the manager.
--- @param name string — unique panel key ("inventory", "character", "achievements", "codex")
--- @param callbacks PanelCallbacks
function PanelManager.register(name: string, callbacks: PanelCallbacks)
	panels[name] = callbacks
	-- Ensure panel starts hidden
	callbacks.screenGui.Enabled = false
end

--- Open a panel by name. Closes any currently open panel first.
function PanelManager.open(name: string)
	if not panels[name] then return end

	-- Close current panel (instant, no animation)
	if activePanel and activePanel ~= name then
		local current = panels[activePanel]
		if current then
			current.close()
			current.screenGui.Enabled = false
		end
	end

	activePanel = name
	local p = panels[name]
	p.screenGui.Enabled = true
	p.open()
	animateOpen(p.frame)

	-- Mouse + crosshair
	setCrosshairVisible(false)
	startMouseOverride()

	-- Click-outside overlay
	showClickOutside()

	fireChanged()
end

--- Close the currently active panel with animation.
function PanelManager.close()
	if not activePanel then return end

	local name = activePanel
	local p = panels[name]
	if not p then
		activePanel = nil
		fireChanged()
		return
	end

	activePanel = nil

	animateClose(p.frame, function()
		p.close()
		p.screenGui.Enabled = false
	end)

	-- Mouse + crosshair
	stopMouseOverride()

	-- Remove overlay
	hideClickOutside()

	fireChanged()
end

--- Toggle a panel: open if closed (or different panel open), close if already open.
function PanelManager.toggle(name: string)
	if activePanel == name then
		PanelManager.close()
	else
		PanelManager.open(name)
	end
end

--- Get the name of the currently active panel, or nil if none.
function PanelManager.getActive(): string?
	return activePanel
end

--- Register a callback fired whenever the active panel changes.
--- The callback receives the new active panel name (or nil).
function PanelManager.onActiveChanged(fn: (name: string?) -> ())
	table.insert(changeCallbacks, fn)
end

--- Check if any panel is currently open.
function PanelManager.isAnyOpen(): boolean
	return activePanel ~= nil
end

return PanelManager
