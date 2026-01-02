----------------------------------------------------
-- CooldownCursor Slash Commands
----------------------------------------------------
local addonName, addonTable = ...
local CooldownCursor = addonTable.Frame

SLASH_COOLDOWNCURSOR1 = "/cdcursor"
SLASH_COOLDOWNCURSOR2 = "/cdc"

SlashCmdList["COOLDOWNCURSOR"] = function(msg)
  local cmd, arg1, arg2 = strsplit(" ", msg:lower(), 3)

  if cmd == "offset" then
    local x = tonumber(arg1)
    local y = tonumber(arg2)
    if x and y then
      CooldownCursor:SetOffset(x, y)
      print("|cff00ff00CooldownCursor|r offset set to:", x, y)
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor offset <x> <y>")
    end
  elseif cmd == "size" then
    local size = tonumber(arg1)
    if size then
      CooldownCursor:SetIconSize(size)
      print("|cff00ff00CooldownCursor|r icon size set to:", size)
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor size <number>")
    end
  elseif cmd == "showtext" then
    local val = arg1
    if val == "on" then
      CooldownCursor:SetShowSpellNames(true)
      print("|cff00ff00CooldownCursor|r spell names enabled")
    elseif val == "off" then
      CooldownCursor:SetShowSpellNames(false)
      print("|cff00ff00CooldownCursor|r spell names disabled")
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor showtext <on|off>")
    end
  elseif cmd == "hidenums" then
    local val = arg1
    if val == "on" then
      CooldownCursor:SetHideCooldownNumbers(true)
      print("|cff00ff00CooldownCursor|r cooldown numbers hidden")
    elseif val == "off" then
      CooldownCursor:SetHideCooldownNumbers(false)
      print("|cff00ff00CooldownCursor|r cooldown numbers shown")
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor hidenums <on|off>")
    end
  elseif cmd == "swipe" then
    local val = arg1
    if val == "on" then
      CooldownCursor:SetShowCooldownSwipe(true)
      print("|cff00ff00CooldownCursor|r cooldown swipe enabled")
    elseif val == "off" then
      CooldownCursor:SetShowCooldownSwipe(false)
      print("|cff00ff00CooldownCursor|r cooldown swipe disabled")
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor swipe <on|off>")
    end
  elseif cmd == "hideafter" then
    local seconds = tonumber(arg1)
    if seconds then
      CooldownCursor:SetHideAfter(seconds)
      print("|cff00ff00CooldownCursor|r icon hide time set to:", seconds)
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor hideafter <seconds>")
    end
  elseif cmd == "animation" then
    local val = arg1
    if val == "on" then
      CooldownCursor:SetAnimation(true)
      print("|cff00ff00CooldownCursor|r cooldown animation enabled")
    elseif val == "off" then
      CooldownCursor:SetAnimation(false)
      print("|cff00ff00CooldownCursor|r cooldown animation disabled")
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor animation <on|off>")
    end
  elseif cmd == "min" then
    local min = tonumber(arg1)
    if min then
      CooldownCursor:SetMinDuration(min)
      print("|cff00ff00CooldownCursor|r cooldown min duration:", min)
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor min <seconds>")
    end
  elseif cmd == "max" then
    local max = tonumber(arg1)
    if max then
      CooldownCursor:SetMaxDuration(max)
      print("|cff00ff00CooldownCursor|r cooldown max duration:", max)
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor max <seconds>")
    end
  elseif cmd == "reset" then
    CooldownCursor:ResetSettings()
    print("|cff00ff00CooldownCursor|r settings reset to default.")
  else
    -- Show help
    print([[
|cff00ff00CooldownCursor Commands|r:
 /cdcursor offset <x> <y>      - Set icon offset from cursor
 /cdcursor size <number>       - Set icon size
 /cdcursor showtext <on|off>   - Toggle spell name display
 /cdcursor hidenums <on|off>   - Toggle cooldown number display
 /cdcursor swipe <on|off>      - Toggle cooldown swipe overlay
 /cdcursor hideafter <sec>     - Set how long icon stays after cast
 /cdcursor min <sec>           - Set min duration of spell cooldowns
 /cdcursor max <sec>           - Set max duration of spell cooldowns
 /cdcursor animation <on|off>  - Set icon animation
 /cdcursor reset               - Reset all settings to default
        ]])
  end
end
