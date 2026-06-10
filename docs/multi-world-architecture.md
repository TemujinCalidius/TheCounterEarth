# The Counter Earth — Multi-World Architecture Design

> **Status:** Design document. No code in this doc has been implemented yet.
> Last updated: 2026-06-10.

This document captures the architecture for multi-world gameplay in The Counter Earth — how players move between zones, how groups stay together, how density is shaped per zone, how subscription-only personal worlds work, and how dungeon matchmaking happens across all running instances.

It is written so that future-me (or any collaborator) can re-derive the design without losing the reasoning. **Concepts come before code.** Most of this is plumbing on top of three Roblox APIs (`TeleportService`, `MemoryStoreService`, `MessagingService`) — once the foundation is built, each new feature is mostly a different key + a different rule.

---

## Table of Contents

1. [The problem space](#the-problem-space)
2. [Roblox primitives this design uses](#roblox-primitives-this-design-uses)
3. [The shared mental model](#the-shared-mental-model)
4. [Four-tier zone crossing logic](#four-tier-zone-crossing-logic)
5. [Density-shaped instance pools](#density-shaped-instance-pools)
6. [Personal subscription worlds](#personal-subscription-worlds)
7. [Parties (cross-server group state)](#parties-cross-server-group-state)
8. [Dungeon LFG (cross-server matchmaking)](#dungeon-lfg-cross-server-matchmaking)
9. [The shared primitive — why it composes](#the-shared-primitive--why-it-composes)
10. [Gotchas and edge cases](#gotchas-and-edge-cases)
11. [Implementation phasing](#implementation-phasing)
12. [Cost model](#cost-model)
13. [Open questions](#open-questions)

---

## The problem space

The game is structured as **many separate worlds** (Roblox Places), each containing its own zones, NPCs, harvest nodes, and lore. Players cross between worlds at zone boundaries. At any moment, each world is running across some number of **instances** (Roblox servers), and the same world may have several instances running in parallel.

The design goals shape every decision below:

| Goal | Why it matters |
|---|---|
| **Group continuity** | A party that crosses a boundary together should still be a party in the next world |
| **Chase continuity** | A pursuer who follows a victim through a portal should land in the same world as them |
| **Neighborhood persistence** | The community in W3/I65 should *tend* to flow into the same W4 instance, creating recognisable crowds across worlds |
| **Density shaping** | Cities feel alive (packed), wilderness feels sparse (atmospheric), without the player ever seeing a config |
| **Subscription worlds** | Premium subscribers own a persistent personal world they can return to, with whitelist control |
| **Cross-server LFG** | Players spread across all running instances can queue for a dungeon and end up in the same dungeon instance |
| **No infrastructure costs** | The whole system runs on Roblox's primitives — zero ongoing compute cost to us |

Notably *not* a goal: every player in the same world instance. That's the "MMO single shard" pattern (think EVE Online) and it's neither possible nor desirable on Roblox. Instead we aim for **good clustering** — the right groups end up together most of the time.

---

## Roblox primitives this design uses

Three Roblox services do the heavy lifting. Everything else is composition.

### `TeleportService` — cross-place/server transport

The fundamentals:

- **`TeleportService:ReserveServer(placeId)`** → returns `(accessCode, privateServerId)`. The access code is a string that grants entry to a specific server instance. **Access codes are permanent until you regenerate.** This is the foundation of every "send a group to the same place" pattern.
- **`TeleportService:TeleportToPrivateServer(placeId, accessCode, players, spawnName?, teleportData?)`** — sends a list of players to the specific server identified by that code. Multiple players can be teleported there at different times.
- **`TeleportService:TeleportPartyAsync(placeId, players)`** — Roblox's built-in "teleport these players together" call. Internally similar to ReserveServer + TeleportToPrivateServer but auto-manages the access code. Simpler when you don't need persistence of the destination.
- **`TeleportService:Teleport(placeId, player)`** — single-player teleport, lands in whatever instance Roblox picks. Used as a fallback.

Important: a "reserved server" isn't truly reserved at the API level — it's just an instance addressable by access code. Anyone with the code can enter, up to MaxPlayers. The access code IS the "permission".

### `MemoryStoreService` — cross-server shared state with TTL

The fundamentals:

- **`MemoryStoreService:GetHashMap(name)`** — a key/value store. Each value can have an independent TTL (1 second to 30 days). Atomic updates via `UpdateAsync`. Reads are eventually consistent across servers but typically replicate within seconds.
- **`MemoryStoreService:GetSortedMap(name)`** — same as HashMap but with sortable scores. Useful for matchmaking queues.
- **`MemoryStoreService:GetQueue(name)`** — FIFO queue.

For us the TTL is the magic — *the engine deletes entries automatically*. No cleanup logic, no timers, no leak risk. Every cross-server primitive in this design uses a HashMap + TTL.

### `MessagingService` — cross-server publish/subscribe

The fundamentals:

- **`MessagingService:PublishAsync(topic, message)`** — broadcasts to every server that has subscribed to `topic`.
- **`MessagingService:SubscribeAsync(topic, callback)`** — listens for messages on a topic.
- Messages have a ~1 second latency typically, limited size (~1KB), and rate-limited (~150 messages/min/topic).

Use MemoryStore for shared *state*. Use MessagingService for shared *events*. Common combo: a matchmaker server holds queue state in MemoryStore, then broadcasts "you've been matched, teleport now" via MessagingService.

---

## The shared mental model

Every multi-world pattern in this design boils down to:

> **Give somebody an access code with a TTL, then let them choose to use it.**

The four design features differ in:

- Who issues the access code
- Who gets to use it
- How long they have to use it
- What happens when the TTL expires

That's the entire architecture. Here's how each feature maps:

| Feature | Who gets the code | TTL | What expires means |
|---|---|---|---|
| **Personal world** | The owner; whitelist; invited friends | Indefinite (stored in DataStore too) | N/A — code persists across sessions |
| **Party crossing** | All online party members | Long (refreshed while party active) | Party member can no longer follow into same instance |
| **Proximity ticket** | Players within X studs of the crosser | 60s | "Chase window" closes; pursuer goes to a different instance |
| **Source-instance affinity** | Anyone from a specific source instance | 30 min (refreshed on use) | Source community has dispersed |
| **Dungeon match** | The matched group from the queue | 60s after match | Group has had time to teleport; if they didn't, queue them again |

One primitive, five rule sets.

---

## Four-tier zone crossing logic

When a player walks through a zone boundary, the server runs through four tiers of preference in order. Each tier is a check; the first one that succeeds wins.

```
Player crosses boundary into destination Place D
   │
   ├─ Tier 1: Do I hold a personal "follow" ticket?
   │     └─ Yes → TeleportToPrivateServer(D, ticket.accessCode, {me})
   │              (proximity hold from a friend who just crossed)
   │
   ├─ Tier 2: Does my source instance have an affinity to D?
   │     ├─ Yes, and destination has space → use that accessCode
   │     │   (preserves community across worlds)
   │     └─ Yes but destination full → fall through
   │
   ├─ Tier 3: Density-shaped matchmaking
   │     ├─ Find all running instances of D
   │     ├─ Sort by population
   │     ├─ Find first one under soft cap → send player there
   │     │   (or under hard cap if all soft caps reached)
   │     └─ All instances at hard cap → fall through
   │
   └─ Tier 4: Brand-new instance
         ├─ TeleportService:ReserveServer(D) → accessCode
         ├─ Issue Tier 1 tickets to players within X studs of me
         ├─ Write Tier 2 affinity entry for my source instance
         └─ TeleportToPrivateServer(D, accessCode, {me})
```

### Tier 1 in detail — proximity tickets

When a player crosses a boundary and **creates a new instance** (Tier 4), they issue tickets to nearby players. These tickets are stored in MemoryStore HashMap keyed by `userId`.

```lua
local PROXIMITY_TICKET_TTL = 60  -- seconds
local NEARBY_RADIUS_STUDS = 60

for _, nearby in findPlayersWithin(crossingPlayer, NEARBY_RADIUS_STUDS) do
    if nearby ~= crossingPlayer then
        tickets:SetAsync(
            tostring(nearby.UserId),
            { accessCode = newAccessCode, issuedBy = crossingPlayer.UserId },
            PROXIMITY_TICKET_TTL
        )
    end
end
```

When *those* players cross the boundary within 60 seconds, they find their ticket and join the same instance.

**Why tickets, not auto-teleport:** the user explicitly designed this not to drag bystanders through. A player gathering wood near the boundary doesn't want to be yanked into another world. They have a ticket waiting if they *choose* to follow; otherwise it evaporates harmlessly.

### Tier 2 in detail — source-instance affinity

When a fresh reservation is created (Tier 4), the server also writes an **affinity entry** keyed by source instance:

```lua
local AFFINITY_TTL = 1800  -- 30 minutes, refreshed on every use

affinities:SetAsync(
    string.format("%d:%s->%d", sourcePlaceId, sourceJobId, destPlaceId),
    { accessCode = newAccessCode, createdAt = os.time() },
    AFFINITY_TTL
)
```

Now any other player from `sourcePlaceId/sourceJobId` who crosses to `destPlaceId` will find this affinity entry and use the same access code — joining the same destination instance.

The TTL refresh keeps this alive as long as traffic keeps flowing:

```lua
-- When affinity is used
local affinity = affinities:GetAsync(key)
if affinity then
    pcall(TeleportToPrivateServer, ...)
    affinities:SetAsync(key, affinity, AFFINITY_TTL)  -- reset TTL
end
```

If no one crosses for 30 minutes, the affinity expires — by which point the destination instance has likely repopulated with other crowds anyway.

### Tier 3 in detail — density matchmaking

Only relevant when Tier 1 and Tier 2 both miss. Reads the **instance registry** (see [Density-shaped instance pools](#density-shaped-instance-pools)) to find a destination instance that has room under the soft cap. If all soft caps are exceeded, falls through to hard caps. If all hard caps exceeded, falls through to Tier 4 (new instance).

### Tier 4 in detail — fresh instance

The fall-through. Reserves a new server, issues tickets + affinity for the newcomer's source.

---

## Density-shaped instance pools

Roblox's default matchmaking is "first available with room." That's fine for some games. For an MMO with distinct *zone vibes* — busy cities, lonely forests — we want **per-Place population targets** that shape feel.

### Per-Place soft/hard caps

```lua
local POPULATION_TARGETS = {
    [CITY_PLACE_ID]       = { soft = 80,  hard = 100 },  -- packed, alive
    [MARKETPLACE_ID]      = { soft = 60,  hard = 100 },  -- busy hub
    [WILDERNESS_PLACE_ID] = { soft = 12,  hard = 30  },  -- room to roam
    [DEEP_FOREST_ID]      = { soft = 6,   hard = 20  },  -- solitude
    [DUNGEON_ID]          = { soft = 5,   hard = 5   },  -- exact party
    [HOUSING_DISTRICT_ID] = { soft = 40,  hard = 60  },  -- friendly neighborhood
}
```

Behaviour:

- **Soft cap = preferred fill level.** Below soft cap, new players prefer to join this instance.
- **Hard cap = absolute maximum.** Above hard cap, no one new joins this instance.
- **Below soft cap → fill up.** Above soft cap but below hard → only fill if no other instance is below soft. Above hard → never.

Result: cities funnel into 1–2 packed instances. Wilderness spreads across many sparse instances. Each Place has its own feel.

### Instance registry

For Tier 3 to work, every running server needs to advertise its population to other servers. Each server registers itself in a MemoryStore HashMap on startup and refreshes every 30 seconds:

```lua
local registry = MemoryStoreService:GetHashMap("InstanceRegistry")

local function registerSelf()
    registry:SetAsync(game.JobId, {
        placeId       = game.PlaceId,
        accessCode    = thisServerAccessCode,  -- if this is a reserved server
        population    = #Players:GetPlayers(),
        lastUpdate    = os.time(),
    }, 90)  -- TTL = 90s, refreshed every 30s — server crash auto-deregisters
end

task.spawn(function()
    while true do
        registerSelf()
        task.wait(30)
    end
end)
```

Note: only servers reachable via `accessCode` are useful for cross-server teleport. Public (non-reserved) servers are reachable via `Teleport` but you can't pick *which* public instance — Roblox does that.

For full control, **every instance should be a reserved server** (created via `ReserveServer`). This means the very first player crossing into a Place creates the first instance; subsequent players are routed via the registry.

### Dynamic targets

Caps don't have to be static. They can swing based on time of day, day of week, events:

```lua
local function getTargets(placeId)
    local base = POPULATION_TARGETS[placeId]
    local now = os.date("*t")
    
    -- Quiet hours (3am–6am local): cities feel sparse
    if now.hour >= 3 and now.hour <= 6 then
        return { soft = math.floor(base.soft * 0.4), hard = math.floor(base.hard * 0.6) }
    end
    
    -- Weekend prime time: more crowding allowed
    if isWeekend(now) and now.hour >= 14 and now.hour <= 20 then
        return { soft = math.floor(base.soft * 1.3), hard = base.hard }
    end
    
    -- Active world event: festival-level density
    if isEventActive(placeId) then
        return { soft = base.hard, hard = base.hard }
    end
    
    return base
end
```

### Special-purpose density pools

The cap data is per-Place, but routing can also branch on player attributes:

| Pool | Purpose |
|---|---|
| **Premium tier** | Subscribers get routed to lighter-loaded instances (perceived perk) |
| **New player sanctuary** | Players with `survivalSeconds < 3600` route to "tutorial" cities — quieter, lower-level NPCs |
| **Level brackets** | "L1–10" and "L11+" instances of the same Place — beginners not drowned by veterans |
| **PvP zone caps** | Wilderness PvP zones hard-capped at 8 to prevent zerg ambushes |
| **Event reservations** | Holiday parade routes all city traffic to 10 pre-reserved instances |

These are **data + routing rules**, not separate infrastructure.

---

## Personal subscription worlds

Subscribers get a persistent personal world (their own Place's instance) that they can return to, decorate, farm in, and whitelist others into.

### Architecture

```
On subscription purchase:
  ├─ MarketplaceService confirms subscription status
  └─ DataStore record created:
        profile.personalWorld = {
            placeId = PERSONAL_WORLD_PLACE_ID,
            accessCode = TeleportService:ReserveServer(PERSONAL_WORLD_PLACE_ID),
            whitelist = { userIds },
            layout = { buildings, farms, etc. (saved on departure) },
        }

Player teleports to personal world:
  ├─ Look up profile.personalWorld.accessCode
  ├─ TeleportToPrivateServer(placeId, accessCode, {player})
  └─ On arrival: server loads layout from DataStore, builds the world

Player leaves personal world:
  ├─ Server saves current layout to DataStore
  └─ Server saves last position, etc.

Whitelist guest tries to enter:
  ├─ Owner's MessagingService listens for "guest_request" events
  ├─ Or whitelist contains the guest's userId
  └─ TeleportToPrivateServer(placeId, accessCode, {guest})
```

### Key Roblox APIs

- **`MarketplaceService:GetUserSubscriptionStatusAsync(player, subscriptionId)`** — verifies premium status. Roblox added native paid subscriptions in 2024 — this is THE supported path. Returns `IsSubscribed`, `ExpireTime`.
- **`TeleportService:ReserveServer`** — creates the personal world instance. Done once per owner.
- **`DataStoreService`** — stores the access code, whitelist, and serialised world layout per owner.

### Why the access code goes in DataStore

Reserved server access codes are permanent — if you lose one, you can't recover it without regenerating (which makes a different server). So the moment we create the personal world, **DataStore the access code immediately, before anything else**. This is the authoritative record of "what world is owner X's world."

### Whitelist enforcement

When a non-owner arrives at the personal world's server (via their friend teleporting them in), the server checks:

```lua
Players.PlayerAdded:Connect(function(player)
    if not isOwner(player) and not whitelist[player.UserId] then
        player:Kick("This is a private world and you are not on the whitelist.")
    end
end)
```

### World layout persistence

Buildings, farms, placed items are serialised on player departure and stored in DataStore. On next entry, the same world is rebuilt server-side from the serialised state. This is exactly the same pattern as Bloxburg, Adopt Me's gardens, and many similar games.

---

## Parties (cross-server group state)

A party is a group of players who want to stay together across world transitions, even if they're momentarily in different instances.

### Architecture

Each party has a record in MemoryStore:

```lua
parties:SetAsync("party:" .. partyId, {
    leader = leaderUserId,
    members = { userId1, userId2, ... },
    formed = os.time(),
    formationPlace = formationPlaceId,
}, PARTY_TTL)
```

When any party member crosses a world boundary:

- Tier 1 (their proximity ticket if it exists) → take precedence
- Otherwise: server checks if any other party member is online and currently on the same source instance
- If yes: that member's destination becomes the affinity destination for the rest
- If no: create new reservation, issue tickets to **all online party members** regardless of physical proximity (party trumps distance)

Party invites broadcast cross-server via MessagingService:

```lua
MessagingService:PublishAsync("party_invite", {
    fromUserId = invitingPlayer.UserId,
    fromName = invitingPlayer.Name,
    toUserId = invitedUserId,
    partyId = partyId,
})
```

Every server subscribed to `party_invite` filters by `toUserId == localPlayer.UserId` and shows a UI prompt to the invited player. If they accept, their server writes them into the party's MemoryStore record.

### Why MemoryStore (not DataStore) for parties

Parties are session-scoped — they don't need to survive a 24-hour offline period. MemoryStore is faster and TTL-managed; DataStore is overkill and slower. Party state evaporates after extended inactivity, which is the correct behaviour.

For *persistent* social groups (guilds, families), use DataStore. Parties are ad-hoc and ephemeral.

---

## Dungeon LFG (cross-server matchmaking)

Players spread across many world instances queue for a specific dungeon. The system gathers enough of them, reserves a dungeon server, and teleports them all in together.

### Architecture

```
Player interacts with a "Gathering Stone" near the dungeon entrance:
   ├─ UI lets them queue for a specific dungeon
   └─ Server writes a queue entry:
        queue:SetAsync(player.UserId, {
            dungeon = "crypts_of_echo_hollow",
            level = playerLevel,
            role = "tank",  -- if role-based
            queuedAt = os.time(),
        }, QUEUE_TTL)  -- if they go offline or cancel, entry expires

Background matchmaker loop (runs on any server with capacity, leader-elected):
   ├─ Polls the queue every 5 seconds
   ├─ When enough players + role balance is satisfied:
   │     ├─ ReserveServer(DUNGEON_PLACE_ID) → accessCode
   │     └─ Publish via MessagingService:
   │           topic: "dungeon_match_ready"
   │           data: { userIds, accessCode, dungeonPlaceId }
   └─ Each player's home server receives, teleports them
```

### Leader election (which server runs the matchmaker?)

You don't want every server polling — wasted resource. Standard pattern: the first server to claim a "matchmaker_leader" key in MemoryStore (with short TTL) is the leader for the next ~30 seconds. It refreshes the lease while it's alive. If it dies, another server claims after lease expiry.

```lua
local LEADER_TTL = 30
local IS_LEADER = false

task.spawn(function()
    while true do
        local won = pcall(function()
            leases:UpdateAsync("matchmaker_leader", function(current)
                if current == nil or current.serverJob == game.JobId then
                    return { serverJob = game.JobId, claimedAt = os.time() }
                end
                return nil  -- don't update, someone else is leader
            end, LEADER_TTL)
        end)
        IS_LEADER = won
        if IS_LEADER then runMatchmakerTick() end
        task.wait(5)
    end
end)
```

### Queue entry TTL

Players who go offline or leave the area should auto-leave the queue. Their queue entries have a TTL refreshed by the player's home server while they're online:

```lua
-- On their home server, every 30s while queued:
queue:SetAsync(player.UserId, queueEntry, QUEUE_TTL)
```

If the home server stops refreshing (because they teleported away, logged out, etc.), the TTL drops and the entry vanishes.

### Composition with other systems

A player matched into a dungeon gets:

- A dungeon access code (single-use 60s ticket)
- Auto-teleported into the dungeon instance with their party (if any)
- On dungeon completion, returned via TeleportService to a hub world

The four-tier crossing logic is bypassed for dungeon teleports — match → teleport, no soft caps needed (dungeons are sized exactly N).

---

## The shared primitive — why it composes

Every multi-world feature in this design uses the same plumbing:

```
1. Reserve a server, get access code
2. Write the access code into MemoryStore HashMap with a TTL, keyed by "who can use it"
3. The key-holder presents the code, gets teleported into that specific instance
```

What changes per feature is *just the key shape and TTL*:

| Feature | Key | TTL | Issuer | Holder |
|---|---|---|---|---|
| Personal world | `personal:{ownerId}` | Indefinite (DataStore-backed) | World creator | Owner + whitelist |
| Party crossing | `party_ticket:{userId}` | Party-lifetime | Party leader's server | Party member |
| Proximity ticket | `prox_ticket:{userId}` | 60s | Crossing player's server | Nearby player |
| Instance affinity | `aff:{srcPlace}:{srcJob}->{destPlace}` | 30min refresh | First fresh-reservation crosser | Anyone from source |
| Dungeon match | `match_ticket:{userId}` | 60s | Matchmaker | Matched player |

You build the foundation once. Each subsequent feature is "different key + different rule about when to write it." This is why I keep saying the four design goals share infrastructure — they're literally the same code with different parameters.

---

## Gotchas and edge cases

### Server full at the moment of teleport

`TeleportToPrivateServer` will silently fail (or raise an error wrapped in pcall) if the destination server is at MaxPlayers. Handle:

```lua
local ok, err = pcall(
    TeleportService.TeleportToPrivateServer,
    TeleportService, destPlaceId, accessCode, {player}
)
if not ok then
    -- Fall through to next tier or normal teleport
    TeleportService:Teleport(destPlaceId, player)
end
```

### Affinity destination becomes stale

A source instance's affinity points at destination Y. Y becomes full. New crosser from source can't fit. Falls through to Tier 3 (density routing), which spawns new instance Z. **Now half the source community is in Y, half in Z** — a split.

Mitigation: when a fresh reservation is created, *overwrite* the existing affinity entry to point to the new instance. Old crossers already in Y stay; new crossers (and the source community's gradually-shifting "center of mass") move to Z. The split narrows over time as people leave Y naturally.

### Bidirectional bonding

Default design only writes "outgoing" affinity (W3/I65 → W4 = I30). Players returning W4 → W3 don't necessarily land back in I65.

To enable bidirectional bonding:
- On teleport, attach `TeleportOptions.SetTeleportData({ sourcePlaceId, sourceJobId })`
- The destination server reads this on player arrival and writes the *return* affinity: `aff:{W4}:{I30}->{W3}` = `accessCode_for_I65` (if still alive)
- On return crossing, the W4 server checks this affinity, sends them back to I65

Adds complexity. Worth it if "community bonds across world journeys" is high-value.

### Leader election split-brain

If MemoryStore replication lag temporarily creates two leaders, both might try to match. Race conditions are mostly benign (worst case: a player gets matched twice, which is handled by checking if they're still in queue before sending the teleport). Worth a `pcall` guard but not catastrophic.

### Ghost personal worlds

A subscriber lapses, doesn't renew. Their personal world's access code is still in their DataStore. Two options:

- **Soft retention** — keep the world available read-only for 30 days; can't modify, can be visited (good for goodwill)
- **Hard expiry** — owner is locked out, world is eventually purged after 90 days

Roblox's `GetUserSubscriptionStatusAsync` returns `ExpireTime`, which lets you implement either.

### Cross-server data race for party membership

Two players invite each other simultaneously. MemoryStore atomicity (`UpdateAsync`) handles this — only one update wins. The losing invite gets a "this user is already in a party" error and shows a friendly message.

### Public servers polluting the registry

Tier 3 reads the instance registry. If non-reserved (public) servers register too, the algorithm might try to teleport to a public server via `TeleportToPrivateServer` and fail (no access code).

Solution: only register reserved servers. Make the first crosser into a Place create the first reserved instance.

---

## Implementation phasing

Don't build this all at once. Each phase delivers value, validates the previous one, and unblocks the next.

### Phase 0 — Prerequisites (already done ✓)

- Sandbox + Hospital places exist (multi-place Rojo setup) ✓
- DataStore persistence working ✓
- Character spawn flow under our control ✓

### Phase 1 — Basic cross-place teleport

**Goal:** Walk from sandbox to hospital and back via portals.

- Portal Part with `Touched` connection in sandbox → `TeleportService:Teleport(HOSPITAL_PLACE_ID, player)`
- Portal in hospital → back to sandbox
- No instance affinity, no parties, no density — just basic transport

**Why first:** validates that cross-place teleport itself works in your project. Get the simple case right before adding complexity.

### Phase 2 — Reserved server + affinity (Tier 2 and 4)

**Goal:** Players crossing together end up in the same destination instance.

- Replace `Teleport` with `ReserveServer` + `TeleportToPrivateServer`
- Instance registry MemoryStore HashMap
- Source-instance affinity HashMap with 30-min TTL
- Two players crossing sandbox → hospital within 30 minutes land in the same hospital instance

**Why next:** the affinity layer alone delivers the "community persists" feel for free without proximity tickets or parties.

### Phase 3 — Proximity tickets (Tier 1)

**Goal:** Chase mechanics. Players near a crosser get a 60s window to follow into the same instance.

- Add `findPlayersWithin` helper
- Write proximity tickets to MemoryStore on fresh reservation
- Check tickets before affinity on crossing

### Phase 4 — Density-shaped matchmaking (Tier 3)

**Goal:** Cities feel packed, wilderness feels sparse.

- Per-Place soft/hard cap config
- Registry-driven instance selection on Tier 3
- Dynamic target overrides (time of day)

### Phase 5 — Party system

**Goal:** Explicit groups that stay together.

- Party formation UI (invite, accept, leave)
- Party state in MemoryStore
- MessagingService for cross-server invites
- Party tickets written on crossing

### Phase 6 — Personal worlds

**Goal:** Subscribers own a persistent world.

- Subscription product setup in Roblox dashboard
- Personal world Place created (new Place in the universe)
- World layout serialisation to DataStore
- Whitelist enforcement
- Owner-only edit mode UI

### Phase 7 — Dungeon LFG

**Goal:** Cross-server matchmaking for dungeons.

- Gathering Stone interactable + queue UI
- Queue in MemoryStore
- Matchmaker leader election
- Match notification + auto-teleport
- Dungeon completion → return teleport

Phases 1–4 form the **core multi-world foundation**. 5–7 are features built on top, each independently shippable.

---

## Cost model

Why this design is essentially free on Roblox:

| Resource | Cost to us |
|---|---|
| Server compute (instances) | $0 — Roblox runs them on their infrastructure |
| Scaling up (more players → more instances) | $0 |
| Reserved server storage (access codes are tiny strings) | $0 |
| `MemoryStoreService` usage | Free within Roblox's generous limits (1000 requests/min/server, plenty for our scale) |
| `MessagingService` usage | Free within limits (150 messages/min/topic) |
| `DataStoreService` usage | Free within limits |
| External HTTP (your EventBridge to Discord etc.) | Bandwidth measured in pennies; rate-limited by you |

The Counter Earth scales from 1 to 100,000 concurrent players without us paying for a single VM, load balancer, or database row. Roblox's economic model:

- They take a cut of in-game purchases + Premium subscriptions
- Their incentive is for our game to be popular and scale
- Their incentive aligns with ours

This is exactly the opposite of Second Life / Linden Labs, where:

- You buy region/sim subscriptions monthly
- Scaling costs *you* directly
- Adding more concurrent players hurts your margin

It's the most creator-friendly multiplayer-platform economics in the industry. Worth knowing because **the design above is only economically viable on Roblox**. On most other engines you'd have to build this against a paid backend (AWS GameLift, PlayFab, etc.) and pay for every concurrent player.

---

## Open questions

Things to decide before serious implementation:

1. **Affinity scope** — outgoing only, or bidirectional? (Affects design complexity)
2. **PvP zone caps** — separate from PvE wilderness caps?
3. **Group size limits** — max party size? 4? 6? 8?
4. **Subscription expiry policy** — soft retention or hard purge for personal worlds?
5. **Whitelist UI for personal worlds** — full friends-list integration, or manual UserId entry, or both?
6. **Dungeon difficulty tiers** — single dungeon queue per dungeon, or tier-aware (Easy/Normal/Hard)?
7. **Cross-region considerations** — Roblox has regional data centers; players in EU might get teleported to a US server depending on instance selection. Worth surfacing as an option? Or let Roblox handle automatically?
8. **Loadout-on-spawn** — when a player arrives in a new world, do they spawn at the world's main spawn, or at a portal-specific arrival point? (Affects portal Part design)
9. **Failed teleport UX** — when all four tiers fail (extremely rare), what do we show the player? "World full, try again in a minute"?

These don't block design or Phase 1 — they're decisions to make as we build each phase.

---

## Reference — relevant Roblox API documentation

For implementation, the authoritative references are:

- [TeleportService](https://create.roblox.com/docs/reference/engine/classes/TeleportService) — `ReserveServer`, `TeleportToPrivateServer`, `TeleportPartyAsync`, `TeleportOptions`
- [MemoryStoreService](https://create.roblox.com/docs/reference/engine/classes/MemoryStoreService) — `GetHashMap`, `GetSortedMap`, `GetQueue`
- [MessagingService](https://create.roblox.com/docs/reference/engine/classes/MessagingService) — `PublishAsync`, `SubscribeAsync`
- [MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService) — `GetUserSubscriptionStatusAsync`
- [DataStoreService](https://create.roblox.com/docs/reference/engine/classes/DataStoreService) — already used extensively in this project

URLs valid as of doc write (2026-06-10).

---

## Document version history

- **2026-06-10** — initial draft. Captures the architecture from conversation discussion. No code yet.
