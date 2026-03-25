# The Counter Earth - Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

---

## [0.23.0] - Zombie NPC system

### Added
- **ZombieService** — hostile NPC system with zone-based spawning, AI state machine (idle → wander → chase → attack → dead), and per-zombie coroutine AI
- **9 zombie animations** — regular idle, crawling idle, standup from crawl, slow walk, scream on detection, run chase, melee attack, and 2 random death animations
- **5 positional sounds** — 2 idle groans, detection scream, attack sound, death sound
- **Zombie combat** — detects players within 30 studs, chases at run speed, melee attacks with damage and cooldown, leash radius to prevent infinite chase
- **Corpse fade** — zombie body persists after death, then fades out over 1 second before despawning
- **NPC damage attribution** — `NpcDamageTag` BindableEvent tracks zombie damage so death cause displays correctly
- **ZombieZones** — configurable spawn zones with `MaxZombies` and `ZombieType` attributes for variant support

### Changed
- **CombatService** — `findNearestTarget()` now searches `Workspace/Zombies` and `Workspace/Animals` subfolders (fixes melee weapons not hitting subfolder NPCs)

### Fixed
- **Melee target search** — weapons could not hit deer or any NPC in subfolders; now searches all NPC folders

---

## [0.22.2] - Bow & arrow meshes, deer death sound, asset preloading

### Added
- **Primitive bow mesh** — replaces placeholder model, grip CFrame configured in ItemRegistry
- **Stone arrow mesh** — projectile cloned from ScatterModels template, oriented along flight direction
- **Nocked arrow visual** — arrow appears on bow during draw, removed on fire or aim exit
- **Bow fire sound** — positional twang sound plays when arrow is released
- **Deer death sound** — positional death cry plays when deer is killed
- **Asset preloading** — all sounds, images, and textures from AssetIds preloaded during loading screen via ContentProvider

---

## [0.22.1] - Deer mesh, carcass models, and ambient sounds

### Added
- **Deer mesh model** — replaces placeholder brown cube with proper mesh from ScatterModels, auto-sized ground placement
- **Walk animation** — deer play walk animation when wandering (1x speed) and fleeing (2x speed)
- **Ambient deer sounds** — random calls every 5-10 minutes per deer, positional audio with 80-stud range
- **Carcass model stages** — dedicated meshes for deer_carcass, deer_skinned, and deer_remains, swapped on interaction
- **Carcass ground sink** — configurable `CARCASS_GROUND_SINK` to hide mesh imperfections at ground level

### Changed
- **Deer death** — model now destroyed immediately when carcass spawns (was 2s delay)
- **Ground placement** — uses bounding box height instead of hardcoded offset for deer and carcass positioning
- **Carcass model swap** — full model replacement approach (clone template, copy attributes) instead of part swapping
- **Raycast rebuild** — deferred rebuild of animal raycast params to pick up late-loading ScatterZones folder

---

## [0.22.0] - Combat, bow & arrows, hunting, and butchering

### Added
- **Combat system** — new `CombatService` handles weapon-only melee attacks; harvest tools (knife, axe) cannot deal PvP damage, preventing accidental harvesting during combat
- **Stone Spear** — first dedicated melee weapon (2 twig + 1 rock); 10 damage, 0.8s cooldown, 8-stud range, 25 durability
- **Primitive Bow** — ranged weapon (2 twig + 3 reed); 15 base damage, draw-time scaling (quick shot = 40%, full draw = 100%), 60 durability
- **Stone Arrows** — craftable ammo (1 twig + 1 rock → 5 arrows); stick in targets/terrain, recoverable via ProximityPrompt, 5-minute despawn
- **Bow aiming** — hold right-click for over-the-shoulder camera, crosshair with power ring, FOV zoom; mobile: AIM + FIRE buttons
- **Draw scaling** — bow damage and arrow speed scale with draw time (0.3s min → 1.5s full draw)
- **Reed Quiver** — equipment slot (5 reed); reduces bow draw cycle from 2.5s to 1.0s when equipped
- **Quiver equipment slot** — new slot in CHARACTER tab (replaces unused Off Hand), equip/unequip UI mirrors backpack
- **Deer NPC** — AI state machine (idle → wander → flee → dead); 30 HP, flees on player proximity or damage, spawns in AnimalZones
- **Carcass & Butchering** — two-step ProximityPrompt flow: Skin (3s, yields crude_hide) → Butcher (4s, yields raw_venison, bone, chance of sinew); requires knife equipped
- **Venison cooking** — raw_venison cooks at campfire in 15s → cooked_venison (hunger: 40, health: 5)
- **New items** — stone_spear, primitive_bow, stone_arrow, reed_quiver, raw_venison, cooked_venison, crude_hide, bone, sinew
- **New crafting recipes** — stone spear, primitive bow, stone arrows (batch ×5), reed quiver
- **Hunting achievements** — First Blood, Hunter, Apex Predator, Skinning 101, Master Butcher, Marksman, Sharpshooter, Quiver Full of Stories, Stick 'Em, Phalanx (10 new)
- **Placeholder models** — Part-based spear, bow, and deer models for testing until Studio meshes are ready
- **DurabilityDeduct BindableFunction** — reusable cross-service durability deduction (used by CombatService, BowService, ButcherService)

### Changed
- **Weapon/tool separation** — new `"weapon"` category and `WeaponInfo` type in ItemRegistry; `"tool"` category reserved for harvest tools only
- **Stone knife** — removed legacy `damage` field and `"weapon"` tag; knife is now purely a harvest/butchering tool
- **Click routing** — HudController routes left-clicks to CombatService for weapons, harvest system for tools; no cross-contamination
- **Achievement count** — increased from 53 to 63 achievements across 21 categories (was 17)

---

## [0.21.0] - Achievement fix, inventory weights, loading screen polish

