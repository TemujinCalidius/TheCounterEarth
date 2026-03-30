# The Counter Earth - System Architecture

## Project Structure

The codebase uses a **multi-place architecture**. Shared core code lives in `src/shared/` and is included by every place via Rojo project files. Per-place scripts live in `src/places/<place>/`.

```
src/
├── shared/                              -- Core code shared across all places
│   ├── config/                          -- Shared configuration (client + server)
│   │   ├── GameplayConfig.luau          -- Energy, movement, health, credits, hotbar, inventory
│   │   ├── StatsConfig.luau             -- Hunger, thirst, fatigue, blood bar, poison bar
│   │   ├── ItemRegistry.luau            -- Item definitions (weight, stackMax, category, etc.)
│   │   ├── CraftingConfig.luau          -- Hand-craft recipes (station="hand")
│   │   ├── CookingConfig.luau           -- Campfire cooking recipes (raw → cooked)
│   │   ├── AchievementConfig.luau       -- Achievement definitions, counters, event mappings
│   │   ├── LoreConfig.luau             -- Lore entry definitions (title, body, category, trigger)
│   │   ├── AssetIds.luau                -- rbxassetid:// mappings for images and sounds
│   │   └── InventoryTypes.luau          -- Shared type definitions
│   │
│   ├── server/                          -- Server-only scripts (all places)
│   │   ├── PlayerStateService.server.luau    -- Player lifecycle, energy, sprint, survival stats, DataStore
│   │   ├── InventoryService.server.luau      -- Slot-based inventory, crafting, hotbar pinning, loot bags
│   │   ├── CampfireService.server.luau       -- Campfire cooking: per-campfire inventory, cook ticks, state sync
│   │   ├── ToolInventoryService.server.luau  -- World tool pickup, equip/unequip, tool templates
│   │   ├── CombatService.server.luau         -- Weapon-only melee attacks, target search
│   │   ├── BowService.server.luau            -- Ranged bow combat, draw scaling, arrow physics
│   │   ├── ButcherService.server.luau        -- Carcass skinning and butchering
│   │   ├── ZombieService.server.luau         -- Hostile NPC AI, zone spawning, combat
│   │   ├── TradingService.server.luau        -- Player-to-player trading
│   │   ├── PlayerInspectService.server.luau  -- Player inspect: profile data on request
│   │   ├── ToolPlaceholders.server.luau      -- Runtime placeholder Tool models (until Studio meshes exist)
│   │   ├── AvatarRigService.server.luau      -- RightHand Motor6D for tool attachment
│   │   ├── AchievementService.server.luau    -- Achievement tracking, counters, unlocks, login streaks
│   │   ├── LoreService.server.luau          -- Lore discovery tracking, DataStore persistence
│   │   ├── EventBridge.luau                  -- ModuleScript: HTTP event dispatcher (+ onFire hook)
│   │   ├── EventBridgeWorker.server.luau     -- Flush loop + init for EventBridge
│   │   └── WaterWell.server.luau             -- Water well thirst refill
│   │
│   ├── client/                          -- Client scripts (all places)
│   │   ├── HudController.client.luau         -- HUD rendering, hotbar display, button bar, campfire cooking UI
│   │   ├── PanelManager.luau                 -- ModuleScript: panel mutual exclusivity, animations, mouse unlock
│   │   ├── InventoryController.client.luau   -- Inventory panel (ITEMS + RECIPES tabs), drag-and-drop
│   │   ├── CharacterPanelController.client.luau  -- Character panel (equipment slots, RPG stats)
│   │   ├── AchievementPanelController.client.luau -- Achievement panel (category filter, progress grid)
│   │   ├── CodexController.client.luau       -- Codex panel (lore entry browser with categories)
│   │   ├── LoreToastController.client.luau   -- Lore discovery toast notifications
│   │   ├── PlacementController.client.luau   -- Ghost preview placement mode for placeables
│   │   ├── BowController.client.luau         -- Bow aiming, draw UI, crosshair, mobile buttons
│   │   ├── LootBagController.client.luau     -- Loot bag countdown timers and death bag beacons
│   │   ├── InspectController.client.luau     -- Player inspect UI, ProximityPrompt on other players
│   │   ├── BoneTracker.client.luau           -- Tracks hand bones for all characters (local + remote)
│   │   ├── LoadingScreen.client.luau         -- Loading screen with scatter-ready fade
│   │   └── AchievementToastController.client.luau -- Achievement unlock toast notifications
│   │
│   ├── character/                       -- Character scripts (all places)
│   │   └── AvatarSetup.client.luau      -- HipHeight, drift correction, freefall suppression
│   │
│   └── modules/                         -- Shared modules
│       └── TooltipModule.luau           -- Tooltip rendering
│
├── places/                              -- Per-place scripts
│   ├── sandbox/                         -- Open-world sandbox
│   │   ├── server/
│   │   │   ├── ScatterSpawnService.server.luau   -- Scatter item spawning in ScatterZones
│   │   │   ├── AnimalService.server.luau         -- Deer AI (idle/wander/flee/dead)
│   │   │   └── TreeService.server.luau           -- Tree lifecycle: fell, stump, trunk, regrowth
│   │   └── client/
│   │       └── GatherController.client.luau      -- Hit-to-harvest feedback (shake, sound, animation)
│   │
│   └── hospital/                        -- Hospital tutorial place
│       ├── server/
│       │   └── PlaceInit.server.luau             -- Fires ScatterReady for loading screen
│       └── client/
│           └── FirstPersonCamera.client.luau     -- First-person camera lock + crosshair UI
│
assets/
├── raw/
│   ├── textures/mainHUD/           -- Source HUD icon files (health, energy, credit)
│   ├── textures/vignetteEffect.png -- Vignette overlay texture
│   ├── audio/                      -- Source audio files (breathing, heartbeat)
│   └── docs/                       -- This documentation (not synced to Studio)
```

