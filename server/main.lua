local ActiveContracts = {}
local ActiveSessions  = {}

local Coop = {
  leaderToPartner = {},
  partnerToLeader = {},
  pending = {},
}

local function resolveDbId(_, player)
  local cid = player and FW.GetCid(player) or nil
  return cid, cid, nil, nil
end

local Cooldowns       = {}

local function now() return os.time() end

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

local function computeRequiredStepsFromClient(requiredList)
  local requiredSet = {}
  local cleanList = {}

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

  local t = math.random() * 2.0 * math.pi
  local u = math.random()
  local r = math.sqrt(u) * radius
  return r * math.cos(t), r * math.sin(t)
end

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

  local radius = tonumber(contract.searchRadius) or 180.0
  local cx, cy, cz = contract.searchCenter.x, contract.searchCenter.y, contract.searchCenter.z
  local ox, oy = randInCircle(radius)
  local x, y = cx + ox, cy + oy
  local z = cz + 1.0

  local heading = math.random(0, 359) + 0.0

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

  local mods, mmults, forcedSteps = rollContractModifiers(tierKey)

  local bonusObj = rollBonusObjective(tierKey)

  local radius = (Config.Search and Config.Search.radius) or 180.0
  radius = radius * (tonumber(mmults.radius or 1.0) or 1.0)
  if uinfo and uinfo.mult and uinfo.mult.radius then
    radius = radius * (tonumber(uinfo.mult.radius) or 1.0)
  end
  local center = vector3(spawnBase.x, spawnBase.y, spawnBase.z)

  local duration = (Config.Contract and Config.Contract.durationSeconds) or 1800
  duration = math.floor(duration * (tonumber(mmults.duration or 1.0) or 1.0))
  duration = math.max(300, duration)

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

    modifiers = mods,
    modMult = {
      payout = mmults.payout or 1.0,
      alert = mmults.alert or 1.0,
      radius = mmults.radius or 1.0,
      duration = mmults.duration or 1.0,
    },
    forcedSteps = forcedSteps,

    bonusObjective = bonusObj,
    bonus = { state = bonusObj and "active" or "none", failed = false, achieved = false },
  }

  return c
end

local getUpgradeInfo

local function giveFinalRewards(src, contract)
  local tier = Config.Tiers[contract.tier]
  if not tier then return 0 end

  local player = FW.GetPlayer(src)
  local dbid = resolveDbId(src, player)
  local uinfo = dbid and getUpgradeInfo(dbid) or nil
  local payoutMult = (uinfo and uinfo.mult and uinfo.mult.payout) or 1.0
  if contract and contract.modMult and contract.modMult.payout then
    payoutMult = payoutMult * (tonumber(contract.modMult.payout) or 1.0)
  end

  local cash = 0
  if tier.payout and tier.payout.cash then
    cash = Util.RandInt(tier.payout.cash.min or 0, tier.payout.cash.max or 0)
    cash = math.floor(cash * payoutMult)
    if player then
      FW.AddMoney(player, 'cash', cash)
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

