----------------------------------------------------
-- CooldownCursor: Core
-- Frame creation, module system, icon factory,
-- pool management, shared state
----------------------------------------------------
local addonName, addonTable = ...

local C = addonTable.Constants
local defaults = addonTable.Defaults
local PROC_OVERLAY_ATLAS_SETTINGS = C.PROC_OVERLAY_ATLAS_SETTINGS
local PROC_OUTLINE_ATLAS_SETTINGS = C.PROC_OUTLINE_ATLAS_SETTINGS
local DEFAULT_SYSTEM_FONTS = C.DEFAULT_SYSTEM_FONTS
local PercentToAlpha = addonTable.Util.PercentToAlpha

----------------------------------------------------
-- Frame Creation & Module System
----------------------------------------------------
local CooldownCursor = CreateFrame("Frame")
addonTable.Frame = CooldownCursor

addonTable.Modules = addonTable.Modules or {}

-- Preserve the original Frame metatable
local originalMT = getmetatable(CooldownCursor)
local originalIndex = originalMT and originalMT.__index

setmetatable(CooldownCursor, {
  __index = function(self, key)
    -- First, check the original Frame methods
    if originalIndex then
      local value
      if type(originalIndex) == "function" then
        value = originalIndex(self, key)
      elseif type(originalIndex) == "table" then
        value = originalIndex[key]
      end
      if value ~= nil then
        return value
      end
    end

    -- Then search registered modules for the method
    for _, module in pairs(addonTable.Modules) do
      if module[key] then
        return module[key]
      end
    end
    return nil
  end
})

----------------------------------------------------
-- Shared Runtime State
----------------------------------------------------
addonTable.State = {
  -- Spell tracking
  lastSpellId = nil,
  hideTimer = nil,
  activeSpellID = nil,
  inCombat = false,

  -- Fonts
  fontsTable = {},

  -- Preview
  previewMouseMode = true,
  previewActive = false,
  previewTicker = nil,

  -- Options panel state
  optionsOpen = false,

  -- Proc state
  activeProcSpells = {},
  procCapableSpells = {},

  -- Spell cache (invalidated on spec change)
  knownSpellCache = {},

  -- Screen metrics (refreshed on scale/resolution changes)
  cachedUIScale = 1,
  cachedScreenW = 0,
  cachedScreenH = 0,

  -- Cached OnUpdate settings (refreshed in UpdateDisplay / RefreshCachedSettings)
  cachedIconSize = nil,
  cachedAnchorPadding = nil,
  cachedAnchor = nil,
  cachedIconHide = false,
  cachedAnchorOX = 0,
  cachedAnchorOY = 0,
  cachedHalfSize = 0,

  -- Reusable buffer for ApplyShowBehavior (avoids table alloc per call)
  toRemoveBuffer = {},

  -- Multi-icon state
  iconPool = {},
  activeIcons = {},
  iconsByPriority = {},
  nextIconID = 1,

  -- Player class cache
  playerClass = nil,
}

local State = addonTable.State

----------------------------------------------------
-- Known Spell Cache
----------------------------------------------------
local function IsSpellKnownCached(spellID)
  local cached = State.knownSpellCache[spellID]
  if cached == nil then
    cached = C_SpellBook.IsSpellKnown(spellID)
    State.knownSpellCache[spellID] = cached
  end
  return cached
end

----------------------------------------------------
-- Screen Metrics
----------------------------------------------------
local function RefreshScreenMetrics()
  State.cachedUIScale = UIParent:GetEffectiveScale()
  State.cachedScreenW = UIParent:GetWidth()
  State.cachedScreenH = UIParent:GetHeight()
end

----------------------------------------------------
-- Proc helpers
----------------------------------------------------
local function IsProcOverlayEnabled()
  local atlas = CooldownCursorDB.global.procOverlayAtlas or defaults.procOverlayAtlas
  return atlas and atlas ~= "" and atlas ~= "none"
end

local function IsProcOutlineEnabled()
  local atlas = CooldownCursorDB.global.procOutlineAtlas or defaults.procOutlineAtlas
  return atlas and atlas ~= "" and atlas ~= "none"
end

----------------------------------------------------
-- LibSharedMedia support
----------------------------------------------------
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

