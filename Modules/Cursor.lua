----------------------------------------------------
-- CooldownCursor: Cursor Module
-- Cursor tracking, positioning, anchoring,
-- UI panel tracking, icon visual updates
----------------------------------------------------
local _, addonTable = ...

local C = addonTable.Constants
local defaults = addonTable.Defaults
local State = addonTable.State
local Internal = addonTable.Internal
local HexToRGB = addonTable.Util.HexToRGB
local PercentToAlpha = addonTable.Util.PercentToAlpha
local ApplyFonts = Internal.ApplyFonts

local SHOW_BEHAVIOR = C.SHOW_BEHAVIOR
local STACK_DIRECTION = C.STACK_DIRECTION
local STACK_GROWTH = C.STACK_GROWTH
local FRAME_STRATA = C.FRAME_STRATA
local CD_TEXT_ANCHOR_POINTS = C.CD_TEXT_ANCHOR_POINTS
local SPELL_TEXT_ANCHOR_POINTS = C.SPELL_TEXT_ANCHOR_POINTS
local CHARGE_TEXT_ANCHOR_POINTS = C.CHARGE_TEXT_ANCHOR_POINTS
local PROC_OVERLAY_ATLAS_SETTINGS = C.PROC_OVERLAY_ATLAS_SETTINGS
local PROC_OUTLINE_ATLAS_SETTINGS = C.PROC_OUTLINE_ATLAS_SETTINGS
local IsProcOverlayEnabled = Internal.IsProcOverlayEnabled
local IsProcOutlineEnabled = Internal.IsProcOutlineEnabled
local MasqueGroup = Internal.MasqueGroup

local CooldownCursor = addonTable.Frame

----------------------------------------------------
-- Anchor Positioning
----------------------------------------------------
local FLIP_X = {
  LEFT = "RIGHT", RIGHT = "LEFT",
  TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT",
  BOTTOMLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "BOTTOMLEFT",
  TOP = "TOP", BOTTOM = "BOTTOM", CENTER = "CENTER",
}
local FLIP_Y = {
  TOP = "BOTTOM", BOTTOM = "TOP",
  TOPLEFT = "BOTTOMLEFT", TOPRIGHT = "BOTTOMRIGHT",
  BOTTOMLEFT = "TOPLEFT", BOTTOMRIGHT = "TOPRIGHT",
  LEFT = "LEFT", RIGHT = "RIGHT", CENTER = "CENTER",
}

local function FlipAnchorX(anchor)
  return FLIP_X[anchor] or anchor
end

local function FlipAnchorY(anchor)
  return FLIP_Y[anchor] or anchor
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

local function RefreshCachedSettings()
  State.cachedIconSize = CooldownCursorDB.global.iconSize or defaults.iconSize
  State.cachedAnchorPadding = CooldownCursorDB.global.anchorPadding or defaults.anchorPadding
  State.cachedAnchor = CooldownCursorDB.global.anchor or defaults.anchor
  State.cachedIconHide = CooldownCursorDB.global.iconHide or false
  State.cachedAnchorOX, State.cachedAnchorOY = AnchorOffsets(State.cachedAnchor, State.cachedIconSize, State.cachedAnchorPadding)
  State.cachedHalfSize = State.cachedIconSize / 2
end

----------------------------------------------------
-- Multi-Icon Stack Offset Calculation
----------------------------------------------------
local function GetRadiusOffset(index, totalIcons, growth)
  local radius = CooldownCursorDB.global.radiusDistance or defaults.radiusDistance
  local startAngle = CooldownCursorDB.global.radiusStartAngle or defaults.radiusStartAngle

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

local function GetLinearOffset(cumulativeOffset, direction, growth)
  if direction == STACK_DIRECTION.VERTICAL then
    if growth == STACK_GROWTH.DOWN then
      return 0, -cumulativeOffset
    else -- UP
      return 0, cumulativeOffset
    end
  else -- HORIZONTAL
    if growth == STACK_GROWTH.RIGHT then
      return cumulativeOffset, 0
    else -- LEFT
      return -cumulativeOffset, 0
    end
  end
end

----------------------------------------------------
-- UI Panel tracking
----------------------------------------------------
local openPanels = {}
local cachedPanelOpen = false

local function RefreshPanelCache()
  cachedPanelOpen = (next(openPanels) ~= nil)
    or (GameMenuFrame and GameMenuFrame:IsShown())
    or (SettingsPanel and SettingsPanel:IsShown())
    or false
end

hooksecurefunc("ShowUIPanel", function(frame)
  if frame then
    openPanels[frame] = true
    RefreshPanelCache()
  end
end)

hooksecurefunc("HideUIPanel", function(frame)
  if frame then
    openPanels[frame] = nil
    RefreshPanelCache()
  end
end)

