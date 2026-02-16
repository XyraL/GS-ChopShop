Config = {}

Config.Framework = "auto" -- "auto" | "qbox" | "qbcore"

Config.Inventory = "auto" -- "auto" | "ox" | "qb" | "ps"
Config.UseOxLib = true    -- if true, uses ox_lib for notify/progress (recommended). If false, tries qb-core progressbar/notify.

Config.TabletItem = "chop_tablet"

Config.Contract = {
  cooldownSeconds = 300,
  durationSeconds = 1800,
  maxActivePerPlayer = 1,
  allowMultiplePlayers = true,
}

--========================================
-- CONTRACTS Modifiers
--========================================
-- Adds small randomized twists to each contract (requirements/reward/risk).
-- If you want classic/static contracts, set enabled=false.
Config.ContractModifiers = {
  enabled = true,
  minActive = 1,
  maxActive = 2,

  -- If a modifier requires a step, we can force that step on even if the
  forceStepsOn = true,

  defs = {
    require_vin = {
      label = 'VIN Scrub Required',
      desc  = 'Scratch VIN before dismantling.',
      addSteps = { 'vin_scratch' },
      payoutMult = 1.12,
      alertMult  = 1.05,
      weights = { tier1 = 12, tier2 = 16, tier3 = 18 },
    },
    plates_mandatory = {
      label = 'Plates Must Go',
      desc  = 'Remove both plates first.',
      addSteps = { 'plate_front', 'plate_rear' },
      payoutMult = 1.08,
      weights = { tier1 = 18, tier2 = 14, tier3 = 10 },
    },
    cut_required = {
      label = 'Shell Cut Order',
      desc  = 'Move shell to the line, cut, then dispose.',
      addSteps = { 'move_shell', 'cut_shell' },
      payoutMult = 1.15,
      alertMult  = 1.08,
      weights = { tier1 = 5, tier2 = 10, tier3 = 14 },
    },
    tight_intel = {
      label = 'Tight Intel',
      desc  = 'Smaller search radius. Cleaner pickup.',
      radiusMult = 0.75,
      payoutMult = 1.06,
      weights = { tier1 = 10, tier2 = 12, tier3 = 14 },
    },
    short_fuse = {
      label = 'Short Fuse',
      desc  = 'Reduced timer. Finish quick.',
      durationMult = 0.75,
      payoutMult   = 1.18,
      weights = { tier1 = 6, tier2 = 8, tier3 = 10 },
    },
  }
}

-- Search zone settings
Config.Search = {
  radius = 180.0, -- meters
  blipColor = 1,
  blipAlpha = 120,
}

Config.V2 = {
  vinScratch = true,
  removePlates = true,

  -- If true, "final" is completed at a converter station instead of on the vehicle.
  useConverterFinale = false,
}

Config.PDAlert = {
  enabled = true,
  onStart = true,       -- alert chance when contract starts (after the vehicle is spawned)
  onArrival = false,    -- alert chance when arriving to chop bay
  chance = { tier1 = 15, tier2 = 25, tier3 = 40 }, -- %
  cooldownSeconds = 60,
  dispatch = "custom",  -- (event stub), you can swap
}

Config.Tiers = {
  tier1 = {
    label = "Tier 1",
    vehicles = { 'blista', 'asea', 'emperor', 'primo', 'intruder' },
    payout = { cash = { min = 2000, max = 4500 } },
    items = {
      { name = "scrapmetal", min = 10, max = 25, chance = 100 },
      { name = "rubber", min = 8, max = 18, chance = 60 },
    }
  },
  tier2 = {
    label = "Tier 2",
    vehicles = { 'sultan', 'buffalo', 'jackal', 'fugitive', 'kuruma' },
    payout = { cash = { min = 5000, max = 9000 } },
    items = {
      { name = "scrapmetal", min = 18, max = 35, chance = 100 },
      { name = "electronics", min = 1, max = 3, chance = 35 },
    }
  },
  tier3 = {
    label = "Tier 3",
    vehicles = { 'elegy', 'comet2', 'schafter3', 'banshee', 'ninef' },
    payout = { cash = { min = 10000, max = 18000 } },
    items = {
      { name = "scrapmetal", min = 25, max = 55, chance = 100 },
      { name = "electronics", min = 2, max = 6, chance = 55 },
      { name = "advancedlockpick", min = 1, max = 1, chance = 10 },
    }
  },
}

