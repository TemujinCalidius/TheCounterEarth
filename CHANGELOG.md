# The Counter Earth - Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

---

## [0.6.0] - 2026-03-08

### Added
- **Campfire placement system** — ghost preview placement mode for placeable items. Clone ghost follows mouse cursor with green/red validity coloring based on range. Left-click to place, right-click/Escape to cancel
- **PlacementController** (`PlacementController.client.luau`) — new client script handling ghost preview, raycasting, and placement input
- **Server placement validation** — `PlaceItem` remote in InventoryService validates item category, CFrame type, range (≤20 studs), and 1s cooldown before spawning
- **Ghost template publishing** — server auto-clones placeable Models from `ServerStorage/ItemTools` to `ReplicatedStorage/PlaceableGhosts` at startup with effects disabled
- **Campfire sitting system** — players auto-sit when idle ≥3 seconds within 10 studs of a placed campfire. Sit animation plays via `SittingAtCampfire` attribute
- **Campfire regen** — health regen (2 HP/s) and energy regen (5 energy/s) while sitting at campfire. Energy regen works even when hungry/thirsty
- **Campfire auto-cleanup** — placed campfires auto-delete after 10 minutes with no player nearby (`_lastOccupiedTime` attribute tracking)
- **Instant hotbar placement** — pressing a hotbar number key for a placeable item immediately enters placement mode (no extra click needed)
- **Inventory "PLACE" button** — placeable items show a "PLACE" button in inventory detail panel instead of "USE"
- **PlaceableModels folder** — `ServerStorage/PlaceableModels/init.meta.json` for Rojo asset persistence
- **Sitting animation** — R15 sit animation (`rbxassetid://101839416066342`) in AssetIds
- **Campfire config** — `GameplayConfig.Campfire` section with sit radius, idle time, regen rates, placement range, and inactive lifetime

### Changed
- `ToolInventoryService` HotbarEquipRequest now handles placeables without equipping a physical Tool (highlights slot only)
- `syncEquippedSlotFromCharacter` preserves placeable slot selection instead of resetting to 0
- `InventoryController` detail panel shows "PLACE" for placeables and fires `StartPlacement` BindableEvent
- `HudController` guards all input during placement mode (`IsPlacementMode` attribute)
- `PlayerStateService` heartbeat loop now includes campfire proximity detection, idle tracking, sit/regen logic, and auto-cleanup sweep
- `PinToHotbar` category gate updated to allow placeables

---

## [0.5.0] - 2026-03-08

### Added
- **Scatter template system** — ScatterSpawnService clones Studio-placed MeshPart/Model templates from `ServerStorage/ScatterModels/` instead of creating placeholder parts. Fallback to coloured placeholders for items without templates
- **Rojo asset persistence** — `init.meta.json` with `ignoreUnknownInstances` in `ServerStorage/ScatterModels/` prevents Rojo from deleting Studio-placed mesh models on sync
- **Consumable eating channel** — 2-second eat channel with chewing sound before item is consumed. Client-side `isEating` flag prevents overlapping eats
- **Server-side eat cooldown** — 2-second cooldown on `UseItem` prevents rapid-fire consumption exploits
- **Water Well script** (`WaterWell.server.luau`) — attaches ProximityPrompt to any Part named "WaterWell" in Workspace; pressing E fully restores thirst via `ConsumeEffect`
- **Chewing sound asset** — added `ChewingSound` to AssetIds for eating feedback

### Changed
- `ScatterSpawnService` now looks up templates via `findTemplate()` in `ServerStorage/ScatterModels/`; wraps bare MeshParts in a Model automatically
- `getZoneBounds()` now filters only `BasePart` children from ScatterZones (previously could pick non-BasePart children like folders)
- `InventoryService` tool building now clones MeshPart templates as the tool Handle directly (no invisible Handle + Weld pattern), with `tool.Grip = CFrame.new(0, -0.4, 0)` for correct hand positioning
- `HudController` eating flow refactored: click starts 2s channel with chewing sound, then fires `UseItem` on completion. Drinks skip chewing sound
- `ItemRegistry` BrownMushroom updated with `meshSize` field for proper tool handle sizing

### Fixed
- Scatter items spawning outside ScatterZones when the folder contained non-BasePart children (e.g. Templates subfolder)
- 1 HP/s health drain caused by thirst reaching 0 (dehydration) — added Water Well for testing thirst refill

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
