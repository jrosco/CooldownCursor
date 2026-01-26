-- Options.lua
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
      min = 0.5, max = 30, step = 0.1,
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
      desc = "Reset all settings to defaults.",
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
          name = "Size",
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
    maintainerGroup = {
      type = "group",
      name = "Maintainer",
      order = 400,
      args = {
        aboutHeader = {
          type = "header",
          name = "Addon Information",
          order = 410,
        },

        version = {
          type = "description",
          name = function()
            return "Version: |cffffffff" .. CooldownCursor:GetVersion() .. "|r"
          end,
          order = 420,
        },

        author = {
          type = "description",
          name = function()
            return "Author: |cffffffff" .. CooldownCursor:GetAuthor() .. "|r"
          end,
          order = 430,
        },

        notes = {
          type = "description",
          name = function()
            local notes = CooldownCursor:GetNotes()
            if notes == "" then return "" end
            return "Notes: |cffffffff" .. notes .. "|r"
          end,
          order = 440,
        },

        spacer = { type = "description", name = " ", order = 4 },

        website = {
          type = "input",
          name = "Website",
          order = 450,
          width = "full",
          get = function() return "https://www.curseforge.com/wow/addons/cooldowncursor" end,
          set = function() end, -- read-only
        },

        issues = {
          type = "input",
          name = "Issues / GitHub",
          desc = "Where to report bugs / feature requests.",
          order = 460,
          width = "full",
          get = function() return "https://github.com/jrosco/CooldownCursor/issues" end,
          set = function() end, -- read-only
        },

        slash = {
          type = "description",
          name = "Slash commands: |cffffffff/cdc|r or |cffffffff/cdcursor|r",
          order = 470,
        },
      },
    },
  },
}

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

end
