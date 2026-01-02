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
icon:SetSize(
  CooldownCursorDB and CooldownCursorDB.iconSize or defaults.iconSize,
  CooldownCursorDB and CooldownCursorDB.iconSize or defaults.iconSize
)
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
-- Cursor follow
----------------------------------------------------
local function UpdateCooldownIconFrame(self)
  local scale = UIParent:GetEffectiveScale()
  local x, y = GetCursorPosition()
  self:SetPoint(
    "CENTER",
    UIParent,
    "BOTTOMLEFT",
    (x / scale) + CooldownCursorDB.offsetX,
    (y / scale) + CooldownCursorDB.offsetY
  )
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

  -- Masque re-skin after active live icon changes
  if MasqueGroup and icon:IsShown() then
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
  activeSpellID, activeStartTime, activeDuration = nil, nil, nil
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

function CooldownCursor:SetOffset(x, y)
  CooldownCursorDB.offsetX = tonumber(x) or defaults.offsetX
  CooldownCursorDB.offsetY = tonumber(y) or defaults.offsetY
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

  local unit, _, spellID = ...
  if unit ~= "player" or not spellID then return end

  local cd = C_Spell.GetSpellCooldown(spellID)
  if not cd or not cd.startTime or not cd.duration then return end

  -- Different spell overrides current display immediately
  if lastSpellId and lastSpellId ~= spellID then
    HideIconNow()
  end

  lastSpellId = spellID
  ShowSpellIcon(spellID, cd.startTime, cd.duration)
end)

----------------------------------------------------
-- Register events
----------------------------------------------------
CooldownCursor:RegisterEvent("ADDON_LOADED")
CooldownCursor:RegisterEvent("UNIT_SPELLCAST_FAILED")
