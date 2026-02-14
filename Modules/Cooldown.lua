----------------------------------------------------
-- CooldownCursor: Cooldown Module
-- Cooldown logic: show/hide/remove, behavior
-- strategies, spell rules, sorting, timers
----------------------------------------------------
local _, addonTable = ...

local C = addonTable.Constants
local defaults = addonTable.Defaults
local State = addonTable.State
local Internal = addonTable.Internal
local PercentToAlpha = addonTable.Util.PercentToAlpha

local SHOW_BEHAVIOR = C.SHOW_BEHAVIOR
local SORT_ORDER = C.SORT_ORDER
local STACK_DIRECTION = C.STACK_DIRECTION
local IsProcOverlayEnabled = Internal.IsProcOverlayEnabled
local IsProcOutlineEnabled = Internal.IsProcOutlineEnabled
local EnsureMasqueButton = Internal.EnsureMasqueButton
local GetIconFromPool = Internal.GetIconFromPool
local ReturnIconToPool = Internal.ReturnIconToPool
local IsSpellKnownCached = Internal.IsSpellKnownCached

local CooldownCursor = addonTable.Frame

----------------------------------------------------
-- Player Class Helper
----------------------------------------------------
local function GetPlayerClass()
  if not State.playerClass then
    local _, classToken = UnitClass("player")
    State.playerClass = classToken
  end
  return State.playerClass
end

----------------------------------------------------
-- Spell Rule Logic
----------------------------------------------------
local function GetClassRules()
  local data = CooldownCursorDB.spellRules
  if not data then return nil end

  local class = GetPlayerClass()
  if not class then return nil end

  -- Initialize class rules table if needed
  if not data.rules then
    data.rules = {}
  end
  if not data.rules[class] then
    data.rules[class] = {}
  end

  return data.rules[class]
end

local function GetSpellRule(self, spellID)
  local data = CooldownCursorDB.spellRules
  if not data then return false end
  if data.settings and data.settings.disableRules then return true end

  local classRules = GetClassRules()
  -- If no rules exist for this class, don't show any spells
  if not classRules or not next(classRules) then return false end

  local rule = classRules[spellID]
  -- If spell is not in rules, don't show it
  if not rule then return false end

  -- If spell is not known to the player (wrong spec, etc.), don't show it
  if not IsSpellKnownCached(spellID) then return false end

  -- Return whether the spell is enabled
  local settings = rule.settings or {}
  return settings.enabled ~= false, rule
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
-- Forward declarations
----------------------------------------------------
local RemoveIconForSpell
local ScheduleHideTimerForIcon
local ShowSpellIcon
local ApplyShowBehavior

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
  Internal.UpdateIconPositions()
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

  local _, rule = GetSpellRule(CooldownCursor, spellID)
  local settings = rule and rule.settings or {}
  local metadata = rule and rule.metadata or {}
  local priority = settings.priority or 0
  local procActive = State.activeProcSpells[spellID] or false

  -- If this spell is an instant cast or has no cooldown, and it's not from a proc, don't create icon.
  if not fromProc and rule and not metadata.hasCooldown and not metadata.hasCharges then
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

  CooldownCursor:UpdateSingleIcon(iconFrame, spellID)

  -- Register with Masque after size is set (lazy registration)
  EnsureMasqueButton(iconFrame)

  iconFrame.icon:SetTexture(spellInfo.iconID)

  -- Proc-only spells have no real cooldown - hide the timer overlay
  if fromProc and not metadata.hasCooldown and not metadata.hasCharges then
    iconFrame.cooldown:SetHideCountdownNumbers(true)
    iconFrame.cooldown:SetDrawSwipe(false)
  else
    iconFrame.cooldown:SetCooldownFromDurationObject(durationObject)
  end

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
      Internal.UpdateIconPositions()
      return iconFrame, existingIcon -- caller will run ApplyShowBehavior() after us
    end

    local iconFrame, iconData = SetupNewIcon(spellID, spellInfo, durationObject, fromProc)
    if iconFrame then
      SortIcons()
      Internal.UpdateIconPositions()
      EnforceMaxIcons()
      ScheduleHideTimerForIcon(iconFrame, spellID)
    end
    return iconFrame, iconData
  end
  return nil, nil
end

