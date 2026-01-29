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
          min = 16, max = 128, step = 1,
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

local function HexColorGet(key, fallbackHex)
  -- AceConfig color expects r,g,b,a in 0..1
  local hex = (CooldownCursor:GetDBValue(key) or fallbackHex or "ffffff"):gsub("#", "")
  if #hex ~= 6 then hex = "ffffff" end
  local r = tonumber(hex:sub(1,2), 16) / 255
  local g = tonumber(hex:sub(3,4), 16) / 255
  local b = tonumber(hex:sub(5,6), 16) / 255
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
    header = {
      type = "header",
      name = "Options",
      order = 0,
    },

    showWhen = {
      type = "select",
      name = "Show",
      desc = "When the icon should appear.",
      order = 10,
      values = ShowWhenValues(),
      get = function() return CooldownCursor:GetDBValue("showWhen") end,
      set = function(_, v) CooldownCursor:SetDBNumber("showWhen", v) end,
    },

    preview = {
      type = "execute",
      name = "Preview",
      desc = "Toggle the preview cooldown",
      order = 20,
      func = function() CooldownCursor:Preview() end,
    },

    previewMouse = {
      type = "toggle",
      name = "Preview on Cursor",
      desc = "Enable the preview cooldown at the cursor.",
      order = 30,
      get = function() return not not CooldownCursor:GetPreviewMouseMode() end,
      set = function(_, v) CooldownCursor:SetPreviewMouseMode(v) end,
    },

    spacer1 = { type = "description", name = " ", order = 5 },

    hideAfter = {
      type = "range",
      name = "Hide After (seconds)",
      desc = "How long the icon stays visible before hiding.",
      order = 40,
      min = 1, max = 120, step = 1,
      get = function() return CooldownCursor:GetDBValue("hideAfter") end,
      set = function(_, v) CooldownCursor:SetHideAfter(v) end,
    },

    fadeOutDuration = {
      type = "range",
      name = "Fade Out (seconds)",
      desc = "How long the icon takes to fade out when hiding.",
      order = 50,
      min = 0, max = 3, step = 0.05,
      get = function() return CooldownCursor:GetDBValue("fadeOutDuration") end,
      set = function(_, v) CooldownCursor:SetFadeOutDuration(v) end,
    },

    scale = {
      type = "range",
      name = "Scale",
      desc = "Scale of the icon and text (0.5 - 5).",
      order = 60,
      min = 0.5, max = 5, step = 0.01,
      get = function() return CooldownCursor:GetDBValue("scale") end,
      set = function(_, v) CooldownCursor:SetDBNumber("scale", v) end,
    },

    animation = {
      type = "toggle",
      name = "Animation",
      desc = "Enable the icon pop animation.",
      order = 70,
      get = function() return not not CooldownCursor:GetDBValue("animation") end,
      set = function(_, v) CooldownCursor:SetDBBoolean("animation", v) end,
    },

    hideWhileMounted = {
      type = "toggle",
      name = "Hide While Mounted",
      desc = "Hide the icon while mounted.",
      order = 80,
      get = function() return not not CooldownCursor:GetDBValue("hideWhileMounted") end,
      set = function(_, v) CooldownCursor:SetDBBoolean("hideWhileMounted", v) end,
    },

    reset = {
      type = "execute",
      name = "Reset",
      desc = "Reset all settings to defaults, except spell rules.",
      order = 90,
      confirm = true,
      func = function() CooldownCursor:ResetSettings() end,
    },

    iconGroup = {
      type = "group",
      name = "Icon",
      order = 100,
      args = {
        iconHide = {
          type = "toggle",
          name = "Hide Icon Texture",
          desc = "Hide the spell icon texture (text/number may still show).",
          order = 1,
          get = function() return not not CooldownCursor:GetDBValue("iconHide") end,
          set = function(_, v) CooldownCursor:SetDBBoolean("iconHide", v) end,
        },

        showCooldownSwipe = {
          type = "toggle",
          name = "Swipe",
          desc = "Show the cooldown swipe overlay.",
          order = 110,
          get = function() return not not CooldownCursor:GetDBValue("showCooldownSwipe") end,
          set = function(_, v) CooldownCursor:SetDBBoolean("showCooldownSwipe", v) end,
        },

        iconSize = {
          type = "range",
          name = "Global Size",
          desc = "Icon size in pixels.",
          order = 120,
          min = 16, max = 128, step = 1,
          get = function() return CooldownCursor:GetDBValue("iconSize") end,
          set = function(_, v) CooldownCursor:SetDBNumber("iconSize", v) end,
        },

        iconAlpha = {
          type = "range",
          name = "Alpha (%)",
          desc = "Icon transparency (0-100).",
          order = 130,
          min = 0, max = 100, step = 1,
          get = function() return CooldownCursor:GetDBValue("iconAlpha") end,
          set = function(_, v) CooldownCursor:SetDBNumber("iconAlpha", v) end,
        },

        strata = {
          type = "select",
          name = "Frame Strata",
          desc = "Orders the icon on the screen, affecting how it overlaps on the UI.",
          order = 140,
          values = FrameStrataValues,
          get = function() return CooldownCursor:GetDBValue("frameStrata") end,
          set = function(_, v) CooldownCursor:SetDBString("frameStrata", v) end,
        },

        anchor = {
          type = "select",
          name = "Anchor",
          desc = "Where to place the icon relative to the cursor.",
          order = 150,
          values = AnchorValues,
          get = function() return CooldownCursor:GetDBValue("anchor") end,
          set = function(_, v) CooldownCursor:SetDBString("anchor", v) end,
        },
      },
    },

    textGroup = {
      type = "group",
      name = "Spell Text",
      order = 200,
      args = {
        showSpellNames = {
          type = "toggle",
          name = "Show Spell Name",
          order = 1,
          get = function() return not not CooldownCursor:GetDBValue("showSpellNames") end,
          set = function(_, v) CooldownCursor:SetDBBoolean("showSpellNames", v) end,
        },

        spellTextAlpha = {
          type = "range",
          name = "Alpha (%)",
          order = 210,
          min = 0, max = 100, step = 1,
          get = function() return CooldownCursor:GetDBValue("spellTextAlpha") end,
          set = function(_, v) CooldownCursor:SetDBNumber("spellTextAlpha", v) end,
        },

        spellTextAnchor = {
          type = "select",
          name = "Anchor",
          desc = "Where the spell name appears relative to the icon.",
          order = 220,
          values = { TOP = "TOP", BOTTOM = "BOTTOM" },
          get = function() return (CooldownCursor:GetDBValue("spellTextAnchor") or "TOP") end,
          set = function(_, v) CooldownCursor:SetDBString("spellTextAnchor", v) end,
        },

        spellTextSize = {
          type = "range",
          name = "Size",
          order = 230,
          min = 6, max = 80, step = 1,
          get = function() return tonumber(CooldownCursor:GetDBValue("spellTextSize")) or 14 end,
          set = function(_, v) CooldownCursor:SetDBNumber("spellTextSize", v) end,
        },

        spellTextFont = {
          type = "select",
          name = "Font",
          order = 240,
          values = FontValues,
          get = function() return (CooldownCursor:GetDBValue("spellTextFont")) end,
          set = function(_, v) CooldownCursor:SetFontPath("spellTextFont", v) end,
        },

        spellTextFontType = {
          type = "select",
          name = "Font Type",
          order = 250,
          values = fontTypeValues,
          get = function() return (CooldownCursor:GetDBValue("spellTextFontType")) end,
          set = function(_, v)
            -- if CooldownCursor.GetValidFontType and not CooldownCursor:GetValidFontType(v) then return end
            CooldownCursor:SetDBString("spellTextFontType", v)
          end,
        },

        spellTextColor = {
          type = "color",
          name = "Color",
          hasAlpha = false,
          order = 260,
          get = function() return HexColorGet("spellTextColor", "ffd100") end,
          set = function(_, r, g, b, a) HexColorSet("spellTextColor", r, g, b, a) end,
        },
      },
    },

    numberGroup = {
      type = "group",
      name = "Cooldown Numbers",
      order = 300,
      args = {
        omniCCWarn = {
          type = "description",
          name = function()
            if CooldownCursor:IsOmniCCLoaded() then
              return "|cffff5555OmniCC detected: these settings will be ignored to avoid conflicts.|r"
            end
            return nil
          end,
          order = 0,
        },

        hideCooldownNumbers = {
          type = "toggle",
          name = "Hide Blizzard Cooldown Numbers",
          desc = "If enabled, the Blizzard cooldown number text is hidden.",
          order = 310,
          disabled = function() return CooldownCursor:IsOmniCCLoaded() end,
          get = function() return not not CooldownCursor:GetDBValue("hideCooldownNumbers") end,
          set = function(_, v) CooldownCursor:SetDBBoolean("hideCooldownNumbers", v) end,
        },

        cooldownTextAlpha = {
          type = "range",
          name = "Alpha (%)",
          order = 320,
          min = 0, max = 100, step = 1,
          disabled = function() return CooldownCursor:IsOmniCCLoaded() end,
          get = function() return (CooldownCursor:GetDBValue("cooldownTextAlpha")) end,
          set = function(_, v) CooldownCursor:SetDBNumber("cooldownTextAlpha", v) end,
        },

        cooldownTextAnchor = {
          type = "select",
          name = "Anchor",
          order = 330,
          disabled = function() return CooldownCursor:IsOmniCCLoaded() end,
          values = {
            TOP="TOP", BOTTOM="BOTTOM", LEFT="LEFT", RIGHT="RIGHT",
            CENTER="CENTER", TOPLEFT="TOPLEFT", TOPRIGHT="TOPRIGHT",
            BOTTOMLEFT="BOTTOMLEFT", BOTTOMRIGHT="BOTTOMRIGHT",
          },
          get = function() return (CooldownCursor:GetDBValue("cooldownTextAnchor") or "TOP") end,
          set = function(_, v) CooldownCursor:SetDBString("cooldownTextAnchor", v) end,
        },

        cooldownTextSize = {
          type = "range",
          name = "Size",
          order = 340,
          min = 6, max = 80, step = 1,
          disabled = function() return CooldownCursor:IsOmniCCLoaded() end,
          get = function() return tonumber(CooldownCursor:GetDBValue("cooldownTextSize")) or 16 end,
          set = function(_, v) CooldownCursor:SetDBNumber("cooldownTextSize", v) end,
        },

        cooldownTextFont = {
          type = "select",
          name = "Font",
          order = 350,
          disabled = function() return CooldownCursor:IsOmniCCLoaded() end,
          values = FontValues,
          get = function() return (CooldownCursor:GetDBValue("cooldownTextFont")) end,
          set = function(_, v) CooldownCursor:SetFontPath("cooldownTextFont", v) end,
        },

        cooldownTextFontType = {
          type = "select",
          name = "Font Type",
          order = 360,
          disabled = function() return CooldownCursor:IsOmniCCLoaded() end,
          values = fontTypeValues,
          get = function() return (CooldownCursor:GetDBValue("cooldownTextFontType") or "OUTLINE") end,
          set = function(_, v)
            -- if CooldownCursor.GetValidFontType and not CooldownCursor:GetValidFontType(v) then return end
            CooldownCursor:SetDBString("cooldownTextFontType", v)
          end,
        },

        cooldownTextColor = {
          type = "color",
          name = "Color",
          hasAlpha = false,
          order = 370,
          disabled = function() return CooldownCursor:IsOmniCCLoaded() end,
          get = function() return HexColorGet("cooldownTextColor", "ffffff") end,
          set = function(_, r, g, b, a) HexColorSet("cooldownTextColor", r, g, b, a) end,
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

        iconSize = {
          type = "range",
          name = "Icon Size",
          order = 424,
          min = 16, max = 128, step = 1,
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
            })

            CooldownCursor._spellRuleStatusText =
              ("Added: %s (%d)"):format(info.name, spellID)
            CooldownCursor._spellRuleStatusColor = "55ff55" -- green

            -- Reset inputs
            CooldownCursor._newRuleSpellID = nil

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

    maintainerGroup = {
      type = "group",
      name = "Maintainer",
      order = 500,
      args = {
        aboutHeader = {
          type = "header",
          name = "Addon Information",
          order = 510,
        },

        version = {
          type = "description",
          name = function()
            return "Version: |cffffffff" .. CooldownCursor:GetVersion() .. "|r"
          end,
          order = 520,
        },

        author = {
          type = "description",
          name = function()
            return "Author: |cffffffff" .. CooldownCursor:GetAuthor() .. "|r"
          end,
          order = 530,
        },

        notes = {
          type = "description",
          name = function()
            local notes = CooldownCursor:GetNotes()
            if notes == "" then return "" end
            return "Notes: |cffffffff" .. notes .. "|r"
          end,
          order = 540,
        },

        spacer = { type = "description", name = " ", order = 4 },

        website = {
          type = "input",
          name = "Website",
          order = 550,
          width = "full",
          get = function() return "https://www.curseforge.com/wow/addons/cooldowncursor" end,
          set = function() end, -- read-only
        },

        issues = {
          type = "input",
          name = "Issues / GitHub",
          desc = "Where to report bugs / feature requests.",
          order = 560,
          width = "full",
          get = function() return "https://github.com/jrosco/CooldownCursor/issues" end,
          set = function() end, -- read-only
        },

        slash = {
          type = "description",
          name = "Slash commands: |cffffffff/cdc|r or |cffffffff/cdcursor|r",
          order = 570,
        },
      },
    },
  },
}

-- Expose options table
CooldownCursor.options = options

function CooldownCursor:OnOptionsOpened()
  -- Options Panel Opened
  return
end

function CooldownCursor:OnOptionsClosed()
  -- Options Panel Closed
  CooldownCursor:HideIconNow()
  CooldownCursor:SetPreviewMouseMode(false)
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
