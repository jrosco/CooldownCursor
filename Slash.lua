----------------------------------------------------
-- CooldownCursor Slash Commands
----------------------------------------------------
local addonName, addonTable = ...
local CooldownCursor = addonTable.Frame

SLASH_COOLDOWNCURSOR1 = "/cdcursor"
SLASH_COOLDOWNCURSOR2 = "/cdc"

local PREFIX = "|cff00ff00CooldownCursor|r"

----------------------------------------------------
-- Helper functions
----------------------------------------------------
local function Print(...)
  print(PREFIX, ...)
end

local function Trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

local function ToBool(s)
  s = (Trim(s)):lower()
  if s == "on" or s == "1" or s == "true" or s == "yes" then return true end
  if s == "off" or s == "0" or s == "false" or s == "no" then return false end
  return nil
end

local function ToNum(s)
  return tonumber(Trim(s))
end

local function ToggleBool(t)
  return not t
end

----------------------------------------------------
-- Help Menu
----------------------------------------------------
local function Usage(line)
  Print("usage:", line)
end

local function Help()
  print([[
|cff00ff00CooldownCursor Commands|r:
 /cdcursor icon                     - Configure icon settings (submenu)
 /cdcursor text                     - Configure spellname text settings (submenu)
 /cdcursor number                   - Configure cooldown number settings (submenu)
 /cdcursor scale                    - Set scale of icon and texts
 /cdcursor animation                - Toggle icon animation on/off
 /cdcursor fadeout                  - Set icon fade-out duration in seconds
 /cdcursor strata                   - Set icon frame strata
 /cdcursor hideafter                - Set icon hide-after duration in seconds
 /cdcursor show <0||1||2>           - 0=always, 1=in-combat, 2=out-of-combat
 /cdcursor mount                    - Toggle hide while mounted
 /cdcursor preview                  - Toggle preview mode
 /cdcursor help                     - Show this help message
 /cdcursor reset                    - Reset all settings to default
 /cdcursor status                   - Show current settings
]])
end

----------------------------------------------------
--- Command Handlers
----------------------------------------------------
local handlers = {}

-- Adding a new command
-- handlers.newcmd = function(...) ... end

handlers.help = function()
  Help()
end

handlers.anchors = function()
  Print("Valid anchors:")
  local anchors = CooldownCursor:GetValidAnchorPositions()
  for _, pos in ipairs(anchors) do
    print(" -", pos)
  end
end

handlers.animation = function()
  local toggle = ToggleBool(CooldownCursor:GetDBValue("animation"))
  CooldownCursor:SetDBBoolean("animation", toggle)
  Print("animation set to:", toggle and "on" or "off")
end

handlers.fadeout = function(arg1)
  local n = ToNum(arg1)
  if not n then return Usage("/cdcursor fadeout <seconds>") end
  CooldownCursor:SetFadeOutDuration(n)
  Print("icon fade-out duration set to:", n)
end

handlers.fonts = function()
  Print("Available fonts:")
  local allFonts = CooldownCursor:GetAllFonts()
  for _, path in ipairs(allFonts) do
    print(" -", path)
  end
end

handlers.hideafter = function(arg1)
  local n = ToNum(arg1)
  if not n then return Usage("/cdcursor hideafter <seconds>") end
  CooldownCursor:SetHideAfter(n)
  Print("icon hide after set to:", n)
end

