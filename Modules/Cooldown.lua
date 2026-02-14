----------------------------------------------------
-- CooldownCursor: Cooldown Module
-- Cooldown logic: spell rules, show behavior
-- strategies, combat state
----------------------------------------------------
local _, addonTable = ...

local C = addonTable.Constants
local defaults = addonTable.Defaults
local State = addonTable.State
local Internal = addonTable.Internal
local PercentToAlpha = addonTable.Util.PercentToAlpha

local SHOW_BEHAVIOR = C.SHOW_BEHAVIOR
local IsSpellKnownCached = Internal.IsSpellKnownCached

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
-- Show Behavior
----------------------------------------------------
-- AUTO_HIDE_AFTER: does nothing here, handled by ScheduleHideTimerForIcon as before.
-- ON_COOLDOWN:     removes icons whose cooldown has ended.
-- OFF_COOLDOWN:    seeds icons from rules, then hides/shows based on cooldown state.
local function ApplyShowBehavior()
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
            Internal.ShowSpellIcon(spellID, durationObject)
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
        Internal.UpdateChargeCount(iconFrame, spellID)
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
    Internal.RemoveIconForSpell(State.toRemoveBuffer[i], false)
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
        Internal.RemoveIconForSpell(State.iconsByPriority[1].spellID, CooldownCursorDB.global.fadeOutDuration == 0)
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
Internal.ApplyShowBehavior = ApplyShowBehavior
Internal.IsSecretValue = IsSecretValue

addonTable.Modules.Cooldown = Cooldown
