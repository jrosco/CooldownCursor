----------------------------------------------------
-- CooldownCursor Addon
----------------------------------------------------
local addonName, addonTable = ...
local CooldownCursor = CreateFrame("Frame")
addonTable.Frame = CooldownCursor

----------------------------------------------------
-- Runtime state
----------------------------------------------------
local lastSpellId = nil
local hideTimer = nil
local activeSpellID = nil
local activeStartTime = nil
local activeDuration = nil
local inCombat = false
local fontsTable = {}

local SHOW_WHEN_STATE = {
  ALWAYS = 0,
  COMBAT = 1,
  NON_COMBAT = 2,
}

local ANCHOR_POSITION = {
  CENTER = "CENTER",
  TOP = "TOP",
  BOTTOM = "BOTTOM",
  LEFT = "LEFT",
  RIGHT = "RIGHT",
  TOPLEFT = "TOPLEFT",
  TOPRIGHT = "TOPRIGHT",
  BOTTOMLEFT = "BOTTOMLEFT",
  BOTTOMRIGHT = "BOTTOMRIGHT",
}

local CD_TEXT_ANCHOR_POINTS = {
  TOP = {
    point = "TOP",
    x = 0,
    y = -4,
  },
  BOTTOM = {
    point = "BOTTOM",
    x = 0,
    y = 4,
  },
  LEFT = {
    point = "LEFT",
    x = 4,
    y = 0,
  },
  RIGHT = {
    point = "RIGHT",
    x = -4,
    y = 0,
  },
  CENTER = {
    point = "CENTER",
    x = 0,
    y = 0,
  },
  TOPLEFT = {
    point = "TOPLEFT",
    x = 4,
    y = -4,
  },
  TOPRIGHT = {
    point = "TOPRIGHT",
    x = -4,
    y = -4,
  },
  BOTTOMLEFT = {
    point = "BOTTOMLEFT",
    x = 4,
    y = 4,
  },
  BOTTOMRIGHT = {
    point = "BOTTOMRIGHT",
    x = -4,
    y = 4,
  },
}

local SPELL_TEXT_ANCHOR_POINTS = {
  BOTTOM = {
    point = "TOP",
    relativeTo = "BOTTOM",
    x = 0,
    y = -4,
  },
  TOP = {
    point = "BOTTOM",
    relativeTo = "TOP",
    x = 0,
    y = 4,
  },
}

local FONT_TYPES = {
  OUTLINE = "OUTLINE",
  THICKOUTLINE = "THICKOUTLINE",
  MONOCHROME = "MONOCHROME",
  NONE = "NONE"
}

-- Default WoW fonts with descriptive names
local DEFAULT_SYSTEM_FONTS = {
    ["Default"] = "Fonts\\FRIZQT__.TTF",
    ["2002 Bold"] = "Fonts\\2002B.TTF",
    ["2002"] = "Fonts\\2002.TTF",
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
    ["Skurri"] = "Fonts\\skurri.ttf",
    ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
    ["Nimrod MT"] = "Fonts\\NIM_____.ttf",
}

----------------------------------------------------
-- Live Preview state
----------------------------------------------------
local previewActive = false
local previewTicker = nil

----------------------------------------------------
-- Defaults / SavedVariables
----------------------------------------------------
local defaults = {
  offsetX = 0, -- TODO: unused
  offsetY = 0, -- TODO: unused
  scale = 1,
  iconSize = 48,
  iconAlpha = 100,
  iconHide = false,
  showSpellNames = false,
  hideCooldownNumbers = false,
  showCooldownSwipe = false,
  hideAfter = 3,
  animation = false,
  minDuration = 1.5, -- TODO: remove in midnight
  maxDuration = 600, -- TODO: remove in midnight
  fadeOutDuration = 0,
  showWhen = SHOW_WHEN_STATE.ALWAYS, -- 0=always, 1=in-combat, 2=out-of-combat
  hideWhileMounted = false, -- hide when mounted
  anchor = ANCHOR_POSITION.TOPLEFT,
  anchorPadding = 2, -- distance from cursor
  spellTextFont = "Friz Quadrata TT",
  spellTextFontPath = DEFAULT_SYSTEM_FONTS["Friz Quadrata TT"],
  spellTextSize = 14,
  spellTextFontType = FONT_TYPES.OUTLINE,
  spellTextColor = "#FFD100",
  spellTextAnchor = "TOP", -- or BOTTOM
  spellTextAlpha = 100,
  cooldownTextSize = 20,
  cooldownTextFont = "Friz Quadrata TT",
  cooldownTextFontPath = DEFAULT_SYSTEM_FONTS["Friz Quadrata TT"],
  cooldownTextFontType = FONT_TYPES.OUTLINE,
  cooldownTextColor = "#FFFFFF",
  cooldownTextAnchor = CD_TEXT_ANCHOR_POINTS.CENTER.point,
  cooldownTextAlpha = 100,
}

