local addonName, addonTable = ...
local CooldownCursor = addonTable.Frame
local State = addonTable.State
local Internal = addonTable.Internal
local OPTIONS_APP_NAME = addonName

local AceConfig = LibStub and LibStub("AceConfig-3.0", true)
local AceConfigDialog = LibStub and LibStub("AceConfigDialog-3.0", true)

local version = CooldownCursor:GetVersion()

local name = function()
  return "CooldownCursor |cff00ff00v" .. version .. "|r"
end

local fontValues = {}
local anchorValues = {}
local frameStrataValues = {}

-- Debounce timer for priority slider rebuild
local priorityRebuildTimer = nil

local fontTypeValues = {
  NONE = "None",
  OUTLINE = "Outline",
  THICKOUTLINE = "Thick Outline",
  MONOCHROME = "Monochrome",
  MONOCHROMEOUTLINE = "Monochrome Outline",
  MONOCHROMETHICKOUTLINE = "Monochrome Thick Outline",
}

local function GetRuleDisplayColor(enabled)
  if CooldownCursorDB.spellRules.settings.disableRules then
    return "9d9d9d", "(rules disabled)"
  end

  if enabled == nil then return "ffff00", "" end
  if enabled then return "00ff00", "" end

  return "ff5555", "(disabled)"
end

-- Helper to get class-specific rules for the current player
local function GetClassRulesForUI()
  CooldownCursorDB.spellRules = CooldownCursorDB.spellRules or {}
  CooldownCursorDB.spellRules.rules = CooldownCursorDB.spellRules.rules or {}

  local class = CooldownCursor:GetPlayerClass()
  if not class then return {} end

  if not CooldownCursorDB.spellRules.rules[class] then
    CooldownCursorDB.spellRules.rules[class] = {}
  end

  return CooldownCursorDB.spellRules.rules[class]
end

function CooldownCursor:RebuildSpellRuleOptions()
  local group = self.options.args.spellRulesGroup
  local args = group.args

  -- Remove old spell entries only
  for k in pairs(args) do
    if k:match("^spell_") then
      args[k] = nil
    end
  end

  -- Get class-specific rules
  local classRules = GetClassRulesForUI()

  -- Build sortable list
  local sorted = {}

  for spellID, rule in pairs(classRules) do
    if type(spellID) == "number" and C_SpellBook.IsSpellKnown(spellID) then
      local info = C_Spell.GetSpellInfo(spellID)
      local name = info and info.name or ("SpellID " .. spellID)
      local icon = info and info.originalIconID or nil

      table.insert(sorted, {
        spellID = spellID,
        icon = icon,
        name = name,
        rule = rule,
      })
    end
  end

  -- Sort by priority (higher first), then alphabetically for priority 0
  table.sort(sorted, function(a, b)
    local aPriority = (a.rule.settings and a.rule.settings.priority) or 0
    local bPriority = (b.rule.settings and b.rule.settings.priority) or 0

    -- Spells with priority > 0 come before priority 0
    if aPriority > 0 and bPriority == 0 then
      return true
    end
    if bPriority > 0 and aPriority == 0 then
      return false
    end

    -- Both have priority: sort by priority descending (higher first)
    if aPriority > 0 and bPriority > 0 then
      return aPriority > bPriority
    end

    -- Both priority 0: sort alphabetically
    return a.name:lower() < b.name:lower()
  end)

  -- Build UI groups
  local order = 10

  for _, entry in ipairs(sorted) do
    local spellID = entry.spellID
    local rule = entry.rule
    local settings = rule.settings or {}
    local name = entry.name
    local enabled = settings.enabled
    local icon = entry.icon
    local priority = settings.priority or 0
    local color, suffix = GetRuleDisplayColor(enabled)
    local priorityText = priority > 0 and ("|cffaaaaaa[%d]|r "):format(priority) or ""
    name = ("%s|cff%s%s %s|r"):format(priorityText, color, name, suffix)

    args["spell_" .. spellID] = {
      type = "group",
      name = name,
      order = order,
      icon = icon,
      inline = false,
      disabled = function() return CooldownCursorDB.spellRules.settings.disableRules end,
      args = {

        enabled = {
          type = "toggle",
          name = "Enabled",
          desc = "When enabled, this spell will show cooldowns at your cursor.",
          order = 10,
          get = function() return settings.enabled ~= false end,
          set = function(_, v)
            settings.enabled = v
            self:UpdateDisplay()
            self:RebuildSpellRuleOptions()
            self:NotifyOptionsChanged()
          end,
        },

        priority = {
          type = "range",
          name = "Priority",
          desc = "Priority for this spell when using Priority sort order (0-100, higher appears first).",
          order = 15,
          min = 0,
          max = 100,
          step = 1,
          disabled = function()
            return CooldownCursor:GetDBValue("stackDirection") == "SINGLE" or
                CooldownCursorDB.spellRules.settings.disableRules or
                not settings.enabled
          end,
          get = function()
            return settings.priority or 0
          end,
          set = function(_, v)
            settings.priority = v
            self:UpdateDisplay()
            -- Debounce the rebuild so slider moves smoothly
            if priorityRebuildTimer then
              priorityRebuildTimer:Cancel()
            end
            priorityRebuildTimer = C_Timer.NewTimer(0.3, function()
              self:RebuildSpellRuleOptions()
              self:NotifyOptionsChanged()
              priorityRebuildTimer = nil
            end)
          end,
        },

        header = {
          type = "header",
          name = "Spell icon options",
          order = 20,
        },

        description = {
          type = "description",
          name = "Update a spell icon settings.",
          order = 21,
        },

        iconSize = {
          type = "range",
          name = "Icon Size",
          order = 22,
          min = 16,
          max = 128,
          step = 1,
          disabled = function()
            return settings.useGlobalIconSize ~= false or not settings.enabled
          end,
          get = function()
            return settings.iconSize or CooldownCursor:GetDBValue("iconSize")
          end,
          set = function(_, v)
            settings.iconSize = v
            settings.useGlobalIconSize = false -- auto-disable inheritance
            self:UpdateDisplay()
          end,
        },

        useGlobalIconSize = {
          type = "toggle",
          name = "Use Global Icon Size",
          desc = "Use the global icon size instead of a per-spell value.",
          order = 23,
          get = function()
            return settings.useGlobalIconSize ~= false
          end,
          set = function(_, v)
            settings.useGlobalIconSize = v
            if v then
              settings.iconSize = nil
            end
            self:UpdateDisplay()
          end,
        },

        footer = {
          type = "header",
          name = "",
          order = 100,
        },

        remove = {
          type = "execute",
          name = "Remove Rule for Spell " .. name,
          order = 110,
          confirm = true,
          func = function()
            CooldownCursor:RemoveSpellRule(spellID)
          end,
        },
      },
    }

    order = order + 1
  end
end

local function AnchorValues()
  if next(anchorValues) ~= nil then
    -- return cached values
    return anchorValues
  end
  for _, a in ipairs(CooldownCursor:GetValidAnchorPositions()) do
    anchorValues[a] = a
  end
  return anchorValues
end

local function FrameStrataValues()
  if next(frameStrataValues) ~= nil then
    -- return cached values
    return frameStrataValues
  end
  for _, a in ipairs(CooldownCursor:GetValidFrameStratas()) do
    frameStrataValues[a] = a
  end
  return frameStrataValues
end

local function FontValues()
  if next(fontValues) ~= nil then
    -- return cached values
    return fontValues
  end
  for _, path in ipairs(CooldownCursor:GetAllFonts()) do
    fontValues[path] = path
  end
  return fontValues
end

local function ShowWhenValues()
  return {
    [0] = "Always",
    [1] = "In Combat",
    [2] = "Out of Combat",
  }
end

local function ShowBehaviorValues()
  return {
    [0] = "On Cooldown",
    [1] = "Off Cooldown (Ready)",
    [2] = "Auto-Hide After",
  }
end

local function ProcOverlayAtlasValues()
  local values = {}
  local settings = CooldownCursor:GetProcOverlayAtlasSettings() or {}
  values["none"] = "None"
  for atlas, data in pairs(settings) do
    values[atlas] = (data and data.name) or atlas
  end
  return values