-- GameMenuFrame and SettingsPanel bypass ShowUIPanel/HideUIPanel,
-- so we hook their Show/Hide to keep the cache accurate.
local function HookPanelVisibility(panel)
  if not panel then return end
  panel:HookScript("OnShow", RefreshPanelCache)
  panel:HookScript("OnHide", RefreshPanelCache)
end
HookPanelVisibility(GameMenuFrame)
HookPanelVisibility(SettingsPanel)

local function IsAnyPanelOpen()
  return cachedPanelOpen
end

----------------------------------------------------
-- Cursor tracking and positioning (OnUpdate)
----------------------------------------------------
local function UpdateCooldownIconFrame(self)
  if IsAnyPanelOpen() and not State.previewActive then
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -100, -100) -- Move off-screen
    return
  end

  local cursorX, cursorY = GetCursorPosition()

  -- Convert cursor position to UI coordinates (using cached metrics)
  local x = cursorX / State.cachedUIScale
  local y = cursorY / State.cachedUIScale
  local half = State.cachedHalfSize

  -- Use pre-computed base offset from anchor
  local ox, oy = State.cachedAnchorOX, State.cachedAnchorOY

  -- Add stack offset (this positions icons relative to each other)
  ox = ox + (self.stackOffsetX or 0)
  oy = oy + (self.stackOffsetY or 0)

  local targetX = x + ox
  local targetY = y + oy

  -- Check if it would go off-screen
  local offLeft = (targetX - half) < 0
  local offRight = (targetX + half) > State.cachedScreenW
  local offBottom = (targetY - half) < 0
  local offTop = (targetY + half) > State.cachedScreenH

  -- Flip anchor if needed
  local flipped = State.cachedAnchor
  if offLeft or offRight then
    flipped = FlipAnchorX(flipped)
  end
  if offBottom or offTop then
    flipped = FlipAnchorY(flipped)
  end

  -- Recalculate if flipped
  if flipped ~= State.cachedAnchor then
    ox, oy = AnchorOffsets(flipped, State.cachedIconSize, State.cachedAnchorPadding)
    ox = ox + (self.stackOffsetX or 0)
    oy = oy + (self.stackOffsetY or 0)
    targetX = x + ox
    targetY = y + oy
  end

  -- Only update position if it actually changed (avoids redundant layout invalidation)
  if self._lastX ~= targetX or self._lastY ~= targetY then
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", targetX, targetY)
    self._lastX = targetX
    self._lastY = targetY
  end
end

