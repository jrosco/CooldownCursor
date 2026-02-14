----------------------------------------------------
-- CooldownCursor Addon
----------------------------------------------------
local addonName, addonTable = ...
local CooldownCursor = CreateFrame("Frame")
addonTable.Frame = CooldownCursor

----------------------------------------------------
-- Module System (Metatable Delegation)
-- Modules register in addonTable.Modules and their
-- methods become available on CooldownCursor
----------------------------------------------------
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
-- Runtime state
----------------------------------------------------
local lastSpellId = nil
local hideTimer = nil
local activeSpellID = nil
local inCombat = false
local fontsTable = {}
local previewMouseMode = true
local activeProcSpells = {}
local procCapableSpells = {}

-- Cached known-spell lookup (invalidated on spec change)
local knownSpellCache = {}

local function IsSpellKnownCached(spellID)
  local cached = knownSpellCache[spellID]
  if cached == nil then
    cached = C_SpellBook.IsSpellKnown(spellID)
    knownSpellCache[spellID] = cached
  end
  return cached
end

-- Cached screen metrics (refreshed on scale/resolution changes)
local cachedUIScale = 1
local cachedScreenW = 0
local cachedScreenH = 0

local function RefreshScreenMetrics()
  cachedUIScale = UIParent:GetEffectiveScale()
  cachedScreenW = UIParent:GetWidth()
  cachedScreenH = UIParent:GetHeight()
end

-- Cached OnUpdate settings (refreshed in UpdateDisplay / RefreshCachedSettings)
local cachedIconSize = nil
local cachedAnchorPadding = nil
local cachedAnchor = nil
local cachedIconHide = false
local cachedAnchorOX = 0
local cachedAnchorOY = 0
local cachedHalfSize = 0

-- Reusable buffer for ApplyShowBehavior (avoids table alloc per call)
local toRemoveBuffer = {}

-- Multi-icon state
local iconPool = {}
local activeIcons = {}
local iconsByPriority = {}
local nextIconID = 1

local SHOW_WHEN_STATE = {
  ALWAYS = 0,
  COMBAT = 1,
  NON_COMBAT = 2,
}