getUpgradeInfo = function(cid)
  local u = (DB and DB.GetUpgrades) and DB.GetUpgrades(cid) or {}
  local cfg = Config.Upgrades or {}
  local pm = cfg.priceMult or 1.22

  local function priceFor(key, level)
    local uc = cfg[key]
    if not uc then return 0 end
    local base = tonumber(uc.basePrice or 0) or 0
    return math.floor(base * (pm ^ (level or 0)))
  end

  local timeMult = 1.0
  local payoutMult = 1.0
  local alertMult = 1.0
  local radiusMult = 1.0
  local finalMult = 1.0

  local function lv(key) return tonumber(u[key] or 0) or 0 end
  local function cfgOf(key) return cfg[key] end

  do
    local reduce = 0.0
    local minM = 0.55
    local keys = { 'chop_speed', 'tech_hand', 'shop_lift' }
    for _, k in ipairs(keys) do
      local c = cfgOf(k)
      if c then
        reduce = reduce + (tonumber(c.timeReducePerLevel or 0) or 0) * lv(k)
        minM = math.min(minM, tonumber(c.minTimeMult or minM) or minM)
      end
    end
    timeMult = math.max(minM, 1.0 - reduce)
  end

  do
    local bonus = 0.0
    local maxM = 3.0
    local keys = { 'clean_payout', 'broker_cut', 'shop_compactor', 'net_fence', 'net_forgery', 'net_parts' }
    for _, k in ipairs(keys) do
      local c = cfgOf(k)
      if c then
        bonus = bonus + (tonumber(c.payoutBonusPerLevel or 0) or 0) * lv(k)
        maxM = math.max(maxM, tonumber(c.maxPayoutMult or maxM) or maxM)
      end
    end
    payoutMult = math.min(maxM, 1.0 + bonus)
  end

  do
    local reduce = 0.0
    local minM = 0.35
    local keys = { 'heat_dampener', 'shop_dampening' }
    for _, k in ipairs(keys) do
      local c = cfgOf(k)
      if c then
        reduce = reduce + (tonumber(c.alertReducePerLevel or 0) or 0) * lv(k)
        minM = math.min(minM, tonumber(c.minAlertMult or minM) or minM)
      end
    end
    alertMult = math.max(minM, 1.0 - reduce)
  end

  do
    local reduce = 0.0
    local minM = 0.55
    local keys = { 'scanner', 'runner_instinct' }
    for _, k in ipairs(keys) do
      local c = cfgOf(k)
      if c then
        reduce = reduce + (tonumber(c.radiusReducePerLevel or 0) or 0) * lv(k)
        minM = math.min(minM, tonumber(c.minRadiusMult or minM) or minM)
      end
    end
    radiusMult = math.max(minM, 1.0 - reduce)
  end

  do
    local reduce = 0.0
    local minM = 0.55
    local keys = { 'auto_dispatch', 'shop_shredder' }
    for _, k in ipairs(keys) do
      local c = cfgOf(k)
      if c then
        reduce = reduce + (tonumber(c.finalReducePerLevel or 0) or 0) * lv(k)
        minM = math.min(minM, tonumber(c.minFinalMult or minM) or minM)
      end
    end
    finalMult = math.max(minM, 1.0 - reduce)
  end

  local out = {
    levels = u,
    prices = {
      chop_speed = priceFor('chop_speed', u.chop_speed or 0),
      clean_payout = priceFor('clean_payout', u.clean_payout or 0),
      heat_dampener = priceFor('heat_dampener', u.heat_dampener or 0),
      scanner = priceFor('scanner', u.scanner or 0),
      auto_dispatch = priceFor('auto_dispatch', u.auto_dispatch or 0),
      tech_hand = priceFor('tech_hand', u.tech_hand or 0),
      runner_instinct = priceFor('runner_instinct', u.runner_instinct or 0),
      broker_cut = priceFor('broker_cut', u.broker_cut or 0),
      shop_lift = priceFor('shop_lift', u.shop_lift or 0),
      shop_dampening = priceFor('shop_dampening', u.shop_dampening or 0),
      shop_compactor = priceFor('shop_compactor', u.shop_compactor or 0),
      shop_shredder = priceFor('shop_shredder', u.shop_shredder or 0),
      net_fence = priceFor('net_fence', u.net_fence or 0),
      net_forgery = priceFor('net_forgery', u.net_forgery or 0),
      net_parts = priceFor('net_parts', u.net_parts or 0),
    },
    caps = {
      chop_speed = (cfg.chop_speed and cfg.chop_speed.maxLevel) or 0,
      clean_payout = (cfg.clean_payout and cfg.clean_payout.maxLevel) or 0,
      heat_dampener = (cfg.heat_dampener and cfg.heat_dampener.maxLevel) or 0,
      scanner = (cfg.scanner and cfg.scanner.maxLevel) or 0,
      auto_dispatch = (cfg.auto_dispatch and cfg.auto_dispatch.maxLevel) or 0,
      tech_hand = (cfg.tech_hand and cfg.tech_hand.maxLevel) or 0,
      runner_instinct = (cfg.runner_instinct and cfg.runner_instinct.maxLevel) or 0,
      broker_cut = (cfg.broker_cut and cfg.broker_cut.maxLevel) or 0,
      shop_lift = (cfg.shop_lift and cfg.shop_lift.maxLevel) or 0,
      shop_dampening = (cfg.shop_dampening and cfg.shop_dampening.maxLevel) or 0,
      shop_compactor = (cfg.shop_compactor and cfg.shop_compactor.maxLevel) or 0,
      shop_shredder = (cfg.shop_shredder and cfg.shop_shredder.maxLevel) or 0,
      net_fence = (cfg.net_fence and cfg.net_fence.maxLevel) or 0,
      net_forgery = (cfg.net_forgery and cfg.net_forgery.maxLevel) or 0,
      net_parts = (cfg.net_parts and cfg.net_parts.maxLevel) or 0,
    },
        defs = {
      chop_speed = { stat = 'time', mode = 'reduce', per = (cfg.chop_speed and cfg.chop_speed.timeReducePerLevel) or 0, min = (cfg.chop_speed and cfg.chop_speed.minTimeMult) or 0.55 },
      tech_hand = { stat = 'time', mode = 'reduce', per = (cfg.tech_hand and cfg.tech_hand.timeReducePerLevel) or 0, min = (cfg.tech_hand and cfg.tech_hand.minTimeMult) or 0.55 },
      shop_lift = { stat = 'time', mode = 'reduce', per = (cfg.shop_lift and cfg.shop_lift.timeReducePerLevel) or 0, min = (cfg.shop_lift and cfg.shop_lift.minTimeMult) or 0.55 },

      clean_payout = { stat = 'payout', mode = 'bonus', per = (cfg.clean_payout and cfg.clean_payout.payoutBonusPerLevel) or 0, max = (cfg.clean_payout and cfg.clean_payout.maxPayoutMult) or 3.0 },
      broker_cut = { stat = 'payout', mode = 'bonus', per = (cfg.broker_cut and cfg.broker_cut.payoutBonusPerLevel) or 0, max = (cfg.broker_cut and cfg.broker_cut.maxPayoutMult) or 3.0 },
      shop_compactor = { stat = 'payout', mode = 'bonus', per = (cfg.shop_compactor and cfg.shop_compactor.payoutBonusPerLevel) or 0, max = (cfg.shop_compactor and cfg.shop_compactor.maxPayoutMult) or 3.0 },
      net_fence = { stat = 'payout', mode = 'bonus', per = (cfg.net_fence and cfg.net_fence.payoutBonusPerLevel) or 0, max = (cfg.net_fence and cfg.net_fence.maxPayoutMult) or 3.0 },
      net_forgery = { stat = 'payout', mode = 'bonus', per = (cfg.net_forgery and cfg.net_forgery.payoutBonusPerLevel) or 0, max = (cfg.net_forgery and cfg.net_forgery.maxPayoutMult) or 3.0 },
      net_parts = { stat = 'payout', mode = 'bonus', per = (cfg.net_parts and cfg.net_parts.payoutBonusPerLevel) or 0, max = (cfg.net_parts and cfg.net_parts.maxPayoutMult) or 3.0 },

      heat_dampener = { stat = 'alert', mode = 'reduce', per = (cfg.heat_dampener and cfg.heat_dampener.alertReducePerLevel) or 0, min = (cfg.heat_dampener and cfg.heat_dampener.minAlertMult) or 0.35 },
      shop_dampening = { stat = 'alert', mode = 'reduce', per = (cfg.shop_dampening and cfg.shop_dampening.alertReducePerLevel) or 0, min = (cfg.shop_dampening and cfg.shop_dampening.minAlertMult) or 0.35 },

      scanner = { stat = 'radius', mode = 'reduce', per = (cfg.scanner and cfg.scanner.radiusReducePerLevel) or 0, min = (cfg.scanner and cfg.scanner.minRadiusMult) or 0.55 },
      runner_instinct = { stat = 'radius', mode = 'reduce', per = (cfg.runner_instinct and cfg.runner_instinct.radiusReducePerLevel) or 0, min = (cfg.runner_instinct and cfg.runner_instinct.minRadiusMult) or 0.55 },

      auto_dispatch = { stat = 'final', mode = 'reduce', per = (cfg.auto_dispatch and cfg.auto_dispatch.finalReducePerLevel) or 0, min = (cfg.auto_dispatch and cfg.auto_dispatch.minFinalMult) or 0.55 },
      shop_shredder = { stat = 'final', mode = 'reduce', per = (cfg.shop_shredder and cfg.shop_shredder.finalReducePerLevel) or 0, min = (cfg.shop_shredder and cfg.shop_shredder.minFinalMult) or 0.45 },
    },
mult = {
      time = timeMult,
      payout = payoutMult,
      alert = alertMult,
      radius = radiusMult,
      final = finalMult,
    }
  }

  return out