function CooldownCursor:ApplyDefaults()
  CooldownCursorDB = CooldownCursorDB or {}
  for k, v in pairs(defaults) do
    if CooldownCursorDB[k] == nil then
      CooldownCursorDB[k] = v
    end
  end
end

----------------------------------------------------
-- Icon frame initialization
----------------------------------------------------
local icon = CreateFrame("Frame", "CooldownCursorIcon", UIParent)
icon:EnableMouse(false)
icon:SetSize(defaults.iconSize, defaults.iconSize)
icon:Hide()

icon.icon = icon:CreateTexture(nil, "BACKGROUND")
icon.icon:SetAllPoints()

icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
icon.cooldown:SetAllPoints(icon)
icon.cooldown:SetDrawEdge(false)

-- Cache the cooldown text region for later use
local cooldownRegion = icon.cooldown:GetRegions()
if cooldownRegion and cooldownRegion:IsObjectType("FontString") then
  icon.cooldownText = cooldownRegion
end

icon.text = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
icon.text:SetPoint("BOTTOM", icon, "TOP", 0, 4)
icon.text:Hide()

----------------------------------------------------
-- Show animation initialization
----------------------------------------------------
icon.showAnim = icon:CreateAnimationGroup()

local scaleUp = icon.showAnim:CreateAnimation("Scale")
scaleUp:SetOrder(1)
scaleUp:SetScale(1.15, 1.15)
scaleUp:SetDuration(0.08)

local scaleDown = icon.showAnim:CreateAnimation("Scale")
scaleDown:SetOrder(2)
scaleDown:SetScale(1 / 1.15, 1 / 1.15)
scaleDown:SetDuration(0.08)

----------------------------------------------------
-- Fade out icon animation initialization
----------------------------------------------------
icon.fadeOut = icon:CreateAnimationGroup()
local fadeOut = icon.fadeOut:CreateAnimation("Alpha")
fadeOut:SetFromAlpha(1)
fadeOut:SetToAlpha(0)
fadeOut:SetDuration(defaults.fadeOutDuration or 0)
fadeOut:SetSmoothing("OUT")

icon.fadeOut:SetScript("OnFinished", function()
  icon:SetScript("OnUpdate", nil)
  icon.cooldown:Clear()
  icon.text:Hide()
  icon:Hide()
  icon.icon:SetAlpha(1) -- reset for next show
end)

----------------------------------------------------
-- Masque support initialization
----------------------------------------------------
local Masque = LibStub and LibStub("Masque", true)
local MasqueGroup = Masque and Masque:Group(addonName)
if MasqueGroup then
  MasqueGroup:AddButton(icon, {
    Icon = icon.icon,
    Cooldown = icon.cooldown,
  })
end

----------------------------------------------------
-- OmniCC support check
----------------------------------------------------
function CooldownCursor:IsOmniCCLoaded()
  local _, loaded = C_AddOns.IsAddOnLoaded("OmniCC")
  return loaded
end

----------------------------------------------------
--- LibSharedMedia support
----------------------------------------------------
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

----------------------------------------------------
-- Internal cursor positioning helper
----------------------------------------------------
local function FlipAnchorX(anchor)
  if anchor:find("LEFT") then
    return anchor:gsub("LEFT", "RIGHT")
  elseif anchor:find("RIGHT") then
    return anchor:gsub("RIGHT", "LEFT")
  elseif anchor == "LEFT" then
    return "RIGHT"
  elseif anchor == "RIGHT" then
    return "LEFT"
  end
  return anchor
end

local function FlipAnchorY(anchor)
  if anchor:find("TOP") then
    return anchor:gsub("TOP", "BOTTOM")
  elseif anchor:find("BOTTOM") then
    return anchor:gsub("BOTTOM", "TOP")
  elseif anchor == "TOP" then
    return "BOTTOM"
  elseif anchor == "BOTTOM" then
    return "TOP"
  end
  return anchor
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