local SHOW_BEHAVIOR = {
  ON_COOLDOWN = 0,     -- Show on cooldown, remove icon when spell comes off cooldown
  OFF_COOLDOWN = 1,    -- Show only when spell is ready (off cooldown)
  AUTO_HIDE_AFTER = 3, -- Show on cooldown, auto-hide after X seconds (default, original behaviour)
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

local FRAME_STRATA = {
  BACKGROUND = "BACKGROUND",
  LOW = "LOW",
  MEDIUM = "MEDIUM",
  HIGH = "HIGH",
  DIALOG = "DIALOG",
  TOOLTIP = "TOOLTIP",
}

local CD_TEXT_ANCHOR_POINTS = {
  TOP = { point = "TOP", x = 0, y = -4 },
  BOTTOM = { point = "BOTTOM", x = 0, y = 4 },
  LEFT = { point = "LEFT", x = 4, y = 0 },
  RIGHT = { point = "RIGHT", x = -4, y = 0 },
  CENTER = { point = "CENTER", x = 0, y = 0 },
  TOPLEFT = { point = "TOPLEFT", x = 4, y = -4 },
  TOPRIGHT = { point = "TOPRIGHT", x = -4, y = -4 },
  BOTTOMLEFT = { point = "BOTTOMLEFT", x = 4, y = 4 },
  BOTTOMRIGHT = { point = "BOTTOMRIGHT", x = -4, y = 4 },
}

local SPELL_TEXT_ANCHOR_POINTS = {
  BOTTOM = { point = "TOP", relativeTo = "BOTTOM", x = 0, y = -4 },
  TOP = { point = "BOTTOM", relativeTo = "TOP", x = 0, y = 4 },
}

local CHARGE_TEXT_ANCHOR_POINTS = {
  TOP = { point = "TOP", x = 0, y = -2 },
  BOTTOM = { point = "BOTTOM", x = 0, y = 2 },
  LEFT = { point = "LEFT", x = 2, y = 0 },
  RIGHT = { point = "RIGHT", x = -2, y = 0 },
  CENTER = { point = "CENTER", x = 0, y = 0 },
  TOPLEFT = { point = "TOPLEFT", x = 2, y = -2 },
  TOPRIGHT = { point = "TOPRIGHT", x = -2, y = -2 },
  BOTTOMLEFT = { point = "BOTTOMLEFT", x = 2, y = 2 },
  BOTTOMRIGHT = { point = "BOTTOMRIGHT", x = -2, y = 2 },
}

local FONT_TYPES = {
  NONE = nil,
  OUTLINE = "OUTLINE",
  THICKOUTLINE = "THICKOUTLINE",
  MONOCHROME = "MONOCHROME",
  MONOCHROMEOUTLINE = "MONOCHROMEOUTLINE",
  MONOCHROMETHICKOUTLINE = "MONOCHROMETHICKOUTLINE",
}

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

-- Multi-icon constants
local SORT_ORDER = {
  ALPHABETICAL = "ALPHABETICAL",
  PRIORITY = "PRIORITY",
  TIME_ADDED = "TIME_ADDED",
}

local STACK_DIRECTION = {
  SINGLE = "SINGLE",
  VERTICAL = "VERTICAL",
  HORIZONTAL = "HORIZONTAL",
  RADIUS = "RADIUS",
}

local STACK_GROWTH = {
  DOWN = "DOWN",
  UP = "UP",
  LEFT = "LEFT",
  RIGHT = "RIGHT",
  CLOCKWISE = "CLOCKWISE",
  COUNTERCLOCKWISE = "COUNTERCLOCKWISE",
}

-----------------------------------------------------
--- Proc Overlay/Outline Atlas Settings
-----------------------------------------------------
local PROC_OVERLAY_ATLAS_SETTINGS = {
  ["ArtifactsFX-SpinningGlowys"] = { name = "Spinning Glowys", scale = 1.5 },
  ["AftLevelup-WhiteStarBurst"] = { name = "Star Burst", scale = 2 },
  ["ArtifactsFX-Whirls"] = { name = "Whirls", scale = 1.4 },
}

local PROC_OUTLINE_ATLAS_SETTINGS = {
  ["combattimeline-fx-queued"] = { name = "Square Neon Glow", scale = 1.6 },
  ["combattimeline-fx-deadlyglow-base"] = { name = "Square Glow", scale = 1.6 },
  ["talents-node-choiceflyout-square-ghost"] = { name = "Square Dotted", scale = 1.2 },
}

function CooldownCursor:GetProcOverlayAtlasSettings()
  return PROC_OVERLAY_ATLAS_SETTINGS
end

function CooldownCursor:GetProcOutlineAtlasSettings()
  return PROC_OUTLINE_ATLAS_SETTINGS
end

local function IsProcOverlayEnabled()
  local atlas = CooldownCursorDB.global.procOverlayAtlas or defaults.procOverlayAtlas
  return atlas and atlas ~= "" and atlas ~= "none"
end

local function IsProcOutlineEnabled()
  local atlas = CooldownCursorDB.global.procOutlineAtlas or defaults.procOutlineAtlas
  return atlas and atlas ~= "" and atlas ~= "none"
end

----------------------------------------------------
-- Live Preview state
----------------------------------------------------
local previewActive = false
local previewTicker = nil
local previewIndicator = nil -- Banner frame to show "PREVIEW MODE"

----------------------------------------------------
-- Defaults / SavedVariables
----------------------------------------------------
local spellRules = {
  settings = {
    disableRules = false,
  },
  rules = {}
}

local defaults = {
  enabled = true,
  offsetX = 0,
  offsetY = 0,
  scale = 1,
  iconSize = 48,
  iconAlpha = 100,
  showProcs = false,
  showCharges = true,
  procOverlayAtlas = "none",
  procOutlineAtlas = "combattimeline-fx-queued",
  procOverlayColor = "#FFFFFF",
  procOutlineColor = "#FFFFFF",
  iconHide = false,
  showSpellNames = false,
  hideCooldownNumbers = false,
  showCooldownSwipe = true,
  hideAfter = 30,
  animation = false,
  fadeOutDuration = 0,
  showWhen = SHOW_WHEN_STATE.COMBAT,
  showBehavior = SHOW_BEHAVIOR.ON_COOLDOWN,
  hideWhileMounted = false,
  anchor = ANCHOR_POSITION.TOPRIGHT,
  anchorPadding = 2,
  spellTextFont = "Friz Quadrata TT",
  spellTextFontPath = DEFAULT_SYSTEM_FONTS["Friz Quadrata TT"],
  spellTextSize = 14,
  spellTextFontType = FONT_TYPES.OUTLINE,
  spellTextColor = "#FFD100",
  spellTextAnchor = "TOP",
  spellTextAlpha = 100,
  cooldownTextSize = 20,
  cooldownTextFont = "Friz Quadrata TT",
  cooldownTextFontPath = DEFAULT_SYSTEM_FONTS["Friz Quadrata TT"],
  cooldownTextFontType = FONT_TYPES.OUTLINE,
  cooldownTextColor = "#FFFFFF",
  cooldownTextAnchor = CD_TEXT_ANCHOR_POINTS.CENTER.point,
  cooldownTextAlpha = 100,
  chargeTextSize = 12,
  chargeTextFont = "Friz Quadrata TT",
  chargeTextFontPath = DEFAULT_SYSTEM_FONTS["Friz Quadrata TT"],
  chargeTextFontType = FONT_TYPES.OUTLINE,
  chargeTextColor = "#FFFFFF",
  chargeTextAnchor = CHARGE_TEXT_ANCHOR_POINTS.BOTTOMRIGHT.point,
  chargeTextAlpha = 100,
  frameStrata = FRAME_STRATA.HIGH,
  spellRules = spellRules,

  -- Multiple Icon Display Settings
  maxIcons = 10,
  stackDirection = STACK_DIRECTION.HORIZONTAL,
  stackSpacing = 4,
  sortOrder = SORT_ORDER.PRIORITY,
  stackGrowth = STACK_GROWTH.RIGHT,
  iconPoolSize = 10,
  radiusDistance = 80,
  radiusStartAngle = 0,
}

function CooldownCursor:ApplyDefaults()
  CooldownCursorDB = CooldownCursorDB or {}
  CooldownCursorDB.global = CooldownCursorDB.global or {}
  for k, v in pairs(defaults) do
    if k == "spellRules" then
      if CooldownCursorDB.spellRules == nil then
        CooldownCursorDB.spellRules = v
      end
    else
      if CooldownCursorDB.global[k] == nil then
        CooldownCursorDB.global[k] = v
      end
    end
  end
  CooldownCursor:ApplyBreakingChangesAndSetReleaseNotes()
end

function CooldownCursor:ApplyBreakingChangesAndSetReleaseNotes()
  -- Use it to:
  -- 1. Apply any breaking changes to CooldownCursorDB (migrations)
  -- 2. Set release notes for display in Options UI

  -- Migrate old flags into _migrated table (must run first)
  if CooldownCursorDB._migrated == nil then
    CooldownCursorDB._migrated = {}
    if CooldownCursorDB._version then
      CooldownCursorDB._migrated.version = CooldownCursorDB._version
      CooldownCursorDB._version = nil
    end
    if CooldownCursorDB._migratedWhitelist then
      CooldownCursorDB._migrated.whitelist = CooldownCursorDB._migratedWhitelist
      CooldownCursorDB._migratedWhitelist = nil
    end
    if CooldownCursorDB._cleanedFlatRules then
      CooldownCursorDB._migrated.cleanedFlatRules = CooldownCursorDB._cleanedFlatRules
      CooldownCursorDB._cleanedFlatRules = nil
    end
  end

  -- Migrate top-level settings into .global subtable
  if not CooldownCursorDB._migrated.movedToGlobal then
    CooldownCursorDB.global = CooldownCursorDB.global or {}
    for k, v in pairs(CooldownCursorDB) do
      if k ~= "global" and k ~= "spellRules" and k ~= "_migrated" then
        CooldownCursorDB.global[k] = v
        CooldownCursorDB[k] = nil
      end
    end
    CooldownCursorDB._migrated.movedToGlobal = true
  end

  -- Initialize version if missing
  if not CooldownCursorDB._migrated.version then
    CooldownCursorDB._migrated.version = 0
  end

  -- ========================================
  -- BREAKING CHANGES (Migrations)
  -- ========================================
  -- Put code here that changes CooldownCursorDB values
  -- This runs every time, so use conditional checks

  local breakingChanges = {}
  local newFeatures = {}
  local fixes = {}
  local major = tonumber(self:GetMajorVersion())

  ----------------------------------------------------------------------------------
  -- migration from version 1 to 2 -------------------------------------------------
  if CooldownCursorDB._migrated.version < 2 then
    -- Run breaking changes here
    if CooldownCursorDB.global.showWhen == SHOW_WHEN_STATE.ALWAYS then
      CooldownCursorDB.global.showWhen = SHOW_WHEN_STATE.COMBAT
    end

    if CooldownCursorDB.global.anchor ~= ANCHOR_POSITION.TOPRIGHT then
      CooldownCursorDB.global.anchor = ANCHOR_POSITION.TOPRIGHT
    end
  end
  ----------------------------------------------------------------------------------

  ----------------------------------------------------------------------------------
  -- migration v2.1.0 - Remove whitelist setting -----------------------------------
  if not CooldownCursorDB._migrated.whitelist then
    -- Remove deprecated whitelist setting from spell rules
    if CooldownCursorDB.spellRules and CooldownCursorDB.spellRules.settings then
      CooldownCursorDB.spellRules.settings.whitelist = nil
    end
    CooldownCursorDB._migrated.whitelist = true
  end
  ----------------------------------------------------------------------------------

  ----------------------------------------------------------------------------------
  -- migration v2.2.0 - Migrate old flat spell rules to class-based format ---------
  -- Old format: rules[spellID] = {...}
  -- New format: rules[CLASS][spellID] = {...}
  -- This runs incrementally per character - only migrates spells the character knows
  if not CooldownCursorDB._migrated.cleanedFlatRules then
    local rules = CooldownCursorDB.spellRules and CooldownCursorDB.spellRules.rules
    if rules then
      local _, class = UnitClass("player")
      local migratedCount = 0
      local remainingCount = 0

      -- First pass: migrate spells this character knows to their class
      for key, ruleData in pairs(rules) do
        if type(key) == "number" then
          local spellID = key
          if C_SpellBook.IsSpellKnown(spellID) and class then
            -- This character knows this spell - migrate to class format
            if not rules[class] then
              rules[class] = {}
            end
            -- Only migrate if not already in class rules
            if not rules[class][spellID] then
              -- Separate old flat data into settings/metadata
              local settings = {
                enabled = ruleData.enabled,
                priority = ruleData.priority,
                iconSize = ruleData.iconSize,
                useGlobalIconSize = ruleData.useGlobalIconSize,
              }
              rules[class][spellID] = { settings = settings, metadata = {} }
            end

            -- Populate static spell metadata
            local rule = rules[class][spellID]
            local baseCooldownMS, _ = GetSpellBaseCooldown(spellID)
            local baseCooldown = baseCooldownMS and (baseCooldownMS / 1000) or 0
            local chargeInfo = C_Spell.GetSpellCharges(spellID)
            local info = C_Spell.GetSpellInfo(spellID)
            rule.metadata = rule.metadata or {}
            rule.metadata.baseCooldown = baseCooldown
            rule.metadata.hasCooldown = baseCooldown > 1.5
            rule.metadata.hasCharges = chargeInfo ~= nil
            rule.metadata.maxCharges = chargeInfo and chargeInfo.maxCharges or nil
            rule.metadata.isInstantCast = info and info.castTime == 0 or false
            rule.metadata.castTime = info and (info.castTime / 1000) or 0
            rule.metadata.hasRange = info and info.maxRange > 0 or false
            rule.metadata.maxRange = info and info.maxRange or 0

            rules[spellID] = nil -- Remove from old format
            migratedCount = migratedCount + 1
          else
            -- This character doesn't know this spell - leave for another alt
            remainingCount = remainingCount + 1
          end
        end
      end

      -- Only mark as done when no old-format rules remain
      if remainingCount == 0 then
        CooldownCursorDB._migrated.cleanedFlatRules = true
      end

      if migratedCount > 0 then
        print("|cff00ff00CooldownCursor:|r Migrated " ..
        migratedCount .. " spell rules to " .. (class or "unknown") .. " format.")
      end
    else
      -- No rules exist, mark as done
      CooldownCursorDB._migrated.cleanedFlatRules = true
    end
  end
  ----------------------------------------------------------------------------------

  CooldownCursorDB._migrated.version = major

  -- ========================================
  -- RELEASE NOTES (Display Only)
  -- ========================================
  -- These are just for showing users what changed
  -- No code execution, just messages
  -- Notes are organized by version (newest first)

  local _cleanedFlatRulesCheckMsg = CooldownCursorDB._migrated.cleanedFlatRules and "Your migration is marked cleaned" or
  "Your migration rules are pending cleanup"
  local releaseNotesByVersion = {
    ["2.2.0"] = {
      breakingChanges = {
        "Settings have been moved to a 'global' subtable in SavedVariables - existing settings are automatically migrated",
        "Spell rules are now saved per class - |cff00ff00you may need to|r |cffFFBB4A/reload|r |cff00ff00UI for alt characters|r",
        _cleanedFlatRulesCheckMsg,
      },
      newFeatures = {
        "Proc Spell Support: Show spell icons when procs are active",
        "Charge Spell Support: Show spell icons with charges when active",
        "Proc visual indicators with customizable overlay and border",
        "Class-based Spell Rules: Each class now has its own separate spell rules",
        "Spells not known to your current spec are automatically hidden",
      }
    },
    ["2.1.5"] = {
      newFeatures = {
        "Added 'Export Settings to Chat' button in Advanced > Utility for easy status sharing",
        "Added 'Share Configuration' feature to generate copyable settings string for sharing",
        "Added 'Reload UI' button in Advanced > Utility for quick interface reload",
      },
      fixes = {
        "Fixed icon size not persisting correctly after UI reload when using Masque",
        "Improved Masque integration with lazy registration for better performance",
        "Fixed 'Hide While Mounted' to actively hide existing icons instead of only preventing new ones",
      },
    },
    ["2.1.4"] = {
      fixes = {
        "Performance optimizations for smoother cursor icon tracking and reduced memory allocations",
        "Removed OmniCC support (no longer available in Midnight)",

      },
    },
    ["2.1.3"] = {
      fixes = {
        "Fixed spell icons not showing when 'Show When' is set to 'Out of Combat' or 'Always'",
        "Fixed combat state not updating immediately when changing 'Show When' setting",
        "Fixed addon not detecting combat state correctly on reload",
      },
    },
    ["2.1.2"] = {
      fixes = {
        "Minor bug fixes",
      },
    },
    ["2.1.0"] = {
      breakingChanges = {
        "Simplified Spell Rules: Removed whitelist/blacklist mode - now uses simple enable/disable per spell",
        "Spells must now be explicitly added to rules to show cooldowns",
      },
      newFeatures = {
        "Added Show Behavior modes: On Cooldown, Off Cooldown (Ready) - Experimental",
        "Added ability to completely disable the addon from Quick Settings",
        "Added spellbook dropdown for easy spell rule management",
        "Added priority display [number] in spell list for quick visibility",
        "Added primary icon indicator in RADIUS preview mode",
        "Preview mode now uses your spell rules instead of default spells",
        "Display Mode now auto-sets anchor and growth direction defaults",
        "Spell list now sorted by priority (higher first), then alphabetically",
      },
      fixes = {
        "Fixed icon arrangement when switching between Show Behavior modes",
        "Fixed alpha state restoration when switching to On Cooldown mode",
        "Smoother priority slider with debounced updates",
      },
    },
    ["2.0.4"] = {
      breakingChanges = {},
      newFeatures = {},
      fixes = {
        "Improved cooldown accuracy: all active icons now refresh when buffs/talents affect multiple cooldowns",
      },
    },
    ["2.0.3"] = {
      breakingChanges = {},
      newFeatures = {},
      fixes = {
        "Fixed Minor bug fixes",
      },
    },
    ["2.0.1"] = {
      breakingChanges = {},
      newFeatures = {},
      fixes = {
        "Fixed Masque skin/style when showing multiple icon display",
      },
    },
    ["2.0.0"] = {
      breakingChanges = {
        "Changed 'Show When' default from 'Always' to 'In Combat'",
        "Changed 'Anchor' default to 'Top Right'",
      },
      newFeatures = {
        "Added RADIUS, HORIZONTAL and VERTICAL display modes for multi-icon stacking",
        "Added HORIZONTAL and VERTICAL stack directions",
      },
      fixes = {
        "Fixed SPELL_UPDATE_COOLDOWN not triggering spells with CD Buff updates",
      },
    },
  }

  -- Helper to parse version string into comparable numbers
  local function ParseVersion(vStr)
    local major, minor, patch = vStr:match("^(%d+)%.(%d+)%.(%d+)$")
    if major then
      return tonumber(major) * 10000 + tonumber(minor) * 100 + tonumber(patch)
    end
    return 0
  end

  -- Sort versions (newest first)
  local sortedVersions = {}
  for version in pairs(releaseNotesByVersion) do
    table.insert(sortedVersions, version)
  end
  table.sort(sortedVersions, function(a, b)
    return ParseVersion(a) > ParseVersion(b)
  end)

  -- Store for Options.lua to display
  self.releaseNotes = {
    byVersion = releaseNotesByVersion,
    sortedVersions = sortedVersions,
  }
end

----------------------------------------------------
-- Icon frame creation
----------------------------------------------------
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
    table.insert(iconPool, iconFrame)
  end
end

local function GetIconFromPool()
  if #iconPool > 0 then
    return table.remove(iconPool, 1)
  end
  local newIcon = CreateIconFrame(nextIconID)
  nextIconID = nextIconID + 1
  return newIcon
end

function ReturnIconToPool(iconFrame)
  if not iconFrame then return end

  iconFrame:Hide()
  iconFrame:SetScript("OnUpdate", nil)
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

  table.insert(iconPool, iconFrame)
end

----------------------------------------------------
-- Masque support
----------------------------------------------------
local Masque = LibStub and LibStub("Masque", true)
local MasqueGroup = Masque and Masque:Group(addonName)
local registeredWithMasque = {}

-- Lazy registration: only add icons to Masque when they're actually used
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
--- LibSharedMedia support
----------------------------------------------------
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

----------------------------------------------------
-- Internal cursor positioning helper
----------------------------------------------------
-- Pre-built flip lookup tables (replaces string.find/gsub per frame)
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
  cachedIconSize = CooldownCursorDB.global.iconSize or defaults.iconSize
  cachedAnchorPadding = CooldownCursorDB.global.anchorPadding or defaults.anchorPadding
  cachedAnchor = CooldownCursorDB.global.anchor or defaults.anchor
  cachedIconHide = CooldownCursorDB.global.iconHide or false
  cachedAnchorOX, cachedAnchorOY = AnchorOffsets(cachedAnchor, cachedIconSize, cachedAnchorPadding)
  cachedHalfSize = cachedIconSize / 2
end

----------------------------------------------------
--- Get available fonts helper
----------------------------------------------------
local function FontNames()
  if #fontsTable > 0 then
    return fontsTable
  end

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
-- Generic table keys helper
----------------------------------------------------
local function GetTableKeys(tbl)
  local keys = {}
  for k in pairs(tbl) do
    table.insert(keys, k)
  end
  return keys
end

----------------------------------------------------
-- Generic validation helper
----------------------------------------------------
local function IsValidTableKey(tbl, key)
  if not key then return false end
  local upper = string.upper(key)
  return tbl[upper] ~= nil
end

----------------------------------------------------
--- Internal Color helper
--------------------------------------------------
local function HexToRGB(hex)
  hex = hex:gsub("#", "")
  if #hex ~= 6 then return 1, 1, 1 end
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
  if alpha > 1 then
    alpha = math.max(0, math.min(100, alpha)) / 100
  end
  return alpha
end

--------------------------------------------------
-- Internal Font Path helper
--------------------------------------------------
local function FontPath(fontName)
  local path = DEFAULT_SYSTEM_FONTS[tostring(fontName) or nil]
  if LSM and path == nil then
    path = LSM:Fetch("font", tostring(fontName))
  end
  return path
end

--------------------------------------------------
--- Internal Apply Fonts helper
--------------------------------------------------
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
-- Multi-Icon Stack Offset Calculation
----------------------------------------------------
local function GetRadiusOffset(index, totalIcons, growth)
  local radius = CooldownCursorDB.global.radiusDistance or defaults.radiusDistance
  local startAngle = CooldownCursorDB.global.radiusStartAngle or defaults.radiusStartAngle

  -- Calculate angle for this icon
  local angleStep = 360 / math.max(1, totalIcons)
  local angle = startAngle + (angleStep * index)

  -- Reverse direction for counterclockwise
  if growth == STACK_GROWTH.COUNTERCLOCKWISE then
    angle = startAngle - (angleStep * index)
  end

  -- Convert to radians
  local rad = math.rad(angle)

  -- Calculate position on circle
  local offsetX = math.cos(rad) * radius
  local offsetY = -math.sin(rad) * radius -- Negative because Y increases downward in WoW

  return offsetX, offsetY
end

local function GetLinearOffset(cumulativeOffset, direction, growth)
  if direction == STACK_DIRECTION.VERTICAL then
    if growth == STACK_GROWTH.DOWN then
      return 0, -cumulativeOffset
    else -- UP
      return 0, cumulativeOffset
    end
  else -- HORIZONTAL
    if growth == STACK_GROWTH.RIGHT then
      return cumulativeOffset, 0
    else -- LEFT
      return -cumulativeOffset, 0
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
-- Cursor tracking and positioning
----------------------------------------------------
local function UpdateCooldownIconFrame(self)
  if IsAnyPanelOpen() and not previewActive then
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -100, -100) -- Move off-screen
    return
  end

  local cursorX, cursorY = GetCursorPosition()

  -- Convert cursor position to UI coordinates (using cached metrics)
  local x = cursorX / cachedUIScale
  local y = cursorY / cachedUIScale
  local half = cachedHalfSize

  -- Use pre-computed base offset from anchor
  local ox, oy = cachedAnchorOX, cachedAnchorOY

  -- Add stack offset (this positions icons relative to each other)
  ox = ox + (self.stackOffsetX or 0)
  oy = oy + (self.stackOffsetY or 0)

  local targetX = x + ox
  local targetY = y + oy

  -- Check if it would go off-screen
  local offLeft = (targetX - half) < 0
  local offRight = (targetX + half) > cachedScreenW
  local offBottom = (targetY - half) < 0
  local offTop = (targetY + half) > cachedScreenH

  -- Flip anchor if needed
  local flipped = cachedAnchor
  if offLeft or offRight then
    flipped = FlipAnchorX(flipped)
  end
  if offBottom or offTop then
    flipped = FlipAnchorY(flipped)
  end

  -- Recalculate if flipped
  if flipped ~= cachedAnchor then
    ox, oy = AnchorOffsets(flipped, cachedIconSize, cachedAnchorPadding)
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
-- Apply settings and refresh active display
----------------------------------------------------
function CooldownCursor:UpdateDisplay(spellID)
  RefreshCachedSettings()
  if self:IsMultiIconEnabled() then
    for _, iconData in ipairs(iconsByPriority) do
      self:UpdateSingleIcon(iconData.iconFrame, iconData.spellID)
    end
    UpdateIconPositions()
  else
    if #iconsByPriority > 0 then
      local firstIcon = iconsByPriority[1].iconFrame
      firstIcon.stackOffsetX = 0
      firstIcon.stackOffsetY = 0
      self:UpdateSingleIcon(firstIcon, iconsByPriority[1].spellID)
    end
  end

  -- Apply Masque skin once after all icons are updated
  if MasqueGroup then
    MasqueGroup:ReSkin()
  end