----------------------------------------------------
-- Show Behavior
----------------------------------------------------
-- AUTO_HIDE_AFTER: does nothing here, handled by ScheduleHideTimerForIcon as before.
-- ON_COOLDOWN:     removes icons whose cooldown has ended.
-- OFF_COOLDOWN:    seeds icons from rules, then hides/shows based on cooldown state.
ApplyShowBehavior = function()
  -- Don't interfere with preview icons
  if State.previewActive then return end

  -- Don't do anything if addon is disabled
  if CooldownCursorDB.global.enabled == false then
    return
  end

  local showBehavior = CooldownCursorDB.global.showBehavior or SHOW_BEHAVIOR.AUTO_HIDE_AFTER

  -- AUTO_HIDE_AFTER - nothing extra to do here
  if showBehavior == SHOW_BEHAVIOR.AUTO_HIDE_AFTER then
    -- If a spell can proc, only show it while the proc is active
    if CooldownCursorDB.global.showProcs ~= false then
      for spellID, iconData in pairs(State.activeIcons) do
        local iconFrame = iconData.iconFrame
        if iconFrame and State.procCapableSpells[spellID] then
          local isProcActive = iconData.procActive or iconFrame.procActive
          if isProcActive then
            iconFrame:SetAlpha(PercentToAlpha(CooldownCursorDB.global.iconAlpha or defaults.iconAlpha))
          else
            iconFrame:SetAlpha(0)
          end
        end
      end
      Internal.UpdateIconPositions()
    end
    return
  end

  -- OFF_COOLDOWN: seed icons for any rule-listed spells not yet tracked.
  if showBehavior == SHOW_BEHAVIOR.OFF_COOLDOWN then
    local classRules = GetClassRules()
    if classRules then
      for spellID, rule in pairs(classRules) do
        -- If spell has no cooldown and user doesn't want to show procs, skip it
        if not CooldownCursorDB.global.showProcs and rule.metadata.baseCooldown == 0 then
          -- continue to next spell (can't use continue in Lua, so we use a nested if)
        elseif (rule.settings and rule.settings.enabled ~= false) and not State.activeIcons[spellID] and IsSpellKnownCached(spellID) then
          local durationObject = C_Spell.GetSpellCooldownDuration(spellID)
          if durationObject then
            ShowSpellIcon(spellID, durationObject)
          end
        end
      end
    end
  end

  -- Collect spellIDs to remove (ON_COOLDOWN mode).
  local toRemoveCount = 0

  for spellID, iconData in pairs(State.activeIcons) do
    local iconFrame = iconData.iconFrame
    if iconFrame then
      local isOnCooldown = iconFrame.cooldown:IsShown()
      local isProcActive = (CooldownCursorDB.global.showProcs ~= false) and (iconData.procActive or iconFrame.procActive)

      -- Update charge count text (only for spells that have charges)
      if iconData.hasCharges then
        UpdateChargeCount(iconFrame, spellID)
      end

      -- Reset alpha in case it was modified in OFF_COOLDOWN mode
      if isOnCooldown or isProcActive then
        iconFrame:SetAlpha(PercentToAlpha(CooldownCursorDB.global.iconAlpha or defaults.iconAlpha))
      end

      if showBehavior == SHOW_BEHAVIOR.ON_COOLDOWN then
        if not isOnCooldown and not isProcActive then
          toRemoveCount = toRemoveCount + 1
          State.toRemoveBuffer[toRemoveCount] = spellID
        end
      elseif showBehavior == SHOW_BEHAVIOR.OFF_COOLDOWN then
        local procOnlySpell = State.procCapableSpells[spellID] and iconData.baseCooldown == 0
        if isProcActive then
          iconFrame:SetAlpha(PercentToAlpha(CooldownCursorDB.global.iconAlpha or defaults.iconAlpha))
        elseif procOnlySpell and (CooldownCursorDB.global.showProcs ~= false) then
          iconFrame:SetAlpha(0)
        elseif isOnCooldown then
          local chargeInfo = CooldownCursorDB.global.showCharges ~= false and C_Spell.GetSpellCharges(spellID)
          if chargeInfo and chargeInfo.currentCharges then
            iconFrame:SetAlpha(PercentToAlpha(CooldownCursorDB.global.iconAlpha or defaults.iconAlpha))
          else
            iconFrame:SetAlpha(0)
          end
        else
          iconFrame:SetAlpha(CooldownCursorDB.global.iconAlpha or defaults.iconAlpha)
        end
      end
    end
  end

  -- Now safe to remove
  for i = 1, toRemoveCount do
    RemoveIconForSpell(State.toRemoveBuffer[i], false)
    State.toRemoveBuffer[i] = nil
  end

  -- Repack icon positions after visibility changes.
  Internal.UpdateIconPositions()
end

----------------------------------------------------
-- Internal Check if secret helper
----------------------------------------------------
local function IsSecretValue(value)
  local valueType = type(value)
  if valueType == "number" then
    local success = pcall(function() return value == 0 end)
    return not success
  end
  return false
end

----------------------------------------------------
-- Cooldown Module
----------------------------------------------------
local Cooldown = {}

function Cooldown:GetSpellRule(spellID)
  return GetSpellRule(self, spellID)
end

function Cooldown:GetPlayerClass()
  return GetPlayerClass()
end

function Cooldown:HideIconNow()
  if State.previewTicker then
    State.previewTicker:Cancel()
    State.previewTicker = nil
  end
  State.previewActive = false

  if self:IsMultiIconEnabled() then
    self:HideAllIcons(true)
  else
    if #State.iconsByPriority > 0 then
      local iconFrame = State.iconsByPriority[1].iconFrame
      if iconFrame then
        RemoveIconForSpell(State.iconsByPriority[1].spellID, CooldownCursorDB.global.fadeOutDuration == 0)
      end
    end
    State.lastSpellId = nil
    State.activeSpellID = nil
  end
end

----------------------------------------------------
-- Export Internal functions
----------------------------------------------------
Internal.GetClassRules = GetClassRules
Internal.GetPlayerClass = GetPlayerClass
Internal.ShowSpellIcon = ShowSpellIcon
Internal.RemoveIconForSpell = RemoveIconForSpell
Internal.ApplyShowBehavior = ApplyShowBehavior
Internal.UpdateChargeCount = UpdateChargeCount
Internal.IsSecretValue = IsSecretValue
Internal.SortIcons = SortIcons

addonTable.Modules.Cooldown = Cooldown
