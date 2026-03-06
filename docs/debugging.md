# CooldownCursor — Debugging Guide

This guide covers the built-in debug tools added in the `Modules/Debug.lua` module.
All debug output is printed to the in-game chat window with an orange `[CC Debug]` prefix.

---

## Enabling Debug Mode

Debug mode is toggled with the slash command:

```
/cdc debug
```

- **ON** — all `Internal.DebugLog()` calls become active; events start recording to the buffer
- **OFF** — all output stops; event buffer stops recording

The flag is stored in `CooldownCursorDB.global.debugMode` and persists across sessions.
Turn it off when not actively developing to avoid chat spam.

### Event Logging (separate toggle)

Event printing to chat can be noisy. Toggle it independently with:

```
/cdc debug events
```

- **ON** — events print to chat as they fire (default when debug mode is first enabled)
- **OFF** — events are still recorded to the buffer silently; use `/cdc debug log` to inspect them

The flag is stored in `CooldownCursorDB.global.debugLogEvents`. Turning events off lets you
leave debug mode on for `DebugLog()` output without chat being flooded by every game event.

---

## Slash Commands

All debug subcommands follow the pattern `/cdc debug <subcommand>`.

| Command | Description |
|---|---|
| `/cdc debug` | Toggle debug mode on / off |
| `/cdc debug state` | Dump current addon state |
| `/cdc debug icons` | Dump all active icon frames |
| `/cdc debug rules` | Dump spell rules for your current class/spec |
| `/cdc debug spell <id>` | Full spell info lookup by spell ID |
| `/cdc debug pool` | Icon pool statistics |
| `/cdc debug events` | Toggle event printing on / off (events still recorded to buffer) |
| `/cdc debug log` | Show the last 50 events in the buffer |
| `/cdc debug cache` | Dump spell cache state (spellbook cache + knownSpellCache) |
| `/cdc debug filter` | Show active event filter |
| `/cdc debug filter <EVENT>` | Toggle an event name in/out of the filter |
| `/cdc debug filter clear` | Clear all filters (record all events again) |

---

## Subcommand Reference

### `state` — Addon State

Prints a snapshot of the key runtime values from `addonTable.State`:

```
inCombat          : true/false
previewActive     : true/false
optionsOpen       : true/false
playerClass       : WARRIOR / MAGE / etc.
activeIcons       : N (icons currently displayed)
iconPool          : N available, N allocated
activeProcSpells  : N
procCapableSpells : N
knownSpellCache   : N entries
cachedUIScale     : 1.0
cachedScreen      : 2560 x 1440
cachedIconSize    : 48
cachedAnchor      : TOPRIGHT
positionMode      : CURSOR / SCREEN
showBehavior      : 0 / 1 / 2
showWhen          : 0 / 1 / 2
```

**When to use:** Any time behaviour seems wrong — check `inCombat`, `showWhen`,
`showBehavior`, and `positionMode` first.

---

### `icons` — Active Icons

Lists every icon currently tracked in `State.iconsByPriority`:

```
[1] 12345  Frostbolt              prio:5  proc:false  procOnly:false  charges:false  shown  alpha:1.00  on-cd
[2] 11426  Ice Barrier            prio:3  proc:false  procOnly:false  charges:false  hidden alpha:0.00  off-cd
```

**Columns:**
- `[N]` — sort position (highest priority first by default)
- Spell ID and name
- `prio` — configured priority from spell rules
- `proc` — whether `procActive` is set on this icon
- `procOnly` — icon was created solely for a proc glow (no base cooldown)
- `charges` — whether this spell has charges
- `shown/hidden` — frame visibility
- `alpha` — current frame alpha (0.00 = invisible, 1.00 = fully visible)
- `on-cd / off-cd` — whether the cooldown swipe frame is active

**When to use:** Icons appearing or disappearing unexpectedly, alpha/visibility issues,
proc state not clearing correctly.

---

### `rules` — Spell Rules

Lists all spell rules configured for your current class and spec:

```
[12345] Frostbolt               on  | prio:5  | cd:3.0s  | charges:false | active
[11426] Ice Barrier             on  | prio:3  | cd:25.0s | charges:false | inactive
[55342] Mirror Image            off | prio:0  | cd:120.0s| charges:false | inactive
```

**When to use:** A spell isn't showing — check it appears here and is `on`. If it's
missing entirely, you need to add it via the Options UI or `/cdc` commands. If it shows
`inactive`, the addon isn't tracking it yet (hasn't been cast this session).

---

### `spell <id>` — Spell Info Lookup