----------------------------------------------------
--- Get available fonts helper
----------------------------------------------------
local function FontNames()
  -- Return cached list if already built
  if #fontsTable > 0 then
    return fontsTable
  end
  -- Build font list
  if LSM then
    for _, fontName in pairs(LSM:List("font")) do
      local path = LSM:Fetch("font", fontName)
      if path then
        table.insert(fontsTable, fontName)
      end
    end
  else
    for name, _ in pairs(DEFAULT_SYSTEM_FONTS) do
      table.insert(fontsTable, name)
    end
  end
  return fontsTable
end

----------------------------------------------------
--- Internal Color helper
--------------------------------------------------
local function HexToRGB(hex)
  hex = hex:gsub("#", "")

  if #hex ~= 6 then
    return 1, 1, 1
  end

  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255

  return r, g, b
end

----------------------------------------------------
--- Internal Alpha helper
----------------------------------------------------
local function PercentToAlpha(percent)
  local alpha = tonumber(percent)
  if not alpha then return end

  -- Accept 0–100 and convert to 0–1
  if alpha > 1 then
    alpha = math.max(0, math.min(100, alpha)) / 100
  end

  return alpha

end

--------------------------------------------------
-- Internal Font Path helper
--------------------------------------------------
local function FontPath(fontName)
  local path = DEFAULT_SYSTEM_FONTS[tostring(fontName)]
  if LSM then
    path = LSM:Fetch("font", tostring(fontName)) or path
  end
  return path
end

----------------------------------------------------
-- Cursor tracking and positioning
----------------------------------------------------
local function UpdateCooldownIconFrame(self)
  local uiScale  = UIParent:GetEffectiveScale()
  local cursorX, cursorY = GetCursorPosition()

  local x = cursorX / uiScale
  local y = cursorY / uiScale

  local size = CooldownCursorDB.iconSize or defaults.iconSize
  local pad  = CooldownCursorDB.anchorPadding or defaults.anchorPadding
  local anchor = CooldownCursorDB.anchor or defaults.anchor

  local screenW = UIParent:GetWidth()
  local screenH = UIParent:GetHeight()
  local half = size / 2

  -- Calculate desired offsets
  local ox, oy = AnchorOffsets(anchor, size, pad)
  local targetX = x + ox
  local targetY = y + oy

  -- Check if it would go off-screen
  local offLeft   = (targetX - half) < 0
  local offRight  = (targetX + half) > screenW
  local offBottom = (targetY - half) < 0
  local offTop    = (targetY + half) > screenH

  -- Flip anchor if needed
  local flipped = anchor

  if offLeft or offRight then
    flipped = FlipAnchorX(flipped)
  end
  if offBottom or offTop then
    flipped = FlipAnchorY(flipped)
  end

  -- Recompute offsets after flipping
  ox, oy = AnchorOffsets(flipped, size, pad)

  self:ClearAllPoints()
  self:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
    x + ox * (CooldownCursorDB.scale or defaults.scale),
    y + oy * (CooldownCursorDB.scale or defaults.scale))
end

