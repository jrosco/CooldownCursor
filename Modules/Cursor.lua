----------------------------------------------------
-- CooldownCursor: Cursor Module
-- Cursor tracking, positioning, anchoring,
-- UI panel tracking
----------------------------------------------------
local _, addonTable = ...

local C = addonTable.Constants
local defaults = addonTable.Defaults
local State = addonTable.State
local Internal = addonTable.Internal

local POSITION_MODE = C.POSITION_MODE

----------------------------------------------------
-- Anchor Positioning
----------------------------------------------------
local FLIP_X = {
  LEFT = "RIGHT", RIGHT = "LEFT",
  TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT",
  BOTTOMLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "BOTTOMLEFT",
  TOP = "TOP", BOTTOM = "BOTTOM", CENTER = "CENTER",
}
local FLIP_Y = {
  TOP = "BOTTOM", BOTTOM = "TOP",
  TOPLEFT = "BOTTOMLEFT", TOPRIGHT = "BOTTOMRIGHT",
  BOTTOMLEFT = "TOPLEFT", BOTTOMRIGHT = "TOPRIGHT",
  LEFT = "LEFT", RIGHT = "RIGHT", CENTER = "CENTER",
}

local function FlipAnchorX(anchor)
  return FLIP_X[anchor] or anchor
end

local function FlipAnchorY(anchor)
  return FLIP_Y[anchor] or anchor
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

local function RefreshCachedSettings()
  State.cachedIconSize = CooldownCursorDB.global.iconSize or defaults.iconSize
  State.cachedAnchorPadding = CooldownCursorDB.global.anchorPadding or defaults.anchorPadding
  State.cachedAnchor = CooldownCursorDB.global.anchor or defaults.anchor
  State.cachedIconHide = CooldownCursorDB.global.iconHide or false
  State.cachedAnchorOX, State.cachedAnchorOY = AnchorOffsets(State.cachedAnchor, State.cachedIconSize, State.cachedAnchorPadding)
  State.cachedHalfSize = State.cachedIconSize / 2
end

----------------------------------------------------
-- Screen Anchor (Drag)
----------------------------------------------------
local anchorFrame

local function EnsureAnchorFrame()
  if anchorFrame then return anchorFrame end

  anchorFrame = CreateFrame("Frame", "CooldownCursorAnchor", UIParent)
  anchorFrame:SetSize(32, 32)
  anchorFrame:SetFrameStrata("DIALOG")
  anchorFrame:SetClampedToScreen(true)
  anchorFrame:EnableMouse(true)
  anchorFrame:SetMovable(true)
  anchorFrame:RegisterForDrag("LeftButton")
  anchorFrame:Hide()

  local tex = anchorFrame:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetColorTexture(0, 1, 0, 0.15)
  anchorFrame._bg = tex

  local border = anchorFrame:CreateTexture(nil, "BORDER")
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetColorTexture(0, 1, 0, 0.6)
  anchorFrame._border = border

  local label = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -2)
  label:SetText("CooldownCursor")
  anchorFrame._label = label

  anchorFrame:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then return end
    local mode = CooldownCursorDB.global.positionMode or defaults.positionMode
    if mode ~= POSITION_MODE.SCREEN then return end
    self:StartMoving()
  end)

  anchorFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local ux, uy = UIParent:GetCenter()
    local ax, ay = self:GetCenter()
    if ux and uy and ax and ay then
      CooldownCursorDB.global.offsetX = ax - ux
      CooldownCursorDB.global.offsetY = ay - uy
    end
    if Internal and Internal.UpdateIconPositions then
      Internal.UpdateIconPositions()
    end
  end)

  return anchorFrame
end

local function ApplyAnchorPosition()
  local anchor = EnsureAnchorFrame()
  local ox = CooldownCursorDB.global.offsetX or defaults.offsetX or 0
  local oy = CooldownCursorDB.global.offsetY or defaults.offsetY or 0
  anchor:ClearAllPoints()
  anchor:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
end

local function IsScreenMode()
  local mode = CooldownCursorDB.global.positionMode or defaults.positionMode
  return mode == POSITION_MODE.SCREEN
end

local function UpdateAnchorVisibility()
  if not IsScreenMode() then
    if anchorFrame then anchorFrame:Hide() end
    return
  end

  ApplyAnchorPosition()
  if State.previewActive or State.optionsOpen then
    anchorFrame:Show()
  else
    anchorFrame:Hide()
  end
end