## Sync Setup

- **Rojo 7.6.1** syncs `src/` to Roblox Studio via per-place project files
- **Sandbox:** `tools/rojo-7.6.1/rojo serve sandbox.project.json`
- **Hospital:** `tools/rojo-7.6.1/rojo serve hospital.project.json`
- Stop one before starting the other (they share the default port 34872)
- Studio plugin must match version 7.6.1
- `assets/raw/` is NOT synced — local-only reference files and documentation

---

## Core Systems

### 1. Player State (PlayerStateService)

The central server authority for player data. Owns the `Remotes` folder.

**Responsibilities:**
- Energy: drains on sprint (16/s) and jump (10 per jump), regens when standing still (14/s after 0.75s delay)
- At 0 energy: jumping disabled, walk speed drops to exhausted speed (6)
- Health: loaded from DataStore, no auto-regen (destroys the default Health regen script)
- Survival stats: hunger, thirst, fatigue — each drains over time with configurable rates
- Blood bar (100 → 0): drains while IsBleeding, regens when wound clots (gated by hunger/thirst). At 0: severe health drain
- Poison bar (0 → 100): fills while IsPoisoned, decays when source removed. Health drain scales with level
- Bleed stacking: multiple wounds = faster blood drain. Natural clotting removes one stack per NaturalStopSeconds
- Weight-based speed penalty: SlowThreshold (80%) -> CrawlThreshold (100%) -> StopThreshold (150%)
- Bedroll respawn: tracks bedroll placement per player, teleports to bedroll on death respawn
- Relog teleport: saves player position to DataStore, teleports back on rejoin (one-time use)
- Campsite cleanup: paired campfire+bedroll stays alive while owner is online; otherwise 10-min inactivity timer
- Credits: DataStore persistence with legacy store migration
- RPG stat attributes (STR, AGI, CON, WIS, INT, CHA) — initialized to 0, reserved for future SkillSystem

**DataStore:**
- Store name: `PlayerProfileV2`, key format: `player_{userId}`
- Profile version: 7
- Auto-saves every 60s when dirty, force-saves on leave and BindToClose
- Saves: credits, energy, health, hunger, thirst, fatigue, blood, poison, bleed stacks, active effect flags, hotbar inventory, slot-based inventory, per-item expiry timestamps, last position, achievements, discoveredLore
- `lastPosition` saved as `{x,y,z}` from HumanoidRootPart on save; used for relog teleport (one-time)
- `invSlots[].expiries` saved as array of `os.time()` timestamps per slot

**Remote Events (created here):**
- `SprintIntent` — client tells server sprint on/off
- `HotbarEquipRequest` — client requests equip by slot number
- `HotbarAttackRequest` — reserved for attack input