----------------------------------------------------
-- Apply settings and refresh active display
----------------------------------------------------
function CooldownCursor:UpdateDisplay()

  -- Show/hide icon
  icon.icon:SetShown(not CooldownCursorDB.iconHide)

  icon.icon:SetAlpha(
    PercentToAlpha(CooldownCursorDB.iconAlpha or defaults.iconAlpha)
  )

  -- Check for OmniCC presence
  local omniCC = self:IsOmniCCLoaded()
  if icon.cooldownText and not omniCC then
    -- Set Cooldown text font and color
    icon.cooldownText:SetFont(CooldownCursorDB.cooldownTextFontPath or
      defaults.cooldownTextFontPath,
      CooldownCursorDB.cooldownTextSize or defaults.cooldownTextSize,
      CooldownCursorDB.cooldownTextFontType or defaults.cooldownTextFontType
    )
    local cdr, cdg, cdb = HexToRGB(
    CooldownCursorDB.cooldownTextColor or defaults.cooldownTextColor)
    local cdAlpha = PercentToAlpha(CooldownCursorDB.cooldownTextAlpha or
      defaults.cooldownTextAlpha)
    icon.cooldownText:SetTextColor(cdr, cdg, cdb, cdAlpha)

    -- Set Cooldown Text anchor position
    local anchorPoint =
      CD_TEXT_ANCHOR_POINTS[string.upper(CooldownCursorDB.cooldownTextAnchor)]
        or CD_TEXT_ANCHOR_POINTS[string.upper(defaults.cooldownTextAnchor)]
    icon.cooldownText:ClearAllPoints()
    icon.cooldownText:SetPoint(
      anchorPoint.point,
      icon,
      anchorPoint.point,
      anchorPoint.x,
      anchorPoint.y
    )
  end

  if icon.text then
    -- Set Spell Text font and color
    icon.text:SetFont(CooldownCursorDB.spellTextFontPath or
      defaults.spellTextFontPath,
      CooldownCursorDB.spellTextSize or defaults.spellTextSize,
      CooldownCursorDB.spellTextFontType or defaults.spellTextFontType
    )

    local textr, textg, textb = HexToRGB(
      CooldownCursorDB.spellTextColor or defaults.spellTextColor)
    local textAlpha = PercentToAlpha(CooldownCursorDB.spellTextAlpha or
      defaults.spellTextAlpha)
    icon.text:SetTextColor(textr, textg, textb, textAlpha)
  end

  -- Set Spell Text anchor position
  local anchorPoint =
    SPELL_TEXT_ANCHOR_POINTS[string.upper(CooldownCursorDB.spellTextAnchor)]
      or SPELL_TEXT_ANCHOR_POINTS[string.upper(defaults.spellTextAnchor)]
  icon.text:ClearAllPoints()
  icon.text:SetPoint(
    anchorPoint.point,
    icon,
    anchorPoint.relativeTo,
    anchorPoint.x,
    anchorPoint.y
  )

  -- Set icon size and scale
  -- Don't scale with icon.icon:SetScale() as it messes with cursor position calculations
  icon:SetSize(CooldownCursorDB.iconSize * (CooldownCursorDB.scale or defaults.scale),
    CooldownCursorDB.iconSize * (CooldownCursorDB.scale or defaults.scale))

  -- Set all other scale settings
  icon.text:SetScale(CooldownCursorDB.scale or defaults.scale)
  icon.cooldown:SetScale(CooldownCursorDB.scale or defaults.scale)

  -- Hide countdown numbers when enabled
  icon.cooldown:SetHideCountdownNumbers(
    CooldownCursorDB.hideCooldownNumbers
  )

  -- Show/hide cooldown swipe
  icon.cooldown:SetDrawSwipe(
    CooldownCursorDB.showCooldownSwipe
  )

  -- Refresh active live spell name
  if icon:IsShown() and activeSpellID then
    local info = C_Spell.GetSpellInfo(activeSpellID)
    if CooldownCursorDB.showSpellNames and info.name then
      icon.text:SetText(info.name)
      icon.text:Show()
    else
      icon.text:Hide()
    end
  end

  -- Masque re-skin icon changes
  if MasqueGroup then
    MasqueGroup:ReSkin()
    if CooldownCursorDB.iconHide then
      icon.icon:SetAlpha(0)
    end
  end
end

----------------------------------------------------
-- Internal hide helper
----------------------------------------------------
local function HideIconNow()
  if previewTicker then
    previewTicker:Cancel()
    previewTicker = nil
  end
  previewActive = false

  if CooldownCursorDB.fadeOutDuration == 0 then
    icon:SetScript("OnUpdate", nil)
    icon.cooldown:Clear()
    icon.text:Hide()
  end

  lastSpellId = nil
  if hideTimer then
    hideTimer:Cancel()
    hideTimer = nil
  end
  activeSpellID, activeStartTime, activeDuration = nil, nil, nil
  if CooldownCursorDB.fadeOutDuration == 0 then
    icon:Hide()
    icon.icon:SetAlpha(
      PercentToAlpha(CooldownCursorDB.iconAlpha or defaults.iconAlpha)
    )
  else
    icon.fadeOut:Stop()
    fadeOut:SetDuration(tonumber(CooldownCursorDB.fadeOutDuration) or 0)
    icon.icon:SetAlpha(
      PercentToAlpha(CooldownCursorDB.iconAlpha or defaults.iconAlpha)
    )
    icon.fadeOut:Play()
  end

end

