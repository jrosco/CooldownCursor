----------------------------------------------------
-- CooldownCursor: Cursor Module
-- Cursor tracking, positioning, anchoring,
-- UI panel tracking
----------------------------------------------------
local _, addonTable = ...

local defaults = addonTable.Defaults
local State = addonTable.State

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

addonTable.Modules.Cursor = {}
