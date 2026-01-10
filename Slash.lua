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
 /cdcursor animation                - Toggle icon animation on/off
 /cdcursor fadeout                  - Set icon fade-out duration in seconds
 /cdcursor hideafter                - Set icon hide-after duration in seconds
 /cdcursor show <0||1||2>           - 0=always, 1=in-combat, 2=out-of-combat
 /cdcursor preview                  - Toggle preview mode
 /cdcursor config                   - Open configuration panel
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
  local toggle = ToggleBool(CooldownCursorDB.animation)
  CooldownCursor:SetAnimation(toggle)
  Print("animation set to:", toggle and "on" or "off")
end

handlers.config = function()
  if not CooldownCursor:isAceConfigLoaded() then
    Print("AceConfig not found! Cannot open options panel.")
    return
  end
  Settings.OpenToCategory("CooldownCursor")
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
    CooldownCursor:SetIconAlpha(n)
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
    CooldownCursor:SetAnchor(pos)
    Print("anchor set to:", pos)
  elseif arg1 == "size" then
     local n = ToNum(arg2)
     if not n then return Usage("/cdcursor icon size <number>") end
     CooldownCursor:SetIconSize(n)
     Print("icon size set to:", n)
  elseif arg1 == "swipe" then
    local toggle = ToggleBool(CooldownCursorDB.showCooldownSwipe)
    CooldownCursor:SetShowCooldownSwipe(toggle)
    Print("swipe set to:", toggle and "on" or "off")
  elseif arg1 == "toggle" then
    local toggle = ToggleBool(CooldownCursorDB.iconHide)
    CooldownCursor:SetIconHide(toggle)
    Print("icon is now", toggle and "hidden" or "shown")
  else
    Usage("/cdcursor icon <alpha||anchor||size||swipe||toggle>")
  end
end

-- Deprecated in Midnight
handlers.max = function(arg1)
  local n = ToNum(arg1)
  if not n then return Usage("/cdcursor max <seconds>") end
  CooldownCursor:SetMaxDuration(n)
  Print("cooldown max duration:", n)
end

-- Deprecated in Midnight
handlers.min = function(arg1)
  local n = ToNum(arg1)
  if not n then return Usage("/cdcursor min <seconds>") end
  CooldownCursor:SetMinDuration(n)
  Print("cooldown min duration:", n)
end

handlers.number = function(arg1, arg2)
  local omniCC = CooldownCursor:IsOmniCCLoaded()
  if omniCC then
    Print("Warning: OmniCC is detected as loaded. Cooldown text settings will be ignored to avoid conflicts.")
    return
  end
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
    CooldownCursor:SetCooldownTextAlpha(n)
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
    CooldownCursor:SetCooldownTextAnchor(pos)
    Print("cooldown number anchor set to:", pos)
  elseif arg1 == "color" then
    CooldownCursor:SetCooldownTextColor(arg2)
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
    CooldownCursor:SetCooldownTextFont(font)
    Print("cooldown number font set to:", font)
  elseif arg1 == "ftype" then
    local ftype = string.upper(arg2)
    if not CooldownCursor:GetValidFontType(ftype) then
      Print("invalid font type:", ftype)
      Print("/cdcursor number ftype <outline||thickoutline||monochrome||none>")
      return
    end
    CooldownCursor:SetCooldownTextFontType(ftype)
    Print("cooldown number font type set to:", ftype)
  elseif arg1 == "size" then
    local n = ToNum(arg2)
    if not n then return Usage("/cdcursor number size <number>") end
    CooldownCursor:SetCooldownTextSize(n)
    Print("cooldown number size set to:", n)
  elseif arg1 == "toggle" then
    local toggle = ToggleBool(CooldownCursorDB.hideCooldownNumbers)
    CooldownCursor:SetHideCooldownNumbers(toggle)
    Print("cooldown numbers now",toggle and "hidden" or "shown")
  else
    Usage("/cdcursor number <alpha||anchor||color||font||ftype||size||toggle>")
  end
end

handlers.preview = function()
  CooldownCursor:Preview()
  Print("toggled preview.")
end

