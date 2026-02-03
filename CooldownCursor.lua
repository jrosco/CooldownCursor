----------------------------------------------------
-- CooldownCursor Addon
----------------------------------------------------
local addonName, addonTable = ...
local CooldownCursor = CreateFrame("Frame")
addonTable.Frame = CooldownCursor

----------------------------------------------------
-- Module System (Metatable Delegation)
-- Modules register in addonTable.Modules and their
-- methods become available on CooldownCursor
----------------------------------------------------
addonTable.Modules = addonTable.Modules or {}

-- Preserve the original Frame metatable
local originalMT = getmetatable(CooldownCursor)
local originalIndex = originalMT and originalMT.__index

setmetatable(CooldownCursor, {
  __index = function(self, key)
    -- First, check the original Frame methods
    if originalIndex then
      local value
      if type(originalIndex) == "function" then
        value = originalIndex(self, key)
      elseif type(originalIndex) == "table" then
        value = originalIndex[key]
      end
      if value ~= nil then
        return value
      end
    end

    -- Then search registered modules for the method
    for _, module in pairs(addonTable.Modules) do
      if module[key] then
        return module[key]
      end
    end
    return nil
  end
})

----------------------------------------------------
-- Runtime state
----------------------------------------------------
local lastSpellId = nil
local hideTimer = nil
local activeSpellID = nil
local inCombat = false
local fontsTable = {}
local previewMouseMode = true

-- Multi-icon state
local iconPool = {}
local activeIcons = {}
local iconsByPriority = {}
local nextIconID = 1

local SHOW_WHEN_STATE = {
  ALWAYS = 0,
  COMBAT = 1,
  NON_COMBAT = 2,
}