**BindableEvents (ServerStorage/ServerBindables):**
- `ConsumeEffect` — InventoryService fires consume effects (hunger/thirst/energy/blood/poison deltas, stopBleed/stopPoison)
- `ApplyStatusEffect` — weapon scripts / test parts fire `"bleed"`, `"poison"`, `"clearBleed"`, `"clearPoison"`

**BindableFunctions (ServerStorage/ServerBindables):**
- `InventoryAdd` — CampfireService calls to add items to player inventory
- `InventoryRemove` — CampfireService calls to remove items from player inventory
- `InventoryGetQty` — CampfireService calls to check player item quantities

### 2. Inventory (InventoryService)

Slot-based inventory system using player attributes.

**Data Model:**
- `InvSlot_N` (string attribute) — itemId at slot N, nil if empty
- `InvQty_N` (number attribute) — quantity at slot N
- `InvExpires_N` (string attribute) — comma-separated `os.time()` expiry timestamps, sorted ascending. One per item in the stack.
- `MaxInvSlots` (number attribute) — caps how many slots exist (default: 5 pocket slots)
- `CarryWeight` / `MaxCarryWeight` — weight tracking attributes

**Operations:**
- `addQty()` — adds items, first filling partial stacks then empty slots; checks weight limit. Sets per-item expiry timestamps for perishable items.
- `removeQty()` — removes items from highest slots first, trims oldest expiry timestamps
- `refreshWeight()` — recalculates CarryWeight from all slots

**Spoilage System:**
- Per-item expiry timestamps stored as comma-separated string in `InvExpires_N`
- Heartbeat loop (every 10s): scans all players' slots, counts expired timestamps, converts to `spoiled_food`
- Handles offline catch-up: multiple items can spoil in a single tick
- Split preserves timestamps: oldest N go to new slot
- Merge combines and re-sorts timestamp lists
- DataStore: saved as `expiries` array in invSlots entries

**Bedroll Placement:**
- Must be placed within `RequiredCampfireRadius` of an existing campfire
- One bedroll per player: placing a new one destroys the old one

**Remote Events (created here):**
- `UseItem` — consume one stack item (applies health/hunger/thirst/fatigue/energy effects)
- `CraftItem` — hand-craft a recipe (checks ingredients, removes them, adds output)
- `SplitStack` — split a slot into two
- `SwapSlots` — swap two inventory slots (drag-and-drop reorder)
- `DropItem` — drop items from a slot as a loot bag in the world
- `PinToHotbar` — pin an item to the first free hotbar slot
- `PinToSpecificSlot` — pin an item to a specific hotbar slot (drag from inventory)
- `UnpinFromHotbar` — unpin an item from a hotbar slot
- `SwapHotbarSlots` — swap two hotbar slots (drag-to-reorder)
- `PlaceItem` — place a placeable item in the world (validates range, cooldown)
- `OpenCampfire` — client requests campfire inventory state
- `CampfireState` — server broadcasts campfire state to nearby clients
- `CampfireAddItem` — add item from player inventory to campfire input
- `CampfireTakeItem` — take item from campfire slot to player inventory
- `HarvestHit` — client fires when left-clicking near a harvest node
- `HarvestResult` — server sends yield info (model, qty, displayName, nodeDestroyed) for client feedback
- `HarvestNotify` — server sends error messages ("You need a knife", "Inventory full!")
- `DeathBagBeacon` — server notifies bag owner to render beacon

**BindableFunctions (ServerStorage/ServerBindables):**
- `InventoryDumpAll` — PlayerStateService calls on death to dump all inventory into death loot bag

**Loot Bags:**
- Dropped on DropItem or death
- Model with IntValue children for each item stack
- ProximityPrompt (E key) to loot
- Death bags: `_isDeathBag`, `_OwnerUserId`, `_SpawnTime`, `_Lifetime` attributes
- Auto-despawn after Lifetime seconds (default 300s for death bags)

**Scatter Items:**
- Models in Workspace with `_ScatterItem` attribute set to itemId
- Instant-pickup items (twig, rock, mushroom): InventoryService auto-adds ProximityPrompts
- Harvest nodes (reed, future ores): use left-click hit-to-harvest system, no ProximityPrompt

