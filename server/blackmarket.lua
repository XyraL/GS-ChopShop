-- GS-ChopShop: Black Market War + Prestige Ladder
-- Loads automatically via fxmanifest (server/*.lua)

War = War or {}

local function now() return os.time() end
local function rnd(a,b) return math.random(a,b) end

local function safeJson(t)
  local ok, enc = pcall(json.encode, t)
  return ok and enc or '{}'
end

local function getCfg()
  return Config.BlackMarketWar or {}
end

-- In-memory state (authoritative, DB is persistence)
local State = {
  active = false,
  id = 0,
  theme = 'BLACK MARKET',
  startedAt = 0,
  endsAt = 0,
  rotationSeconds = 1200,
  nextRotationAt = 0,
  pool = {},
}


-- Performance: cache leaderboard + batch DB writes
local PendingDeltas = {}   -- [syndId] = { points=, perfectRuns=, eliteCompleted=, dynastyCompleted=, prestigePoints= }
local NameCache = {}       -- [syndId] = name
local TotalsCache = {}     -- [syndId] = { points, perfect_runs, elite_completed, dynasty_completed, perfect_runs }
local SortedCache = {}     -- array of rows (built on demand)
local CacheDirty = true
local LastBroadcast = 0
local LastFlush = 0

local function markDirty() CacheDirty = true end

local function ensureName(syndId)
  if NameCache[syndId] then return NameCache[syndId] end
  if DB and DB.GetSyndicateById then
    local s = DB.GetSyndicateById(syndId)
    if s and s.name then
      NameCache[syndId] = s.name
      return s.name
    end
  end
  NameCache[syndId] = ('Syndicate #%d'):format(syndId)
  return NameCache[syndId]
end

local function rebuildSorted(limit)
  limit = math.floor(tonumber(limit or 10) or 10)
  if limit < 1 then limit = 1 end
  if limit > 25 then limit = 25 end

  local rows = {}
  for sid, t in pairs(TotalsCache) do
    rows[#rows+1] = {
      syndicate_id = sid,
      name = ensureName(sid),
      points = t.points or 0,
      perfect_runs = t.perfect_runs or 0,
      elite_completed = t.elite_completed or 0,
      dynasty_completed = t.dynasty_completed or 0,
    }
  end

  table.sort(rows, function(a,b)
    if a.points ~= b.points then return a.points > b.points end
    if a.elite_completed ~= b.elite_completed then return a.elite_completed > b.elite_completed end
    return a.perfect_runs > b.perfect_runs
  end)

  SortedCache = {}
  for i=1, math.min(limit, #rows) do
    SortedCache[i] = rows[i]
  end
  CacheDirty = false
end

local function makePoolEntry(idx, tierKey, kind, theme)
  local cfg = getCfg()
  local tiers = (cfg and cfg.tiers) or {}
  local tc = tiers[kind] or {}

  local modsMin = tc.minMods or 2
  local modsMax = tc.maxMods or 3

  return {
    id = ('%d-%d-%s'):format(State.id, idx, kind),
    kind = kind,                 -- standard | elite | dynasty
    tier = tierKey,              -- tier1/tier2/tier3
    label = tc.label or kind:upper(),
    desc = tc.desc or '',
    modsMin = modsMin,
    modsMax = modsMax,
    payoutMult = tonumber(tc.payoutMult or 1.0) or 1.0,
    pointsBase = tonumber(tc.pointsBase or 100) or 100,
    pointsPerfect = tonumber(tc.pointsPerfect or 50) or 50,
    pointsBonusObj = tonumber(tc.pointsBonusObj or 25) or 25,
    pointsStackPenalty = tonumber(tc.pointsStackPenalty or 0.35) or 0.35,
    theme = theme,
    createdAt = now(),
    expiresAt = 0, -- filled on rotation
  }
end

local function rebuildPool()
  local cfg = getCfg()
  State.pool = {}
  if not State.active then return end

  local poolCfg = cfg.pool or { standard = 2, elite = 1, dynasty = 1 }
  local idx = 1

  local function addMany(kind, count)
    for _=1, (count or 0) do
      -- Tier choice rules: standard can be any, elite minimum tier2, dynasty minimum tier3
      local tierKey = 'tier1'
      if kind == 'elite' then tierKey = (math.random() < 0.6) and 'tier2' or 'tier3'
      elseif kind == 'dynasty' then tierKey = 'tier3'
      else
        local r = math.random()
        if r < 0.55 then tierKey = 'tier1' elseif r < 0.85 then tierKey = 'tier2' else tierKey = 'tier3' end
      end

      State.pool[#State.pool+1] = makePoolEntry(idx, tierKey, kind, State.theme)
      idx += 1
    end
  end

  addMany('standard', poolCfg.standard or 2)
  addMany('elite', poolCfg.elite or 1)
  addMany('dynasty', poolCfg.dynasty or 1)

  local exp = now() + (State.rotationSeconds or 1200)
  for i=1,#State.pool do
    State.pool[i].expiresAt = exp
  end
  State.nextRotationAt = exp
end

local function loadFromDb()
  if not DB or not DB.GetActiveBMEvent then return end
  local ev = DB.GetActiveBMEvent()
  if not ev then return end

  if ev.endsAt > now() then
    State.active = true
    State.id = ev.id
    State.theme = ev.theme or 'BLACK MARKET'
    State.startedAt = ev.startedAt
    State.endsAt = ev.endsAt
    State.rotationSeconds = ev.rotationSeconds or 1200
    State.nextRotationAt = (ev.meta and tonumber(ev.meta.nextRotationAt)) or 0

    -- Restore pool if present in meta
    local pool = ev.meta and ev.meta.pool
    if type(pool) == 'table' and #pool > 0 then
      State.pool = pool
    else
      rebuildPool()
    end

    -- Load leaderboard cache once to avoid frequent DB hits
    if DB and DB.GetBMLeaderboard then
      local rows = DB.GetBMLeaderboard(State.id, 25) or {}
      TotalsCache = {}
      for i=1, #rows do
        local r = rows[i]
        local sid = tonumber(r.syndicate_id) or 0
        if sid > 0 then
          NameCache[sid] = r.name or NameCache[sid]
          TotalsCache[sid] = {
            points = tonumber(r.points) or 0,
            perfect_runs = tonumber(r.perfect_runs) or 0,
            elite_completed = tonumber(r.elite_completed) or 0,
            dynasty_completed = tonumber(r.dynasty_completed) or 0,
          }
        end
      end
      markDirty()
    end

    if State.nextRotationAt <= now() then
      rebuildPool()
    end
  else
    -- event expired; do nothing
    State.active = false
  end
end

local function persistMeta()
  if not DB or not DB.CreateBMEvent or not DB.GetActiveBMEvent then return end
  -- We persist pool + nextRotationAt in the event meta blob
  local ev = DB.GetActiveBMEvent()
  if not ev or ev.id ~= State.id then return end
  local meta = ev.meta or {}
  meta.pool = State.pool
  meta.nextRotationAt = State.nextRotationAt
  -- update meta (use exec directly; keep compatible with older DB libs)
  if DB.Exec then
    DB.Exec([[UPDATE gs_chopshop_bm_event SET meta = ? WHERE id = ?;]], { safeJson(meta), State.id })
  end
end

local function syndicateEligibility(synd)
  local cfg = getCfg()
  if not cfg.enabled then return false, 'Disabled' end
  if not synd or not synd.id or synd.id <= 0 then return false, 'Join a group first' end
  local prest = synd.prestige or 0
  local minPrest = cfg.minPrestige or 3
  if prest < minPrest then
    return false, ('Requires Prestige %d'):format(minPrest)
  end
  return true
end

-- Public API -------------------------------------------------
function War.GetState()
  local s = {
    active = State.active,
    id = State.id,
    theme = State.theme,
    startedAt = State.startedAt,
    endsAt = State.endsAt,
    rotationSeconds = State.rotationSeconds,
    nextRotationAt = State.nextRotationAt,
  }
  return s
end

function War.GetPool()
  return State.pool or {}
end

function War.GetLeaderboard(limit)
  if not State.active then return {} end
  if CacheDirty then rebuildSorted(limit or 10) end
  -- Return a shallow copy so callers can't mutate cache
  local out = {}
  for i=1, #(SortedCache or {}) do out[i] = SortedCache[i] end
  return out
end

function War.Start(theme)
  local cfg = getCfg()
  if not cfg.enabled then return false, 'disabled' end
  if State.active and State.endsAt > now() then return false, 'already_active' end

  local dur = math.floor(tonumber(cfg.durationSeconds or (90*60)) or (90*60))
  local rot = math.floor(tonumber(cfg.rotationSeconds or (20*60)) or (20*60))
  State.active = true
  State.theme = tostring(theme or (cfg.themes and cfg.themes[math.random(1,#cfg.themes)]) or 'BLACK MARKET')
  State.startedAt = now()
  State.endsAt = State.startedAt + dur
  State.rotationSeconds = rot

  -- Create DB event row
  local meta = { pool = {}, nextRotationAt = 0 }
  State.id = (DB and DB.CreateBMEvent) and DB.CreateBMEvent(State.theme, State.startedAt, State.endsAt, rot, meta) or 0

  rebuildPool()
  persistMeta()

  return true
end

function War.End()
  if not State.active then return false end
  -- flush pending points before closing
  War.Flush()
  State.active = false
  State.pool = {}
  persistMeta()
  return true
end

-- Award points after a BM contract completes
function War.AwardOnCompletion(syndicateId, contract, meta)
  if not State.active then return end
  if not DB or not DB.AddBMPoints then return end
  if not syndicateId or syndicateId <= 0 then return end
  if not contract or not contract.bm then return end

  meta = meta or {}
  local kind = tostring(contract.bm.kind or 'standard')
  local base = tonumber(contract.bm.pointsBase or 100) or 100

  local perfect = meta.perfect and true or false
  local bonusAchieved = meta.bonusAchieved and true or false

  local pts = base
  if perfect then pts += tonumber(contract.bm.pointsPerfect or 50) or 50 end
  if bonusAchieved then pts += tonumber(contract.bm.pointsBonusObj or 25) or 25 end

  -- Penalty for repeated model+modifier combo (anti farm)
  local stack = tonumber(meta.stackCount or 0) or 0
  if stack > 0 then
    local pen = tonumber(contract.bm.pointsStackPenalty or 0.35) or 0.35
    local mult = math.max(0.15, 1.0 - (pen * stack))
    pts = math.floor(pts * mult)
  end

  local delta = { points = pts }
  if perfect then delta.perfectRuns = 1 end
  if kind == 'elite' then delta.eliteCompleted = 1 end
  if kind == 'dynasty' then delta.dynastyCompleted = 1 end

  -- Update in-memory totals and queue DB write
  local t = TotalsCache[syndicateId] or { points = 0, perfect_runs = 0, elite_completed = 0, dynasty_completed = 0 }
  t.points = (t.points or 0) + (delta.points or 0)
  t.perfect_runs = (t.perfect_runs or 0) + (delta.perfectRuns or 0)
  t.elite_completed = (t.elite_completed or 0) + (delta.eliteCompleted or 0)
  t.dynasty_completed = (t.dynasty_completed or 0) + (delta.dynastyCompleted or 0)
  TotalsCache[syndicateId] = t

  local p = PendingDeltas[syndicateId] or { points = 0, perfectRuns = 0, eliteCompleted = 0, dynastyCompleted = 0, prestigePoints = 0 }
  p.points = p.points + (delta.points or 0)
  p.perfectRuns = p.perfectRuns + (delta.perfectRuns or 0)
  p.eliteCompleted = p.eliteCompleted + (delta.eliteCompleted or 0)
  p.dynastyCompleted = p.dynastyCompleted + (delta.dynastyCompleted or 0)

  -- Also queue prestige points (slow burn)
  local pp = math.floor(pts * (tonumber(getCfg().prestigePointRate or 0.10) or 0.10))
  if pp > 0 then
    p.prestigePoints = p.prestigePoints + pp
  end

  PendingDeltas[syndicateId] = p
  markDirty()
end

-- Contract acceptance: returns entry table or nil
function War.ConsumePoolEntry(entryId)
  if not State.active then return nil end
  if not entryId then return nil end
  local id = tostring(entryId)
  for i=1, #(State.pool or {}) do
    if tostring(State.pool[i].id) == id then
      local e = State.pool[i]
      table.remove(State.pool, i)
      persistMeta()
      return e
    end
  end
  return nil
end



function War.Flush()
  if not (DB and DB.Ready) then return end
  if not State.active or State.id <= 0 then return end

  local bmRows = {}
  local ppRows = {}

  for sid, d in pairs(PendingDeltas) do
    if d and (d.points ~= 0 or d.perfectRuns ~= 0 or d.eliteCompleted ~= 0 or d.dynastyCompleted ~= 0) then
      bmRows[#bmRows+1] = {
        syndicate_id = sid,
        points = d.points,
        perfectRuns = d.perfectRuns,
        eliteCompleted = d.eliteCompleted,
        dynastyCompleted = d.dynastyCompleted,
      }
    end
    if d and (d.prestigePoints or 0) ~= 0 then
      ppRows[#ppRows+1] = { syndicate_id = sid, amount = d.prestigePoints }
    end
  end

  PendingDeltas = {}

  if #bmRows > 0 then
    if DB.AddBMPointsBatch then
      DB.AddBMPointsBatch(State.id, bmRows)
    else
      for i=1,#bmRows do
        DB.AddBMPoints(State.id, bmRows[i].syndicate_id, bmRows[i])
      end
    end
  end

  if #ppRows > 0 and DB.AddSyndicatePrestigePointsBatch then
    DB.AddSyndicatePrestigePointsBatch(ppRows)
  elseif #ppRows > 0 and DB.AddSyndicatePrestigePoints then
    for i=1,#ppRows do DB.AddSyndicatePrestigePoints(ppRows[i].syndicate_id, ppRows[i].amount) end
  end
end

-- Auto-rotation thread
CreateThread(function()
  -- Wait for DB init/migrations to complete before touching BM tables.
  -- Without this, first boot can query BM tables before they're created.
  while not (DB and DB.Ready) do
    Wait(250)
  end

  loadFromDb()

  while true do
    local cfg = getCfg()
    if cfg.enabled and State.active then
      local t = now()
      if t >= State.endsAt then
        War.End()
      elseif State.nextRotationAt > 0 and t >= State.nextRotationAt then
        rebuildPool()
        persistMeta()
      end

      -- batch flush to DB once a minute during war
      if (t - LastFlush) >= 60 then
        LastFlush = t
        War.Flush()
      end
    end
    Wait(10 * 1000)
  end
end)

-- Admin commands
RegisterCommand('gs_bm_start', function(src, args)
  if src ~= 0 then return end
  local theme = args and table.concat(args, ' ') or nil
  local ok, err = War.Start(theme)
  print('[gs-chopshop] Black Market War start:', ok, err or '')
end, true)

RegisterCommand('gs_bm_end', function(src)
  if src ~= 0 then return end
  War.End()
  print('[gs-chopshop] Black Market War ended')
end, true)