handlers.icon = function(arg1, arg2)
  if not arg1 or arg1 == "" then
    Usage("/cdcursor icon <anchor||size||alpha||swipe||toggle>")
    print("options:")
    print("   anchor        - Set icon anchor position")
    print("   size          - Set icon size")
    print("   alpha         - Set icon alpha (0-100)")
    print("   swipe         - Set icon swipe on/off")
    print("   toggle        - Toggle icon display")
    return
  end

  if arg1 == "alpha" then
    local n = ToNum(arg2)
    if not n then return Usage("/cdcursor icon alpha <number>") end
    CooldownCursor:SetDBNumber("iconAlpha", n)
    Print("icon alpha set to:", n)
  elseif arg1 == "anchor" then
    local pos = string.upper(arg2)
    local validAnchor = CooldownCursor:GetValidAnchorPosition(pos)
    if not validAnchor then
      Print("invalid anchor position:", pos)
      Print("/cdcursor icon anchor <anchor>")
      handlers.anchors()
      return
    end
    CooldownCursor:SetDBString("anchor", pos)
    Print("anchor set to:", pos)
  elseif arg1 == "size" then
    local n = ToNum(arg2)
    if not n then return Usage("/cdcursor icon size <number>") end
    CooldownCursor:SetDBNumber("iconSize", n)
    Print("icon size set to:", n)
  elseif arg1 == "swipe" then
    local toggle = ToggleBool(CooldownCursor:GetDBValue("showCooldownSwipe"))
    CooldownCursor:SetDBBoolean("showCooldownSwipe", toggle)
    Print("swipe set to:", toggle and "on" or "off")
  elseif arg1 == "toggle" then
    local toggle = ToggleBool(CooldownCursor:GetDBValue("iconHide"))
    CooldownCursor:SetDBBoolean("iconHide", toggle)
    Print("icon is now", toggle and "hidden" or "shown")
  else
    Usage("/cdcursor icon <alpha||anchor||size||swipe||toggle>")
  end
end

-- Deprecated in Midnight
handlers.max = function(arg1)
  local n = ToNum(arg1)
  if not n then return Usage("/cdcursor max <seconds>") end
  CooldownCursor:SetDBNumber("maxDuration", n)
  Print("cooldown max duration:", n)
end

-- Deprecated in Midnight
handlers.min = function(arg1)
  local n = ToNum(arg1)
  if not n then return Usage("/cdcursor min <seconds>") end
  CooldownCursor:SetDBNumber("minDuration", n)
  Print("cooldown min duration:", n)
end

handlers.mount = function()
  local toggle = ToggleBool(CooldownCursor:GetDBValue("hideWhileMounted"))
  CooldownCursor:SetDBBoolean("hideWhileMounted", toggle)
  Print("hide while mounted is now", toggle and "enabled" or "disabled")
end

handlers.number = function(arg1, arg2)
  if not arg1 or arg1 == "" then
    Usage("/cdcursor number <alpha||anchor||color||font||ftype||size||toggle>")
    print("options:")
    print("   alpha     - Set cooldown text alpha (0-100)")
    print("   anchor    - Set cooldown text anchor position")
    print("   color     - Set cooldown text color (use hex code, e.g. ff0000)")
    print("   font      - Set cooldown text font")
    print("   ftype     - Set cooldown text font type (outline, thickoutline, monochrome, none)")
    print("   size      - Set cooldown text size")
    print("   toggle    - Toggle cooldown name display")
    return
  end

  if arg1 == "alpha" then
    local n = ToNum(arg2)
    if not n then return Usage("/cdcursor number alpha <number>") end
    CooldownCursor:SetDBNumber("cooldownTextAlpha", n)
    Print("cooldown number alpha set to:", n)
  elseif arg1 == "anchor" then
    local pos = string.upper(arg2)
    local validAnchor = CooldownCursor:GetValidCooldownTextAnchorPosition(pos)
    if not validAnchor then
      Print("invalid anchor position:", pos)
      Print("/cdcursor number anchor <anchor>")
      handlers.anchors()
      return
    end
    CooldownCursor:SetDBString("cooldownTextAnchor", pos)
    Print("cooldown number anchor set to:", pos)
  elseif arg1 == "color" then
    CooldownCursor:SetDBString("cooldownTextColor", arg2)
    Print("cooldown number color set to:", arg2)
  elseif arg1 == "font" then
    local font = arg2
    if not font or font == "" then
      Print("no font provided", font)
      Print("to see available fonts run:")
      Print("/cdcursor fonts")
      return
    end
    local validFont = CooldownCursor:GetAllFonts()
    if not tContains(validFont, font) then
      Print("invalid font", font)
      Print("to see available fonts run:")
      Print("/cdcursor fonts")
      return
    end
    CooldownCursor:SetFontPath("cooldownTextFont", font)
    Print("cooldown number font set to:", font)
  elseif arg1 == "ftype" then
    local ftype = string.upper(arg2)
    if not CooldownCursor:GetValidFontType(ftype) then
      Print("invalid font type:", ftype)
      Print(
      "/cdcursor number ftype <outline||thickoutline||monochrome||monochromeoutline||monochromethickoutline||none>")
      return
    end
    CooldownCursor:SetDBString("cooldownTextFontType", ftype)
    Print("cooldown number font type set to:", ftype)
  elseif arg1 == "size" then
    local n = ToNum(arg2)
    if not n then return Usage("/cdcursor number size <number>") end
    CooldownCursor:SetDBNumber("cooldownTextSize", n)
    Print("cooldown number size set to:", n)
  elseif arg1 == "toggle" then
    local toggle = ToggleBool(CooldownCursor:GetDBValue("hideCooldownNumbers"))
    CooldownCursor:SetDBBoolean("hideCooldownNumbers", toggle)
    Print("cooldown numbers now", toggle and "hidden" or "shown")
  else
    Usage("/cdcursor number <alpha||anchor||color||font||ftype||size||toggle>")
  end
