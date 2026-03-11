<p align="center">
  <img src="assets/raw/screenshots/Alpha%20Logo.png" alt="The Counter Earth" width="600">
</p>

# The Counter Earth

A survival/roleplay framework for Roblox, built as a complete foundation that world builders can extend with their own maps, stories, and gameplay.

The Counter Earth ships as a ready-to-run Roblox experience with core survival mechanics, inventory management, and player progression systems already wired up. Creators drop it into their world, customize the config files, and focus on building the experience — not the plumbing.

## What's Included

- **Energy & Sprint** — stamina system with sprint drain, jump cost, and standing-still regeneration
- **Survival Stats** — hunger, thirst, and fatigue that drain over time with configurable penalties when depleted
- **Health System** — persistent health (no auto-regen), bleeding and poison status effects
- **Slot-Based Inventory** — weight-limited grid inventory with stacking, splitting, and crafting
- **Hotbar** — 9-slot quick-access bar (keys 1-9) with drag-to-reorder
- **Drag-and-Drop** — drag items between inventory slots, from inventory to hotbar, or drop to the world
- **Placeable Items** — ghost preview placement mode with range validation, campfire sitting with health/energy regen
- **Tool Pickup** — ProximityPrompt-based world item pickup with auto-hotbar assignment
- **HUD** — health/energy/survival bars, hotbar display, vignette and audio feedback
- **Persistence** — full DataStore save/load for all player data (credits, stats, inventory, hotbar)
- **Crafting** — recipe-based crafting system with server-side validation
- **Loot Bags** — items drop as lootable bags on death or manual drop

## For World Builders

The Counter Earth is designed as a starting point. The core systems handle:

- Player state, survival mechanics, and data persistence
- Inventory and item management with weight/stack limits
- Secure client-server communication with input validation
- HUD rendering and audio feedback

You bring the world: terrain, buildings, NPCs, quests, lore. Configure gameplay values in a few Luau files and build your experience on top of a tested foundation.

### Configuration

All gameplay values are centralized — no hunting through scripts:

| File | What It Controls |
|------|-----------------|
| `GameplayConfig.luau` | Energy, movement speeds, health, credits, hotbar, inventory, weight |
| `StatsConfig.luau` | Hunger, thirst, fatigue drain rates and penalties |
| `ItemRegistry.luau` | Item definitions (name, weight, stack size, category, effects) |
| `CraftingConfig.luau` | Crafting recipes and ingredients |
| `AssetIds.luau` | Roblox asset IDs for icons and audio |

## Tech Stack

- **Luau** — all game logic
- **Rojo 7.6.1** — file sync between VS Code and Roblox Studio
- **DataStoreService** — player data persistence

## Project Structure

```
src/
  ReplicatedStorage/Config/   -- Shared config (client + server)
  ServerScriptService/        -- Server scripts (state, inventory, tools)
  StarterPlayer/              -- Client scripts (HUD, inventory UI)
docs/                         -- System documentation
assets/raw/                   -- Source textures, audio (local only, not in repo)
default.project.json          -- Rojo project config
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

2. Start the Rojo sync server:
   ```bash
   rojo serve default.project.json
   ```
   Or if using the bundled binary:
   ```bash
   tools/rojo-7.6.1/rojo serve default.project.json
   ```

3. Open your place in Roblox Studio, connect via the Rojo plugin, and hit Play.

### VS Code Sourcemap (for Luau LSP)

```bash
rojo sourcemap default.project.json -o sourcemap.json
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — full system overview, data flow, and security model
- [Drag-and-Drop](docs/DRAG_AND_DROP.md) — coordinate spaces, ghost rendering, hit detection
- [Changelog](CHANGELOG.md) — version history

## Status

Early development. Core systems are functional and being tested with a small group before expanding.

## License

[MIT](LICENSE) -- Samuel Lison
