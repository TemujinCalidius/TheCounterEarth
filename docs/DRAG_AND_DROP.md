# Drag-and-Drop System

## Overview

Two independent drag-and-drop systems exist:

1. **Inventory Controller** (`InventoryController.client.luau`) — drag items from the inventory grid to hotbar slots, between inventory slots, or to empty space (drop)
2. **HUD Controller** (`HudController.client.luau`) — drag hotbar slots to reorder them

Both follow the same pattern but operate on different UI elements and fire different remote events.

---

## Architecture

### Drag State Variables

Each system tracks:
- `dragSlot` (number) — the slot index being dragged (0 = not dragging)
- `dragStartPos` (Vector2) — mouse position when drag started
- `isDragging` (boolean) — whether the drag threshold has been exceeded
- `dragGhost` (Frame?) — the visual ghost element following the cursor

### Drag Threshold

A minimum pixel distance (8px) must be exceeded before a drag activates. This prevents accidental drags from regular clicks.

```
DRAG_THRESHOLD = 8
```

### Input Flow

```
InputBegan (per slot)
  └─ Records dragSlot and dragStartPos

InputChanged (global, MouseMovement)
  ├─ If not isDragging: check if distance > threshold → create ghost
  └─ If isDragging: update ghost position

InputEnded (global, MouseButton1)
  ├─ If isDragging: perform hit detection → fire remote
  └─ Cleanup: destroy ghost, reset state
```

---

## Ghost Icon

The drag ghost is a semi-transparent clone of the slot's appearance that follows the cursor.

### Overlay ScreenGui

Ghost icons are parented to a dedicated `ScreenGui` with `IgnoreGuiInset = true`:

```lua
local dragOverlay = Instance.new("ScreenGui")
dragOverlay.Name             = "DragOverlay"      -- or "HudDragOverlay"
dragOverlay.ResetOnSpawn     = false
dragOverlay.IgnoreGuiInset   = true               -- KEY: matches GetMouseLocation() space
dragOverlay.DisplayOrder     = 100                 -- renders above everything
dragOverlay.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
dragOverlay.Parent           = player.PlayerGui
```

**Why IgnoreGuiInset = true:**
- `GetMouseLocation()` returns coordinates including the ~30px GUI inset
- A ScreenGui with `IgnoreGuiInset = true` has its Position space starting from the very top of the screen
- This means `GetMouseLocation()` values can be used directly as Position coordinates — no offset math needed

### Ghost Positioning

```lua
local mousePos = UserInputService:GetMouseLocation()
ghost.Position = UDim2.new(0, mousePos.X - 28, 0, mousePos.Y - 28)
```

The `-28` centers a 56x56 ghost on the cursor.

---

## Hit Detection

When the mouse button is released during a drag, the system checks which slot (if any) the cursor is over.

### Coordinate Space

Hit detection uses `input.Position` from the `InputEnded` event, NOT `GetMouseLocation()`:

```lua
local pos = Vector2.new(input.Position.X, input.Position.Y)
```

**Why `input.Position`:**
- `AbsolutePosition` on GUI elements is in raw screen coordinates (no GUI inset)
- `input.Position` also gives raw screen coordinates (no GUI inset)
- These two coordinate spaces match, so hit testing works correctly
- `GetMouseLocation()` includes the GUI inset and would cause a ~30px vertical offset in hit detection

### Hit Test Logic

For each potential target slot, check if the cursor position falls within its bounds:

```lua
local ap = slot.AbsolutePosition
local as = slot.AbsoluteSize
if pos.X >= ap.X and pos.X <= ap.X + as.X
   and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y then
    -- hit! this is the target slot
end
```

---

## Inventory Controller Drag Actions

| Drag From | Drop On | Remote Fired | Effect |
|-----------|---------|-------------|--------|
| Inventory slot | Hotbar slot | `PinToSpecificSlot(itemId, slotNum)` | Pins item to that exact hotbar slot |
| Inventory slot | Inventory slot | `SwapSlots(fromSlot, toSlot)` | Swaps the two inventory slots |
| Inventory slot | Empty space | `DropItem(fromSlot, qty)` | Drops items as a loot bag in the world |

## HUD Controller Drag Actions

| Drag From | Drop On | Remote Fired | Effect |
|-----------|---------|-------------|--------|
| Hotbar slot | Hotbar slot | `SwapHotbarSlots(fromSlot, toSlot)` | Swaps the two hotbar slots |
| Hotbar slot | Empty space | (no action) | Drag cancelled, item stays |

---

## Server-Side Handlers

### PinToSpecificSlot (InventoryService)
1. Validates itemId and target slot (1-9)
2. Checks item exists in player's inventory
3. Checks item is a tool/weapon/consumable
4. If target slot occupied: clears old occupant (unpins but stays in inventory)
5. Sets `HotbarSlotN` attribute to itemId
6. Spawns Tool instance in Backpack

### SwapHotbarSlots (InventoryService)
1. Validates both slot numbers (1-9)
2. Reads both slot attributes
3. Swaps the attribute values
4. Updates `HotbarEquippedSlot` if either swapped slot was the equipped one

### SwapSlots (InventoryService)
1. Validates both slot numbers (1 to MaxInvSlots)
2. Reads itemId and qty from both slots
3. Writes each slot's data to the other

### DropItem (InventoryService)
1. Validates slot number and quantity
2. Removes items from the slot
3. Refreshes carry weight
4. Creates a loot bag Model in Workspace at the player's position

---

## Known Considerations

- **Coordinate space mismatch**: The ~30px GUI inset is the root cause of most drag offset bugs. The solution (IgnoreGuiInset overlay + input.Position for hit detection) handles this cleanly.
- **Ghost cleanup**: Ghosts are always destroyed in InputEnded, even if no valid drop target is found.
- **No drag between systems**: You cannot currently drag from the hotbar to the inventory panel or vice versa. Inventory→hotbar is one-way via drag; hotbar→hotbar is reorder only.
