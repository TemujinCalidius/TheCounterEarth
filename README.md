<p align="center">
  <img src="assets/raw/screenshots/Alpha%20Logo.png" alt="The Counter Earth" width="600">
</p>

# The Counter Earth

A survival/roleplay framework for Roblox, built as a complete foundation that world builders can extend with their own maps, stories, and gameplay.

The Counter Earth ships as a ready-to-run Roblox experience with core survival mechanics, inventory management, and player progression systems already wired up. Creators drop it into their world, customize the config files, and focus on building the experience — not the plumbing.

## What's Included

- **Multi-Place Architecture** — shared core code across multiple places (sandbox, hospital, etc.) with per-place scripts for place-specific logic
- **Energy & Sprint** — stamina system with sprint drain, jump cost, and standing-still regeneration
- **Survival Stats** — hunger, thirst, and fatigue that drain over time with configurable penalties when depleted
- **Health System** — persistent health (no auto-regen), bleeding and poison status effects with particle FX
- **Slot-Based Inventory** — weight-limited grid inventory with stacking, splitting, drag-and-drop, and loot bags
- **Panel System** — PanelManager handles mutual exclusivity, open/close animations, and mouse unlock for four panels: Inventory, Character, Achievements, and Codex
- **Hotbar** — 9-slot quick-access bar (keys 1-9) with drag-to-reorder and durability/spoilage bars
- **Drag-and-Drop** — drag items between inventory slots, to hotbar, to trade panel, or drop to the world
- **Crafting** — hand-crafting with 5-second channeled animation, campfire station cooking with recipe book
- **Tool Durability** — tools wear down with each use and break when depleted, creating ongoing crafting demand
- **Hit-to-Harvest** — ARK-style resource gathering with per-hit yield, tool requirements, and node HP
- **Combat System** — weapon-only melee attacks and ranged bow combat with draw-time damage scaling
- **Hunting & Butchering** — deer AI (idle/wander/flee), two-step carcass processing (skin → butcher), venison cooking
- **Zombie NPCs** — hostile NPC system with zone-based spawning, AI state machine, melee attacks, and corpse fade
- **Player Trading** — drag-to-player trade initiation, split-view offer window, mutual confirmation, weight overflow protection
- **Placeable Items** — ghost preview placement mode with range validation, campfire sitting with health/energy regen
- **Campfire Cooking** — station-based cooking with input/output slots, progress bar, and shared access
- **Bedroll & Respawn** — placeable bedroll sets respawn point, relog position persistence
- **Food Spoilage** — per-item expiry timestamps, items spoil individually over time
- **Loot Bags** — items drop as lootable bags on death or manual drop, with countdown timers and owner beacons
- **Achievement System** — event-driven achievement tracking with counters, toast notifications, and dedicated panel
- **Lore & Codex** — discoverable lore entries with toast notifications, Codex panel with category browser, DataStore persistence
- **Custom Avatar** — single-mesh custom character support with HipHeight adjustment, drift correction, and custom animations (idle, walk, run, sit, sleep, harvest)
- **First-Person Camera** — per-place first-person mode with crosshair UI and inventory mouse unlock
- **HUD** — health/energy/survival bars, hotbar with durability overlays, vignette and audio feedback, vertical button bar for panel access
- **Mobile/Tablet Support** — full touch input support: tap-to-equip hotbar, drag-to-reorder slots, sprint toggle button, dedicated placement buttons (PLACE/R/X), screen-center ghost aiming, and touch-aware harvest/attack
- **Persistence** — full DataStore save/load for all player data (credits, stats, inventory, hotbar, durability, expiry, position)
- **Tool Pickup** — ProximityPrompt-based world item pickup with auto-hotbar assignment

## For World Builders

The Counter Earth is designed as a starting point. The core systems handle:

- Player state, survival mechanics, and data persistence
- Inventory and item management with weight/stack limits
- Secure client-server communication with input validation
- HUD rendering and audio feedback

You bring the world: terrain, buildings, NPCs, quests, lore. Configure gameplay values in a few Luau files and build your experience on top of a tested foundation.

### Configuration

All gameplay values are centralized in `src/shared/config/` — no hunting through scripts:

| File | What It Controls |
|------|-----------------|
| `GameplayConfig.luau` | Energy, movement, health, credits, hotbar, inventory, weight, campfire, bedroll, trading, loot bags |
| `StatsConfig.luau` | Hunger, thirst, fatigue drain rates and penalties |
| `ItemRegistry.luau` | Item definitions (name, weight, stack size, category, durability, spoilage, effects) |
| `CraftingConfig.luau` | Hand-crafting recipes and ingredients |
| `CookingConfig.luau` | Campfire cooking recipes (raw → cooked, cook times, station type) |
| `AchievementConfig.luau` | Achievement definitions, counters, event-to-counter mappings |
| `LoreConfig.luau` | Lore entry definitions (title, body, category, area, trigger conditions) |
| `AssetIds.luau` | Roblox asset IDs for icons, sounds, animations, and meshes |

## Tech Stack

- **Luau** — all game logic
- **Rojo 7.6.1** — file sync between VS Code and Roblox Studio
- **DataStoreService** — player data persistence

## Project Structure

The codebase uses a **multi-place architecture**. Shared core code lives in `src/shared/` and is included by all places. Per-place scripts live in `src/places/<place>/`.

```
src/
  shared/                     -- Core code shared across all places
    config/                   -- GameplayConfig, ItemRegistry, StatsConfig, etc.
    server/                   -- PlayerStateService, InventoryService, CombatService, etc.
    client/                   -- HudController, InventoryController, PanelManager, CodexController, etc.
    character/                -- AvatarSetup (HipHeight, drift correction, freefall suppression)
    modules/                  -- Shared modules (TooltipModule)
  places/
    sandbox/                  -- Open-world sandbox place
      server/                 -- ScatterSpawnService, AnimalService, TreeService
      client/                 -- GatherController
    hospital/                 -- Hospital tutorial place
      server/                 -- PlaceInit
      client/                 -- FirstPersonCamera, crosshair UI
docs/                         -- System documentation
assets/raw/                   -- Source textures, audio (local only, not in repo)
sandbox.project.json          -- Rojo config for sandbox place
hospital.project.json         -- Rojo config for hospital place
CHANGELOG.md                  -- Version history
```

## Getting Started

### Prerequisites

- [Roblox Studio](https://www.roblox.com/create)
- [Rojo 7.6.1](https://github.com/rojo-rbx/rojo/releases) (CLI + Studio plugin must match)

### Setup

1. Clone the repo:
   ```bash
   git clone https://github.com/TemujinCalidius/TheCounterEarth.git
   cd TheCounterEarth
   ```

2. Start the Rojo sync server for the place you want to work on:
   ```bash
   # Sandbox (open-world)
   tools/rojo-7.6.1/rojo serve sandbox.project.json

   # Hospital (tutorial)
   tools/rojo-7.6.1/rojo serve hospital.project.json
   ```
   Stop one before starting the other (they share the default port).

3. Open your place in Roblox Studio, connect via the Rojo plugin, and hit Play.

### VS Code Sourcemap (for Luau LSP)

```bash
rojo sourcemap sandbox.project.json -o sourcemap.json
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — full system overview, data flow, and security model
- [Drag-and-Drop](docs/DRAG_AND_DROP.md) — coordinate spaces, ghost rendering, hit detection
- [Style Guide](docs/STYLE_GUIDE.md) — code conventions and patterns
- [Changelog](CHANGELOG.md) — version history

## Status

Early development. Core systems are functional and being tested with a small group before expanding.

## License

[MIT](LICENSE) -- Samuel Lison