----------------------------------------------------
-- Font helpers
----------------------------------------------------
local function FontNames()
  if #State.fontsTable > 0 then
    return State.fontsTable
  end

  if LSM then
    for _, fontName in pairs(LSM:List("font")) do
      local path = LSM:Fetch("font", fontName)
      if path then
        table.insert(State.fontsTable, fontName)
      end
    end
  else
    for name, _ in pairs(DEFAULT_SYSTEM_FONTS) do
      table.insert(State.fontsTable, name)
    end
  end
  return State.fontsTable
end

local function FontPath(fontName)
  local path = DEFAULT_SYSTEM_FONTS[tostring(fontName) or nil]
  if LSM and path == nil then
    path = LSM:Fetch("font", tostring(fontName))
  end
  return path
end

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
-- Masque support
----------------------------------------------------
local Masque = LibStub and LibStub("Masque", true)
local MasqueGroup = Masque and Masque:Group(addonName)
local registeredWithMasque = {}

local function EnsureMasqueButton(iconFrame)
  if not MasqueGroup or not iconFrame then return end

  if not registeredWithMasque[iconFrame] then
    MasqueGroup:AddButton(iconFrame, {
      Icon = iconFrame.icon,
      Cooldown = iconFrame.cooldown,
    })
    registeredWithMasque[iconFrame] = true
  end
end

----------------------------------------------------
-- Icon frame creation
----------------------------------------------------
-- Forward declaration for ReturnIconToPool (used in fadeOut callback)
local ReturnIconToPool

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
  iconFrame.cooldown:SetDrawBling(false)

  local cooldownRegion = iconFrame.cooldown:GetRegions()
  if cooldownRegion and cooldownRegion:IsObjectType("FontString") then
    iconFrame.cooldownText = cooldownRegion
  end

  iconFrame.text = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  iconFrame.text:SetPoint("BOTTOM", iconFrame, "TOP", 0, 4)
  iconFrame.text:Hide()

  -- Overlay frame for charge text (sits above cooldown swipe, independent of cooldown lifecycle)
  iconFrame.chargeOverlay = CreateFrame("Frame", nil, iconFrame)
  iconFrame.chargeOverlay:SetAllPoints(iconFrame)
  iconFrame.chargeOverlay:SetFrameLevel(iconFrame.cooldown:GetFrameLevel() + 1)
  iconFrame.chargeText = iconFrame.chargeOverlay:CreateFontString(nil, "OVERLAY")
  iconFrame.chargeText:Hide()

  -- Preview mode indicator text
  iconFrame.previewText = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  iconFrame.previewText:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, -10)
  iconFrame.previewText:SetText("|cff00ff00PREVIEW|r")
  iconFrame.previewText:Hide()

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
    iconFrame.chargeText:Hide()
    iconFrame:Hide()
    iconFrame.icon:SetAlpha(1)
    ReturnIconToPool(iconFrame)
  end)

  -- Primary icon indicator border (for preview mode)
  iconFrame.primaryBorder = iconFrame:CreateTexture(nil, "OVERLAY")
  iconFrame.primaryBorder:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -3, 3)
  iconFrame.primaryBorder:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 3, -3)
  iconFrame.primaryBorder:SetColorTexture(0, 1, 0, 0.8) -- Green border
  iconFrame.primaryBorder:Hide()

  -- Primary label text
  iconFrame.primaryLabel = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  iconFrame.primaryLabel:SetPoint("BOTTOM", iconFrame, "TOP", 0, 6)
  iconFrame.primaryLabel:SetText("|cff00ff00PRIMARY|r")
  iconFrame.primaryLabel:Hide()

  -- Proc overlay (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW)
  iconFrame.procOverlay = iconFrame:CreateTexture(nil, "OVERLAY")
  local overlayAtlas = CooldownCursorDB.global.procOverlayAtlas or defaults.procOverlayAtlas
  if IsProcOverlayEnabled() and overlayAtlas and overlayAtlas ~= "" then
    iconFrame.procOverlay:SetAtlas(overlayAtlas, true)
  end
  iconFrame.procOverlay:SetBlendMode("ADD")
  iconFrame.procOverlay:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
  iconFrame.procOverlay:Hide()

  -- Proc outline border
  iconFrame.procOutline = iconFrame:CreateTexture(nil, "OVERLAY")
  local outlineAtlas = CooldownCursorDB.global.procOutlineAtlas or defaults.procOutlineAtlas
  if IsProcOutlineEnabled() and outlineAtlas and outlineAtlas ~= "" then
    iconFrame.procOutline:SetAtlas(outlineAtlas, true)
  end
  iconFrame.procOutline:SetBlendMode("ADD")
  iconFrame.procOutline:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
  iconFrame.procOutline:SetAlpha(0.9)
  iconFrame.procOutline:Hide()


  iconFrame.iconID = index
  iconFrame.spellID = nil
  iconFrame.addedTime = nil
  iconFrame.priority = 0
  iconFrame.hideTimer = nil
  iconFrame.stackOffsetX = 0
  iconFrame.stackOffsetY = 0
  iconFrame.procActive = false
  iconFrame.procOnly = false

  return iconFrame
