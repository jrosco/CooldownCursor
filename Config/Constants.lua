----------------------------------------------------
-- CooldownCursor: Constants & Enums
----------------------------------------------------
local _, addonTable = ...

----------------------------------------------------
-- Enums
----------------------------------------------------
local SHOW_WHEN_STATE = {
  ALWAYS = 0,
  COMBAT = 1,
  NON_COMBAT = 2,
}

local SHOW_BEHAVIOR = {
  ON_COOLDOWN = 0,     -- Show on cooldown, remove icon when spell comes off cooldown
  OFF_COOLDOWN = 1,    -- Show only when spell is ready (off cooldown)
  AUTO_HIDE_AFTER = 2, -- Show on cooldown, auto-hide after X seconds (default, original behaviour)
}

local ANCHOR_POSITION = {
  CENTER = "CENTER",
  TOP = "TOP",
  BOTTOM = "BOTTOM",
  LEFT = "LEFT",
  RIGHT = "RIGHT",
  TOPLEFT = "TOPLEFT",
  TOPRIGHT = "TOPRIGHT",
  BOTTOMLEFT = "BOTTOMLEFT",
  BOTTOMRIGHT = "BOTTOMRIGHT",
}

local FRAME_STRATA = {
  BACKGROUND = "BACKGROUND",
  LOW = "LOW",
  MEDIUM = "MEDIUM",
  HIGH = "HIGH",
  DIALOG = "DIALOG",
  TOOLTIP = "TOOLTIP",
}

local CD_TEXT_ANCHOR_POINTS = {
  TOP = { point = "TOP", x = 0, y = -4 },
  BOTTOM = { point = "BOTTOM", x = 0, y = 4 },
  LEFT = { point = "LEFT", x = 4, y = 0 },
  RIGHT = { point = "RIGHT", x = -4, y = 0 },
  CENTER = { point = "CENTER", x = 0, y = 0 },
  TOPLEFT = { point = "TOPLEFT", x = 4, y = -4 },
  TOPRIGHT = { point = "TOPRIGHT", x = -4, y = -4 },
  BOTTOMLEFT = { point = "BOTTOMLEFT", x = 4, y = 4 },
  BOTTOMRIGHT = { point = "BOTTOMRIGHT", x = -4, y = 4 },
}

local SPELL_TEXT_ANCHOR_POINTS = {
  BOTTOM = { point = "TOP", relativeTo = "BOTTOM", x = 0, y = -4 },
  TOP = { point = "BOTTOM", relativeTo = "TOP", x = 0, y = 4 },
}

local CHARGE_TEXT_ANCHOR_POINTS = {
  TOP = { point = "TOP", x = 0, y = -2 },
  BOTTOM = { point = "BOTTOM", x = 0, y = 2 },
  LEFT = { point = "LEFT", x = 2, y = 0 },
  RIGHT = { point = "RIGHT", x = -2, y = 0 },
  CENTER = { point = "CENTER", x = 0, y = 0 },
  TOPLEFT = { point = "TOPLEFT", x = 2, y = -2 },
  TOPRIGHT = { point = "TOPRIGHT", x = -2, y = -2 },
  BOTTOMLEFT = { point = "BOTTOMLEFT", x = 2, y = 2 },
  BOTTOMRIGHT = { point = "BOTTOMRIGHT", x = -2, y = 2 },
}

local FONT_TYPES = {
  NONE = nil,
  OUTLINE = "OUTLINE",
  THICKOUTLINE = "THICKOUTLINE",
  MONOCHROME = "MONOCHROME",
  MONOCHROMEOUTLINE = "MONOCHROMEOUTLINE",
  MONOCHROMETHICKOUTLINE = "MONOCHROMETHICKOUTLINE",
}

local DEFAULT_SYSTEM_FONTS = {
  ["Default"] = "Fonts\\FRIZQT__.TTF",
  ["2002 Bold"] = "Fonts\\2002B.TTF",
  ["2002"] = "Fonts\\2002.TTF",
  ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
  ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
  ["Skurri"] = "Fonts\\skurri.ttf",
  ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
  ["Nimrod MT"] = "Fonts\\NIM_____.ttf",
}

