local ActiveContracts = {} -- [src] = contract
local ActiveSessions  = {} -- [src] = { netId, bayIndex, done = { [stepKey]=true } }

-- Co-op removed. Use Syndicates.

-- IMPORTANT:
-- ChopShop DB rows are keyed by QBCore/QBox citizenid (values like "D3ZJ9ESN").
-- Previous builds tried to "auto-resolve" citizenid vs license, which can cause
-- reads to miss rows even though writes succeeded. We hard-lock everything to citizenid
-- so reads always match writes.
local function resolveDbId(_, player)
  local cid = player and FW.GetCid(player) or nil
  return cid, cid, nil, nil
end

local function getSourceByCid(cid)
  if not cid then return nil end
  for _, sid in ipairs(GetPlayers()) do
    local p = FW.GetPlayer(tonumber(sid))
    if p and FW.GetCid(p) == cid then
      return tonumber(sid)
    end
  end
  return nil
end

local Cooldowns       = {} -- [src] = os.time()

local function now() return os.time() end

--==============================
-- Syndicate helpers (permissions, settings, buffs)
--==============================
local function rankKey(rank)
  rank = tonumber(rank or 1) or 1
  if rank >= 3 then return 'boss' end
  if rank == 2 then return 'capo' end
  return 'member'
end

local function hasSyndPerm(synd, perm)
  if not synd or not synd.id or synd.id <= 0 then return false end
  local key = rankKey(synd.rank)
  local perms = Config.SyndicatePermissions or {}
  local t = perms[key] or {}
  return t[perm] == true
end

local function getSyndicateContextByCid(cid)
  if not (DB and DB.GetPlayerSyndicate) then return nil end
  local s = DB.GetPlayerSyndicate(cid)
  if not s or (s.id or 0) <= 0 then return nil end
  local settings = (DB and DB.GetSyndicateSettings) and DB.GetSyndicateSettings(s.id) or { routingEnabled=false, routingPercent=0.15, branding={} }
  local perks = (DB and DB.GetSyndicatePerks) and DB.GetSyndicatePerks(s.id) or {}
  local stats = (DB and DB.GetSyndicateStatsAgg) and DB.GetSyndicateStatsAgg(s.id) or {}
  local op = (DB and DB.GetSyndicateOp) and DB.GetSyndicateOp(s.id) or { opId=nil, activeUntil=0, cooldownUntil=0, meta={} }
  return { synd = s, settings = settings, perks = perks, stats = stats, op = op }
end

local function computeSyndicateBuffs(ctx)
  ctx = ctx or {}
  local perks = ctx.perks or {}
  local op = ctx.op or {}
  local tree = (Config.SyndicateTree and Config.SyndicateTree.nodes) or {}
  local mult = {
    payout = 1.0,
    time = 1.0,
    rareRoll = 0.0,
    routingCapAdd = 0.0,
    vaultInterest = 0.0,
    opCooldownMult = 1.0,
    opStrengthMult = 1.0,
    upgradePriceMult = 1.0,
    opsUnlocked = false,
  }

  -- Interpret tree effects from perk levels (stored in perks table)
  for nodeId, lvl in pairs(perks) do
    local n = tree[nodeId]
    lvl = tonumber(lvl or 0) or 0
    if n and lvl > 0 and n.effect then
      if n.effect.payoutMult then mult.payout = mult.payout * (1.0 + (n.effect.payoutMult * lvl)) end
      if n.effect.timeMult then mult.time = mult.time * (1.0 + (n.effect.timeMult * lvl)) end
      if n.effect.rareRoll then mult.rareRoll = mult.rareRoll + (n.effect.rareRoll * lvl) end
      if n.effect.routingCapAdd then mult.routingCapAdd = mult.routingCapAdd + (n.effect.routingCapAdd * lvl) end
      if n.effect.vaultInterest then mult.vaultInterest = mult.vaultInterest + (n.effect.vaultInterest * lvl) end
      if n.effect.opCooldownMult then mult.opCooldownMult = mult.opCooldownMult * (1.0 + (n.effect.opCooldownMult * lvl)) end
      if n.effect.opStrengthMult then mult.opStrengthMult = mult.opStrengthMult * (1.0 + (n.effect.opStrengthMult * lvl)) end
      if n.effect.unlockOps then mult.opsUnlocked = true end
    end
  end

  -- Active operation buffs
  local nowt = now()
  if op and op.opId and (tonumber(op.activeUntil or 0) or 0) > nowt then
    local defs = (Config.SyndicateOperations and Config.SyndicateOperations.defs) or {}
    local d = defs[op.opId]
    if d and d.mult then
      local strength = mult.opStrengthMult or 1.0
      if d.mult.payout then mult.payout = mult.payout * (1.0 + (tonumber(d.mult.payout) or 0) * strength) end
      if d.mult.rareRoll then mult.rareRoll = mult.rareRoll + (tonumber(d.mult.rareRoll) or 0) * strength end
      if d.mult.upgradePrice then mult.upgradePriceMult = mult.upgradePriceMult * (1.0 + (tonumber(d.mult.upgradePrice) or 0) * strength) end
    end
  end

  return mult
end

local function payCashWithRouting(src, player, amount, ctx, reason)
  amount = math.floor(tonumber(amount or 0) or 0)
  if amount <= 0 then return 0, 0 end
  if not player then return 0, 0 end

  if not ctx or not ctx.synd or (ctx.synd.id or 0) <= 0 then
    FW.AddMoney(player, 'cash', amount)
    return amount, 0
  end

  local settings = ctx.settings or { routingEnabled=false, routingPercent=0.15 }
  local routeOn = settings.routingEnabled == true
  local pct = tonumber(settings.routingPercent or 0.0) or 0.0

  local capBase = (Config.SyndicateRevenueRouting and tonumber(Config.SyndicateRevenueRouting.maxPercent or 0.35)) or 0.35
  local buffs = computeSyndicateBuffs(ctx)
  local cap = math.max(0.0, math.min(0.95, capBase + (buffs.routingCapAdd or 0.0)))
  local minP = (Config.SyndicateRevenueRouting and tonumber(Config.SyndicateRevenueRouting.minPercent or 0.0)) or 0.0
  pct = math.max(minP, math.min(cap, pct))

  if not routeOn or pct <= 0.0001 or not (DB and DB.DepositToVault) then
    FW.AddMoney(player, 'cash', amount)
    return amount, 0
  end

  local routed = math.floor(amount * pct)
  local take = math.max(0, math.min(amount, routed))
  local keep = amount - take

  if keep > 0 then FW.AddMoney(player, 'cash', keep) end
  if take > 0 then
    DB.DepositToVault(ctx.synd.id, FW.GetCid(player), take)
    if DB.AddVaultTx then
      DB.AddVaultTx(ctx.synd.id, FW.GetCid(player), take, 'route', reason or 'CONTRACT', { pct = pct })
    end
  end

  return keep, take
end


local function trimPlate(p)
  return (p or ''):gsub('%s+', '')
end

local function onCooldown(src)
  local last = Cooldowns[src] or 0
  return (now() - last) < (Config.Contract.cooldownSeconds or 0)
end

local function setCooldown(src)
  Cooldowns[src] = now()
end

local function getContract(src)
  return ActiveContracts[src]
end

local function clearContract(src)
  local c = ActiveContracts[src]
  ActiveContracts[src] = nil
  ActiveSessions[src] = nil
  return c
end

local function getStepDef(stepKey)
  for _, s in ipairs(Config.AdvancedSteps or {}) do
    if s.key == stepKey then return s end
  end
  return nil
end