handlers.reset = function()
  CooldownCursor:ResetSettings()
  Print("settings reset to default.")
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
    CooldownCursor:SetSpellTextAlpha(n)
    Print("spell text alpha set to:", n)
  elseif arg1 == "anchor" then
    local pos = string.upper(arg2)
    local validAnchor = CooldownCursor:GetValidSpellTextAnchorPosition(pos)
    if not validAnchor then
      Print("invalid anchor position:", pos)
      Print("/cdcursor text anchor <top||bottom>")
      return
    end
    CooldownCursor:SetSpellTextAnchor(pos)
    Print("spell text anchor set to:", pos)
  elseif arg1 == "color" then
    CooldownCursor:SetSpellTextColor(arg2)
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
    CooldownCursor:SetSpellTextFont(arg2)
    Print("spell text font set to:", arg2)
  elseif arg1 == "ftype" then
    local ftype = string.upper(arg2)
    if not CooldownCursor:GetValidFontType(ftype) then
      Print("invalid font type:", ftype)
      Print("/cdcursor text ftype <outline||thickoutline||monochrome||none>")
      return
    end
    CooldownCursor:SetSpellTextFontType(ftype)
    Print("spell text font type set to:", ftype)
  elseif arg1 == "size" then
    local n = ToNum(arg2)
    if not n then return Usage("/cdcursor text size <number>") end
    CooldownCursor:SetSpellTextSize(n)
    Print("spell text size set to:", n)
  elseif arg1 == "toggle" then
    local toggle = ToggleBool(CooldownCursorDB.showSpellNames)
    CooldownCursor:SetShowSpellNames(toggle)
    Print("spell names now", toggle and "on" or "off")
  else
    Usage("/cdcursor text <alpha||anchor||color||font||ftype||size||toggle>")
  end
end

handlers.status = function()
  Print("Current Icon settings:")
  Print("   alpha:", CooldownCursorDB.iconAlpha)
  Print("   anchor:", CooldownCursorDB.anchor or "CENTER")
  Print("   animation:", CooldownCursorDB.animation and "on" or "off")
  Print("   cooldown swipe:", CooldownCursorDB.showCooldownSwipe and "on" or "off")
  Print("   fade out:", CooldownCursorDB.fadeOutDuration)
  Print("   hide after:", CooldownCursorDB.hideAfter)
  Print("   hide cooldown numbers:", CooldownCursorDB.hideCooldownNumbers and "on" or "off")
  Print("   icon:", CooldownCursorDB.iconHide and "hidden" or "shown")
  Print("   show spell names:", CooldownCursorDB.showSpellNames and "on" or "off")
  local show = CooldownCursorDB.showWhen
  local showLabel = (show == 0 and "always") or (show == 1 and "in-combat") or "out-of-combat"
  Print("   show mode:", show, "(", showLabel, ")")
  Print("   size:", CooldownCursorDB.iconSize)
  Print("   OmniCC loaded:", CooldownCursor:IsOmniCCLoaded() and "yes" or "no")
  Print("Current Spelltext settings:")
  Print("   alpha:", CooldownCursorDB.spellTextAlpha)
  Print("   anchor:", CooldownCursorDB.spellTextAnchor)
  Print("   color:", CooldownCursorDB.spellTextColor)
  Print("   font:", CooldownCursorDB.spellTextFont)
  Print("   font path:", CooldownCursorDB.spellTextFontPath)
  Print("   ftype:", CooldownCursorDB.spellTextFontType)
  Print("   size:", CooldownCursorDB.spellTextSize)
  Print("Current Cooldown text settings:")
  Print("   alpha:", CooldownCursorDB.cooldownTextAlpha)
  Print("   anchor:", CooldownCursorDB.cooldownTextAnchor)
  Print("   color:", CooldownCursorDB.cooldownTextColor)
  Print("   font:", CooldownCursorDB.cooldownTextFont)
  Print("   font path:", CooldownCursorDB.cooldownTextFontPath)
  Print("   ftype:", CooldownCursorDB.cooldownTextFontType)
  Print("   size:", CooldownCursorDB.cooldownTextSize)
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
  -- Update Display after any command
  CooldownCursor:UpdateDisplay()
end