**Hit-to-Harvest System:**
- Resource nodes have `_NodeHealth`, `_HarvestYieldMin`/`Max`, `_HitCooldown` attributes
- Client detects nearest harvest node within 8 studs on left-click, fires `HarvestHit`
- Server validates range, tool requirement, cooldown, then deducts 1 HP and gives random yield
- If inventory full, hit is blocked (node keeps HP). Node destroyed at 0 HP → respawn via ScatterSpawnService
- Target locking: client stays locked to one node until it's destroyed or out of range
- Remotes: `HarvestHit` (client→server), `HarvestResult` (server→client, yield + feedback), `HarvestNotify` (server→client, error messages)

**Death Loot Bags:**
- On death, `InventoryDumpAll` BindableFunction dumps all inventory into a death loot bag
- Death bags have `_isDeathBag`, `_OwnerUserId`, `_SpawnTime`, `_Lifetime` attributes
- `DeathBagBeacon` remote notifies the owner's client to render a golden beacon
- LootBagController renders countdown timer on all bags, beacon only for owner's death bags

### 3. Tool Inventory (ToolInventoryService)

Bridges inventory items to Roblox Tool instances.

**Responsibilities:**
- World tools (Tool instances in Workspace): adds ProximityPrompt, CanTouch=false on handle
- On pickup: adds to inventory slots AND auto-pins to hotbar; clones template to Backpack
- Tool templates stored in `ServerStorage/ItemTools` (auto-captured from first world pickup)
- On character respawn: re-grants Tool instances for all pinned hotbar slots
- Equip/unequip via `HotbarEquipRequest`: toggle equip (same slot = unequip)
- Syncs `HotbarEquippedSlot` attribute from character's equipped tool

### 4. Campfire Cooking (CampfireService)

ARK/Minecraft-style station cooking. Campfires act as shared containers — any player nearby can interact.

**Per-campfire state:**
- `input` — item stack in the input slot (itemId + qty)
- `output` — cooked item stack in the output slot (itemId + qty)
- `cookProgress` / `cookDuration` — seconds into current cook / total required

**Cooking loop (Heartbeat):**
- For each campfire with non-empty input: increment cookProgress by dt
- When cookProgress >= cookDuration: move 1 unit from input to output, reset progress
- If output slot at max stack: cooking pauses until output is taken
- Non-cookable items sit in input without cooking

**Viewer tracking:**
- `campfireViewers[model]` tracks which players have the UI open
- Server broadcasts `CampfireState` to all viewers on state change

**Campfire lifecycle:**
- Registered when `_PlacedItem = "campfire"` model appears in Workspace
- ProximityPrompt added by InventoryService on placement
- On `model.Destroying`: drops loot bag with remaining input/output items

**Recipes:**
- Defined in `CookingConfig.luau` — key is raw item ID, value is `{ output, cookSeconds, station, skillLevel, displayName }`

### 5. Scatter Spawn (ScatterSpawnService)

Spawns floor-scatter items in the world within ScatterZones.

**Scatter Definitions:**
- Each item type has: `maxCount`, `respawnMin`/`Max`, visual config, optional template variants
- Harvest nodes add: `nodeHealth`, `harvestYield` (min/max), `hitCooldown`, `requireTool`
- Tree entries add: `isTree`, `minSpacing`, particle emitters (leaf + wood chip)
- Placement options: `nearWater` (spawn near water edges), `groundSink` (embed in ground), `alignToSlope` (tilt to terrain normal)

**Spawn Process:**
- Raycasts from sky to find ground position within ScatterZones
- RaycastParams exclude ScatterZones folder and Scatter folder so items land on terrain
- Rejects slopes steeper than 25° (surface normal dot product)
- Water-edge items: must be on dry land with water within 12 studs
- Clones Studio-placed templates from `ServerStorage/ScatterModels/` (falls back to colored placeholder parts)
- Templates use `GetBoundingBox()` for accurate vertical positioning
- Trees enforce `minSpacing` (12 studs) — rejects positions too close to existing trees

**Respawn:**
- When a model is destroyed (picked up or harvested), `AncestryChanged` triggers a delayed respawn (random delay within `respawnMin`–`respawnMax`)
- Trees skip AncestryChanged respawn — TreeService manages full lifecycle including stump-based regrowth

### 6. Tree Harvesting (TreeService)

Multi-phase tree lifecycle inspired by Medieval Dynasty — fell the tree, section the trunk, pick up logs.

