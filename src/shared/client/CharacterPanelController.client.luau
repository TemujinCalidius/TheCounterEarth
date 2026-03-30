-- CharacterPanelController.client.luau
-- Standalone character panel: equipment slots and RPG stat block.
-- Opened via HUD button bar or C key. Managed by PanelManager.

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ItemRegistry  = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ItemRegistry"))
local PanelManager  = require(script.Parent:WaitForChild("PanelManager"))

local remotes                = ReplicatedStorage:WaitForChild("Remotes")
local unequipBackpackRemote  = remotes:WaitForChild("UnequipBackpack")  :: RemoteEvent
local unequipQuiverRemote    = remotes:WaitForChild("UnequipQuiver")    :: RemoteEvent

-- ── Style (matches InventoryController palette) ─────────────────────────
local BG     = Color3.fromRGB(20, 22, 30)
local BG2    = Color3.fromRGB(32, 36, 50)
local BG3    = Color3.fromRGB(42, 48, 66)
local ACCENT = Color3.fromRGB(92, 184, 200)  -- teal accent for character panel
local TEXT   = Color3.fromRGB(220, 225, 240)
local MUTED  = Color3.fromRGB(120, 132, 158)
local FONTB  = Enum.Font.GothamBold
local FONT   = Enum.Font.Gotham