Config.Unlocks = {
  tier2RequiresTier1 = 10, -- complete 10 Tier1 to unlock Tier2
  tier3RequiresTier2 = 10, -- complete 10 Tier2 to unlock Tier3
}

-- Contract vehicle spawn/search anchors around the map
Config.SpawnPoints = {
  vec4(-144.65, -1456.5, 32.02, 139.95),
  vec4(35.49, -1625.17, 27.86, 320.89),
  vec4(258.99, -1766.22, 27.33, 328.0),
  vec4(323.67, -1245.61, 28.97, 268.4),
  vec4(303.29, -695.06, 27.88, 249.64),
  vec4(-826.86, -407.22, 35.2, 297.28),
  vec4(-1649.93, -226.51, 53.6, 68.62),
  vec4(-1352.21, -1116.79, 2.69, 294.63),
}

-- Ped disabled (tablet-only)
Config.Ped = { enabled = false }

-- Salvage Yard bays
Config.Bays = {
  vec4(-425.99, -1680.98, 17.6, 341.96),
  vec4(-419.79, -1682.96, 17.6, 341.96),
}

Config.ChopSpots = Config.Bays

-- Advanced workflow steps
Config.AdvancedSteps = {
  { key = "vin_scratch" },
  { key = "plate_front" },
  { key = "plate_rear" },

  -- Strip parts
  { key = "door_lf" }, { key = "door_rf" }, { key = "door_lr" }, { key = "door_rr" },
  { key = "hood" }, { key = "trunk" },
  { key = "wheel_lf" }, { key = "wheel_rf" }, { key = "wheel_lr" }, { key = "wheel_rr" },

  -- Workflow stages
  { key = "move_shell" },
  { key = "engine" },
  { key = "cut_shell" },
    { key = "final" },
}

--========================================
-- ADVANCED FEATURES 
--========================================
Config.V3 = {
  enableMoveCutCrush = true,
  enforceStepOrder = true,

  cutLine = {
    enabled = true,
    radius = 3.0,
    offsetForward = 2.2,
    marker = { type = 1, scale = 1.25, height = 0.25 },
  },

  minigames = {
    enabled = true,
    tierScaling = true,
    failTimePenaltyMult = 0.50, -- +50% time if you fail a skillcheck
  },

  fx = {
    sparks = true,
    grinderSound = true,
  },

  coop = {
    enabled = true,
    maxHelpers = 3,
    splitMode = "equal", -- "equal" | "owner_majority"
    ownerShare = 0.60,
  },

  hints = {
    enabled = true,
    setWaypointToYardOnFound = true,
    setWaypointToCrusherOnCut = false,
  },
}



--========================================
-- USER-FRIENDLY GUIDES / MARKERS
--========================================
Config.V4 = {
  guides = {
    enabled = false,
    showNextStepArrow = false,   -- shows a small arrow marker above the next required step
    showCutLineMarker = true,   -- shows marker at cut line when move_shell pending
    markerDrawDist = 35.0,
  },
  minigames = {
    perPart = true, -- different difficulty per part type + tier scaling
  }
}

Config.Leaderboard = {
  enabled = true,
  topCount = 10
}

Config.Debug = {
  enabled = false,
  -- If true, /choptest can be used without an ACE permission.
  -- Turn this off in production.
  AllowChopTestWithoutAce = true,
}

--========================================
-- UPGRADES
--========================================
Config.Upgrades = {
  priceAccount = 'cash',
  priceMult = 1.22,

  chop_speed = {
    label = 'Chop Speed',
    basePrice = 25000,
    maxLevel = 10,
    timeReducePerLevel = 0.05,
    minTimeMult = 0.55,
  },

  clean_payout = {
    label = 'Clean Payout',
    basePrice = 40000,
    maxLevel = 10,
    payoutBonusPerLevel = 0.10,
    maxPayoutMult = 3.0,
  },

  heat_dampener = {
    label = 'Heat Dampener',
    basePrice = 60000,
    maxLevel = 10,
    alertReducePerLevel = 0.08,
    minAlertMult = 0.35,
  },

  scanner = {
    label = 'Scanner Suite',
    basePrice = 85000,
    maxLevel = 5,
    radiusReducePerLevel = 0.10,
    minRadiusMult = 0.55,
  },

  auto_dispatch = {
    label = 'Auto Dispatch',
    basePrice = 120000,
    maxLevel = 5,
    finalReducePerLevel = 0.10,
    minFinalMult = 0.55,
  },
}
