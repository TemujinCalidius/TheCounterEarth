# Skills & XP System Archive (placeholder state — 2026-03-28)

No skill progression was implemented. This documents the placeholder framework that existed.

---

## RPG Stats (6 base attributes)

Initialized to 0 on player join. Displayed in CHARACTER tab. Never modified by any system.

| Attribute Key | Name | Description |
|---|---|---|
| Stat_STR | Strength | Physical power |
| Stat_AGI | Agility | Speed & precision |
| Stat_CON | Constitution | Health & stamina |
| Stat_WIS | Wisdom | Survival intuition |
| Stat_INT | Intellect | Crafting & lore |
| Stat_CHA | Charisma | NPC pricing & diplomacy |

**Where defined:** `PlayerStateService.server.luau` lines 1326-1332
**Where displayed:** `InventoryController.client.luau` CHARACTER tab (lines 1194-1365)

---

## Profession Categories (external analytics only)

XP events were fired to the external API (`EventBridge`) with profession tags, but never tracked in-game.

| Profession | Triggered By | XP Formula | Source File |
|---|---|---|---|
| foraging | Picking up scatter items (twig, rock, mushroom) | yield * 5 | InventoryService.server.luau |
| woodcutting | Tree harvesting | yield * 5 | InventoryService.server.luau |
| mining | Boulder mining | yield * 5 | InventoryService.server.luau |
| crafting | Hand-crafting items | outputQty * 10 | InventoryService.server.luau |
| cooking | Campfire cooking | 10 (flat) | CampfireService.server.luau |

---

## Recipe Skill Requirements (unused)

All recipes had `skillLevel = 1` which was never validated.

**CraftingConfig recipes (10):**
stone_axe, stone_pickaxe, stone_knife, stone_spear, campfire, bedroll, satchel_reed, primitive_bow, arrow, arrow (x5)

**CookingConfig recipes (2):**
cooked_mushroom, cooked_venison

---

## CHARACTER Tab UI Layout

The inventory CHARACTER tab had two sections:
- **EQUIPMENT** (left): 6 slots — Head, Chest, Legs, Rings, Main Hand, Coin Pouch/Backpack/Quiver
- **ATTRIBUTES** (right): 6 stat boxes showing name, description, value

Equipment slots were functional (equip/unequip). Stat values always showed 0.

---

## What Was NOT Implemented

- No SkillService or XPService
- No skill leveling or XP accumulation
- No skill trees or progression paths
- No stat modification from any source
- No skill-gated recipe validation
- No in-game XP tracking (only external API events)