local function nonFinalSteps()
  local out = {}
  for _, s in ipairs(Config.AdvancedSteps or {}) do
    if s.key ~= 'final' then
      out[#out+1] = s.key
    end
  end
  return out
end

local NON_FINAL = nonFinalSteps()

-- Step order index (for sorting requiredList consistently)
local STEP_INDEX = {}
do
  local i = 0
  for _, s in ipairs(Config.AdvancedSteps or {}) do
    i = i + 1
    STEP_INDEX[s.key] = i
  end
end

local function stepEnabledServer(stepKey)
  if stepKey == 'vin_scratch' then return Config.V2 and Config.V2.vinScratch end
  if stepKey == 'plate_front' or stepKey == 'plate_rear' then return Config.V2 and Config.V2.removePlates end
  if stepKey == 'move_shell' or stepKey == 'cut_shell' then
    return Config.V3 and Config.V3.enableMoveCutCrush
  end
  return true
end

-- NOTE: GetEntityBoneIndexByName is not available server-side.
-- For V2, the client computes which steps apply to the specific vehicle (based on bones/doors)
-- and sends that list to the server when beginning the chop.
local function computeRequiredStepsFromClient(requiredList)
  local requiredSet = {}
  local cleanList = {}

  -- Build a whitelist set of valid non-final keys
  local valid = {}
  for _, k in ipairs(NON_FINAL) do
    if stepEnabledServer(k) then
      valid[k] = true
    end
  end

  if type(requiredList) == 'table' then
    for _, k in ipairs(requiredList) do
      k = tostring(k or '')
      if valid[k] and not requiredSet[k] then
        requiredSet[k] = true
        cleanList[#cleanList + 1] = k
      end
    end
  end

  -- Fallback: if client didn't send anything usable, require all enabled non-final steps
  if #cleanList == 0 then
    for _, k in ipairs(NON_FINAL) do
      if stepEnabledServer(k) then
        requiredSet[k] = true
        cleanList[#cleanList + 1] = k
      end
    end
  end

  return requiredSet, cleanList
end


local function allNonFinalDone(done, requiredSet)
  requiredSet = requiredSet or {}
  for k, _ in pairs(requiredSet) do
    if not done[k] then return false end
  end
  return true
end

local function randInCircle(radius)
  -- uniform distribution in a circle
  local t = math.random() * 2.0 * math.pi
  local u = math.random()
  local r = math.sqrt(u) * radius
  return r * math.cos(t), r * math.sin(t)
end

--==============================
-- Smarter Contracts: Modifiers
--==============================
local function rollContractModifiers(tierKey)
  local cm = Config.ContractModifiers
  if not cm or not cm.enabled then return {}, { payout = 1.0, alert = 1.0, radius = 1.0, duration = 1.0 }, {} end

  local defs = cm.defs or {}
  local pool = {}
  for id, def in pairs(defs) do
    local w = 0
    if def.weights and def.weights[tierKey] then w = tonumber(def.weights[tierKey]) or 0 end
    if w > 0 then
      pool[#pool+1] = { id = id, w = w, def = def }
    end
  end

  local function pickOne()
    local total = 0
    for _, it in ipairs(pool) do total = total + (it.w or 0) end
    if total <= 0 then return nil end
    local r = math.random() * total
    local acc = 0
    for idx, it in ipairs(pool) do
      acc = acc + (it.w or 0)
      if r <= acc then
        table.remove(pool, idx)
        return it
      end
    end
    return nil
  end

  local minA = tonumber(cm.minActive or 0) or 0
  local maxA = tonumber(cm.maxActive or 2) or 2
  maxA = math.max(minA, maxA)
  local want = math.random(minA, maxA)

  local mods, mults, forced = {}, { payout = 1.0, alert = 1.0, radius = 1.0, duration = 1.0 }, {}
  for _ = 1, want do
    local it = pickOne()
    if not it then break end
    local def = it.def or {}

    mults.payout = mults.payout * (tonumber(def.payoutMult or 1.0) or 1.0)
    mults.alert  = mults.alert  * (tonumber(def.alertMult  or 1.0) or 1.0)
    mults.radius = mults.radius * (tonumber(def.radiusMult or 1.0) or 1.0)
    mults.duration = mults.duration * (tonumber(def.durationMult or 1.0) or 1.0)

    if type(def.addSteps) == 'table' then
      for _, sk in ipairs(def.addSteps) do
        forced[tostring(sk)] = true
      end
    end

    mods[#mods+1] = {
      id = it.id,
      label = tostring(def.label or it.id),
      desc = tostring(def.desc or ''),
    }
  end

  return mods, mults, forced
end

--==============================
-- Bonus Objectives (per-contract)
--==============================
local function rollBonusObjective(tierKey)
  local bo = Config.BonusObjectives
  if not bo or not bo.enabled then return nil end
  local chance = tonumber(bo.chance or 0) or 0
  if chance <= 0 then return nil end
  if math.random(1, 100) > chance then return nil end

  local defs = bo.defs or {}
  local pool, total = {}, 0
  for id, def in pairs(defs) do
    local w = tonumber(def.weight or 0) or 0
    if w > 0 then
      total = total + w
      pool[#pool+1] = { id = id, w = w, def = def }
    end
  end
  if total <= 0 or #pool == 0 then return nil end

  local r = math.random() * total
  local acc = 0
  for _, it in ipairs(pool) do
    acc = acc + (it.w or 0)
    if r <= acc then
      local def = it.def or {}
      return {
        id = it.id,
        label = tostring(def.label or it.id),
        desc = tostring(def.desc or ""),
        moneyMult = tonumber(def.moneyMult or 1.0) or 1.0,
        rep = tonumber(def.rep or 0) or 0,
        timeLimitSeconds = tonumber(def.timeLimitSeconds or 0) or 0,
        minBodyHealthRatio = tonumber(def.minBodyHealthRatio or 0) or 0,
      }
    end
  end
  return nil
end


--==============================
-- Bonus Live Status Helpers
--==============================
local function sendBonusStatus(src, state, reason)
  TriggerClientEvent('gs-chopshop:client:bonusStatus', src, {
    state = state,
    reason = reason or "",
  })
end

local function applyBonusSignal(src, signal, reason)
  local c = getContract(src)
  if not c or not c.bonusObjective or not c.bonusObjective.id then return end

  c.bonus = c.bonus or { state = "active", failed = false, achieved = false, strikes = 0 }
  if c.bonus.state == "completed" or c.bonus.state == "failed" then return end

  local strictFail = false
  if signal == "skillfail" and (c.bonusObjective.id == "flawless_hands") then
    strictFail = true
  end
  if signal == "alert" and (c.bonusObjective.id == "silent_operator") then
    strictFail = true
  end

  if strictFail then
    c.bonus.failed = true
    c.bonus.state = "failed"
    sendBonusStatus(src, "failed", reason or "Objective failed.")
    return
  end

  c.bonus.strikes = (tonumber(c.bonus.strikes or 0) or 0) + 1

  if c.bonus.strikes >= 2 then
    c.bonus.failed = true
    c.bonus.state = "failed"
    sendBonusStatus(src, "failed", reason or "Objective failed.")
  else
    c.bonus.state = "at_risk"
    sendBonusStatus(src, "at_risk", reason or "BONUS AT RISK")
  end
end

local function spawnContractVehicle(contract)
  if not contract then return nil, "no_contract" end

  local model = contract.model
  local tierKey = contract.tier
  local plate = contract.plate

  if type(model) ~= "string" or model == "" then
    print(("[GS-ChopShop] ERROR: contract.model invalid. tier=%s model=%s"):format(tostring(tierKey), tostring(model)))
    return nil, "invalid_model"
  end

  local modelHash = joaat(model)
  if not modelHash or modelHash == 0 then
    print(("[GS-ChopShop] ERROR: joaat failed for model=%s"):format(tostring(model)))
    return nil, "invalid_model"
  end

  -- Pick a random point inside the search radius around the center
  local radius = tonumber(contract.searchRadius) or 180.0
  local cx, cy, cz = contract.searchCenter.x, contract.searchCenter.y, contract.searchCenter.z
  local ox, oy = randInCircle(radius)
  local x, y = cx + ox, cy + oy
  local z = cz + 1.0

  -- Random heading, or use spawnBase heading if you want
  local heading = math.random(0, 359) + 0.0

  -- (Optional) Try load model; depending on artifacts, this may or may not matter server-side
  if RequestModel then
    RequestModel(modelHash)
    local timeout = GetGameTimer() + 5000
    while HasModelLoaded and not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
      Wait(0)
    end
  end

  local veh = CreateVehicle(modelHash, x, y, z, heading, true, true)

  if veh == 0 or not DoesEntityExist(veh) then
    print(('[GS-ChopShop] Failed to spawn vehicle model "%s" (%s)'):format(tostring(model), tostring(modelHash)))
    return nil, "spawn_failed"
  end

  SetVehicleNumberPlateText(veh, plate)
  SetEntityAsMissionEntity(veh, true, true)

  local netId = NetworkGetNetworkIdFromEntity(veh)
  SetNetworkIdExistsOnAllMachines(netId, true)
  SetNetworkIdCanMigrate(netId, false)

  -- store back into contract
  contract.netId = netId

  return veh, nil
end


local function makeContract(src, tierKey, uinfo)
  local tier = Config.Tiers[tierKey]
if not tier or type(tier.vehicles) ~= "table" or #tier.vehicles == 0 then
  print(("[GS-ChopShop] Invalid tier vehicles. tierKey=%s"):format(tostring(tierKey)))
  return nil, "bad_tier"
end

local model = Util.Pick(tier.vehicles)
if type(model) ~= "string" or model == "" then
  print(("[GS-ChopShop] Util.Pick returned nil model. tierKey=%s count=%s"):format(
    tostring(tierKey), tostring(#tier.vehicles)
  ))
  return nil, "bad_model_pick"
end
  local spawnBase = Util.Pick(Config.SpawnPoints)
  local plate = Util.MakePlate()

  -- Roll modifiers (smarter contracts)
  local mods, mmults, forcedSteps = rollContractModifiers(tierKey)

  -- Roll a bonus objective (optional)
  local bonusObj = rollBonusObjective(tierKey)

  local radius = (Config.Search and Config.Search.radius) or 180.0
  radius = radius * (tonumber(mmults.radius or 1.0) or 1.0)
  if uinfo and uinfo.mult and uinfo.mult.radius then
    radius = radius * (tonumber(uinfo.mult.radius) or 1.0)
  end
  local center = vector3(spawnBase.x, spawnBase.y, spawnBase.z)

  local duration = (Config.Contract and Config.Contract.durationSeconds) or 1800
  duration = math.floor(duration * (tonumber(mmults.duration or 1.0) or 1.0))
  duration = math.max(300, duration) -- never under 5 minutes

  local c = {
    tier = tierKey,
    model = model,
    plate = plate,
    spawnBase = spawnBase,
    searchCenter = center,
    searchRadius = radius,
    startedAt = now(),
    expiresAt = now() + duration,
    netId = nil,
    found = false,

    -- modifiers
    modifiers = mods,
    modMult = {
      payout = mmults.payout or 1.0,
      alert = mmults.alert or 1.0,
      radius = mmults.radius or 1.0,
      duration = mmults.duration or 1.0,
    },
    forcedSteps = forcedSteps,

    -- bonus objective (evaluated on completion)
    bonusObjective = bonusObj,
    bonus = { state = bonusObj and "active" or "none", failed = false, achieved = false },
  }

  return c
end

-- Forward declare since it's used before definition below
local getUpgradeInfo

local function giveFinalRewards(src, contract)
  local tier = Config.Tiers[contract.tier]
  if not tier then return 0 end

  local player = FW.GetPlayer(src)
  local dbid = resolveDbId(src, player)
  local syndCtx = getSyndicateContextByCid(dbid)
  local syndBuff = syndCtx and computeSyndicateBuffs(syndCtx) or { upgradePriceMult = 1.0 }
  local uinfo = dbid and getUpgradeInfo(dbid, { priceMult = syndBuff.upgradePriceMult }) or nil

  -- Personal upgrades + contract modifiers
  local payoutMult = (uinfo and uinfo.mult and uinfo.mult.payout) or 1.0
  if contract and contract.modMult and contract.modMult.payout then
    payoutMult = payoutMult * (tonumber(contract.modMult.payout) or 1.0)
  end

  -- Syndicate buffs (tree + active operations)
  local ctx = getSyndicateContextByCid(dbid)
  if ctx then
    local sb = computeSyndicateBuffs(ctx)
    payoutMult = payoutMult * (sb.payout or 1.0)

  -- Black Market War contracts can boost payout
  if contract and contract.bm and contract.bm.payoutMult then
    payoutMult = payoutMult * (tonumber(contract.bm.payoutMult) or 1.0)
  end

  end

  local cash = 0
  if tier.payout and tier.payout.cash then
    cash = Util.RandInt(tier.payout.cash.min or 0, tier.payout.cash.max or 0)
    cash = math.floor(cash * payoutMult)

    if player then
      -- Pay through routing (if enabled)
      payCashWithRouting(src, player, cash, ctx, 'CONTRACT_BASE')
    end
  end

  if tier.items then
    for _, it in ipairs(tier.items) do
      local chance = it.chance or 100
      if math.random(1, 100) <= chance then
        local amt = Util.RandInt(it.min or 1, it.max or 1)
        FW.AddItem(src, it.name, amt)
      end
    end
  end

  return cash
end

local function enforceTierUnlock(src, player, tierKey)
  local cid = FW.GetCid(player)
  local prog = DB.GetTierProgress(cid) or { tier1 = 0, tier2 = 0, tier3 = 0 }
  local rep = (DB and DB.GetRep) and DB.GetRep(cid) or 0
  local rl = Config.RepUnlocks or {}
  prog.rep = (DB.GetRep and DB.GetRep(cid)) or 0
  local req = Config.Unlocks or { tier2RequiresTier1 = 0, tier3RequiresTier2 = 0 }

  if tierKey == 'tier2' and (prog.tier1 or 0) < (req.tier2RequiresTier1 or 0) then
    TriggerClientEvent('gs-chopshop:client:notify', src,
      ('Tier 2 locked. Complete %d Tier 1 contracts.'):format(req.tier2RequiresTier1), 'error')
    return false
  end

  if tierKey == 'tier3' and (prog.tier2 or 0) < (req.tier3RequiresTier2 or 0) then
    TriggerClientEvent('gs-chopshop:client:notify', src,
      ('Tier 3 locked. Complete %d Tier 2 contracts.'):format(req.tier3RequiresTier2), 'error')
    return false
  end

  return true
end

getUpgradeInfo = function(cid, ctx)
  ctx = ctx or {}
  local u = (DB and DB.GetUpgrades) and DB.GetUpgrades(cid) or {}
  local cfg = Config.Upgrades or {}
  local pm = cfg.priceMult or 1.22
  local extraPriceMult = tonumber(ctx and ctx.priceMult or 1.0) or 1.0
  if extraPriceMult <= 0 then extraPriceMult = 1.0 end

  local function priceFor(key, level)
    local uc = cfg[key]
    if not uc then return 0 end
    local base = tonumber(uc.basePrice or 0) or 0
    return math.floor((base * (pm ^ (level or 0))) * extraPriceMult)
  end

  local function clampMin(val, minv)
    minv = tonumber(minv or 0) or 0
    if minv <= 0 then return val end
    return math.max(minv, val)
  end

  local function clampMax(val, maxv)
    maxv = tonumber(maxv or 0) or 0
    if maxv <= 0 then return val end
    return math.min(maxv, val)
  end

  -- multipliers (defaults)
  local mult = {
    time = 1.0,
    payout = 1.0,
    alert = 1.0,
    radius = 1.0,
    final = 1.0,
  }

  -- Apply upgrade effects dynamically based on fields present
  for key, uc in pairs(cfg) do
    if key ~= 'priceAccount' and key ~= 'priceMult' and type(uc) == 'table' then
      local lv = tonumber(u[key] or 0) or 0

      if uc.timeReducePerLevel then
        local v = 1.0 - (tonumber(uc.timeReducePerLevel) or 0) * lv
        mult.time = clampMin(mult.time * v, uc.minTimeMult)
      end

      if uc.payoutBonusPerLevel then
        local v = 1.0 + (tonumber(uc.payoutBonusPerLevel) or 0) * lv
        v = clampMax(v, uc.maxPayoutMult)
        mult.payout = mult.payout * v
      end

      if uc.alertReducePerLevel then
        local v = 1.0 - (tonumber(uc.alertReducePerLevel) or 0) * lv
        mult.alert = clampMin(mult.alert * v, uc.minAlertMult)
      end

      if uc.radiusReducePerLevel then
        local v = 1.0 - (tonumber(uc.radiusReducePerLevel) or 0) * lv
        mult.radius = clampMin(mult.radius * v, uc.minRadiusMult)
      end

      if uc.finalReducePerLevel then
        local v = 1.0 - (tonumber(uc.finalReducePerLevel) or 0) * lv
        mult.final = clampMin(mult.final * v, uc.minFinalMult)
      end
    end
  end

  -- Role + synergy (co-op)
  local role = (DB and DB.GetRole) and DB.GetRole(cid) or nil
  local rolesCfg = Config.Roles or {}
  if rolesCfg.enabled and role and rolesCfg.defs and rolesCfg.defs[role] and rolesCfg.defs[role].mult then
    for k, v in pairs(rolesCfg.defs[role].mult) do
      mult[k] = mult[k] * (tonumber(v) or 1.0)
    end
  end

  
  -- Syndicate perks (shared)
  if DB and DB.GetPlayerSyndicate and DB.GetSyndicatePerks then
    local s = DB.GetPlayerSyndicate(cid)
    if s and (s.id or 0) > 0 then
      local perks = DB.GetSyndicatePerks(s.id)
      local lvPayout = tonumber(perks.payoutMult or 0) or 0
      local lvTime   = tonumber(perks.timeMult or 0) or 0
      local lvRad    = tonumber(perks.radiusMult or 0) or 0
      if lvPayout > 0 then mult.payout = mult.payout * (1.0 + 0.02 * lvPayout) end
      if lvTime > 0 then mult.time   = clampMin(mult.time * (1.0 - 0.02 * lvTime), 0.50) end
      if lvRad > 0 then mult.radius = clampMin(mult.radius * (1.0 - 0.03 * lvRad), 0.50) end
    end
  end

-- If we have a partner, attempt synergy bonuses
  local partnerRole = nil
  if ctx.partnerCid and DB and DB.GetRole then
    partnerRole = DB.GetRole(ctx.partnerCid)
  end
  local synergyLabel = nil
  if rolesCfg.enabled and rolesCfg.synergies and role and partnerRole then
    local a, b = tostring(role), tostring(partnerRole)
    local key1 = a .. '_' .. b
    local key2 = b .. '_' .. a
    local s = rolesCfg.synergies[key1] or rolesCfg.synergies[key2]
    if s and s.mult then
      synergyLabel = s.label
      for k, v in pairs(s.mult) do
        mult[k] = mult[k] * (tonumber(v) or 1.0)
      end
    end
  end

  -- Syndicate passive bonuses
  local synd = (DB and DB.GetPlayerSyndicate) and DB.GetPlayerSyndicate(cid) or nil
  if not synd then synd = { id = 0, name = nil, level = 0, influence = 0, rank = 0 } end
  if Config.Syndicate and Config.Syndicate.enabled then
    local lvl = tonumber(synd.level or 0) or 0
    local per = Config.Syndicate.perLevel or {}
    if per.payout and per.payout ~= 0 then
      mult.payout = mult.payout * (1.0 + math.max(0.0, lvl * (tonumber(per.payout) or 0)))
    end
    if per.time and per.time ~= 0 then
      local t = 1.0 - math.max(0.0, lvl * (tonumber(per.time) or 0))
      mult.time = mult.time * math.max(0.55, t)
    end
  end

  -- Prices + caps (dynamic) + caps (dynamic)
  local prices = {}
  local caps = {}
  for key, uc in pairs(cfg) do
    if key ~= 'priceAccount' and key ~= 'priceMult' and type(uc) == 'table' then
      local lv = tonumber(u[key] or 0) or 0
      prices[key] = priceFor(key, lv)
      caps[key] = tonumber(uc.maxLevel or 0) or 0
    end
  end

  return {
    levels = u,
    prices = prices,
    caps = caps,
    mult = mult,
    role = role,
    partnerRole = partnerRole,
    synergy = synergyLabel,
    syndicate = synd,
  }
end


local function pushData(src)
  local player = FW.GetPlayer(src)
  if not player then return end
  -- DB is keyed by citizenid.
  local cid = FW.GetCid(player)
  local dbid = cid
  local contract = getContract(src)
  local session = ActiveSessions[src]

  local top = (Config.Leaderboard and Config.Leaderboard.enabled) and DB.GetTop(Config.Leaderboard.topCount or 10) or {}
  local topSynd = (Config.Leaderboard and Config.Leaderboard.enabled and DB.GetTopSyndicates) and DB.GetTopSyndicates(Config.Leaderboard.topCount or 10) or {}
  local hist = DB.GetHistory(dbid, 10)
  local prog = DB.GetTierProgress(dbid)
  prog.rep = (DB.GetRep and DB.GetRep(dbid)) or 0
  local profile = (DB.GetProfile and DB.GetProfile(dbid)) or { alias = nil, privacy = 1 }

  local syndCtx = getSyndicateContextByCid(dbid)
  local syndBuff = syndCtx and computeSyndicateBuffs(syndCtx) or { upgradePriceMult = 1.0 }
  local uinfo = dbid and getUpgradeInfo(dbid, { priceMult = syndBuff.upgradePriceMult }) or nil

  -- IMPORTANT: don't send the raw session table.
  -- session.required is a server-side set/map (NOT an ordered list) and it will break the NUI
  -- which expects session.requiredList to be an array.
  local safeSession = nil
  if session then
    safeSession = {
      netId = session.netId,
      bayIndex = session.bayIndex,
      done = session.done or {},
      requiredList = session.requiredList or {},
      startedAt = session.startedAt,
      timeMult = session.timeMult or (uinfo and uinfo.mult and uinfo.mult.time) or 1.0,
      finalMult = session.finalMult or (uinfo and uinfo.mult and uinfo.mult.final) or 1.0,
    }
  end

  TriggerClientEvent('gs-chopshop:client:receiveData', src, {
    serverTime = os.time(),
    me = { citizenid = dbid },
    debug = (type(Config.Debug) == 'table' and Config.Debug.enabled) and {
      dbReady = (DB and DB.Ready) and true or false,
      cid = cid,
      dbid = dbid,
      license = nil,
    } or nil,
    unlocks = Config.Unlocks,
    contract = contract and {
      tier = contract.tier,
      model = contract.model,
      plate = contract.plate,
      startedAt = contract.startedAt,
      expiresAt = contract.expiresAt,
      searchCenter = contract.searchCenter,
      searchRadius = contract.searchRadius,
      found = contract.found and true or false,
      modifiers = contract.modifiers or {},
      special = contract.special and true or false,
      specialTag = contract.specialTag,
    } or nil,
    session = safeSession,
	    leaderboard = top,
	    topSyndicates = topSynd,
    history = hist,
    progress = prog,
    toolMastery = (function()
      local ok, m = pcall(function()
        local r = GetCurrentResourceName()
        if exports and exports[r] and exports[r].GetToolMasteryForCid then
          return exports[r]:GetToolMasteryForCid(dbid)
        end
        return (DB and DB.GetToolMastery and DB.GetToolMastery(dbid)) or nil
      end)
      if ok then return m end
      return nil
    end)(),
    upgrades = uinfo,
    syndicate = (DB and DB.GetPlayerSyndicate) and DB.GetPlayerSyndicate(dbid) or nil,
    syndicateMembers = (DB and DB.GetPlayerSyndicate and DB.GetSyndicateMembers) and (function()
      local s = DB.GetPlayerSyndicate(dbid)
      if s and s.id and s.id > 0 then return DB.GetSyndicateMembers(s.id) end
      return {}
    end)() or {},
    syndicateVault = (DB and DB.GetPlayerSyndicate and DB.GetVault) and (function()
      local s = DB.GetPlayerSyndicate(dbid)
      if s and s.id and s.id > 0 then return DB.GetVault(s.id) end
      return 0
    end)() or 0,
    syndicateVaultTx = (DB and DB.GetPlayerSyndicate and DB.GetVaultTx) and (function()
      local s = DB.GetPlayerSyndicate(dbid)
      if s and s.id and s.id > 0 then return DB.GetVaultTx(s.id, 10) end
      return {}
    end)() or {},
    syndicatePerks = (DB and DB.GetPlayerSyndicate and DB.GetSyndicatePerks) and (function()
      local s = DB.GetPlayerSyndicate(dbid)
      if s and s.id and s.id > 0 then return DB.GetSyndicatePerks(s.id) end
      return {}
    end)() or {},
    syndicateSettings = (DB and DB.GetPlayerSyndicate and DB.GetSyndicateSettings) and (function()
      local s = DB.GetPlayerSyndicate(dbid)
      if s and s.id and s.id > 0 then return DB.GetSyndicateSettings(s.id) end
      return { routingEnabled = false, routingPercent = (Config.SyndicateRevenueRouting and Config.SyndicateRevenueRouting.defaultPercent) or 0.15, branding = {} }
    end)() or nil,
    syndicateStatsAgg = (DB and DB.GetPlayerSyndicate and DB.GetSyndicateStatsAgg) and (function()
      local s = DB.GetPlayerSyndicate(dbid)
      if s and s.id and s.id > 0 then return DB.GetSyndicateStatsAgg(s.id) end
      return {}
    end)() or {},
    syndicateOp = (DB and DB.GetPlayerSyndicate and DB.GetSyndicateOp) and (function()
      local s = DB.GetPlayerSyndicate(dbid)
      if s and s.id and s.id > 0 then return DB.GetSyndicateOp(s.id) end
      return { opId = nil, activeUntil = 0, cooldownUntil = 0, meta = {} }
    end)() or {},
    syndicateTreeCfg = (Config.SyndicateTree and Config.SyndicateTree.nodes) or {},
    syndicateOpsCfg = (Config.SyndicateOperations and Config.SyndicateOperations.defs) or {},
    syndicatePrestigeCfg = Config.SyndicatePrestige or {},

    syndicatePermsCfg = Config.SyndicatePermissions or {},
    syndicateRoutingCfg = Config.SyndicateRevenueRouting or {},
    blackMarketCfg = Config.BlackMarketWar or {},

    roleDefs = nil,
    syndicateCfg = (Config.Syndicate and Config.Syndicate.enabled) and { influencePerLevel = Config.Syndicate.influencePerLevel } or nil,
    syndicatePerkCfg = Config.SyndicatePerks or {},
    syndicatePrestige = (DB and DB.GetPlayerSyndicate and DB.GetSyndicatePrestige) and (function()
      local s = DB.GetPlayerSyndicate(dbid)
      if s and s.id and s.id > 0 then return DB.GetSyndicatePrestige(s.id) end
      return { prestige = 0, points = 0, winStreak = 0 }
    end)() or { prestige = 0, points = 0, winStreak = 0 },
    bmEvent = (War and War.GetState) and War.GetState() or { active = false },
    bmPool = (War and War.GetPool) and War.GetPool() or {},
    bmLeaderboard = (War and War.GetLeaderboard) and War.GetLeaderboard(10) or {},

    profile = profile,
    special = {
      repRequired = (Config.SpecialContracts and Config.SpecialContracts.repRequired) or 0,
      enabled = (Config.SpecialContracts and Config.SpecialContracts.enabled) and true or false,
    },
  })
end

-- Expose internal helpers for other server scripts (Black Market, etc.)
GSCS = GSCS or {}
GSCS.ActiveContracts = ActiveContracts
GSCS.ActiveSessions = ActiveSessions
GSCS.MakeContract = makeContract
GSCS.RollContractModifiers = rollContractModifiers
GSCS.PushData = pushData


RegisterNetEvent('gs-chopshop:server:requestData', function()
  local src = source
  pushData(src)
end)

RegisterNetEvent('gs-chopshop:server:buyUpgrade', function(upgradeId)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end

  upgradeId = tostring(upgradeId or '')
  local cfg = Config.Upgrades or {}
  local uc = cfg[upgradeId]
  if not uc then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Unknown upgrade.', 'error')
    return
  end

  local dbid = resolveDbId(src, player)
  local syndCtx = getSyndicateContextByCid(dbid)
  local syndBuff = syndCtx and computeSyndicateBuffs(syndCtx) or { upgradePriceMult = 1.0 }
  local uinfo = getUpgradeInfo(dbid, { priceMult = syndBuff.upgradePriceMult })
  local levels = (uinfo and uinfo.levels) or {}
  local caps = (uinfo and uinfo.caps) or {}
  local current = tonumber(levels[upgradeId] or 0) or 0
  local cap = tonumber(caps[upgradeId] or uc.maxLevel or 0) or 0
  if cap > 0 and current >= cap then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Upgrade already maxed.', 'error')
    return
  end

  local price = (uinfo and uinfo.prices and uinfo.prices[upgradeId]) or 0
  local acct = cfg.priceAccount or 'cash'
  local have = FW.GetMoney(player, acct)
  if have < price then
    TriggerClientEvent('gs-chopshop:client:notify', src, ('Not enough %s. Need $%d.'):format(acct, price), 'error')
    return
  end

  FW.RemoveMoney(player, acct, price)
  local ok, err = pcall(function()
    DB.SetUpgrade(dbid, upgradeId, current + 1)
  end)
  if not ok then
    -- Refund on DB failure so upgrades never "eat" money.
    FW.AddMoney(player, acct, price)
    print(('^1[gs-chopshop]^0 Upgrade DB error (%s): %s'):format(upgradeId, tostring(err)))
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Upgrade purchase failed (DB). Refunded.', 'error')
    pushData(src)
    return
  end

  TriggerClientEvent('gs-chopshop:client:notify', src,
    ('%s upgraded to Level %d.'):format(uc.label or upgradeId, current + 1), 'success')

  -- Push twice: once now, and again shortly after (covers slower DB backends)
  pushData(src)
  CreateThread(function()
    Wait(350)
    pushData(src)
  end)
end)

-- Admin/debug: instantly simulate a completed chop to test UI/DB without running the whole flow.
-- Usage:
--   /choptest            -> tier1, $5000
--   /choptest tier2      -> tier2, $5000
--   /choptest tier3 9000 -> tier3, $9000
RegisterCommand('choptest', function(src, args)
  if src == 0 then return end

  local allowNoAce = (type(Config.Debug) == 'table' and Config.Debug.AllowChopTestWithoutAce) or false
  if (not allowNoAce) and (not IsPlayerAceAllowed(src, 'gs-chopshop.admin')) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'No permission. (ACE: gs-chopshop.admin)', 'error')
    return
  end

  local player = FW.GetPlayer(src)
  if not player then return end

  local tierKey = tostring(args[1] or 'tier1')
  if not Config.Tiers or not Config.Tiers[tierKey] then tierKey = 'tier1' end

  local earned = tonumber(args[2] or 5000) or 5000
  earned = math.floor(math.max(0, earned))

  local dbid, cid, license = resolveDbId(src, player)
  local name = FW.GetName(player)

  -- Write stats/progress like a successful completion.
  local ok, err = pcall(function()
    if DB and DB.AddResult then
      local baseRep = (Config.Reputation and tonumber(Config.Reputation.basePerChop or 0)) or 0
      DB.AddResult(dbid, name, tierKey, 'debug_test', earned, true, baseRep)
    end
    if DB and DB.AddTierProgress then
      DB.AddTierProgress(dbid, tierKey)
    end
  end)

  if not ok then
    print(('^1[gs-chopshop]^0 /choptest DB error: %s'):format(err))
    TriggerClientEvent('gs-chopshop:client:notify', src, 'DB error, check console.', 'error')
    return
  end

  -- Read back immediately so we can confirm DB writes are working.
  local prog = (DB and DB.GetTierProgress) and DB.GetTierProgress(dbid) or { tier1 = 0, tier2 = 0, tier3 = 0 }
  prog.rep = (DB and DB.GetRep and DB.GetRep(dbid)) or 0

  TriggerClientEvent('gs-chopshop:client:notify', src,
    ('ChopTest: %s +$%d | Progress now: T1=%d T2=%d T3=%d'):format(tierKey, earned, prog.tier1 or 0, prog.tier2 or 0, prog.tier3 or 0),
    'success')

  -- Actually grant the money too (helps verify economy hooks quickly)
  FW.AddMoney(player, 'cash', earned)

  pushData(src)

  CreateThread(function()
    Wait(350)
    pushData(src)
  end)
end, false)

-- Admin/debug: print identifier resolution + DB row counts (helps diagnose "DB has data but UI shows 0").
RegisterCommand('chopdebug', function(src)
  if src == 0 then return end
  if not IsPlayerAceAllowed(src, 'gs-chopshop.admin') then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'No permission. (ACE: gs-chopshop.admin)', 'error')
    return
  end

  local player = FW.GetPlayer(src)
  if not player then return end
  local dbid, cid, license = resolveDbId(src, player)

  local tiersCid = (DB and DB.HasTierRow and cid) and (DB.HasTierRow(cid) and 1 or 0) or 0
  local tiersLic = (DB and DB.HasTierRow and license) and (DB.HasTierRow(license) and 1 or 0) or 0

  local prog = (DB and DB.GetTierProgress) and DB.GetTierProgress(dbid) or { tier1 = 0, tier2 = 0, tier3 = 0 }
  prog.rep = (DB and DB.GetRep and DB.GetRep(dbid)) or 0

  print(('^3[gs-chopshop]^0 chopdebug src=%s cid=%s license=%s dbid=%s tiersRow[cid]=%s tiersRow[license]=%s prog=%s')
    :format(src, tostring(cid), tostring(license), tostring(dbid), tiersCid, tiersLic, json.encode(prog)))

  TriggerClientEvent('gs-chopshop:client:notify', src,
    ('Debug: dbid=%s | TiersRow(citizen)=%s TiersRow(license)=%s | T1=%d T2=%d T3=%d')
      :format(tostring(dbid), tiersCid, tiersLic, prog.tier1 or 0, prog.tier2 or 0, prog.tier3 or 0),
    'success')

  pushData(src)
end, false)

RegisterCommand('choppeek', function(src)
  local rows = DB and DB.PeekIds and DB.PeekIds(10) or {}
  print(('^3[gs-chopshop]^0 choppeek rows=%s'):format(#rows))
  for i, r in ipairs(rows) do
    print(('^3[gs-chopshop]^0 [%d] citizenid=%s tier1=%s tier2=%s tier3=%s'):format(
      i, tostring(r.citizenid), tostring(r.tier1), tostring(r.tier2), tostring(r.tier3)
    ))
  end
end, true)

RegisterCommand('chopdb', function(src)
  local dbName = DB.Scalar("SELECT DATABASE()") or "nil"
  local tiers = DB.Scalar("SELECT COUNT(*) FROM gs_chopshop_tiers") or -1
  local hist  = DB.Scalar("SELECT COUNT(*) FROM gs_chopshop_history") or -1
  local stats = DB.Scalar("SELECT COUNT(*) FROM gs_chopshop_stats") or -1
  local upg   = DB.Scalar("SELECT COUNT(*) FROM gs_chopshop_upgrades") or -1

  print(("^3[gs-chopshop]^0 DB=%s | tiers=%s history=%s stats=%s upgrades=%s"):format(
    tostring(dbName), tostring(tiers), tostring(hist), tostring(stats), tostring(upg)
  ))

  if src and src > 0 then
    TriggerClientEvent('ox_lib:notify', src, {
      title = "ChopShop DB",
      description = ("DB=%s | tiers=%s hist=%s stats=%s upg=%s"):format(dbName, tiers, hist, stats, upg),
      type = "inform"
    })
  end
end, true)


RegisterNetEvent('gs-chopshop:server:startContract', function(tierKey)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local dbid = resolveDbId(src, player)
  local syndCtx = getSyndicateContextByCid(dbid)
  local syndBuff = syndCtx and computeSyndicateBuffs(syndCtx) or { upgradePriceMult = 1.0 }
  local uinfo = dbid and getUpgradeInfo(dbid, { priceMult = syndBuff.upgradePriceMult }) or nil

  if onCooldown(src) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'You must wait before starting another contract.', 'error')
    return
  end

  if getContract(src) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'You already have an active contract.', 'error')
    return
  end

  if not enforceTierUnlock(src, player, tierKey) then
    return
  end

  local contract, err = makeContract(src, tierKey, uinfo)
  if not contract then
    TriggerClientEvent('gs-chopshop:client:notify', src, err or 'Failed to create contract.', 'error')
    return
  end

  ActiveContracts[src] = contract
  setCooldown(src)

-- Ask client to spawn the contract vehicle inside the radius safely

Wait(0) -- one tick is enough

TriggerClientEvent('gs-chopshop:client:spawnContractVehicle', src, {
  model = contract.model,
  plate = contract.plate,
  searchCenter = contract.searchCenter,
  searchRadius = contract.searchRadius
})

  TriggerClientEvent('gs-chopshop:client:beginSearch', src, {
    tier = contract.tier,
    model = contract.model,
    plate = contract.plate,
    startedAt = contract.startedAt,
    expiresAt = contract.expiresAt,
    searchCenter = contract.searchCenter,
    searchRadius = contract.searchRadius,
    modifiers = contract.modifiers or {},
    bonusObjective = contract.bonusObjective,

  })

  pushData(src)
end)

--==============================
-- Special Contracts (rep-gated)
--==============================
RegisterNetEvent('gs-chopshop:server:startSpecialContract', function()
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end

  local sc = Config.SpecialContracts or {}
  if not sc.enabled then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Special contracts are disabled.', 'error')
    return
  end

  if onCooldown(src) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'You must wait before starting another contract.', 'error')
    return
  end
  if getContract(src) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'You already have an active contract.', 'error')
    return
  end

  local cid = FW.GetCid(player)
  local rep = (DB and DB.GetRep) and (DB.GetRep(cid) or 0) or 0
  local need = tonumber(sc.repRequired or 0) or 0
  if rep < need then
    TriggerClientEvent('gs-chopshop:client:notify', src, ('Need %d REP for Special Contracts.'):format(need), 'error')
    return
  end

  local dbid = resolveDbId(src, player)
  local syndCtx = getSyndicateContextByCid(dbid)
  local syndBuff = syndCtx and computeSyndicateBuffs(syndCtx) or { upgradePriceMult = 1.0 }
  local uinfo = dbid and getUpgradeInfo(dbid, { priceMult = syndBuff.upgradePriceMult }) or nil
  local contract, err = makeContract(src, sc.baseTier or 'tier3', uinfo)
  if not contract then
    TriggerClientEvent('gs-chopshop:client:notify', src, err or 'Failed to create special contract.', 'error')
    return
  end

  contract.special = true
  contract.specialTag = tostring(sc.label or 'BLACK OPS')
  contract.modMult = contract.modMult or { payout = 1.0, alert = 1.0, radius = 1.0, duration = 1.0 }
  contract.modMult.payout = (contract.modMult.payout or 1.0) * (tonumber(sc.payoutMult or 1.35) or 1.35)
  contract.modMult.alert  = (contract.modMult.alert or 1.0)  * (tonumber(sc.alertMult  or 1.10) or 1.10)
  -- Make specials always show at least 2 modifiers so it feels different.
  local wantMin = tonumber(sc.minMods or 2) or 2
  if (contract.modifiers and #contract.modifiers or 0) < wantMin then
    -- temporarily bump minActive and reroll
    local oldMin, oldMax = Config.ContractModifiers.minActive, Config.ContractModifiers.maxActive
    Config.ContractModifiers.minActive = wantMin
    Config.ContractModifiers.maxActive = math.max(wantMin, tonumber(sc.maxMods or 3) or 3)
    contract.modifiers, contract.modMult, contract.forcedSteps = rollContractModifiers(contract.tier)
    -- re-apply special mults
    contract.modMult.payout = (contract.modMult.payout or 1.0) * (tonumber(sc.payoutMult or 1.35) or 1.35)
    contract.modMult.alert  = (contract.modMult.alert or 1.0)  * (tonumber(sc.alertMult  or 1.10) or 1.10)
    Config.ContractModifiers.minActive, Config.ContractModifiers.maxActive = oldMin, oldMax
  end

  if sc.forceBonusObjective then
    contract.bonusObjective = rollBonusObjective(contract.tier) or contract.bonusObjective
    contract.bonus = { state = contract.bonusObjective and 'active' or 'none', failed = false, achieved = false }
  end

  ActiveContracts[src] = contract
  setCooldown(src)

  Wait(0)
  TriggerClientEvent('gs-chopshop:client:spawnContractVehicle', src, {
    model = contract.model,
    plate = contract.plate,
    searchCenter = contract.searchCenter,
    searchRadius = contract.searchRadius
  })

  TriggerClientEvent('gs-chopshop:client:beginSearch', src, {
    tier = contract.tier,
    model = contract.model,
    plate = contract.plate,
    startedAt = contract.startedAt,
    expiresAt = contract.expiresAt,
    searchCenter = contract.searchCenter,
    searchRadius = contract.searchRadius,
    modifiers = contract.modifiers or {},
    bonusObjective = contract.bonusObjective,
    specialTag = contract.specialTag,
  })

  pushData(src)
end)

--==============================
-- Profile (alias/privacy)
--==============================
RegisterNetEvent('gs-chopshop:server:setProfile', function(alias, privacy)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local cid = FW.GetCid(player)
  if DB and DB.SetProfile then
    DB.SetProfile(cid, alias, privacy)
  end
  pushData(src)
end)
-- Co-op roles removed. Keep event for backward compatibility.
RegisterNetEvent('gs-chopshop:server:setRole', function()
  local src = source
  TriggerClientEvent('gs-chopshop:client:notify', src, 'Co-op roles removed. Use Syndicate ranks instead.', 'inform')
end)


RegisterNetEvent('gs-chopshop:server:createSyndicate', function(name)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  if not (Config.Syndicate and Config.Syndicate.enabled) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Syndicate disabled.', 'error')
    return
  end

  local cid = FW.GetCid(player)
  if not (DB and DB.CreateSyndicate and DB.GetPlayerSyndicate) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'DB not ready.', 'error')
    return
  end

  local existing = DB.GetPlayerSyndicate(cid)
  if existing and existing.id and existing.id > 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'You are already in a syndicate.', 'error')
    return
  end

  local id, err = DB.CreateSyndicate(cid, name)
  if not id then
    if err == 'invalid' then
      TriggerClientEvent('gs-chopshop:client:notify', src, 'Invalid syndicate name.', 'error')
    else
      TriggerClientEvent('gs-chopshop:client:notify', src, 'Syndicate name taken or creation failed.', 'error')
    end
    return
  end

  TriggerClientEvent('gs-chopshop:client:notify', src, 'Syndicate created.', 'success')
  -- push fresh data so UI updates immediately
  TriggerClientEvent('gs-chopshop:client:forceRefresh', src)
end)

RegisterNetEvent('gs-chopshop:server:syndicate:disband', function()
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local cid = FW.GetCid(player)
  if not (DB and DB.GetPlayerSyndicate and DB.DeleteSyndicate) then return end
  local s = DB.GetPlayerSyndicate(cid)
  if not s or not s.id or s.id <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'No syndicate to disband.', 'error')
    return
  end
  if s.owner ~= cid then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Only the boss can disband.', 'error')
    return
  end
  local members = (DB and DB.GetSyndicateMembers) and DB.GetSyndicateMembers(s.id) or {}
  DB.DeleteSyndicate(s.id)
  TriggerClientEvent('gs-chopshop:client:notify', src, 'Syndicate disbanded.', 'success')
  for i=1, #(members or {}) do
    local mid = members[i] and members[i].citizenid
    if mid then
      local ms = getSourceByCid(mid)
      if ms then TriggerClientEvent('gs-chopshop:client:forceRefresh', ms) end
    end
  end
  TriggerClientEvent('gs-chopshop:client:forceRefresh', src)
end)

