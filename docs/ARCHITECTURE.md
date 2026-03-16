# The Counter Earth - System Architecture

## Project Structure

```
src/
├── ReplicatedStorage/Config/       -- Shared configuration (client + server)
│   ├── GameplayConfig.luau         -- Energy, movement, health, credits, hotbar, inventory
│   ├── StatsConfig.luau            -- Hunger, thirst, fatigue, blood bar, poison bar
│   ├── ItemRegistry.luau           -- Item definitions (weight, stackMax, category, etc.)
│   ├── CraftingConfig.luau         -- Hand-craft recipes (station="hand")
│   ├── CookingConfig.luau          -- Campfire cooking recipes (raw → cooked)
│   ├── AssetIds.luau               -- rbxassetid:// mappings for images and sounds
│   └── InventoryTypes.luau         -- Shared type definitions
│
├── ServerScriptService/            -- Server-only scripts
│   ├── PlayerStateService.server.luau    -- Player lifecycle, energy, sprint, survival stats, DataStore
│   ├── InventoryService.server.luau      -- Slot-based inventory, crafting, hotbar pinning, loot bags
│   ├── CampfireService.server.luau       -- Campfire cooking: per-campfire inventory, cook ticks, state sync
│   ├── ToolInventoryService.server.luau  -- World tool pickup, equip/unequip, tool templates
│   ├── ScatterSpawnService.server.luau   -- Scatter item spawning in the world
│   ├── TradingService.server.luau        -- Player-to-player trading
│   ├── PlayerInspectService.server.luau  -- Player inspect: profile data on request
│   ├── EventBridge.luau                  -- ModuleScript: HTTP event dispatcher
│   └── EventBridgeWorker.server.luau     -- Flush loop + init for EventBridge
│
├── StarterPlayer/StarterPlayerScripts/   -- Client scripts
│   ├── HudController.client.luau         -- HUD rendering, hotbar display, campfire cooking UI
│   ├── InventoryController.client.luau   -- Inventory panel, recipe book, drag-and-drop
│   ├── PlacementController.client.luau   -- Ghost preview placement mode for placeables
│   ├── GatherController.client.luau      -- Hit-to-harvest feedback (shake, sound, animation, floating text)
│   ├── LootBagController.client.luau     -- Loot bag countdown timers and death bag beacons
│   └── InspectController.client.luau     -- Player inspect UI, ProximityPrompt on other players
│
assets/
├── raw/
│   ├── textures/mainHUD/           -- Source HUD icon files (health, energy, credit)
│   ├── textures/vignetteEffect.png -- Vignette overlay texture
│   ├── audio/                      -- Source audio files (breathing, heartbeat)
│   └── docs/                       -- This documentation (not synced to Studio)
```

## Sync Setup

- **Rojo 7.6.1** syncs `src/` to Roblox Studio via `default.project.json`
- Binary: `tools/rojo-7.6.1/rojo serve default.project.json`
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
- Profile version: 5
- Auto-saves every 60s when dirty, force-saves on leave and BindToClose
- Saves: credits, energy, health, hunger, thirst, fatigue, blood, poison, bleed stacks, active effect flags, hotbar inventory, slot-based inventory, per-item expiry timestamps, last position
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
- Placement options: `nearWater` (spawn near water edges), `groundSink` (embed in ground), `alignToSlope` (tilt to terrain normal)

**Spawn Process:**
- Raycasts from sky to find ground position within ScatterZones
- Rejects slopes steeper than 25° (surface normal dot product)
- Water-edge items: must be on dry land with water within 12 studs
- Clones Studio-placed templates from `ServerStorage/ScatterModels/` (falls back to colored placeholder parts)
- Templates use `GetBoundingBox()` for accurate vertical positioning

**Respawn:**
- When a model is destroyed (picked up or harvested), `AncestryChanged` triggers a delayed respawn (random delay within `respawnMin`–`respawnMax`)

### 6. Gather Controller (GatherController)

Client-side hit feedback for the harvest system.

**On HarvestResult from server:**
- Plays tool-specific swing animation (knife/pickaxe/axe based on equipped tool kind)
- Shakes the target model (6-frame decaying intensity)
- Plays spatial harvest sound at the node (per-resource: reed has its own sound)
- Shows floating "+N ItemName" text that fades upward over ~0.6s