end

function CooldownCursor:UpdateSingleIcon(icon, spellID)
  if not icon then return end

  icon.icon:SetShown(not CooldownCursorDB.global.iconHide)
  icon.icon:SetAlpha(PercentToAlpha(CooldownCursorDB.global.iconAlpha or defaults.iconAlpha))

  icon:SetFrameStrata(
    FRAME_STRATA[string.upper(CooldownCursorDB.global.frameStrata)] or
    FRAME_STRATA[string.upper(defaults.frameStrata)]
  )

  if icon.cooldownText then
    ApplyFonts(
      icon.cooldownText,
      CooldownCursorDB.global.cooldownTextFontPath or defaults.cooldownTextFontPath,
      CooldownCursorDB.global.cooldownTextSize or defaults.cooldownTextSize,
      CooldownCursorDB.global.cooldownTextFontType or defaults.cooldownTextFontType
    )

    local cdr, cdg, cdb = HexToRGB(CooldownCursorDB.global.cooldownTextColor or defaults.cooldownTextColor)
    local cdAlpha = PercentToAlpha(CooldownCursorDB.global.cooldownTextAlpha or defaults.cooldownTextAlpha)
    icon.cooldownText:SetTextColor(cdr, cdg, cdb, cdAlpha)

    local anchorPoint = CD_TEXT_ANCHOR_POINTS[string.upper(CooldownCursorDB.global.cooldownTextAnchor)]
        or CD_TEXT_ANCHOR_POINTS[string.upper(defaults.cooldownTextAnchor)]
    icon.cooldownText:ClearAllPoints()
    icon.cooldownText:SetPoint(anchorPoint.point, icon, anchorPoint.point, anchorPoint.x, anchorPoint.y)
  end

  if icon.text then
    ApplyFonts(
      icon.text,
      CooldownCursorDB.global.spellTextFontPath or defaults.spellTextFontPath,
      CooldownCursorDB.global.spellTextSize or defaults.spellTextSize,
      CooldownCursorDB.global.spellTextFontType or defaults.spellTextFontType
    )

    local textr, textg, textb = HexToRGB(CooldownCursorDB.global.spellTextColor or defaults.spellTextColor)
    local textAlpha = PercentToAlpha(CooldownCursorDB.global.spellTextAlpha or defaults.spellTextAlpha)
    icon.text:SetTextColor(textr, textg, textb, textAlpha)
  end

  if icon.chargeText then
    ApplyFonts(
      icon.chargeText,
      CooldownCursorDB.global.chargeTextFontPath or defaults.chargeTextFontPath,
      CooldownCursorDB.global.chargeTextSize or defaults.chargeTextSize,
      CooldownCursorDB.global.chargeTextFontType or defaults.chargeTextFontType
    )

    local chr, chg, chb = HexToRGB(CooldownCursorDB.global.chargeTextColor or defaults.chargeTextColor)
    local chAlpha = PercentToAlpha(CooldownCursorDB.global.chargeTextAlpha or defaults.chargeTextAlpha)
    icon.chargeText:SetTextColor(chr, chg, chb, chAlpha)

    local anchorPoint = CHARGE_TEXT_ANCHOR_POINTS
    [string.upper(CooldownCursorDB.global.chargeTextAnchor or defaults.chargeTextAnchor)]
    icon.chargeText:ClearAllPoints()
    icon.chargeText:SetPoint(anchorPoint.point, icon, anchorPoint.point, anchorPoint.x, anchorPoint.y)
  end

  if icon.procOverlay then
    local showProcs = CooldownCursorDB.global.showProcs ~= false
    local showOverlay = IsProcOverlayEnabled()
    local overlayAtlas = CooldownCursorDB.global.procOverlayAtlas or defaults.procOverlayAtlas
    if overlayAtlas and overlayAtlas ~= "" then
      icon.procOverlay:SetAtlas(overlayAtlas, true)
    end
    local orr, org, orb = HexToRGB(CooldownCursorDB.global.procOverlayColor or defaults.procOverlayColor)
    icon.procOverlay:SetVertexColor(orr, org, orb, 1)
    icon.procOverlay:SetShown(showProcs and showOverlay and (icon.procActive == true))
  end
  if icon.procOutline then
    local showProcs = CooldownCursorDB.global.showProcs ~= false
    local showOutline = IsProcOutlineEnabled()
    local outlineAtlas = CooldownCursorDB.global.procOutlineAtlas or defaults.procOutlineAtlas
    if outlineAtlas and outlineAtlas ~= "" then
      icon.procOutline:SetAtlas(outlineAtlas, true)
    end
    local otr, otg, otb = HexToRGB(CooldownCursorDB.global.procOutlineColor or defaults.procOutlineColor)
    icon.procOutline:SetVertexColor(otr, otg, otb, 1)
    icon.procOutline:SetShown(showProcs and showOutline and (icon.procActive == true))
  end

  local anchorPoint = SPELL_TEXT_ANCHOR_POINTS[string.upper(CooldownCursorDB.global.spellTextAnchor)]
      or SPELL_TEXT_ANCHOR_POINTS[string.upper(defaults.spellTextAnchor)]
  icon.text:ClearAllPoints()
  icon.text:SetPoint(anchorPoint.point, icon, anchorPoint.relativeTo, anchorPoint.x, anchorPoint.y)

  local size = CooldownCursor:GetEffectiveIconSize(spellID)
  local scale = CooldownCursorDB.global.scale or defaults.scale
  icon:SetSize(size * scale, size * scale)
  icon.text:SetScale(scale)
  icon.cooldown:SetScale(scale)
  if icon.procOverlay then
    local overlayAtlas = CooldownCursorDB.global.procOverlayAtlas or defaults.procOverlayAtlas
    local overlayScale = 1.6
    if overlayAtlas and PROC_OVERLAY_ATLAS_SETTINGS[overlayAtlas] then
      overlayScale = PROC_OVERLAY_ATLAS_SETTINGS[overlayAtlas].scale or overlayScale
    end
    icon.procOverlay:SetSize(size * scale * overlayScale, size * scale * overlayScale)
  end
  if icon.procOutline then
    local outlineAtlas = CooldownCursorDB.global.procOutlineAtlas or defaults.procOutlineAtlas
    local outlineScale = 1.9
    if outlineAtlas and PROC_OUTLINE_ATLAS_SETTINGS[outlineAtlas] then
      outlineScale = PROC_OUTLINE_ATLAS_SETTINGS[outlineAtlas].scale or outlineScale
    end
    icon.procOutline:SetSize(size * scale * outlineScale, size * scale * outlineScale)
  end

  icon.cooldown:SetHideCountdownNumbers(CooldownCursorDB.global.hideCooldownNumbers)
  icon.cooldown:SetDrawSwipe(CooldownCursorDB.global.showCooldownSwipe)

  if icon:IsShown() and icon.spellID then
    local info = C_Spell.GetSpellInfo(icon.spellID)
    if info and CooldownCursorDB.global.showSpellNames and info.name then
      icon.text:SetText(info.name)
      icon.text:Show()
    else
      icon.text:Hide()
    end
  end

  -- Apply Masque iconHide override (ReSkin is called once in UpdateDisplay)
  if MasqueGroup and CooldownCursorDB.global.iconHide then
    icon.icon:SetAlpha(0)
  end
