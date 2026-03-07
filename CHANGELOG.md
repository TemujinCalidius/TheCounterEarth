# The Colony - Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

---

## [0.4.0] - 2026-03-07

### Added
- **Blood bar** (100 → 0) — drains while bleeding, regenerates when wound clots. At 0 blood: 3 HP/s health drain (severe). Regen gated by hunger/thirst (above 50% = full rate, below = half, at 0 = stopped)
- **Poison bar** (0 → 100) — fills while poisoned, decays when source removed. Health drain scales linearly with level (up to 2 HP/s at 100%). Energy regen halved while any poison present
- **Bleed stacking** — each wound adds a bleed stack. More stacks = faster blood drain. Natural clotting removes one stack at a time. Bandage clears all stacks
- **Blood & Poison persistence** — both bar levels AND active effect flags saved to DataStore. Cannot relog to reset
- **Blood & Poison HUD bars** — expanded survival panel now shows 5 bars (hunger, thirst, fatigue, blood, poison) with warning colour tints
- **Status effect badges with icons** — bleeding and poison HUD indicators now show BloodIcon and PoisonIcon from AssetIds
- **Particle effects** — blood drip particles (using BloodIcon texture) on character while actively bleeding; green toxic aura particles while poisoned
- **ApplyStatusEffect BindableEvent** — `ServerStorage/ServerBindables/ApplyStatusEffect` for weapon scripts, test parts, and other systems to trigger bleed/poison through proper server state
- **HUD icons** — hooked up HungerIcon, ThirstIcon, FatigueIcon, BloodIcon, PoisonIcon from AssetIds into survival bars and status badges
- Status effect test script (`assets/raw/scripts/StatusEffectTestPart.server.lua`) — drop in a Part, press E to add bleed stacks + poison, hold R to clear

### Changed
- Blood/Poison converted from boolean status effects to persistent numeric bars (StatsConfig)
- `setSurvivalStat()` now always accumulates internal value (fixes sub-threshold per-frame deltas being lost at high framerates)
- DataStore profile now saves Blood, Poison, BleedStacks, IsBleeding, IsPoisoned
- Expanded HUD panel height from 156px to 236px for 5 survival bars
- Death now resets blood to 100 and poison to 0

### Removed
- Wild Berries (`wild_berry`) removed from ItemRegistry and scatter spawn system — will be re-added as bush-harvestable items
- Cooked Berries (`cooked_berries`) removed from ItemRegistry

---

## [0.3.0] - 2026-03-06

### Added
- **Drag-and-drop: Inventory → Hotbar** — drag items from the inventory grid onto specific hotbar slots (fires `PinToSpecificSlot`)
- **Drag-and-drop: Inventory → Inventory** — drag to swap two inventory slots (fires `SwapSlots`)
- **Drag-and-drop: Inventory → Empty space** — drop items to the world as loot bags (fires `DropItem`)
- **Drag-and-drop: Hotbar reorder** — drag hotbar slots onto each other to swap positions (fires `SwapHotbarSlots`)
- `PinToSpecificSlot` remote event and server handler in InventoryService
- `SwapHotbarSlots` remote event and server handler in InventoryService
- Dedicated `IgnoreGuiInset = true` overlay ScreenGuis for drag ghost positioning
- Project documentation in `assets/raw/docs/`

### Fixed
- Drag ghost icon offset (~30px below cursor) caused by GUI inset coordinate mismatch — resolved with IgnoreGuiInset overlay
- Hit detection misalignment — switched from `GetMouseLocation()` to `input.Position` for drop target detection

---

## [0.2.0] - 2026-03-05

