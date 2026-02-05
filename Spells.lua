----------------------------------------------------
-- CooldownCursor Spells Module
-- Spellbook Scanner (11.0+ API)
-- Collects detailed spell information from player's spellbook
----------------------------------------------------
local addonName, addonTable = ...

----------------------------------------------------
-- Spell Type Enum Names
----------------------------------------------------
local SpellBookItemTypeNames = {
  [Enum.SpellBookItemType.None] = "None",
  [Enum.SpellBookItemType.Spell] = "Spell",
  [Enum.SpellBookItemType.FutureSpell] = "FutureSpell",
  [Enum.SpellBookItemType.PetAction] = "PetAction",
  [Enum.SpellBookItemType.Flyout] = "Flyout",
}

----------------------------------------------------
-- Cache for scanned spells
----------------------------------------------------
local spellBookCache = nil
local spellBookCacheTime = 0
local CACHE_DURATION = 60 -- Seconds before cache expires

----------------------------------------------------
-- Build detailed spell data table
----------------------------------------------------
local function BuildSpellData(spellID, slotIndex, spellBank, tabName, isFromFlyout, flyoutName, itemInfo)
  if InCombatLockdown() then return nil end
  if not spellID then return nil end

  -- Get core spell info from C_Spell
  local spellInfo = C_Spell.GetSpellInfo(spellID)
  if not spellInfo then return nil end

  -- Get base cooldown (in milliseconds)
  local baseCooldownMS, baseGcdMS = GetSpellBaseCooldown(spellID)
  local hasCooldown = baseCooldownMS and baseCooldownMS > 0

  -- Get current cooldown state
  local cooldownInfo = C_Spell.GetSpellCooldown(spellID)

  -- Get usability
  local isUsable, insufficientPower = C_Spell.IsSpellUsable(spellID)

  -- Get charges if applicable
  local chargeInfo = C_Spell.GetSpellCharges(spellID)

  -- Determine spell type string
  local spellTypeEnum = itemInfo and itemInfo.itemType or Enum.SpellBookItemType.Spell
  local spellTypeName = SpellBookItemTypeNames[spellTypeEnum] or "Unknown"

  -- Check if passive
  local isPassive = itemInfo and itemInfo.isPassive or false

  -- Build the data table
  local data = {
    -- Core identification
    spellID = spellID,
    name = spellInfo.name,
    subName = itemInfo and itemInfo.subName or "",

    -- Visual
    iconID = spellInfo.iconID,
    originalIconID = spellInfo.originalIconID,

    -- Classification
    spellType = spellTypeName,
    spellTypeEnum = spellTypeEnum,
    isPassive = isPassive,
    isOffSpec = itemInfo and itemInfo.isOffSpec or false,

    -- Cooldown info
    hasCooldown = hasCooldown,
    baseCooldown = baseCooldownMS and (baseCooldownMS / 1000) or 0,
    baseGCD = baseGcdMS and (baseGcdMS / 1000) or 0,

    -- Current cooldown state (snapshot at time of scan)
    cooldownStartTime = cooldownInfo and cooldownInfo.startTime or 0,
    cooldownDuration = cooldownInfo and cooldownInfo.duration or 0,
    cooldownEnabled = cooldownInfo and cooldownInfo.isEnabled or true,

    -- Casting info
    castTime = spellInfo.castTime / 1000,
    isInstantCast = spellInfo.castTime == 0,

    -- Range
    minRange = spellInfo.minRange,
    maxRange = spellInfo.maxRange,
    hasRange = spellInfo.maxRange > 0,

    -- Usability
    isUsable = isUsable,
    insufficientPower = insufficientPower,

    -- Charges (nil if spell doesn't use charges)
    hasCharges = chargeInfo ~= nil,
    currentCharges = chargeInfo and chargeInfo.currentCharges,
    maxCharges = chargeInfo and chargeInfo.maxCharges,
    chargeRecoveryStart = chargeInfo and chargeInfo.cooldownStartTime,
    chargeRecoveryDuration = chargeInfo and chargeInfo.cooldownDuration,

    -- Spellbook location
    spellBookSlot = slotIndex,
    spellBank = spellBank,
    tabName = tabName,

    -- Flyout info
    isFromFlyout = isFromFlyout,
    flyoutName = flyoutName,
  }

  return data
end

----------------------------------------------------
-- Process a spell bank (Player or Pet)
----------------------------------------------------
local function ProcessSpellBank(spells, spellBank, includeFutureSpells)
  local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines(spellBank)

  for skillLineIndex = 1, numSkillLines do
    local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex, spellBank)

    if skillLineInfo then
      local offset = skillLineInfo.itemIndexOffset
      local numSlots = skillLineInfo.numSpellBookItems
      local tabName = skillLineInfo.name

      for i = 1, numSlots do
        local slotIndex = offset + i
        local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)

        if itemInfo then
          -- Skip future spells unless requested
          if itemInfo.itemType == Enum.SpellBookItemType.FutureSpell and not includeFutureSpells then
            -- Skip
          -- Handle Flyouts (portals, teleports, etc.)
          elseif itemInfo.itemType == Enum.SpellBookItemType.Flyout then
            local flyoutID = itemInfo.actionID
            if flyoutID then
              local _, _, numFlyoutSlots = GetFlyoutInfo(flyoutID)
              if numFlyoutSlots then
                for flyoutSlot = 1, numFlyoutSlots do
                  local flyoutSpellID, overrideSpellID, isKnown = GetFlyoutSlotInfo(flyoutID, flyoutSlot)
                  if isKnown and flyoutSpellID then
                    local spellID = overrideSpellID or flyoutSpellID
                    local spellData = BuildSpellData(spellID, slotIndex, spellBank, tabName, true, itemInfo.name, nil)
                    if spellData then
                      table.insert(spells, spellData)
                    end
                  end
                end
              end
            end
          -- Regular spells
          elseif itemInfo.spellID then
            local spellData = BuildSpellData(itemInfo.spellID, slotIndex, spellBank, tabName, false, nil, itemInfo)
            if spellData then
              table.insert(spells, spellData)
            end
          end
        end
      end
    end
  end
