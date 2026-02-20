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
-- Event handler
----------------------------------------------------
local SPELL_EVENTS = {
  UNIT_SPELLCAST_FAILED = true,
  UNIT_SPELLCAST_SENT = true,
  UNIT_SPELLCAST_SUCCEEDED = true,
  SPELL_UPDATE_COOLDOWN = true,
  SPELL_UPDATE_USABLE = true,
}
local pendingSpellTimers = {}

CooldownCursor:SetScript("OnEvent", function(self, event, ...)
  local unit
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then return end
    self:ApplyDefaults()
    RefreshScreenMetrics()
    self:InitMultiIconSystem()
    self:UpdateDisplay()
    self:InitAce3Options()
    self:UnregisterEvent("ADDON_LOADED")
    State.inCombat = InCombatLockdown()
    return
  end

  if event == "PLAYER_SPECIALIZATION_CHANGED" then
    unit = ...
    if unit == "player" then
      wipe(State.knownSpellCache)
      CooldownCursor:HideAllIcons(true)
      ApplyShowBehavior()
      return
    end
  end

  -- Detect mount/dismount
  if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
    CheckMountedState()
    return
  end

  if event == "SPELL_UPDATE_CHARGES" then
    if CheckShowWhenState() then return end
    if CheckMountedState() then return end
    if CooldownCursorDB.global.showCharges ~= false then
      for spellID, iconData in pairs(State.activeIcons) do
        if iconData and iconData.iconFrame and iconData.hasCharges then
          UpdateChargeCount(iconData.iconFrame, spellID)
        end
      end
      ApplyShowBehavior()
    end
    return
  end

  if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
    if CheckShowWhenState() then return end
    if CheckMountedState() then return end
    local spellID = ...
    if not spellID then return end
    if CooldownCursorDB.global.showProcs == false then return end

    local show = CooldownCursor:GetSpellRule(spellID)
    if not show then return end
    State.activeProcSpells[spellID] = true
    State.procCapableSpells[spellID] = true
    local durationObj = C_Spell.GetSpellCooldownDuration(spellID)
    local hadIcon = State.activeIcons[spellID] ~= nil
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
    return
  end

  if event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
    local spellID = ...
    if not spellID then return end
    if CooldownCursorDB.global.showProcs == false then return end
    State.activeProcSpells[spellID] = nil
    local iconData = State.activeIcons[spellID]
    if iconData and iconData.iconFrame then
      local iconFrame = iconData.iconFrame
      iconData.procActive = false
      iconFrame.procActive = false
      if iconFrame.procOverlay then
        iconFrame.procOverlay:Hide()
      end
      if iconFrame.procOutline then
        iconFrame.procOutline:Hide()
      end
      if iconData.procOnly then
        RemoveIconForSpell(spellID, true)
      end
    end
    return
  end

  if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    RefreshScreenMetrics()
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    State.inCombat = true
    if not CheckShowWhenState(true) then
      ApplyShowBehavior()
    end
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    State.inCombat = false
    if not CheckShowWhenState(true) then
      ApplyShowBehavior()
    end
    return
  end

  if CheckShowWhenState() then return end

  if CheckMountedState() then return end

  if event == "SPELL_UPDATE_USABLE" or event == "PLAYER_ENTERING_WORLD" then
    ApplyShowBehavior()
    return
  end

  if SPELL_EVENTS[event] then
    -- Check if addon is enabled
    if CooldownCursorDB.global.enabled == false then
      return
    end

    local spellID

    -- SPELL_UPDATE_COOLDOWN (11.1.5+) provides spellID, baseSpellID,
    -- category, startRecoveryCategory. A nil spellID means all cooldowns
    -- should be refreshed (handled by the nil check below).
    if event == "SPELL_UPDATE_COOLDOWN" then
      spellID, _, _, _ = ...
    else
      unit, _, spellID = ...
      if unit ~= "player" then return end
    end
    if not spellID then
      ApplyShowBehavior()
      return
    end

    -- Check user spell rules before doing any cooldown queries
    local show, rule = CooldownCursor:GetSpellRule(spellID)
    if not show then return end
    local hasCharges = rule and rule.metadata and rule.metadata.hasCharges or false

    -- Debounce: skip if a timer is already pending for this spellID
    if not pendingSpellTimers[spellID] then
      pendingSpellTimers[spellID] = true
      -- Delay slightly to allow cooldown to register
      C_Timer.After(0.01, function()
        pendingSpellTimers[spellID] = nil
        local durationObj = C_Spell.GetSpellCooldownDuration(spellID)

        if not durationObj then return end

        -- local usable = C_Spell.IsSpellUsable(spellID)
        local inRange = C_Spell.IsSpellInRange(spellID)

        -- Check spell usability
        if inRange == false and
          CooldownCursorDB.global.showBehavior ~= SHOW_BEHAVIOR.OFF_COOLDOWN then
          return
        end

        if hasCharges then
          local iconFrame, _ = ShowSpellIcon(spellID, durationObj)
          UpdateChargeCount(iconFrame, spellID)
          ApplyShowBehavior()
          return
        end

        if durationObj then
          ShowSpellIcon(spellID, durationObj)
        end

        ApplyShowBehavior()
      end)
    end
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