local SHOW_BEHAVIOR = {
  AUTO_HIDE_AFTER = 0, -- Show on cooldown, auto-hide after X seconds (default, original behaviour)
  ON_COOLDOWN = 1,     -- Show on cooldown, remove icon when spell comes off cooldown
  OFF_COOLDOWN = 2,    -- Show only when spell is ready (off cooldown)
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

-- Multi-icon constants
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

----------------------------------------------------
-- Live Preview state
----------------------------------------------------
local previewActive = false
local previewTicker = nil

----------------------------------------------------
-- Defaults / SavedVariables
----------------------------------------------------
local spellRules = {
  settings = {
    disableRules = false,
  },
  rules = {}
}

local defaults = {
  enabled = true,
  offsetX = 0,
  offsetY = 0,
  scale = 1,
  iconSize = 48,
  iconAlpha = 100,
  iconHide = false,
  showSpellNames = false,
  hideCooldownNumbers = false,
  showCooldownSwipe = true,
  hideAfter = 30,
  animation = false,
  fadeOutDuration = 0,
  showWhen = SHOW_WHEN_STATE.COMBAT,
  showBehavior = SHOW_BEHAVIOR.AUTO_HIDE_AFTER,
  hideWhileMounted = false,
  anchor = ANCHOR_POSITION.TOPRIGHT,
  anchorPadding = 2,
  spellTextFont = "Friz Quadrata TT",
  spellTextFontPath = DEFAULT_SYSTEM_FONTS["Friz Quadrata TT"],
  spellTextSize = 14,
  spellTextFontType = FONT_TYPES.OUTLINE,
  spellTextColor = "#FFD100",
  spellTextAnchor = "TOP",
  spellTextAlpha = 100,
  cooldownTextSize = 20,
  cooldownTextFont = "Friz Quadrata TT",
  cooldownTextFontPath = DEFAULT_SYSTEM_FONTS["Friz Quadrata TT"],
  cooldownTextFontType = FONT_TYPES.OUTLINE,
  cooldownTextColor = "#FFFFFF",
  cooldownTextAnchor = CD_TEXT_ANCHOR_POINTS.CENTER.point,
  cooldownTextAlpha = 100,
  frameStrata = FRAME_STRATA.HIGH,
  spellRules = spellRules,

  -- Multiple Icon Display Settings
  maxIcons = 10,
  stackDirection = STACK_DIRECTION.HORIZONTAL,
  stackSpacing = 4,
  sortOrder = SORT_ORDER.PRIORITY,
  stackGrowth = STACK_GROWTH.RIGHT,
  iconPoolSize = 10,
  radiusDistance = 80,
  radiusStartAngle = 0,
}

function CooldownCursor:ApplyDefaults()
  CooldownCursorDB = CooldownCursorDB or {}
  for k, v in pairs(defaults) do
    if CooldownCursorDB[k] == nil then
      CooldownCursorDB[k] = v
    end
  end
  CooldownCursor:ApplyBreakingChangesAndSetReleaseNotes()
end

function CooldownCursor:ApplyBreakingChangesAndSetReleaseNotes()
  -- Use it to:
  -- 1. Apply any breaking changes to CooldownCursorDB (migrations)
  -- 2. Set release notes for display in Options UI

  -- Initialize version if missing
  if not CooldownCursorDB._version then
    CooldownCursorDB._version = 0
  end

  -- ========================================
  -- BREAKING CHANGES (Migrations)
  -- ========================================
  -- Put code here that changes CooldownCursorDB values
  -- This runs every time, so use conditional checks

  local breakingChanges = {}
  local newFeatures = {}
  local fixes = {}
  local major = tonumber(self:GetMajorVersion())

  ----------------------------------------------------------------------------------
  -- migration from version 1 to 2 -------------------------------------------------
  if CooldownCursorDB._version < 2 then
    -- Run breaking changes here
    if CooldownCursorDB.showWhen == SHOW_WHEN_STATE.ALWAYS then
      CooldownCursorDB.showWhen = SHOW_WHEN_STATE.COMBAT
    end

    if CooldownCursorDB.anchor ~= ANCHOR_POSITION.TOPRIGHT then
      CooldownCursorDB.anchor = ANCHOR_POSITION.TOPRIGHT
    end
  end
  ----------------------------------------------------------------------------------

  ----------------------------------------------------------------------------------
  -- migration v2.1.0 - Remove whitelist setting -----------------------------------
  if not CooldownCursorDB._migratedWhitelist then
    -- Remove deprecated whitelist setting from spell rules
    if CooldownCursorDB.spellRules and CooldownCursorDB.spellRules.settings then
      CooldownCursorDB.spellRules.settings.whitelist = nil
    end
    CooldownCursorDB._migratedWhitelist = true
  end
  ----------------------------------------------------------------------------------
  ----------------------------------------------------------------------------------

  CooldownCursorDB._version = major

  -- ========================================
  -- RELEASE NOTES (Display Only)
  -- ========================================
  -- These are just for showing users what changed
  -- No code execution, just messages
  -- Notes are organized by version (newest first)

  local releaseNotesByVersion = {
    ["2.1.0"] = {
      breakingChanges = {
        "Simplified Spell Rules: Removed whitelist/blacklist mode - now uses simple enable/disable per spell",
        "Spells must now be explicitly added to rules to show cooldowns",
      },
      newFeatures = {
        "Added Show Behavior modes: On Cooldown, Off Cooldown (Ready) - Experimental",
        "Added ability to completely disable the addon from Quick Settings",
        "Added spellbook dropdown for easy spell rule management",
        "Added priority display [number] in spell list for quick visibility",
        "Added primary icon indicator in RADIUS preview mode",
        "Preview mode now uses your spell rules instead of default spells",
        "Display Mode now auto-sets anchor and growth direction defaults",
        "Spell list now sorted by priority (higher first), then alphabetically",
      },
      fixes = {
        "Fixed icon arrangement when switching between Show Behavior modes",
        "Fixed alpha state restoration when switching to On Cooldown mode",
        "Smoother priority slider with debounced updates",
      },
    },
    ["2.0.4"] = {
      breakingChanges = {},
      newFeatures = {},
      fixes = {
        "Improved cooldown accuracy: all active icons now refresh when buffs/talents affect multiple cooldowns",
      },
    },
    ["2.0.3"] = {
      breakingChanges = {},
      newFeatures = {},
      fixes = {
        "Fixed Minor bug fixes",
      },
    },
    ["2.0.1"] = {
      breakingChanges = {},
      newFeatures = {},
      fixes = {
        "Fixed Masque skin/style when showing multiple icon display",
      },
    },
    ["2.0.0"] = {
      breakingChanges = {
        "Changed 'Show When' default from 'Always' to 'In Combat'",
        "Changed 'Anchor' default to 'Top Right'",
      },
      newFeatures = {
        "Added RADIUS, HORIZONTAL and VERTICAL display modes for multi-icon stacking",
        "Added HORIZONTAL and VERTICAL stack directions",
      },
      fixes = {
        "Fixed SPELL_UPDATE_COOLDOWN not triggering spells with CD Buff updates",
      },
    },
  }

  -- Helper to parse version string into comparable numbers
  local function ParseVersion(vStr)
    local major, minor, patch = vStr:match("^(%d+)%.(%d+)%.(%d+)$")
    if major then
      return tonumber(major) * 10000 + tonumber(minor) * 100 + tonumber(patch)
    end
    return 0
  end

  -- Sort versions (newest first)
  local sortedVersions = {}
  for version in pairs(releaseNotesByVersion) do
    table.insert(sortedVersions, version)
  end
  table.sort(sortedVersions, function(a, b)
    return ParseVersion(a) > ParseVersion(b)
  end)

  -- Store for Options.lua to display
  self.releaseNotes = {
    byVersion = releaseNotesByVersion,
    sortedVersions = sortedVersions,
  }
end

----------------------------------------------------
-- Icon frame creation
----------------------------------------------------
local function CreateIconFrame(index)
  local iconFrame = CreateFrame("Frame", "CooldownCursorIcon" .. index, UIParent)
  iconFrame:EnableMouse(false)
  iconFrame:SetSize(defaults.iconSize, defaults.iconSize)
  iconFrame:SetFrameStrata(defaults.frameStrata)
  iconFrame:Hide()

  iconFrame.icon = iconFrame:CreateTexture(nil, "BACKGROUND")
  iconFrame.icon:SetAllPoints()

  iconFrame.cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
  iconFrame.cooldown:SetAllPoints(iconFrame)
  iconFrame.cooldown:SetDrawEdge(false)

  local cooldownRegion = iconFrame.cooldown:GetRegions()
  if cooldownRegion and cooldownRegion:IsObjectType("FontString") then
    iconFrame.cooldownText = cooldownRegion
  end

  iconFrame.text = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  iconFrame.text:SetPoint("BOTTOM", iconFrame, "TOP", 0, 4)
  iconFrame.text:Hide()

  iconFrame.showAnim = iconFrame:CreateAnimationGroup()
  local scaleUp = iconFrame.showAnim:CreateAnimation("Scale")
  scaleUp:SetOrder(1)
  scaleUp:SetScale(1.15, 1.15)
  scaleUp:SetDuration(0.08)
  local scaleDown = iconFrame.showAnim:CreateAnimation("Scale")
  scaleDown:SetOrder(2)
  scaleDown:SetScale(1 / 1.15, 1 / 1.15)
  scaleDown:SetDuration(0.08)

  iconFrame.fadeOut = iconFrame:CreateAnimationGroup()
  local fadeOut = iconFrame.fadeOut:CreateAnimation("Alpha")
  fadeOut:SetFromAlpha(1)
  fadeOut:SetToAlpha(0)
  fadeOut:SetDuration(defaults.fadeOutDuration or 0)
  fadeOut:SetSmoothing("OUT")

  iconFrame.fadeOut:SetScript("OnFinished", function()
    iconFrame:SetScript("OnUpdate", nil)
    iconFrame.cooldown:Clear()
    iconFrame.text:Hide()
    iconFrame:Hide()
    iconFrame.icon:SetAlpha(1)
    ReturnIconToPool(iconFrame)
  end)

  -- Primary icon indicator border (for preview mode)
  iconFrame.primaryBorder = iconFrame:CreateTexture(nil, "OVERLAY")
  iconFrame.primaryBorder:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -3, 3)
  iconFrame.primaryBorder:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 3, -3)
  iconFrame.primaryBorder:SetColorTexture(0, 1, 0, 0.8) -- Green border
  iconFrame.primaryBorder:Hide()

  -- Primary label text
  iconFrame.primaryLabel = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  iconFrame.primaryLabel:SetPoint("BOTTOM", iconFrame, "TOP", 0, 6)
  iconFrame.primaryLabel:SetText("|cff00ff00PRIMARY|r")
  iconFrame.primaryLabel:Hide()

  iconFrame.iconID = index
  iconFrame.spellID = nil
  iconFrame.addedTime = nil
  iconFrame.priority = 0
  iconFrame.hideTimer = nil
  iconFrame.stackOffsetX = 0
  iconFrame.stackOffsetY = 0

  return iconFrame
end

----------------------------------------------------
-- Icon Pool Management
----------------------------------------------------
local function InitializeIconPool()
  local poolSize = CooldownCursorDB.iconPoolSize or defaults.iconPoolSize
  for i = 1, poolSize do
    local iconFrame = CreateIconFrame(i)
    table.insert(iconPool, iconFrame)
  end
end

local function GetIconFromPool()
  if #iconPool > 0 then
    return table.remove(iconPool, 1)
  end
  local newIcon = CreateIconFrame(nextIconID)
  nextIconID = nextIconID + 1
  return newIcon
end

function ReturnIconToPool(iconFrame)
  if not iconFrame then return end

  iconFrame:Hide()
  iconFrame:SetScript("OnUpdate", nil)
  iconFrame.spellID = nil
  iconFrame.addedTime = nil
  iconFrame.priority = 0
  iconFrame.stackOffsetX = 0
  iconFrame.stackOffsetY = 0

  -- Hide primary indicator
  if iconFrame.primaryBorder then
    iconFrame.primaryBorder:Hide()
  end
  if iconFrame.primaryLabel then
    iconFrame.primaryLabel:Hide()
  end

  if iconFrame.hideTimer then
    iconFrame.hideTimer:Cancel()
    iconFrame.hideTimer = nil
  end

  table.insert(iconPool, iconFrame)
end

----------------------------------------------------
-- Masque support
----------------------------------------------------
local Masque = LibStub and LibStub("Masque", true)
local MasqueGroup = Masque and Masque:Group(addonName)