end

----------------------------------------------------
-- Icon Pool Management
----------------------------------------------------
local function InitializeIconPool()
  local poolSize = CooldownCursorDB.global.iconPoolSize or defaults.iconPoolSize
  for i = 1, poolSize do
    local iconFrame = CreateIconFrame(i)
    table.insert(State.iconPool, iconFrame)
  end
  State.nextIconID = poolSize + 1
end

local function GetIconFromPool()
  local iconFrame
  if #State.iconPool > 0 then
    iconFrame = table.remove(State.iconPool)
  else
    iconFrame = CreateIconFrame(State.nextIconID)
    State.nextIconID = State.nextIconID + 1
  end
  iconFrame._inPool = false
  return iconFrame
end

ReturnIconToPool = function(iconFrame)
  if not iconFrame then return end

  -- Guard against double-return (same frame already in pool)
  if iconFrame._inPool then return end
  iconFrame._inPool = true

  -- Stop any playing animations to prevent OnFinished from firing later
  if iconFrame.showAnim then
    iconFrame.showAnim:Stop()
  end
  if iconFrame.fadeOut then
    iconFrame.fadeOut:Stop()
  end

  -- Clear cooldown swipe so pooled frames don't carry stale state
  if iconFrame.cooldown then
    iconFrame.cooldown:Clear()
  end

  -- Reset the frame to a clean default state before it goes back into the pool
  iconFrame:Hide()
  iconFrame:SetScript("OnUpdate", nil)
  iconFrame:SetScale(1)
  iconFrame.spellID = nil
  iconFrame.addedTime = nil
  iconFrame.priority = 0
  iconFrame.stackOffsetX = 0
  iconFrame.stackOffsetY = 0
  iconFrame._lastX = nil
  iconFrame._lastY = nil

  -- Hide primary indicator
  if iconFrame.primaryBorder then
    iconFrame.primaryBorder:Hide()
  end
  if iconFrame.primaryLabel then
    iconFrame.primaryLabel:Hide()
  end
  if iconFrame.chargeText then
    iconFrame.chargeText:Hide()
  end
  if iconFrame.procOverlay then
    iconFrame.procOverlay:Hide()
  end
  if iconFrame.procOutline then
    iconFrame.procOutline:Hide()
  end
  iconFrame.procActive = false
  iconFrame.procOnly = false

  -- Hide preview text
  if iconFrame.previewText then
    iconFrame.previewText:Hide()
  end

  if iconFrame.hideTimer then
    iconFrame.hideTimer:Cancel()
    iconFrame.hideTimer = nil
  end

  table.insert(State.iconPool, iconFrame)
end

----------------------------------------------------
-- Export Internal functions
----------------------------------------------------
addonTable.Internal = {
  IsSpellKnownCached = IsSpellKnownCached,
  RefreshScreenMetrics = RefreshScreenMetrics,
  IsProcOverlayEnabled = IsProcOverlayEnabled,
  IsProcOutlineEnabled = IsProcOutlineEnabled,
  FontNames = FontNames,
  FontPath = FontPath,
  ApplyFonts = ApplyFonts,
  EnsureMasqueButton = EnsureMasqueButton,
  MasqueGroup = MasqueGroup,
  CreateIconFrame = CreateIconFrame,
  InitializeIconPool = InitializeIconPool,
  GetIconFromPool = GetIconFromPool,
  ReturnIconToPool = ReturnIconToPool,
}