end

handlers.preview = function()
  CooldownCursor:Preview()
  local mode = ToggleBool(CooldownCursor:GetPreviewMouseMode())
  CooldownCursor:SetPreviewMouseMode(mode)
  Print("toggled preview.")
end

handlers.reset = function()
  CooldownCursor:ResetSettings()
  Print("settings reset to default.")
end

handlers.scale = function(arg1)
  local n = ToNum(arg1)
  if not n then return Usage("/cdcursor scale <0.5 - 5>") end
  if n < 0.5 or n > 5 then
    Print("scale must be greater than or equal to 0.5 and less than or equal to 5")
    return
  end
  CooldownCursor:SetDBNumber("scale", n)
  Print("scale set to:", n)
end

handlers.show = function(arg1)
  local n = ToNum(arg1)
  if n ~= 0 and n ~= 1 and n ~= 2 then
    return Usage("/cdcursor show <0||1||2>   (0=always, 1=in-combat, 2=out-of-combat)")
  end
  CooldownCursor:SetDBNumber("showWhen", n)
  local label = (n == 0 and "always") or (n == 1 and "in-combat") or "out-of-combat"
  Print("show mode set to:", label)
end

handlers.strata = function(arg1)
  local strata = string.upper(arg1)
  if not CooldownCursor:GetValidFrameStrata(strata) then
    Print("invalid frame strata:", strata)
    Print("/cdcursor strata <strata>")
    Print("valid stratas are: background, low, medium, high, dialog, tooltip")
    return
  end
  CooldownCursor:SetDBString("frameStrata", strata)
  Print("icon frame strata set to:", strata)
end

