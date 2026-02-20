----------------------------------------------------
-- CooldownCursor: Settings Module
-- Settings API, validators, spell rule CRUD,
-- multi-icon public API
----------------------------------------------------
local addonName, addonTable = ...

local C = addonTable.Constants
local defaults = addonTable.Defaults
local State = addonTable.State
local Internal = addonTable.Internal
local GetTableKeys = addonTable.Util.GetTableKeys
local IsValidTableKey = addonTable.Util.IsValidTableKey

local SHOW_WHEN_STATE = C.SHOW_WHEN_STATE
local ANCHOR_POSITION = C.ANCHOR_POSITION
local FRAME_STRATA = C.FRAME_STRATA
local CD_TEXT_ANCHOR_POINTS = C.CD_TEXT_ANCHOR_POINTS
local SPELL_TEXT_ANCHOR_POINTS = C.SPELL_TEXT_ANCHOR_POINTS
local FONT_TYPES = C.FONT_TYPES
local SORT_ORDER = C.SORT_ORDER
local STACK_DIRECTION = C.STACK_DIRECTION
local STACK_GROWTH = C.STACK_GROWTH
local POSITION_MODE = C.POSITION_MODE

local CooldownCursor = addonTable.Frame

----------------------------------------------------
-- Settings Module
----------------------------------------------------
local Settings = {}

function Settings:GetVersion()
  return C_AddOns.GetAddOnMetadata(addonName, "Version")
end

function Settings:GetMajorVersion()
  local major = C_AddOns.GetAddOnMetadata(addonName, "Version")
  return major:match("^(%d+)")
end

function Settings:GetAuthor()
  return C_AddOns.GetAddOnMetadata(addonName, "Author")
end

function Settings:GetNotes()
  return C_AddOns.GetAddOnMetadata(addonName, "Notes")
end

function Settings:GetDBValue(key)
  if CooldownCursorDB.global[key] ~= nil then
    return CooldownCursorDB.global[key]
  end
  return defaults[key]
end

function Settings:SetDBString(key, value)
  CooldownCursorDB.global[key] = string.format("%s", value)
  if key == "positionMode" then
    Internal.ApplyPositionMode()
    if State.previewActive then
      CooldownCursor:ApplyPreviewPosition()
    end
  end
  self:UpdateDisplay()
end

function Settings:SetDBNumber(key, value)
  CooldownCursorDB.global[key] = tonumber(value)
  -- Switching showBehavior leaves stale icons (wrong alphas, wrong set of
  -- icons tracked). Clear everything and let ApplyShowBehavior re-seed.
  if key == "showBehavior" then
    self:HideAllIcons(true)
    Internal.ApplyShowBehavior()
  end
  if key == "showWhen" and not State.previewActive then
    State.inCombat = InCombatLockdown()
    if (value == SHOW_WHEN_STATE.COMBAT and not State.inCombat)
        or (value == SHOW_WHEN_STATE.NON_COMBAT and State.inCombat) then
      self:HideAllIcons(true)
    else
      Internal.ApplyShowBehavior()
    end
  end
  self:UpdateDisplay()
end

function Settings:SetDBBoolean(key, value)
  CooldownCursorDB.global[key] = value and true or false
  self:UpdateDisplay()
end

function Settings:ClearProcStates(removeProcOnly)
  State.activeProcSpells = {}
  State.procCapableSpells = {}
  local toRemove = {}

  for spellID, iconData in pairs(State.activeIcons) do
    iconData.procActive = false
    if iconData.iconFrame then
      iconData.iconFrame.procActive = false
      if iconData.iconFrame.procOverlay then
        iconData.iconFrame.procOverlay:Hide()
      end
      if iconData.iconFrame.procOutline then
        iconData.iconFrame.procOutline:Hide()
      end
    end
    if removeProcOnly and iconData.procOnly then
      table.insert(toRemove, spellID)
    end
  end

  for _, spellID in ipairs(toRemove) do
    Internal.RemoveIconForSpell(spellID, true)
  end
end

function Settings:AddOrUpdateSpellRule(spellID, ruleData)
  spellID = tonumber(spellID)
  if not spellID then return false, "Invalid spell ID" end

  local spellName = C_Spell.GetSpellInfo(spellID)
  if not spellName then return false, "Unknown spell ID" end

  CooldownCursorDB.spellRules = CooldownCursorDB.spellRules or {}
  CooldownCursorDB.spellRules.settings = CooldownCursorDB.spellRules.settings or {}
  CooldownCursorDB.spellRules.rules = CooldownCursorDB.spellRules.rules or {}

  -- Get class-specific rules table
  local classRules = Internal.GetClassRules()
  if not classRules then return false, "Could not determine player class" end

  classRules[spellID] = classRules[spellID] or { settings = {}, metadata = {} }
  local rule = classRules[spellID]
  rule.settings = rule.settings or {}
  rule.metadata = rule.metadata or {}

  -- Apply user-provided settings
  for k, v in pairs(ruleData or {}) do
    rule.settings[k] = v
  end

  -- Auto-populate static spell metadata
  local baseCooldownMS, _ = GetSpellBaseCooldown(spellID)
  local baseCooldown = baseCooldownMS and (baseCooldownMS / 1000) or 0
  local chargeInfo = C_Spell.GetSpellCharges(spellID)
  local info = C_Spell.GetSpellInfo(spellID)

  rule.metadata.baseCooldown = baseCooldown
  rule.metadata.hasCooldown = baseCooldown > 1.5
  rule.metadata.hasCharges = chargeInfo ~= nil
  rule.metadata.maxCharges = chargeInfo and chargeInfo.maxCharges or nil
  rule.metadata.isInstantCast = info and info.castTime == 0 or false
  rule.metadata.castTime = info and (info.castTime / 1000) or 0
  rule.metadata.hasRange = info and info.maxRange > 0 or false
  rule.metadata.maxRange = info and info.maxRange or 0

  return true, spellName