----------------------------------------------------
-- Scheduled Hide timer
----------------------------------------------------
local function ScheduleHideTimer()
  if not activeSpellID or not activeStartTime or not activeDuration then return end

  if hideTimer then
    hideTimer:Cancel()
    hideTimer = nil
  end

  local timeLeft = (activeStartTime + activeDuration) - GetTime()
  if timeLeft <= 0 then
    if lastSpellId == activeSpellID then
      HideIconNow()
    else
      activeSpellID, activeStartTime, activeDuration = nil, nil, nil
    end
    return
  end

  local hideDelay = math.min(timeLeft, CooldownCursorDB.hideAfter)

  hideTimer = C_Timer.NewTimer(hideDelay, function()
    if lastSpellId == activeSpellID then
      HideIconNow()
    end
  end)
end

----------------------------------------------------
-- Settings API
----------------------------------------------------

-- Get addon version from metadata
function CooldownCursor:GetVersion()
  return C_AddOns.GetAddOnMetadata(addonName, "Version")
end

-- Get addon version from metadata
function CooldownCursor:GetAuthor()
  return C_AddOns.GetAddOnMetadata(addonName, "Author")
end

-- Get addon notes from metadata
function CooldownCursor:GetNotes()
  return C_AddOns.GetAddOnMetadata(addonName, "Notes")
end

-- Get a value from the SavedVariables table
function CooldownCursor:GetDBValue(key)
  return CooldownCursorDB[key] or defaults[key]
end

-- Set a string value in the SavedVariables table
function CooldownCursor:SetDBString(key, value)
  CooldownCursorDB[key] = string.format("%s", value)
  self:UpdateDisplay()
end

-- Set a numeric value in the SavedVariables table
function CooldownCursor:SetDBNumber(key, value)
  CooldownCursorDB[key] = tonumber(value)
  self:UpdateDisplay()
end

-- Set a boolean value in the SavedVariables table
function CooldownCursor:SetDBBoolean(key, value)
  CooldownCursorDB[key] = value and true or false
  self:UpdateDisplay()
end

-- Set font names and paths in the SavedVariables table
function CooldownCursor:SetFontPath(key, value)
  CooldownCursorDB[key] = value
  CooldownCursorDB[key .. "Path"] = FontPath(
    CooldownCursorDB[key])
  self:UpdateDisplay()
end

-- Get list of all available fonts
function CooldownCursor:GetAllFonts()
  return FontNames()
end

-- Get list of valid font types
function CooldownCursor:GetValidFontTypes()
  return FONT_TYPES
end

-- Get list of valid anchor positions
function CooldownCursor:GetValidAnchorPositions()
  local positions = {}
  for k, v in pairs(ANCHOR_POSITION) do
    table.insert(positions, k)
  end
  return positions
end

-- Get list of valid spell text anchor positions
function CooldownCursor:GetValidSpellTextAnchorPositions()
  local positions = {}
  for k, v in pairs(SPELL_TEXT_ANCHOR_POINTS) do
    table.insert(positions, k)
  end
  return positions
end

-- Get list of valid cooldown text anchor positions
function CooldownCursor:GetValidCooldownTextAnchorPositions()
  local positions = {}  
  for k, v in pairs(CD_TEXT_ANCHOR_POINTS) do
    table.insert(positions, k)
  end
  return positions
end

-- Validation font type
function CooldownCursor:GetValidFontType(ftype)
  local fontType = string.upper(ftype)
  return FONT_TYPES[fontType] ~= nil
end

-- Validation anchor position
function CooldownCursor:GetValidAnchorPosition(pos)
  local anchor = string.upper(pos)
  return ANCHOR_POSITION[anchor] ~= nil
end

-- Validation anchor position
function CooldownCursor:GetValidSpellTextAnchorPosition(pos)
  local anchor = string.upper(pos)
  return SPELL_TEXT_ANCHOR_POINTS[anchor] ~= nil
end

-- Validation cooldown text anchor position
function CooldownCursor:GetValidCooldownTextAnchorPosition(pos)
  local anchor = string.upper(pos)
  return CD_TEXT_ANCHOR_POINTS[anchor] ~= nil
end

function CooldownCursor:SetHideAfter(seconds)
  CooldownCursorDB.hideAfter = tonumber(seconds) or defaults.hideAfter
  -- If icon currently visible, re-arm timer using new value
  if icon:IsShown() and lastSpellId then
    ScheduleHideTimer()
  end
end

function CooldownCursor:SetFadeOutDuration(seconds)
  CooldownCursorDB.fadeOutDuration = tonumber(seconds) or defaults.fadeOutDuration
  -- If icon currently visible, re-arm timer using new value 
  if icon:IsShown() and not previewActive then
    HideIconNow()
  end
end