**Lifecycle (6 phases):**
1. **Standing** — 8 HP, no yield; player chops with axe, tree shakes + leaf/wood chip particles
2. **Falling** — server Heartbeat tween rotates tree 90° away from player over 2s; deals 20 dmg on contact
3. **Stump + Trunk** — original tree destroyed; stump placed at base; brown trunk Part lying on ground with 2 cut point markers
4. **Trunk Sectioning** — cut point 1: trunk shrinks from that end, 1 log spawns; cut point 2: trunk destroyed, 2 logs spawn
5. **Log Pickup** — 3 oak_log segments with ProximityPrompt (E key); auto-despawn after 10 min
6. **Regrowth** — stump timer (1–1.5 hours) → clone random tree template → destroy stump

**Key attributes:** `_IsTree`, `_TreePhase` (standing/falling/trunk), `_CutPoint`, `_CutPointIndex`, `_TrunkSegment`, `_TreeStump`

**Cut points:** Standalone Models in Scatter folder (not children of trunk) so client harvest scan finds them. Linked to trunk via `TrunkRef` ObjectValue. Invisible hit target Part + BillboardGui with "Chop Here" marker.

**Integration:** InventoryService checks `_IsTree` on harvest — fires `TreeFelled` BindableEvent instead of normal destroy path. TreeService listens and runs the fell sequence.

**Config:** `GameplayConfig.Tree` — node health, hit cooldown, cut point hits, fall duration/damage, log despawn, respawn timers, spacing.

**Placeholder tools:** `ToolPlaceholders.server.luau` auto-generates stone_axe, stone_pickaxe, stone_knife Tool instances with welded geometric parts. Skipped if Studio model already exists in `ServerStorage/ItemTools`.

### 7. Gather Controller (GatherController)

Client-side hit feedback for the harvest system.

**On HarvestResult from server:**
- Plays tool-specific swing animation (knife/pickaxe/axe based on equipped tool kind)
- Shakes the target model (6-frame decaying intensity)
- Plays spatial harvest sound at the node (per-resource: reed has its own sound)
- Shows floating "+N ItemName" text that fades upward over ~0.6s

**On HarvestNotify:** Shows error text near player head (e.g. "You need a knife", "Inventory full!")

### 8. Player Inspect (PlayerInspectService + InspectController)

Inspect other players' profiles via ProximityPrompt.

**Server (PlayerInspectService):**
- Creates `InspectRequest` (Client→Server) and `InspectData` (Server→Client) remotes
- Accepts Player instance or UserId, validates range (InteractRange), 1s cooldown
- Reads target's live attributes: health (from Humanoid), hunger, thirst, fatigue, credits, equipped item, survival time
- Derives wealth tier from credits (Destitute/Poor/Comfortable/Wealthy/Elite)
- Returns payload to requesting client

**Client (InspectController):**
- Attaches "Inspect" ProximityPrompt (G key) to other players' Head parts
- `Exclusivity = AlwaysShow` so it renders alongside other prompts
- On trigger: fires `InspectRequest` with target Player instance
- On data received: shows inspect panel with stat bars, wealth tier, survival time, equipped item
- TRADE button: fires `TradeInitiate` with empty offer to start trade from inspect screen
- Panel is draggable and position persists across sessions

### 9. Loot Bag Controller (LootBagController)

Client-side rendering for loot bag timers and death bag beacons.

**Countdown Timer:** BillboardGui on all loot bags showing remaining time. Updates once per second. Color shifts: white → yellow (≤60s) → red (≤30s).

**Death Beacon (owner only):** Golden neon beam (200 studs tall, 1.5 studs wide), ground glow ring (cylinder), PointLight. Only rendered for the owning player's death bag via `DeathBagBeacon` remote.

**Replication handling:** `waitForHandle()` with 3s timeout for bag PrimaryPart replication. `task.defer` in ChildAdded for attribute replication timing.

### 10. HUD (HudController)

Client-side UI rendering.

**HUD Panel (top-left):**
- Health bar (red), Energy bar (green), Credits display
- Survival stat bars: Hunger (orange), Thirst (blue), Fatigue (purple), Blood (red), Poison (green)
- Status indicators: bleeding (with BloodIcon), poisoned (with PoisonIcon), pulsing badges
- Particle effects on character: blood drip particles while bleeding, green toxic aura while poisoned
- Icons from AssetIds with fallback text
- Disables default Roblox health bar and backpack GUI

