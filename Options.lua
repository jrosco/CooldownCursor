local addonName, addonTable = ...
local CooldownCursor = addonTable.Frame
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

local fontTypeValues = {
  NONE = "None",
  OUTLINE = "Outline",
  THICKOUTLINE = "Thick Outline",
  MONOCHROME = "Monochrome",
  MONOCHROMEOUTLINE = "Monochrome Outline",
  MONOCHROMETHICKOUTLINE = "Monochrome Thick Outline",
}

local function GetRuleDisplayColor(enabled)
  local whitelistSuffix = ""
  local blacklistSuffix = ""
  if CooldownCursorDB.spellRules.settings.disableRules then
    return "9d9d9d", "(disabled)"
  end

  if CooldownCursorDB.spellRules.settings.whitelist then
    whitelistSuffix = "(*)"
  end
  if not CooldownCursorDB.spellRules.settings.whitelist then
    blacklistSuffix = "(*)"
  end
  if enabled == nil then return "ffff00", "" end
  if enabled then return "00ff00", whitelistSuffix end

  return "ff5555", blacklistSuffix
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

  CooldownCursorDB.spellRules = CooldownCursorDB.spellRules or { rules = {} }

  -- Build sortable list
  local sorted = {}

  for spellID, rule in pairs(CooldownCursorDB.spellRules.rules) do
    if type(spellID) == "number" then
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

  -- Sort alphabetically (case-insensitive)
  table.sort(sorted, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  -- Build UI groups
  local order = 10

  for _, entry in ipairs(sorted) do
    local spellID = entry.spellID
    local rule = entry.rule
    local name = entry.name
    local enabled = rule.enabled
    local icon = entry.icon
    local color, suffix = GetRuleDisplayColor(enabled)
    name = ("|cff%s%s %s|r"):format(color, name, suffix)

    args["spell_" .. spellID] = {
      type = "group",
      name = name,
      order = order,
      icon = icon,
      inline = false,
      disabled = function() return CooldownCursorDB.spellRules.settings.disableRules end,
      args = {

        enabled = {
          type = "select",
          name = "Rule Type",
          desc = "Whitelist (show spell) or Blacklist (hide spell).",
          values = { [true] = "Whitelist", [false] = "Blacklist" },
          order = 10,
          get = function() return rule.enabled ~= false end,
          set = function(_, v)
            rule.enabled = v
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
                rule.enabled == false
          end,
          get = function()
            return rule.priority or 0
          end,
          set = function(_, v)
            rule.priority = v
            self:UpdateDisplay()
            self:NotifyOptionsChanged()
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
            return rule.useGlobalIconSize ~= false or rule.enabled == false
          end,
          get = function()
            return rule.iconSize or CooldownCursor:GetDBValue("iconSize")
          end,
          set = function(_, v)
            rule.iconSize = v
            rule.useGlobalIconSize = false -- auto-disable inheritance
            self:UpdateDisplay()
          end,
        },

        useGlobalIconSize = {
          type = "toggle",
          name = "Use Global Icon Size",
          desc = "Use the global icon size instead of a per-spell value.",
          order = 23,
          get = function()
            return rule.useGlobalIconSize ~= false
          end,
          set = function(_, v)
            rule.useGlobalIconSize = v
            if v then
              rule.iconSize = nil
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
    [0] = "Auto-Hide After",
    [1] = "On Cooldown",
    [2] = "Off Cooldown (Ready)",
  }
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
      name = "Common Settings",
      order = 0,
      args = {

        welcomeHeader = {
          type = "header",
          name = "Common Settings",
          order = 1,
        },

        description = {
          type = "description",
          name = "|cff00ff00Quick access to the most commonly used settings.|r\n" ..
              "These are the essential settings to get started!\n" ..
              "Configure these first, then explore other tabs for advanced options.",
          order = 2,
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
          name = "Show Behavior |cff345BFF(Experimental)|r",
          desc = "On Cooldown |cffFF1E34(Experimental)|r - Icons appear when a spell goes on cooldown.\n\n" ..
              "Off Cooldown |cffFF1E34(Experimental)|r - Icons appear when a spell comes off cooldown and is ready to use again.\n\n" ..
              "Auto-Hide After |cffFFFFFF(Default/Legacy)|r - Icons appear when a spell goes on cooldown and automatically disappear after a set time. See 'Auto-Hide After' option.",
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
            return CooldownCursor:GetDBValue("showBehavior") ~= 0
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
            -- Build release notes from categories
            if not CooldownCursor.releaseNotes then
              return "Check back after the next update for release notes."
            end

            local notes = CooldownCursor.releaseNotes
            local lines = {}

            -- Breaking Changes
            if notes.breakingChanges and #notes.breakingChanges > 0 then
              table.insert(lines, "|cffFF1E34 Breaking Changes:|r")
              for _, change in ipairs(notes.breakingChanges) do
                table.insert(lines, "• " .. change)
              end
              table.insert(lines, "")
            end

            -- New Features
            if notes.newFeatures and #notes.newFeatures > 0 then
              if #lines > 0 then table.insert(lines, "") end
              table.insert(lines, "|cff345BFFNew Features:|r")
              for _, feature in ipairs(notes.newFeatures) do
                table.insert(lines, "• " .. feature)
              end
              table.insert(lines, "")
            end

            -- Fixes
            if notes.fixes and #notes.fixes > 0 then
              if #lines > 0 then table.insert(lines, "") end
              table.insert(lines, "|cffFFBB4AFixes:|r")
              for _, fix in ipairs(notes.fixes) do
                table.insert(lines, "• " .. fix)
              end
            end

            -- If no categories have content
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
          order = 50,
          width = "normal",
          get = function() return CooldownCursor:GetDBValue("animation") end,
          set = function(_, v) CooldownCursor:SetDBBoolean("animation", v) end,
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

        spacer3 = {
          type = "description",
          name = " ",
          order = 75,
        },

        positionHeader = {
          type = "header",
          name = "Position",
          order = 80,
        },

        anchor = {
          type = "select",
          name = "Anchor Point",
          desc = "Where to position the icon relative to your cursor.\n\n" ..
              "TOPLEFT = Icon appears above and left of cursor",
          order = 90,
          width = "normal",
          values = AnchorValues,
          get = function() return CooldownCursor:GetDBValue("anchor") end,
          set = function(_, v) CooldownCursor:SetDBString("anchor", v) end,
        },

        anchorPadding = {
          type = "range",
          name = "Cursor Distance",
          desc = "How far from the cursor the icon appears (in pixels).",
          order = 100,
          width = "normal",
          min = 0,
          max = 100,
          step = 1,
          get = function() return CooldownCursor:GetDBValue("anchorPadding") end,
          set = function(_, v) CooldownCursor:SetDBNumber("anchorPadding", v) end,
        },

        -- TODO: Working on better offset controls
        -- offsetX = {
        --   type = "range",
        --   name = "Horizontal Offset",
        --   desc = "Additional horizontal adjustment (negative = left, positive = right).",
        --   order = 110,
        --   width = "normal",
        --   min = -500, max = 500, step = 1,
        --   get = function() return CooldownCursor:GetDBValue("offsetX") end,
        --   set = function(_, v) CooldownCursor:SetDBNumber("offsetX", v) end,
        -- },

        -- offsetY = {
        --   type = "range",
        --   name = "Vertical Offset",
        --   desc = "Additional vertical adjustment (negative = down, positive = up).",
        --   order = 120,
        --   width = "normal",
        --   min = -500, max = 500, step = 1,
        --   get = function() return CooldownCursor:GetDBValue("offsetY") end,
        --   set = function(_, v) CooldownCursor:SetDBNumber("offsetY", v) end,
        -- },

      },
    },

    -- ========================================
    -- LAYOUT TAB (Multi-Icon)
    -- ========================================
    layoutGroup = {
      type = "group",
      name = "Layout",
      order = 200,
      args = {

        header = {
          type = "header",
          name = "Multi-Icon Layout",
          order = 1,
        },

        description = {
          type = "description",
          name = "Configure how multiple cooldown icons are arranged.\n\n" ..
              "|cffaaaaaaTip: These settings only apply when Display Mode is set to VERTICAL, HORIZONTAL, or RADIUS.|r",
          order = 2,
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
            CooldownCursor:SetDBString("stackDirection", v)
          end,
        },

        maxIcons = {
          type = "range",
          name = "Maximum Icons",
          desc = "How many cooldown icons to show at once.\n\n" ..
              "When you have more cooldowns than this, the oldest/lowest priority icons are removed.",
          order = 10,
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
          order = 20,
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

        anchor = {
          type = "select",
          name = "Anchor Point",
          desc = "Where to position the icon relative to your cursor.\n\n" ..
              "TOPLEFT = Icon appears above and left of cursor",
          order = 21,
          width = "normal",
          values = AnchorValues,
          get = function() return CooldownCursor:GetDBValue("anchor") end,
          set = function(_, v) CooldownCursor:SetDBString("anchor", v) end,
        },

        spacer2 = {
          type = "description",
          name = " ",
          order = 25,
        },

        stackingHeader = {
          type = "header",
          name = "Vertical / Horizontal Spacing",
          order = 30,
        },

        stackSpacing = {
          type = "range",
          name = "Icon Spacing",
          desc = "Gap between stacked icons in pixels.\n\n" ..
              "Only applies to VERTICAL and HORIZONTAL modes.",
          order = 40,
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
          order = 45,
        },

        radiusHeader = {
          type = "header",
          name = "Radius Settings",
          order = 50,
        },

        radiusDistance = {
          type = "range",
          name = "Circle Radius",
          desc = "Distance from cursor for radius layout (in pixels).\n\n" ..
              "Only applies to RADIUS mode.",
          order = 60,
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
              "• 0° = Right\n" ..
              "• 90° = Bottom\n" ..
              "• 180° = Left\n" ..
              "• 270° = Top",
          order = 70,
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
          order = 75,
        },

        sortHeader = {
          type = "header",
          name = "Icon Sorting",
          order = 80,
        },

        sortOrder = {
          type = "select",
          name = "Sort By",
          desc = "How to order multiple cooldown icons.",
          order = 90,
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
              return "|cffaaaaaa• Sorting doesn't apply in SINGLE mode|r"
            end
            local sortOrder = CooldownCursor:GetDBValue("sortOrder")
            if sortOrder == "DURATION" then
              return "|cffaaaaaa• Shortest cooldowns appear first|r"
            elseif sortOrder == "ALPHABETICAL" then
              return "|cffaaaaaa• Sorted A-Z by spell name|r"
            elseif sortOrder == "PRIORITY" then
              return "|cffaaaaaa• Sorted by spell rule priority (set in Spell Rules tab)|r"
            elseif sortOrder == "TIME_ADDED" then
              return "|cffaaaaaa• Oldest cooldowns appear first|r"
            end
            return ""
          end,
          order = 95,
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
          name = function()
            if CooldownCursor:IsOmniCCLoaded() then
              return "|cffff8800OmniCC is active - it controls cooldown number appearance.|r"
            end
            return "Customize how the cooldown timer appears on the icon."
          end,
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
            return CooldownCursor:IsOmniCCLoaded() or
                CooldownCursor:GetDBValue("hideCooldownNumbers")
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
            return CooldownCursor:IsOmniCCLoaded() or
                CooldownCursor:GetDBValue("hideCooldownNumbers")
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
          disabled = function() return CooldownCursor:IsOmniCCLoaded() end,
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
            return CooldownCursor:IsOmniCCLoaded() or
                CooldownCursor:GetDBValue("hideCooldownNumbers")
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
            return CooldownCursor:IsOmniCCLoaded() or
                CooldownCursor:GetDBValue("hideCooldownNumbers")
          end,
          values = AnchorValues,
          get = function() return CooldownCursor:GetDBValue("cooldownTextAnchor") end,
          set = function(_, v) CooldownCursor:SetDBString("cooldownTextAnchor", v) end,
        },
      },
    },

    spellRulesGroup = {
      type = "group",
      name = "Spell Rules",
      order = 400,
      args = {

        activeRule = {
          type = "select",
          name = "Active Rule Mode",
          values = { [true] = "Whitelist", [false] = "Blacklist" },
          desc = "Choose whether spell rules are treated as a whitelist or blacklist by default.",
          order = 405,
          disabled = function() return CooldownCursorDB.spellRules.settings.disableRules end,
          get = function()
            return CooldownCursorDB.spellRules.settings.whitelist
          end,
          set = function(_, v)
            CooldownCursorDB.spellRules.settings.whitelist = v
            CooldownCursor:UpdateDisplay()
            CooldownCursor:RebuildSpellRuleOptions()
            CooldownCursor:NotifyOptionsChanged()
          end,
        },

        disableRules = {
          type = "toggle",
          name = "Disable All Spell Rules",
          desc = "If enabled, all spell rules will be ignored.",
          order = 410,
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


        header = {
          type = "header",
          name = "Spell Rule Editor",
          order = 415,
        },

        description = {
          type = "description",
          name = "Add or update a spell rule by entering its numeric Spell ID below.",
          order = 416,
        },

        spacer = {
          type = "description",
          name = " ",
          order = 420,
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
          end,
        },

        enabled = {
          type = "select",
          name = "Add to",
          desc = "Choose whether to add the spell as a whitelist or blacklist rule.",
          values = { [true] = "Whitelist", [false] = "Blacklist" },
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
          get = function()
            return CooldownCursor._newRuleIconSize or CooldownCursor:GetDBValue("iconSize")
          end,
          set = function(_, v)
            CooldownCursor._newRuleIconSize = v
          end,
        },

        add = {
          type = "execute",
          name = "Add / Update Spell Rule",
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
            CooldownCursor:AddOrUpdateSpellRule(spellID, {
              enabled  = CooldownCursor._newRuleEnabled ~= false,
              iconSize = CooldownCursor._newRuleIconSize,
              priority = CooldownCursor._newRulePriority or 0,
            })

            CooldownCursor._spellRuleStatusText =
                ("Added: %s (%d)"):format(info.name, spellID)
            CooldownCursor._spellRuleStatusColor = "55ff55" -- green

            -- Reset inputs
            CooldownCursor._newRuleSpellID = nil
            CooldownCursor._newRulePriority = nil

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
  CooldownCursor:HideIconNow()
  CooldownCursor:ApplyBreakingChangesAndSetReleaseNotes()
end

function CooldownCursor:OnOptionsClosed()
  -- Options Panel Closed
  CooldownCursor:HideIconNow()
  CooldownCursor:SetPreviewMouseMode(true)
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