----------------------------------------------------
-- Update Single Icon Appearance
----------------------------------------------------
local function UpdateSingleIcon(self, icon, spellID)
  if not icon then return end

  icon.icon:SetShown(not CooldownCursorDB.global.iconHide)
  icon.icon:SetAlpha(PercentToAlpha(CooldownCursorDB.global.iconAlpha or defaults.iconAlpha))

  icon:SetFrameStrata(
    FRAME_STRATA[string.upper(CooldownCursorDB.global.frameStrata)] or
    FRAME_STRATA[string.upper(defaults.frameStrata)]
  )

  if icon.cooldownText then
    ApplyFonts(
      icon.cooldownText,
      CooldownCursorDB.global.cooldownTextFontPath or defaults.cooldownTextFontPath,
      CooldownCursorDB.global.cooldownTextSize or defaults.cooldownTextSize,
      CooldownCursorDB.global.cooldownTextFontType or defaults.cooldownTextFontType
    )

    local cdr, cdg, cdb = HexToRGB(CooldownCursorDB.global.cooldownTextColor or defaults.cooldownTextColor)
    local cdAlpha = PercentToAlpha(CooldownCursorDB.global.cooldownTextAlpha or defaults.cooldownTextAlpha)
    icon.cooldownText:SetTextColor(cdr, cdg, cdb, cdAlpha)

    local anchorPoint = CD_TEXT_ANCHOR_POINTS[string.upper(CooldownCursorDB.global.cooldownTextAnchor)]
        or CD_TEXT_ANCHOR_POINTS[string.upper(defaults.cooldownTextAnchor)]
    icon.cooldownText:ClearAllPoints()
    icon.cooldownText:SetPoint(anchorPoint.point, icon, anchorPoint.point, anchorPoint.x, anchorPoint.y)
  end

  if icon.text then
    ApplyFonts(
      icon.text,
      CooldownCursorDB.global.spellTextFontPath or defaults.spellTextFontPath,
      CooldownCursorDB.global.spellTextSize or defaults.spellTextSize,
      CooldownCursorDB.global.spellTextFontType or defaults.spellTextFontType
    )

    local textr, textg, textb = HexToRGB(CooldownCursorDB.global.spellTextColor or defaults.spellTextColor)
    local textAlpha = PercentToAlpha(CooldownCursorDB.global.spellTextAlpha or defaults.spellTextAlpha)
    icon.text:SetTextColor(textr, textg, textb, textAlpha)
  end

  if icon.chargeText then
    ApplyFonts(
      icon.chargeText,
      CooldownCursorDB.global.chargeTextFontPath or defaults.chargeTextFontPath,
      CooldownCursorDB.global.chargeTextSize or defaults.chargeTextSize,
      CooldownCursorDB.global.chargeTextFontType or defaults.chargeTextFontType
    )

    local chr, chg, chb = HexToRGB(CooldownCursorDB.global.chargeTextColor or defaults.chargeTextColor)
    local chAlpha = PercentToAlpha(CooldownCursorDB.global.chargeTextAlpha or defaults.chargeTextAlpha)
    icon.chargeText:SetTextColor(chr, chg, chb, chAlpha)

    local anchorPoint = CHARGE_TEXT_ANCHOR_POINTS
    [string.upper(CooldownCursorDB.global.chargeTextAnchor or defaults.chargeTextAnchor)]
    icon.chargeText:ClearAllPoints()
    icon.chargeText:SetPoint(anchorPoint.point, icon, anchorPoint.point, anchorPoint.x, anchorPoint.y)
  end

  if icon.procOverlay then
    local showProcs = CooldownCursorDB.global.showProcs ~= false
    local showOverlay = IsProcOverlayEnabled()
    local overlayAtlas = CooldownCursorDB.global.procOverlayAtlas or defaults.procOverlayAtlas
    if overlayAtlas and overlayAtlas ~= "" then
      icon.procOverlay:SetAtlas(overlayAtlas, true)
    end
    local orr, org, orb = HexToRGB(CooldownCursorDB.global.procOverlayColor or defaults.procOverlayColor)
    icon.procOverlay:SetVertexColor(orr, org, orb, 1)
    icon.procOverlay:SetShown(showProcs and showOverlay and (icon.procActive == true))
  end
  if icon.procOutline then
    local showProcs = CooldownCursorDB.global.showProcs ~= false
    local showOutline = IsProcOutlineEnabled()
    local outlineAtlas = CooldownCursorDB.global.procOutlineAtlas or defaults.procOutlineAtlas
    if outlineAtlas and outlineAtlas ~= "" then
      icon.procOutline:SetAtlas(outlineAtlas, true)
    end
    local otr, otg, otb = HexToRGB(CooldownCursorDB.global.procOutlineColor or defaults.procOutlineColor)
    icon.procOutline:SetVertexColor(otr, otg, otb, 1)
    icon.procOutline:SetShown(showProcs and showOutline and (icon.procActive == true))
  end

  local anchorPoint = SPELL_TEXT_ANCHOR_POINTS[string.upper(CooldownCursorDB.global.spellTextAnchor)]
      or SPELL_TEXT_ANCHOR_POINTS[string.upper(defaults.spellTextAnchor)]
  icon.text:ClearAllPoints()
  icon.text:SetPoint(anchorPoint.point, icon, anchorPoint.relativeTo, anchorPoint.x, anchorPoint.y)

  local size = CooldownCursor:GetEffectiveIconSize(spellID)
  local scale = CooldownCursorDB.global.scale or defaults.scale
  icon:SetSize(size * scale, size * scale)
  icon.text:SetScale(scale)
  icon.cooldown:SetScale(scale)
  if icon.procOverlay then
    local overlayAtlas = CooldownCursorDB.global.procOverlayAtlas or defaults.procOverlayAtlas
    local overlayScale = 1.6
    if overlayAtlas and PROC_OVERLAY_ATLAS_SETTINGS[overlayAtlas] then
      overlayScale = PROC_OVERLAY_ATLAS_SETTINGS[overlayAtlas].scale or overlayScale
    end
    icon.procOverlay:SetSize(size * scale * overlayScale, size * scale * overlayScale)
  end
  if icon.procOutline then
    local outlineAtlas = CooldownCursorDB.global.procOutlineAtlas or defaults.procOutlineAtlas
    local outlineScale = 1.9
    if outlineAtlas and PROC_OUTLINE_ATLAS_SETTINGS[outlineAtlas] then
      outlineScale = PROC_OUTLINE_ATLAS_SETTINGS[outlineAtlas].scale or outlineScale
    end
    icon.procOutline:SetSize(size * scale * outlineScale, size * scale * outlineScale)
  end

  icon.cooldown:SetHideCountdownNumbers(CooldownCursorDB.global.hideCooldownNumbers)
  icon.cooldown:SetDrawSwipe(CooldownCursorDB.global.showCooldownSwipe)

  if icon:IsShown() and icon.spellID then
    local info = C_Spell.GetSpellInfo(icon.spellID)
    if info and CooldownCursorDB.global.showSpellNames and info.name then
      icon.text:SetText(info.name)
      icon.text:Show()
    else
      icon.text:Hide()
    end
  end

  -- Apply Masque iconHide override (ReSkin is called once in UpdateDisplay)
  if MasqueGroup and CooldownCursorDB.global.iconHide then
    icon.icon:SetAlpha(0)
  end