**Button Bar (right edge, vertical):**
- 4 buttons: Inventory, Character, Achievements, Codex
- Per-panel accent colors, hover/active states, 80% icon fill
- Desktop: vertical strip above hotbar on right edge; Mobile: adapted layout
- Each button toggles its panel via PanelManager

**Hotbar (bottom-center):**
- 9 slots (keys 1-9), reads `HotbarSlot1`–`HotbarSlot9` attributes
- Active slot highlighted based on `HotbarEquippedSlot` attribute
- Toggle equip: pressing same key unequips
- Drag-to-reorder: drag a hotbar slot onto another to swap (fires `SwapHotbarSlots`)

**Audio:**
- Breathing loop: volume and speed scale with energy ratio
- Heartbeat loop: triggers below 40% health, volume/speed scale with health ratio

**Visual Effects:**
- Vignette overlay: opacity increases as energy drops (darkens screen edges)

### 11. Panel Manager (PanelManager)

Shared ModuleScript that coordinates all full-screen panels.

**Responsibilities:**
- Mutual exclusivity: only one panel open at a time (opening one closes others)
- Open/close animations (slide or fade)
- Mouse unlock in first-person mode when a panel is open
- Crosshair hiding while panels are visible
- Click-outside-to-close behavior
- Registered panels: Inventory, Character, Achievements, Codex

### 12. Inventory Panel (InventoryController)

Client-side inventory panel with drag-and-drop. Registered with PanelManager.

**Tabs:** ITEMS | RECIPES

**ITEMS tab:** Grid display of inventory slots, detail panel with USE/PLACE/HOTBAR/SPLIT/DROP actions.

**RECIPES tab:** Unified recipe list from CraftingConfig + CookingConfig.
- Filter bar: ALL / HAND / CAMPFIRE
- Hand-craft recipes: interactive with CRAFT button and ingredient availability ([ok]/[need])
- Station recipes: read-only with input → output + cook time display
- Station badges: HAND (blue) / CAMPFIRE (orange) on each row

**Drag-and-Drop:**
- Inventory slot → Hotbar slot: fires `PinToSpecificSlot` with target slot number
- Inventory slot → Inventory slot: fires `SwapSlots`
- Inventory slot → Campfire input slot: fires `CampfireAddItem` (cross-ScreenGui via ObjectValue ref)
- Inventory slot → empty space: fires `DropItem` (drops to world)
- Visual ghost icon follows cursor during drag

### 13. Character Panel (CharacterPanelController)

Dedicated panel for equipment and RPG stats. Registered with PanelManager.

**Contents:**
- Equipment slots (head, chest, legs, feet, weapon, offhand)
- RPG stat block (STR, AGI, CON, WIS, INT, CHA)
- Previously the CHARACTER tab inside InventoryController; now its own panel

### 14. Achievement Panel (AchievementPanelController)

Dedicated panel for achievement browsing. Registered with PanelManager.

**Contents:**
- Category filter bar (ALL + per-category buttons)
- Scrollable grid of achievement cards with icon, name, progress bar (e.g. "5/10"), green check for unlocked
- Previously the ACHIEVEMENTS tab inside InventoryController; now its own panel

### 15. Codex & Lore System

Lore discovery and browsing system. Player finds lore entries through exploration; entries persist in DataStore.

**Server (`LoreService.server.luau`):**
- Tracks discovered lore per player in `discoveredLore` set (DataStore profile v7)
- `DiscoverLore` RemoteEvent: client or server triggers discovery
- `LoreDiscovered` RemoteEvent: server confirms discovery to client (triggers toast)
- `GetDiscoveredLore` RemoteFunction: client requests full discovered set on join
- Fires `lore_discovered` event via EventBridge

**Config (`LoreConfig.luau`):**
- Lore entry definitions: key, title, body text, category, area, optional trigger conditions
- Categories group entries for Codex browsing (e.g. Environment, Characters, Events)

**Client (`CodexController.client.luau`):**
- Codex panel registered with PanelManager
- Category sidebar + entry list + detail view
- Undiscovered entries shown as locked/greyed out
- Discovered entries show full title and body text

**Client (`LoreToastController.client.luau`):**
- Toast notification on lore discovery (slides in, holds, fades out)
- Similar pattern to AchievementToastController

---

## Communication Flow

