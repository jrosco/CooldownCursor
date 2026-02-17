----------------------------------------------------
-- CooldownCursor: Icons Module
-- Icon lifecycle, appearance, layout, sorting,
-- charge display, timers, pool management
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
local SORT_ORDER = C.SORT_ORDER
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
local EnsureMasqueButton = Internal.EnsureMasqueButton
local GetIconFromPool = Internal.GetIconFromPool
local ReturnIconToPool = Internal.ReturnIconToPool
local IsSpellKnownCached = Internal.IsSpellKnownCached

local CooldownCursor = addonTable.Frame

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
-- Charge Count Helper
----------------------------------------------------
local function UpdateChargeCount(iconFrame, spellID)
  if not iconFrame or not iconFrame.chargeText then return end

  if CooldownCursorDB.global.showCharges == false then
    iconFrame.chargeText:Hide()
    return
  end

  local chargeInfo = C_Spell.GetSpellCharges(spellID)
  if chargeInfo then
    iconFrame.chargeText:SetText(chargeInfo.currentCharges)
    iconFrame.chargeText:Show()
  else
    iconFrame.chargeText:Hide()
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
  local sortOrder = CooldownCursorDB.global.sortOrder or SORT_ORDER.PRIORITY

  if sortOrder == SORT_ORDER.ALPHABETICAL then
    table.sort(State.iconsByPriority, SortIconsAlphabetically)
  elseif sortOrder == SORT_ORDER.PRIORITY then
    table.sort(State.iconsByPriority, SortIconsByPriority)
  elseif sortOrder == SORT_ORDER.TIME_ADDED then
    table.sort(State.iconsByPriority, SortIconsByTimeAdded)
  else
    -- Fallback to PRIORITY if invalid sort order
    table.sort(State.iconsByPriority, SortIconsByPriority)
  end
end

----------------------------------------------------
-- Update Single Icon Appearance
----------------------------------------------------
local function ApplyCooldownSwipeSettings(iconFrame)
  if not iconFrame or not iconFrame.cooldown then return end
  if State.previewActive and iconFrame.durationObject and iconFrame.cooldown.SetCooldownFromDurationObject then
    -- Re-apply current cooldown so swipe visuals refresh during preview updates
    iconFrame.cooldown:SetCooldownFromDurationObject(iconFrame.durationObject)
  end
  iconFrame.cooldown:SetHideCountdownNumbers(CooldownCursorDB.global.hideCooldownNumbers)
  iconFrame.cooldown:SetDrawSwipe(CooldownCursorDB.global.showCooldownSwipe)
  if iconFrame.cooldown.SetSwipeColor then
    local swr, swg, swb = HexToRGB(CooldownCursorDB.global.cooldownSwipeColor or defaults.cooldownSwipeColor)
    local swAlpha = PercentToAlpha(CooldownCursorDB.global.cooldownSwipeAlpha or defaults.cooldownSwipeAlpha)
    iconFrame.cooldown:SetSwipeColor(swr, swg, swb, swAlpha)
  end
end

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

  ApplyCooldownSwipeSettings(icon)

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
-- Forward declarations
----------------------------------------------------
local RemoveIconForSpell
local ScheduleHideTimerForIcon
local ShowSpellIcon

----------------------------------------------------
-- Remove Icon for Spell
----------------------------------------------------
RemoveIconForSpell = function(spellID, immediate)
  local iconData = State.activeIcons[spellID]
  if not iconData then return end

  State.activeIcons[spellID] = nil

  for i, data in ipairs(State.iconsByPriority) do
    if data.spellID == spellID then
      table.remove(State.iconsByPriority, i)
      break
    end
  end

  local iconFrame = iconData.iconFrame

  if iconFrame.hideTimer then
    iconFrame.hideTimer:Cancel()
    iconFrame.hideTimer = nil
  end

  if immediate or CooldownCursorDB.global.fadeOutDuration == 0 then
    ReturnIconToPool(iconFrame)
  else
    iconFrame.fadeOut:Stop()
    local fadeOutAnim = iconFrame.fadeOut:GetAnimations()
    fadeOutAnim:SetDuration(CooldownCursorDB.global.fadeOutDuration or 0.3)
    iconFrame.fadeOut:Play()
  end

  SortIcons()
  UpdateIconPositions()
