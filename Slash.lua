----------------------------------------------------
-- CooldownCursor Slash Commands
----------------------------------------------------
local addonName, addonTable = ...
local CooldownCursor = addonTable.Frame

SLASH_COOLDOWNCURSOR1 = "/cdcursor"
SLASH_COOLDOWNCURSOR2 = "/cdc"

local PREFIX = "|cff00ff00CooldownCursor|r"

-- TODO: See if we can get these from CooldownCursor.lua
local VALID_ANCHORS = {
  "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT",
  "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
}

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
 /cdcursor anchor <position>        - Set icon anchor position (relative to cursor)
 /cdcursor size <number>            - Set icon size
 /cdcursor hideafter <sec>          - Set how long icon stays after cast
 /cdcursor min <sec>                - Set min duration of spell cooldowns
 /cdcursor max <sec>                - Set max duration of spell cooldowns
 /cdcursor fadeout <sec>            - Set icon fade-out duration
 /cdcursor show <0||1||2>           - 0=always, 1=in-combat, 2=out-of-combat
 /cdcursor toggle                   - Toggle swipe, text, animation, numbers flags
 /cdcursor reset                    - Reset all settings to default
 /cdcursor preview                  - Toggle preview mode
 /cdcursor status                   - Show current settings
]])
end

----------------------------------------------------
--- Command Handlers
----------------------------------------------------
local handlers = {}

-- Adding a new command 
-- handlers.newcmd = function(...) ... end

handlers.anchor = function(arg1)
  if not arg1 or arg1 == "" then
    Usage("/cdcursor anchor <position>")
    handlers.anchors()
    return
  end
  local pos = string.upper(arg1)
  CooldownCursor:SetAnchor(pos)
  Print("anchor set to:", pos)
end

handlers.anchors = function()
  Print("Valid anchors:")
  for _, a in ipairs(VALID_ANCHORS) do
    print(" -", a)
  end
end

handlers.size = function(arg1)
  local n = ToNum(arg1)
  if not n then return Usage("/cdcursor size <number>") end
  CooldownCursor:SetIconSize(n)
  Print("icon size set to:", n)
end

handlers.hideafter = function(arg1)
  local n = ToNum(arg1)
  if not n then return Usage("/cdcursor hideafter <seconds>") end
  CooldownCursor:SetHideAfter(n)
  Print("icon hide time set to:", n)
end

handlers.min = function(arg1)
  local n = ToNum(arg1)
  if not n then return Usage("/cdcursor min <seconds>") end
  CooldownCursor:SetMinDuration(n)
  Print("cooldown min duration:", n)
end

handlers.max = function(arg1)
  local n = ToNum(arg1)
  if not n then return Usage("/cdcursor max <seconds>") end
  CooldownCursor:SetMaxDuration(n)
  Print("cooldown max duration:", n)
end

handlers.fadeout = function(arg1)
  local n = ToNum(arg1)
  if n == nil then return Usage("/cdcursor fadeout <seconds>") end
  CooldownCursor:SetFadeOutDuration(n)
  Print("fade-out duration:", n)
end

handlers.show = function(arg1)
  local n = ToNum(arg1)
  if n ~= 0 and n ~= 1 and n ~= 2 then
    return Usage("/cdcursor show <0||1||2>   (0=always, 1=in-combat, 2=out-of-combat)")
  end
  CooldownCursor:SetShowWhen(n)
  local label = (n == 0 and "always") or (n == 1 and "in-combat") or "out-of-combat"
  Print("show mode set to:", label)
end

handlers.toggle = function(arg1)
  if not arg1 or arg1 == "" then
    Usage("/cdcursor toggle <swipe||text||animation||numbers>")
    print("options:")
    print("   swipe       - Toggle cooldown swipe overlay")
    print("   text        - Toggle spell name display")
    print("   animation   - Toggle Toggle icon animation")
    print("   numbers     - Toggle hiding cooldown numbers")
    return
  end

  arg1 = arg1:lower()

  -- Toggle Swipe
  if arg1 == "swipe" then
    local toggle = ToggleBool(CooldownCursorDB.showCooldownSwipe)
    CooldownCursor:SetShowCooldownSwipe(toggle)
    Print("cooldown swipe now", toggle and "on" or "off")

  -- Toggle Spell Text
  elseif arg1 == "text" then
    local toggle = ToggleBool(CooldownCursorDB.showSpellNames)
    CooldownCursor:SetShowSpellNames(toggle)
    Print("spell names now", toggle and "on" or "off")

  -- Toggle Animation
  elseif arg1 == "animation" then
    local toggle = ToggleBool(CooldownCursorDB.animation)
    CooldownCursor:SetAnimation(toggle)
    Print("animation now", toggle and "on" or "off")

  -- Toggle cooldown number
  elseif arg1 == "numbers" then
    local toggle = ToggleBool(CooldownCursorDB.hideCooldownNumbers)
    CooldownCursor:SetHideCooldownNumbers(toggle)
    Print("cooldown numbers now",toggle and "hidden" or "shown")
  else
    Usage("/cdcursor toggle <swipe||text||animation||numbers>")
  end
end

handlers.status = function()
  Print("Current settings:")
  Print(" anchor:", CooldownCursorDB.anchor or "CENTER")
  Print(" size:", CooldownCursorDB.iconSize)
  Print(" show spell names:", CooldownCursorDB.showSpellNames and "on" or "off")
  Print(" hide cooldown numbers:", CooldownCursorDB.hideCooldownNumbers and "on" or "off")
  Print(" cooldown swipe:", CooldownCursorDB.showCooldownSwipe and "on" or "off")
  Print(" hide after:", CooldownCursorDB.hideAfter)
  Print(" animation:", CooldownCursorDB.animation and "on" or "off")
  Print(" fade out:", CooldownCursorDB.fadeOutDuration)
  local show = CooldownCursorDB.showWhen
  local showLabel = (show == 0 and "always") or (show == 1 and "in-combat") or "out-of-combat"
  Print(" show mode:", show, "(", showLabel, ")")
end

handlers.reset = function()
  CooldownCursor:ResetSettings()
  Print("settings reset to default.")
end

handlers.preview = function()
  CooldownCursor:Preview()
  Print("toggled preview.")
end

----------------------------------------------------
--- Command Alias Handlers
----------------------------------------------------
handlers.swipe = function()
  handlers.toggle("swipe")
end

handlers.text = function()
  handlers.toggle("text")
end

handlers.animation = function()
  handlers.toggle("animation")
end

handlers.numbers = function()
  handlers.toggle("numbers")
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
  arg1 = Trim(arg1)
  arg2 = Trim(arg2)

  local fn = handlers[cmd]
  if not fn then
    Help()
    return
  end

  fn(arg1, arg2)
end
