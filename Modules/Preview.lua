----------------------------------------------------
-- CooldownCursor: Preview Module
-- Preview mode system for configuration
----------------------------------------------------
local _, addonTable = ...

local C = addonTable.Constants
local defaults = addonTable.Defaults
local State = addonTable.State
local Internal = addonTable.Internal
local POSITION_MODE = C.POSITION_MODE
local IsProcOverlayEnabled = Internal.IsProcOverlayEnabled
local IsProcOutlineEnabled = Internal.IsProcOutlineEnabled
local ShowSpellIcon = Internal.ShowSpellIcon
local GetClassRules = Internal.GetClassRules
local IsSpellKnownCached = Internal.IsSpellKnownCached
local UpdateCooldownIconFrame = Internal.UpdateCooldownIconFrame

local CooldownCursor = addonTable.Frame

----------------------------------------------------
-- Preview Mode Indicator
----------------------------------------------------
local function ShowPreviewIndicator()
  for _, iconData in ipairs(State.iconsByPriority) do
    if iconData.iconFrame and iconData.iconFrame.previewText then
      iconData.iconFrame.previewText:Show()
    end
  end
end

local function HidePreviewIndicator()
  for _, iconData in ipairs(State.iconsByPriority) do
    if iconData.iconFrame and iconData.iconFrame.previewText then
      iconData.iconFrame.previewText:Hide()
    end
  end
end

----------------------------------------------------
-- Live Preview API
----------------------------------------------------
local function StopPreview()
  State.previewActive = false
  if State.previewTicker then
    State.previewTicker:Cancel()
    State.previewTicker = nil
  end
  HidePreviewIndicator()
  Internal.UpdateAnchorVisibility()
end

local function StartPreviewLoop(showFunc, intervalSeconds)
  State.previewActive = true
  Internal.UpdateAnchorVisibility()
  ShowPreviewIndicator()
  showFunc()
  State.previewTicker = C_Timer.NewTicker(intervalSeconds, function()
    if State.previewActive then
      showFunc()
    else
      StopPreview()
    end
  end)
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

----------------------------------------------------
-- Preview Module
----------------------------------------------------
local Preview = {}

function Preview:Preview()
  if self:IsMultiIconEnabled() then
    self:PreviewMultiIcon()
    return
  end

  if State.previewActive then
    StopPreview()
    self:HideIconNow()
    return
  end

  local function ApplyPreviewProc(iconFrame, iconData)
    if not iconFrame or not iconData then return end
    if CooldownCursorDB.global.showProcs == false then return end
    iconData.procActive = true
    iconFrame.procActive = true
    if iconFrame.procOverlay then
      if IsProcOverlayEnabled() then
        iconFrame.procOverlay:Show()
      else
        iconFrame.procOverlay:Hide()
      end
    end
    if iconFrame.procOutline then
      if IsProcOutlineEnabled() then
        iconFrame.procOutline:Show()
      else
        iconFrame.procOutline:Hide()
      end
    end
  end

  local function ShowPreviewIcon()
    local durationObj = C_DurationUtil.CreateDuration()
    durationObj:SetTimeFromStart(GetTime(), 30)
    local iconFrame, iconData = ShowSpellIcon(116, durationObj) -- Frostbolt
    ApplyPreviewProc(iconFrame, iconData)
    self:ApplyPreviewPosition()
  end

  StartPreviewLoop(ShowPreviewIcon, 30)
end

function Preview:PreviewMultiIcon()
  if State.previewActive then
    StopPreview()
    self:HideAllIcons(true)
    return
  end

  -- Build preview spell list from spell rules, or fall back to default pool
  local function GetPreviewSpells()
    local previewSpells = {}

    -- Get class-specific rules
    local classRules = GetClassRules()

    if classRules and next(classRules) then
      -- Use spells from user's class-specific spell rules
      for spellID, rule in pairs(classRules) do
        local ruleSettings = rule.settings or {}
        local metadata = rule.metadata or {}
        if ruleSettings.enabled ~= false and IsSpellKnownCached(spellID) then
          local info = C_Spell.GetSpellInfo(spellID)
          if info then
            local isProc = not metadata.hasCooldown and not metadata.hasCharges
            table.insert(previewSpells, {
              id = spellID,
              duration = 30 + (#previewSpells * 5), -- Vary durations
              name = info.name,
              priority = ruleSettings.priority or 0,
              isProc = isProc,
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

  local function ApplyPreviewProc(iconFrame, iconData)
    if not iconFrame or not iconData then return end
    if CooldownCursorDB.global.showProcs == false then return end
    iconData.procActive = true
    iconFrame.procActive = true
    if iconFrame.procOverlay then
      if IsProcOverlayEnabled() then
        iconFrame.procOverlay:Show()
      else
        iconFrame.procOverlay:Hide()
      end
    end
    if iconFrame.procOutline then
      if IsProcOutlineEnabled() then
        iconFrame.procOutline:Show()
      else
        iconFrame.procOutline:Hide()
      end
    end
  end

  local function ShowPreviewIcons()
    local maxIcons = self:GetDBValue("maxIcons")
    local spellPool = GetPreviewSpells()
    local numToShow = math.min(maxIcons, #spellPool)

    for i = 1, numToShow do
      local spellData = spellPool[i]
      local durationObj = C_DurationUtil.CreateDuration()
      durationObj:SetTimeFromStart(GetTime(), spellData.duration)
      local iconFrame, iconData = ShowSpellIcon(spellData.id, durationObj, spellData.isProc)
      if spellData.isProc then
        ApplyPreviewProc(iconFrame, iconData)
      end
    end
    self:ApplyPreviewPosition()
  end

  StartPreviewLoop(ShowPreviewIcons, 50)
end

function Preview:ApplyPreviewPosition()
  if not State.previewActive then return end

  local positionMode = CooldownCursorDB.global.positionMode or defaults.positionMode
  local isRadius = (CooldownCursorDB.global.stackDirection or defaults.stackDirection) == "RADIUS"

  if positionMode == POSITION_MODE.SCREEN then
    for _, iconData in ipairs(State.iconsByPriority) do
      iconData.iconFrame:SetScript("OnUpdate", nil)
    end
    Internal.ApplyScreenAnchors()
    return
  end

  if State.previewMouseMode then
    for i, iconData in ipairs(State.iconsByPriority) do
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
    for _, iconData in ipairs(State.iconsByPriority) do
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

addonTable.Modules.Preview = Preview