end

----------------------------------------------------
-- Update Icon Positions
----------------------------------------------------
local function UpdateIconPositions()
  local showBehavior = CooldownCursorDB.global.showBehavior or SHOW_BEHAVIOR.AUTO_HIDE_AFTER
  local stackDirection = CooldownCursorDB.global.stackDirection or defaults.stackDirection
  local isOffCooldown = (showBehavior == SHOW_BEHAVIOR.OFF_COOLDOWN)

  -- Radius + OFF_COOLDOWN: don't repack. Radius spaces icons evenly around
  -- a circle using the total count, so changing that count as icons appear/
  -- disappear causes all positions to jump. Just let them sit.
  local repackVisible = isOffCooldown and (stackDirection ~= STACK_DIRECTION.RADIUS)

  -- In OFF_COOLDOWN mode (non-Radius), only visible icons should occupy
  -- stack slots. Count visible icons first so GetLinearOffset gets the right total.
  local visibleCount = 0
  if repackVisible then
    for _, iconData in ipairs(State.iconsByPriority) do
      if iconData.iconFrame and iconData.iconFrame:GetAlpha() > 0 then
        visibleCount = visibleCount + 1
      end
    end
  else
    visibleCount = #State.iconsByPriority
  end

  -- Assign positions. When repacking, invisible icons are parked at 0,0
  -- (they're invisible anyway) and visible icons get sequential slots so
  -- they pack tightly with no gaps.
  local scale = CooldownCursorDB.global.scale or defaults.scale
  local spacing = CooldownCursorDB.global.stackSpacing or defaults.stackSpacing
  local direction = CooldownCursorDB.global.stackDirection or STACK_DIRECTION.VERTICAL
  local growth = CooldownCursorDB.global.stackGrowth or STACK_GROWTH.DOWN
  local isRadius = (direction == STACK_DIRECTION.RADIUS)
  local visibleIndex = 0
  local cumulativeOffset = 0
  for i, iconData in ipairs(State.iconsByPriority) do
    local iconFrame = iconData.iconFrame
    if iconFrame then
      if repackVisible and iconFrame:GetAlpha() == 0 then
        -- Invisible - park it, no stack slot consumed
        iconFrame.stackOffsetX = 0
        iconFrame.stackOffsetY = 0
      else
        local index = repackVisible and visibleIndex or (i - 1)
        local offsetX, offsetY
        if isRadius then
          offsetX, offsetY = GetRadiusOffset(index, visibleCount, growth)
        elseif index == 0 then
          offsetX, offsetY = 0, 0
        else
          offsetX, offsetY = GetLinearOffset(cumulativeOffset, direction, growth)
        end
        iconFrame.stackOffsetX = offsetX
        iconFrame.stackOffsetY = offsetY
        -- Accumulate offset using this icon's actual size for the next icon
        local iconSize = CooldownCursor:GetEffectiveIconSize(iconData.spellID)
        cumulativeOffset = cumulativeOffset + (iconSize * scale) + spacing
        visibleIndex = visibleIndex + 1
      end
    end
  end
end

----------------------------------------------------
-- Update Display (refresh all active icons)
----------------------------------------------------
local function UpdateDisplay(self, spellID)
  RefreshCachedSettings()
  if self:IsMultiIconEnabled() then
    for _, iconData in ipairs(State.iconsByPriority) do
      UpdateSingleIcon(self, iconData.iconFrame, iconData.spellID)
    end
    UpdateIconPositions()
  else
    if #State.iconsByPriority > 0 then
      local firstIcon = State.iconsByPriority[1].iconFrame
      firstIcon.stackOffsetX = 0
      firstIcon.stackOffsetY = 0
      UpdateSingleIcon(self, firstIcon, State.iconsByPriority[1].spellID)
    end
  end

  -- Apply Masque skin once after all icons are updated
  if MasqueGroup then
    MasqueGroup:ReSkin()
  end
end

----------------------------------------------------
-- Cursor Module
----------------------------------------------------
local Cursor = {}

function Cursor:UpdateDisplay(spellID)
  UpdateDisplay(self, spellID)
end

function Cursor:UpdateSingleIcon(icon, spellID)
  UpdateSingleIcon(self, icon, spellID)
end

----------------------------------------------------
-- Export Internal functions
----------------------------------------------------
Internal.UpdateCooldownIconFrame = UpdateCooldownIconFrame
Internal.UpdateSingleIcon = UpdateSingleIcon
Internal.UpdateIconPositions = UpdateIconPositions
Internal.RefreshCachedSettings = RefreshCachedSettings

addonTable.Modules.Cursor = Cursor