RegisterNetEvent('gs-chopshop:server:syndicate:leave', function()
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local cid = FW.GetCid(player)
  if not (DB and DB.GetPlayerSyndicate and DB.RemoveMember) then return end
  local s = DB.GetPlayerSyndicate(cid)
  if not s or not s.id or s.id <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'You are not in a syndicate.', 'error')
    return
  end
  if s.owner == cid then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Boss must disband, not leave.', 'error')
    return
  end
  DB.RemoveMember(s.id, cid)
  TriggerClientEvent('gs-chopshop:client:notify', src, 'You left the syndicate.', 'success')
  TriggerClientEvent('gs-chopshop:client:forceRefresh', src)
end)

RegisterNetEvent('gs-chopshop:server:syndicate:invite', function(targetSrc)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  targetSrc = tonumber(targetSrc or 0) or 0
  if targetSrc <= 0 then return end
  local target = FW.GetPlayer(targetSrc)
  if not target then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Player not found.', 'error')
    return
  end

  local cid = FW.GetCid(player)
  local tcid = FW.GetCid(target)
  if not (DB and DB.GetPlayerSyndicate) then return end
  local s = DB.GetPlayerSyndicate(cid)
  if not s or not s.id or s.id <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Create a syndicate first.', 'error')
    return
  end
  if s.rank < 2 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Not enough rank to invite.', 'error')
    return
  end
  local targetS = DB.GetPlayerSyndicate(tcid)
  if targetS and targetS.id and targetS.id > 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Player already in a syndicate.', 'error')
    return
  end

  TriggerClientEvent('gs-chopshop:client:syndicateInvite', targetSrc, {
    syndicateId = s.id,
    name = s.name,
    from = src,
  })
  TriggerClientEvent('gs-chopshop:client:notify', src, 'Invite sent.', 'success')
end)

