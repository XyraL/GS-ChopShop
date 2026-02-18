--========================================
-- GS-ChopShop: Tool Mastery (Individual)
-- Arcade-friendly progression: tiny QoL buffs, no economy inflation.
-- Stored per player (citizenid) as JSON in DB.
--========================================

local TOOL_KEYS = { 'wrench', 'impact', 'socket', 'cutter', 'final' }

local CACHE = {}   -- [cid] = masteryTable
local DIRTY = {}   -- [cid] = true
local nextFlushAt = 0

local function emptyMastery()
  local t = {}
  for _, k in ipairs(TOOL_KEYS) do
    t[k] = { xp = 0, level = 1 }
  end
  return t
end

local function clamp(n, a, b)
  n = tonumber(n) or 0
  if n < a then return a end
  if n > b then return b end
  return n
end

-- 5 levels, modest bonuses. XP curve is intentionally short.
local function levelForXp(xp)
  xp = tonumber(xp) or 0
  if xp >= 600 then return 5 end
  if xp >= 320 then return 4 end
  if xp >= 160 then return 3 end
  if xp >= 60 then return 2 end
  return 1
end

local function computeLevels(m)
  for _, k in ipairs(TOOL_KEYS) do
    local node = m[k] or { xp = 0 }
    node.xp = tonumber(node.xp) or 0
    node.level = levelForXp(node.xp)
    m[k] = node
  end
  return m
end

local function getCidFromSrc(src)
  local player = FW.GetPlayer(src)
  if not player then return nil end
  return FW.GetCid(player)
end

local function loadCid(cid)
  if not cid or cid == '' then return emptyMastery() end
  if CACHE[cid] then return CACHE[cid] end
  local m = (DB and DB.GetToolMastery and DB.GetToolMastery(cid)) or nil
  if type(m) ~= 'table' then m = emptyMastery() end
  CACHE[cid] = computeLevels(m)
  return CACHE[cid]
end

local function markDirty(cid)
  if not cid then return end
  DIRTY[cid] = true
  if nextFlushAt == 0 then
    nextFlushAt = os.time() + 60
  end
end

local function flushDirty(force)
  if not (DB and DB.SetToolMastery) then return end
  local now = os.time()
  if not force and (nextFlushAt == 0 or now < nextFlushAt) then return end

  for cid, _ in pairs(DIRTY) do
    local m = CACHE[cid]
    if m then
      DB.SetToolMastery(cid, m)
    end
    DIRTY[cid] = nil
  end
  nextFlushAt = 0
end

CreateThread(function()
  while true do
    Wait(1000)
    flushDirty(false)
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  flushDirty(true)
end)

RegisterNetEvent('gs-chopshop:server:toolMastery:request', function()
  local src = source
  local cid = getCidFromSrc(src)
  if not cid then return end
  local m = loadCid(cid)
  TriggerClientEvent('gs-chopshop:client:toolMastery:set', src, m)
end)

RegisterNetEvent('gs-chopshop:server:toolMastery:add', function(toolKey, perfect)
  local src = source
  local cid = getCidFromSrc(src)
  if not cid then return end

  toolKey = tostring(toolKey or '')
  if toolKey == '' then return end

  local m = loadCid(cid)
  if not m[toolKey] then return end

  local add = 1
  if perfect == true then add = 2 end

  m[toolKey].xp = clamp((m[toolKey].xp or 0) + add, 0, 200000)
  computeLevels(m)
  markDirty(cid)

  -- Lightweight client sync. This table is tiny.
  TriggerClientEvent('gs-chopshop:client:toolMastery:set', src, m)
end)

exports('GetToolMasteryForCid', function(cid)
  return loadCid(cid)
end)