end

local function ProcOutlineAtlasValues()
  local values = {}
  local settings = CooldownCursor:GetProcOutlineAtlasSettings() or {}
  values["none"] = "None"
  for atlas, data in pairs(settings) do
    values[atlas] = (data and data.name) or atlas
  end
  return values
end

-- Helper to set smart defaults when Display Mode changes
local function ApplyDisplayModeDefaults(newMode)
  if newMode == "HORIZONTAL" then
    -- Default to RIGHT growth with TOPRIGHT anchor
    CooldownCursorDB.global.stackGrowth = "RIGHT"
    CooldownCursorDB.global.anchor = "TOPRIGHT"
  elseif newMode == "VERTICAL" then
    -- Default to DOWN growth with BOTTOM anchor
    CooldownCursorDB.global.stackGrowth = "DOWN"
    CooldownCursorDB.global.anchor = "BOTTOM"
  elseif newMode == "RADIUS" then
    -- Default to CLOCKWISE growth with CENTER anchor
    CooldownCursorDB.global.stackGrowth = "CLOCKWISE"
    CooldownCursorDB.global.anchor = "CENTER"
  end
  -- SINGLE mode: no automatic changes
end

local function HexColorGet(key, fallbackHex)
  -- AceConfig color expects r,g,b,a in 0..1
  local hex = (CooldownCursor:GetDBValue(key) or fallbackHex or "ffffff"):gsub("#", "")
  if #hex ~= 6 then hex = "ffffff" end
  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255
  return r, g, b, 1
end

local function HexColorSet(key, r, g, b, a)
  local function toHex(x)
    x = math.floor((x or 1) * 255 + 0.5)
    return string.format("%02x", math.max(0, math.min(255, x)))
  end
  local hex = toHex(r) .. toHex(g) .. toHex(b)
  CooldownCursor:SetDBString(key, "#" .. hex)
end