RegisterNetEvent('gs-chopshop:server:syndicate:acceptInvite', function(syndId)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local cid = FW.GetCid(player)
  syndId = tonumber(syndId or 0) or 0
  if syndId <= 0 then return end
  if not (DB and DB.AddMember and DB.GetPlayerSyndicate) then return end
  local existing = DB.GetPlayerSyndicate(cid)
  if existing and existing.id and existing.id > 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'You are already in a syndicate.', 'error')
    return
  end
  DB.AddMember(syndId, cid, 1)
  TriggerClientEvent('gs-chopshop:client:notify', src, 'Joined syndicate.', 'success')
  TriggerClientEvent('gs-chopshop:client:forceRefresh', src)
end)

-- Syndicate management (rank + kick)
RegisterNetEvent('gs-chopshop:server:syndicate:setRank', function(targetCid, newRank)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local cid = FW.GetCid(player)
  targetCid = tostring(targetCid or '')
  newRank = tonumber(newRank or 0) or 0
  if targetCid == '' or newRank < 1 or newRank > 3 then return end

  if not (DB and DB.GetPlayerSyndicate and DB.SetMemberRank) then return end
  local s = DB.GetPlayerSyndicate(cid)
  if not s or (s.id or 0) <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'You are not in a syndicate.', 'error')
    return
  end
  local t = DB.GetPlayerSyndicate(targetCid)
  if not t or t.id ~= s.id then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Target not in your syndicate.', 'error')
    return
  end
  if s.rank < 2 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Not enough rank.', 'error')
    return
  end
  if s.rank == 2 then
    if t.rank >= 2 then
      TriggerClientEvent('gs-chopshop:client:notify', src, 'You cannot modify officers/boss.', 'error')
      return
    end
    if newRank ~= 1 then
      TriggerClientEvent('gs-chopshop:client:notify', src, 'Officers cannot promote.', 'error')
      return
    end
  end
  if t.rank == 3 and targetCid ~= cid then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Cannot change boss rank.', 'error')
    return
  end

  DB.SetMemberRank(s.id, targetCid, newRank)
  TriggerClientEvent('gs-chopshop:client:notify', src, 'Rank updated.', 'success')

  TriggerClientEvent('gs-chopshop:client:forceRefresh', src)
  local ts = getSourceByCid(targetCid)
  if ts then TriggerClientEvent('gs-chopshop:client:forceRefresh', ts) end
