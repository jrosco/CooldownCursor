----------------------------------------------------
-- CooldownCursor: Init
-- Event handler and event registration
----------------------------------------------------
local addonName, addonTable = ...

local C = addonTable.Constants
local State = addonTable.State
local Internal = addonTable.Internal
local ShowSpellIcon = Internal.ShowSpellIcon
local ApplyShowBehavior = Internal.ApplyShowBehavior
local RemoveIconForSpell = Internal.RemoveIconForSpell
local UpdateChargeCount = Internal.UpdateChargeCount
local RefreshScreenMetrics = Internal.RefreshScreenMetrics
local ApplyPositionMode = Internal.ApplyPositionMode
local IsProcOverlayEnabled = Internal.IsProcOverlayEnabled
local IsProcOutlineEnabled = Internal.IsProcOutlineEnabled

local SHOW_WHEN_STATE = C.SHOW_WHEN_STATE
local SHOW_BEHAVIOR = C.SHOW_BEHAVIOR

local CooldownCursor = addonTable.Frame

----------------------------------------------------
-- Show-when state helper
----------------------------------------------------
-- Returns true if the current combat state does NOT match showWhen,
-- meaning events should be suppressed. Handles combat transitions
-- by hiding icons when leaving the allowed state.
local function CheckShowWhenState(combatTransition)
  local showWhen = CooldownCursorDB.global.showWhen
  if not showWhen or showWhen == SHOW_WHEN_STATE.ALWAYS then
    return false
  end

  if showWhen == SHOW_WHEN_STATE.COMBAT then
    if not State.inCombat then
      -- Leaving combat with COMBAT mode: hide icons
      if combatTransition then
        CooldownCursor:HideIconNow()
      end
      return true
    end
  elseif showWhen == SHOW_WHEN_STATE.NON_COMBAT then
    if State.inCombat then
      -- Entering combat with NON_COMBAT mode: hide icons
      if combatTransition then
        CooldownCursor:HideIconNow()
      end
      return true
    end
  end

  return false
end

----------------------------------------------------
-- Mounted state helper
----------------------------------------------------
local wasMounted = false

local function CheckMountedState()
  if not CooldownCursorDB.global.hideWhileMounted then return false end

  local mounted = IsMounted()
  if mounted then
    if not wasMounted then
      wasMounted = true
      CooldownCursor:HideAllIcons(true)
    end
    return true -- signal: skip further processing
  end

  if wasMounted then
    wasMounted = false
    if not CheckShowWhenState() then
      ApplyShowBehavior()
    end
  end
  return false
end

----------------------------------------------------
-- Guard helper
-- Returns true if the event should be suppressed
-- due to combat/show-when state or mounted state.
----------------------------------------------------
local function IsGuarded()
  return CheckShowWhenState() or CheckMountedState()
end

----------------------------------------------------
-- Spell event debounce + processing
----------------------------------------------------
local pendingSpellTimers = {}

local function ProcessSpellEvent(spellID, hasCharges)
  if pendingSpellTimers[spellID] then return end
  pendingSpellTimers[spellID] = true

  -- Delay slightly to allow cooldown to register
  C_Timer.After(0.01, function()
    pendingSpellTimers[spellID] = nil
    local durationObj = C_Spell.GetSpellCooldownDuration(spellID)
    if not durationObj then return end

    local inRange = C_Spell.IsSpellInRange(spellID)
    if inRange == false and
      CooldownCursorDB.global.showBehavior ~= SHOW_BEHAVIOR.OFF_COOLDOWN then
      return
    end

    if hasCharges then
      local iconFrame = ShowSpellIcon(spellID, durationObj)
      UpdateChargeCount(iconFrame, spellID)
    else
      ShowSpellIcon(spellID, durationObj)
    end

    ApplyShowBehavior()
  end)
end

----------------------------------------------------
-- Shared handler for spell cast / cooldown events
-- Covers: UNIT_SPELLCAST_SENT, UNIT_SPELLCAST_SUCCEEDED,
--         UNIT_SPELLCAST_FAILED, SPELL_UPDATE_COOLDOWN
----------------------------------------------------
local SPELL_CAST_EVENTS = {
  UNIT_SPELLCAST_FAILED    = true,
  UNIT_SPELLCAST_SENT      = true,
  UNIT_SPELLCAST_SUCCEEDED = true,
  SPELL_UPDATE_COOLDOWN    = true,
}

local function HandleSpellCastEvent(self, event, ...)
  if CooldownCursorDB.global.enabled == false then return end
  if IsGuarded() then return end

  local spellID
  if event == "SPELL_UPDATE_COOLDOWN" then
    -- provides spellID, baseSpellID, category, startRecoveryCategory
    spellID = ...
  elseif event == "UNIT_SPELLCAST_SENT" then
    local unit, _, _, sid = ...
    if unit ~= "player" then return end
    spellID = sid
  else
    local unit, _, sid = ...
    if unit ~= "player" then return end
    spellID = sid
  end

  if not spellID then
    ApplyShowBehavior()
    return
  end

  local show, rule = self:GetSpellRule(spellID)
  if not show then return end

  local hasCharges = rule and rule.metadata and rule.metadata.hasCharges or false
  ProcessSpellEvent(spellID, hasCharges)