**On HarvestNotify:** Shows error text near player head (e.g. "You need a knife", "Inventory full!")

### 7. Player Inspect (PlayerInspectService + InspectController)

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

### 8. Loot Bag Controller (LootBagController)

Client-side rendering for loot bag timers and death bag beacons.

**Countdown Timer:** BillboardGui on all loot bags showing remaining time. Updates once per second. Color shifts: white → yellow (≤60s) → red (≤30s).

**Death Beacon (owner only):** Golden neon beam (200 studs tall, 1.5 studs wide), ground glow ring (cylinder), PointLight. Only rendered for the owning player's death bag via `DeathBagBeacon` remote.

**Replication handling:** `waitForHandle()` with 3s timeout for bag PrimaryPart replication. `task.defer` in ChildAdded for attribute replication timing.

### 9. HUD (HudController)

Client-side UI rendering.

**HUD Panel (top-left):**
- Health bar (red), Energy bar (green), Credits display
- Survival stat bars: Hunger (orange), Thirst (blue), Fatigue (purple), Blood (red), Poison (green)
- Status indicators: bleeding (with BloodIcon), poisoned (with PoisonIcon), pulsing badges
- Particle effects on character: blood drip particles while bleeding, green toxic aura while poisoned
- Icons from AssetIds with fallback text
- Disables default Roblox health bar and backpack GUI

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

### 10. Inventory Controller (InventoryController)

Client-side inventory panel with drag-and-drop.

**Tabs:** ITEMS | RECIPES | CHARACTER

**ITEMS tab:** Grid display of inventory slots, detail panel with USE/PLACE/HOTBAR/SPLIT/DROP actions.

**RECIPES tab:** Unified recipe list from CraftingConfig + CookingConfig.
- Filter bar: ALL / HAND / CAMPFIRE
- Hand-craft recipes: interactive with CRAFT button and ingredient availability ([ok]/[need])
- Station recipes: read-only with input → output + cook time display
- Station badges: HAND (blue) / CAMPFIRE (orange) on each row

**CHARACTER tab:** Equipment slots and RPG stat block.

**Drag-and-Drop:**
- Inventory slot → Hotbar slot: fires `PinToSpecificSlot` with target slot number
- Inventory slot → Inventory slot: fires `SwapSlots`
- Inventory slot → Campfire input slot: fires `CampfireAddItem` (cross-ScreenGui via ObjectValue ref)
- Inventory slot → empty space: fires `DropItem` (drops to world)
- Visual ghost icon follows cursor during drag

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

## External Event Bridge (EventBridge)

Pushes game events to the external website/Discord bot via HttpService.

**Module (`EventBridge.luau`):**
- `EventBridge.fire(eventType, player?, data?)` — fire-and-forget from any server script
- Immediate events (death, trade, join, leave) send instantly via `task.spawn`
- Batched events (craft, harvest, consume) queue and flush every 5s
- All HTTP calls wrapped in `pcall` — failures never break gameplay
- API key read from `ServerStorage.Secrets.WebhookApiKey` (not in git)
- Disabled in Studio by default (`EnableInStudio = false`)

**Worker (`EventBridgeWorker.server.luau`):**
- Calls `EventBridge.init()`, runs periodic flush loop, `BindToClose` final flush

**Config:** `GameplayConfig.EventBridge` — endpoint URL, flush interval, batch sizes, immediate event list

**Payload format:** JSON POST to endpoint with `X-Api-Key` header. Envelope contains `serverJobId`, `placeId`, `timestamp`, and `events` array.

**Events fired:**
| Event | Source Script | Priority |
|---|---|---|
| `player_join` | PlayerStateService | Immediate |
| `player_leave` | PlayerStateService | Immediate |
| `player_death` | PlayerStateService | Immediate |
| `trade_complete` | TradingService | Immediate |
| `craft_item` | InventoryService | Batched |
| `harvest` | InventoryService | Batched |
| `item_consume` | InventoryService | Batched |

---

## Security Model

- Server validates ALL remote event inputs (type checks, range clamps)
- `sanitizeItemId()` used everywhere item names cross trust boundaries (40 char limit, alphanumeric+underscore+dash+space only)
- Client is never trusted — all inventory mutations happen server-side
- Tool instances are cloned from server-side templates, not from client data