local function ApplyScreenAnchors()
  if not IsScreenMode() then return end
  ApplyAnchorPosition()
  for _, iconData in ipairs(State.iconsByPriority) do
    local iconFrame = iconData.iconFrame
    if iconFrame then
      iconFrame:ClearAllPoints()
      iconFrame:SetPoint("CENTER", anchorFrame, "CENTER",
        iconFrame.stackOffsetX or 0,
        iconFrame.stackOffsetY or 0
      )
    end
  end
end

local function ApplyPositionMode()
  if IsScreenMode() then
    UpdateAnchorVisibility()
    for _, iconData in ipairs(State.iconsByPriority) do
      local iconFrame = iconData.iconFrame
      if iconFrame then
        iconFrame:SetScript("OnUpdate", nil)
      end
    end
    if Internal and Internal.UpdateIconPositions then
      Internal.UpdateIconPositions()
    end
  else
    if anchorFrame then anchorFrame:Hide() end
    for _, iconData in ipairs(State.iconsByPriority) do
      local iconFrame = iconData.iconFrame
      if iconFrame then
        iconFrame:SetScript("OnUpdate", addonTable.Internal.UpdateCooldownIconFrame)
      end
    end
  end
end

----------------------------------------------------
-- UI Panel tracking
----------------------------------------------------
local openPanels = {}
local cachedPanelOpen = false

local function RefreshPanelCache()
  cachedPanelOpen = (next(openPanels) ~= nil)
    or (GameMenuFrame and GameMenuFrame:IsShown())
    or (SettingsPanel and SettingsPanel:IsShown())
    or false
end

hooksecurefunc("ShowUIPanel", function(frame)
  if frame then
    openPanels[frame] = true
    RefreshPanelCache()
  end
end)

hooksecurefunc("HideUIPanel", function(frame)
  if frame then
    openPanels[frame] = nil
    RefreshPanelCache()
  end
end)

-- GameMenuFrame and SettingsPanel bypass ShowUIPanel/HideUIPanel,
-- so we hook their Show/Hide to keep the cache accurate.
local function HookPanelVisibility(panel)
  if not panel then return end
  panel:HookScript("OnShow", RefreshPanelCache)
  panel:HookScript("OnHide", RefreshPanelCache)
end
HookPanelVisibility(GameMenuFrame)
HookPanelVisibility(SettingsPanel)

local function IsAnyPanelOpen()
  return cachedPanelOpen
end

----------------------------------------------------
-- Cursor tracking and positioning (OnUpdate)
----------------------------------------------------
local function UpdateCooldownIconFrame(self)
  if IsAnyPanelOpen() and not State.previewActive then
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -100, -100) -- Move off-screen
    return
  end

  local cursorX, cursorY = GetCursorPosition()

  -- Convert cursor position to UI coordinates (using cached metrics)
  local x = cursorX / State.cachedUIScale
  local y = cursorY / State.cachedUIScale
  local half = State.cachedHalfSize

  -- Use pre-computed base offset from anchor
  local ox, oy = State.cachedAnchorOX, State.cachedAnchorOY

  -- Add stack offset (this positions icons relative to each other)
  ox = ox + (self.stackOffsetX or 0)
  oy = oy + (self.stackOffsetY or 0)

  local targetX = x + ox
  local targetY = y + oy

  -- Check if it would go off-screen
  local offLeft = (targetX - half) < 0
  local offRight = (targetX + half) > State.cachedScreenW
  local offBottom = (targetY - half) < 0
  local offTop = (targetY + half) > State.cachedScreenH

  -- Flip anchor if needed
  local flipped = State.cachedAnchor
  if offLeft or offRight then
    flipped = FlipAnchorX(flipped)
  end
  if offBottom or offTop then
    flipped = FlipAnchorY(flipped)
  end

  -- Recalculate if flipped
  if flipped ~= State.cachedAnchor then
    ox, oy = AnchorOffsets(flipped, State.cachedIconSize, State.cachedAnchorPadding)
    ox = ox + (self.stackOffsetX or 0)
    oy = oy + (self.stackOffsetY or 0)
    targetX = x + ox
    targetY = y + oy
  end

  -- Only update position if it actually changed (avoids redundant layout invalidation)
  if self._lastX ~= targetX or self._lastY ~= targetY then
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", targetX, targetY)
    self._lastX = targetX
    self._lastY = targetY
  end
end

----------------------------------------------------
-- Export Internal functions
----------------------------------------------------
addonTable.Internal.UpdateCooldownIconFrame = UpdateCooldownIconFrame
addonTable.Internal.RefreshCachedSettings = RefreshCachedSettings
addonTable.Internal.UpdateAnchorVisibility = UpdateAnchorVisibility
addonTable.Internal.ApplyScreenAnchors = ApplyScreenAnchors
addonTable.Internal.ApplyPositionMode = ApplyPositionMode

addonTable.Modules.Cursor = {}