end

----------------------------------------------------
-- Schedule Hide Timer for Icon
----------------------------------------------------
ScheduleHideTimerForIcon = function(iconFrame, spellID)
  -- Don't schedule hide timer during preview mode
  if State.previewActive then
    return
  end

  -- Hide timer only applies to AUTO_HIDE_AFTER mode.
  local showBehavior = CooldownCursorDB.global.showBehavior or SHOW_BEHAVIOR.AUTO_HIDE_AFTER
  if showBehavior ~= SHOW_BEHAVIOR.AUTO_HIDE_AFTER then
    return
  end

  if iconFrame.hideTimer then
    iconFrame.hideTimer:Cancel()
  end

  local hideAfter = CooldownCursorDB.global.hideAfter or defaults.hideAfter

  iconFrame.hideTimer = C_Timer.NewTimer(hideAfter, function()
    RemoveIconForSpell(spellID, false)
  end)
end

----------------------------------------------------
-- Enforce Max Icons
----------------------------------------------------
local function EnforceMaxIcons()
  local maxIcons = CooldownCursorDB.global.maxIcons or defaults.maxIcons

  while #State.iconsByPriority > maxIcons do
    local toRemove = State.iconsByPriority[#State.iconsByPriority]
    RemoveIconForSpell(toRemove.spellID, true)
  end
end

----------------------------------------------------
-- Icon Setup Helper
----------------------------------------------------
local function SetupNewIcon(spellID, spellInfo, durationObject, fromProc)
  local iconFrame = GetIconFromPool()
  if not iconFrame then return nil, nil end

  local _, rule = CooldownCursor:GetSpellRule(spellID)
  local settings = rule and rule.settings or {}
  local metadata = rule and rule.metadata or {}
  local priority = settings.priority or 0
  local procActive = State.activeProcSpells[spellID] or false

  -- If this spell is an instant cast or has no cooldown, and it's not from a proc, don't create icon.
  if not fromProc and rule and not metadata.hasCooldown and not metadata.hasCharges then
    ReturnIconToPool(iconFrame)
    return
  end

  local iconData = {
    spellID = spellID,
    iconFrame = iconFrame,
    durationObject = durationObject,
    spellName = spellInfo.name,
    addedTime = GetTime(),
    priority = priority,
    procActive = procActive,
    procOnly = fromProc == true,
    baseCooldown = metadata.baseCooldown or 0,
    hasCharges = metadata.hasCharges or false,
  }

  State.activeIcons[spellID] = iconData
  table.insert(State.iconsByPriority, iconData)

  iconFrame.spellID = spellID
  iconFrame.addedTime = iconData.addedTime
  iconFrame.priority = priority
  iconFrame.procActive = procActive
  iconFrame.procOnly = fromProc == true

  UpdateSingleIcon(CooldownCursor, iconFrame, spellID)

  -- Register with Masque after size is set (lazy registration)
  EnsureMasqueButton(iconFrame)

  iconFrame.icon:SetTexture(spellInfo.iconID)

  -- Proc-only spells have no real cooldown - hide the timer overlay
  if fromProc and not metadata.hasCooldown and not metadata.hasCharges then
    iconFrame.cooldown:SetHideCountdownNumbers(true)
    iconFrame.cooldown:SetDrawSwipe(false)
  else
    iconFrame.cooldown:SetCooldownFromDurationObject(durationObject)
    ApplyCooldownSwipeSettings(iconFrame)
  end
  iconFrame.durationObject = durationObject

  if CooldownCursorDB.global.showSpellNames and spellInfo.name then
    iconFrame.text:SetText(spellInfo.name)
    iconFrame.text:Show()
  else
    iconFrame.text:Hide()
  end

  if CooldownCursorDB.global.animation then
    iconFrame:SetScale(1)
    iconFrame.showAnim:Stop()
    iconFrame.showAnim:Play()
  end

  iconFrame.icon:SetAlpha(PercentToAlpha(CooldownCursorDB.global.iconAlpha))
  iconFrame:SetScript("OnUpdate", Internal.UpdateCooldownIconFrame)
  iconFrame:Show()

  -- Update charge count display
  UpdateChargeCount(iconFrame, spellID)

  if iconFrame.procOverlay then
    local showProcs = CooldownCursorDB.global.showProcs ~= false
    local showOverlay = IsProcOverlayEnabled()
    iconFrame.procOverlay:SetShown(showProcs and showOverlay and procActive)
  end
  if iconFrame.procOutline then
    local showProcs = CooldownCursorDB.global.showProcs ~= false
    local showOutline = IsProcOutlineEnabled()
    iconFrame.procOutline:SetShown(showProcs and showOutline and procActive)
  end

  -- Show preview text if in preview mode
  if State.previewActive and iconFrame.previewText then
    iconFrame.previewText:Show()
  end

  return iconFrame, iconData
end

----------------------------------------------------
-- Show icon + cooldown
----------------------------------------------------
ShowSpellIcon = function(spellID, durationObject, fromProc)
  -- Don't create icons if addon is disabled
  if CooldownCursorDB.global.enabled == false then
    return nil, nil
  end

  local spellInfo = C_Spell.GetSpellInfo(spellID)
  if not spellInfo or not spellInfo.iconID then return nil, nil end

  local stackDirection = CooldownCursorDB.global.stackDirection or defaults.stackDirection
  local isSingleMode = (stackDirection == STACK_DIRECTION.SINGLE)

  if isSingleMode then
    -- SINGLE mode: Always override with newest spell
    if #State.iconsByPriority > 0 then
      for i = #State.iconsByPriority, 1, -1 do
        RemoveIconForSpell(State.iconsByPriority[i].spellID, true)
      end
    end

    local iconFrame, iconData = SetupNewIcon(spellID, spellInfo, durationObject, fromProc)
    if iconFrame then
      ScheduleHideTimerForIcon(iconFrame, spellID)
    end
    return iconFrame, iconData
  end

  if CooldownCursor:IsMultiIconEnabled() then
    -- If spell already exists, update it instead of creating duplicate
    local existingIcon = State.activeIcons[spellID]
    if existingIcon then
      local iconFrame = existingIcon.iconFrame
      iconFrame.cooldown:SetCooldownFromDurationObject(durationObject)
      ApplyCooldownSwipeSettings(iconFrame)
      iconFrame.durationObject = durationObject
      existingIcon.durationObject = durationObject
      if not fromProc then
        existingIcon.procOnly = false
        iconFrame.procOnly = false
      end
      if State.activeProcSpells[spellID] and CooldownCursorDB.global.showProcs ~= false then
        existingIcon.procActive = true
        iconFrame.procActive = true
        if iconFrame.procOverlay then
          if IsProcOverlayEnabled() then
            iconFrame.procOverlay:Show()
          else
            iconFrame.procOverlay:Hide()
          end
        end
        if iconFrame.procOutline and IsProcOutlineEnabled() then
          iconFrame.procOutline:Show()
        end
      end
      UpdateChargeCount(iconFrame, spellID)
      ScheduleHideTimerForIcon(iconFrame, spellID)
      SortIcons()
      UpdateIconPositions()
      return iconFrame, existingIcon -- caller will run ApplyShowBehavior() after us
    end

    local iconFrame, iconData = SetupNewIcon(spellID, spellInfo, durationObject, fromProc)
    if iconFrame then
      SortIcons()
      UpdateIconPositions()
      EnforceMaxIcons()
      ScheduleHideTimerForIcon(iconFrame, spellID)
    end
    return iconFrame, iconData
  end
  return nil, nil
end

----------------------------------------------------
-- Update Display (refresh all active icons)
----------------------------------------------------
local function UpdateDisplay(self, spellID)
  Internal.RefreshCachedSettings()
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
-- Icons Module
----------------------------------------------------
local Icons = {}

function Icons:UpdateDisplay(spellID)
  UpdateDisplay(self, spellID)
end

function Icons:UpdateSingleIcon(icon, spellID)
  UpdateSingleIcon(self, icon, spellID)
end

----------------------------------------------------
-- Export Internal functions
----------------------------------------------------
Internal.UpdateSingleIcon = UpdateSingleIcon
Internal.UpdateIconPositions = UpdateIconPositions
Internal.ShowSpellIcon = ShowSpellIcon
Internal.RemoveIconForSpell = RemoveIconForSpell
Internal.UpdateChargeCount = UpdateChargeCount
Internal.SortIcons = SortIcons

addonTable.Modules.Icons = Icons
