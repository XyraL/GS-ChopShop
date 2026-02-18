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
-- SPECIAL CONTRACTS (rep-gated)
--========================================
Config.SpecialContracts = {
  enabled = true,
  label = 'BLACK OPS',
  repRequired = 50,
  baseTier = 'tier3',
  payoutMult = 1.35,
  alertMult = 1.10,
  minMods = 2,
  maxMods = 3,
  forceBonusObjective = true,
}

--========================================
-- CO-OP (invite a partner for a split)
--========================================
Config.Coop = {
  enabled = false,
  partnerShare = 0.35,      -- % of leader cash payout given to partner
  partnerRepShare = 1.0,    -- multiplier on partner rep (1.0 = same rep as leader)
}

--========================================
-- SMARTER CONTRACTS (Modifiers)
--========================================
-- Adds small randomized twists to each contract (requirements/reward/risk).
-- If you want classic/static contracts, set enabled=false.
Config.ContractModifiers = {
  enabled = true,
  -- Keep at least 1 active by default so players can *see* and feel the system.
  minActive = 1,
  maxActive = 2,

  -- If a modifier requires a step, we can force that step on even if the
  -- toggle in V2/V3 is disabled.
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

-- Search zone settings (ONE definition only)
Config.Search = {
  radius = 180.0, -- meters
  blipColor = 1,
  blipAlpha = 120,
}

Config.V2 = {
  -- Realism steps
  vinScratch = true,
  removePlates = true,

  -- If true, "final" is completed at a converter station instead of on the vehicle.
  useConverterFinale = false,
}

-- Friendly alias (same table as V2)
Config.RealismSteps = Config.V2

Config.PDAlert = {
  enabled = true,
  onStart = true,       -- alert chance when contract starts (after the vehicle is spawned)
  onArrival = false,    -- alert chance when arriving to chop bay
  chance = { tier1 = 15, tier2 = 25, tier3 = 40 }, -- %
  cooldownSeconds = 60,
  dispatch = "custom",  -- "custom" for now (event stub), you can swap later
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

-- Legacy alias
Config.ChopSpots = Config.Bays

-- Advanced workflow steps (order matters)
Config.AdvancedSteps = {
  -- Optional realism steps
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
-- V3 ADVANCED FEATURES (NO HEAT SYSTEM)
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

-- Friendly alias (same table as V3)
Config.ShellPipeline = Config.V3



--========================================
-- V4 USER-FRIENDLY GUIDES / MARKERS
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
-- LUXURY UPGRADES (OPTION C)
--========================================

Config.Upgrades = {
  -- Which account to charge for upgrades.
  priceAccount = 'cash',

  -- Price scaling per level (basePrice * priceMult^(currentLevel))
  priceMult = 1.22,

  --[[ 
    Upgrade definitions:
      label, desc, tag, category: UI fields
      basePrice, maxLevel: economy fields
      Effect fields:
        timeReducePerLevel, minTimeMult
        payoutBonusPerLevel, maxPayoutMult
        alertReducePerLevel, minAlertMult
        radiusReducePerLevel, minRadiusMult
        finalReducePerLevel, minFinalMult
        specialWeightBonusPerLevel (optional: syndicate/special weighting)
  ]]

  -- Personal (Operator)
  tech_hands = {
    label = 'Technician Hands',
    desc  = 'Quicker work on dismantle actions.',
    tag   = 'Personal',
    category = 'personal',
    basePrice = 18000,
    maxLevel = 15,
    timeReducePerLevel = 0.03,
    minTimeMult = 0.55,
  },

  runner_instinct = {
    label = 'Runner Instinct',
    desc  = 'Better search intel and faster lock-on.',
    tag   = 'Personal',
    category = 'personal',
    basePrice = 24000,
    maxLevel = 10,
    radiusReducePerLevel = 0.06,
    minRadiusMult = 0.55,
  },

  broker_cut = {
    label = 'Broker Cut',
    desc  = 'Cleaner deals, better money per run.',
    tag   = 'Personal',
    category = 'personal',
    basePrice = 32000,
    maxLevel = 15,
    payoutBonusPerLevel = 0.06,
    maxPayoutMult = 2.50,
  },

  scanner = {
    label = 'Scanner Suite',
    desc  = 'Tightens the search radius on higher tiers.',
    tag   = 'Personal',
    category = 'personal',
    basePrice = 85000,
    maxLevel = 5,
    radiusReducePerLevel = 0.10,
    minRadiusMult = 0.55,
  },

  -- Shop (Facility)
  hydraulic_lift = {
    label = 'Hydraulic Lift',
    desc  = 'Faster positioning and access to parts.',
    tag   = 'Shop',
    category = 'shop',
    basePrice = 50000,
    maxLevel = 10,
    timeReducePerLevel = 0.04,
    minTimeMult = 0.55,
  },

  chop_speed = {
    label = 'Chop Speed',
    desc  = 'Reduces action time across steps.',
    tag   = 'Shop',
    category = 'shop',
    basePrice = 25000,
    maxLevel = 10,
    timeReducePerLevel = 0.05,
    minTimeMult = 0.55,
  },

  sound_dampening = {
    label = 'Sound Dampening',
    desc  = 'Lower attention during the job.',
    tag   = 'Shop',
    category = 'shop',
    basePrice = 55000,
    maxLevel = 10,
    alertReducePerLevel = 0.06,
    minAlertMult = 0.35,
  },

  heat_dampener = {
    label = 'Heat Dampener',
    desc  = 'Lowers the chance of police attention.',
    tag   = 'Shop',
    category = 'shop',
    basePrice = 60000,
    maxLevel = 10,
    alertReducePerLevel = 0.08,
    minAlertMult = 0.35,
  },

  scrap_compactor = {
    label = 'Scrap Compactor',
    desc  = 'More value from the same metal.',
    tag   = 'Shop',
    category = 'shop',
    basePrice = 70000,
    maxLevel = 10,
    payoutBonusPerLevel = 0.05,
    maxPayoutMult = 2.75,
  },

  shell_shredder = {
    label = 'Shell Shredder',
    desc  = 'Streamlines final disposal.',
    tag   = 'Shop',
    category = 'shop',
    basePrice = 110000,
    maxLevel = 8,
    finalReducePerLevel = 0.08,
    minFinalMult = 0.55,
  },

  auto_dispatch = {
    label = 'Auto Dispatch',
    desc  = 'Streamlines final disposal.',
    tag   = 'Shop',
    category = 'shop',
    basePrice = 120000,
    maxLevel = 5,
    finalReducePerLevel = 0.10,
    minFinalMult = 0.55,
  },

  clean_payout = {
    label = 'Clean Payout',
    desc  = 'Boosts final cash payout.',
    tag   = 'Shop',
    category = 'shop',
    basePrice = 40000,
    maxLevel = 10,
    payoutBonusPerLevel = 0.10,
    maxPayoutMult = 3.0,
  },

  -- Network (Syndicate)
  fence_connections = {
    label = 'Fence Connections',
    desc  = 'Better buyers and better prices.',
    tag   = 'Network',
    category = 'network',
    basePrice = 90000,
    maxLevel = 10,
    payoutBonusPerLevel = 0.07,
    maxPayoutMult = 3.0,
  },

  parts_market = {
    label = 'Parts Market',
    desc  = 'Demand spikes, payouts climb.',
    tag   = 'Network',
    category = 'network',
    basePrice = 65000,
    maxLevel = 15,
    payoutBonusPerLevel = 0.04,
    maxPayoutMult = 3.0,
  },

  forgery_lab = {
    label = 'Forgery Lab',
    desc  = 'Improves special contract access.',
    tag   = 'Network',
    category = 'network',
    basePrice = 150000,
    maxLevel = 10,
    specialWeightBonusPerLevel = 0.05,
  },
}

-- Specialization Roles (Co-op)
Config.Roles = {
  enabled = false,
  -- Base multipliers applied on top of upgrades (no heat required).
  defs = {
    tech = {
      label = 'Tech',
      desc  = 'Faster dismantle actions and assist boosts.',
      mult = { time = 0.96, final = 0.98 },
    },
    runner = {
      label = 'Runner',
      desc  = 'Better search intel and mobility.',
      mult = { radius = 0.94, time = 0.99 },
    },
    broker = {
      label = 'Broker',
      desc  = 'Better payouts and contract quality.',
      mult = { payout = 1.06, alert = 0.98 },
    },
  },
  -- Crew synergy bonuses (applied when a co-op partner exists).
  synergies = {
    tech_tech = { label = 'Assembly Line', mult = { time = 0.95 } },
    tech_runner = { label = 'Pit Crew', mult = { time = 0.97, final = 0.95 } },
    runner_broker = { label = 'Clean Route', mult = { radius = 0.97, payout = 1.04 } },
    full_house = { label = 'Syndicate Efficiency', mult = { time = 0.96, payout = 1.03 } },
  }
}

-- Syndicate progression (Empire layer)
Config.Syndicate = {
  enabled = true,
  -- Influence gained per successful contract (base + tier bonus)
  influenceBase = 5,
  influenceByTier = { tier1 = 3, tier2 = 5, tier3 = 8 },
  -- Influence required per level
  influencePerLevel = 100,

  -- Passive bonus per syndicate level (small, keep it fair)
  perLevel = {
    payout = 0.005, -- +0.5% per level
    time = 0.002,   -- -0.2% per level
  }
}

--[[
  BONUS OBJECTIVES (per-contract)
  These roll on top of Smart Modifiers.
  Reward = extra money + reputation points on completion.
--]]
Config.BonusObjectives = {
  enabled = true,
  -- Set to 0 to make them optional/rare
  chance = 100,

  -- If enabled, a contract always rolls at most one objective.
  -- (Keep it simple for players, and readable in UI.)
  defs = {
    speed_run = {
      label = 'Speed Run',
      desc  = 'Finish the chop fast. No sightseeing.',
      weight = 40,
      -- seconds from contract start to disposal
      timeLimitSeconds = 420,
      moneyMult = 1.20,
      rep = 3,
    },
    clean_work = {
      label = 'Clean Work',
      desc  = 'Keep the shell clean. No big dents.',
      weight = 25,
      minBodyHealthRatio = 0.85,
      moneyMult = 1.15,
      rep = 2,
    },
    silent_operator = {
      label = 'Silent Operator',
      desc  = 'No heat. No dispatch.',
      weight = 20,
      moneyMult = 1.18,
      rep = 3,
    },
    flawless_hands = {
      label = 'Flawless Hands',
      desc  = 'No slip-ups. Don\'t fail a step.',
      weight = 15,
      moneyMult = 1.12,
      rep = 2,
    }
  }
}

-- Base reputation gain per successful contract (in addition to bonus objective rep)
Config.Reputation = Config.Reputation or { basePerChop = 1 }


-- Syndicate Influence Shop (shared perks)
Config.SyndicatePerks = {
  vaultBoost = {
    label = 'Vault Interest',
    desc = 'Adds +1% vault interest per level (paid daily).',
    baseCost = 250,
    growth = 0.35,
    maxLevel = 10,
  },
  payoutMult = {
    label = 'Syndicate Cut',
    desc = '+2% payout per level for all members.',
    baseCost = 400,
    growth = 0.35,
    maxLevel = 10,
  },
  timeMult = {
    label = 'Clockwork Crew',
    desc = '-2% contract time per level for all members.',
    baseCost = 400,
    growth = 0.35,
    maxLevel = 10,
  },
  radiusMult = {
    label = 'Street Eyes',
    desc = '-3% search radius per level for all members.',
    baseCost = 350,
    growth = 0.35,
    maxLevel = 10,
  },
}


--==============================
-- Syndicate Empire Layer (Expanded)
--==============================

-- Rank permissions (configurable). Ranks are numeric: 1=member, 2=capo, 3=boss.
Config.SyndicatePermissions = {
  member = {
    invite = false,
    withdraw = false,
    purchase = false,
    ops = false,
    branding = false,
    promote = false,
    kick = false,
    disband = false,
    routing = false,
  },
  capo = {
    invite = true,
    withdraw = true,
    purchase = true,
    ops = true,
    branding = false,
    promote = false,
    kick = true,
    disband = false,
    routing = true,
  },
  boss = {
    invite = true,
    withdraw = true,
    purchase = true,
    ops = true,
    branding = true,
    promote = true,
    kick = true,
    disband = true,
    routing = true,
  }
}

-- Auto revenue routing (from contract payouts into Syndicate Bank)
Config.SyndicateRevenueRouting = {
  enabledByDefault = false,
  defaultPercent = 0.15, -- 15%
  minPercent = 0.00,
  maxPercent = 0.35, -- keep it fair
}

-- Syndicate upgrade tree (funds + influence + level requirement)
-- Costs are paid from:
--   funds: Syndicate Vault
--   influence: Syndicate Influence
-- Requirements:
--   minLevel: syndicate level required to buy next level
--   requires: { nodeId = levelRequired }
Config.SyndicateTree = {
  nodes = {
    -- FINANCE
    routing_efficiency = {
      label = 'Routing Efficiency',
      desc  = 'Increases max routing percent cap.',
      branch = 'Finance',
      maxLevel = 5,
      cost = { funds = 15000, influence = 120, growth = 0.35 },
      minLevel = 0,
      effect = { routingCapAdd = 0.02 }, -- +2% max cap per level
    },
    vault_interest = {
      label = 'Vault Interest',
      desc  = 'Daily interest on vault balance (server-side payout).',
      branch = 'Finance',
      maxLevel = 10,
      cost = { funds = 25000, influence = 150, growth = 0.35 },
      minLevel = 2,
      effect = { vaultInterest = 0.01 }, -- +1% per level
    },
    syndicate_cut = {
      label = 'Syndicate Cut',
      desc  = 'All members earn more per contract.',
      branch = 'Finance',
      maxLevel = 10,
      cost = { funds = 30000, influence = 200, growth = 0.40 },
      minLevel = 1,
      effect = { payoutMult = 0.02 }, -- +2% per level
    },

    -- CONTRACTS
    black_market_contacts = {
      label = 'Black Market Contacts',
      desc  = 'Higher chance for rare contract rolls.',
      branch = 'Contracts',
      maxLevel = 8,
      cost = { funds = 45000, influence = 240, growth = 0.38 },
      minLevel = 3,
      effect = { rareRoll = 0.04 }, -- +4% weighting per level (server-side)
    },
    clean_pipeline = {
      label = 'Clean Pipeline',
      desc  = 'Slightly shorter contract duration for all members.',
      branch = 'Contracts',
      maxLevel = 10,
      cost = { funds = 35000, influence = 200, growth = 0.35 },
      minLevel = 2,
      effect = { timeMult = -0.02 }, -- -2% per level
    },

    -- OPERATIONS
    ops_department = {
      label = 'Operations Department',
      desc  = 'Unlocks syndicate-wide operations.',
      branch = 'Operations',
      maxLevel = 1,
      cost = { funds = 80000, influence = 400, growth = 0.0 },
      minLevel = 4,
      effect = { unlockOps = true },
    },
    ops_cooldown = {
      label = 'Operational Tempo',
      desc  = 'Reduces operation cooldowns.',
      branch = 'Operations',
      maxLevel = 5,
      cost = { funds = 65000, influence = 280, growth = 0.32 },
      minLevel = 5,
      requires = { ops_department = 1 },
      effect = { opCooldownMult = -0.08 }, -- -8% per level
    },
    ops_strength = {
      label = 'Force Multiplier',
      desc  = 'Stronger operation bonuses.',
      branch = 'Operations',
      maxLevel = 5,
      cost = { funds = 65000, influence = 280, growth = 0.32 },
      minLevel = 5,
      requires = { ops_department = 1 },
      effect = { opStrengthMult = 0.10 }, -- +10% per level
    },
  }
}

-- Syndicate Operations (syndicate-wide timed buffs)
Config.SyndicateOperations = {
  enabled = true,
  defs = {
    parts_distribution = {
      label = 'Parts Distribution',
      desc  = 'Boosts payout for a short window.',
      durationMinutes = 30,
      cooldownMinutes = 60,
      cost = { funds = 50000, influence = 150, minLevel = 4 },
      mult = { payout = 0.15 }, -- +15%
    },
    black_market_push = {
      label = 'Black Market Push',
      desc  = 'Improves rare contract odds temporarily.',
      durationMinutes = 60,
      cooldownMinutes = 120,
      cost = { funds = 70000, influence = 250, minLevel = 6 },
      mult = { rareRoll = 0.20 }, -- +20% rare weighting
    },
    supply_run = {
      label = 'Supply Run',
      desc  = 'Reduces personal upgrade prices briefly.',
      durationMinutes = 30,
      cooldownMinutes = 90,
      cost = { funds = 45000, influence = 140, minLevel = 5 },
      mult = { upgradePrice = -0.10 }, -- -10%
    },
  }
}

--=====================================================
-- Syndicate Prestige Ladder (slow, competitive)
-- Funds + Influence + Level requirement (your balance pick)
--=====================================================
Config.SyndicatePrestige = {
  -- Tiers are keyed by the *resulting* prestige.
  -- Example: tiers[1] requirements to go from 0 -> 1.
  tiers = {
    [1] = { levelReq = 6,  fundsCost = 150000, influenceCost = 300 },
    [2] = { levelReq = 9,  fundsCost = 350000, influenceCost = 650 },
    [3] = { levelReq = 12, fundsCost = 800000, influenceCost = 1200 },
    [4] = { levelReq = 15, fundsCost = 1600000, influenceCost = 2200 },
    [5] = { levelReq = 18, fundsCost = 3200000, influenceCost = 4000 },
  }
}

--=====================================================
-- Black Market War (Prestige III+) - rotating contract pool
--=====================================================
Config.BlackMarketWar = {
  enabled = true,

  -- Access gate
  minPrestige = 3,

  -- Event timing (admin starts via server console command `gs_bm_start`)
  durationSeconds = 90 * 60,   -- 90 minutes
  rotationSeconds = 20 * 60,   -- refresh offers every 20 minutes

  -- Contract duration is slightly tighter than normal (multiplies base duration)
  durationMult = 0.80,

  -- A slice of BM points becomes prestige points (slow burn)
  prestigePointRate = 0.10,

  themes = {
    'BLACK MARKET',
    'GHOST AUCTION',
    'SILK ROAD REBORN',
    'THE NIGHT SHIFT',
    'THE BROKER WAR',
  },

  pool = {
    standard = 2,
    elite = 1,
    dynasty = 1,
  },

  tiers = {
    standard = {
      label = 'Standard Offer',
      desc  = 'Solid payout, hard rules. Score points for your group.',
      minMods = 2, maxMods = 3,
      payoutMult = 1.20,
      pointsBase = 90,
      pointsPerfect = 45,
      pointsBonusObj = 20,
      pointsStackPenalty = 0.35,
    },
    elite = {
      label = 'Elite Offer',
      desc  = 'High payout. More modifiers. Bigger points.',
      minMods = 3, maxMods = 4,
      payoutMult = 1.40,
      pointsBase = 140,
      pointsPerfect = 70,
      pointsBonusObj = 35,
      pointsStackPenalty = 0.30,
    },
    dynasty = {
      label = 'Dynasty Offer',
      desc  = 'The crown. Short fuse. Heavy modifiers. Massive points.',
      minMods = 4, maxMods = 5,
      payoutMult = 1.65,
      pointsBase = 220,
      pointsPerfect = 120,
      pointsBonusObj = 60,
      pointsStackPenalty = 0.25,
    }
  }
}


