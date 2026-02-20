----------------------------------------------------
-- CooldownCursor: Anchor Module
-- Screen anchor positioning, drag handling,
-- position modes
----------------------------------------------------
local _, addonTable = ...

local C = addonTable.Constants
local defaults = addonTable.Defaults
local State = addonTable.State
local Internal = addonTable.Internal

local POSITION_MODE = C.POSITION_MODE

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
    local updateFn = Internal.UpdateCooldownIconFrame
    for _, iconData in ipairs(State.iconsByPriority) do
      local iconFrame = iconData.iconFrame
      if iconFrame then
        iconFrame:SetScript("OnUpdate", updateFn)
      end
    end
  end
end

----------------------------------------------------
-- Export Internal functions
----------------------------------------------------
addonTable.Internal.UpdateAnchorVisibility = UpdateAnchorVisibility
addonTable.Internal.ApplyScreenAnchors = ApplyScreenAnchors
addonTable.Internal.ApplyPositionMode = ApplyPositionMode

addonTable.Modules.Anchor = {}