function CooldownCursor:ResetSettings()
  HideIconNow()
  CooldownCursorDB = {}
  self:ApplyDefaults()
  self:UpdateDisplay()
end

----------------------------------------------------
-- Show icon + cooldown
----------------------------------------------------
local function ShowSpellIcon(spellID, startTime, duration)
  local spellInfo = C_Spell.GetSpellInfo(spellID)
  if not spellInfo or not spellInfo.iconID then return end

  local timeLeft = (startTime + duration) - GetTime()
  if timeLeft <= 1
      or duration < (CooldownCursorDB.minDuration or 1.5)
      or duration > (CooldownCursorDB.maxDuration or math.huge)
  then
    return
  end

  -- Apply settings before showing
  CooldownCursor:UpdateDisplay()

  -- Pop in animation
  if CooldownCursorDB.animation then
    icon:SetScale(1)
    icon.showAnim:Stop()
    icon.showAnim:Play()
  end

  icon.icon:SetTexture(spellInfo.iconID)
  icon.cooldown:SetCooldown(startTime, duration)

  activeSpellID = spellID
  activeStartTime = startTime
  activeDuration = duration

  if CooldownCursorDB.showSpellNames and spellInfo.name then
    icon.text:SetText(spellInfo.name)
    icon.text:Show()
  else
    icon.text:Hide()
  end

  icon:SetScript("OnUpdate", UpdateCooldownIconFrame)

  -- Stop any fade-out in progress so it doesn't hide us on finish
  icon.fadeOut:Stop()
  icon.icon:SetAlpha(
    PercentToAlpha(CooldownCursorDB.iconAlpha)
  )

  icon:Show()

  -- Always (re)schedule hide after showing
  ScheduleHideTimer()
end

----------------------------------------------------
-- Live Preview API
----------------------------------------------------
function CooldownCursor:Preview()
  local previewSpellID = 116 -- Frostbolt (safe)
  local previewDuration = 30

  if previewActive then
    previewActive = false
    if previewTicker then
      previewTicker:Cancel()
      previewTicker = nil
    end
    HideIconNow()
    return
  end

  previewActive = true

  -- Show once using your normal function/path
  ShowSpellIcon(previewSpellID, GetTime(), previewDuration)

  -- Loop: when it finishes, start again
  -- It loops because C_Timer.NewTicker() is the loop.
  if previewTicker then
    previewTicker:Cancel()
    previewTicker = nil
  end

  previewTicker = C_Timer.NewTicker(previewDuration, function()
    if not previewActive or not icon:IsShown() then return end
    icon.cooldown:SetCooldown(GetTime(), previewDuration)
  end)
end

----------------------------------------------------
-- Event handler
----------------------------------------------------
CooldownCursor:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then return end
    self:ApplyDefaults()
    self:UpdateDisplay()
    self:UnregisterEvent("ADDON_LOADED")
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
    return
  end

  if event == "UNIT_SPELLCAST_FAILED" then
    if CooldownCursorDB.showWhen == SHOW_WHEN_STATE.NON_COMBAT and inCombat then
      return
    end

    if CooldownCursorDB.showWhen == SHOW_WHEN_STATE.COMBAT and not inCombat then
      return
    end

    if CooldownCursorDB.hideWhileMounted and IsMounted() then
      return
    end

    local unit, _, spellID = ...
    if unit ~= "player" or not spellID then return end

    local cd = C_Spell.GetSpellCooldown(spellID)
    if not cd or not cd.startTime or not cd.duration then return end

    -- Different spell overrides current display immediately
    if lastSpellId and lastSpellId ~= spellID then
       if not cd.duration or cd.duration <= 1 then
        -- This stops other failed spells e.g out of range from hiding the
        -- correct cooldown icons when active.
        -- TODO:
        -- This will not work in midnight.
        -- Investigate using cd.isOnGCD and C_Spell.IsSpellInRange in midnight 
        -- or similar if needed.
        return
      end
      HideIconNow()
    end

    lastSpellId = spellID
    ShowSpellIcon(spellID, cd.startTime, cd.duration)
  end
end)

----------------------------------------------------
-- Register events
----------------------------------------------------
CooldownCursor:RegisterEvent("ADDON_LOADED")
CooldownCursor:RegisterEvent("UNIT_SPELLCAST_FAILED")
CooldownCursor:RegisterEvent("PLAYER_REGEN_DISABLED")
CooldownCursor:RegisterEvent("PLAYER_REGEN_ENABLED")