```
Client                          Server
──────                          ──────
HudController
  ├─ reads player attributes    PlayerStateService
  │   (Energy, Health, etc.)      ├─ manages attributes
  ├─ key 1-9 → HotbarEquipRequest → ToolInventoryService (equip/unequip)
  └─ drag hotbar → SwapHotbarSlots → InventoryService (swap hotbar)

InventoryController
  ├─ reads InvSlot_N / InvQty_N PlayerStateService (sets on load)
  ├─ drag to hotbar → PinToSpecificSlot → InventoryService
  ├─ drag between slots → SwapSlots → InventoryService
  └─ drag to empty → DropItem → InventoryService → creates loot bag
```

---

## Coordinate Space Notes (Drag-and-Drop)

Roblox has a ~30px GUI inset at the top (topbar/menu). This affects coordinate systems:

- `UserInputService:GetMouseLocation()` — returns screen-space coords INCLUDING the inset
- `input.Position` (from InputBegan/InputChanged/InputEnded) — returns raw screen coords WITHOUT the inset
- `AbsolutePosition` on GUI elements — matches raw screen coords (no inset)
- `ScreenGui` with `IgnoreGuiInset = false` (default) — Position space starts BELOW the inset
- `ScreenGui` with `IgnoreGuiInset = true` — Position space matches `GetMouseLocation()`

**Solution used:**
- Drag ghost icons are parented to a dedicated `ScreenGui` with `IgnoreGuiInset = true` and `DisplayOrder = 100`
- Ghost position uses `GetMouseLocation()` directly (no offset correction needed)
- Hit detection for drop targets uses `input.Position` to match `AbsolutePosition` coordinate space

---

## Config Reference

All gameplay values live in `GameplayConfig.luau` — never hardcoded in scripts.

| System | Key Values |
|--------|-----------|
| Energy | Max=100, SprintDrain=16/s, JumpCost=10, Regen=14/s, RegenDelay=0.75s, MinToJump=10 |
| Movement | Walk=16, Sprint=24, Exhausted=6, JumpPower=50 |
| Hotbar | 9 slots |
| Inventory | PocketSlots=5, BasePocketWeight=5kg |
| Weight | Slow@80%, Crawl@100%, Stop@150% |
| Death Bag | MaxWeight=999 (no limit), Lifetime=300s |
| Bedroll | RequiredCampfireRadius=15, KeepCampfireAliveRadius=15 |

Survival stat values live in `StatsConfig.luau` (hunger, thirst, fatigue drain rates, empty penalties, etc.).

---

## Custom Avatar & Tool Attachment

Single-mesh Mixamo avatars need special handling for tool attachment since standard R15 Motor6Ds don't exist.

**Server (`AvatarRigService.server.luau`):** Creates a `RightHandJoint` Motor6D between `HumanoidRootPart` and a transparent `RightHand` Part on each character spawn. This lets Roblox's built-in `humanoid:EquipTool()` work.

**Client (`BoneTracker.client.luau`):** Runs on each client, tracking the `mixamorig:RightHand` bone inside the `Base_Avatar` MeshPart for ALL visible characters (local + remote). Updates `Motor6D.C0` every `PreRender` frame so equipped tools follow the hand animation with zero visual lag.

**Client (`AvatarSetup.client.luau`):** Local-player-only setup: HipHeight adjustment, movement drift correction (max friction + active sideways velocity dampening to eliminate ice-skating on direction changes), and jump freefall suppression for single-mesh avatars.

**Config:** `GameplayConfig.Avatar` — `HandBoneName`, `MeshPartName`, `HipHeight`

---

## External Event Bridge (EventBridge)

Pushes game events to the external website/Discord bot via HttpService.

**Module (`EventBridge.luau`):**
- `EventBridge.fire(eventType, player?, data?)` — fire-and-forget from any server script
- Immediate events (death, trade, join, leave) send instantly via `task.spawn`
- Batched events (craft, harvest, cook, consume) queue and flush every 5s
- All HTTP calls wrapped in `pcall` — failures never break gameplay
- API key read from `ServerStorage.Secrets.WebHookApiKey` (not in git)
- Disabled in Studio by default (`EnableInStudio = false`)

**Worker (`EventBridgeWorker.server.luau`):**
- Calls `EventBridge.init()`, runs periodic flush loop, `BindToClose` final flush

**Config:** `GameplayConfig.EventBridge` — endpoint URL, flush interval, batch sizes, immediate event list