### Added
- **Survival stats system** — hunger, thirst, fatigue with configurable drain rates
- `StatsConfig.luau` — centralized survival stat configuration
- Hunger: drains over time, extra drain while sprinting, health damage when empty
- Thirst: drains over time, extra drain while sprinting, health damage when empty, blocks energy regen when empty
- Fatigue: drains over time, restores while resting, speed/energy-regen penalty when empty
- Bleeding status effect — timed health drain, clears naturally or via consumable
- Poison status effect — exponentially decaying health drain, clears naturally or via consumable
- Survival stat bars in HUD (hunger=orange, thirst=blue, fatigue=purple)
- Bleeding/poison status indicators in HUD
- `ConsumeEffect` BindableEvent — InventoryService fires consume effects to PlayerStateService
- Consumable items can restore hunger/thirst/fatigue/energy and clear status effects
- Survival stats persist in DataStore (profile version 4)

### Changed
- PlayerStateService heartbeat loop now processes hunger/thirst/fatigue/bleeding/poison
- Profile save format updated to version 4 (adds survival fields)
- HUD layout expanded to show survival stat bars below energy

---

## [0.1.0] - 2026-03-04

### Added
- **Slot-based inventory system** (`InventoryService.server.luau`)
  - Player attributes: `InvSlot_N`, `InvQty_N`, `MaxInvSlots`
  - Weight tracking: `CarryWeight`, `MaxCarryWeight`
  - Stack merging, empty slot allocation, weight limit enforcement
  - `UseItem`, `CraftItem`, `SplitStack`, `SwapSlots`, `DropItem` remotes
  - `PinToHotbar`, `UnpinFromHotbar` remotes
  - Loot bag creation on drop/death with ProximityPrompt pickup
  - Scatter item auto-management (`_ScatterItem` attribute on Models)
- **Inventory UI** (`InventoryController.client.luau`)
  - Tab key toggle
  - Grid display of inventory slots with item names and quantities
- **Crafting system** (`CraftingConfig.luau`)
  - Recipe definitions with ingredient lists and output
  - Server-side ingredient validation and consumption
- `ItemRegistry.luau` — item definitions (displayName, weight, stackMax, category, onConsume)
- `InventoryTypes.luau` — shared type definitions
- Weight-based speed penalty system (configurable thresholds in GameplayConfig)
- Inventory slot persistence in DataStore (invSlots array in profile)

---

## [0.0.1] - 2026-03-03

### Added
- **Project scaffold** — Rojo 7.6.1 project structure with `default.project.json`
- **Player state system** (`PlayerStateService.server.luau`)
  - Energy: max 100, sprint drain 16/s, jump cost 10, regen 14/s with 0.75s delay
  - Sprint: client sends intent via `SprintIntent` remote, server controls walk speed
  - At 0 energy: jumping disabled, walk speed drops to 6
  - Health: loaded from DataStore, no auto-regen (destroys default Health script)
  - Credits: DataStore persistence (`PlayerProfileV2`), legacy migration from `CreditsV1`
  - Auto-save every 60s, force-save on leave and BindToClose
- **Tool system** (`ToolInventoryService.server.luau`)
  - 9-slot hotbar (keys 1-9) with `HotbarSlot1`–`HotbarSlot9` attributes
  - `HotbarEquippedSlot` attribute for active slot tracking
  - World tool pickup via ProximityPrompt (E key), `CanTouch=false` on handles
  - Tool templates auto-captured to `ServerStorage/ItemTools`
  - Toggle equip: pressing same slot unequips
  - Tools re-granted on character respawn
- **HUD** (`HudController.client.luau`)
  - Top-left panel: health bar (red), energy bar (green), credits display
  - Bottom-center hotbar: 9 slots with active highlight
  - Breathing audio loop (volume/speed scale with energy ratio)
  - Heartbeat audio loop (triggers below 40% health)
  - Vignette overlay (opacity scales with energy depletion)
  - Custom chat window positioning (bottom-left)
  - Disables default Roblox health bar and backpack GUI
- **Configuration** (`GameplayConfig.luau`, `AssetIds.luau`)
  - Centralized config for all gameplay values
  - Asset ID mappings for icons and audio
- **Assets**
  - Health, Energy, Credit icon textures
  - Vignette overlay texture
  - Breathing and heartbeat audio files