local options = {
  type = "group",
  name = name,
  args = {

    -- header = {
    --   type = "header",
    --   name = "Options",
    --   order = 0,
    -- },
    preview = {
      type = "execute",
      name = "Toggle Preview",
      desc = "Click to see your current settings in action!\n\n" ..
          "The preview will loop continuously until you click again to turn it off.",
      order = 50,
      width = "normal",
      func = function() CooldownCursor:Preview() end,
    },

    previewMouse = {
      type = "toggle",
      name = "Preview Follows Cursor",
      desc = "Make the preview icons follow your mouse cursor.\n\n" ..
          "When disabled, icons appear next to the settings panel.",
      order = 60,
      width = "normal",
      get = function() return CooldownCursor:GetPreviewMouseMode() end,
      set = function(_, v) CooldownCursor:SetPreviewMouseMode(v) end,
    },

    -- ========================================
    -- QUICK SETTINGS TAB
    -- ========================================
    quickSettings = {
      type = "group",
      name = "Quick Settings",
      order = 0,
      args = {

        welcomeHeader = {
          type = "header",
          name = "Quick Settings",
          order = 1,
        },

        description = {
          type = "description",
          name = "|cff00ff00Quick access to the most commonly used settings.|r\n" ..
              "To start tracking cooldowns, add spells in the |cffffd100Spell Rules|r tab.\n" ..
              "Configure options here, then explore other tabs for advanced settings.",
          order = 2,
        },

        spacer0 = {
          type = "description",
          name = " ",
          order = 3,
        },

        enabled = {
          type = "toggle",
          name = "Enable Addon",
          desc = "Turn CooldownCursor on or off.\n\n" ..
              "When disabled, no cooldown icons will appear at your cursor.",
          order = 4,
          width = "normal",
          get = function() return CooldownCursor:GetDBValue("enabled") end,
          set = function(_, v)
            CooldownCursor:SetDBBoolean("enabled", v)
            if not v then
              CooldownCursor:HideIconNow()
            end
          end,
        },

        showProcs = {
          type = "toggle",
          name = "Show Procs",
          desc = "Enable proc detection for spells that can glow.\n\n" ..
              "If disabled, proc visuals are hidden and proc-only icons are hidden.\n\n" .. 
              "|cffff0000NOTE: Spells must be added to the Spell Rules|r",
          order = 4.1,
          width = "normal",
          get = function() return CooldownCursor:GetDBValue("showProcs") end,
          set = function(_, v)
            CooldownCursor:SetDBBoolean("showProcs", v)
            if not v then
              CooldownCursor:ClearProcStates(true)
            end
            CooldownCursor:UpdateDisplay()
          end,
        },

        showCharges = {
          type = "toggle",
          name = "Show Charges",
          desc = "Display the current charge count on spell icons for spells with multiple charges.",
          order = 4.2,
          width = "normal",
          get = function() return CooldownCursor:GetDBValue("showCharges") end,
          set = function(_, v)
            CooldownCursor:SetDBBoolean("showCharges", v)
            CooldownCursor:UpdateDisplay()
          end,
        },

        enabledWarning = {
          type = "description",
          name = function()
            if CooldownCursor:GetDBValue("enabled") == false then
              return "|cffff5555CooldownCursor is currently DISABLED.|r No cooldowns will appear at your cursor."
            end
            return ""
          end,
          order = 4.5,
        },

        spacer1 = {
          type = "description",
          name = " ",
          order = 5,
        },

        displayMode = {
          type = "select",
          name = "Display Mode",
          desc = "How cooldown icons appear:\n\n" ..
              "• SINGLE - Shows only the most recent cooldown (recommended for beginners)\n" ..
              "• VERTICAL - Stack multiple cooldowns vertically\n" ..
              "• HORIZONTAL - Stack multiple cooldowns horizontally\n" ..
              "• RADIUS - Arrange multiple cooldowns in a circle around cursor",
          order = 10,
          width = "normal",
          values = function()
            return CooldownCursor:GetValidStackDirections()
          end,
          get = function()
            return CooldownCursor:GetDBValue("stackDirection")
          end,
          set = function(_, v)
            ApplyDisplayModeDefaults(v)
            CooldownCursor:SetDBString("stackDirection", v)
          end,
        },

        modeInfo = {
          type = "description",
          name = function()
            local mode = CooldownCursor:GetDBValue("stackDirection")
            if mode == "SINGLE" then
              return "|cffaaaaaaSINGLE mode: Shows only your most recent cooldown. Perfect for a clean UI!|r"
            elseif mode == "VERTICAL" or mode == "HORIZONTAL" then
              return "|cffaaaaaaSTACKING mode: Shows multiple cooldowns at once. Configure 'Maximum Icons' in the Layout tab.|r"
            elseif mode == "RADIUS" then
              return "|cffaaaaaaRADIUS mode: Icons form a circle around your cursor. Adjust distance in the Layout tab.|r"
            end
            return ""
          end,
          order = 15,
        },

        spacer2 = {
          type = "description",
          name = " ",
          order = 18,
        },

        showWhen = {
          type = "select",
          name = "Show Icons",
          desc = "When should cooldown icons appear?",
          order = 20,
          width = "normal",
          values = ShowWhenValues(),
          get = function() return CooldownCursor:GetDBValue("showWhen") end,
          set = function(_, v) CooldownCursor:SetDBNumber("showWhen", v) end,
        },

        showBehavior = {
          type = "select",
          name = "Show Behavior",
          desc = "On Cooldown - Icons appear when a spell goes on cooldown.\n\n" ..
              "Off Cooldown - Icons appear when a spell comes off cooldown and is ready to use again.\n\n" ..
              "Auto-Hide After - Icons appear when a spell goes on cooldown and automatically disappear after a set time. See 'Auto-Hide After' option.",
          order = 25,
          width = "normal",
          values = ShowBehaviorValues(),
          get = function() return CooldownCursor:GetDBValue("showBehavior") end,
          set = function(_, v)
            CooldownCursor:SetDBNumber("showBehavior", v)
          end,
        },

        hideAfter = {
          type = "range",
          name = "Auto-Hide After",
          desc = "Icons automatically disappear after this many seconds.\n\n" ..
              "Tip: Set to 30-60 seconds to track important cooldowns longer.",
          order = 30,
          width = "normal",
          min = 1,
          max = 120,
          step = 1,
          disabled = function()
            return CooldownCursor:GetDBValue("showBehavior") ~= 2
          end,
          get = function() return CooldownCursor:GetDBValue("hideAfter") end,
          set = function(_, v) CooldownCursor:SetHideAfter(v) end,
        },

        hideWhileMounted = {
          type = "toggle",
          name = "Hide While Mounted",
          desc = "Don't show icons while you're on a mount.",
          order = 35,
          width = "normal",
          get = function() return CooldownCursor:GetDBValue("hideWhileMounted") end,
          set = function(_, v) CooldownCursor:SetDBBoolean("hideWhileMounted", v) end,
        },

        spacer3 = {
          type = "description",
          name = " ",
          order = 38,
        },


        releaseNotes = {
          type = "header",
          name = "Release Notes",
          order = 100,
        },


        releaseNotesDesc = {
          type = "description",
          name = function()
            -- Build release notes organized by version (newest first)
            if not CooldownCursor.releaseNotes then
              return "Check back after the next update for release notes."
            end

            local notes = CooldownCursor.releaseNotes
            local lines = {}

            -- Iterate through versions (sorted newest first)
            for _, version in ipairs(notes.sortedVersions or {}) do
              local versionNotes = notes.byVersion[version]
              if versionNotes then
                local hasContent = (versionNotes.breakingChanges and #versionNotes.breakingChanges > 0)
                    or (versionNotes.newFeatures and #versionNotes.newFeatures > 0)
                    or (versionNotes.fixes and #versionNotes.fixes > 0)

                if hasContent then
                  -- Version header
                  if #lines > 0 then table.insert(lines, "") end
                  table.insert(lines, "|cff00ff00v" .. version .. "|r")

                  -- Breaking Changes
                  if versionNotes.breakingChanges and #versionNotes.breakingChanges > 0 then
                    table.insert(lines, "  |cffFF1E34Breaking Changes:|r")
                    for _, change in ipairs(versionNotes.breakingChanges) do
                      table.insert(lines, "  • " .. change)
                    end
                  end

                  -- New Features
                  if versionNotes.newFeatures and #versionNotes.newFeatures > 0 then
                    table.insert(lines, "  |cff345BFFNew Features:|r")
                    for _, feature in ipairs(versionNotes.newFeatures) do
                      table.insert(lines, "  • " .. feature)
                    end
                  end

                  -- Fixes
                  if versionNotes.fixes and #versionNotes.fixes > 0 then
                    table.insert(lines, "  |cffFFBB4AFixes:|r")
                    for _, fix in ipairs(versionNotes.fixes) do
                      table.insert(lines, "  • " .. fix)
                    end
                  end
                end
              end
            end

            -- If no versions have content
            if #lines == 0 then
              return "No release notes for this version."
            end

            return table.concat(lines, "\n")
          end,
          order = 101,
          fontSize = "medium",
        },
      },
    },

    -- ========================================
    -- APPEARANCE TAB
    -- ========================================
    appearanceGroup = {
      type = "group",
      name = "Appearance",
      order = 100,
      args = {

        header = {
          type = "header",
          name = "Icon Appearance",
          order = 1,
        },

        description = {
          type = "description",
          name = "Customize how cooldown icons look.",
          order = 2,
        },

        spacer1 = {
          type = "description",
          name = " ",
          order = 5,
        },

        iconSize = {
          type = "range",
          name = "Icon Size",
          desc = "Size of the cooldown icon in pixels.\n\n" ..
              "Recommended: 48-64 for most setups.",
          order = 10,
          width = "normal",
          min = 16,
          max = 128,
          step = 1,
          get = function() return CooldownCursor:GetDBValue("iconSize") end,
          set = function(_, v) CooldownCursor:SetDBNumber("iconSize", v) end,
        },

        scale = {
          type = "range",
          name = "Scale",
          desc = "Overall scale multiplier for icon and text.\n\n" ..
              "Use this to make everything bigger or smaller proportionally.",
          order = 20,
          width = "normal",
          min = 0.5,
          max = 5,
          step = 0.05,
          get = function() return CooldownCursor:GetDBValue("scale") end,
          set = function(_, v) CooldownCursor:SetDBNumber("scale", v) end,
        },

        iconAlpha = {
          type = "range",
          name = "Icon Transparency",
          desc = "How see-through the icon is (0 = invisible, 100 = solid).",
          order = 30,
          width = "normal",
          min = 0,
          max = 100,
          step = 5,
          get = function() return CooldownCursor:GetDBValue("iconAlpha") end,
          set = function(_, v) CooldownCursor:SetDBNumber("iconAlpha", v) end,
        },

        frameStrata1 = {
          type = "select",
          name = "Frame Strata",
          desc = "Controls if icons appear above or below other UI elements.\n\n" ..
              "HIGH (recommended) - Above most UI\n" ..
              "DIALOG - Above everything\n" ..
              "MEDIUM - Standard UI level\n\n" ..
              "Change this if icons are appearing behind other frames.",
          order = 35,
          width = "normal",
          values = FrameStrataValues,
          get = function() return CooldownCursor:GetDBValue("frameStrata") end,
          set = function(_, v) CooldownCursor:SetDBString("frameStrata", v) end,
        },

        spacer2 = {
          type = "description",
          name = " ",
          order = 35,
        },

        visualHeader = {
          type = "header",
          name = "Visual Effects",
          order = 40,
        },

        animation = {
          type = "toggle",
          name = "Pop Animation",
          desc = "Icons briefly scale up when they appear.",
          order = 54,
          width = "normal",
          get = function() return CooldownCursor:GetDBValue("animation") end,
          set = function(_, v) CooldownCursor:SetDBBoolean("animation", v) end,
        },

        procOverlayAtlas = {
          type = "select",
          name = "Proc Overlay Atlas",
          desc = "Select the atlas used for the proc overlay glow.\n\nEnable 'Show Procs' in Quick Settings to see proc visuals and options.",
          order = 50,
          width = "normal",
          disabled = function() return CooldownCursor:GetDBValue("showProcs") == false end,
          values = ProcOverlayAtlasValues(),
          get = function() return CooldownCursor:GetDBValue("procOverlayAtlas") end,
          set = function(_, v)
            CooldownCursor:SetDBString("procOverlayAtlas", v)
            CooldownCursor:UpdateDisplay()
          end,
        },

        procOverlayColor = {
          type = "color",
          name = "Proc Overlay Color",
          desc = "Tint color for the proc overlay glow.",
          order = 50.5,
          disabled = function() return CooldownCursor:GetDBValue("showProcs") == false end,
          get = function() return HexColorGet("procOverlayColor", "FFFFFF") end,
          set = function(_, r, g, b, a) HexColorSet("procOverlayColor", r, g, b, a) end,
        },

        procOutlineAtlas = {
          type = "select",
          name = "Proc Outline Atlas",
          desc = "Select the atlas used for the proc outline border.\n\nEnable 'Show Procs' in Quick Settings to see proc visuals and options.",
          order = 51,
          width = "normal",
          disabled = function() return CooldownCursor:GetDBValue("showProcs") == false end,
          values = ProcOutlineAtlasValues(),
          get = function() return CooldownCursor:GetDBValue("procOutlineAtlas") end,
          set = function(_, v)
            CooldownCursor:SetDBString("procOutlineAtlas", v)
            CooldownCursor:UpdateDisplay()
          end,
        },

        procOutlineColor = {
          type = "color",
          name = "Proc Outline Color",
          desc = "Tint color for the proc outline border.",
          order = 51.5,
          disabled = function() return CooldownCursor:GetDBValue("showProcs") == false end,
          get = function() return HexColorGet("procOutlineColor", "FFFFFF") end,
          set = function(_, r, g, b, a) HexColorSet("procOutlineColor", r, g, b, a) end,
        },


        fadeOutDuration = {
          type = "range",
          name = "Fade Out Duration",
          desc = "How long icons take to fade out when hiding (in seconds).\n\n" ..
              "Set to 0 for instant disappear.",
          order = 55,
          width = "normal",
          min = 0,
          max = 3,
          step = 0.05,
          get = function() return CooldownCursor:GetDBValue("fadeOutDuration") end,
          set = function(_, v) CooldownCursor:SetFadeOutDuration(v) end,
        },

        showCooldownSwipe = {
          type = "toggle",
          name = "Cooldown Swipe",
          desc = "Show the circular 'clock' animation on the icon.",
          order = 60,
          width = "normal",
          get = function() return CooldownCursor:GetDBValue("showCooldownSwipe") end,
          set = function(_, v) CooldownCursor:SetDBBoolean("showCooldownSwipe", v) end,
        },

        iconHide = {
          type = "toggle",
          name = "Hide Icon Texture",
          desc = "Only show the cooldown numbers/text, not the spell icon.\n\n" ..
              "Useful for minimalist setups.",
          order = 70,
          width = "normal",
          get = function() return CooldownCursor:GetDBValue("iconHide") end,
          set = function(_, v) CooldownCursor:SetDBBoolean("iconHide", v) end,
        },

      },
    },

    -- ========================================
    -- DISPLAY & PLACEMENT TAB
    -- ========================================
    positionGroup = {
      type = "group",
      name = "Display & Placement",
      order = 150,
      args = {

        header = {
          type = "header",
          name = "Display & Placement",
          order = 1,
        },

        description = {
          type = "description",
          name = "Configure where cooldown icons appear and how multiple icons are arranged.\n\n" ..
              "|cffaaaaaaTip: Screen mode uses a draggable anchor that is only visible in Preview.|r",
          order = 2,
        },

        spacer1 = {
          type = "description",
          name = " ",
          order = 3,
        },

        placementHeader = {
          type = "header",
          name = "Placement",
          order = 5,
        },

        positionMode = {
          type = "select",
          name = "Position Mode",
          desc = "Choose how cooldown icons are positioned.\n\n" ..
              "Cursor: follow the mouse cursor (default)\n" ..
              "Screen: use a draggable anchor frame (shown only in Preview)",
          order = 10,
          width = "normal",
          values = function()
            return CooldownCursor:GetValidPositionModes()
          end,
          get = function()
            return CooldownCursor:GetDBValue("positionMode")
          end,
          set = function(_, v)
            CooldownCursor:SetDBString("positionMode", v)
          end,
        },

        resetAnchor = {
          type = "execute",
          name = "Reset Anchor Position",
          desc = "Reset the draggable anchor back to the screen center.",
          order = 15,
          width = "normal",
          hidden = function()
            return CooldownCursor:GetDBValue("positionMode") ~= "SCREEN"
          end,
          disabled = function()
            return InCombatLockdown()
          end,
          func = function()
            CooldownCursorDB.global.offsetX = 0
            CooldownCursorDB.global.offsetY = 0
            if Internal and Internal.ApplyPositionMode then
              Internal.ApplyPositionMode()
            end
          end,
        },

        anchor = {
          type = "select",
          name = "Anchor Point",
          desc = "Where to position the icon relative to your cursor.\n\n" ..
              "TOPLEFT = Icon appears above and left of cursor",
          order = 20,
          width = "normal",
          values = AnchorValues,
          disabled = function()
            return CooldownCursor:GetDBValue("positionMode") == "SCREEN"
          end,
          get = function() return CooldownCursor:GetDBValue("anchor") end,
          set = function(_, v) CooldownCursor:SetDBString("anchor", v) end,
        },

        anchorPadding = {
          type = "range",
          name = "Cursor Distance",
          desc = "How far from the cursor the icon appears (in pixels).",
          order = 25,
          width = "normal",
          min = 0,
          max = 100,
          step = 1,
          disabled = function()
            return CooldownCursor:GetDBValue("positionMode") == "SCREEN"
          end,
          get = function() return CooldownCursor:GetDBValue("anchorPadding") end,
          set = function(_, v) CooldownCursor:SetDBNumber("anchorPadding", v) end,
        },

        -- TODO: Working on better offset controls
        -- offsetX = {
        --   type = "range",
        --   name = "Horizontal Offset",
        --   desc = "Additional horizontal adjustment (negative = left, positive = right).",
        --   order = 50,
        --   width = "normal",
        --   min = -500, max = 500, step = 1,
        --   get = function() return CooldownCursor:GetDBValue("offsetX") end,
        --   set = function(_, v) CooldownCursor:SetDBNumber("offsetX", v) end,
        -- },

        -- offsetY = {
        --   type = "range",
        --   name = "Vertical Offset",
        --   desc = "Additional vertical adjustment (negative = down, positive = up).",
        --   order = 60,
        --   width = "normal",
        --   min = -500, max = 500, step = 1,
        --   get = function() return CooldownCursor:GetDBValue("offsetY") end,
        --   set = function(_, v) CooldownCursor:SetDBNumber("offsetY", v) end,
        -- },

        spacer2 = {
          type = "description",
          name = " ",
          order = 30,
        },

        layoutHeader = {
          type = "header",
          name = "Layout",
          order = 40,
        },

        layoutDescription = {
          type = "description",
          name = "|cffaaaaaaTip: These settings only apply when Display Mode is set to VERTICAL, HORIZONTAL, or RADIUS.|r",
          order = 41,
        },

        displayMode = {
          type = "select",
          name = "Display Mode",
          desc = "How cooldown icons appear:\n\n" ..
              "- SINGLE - Shows only the most recent cooldown (recommended for beginners)\n" ..
              "- VERTICAL - Stack multiple cooldowns vertically\n" ..
              "- HORIZONTAL - Stack multiple cooldowns horizontally\n" ..
              "- RADIUS - Arrange multiple cooldowns in a circle around cursor",
          order = 50,
          width = "normal",
          values = function()
            return CooldownCursor:GetValidStackDirections()
          end,
          get = function()
            return CooldownCursor:GetDBValue("stackDirection")
          end,
          set = function(_, v)
            ApplyDisplayModeDefaults(v)
            CooldownCursor:SetDBString("stackDirection", v)
          end,
        },

        maxIcons = {
          type = "range",
          name = "Maximum Icons",
          desc = "How many cooldown icons to show at once.\n\n" ..
              "When you have more cooldowns than this, the oldest/lowest priority icons are removed.",
          order = 60,
          width = "normal",
          min = 1,
          max = 10,
          step = 1,
          disabled = function()
            return CooldownCursor:GetDBValue("stackDirection") == "SINGLE"
          end,
          get = function()
            return CooldownCursor:GetDBValue("maxIcons")
          end,
          set = function(_, v)
            CooldownCursor:SetDBNumber("maxIcons", v)
          end,
        },

        stackGrowth = {
          type = "select",
          name = "Growth Direction",
          desc = "Which direction icons stack in.",
          order = 70,
          width = "normal",
          values = function()
            return CooldownCursor:GetValidStackGrowth()
          end,
          disabled = function()
            return CooldownCursor:GetDBValue("stackDirection") == "SINGLE"
          end,
          get = function()
            return CooldownCursor:GetDBValue("stackGrowth")
          end,
          set = function(_, v)
            CooldownCursor:SetDBString("stackGrowth", v)
          end,
        },

        stackingHeader = {
          type = "header",
          name = "Vertical / Horizontal Spacing",
          order = 80,
        },

        stackSpacing = {
          type = "range",
          name = "Icon Spacing",
          desc = "Gap between stacked icons in pixels.\n\n" ..
              "Only applies to VERTICAL and HORIZONTAL modes.",
          order = 90,
          width = "normal",
          min = -20,
          max = 20,
          step = 1,
          disabled = function()
            local dir = CooldownCursor:GetDBValue("stackDirection")
            return dir == "RADIUS" or dir == "SINGLE"
          end,
          get = function()
            return CooldownCursor:GetDBValue("stackSpacing")
          end,
          set = function(_, v)
            CooldownCursor:SetDBNumber("stackSpacing", v)
          end,
        },

        spacer3 = {
          type = "description",
          name = " ",
          order = 95,
        },

        radiusHeader = {
          type = "header",
          name = "Radius Settings",
          order = 100,
        },

        radiusDistance = {
          type = "range",
          name = "Circle Radius",
          desc = "Distance from cursor for radius layout (in pixels).\n\n" ..
              "Only applies to RADIUS mode.",
          order = 110,
          width = "normal",
          min = 40,
          max = 200,
          step = 5,
          disabled = function()
            return CooldownCursor:GetDBValue("stackDirection") ~= "RADIUS"
          end,
          get = function()
            return CooldownCursor:GetDBValue("radiusDistance")
          end,
          set = function(_, v)
            CooldownCursor:SetDBNumber("radiusDistance", v)
          end,
        },

        radiusStartAngle = {
          type = "range",
          name = "Starting Angle",
          desc = "Where the first icon appears in the circle:\n" ..
              "- 0 deg = Right\n" ..
              "- 90 deg = Bottom\n" ..
              "- 180 deg = Left\n" ..
              "- 270 deg = Top",
          order = 120,
          width = "normal",
          min = 0,
          max = 359,
          step = 15,
          disabled = function()
            return CooldownCursor:GetDBValue("stackDirection") ~= "RADIUS"
          end,
          get = function()
            return CooldownCursor:GetDBValue("radiusStartAngle")
          end,
          set = function(_, v)
            CooldownCursor:SetDBNumber("radiusStartAngle", v)
          end,
        },

        spacer4 = {
          type = "description",
          name = " ",
          order = 125,
        },

        sortHeader = {
          type = "header",
          name = "Icon Sorting",
          order = 130,
        },

        sortOrder = {
          type = "select",
          name = "Sort By",
          desc = "How to order multiple cooldown icons.",
          order = 140,
          width = "normal",
          values = function()
            return CooldownCursor:GetValidSortOrders()
          end,
          disabled = function()
            return CooldownCursor:GetDBValue("stackDirection") == "SINGLE"
          end,
          get = function()
            return CooldownCursor:GetDBValue("sortOrder")
          end,
          set = function(_, v)
            CooldownCursor:SetDBString("sortOrder", v)
          end,
        },

        sortDescription = {
          type = "description",
          name = function()
            local dir = CooldownCursor:GetDBValue("stackDirection")
            if dir == "SINGLE" then
              return "|cffaaaaaa- Sorting doesn't apply in SINGLE mode|r"
            end
            local sortOrder = CooldownCursor:GetDBValue("sortOrder")
            if sortOrder == "DURATION" then
              return "|cffaaaaaa- Shortest cooldowns appear first|r"
            elseif sortOrder == "ALPHABETICAL" then
              return "|cffaaaaaa- Sorted A-Z by spell name|r"
            elseif sortOrder == "PRIORITY" then
              return "|cffaaaaaa- Sorted by spell rule priority (set in Spell Rules tab)|r"
            elseif sortOrder == "TIME_ADDED" then
              return "|cffaaaaaa- Oldest cooldowns appear first|r"
            end
            return ""
          end,
          order = 145,
        },
      },
    },

    -- ========================================
    -- TEXT & NUMBERS TAB
    -- ========================================
    textGroup = {
      type = "group",
      name = "Text & Numbers",
      order = 300,
      args = {

        spellNamesHeader = {
          type = "header",
          name = "Spell Names",
          order = 1,
        },

        showSpellNames = {
          type = "toggle",
          name = "Show Spell Names",
          desc = "Display the name of the spell below the icon.",
          order = 10,
          width = "normal",
          get = function() return CooldownCursor:GetDBValue("showSpellNames") end,
          set = function(_, v) CooldownCursor:SetDBBoolean("showSpellNames", v) end,
        },

        spellTextSize = {
          type = "range",
          name = "Font Size",
          order = 20,
          width = "normal",
          min = 6,
          max = 32,
          step = 1,
          disabled = function() return not CooldownCursor:GetDBValue("showSpellNames") end,
          get = function() return CooldownCursor:GetDBValue("spellTextSize") end,
          set = function(_, v) CooldownCursor:SetDBNumber("spellTextSize", v) end,
        },

        spellTextFont = {
          type = "select",
          name = "Font",
          order = 30,
          width = "normal",
          disabled = function() return not CooldownCursor:GetDBValue("showSpellNames") end,
          values = FontValues,
          -- dialogControl = "LSM30_Font", TODO: https://github.com/SFX-WoW/AceGUI-3.0_SFX-Widgets/wiki/Installation
          -- values = AceGUIWidgetLSMlists.font,
          get = function() return CooldownCursor:GetDBValue("spellTextFont") end,
          set = function(_, v) CooldownCursor:SetFontPath("spellTextFont", v) end,
        },

        spellTextFontType = {
          type = "select",
          name = "Font Type",
          order = 35,
          values = fontTypeValues,
          get = function() return (CooldownCursor:GetDBValue("spellTextFontType")) end,
          set = function(_, v)
            CooldownCursor:SetDBString("spellTextFontType", v)
          end,
        },

        spellTextColor = {
          type = "color",
          name = "Color",
          hasAlpha = false,
          order = 40,
          width = "normal",
          disabled = function() return not CooldownCursor:GetDBValue("showSpellNames") end,
          get = function() return HexColorGet("spellTextColor", "FFD100") end,
          set = function(_, r, g, b, a) HexColorSet("spellTextColor", r, g, b, a) end,
        },

        spacer1 = {
          type = "description",
          name = " ",
          order = 45,
        },

        cooldownNumbersHeader = {
          type = "header",
          name = "Cooldown Numbers",
          order = 50,
        },

        cooldownNumbersNote = {
          type = "description",
          name = "Customize how the cooldown timer appears on the icon.",
          order = 55,
        },

        hideCooldownNumbers = {
          type = "toggle",
          name = "Hide Cooldown Numbers",
          desc = "Don't show the countdown timer on icons.",
          order = 60,
          width = "normal",
          get = function() return CooldownCursor:GetDBValue("hideCooldownNumbers") end,
          set = function(_, v) CooldownCursor:SetDBBoolean("hideCooldownNumbers", v) end,
        },

        cooldownTextSize = {
          type = "range",
          name = "Font Size",
          order = 70,
          width = "normal",
          min = 6,
          max = 48,
          step = 1,
          disabled = function()
            return CooldownCursor:GetDBValue("hideCooldownNumbers")
          end,
          get = function() return CooldownCursor:GetDBValue("cooldownTextSize") end,
          set = function(_, v) CooldownCursor:SetDBNumber("cooldownTextSize", v) end,
        },

        cooldownTextFont = {
          type = "select",
          name = "Font",
          order = 80,
          width = "normal",
          disabled = function()
            return CooldownCursor:GetDBValue("hideCooldownNumbers")
          end,
          values = FontValues,
          -- dialogControl = "LSM30_Font", TODO: https://github.com/SFX-WoW/AceGUI-3.0_SFX-Widgets/wiki/Installation
          -- values = AceGUIWidgetLSMlists.font,
          get = function() return CooldownCursor:GetDBValue("cooldownTextFont") end,
          set = function(_, v) CooldownCursor:SetFontPath("cooldownTextFont", v) end,
        },

        cooldownTextFontType = {
          type = "select",
          name = "Font Type",
          order = 85,
          disabled = false,
          values = fontTypeValues,
          get = function() return (CooldownCursor:GetDBValue("cooldownTextFontType") or "OUTLINE") end,
          set = function(_, v)
            CooldownCursor:SetDBString("cooldownTextFontType", v)
          end,
        },

        cooldownTextColor = {
          type = "color",
          name = "Color",
          hasAlpha = false,
          order = 90,
          width = "normal",
          disabled = function()
            return CooldownCursor:GetDBValue("hideCooldownNumbers")
          end,
          get = function() return HexColorGet("cooldownTextColor", "FFFFFF") end,
          set = function(_, r, g, b, a) HexColorSet("cooldownTextColor", r, g, b, a) end,
        },

        cooldownTextAnchor = {
          type = "select",
          name = "Position",
          desc = "Where to position the cooldown number on the icon.",
          order = 100,
          width = "normal",
          disabled = function()
            return CooldownCursor:GetDBValue("hideCooldownNumbers")
          end,
          values = AnchorValues,
          get = function() return CooldownCursor:GetDBValue("cooldownTextAnchor") end,
          set = function(_, v) CooldownCursor:SetDBString("cooldownTextAnchor", v) end,
        },

        -- Charge Count section
        chargeCountHeader = {
          type = "header",
          name = "Charge Count",
          order = 110,
        },

        chargeTextSize = {
          type = "range",
          name = "Font Size",
          desc = "Size of the charge count text.",
          order = 120,
          min = 6,
          max = 32,
          step = 1,
          width = "normal",
          disabled = function() return CooldownCursor:GetDBValue("showCharges") == false end,
          get = function() return CooldownCursor:GetDBValue("chargeTextSize") end,
          set = function(_, v) CooldownCursor:SetDBNumber("chargeTextSize", v) end,
        },

        chargeTextFont = {
          type = "select",
          name = "Font",
          desc = "Font used for the charge count text.",
          order = 130,
          width = "normal",
          disabled = function() return CooldownCursor:GetDBValue("showCharges") == false end,
          values = FontValues,
          get = function() return CooldownCursor:GetDBValue("chargeTextFont") end,
          set = function(_, v) CooldownCursor:SetFontPath("chargeTextFont", v) end,
        },

        chargeTextFontType = {
          type = "select",
          name = "Font Type",
          desc = "Font outline type for the charge count text.",
          order = 140,
          width = "normal",
          disabled = function() return CooldownCursor:GetDBValue("showCharges") == false end,
          values = fontTypeValues,
          get = function() return CooldownCursor:GetDBValue("chargeTextFontType") end,
          set = function(_, v)
            CooldownCursor:SetDBString("chargeTextFontType", v)
          end,
        },

        chargeTextColor = {
          type = "color",
          name = "Color",
          hasAlpha = false,
          order = 150,
          width = "normal",
          disabled = function() return CooldownCursor:GetDBValue("showCharges") == false end,
          get = function() return HexColorGet("chargeTextColor", "FFFFFF") end,
          set = function(_, r, g, b, a) HexColorSet("chargeTextColor", r, g, b, a) end,
        },

        chargeTextAnchor = {
          type = "select",
          name = "Position",
          desc = "Where to position the charge count on the icon.",
          order = 160,
          width = "normal",
          disabled = function() return CooldownCursor:GetDBValue("showCharges") == false end,
          values = AnchorValues,
          get = function() return CooldownCursor:GetDBValue("chargeTextAnchor") end,
          set = function(_, v) CooldownCursor:SetDBString("chargeTextAnchor", v) end,
        },
      },
    },

    spellRulesGroup = {
      type = "group",
      name = "Spell Rules",
      order = 400,
      args = {

        classHeader = {
          type = "description",
          name = function()
            local class = CooldownCursor:GetPlayerClass()
            if class then
              -- Class colors (approximate WoW class colors)
              local classColors = {
                WARRIOR = "C69B6D",
                PALADIN = "F48CBA",
                HUNTER = "AAD372",
                ROGUE = "FFF468",
                PRIEST = "FFFFFF",
                DEATHKNIGHT = "C41E3A",
                SHAMAN = "0070DD",
                MAGE = "3FC7EB",
                WARLOCK = "8788EE",
                MONK = "00FF98",
                DRUID = "FF7C0A",
                DEMONHUNTER = "A330C9",
                EVOKER = "33937F",
              }
              local color = classColors[class] or "FFFFFF"
              return string.format("|cff%s%s|r Spell Rules", color, class:gsub("^%l", string.upper):gsub("(%u)", " %1"):sub(2))
            end
            return "Spell Rules"
          end,
          fontSize = "large",
          order = 399,
        },

        specHeader = {
          type = "description",
          name = function()
            local specIndex = GetSpecialization()
            if specIndex then
              local _, specName, _, specIcon = GetSpecializationInfo(specIndex)
              if specName then
                local iconText = specIcon and string.format("|T%d:16:16:0:0|t ", specIcon) or ""
                return string.format("%s|cffffff00%s|r Specialization", iconText, specName)
              end
            end
            return ""
          end,
          fontSize = "medium",
          order = 399.5,
        },

        rulesDescription = {
          type = "description",
          name = function()
            local class = CooldownCursor:GetPlayerClass()
            local classText = class and string.format(" for your |cffffd100%s|r", class:lower():gsub("^%l", string.upper)) or ""
            return "Manage which spells show cooldowns at your cursor" .. classText .. ".\n\n" ..
                "|cffaaaaaaTip: Spells not known to your current spec are automatically hidden.|r"
          end,
          order = 400,
        },

        header = {
          type = "header",
          name = "Add from Spellbook",
          order = 415,
        },

        spellbookDescription = {
          type = "description",
          name = function()
            if InCombatLockdown() then
              return "|cffff5555You are in combat!|r\n" ..
                  "The spellbook cannot be accessed during combat. " ..
                  "You can still add spells manually using the Spell ID field below."
            end
            return "Select a spell from your spellbook to add it as a rule, or manually enter a Spell ID below."
          end,
          order = 416,
        },

        spellbookDropdown = {
          type = "select",
          name = "Select Spell",
          desc = "Choose a spell from your spellbook with a cooldown.\n\n" ..
              "|cffaaaaaaTip: This list shows all your active spells that have cooldowns.|r",
          order = 417,
          width = "double",
          disabled = function()
            return InCombatLockdown()
          end,
          values = function()
            if InCombatLockdown() then
              return { [0] = "|cff888888-- Not available in combat --|r" }
            end
            local values = { [0] = "|cff888888-- Select a spell --|r" }
            local includeNoCooldown = CooldownCursor._includeNoCooldownSpells ~= false
            local includePets = CooldownCursor._includePetSpells or false
            local spells = CooldownCursor:GetCooldownSpells(includePets, 0, true, includeNoCooldown)

            for _, spell in ipairs(spells) do
              if spell.spellID and spell.name then
                -- Format: "|Ticon:size|t Spell Name (ID) [Tab]"
                local icon = spell.iconID and string.format("|T%d:14:14:0:0|t ", spell.iconID) or ""
                local label = string.format("%s%s |cff888888(%d)|r", icon, spell.name, spell.spellID)
                if spell.tabName then
                  label = label .. string.format(" |cff666666[%s]|r", spell.tabName)
                end
                values[spell.spellID] = label
              end
            end

            return values
          end,
          sorting = function()
            -- Return spellIDs sorted alphabetically by spell name
            local includeNoCooldown = CooldownCursor._includeNoCooldownSpells ~= false
            local includePets = CooldownCursor._includePetSpells or false
            local spells = CooldownCursor:GetCooldownSpells(includePets, 0, true, includeNoCooldown)
            table.sort(spells, function(a, b)
              return (a.name or ""):lower() < (b.name or ""):lower()
            end)

            local sortedKeys = { 0 } -- "Select a spell" first
            for _, spell in ipairs(spells) do
              if spell.spellID then
                table.insert(sortedKeys, spell.spellID)
              end
            end
            return sortedKeys
          end,
          get = function()
            return CooldownCursor._selectedSpellbookSpell or 0
          end,
          set = function(_, v)
            CooldownCursor._selectedSpellbookSpell = v
            if v and v > 0 then
              -- Auto-fill the spell ID input
              CooldownCursor._newRuleSpellID = v
              CooldownCursor._spellRuleStatusText = nil
              CooldownCursor:NotifyOptionsChanged()
            end
          end,
        },

        includePetSpells = {
          type = "toggle",
          name = "Pet Spells",
          desc = "Include pet spells in the dropdown list.",
          order = 418.5,
          width = "normal",
          disabled = function()
            return InCombatLockdown()
          end,
          get = function()
            return CooldownCursor._includePetSpells or false
          end,
          set = function(_, v)
            CooldownCursor._includePetSpells = v
            CooldownCursor._selectedSpellbookSpell = 0
            CooldownCursor:NotifyOptionsChanged()
          end,
        },

        includeNoCooldownSpells = {
          type = "toggle",
          name = "Non-Cooldown Spells",
          desc = "Show spells without cooldowns in the dropdown list.\n\n" ..
              "Useful for adding spells that don't have a base cooldown (e.g. procs, buffs).",
          order = 418,
          width = "normal",
          disabled = function()
            return InCombatLockdown()
          end,
          get = function()
            return CooldownCursor._includeNoCooldownSpells ~= false
          end,
          set = function(_, v)
            CooldownCursor._includeNoCooldownSpells = v
            CooldownCursor._selectedSpellbookSpell = 0
            CooldownCursor:NotifyOptionsChanged()
          end,
        },

        addFromSpellbook = {
          type = "execute",
          name = "Add",
          desc = "Add the selected spell to your rules.\n\n" ..
              "|cffaaaaaaTip: Select a spell from the dropdown first.|r",
          order = 417.5,
          width = "half",
          func = function()
            local spellID = CooldownCursor._selectedSpellbookSpell
            if not spellID or spellID == 0 then
              CooldownCursor._spellRuleStatusText = "Please select a spell first"
              CooldownCursor._spellRuleStatusColor = "ff5555"
              CooldownCursor:NotifyOptionsChanged()
              return
            end

            local info = C_Spell.GetSpellInfo(spellID)
            if not info then
              CooldownCursor._spellRuleStatusText = "Spell not found"
              CooldownCursor._spellRuleStatusColor = "ff5555"
              CooldownCursor:NotifyOptionsChanged()
              return
            end

            -- Add rule with default settings (enabled by default)
            CooldownCursor:AddOrUpdateSpellRule(spellID, {
              enabled = true,
              priority = 0,
            })

            CooldownCursor._spellRuleStatusText =
                ("Added: %s (%d)"):format(info.name, spellID)
            CooldownCursor._spellRuleStatusColor = "55ff55"

            -- Reset selection
            CooldownCursor._selectedSpellbookSpell = 0

            CooldownCursor:RebuildSpellRuleOptions()
            CooldownCursor:NotifyOptionsChanged()
            CooldownCursor:UpdateDisplay()
          end,
        },

        spacer1 = {
          type = "description",
          name = " ",
          order = 419,
        },

        manualHeader = {
          type = "header",
          name = "Edit Mode",
          order = 420,
        },

        manualDescription = {
          type = "description",
          name = function()
            local spellID = CooldownCursor._newRuleSpellID
            if spellID and spellID > 0 then
              local info = C_Spell.GetSpellInfo(spellID)
              if info then
                local icon = info.iconID and string.format("|T%d:20:20:0:0|t ", info.iconID) or ""
                local baseCooldownMS = GetSpellBaseCooldown(spellID)
                local baseCooldown = baseCooldownMS and (baseCooldownMS / 1000) or 0

                local details = string.format(
                  "%s|cff00ff00%s|r  |cff888888(ID: %d)|r\n" ..
                  "Base Cooldown: |cffffffff%s|r",
                  icon,
                  info.name,
                  spellID,
                  baseCooldown > 0 and string.format("%.1fs", baseCooldown) or "None"
                )
                return details
              else
                return "|cffff5555Spell not found.|r Enter a valid Spell ID."
              end
            end
            return "Select a spell from the dropdown above, or enter a Spell ID manually."
          end,
          order = 420.5,
        },

        spacer = {
          type = "description",
          name = " ",
          order = 420.6,
        },

        spellID = {
          type = "input",
          name = "Spell ID",
          desc = "Enter a numeric spell ID (e.g. 13750).",
          order = 421,
          width = "half",
          get = function()
            return tostring(CooldownCursor._newRuleSpellID or "")
          end,

          set = function(_, value)
            local id = tonumber(value)
            CooldownCursor._newRuleSpellID = id
            CooldownCursor:NotifyOptionsChanged()
          end,
        },

        enabled = {
          type = "toggle",
          name = "Enabled",
          desc = "When enabled, this spell will show cooldowns at your cursor.",
          order = 422,
          get = function()
            return CooldownCursor._newRuleEnabled ~= false
          end,
          set = function(_, v)
            CooldownCursor._newRuleEnabled = v
          end,
        },

        priority = {
          type = "range",
          name = "Priority",
          desc = "Priority for this spell (0-100, higher appears first in Priority sort mode).",
          order = 423,
          min = 0,
          max = 100,
          step = 1,
          width = "normal",
          disabled = function()
            return CooldownCursor:GetDBValue("stackDirection") == "SINGLE"
          end,
          get = function()
            return CooldownCursor._newRulePriority or 0
          end,
          set = function(_, v)
            CooldownCursor._newRulePriority = v
          end,
        },

        iconSize = {
          type = "range",
          name = "Icon Size",
          order = 424,
          min = 16,
          max = 128,
          step = 1,
          disabled = function()
            return CooldownCursor._newRuleUseGlobalIconSize ~= false
          end,
          get = function()
            return CooldownCursor._newRuleIconSize or CooldownCursor:GetDBValue("iconSize")
          end,
          set = function(_, v)
            CooldownCursor._newRuleIconSize = v
            CooldownCursor._newRuleUseGlobalIconSize = false
          end,
        },

        useGlobalIconSize = {
          type = "toggle",
          name = "Use Global Icon Size",
          desc = "Use the global icon size instead of a per-spell value.",
          order = 424.5,
          get = function()
            return CooldownCursor._newRuleUseGlobalIconSize ~= false
          end,
          set = function(_, v)
            CooldownCursor._newRuleUseGlobalIconSize = v
            if v then
              CooldownCursor._newRuleIconSize = nil
            end
          end,
        },

        add = {
          type = "execute",
          name = "Add / Update",
          order = 425,
          func = function()
            local spellID = CooldownCursor._newRuleSpellID

            if not spellID then
              CooldownCursor._spellRuleStatusText = "Invalid Spell ID"
              CooldownCursor._spellRuleStatusColor = "ff5555" -- red
              CooldownCursor:NotifyOptionsChanged()
              return
            end

            local info = C_Spell.GetSpellInfo(spellID)
            if not info then
              CooldownCursor._spellRuleStatusText = "Spell not found"
              CooldownCursor._spellRuleStatusColor = "ff5555"
              CooldownCursor:NotifyOptionsChanged()
              return
            end

            -- Add / update rule
            local useGlobal = CooldownCursor._newRuleUseGlobalIconSize ~= false
            CooldownCursor:AddOrUpdateSpellRule(spellID, {
              enabled  = CooldownCursor._newRuleEnabled ~= false,
              iconSize = useGlobal and nil or CooldownCursor._newRuleIconSize,
              useGlobalIconSize = useGlobal,
              priority = CooldownCursor._newRulePriority or 0,
            })

            CooldownCursor._spellRuleStatusText =
                ("Added: %s (%d)"):format(info.name, spellID)
            CooldownCursor._spellRuleStatusColor = "55ff55" -- green

            -- Reset inputs
            CooldownCursor._newRuleSpellID = nil
            CooldownCursor._newRulePriority = nil
            CooldownCursor._newRuleIconSize = nil
            CooldownCursor._newRuleUseGlobalIconSize = nil

            CooldownCursor:RebuildSpellRuleOptions()
            CooldownCursor:NotifyOptionsChanged()
            CooldownCursor:UpdateDisplay()
          end,
        },

        statusText = {
          type = "description",
          name = function()
            if not CooldownCursor._spellRuleStatusText then
              return nil
            end
            return string.format(
              "|cff%s%s|r",
              CooldownCursor._spellRuleStatusColor,
              CooldownCursor._spellRuleStatusText
            )
          end,
          order = 424.5,
        },

        spellbookHeader = {
          type = "header",
          name = "",
          order = 500,
        },

        refreshSpellbook = {
          type = "execute",
          name = "Refresh Spellbook",
          desc = "Refresh the spellbook list.\n\n" ..
              "|cffaaaaaaTip: Use this after changing talents or specialization.|r",
          order = 510,
          disabled = function()
            return InCombatLockdown()
          end,
          func = function()
            CooldownCursor:InvalidateSpellBookCache()
            CooldownCursor._spellRuleStatusText = "Spellbook refreshed!"
            CooldownCursor._spellRuleStatusColor = "55ff55"
            CooldownCursor:NotifyOptionsChanged()
          end,
        },
      },
    },

    -- ========================================
    -- ADVANCED TAB
    -- ========================================
    advancedGroup = {
      type = "group",
      name = "Advanced",
      order = 500,
      args = {

        header = {
          type = "header",
          name = "Advanced Settings",
          order = 1,
        },

        description = {
          type = "description",
          name = "|cffff8800Warning:|r These settings are for advanced users.\n" ..
              "Most users won't need to change these!",
          order = 2,
        },

        spacer1 = {
          type = "description",
          name = " ",
          order = 5,
        },

        performanceHeader = {
          type = "header",
          name = "Performance",
          order = 10,
        },

        iconPoolSize = {
          type = "range",
          name = "Icon Pool Size",
          desc = "Pre-creates this many icon frames for better performance.\n\n" ..
              "|cffff8800Requires /reload to take effect.|r\n\n" ..
              "Set higher than 'Maximum Icons' for best performance.",
          order = 20,
          width = "normal",
          min = 5,
          max = 20,
          step = 1,
          get = function()
            return CooldownCursor:GetDBValue("iconPoolSize")
          end,
          set = function(_, v)
            CooldownCursor:SetDBNumber("iconPoolSize", v)
          end,
        },

        spacer2 = {
          type = "description",
          name = " ",
          order = 35,
        },

        resetHeader = {
          type = "header",
          name = "Reset",
          order = 50,
        },

        reset = {
          type = "execute",
          name = "Reset All Settings",
          desc = "Reset everything to default values (except Spell Rules).",
          order = 60,
          confirm = true,
          func = function() CooldownCursor:ResetSettings() end,
        },

        clearAllSpellRules = {
          type = "execute",
          name = function()
            local class = CooldownCursor:GetPlayerClass()
            if class then
              return "Clear " .. class:gsub("^%l", string.upper):gsub("(%u)", " %1"):sub(2) .. " Spell Rules"
            end
            return "Clear All Spell Rules"
          end,
          desc = function()
            local class = CooldownCursor:GetPlayerClass()
            local classText = class and string.format(" for your %s", class:lower():gsub("^%l", string.upper)) or ""
            return "Remove all spell rules" .. classText .. ".\n\n" ..
                "|cffff8800Warning:|r This cannot be undone!"
          end,
          order = 70,
          confirm = true,
          confirmText = "Are you sure you want to delete ALL spell rules for this class? This cannot be undone.",
          func = function()
            local class = CooldownCursor:GetPlayerClass()
            if class and CooldownCursorDB.spellRules and CooldownCursorDB.spellRules.rules then
              CooldownCursorDB.spellRules.rules[class] = {}
            end
            CooldownCursor:RebuildSpellRuleOptions()
            CooldownCursor:NotifyOptionsChanged()
            CooldownCursor:UpdateDisplay()
          end,
        },

        spellRulesHeader = {
          type = "header",
          name = "Spell Rules",
          order = 80,
        },

        disableRules = {
          type = "toggle",
          name = "Disable All Spell Rules",
          desc = "When enabled, spell rules are ignored and all spells will show cooldowns.",
          order = 90,
          get = function()
            return CooldownCursorDB.spellRules.settings.disableRules
          end,
          set = function(_, v)
            CooldownCursorDB.spellRules.settings.disableRules = v
            CooldownCursor:UpdateDisplay()
            CooldownCursor:RebuildSpellRuleOptions()
            CooldownCursor:NotifyOptionsChanged()
          end,
        },

        disableRulesWarning = {
          type = "description",
          name = function()
            if CooldownCursorDB.spellRules.settings.disableRules then
              return "|cffff5555Spell rules are currently DISABLED.|r All spells will show cooldowns."
            end
            return ""
          end,
          order = 91,
        },

        spacer3 = {
          type = "description",
          name = " ",
          order = 95,
        },

        utilityHeader = {
          type = "header",
          name = "Utility",
          order = 100,
        },

        exportSettings = {
          type = "execute",
          name = "Export Settings to Chat",
          desc = "Dumps all your current settings to the chat window.\n\n" ..
              "Use this to share your configuration with others or when reporting issues to the developer.",
          order = 105,
          func = function()
            CooldownCursor:ExportSettings()
          end,
        },

        spacer4 = {
          type = "description",
          name = " ",
          order = 106,
        },

        exportStringHeader = {
          type = "header",
          name = "Share Configuration",
          order = 107,
        },

        exportStringDesc = {
          type = "description",
          name = "Generate a copyable string of your settings to share with others.\n\n" ..
              "|cffaaaaaaTip: Click the button below, then click in the text box, press Ctrl+A to select all, and Ctrl+C to copy.|r",
          order = 108,
        },

        generateExportString = {
          type = "execute",
          name = "Generate Export String",
          desc = "Creates a copyable string containing all your settings.",
          order = 109,
          width = "normal",
          func = function()
            CooldownCursor._exportString = CooldownCursor:SerializeSettings()
            CooldownCursor:NotifyOptionsChanged()
          end,
        },

        exportString = {
          type = "input",
          name = "Settings String",
          desc = "Click in the box, press Ctrl+A to select all, then Ctrl+C to copy.",
          order = 110,
          width = "full",
          multiline = 8,
          get = function()
            return CooldownCursor._exportString or "Click 'Generate Export String' above to create a shareable settings string."
          end,
          set = function() end, -- Read-only
        },

        spacer5 = {
          type = "description",
          name = " ",
          order = 111,
        },

        reloadUI = {
          type = "execute",
          name = "Reload UI",
          desc = "Reloads the user interface.\n\n" ..
              "Use this after changing settings that require a reload (like Icon Pool Size).",
          order = 105.5,
          confirm = true,
          confirmText = "Reload the UI now?",
          func = function()
            ReloadUI()
          end,
        },
      },
    },

    -- ========================================
    -- ABOUT TAB
    -- ========================================
    maintainerGroup = {
      type = "group",
      name = "About",
      order = 1000,
      args = {
        header = {
          type = "header",
          name = "CooldownCursor",
          order = 1,
        },

        version = {
          type = "description",
          name = function()
            return string.format("|cff00ff00Version:|r %s", CooldownCursor:GetVersion() or "Unknown")
          end,
          fontSize = "medium",
          order = 10,
        },

        author = {
          type = "description",
          name = function()
            return string.format("|cff00ff00Author:|r %s", CooldownCursor:GetAuthor() or "Unknown")
          end,
          fontSize = "medium",
          order = 20,
        },

        description = {
          type = "description",
          name = function()
            return CooldownCursor:GetNotes() or ""
          end,
          order = 30,
        },
      },
    },
  },
}

-- Expose options table
CooldownCursor.options = options


function CooldownCursor:OnOptionsOpened()
  -- Options Panel Opened
  State.optionsOpen = true
  self:RebuildSpellRuleOptions()
  CooldownCursor:ApplyBreakingChangesAndSetReleaseNotes()
  if Internal and Internal.UpdateAnchorVisibility then
    Internal.UpdateAnchorVisibility()
  end
end

function CooldownCursor:OnOptionsClosed()
  -- Options Panel Closed
  State.optionsOpen = false
  CooldownCursor:SetPreviewMouseMode(true)
  if Internal and Internal.UpdateAnchorVisibility then
    Internal.UpdateAnchorVisibility()
  end
end

function CooldownCursor:isAceConfigLoaded()
  return AceConfig and AceConfigDialog
end

function CooldownCursor:InitAce3Options()
  if not self:isAceConfigLoaded() then return end

  -- Register option schema
  AceConfig:RegisterOptionsTable(OPTIONS_APP_NAME, options)

  -- Register Blizzard Settings panel
  AceConfigDialog:AddToBlizOptions(
    OPTIONS_APP_NAME,
    "CooldownCursor"
  )

  -- Detect Blizzard Settings panel open
  hooksecurefunc(SettingsPanel, "Open", function()
    self:OnOptionsOpened()
  end)

  -- Detect Blizzard Settings panel closed
  hooksecurefunc(SettingsPanel, "Close", function()
    self:OnOptionsClosed()
  end)

  -- Build dynamic spell rule UI
  self:RebuildSpellRuleOptions()

  -- Tell AceConfig the table changed
  LibStub("AceConfigRegistry-3.0"):NotifyChange("CooldownCursor")
end

function CooldownCursor:NotifyOptionsChanged()
  local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
  if AceConfigRegistry then
    AceConfigRegistry:NotifyChange("CooldownCursor")
  end
end