end

----------------------------------------------------
-- Event handler dispatch table
----------------------------------------------------
local eventHandlers = {}

eventHandlers.ADDON_LOADED = function(self, name)
  if name ~= addonName then return end
  self:ApplyDefaults()
  RefreshScreenMetrics()
  self:InitMultiIconSystem()
  self:UpdateDisplay()
  if ApplyPositionMode then ApplyPositionMode() end
  self:InitAce3Options()
  self:UnregisterEvent("ADDON_LOADED")
  State.inCombat = InCombatLockdown()
end

eventHandlers.PLAYER_SPECIALIZATION_CHANGED = function(self, unit)
  if unit ~= "player" then return end
  wipe(State.knownSpellCache)
  self:InvalidateSpellBookCache()
  self:HideAllIcons(true)
  ApplyShowBehavior()
end

eventHandlers.PLAYER_MOUNT_DISPLAY_CHANGED = function(_)
  CheckMountedState()
end

eventHandlers.PLAYER_REGEN_DISABLED = function(_)
  State.inCombat = true
  if not CheckShowWhenState(true) then
    ApplyShowBehavior()
  end
end

eventHandlers.PLAYER_REGEN_ENABLED = function(_)
  State.inCombat = false
  if not CheckShowWhenState(true) then
    ApplyShowBehavior()
  end
end

eventHandlers.UI_SCALE_CHANGED = function(_)
  RefreshScreenMetrics()
end
eventHandlers.DISPLAY_SIZE_CHANGED = eventHandlers.UI_SCALE_CHANGED

eventHandlers.SPELL_UPDATE_USABLE = function(_)
  if IsGuarded() then return end
  ApplyShowBehavior()
end

eventHandlers.PLAYER_ENTERING_WORLD = function(_)
  if IsGuarded() then return end
  ApplyShowBehavior()
end

eventHandlers.SPELL_UPDATE_CHARGES = function(_)
  if IsGuarded() then return end
  if CooldownCursorDB.global.showCharges == false then return end
  for spellID, iconData in pairs(State.activeIcons) do
    if iconData and iconData.iconFrame and iconData.hasCharges then
      UpdateChargeCount(iconData.iconFrame, spellID)
    end
  end
  ApplyShowBehavior()
end

eventHandlers.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = function(self, spellID)
  if not spellID then return end
  if CooldownCursorDB.global.showProcs == false then return end
  if IsGuarded() then return end

  local show = self:GetSpellRule(spellID)
  if not show then return end

  State.activeProcSpells[spellID] = true
  State.procCapableSpells[spellID] = true
  local hadIcon = State.activeIcons[spellID] ~= nil
  local durationObj = C_Spell.GetSpellCooldownDuration(spellID)
  local iconFrame, iconData = ShowSpellIcon(spellID, durationObj, true)
  if iconFrame and iconData then
    iconData.procActive = true
    iconFrame.procActive = true
    if not hadIcon then
      iconData.procOnly = true
      iconFrame.procOnly = true
    end
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
end

eventHandlers.SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = function(_, spellID)
  if not spellID then return end
  if CooldownCursorDB.global.showProcs == false then return end

  State.activeProcSpells[spellID] = nil
  local iconData = State.activeIcons[spellID]
  if not (iconData and iconData.iconFrame) then return end

  local iconFrame = iconData.iconFrame
  iconData.procActive = false
  iconFrame.procActive = false
  if iconFrame.procOverlay then iconFrame.procOverlay:Hide() end
  if iconFrame.procOutline then iconFrame.procOutline:Hide() end
  if iconData.procOnly then
    RemoveIconForSpell(spellID, true)
  end
end

-- Wire the four spell cast/cooldown events to the shared handler
for eventName in pairs(SPELL_CAST_EVENTS) do
  eventHandlers[eventName] = function(self, ...)
    HandleSpellCastEvent(self, eventName, ...)
  end
end

----------------------------------------------------
-- Event dispatcher
----------------------------------------------------
CooldownCursor:SetScript("OnEvent", function(self, event, ...)
  if Internal.LogEvent then
    Internal.LogEvent(event, ...)
  end
  local handler = eventHandlers[event]
  if handler then
    handler(self, ...)
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
CooldownCursor:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
CooldownCursor:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
CooldownCursor:RegisterEvent("SPELL_UPDATE_CHARGES")
CooldownCursor:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
CooldownCursor:RegisterEvent("UI_SCALE_CHANGED")
CooldownCursor:RegisterEvent("DISPLAY_SIZE_CHANGED")
CooldownCursor:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
CooldownCursor:RegisterEvent("PLAYER_ENTERING_WORLD")