**Payload format:** JSON POST to endpoint with `X-Api-Key` header. Envelope contains `serverJobId`, `placeId`, `timestamp`, and `events` array.

**Events fired:**
| Event | Source Script | Priority | Extra Fields |
|---|---|---|---|
| `player_join` | PlayerStateService | Immediate | playerCount |
| `player_leave` | PlayerStateService | Immediate | survivalSeconds, playerCount |
| `player_death` | PlayerStateService | Immediate | cause, killerUserId, killerName, survivalSeconds, position |
| `trade_complete` | TradingService | Immediate | offerA/offerB with itemName, partnerUserId |
| `craft_complete` | InventoryService | Batched | itemId, itemName |
| `harvest_complete` | InventoryService | Batched | itemId, itemName |
| `cook_complete` | CampfireService | Batched | itemId, itemName |
| `item_consume` | InventoryService | Batched | itemId |
| `item_dropped` | InventoryService | Batched | itemId, qty |
| `tool_broken` | InventoryService | Batched | itemId, itemName |
| `spoilage_lost` | InventoryService | Batched | totalSpoiled |
| `inventory_full_reject` | InventoryService | Batched | itemId |
| `first_campfire` | InventoryService | Batched | — (per-session milestone) |
| `first_craft` | InventoryService | Batched | itemId, itemName |
| `bedroll_placed_near_others` | InventoryService | Batched | nearbyBedrolls |
| `starvation_close_call` | PlayerStateService | Batched | stat (hunger/thirst) |
| `campfire_session` | PlayerStateService | Batched | nearbyPlayers |
| `achievement_unlocked` | AchievementService | Immediate | key, name, icon, category, counterValue, totalUnlocked, totalAchievements |
| `lore_discovered` | LoreService | Immediate | loreKey, title, category, area, totalDiscovered |

**PvP damage tagging:** Weapon scripts should fire `ServerBindables.PvPDamageTag:Fire(victimPlayer, attackerPlayer)` when dealing damage. This tags the victim so `player_death` includes killer info.

**cook_complete attribution:** Fires for the player who last added raw food to the campfire input slot (`lastAddedBy`). Falls back to the campfire placer if the adder has left the server.

---

## Achievement System

Event-driven achievement tracking. The game is the single source of truth — the web/Discord listens for `achievement_unlocked` events. Achievement definitions live in `AchievementConfig.luau`.

**Server (`AchievementService.server.luau`):**
- Registers `EventBridge.onFire` hook to auto-increment counters from existing game events (no changes to source scripts needed)
- Checks all achievements sharing a counter whenever it changes; awards unlocks at threshold
- Fires `AchievementUnlocked` RemoteEvent to client (toast) + `EventBridge.fire("achievement_unlocked")` to web
- Login streak: compares UTC date on join. Consecutive day → increment, gap → reset to 1
- Playtime: 60s tick loop increments `playtime_total` for all online players
- Credits peak: watches `Credits` attribute changes, stores highest-ever value
- BindableFunctions (`AchievementLoad`/`AchievementSave`/`AchievementGetState`) for PlayerStateService integration

**Config (`AchievementConfig.luau`):** Shared between server and client. Defines achievements (key, name, icon, category, counter, threshold, optional `badgeId` for Roblox Badge integration), counter names, event-to-counter mappings with conditions, and lookup tables (ByCounter, ByKey).

**DataStore (profile v7):** `achievements = { counters = {}, unlocked = { key → timestamp }, loginStreak = { lastLoginDate, currentStreak, longestStreak } }`. ~2-3KB added per profile. Also stores `discoveredLore` set for lore system.

**Client toast (`AchievementToastController.client.luau`):** Gold-accented 300×70px frame slides in from top-right on unlock, holds 4s, fades out. Queue system for multiple unlocks.

**Achievement Panel (`AchievementPanelController.client.luau`):** Dedicated panel (registered with PanelManager) with category filter bar and scrollable grid of achievement cards showing icon, name, progress (e.g. "5/10"), and green check for unlocked.

**Inspect panel:** Shows "X/N — Most Recent Achievement" row on other players' inspect cards.

---

## Security Model

- Server validates ALL remote event inputs (type checks, range clamps)
- `sanitizeItemId()` used everywhere item names cross trust boundaries (40 char limit, alphanumeric+underscore+dash+space only)
- Client is never trusted — all inventory mutations happen server-side
- Tool instances are cloned from server-side templates, not from client data