Queries the full WoW API for a single spell ID and prints everything the addon uses to
make decisions about it:

```
/cdc debug spell 12345
```

Output:
```
[CC Debug] === Spell 12345 (Frostbolt) ===
[CC Debug] Icon ID   : 135846
[CC Debug] CastTime  : 2.0 sec
[CC Debug] Range     : 0 - 40
[CC Debug] Cooldown  : start: 0  duration: 0  enabled: true
[CC Debug] CD Dur    : nil (not on cooldown)
[CC Debug] Charges   : none
[CC Debug] Base CD   : 0  Base GCD: 1.5
[CC Debug] Usable    : true  InsufficientPower: false
[CC Debug] InRange   : nil
[CC Debug] Known     : true
[CC Debug] In Rules  : yes | enabled: true | priority: 5
[CC Debug] Active    : false
```

**Key fields:**

| Field | What it means |
|---|---|
| `CD Dur` | Return value of `C_Spell.GetSpellCooldownDuration()` — `nil` means the spell is not on cooldown right now. This is what the addon uses to decide whether to show an icon. |
| `Base CD` | Base cooldown in seconds from `GetSpellBaseCooldown()`. GCD-only spells show `0` here. |
| `InRange` | `nil` = range not applicable, `true` = in range, `false` = out of range. Out-of-range spells are suppressed unless `showBehavior` is `OFF_COOLDOWN`. |
| `Known` | Whether your character currently knows this spell. Unknown spells are skipped by the cache. |
| `In Rules` | Whether this spell has an entry in your class spell rules and whether it is enabled. |

**When to use:** A specific spell never shows an icon. Walk through the output — if
`Known` is false, `In Rules` is no/disabled, or `CD Dur` is nil after casting, you've
found the reason.

---

### `events` — Toggle Event Printing

```
/cdc debug events
```

Toggles whether events are printed to chat as they fire. Events are **always recorded** to
the ring buffer while debug mode is on — this toggle only controls the chat output.

Use this to silence the event flood while still being able to call `/cdc debug log` on demand.

---

### `log` — Show Event Buffer

Shows the last 50 events received by the `OnEvent` dispatcher, most recent at the bottom:

```
[ 1] ADDON_LOADED                               (2.34s ago) CooldownCursor
[ 2] PLAYER_ENTERING_WORLD                      (2.30s ago)
[ 3] SPELL_UPDATE_USABLE                        (1.12s ago)
[ 4] UNIT_SPELLCAST_SUCCEEDED                   (0.45s ago) player  12345
[ 5] SPELL_UPDATE_COOLDOWN                      (0.45s ago) 12345
```

> **Note:** The buffer only records events that fire **while debug mode is on**.
> If the buffer is empty after enabling debug, cast a spell or change zones to generate events.
> Event printing does **not** need to be on for the buffer to fill.

**When to use:** Verify that expected events are firing. If `SPELL_UPDATE_COOLDOWN`
never appears after casting, the event is not reaching the dispatcher.

---

### `cache` — Spell Cache State

```
/cdc debug cache
```

Output:

```
[CC Debug] === Spell Cache ===
[CC Debug] spellBookCache : 142 spells | age: 3.2s / 60s TTL
[CC Debug] knownSpellCache: 8 entries
[CC Debug] --- knownSpellCache (first 20) ---
[CC Debug]   [12345] Frostbolt               known:true
[CC Debug]   [11426] Ice Barrier             known:true
```

**Fields:**

| Field | What it means |
|---|---|
| `spellBookCache` | Result of the last `C_SpellBook` full scan. Shows entry count, how old the scan is, and whether it's still within the 60s TTL. If `EXPIRED`, the next call to `GetAllSpellBookSpells` will trigger a fresh scan. |
| `knownSpellCache` | Per-session cache of `C_SpellBook.IsSpellKnown()` results, keyed by spell ID. Wiped on `PLAYER_SPECIALIZATION_CHANGED`. |

**When to use:** A spell appears in rules but isn't showing — check if it's `known:true` in
the knownSpellCache. If the spellbook cache is stale or empty, the addon may not have
registered the spell yet.

---

### `pool` — Icon Pool Stats

```
[CC Debug] === Icon Pool ===
[CC Debug] Available  : 8
[CC Debug] Active     : 2
[CC Debug] Next ID    : 11
[CC Debug] Allocated  : 10
[CC Debug] Pool size  : 10
```

**When to use:** Investigating frame leaks or pool exhaustion. If `Allocated` keeps
growing well beyond `Pool size + Active`, frames are not returning to the pool correctly
(check `ReturnIconToPool` in `Core.lua`).

