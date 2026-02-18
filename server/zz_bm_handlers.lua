-- NUI/Net handlers for Black Market War + Syndicate Prestige

local function now() return os.time() end

-- Prevent double-press / race conditions on prestige
local PrestigeLocks = {} -- [syndicateId]=true

local function notify(src, msg, typ)
  TriggerClientEvent('gs-chopshop:client:notify', src, msg, typ or 'inform')
end

-- Accept a Black Market contract from the rotating pool
RegisterNetEvent('gs-chopshop:server:bm:accept', function(entryId)
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end

  if GSCS.ActiveContracts[src] then
    notify(src, 'Finish or cancel your current contract first.', 'error')
    return
  end

  local cid = FW.GetCid(player)
  local s = DB and DB.GetPlayerSyndicate and DB.GetPlayerSyndicate(cid) or nil
  if not s or not s.id or s.id <= 0 then
    notify(src, 'Join a group first.', 'error')
    return
  end

  if PrestigeLocks[s.id] then
    notify(src, 'Prestige is already processing...', 'error')
    return
  end
  PrestigeLocks[s.id] = true

  local prest = DB.GetSyndicatePrestige and DB.GetSyndicatePrestige(s.id) or { prestige = 0 }
  s.prestige = prest.prestige

  local okElig, why = (War and War.GetState) and (function()
    local cfg = Config.BlackMarketWar or {}
    if not cfg.enabled then return false, 'Disabled' end
    if not War.GetState().active then return false, 'No active war' end
    local minPrest = cfg.minPrestige or 3
    if (s.prestige or 0) < minPrest then return false, ('Requires Prestige %d'):format(minPrest) end
    return true
  end)() or false

  if not okElig then
    notify(src, why or 'Not eligible.', 'error')
    return
  end

  local entry = War and War.ConsumePoolEntry and War.ConsumePoolEntry(entryId) or nil
  if not entry then
    notify(src, 'That offer expired. Refresh the tablet.', 'error')
    return
  end

  -- Build a contract using normal pipeline but with BM metadata
  local tierKey = tostring(entry.tier or 'tier1')
  local contract = GSCS.MakeContract(src, tierKey, { isSpecial = true, tag = 'BLACK MARKET' })
  if not contract then
    notify(src, 'Failed to create contract.', 'error')
    return
  end

  contract.bm = {
    kind = entry.kind,
    pointsBase = entry.pointsBase,
    pointsPerfect = entry.pointsPerfect,
    pointsBonusObj = entry.pointsBonusObj,
    pointsStackPenalty = entry.pointsStackPenalty,
    payoutMult = entry.payoutMult,
  }
  contract.special = true
  contract.specialTag = ('BM: %s'):format((entry.kind or 'standard'):upper())

  -- Force heavier modifier count
  if Config.ContractModifiers and Config.ContractModifiers.enabled and contract.modifiers then
    -- ensure at least entry modsMin
    local current = 0
    for _ in pairs(contract.modifiers) do current = current + 1 end
    local want = math.max(current, tonumber(entry.modsMin or 2) or 2)
    local max = tonumber(entry.modsMax or want) or want
    local cfg = Config.ContractModifiers

    -- Try to add extra modifiers by rerolling a few times
    local tries = 0
    while current < want and tries < 8 do
      tries = tries + 1
      local extra = GSCS.RollContractModifiers(tierKey, want, max)
      if extra then
        for k,v in pairs(extra) do
          if not contract.modifiers[k] then
            contract.modifiers[k] = v
            current = current + 1
            if current >= want then break end
          end
        end
      end
    end
  end

  -- Tighten the fuse a bit
  local cfg = Config.BlackMarketWar or {}
  local dm = tonumber(cfg.durationMult or 0.80) or 0.80
  contract.expiresAt = math.floor((contract.startedAt or now()) + ((Config.Contract.durationSeconds or 1800) * dm))

  -- Apply payout multiplier on completion via session.finalMult
  GSCS.GSCS.ActiveContracts[src] = contract

  notify(src, ('Black Market contract accepted: %s'):format(entry.label or 'Offer'), 'success')
  GSCS.PushData(src)
end)

-- Syndicate prestige up (Funds + Influence + Level gate)
local function unlockPrestige(sid)
  if sid and PrestigeLocks then PrestigeLocks[sid] = nil end
end

RegisterNetEvent('gs-chopshop:server:syndicate:prestigeUp', function()
  local src = source
  local player = FW.GetPlayer(src)
  if not player then return end

  local cid = FW.GetCid(player)
  local s = DB and DB.GetPlayerSyndicate and DB.GetPlayerSyndicate(cid) or nil
  if not s or not s.id or s.id <= 0 then
    notify(src, 'Join a group first.', 'error')
    return
  end

  if PrestigeLocks[s.id] then
    notify(src, 'Prestige is already processing...', 'error')
    return
  end
  PrestigeLocks[s.id] = true

  local p = DB.GetSyndicatePrestige and DB.GetSyndicatePrestige(s.id) or { prestige = 0, points = 0 }
  local cur = tonumber(p.prestige or 0) or 0

  local cfg = Config.SyndicatePrestige or {}
  local tiers = cfg.tiers or {}
  local nextCfg = tiers[cur + 1]
  if not nextCfg then
    notify(src, 'Max prestige reached.', 'error')
    unlockPrestige(s.id)
    return
  end

  local levelReq = tonumber(nextCfg.levelReq or 0) or 0
  local infReq = tonumber(nextCfg.influenceCost or 0) or 0
  local fundsReq = tonumber(nextCfg.fundsCost or 0) or 0

  if (tonumber(s.level or 0) or 0) < levelReq then
    notify(src, ('Requires Group Level %d.'):format(levelReq), 'error')
    unlockPrestige(s.id)
    return
  end

  if (tonumber(s.influence or 0) or 0) < infReq then
    notify(src, ('Requires %d influence.'):format(infReq), 'error')
    unlockPrestige(s.id)
    return
  end

  local vault = DB.GetVault and DB.GetVault(s.id) or 0
  if vault < fundsReq then
    notify(src, ('Requires $%d funds in bank.'):format(fundsReq), 'error')
    unlockPrestige(s.id)
    return
  end

  -- Charge costs
  if fundsReq > 0 and DB.WithdrawFromVault then
    local ok = DB.WithdrawFromVault(s.id, cid, fundsReq)
    if not ok then
      notify(src, 'Bank withdrawal failed.', 'error')
      unlockPrestige(s.id)
      return
    end
  end

  if infReq > 0 and DB.AddSyndicateInfluence then
    DB.AddSyndicateInfluence(s.id, -infReq)
  end

  local newPrest = cur + 1
  DB.SetSyndicatePrestige(s.id, newPrest, tonumber(p.points or 0) or 0)

  -- Prestige V2: corporate restructure (reset level/influence/perks, keep some bank)
  local keep = 0.25 + (0.05 * newPrest)
  if keep > 0.45 then keep = 0.45 end
  if DB.PrestigeResetSyndicate then
    DB.PrestigeResetSyndicate(s.id, 1, keep)
  else
    -- fallback: at least reset level/influence
    if DB.SetSyndicateStats then DB.SetSyndicateStats(s.id, 1, 0) end
  end

  notify(src, ('Prestige increased to %d (kept %d%% of bank).'):format(newPrest, math.floor(keep*100)), 'success')
  unlockPrestige(s.id)
  GSCS.PushData(src)
end)

