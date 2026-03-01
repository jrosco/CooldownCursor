----------------------------------------------------
-- CooldownCursor: Debug Module
-- Development helpers, state inspection, event logging
----------------------------------------------------
local _, addonTable = ...

local State = addonTable.State
local Internal = addonTable.Internal

local PREFIX = "|cffff9900[CC Debug]|r"
local MAX_EVENT_LOG = 50

----------------------------------------------------
-- Helpers
----------------------------------------------------
local debugMode      = false  -- resets to false on every reload
local debugLogEvents = true   -- event printing defaults on when debug is enabled

local function IsDebugEnabled()
  return debugMode
end

local function IsEventLoggingEnabled()
  return debugMode and debugLogEvents
end

local function DebugLog(...)
  if not IsDebugEnabled() then return end
  print(PREFIX, ...)
end

local function CountTable(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

----------------------------------------------------
-- Event log (ring buffer) + filter
----------------------------------------------------
local eventLog    = {}
local eventFilter = {}  -- set of uppercase event names; empty = all events pass

local function PassesFilter(event)
  return next(eventFilter) == nil or eventFilter[event] == true
end

local function LogEvent(event, ...)
  if not IsDebugEnabled() then return end
  if not PassesFilter(event) then return end
  if #eventLog >= MAX_EVENT_LOG then
    table.remove(eventLog, 1)
  end
  table.insert(eventLog, { time = GetTime(), event = event, args = { ... } })
  -- Only print to chat if event logging is enabled (separate toggle)
  if IsEventLoggingEnabled() then
    DebugLog("EVENT:", event, ...)
  end
end

----------------------------------------------------
-- Debug Module
----------------------------------------------------
local Debug = {}

function Debug:Toggle()
  debugMode = not debugMode
  print(PREFIX, debugMode and "|cff00ff00ON|r" or "|cffff0000OFF|r")
  if debugMode then
    local evtStatus = debugLogEvents and "|cff00ff00on|r" or "|cffff0000off|r"
    print(PREFIX, "Event logging:", evtStatus, "— toggle with /cdc debug events")
    print(PREFIX, "Subcommands: state | icons | rules | spell <id> | pool | events | log | cache | filter")
  end
end

----------------------------------------------------
-- /cdc debug events  (toggle event printing)
----------------------------------------------------
function Debug:ToggleEvents()
  debugLogEvents = not debugLogEvents
  local status = debugLogEvents and "|cff00ff00ON|r" or "|cffff0000OFF|r"
  print(PREFIX, "Event logging:", status)
  if not debugLogEvents then
    print(PREFIX, "(events still recorded — use /cdc debug log to view)")
  end
end

----------------------------------------------------
-- /cdc debug filter [EVENT_NAME|clear]
----------------------------------------------------
function Debug:ToggleFilter(arg)
  if not arg or arg == "" then
    local count = CountTable(eventFilter)
    if count == 0 then
      print(PREFIX, "No event filter active (all events recorded)")
    else
      print(PREFIX, "Active filter (" .. count .. "):")
      for name in pairs(eventFilter) do
        print(PREFIX, " -", name)
      end
    end
    return
  end
  if arg == "clear" then
    eventFilter = {}
    print(PREFIX, "Event filter cleared (all events recorded)")
    return
  end
  local name = arg:upper()
  if eventFilter[name] then
    eventFilter[name] = nil
    print(PREFIX, "Filter removed:", name)
  else
    eventFilter[name] = true
    print(PREFIX, "Filter added:", name)
  end
  local count = CountTable(eventFilter)
  if count > 0 then
    print(PREFIX, count, "filter(s) active — only matching events recorded")
  else
    print(PREFIX, "No filters active — all events recorded")
  end
end

----------------------------------------------------
-- /cdc debug state
----------------------------------------------------
function Debug:DumpState()
  print(PREFIX, "=== State ===")
  print(PREFIX, "inCombat         :", tostring(State.inCombat))
  print(PREFIX, "previewActive    :", tostring(State.previewActive))
  print(PREFIX, "optionsOpen      :", tostring(State.optionsOpen))
  print(PREFIX, "playerClass      :", tostring(State.playerClass))
  print(PREFIX, "activeIcons      :", #State.iconsByPriority)
  print(PREFIX, "iconPool         :", #State.iconPool, "available,", State.nextIconID - 1, "allocated")
  print(PREFIX, "activeProcSpells :", CountTable(State.activeProcSpells))
  print(PREFIX, "procCapableSpells:", CountTable(State.procCapableSpells))
  print(PREFIX, "knownSpellCache  :", CountTable(State.knownSpellCache), "entries")
  print(PREFIX, "cachedUIScale    :", State.cachedUIScale)
  print(PREFIX, "cachedScreen     :", State.cachedScreenW, "x", State.cachedScreenH)
  print(PREFIX, "cachedIconSize   :", State.cachedIconSize)
  print(PREFIX, "cachedAnchor     :", State.cachedAnchor)
  print(PREFIX, "positionMode     :", CooldownCursorDB.global.positionMode)
  print(PREFIX, "showBehavior     :", CooldownCursorDB.global.showBehavior)
  print(PREFIX, "showWhen         :", CooldownCursorDB.global.showWhen)
end

----------------------------------------------------
-- /cdc debug icons
----------------------------------------------------
function Debug:DumpIcons()
  local count = #State.iconsByPriority
  print(PREFIX, "=== Active Icons (" .. count .. ") ===")
  if count == 0 then
    print(PREFIX, "(none)")
    return
  end
  for i, iconData in ipairs(State.iconsByPriority) do
    local spellID = iconData.spellID
    local info = C_Spell.GetSpellInfo(spellID)
    local name = info and info.name or "Unknown"
    local iconFrame = iconData.iconFrame
    local shown = iconFrame and iconFrame:IsShown() and "shown" or "hidden"
    local alpha = iconFrame and string.format("%.2f", iconFrame:GetAlpha()) or "?"
    local onCD = (iconFrame and iconFrame.cooldown and iconFrame.cooldown:IsShown())
      and "|cffff4400on-cd|r" or "|cff00ff00off-cd|r"
    print(PREFIX, string.format(
      "[%d] %d %-22s prio:%-2d proc:%-5s procOnly:%-5s charges:%-5s %s alpha:%s %s",
      i, spellID, name,
      iconData.priority or 0,
      tostring(iconData.procActive),
      tostring(iconData.procOnly),
      tostring(iconData.hasCharges),
      shown, alpha, onCD
    ))
  end
end

----------------------------------------------------
-- /cdc debug rules
----------------------------------------------------
function Debug:DumpRules()
  local classRules = Internal.GetClassRules and Internal.GetClassRules()
  if not classRules then
    print(PREFIX, "No class rules found")
    return
  end
  local sorted = {}
  for spellID in pairs(classRules) do
    table.insert(sorted, spellID)
  end
  table.sort(sorted)
  print(PREFIX, "=== Spell Rules (" .. #sorted .. ") ===")
  for _, spellID in ipairs(sorted) do
    local rule = classRules[spellID]
    local info = C_Spell.GetSpellInfo(spellID)
    local name = info and info.name or "Unknown"
    local settings = rule.settings or {}
    local metadata = rule.metadata or {}
    local enabledStr = settings.enabled ~= false
      and "|cff00ff00on|r" or "|cffff0000off|r"
    local activeStr = State.activeIcons[spellID] ~= nil
      and "|cff00ff00active|r" or "inactive"
    print(PREFIX, string.format(
      "  [%d] %-24s %s | prio:%-2s | cd:%.1fs | charges:%-5s | %s",
      spellID, name, enabledStr,
      tostring(settings.priority or 0),
      metadata.baseCooldown or 0,
      tostring(metadata.hasCharges or false),
      activeStr
    ))
  end
end

----------------------------------------------------
-- /cdc debug spell <id>
----------------------------------------------------
function Debug:DumpSpell(arg)
  local spellID = tonumber(arg)
  if not spellID then
    print(PREFIX, "Usage: /cdc debug spell <spellID>")
    return
  end
  local info = C_Spell.GetSpellInfo(spellID)
  if not info then
    print(PREFIX, "No info found for spellID:", spellID)
    return
  end
  print(PREFIX, "=== Spell", spellID, "(" .. (info.name or "?") .. ") ===")
  print(PREFIX, "Icon ID  :", info.iconID)
  print(PREFIX, "CastTime :", info.castTime / 1000, "sec")
  print(PREFIX, "Range    :", info.minRange, "-", info.maxRange)

  local cd = C_Spell.GetSpellCooldown(spellID)
  if cd then
    print(PREFIX, "Cooldown : start:", cd.startTime, "| duration:", cd.duration, "| enabled:", tostring(cd.isEnabled))
  end

  local cdDur = C_Spell.GetSpellCooldownDuration(spellID)
  print(PREFIX, "CD Dur   :", cdDur and tostring(cdDur) or "nil (not on cooldown)")

  local charges = C_Spell.GetSpellCharges(spellID)
  if charges then
    print(PREFIX, "Charges  :", charges.currentCharges, "/", charges.maxCharges,
      "| recovery:", charges.cooldownDuration, "s")
  else
    print(PREFIX, "Charges  : none")
  end

  local baseCd, baseGcd = GetSpellBaseCooldown(spellID)
  print(PREFIX, "Base CD  :", baseCd and (baseCd / 1000) or "nil",
    "| Base GCD:", baseGcd and (baseGcd / 1000) or "nil")

  local usable, insufficientPower = C_Spell.IsSpellUsable(spellID)
  print(PREFIX, "Usable   :", tostring(usable), "| InsufficientPower:", tostring(insufficientPower))

  local inRange = C_Spell.IsSpellInRange(spellID)
  print(PREFIX, "InRange  :", tostring(inRange))

  print(PREFIX, "Known    :", tostring(C_SpellBook.IsSpellKnown(spellID)))

  local classRules = Internal.GetClassRules and Internal.GetClassRules()
  if classRules and classRules[spellID] then
    local rule = classRules[spellID]
    local s = rule.settings or {}
    print(PREFIX, "In Rules : yes | enabled:", tostring(s.enabled ~= false),
      "| priority:", tostring(s.priority or 0))
  else
    print(PREFIX, "In Rules : no")
  end

  local activeIcon = State.activeIcons[spellID]
  print(PREFIX, "Active   :", activeIcon and "yes" or "no")
end

----------------------------------------------------
-- /cdc debug pool
----------------------------------------------------
function Debug:DumpPool()
  print(PREFIX, "=== Icon Pool ===")
  print(PREFIX, "Available  :", #State.iconPool)
  print(PREFIX, "Active     :", #State.iconsByPriority)
  print(PREFIX, "Next ID    :", State.nextIconID)
  print(PREFIX, "Allocated  :", State.nextIconID - 1)
  print(PREFIX, "Pool size  :", CooldownCursorDB.global.iconPoolSize or "?")
end

----------------------------------------------------
-- /cdc debug log  (show the event ring buffer)
----------------------------------------------------
function Debug:DumpLog()
  local filterCount = CountTable(eventFilter)
  local header = "=== Event Log (" .. #eventLog .. "/" .. MAX_EVENT_LOG .. ")"
  if filterCount == 1 then
    header = header .. " [filter: " .. next(eventFilter) .. "]"
  elseif filterCount > 1 then
    header = header .. " [" .. filterCount .. " filters]"
  end
  print(PREFIX, header .. " ===")
  if #eventLog == 0 then
    print(PREFIX, "(empty — debug must be on when events fire)")
    return
  end
  local now = GetTime()
  for i, entry in ipairs(eventLog) do
    local ago = string.format("%.2fs ago", now - entry.time)
    local args = ""
    for j = 1, math.min(3, #entry.args) do
      args = args .. " " .. tostring(entry.args[j])
    end
    print(PREFIX, string.format("[%2d] %-42s (%s)%s", i, entry.event, ago, args))
  end
end

----------------------------------------------------
-- /cdc debug cache
----------------------------------------------------
function Debug:DumpCache()
  print(PREFIX, "=== Spell Cache ===")

  -- Spellbook cache (scanned from C_SpellBook)
  local cacheInfo = addonTable.Spells:GetCacheInfo()
  if cacheInfo.valid then
    print(PREFIX, string.format("spellBookCache : %d spells | age: %.1fs / %ds TTL",
      cacheInfo.size, cacheInfo.age, cacheInfo.expires))
  elseif cacheInfo.size > 0 then
    print(PREFIX, string.format("spellBookCache : %d spells | EXPIRED (age: %.1fs)",
      cacheInfo.size, cacheInfo.age or 0))
  else
    print(PREFIX, "spellBookCache : empty (not yet scanned this session)")
  end

  -- knownSpellCache (per-session, wiped on spec change)
  local total = CountTable(State.knownSpellCache)
  print(PREFIX, "knownSpellCache:", total, "entries")
  if total == 0 then return end

  print(PREFIX, "--- knownSpellCache (first 20) ---")
  local count = 0
  for spellID, known in pairs(State.knownSpellCache) do
    count = count + 1
    if count > 20 then break end
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    local name = spellInfo and spellInfo.name or "Unknown"
    print(PREFIX, string.format("  [%d] %-24s known:%s", spellID, name, tostring(known)))
  end
  if total > 20 then
    print(PREFIX, "  ... and", total - 20, "more")
  end
end

----------------------------------------------------
-- Export
----------------------------------------------------
Internal.DebugLog = DebugLog
Internal.LogEvent = LogEvent

addonTable.Modules.Debug = Debug