end)

RegisterNetEvent('gs-chopshop:server:syndicate:kick', function(targetCid)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local cid = FW.GetCid(player)
  targetCid = tostring(targetCid or '')
  if targetCid == '' then return end

  if not (DB and DB.GetPlayerSyndicate and DB.RemoveMember) then return end
  local s = DB.GetPlayerSyndicate(cid)
  if not s or (s.id or 0) <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'You are not in a syndicate.', 'error')
    return
  end
  local t = DB.GetPlayerSyndicate(targetCid)
  if not t or t.id ~= s.id then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Target not in your syndicate.', 'error')
    return
  end
  if t.rank == 3 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Cannot kick the boss.', 'error')
    return
  end
  if s.rank < 2 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Not enough rank.', 'error')
    return
  end
  if s.rank == 2 and t.rank >= 2 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Officers can only kick members.', 'error')
    return
  end

  DB.RemoveMember(s.id, targetCid)
  TriggerClientEvent('gs-chopshop:client:notify', src, 'Member removed.', 'success')
  local ts = getSourceByCid(targetCid)
  if ts then
    TriggerClientEvent('gs-chopshop:client:notify', ts, 'You were removed from the syndicate.', 'error')
    TriggerClientEvent('gs-chopshop:client:forceRefresh', ts)
  end
  TriggerClientEvent('gs-chopshop:client:forceRefresh', src)
