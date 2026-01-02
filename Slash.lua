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
    if arg1 and arg2 then
      CooldownCursor:SetOffset(arg1, arg2)
      print("|cff00ff00CooldownCursor|r offset set to:", arg1, arg2)
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor offset <x> <y>")
    end
  elseif cmd == "size" then
    if arg1 then
      CooldownCursor:SetIconSize(arg1)
      print("|cff00ff00CooldownCursor|r icon size set to:", arg1)
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor size <number>")
    end
  elseif cmd == "showtext" then
    if arg1 == "on" then
      CooldownCursor:SetShowSpellNames(true)
      print("|cff00ff00CooldownCursor|r spell names enabled")
    elseif arg1 == "off" then
      CooldownCursor:SetShowSpellNames(false)
      print("|cff00ff00CooldownCursor|r spell names disabled")
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor showtext <on|off>")
    end
  elseif cmd == "hidenums" then
    if arg1 == "on" then
      CooldownCursor:SetHideCooldownNumbers(true)
      print("|cff00ff00CooldownCursor|r cooldown numbers hidden")
    elseif arg1 == "off" then
      CooldownCursor:SetHideCooldownNumbers(false)
      print("|cff00ff00CooldownCursor|r cooldown numbers shown")
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor hidenums <on|off>")
    end
  elseif cmd == "swipe" then
    if arg1 == "on" then
      CooldownCursor:SetShowCooldownSwipe(true)
      print("|cff00ff00CooldownCursor|r cooldown swipe enabled")
    elseif arg1 == "off" then
      CooldownCursor:SetShowCooldownSwipe(false)
      print("|cff00ff00CooldownCursor|r cooldown swipe disabled")
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor swipe <on|off>")
    end
  elseif cmd == "hideafter" then
    if arg1 then
      CooldownCursor:SetHideAfter(arg1)
      print("|cff00ff00CooldownCursor|r icon hide time set to:", arg1)
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor hideafter <seconds>")
    end
  elseif cmd == "animation" then
    if arg1 == "on" then
      CooldownCursor:SetAnimation(true)
      print("|cff00ff00CooldownCursor|r cooldown animation enabled")
    elseif arg1 == "off" then
      CooldownCursor:SetAnimation(false)
      print("|cff00ff00CooldownCursor|r cooldown animation disabled")
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor animation <on|off>")
    end
  elseif cmd == "min" then
    if arg1 then
      CooldownCursor:SetMinDuration(arg1)
      print("|cff00ff00CooldownCursor|r cooldown min duration:", arg1)
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor min <seconds>")
    end
  elseif cmd == "max" then
    if arg1 then
      CooldownCursor:SetMaxDuration(arg1)
      print("|cff00ff00CooldownCursor|r cooldown max duration:", arg1)
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor max <seconds>")
    end
  elseif cmd == "fadeout" then
    if arg1 then
      CooldownCursor:SetFadeOutDuration(arg1)
      print("|cff00ff00CooldownCursor|r cooldown fade out duration:", arg1)
    else
      print("|cff00ff00CooldownCursor|r usage: /cdcursor fadeout <seconds>")
    end
  elseif cmd == "reset" then
    CooldownCursor:ResetSettings()
    print("|cff00ff00CooldownCursor|r settings reset to default.")
  elseif cmd == "preview" then
    CooldownCursor:Preview()
    print("|cff00ff00CooldownCursor|r previewing cooldown icon.")
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
 /cdcursor fadeout <sec>       - Set icon fade-out duration
 /cdcursor reset               - Reset all settings to default
 /cdcursor preview             - Preview the cooldown icon
        ]])
  end
end