end

----------------------------------------------------
-- Public API (stored in addonTable for access)
----------------------------------------------------
local Spells = {}
addonTable.Spells = Spells

--- Get all spells from the player's spellbook
-- @param includePetSpells boolean - Include pet spells in the scan
-- @param includeFutureSpells boolean - Include spells not yet learned
-- @param forceRefresh boolean - Bypass cache and rescan
-- @return table - Array of spell data tables
function Spells:GetAllSpellBookSpells(includePetSpells, includeFutureSpells, forceRefresh)
  -- Return cached data if still valid
  local now = GetTime()
  if not forceRefresh and spellBookCache and (now - spellBookCacheTime) < CACHE_DURATION then
    return spellBookCache
  end

  local spells = {}

  -- Process player spells
  ProcessSpellBank(spells, Enum.SpellBookSpellBank.Player, includeFutureSpells)

  -- Optionally process pet spells
  if includePetSpells then
    ProcessSpellBank(spells, Enum.SpellBookSpellBank.Pet, includeFutureSpells)
  end

  -- Update cache
  spellBookCache = spells
  spellBookCacheTime = now

  return spells
end

--- Get only spells with cooldowns (useful for cooldown tracking)
-- @param includePetSpells boolean - Include pet spells
-- @param minCooldown number - Minimum base cooldown in seconds (default 1.5 to filter GCD-only spells)
-- @param onlyKnown boolean - Only include spells the player currently knows
-- @return table - Array of cooldown spell data
function Spells:GetCooldownSpells(includePetSpells, minCooldown, onlyKnown)
  local allSpells = self:GetAllSpellBookSpells(includePetSpells, false, false)
  local cooldownSpells = {}

  -- Default to 1.5 seconds to filter out GCD-only spells
  minCooldown = minCooldown or 1.5

  for _, spell in ipairs(allSpells) do
    if spell.hasCooldown
        and not spell.isPassive
        and spell.baseCooldown >= minCooldown
        and (not onlyKnown or C_SpellBook.IsSpellKnown(spell.spellID))
    then
      table.insert(cooldownSpells, spell)
    end
  end

  return cooldownSpells
end

--- Get spells indexed by spellID for quick lookup
-- @param includePetSpells boolean - Include pet spells
-- @param includeFutureSpells boolean - Include future spells
-- @return table - Dictionary keyed by spellID
function Spells:GetSpellBookByID(includePetSpells, includeFutureSpells)
  local allSpells = self:GetAllSpellBookSpells(includePetSpells, includeFutureSpells, false)
  local byID = {}

  for _, spell in ipairs(allSpells) do
    byID[spell.spellID] = spell
  end

  return byID
end

--- Invalidate the spellbook cache (call when talents/spec changes)
function Spells:InvalidateSpellBookCache()
  spellBookCache = nil
  spellBookCacheTime = 0
end

--- Get the SpellBookItemType name for a given enum value
-- @param enumValue number - Enum.SpellBookItemType value
-- @return string - Human readable name
function Spells:GetSpellTypeName(enumValue)
  return SpellBookItemTypeNames[enumValue] or "Unknown"
end

----------------------------------------------------
-- Register Module
-- This makes Spells methods available via CooldownCursor
--
-- Usage:
--   local spells = CooldownCursor:GetCooldownSpells(true)
--   local allSpells = CooldownCursor:GetAllSpellBookSpells(false, false, false)
--   local spellLookup = CooldownCursor:GetSpellBookByID(false, false)
--   CooldownCursor:InvalidateSpellBookCache()
----------------------------------------------------
addonTable.Modules = addonTable.Modules or {}
addonTable.Modules.Spells = Spells