end)



-- Syndicate Vault (shared bank)
RegisterNetEvent('gs-chopshop:server:syndicate:deposit', function(amount)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local cid = FW.GetCid(player)
  amount = math.floor(tonumber(amount or 0) or 0)
  if amount <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Invalid amount.', 'error')
    return
  end
  local s = (DB and DB.GetPlayerSyndicate) and DB.GetPlayerSyndicate(cid) or nil
  if not s or (s.id or 0) <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'You are not in a syndicate.', 'error')
    return
  end

  local ok = FW.RemoveMoney(player, 'bank', amount)
  if not ok then
    ok = FW.RemoveMoney(player, 'cash', amount)
  end
  if not ok then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Not enough money.', 'error')
    return
  end

  if DB and DB.DepositToVault then
    DB.DepositToVault(s.id, cid, amount)
  end
  TriggerClientEvent('gs-chopshop:client:notify', src, ('Deposited $%s to vault.'):format(amount), 'success')
  TriggerClientEvent('gs-chopshop:client:forceRefresh', src)
end)

RegisterNetEvent('gs-chopshop:server:syndicate:withdraw', function(amount)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local cid = FW.GetCid(player)
  amount = math.floor(tonumber(amount or 0) or 0)
  if amount <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Invalid amount.', 'error')
    return
  end
  local s = (DB and DB.GetPlayerSyndicate) and DB.GetPlayerSyndicate(cid) or nil
  if not s or (s.id or 0) <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'You are not in a syndicate.', 'error')
    return
  end
  -- Capo+ can withdraw
  if (s.rank or 1) < 2 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Not enough rank to withdraw.', 'error')
    return
  end

  local ok, err = (DB and DB.WithdrawFromVault) and DB.WithdrawFromVault(s.id, cid, amount)
  if not ok then
    TriggerClientEvent('gs-chopshop:client:notify', src, (err == 'insufficient') and 'Vault is empty.' or 'Withdraw failed.', 'error')
    return
  end
  FW.AddMoney(player, 'bank', amount)
  TriggerClientEvent('gs-chopshop:client:notify', src, ('Withdrew $%s from vault.'):format(amount), 'success')
  TriggerClientEvent('gs-chopshop:client:forceRefresh', src)
end)

-- Syndicate Influence Shop (shared perks)
RegisterNetEvent('gs-chopshop:server:syndicate:buyPerk', function(perkId)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local cid = FW.GetCid(player)
  perkId = tostring(perkId or '')
  if perkId == '' then return end

  local s = (DB and DB.GetPlayerSyndicate) and DB.GetPlayerSyndicate(cid) or nil
  if not s or (s.id or 0) <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'You are not in a syndicate.', 'error')
    return
  end

  if not hasSyndPerm(s, 'purchase') then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Not enough rank to purchase upgrades.', 'error')
    return
  end

  local tree = (Config.SyndicateTree and Config.SyndicateTree.nodes) or {}
  local node = tree[perkId]
  local perks = (DB and DB.GetSyndicatePerks) and DB.GetSyndicatePerks(s.id) or {}
  local cur = tonumber(perks[perkId] or 0) or 0

  -- If node doesn't exist in the new tree, fall back to legacy influence shop (kept for backwards compat)
  if not node then
    local perkCfg = (Config.SyndicatePerks or {})[perkId]
    if not perkCfg then
      TriggerClientEvent('gs-chopshop:client:notify', src, 'Unknown upgrade.', 'error')
      return
    end
    local cap = tonumber(perkCfg.maxLevel or 0) or 0
    if cap > 0 and cur >= cap then
      TriggerClientEvent('gs-chopshop:client:notify', src, 'Already maxed.', 'error')
      return
    end
    local cost = tonumber(perkCfg.baseCost or 0) or 0
    local growth = tonumber(perkCfg.growth or 0) or 0
    local price = math.floor(cost * ((1.0 + growth) ^ cur))
    if (s.influence or 0) < price then
      TriggerClientEvent('gs-chopshop:client:notify', src, ('Not enough influence. Need %s.'):format(price), 'error')
      return
    end
    if DB and DB.SetSyndicateStats then
      DB.SetSyndicateStats(s.id, s.level or 0, (s.influence or 0) - price)
    end
    if DB and DB.SetSyndicatePerk then
      DB.SetSyndicatePerk(s.id, perkId, cur + 1)
    end
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Upgrade purchased.', 'success')
  else
    local cap = tonumber(node.maxLevel or 0) or 0
    if cap > 0 and cur >= cap then
      TriggerClientEvent('gs-chopshop:client:notify', src, 'Already maxed.', 'error')
      return
    end

    local minLevel = tonumber(node.minLevel or 0) or 0
    if (tonumber(s.level or 0) or 0) < minLevel then
      TriggerClientEvent('gs-chopshop:client:notify', src, ('Requires Syndicate Level %d.'):format(minLevel), 'error')
      return
    end

    if node.requires and type(node.requires) == 'table' then
      for reqId, reqLv in pairs(node.requires) do
        local haveLv = tonumber(perks[reqId] or 0) or 0
        if haveLv < (tonumber(reqLv or 0) or 0) then
          TriggerClientEvent('gs-chopshop:client:notify', src, 'Missing prerequisite upgrade(s).', 'error')
          return
        end
      end
    end

    local baseFunds = tonumber(node.cost and node.cost.funds or 0) or 0
    local baseInf   = tonumber(node.cost and node.cost.influence or 0) or 0
    local growth    = tonumber(node.cost and node.cost.growth or 0) or 0

    local fundsCost = math.floor(baseFunds * ((1.0 + growth) ^ cur))
    local infCost   = math.floor(baseInf   * ((1.0 + growth) ^ cur))

    if fundsCost < 0 then fundsCost = 0 end
    if infCost < 0 then infCost = 0 end

    local vault = (DB and DB.GetVault) and DB.GetVault(s.id) or 0
    if vault < fundsCost then
      TriggerClientEvent('gs-chopshop:client:notify', src, ('Syndicate funds too low. Need $%d.'):format(fundsCost), 'error')
      return
    end
    if (tonumber(s.influence or 0) or 0) < infCost then
      TriggerClientEvent('gs-chopshop:client:notify', src, ('Not enough influence. Need %d.'):format(infCost), 'error')
      return
    end

    -- Spend funds + influence
    if fundsCost > 0 and DB and DB.WithdrawFromVault then
      local ok = DB.WithdrawFromVault(s.id, cid, fundsCost)
      if not ok then
        TriggerClientEvent('gs-chopshop:client:notify', src, 'Funds spend failed.', 'error')
        return
      end
      if DB.AddVaultTx then
        DB.AddVaultTx(s.id, cid, fundsCost, 'perk', ('PERK:%s'):format(perkId), { nextLevel = cur + 1 })
      end
    end

    if infCost > 0 and DB and DB.SetSyndicateStats then
      DB.SetSyndicateStats(s.id, s.level or 0, (tonumber(s.influence or 0) or 0) - infCost)
    end

    if DB and DB.SetSyndicatePerk then
      DB.SetSyndicatePerk(s.id, perkId, cur + 1)
    end

    TriggerClientEvent('gs-chopshop:client:notify', src, 'Syndicate upgrade unlocked.', 'success')
  end

  -- Refresh all online members
  local members = (DB and DB.GetSyndicateMembers) and DB.GetSyndicateMembers(s.id) or {}
  for i=1, #(members or {}) do
    local mid = members[i] and members[i].citizenid
    local ms = mid and getSourceByCid(mid)
    if ms then TriggerClientEvent('gs-chopshop:client:forceRefresh', ms) end
  end

-- Syndicate routing + branding + operations
RegisterNetEvent('gs-chopshop:server:syndicate:setRouting', function(enabled, percent)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local cid = FW.GetCid(player)

  local s = (DB and DB.GetPlayerSyndicate) and DB.GetPlayerSyndicate(cid) or nil
  if not s or (s.id or 0) <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'No syndicate.', 'error')
    return
  end
  if not hasSyndPerm(s, 'routing') then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Not allowed.', 'error')
    return
  end

  local cfg = Config.SyndicateRevenueRouting or {}
  local pct = tonumber(percent or cfg.defaultPercent or 0.15) or 0.15
  pct = math.max(tonumber(cfg.minPercent or 0.0) or 0.0, math.min(tonumber(cfg.maxPercent or 0.35) or 0.35, pct))

  if DB and DB.SetSyndicateSettings then
    local cur = (DB.GetSyndicateSettings and DB.GetSyndicateSettings(s.id)) or { branding = {} }
    cur.routingEnabled = enabled and true or false
    cur.routingPercent = pct
    DB.SetSyndicateSettings(s.id, cur)
  end

  TriggerClientEvent('gs-chopshop:client:notify', src, 'Routing updated.', 'success')
  local members = (DB and DB.GetSyndicateMembers) and DB.GetSyndicateMembers(s.id) or {}
  for i=1, #(members or {}) do
    local ms = getSourceByCid(members[i].citizenid)
    if ms then TriggerClientEvent('gs-chopshop:client:forceRefresh', ms) end
  end
end)

RegisterNetEvent('gs-chopshop:server:syndicate:setBranding', function(branding)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local cid = FW.GetCid(player)

  local s = (DB and DB.GetPlayerSyndicate) and DB.GetPlayerSyndicate(cid) or nil
  if not s or (s.id or 0) <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'No syndicate.', 'error')
    return
  end
  if not hasSyndPerm(s, 'branding') then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Not allowed.', 'error')
    return
  end

  branding = branding or {}
  if type(branding) ~= 'table' then branding = {} end
  branding.tag = branding.tag and tostring(branding.tag):sub(1, 12) or nil
  branding.color = branding.color and tostring(branding.color):sub(1, 16) or nil
  branding.logo = branding.logo and tostring(branding.logo):sub(1, 32) or nil

  if DB and DB.SetSyndicateSettings then
    local cur = (DB.GetSyndicateSettings and DB.GetSyndicateSettings(s.id)) or {}
    cur.branding = branding
    DB.SetSyndicateSettings(s.id, cur)
  end

  TriggerClientEvent('gs-chopshop:client:notify', src, 'Branding updated.', 'success')
  local members = (DB and DB.GetSyndicateMembers) and DB.GetSyndicateMembers(s.id) or {}
  for i=1, #(members or {}) do
    local ms = getSourceByCid(members[i].citizenid)
    if ms then TriggerClientEvent('gs-chopshop:client:forceRefresh', ms) end
  end
end)

