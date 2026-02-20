----------------------------------------------------
-- CooldownCursor: Defaults & Migrations
----------------------------------------------------
local addonName, addonTable = ...

local C = addonTable.Constants
local SHOW_WHEN_STATE = C.SHOW_WHEN_STATE
local SHOW_BEHAVIOR = C.SHOW_BEHAVIOR
local ANCHOR_POSITION = C.ANCHOR_POSITION
local FRAME_STRATA = C.FRAME_STRATA
local CD_TEXT_ANCHOR_POINTS = C.CD_TEXT_ANCHOR_POINTS
local CHARGE_TEXT_ANCHOR_POINTS = C.CHARGE_TEXT_ANCHOR_POINTS
local FONT_TYPES = C.FONT_TYPES
local DEFAULT_SYSTEM_FONTS = C.DEFAULT_SYSTEM_FONTS
local SORT_ORDER = C.SORT_ORDER
local STACK_DIRECTION = C.STACK_DIRECTION
local STACK_GROWTH = C.STACK_GROWTH

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

-- Export defaults
addonTable.Defaults = defaults

----------------------------------------------------
-- Defaults Module
----------------------------------------------------
local Defaults = {}

function Defaults:ApplyDefaults()
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
  self:ApplyBreakingChangesAndSetReleaseNotes()
end

function Defaults:ApplyBreakingChangesAndSetReleaseNotes()
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
    ["2.3.0"] = {
      fixes = {
        "Fixed a visual sparkle or flash that appeared when a spell icon first showed up",
        "Fixed icons briefly disappearing and reappearing when multiple spells come off cooldown at the same time",
        "Fixed 'Hide While Mounted' not always hiding icons when mounting — icons now reliably hide and restore on dismount",
        "Fixed proc and charge spell icons ignoring the 'Hide While Mounted' and 'Show When' settings",
        "Fixed icons sometimes appearing transparent in 'Off Cooldown (Ready)' display mode",
      },
    },
    ["2.2.2"] = {
      fixes = {
        "Event triggering with ApplyShowBehavior() when show out-of-combat / always enabled",
      },
    },
    ["2.2.1"] = {
      fixes = {
        "Fixed SPELL_UPDATE_CHARGES event not refreshing charge counts",
      },
    },
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
    local maj, minor, patch = vStr:match("^(%d+)%.(%d+)%.(%d+)$")
    if maj then
      return tonumber(maj) * 10000 + tonumber(minor) * 100 + tonumber(patch)
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
  local CooldownCursor = addonTable.Frame
  CooldownCursor.releaseNotes = {
    byVersion = releaseNotesByVersion,
    sortedVersions = sortedVersions,
  }
end

addonTable.Modules = addonTable.Modules or {}
addonTable.Modules.Defaults = Defaults