-- ── Helpers ─────────────────────────────────────────────────────────────
local function addCorner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function makeLabel(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3             = TEXT
	l.Font                   = FONT
	l.TextSize               = 13
	local a: any = l
	for k, v in pairs(props) do a[k] = v end
	l.Parent = parent
	return l
end

-- ── Build ScreenGui ─────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name           = "CharacterGui"
gui.ResetOnSpawn   = false
gui.DisplayOrder   = 5
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = playerGui

-- Panel frame (shared sizing with other panels)
local panel = Instance.new("Frame")
panel.Name                 = "CharacterPanel"
panel.Size                 = UDim2.new(0.7, 0, 0.75, 0)
panel.Position             = UDim2.new(0.5, 0, 0.5, 0)
panel.AnchorPoint          = Vector2.new(0.5, 0.5)
panel.BackgroundColor3     = BG
panel.BorderSizePixel      = 0
panel.Parent               = gui
addCorner(panel, 12)

local panelStroke = Instance.new("UIStroke")
panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
panelStroke.Thickness       = 1
panelStroke.Color           = Color3.fromRGB(60, 60, 70)
panelStroke.Parent          = panel

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size                 = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundTransparency = 1
titleBar.Parent               = panel

makeLabel(titleBar, {
	Size           = UDim2.new(1, -60, 0, 24),
	Position       = UDim2.new(0, 16, 0, 10),
	Text           = "CHARACTER",
	Font           = FONTB,
	TextSize       = 16,
	TextColor3     = TEXT,
	TextXAlignment = Enum.TextXAlignment.Left,
})

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Name               = "CloseBtn"
closeBtn.Size               = UDim2.new(0, 30, 0, 30)
closeBtn.Position           = UDim2.new(1, -40, 0, 7)
closeBtn.BackgroundColor3   = BG2
closeBtn.BorderSizePixel    = 0
closeBtn.Text               = "X"
closeBtn.TextColor3         = TEXT
closeBtn.Font               = FONTB
closeBtn.TextSize           = 14
closeBtn.Parent             = panel
addCorner(closeBtn, 5)

closeBtn.Activated:Connect(function()
	PanelManager.close()
end)

-- Content area (below title bar)
local content = Instance.new("Frame")
content.Size                 = UDim2.new(1, -24, 1, -56)
content.Position             = UDim2.new(0, 12, 0, 50)
content.BackgroundTransparency = 1
content.Parent               = panel

-- ── Equipment section (left side) ───────────────────────────────────────

local equipSection = Instance.new("Frame")
equipSection.Size             = UDim2.new(0, 255, 1, 0)
equipSection.BackgroundTransparency = 1
equipSection.Parent           = content

makeLabel(equipSection, {
	Size           = UDim2.new(1, 0, 0, 16),
	Text           = "EQUIPMENT",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3     = MUTED,
	Font           = FONTB,
	TextSize       = 10,
})

local SLOT_PAIRS = {
	{ "Head",       "Head",       "Neck",     "Neck"      },
	{ "Chest",      "Chest",      "Belt",     "Belt"      },
	{ "Legs",       "Legs",       "Feet",     "Feet"      },
	{ "RingL",      "Ring (L)",   "RingR",    "Ring (R)"  },
	{ "MainHand",   "Main Hand",  "Quiver",   "Quiver"    },
	{ "CoinPouch",  "Coin Pouch", "Backpack", "Backpack"  },
}

local SLOT_W, SLOT_H, SLOT_GAP = 118, 40, 6

type SlotRef = { nameLabel: TextLabel, valLabel: TextLabel, box: Frame? }
local slotRefs: { [string]: SlotRef } = {}

local function makeSlotBox(parent: Instance, slotId: string, labelText: string, xOff: number, yOff: number)
	local box = Instance.new("Frame")
	box.Size             = UDim2.new(0, SLOT_W, 0, SLOT_H)
	box.Position         = UDim2.new(0, xOff, 0, yOff)
	box.BackgroundColor3 = BG3
	box.BorderSizePixel  = 0
	box.Parent           = parent
	addCorner(box, 5)

	local nameLabel = makeLabel(box, {
		Size           = UDim2.new(1, -6, 0, 14),
		Position       = UDim2.new(0, 6, 0, 3),
		Text           = labelText,
		TextColor3     = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize       = 10,
	})
	local valLabel = makeLabel(box, {
		Size           = UDim2.new(1, -6, 0, 18),
		Position       = UDim2.new(0, 6, 0, 18),
		Text           = "--",
		TextColor3     = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font           = FONTB,
		TextSize       = 12,
	})
	slotRefs[slotId] = { nameLabel = nameLabel, valLabel = valLabel, box = box }
end

for row, pair in ipairs(SLOT_PAIRS) do
	local yOff = 20 + (row - 1) * (SLOT_H + SLOT_GAP)
	makeSlotBox(equipSection, pair[1], pair[2], 0,          yOff)
	makeSlotBox(equipSection, pair[3], pair[4], SLOT_W + 8, yOff)
end

-- Click Backpack slot to unequip
do
	local bpRef = slotRefs["Backpack"]
	if bpRef and bpRef.box then
		local btn = Instance.new("TextButton")
		btn.Size                    = UDim2.new(1, 0, 1, 0)
		btn.BackgroundTransparency  = 1
		btn.Text                    = ""
		btn.Parent                  = bpRef.box
		btn.Activated:Connect(function()
			local equipped = player:GetAttribute("EquipSlot_Backpack") or ""
			if equipped ~= "" then
				unequipBackpackRemote:FireServer()
			end
		end)
	end
end

-- Click Quiver slot to unequip
do
	local qRef = slotRefs["Quiver"]
	if qRef and qRef.box then
		local btn = Instance.new("TextButton")
		btn.Size                    = UDim2.new(1, 0, 1, 0)
		btn.BackgroundTransparency  = 1
		btn.Text                    = ""
		btn.Parent                  = qRef.box
		btn.Activated:Connect(function()
			local equipped = player:GetAttribute("EquipSlot_Quiver") or ""
			if equipped ~= "" then
				unequipQuiverRemote:FireServer()
			end
		end)
	end
end

-- ── Stats section (right side) ──────────────────────────────────────────

local statsSection = Instance.new("Frame")
statsSection.Size             = UDim2.new(1, -265, 1, 0)
statsSection.Position         = UDim2.new(0, 265, 0, 0)
statsSection.BackgroundTransparency = 1
statsSection.Parent           = content

makeLabel(statsSection, {
	Size           = UDim2.new(1, 0, 0, 16),
	Text           = "ATTRIBUTES",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3     = MUTED,
	Font           = FONTB,
	TextSize       = 10,
})

local STAT_DEFS = {
	{ id = "STR", label = "Strength",     desc = "Physical power"           },
	{ id = "AGI", label = "Agility",      desc = "Speed & precision"        },
	{ id = "CON", label = "Constitution", desc = "Health & stamina"         },
	{ id = "WIS", label = "Wisdom",       desc = "Survival intuition"       },
	{ id = "INT", label = "Intellect",    desc = "Crafting & lore"          },
	{ id = "CHA", label = "Charisma",     desc = "NPC pricing & diplomacy"  },
}

type StatRef = { valLabel: TextLabel }
local statRefs: { [string]: StatRef } = {}

for i, stat in ipairs(STAT_DEFS) do
	local yOff = 20 + (i - 1) * 48
	local statBox = Instance.new("Frame")
	statBox.Size             = UDim2.new(1, 0, 0, 44)
	statBox.Position         = UDim2.new(0, 0, 0, yOff)
	statBox.BackgroundColor3 = BG3
	statBox.BorderSizePixel  = 0
	statBox.Parent           = statsSection
	addCorner(statBox, 5)

	makeLabel(statBox, {
		Size           = UDim2.new(1, -50, 0, 16),
		Position       = UDim2.new(0, 8, 0, 4),
		Text           = stat.label,
		Font           = FONTB,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize       = 12,
	})
	makeLabel(statBox, {
		Size           = UDim2.new(1, -50, 0, 16),
		Position       = UDim2.new(0, 8, 0, 22),
		Text           = stat.desc,
		TextColor3     = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize       = 10,
	})

	local valLabel = makeLabel(statBox, {
		Size           = UDim2.new(0, 40, 1, 0),
		Position       = UDim2.new(1, -48, 0, 0),
		Text           = "0",
		Font           = FONTB,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize       = 16,
		TextColor3     = ACCENT,
	})
	statRefs[stat.id] = { valLabel = valLabel }
end

-- ── Refresh ─────────────────────────────────────────────────────────────

local function refreshCharacter()
	for slotId, ref in pairs(slotRefs) do
		local raw: any
		if slotId == "MainHand" then
			local equippedSlot = tonumber(player:GetAttribute("HotbarEquippedSlot")) or 0
			if equippedSlot >= 1 and equippedSlot <= 9 then
				raw = player:GetAttribute("HotbarSlot" .. equippedSlot)
			end
		else
			raw = player:GetAttribute("EquipSlot_" .. slotId)
		end

		local itemId = type(raw) == "string" and raw or ""
		if itemId ~= "" then
			local def = ItemRegistry.get(itemId)
			ref.valLabel.Text      = def and def.displayName or itemId
			ref.valLabel.TextColor3 = TEXT
		else
			ref.valLabel.Text      = "--"
			ref.valLabel.TextColor3 = MUTED
		end
	end

	for statId, ref in pairs(statRefs) do
		local val = tonumber(player:GetAttribute("Stat_" .. statId)) or 0
		ref.valLabel.Text = tostring(math.floor(val))
	end
end

-- ── Register with PanelManager ──────────────────────────────────────────

PanelManager.register("character", {
	open = function()
		refreshCharacter()
	end,
	close = function()
		-- nothing special needed on close
	end,
	frame = panel,
	screenGui = gui,
})

-- Hotkey: C to toggle character panel
ContextActionService:BindActionAtPriority(
	"ToggleCharacter",
	function(_name, state, _obj)
		if state == Enum.UserInputState.Begin then
			PanelManager.toggle("character")
		end
		return Enum.ContextActionResult.Sink
	end,
	false,
	Enum.ContextActionPriority.High.Value,
	Enum.KeyCode.C
)

-- ── Reactive attribute updates ──────────────────────────────────────────

player.AttributeChanged:Connect(function(attrName: string)
	if not PanelManager.getActive() == "character" then return end

	if attrName == "HotbarEquippedSlot"
		or attrName:sub(1, 10) == "HotbarSlot"
		or attrName:sub(1, 5) == "Stat_"
		or attrName:sub(1, 10) == "EquipSlot_"
	then
		refreshCharacter()
	end
end)