RegisterNetEvent('gs-chopshop:server:syndicate:startOp', function(opId)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end
  local cid = FW.GetCid(player)

  local s = (DB and DB.GetPlayerSyndicate) and DB.GetPlayerSyndicate(cid) or nil
  if not s or (s.id or 0) <= 0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'No syndicate.', 'error')
    return
  end
  if not hasSyndPerm(s, 'ops') then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Not allowed.', 'error')
    return
  end

  local defs = (Config.SyndicateOperations and Config.SyndicateOperations.defs) or {}
  local d = defs[tostring(opId or '')]
  if not d then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Unknown operation.', 'error')
    return
  end

  local ctx = getSyndicateContextByCid(cid)
  local buffs = computeSyndicateBuffs(ctx)
  if not buffs.opsUnlocked then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Operations locked. Unlock Operations Department first.', 'error')
    return
  end

  local opState = (DB and DB.GetSyndicateOp) and DB.GetSyndicateOp(s.id) or { activeUntil=0, cooldownUntil=0 }
  local tnow = now()
  if (tonumber(opState.cooldownUntil or 0) or 0) > tnow then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Operation on cooldown.', 'error')
    return
  end
  if (tonumber(opState.activeUntil or 0) or 0) > tnow then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'An operation is already active.', 'error')
    return
  end

  local minLevel = tonumber(d.cost and d.cost.minLevel or d.cost and d.cost.level or 0) or 0
  if (tonumber(s.level or 0) or 0) < minLevel then
    TriggerClientEvent('gs-chopshop:client:notify', src, ('Requires Syndicate Level %d.'):format(minLevel), 'error')
    return
  end

  local fundsCost = math.floor(tonumber(d.cost and d.cost.funds or 0) or 0)
  local infCost = math.floor(tonumber(d.cost and d.cost.influence or 0) or 0)
  local vault = (DB and DB.GetVault) and DB.GetVault(s.id) or 0
  if vault < fundsCost then
    TriggerClientEvent('gs-chopshop:client:notify', src, ('Syndicate funds too low. Need $%d.'):format(fundsCost), 'error')
    return
  end
  if (tonumber(s.influence or 0) or 0) < infCost then
    TriggerClientEvent('gs-chopshop:client:notify', src, ('Not enough influence. Need %d.'):format(infCost), 'error')
    return
  end

  if fundsCost > 0 and DB and DB.WithdrawFromVault then
    local ok = DB.WithdrawFromVault(s.id, cid, fundsCost)
    if not ok then
      TriggerClientEvent('gs-chopshop:client:notify', src, 'Funds spend failed.', 'error')
      return
    end
    if DB.AddVaultTx then
      DB.AddVaultTx(s.id, cid, fundsCost, 'op', ('OP:%s'):format(opId), {})
    end
  end
  if infCost > 0 and DB and DB.SetSyndicateStats then
    DB.SetSyndicateStats(s.id, s.level or 0, (tonumber(s.influence or 0) or 0) - infCost)
  end

  local dur = math.floor((tonumber(d.durationMinutes or 0) or 0) * 60)
  local cd  = math.floor((tonumber(d.cooldownMinutes or 0) or 0) * 60)
  local cdMult = buffs.opCooldownMult or 1.0
  local activeUntil = tnow + math.max(60, dur)
  local cooldownUntil = activeUntil + math.floor(cd * cdMult)

  if DB and DB.SetSyndicateOp then
    DB.SetSyndicateOp(s.id, tostring(opId), activeUntil, cooldownUntil, {})
  end

  TriggerClientEvent('gs-chopshop:client:notify', src, 'Operation started.', 'success')
  local members = (DB and DB.GetSyndicateMembers) and DB.GetSyndicateMembers(s.id) or {}
  for i=1, #(members or {}) do
    local ms = getSourceByCid(members[i].citizenid)
    if ms then TriggerClientEvent('gs-chopshop:client:forceRefresh', ms) end
  end
end)

end)


-- Co-op system removed. Use Syndicates.

RegisterNetEvent('gs-chopshop:server:cancelContract', function()
  local src = source
  local c = getContract(src)
  if not c then return end

  if c.netId then
    local veh = NetworkGetEntityFromNetworkId(c.netId)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
      DeleteEntity(veh)
    end
  end

  clearContract(src)
  TriggerClientEvent('gs-chopshop:client:contractCanceled', src)
  pushData(src)
end)


RegisterNetEvent('gs-chopshop:server:registerSpawnedVehicle', function(netId, plate)
  local src = source
  local c = getContract(src)
  if not c then return end

  if not netId or tonumber(netId) == nil then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Vehicle spawn failed (no netId).', 'error')
    clearContract(src)
    return
  end

  if trimPlate(plate) ~= trimPlate(c.plate) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Vehicle spawn failed (plate mismatch).', 'error')
    clearContract(src)
    return
  end

  c.netId = tonumber(netId)

  -- PD alert on start (now that the vehicle exists)
  if Config.PDAlert and Config.PDAlert.enabled and Config.PDAlert.onStart then
    local veh = NetworkGetEntityFromNetworkId(c.netId)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
      local player = FW.GetPlayer(src)
      local dbid = resolveDbId(src, player)
      local syndCtx = getSyndicateContextByCid(dbid)
  local syndBuff = syndCtx and computeSyndicateBuffs(syndCtx) or { upgradePriceMult = 1.0 }
  local uinfo = dbid and getUpgradeInfo(dbid, { priceMult = syndBuff.upgradePriceMult }) or nil
      local mult = (uinfo and uinfo.mult and uinfo.mult.alert) or 1.0
      if c and c.modMult and c.modMult.alert then
        mult = mult * (tonumber(c.modMult.alert) or 1.0)
      end
      local alerted = Alerts.Try(src, c.tier, GetEntityCoords(veh), c.plate, c.model, mult)
      if alerted then applyBonusSignal(src, "alert", "Alert triggered") end
    end
  end
end)


RegisterNetEvent('gs-chopshop:server:markFound', function(netId, plate)
  local src = source
  local c = getContract(src)
  if not c then return end
  if c.found then return end

  if trimPlate(plate) ~= trimPlate(c.plate) then return end

  -- accept and store whatever netId the player found
  c.netId = tonumber(netId) or c.netId
  c.found = true

  TriggerClientEvent('gs-chopshop:client:foundAck', src)
end)


RegisterNetEvent('gs-chopshop:server:beginChop', function(netId, bayIndex, requiredList)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end

  local c = getContract(src)
  if not c then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'No active contract.', 'error')
    return
  end

  if now() > c.expiresAt then
    clearContract(src)
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Contract expired.', 'error')
    return
  end

  if ActiveSessions[src] then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Chop already in progress.', 'error')
    return
  end

  if tonumber(netId) ~= tonumber(c.netId) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'This is not your contract vehicle.', 'error')
    return
  end

  local veh = NetworkGetEntityFromNetworkId(netId)
  if not veh or veh == 0 or not DoesEntityExist(veh) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Vehicle missing.', 'error')
    return
  end

  if trimPlate(GetVehicleNumberPlateText(veh)) ~= trimPlate(c.plate) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Wrong plate.', 'error')
    return
  end

  if GetEntityModel(veh) ~= joaat(c.model) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Wrong model.', 'error')
    return
  end

  local ped = GetPlayerPed(src)
  if ped and ped ~= 0 then
    local driver = GetPedInVehicleSeat(veh, -1)
    if driver ~= ped then
      TriggerClientEvent('gs-chopshop:client:notify', src, 'You must be the driver.', 'error')
      return
    end
  end

  bayIndex = tonumber(bayIndex) or 1
  local bay = (Config.Bays and Config.Bays[bayIndex]) or (Config.ChopSpots and Config.ChopSpots[bayIndex])
  if not bay then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Invalid chop bay.', 'error')
    return
  end

  local vpos = GetEntityCoords(veh)
  local bpos = vector3(bay.x, bay.y, bay.z)
  if #(vpos - bpos) > 7.0 then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Pull closer into the bay.', 'error')
    return
  end

  if Config.PDAlert and Config.PDAlert.enabled and Config.PDAlert.onArrival then
    local player = FW.GetPlayer(src)
    local dbid = resolveDbId(src, player)
    local syndCtx = getSyndicateContextByCid(dbid)
  local syndBuff = syndCtx and computeSyndicateBuffs(syndCtx) or { upgradePriceMult = 1.0 }
  local uinfo = dbid and getUpgradeInfo(dbid, { priceMult = syndBuff.upgradePriceMult }) or nil
    local mult = (uinfo and uinfo.mult and uinfo.mult.alert) or 1.0
    if c and c.modMult and c.modMult.alert then
      mult = mult * (tonumber(c.modMult.alert) or 1.0)
    end
    local alerted = Alerts.Try(src, c.tier, vpos, c.plate, c.model, mult)
      if alerted then applyBonusSignal(src, "alert", "Alert triggered") end
  end

  local requiredSet, requiredList = computeRequiredStepsFromClient(requiredList)

  -- Apply forced steps from smarter-contract modifiers
  if c and c.forcedSteps and type(c.forcedSteps) == 'table' then
    for sk, _ in pairs(c.forcedSteps) do
      sk = tostring(sk)
      if sk ~= '' and sk ~= 'final' then
        if (Config.ContractModifiers and Config.ContractModifiers.forceStepsOn) or stepEnabledServer(sk) then
          if not requiredSet[sk] then
            requiredSet[sk] = true
            requiredList[#requiredList+1] = sk
          end
        end
      end
    end
  end

  -- Sort requiredList by configured workflow order
  table.sort(requiredList, function(a, b)
    return (STEP_INDEX[a] or 9999) < (STEP_INDEX[b] or 9999)
  end)

  local player = FW.GetPlayer(src)
  local dbid = resolveDbId(src, player)
  local syndCtx = getSyndicateContextByCid(dbid)
  local syndBuff = syndCtx and computeSyndicateBuffs(syndCtx) or { upgradePriceMult = 1.0 }
  local uinfo = dbid and getUpgradeInfo(dbid, { priceMult = syndBuff.upgradePriceMult }) or nil
  local mults = (uinfo and uinfo.mult) or {}

ActiveSessions[src] = {
  netId = netId,
  bayIndex = bayIndex,
  done = {},
  required = requiredSet,
  requiredList = requiredList,
  startedAt = now(),
  timeMult = mults.time or 1.0,
  finalMult = mults.final or 1.0,
  failedSkill = false,
  alertTriggered = (c and c.bonus and c.bonus.failed) and true or false,
  startBodyHealth = GetVehicleBodyHealth(veh) or 1000.0,

}

TriggerClientEvent('gs-chopshop:client:chopSessionStarted', src, {
  netId = netId,
  bayIndex = bayIndex,
  done = {},
  -- IMPORTANT: client/NUI expects an ordered array called requiredList.
  requiredList = requiredList,
  timeMult = mults.time or 1.0,
  finalMult = mults.final or 1.0,
})
end)


-- Client can report a failed skill check for bonus objectives
RegisterNetEvent("gs-chopshop:server:noteSkillFail", function()
  local src = source
  local sess = ActiveSessions[src]
  if sess then
    sess.failedSkill = true
  end
  applyBonusSignal(src, "skillfail", "Skill check failed")
end)


RegisterNetEvent('gs-chopshop:server:completeStep', function(stepKey)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end

  local c = getContract(src)
  local sess = ActiveSessions[src]
  if not c or not sess then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'No active chop session.', 'error')
    return
  end

  stepKey = tostring(stepKey or '')
  local def = getStepDef(stepKey)
  if not def then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Invalid step.', 'error')
    return
  end

