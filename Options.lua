-- Options.lua
local addonName, addonTable = ...
local CooldownCursor = addonTable.Frame

local AceConfig = LibStub and LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub and LibStub("AceConfigDialog-3.0")

local function Get(info)
  local key = info[#info]
  return CooldownCursorDB[key]
end

local function Set(info, value)
  local key = info[#info]
  CooldownCursorDB[key] = value

  -- Route to your existing APIs where needed:
  if key == "iconSize" then
    CooldownCursor:SetIconSize(value)
  elseif key == "hideAfter" then
    CooldownCursor:SetHideAfter(value)
  elseif key == "fadeOutDuration" then
    CooldownCursor:SetFadeOutDuration(value)
  elseif key == "showSpellNames" then
    CooldownCursor:SetShowSpellNames(value)
  elseif key == "showCooldownSwipe" then
    CooldownCursor:SetShowCooldownSwipe(value)
  elseif key == "hideCooldownNumbers" then
    CooldownCursor:SetHideCooldownNumbers(value)
  elseif key == "animation" then
    CooldownCursor:SetAnimation(value)
  elseif key == "anchor" then
    CooldownCursor:SetAnchor(value)
  else
    -- Fallback: apply live updates if you have a single “refresh” call
    if CooldownCursor.UpdateDisplay then
      CooldownCursor:UpdateDisplay()
    end
  end
  CooldownCursor:UpdateDisplay()
end

local options = {
  type = "group",
  name = "CooldownCursor",
  args = {
    general = {
      type = "group",
      name = "General",
      order = 1,
      get = Get,
      set = Set,
      args = {
        iconSize = {
          type = "range",
          name = "Icon Size",
          min = 16, max = 128, step = 1,
          order = 1,
        },
        hideAfter = {
          type = "range",
          name = "Hide After (seconds)",
          min = 0.5, max = 30, step = 0.5,
          order = 2,
        },
        fadeOutDuration = {
          type = "range",
          name = "Fade Out Duration (seconds)",
          min = 0, max = 2, step = 0.05,
          order = 3,
        },
        anchor = {
          type = "select",
          name = "Anchor",
          values = {
            CENTER="CENTER",
            TOP="TOP", BOTTOM="BOTTOM", LEFT="LEFT", RIGHT="RIGHT",
            TOPLEFT="TOPLEFT", TOPRIGHT="TOPRIGHT",
            BOTTOMLEFT="BOTTOMLEFT", BOTTOMRIGHT="BOTTOMRIGHT",
          },
          order = 4,
        },
      },
    },

    toggles = {
      type = "group",
      name = "Toggles",
      order = 2,
      get = Get,
      set = Set,
      args = {
        showSpellNames = {
          type = "toggle",
          name = "Show Spell Names",
          order = 1,
        },
        showCooldownSwipe = {
          type = "toggle",
          name = "Show Cooldown Swipe",
          order = 2,
        },
        hideCooldownNumbers = {
          type = "toggle",
          name = "Hide Cooldown Numbers",
          order = 3,
        },
        animation = {
          type = "toggle",
          name = "Pop Animation",
          order = 4,
        },
      },
    },

    tools = {
      type = "group",
      name = "Tools",
      order = 3,
      args = {
        preview = {
          type = "execute",
          name = "Toggle Preview",
          order = 1,
          func = function() CooldownCursor:Preview() end,
        },
        reset = {
          type = "execute",
          name = "Reset to Defaults",
          order = 2,
          confirm = true,
          func = function() CooldownCursor:ResetSettings() end,
        },
      },
    },
  },
}

function CooldownCursor:isAceConfigLoaded()
  if not AceConfig and not AceConfigDialog then
    return false
  end
  return true
end

function CooldownCursor:InitAce3Options()
  if not self:isAceConfigLoaded() then return end
  -- Register options table
  AceConfig:RegisterOptionsTable(addonName, options)

  -- Add to Blizzard Interface Options (Ace3 creates the panel)
  AceConfigDialog:AddToBlizOptions(addonName, "CooldownCursor")
end