local SORT_ORDER = {
  ALPHABETICAL = "ALPHABETICAL",
  PRIORITY = "PRIORITY",
  TIME_ADDED = "TIME_ADDED",
}

local STACK_DIRECTION = {
  SINGLE = "SINGLE",
  VERTICAL = "VERTICAL",
  HORIZONTAL = "HORIZONTAL",
  RADIUS = "RADIUS",
}

local STACK_GROWTH = {
  DOWN = "DOWN",
  UP = "UP",
  LEFT = "LEFT",
  RIGHT = "RIGHT",
  CLOCKWISE = "CLOCKWISE",
  COUNTERCLOCKWISE = "COUNTERCLOCKWISE",
}

-----------------------------------------------------
--- Proc Overlay/Outline Atlas Settings
-----------------------------------------------------
local PROC_OVERLAY_ATLAS_SETTINGS = {
  ["ArtifactsFX-SpinningGlowys"] = { name = "Spinning Glowys", scale = 1.5 },
  ["AftLevelup-WhiteStarBurst"] = { name = "Star Burst", scale = 2 },
  ["ArtifactsFX-Whirls"] = { name = "Whirls", scale = 1.4 },
}

local PROC_OUTLINE_ATLAS_SETTINGS = {
  ["combattimeline-fx-queued"] = { name = "Square Neon Glow", scale = 1.6 },
  ["combattimeline-fx-deadlyglow-base"] = { name = "Square Glow", scale = 1.6 },
  ["talents-node-choiceflyout-square-ghost"] = { name = "Square Dotted", scale = 1.2 },
}

----------------------------------------------------
-- Utility Functions
----------------------------------------------------
local function HexToRGB(hex)
  hex = hex:gsub("#", "")
  if #hex ~= 6 then return 1, 1, 1 end
  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255
  return r, g, b
end

local function PercentToAlpha(percent)
  local alpha = tonumber(percent)
  if not alpha then return 1 end
  if alpha > 1 then
    alpha = math.max(0, math.min(100, alpha)) / 100
  end
  return alpha
end

local function GetTableKeys(tbl)
  local keys = {}
  for k in pairs(tbl) do
    table.insert(keys, k)
  end
  return keys
end

local function IsValidTableKey(tbl, key)
  if not key then return false end
  local upper = string.upper(key)
  return tbl[upper] ~= nil
end

----------------------------------------------------
-- Export to addonTable
----------------------------------------------------
addonTable.Constants = {
  SHOW_WHEN_STATE = SHOW_WHEN_STATE,
  SHOW_BEHAVIOR = SHOW_BEHAVIOR,
  ANCHOR_POSITION = ANCHOR_POSITION,
  FRAME_STRATA = FRAME_STRATA,
  CD_TEXT_ANCHOR_POINTS = CD_TEXT_ANCHOR_POINTS,
  SPELL_TEXT_ANCHOR_POINTS = SPELL_TEXT_ANCHOR_POINTS,
  CHARGE_TEXT_ANCHOR_POINTS = CHARGE_TEXT_ANCHOR_POINTS,
  FONT_TYPES = FONT_TYPES,
  DEFAULT_SYSTEM_FONTS = DEFAULT_SYSTEM_FONTS,
  SORT_ORDER = SORT_ORDER,
  STACK_DIRECTION = STACK_DIRECTION,
  STACK_GROWTH = STACK_GROWTH,
  PROC_OVERLAY_ATLAS_SETTINGS = PROC_OVERLAY_ATLAS_SETTINGS,
  PROC_OUTLINE_ATLAS_SETTINGS = PROC_OUTLINE_ATLAS_SETTINGS,
}

addonTable.Util = {
  HexToRGB = HexToRGB,
  PercentToAlpha = PercentToAlpha,
  GetTableKeys = GetTableKeys,
  IsValidTableKey = IsValidTableKey,
}

----------------------------------------------------
-- Module methods (accessible via CooldownCursor:Method())
----------------------------------------------------
local Constants = {}

function Constants:GetProcOverlayAtlasSettings()
  return PROC_OVERLAY_ATLAS_SETTINGS
end

function Constants:GetProcOutlineAtlasSettings()
  return PROC_OUTLINE_ATLAS_SETTINGS
end

addonTable.Modules = addonTable.Modules or {}
addonTable.Modules.Constants = Constants