----------------------------------------------------
-- OmniCC support check
----------------------------------------------------
function CooldownCursor:IsOmniCCLoaded()
  local _, loaded = C_AddOns.IsAddOnLoaded("OmniCC")
  return loaded
end

----------------------------------------------------
--- LibSharedMedia support
----------------------------------------------------
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

----------------------------------------------------
-- Internal cursor positioning helper
----------------------------------------------------
local function FlipAnchorX(anchor)
  if anchor:find("LEFT") then
    return anchor:gsub("LEFT", "RIGHT")
  elseif anchor:find("RIGHT") then
    return anchor:gsub("RIGHT", "LEFT")
  elseif anchor == "LEFT" then
    return "RIGHT"
  elseif anchor == "RIGHT" then
    return "LEFT"
  end
  return anchor
end

local function FlipAnchorY(anchor)
  if anchor:find("TOP") then
    return anchor:gsub("TOP", "BOTTOM")
  elseif anchor:find("BOTTOM") then
    return anchor:gsub("BOTTOM", "TOP")
  elseif anchor == "TOP" then
    return "BOTTOM"
  elseif anchor == "BOTTOM" then
    return "TOP"
  end
  return anchor
end

local function AnchorOffsets(anchor, size, pad)
  local half = (size / 2)
  local d = half + (pad or 0)
  local ox, oy = 0, 0

  if anchor == "TOP" then
    oy = d
  elseif anchor == "BOTTOM" then
    oy = -d
  elseif anchor == "LEFT" then
    ox = -d
  elseif anchor == "RIGHT" then
    ox = d
  elseif anchor == "TOPLEFT" then
    ox, oy = -d, d
  elseif anchor == "TOPRIGHT" then
    ox, oy = d, d
  elseif anchor == "BOTTOMLEFT" then
    ox, oy = -d, -d
  elseif anchor == "BOTTOMRIGHT" then
    ox, oy = d, -d
  end

  return ox, oy
end

----------------------------------------------------
--- Get available fonts helper
----------------------------------------------------
local function FontNames()
  if #fontsTable > 0 then
    return fontsTable
  end

  if LSM then
    for _, fontName in pairs(LSM:List("font")) do
      local path = LSM:Fetch("font", fontName)
      if path then
        table.insert(fontsTable, fontName)
      end
    end
  else
    for name, _ in pairs(DEFAULT_SYSTEM_FONTS) do
      table.insert(fontsTable, name)
    end
  end
  return fontsTable
end

----------------------------------------------------
-- Generic table keys helper
----------------------------------------------------
local function GetTableKeys(tbl)
  local keys = {}
  for k in pairs(tbl) do
    table.insert(keys, k)
  end
  return keys
end

----------------------------------------------------
-- Generic validation helper
----------------------------------------------------
local function IsValidTableKey(tbl, key)
  if not key then return false end
  local upper = string.upper(key)
  return tbl[upper] ~= nil
end

----------------------------------------------------
--- Internal Color helper
--------------------------------------------------
local function HexToRGB(hex)
  hex = hex:gsub("#", "")
  if #hex ~= 6 then return 1, 1, 1 end
  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255
  return r, g, b
end

----------------------------------------------------
--- Internal Alpha helper
----------------------------------------------------
local function PercentToAlpha(percent)
  local alpha = tonumber(percent)
  if not alpha then return end
  if alpha > 1 then
    alpha = math.max(0, math.min(100, alpha)) / 100
  end
  return alpha
end

--------------------------------------------------
-- Internal Font Path helper
--------------------------------------------------
local function FontPath(fontName)
  local path = DEFAULT_SYSTEM_FONTS[tostring(fontName) or nil]
  if LSM and path == nil then
    path = LSM:Fetch("font", tostring(fontName))
  end
  return path
end

--------------------------------------------------
--- Internal Apply Fonts helper
--------------------------------------------------
local function ApplyFonts(obj, path, size, flags)
  if flags == "NONE" or flags == "" then
    flags = nil
  end
  local applied = obj:SetFont(path, size, flags)
  if not applied then
    obj:SetFont("Fonts\\FRIZQT__.TTF", size, nil)
  end
end

----------------------------------------------------
-- Multi-Icon Stack Offset Calculation
----------------------------------------------------
local function GetStackOffset(index, totalIcons)
  local iconSize = CooldownCursorDB.iconSize or defaults.iconSize
  local spacing = CooldownCursorDB.stackSpacing or defaults.stackSpacing
  local direction = CooldownCursorDB.stackDirection or STACK_DIRECTION.VERTICAL
  local growth = CooldownCursorDB.stackGrowth or STACK_GROWTH.DOWN

  -- For Radius layout
  if direction == STACK_DIRECTION.RADIUS then
    local radius = CooldownCursorDB.radiusDistance or defaults.radiusDistance
    local startAngle = CooldownCursorDB.radiusStartAngle or defaults.radiusStartAngle

    -- Calculate angle for this icon
    local angleStep = 360 / math.max(1, totalIcons)
    local angle = startAngle + (angleStep * index)

    -- Reverse direction for counterclockwise
    if growth == STACK_GROWTH.COUNTERCLOCKWISE then
      angle = startAngle - (angleStep * index)
    end

    -- Convert to radians
    local rad = math.rad(angle)

    -- Calculate position on circle
    local offsetX = math.cos(rad) * radius
    local offsetY = -math.sin(rad) * radius -- Negative because Y increases downward in WoW

    return offsetX, offsetY
  end

  -- For Vertical/Horizontal layouts - only apply offset if index > 0
  if index == 0 then
    return 0, 0 -- First icon at cursor position
  end

  local offset = (iconSize + spacing) * index

  if direction == STACK_DIRECTION.VERTICAL then
    if growth == STACK_GROWTH.DOWN then
      return 0, -offset
    else -- UP
      return 0, offset
    end
  else -- HORIZONTAL
    if growth == STACK_GROWTH.RIGHT then
      return offset, 0
    else -- LEFT
      return -offset, 0
    end
  end
end

----------------------------------------------------
-- Cursor tracking and positioning
----------------------------------------------------
local function UpdateCooldownIconFrame(self)
  local uiScale = UIParent:GetEffectiveScale()
  local cursorX, cursorY = GetCursorPosition()

  -- Convert cursor position to UI coordinates
  local x = cursorX / uiScale
  local y = cursorY / uiScale

  local size = CooldownCursorDB.iconSize or defaults.iconSize
  local pad = CooldownCursorDB.anchorPadding or defaults.anchorPadding
  local anchor = CooldownCursorDB.anchor or defaults.anchor

  local screenW = UIParent:GetWidth()
  local screenH = UIParent:GetHeight()
  local half = size / 2

  -- Get base offset from anchor
  local ox, oy = AnchorOffsets(anchor, size, pad)

  -- Add stack offset (this positions icons relative to each other)
  ox = ox + (self.stackOffsetX or 0)
  oy = oy + (self.stackOffsetY or 0)

  local targetX = x + ox
  local targetY = y + oy

  -- Check if it would go off-screen
  local offLeft = (targetX - half) < 0
  local offRight = (targetX + half) > screenW
  local offBottom = (targetY - half) < 0
  local offTop = (targetY + half) > screenH

  -- Flip anchor if needed
  local flipped = anchor
  if offLeft or offRight then
    flipped = FlipAnchorX(flipped)
  end
  if offBottom or offTop then
    flipped = FlipAnchorY(flipped)
  end

  -- Recalculate if flipped
  if flipped ~= anchor then
    ox, oy = AnchorOffsets(flipped, size, pad)
    ox = ox + (self.stackOffsetX or 0)
    oy = oy + (self.stackOffsetY or 0)
    targetX = x + ox
    targetY = y + oy
  end

  -- Set position directly
  self:ClearAllPoints()
  self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", targetX, targetY)