end

function Settings:RemoveSpellRule(spellID)
  local classRules = Internal.GetClassRules()
  if not classRules then return end

  classRules[spellID] = nil
  CooldownCursor:UpdateDisplay()
  CooldownCursor:RebuildSpellRuleOptions()
  CooldownCursor:NotifyOptionsChanged()
end

function Settings:GetEffectiveIconSize(spellID)
  local globalSize = self:GetDBValue("iconSize")
  local classRules = Internal.GetClassRules()

  if not classRules then return globalSize end

  local rule = classRules[spellID]
  if not rule or not rule.settings then return globalSize end

  if rule.settings.useGlobalIconSize ~= false then return globalSize end

  if rule.settings.iconSize then return rule.settings.iconSize end

  return globalSize
end

function Settings:SetFontPath(key, value)
  CooldownCursorDB.global[key] = value
  CooldownCursorDB.global[key .. "Path"] = Internal.FontPath(CooldownCursorDB.global[key])
  self:UpdateDisplay()
end

function Settings:GetAllFonts()
  return Internal.FontNames()
end

function Settings:GetValidFontTypes()
  return FONT_TYPES
end

function Settings:GetValidAnchorPositions()
  return GetTableKeys(ANCHOR_POSITION)
end

function Settings:GetValidFrameStratas()
  return GetTableKeys(FRAME_STRATA)
end

function Settings:GetValidSpellTextAnchorPositions()
  return GetTableKeys(SPELL_TEXT_ANCHOR_POINTS)
end

function Settings:GetValidCooldownTextAnchorPositions()
  return GetTableKeys(CD_TEXT_ANCHOR_POINTS)
end

function Settings:GetValidFontType(ftype)
  if not ftype then return false end
  local fontType = string.upper(ftype)
  if fontType == "NONE" then return true end
  return FONT_TYPES[fontType] ~= nil
end

function Settings:GetValidAnchorPosition(pos)
  return IsValidTableKey(ANCHOR_POSITION, pos)
end

function Settings:GetValidSpellTextAnchorPosition(pos)
  return IsValidTableKey(SPELL_TEXT_ANCHOR_POINTS, pos)
end

function Settings:GetValidCooldownTextAnchorPosition(pos)
  return IsValidTableKey(CD_TEXT_ANCHOR_POINTS, pos)
end

function Settings:GetValidFrameStrata(strata)
  return IsValidTableKey(FRAME_STRATA, strata)
end

function Settings:SetHideAfter(seconds)
  CooldownCursorDB.global.hideAfter = tonumber(seconds) or defaults.hideAfter
end

function Settings:SetFadeOutDuration(seconds)
  CooldownCursorDB.global.fadeOutDuration = tonumber(seconds) or defaults.fadeOutDuration
end

function Settings:GetPreviewMouseMode()
  return State.previewMouseMode
end

function Settings:SetPreviewMouseMode(enabled)
  State.previewMouseMode = enabled
  if State.previewActive then
    CooldownCursor:ApplyPreviewPosition()
  end
end

function Settings:ResetSettings()
  CooldownCursor:HideIconNow()
  CooldownCursorDB.global = {}
  self:ApplyDefaults()
  self:UpdateDisplay()
  Internal.ApplyPositionMode()
  CooldownCursor:SetPreviewMouseMode(true)
end

----------------------------------------------------
-- Multi-Icon Public API
----------------------------------------------------

function Settings:HideAllIcons(immediate)
  -- Directly clean up each icon frame instead of using RemoveIconForSpell,
  -- which calls SortIcons/UpdateIconPositions after every single removal.
  for _, iconData in ipairs(State.iconsByPriority) do
    local iconFrame = iconData.iconFrame
    if iconFrame then
      if immediate or CooldownCursorDB.global.fadeOutDuration == 0 then
        Internal.ReturnIconToPool(iconFrame)
      else
        if iconFrame.fadeOut then
          iconFrame.fadeOut:Stop()
          local fadeOutAnim = iconFrame.fadeOut:GetAnimations()
          fadeOutAnim:SetDuration(CooldownCursorDB.global.fadeOutDuration or 0.3)
          iconFrame.fadeOut:Play()
        else
          Internal.ReturnIconToPool(iconFrame)
        end
      end
    end
  end
  State.activeIcons = {}
  State.iconsByPriority = {}
end

function Settings:GetActiveIconCount()
  return #State.iconsByPriority
end

function Settings:IsMultiIconEnabled()
  local stackDirection = CooldownCursorDB.global.stackDirection or defaults.stackDirection
  return stackDirection ~= STACK_DIRECTION.SINGLE
end

function Settings:InitMultiIconSystem()
  Internal.InitializeIconPool()
end

function Settings:GetValidSortOrders()
  return {
    ALPHABETICAL = "Alphabetical",
    PRIORITY = "Priority (Spell Rules)",
    TIME_ADDED = "Time Added (Oldest First)",
  }
end

function Settings:GetValidStackDirections()
  return {
    VERTICAL = "Vertical",
    SINGLE = "Single (Override)",
    HORIZONTAL = "Horizontal",
    RADIUS = "Radius (Circle)",
  }
end

function Settings:GetValidPositionModes()
  return {
    CURSOR = "Cursor (Follow Mouse)",
    SCREEN = "Screen (Drag Anchor)",
  }
end

function Settings:GetValidStackGrowth()
  local direction = CooldownCursorDB.global.stackDirection or STACK_DIRECTION.VERTICAL

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

addonTable.Modules.Settings = Settings