handlers.text = function(arg1, arg2)
  if not arg1 or arg1 == "" then
    Usage("/cdcursor text <alpha||anchor||color||font||ftype||size||toggle>")
    print("options:")
    print("   alpha     - Set spell text alpha (0-100)")
    print("   anchor    - Set spell text anchor position (TOP or BOTTOM)")
    print("   color     - Set spell text color (use hex code, e.g. ff0000)")
    print("   font      - Set spell text font")
    print("   ftype     - Set spell text font type (outline, thickoutline, monochrome, none)")
    print("   size      - Set spell text size")
    print("   toggle    - Toggle spell name display")
    return
  end

  if arg1 == "alpha" then
    local n = ToNum(arg2)
    if not n then return Usage("/cdcursor text alpha <number>") end
    CooldownCursor:SetDBNumber("spellTextAlpha", n)
    Print("spell text alpha set to:", n)
  elseif arg1 == "anchor" then
    local pos = string.upper(arg2)
    local validAnchor = CooldownCursor:GetValidSpellTextAnchorPosition(pos)
    if not validAnchor then
      Print("invalid anchor position:", pos)
      Print("/cdcursor text anchor <top||bottom>")
      return
    end
    CooldownCursor:SetDBString("spellTextAnchor", pos)
    Print("spell text anchor set to:", pos)
  elseif arg1 == "color" then
    CooldownCursor:SetDBString("spellTextColor", arg2)
    Print("spell text color set to:", arg2)
  elseif arg1 == "font" then
    local font = arg2
    if not font or font == "" then
      Print("no font provided", font)
      Print("to see available fonts run:")
      Print("/cdcursor fonts")
      return
    end
    local validFont = CooldownCursor:GetAllFonts()
    if not tContains(validFont, font) then
      Print("invalid font", font)
      Print("to see available fonts run:")
      Print("/cdcursor fonts")
      return
    end
    CooldownCursor:SetFontPath("spellTextFont", arg2)
    Print("spell text font set to:", arg2)
  elseif arg1 == "ftype" then
    local ftype = string.upper(arg2)
    if not CooldownCursor:GetValidFontType(ftype) then
      Print("invalid font type:", ftype)
      Print("/cdcursor text ftype <outline||thickoutline||monochrome||monochromeoutline||monochromethickoutline||none>")
      return
    end
    CooldownCursor:SetDBString("spellTextFontType", ftype)
    Print("spell text font type set to:", ftype)
  elseif arg1 == "size" then
    local n = ToNum(arg2)
    if not n then return Usage("/cdcursor text size <number>") end
    CooldownCursor:SetDBNumber("spellTextSize", n)
    Print("spell text size set to:", n)
  elseif arg1 == "toggle" then
    local toggle = ToggleBool(CooldownCursor:GetDBValue("showSpellNames"))
    CooldownCursor:SetDBBoolean("showSpellNames", toggle)
    Print("spell names now", toggle and "on" or "off")
  else
    Usage("/cdcursor text <alpha||anchor||color||font||ftype||size||toggle>")
  end
end

-- Expose a method on CooldownCursor for exporting settings
function CooldownCursor:ExportSettings()
  Print("======================================")
  Print("CooldownCursor Settings Export")
  Print("======================================")

  -- Skip internal keys (those starting with _) and complex objects
  local skipKeys = {
    spellRules = true,
    releaseNotes = true,
  }

  -- Collect and sort all setting keys
  local sortedKeys = {}
  for key, _ in pairs(CooldownCursorDB) do
    -- Skip internal keys (starting with _) and skipped keys
    if not key:match("^_") and not skipKeys[key] then
      table.insert(sortedKeys, key)
    end
  end
  table.sort(sortedKeys)

  -- Function to format value for display
  local function FormatValue(value)
    local valueType = type(value)

    if valueType == "boolean" then
      return value and "true" or "false"
    elseif valueType == "number" then
      return tostring(value)
    elseif valueType == "string" then
      return value
    elseif valueType == "table" then
      return "[table]"
    else
      return tostring(value)
    end
  end

  -- Print all settings
  for _, key in ipairs(sortedKeys) do
    local value = CooldownCursorDB[key]
    Print("   " .. key .. ":", FormatValue(value))
  end

  -- Handle spell rules separately
  if CooldownCursorDB.spellRules and CooldownCursorDB.spellRules.rules then
    Print("")
    Print("Spell Rules:")
    local ruleCount = 0
    local sortedRules = {}

    for spellID, rule in pairs(CooldownCursorDB.spellRules.rules) do
      if type(spellID) == "number" then
        ruleCount = ruleCount + 1
        table.insert(sortedRules, {spellID = spellID, rule = rule})
      end
    end

    -- Sort by spell ID
    table.sort(sortedRules, function(a, b) return a.spellID < b.spellID end)

    for _, entry in ipairs(sortedRules) do
      local spellID = entry.spellID
      local rule = entry.rule
      local info = C_Spell.GetSpellInfo(spellID)
      local spellName = info and info.name or ("Unknown Spell " .. spellID)

      local enabled = rule.enabled ~= false and "enabled" or "disabled"
      local priority = rule.priority or 0
      local iconSize = rule.iconSize or "default"

      Print(string.format("   [%d] %s - %s (priority: %s, size: %s)",
        spellID, spellName, enabled, tostring(priority), tostring(iconSize)))
    end

    Print(string.format("   Total: %d spell rule(s)", ruleCount))

    -- Print spell rules settings
    if CooldownCursorDB.spellRules.settings then
      Print("")
      Print("Spell Rules Settings:")
      Print("   disableRules:", FormatValue(CooldownCursorDB.spellRules.settings.disableRules))
    end
  end

  Print("======================================")