end

----------------------------------------------------
-- Apply settings and refresh active display
----------------------------------------------------
function CooldownCursor:UpdateDisplay(spellID)
  if self:IsMultiIconEnabled() then
    for _, iconData in ipairs(iconsByPriority) do
      self:UpdateSingleIcon(iconData.iconFrame, iconData.spellID)
    end
    UpdateIconPositions()
  else
    if #iconsByPriority > 0 then
      local firstIcon = iconsByPriority[1].iconFrame
      firstIcon.stackOffsetX = 0
      firstIcon.stackOffsetY = 0
      self:UpdateSingleIcon(firstIcon, iconsByPriority[1].spellID)
    end
  end
end

function CooldownCursor:UpdateSingleIcon(icon, spellID)
  if not icon then return end

  icon.icon:SetShown(not CooldownCursorDB.iconHide)
  icon.icon:SetAlpha(PercentToAlpha(CooldownCursorDB.iconAlpha or defaults.iconAlpha))

  icon:SetFrameStrata(
    FRAME_STRATA[string.upper(CooldownCursorDB.frameStrata)] or
    FRAME_STRATA[string.upper(defaults.frameStrata)]
  )

  local omniCC = self:IsOmniCCLoaded()
  if icon.cooldownText and not omniCC then
    ApplyFonts(
      icon.cooldownText,
      CooldownCursorDB.cooldownTextFontPath or defaults.cooldownTextFontPath,
      CooldownCursorDB.cooldownTextSize or defaults.cooldownTextSize,
      CooldownCursorDB.cooldownTextFontType or defaults.cooldownTextFontType
    )

    local cdr, cdg, cdb = HexToRGB(CooldownCursorDB.cooldownTextColor or defaults.cooldownTextColor)
    local cdAlpha = PercentToAlpha(CooldownCursorDB.cooldownTextAlpha or defaults.cooldownTextAlpha)
    icon.cooldownText:SetTextColor(cdr, cdg, cdb, cdAlpha)

    local anchorPoint = CD_TEXT_ANCHOR_POINTS[string.upper(CooldownCursorDB.cooldownTextAnchor)]
        or CD_TEXT_ANCHOR_POINTS[string.upper(defaults.cooldownTextAnchor)]
    icon.cooldownText:ClearAllPoints()
    icon.cooldownText:SetPoint(anchorPoint.point, icon, anchorPoint.point, anchorPoint.x, anchorPoint.y)
  end

  if icon.text then
    ApplyFonts(
      icon.text,
      CooldownCursorDB.spellTextFontPath or defaults.spellTextFontPath,
      CooldownCursorDB.spellTextSize or defaults.spellTextSize,
      CooldownCursorDB.spellTextFontType or defaults.spellTextFontType
    )

    local textr, textg, textb = HexToRGB(CooldownCursorDB.spellTextColor or defaults.spellTextColor)
    local textAlpha = PercentToAlpha(CooldownCursorDB.spellTextAlpha or defaults.spellTextAlpha)
    icon.text:SetTextColor(textr, textg, textb, textAlpha)
  end

  local anchorPoint = SPELL_TEXT_ANCHOR_POINTS[string.upper(CooldownCursorDB.spellTextAnchor)]
      or SPELL_TEXT_ANCHOR_POINTS[string.upper(defaults.spellTextAnchor)]
  icon.text:ClearAllPoints()
  icon.text:SetPoint(anchorPoint.point, icon, anchorPoint.relativeTo, anchorPoint.x, anchorPoint.y)

  local size = CooldownCursor:GetEffectiveIconSize(spellID)
  local scale = CooldownCursorDB.scale or defaults.scale
  icon:SetSize(size * scale, size * scale)
  icon.text:SetScale(scale)
  icon.cooldown:SetScale(scale)

  icon.cooldown:SetHideCountdownNumbers(CooldownCursorDB.hideCooldownNumbers)
  icon.cooldown:SetDrawSwipe(CooldownCursorDB.showCooldownSwipe)

  if icon:IsShown() and icon.spellID then
    local info = C_Spell.GetSpellInfo(icon.spellID)
    if info and CooldownCursorDB.showSpellNames and info.name then
      icon.text:SetText(info.name)
      icon.text:Show()
    else
      icon.text:Hide()
    end
  end


  -- Apply Masque skin to this icon
  if MasqueGroup then
    MasqueGroup:ReSkin()
    if CooldownCursorDB.iconHide then
      icon.icon:SetAlpha(0)
    end
  end
end

----------------------------------------------------
-- Icon Sorting Functions
----------------------------------------------------
local function SortIconsByTimeAdded(a, b)
  return a.addedTime < b.addedTime
end
local function SortIconsAlphabetically(a, b)
  return (a.spellName or ""):lower() < (b.spellName or ""):lower()
end

local function SortIconsByPriority(a, b)
  if a.priority ~= b.priority then
    return a.priority > b.priority
  end
  return SortIconsByTimeAdded(a, b)
end

local function SortIcons()
  local sortOrder = CooldownCursorDB.sortOrder or SORT_ORDER.PRIORITY

  if sortOrder == SORT_ORDER.ALPHABETICAL then
    table.sort(iconsByPriority, SortIconsAlphabetically)
  elseif sortOrder == SORT_ORDER.PRIORITY then
    table.sort(iconsByPriority, SortIconsByPriority)
  elseif sortOrder == SORT_ORDER.TIME_ADDED then
    table.sort(iconsByPriority, SortIconsByTimeAdded)
  else
    -- Fallback to PRIORITY if invalid sort order
    table.sort(iconsByPriority, SortIconsByPriority)
  end
end