end

local function pushData(src)
  local player = FW.GetPlayer(src)
  if not player then return end

  local cid = FW.GetCid(player)
  local dbid = cid
  local contract = getContract(src)
  local session = ActiveSessions[src]

  local top = (Config.Leaderboard and Config.Leaderboard.enabled) and DB.GetTop(Config.Leaderboard.topCount or 10) or {}
  local hist = DB.GetHistory(dbid, 10)
  local prog = DB.GetTierProgress(dbid)
  prog.rep = (DB.GetRep and DB.GetRep(dbid)) or 0
  local profile = (DB.GetProfile and DB.GetProfile(dbid)) or { alias = nil, privacy = 1 }
  local uinfo = dbid and getUpgradeInfo(dbid) or nil

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
    history = hist,
    progress = prog,
    upgrades = uinfo,
    profile = profile,
    special = {
      repRequired = (Config.SpecialContracts and Config.SpecialContracts.repRequired) or 0,
      enabled = (Config.SpecialContracts and Config.SpecialContracts.enabled) and true or false,
    },
  })
end

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
  local uinfo = getUpgradeInfo(dbid)
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

    FW.AddMoney(player, acct, price)
    print(('^1[gs-chopshop]^0 Upgrade DB error (%s): %s'):format(upgradeId, tostring(err)))
    TriggerClientEvent('gs-chopshop:client:notify', src, 'Upgrade purchase failed (DB). Refunded.', 'error')
    pushData(src)
    return
  end

  TriggerClientEvent('gs-chopshop:client:notify', src,
    ('%s upgraded to Level %d.'):format(uc.label or upgradeId, current + 1), 'success')

  pushData(src)
  CreateThread(function()
    Wait(350)
    pushData(src)
  end)
