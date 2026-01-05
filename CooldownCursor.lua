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
local inCombat = false

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

----------------------------------------------------
-- Live Preview state
----------------------------------------------------
local previewActive = false
local previewTicker = nil

----------------------------------------------------
-- Defaults / SavedVariables
----------------------------------------------------
local defaults = {
  offsetX = 0,
  offsetY = 0,
  iconSize = 48,
  showSpellNames = false,
  hideCooldownNumbers = false,
  showCooldownSwipe = false,
  hideAfter = 3,
  animation = false,
  minDuration = 1.5,
  maxDuration = 600,
  fadeOutDuration = 0,
  showWhen = SHOW_WHEN_STATE.ALWAYS, -- 0=always, 1=in-combat, 2=out-of-combat
  anchor = ANCHOR_POSITION.TOPRIGHT,
  anchorPadding = 2, -- distance from cursor
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
-- Icon frame
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

icon.text = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
icon.text:SetPoint("BOTTOM", icon, "TOP", 0, 4)
icon.text:Hide()

----------------------------------------------------
-- Show animation (scale pop)
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
-- Fade out icon animation
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
  icon:SetAlpha(1) -- reset for next show
end)

----------------------------------------------------
-- Masque support
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
-- Cursor tracking and positioning
----------------------------------------------------
local function UpdateCooldownIconFrame(self)
  local scale = UIParent:GetEffectiveScale()
  local cursorX, cursorY = GetCursorPosition()

  local x = cursorX / scale
  local y = cursorY / scale

  local size = CooldownCursorDB.iconSize or 48
  local pad  = CooldownCursorDB.anchorPadding or 8
  local anchor = CooldownCursorDB.anchor or "TOP"

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
  self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + ox, y + oy)
end


----------------------------------------------------
-- Apply settings and refresh active display
----------------------------------------------------
function CooldownCursor:UpdateDisplay()
  -- Set icon size
  icon:SetSize(CooldownCursorDB.iconSize, CooldownCursorDB.iconSize)

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
  else
    icon.text:Hide()
  end

  if icon:IsShown() then
    UpdateCooldownIconFrame(self)
  end

  -- Masque re-skin icon changes
  if MasqueGroup then
    MasqueGroup:ReSkin()
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
  activeSpellID = nil
  if CooldownCursorDB.fadeOutDuration == 0 then
    icon:Hide()
    icon:SetAlpha(1)
  else
    icon.fadeOut:Stop()
    fadeOut:SetDuration(tonumber(CooldownCursorDB.fadeOutDuration) or 0)
    icon:SetAlpha(1)
    icon.fadeOut:Play()
  end
end

----------------------------------------------------
-- Scheduled Hide timer
----------------------------------------------------
local function ScheduleHideTimer()
  if not activeSpellID then return end

  if hideTimer then
    hideTimer:Cancel()
    hideTimer = nil
  end

  -- Use fixed hideAfter duration (Midnight-safe)
  local hideDelay = CooldownCursorDB.hideAfter or defaults.hideAfter

  hideTimer = C_Timer.NewTimer(hideDelay, function()
    if lastSpellId == activeSpellID then
      HideIconNow()
    end
  end)
end

----------------------------------------------------
-- Settings API
----------------------------------------------------
function CooldownCursor:SetIconSize(size)
  CooldownCursorDB.iconSize = tonumber(size) or defaults.iconSize
  self:UpdateDisplay()
end

function CooldownCursor:SetShowSpellNames(enabled)
  CooldownCursorDB.showSpellNames = enabled
  self:UpdateDisplay()
end

function CooldownCursor:SetHideCooldownNumbers(enabled)
  CooldownCursorDB.hideCooldownNumbers = enabled
  self:UpdateDisplay()
end

function CooldownCursor:SetShowCooldownSwipe(enabled)
  CooldownCursorDB.showCooldownSwipe = enabled
  self:UpdateDisplay()
end

function CooldownCursor:SetAnchor(anchor)
  CooldownCursorDB.anchor = string.upper(anchor) or defaults.anchor
  self:UpdateDisplay()
end

function CooldownCursor:SetMinDuration(seconds)
  CooldownCursorDB.minDuration = tonumber(seconds) or defaults.minDuration
end

function CooldownCursor:SetMaxDuration(seconds)
  CooldownCursorDB.maxDuration = tonumber(seconds) or defaults.maxDuration
end

function CooldownCursor:SetHideAfter(seconds)
  CooldownCursorDB.hideAfter = tonumber(seconds) or defaults.hideAfter
  -- If icon currently visible, re-arm timer using new value
  if icon:IsShown() and lastSpellId then
    ScheduleHideTimer()
  end
end

function CooldownCursor:SetAnimation(enabled)
  CooldownCursorDB.animation = enabled
end

function CooldownCursor:SetFadeOutDuration(seconds)
  CooldownCursorDB.fadeOutDuration = tonumber(seconds) or defaults.fadeOutDuration
  -- If icon currently visible, re-arm timer using new value 
  if icon:IsShown() then
    HideIconNow()
  end
end

function CooldownCursor:SetShowWhen(state)
  CooldownCursorDB.showWhen = state
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

  if CooldownCursorDB.showSpellNames and spellInfo.name then
    icon.text:SetText(spellInfo.name)
    icon.text:Show()
  else
    icon.text:Hide()
  end

  icon:SetScript("OnUpdate", UpdateCooldownIconFrame)

  -- Stop any fade-out in progress so it doesn't hide us on finish
  icon.fadeOut:Stop()
  icon:SetAlpha(1)

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

    local unit, _, spellID = ...
    if unit ~= "player" or not spellID then return end

    local cd = C_Spell.GetSpellCooldown(spellID)
    local usable = C_Spell.IsSpellUsable(spellID)
    local inRange = C_Spell.IsSpellInRange(spellID)
    if usable == false or inRange == false then return end
    if not cd or not cd.startTime or not cd.duration or cd.isOnGCD then return end

    -- Different spell overrides current display immediately
    if lastSpellId and lastSpellId ~= spellID then
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