end

----------------------------------------------------
-- Icon Sorting Functions
----------------------------------------------------
local function SortIconsByTimeAdded(a, b)
  return a.addedTime < b.addedTime
end
local function SortIconsAlphabetically(a, b)
  return (a.spellName or ""):lower() < (b.spellName or ""):lower()
end

local function SortIconsByPriority(a, b)
  if a.priority ~= b.priority then
    return a.priority > b.priority
  end
  return SortIconsByTimeAdded(a, b)
end

local function SortIcons()
  local sortOrder = CooldownCursorDB.global.sortOrder or SORT_ORDER.PRIORITY

  if sortOrder == SORT_ORDER.ALPHABETICAL then
    table.sort(iconsByPriority, SortIconsAlphabetically)
  elseif sortOrder == SORT_ORDER.PRIORITY then
    table.sort(iconsByPriority, SortIconsByPriority)
  elseif sortOrder == SORT_ORDER.TIME_ADDED then
    table.sort(iconsByPriority, SortIconsByTimeAdded)
  else
    -- Fallback to PRIORITY if invalid sort order
    table.sort(iconsByPriority, SortIconsByPriority)
  end
end

----------------------------------------------------
-- Update Icon Positions
----------------------------------------------------
function UpdateIconPositions()
  local showBehavior = CooldownCursorDB.global.showBehavior or SHOW_BEHAVIOR.AUTO_HIDE_AFTER
  local stackDirection = CooldownCursorDB.global.stackDirection or defaults.stackDirection
  local isOffCooldown = (showBehavior == SHOW_BEHAVIOR.OFF_COOLDOWN)

  -- Radius + OFF_COOLDOWN: don't repack. Radius spaces icons evenly around
  -- a circle using the total count, so changing that count as icons appear/
  -- disappear causes all positions to jump. Just let them sit.
  local repackVisible = isOffCooldown and (stackDirection ~= STACK_DIRECTION.RADIUS)

  -- In OFF_COOLDOWN mode (non-Radius), only visible icons should occupy
  -- stack slots. Count visible icons first so GetLinearOffset gets the right total.
  local visibleCount = 0
  if repackVisible then
    for _, iconData in ipairs(iconsByPriority) do
      if iconData.iconFrame and iconData.iconFrame:GetAlpha() > 0 then
        visibleCount = visibleCount + 1
      end
    end
  else
    visibleCount = #iconsByPriority
  end

  -- Assign positions. When repacking, invisible icons are parked at 0,0
  -- (they're invisible anyway) and visible icons get sequential slots so
  -- they pack tightly with no gaps.
  local scale = CooldownCursorDB.global.scale or defaults.scale
  local spacing = CooldownCursorDB.global.stackSpacing or defaults.stackSpacing
  local direction = CooldownCursorDB.global.stackDirection or STACK_DIRECTION.VERTICAL
  local growth = CooldownCursorDB.global.stackGrowth or STACK_GROWTH.DOWN
  local isRadius = (direction == STACK_DIRECTION.RADIUS)
  local visibleIndex = 0
  local cumulativeOffset = 0
  for i, iconData in ipairs(iconsByPriority) do
    local iconFrame = iconData.iconFrame
    if iconFrame then
      if repackVisible and iconFrame:GetAlpha() == 0 then
        -- Invisible - park it, no stack slot consumed
        iconFrame.stackOffsetX = 0
        iconFrame.stackOffsetY = 0
      else
        local index = repackVisible and visibleIndex or (i - 1)
        local offsetX, offsetY
        if isRadius then
          offsetX, offsetY = GetRadiusOffset(index, visibleCount, growth)
        elseif index == 0 then
          offsetX, offsetY = 0, 0
        else
          offsetX, offsetY = GetLinearOffset(cumulativeOffset, direction, growth)
        end
        iconFrame.stackOffsetX = offsetX
        iconFrame.stackOffsetY = offsetY
        -- Accumulate offset using this icon's actual size for the next icon
        local iconSize = CooldownCursor:GetEffectiveIconSize(iconData.spellID)
        cumulativeOffset = cumulativeOffset + (iconSize * scale) + spacing
        visibleIndex = visibleIndex + 1
      end
    end
  end
end

----------------------------------------------------
-- Remove Icon for Spell
----------------------------------------------------
local function RemoveIconForSpell(spellID, immediate)
  local iconData = activeIcons[spellID]
  if not iconData then return end

  activeIcons[spellID] = nil

  for i, data in ipairs(iconsByPriority) do
    if data.spellID == spellID then
      table.remove(iconsByPriority, i)
      break
    end
  end

  local iconFrame = iconData.iconFrame

  if iconFrame.hideTimer then
    iconFrame.hideTimer:Cancel()
    iconFrame.hideTimer = nil
  end

  if immediate or CooldownCursorDB.global.fadeOutDuration == 0 then
    ReturnIconToPool(iconFrame)
  else
    iconFrame.fadeOut:Stop()
    local fadeOutAnim = iconFrame.fadeOut:GetAnimations()
    fadeOutAnim:SetDuration(CooldownCursorDB.global.fadeOutDuration or 0.3)
    iconFrame.fadeOut:Play()
  end

  SortIcons()
  UpdateIconPositions()
end

----------------------------------------------------
-- Schedule Hide Timer for Icon
----------------------------------------------------
local function ScheduleHideTimerForIcon(iconFrame, spellID)
  -- Don't schedule hide timer during preview mode
  if previewActive then
    return
  end

  -- Hide timer only applies to AUTO_HIDE_AFTER mode.
  -- ON_COOLDOWN removes icons itself when cooldown ends.
  -- OFF_COOLDOWN keeps icons alive permanently so it can show/hide them.
  local showBehavior = CooldownCursorDB.global.showBehavior or SHOW_BEHAVIOR.AUTO_HIDE_AFTER
  if showBehavior ~= SHOW_BEHAVIOR.AUTO_HIDE_AFTER then
    return
  end

  if iconFrame.hideTimer then
    iconFrame.hideTimer:Cancel()
  end

  local hideAfter = CooldownCursorDB.global.hideAfter or defaults.hideAfter

  iconFrame.hideTimer = C_Timer.NewTimer(hideAfter, function()
    RemoveIconForSpell(spellID, false)
  end)
end

----------------------------------------------------
-- Enforce Max Icons
----------------------------------------------------
local function EnforceMaxIcons()
  local maxIcons = CooldownCursorDB.global.maxIcons or defaults.maxIcons

  while #iconsByPriority > maxIcons do
    local toRemove = iconsByPriority[#iconsByPriority]
    RemoveIconForSpell(toRemove.spellID, true)
  end
end

----------------------------------------------------
-- Player Class Helper
----------------------------------------------------
local playerClass = nil

local function GetPlayerClass()
  if not playerClass then
    local _, classToken = UnitClass("player")
    playerClass = classToken
  end
  return playerClass
end

----------------------------------------------------
-- Spell Rule Logic
----------------------------------------------------

-- Get the rules table for the current player's class
local function GetClassRules()
  local data = CooldownCursorDB.spellRules
  if not data then return nil end

  local class = GetPlayerClass()
  if not class then return nil end

  -- Initialize class rules table if needed
  if not data.rules then
    data.rules = {}
  end
  if not data.rules[class] then
    data.rules[class] = {}
  end

  return data.rules[class]
end

function CooldownCursor:GetSpellRule(spellID)
  local data = CooldownCursorDB.spellRules
  if not data then return false end
  if data.settings and data.settings.disableRules then return true end

  local classRules = GetClassRules()
  -- If no rules exist for this class, don't show any spells
  if not classRules or not next(classRules) then return false end

  local rule = classRules[spellID]
  -- If spell is not in rules, don't show it
  if not rule then return false end

  -- If spell is not known to the player (wrong spec, etc.), don't show it
  if not IsSpellKnownCached(spellID) then return false end

  -- Return whether the spell is enabled
  local settings = rule.settings or {}
  return settings.enabled ~= false, rule
end

-- Expose GetPlayerClass for Options.lua
function CooldownCursor:GetPlayerClass()
  return GetPlayerClass()
end

----------------------------------------------------
-- Charge Count Helper
----------------------------------------------------
local function UpdateChargeCount(iconFrame, spellID)
  if not iconFrame or not iconFrame.chargeText then return end

  if CooldownCursorDB.global.showCharges == false then
    iconFrame.chargeText:Hide()
    return
  end

  local chargeInfo = C_Spell.GetSpellCharges(spellID)
  if chargeInfo then
    iconFrame.chargeText:SetText(chargeInfo.currentCharges)
    iconFrame.chargeText:Show()
  else
    iconFrame.chargeText:Hide()
  end
end

----------------------------------------------------
-- Icon Setup Helper
----------------------------------------------------
local function SetupNewIcon(spellID, spellInfo, durationObject, fromProc)
  local iconFrame = GetIconFromPool()
  if not iconFrame then return nil, nil end

  local _, rule = CooldownCursor:GetSpellRule(spellID)
  local settings = rule and rule.settings or {}
  local metadata = rule and rule.metadata or {}
  local priority = settings.priority or 0
  local procActive = activeProcSpells[spellID] or false

  -- If this spell is an instant cast or has no cooldown, and it's not from a proc, don't create icon.
  if not fromProc and rule and not metadata.hasCooldown and not metadata.hasCharges then
    return
  end

  local iconData = {
    spellID = spellID,
    iconFrame = iconFrame,
    durationObject = durationObject,
    spellName = spellInfo.name,
    addedTime = GetTime(),
    priority = priority,
    procActive = procActive,
    procOnly = fromProc == true,
    baseCooldown = metadata.baseCooldown or 0,
    hasCharges = metadata.hasCharges or false,
  }

  activeIcons[spellID] = iconData
  table.insert(iconsByPriority, iconData)

  iconFrame.spellID = spellID
  iconFrame.addedTime = iconData.addedTime
  iconFrame.priority = priority
  iconFrame.procActive = procActive
  iconFrame.procOnly = fromProc == true

  CooldownCursor:UpdateSingleIcon(iconFrame, spellID)

  -- Register with Masque after size is set (lazy registration)
  EnsureMasqueButton(iconFrame)

  iconFrame.icon:SetTexture(spellInfo.iconID)

  -- Proc-only spells have no real cooldown - hide the timer overlay
  if fromProc and not metadata.hasCooldown and not metadata.hasCharges then
    iconFrame.cooldown:SetHideCountdownNumbers(true)
    iconFrame.cooldown:SetDrawSwipe(false)
  else
    iconFrame.cooldown:SetCooldownFromDurationObject(durationObject)
  end

  if CooldownCursorDB.global.showSpellNames and spellInfo.name then
    iconFrame.text:SetText(spellInfo.name)
    iconFrame.text:Show()
  else
    iconFrame.text:Hide()
  end

  if CooldownCursorDB.global.animation then
    iconFrame:SetScale(1)
    iconFrame.showAnim:Stop()
    iconFrame.showAnim:Play()
  end

  iconFrame.icon:SetAlpha(PercentToAlpha(CooldownCursorDB.global.iconAlpha))
  iconFrame:SetScript("OnUpdate", UpdateCooldownIconFrame)
  iconFrame:Show()

  -- Update charge count display
  UpdateChargeCount(iconFrame, spellID)

  if iconFrame.procOverlay then
    local showProcs = CooldownCursorDB.global.showProcs ~= false
    local showOverlay = IsProcOverlayEnabled()
    iconFrame.procOverlay:SetShown(showProcs and showOverlay and procActive)
  end
  if iconFrame.procOutline then
    local showProcs = CooldownCursorDB.global.showProcs ~= false
    local showOutline = IsProcOutlineEnabled()
    iconFrame.procOutline:SetShown(showProcs and showOutline and procActive)
  end

  -- Show preview text if in preview mode
  if previewActive and iconFrame.previewText then
    iconFrame.previewText:Show()
  end

  return iconFrame, iconData
end

----------------------------------------------------
-- Show icon + cooldown
----------------------------------------------------
local function ShowSpellIcon(spellID, durationObject, fromProc)
  -- Don't create icons if addon is disabled
  if CooldownCursorDB.global.enabled == false then
    return nil, nil
  end

  local spellInfo = C_Spell.GetSpellInfo(spellID)
  if not spellInfo or not spellInfo.iconID then return nil, nil end

  local stackDirection = CooldownCursorDB.global.stackDirection or defaults.stackDirection
  local isSingleMode = (stackDirection == STACK_DIRECTION.SINGLE)

  if isSingleMode then
    -- SINGLE mode: Always override with newest spell
    if #iconsByPriority > 0 then
      for i = #iconsByPriority, 1, -1 do
        RemoveIconForSpell(iconsByPriority[i].spellID, true)
      end
    end

    local iconFrame, iconData = SetupNewIcon(spellID, spellInfo, durationObject, fromProc)
    if iconFrame then
      ScheduleHideTimerForIcon(iconFrame, spellID)
    end
    return iconFrame, iconData
  end

  if CooldownCursor:IsMultiIconEnabled() then
    -- If spell already exists, update it instead of creating duplicate
    local existingIcon = activeIcons[spellID]
    if existingIcon then
      local iconFrame = existingIcon.iconFrame
      iconFrame.cooldown:SetCooldownFromDurationObject(durationObject)
      existingIcon.durationObject = durationObject
      if not fromProc then
        existingIcon.procOnly = false
        iconFrame.procOnly = false
      end
      if activeProcSpells[spellID] and CooldownCursorDB.global.showProcs ~= false then
        existingIcon.procActive = true
        iconFrame.procActive = true
        if iconFrame.procOverlay then
          if IsProcOverlayEnabled() then
            iconFrame.procOverlay:Show()
          else
            iconFrame.procOverlay:Hide()
          end
        end
        if iconFrame.procOutline and IsProcOutlineEnabled() then
          iconFrame.procOutline:Show()
        end
      end
      UpdateChargeCount(iconFrame, spellID)
      ScheduleHideTimerForIcon(iconFrame, spellID)
      SortIcons()
      UpdateIconPositions()
      return iconFrame, existingIcon -- caller will run ApplyShowBehavior() after us
    end

    local iconFrame, iconData = SetupNewIcon(spellID, spellInfo, durationObject, fromProc)
    if iconFrame then
      SortIcons()
      UpdateIconPositions()
      EnforceMaxIcons()
      ScheduleHideTimerForIcon(iconFrame, spellID)
    end
    return iconFrame, iconData
  end
  return nil, nil
end

----------------------------------------------------
-- Show Behavior
----------------------------------------------------
-- AUTO_HIDE_AFTER: does nothing here, handled by ScheduleHideTimerForIcon as before.
-- ON_COOLDOWN:     removes icons whose cooldown has ended.
-- OFF_COOLDOWN:    seeds icons from rules, then hides/shows based on cooldown state.
local function ApplyShowBehavior()
  -- Don't interfere with preview icons
  if previewActive then return end

  -- Don't do anything if addon is disabled
  if CooldownCursorDB.global.enabled == false then
    return
  end

  local showBehavior = CooldownCursorDB.global.showBehavior or SHOW_BEHAVIOR.AUTO_HIDE_AFTER

  -- AUTO_HIDE_AFTER - nothing extra to do here
  if showBehavior == SHOW_BEHAVIOR.AUTO_HIDE_AFTER then
    -- If a spell can proc, only show it while the proc is active
    if CooldownCursorDB.global.showProcs ~= false then
      for spellID, iconData in pairs(activeIcons) do
        local iconFrame = iconData.iconFrame
        if iconFrame and procCapableSpells[spellID] then
          local isProcActive = iconData.procActive or iconFrame.procActive
          if isProcActive then
            iconFrame:SetAlpha(PercentToAlpha(CooldownCursorDB.global.iconAlpha or defaults.iconAlpha))
          else
            iconFrame:SetAlpha(0)
          end
        end
      end
      UpdateIconPositions()
    end
    return
  end

  -- OFF_COOLDOWN: seed icons for any rule-listed spells not yet tracked.
  -- We need the icons to exist so their cooldown frames stay current
  -- and we can check IsShown() on each event.
  if showBehavior == SHOW_BEHAVIOR.OFF_COOLDOWN then
    local classRules = GetClassRules()
    if classRules then
      for spellID, rule in pairs(classRules) do
        -- If spell has no cooldown and user doesn't want to show procs, skip it
        if not CooldownCursorDB.global.showProcs and rule.metadata.baseCooldown == 0 then
          -- continue to next spell (can't use continue in Lua, so we use a nested if)
        elseif (rule.settings and rule.settings.enabled ~= false) and not activeIcons[spellID] and IsSpellKnownCached(spellID) then
          local durationObject = C_Spell.GetSpellCooldownDuration(spellID)
          if durationObject then
            ShowSpellIcon(spellID, durationObject)
          end
        end
      end
    end
  end

  -- Collect spellIDs to remove (ON_COOLDOWN mode).
  -- We cannot call RemoveIconForSpell inside the loop because it
  -- modifies activeIcons while we are iterating it.
  -- Reuse a buffer to avoid allocating a new table every call.
  local toRemoveCount = 0

  for spellID, iconData in pairs(activeIcons) do
    local iconFrame = iconData.iconFrame
    if iconFrame then
      local isOnCooldown = iconFrame.cooldown:IsShown()
      local isProcActive = (CooldownCursorDB.global.showProcs ~= false) and (iconData.procActive or iconFrame.procActive)

      -- Update charge count text (only for spells that have charges)
      if iconData.hasCharges then
        UpdateChargeCount(iconFrame, spellID)
      end

      -- Reset alpha in case it was modified in OFF_COOLDOWN mode
      if isOnCooldown or isProcActive then
        iconFrame:SetAlpha(PercentToAlpha(CooldownCursorDB.global.iconAlpha or defaults.iconAlpha))
      end

      if showBehavior == SHOW_BEHAVIOR.ON_COOLDOWN then
        -- ON_COOLDOWN: icon should only be visible while on cooldown.
        -- Mark for removal once the cooldown ends.
        if not isOnCooldown and not isProcActive then
          toRemoveCount = toRemoveCount + 1
          toRemoveBuffer[toRemoveCount] = spellID
        end
      elseif showBehavior == SHOW_BEHAVIOR.OFF_COOLDOWN then
        -- OFF_COOLDOWN: icon should only be visible when ready.
        -- Use SetAlpha so the cooldown frame stays alive and keeps updating.
        local procOnlySpell = procCapableSpells[spellID] and iconData.baseCooldown == 0
        if isProcActive then
          -- Proc is active - always show
          iconFrame:SetAlpha(PercentToAlpha(CooldownCursorDB.global.iconAlpha or defaults.iconAlpha))
        elseif procOnlySpell and (CooldownCursorDB.global.showProcs ~= false) then
          -- Proc-only spell (no cooldown) not currently proccing - hide
          iconFrame:SetAlpha(0)
        elseif isOnCooldown then
          -- On cooldown - but if spell has charges available, still show it
          local chargeInfo = CooldownCursorDB.global.showCharges ~= false and C_Spell.GetSpellCharges(spellID)
          if chargeInfo and chargeInfo.currentCharges then
            iconFrame:SetAlpha(PercentToAlpha(CooldownCursorDB.global.iconAlpha or defaults.iconAlpha))
          else
            iconFrame:SetAlpha(0)
          end
        else
          -- Off cooldown and ready - show
          iconFrame:SetAlpha(CooldownCursorDB.global.iconAlpha or defaults.iconAlpha)
        end
      end
    end
  end

  -- Now safe to remove - we are no longer iterating activeIcons
  for i = 1, toRemoveCount do
    RemoveIconForSpell(toRemoveBuffer[i], false)
    toRemoveBuffer[i] = nil
  end

  -- Repack icon positions after visibility changes.
  -- In OFF_COOLDOWN mode this collapses gaps left by invisible icons.
  UpdateIconPositions()
end

----------------------------------------------------
-- Internal hide helper
----------------------------------------------------
function CooldownCursor:HideIconNow()
  if previewTicker then
    previewTicker:Cancel()
    previewTicker = nil
  end
  previewActive = false

  if self:IsMultiIconEnabled() then
    self:HideAllIcons(true)
  else
    if #iconsByPriority > 0 then
      local iconFrame = iconsByPriority[1].iconFrame
      if iconFrame then
        RemoveIconForSpell(iconsByPriority[1].spellID, CooldownCursorDB.global.fadeOutDuration == 0)
      end
    end
    lastSpellId = nil
    activeSpellID = nil
  end
end

----------------------------------------------------
-- Internal Check if secret helper
----------------------------------------------------
local function IsSecretValue(value)
  local valueType = type(value)
  if valueType == "number" then
    -- try to perform an operation that would fail on a secret value
    local success = pcall(function() return value == 0 end)
    return not success
  end
  return false
end

----------------------------------------------------
-- Settings API
----------------------------------------------------

function CooldownCursor:GetVersion()
  return C_AddOns.GetAddOnMetadata(addonName, "Version")
end

function CooldownCursor:GetMajorVersion()
  local major = C_AddOns.GetAddOnMetadata(addonName, "Version")
  return major:match("^(%d+)")
end

function CooldownCursor:GetAuthor()
  return C_AddOns.GetAddOnMetadata(addonName, "Author")
end

function CooldownCursor:GetNotes()
  return C_AddOns.GetAddOnMetadata(addonName, "Notes")
end

function CooldownCursor:GetDBValue(key)
  if CooldownCursorDB.global[key] ~= nil then
    return CooldownCursorDB.global[key]
  end
  return defaults[key]
end

function CooldownCursor:SetDBString(key, value)
  CooldownCursorDB.global[key] = string.format("%s", value)
  self:UpdateDisplay()
end

function CooldownCursor:SetDBNumber(key, value)
  CooldownCursorDB.global[key] = tonumber(value)
  -- Switching showBehavior leaves stale icons (wrong alphas, wrong set of
  -- icons tracked). Clear everything and let ApplyShowBehavior re-seed.
  if key == "showBehavior" then
    self:HideAllIcons(true)
    ApplyShowBehavior()
  end
  if key == "showWhen" and not previewActive then
    inCombat = InCombatLockdown()
    if (value == SHOW_WHEN_STATE.COMBAT and not inCombat)
        or (value == SHOW_WHEN_STATE.NON_COMBAT and inCombat) then
      self:HideAllIcons(true)
    else
      ApplyShowBehavior()
    end
  end
  self:UpdateDisplay()
end

function CooldownCursor:SetDBBoolean(key, value)
  CooldownCursorDB.global[key] = value and true or false
  self:UpdateDisplay()
end

function CooldownCursor:ClearProcStates(removeProcOnly)
  activeProcSpells = {}
  procCapableSpells = {}
  local toRemove = {}

  for spellID, iconData in pairs(activeIcons) do
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
    RemoveIconForSpell(spellID, true)
  end
end

function CooldownCursor:AddOrUpdateSpellRule(spellID, ruleData)
  spellID = tonumber(spellID)
  if not spellID then return false, "Invalid spell ID" end

  local spellName = C_Spell.GetSpellInfo(spellID)
  if not spellName then return false, "Unknown spell ID" end

  CooldownCursorDB.spellRules = CooldownCursorDB.spellRules or {}
  CooldownCursorDB.spellRules.settings = CooldownCursorDB.spellRules.settings or {}
  CooldownCursorDB.spellRules.rules = CooldownCursorDB.spellRules.rules or {}

  -- Get class-specific rules table
  local classRules = GetClassRules()
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

function CooldownCursor:RemoveSpellRule(spellID)
  local classRules = GetClassRules()
  if not classRules then return end

  classRules[spellID] = nil
  CooldownCursor:UpdateDisplay()
  CooldownCursor:RebuildSpellRuleOptions()
  CooldownCursor:NotifyOptionsChanged()
end

function CooldownCursor:GetEffectiveIconSize(spellID)
  local globalSize = self:GetDBValue("iconSize")
  local classRules = GetClassRules()

  if not classRules then return globalSize end

  local rule = classRules[spellID]
  if not rule or not rule.settings then return globalSize end

  if rule.settings.useGlobalIconSize ~= false then return globalSize end

  if rule.settings.iconSize then return rule.settings.iconSize end

  return globalSize
end

function CooldownCursor:SetFontPath(key, value)
  CooldownCursorDB.global[key] = value
  CooldownCursorDB.global[key .. "Path"] = FontPath(CooldownCursorDB.global[key])
  self:UpdateDisplay()
end

function CooldownCursor:GetAllFonts()
  return FontNames()
end

function CooldownCursor:GetValidFontTypes()
  return FONT_TYPES
end

function CooldownCursor:GetValidAnchorPositions()
  return GetTableKeys(ANCHOR_POSITION)
end

function CooldownCursor:GetValidFrameStratas()
  return GetTableKeys(FRAME_STRATA)
end

function CooldownCursor:GetValidSpellTextAnchorPositions()
  return GetTableKeys(SPELL_TEXT_ANCHOR_POINTS)
end

function CooldownCursor:GetValidCooldownTextAnchorPositions()
  return GetTableKeys(CD_TEXT_ANCHOR_POINTS)
end

function CooldownCursor:GetValidFontType(ftype)
  if not ftype then return false end
  local fontType = string.upper(ftype)
  if fontType == "NONE" then return true end
  return FONT_TYPES[fontType] ~= nil
end

function CooldownCursor:GetValidAnchorPosition(pos)
  return IsValidTableKey(ANCHOR_POSITION, pos)
end

function CooldownCursor:GetValidSpellTextAnchorPosition(pos)
  return IsValidTableKey(SPELL_TEXT_ANCHOR_POINTS, pos)
end

function CooldownCursor:GetValidCooldownTextAnchorPosition(pos)
  return IsValidTableKey(CD_TEXT_ANCHOR_POINTS, pos)
end

function CooldownCursor:GetValidFrameStrata(strata)
  return IsValidTableKey(FRAME_STRATA, strata)
end

function CooldownCursor:SetHideAfter(seconds)
  CooldownCursorDB.global.hideAfter = tonumber(seconds) or defaults.hideAfter
end

function CooldownCursor:SetFadeOutDuration(seconds)
  CooldownCursorDB.global.fadeOutDuration = tonumber(seconds) or defaults.fadeOutDuration
end

function CooldownCursor:GetPreviewMouseMode()
  return previewMouseMode
end

function CooldownCursor:SetPreviewMouseMode(enabled)
  previewMouseMode = enabled
  if previewActive then
    CooldownCursor:ApplyPreviewPosition()
  end
end

function CooldownCursor:ResetSettings()
  CooldownCursor:HideIconNow()
  CooldownCursorDB.global = {}
  self:ApplyDefaults()
  self:UpdateDisplay()
  CooldownCursor:SetPreviewMouseMode(true)
end

----------------------------------------------------
-- Multi-Icon Public API
----------------------------------------------------

function CooldownCursor:HideAllIcons(immediate)
  for spellID, _ in pairs(activeIcons) do
    RemoveIconForSpell(spellID, immediate or false)
  end
  activeIcons = {}
  iconsByPriority = {}
end

function CooldownCursor:GetActiveIconCount()
  return #iconsByPriority
end

function CooldownCursor:IsMultiIconEnabled()
  local stackDirection = CooldownCursorDB.global.stackDirection or defaults.stackDirection
  return stackDirection ~= STACK_DIRECTION.SINGLE
end

function CooldownCursor:InitMultiIconSystem()
  InitializeIconPool()
end

function CooldownCursor:GetValidSortOrders()
  return {
    ALPHABETICAL = "Alphabetical",
    PRIORITY = "Priority (Spell Rules)",
    TIME_ADDED = "Time Added (Oldest First)",
  }
end

function CooldownCursor:GetValidStackDirections()
  return {
    VERTICAL = "Vertical",
    SINGLE = "Single (Override)",
    HORIZONTAL = "Horizontal",
    RADIUS = "Radius (Circle)",
  }
end

function CooldownCursor:GetValidStackGrowth()
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

----------------------------------------------------
-- Preview Mode Indicator
----------------------------------------------------
local function ShowPreviewIndicator()
  -- Show preview text on all active icons
  for _, iconData in ipairs(iconsByPriority) do
    if iconData.iconFrame and iconData.iconFrame.previewText then
      iconData.iconFrame.previewText:Show()
    end
  end
end

local function HidePreviewIndicator()
  -- Hide preview text on all active icons
  for _, iconData in ipairs(iconsByPriority) do
    if iconData.iconFrame and iconData.iconFrame.previewText then
      iconData.iconFrame.previewText:Hide()
    end
  end
end

----------------------------------------------------
-- Live Preview API
----------------------------------------------------
local function StopPreview()
  previewActive = false
  if previewTicker then
    previewTicker:Cancel()
    previewTicker = nil
  end
  HidePreviewIndicator()
end

local function StartPreviewLoop(showFunc, intervalSeconds)
  previewActive = true
  ShowPreviewIndicator()
  showFunc()
  previewTicker = C_Timer.NewTicker(intervalSeconds, function()
    if previewActive then
      showFunc()
    else
      StopPreview()
    end
  end)
end

function CooldownCursor:Preview()
  if self:IsMultiIconEnabled() then
    self:PreviewMultiIcon()
    return
  end

  if previewActive then
    StopPreview()
    self:HideIconNow()
    return
  end

  local function ApplyPreviewProc(iconFrame, iconData)
    if not iconFrame or not iconData then return end
    if CooldownCursorDB.global.showProcs == false then return end
    iconData.procActive = true
    iconFrame.procActive = true
    if iconFrame.procOverlay then
      if IsProcOverlayEnabled() then
        iconFrame.procOverlay:Show()
      else
        iconFrame.procOverlay:Hide()
      end
    end
    if iconFrame.procOutline then
      if IsProcOutlineEnabled() then
        iconFrame.procOutline:Show()
      else
        iconFrame.procOutline:Hide()
      end
    end
  end

  local function ShowPreviewIcon()
    local durationObj = C_DurationUtil.CreateDuration()
    durationObj:SetTimeFromStart(GetTime(), 30)
    local iconFrame, iconData = ShowSpellIcon(116, durationObj) -- Frostbolt
    ApplyPreviewProc(iconFrame, iconData)
    self:ApplyPreviewPosition()
  end

  StartPreviewLoop(ShowPreviewIcon, 30)
end

-- Preview spell pool with varying durations
local PREVIEW_SPELL_POOL = {
  { id = 116,   duration = 30 }, -- Frostbolt
  { id = 133,   duration = 15 }, -- Fireball
  { id = 11426, duration = 45 }, -- Ice Barrier
  { id = 2136,  duration = 20 }, -- Fire Blast
  { id = 118,   duration = 35 }, -- Polymorph
  { id = 122,   duration = 25 }, -- Frost Nova
  { id = 1459,  duration = 40 }, -- Arcane Intellect
  { id = 130,   duration = 12 }, -- Slow Fall
  { id = 475,   duration = 50 }, -- Remove Curse
  { id = 1953,  duration = 18 }, -- Blink
}

function CooldownCursor:PreviewMultiIcon()
  if previewActive then
    StopPreview()
    self:HideAllIcons(true)
    return
  end

  -- Build preview spell list from spell rules, or fall back to default pool
  local function GetPreviewSpells()
    local previewSpells = {}

    -- Get class-specific rules
    local classRules = GetClassRules()

    if classRules and next(classRules) then
      -- Use spells from user's class-specific spell rules
      for spellID, rule in pairs(classRules) do
        local ruleSettings = rule.settings or {}
        local metadata = rule.metadata or {}
        if ruleSettings.enabled ~= false and IsSpellKnownCached(spellID) then
          local info = C_Spell.GetSpellInfo(spellID)
          if info then
            local isProc = not metadata.hasCooldown and not metadata.hasCharges
            table.insert(previewSpells, {
              id = spellID,
              duration = 30 + (#previewSpells * 5), -- Vary durations
              name = info.name,
              priority = ruleSettings.priority or 0,
              isProc = isProc,
            })
          end
        end
      end
      -- Sort by priority (highest first)
      table.sort(previewSpells, function(a, b)
        return a.priority > b.priority
      end)
    end

    -- Fall back to default pool if no spell rules
    if #previewSpells == 0 then
      return PREVIEW_SPELL_POOL
    end

    return previewSpells
  end

  local function ApplyPreviewProc(iconFrame, iconData)
    if not iconFrame or not iconData then return end
    if CooldownCursorDB.global.showProcs == false then return end
    iconData.procActive = true
    iconFrame.procActive = true
    if iconFrame.procOverlay then
      if IsProcOverlayEnabled() then
        iconFrame.procOverlay:Show()
      else
        iconFrame.procOverlay:Hide()
      end
    end
    if iconFrame.procOutline then
      if IsProcOutlineEnabled() then
        iconFrame.procOutline:Show()
      else
        iconFrame.procOutline:Hide()
      end
    end
  end

  local function ShowPreviewIcons()
    local maxIcons = self:GetDBValue("maxIcons")
    local spellPool = GetPreviewSpells()
    local numToShow = math.min(maxIcons, #spellPool)

    for i = 1, numToShow do
      local spellData = spellPool[i]
      local durationObj = C_DurationUtil.CreateDuration()
      durationObj:SetTimeFromStart(GetTime(), spellData.duration)
      local iconFrame, iconData = ShowSpellIcon(spellData.id, durationObj, spellData.isProc)
      if spellData.isProc then
        ApplyPreviewProc(iconFrame, iconData)
      end
    end
    self:ApplyPreviewPosition()
  end

  StartPreviewLoop(ShowPreviewIcons, 50)
end

function CooldownCursor:ApplyPreviewPosition()
  if not previewActive then return end

  local isRadius = (CooldownCursorDB.global.stackDirection or defaults.stackDirection) == "RADIUS"

  if previewMouseMode then
    for i, iconData in ipairs(iconsByPriority) do
      iconData.iconFrame:SetScript("OnUpdate", UpdateCooldownIconFrame)

      -- Show primary indicator on first icon in RADIUS mode
      if isRadius and i == 1 then
        iconData.iconFrame.primaryBorder:Show()
        iconData.iconFrame.primaryLabel:Show()
      else
        iconData.iconFrame.primaryBorder:Hide()
        iconData.iconFrame.primaryLabel:Hide()
      end
    end
  else
    for _, iconData in ipairs(iconsByPriority) do
      local icon = iconData.iconFrame
      icon:SetScript("OnUpdate", nil)
      icon:SetFrameStrata("HIGH")
      icon:ClearAllPoints()
      local anchor = SettingsPanel or UIParent
      icon:SetPoint("LEFT", anchor, "RIGHT", 8, 0)

      -- Hide primary indicator when not following mouse
      icon.primaryBorder:Hide()
      icon.primaryLabel:Hide()
    end
  end
end

----------------------------------------------------
-- Event handler
----------------------------------------------------
local SPELL_EVENTS = {
  UNIT_SPELLCAST_FAILED = true,
  UNIT_SPELLCAST_SENT = true,
  UNIT_SPELLCAST_SUCCEEDED = true,
  SPELL_UPDATE_COOLDOWN = true,
  SPELL_UPDATE_USABLE = true,
}
local pendingSpellTimers = {}

CooldownCursor:SetScript("OnEvent", function(self, event, ...)
  local unit
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then return end
    self:ApplyDefaults()
    RefreshScreenMetrics()
    self:InitMultiIconSystem()
    self:UpdateDisplay()
    self:InitAce3Options()
    self:UnregisterEvent("ADDON_LOADED")
    inCombat = InCombatLockdown()
    return
  end

  if event == "PLAYER_SPECIALIZATION_CHANGED" then
    unit = ...
    if unit == "player" then
      knownSpellCache = {}
      CooldownCursor:HideAllIcons(true)
      ApplyShowBehavior()
      return
    end
  end

  if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
    local spellID = ...
    if not spellID then return end
    if CooldownCursorDB.global.showProcs == false then return end

    local show = CooldownCursor:GetSpellRule(spellID)
    if not show then return end
    activeProcSpells[spellID] = true
    procCapableSpells[spellID] = true
    local durationObj = C_Spell.GetSpellCooldownDuration(spellID)
    local hadIcon = activeIcons[spellID] ~= nil
    local iconFrame, iconData = ShowSpellIcon(spellID, durationObj, true)
    if iconFrame and iconData then
      iconData.procActive = true
      iconFrame.procActive = true
      if not hadIcon then
        iconData.procOnly = true
        iconFrame.procOnly = true
      end
      if iconFrame.procOverlay then
        if IsProcOverlayEnabled() then
          iconFrame.procOverlay:Show()
        else
          iconFrame.procOverlay:Hide()
        end
      end
      if iconFrame.procOutline and IsProcOutlineEnabled() then
        iconFrame.procOutline:Show()
      end
    end
    return
  end

  if event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
    local spellID = ...
    if not spellID then return end
    if CooldownCursorDB.global.showProcs == false then return end
    activeProcSpells[spellID] = nil
    local iconData = activeIcons[spellID]
    if iconData and iconData.iconFrame then
      local iconFrame = iconData.iconFrame
      iconData.procActive = false
      iconFrame.procActive = false
      if iconFrame.procOverlay then
        iconFrame.procOverlay:Hide()
      end
      if iconFrame.procOutline then
        iconFrame.procOutline:Hide()
      end
      if iconData.procOnly then
        RemoveIconForSpell(spellID, true)
      end
    end
    return
  end

  if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    RefreshScreenMetrics()
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    -- Entering combat
    inCombat = true
    if CooldownCursorDB.global.showWhen == SHOW_WHEN_STATE.NON_COMBAT then
      CooldownCursor:HideIconNow()
    else
      ApplyShowBehavior()
    end
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    -- Exiting combat
    inCombat = false
    if CooldownCursorDB.global.showWhen == SHOW_WHEN_STATE.COMBAT then
      CooldownCursor:HideIconNow()
    else
      ApplyShowBehavior()
    end
    return
  end

  if CooldownCursorDB.global.showWhen == SHOW_WHEN_STATE.NON_COMBAT and inCombat then
    return
  end

  if CooldownCursorDB.global.showWhen == SHOW_WHEN_STATE.COMBAT and not inCombat then
    return
  end

  if CooldownCursorDB.global.hideWhileMounted and IsMounted() then
    self:HideAllIcons(true)
    return
  end

  if event == "SPELL_UPDATE_USABLE" then
    ApplyShowBehavior()
    return
  end

  if SPELL_EVENTS[event] then
    local spellID
    -- Check if addon is enabled
    if CooldownCursorDB.global.enabled == false then
      return
    end

    -- SPELL_UPDATE_COOLDOWN will update cooldown
    -- that buffs, talents or items may trigger new updated CD times.
    if event == "SPELL_UPDATE_COOLDOWN" then
      spellID, _, _, _ = ...
    else
      unit, _, spellID = ...
      if unit ~= "player" then return end
    end
    if not spellID then return end

    -- Check user spell rules before doing any cooldown queries
    local show, rule = CooldownCursor:GetSpellRule(spellID)
    if not show then return end
    local hasCharges = rule and rule.metadata and rule.metadata.hasCharges or false

    -- Debounce: skip if a timer is already pending for this spellID
    if not pendingSpellTimers[spellID] then
      pendingSpellTimers[spellID] = true
      -- Delay slightly to allow cooldown to register
      C_Timer.After(0.01, function()
        pendingSpellTimers[spellID] = nil
        local durationObj = C_Spell.GetSpellCooldownDuration(spellID)

        if not durationObj then return end

        -- local usable = C_Spell.IsSpellUsable(spellID)
        local inRange = C_Spell.IsSpellInRange(spellID)

        -- Check spell usability
        if inRange == false and
          CooldownCursorDB.global.showBehavior ~= SHOW_BEHAVIOR.OFF_COOLDOWN then
          return
        end

        if hasCharges then
          local iconFrame, _ = ShowSpellIcon(spellID, durationObj)
          UpdateChargeCount(iconFrame, spellID)
          ApplyShowBehavior()
          return
        end

        if durationObj then
          ShowSpellIcon(spellID, durationObj)
        end

        ApplyShowBehavior()
      end)
    end
  end
end)

----------------------------------------------------
-- Register events
----------------------------------------------------
CooldownCursor:RegisterEvent("ADDON_LOADED")
CooldownCursor:RegisterEvent("UNIT_SPELLCAST_SENT")
CooldownCursor:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
CooldownCursor:RegisterEvent("SPELL_UPDATE_COOLDOWN")
CooldownCursor:RegisterEvent("SPELL_UPDATE_USABLE")
CooldownCursor:RegisterEvent("UNIT_SPELLCAST_FAILED")
CooldownCursor:RegisterEvent("PLAYER_REGEN_DISABLED")
CooldownCursor:RegisterEvent("PLAYER_REGEN_ENABLED")
CooldownCursor:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
CooldownCursor:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
CooldownCursor:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
CooldownCursor:RegisterEvent("UI_SCALE_CHANGED")
CooldownCursor:RegisterEvent("DISPLAY_SIZE_CHANGED")