end)

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

  local prog = (DB and DB.GetTierProgress) and DB.GetTierProgress(dbid) or { tier1 = 0, tier2 = 0, tier3 = 0 }
  prog.rep = (DB and DB.GetRep and DB.GetRep(dbid)) or 0

  TriggerClientEvent('gs-chopshop:client:notify', src,
    ('ChopTest: %s +$%d | Progress now: T1=%d T2=%d T3=%d'):format(tierKey, earned, prog.tier1 or 0, prog.tier2 or 0, prog.tier3 or 0),
    'success')

  FW.AddMoney(player, 'cash', earned)

  pushData(src)

  CreateThread(function()
    Wait(350)
    pushData(src)
  end)
end, false)

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
  local uinfo = dbid and getUpgradeInfo(dbid) or nil

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

  })

  pushData(src)
end)

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
  local uinfo = dbid and getUpgradeInfo(dbid) or nil
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

  local wantMin = tonumber(sc.minMods or 2) or 2
  if (contract.modifiers and #contract.modifiers or 0) < wantMin then

    local oldMin, oldMax = Config.ContractModifiers.minActive, Config.ContractModifiers.maxActive
    Config.ContractModifiers.minActive = wantMin
    Config.ContractModifiers.maxActive = math.max(wantMin, tonumber(sc.maxMods or 3) or 3)
    contract.modifiers, contract.modMult, contract.forcedSteps = rollContractModifiers(contract.tier)

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

RegisterNetEvent('gs-chopshop:server:coopInvite', function(target)
  local src = source
  target = tonumber(target or 0) or 0
  if target <= 0 or GetPlayerPing(target) <= 0 then return end
  if src == target then return end

  Coop.pending[target] = { from = src, expires = now() + 30 }
  TriggerClientEvent('gs-chopshop:client:coopInvite', target, src)
  TriggerClientEvent('gs-chopshop:client:notify', src, 'Invite sent.', 'inform')
end)

RegisterNetEvent('gs-chopshop:server:coopRespond', function(accept)
  local target = source
  local p = Coop.pending[target]
  if not p or (p.expires or 0) < now() then
    Coop.pending[target] = nil
    return
  end
  Coop.pending[target] = nil
  local leader = p.from
  if not accept then
    TriggerClientEvent('gs-chopshop:client:notify', leader, 'Invite declined.', 'error')
    return
  end
  Coop.leaderToPartner[leader] = target
  Coop.partnerToLeader[target] = leader
  TriggerClientEvent('gs-chopshop:client:notify', leader, 'Co-op linked.', 'success')
  TriggerClientEvent('gs-chopshop:client:notify', target, 'Co-op linked.', 'success')
end)

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

  if Config.PDAlert and Config.PDAlert.enabled and Config.PDAlert.onStart then
    local veh = NetworkGetEntityFromNetworkId(c.netId)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
      local player = FW.GetPlayer(src)
      local dbid = resolveDbId(src, player)
      local uinfo = dbid and getUpgradeInfo(dbid) or nil
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
    local uinfo = dbid and getUpgradeInfo(dbid) or nil
    local mult = (uinfo and uinfo.mult and uinfo.mult.alert) or 1.0
    if c and c.modMult and c.modMult.alert then
      mult = mult * (tonumber(c.modMult.alert) or 1.0)
    end
    local alerted = Alerts.Try(src, c.tier, vpos, c.plate, c.model, mult)
      if alerted then applyBonusSignal(src, "alert", "Alert triggered") end
  end

  local requiredSet, requiredList = computeRequiredStepsFromClient(requiredList)

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

  table.sort(requiredList, function(a, b)
    return (STEP_INDEX[a] or 9999) < (STEP_INDEX[b] or 9999)
  end)

  local player = FW.GetPlayer(src)
  local dbid = resolveDbId(src, player)
  local uinfo = dbid and getUpgradeInfo(dbid) or nil
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

  requiredList = requiredList,
  timeMult = mults.time or 1.0,
  finalMult = mults.final or 1.0,
})
end)

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

  if stepKey ~= 'final' and Config.V3 and Config.V3.enforceStepOrder then
    for _, s in ipairs(Config.AdvancedSteps or {}) do
      local k = tostring(s.key or '')
      if k == '' or k == 'final' then goto continue_order end
      if not stepEnabledServer(k) then goto continue_order end

      if k == stepKey then break end

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

    local repNow = 0
    local dbidForRep = resolveDbId(src, player)
    if DB and DB.GetRep and dbidForRep then repNow = DB.GetRep(dbidForRep) end
    local repMult = computeRepPayoutMult(repNow)
    if repMult > 1.0 then
      local repExtra = math.floor(cash * math.max(0.0, repMult - 1.0))
      if repExtra > 0 then
        local p = FW.GetPlayer(src)
        if p then FW.AddMoney(p, "cash", repExtra) end
        cash = cash + repExtra
      end
    end

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
          if p then FW.AddMoney(p, "cash", extra) end
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

        local partner = Coop.leaderToPartner[src]
        if partner and GetPlayerPing(partner) > 0 then
          local share = (Config.Coop and tonumber(Config.Coop.partnerShare or 0.35)) or 0.35
          share = math.max(0.05, math.min(0.75, share))
          local cut = math.floor(cash * share)
          local repCut = math.max(0, math.floor(repGain * ((Config.Coop and tonumber(Config.Coop.partnerRepShare or 1.0)) or 1.0)))
          local pp = FW.GetPlayer(partner)
          if pp and cut > 0 then
            FW.AddMoney(pp, 'cash', cut)
          end
          if pp and DB and DB.AddResult then
            local pcid = FW.GetCid(pp)
            local pname = FW.GetName(pp)
            DB.AddResult(pcid, pname, c.tier, c.model, cut, true, repCut)
          end
        end
      end
      if DB and DB.AddTierProgress then
        DB.AddTierProgress(dbid, c.tier)
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