### Fixed
- **Achievement re-award bug** — achievements no longer re-fire toasts/web events on relog; added silent retroactive sweep that backfills the `unlocked` dict from counters on load
- **Redundant `first_craft` event** — removed transient `_HasCrafted` attribute that fired a duplicate EventBridge event every session

### Added
- **Stack weight labels** — inventory slots now show total stack weight (bottom-left, e.g. "1.0kg") in muted text alongside the quantity badge
- **Loading screen flavor text** — rotating survival-themed humor messages ("Convincing deer to cooperate...", "Teaching fish to swim...", etc.) replace static "Loading world..." dots

---

## [0.20.0] - Boulder mining system

### Added
- **Boulder resource nodes** — 4 boulder variants spawn in ScatterZones; mine with pickaxe to harvest stone
  - `boulder_1` — weathered granite with mossy cracks (6-8 HP, medium-large)
  - `boulder_2` — flat-topped layered sandstone (4-7 HP, medium-small)
  - `boulder_3` — smooth river boulder, spawns near water semi-submerged (3-5 HP, smallest)
  - `boulder_4` — jagged cracked rock formation (8-10 HP, largest)
- **Per-variant HP scaling** — each boulder type has its own HP range matching its size; HP randomised per spawn
- **Rock proximity spawning** — small rocks now cluster near boulders (like twigs near trees) instead of spawning randomly
- **Boulder config** — `GameplayConfig.Boulder` section (nodeHealth min/max, hitCooldown, harvestYield, respawn timers, spacing, rock spawn radius)
- **Scale variance** — boulders (±20%) and trees (±15%) spawn at slightly randomised sizes for natural variety
- **Stone chip particles** — particle burst on boulder hit (placeholder texture — upload to fill in `StoneChip` in AssetIds)
- **Node health bars on boulders** — same green→yellow→red bar as trees, auto-hides after 4s
- **Boulder collision** — `hasCollision` ScatterDef field preserves CanCollide on boulder parts (players can't walk through)
- **`_YieldItemId` attribute** — boulders yield `stone` items (not the non-inventoriable `boulder` node item)
- **Mining sound** — `MineRock` sound entry in AssetIds (placeholder — upload audio to fill in)
- **Loading screen** — black overlay with "The Counter Earth" title and animated "Loading world..." text; fades out when scatter spawning completes via `ScatterReady` remote event
- **`ScatterReady` remote event** — fired by ScatterSpawnService when all scatter phases complete; late-joining players also notified
- **Reference art** — AI-generated concept images for all 4 boulder variants + stone icon in `assets/raw/reference/`

### Changed
- **Stone pickaxe icon** — updated to new icon (`rbxassetid://89146262634377`)
- **Stone pickaxe gripCFrame** — tuned for custom mesh avatar hand
- **Stone weight** — reduced from 2.0 to 0.4 kg (twice as heavy as a rock pickup)
- **Stone icon** — updated to `rbxassetid://90151560373302`
- **Template positioning** — models now raycast fresh to terrain after scaling for reliable ground contact

### Removed
- **ScatterSeed system** — removed seeded spawn, `ScatterSeed.luau` data file, `spawnFromSeed()`, `!scatter-snapshot` chat command. Scatter is now always random.

---

## [0.19.7] - Campfire/bedroll placement floating fix

### Fixed
- **Campfire and bedroll float above terrain** — placement raycast was hitting invisible ScatterZone parts instead of terrain; now excludes ScatterZones and Scatter folder from placement raycasts (same root cause as trunk floating fix in 0.19.5)

---

## [0.19.6] - Stone axe mesh and grip tuning

### Added
- **Stone axe mesh** — replaced placeholder geometric parts with a custom 3D model (Studio-placed Tool in ServerStorage/ItemTools)
- **gripCFrame support** — stone_axe now has a tuned `gripCFrame` in ItemRegistry so it sits correctly in the custom mesh avatar's hand
- **GripEditor plugin** — open-source Roblox Studio plugin for visually editing Tool.Grip with Move/Rotate handles; works with custom mesh avatars, R15, and R6 rigs ([Roblox-GripEditor](https://github.com/TemujinCalidius/Roblox-GripEditor))

---

## [0.19.5] - Tree trunk landing, health bars, and harvest polish

### Added
- **Node health bars** — chopping trees and cut points now shows a health bar above the node (green → yellow → red as HP drops, auto-hides after 4 seconds of inactivity, visible up to 35 studs in 3rd person)
- **Chopping animations** — per-tool harvest animations play on hit (axe swing for trees/cut points, knife slash for reeds, pickaxe strike for stone), selected from equipped tool kind
- **Chopping sounds** — `oak_tree → ChopWood` sound mapping plays spatial audio at the node on each hit; tool break sound on durability depletion

### Fixed
- **Trunk segments floating in mid-air** — raycasts for trunk ground placement were hitting invisible ScatterZone parts instead of terrain; now excludes both `ScatterZones` and `Scatter` folder from all TreeService raycasts (trunk segments, stump placement)
- **Stump placement floating** — same ScatterZone raycast issue affected stump ground detection; fixed with shared exclude list

### Changed
- **Hit cooldown reduced** — tree/cut point hit cooldown lowered from 1.8s to 1.0s for snappier chopping feel
- **Tree shake scaling** — trees and cut points shake at 0.6x intensity for more realistic heavy-object feel; cut points shake the parent trunk model via TrunkRef link

---

## [0.19.4] - Click-through and death loot exploit fixes

### Fixed
- **Clicking inventory triggers world actions** — left-clicking on inventory items/tabs/buttons also fired harvest hits or weapon attacks in the game world. The `gameProcessed` guard in HudController only checked Touch inputs, not mouse clicks. Now all input types are blocked when a GUI element handles the click.
- **Death loot pickup exploit** — dying players could spam-pickup their own death loot bag during the death animation, respawning with all gear (fresh durability and spoil timers). Added `Humanoid.Health > 0` check to both `OpenLootBag` and `TakeLootBagItem` server remotes.

### Changed
- **Reed respawn reduced to 15-30s** (was 60-180s) for testing. Will increase for production.

---

## [0.19.3] - Mobile inventory panel off-screen fix

### Fixed
- **Inventory panel invisible on mobile/iPad** — panel position saved as absolute pixel coordinates from desktop would place it off-screen on mobile devices with smaller viewports. Added `clampPanelPosition()` to keep the panel within visible screen bounds on restore, drag-end, and open.
- **Inventory `isOpen` desync after placing items** — using a placeable item from inventory set `panel.Visible = false` without updating `isOpen`, causing the bag button to toggle the wrong direction on next tap.

---

## [0.19.1] - Mobile bag button fix

### Fixed
- **Inventory bag button unresponsive on mobile/iPad** — InventoryGui had no DisplayOrder (defaulted to 0, behind GameplayHud at 2); full-screen tradeQtyOverlay TextButton could intercept touch even when hidden. Set DisplayOrder=5 and toggle Active on overlay.

---

## [0.19.0] - Tier 0 oak tree harvesting system

### Added
- **TreeService** — new server script managing full tree lifecycle: standing → fell → stump + trunk → cut points → log segments → regrowth
- **Tree felling** — chop a standing oak 8 times with a stone_axe to fell it; tree rotates 90° away from player with gravity-eased tween
- **Fall damage** — players caught under a falling tree take 20 HP damage
- **Trunk sectioning** — fallen trunk gets 2 "Chop Here" cut point markers (BillboardGui); chopping the first shrinks the trunk from that end and drops 1 log; chopping the second destroys the trunk and drops 2 more logs
- **Log segment pickup** — 3 oak_log segments per tree, each with ProximityPrompt (E key), auto-despawn after 10 minutes
- **Stump regrowth** — stump spawns at original position; new tree regrows after 1–1.5 hours
- **oak_tree ScatterDef** — trees spawn in ScatterZones with 12-stud minimum spacing, placeholder parts until meshes are ready
- **oak_log item** — renamed from `wood`, with updated tags (`log`, `tier0`), DataStore migration via ITEM_RENAMES
- **Placeholder tool models** — ToolPlaceholders.server.luau auto-generates stone_axe, stone_pickaxe, stone_knife Tool instances with welded handle + head parts (skipped if Studio model exists)
- **Tree config** — `GameplayConfig.Tree` section with all tree parameters (node health, cooldowns, cut points, fall duration, respawn timers, spacing)
- **Leaf particles** — ParticleEmitter burst on tree hit (green leaves, 8 particles per chop)
- **Wood chip particles** — ParticleEmitter burst on tree and cut point hits (brown chips, 12 particles per chop)
- **Reference images** — 7 oak tree asset references generated for 3D modelling (3 tree variants, stump, full trunk, medium trunk, log segment)

### Changed
- **Scatter raycast filtering** — ScatterZones and Scatter folder now excluded from ground raycasts so items land on terrain, not on zone parts
- **Harvest error messages** — dynamic tool requirement messages based on `_RequireTool` attribute (axe for trees, knife for reeds, pickaxe for stone/ore)
- **Tree shake scaling** — trees shake at 0.6x intensity for more realistic mass feel
- **Harvest sound mapping** — added `oak_tree = "ChopWood"` to GatherController

### Fixed
- **Scatter floating items** — items were landing on top of ScatterZone BaseParts instead of terrain; fixed with RaycastParams.Exclude filter
- **Zero-yield "inventory full"** — cut points with 0 yield were incorrectly triggering "Inventory full!" message; added `if yield > 0` guard
- **Tree falling toward player** — CFrame.fromAxisAngle sign was inverted; tree now falls away from player
- **Stump tipping** — cylinder stump lost Z rotation on PivotTo; replaced with upright block geometry
- **Cut point discovery** — cut points parented inside trunk model were invisible to client harvest scan; moved to Scatter folder with ObjectValue trunk reference

---

## [0.18.0] - UI overhaul: tooltips, achievement UX, themed panels

### Added
- **Tooltip system** — new `TooltipModule.luau` shared module with hover tooltips (desktop: mouse-follow with 0.3s delay; mobile: long-press). Supports item, achievement, stat, and text tooltip kinds
- **Item tooltips** — hover any inventory slot to see name, category, weight, durability bar, spoil timer, and consume effects
- **Achievement tooltips** — hover achievement cards for description, progress bar, and unlock timestamp
- **Stat bar tooltips** — hover HUD stat bars (health, energy, hunger, thirst, fatigue, blood, poison) and credits for explanations
- **Hotbar tooltips** — hover hotbar slots to see pinned item details
- **Inspect tooltips** — hover inspected player's stat bars for descriptions with live values
- **Achievement descriptions** — added `desc` field to all 53 achievements with player-facing hint text
- **53 custom achievement icons** — generated via 3D AI Studio, cozy RPG style; replaces emoji TextLabels with ImageLabels (emoji fallback if asset missing)
- **Loot bag 3D model** — replaced plain brown cube with a burlap sack mesh for loot bags and death bags
- **Themed panel backgrounds** — programmatic visual depth on all panels (UIGradient, accent lines, inner glow, bottom shadow) with per-panel accent colours
- **Bag button icon** — replaced empty "BAG" text button with a themed satchel icon

### Changed
- **Achievement category filter** — replaced invisible horizontal scrollbar with a dropdown selector showing all 18 categories with per-category unlock counts (e.g. "Cooking (2/3)")
- **Achievement cards** — added UIStroke (gold when unlocked, muted when locked); icons now use custom ImageLabels
- **Achievement toast** — now displays achievement description text below category subtitle; toast height increased to 90px; icon uses ImageLabel with fade-out support
- **Tab hover effects** — inventory tab buttons (ITEMS, RECIPES, CHAR, ACHIEVE) show subtle highlight on hover
- **Stat bar fills** — added UIGradient for top-to-bottom depth effect on all stat bars
- **Bag button label** — shrunk to small caption below the icon instead of full-size overlay text

### Fixed
- **Reed respawn** — reeds were not respawning after harvest due to overly restrictive water-edge position finder; relaxed slope tolerance from 25° to 40°, added diagonal water checks, increased attempts from 30 to 60, added spawn failure logging

---

## [0.17.0] - asset pipeline & inventory icons

### Added
- **Asset pipeline** — automated image generation (3D AI Studio), background removal, resize to 512x512, and upload to Roblox via Open Cloud API
- **17 inventory icons generated** — stone_pickaxe, wood, stone, iron_ore, cooked_mushroom, spoiled_food, water_skin, bandage, antidote, coin_credits, coin_copper, coin_silver, coin_gold, pouch_credits, pouch_standard, satchel_reed, pack_leather
- **Roblox MCP server** — switched to Vltja/Roblox-MCP (Node.js) with 17 Studio tools and free Creator Store plugin
- **Batch icon generator** — `tools/asset-pipeline/batch_icons.py` for bulk icon generation with rate limiting

### Fixed
- **Asset pipeline endpoints** — updated 3D AI Studio API paths (added `/generate/` suffix, dots in version numbers)
- **Upload type** — changed from `"Decal"` to `"Image"` so icons work in ImageLabel/ImageButton
- **Poll status** — added `"finished"` to completion states (API returns uppercase `FINISHED`)
- **URL extraction** — added `asset` key for 3D AI Studio response format
- **Roblox upload polling** — fixed operation path construction for async uploads
- **stone_pickaxe icon** — replaced invalid hex UUID with proper numeric rbxassetid

---

## [0.16.0] - reed satchel backpack system

### Added
- **Backpack equip system** — equipping a satchel from inventory moves it to the Backpack equipment slot in the CHAR tab, expanding inventory from 5 to 15 slots and carry weight from 5kg to 15kg
- **EQUIP button** in inventory detail strip for backpack items; shows "EQUIPPED" (grayed) when one is already worn
- **Click-to-unequip** on Backpack slot in CHARACTER tab — returns satchel to inventory (blocked if backpack slots contain items)
- **Backpack persistence** — equipped backpack saved/loaded from DataStore profile (`equippedBackpack` field)
- **Death drops backpack** — equipped satchel is dumped into death loot bag along with all inventory; capacity resets to base 5 slots / 5kg

### Changed
- **ItemRegistry backpack format** — switched from grid-based (`gridW`/`gridH`) to slot-based (`slots`/`maxWeight`): satchel_reed = 10 slots / 10kg, pack_leather = 20 slots / 30kg

---

## [0.15.1] - persistence & harvest fixes

### Fixed
- **Achievement data lost on relog** — race condition where AchievementService cleared player state in `PlayerRemoving` before PlayerStateService could save it. Deferred cleanup so save completes first
- **"Inventory full" not visible** — harvest failures (full inventory, no knife) now show a centered red screen notification instead of an invisible BillboardGui above the player's head
- **Bare-hands near harvest node silent failure** — clicking near a reed with nothing equipped now shows "You need a knife" instead of doing nothing
- **AchievementToastController infinite yield** — `WaitForChild("AchievementUnlocked")` without timeout blocked forever if AchievementService failed to start. Added 10s timeout with graceful fallback
- **AchievementConfig parse errors** — removed invalid Luau type annotations on module field assignments that caused cascading script failures

### Changed
- **Bedroll pickup** — any player can now pick up any bedroll (PvP raiding), but pickup is blocked while someone is sleeping/resting on it

---

## [0.15.0] - in-game achievement system (53 achievements)

### Added
- **Achievement system** — 53 achievements across 17 categories (Deaths, Survival, Playtime, Trading, Harvesting, Crafting, Cooking, Wealth, Login Streaks, Tool Breaking, Close Calls, Campfire Sessions, Spoilage, Bedroll, Consumption, PvP Kills, Death Causes)
- **AchievementConfig** — shared config defining all achievements, counter thresholds, and EventBridge-to-counter mappings
- **AchievementService** — server-side tracker: listens to EventBridge events via `onFire` hook, auto-increments counters, checks thresholds, awards unlocks. Handles login streaks, playtime ticks, and credits peak tracking
- **Achievement toast notifications** — gold-accented toast slides in from top-right on unlock (icon, name, category), holds 4s, fades out. Queued for multiple unlocks
- **ACHIEVEMENTS tab** in inventory panel — 4th tab showing scrollable grid of all 53 achievements with category filter bar, progress counters, and unlocked state
- **Achievement count on inspect panel** — inspecting another player shows "X/53 — Most Recent Achievement" row
- **`achievement_unlocked` EventBridge event** — sent immediately to web/Discord on each unlock with key, name, icon, category, counterValue, totalUnlocked, totalAchievements. Game is now the single source of truth for achievements
- **EventBridge `onFire` hook** — local listener system so server modules (like AchievementService) can react to game events without modifying source scripts
- **Login streak tracking** — consecutive UTC-day login detection with streak counter, drives streak_3/streak_7/streak_30 achievements

### Changed
- **DataStore profile version** bumped from v5 to v6 — adds `achievements` table (counters, unlocked timestamps, loginStreak). Backwards-compatible: missing field defaults to empty
- **Inventory tab buttons** resized from 100px to 90px to fit 4 tabs (ITEMS, RECIPES, CHAR, ACHIEVE)
- **Inspect panel height** increased from 340 to 364px to accommodate achievements row

---

## [0.14.0] - knife fix, trade quantity picker, bridge enhancements, cooking fix

### Fixed
- **Knife attachment desync for remote players** — equipped tools (knife, axe, etc.) appeared at shoulder/back on other players' screens. Root cause: hand-bone tracking only ran on the local player's client. New `BoneTracker.client.luau` (StarterPlayerScripts) now tracks hand bones for ALL characters visible to each client
- **Cooked items stuck in campfire input slot** — placing a non-cookable item (e.g. cooked mushroom) in the campfire input made it permanently stuck. Server now rejects items with no cooking recipe. Clicking the input slot now retrieves items back to inventory

### Added
- **Trade quantity picker** — dragging a stack (qty > 1) onto the trade panel or another player now shows a quantity selector popup instead of offering the full stack. Single items skip the picker. Includes +/- buttons and manual entry
- **cook_complete event** — campfire cooking now fires `cook_complete` to the EventBridge for Discord/website tracking
- **Profession mapping for events** — `harvest_complete`, `craft_complete`, `cook_complete` events include `profession`, `xpGained`, and `itemName` fields for the website's profession XP system
- **Death cause tracking** — `player_death` events now include `cause` field (starvation, dehydration, bleeding, poison, unknown). PvP tagging infrastructure ready for when combat is added
- **Trade item names** — `trade_complete` events now include `itemName` alongside `itemId` in offer arrays for richer Discord trade feed
- **Comprehensive gameplay tracking events** — `item_dropped`, `tool_broken`, `spoilage_lost`, `inventory_full_reject`, `campfire_session`, `first_campfire`, `first_craft`, `starvation_close_call` (hunger & thirst), `bedroll_placed_near_others`
- **cook_complete attribution fix** — cooking XP now goes to the player who added the raw food, not just the campfire placer. Falls back to placer if adder left the server

### Changed
- **EventBridge event types renamed** to match web server schema: `harvest` → `harvest_complete`, `craft_item` → `craft_complete`
- **EventBridge disabled in Studio** — `EnableInStudio` set back to `false` to prevent test events polluting live data
- Removed verbose EventBridge HTTP logging (was temporary for debugging)

### Website & Discord Integration (v0.3.0)
- 35+ achievements system with Discord announcements
- Milestone announcements (profession tier-ups, wealth changes, survival records, login streaks)
- Login streak tracking with `/streak` command
- Live server status embed (auto-updates every 2 min)
- Rich list: top 10 wealthiest players in hall-of-fame
- Weekly recap with Player of the Week award
- Trade watchlist alerts via `/watchlist` command
- Enhanced leaderboards: login streak, best survival
- Live "Currently in-game" indicator on website profiles

---

## [0.13.2] - sprint fix for Windows + double-tap W

### Fixed
- **LeftShift sprint not working on some Windows PCs** — Roblox shift-lock or Windows accessibility (sticky keys, language switcher) could mark LeftShift as "processed", causing the input handler to ignore it. Shift check now runs before the gameProcessed guard

### Added
- **RightShift also sprints** — alternative for players whose LeftShift is intercepted
- **Double-tap W to toggle sprint** — tap W twice within 0.3s to start sprinting. Auto-cancels when you stop moving. Works alongside hold-to-sprint with Shift

---

## [0.13.1] - HTTP event bridge (game → website/Discord)

### Added
- **EventBridge module** — centralized HTTP event dispatcher pushes game events to `thecounterearth.com/api/game/events` for Discord bot integration
- **Immediate events**: `player_join`, `player_leave`, `player_death`, `trade_complete` — sent instantly
- **Batched events**: `craft_item`, `harvest`, `item_consume` — queued and flushed every 5 seconds
- Fire-and-forget design: all HTTP calls pcall-wrapped, failures never break gameplay
- API key stored in `ServerStorage.Secrets.WebhookApiKey` (Studio-only, not in git)
- Disabled in Studio by default (`EventBridge.EnableInStudio`)
- Config in `GameplayConfig.EventBridge` (endpoint URL, flush interval, batch sizes)

---

## [0.13.0] - player inspect screen, draggable windows, crafting fix

### Added
- **Player inspect screen** (#28) — ProximityPrompt (G key) on other players opens a profile panel showing name, title, stat bars (health/hunger/thirst/fatigue), wealth tier, survival time, and equipped item. Includes TRADE button to initiate trade from the inspect panel
- **PlayerInspectService** — server validates range, reads target's live attributes, derives wealth tier and formats survival time
- **InspectController** — client manages ProximityPrompts on other players, builds inspect UI panel
- **Draggable panels** — trade, loot bag, cooking, inspect, and inventory panels are draggable by title area (top 30px). Works on PC and mobile
- **Cross-session window positions** — dragged panel positions saved to DataStore and restored on relog via `SaveUIPosition` remote
- **Survival time tracking** — `_SurvivalSeconds` attribute accumulated server-side in Heartbeat, resets on death, persists across sessions
- **Drag-to-trade screen-space fallback** — 80px tolerance when raycast misses mesh avatar geometry

### Fixed
- **Crafting consumes ingredients when inventory full** (#27) — pre-craft capacity check now simulates whether output fits before removing ingredients. Shows "Inventory full!" notification on failure
- **Empty trade initiation** — TradingService now accepts `itemId=""` with `qty=0` to start a trade from the inspect screen TRADE button

---

## [0.12.2] - player inspect screen

### Added
- **Player inspect screen** — ProximityPrompt ("Inspect") on other players opens a profile panel showing health, hunger, thirst, fatigue bars, wealth tier, survival time, equipped item, and title placeholder. Includes TRADE button for direct trade initiation ([#28](https://github.com/TemujinCalidius/TheCounterEarth/issues/28))
- **PlayerInspectService** (`PlayerInspectService.server.luau`) — validates range, reads target player's live attributes, calculates wealth tier and survival time
- **InspectController** (`InspectController.client.luau`) — manages ProximityPrompts on player characters and renders the inspect panel UI
- **Empty trade initiation** — TradingService now supports starting a trade with no initial item offer (used by inspect screen TRADE button)
- **Survival time tracking** — `survivalSeconds` field in DataStore profile, accumulates while alive, resets on death

---

## [0.12.1] - crafting inventory-full fix

### Fixed
- **Crafting consumes ingredients when inventory full** — both client and server now simulate output fit (partial stacks, empty slots, slots freed by ingredient removal) before committing. Client blocks craft immediately with "Inventory full!" in progress bar (same style as "Too heavy to craft!"). Server double-checks and sends `CraftFailed` remote as safety net ([#27](https://github.com/TemujinCalidius/TheCounterEarth/issues/27))

---

## [0.12.0] - 2026-03-14

### Added
- **Mobile/tablet support** — full touch input support across all gameplay systems ([#22](https://github.com/TemujinCalidius/TheCounterEarth/issues/22), [#23](https://github.com/TemujinCalidius/TheCounterEarth/issues/23), [#24](https://github.com/TemujinCalidius/TheCounterEarth/issues/24), [#25](https://github.com/TemujinCalidius/TheCounterEarth/issues/25), [#26](https://github.com/TemujinCalidius/TheCounterEarth/issues/26))
- **Hotbar tap-to-equip on mobile** — per-slot `InputEnded` handler for reliable touch equip without triggering virtual thumbstick
- **Mobile sprint toggle** — RUN/WALK button (bottom-right) that toggles sprint intent, auto-disables when player stops moving
- **Mobile placement system** — dedicated PLACE, Rotate (R), and Cancel (X) buttons for campfire/bedroll placement. Ghost follows screen center via camera-forward raycast with crosshair dot indicator
- **Mobile harvest/attack** — `isClickOrTap()` helper unifies mouse click and touch input for combat and hit-to-harvest, with `gameProcessed` guard to ignore movement touches
- **Inventory drag-and-drop on mobile** — `isMoveInput()` helper unifies mouse movement and touch drag for inventory slot reordering, inventory-to-hotbar pinning, and campfire input
- **Hotbar drag overlay** — full-screen transparent overlay captures touch/mouse release during hotbar drag-to-reorder, fixing both PC and mobile drop detection
- **Bedroll prompt spacing** — `UIOffset` on Lie Down and Pick Up ProximityPrompts prevents overlapping on mobile
- **AvatarRigService** (`AvatarRigService.server.luau`) — new server script creating Motor6D between HumanoidRootPart and RightHand Part so Roblox's built-in tool equip works with single-mesh custom avatars
- **RightHand bone tracking** — AvatarSetup now tracks the `mixamorig:RightHand` bone each frame via `PreRender`, updating the Motor6D C0 for zero-lag tool rendering
- **Jump freefall suppression** — AvatarSetup suppresses premature FreeFall state during jump ascent for single-mesh avatars, re-enables on descent for proper Freefall→Landed transition
- **Avatar config** — `GameplayConfig.Avatar` section centralizes HipHeight (2.6), HandBoneName, MeshPartName, and JumpAnimHoldSeconds
- **Per-item grip CFrame** — tools now support `gripCFrame` in ItemRegistry for custom hand positioning; default grip rotated -70° so tools (knife, axe) sit correctly in hand

### Changed
- **Hotbar `Active = true`** — hotbar root frame sinks touch input to prevent Roblox virtual thumbstick activation when tapping hotbar slots
- **Placement confirm (PC)** — placement confirmation now uses `MouseButton1` only (not Touch), since mobile uses the dedicated PLACE button
- **Mobile button positioning** — sprint button at Y=-200, placement buttons at Y=-280, well above Roblox's built-in JUMP button
- **JumpPower increased** — 50 → 80 to match custom avatar proportions
- **Tool grip standardized** — both InventoryService and ToolInventoryService now apply the same `defaultGrip` CFrame with rotation, replacing the old `CFrame.new(0, -0.4, 0)`

### Fixed
- Hotbar drag-to-reorder broken on both PC and mobile — `GuiObject.InputEnded` fires on boundary exit, not release. Fixed with full-screen overlay approach ([#26](https://github.com/TemujinCalidius/TheCounterEarth/issues/26))
- Placement fires on any screen touch on mobile — camera rotation and movement touches triggered placement ([#23](https://github.com/TemujinCalidius/TheCounterEarth/issues/23))
- Hotbar acts as joystick on mobile — touch on bottom of screen activated Roblox virtual thumbstick ([#22](https://github.com/TemujinCalidius/TheCounterEarth/issues/22))

---

## [0.11.0] - 2026-03-13

### Added
- **Custom avatar support** — `AvatarSetup.client.luau` in StarterCharacterScripts adjusts HipHeight for single-mesh custom avatars
- **StarterCharacterScripts Rojo protection** — `$ignoreUnknownInstances: true` in `default.project.json` prevents Rojo from deleting Studio-placed assets (Animate script, animation folders)

### Changed
- **Custom animation IDs** — updated idle, walk, run, sit, sleep, and harvest knife animations in AssetIds to use custom avatar animations
- **Bedroll sleep orientation** — removed 90-degree Y rotation so character lies along bedroll length instead of width
- **Energy regen ground check** — replaced `FloorMaterial` ground detection with `HumanoidStateType.Swimming` check to fix false-negative grounding with custom avatars

### Known Issues
- Single-mesh custom avatars don't swim properly in terrain water — engine buoyancy doesn't work with single MeshPart characters (see [#19](https://github.com/TemujinCalidius/TheCounterEarth/issues/19))

---

## [0.10.0] - 2026-03-11

### Added
- **Player-to-player trading** — drag an item from your inventory onto another player's character to initiate a trade. Target player sees accept/decline popup with item preview. Both players get a split-view trade window (YOUR OFFER / THEIR OFFER) with mutual confirmation
- **TradingService** (`TradingService.server.luau`) — server-side trade session management with drag-to-player initiation, pending request timeout (15s), offer updates, mutual confirmation, and atomic trade execution
- **Trade overflow protection** — if a received item would exceed the partner's weight limit, excess drops as a loot bag at their feet via `CreateLootBag` BindableFunction
- **Trade range enforcement** — auto-cancels trade if players walk more than 15 studs apart (Heartbeat check)
- **Trade UI** — trade window positioned right of inventory with scrollable offer grids, confirm/cancel buttons, and partner status text. Click items in YOUR OFFER to remove them. Escape closes trade
- **`CreateLootBag` BindableFunction** — cross-service function for spawning loot bags from arbitrary item lists
- **Hand crafting channel** — crafting now takes 5 seconds with a progress bar, looping animation (`rbxassetid://120762235566284`), and sound effect (`rbxassetid://97194221591864`). Inventory closes during crafting so you can see your character. Cancellable by moving or pressing CRAFT again
- **Craft weight check** — crafting checks net weight change (output minus ingredients) against carry capacity before starting. Shows "Too heavy to craft!" if over limit
- **Tool durability system** — tools (stone_knife=20, stone_axe=30, stone_pickaxe=25) now have per-item durability that decrements on each harvest hit. When durability reaches 0, the tool breaks with a notification and sound effect
- **Per-item durability in stacks** — each tool in a stack has independent durability stored as comma-separated `InvDurability_N` attributes (mirrors the expiry pattern). First item in stack is the "active" one that takes damage
- **Durability persistence** — durability values saved/loaded from DataStore. Existing tools without saved durability gracefully receive max durability on load
- **Durability bars** — thin green→yellow→red bar on both hotbar slots and inventory grid cells for durable items. Inventory detail strip shows "Durability: X/Y" text
- **Tool break sound** — `rbxassetid://93653850093139` plays when a tool breaks
- **Tool break notification** — floating text "Your {tool} broke!" appears above player head
- New remotes: `TradeInitiate`, `TradeRequest`, `TradeResponse`, `TradeState`, `TradeUpdateOffer`, `TradeConfirm`, `TradeCancel`
- `GameplayConfig.Trading` — `InteractRange` (15 studs), `RequestTimeoutSeconds` (15s)

### Changed
- **Harvest node destruction delay** — nodes now persist 1.4s after final hit (up from instant) so the client can play feedback animation before the model disappears. ProximityPrompt disabled immediately to prevent interaction
- **Split/swap/spoilage** — all inventory operations (SplitStack, SwapSlots, merge, spoilage sweep) now carry durability data alongside expiry data
- `InvDurability_N` attribute changes trigger DataStore dirty flag for auto-save
- Hotbar and inventory attribute change listeners now include `InvDurability_` prefix

---

## [0.9.0] - 2026-03-11

### Added
- **Death loot bag system** — on death, ALL inventory items are dumped into a death loot bag at the death location. Stats reset to 100% (not 80%)
- **Death bag beacon** — owner-only golden neon beam (200 studs tall) with ground glow ring and PointLight, visible from far away. Other players see the bag but not the beacon
- **Loot bag countdown timer** — BillboardGui timer on all loot bags showing remaining time (M:SS format). Color shifts white → yellow (60s) → red (30s)
- **LootBagController** (`LootBagController.client.luau`) — client script rendering countdown timers and owner-only beacons on loot bags
- **`DeathBagBeacon` remote** — server notifies bag owner's client to render the beacon
- **`InventoryDumpAll` BindableFunction** — cross-service function for PlayerStateService to trigger full inventory dump on death
- **Hit-to-harvest system** — ARK-style resource gathering replaces the old channel/progress-bar system. Each left-click with the correct tool = one hit that damages the node and yields resources
- **Resource node HP** — harvest nodes have `_NodeHealth` attribute. Each hit deducts 1 HP, node breaks when HP reaches 0 and respawns after cooldown
- **Harvest yield per hit** — configurable min/max yield per hit (e.g. reed gives 1-2 per hit with stone knife). Tool tier will scale yield in future
- **Proximity-based harvesting** — left-click anywhere while near a harvest node (8 studs) with the correct tool. No need to aim at the node
- **Target locking** — once you start hitting a node, subsequent clicks keep hitting that same node until it's destroyed or out of range. Prevents accidental switching between nearby nodes
- **Harvest hit cooldown** — 1.5s cooldown between hits (client + server enforced), lets the swing animation play out
- **Harvest feedback** — model shake on hit (6-frame decaying intensity), floating "+N ItemName" text that fades upward, per-tool-kind swing animation, per-resource sound effect
- **Per-tool harvest animations** — `HarvestKnife`, `HarvestPickaxe`, `HarvestAxe` animation slots in AssetIds. Animation auto-selected based on equipped tool kind
- **Reed harvest sound** — spatial sound effect plays at the node's position on each hit
- **Floating name labels** — harvest nodes show their display name as a BillboardGui visible within 15 studs (replaces removed ProximityPrompt)
- **Reed icon** — `rbxassetid://99940535604564` added to AssetIds and ItemRegistry
- **Scatter slope alignment** — `alignToSlope` option tilts scatter models to match terrain surface normal (used for reeds on shoreline slopes)
- **Scatter ground sink** — `groundSink` option sinks models into the ground to hide floating on slopes (reed: 0.3 studs)

### Changed
- **Death stat reset** — all survival stats (hunger, thirst, fatigue, blood) now reset to their `.Max` value (100) on death, not `.StartValue` (80)
- **Scatter slope rejection** — raycasts now return surface normal; positions on slopes steeper than 25° are rejected for scatter placement
- **Reed water edge radius** — increased from 6 to 12 studs for `hasWaterNearby` check, reducing shoreline floating
- **Reed ProximityPrompt removed** — reeds (and all gather items with `nodeHealth > 0`) no longer use ProximityPrompt. Interaction is via left-click proximity
- **GatherController rewritten** — replaced progress bar system with hit feedback controller (shake, floating text, sound, animation)
- **Scatter defs** — `gatherSeconds` replaced with `nodeHealth`, `harvestYield`, `hitCooldown` fields
- **InventoryService remotes** — `GatherStart`/`GatherCancel`/`GatherComplete`/`GatherRequest` replaced with `HarvestHit`/`HarvestResult`/`HarvestNotify`

### Removed
- **Gather channel system** — removed `activeGathers` table, `cancelGather`/`completeGather` functions, Heartbeat validation loop, `_BeingGathered` attribute, `_GatherSeconds` attribute
- **GatherStart/GatherCancel/GatherComplete remotes** — replaced by hit-based remotes

### Fixed
- **Scatter items floating** — removed artificial +0.3 Y offset, added `GetBoundingBox()` for accurate model height, added slope rejection and ground sink
- **Loot bag timer not showing** — fixed replication timing: `waitForHandle()` with 3s timeout and `task.defer` in ChildAdded handler
- **Beacon not visible** — widened beam to 1.5 studs, reduced transparency, added ground glow ring and PointLight

---

## [0.8.0] - 2026-03-09

### Added
- **Bedroll system** — craftable placeable that must be placed near a campfire. Sets respawn point on death. One bedroll per player (placing a new one destroys the old one)
- **Death respawn at bedroll** — dying with an active bedroll teleports you back to it on respawn
- **Relog position persistence** — player's position is saved to DataStore on logout. On rejoin, they spawn at their last position (+2 studs Y) instead of default spawn. One-time use, then cleared
- **Per-item spoilage system** — each perishable item has its own expiry timestamp stored as comma-separated `InvExpires_N` attributes. Items spoil individually based on when they were picked up, converting to `spoiled_food`
- **Spoilage tick loop** — every 10 seconds, scans all player inventories for expired timestamps. Handles offline catch-up (multiple items can spoil in a single tick)
- **`spoiled_food` item** — junk material produced when food spoils. Stackable (10), lightweight, tagged for future alchemy use
- **Bedroll config** — `GameplayConfig.Bedroll` section with `RequiredCampfireRadius` and `KeepCampfireAliveRadius`
- **Campsite pairing** — bedroll within `KeepCampfireAliveRadius` of campfire = paired. Paired campsites stay alive while the owning player is on the server regardless of distance

### Changed
- **Profile version bumped to v5** — DataStore now saves `lastPosition` and per-item `expiries` arrays in invSlots entries
- **v4→v5 migration** — existing perishable items get fresh expiry timers on first load
- **Campsite cleanup loop** — replaced campfire-only logic with paired campsite logic. Campfires and bedrolls both participate. Owner online + paired = stays alive. Otherwise, 10-min inactivity timer
- `BrownMushroom` perishSeconds: 900 → 2400 (40 min)
- `cooked_mushroom` perishSeconds: 1200 → 3600 (1 hour)
- `addQty` now sets per-item expiry timestamps when adding perishable items
- `removeQty` trims oldest expiry timestamps when consuming items
- `splitStack` splits expiry list (oldest N go to new slot)
- `swapSlots` merges expiry lists on same-item merge, swaps on different-item swap
- `InvExpires_N` attribute changes now trigger profileDirty for auto-save
- Item rename migration: `raw_fish`, `cooked_fish`, `raw_meat`, `cooked_meat` → `spoiled_food`

### Removed
- `raw_meat`, `cooked_meat`, `raw_fish`, `cooked_fish` items (test items not yet in game world)
- `raw_meat` and `raw_fish` cooking recipes from CookingConfig

---

## [0.7.0] - 2026-03-08

### Added
- **Campfire cooking system** — ARK/Minecraft-style station cooking. Drag raw food into campfire input slot, it cooks over time on the server, cooked food appears in output slot ready to take. Shared/public — anyone nearby can add or take items
- **CampfireService** (`CampfireService.server.luau`) — manages per-campfire inventory state (input/output slots), autonomous Heartbeat cooking loop, and viewer tracking for state broadcasts
- **CookingConfig** (`CookingConfig.luau`) — campfire recipe definitions mapping raw items to cooked outputs with cook times, station type, and skill level
- **Campfire cooking UI** — floating panel above hotbar with input/output slots, animated progress bar, timer text, and food picker popup. Opens via ProximityPrompt (E key) on placed campfires
- **Recipe Book tab** — CRAFT tab replaced with RECIPES tab showing all recipes (hand-craft + cooking) with station badges (HAND/CAMPFIRE), filter bar (ALL/HAND/CAMPFIRE), and ingredient availability. Hand-craft recipes remain interactive with CRAFT button; station recipes are read-only reference
- **Drag-and-drop to campfire** — drag food from inventory directly onto campfire input slot (cross-ScreenGui hit detection via ObjectValue reference)
- **ProximityPrompt on campfires** — placed campfires get a "Cook" ProximityPrompt for opening the cooking UI, independent of sit mechanic
- **Cross-service inventory BindableFunctions** — `InventoryAdd`, `InventoryRemove`, `InventoryGetQty` in ServerBindables for CampfireService to manipulate player inventories
- **Poison on raw food** — `onConsume.poison` field in ItemRegistry triggers poison bar accumulation when eating raw/toxic food
- **Loot bag on campfire despawn** — campfires with items in input/output drop a loot bag when auto-deleted
- New items: `raw_fish` (hunger=12, poison=10), `cooked_fish` (hunger=25)
- Updated `raw_meat` with `poison = 5` (food poisoning risk from raw meat)
- New remote events: `OpenCampfire`, `CampfireState`, `CampfireAddItem`, `CampfireTakeItem`

### Changed
- `CraftingConfig` recipes now include `station = "hand"` and `skillLevel = 1` fields for Recipe Book display uniformity
- `GameplayConfig.Campfire` expanded with `DefaultCookSeconds`, `MaxInputStack`, `MaxOutputStack`, `InteractRange`
- `InventoryService` UseItem handler now includes `poison` in ConsumeEffect payload
- `PlayerStateService` ConsumeEffect handler now processes poison from food consumption (activates poison status effect)
- CRAFT tab renamed to RECIPES with unified recipe list and filter system

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