---

### `events` — Toggle Event Printing (duplicate reference)

See the [Events section](#events--toggle-event-printing) at the top of this reference, or the
[Log section](#log--show-event-buffer) for viewing the recorded buffer.

**Quick reminder:**

- `/cdc debug events` — toggles whether events print to chat
- `/cdc debug log` — shows the last 50 recorded events regardless of the print toggle

---

### `filter` — Event Filter

Restricts the event log to only specific events. The filter is **in-memory** — it resets
on `/reload` or logout, so it won't affect production sessions.

```text
/cdc debug filter                            -- show active filter
/cdc debug filter SPELL_UPDATE_COOLDOWN      -- add or remove one event
/cdc debug filter UNIT_SPELLCAST_SUCCEEDED   -- toggle a second event
/cdc debug filter clear                      -- clear all filters
```

With no filter set, all events are recorded (default). When one or more events are added,
only those pass through — the rest are silently dropped before reaching the ring buffer.

The active filter is shown in the `/cdc debug log` header:

```text
[CC Debug] === Event Log (3/50) [filter: SPELL_UPDATE_COOLDOWN] ===
[CC Debug] === Event Log (7/50) [2 filters] ===
```

**When to use:** You know which event you're tracking and don't want the buffer filled
with unrelated events. For example, when debugging charge recovery you might filter to
`SPELL_UPDATE_CHARGES` only.

---

## `Internal.DebugLog` — Logging from Other Modules

Any module can conditionally log to the debug output:

```lua
local DebugLog = Internal.DebugLog  -- already exported by Debug.lua

-- Somewhere in your module:
DebugLog("ShowSpellIcon called for spellID:", spellID, "duration:", durationObj)
```

`DebugLog` is a no-op when debug mode is off, so it is safe to leave calls in place
during development. Remove them before releasing.

---

## Common Debugging Scenarios

### "My spell never shows an icon"

1. `/cdc debug rules` — is the spell listed and enabled?
2. `/cdc debug spell <id>` — is it `Known`? Is `CD Dur` returning a value after casting?
3. `/cdc debug events` — does `UNIT_SPELLCAST_SUCCEEDED` fire when you cast it?
4. `/cdc debug state` — is `showWhen` or `showBehavior` suppressing it?

### "Icons disappear immediately after appearing"

1. `/cdc debug state` — check `showBehavior` (0 = ON_COOLDOWN removes icon when CD ends)
2. `/cdc debug icons` — check `on-cd` column right after casting
3. `/cdc debug spell <id>` — check `CD Dur` — a spell with no real cooldown will be removed immediately in ON_COOLDOWN mode

### "Proc icon not showing / not hiding"

1. `/cdc debug state` — confirm `activeProcSpells` count changes when the proc fires
2. `/cdc debug icons` — check `proc` and `procOnly` columns
3. `/cdc debug events` — look for `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` / `_HIDE` events
4. Check Options UI — `showProcs` must be enabled

### "Icon position is wrong after scaling the UI"

1. `/cdc debug state` — check `cachedUIScale`, `cachedScreen`, `cachedAnchor`
2. Trigger a refresh: change UI scale or run `/cdc debug state` again after
   `UI_SCALE_CHANGED` or `DISPLAY_SIZE_CHANGED` fires
3. `cachedAnchorOX / OY` are pre-computed in `RefreshCachedSettings` (Cursor.lua) —
   if the anchor is unexpectedly flipping, the screen boundary calculations in
   `UpdateCooldownIconFrame` are the place to look

---

## File Reference

| File | Role |
|---|---|
| [Modules/Debug.lua](../Modules/Debug.lua) | All debug functions and event log |
| [Init.lua](../Init.lua) | Event dispatcher — calls `Internal.LogEvent` on every event |
| [Slash.lua](../Slash.lua) | `/cdc debug` command entry point |
| [Core.lua](../Core.lua) | `addonTable.State` definition |
| [Modules/Cooldown.lua](../Modules/Cooldown.lua) | `GetSpellRule`, `ApplyShowBehavior` |
| [Modules/Icons.lua](../Modules/Icons.lua) | `ShowSpellIcon`, `RemoveIconForSpell`, pool management |
| [Modules/Cursor.lua](../Modules/Cursor.lua) | `UpdateCooldownIconFrame`, `RefreshCachedSettings` |
| [Modules/Anchor.lua](../Modules/Anchor.lua) | Screen anchor, `ApplyPositionMode` |