----------------------------------------------------
-- Update Icon Positions
----------------------------------------------------
function UpdateIconPositions()
  local showBehavior = CooldownCursorDB.showBehavior or SHOW_BEHAVIOR.AUTO_HIDE_AFTER
  local stackDirection = CooldownCursorDB.stackDirection or defaults.stackDirection
  local isOffCooldown = (showBehavior == SHOW_BEHAVIOR.OFF_COOLDOWN)

  -- Radius + OFF_COOLDOWN: don't repack. Radius spaces icons evenly around
  -- a circle using the total count, so changing that count as icons appear/
  -- disappear causes all positions to jump. Just let them sit.
  local repackVisible = isOffCooldown and (stackDirection ~= STACK_DIRECTION.RADIUS)

  -- In OFF_COOLDOWN mode (non-Radius), only visible icons should occupy
  -- stack slots. Count visible icons first so GetStackOffset gets the right total.
  local visibleCount = 0
  if repackVisible then
    for _, iconData in ipairs(iconsByPriority) do
      if iconData.iconFrame and iconData.iconFrame:GetAlpha() > 0 then
        visibleCount = visibleCount + 1
      end
    end
  else
    visibleCount = #iconsByPriority
  end

  -- Assign positions. When repacking, invisible icons are parked at 0,0
  -- (they're invisible anyway) and visible icons get sequential slots so
  -- they pack tightly with no gaps.
  local visibleIndex = 0
  for i, iconData in ipairs(iconsByPriority) do
    local iconFrame = iconData.iconFrame
    if iconFrame then
      if repackVisible and iconFrame:GetAlpha() == 0 then
        -- Invisible - park it, no stack slot consumed
        iconFrame.stackOffsetX = 0
        iconFrame.stackOffsetY = 0
      else
        -- Visible (or not repacking) - assign the next sequential slot
        local index = repackVisible and visibleIndex or (i - 1)
        local offsetX, offsetY = GetStackOffset(index, visibleCount)
        iconFrame.stackOffsetX = offsetX
        iconFrame.stackOffsetY = offsetY
        visibleIndex = visibleIndex + 1
      end
    end
  end
end

----------------------------------------------------
-- Remove Icon for Spell
----------------------------------------------------
local function RemoveIconForSpell(spellID, immediate)
  local iconData = activeIcons[spellID]
  if not iconData then return end

  activeIcons[spellID] = nil

  for i, data in ipairs(iconsByPriority) do
    if data.spellID == spellID then
      table.remove(iconsByPriority, i)
      break
    end
  end

  local iconFrame = iconData.iconFrame

  if iconFrame.hideTimer then
    iconFrame.hideTimer:Cancel()
    iconFrame.hideTimer = nil
  end

  if immediate or CooldownCursorDB.fadeOutDuration == 0 then
    ReturnIconToPool(iconFrame)
  else
    iconFrame.fadeOut:Stop()
    local fadeOutAnim = iconFrame.fadeOut:GetAnimations()
    fadeOutAnim:SetDuration(CooldownCursorDB.fadeOutDuration or 0.3)
    iconFrame.fadeOut:Play()
  end

  SortIcons()
  UpdateIconPositions()
end

----------------------------------------------------
-- Schedule Hide Timer for Icon
----------------------------------------------------
local function ScheduleHideTimerForIcon(iconFrame, spellID)
  -- Don't schedule hide timer during preview mode
  if previewActive then
    return
  end

  -- Hide timer only applies to AUTO_HIDE_AFTER mode.
  -- ON_COOLDOWN removes icons itself when cooldown ends.
  -- OFF_COOLDOWN keeps icons alive permanently so it can show/hide them.
  local showBehavior = CooldownCursorDB.showBehavior or SHOW_BEHAVIOR.AUTO_HIDE_AFTER
  if showBehavior ~= SHOW_BEHAVIOR.AUTO_HIDE_AFTER then
    return
  end

  if iconFrame.hideTimer then
    iconFrame.hideTimer:Cancel()
  end

  local hideAfter = CooldownCursorDB.hideAfter or defaults.hideAfter

  iconFrame.hideTimer = C_Timer.NewTimer(hideAfter, function()
    RemoveIconForSpell(spellID, false)
  end)
end

----------------------------------------------------
-- Enforce Max Icons
----------------------------------------------------
local function EnforceMaxIcons()
  local maxIcons = CooldownCursorDB.maxIcons or defaults.maxIcons

  while #iconsByPriority > maxIcons do
    local toRemove = iconsByPriority[#iconsByPriority]
    RemoveIconForSpell(toRemove.spellID, true)
  end
end

----------------------------------------------------
-- Spell Rule Logic
----------------------------------------------------
function CooldownCursor:GetSpellRule(spellID)
  local data = CooldownCursorDB.spellRules
  if not data or not data.rules then return false end
  if data.settings.disableRules then return true end

  local rules = data.rules
  -- If no rules exist, don't show any spells
  if not next(rules) then return false end

  local rule = rules[spellID]
  -- If spell is not in rules, don't show it
  if not rule then return false end

  -- Return whether the spell is enabled
  return rule.enabled ~= false, rule
end

----------------------------------------------------
-- Icon Setup Helper
----------------------------------------------------
local function SetupNewIcon(spellID, spellInfo, durationObject)
  local iconFrame = GetIconFromPool()
  if not iconFrame then return nil, nil end

  local _, rule = CooldownCursor:GetSpellRule(spellID)
  local priority = (rule and rule.priority) or 0

  local iconData = {
    spellID = spellID,
    iconFrame = iconFrame,
    durationObject = durationObject,
    spellName = spellInfo.name,
    addedTime = GetTime(),
    priority = priority,
  }

  activeIcons[spellID] = iconData
  table.insert(iconsByPriority, iconData)

  iconFrame.spellID = spellID
  iconFrame.addedTime = iconData.addedTime
  iconFrame.priority = priority

  CooldownCursor:UpdateSingleIcon(iconFrame, spellID)

  iconFrame.icon:SetTexture(spellInfo.iconID)
  iconFrame.cooldown:SetCooldownFromDurationObject(durationObject)

  if CooldownCursorDB.showSpellNames and spellInfo.name then
    iconFrame.text:SetText(spellInfo.name)
    iconFrame.text:Show()
  else
    iconFrame.text:Hide()
  end

  if CooldownCursorDB.animation then
    iconFrame:SetScale(1)
    iconFrame.showAnim:Stop()
    iconFrame.showAnim:Play()
  end

  iconFrame.icon:SetAlpha(PercentToAlpha(CooldownCursorDB.iconAlpha))
  iconFrame:SetScript("OnUpdate", UpdateCooldownIconFrame)
  iconFrame:Show()

  return iconFrame, iconData
end

----------------------------------------------------
-- Show icon + cooldown
----------------------------------------------------
local function ShowSpellIcon(spellID, durationObject)
  -- Don't create icons if addon is disabled
  if CooldownCursorDB.enabled == false then
    return
  end

  local spellInfo = C_Spell.GetSpellInfo(spellID)
  if not spellInfo or not spellInfo.iconID then return end

  local stackDirection = CooldownCursorDB.stackDirection or defaults.stackDirection
  local isSingleMode = (stackDirection == STACK_DIRECTION.SINGLE)

  if isSingleMode then
    -- SINGLE mode: Always override with newest spell
    if #iconsByPriority > 0 then
      for i = #iconsByPriority, 1, -1 do
        RemoveIconForSpell(iconsByPriority[i].spellID, true)
      end
    end

    local iconFrame = SetupNewIcon(spellID, spellInfo, durationObject)
    if iconFrame then
      ScheduleHideTimerForIcon(iconFrame, spellID)
    end
    return
  end

  if CooldownCursor:IsMultiIconEnabled() then
    -- If spell already exists, update it instead of creating duplicate
    local existingIcon = activeIcons[spellID]
    if existingIcon then
      local iconFrame = existingIcon.iconFrame
      iconFrame.cooldown:SetCooldownFromDurationObject(durationObject)
      existingIcon.durationObject = durationObject
      ScheduleHideTimerForIcon(iconFrame, spellID)
      SortIcons()
      UpdateIconPositions()
      return -- caller will run ApplyShowBehavior() after us
    end

    local iconFrame = SetupNewIcon(spellID, spellInfo, durationObject)
    if iconFrame then
      SortIcons()
      UpdateIconPositions()
      EnforceMaxIcons()
      ScheduleHideTimerForIcon(iconFrame, spellID)
    end
  end
end

----------------------------------------------------
-- Show Behavior
----------------------------------------------------
-- AUTO_HIDE_AFTER: does nothing here, handled by ScheduleHideTimerForIcon as before.
-- ON_COOLDOWN:     removes icons whose cooldown has ended.
-- OFF_COOLDOWN:    seeds icons from rules, then hides/shows based on cooldown state.
local function ApplyShowBehavior()
  -- Don't do anything if addon is disabled
  if CooldownCursorDB.enabled == false then
    return
  end

  local showBehavior = CooldownCursorDB.showBehavior or SHOW_BEHAVIOR.AUTO_HIDE_AFTER

  -- AUTO_HIDE_AFTER - nothing extra to do here
  if showBehavior == SHOW_BEHAVIOR.AUTO_HIDE_AFTER then
    return
  end

  -- OFF_COOLDOWN: seed icons for any rule-listed spells not yet tracked.
  -- We need the icons to exist so their cooldown frames stay current
  -- and we can check IsShown() on each event.
  if showBehavior == SHOW_BEHAVIOR.OFF_COOLDOWN then
    local rules = CooldownCursorDB.spellRules and CooldownCursorDB.spellRules.rules
    if rules then
      for spellID, rule in pairs(rules) do
        if rule.enabled ~= false and not activeIcons[spellID] then
          local durationObject = C_Spell.GetSpellCooldownDuration(spellID)
          if durationObject then
            ShowSpellIcon(spellID, durationObject)
          end
        end
      end
    end
  end

  -- Collect spellIDs to remove (ON_COOLDOWN mode).
  -- We cannot call RemoveIconForSpell inside the loop because it
  -- modifies activeIcons while we are iterating it.
  local toRemove = {}

  for spellID, iconData in pairs(activeIcons) do
    local iconFrame = iconData.iconFrame
    if iconFrame then
      local isOnCooldown = iconFrame.cooldown:IsShown()

      -- Reset alpha in case it was modified in OFF_COOLDOWN mode
      if isOnCooldown then
        iconFrame:SetAlpha(PercentToAlpha(CooldownCursorDB.iconAlpha or defaults.iconAlpha))
      end

      if showBehavior == SHOW_BEHAVIOR.ON_COOLDOWN then
        -- ON_COOLDOWN: icon should only be visible while on cooldown.
        -- Mark for removal once the cooldown ends.
        if not isOnCooldown then
          table.insert(toRemove, spellID)
        end
      elseif showBehavior == SHOW_BEHAVIOR.OFF_COOLDOWN then
        -- OFF_COOLDOWN: icon should only be visible when ready.
        -- Use SetAlpha so the cooldown frame stays alive and keeps updating.
        if isOnCooldown then
          iconFrame:SetAlpha(0)
        else
          iconFrame:SetAlpha(CooldownCursorDB.iconAlpha or defaults.iconAlpha)
        end
      end
    end
  end

  -- Now safe to remove - we are no longer iterating activeIcons
  for _, spellID in ipairs(toRemove) do
    RemoveIconForSpell(spellID, false)
  end

  -- Repack icon positions after visibility changes.
  -- In OFF_COOLDOWN mode this collapses gaps left by invisible icons.
  UpdateIconPositions()
end

----------------------------------------------------
-- Internal hide helper
----------------------------------------------------
function CooldownCursor:HideIconNow()
  if previewTicker then
    previewTicker:Cancel()
    previewTicker = nil
  end
  previewActive = false

  if self:IsMultiIconEnabled() then
    self:HideAllIcons(true)
  else
    if #iconsByPriority > 0 then
      local iconFrame = iconsByPriority[1].iconFrame
      if iconFrame then
        RemoveIconForSpell(iconsByPriority[1].spellID, CooldownCursorDB.fadeOutDuration == 0)
      end
    end
    lastSpellId = nil
    activeSpellID = nil
  end
end

----------------------------------------------------
-- Internal Check if secret helper
----------------------------------------------------
local function IsSecretValue(value)
  local valueType = type(value)
  if valueType == "number" then
    -- try to perform an operation that would fail on a secret value
    local success = pcall(function() return value == 0 end)
    return not success
  end
  return false
end

----------------------------------------------------
-- Settings API
----------------------------------------------------

function CooldownCursor:GetVersion()
  return C_AddOns.GetAddOnMetadata(addonName, "Version")
end

function CooldownCursor:GetMajorVersion()
  local major = C_AddOns.GetAddOnMetadata(addonName, "Version")
  return major:match("^(%d+)")
end

function CooldownCursor:GetAuthor()
  return C_AddOns.GetAddOnMetadata(addonName, "Author")
end

function CooldownCursor:GetNotes()
  return C_AddOns.GetAddOnMetadata(addonName, "Notes")
end

function CooldownCursor:GetDBValue(key)
  if CooldownCursorDB[key] ~= nil then
    return CooldownCursorDB[key]
  end
  return defaults[key]
end

function CooldownCursor:SetDBString(key, value)
  CooldownCursorDB[key] = string.format("%s", value)
  self:UpdateDisplay()
end

function CooldownCursor:SetDBNumber(key, value)
  CooldownCursorDB[key] = tonumber(value)
  -- Switching showBehavior leaves stale icons (wrong alphas, wrong set of
  -- icons tracked). Clear everything and let ApplyShowBehavior re-seed.
  if key == "showBehavior" then
    self:HideAllIcons(true)
    ApplyShowBehavior()
  end
  self:UpdateDisplay()
end

function CooldownCursor:SetDBBoolean(key, value)
  CooldownCursorDB[key] = value and true or false
  self:UpdateDisplay()
end

function CooldownCursor:AddOrUpdateSpellRule(spellID, ruleData)
  spellID = tonumber(spellID)
  if not spellID then return false, "Invalid spell ID" end

  local spellName = C_Spell.GetSpellInfo(spellID)
  if not spellName then return false, "Unknown spell ID" end

  CooldownCursorDB.spellRules = CooldownCursorDB.spellRules or {}
  CooldownCursorDB.spellRules.settings = CooldownCursorDB.spellRules.settings or {}
  CooldownCursorDB.spellRules.rules = CooldownCursorDB.spellRules.rules or {}

  local rules = CooldownCursorDB.spellRules.rules
  rules[spellID] = rules[spellID] or {}

  for k, v in pairs(ruleData or {}) do
    rules[spellID][k] = v
  end

  return true, spellName
end

function CooldownCursor:RemoveSpellRule(spellID)
  if not CooldownCursorDB.spellRules or not CooldownCursorDB.spellRules.rules then return end
  CooldownCursorDB.spellRules.rules[spellID] = nil
  CooldownCursor:UpdateDisplay()
  CooldownCursor:RebuildSpellRuleOptions()
  CooldownCursor:NotifyOptionsChanged()
end

function CooldownCursor:GetEffectiveIconSize(spellID)
  local globalSize = self:GetDBValue("iconSize")
  local rulesData = CooldownCursorDB.spellRules

  if not rulesData or not rulesData.rules then return globalSize end

  local rule = rulesData.rules[spellID]
  if not rule then return globalSize end

  if rule.useGlobalIconSize ~= false then return globalSize end

  if rule.iconSize then return rule.iconSize end

  return globalSize
end

function CooldownCursor:SetFontPath(key, value)
  CooldownCursorDB[key] = value
  CooldownCursorDB[key .. "Path"] = FontPath(CooldownCursorDB[key])
  self:UpdateDisplay()
end

function CooldownCursor:GetAllFonts()
  return FontNames()
end

function CooldownCursor:GetValidFontTypes()
  return FONT_TYPES
end

function CooldownCursor:GetValidAnchorPositions()
  return GetTableKeys(ANCHOR_POSITION)
end

function CooldownCursor:GetValidFrameStratas()
  return GetTableKeys(FRAME_STRATA)
end

function CooldownCursor:GetValidSpellTextAnchorPositions()
  return GetTableKeys(SPELL_TEXT_ANCHOR_POINTS)
end

function CooldownCursor:GetValidCooldownTextAnchorPositions()
  return GetTableKeys(CD_TEXT_ANCHOR_POINTS)
end

function CooldownCursor:GetValidFontType(ftype)
  if not ftype then return false end
  local fontType = string.upper(ftype)
  if fontType == "NONE" then return true end
  return FONT_TYPES[fontType] ~= nil
end

function CooldownCursor:GetValidAnchorPosition(pos)
  return IsValidTableKey(ANCHOR_POSITION, pos)
end

function CooldownCursor:GetValidSpellTextAnchorPosition(pos)
  return IsValidTableKey(SPELL_TEXT_ANCHOR_POINTS, pos)
end

function CooldownCursor:GetValidCooldownTextAnchorPosition(pos)
  return IsValidTableKey(CD_TEXT_ANCHOR_POINTS, pos)
end

function CooldownCursor:GetValidFrameStrata(strata)
  return IsValidTableKey(FRAME_STRATA, strata)
end

function CooldownCursor:SetHideAfter(seconds)
  CooldownCursorDB.hideAfter = tonumber(seconds) or defaults.hideAfter
end

function CooldownCursor:SetFadeOutDuration(seconds)
  CooldownCursorDB.fadeOutDuration = tonumber(seconds) or defaults.fadeOutDuration
end

function CooldownCursor:GetPreviewMouseMode()
  return previewMouseMode
end

function CooldownCursor:SetPreviewMouseMode(enabled)
  previewMouseMode = enabled
  if previewActive then
    CooldownCursor:ApplyPreviewPosition()
  end
end

function CooldownCursor:ResetSettings()
  local rules = CooldownCursorDB.spellRules
  local major = tonumber(self:GetMajorVersion()) or 0
  CooldownCursor:HideIconNow()
  CooldownCursorDB = {}
  self:ApplyDefaults()
  self:UpdateDisplay()
  CooldownCursor:SetPreviewMouseMode(true)
  CooldownCursorDB.spellRules = rules
  CooldownCursorDB._version = major
end

----------------------------------------------------
-- Multi-Icon Public API
----------------------------------------------------

function CooldownCursor:HideAllIcons(immediate)
  for spellID, _ in pairs(activeIcons) do
    RemoveIconForSpell(spellID, immediate or false)
  end
  activeIcons = {}
  iconsByPriority = {}
end

function CooldownCursor:GetActiveIconCount()
  return #iconsByPriority
end

function CooldownCursor:IsMultiIconEnabled()
  local stackDirection = CooldownCursorDB.stackDirection or defaults.stackDirection
  return stackDirection ~= STACK_DIRECTION.SINGLE
end

function CooldownCursor:InitMultiIconSystem()
  InitializeIconPool()


  -- Apply Masque to all icons in the pool
  if MasqueGroup and #iconPool > 0 then
    for _, iconFrame in ipairs(iconPool) do
      MasqueGroup:AddButton(iconFrame, {
        Icon = iconFrame.icon,
        Cooldown = iconFrame.cooldown,
      })
    end
  end
end

function CooldownCursor:GetValidSortOrders()
  return {
    ALPHABETICAL = "Alphabetical",
    PRIORITY = "Priority (Spell Rules)",
    TIME_ADDED = "Time Added (Oldest First)",
  }
end

function CooldownCursor:GetValidStackDirections()
  return {
    VERTICAL = "Vertical",
    SINGLE = "Single (Override)",
    HORIZONTAL = "Horizontal",
    RADIUS = "Radius (Circle)",
  }
end

function CooldownCursor:GetValidStackGrowth()
  local direction = CooldownCursorDB.stackDirection or STACK_DIRECTION.VERTICAL

  if direction == STACK_DIRECTION.SINGLE then
    return {
      DOWN = "N/A",
    }
  elseif direction == STACK_DIRECTION.VERTICAL then
    return {
      DOWN = "Down",
      UP = "Up",
    }
  elseif direction == STACK_DIRECTION.HORIZONTAL then
    return {
      LEFT = "Left",
      RIGHT = "Right",
    }
  else -- RADIUS
    return {
      CLOCKWISE = "Clockwise",
      COUNTERCLOCKWISE = "Counter-Clockwise",
    }
  end
end

----------------------------------------------------
-- Live Preview API
----------------------------------------------------
local function StopPreview()
  previewActive = false
  if previewTicker then
    previewTicker:Cancel()
    previewTicker = nil
  end
end

local function StartPreviewLoop(showFunc, intervalSeconds)
  previewActive = true
  showFunc()
  previewTicker = C_Timer.NewTicker(intervalSeconds, function()
    if previewActive then
      showFunc()
    else
      StopPreview()
    end
  end)
end

function CooldownCursor:Preview()
  if self:IsMultiIconEnabled() then
    self:PreviewMultiIcon()
    return
  end

  if previewActive then
    StopPreview()
    self:HideIconNow()
    return
  end

  local function ShowPreviewIcon()
    local durationObj = C_DurationUtil.CreateDuration()
    durationObj:SetTimeFromStart(GetTime(), 30)
    ShowSpellIcon(116, durationObj) -- Frostbolt
    self:ApplyPreviewPosition()
  end

  StartPreviewLoop(ShowPreviewIcon, 30)
end

-- Preview spell pool with varying durations
local PREVIEW_SPELL_POOL = {
  { id = 116,   duration = 30 }, -- Frostbolt
  { id = 133,   duration = 15 }, -- Fireball
  { id = 11426, duration = 45 }, -- Ice Barrier
  { id = 2136,  duration = 20 }, -- Fire Blast
  { id = 118,   duration = 35 }, -- Polymorph
  { id = 122,   duration = 25 }, -- Frost Nova
  { id = 1459,  duration = 40 }, -- Arcane Intellect
  { id = 130,   duration = 12 }, -- Slow Fall
  { id = 475,   duration = 50 }, -- Remove Curse
  { id = 1953,  duration = 18 }, -- Blink
}

function CooldownCursor:PreviewMultiIcon()
  if previewActive then
    StopPreview()
    self:HideAllIcons(true)
    return
  end

  -- Build preview spell list from spell rules, or fall back to default pool
  local function GetPreviewSpells()
    local previewSpells = {}
    local rules = CooldownCursorDB.spellRules and CooldownCursorDB.spellRules.rules

    if rules and next(rules) then
      -- Use spells from user's spell rules
      for spellID, rule in pairs(rules) do
        if rule.enabled ~= false then
          local info = C_Spell.GetSpellInfo(spellID)
          if info then
            table.insert(previewSpells, {
              id = spellID,
              duration = 30 + (#previewSpells * 5), -- Vary durations
              name = info.name,
              priority = rule.priority or 0,
            })
          end
        end
      end
      -- Sort by priority (highest first)
      table.sort(previewSpells, function(a, b)
        return a.priority > b.priority
      end)
    end

    -- Fall back to default pool if no spell rules
    if #previewSpells == 0 then
      return PREVIEW_SPELL_POOL
    end

    return previewSpells
  end

  local function ShowPreviewIcons()
    local maxIcons = self:GetDBValue("maxIcons")
    local spellPool = GetPreviewSpells()
    local numToShow = math.min(maxIcons, #spellPool)

    for i = 1, numToShow do
      local spellData = spellPool[i]
      local durationObj = C_DurationUtil.CreateDuration()
      durationObj:SetTimeFromStart(GetTime(), spellData.duration)
      ShowSpellIcon(spellData.id, durationObj)
    end
    self:ApplyPreviewPosition()
  end

  StartPreviewLoop(ShowPreviewIcons, 50)
end

function CooldownCursor:ApplyPreviewPosition()
  if not previewActive then return end

  local isRadius = (CooldownCursorDB.stackDirection or defaults.stackDirection) == "RADIUS"

  if previewMouseMode then
    for i, iconData in ipairs(iconsByPriority) do
      iconData.iconFrame:SetScript("OnUpdate", UpdateCooldownIconFrame)

      -- Show primary indicator on first icon in RADIUS mode
      if isRadius and i == 1 then
        iconData.iconFrame.primaryBorder:Show()
        iconData.iconFrame.primaryLabel:Show()
      else
        iconData.iconFrame.primaryBorder:Hide()
        iconData.iconFrame.primaryLabel:Hide()
      end
    end
  else
    for _, iconData in ipairs(iconsByPriority) do
      local icon = iconData.iconFrame
      icon:SetScript("OnUpdate", nil)
      icon:SetFrameStrata("HIGH")
      icon:ClearAllPoints()
      local anchor = SettingsPanel or UIParent
      icon:SetPoint("LEFT", anchor, "RIGHT", 8, 0)

      -- Hide primary indicator when not following mouse
      icon.primaryBorder:Hide()
      icon.primaryLabel:Hide()
    end
  end
end

----------------------------------------------------
-- Event handler
----------------------------------------------------
CooldownCursor:SetScript("OnEvent", function(self, event, ...)
  local spellID
  local unit
  local SPELL_EVENTS = {
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_SENT = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
    SPELL_UPDATE_COOLDOWN = true,
    SPELL_UPDATE_USABLE = true,
  }
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then return end
    self:ApplyDefaults()
    self:InitMultiIconSystem()
    self:UpdateDisplay()
    self:InitAce3Options()
    self:UnregisterEvent("ADDON_LOADED")
    return
  end
  if event == "PLAYER_REGEN_DISABLED" then
    -- Entering combat
    inCombat = true
    if CooldownCursorDB.showWhen == SHOW_WHEN_STATE.NON_COMBAT then
      CooldownCursor:HideIconNow()
    end
    ApplyShowBehavior()
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    -- Exiting combat
    inCombat = false
    if CooldownCursorDB.showWhen == SHOW_WHEN_STATE.COMBAT then
      CooldownCursor:HideIconNow()
    end
    -- OFF_COOLDOWN mode: icons only make sense in combat, clear everything
    if (CooldownCursorDB.showBehavior or SHOW_BEHAVIOR.AUTO_HIDE_AFTER) == SHOW_BEHAVIOR.OFF_COOLDOWN then
      CooldownCursor:HideAllIcons(true)
    end
    return
  end

  if event == "SPELL_UPDATE_USABLE" and inCombat then
    ApplyShowBehavior()
    return
  end

  if SPELL_EVENTS[event] then
    -- Check if addon is enabled
    if CooldownCursorDB.enabled == false then
      return
    end

    if CooldownCursorDB.showWhen == SHOW_WHEN_STATE.NON_COMBAT and inCombat then
      return
    end

    if CooldownCursorDB.showWhen == SHOW_WHEN_STATE.COMBAT and not inCombat then
      return
    end

    if CooldownCursorDB.hideWhileMounted and IsMounted() then
      return
    end

    -- SPELL_UPDATE_COOLDOWN will update cooldown
    -- that buffs, talents or items may trigger new updated CD times.
    if event == "SPELL_UPDATE_COOLDOWN" then
      spellID, _, _, _ = ...
    else
      unit, _, spellID = ...
      if unit ~= "player" then return end
    end
    if not spellID then return end

    if activeIcons[spellID] then
      ApplyShowBehavior()
    end

    -- Delay slightly to allow cooldown to register
    C_Timer.After(0.01, function()
      local durationObj = C_Spell.GetSpellCooldownDuration(spellID)

      if not durationObj then return end

      -- Filter out non-cooldown abilities (buffs, mounts, etc.).
      if durationObj and not durationObj:HasSecretValues()
          and durationObj:GetStartTime() == 0 then
        return
      end

      -- Check spells are known to player
      if not IsPlayerSpell(spellID) then return end

      -- local usable = C_Spell.IsSpellUsable(spellID)
      local inRange = C_Spell.IsSpellInRange(spellID)

      -- Check spell usability
      if inRange == false and
          CooldownCursorDB.showBehavior ~= SHOW_BEHAVIOR.OFF_COOLDOWN then
        return
      end

      -- Check user spell rules
      local show, rule = CooldownCursor:GetSpellRule(spellID)
      if not show then return end

      if durationObj then
        ShowSpellIcon(spellID, durationObj)
      end

      ApplyShowBehavior()
    end)
  end
end)

----------------------------------------------------
-- Register events
----------------------------------------------------
CooldownCursor:RegisterEvent("ADDON_LOADED")
CooldownCursor:RegisterEvent("UNIT_SPELLCAST_SENT")
CooldownCursor:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
CooldownCursor:RegisterEvent("SPELL_UPDATE_COOLDOWN")
CooldownCursor:RegisterEvent("SPELL_UPDATE_USABLE")
CooldownCursor:RegisterEvent("UNIT_SPELLCAST_FAILED")
CooldownCursor:RegisterEvent("PLAYER_REGEN_DISABLED")
CooldownCursor:RegisterEvent("PLAYER_REGEN_ENABLED")
