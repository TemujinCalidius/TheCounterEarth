-- InventoryTypes.luau
-- Shared type definitions for the inventory system.
-- No logic lives here — just the data shapes used across server and client.
--
-- GLOSSARY
--   ItemStack   — a quantity of one item type, with optional durability/expiry
--   GridItem    — an ItemStack placed at a specific position in a backpack grid
--   EquipSlot   — one of the named character equipment slots
--   PlayerInventory — the full state of one player's carried items

-- ---------------------------------------------------------------------------
-- ItemStack
-- ---------------------------------------------------------------------------
-- Represents N units of a single item type.
-- durability: current durability points. nil if the item type has no durability.
-- expiresAt:  os.time() Unix timestamp after which the stack has perished.
--             nil if the item type is not perishable.
export type ItemStack = {
	itemId: string,
	qty: number,
	durability: number?,
	expiresAt: number?,
}

-- ---------------------------------------------------------------------------
-- Equipment slots
-- ---------------------------------------------------------------------------
-- Named slots on the player's character paper-doll.
-- main_hand / off_hand  — held items / weapons / shields
-- coin_pouch            — determines which currency economy shows on HUD
-- backpack              — when filled, opens the grid panel
export type EquipSlot =
	"head"
	| "neck"
	| "chest"
	| "belt"
	| "legs"
	| "feet"
	| "ring_l"
	| "ring_r"
	| "main_hand"
	| "off_hand"
	| "coin_pouch"
	| "backpack"

-- Ordered list used for UI layout and iteration.
local EQUIP_SLOT_ORDER: { EquipSlot } = {
	"head",
	"neck",
	"chest",
	"belt",
	"legs",
	"feet",
	"ring_l",
	"ring_r",
	"main_hand",
	"off_hand",
	"coin_pouch",
	"backpack",
}

-- Which slots accept which item categories (enforced on server).
-- nil means the slot is uncategorised / checked by other rules.
local EQUIP_SLOT_ACCEPTS: { [EquipSlot]: { string } } = {
	head       = { "armor" },
	neck       = { "armor", "jewelry" },
	chest      = { "armor" },
	belt       = { "armor", "container" },
	legs       = { "armor" },
	feet       = { "armor" },
	ring_l     = { "jewelry" },
	ring_r     = { "jewelry" },
	main_hand  = { "weapon", "tool", "placeable" },
	off_hand   = { "weapon", "tool", "container" },
	coin_pouch = { "container" },   -- must also have coinPouch field
	backpack   = { "container" },   -- must also have backpack field
}

-- ---------------------------------------------------------------------------
-- GridItem
-- ---------------------------------------------------------------------------
-- An ItemStack placed at a specific top-left cell in the backpack grid.
-- Row and col are 1-indexed. The item occupies cells:
--   (row .. row+h-1) x (col .. col+w-1)
-- where w,h come from ItemRegistry.Items[itemId].slotSize.
export type GridItem = {
	stack: ItemStack,
	row: number,
	col: number,
}

-- ---------------------------------------------------------------------------
-- PlayerInventory
-- ---------------------------------------------------------------------------
-- The full carry state for one player. Authoritative on the server;
-- replicated to the owning client only.
--
-- hotbar:     9 itemId strings (or "" for empty). Each must reference an item
--             that physically exists in equipment or grid.
-- equipment:  One ItemStack per EquipSlot, or nil if the slot is empty.
-- grid:       Items placed in the backpack grid. Empty list when no backpack.
-- gridW/H:    Dimensions of the active backpack grid (0 x 0 = no backpack).
-- currentWeight / maxWeight:
--             Tracked in kg. currentWeight is the sum of all carried item
--             weights × qty. maxWeight = base pocket limit + backpack limit.
export type PlayerInventory = {
	hotbar: { [number]: string },
	equipment: { [string]: ItemStack? },
	grid: { GridItem },
	gridW: number,
	gridH: number,
	currentWeight: number,
	maxWeight: number,
}

-- ---------------------------------------------------------------------------
-- Serialisable form (stored in DataStore)
-- ---------------------------------------------------------------------------
-- Same as PlayerInventory but GridItem.stack.expiresAt is always a number
-- (items that have already expired are stripped on load).
export type SerializedInventory = {
	hotbar: { [number]: string },
	equipment: { [string]: { itemId: string, qty: number, durability: number?, expiresAt: number? }? },
	grid: { { stack: { itemId: string, qty: number, durability: number?, expiresAt: number? }, row: number, col: number } },
	gridW: number,
	gridH: number,
}

-- ---------------------------------------------------------------------------
-- Helpers exported for other modules
-- ---------------------------------------------------------------------------

local function emptyInventory(): PlayerInventory
	local hotbar = table.create(9)
	for i = 1, 9 do
		hotbar[i] = ""
	end
	return {
		hotbar        = hotbar,
		equipment     = {},
		grid          = {},
		gridW         = 0,
		gridH         = 0,
		currentWeight = 0,
		maxWeight     = 0, -- filled in by server using GameplayConfig
	}
end

-- Returns true if the stack has a perishable timestamp that has passed.
local function isExpired(stack: ItemStack): boolean
	if stack.expiresAt == nil then
		return false
	end
	return os.time() > (stack.expiresAt :: number)
end

-- Clamp durability to [0, max]. Returns the new value.
local function clampDurability(current: number, max: number): number
	return math.clamp(current, 0, max)
end

return {
	EQUIP_SLOT_ORDER   = EQUIP_SLOT_ORDER,
	EQUIP_SLOT_ACCEPTS = EQUIP_SLOT_ACCEPTS,
	emptyInventory     = emptyInventory,
	isExpired          = isExpired,
	clampDurability    = clampDurability,
}
