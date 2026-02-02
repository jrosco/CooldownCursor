----------------------------------------------------
-- CooldownCursor Addon
----------------------------------------------------
local addonName, addonTable = ...
local CooldownCursor = CreateFrame("Frame")
addonTable.Frame = CooldownCursor

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
    whitelist = true,
    disableRules = false,
  },
  rules = {}
}

local defaults = {
  offsetX = 0,
  offsetY = 0,
  scale = 1,
  iconSize = 48,
  iconAlpha = 100,
  iconHide = false,
  showSpellNames = false,
  hideCooldownNumbers = false,
  showCooldownSwipe = false,
  hideAfter = 30,
  animation = false,
  fadeOutDuration = 0,
  showWhen = SHOW_WHEN_STATE.COMBAT,
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
  sortOrder = SORT_ORDER.TIME_ADDED,
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

  CooldownCursorDB._version = major

  -- ========================================
  -- RELEASE NOTES (Display Only)
  -- ========================================
  -- These are just for showing users what changed
  -- No code execution, just messages

  -- breaking changes
  table.insert(breakingChanges, "Changed 'Show When' default from 'Always' to 'In Combat' (v2.0.0)")
  table.insert(breakingChanges, "Changed 'Anchor' default to 'Top Right' (v2.0.0)")
  table.insert(breakingChanges,
    "NOTE: This release is in Beta and may contain bugs. Please report any issues on the CurseForge page (v2.0.0)")
  -- new features
  table.insert(newFeatures, "Added RADIUS, HORIZONTAL and VERTICAL display modes for multi-icon stacking (v2.0.0)")
  table.insert(newFeatures, "Added HORIZONTAL and VERTICAL stack directions (v2.0.0)")
  -- fixes
  table.insert(fixes, "Fixed SPELL_UPDATE_COOLDOWN not triggering spells with CD Buff updates (v2.0.0)")
  table.insert(fixes, "Fixed Masque skin/style when showing multiple icon display (v2.0.1)")
  table.insert(fixes, "Fixed Minor bug fixes (v2.0.3)")
  table.insert(fixes, "Improved cooldown accuracy: all active icons now refresh when buffs/talents affect multiple cooldowns (v2.0.4)")

  -- Store for Options.lua to display
  self.releaseNotes = {
    breakingChanges = breakingChanges,
    newFeatures = newFeatures,
    fixes = fixes,
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
  local totalIcons = #iconsByPriority

  for i, iconData in ipairs(iconsByPriority) do
    local iconFrame = iconData.iconFrame
    if iconFrame then
      local offsetX, offsetY = GetStackOffset(i - 1, totalIcons)
      iconFrame.stackOffsetX = offsetX
      iconFrame.stackOffsetY = offsetY
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
  if not data or not data.rules then return true end
  if data.settings.disableRules then return true end

  local rules = data.rules
  if not next(rules) then return true end

  local rule = rules[spellID]

  if data.settings.whitelist then
    return rule and rule.enabled ~= false, rule
  end

  if rule and rule.enabled == false then
    return false
  end

  return true, rule
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
      return
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
  return CooldownCursorDB[key] or defaults[key]
end

function CooldownCursor:SetDBString(key, value)
  CooldownCursorDB[key] = string.format("%s", value)
  self:UpdateDisplay()
end

function CooldownCursor:SetDBNumber(key, value)
  CooldownCursorDB[key] = tonumber(value)
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

  local function ShowPreviewIcons()
    local maxIcons = self:GetDBValue("maxIcons")
    local numToShow = math.min(maxIcons, #PREVIEW_SPELL_POOL)

    for i = 1, numToShow do
      local spellData = PREVIEW_SPELL_POOL[i]
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

  if previewMouseMode then
    for _, iconData in ipairs(iconsByPriority) do
      iconData.iconFrame:SetScript("OnUpdate", UpdateCooldownIconFrame)
    end
  else
    for _, iconData in ipairs(iconsByPriority) do
      local icon = iconData.iconFrame
      icon:SetScript("OnUpdate", nil)
      icon:SetFrameStrata("HIGH")
      icon:ClearAllPoints()
      local anchor = SettingsPanel or UIParent
      icon:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
    end
  end
end

----------------------------------------------------
-- Spells Module Proxy Methods
-- Access the Spells module via addonTable.Spells
----------------------------------------------------
function CooldownCursor:GetAllSpellBookSpells(includePetSpells, includeFutureSpells, forceRefresh)
  return addonTable.Spells:GetAllSpellBookSpells(includePetSpells, includeFutureSpells, forceRefresh)
end

function CooldownCursor:GetCooldownSpells(includePetSpells)
  return addonTable.Spells:GetCooldownSpells(includePetSpells)
end

function CooldownCursor:GetSpellBookByID(includePetSpells, includeFutureSpells)
  return addonTable.Spells:GetSpellBookByID(includePetSpells, includeFutureSpells)
end

function CooldownCursor:InvalidateSpellBookCache()
  return addonTable.Spells:InvalidateSpellBookCache()
end

function CooldownCursor:GetSpellTypeName(enumValue)
  return addonTable.Spells:GetSpellTypeName(enumValue)
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
    inCombat = true
    if CooldownCursorDB.showWhen == SHOW_WHEN_STATE.NON_COMBAT then
      CooldownCursor:HideIconNow()
    end
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
    if CooldownCursorDB.showWhen == SHOW_WHEN_STATE.COMBAT then
      CooldownCursor:HideIconNow()
    end
    return
  end

  if SPELL_EVENTS[event] then
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

    -- Delay slightly to allow cooldown to register
    C_Timer.After(0.01, function()
      local durationObj = C_Spell.GetSpellCooldownDuration(spellID)

      if not durationObj then return end

      -- Filter out non-combat abilities (buffs, mounts, etc.)
      if durationObj and not durationObj:HasSecretValues()
          and durationObj:GetStartTime() == 0 then
        return
      end

      -- Check spells are known to player
      if not IsPlayerSpell(spellID) then return end

      local usable = C_Spell.IsSpellUsable(spellID)
      local inRange = C_Spell.IsSpellInRange(spellID)

      -- Check spell usability
      if inRange == false then return end
      -- if usable == false then return end

      -- Check user spell rules
      local show, rule = CooldownCursor:GetSpellRule(spellID)
      if not show then return end
      -- if IsSecretValue(spellID) and not type(spellID) == "number" then return end

      if durationObj then
        ShowSpellIcon(spellID, durationObj)
      end
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
CooldownCursor:RegisterEvent("UNIT_SPELLCAST_FAILED")
CooldownCursor:RegisterEvent("PLAYER_REGEN_DISABLED")
CooldownCursor:RegisterEvent("PLAYER_REGEN_ENABLED")