end

-- Generate a compact serialized string of all settings for sharing
function CooldownCursor:SerializeSettings()
  local parts = {}

  -- Skip internal keys (those starting with _) and complex objects
  local skipKeys = {
    spellRules = true,
    releaseNotes = true,
  }

  -- Collect and sort all setting keys
  local sortedKeys = {}
  for key, _ in pairs(CooldownCursorDB) do
    if not key:match("^_") and not skipKeys[key] then
      table.insert(sortedKeys, key)
    end
  end
  table.sort(sortedKeys)

  -- Function to escape special characters in strings
  local function EscapeString(str)
    return str:gsub("([\\;|])", "\\%1")
  end

  -- Serialize each setting
  for _, key in ipairs(sortedKeys) do
    local value = CooldownCursorDB[key]
    local valueType = type(value)
    local serializedValue

    if valueType == "boolean" then
      serializedValue = value and "1" or "0"
    elseif valueType == "number" then
      serializedValue = tostring(value)
    elseif valueType == "string" then
      serializedValue = EscapeString(value)
    else
      serializedValue = nil -- Skip tables and other types
    end

    if serializedValue then
      table.insert(parts, key .. "=" .. serializedValue)
    end
  end

  -- Add spell rules
  if CooldownCursorDB.spellRules and CooldownCursorDB.spellRules.rules then
    local rules = {}
    for spellID, rule in pairs(CooldownCursorDB.spellRules.rules) do
      if type(spellID) == "number" then
        local enabled = rule.enabled ~= false and "1" or "0"
        local priority = rule.priority or 0
        local iconSize = rule.iconSize or ""
        local useGlobal = rule.useGlobalIconSize ~= false and "1" or "0"

        table.insert(rules, string.format("%d:%s:%s:%s:%s",
          spellID, enabled, priority, iconSize, useGlobal))
      end
    end

    if #rules > 0 then
      table.insert(parts, "spellRules=" .. table.concat(rules, "|"))
    end

    -- Add spell rules settings
    if CooldownCursorDB.spellRules.settings then
      local disableRules = CooldownCursorDB.spellRules.settings.disableRules and "1" or "0"
      table.insert(parts, "spellRulesDisabled=" .. disableRules)
    end
  end

  return table.concat(parts, ";")
end

handlers.status = function()
  CooldownCursor:ExportSettings()
end

handlers.version = function()
  Print("v" .. (CooldownCursor:GetVersion() or " unknown"))
end

----------------------------------------------------
--- Command Alias Handlers
----------------------------------------------------

-- Adding a new command alias
-- handlers.alias = function()
--   handlers.cmd(args)
-- end

handlers.h = function()
  handlers.help()
end

handlers.i = function(arg1, arg2)
  handlers.icon(arg1, arg2)
end

handlers.n = function(arg1, arg2)
  handlers.number(arg1, arg2)
end

handlers.p = function()
  handlers.preview()
end

handlers.s = function()
  handlers.status()
end

handlers.t = function(arg1, arg2)
  handlers.text(arg1, arg2)
end

----------------------------------------------------
--Main
----------------------------------------------------
SlashCmdList["COOLDOWNCURSOR"] = function(msg)
  msg = Trim(msg)
  if msg == "" then return Help() end

  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  cmd = (cmd or ""):lower()

  local arg1, arg2 = rest:match("^(%S+)%s*(.-)$")
  arg1 = Trim(arg1) or ""
  arg2 = Trim(arg2) or ""

  arg1 = arg1:lower()

  local fn = handlers[cmd]
  if not fn then
    Help()
    return
  end

  fn(arg1, arg2)
end