if stepKey ~= 'final' then
  if not sess.required or not sess.required[stepKey] then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'That step is not required for this vehicle.', 'error')
    return
  end
end

  -- Optional strict ordering (prevents skipping to later workflow stages)
  if stepKey ~= 'final' and Config.V3 and Config.V3.enforceStepOrder then
    for _, s in ipairs(Config.AdvancedSteps or {}) do
      local k = tostring(s.key or '')
      if k == '' or k == 'final' then goto continue_order end
      if not stepEnabledServer(k) then goto continue_order end

      -- Stop once we reached the requested step
      if k == stepKey then break end

      -- Only enforce required steps for this vehicle
      if sess.required and sess.required[k] and not sess.done[k] then
        TriggerClientEvent('gs-chopshop:client:notify', src, 'Finish earlier steps first.', 'error')
        return
      end

      ::continue_order::
    end
  end

  if sess.done[stepKey] then return end

  local veh = NetworkGetEntityFromNetworkId(sess.netId)
  if not veh or veh == 0 or not DoesEntityExist(veh) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Vehicle missing.', 'error')
    clearContract(src)
    return
  end

  if trimPlate(GetVehicleNumberPlateText(veh)) ~= trimPlate(c.plate) then
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Wrong vehicle.', 'error')
    return
  end

  local ped = GetPlayerPed(src)
  if ped and ped ~= 0 then
    local ppos = GetEntityCoords(ped)
    local vpos = GetEntityCoords(veh)

    if stepKey ~= 'final' then
      if #(ppos - vpos) > 6.0 then
        TriggerClientEvent('gs-chopshop:client:notify', src, 'Get closer to the vehicle.', 'error')
        return
      end
    else
      if not allNonFinalDone(sess.done, sess.required) then
        TriggerClientEvent('gs-chopshop:client:notify', src, 'Strip all parts before disposing the shell.', 'error')
        return
      end

      local bay = (Config.Bays and Config.Bays[sess.bayIndex]) or (Config.ChopSpots and Config.ChopSpots[sess.bayIndex])
      local bpos = vector3(bay.x, bay.y, bay.z)
      if #(ppos - bpos) > 6.0 then
        TriggerClientEvent('gs-chopshop:client:notify', src, 'Step into the bay to dispose.', 'error')
        return
      end
    end
  end

  sess.done[stepKey] = true
  TriggerClientEvent('gs-chopshop:client:stepAck', src, stepKey)

  if stepKey == 'final' then
    local cash = giveFinalRewards(src, c)

    -- Reputation perk payout bonus
    local repNow = 0
    local dbidForRep = resolveDbId(src, player)
    if DB and DB.GetRep and dbidForRep then repNow = DB.GetRep(dbidForRep) end
    local repMult = computeRepPayoutMult(repNow)
    if repMult > 1.0 then
      local repExtra = math.floor(cash * math.max(0.0, repMult - 1.0))
      if repExtra > 0 then
        local p = FW.GetPlayer(src)
        if p then payCashWithRouting(src, p, repExtra, getSyndicateContextByCid(resolveDbId(src, p)), "REP_BONUS") end
        cash = cash + repExtra
      end
    end

    -- Bonus objective evaluation (money + reputation)
    local bonusAchieved, bonusMult, bonusRep = false, 1.0, 0
    if c and c.bonusObjective and c.bonusObjective.id then
      local bo = c.bonusObjective
      local failed = (c.bonus and c.bonus.failed) or false
      if bo.id == "speed_run" and (bo.timeLimitSeconds or 0) > 0 then
        bonusAchieved = (not failed) and ((now() - (c.startedAt or now())) <= bo.timeLimitSeconds)
      elseif bo.id == "clean_work" and (bo.minBodyHealthRatio or 0) > 0 then
        local startH = tonumber(sess.startBodyHealth or 1000.0) or 1000.0
        local endH = tonumber(GetVehicleBodyHealth(veh) or 1000.0) or 1000.0
        if startH <= 0 then startH = 1000.0 end
        bonusAchieved = (not failed) and ((endH / startH) >= bo.minBodyHealthRatio)
      elseif bo.id == "silent_operator" then
        bonusAchieved = (not failed) and (not (sess.alertTriggered or false))
      elseif bo.id == "flawless_hands" then
        bonusAchieved = (not failed) and (not (sess.failedSkill or false))
      end

      if bonusAchieved then
        bonusMult = tonumber(bo.moneyMult or 1.0) or 1.0
        bonusRep = tonumber(bo.rep or 0) or 0
        local extra = math.floor(cash * math.max(0.0, (bonusMult - 1.0)))
        if extra > 0 then
          local p = FW.GetPlayer(src)
          if p then payCashWithRouting(src, p, extra, getSyndicateContextByCid(resolveDbId(src, p)), "BONUS_OBJ") end
          cash = cash + extra
        end
      end

      c.bonus = c.bonus or { state = "active", failed = false, achieved = false }
      c.bonus.achieved = bonusAchieved
      if bonusAchieved then
        c.bonus.state = "completed"
        sendBonusStatus(src, "completed", "Bonus objective completed")
      else
        c.bonus.state = "failed"
        sendBonusStatus(src, "failed", "Bonus objective failed")
      end
    end


    local dbid = resolveDbId(src, player)
    local name = FW.GetName(player)

    local ok, err = pcall(function()
      if DB and DB.AddResult then
        local baseRep = (Config.Reputation and tonumber(Config.Reputation.basePerChop or 0)) or 0
        local repGain = baseRep
        if bonusAchieved and bonusRep and bonusRep > 0 then repGain = repGain + bonusRep end
        DB.AddResult(dbid, name, c.tier, c.model, cash, true, repGain)

        -- Co-op removed: Syndicate members coordinate externally.
      end
      if DB and DB.AddTierProgress then
        DB.AddTierProgress(dbid, c.tier)
      end

      -- Syndicate progression: earn influence, auto-level based on total influence.
      if Config.Syndicate and Config.Syndicate.enabled and DB and DB.GetPlayerSyndicate and DB.AddSyndicateInfluence and DB.SetSyndicateStats then
        local baseInf = tonumber(Config.Syndicate.influenceBase or 0) or 0
        local byTier = Config.Syndicate.influenceByTier or {}
        local tierKey = tostring(c.tier)
        local gain = math.floor(baseInf + (tonumber(byTier[tierKey] or byTier[c.tier] or 0) or 0))

        if gain > 0 then
          local s = DB.GetPlayerSyndicate(dbid)
          if s and s.id and s.id > 0 then
            DB.AddSyndicateInfluence(s.id, gain)

            -- Syndicate aggregate stats
            if DB and DB.AddSyndicateStatsAgg then
              DB.AddSyndicateStatsAgg(s.id, { contractsCompleted = 1, earningsTotal = cash, influenceTotal = gain, bestPayout = cash })
            end

            -- Black Market War scoring (group competitive ladder)
            if c and c.bm and War and War.AwardOnCompletion then
              local perfect = (not (sess.alertTriggered or false)) and (not (sess.failedSkill or false))
              War.AwardOnCompletion(s.id, c, { perfect = perfect, bonusAchieved = bonusAchieved })
            end


            -- Auto-level based on influence
            local per = tonumber(Config.Syndicate.influencePerLevel or 100) or 100
            local updated = DB.GetPlayerSyndicate(dbid)
            local inf = tonumber(updated and updated.influence or 0) or 0
            local newLvl = math.floor(inf / math.max(1, per))
            if newLvl ~= (tonumber(updated and updated.level or 0) or 0) then
              DB.SetSyndicateStats(s.id, newLvl, inf)
            end
          else
            -- Fallback to old per-player influence if not in a syndicate
            if DB.AddInfluence and DB.GetSyndicate and DB.SetSyndicate then
              DB.AddInfluence(dbid, gain)
              local s2 = DB.GetSyndicate(dbid)
              local per = tonumber(Config.Syndicate.influencePerLevel or 100) or 100
              local inf2 = tonumber(s2 and s2.influence or 0) or 0
              local lvl2 = math.floor(inf2 / math.max(1, per))
              if lvl2 ~= (tonumber(s2 and s2.level or 0) or 0) then
                DB.SetSyndicate(dbid, lvl2, inf2)
              end
            end
          end
        end
      end

    end)

    if not ok then
      print(('^1[gs-chopshop]^0 DB update failed on completion: %s'):format(err))
    end

    if DoesEntityExist(veh) then
      DeleteEntity(veh)
    end

    clearContract(src)

    local msg = ("Chop complete! Earned $%d + materials."):format(cash)
    if bonusAchieved and bonusRep and bonusRep > 0 then
      msg = msg .. (" (+%d rep)"):format(bonusRep)
    end
    TriggerClientEvent('gs-chopshop:client:notify', src, msg, 'success')
    TriggerClientEvent('gs-chopshop:client:contractCompleted', src, cash, { bonus = c and c.bonusObjective or nil, bonusAchieved = bonusAchieved, bonusRep = bonusRep })

    pushData(src)
    CreateThread(function()
      Wait(350)
      pushData(src)
    end)
  end
end)

AddEventHandler('playerDropped', function()
  local src = source
  local c = ActiveContracts[src]
  if c and c.netId then
    local veh = NetworkGetEntityFromNetworkId(c.netId)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
      DeleteEntity(veh)
    end
  end
  ActiveContracts[src] = nil
  ActiveSessions[src] = nil
  Cooldowns[src] = nil
end)

CreateThread(function()
  FW.Init()
  DB.Init()

  FW.RegisterUsableItem(Config.TabletItem, function(src)
    TriggerClientEvent('gs-chopshop:client:armOpen', src)
    TriggerClientEvent('gs-chopshop:client:openTablet', src)
  end)
end)


exports('GrantUpgradeLevels', function(src, upgradeId, levels)
  local player = FW.GetPlayer(src)
  if not player then return false end
  upgradeId = tostring(upgradeId or '')
  levels = math.floor(tonumber(levels or 0) or 0)
  if levels <= 0 then return false end
  local dbid = resolveDbId(src, player)
  local u = DB.GetUpgrades(dbid)
  local cur = tonumber(u[upgradeId] or 0) or 0
  DB.SetUpgrade(dbid, upgradeId, cur + levels)
  pushData(src)
  return true
end)

exports('GrantSyndicateInfluence', function(src, amount)
  local player = FW.GetPlayer(src)
  if not player then return false end
  local cid = FW.GetCid(player)
  if not (Config.Syndicate and Config.Syndicate.enabled) then return false end
  amount = math.floor(tonumber(amount or 0) or 0)
  if amount == 0 then return false end

  if DB and DB.GetPlayerSyndicate and DB.AddSyndicateInfluence and DB.SetSyndicateStats then
    local s = DB.GetPlayerSyndicate(cid)
    if s and s.id and s.id > 0 then
      DB.AddSyndicateInfluence(s.id, amount)
      local per = tonumber(Config.Syndicate.influencePerLevel or 100) or 100
      local updated = DB.GetPlayerSyndicate(cid)
      local inf = tonumber(updated and updated.influence or 0) or 0
      local newLvl = math.floor(inf / math.max(1, per))
      if newLvl ~= (tonumber(updated and updated.level or 0) or 0) then
        DB.SetSyndicateStats(s.id, newLvl, inf)
      end
      return true
    end
  end

  -- fallback legacy
  if DB and DB.AddInfluence then
    DB.AddInfluence(cid, amount)
    return true
  end
  return false
end)
