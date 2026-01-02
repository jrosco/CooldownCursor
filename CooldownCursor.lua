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
  maxDuration = 600
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
-- Apply visual settings
----------------------------------------------------
function CooldownCursor:ApplyVisualSettings()
  icon:SetSize(CooldownCursorDB.iconSize, CooldownCursorDB.iconSize)

  -- Hide countdown numbers when enabled
  icon.cooldown:SetHideCountdownNumbers(CooldownCursorDB.hideCooldownNumbers)

  icon.cooldown:SetDrawSwipe(CooldownCursorDB.showCooldownSwipe)

  -- Masque re-skin after icon changes
  if MasqueGroup then
    MasqueGroup:ReSkin()
  end
end

----------------------------------------------------
-- Internal hide helper
----------------------------------------------------
local function HideIconNow()
  icon:SetScript("OnUpdate", nil)
  icon.cooldown:Clear()
  icon:Hide()
  icon.text:Hide()

  lastSpellId = nil
  if hideTimer then
    hideTimer:Cancel()
    hideTimer = nil
  end
  activeSpellID, activeStartTime, activeDuration = nil, nil, nil
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
  CooldownCursorDB.iconSize = size
  self:ApplyVisualSettings()
end

function CooldownCursor:SetShowSpellNames(enabled)
  CooldownCursorDB.showSpellNames = enabled
end

-- TODO: Not working needs investigation
function CooldownCursor:SetHideCooldownNumbers(enabled)
  CooldownCursorDB.hideCooldownNumbers = enabled
  self:ApplyVisualSettings()
end

function CooldownCursor:SetShowCooldownSwipe(enabled)
  CooldownCursorDB.showCooldownSwipe = enabled
  self:ApplyVisualSettings()
end

function CooldownCursor:SetOffset(x, y)
  CooldownCursorDB.offsetX = x
  CooldownCursorDB.offsetY = y
end

function CooldownCursor:SetMinDuration(seconds)
  CooldownCursorDB.minDuration = seconds
end

function CooldownCursor:SetMaxDuration(seconds)
  CooldownCursorDB.maxDuration = seconds
end

function CooldownCursor:SetHideAfter(seconds)
  CooldownCursorDB.hideAfter = seconds
  -- If icon currently visible, re-arm timer using new value
  if icon:IsShown() and lastSpellId then
    ScheduleHideTimer()
  end
end

function CooldownCursor:SetAnimation(enabled)
  CooldownCursorDB.animation = enabled
end

function CooldownCursor:ResetSettings()
  HideIconNow()
  CooldownCursorDB = {}
  self:ApplyDefaults()
  self:ApplyVisualSettings()
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
  CooldownCursor:ApplyVisualSettings()

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
  icon:Show()

  -- Always (re)schedule hide after showing
  ScheduleHideTimer()
end

----------------------------------------------------
-- Event handler
----------------------------------------------------
CooldownCursor:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then return end
    self:ApplyDefaults()
    self:ApplyVisualSettings()
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
