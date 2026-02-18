--========================================
-- GS-ChopShop: Bay Visual Evolution (Client)
-- Purely cosmetic props that unlock based on player progression.
-- No territories, no politics, no gameplay impact.
--========================================

local V = {}
_G.GS_CHOP_VIS = V

local spawned = {} -- [bayIndex] = { ent1, ent2, ... }
local currentBay = nil

local function loadModel(hash)
  if not IsModelInCdimage(hash) then return false end
  RequestModel(hash)
  local t = GetGameTimer() + 2500
  while not HasModelLoaded(hash) and GetGameTimer() < t do
    Wait(0)
  end
  return HasModelLoaded(hash)
end

local function safeCreate(model, x, y, z, heading)
  local h = type(model) == 'number' and model or joaat(model)
  if not loadModel(h) then return nil end
  local ent = CreateObject(h, x, y, z, false, false, false)
  if ent and ent ~= 0 then
    SetEntityHeading(ent, heading or 0.0)
    FreezeEntityPosition(ent, true)
    SetEntityInvincible(ent, true)
    SetEntityAsMissionEntity(ent, true, true)
  end
  SetModelAsNoLongerNeeded(h)
  return ent
end

local function clearBay(bayIndex)
  local list = spawned[bayIndex]
  if not list then return end
  for _, ent in ipairs(list) do
    if ent and ent ~= 0 and DoesEntityExist(ent) then
      DeleteEntity(ent)
    end
  end
  spawned[bayIndex] = nil
end

local function totalContracts(progress)
  if type(progress) ~= 'table' then return 0 end
  return (tonumber(progress.tier1) or 0) + (tonumber(progress.tier2) or 0) + (tonumber(progress.tier3) or 0)
end

local function masterySum(m)
  if type(m) ~= 'table' then return 0 end
  local sum = 0
  for _, k in ipairs({ 'wrench','impact','socket','cutter','final' }) do
    local node = m[k]
    sum = sum + (node and tonumber(node.level) or 1)
  end
  return sum
end

local function spawnForBay(bayIndex, score, masteryScore)
  local bay = (Config and Config.Bays and Config.Bays[bayIndex]) or nil
  if not bay then return end

  clearBay(bayIndex)
  spawned[bayIndex] = {}

  local h = math.rad((bay.w or 0.0) + 0.0)
  local fx = math.cos(h)
  local fy = math.sin(h)
  local rightx = math.cos(h + (math.pi/2))
  local righty = math.sin(h + (math.pi/2))

  local function at(fwd, right, up)
    return bay.x + fx*fwd + rightx*right, bay.y + fy*fwd + righty*right, bay.z + (up or 0.0)
  end

  -- Always: subtle tool box near the bay
  do
    local x,y,z = at(1.0, 1.4, -0.1)
    local ent = safeCreate('prop_tool_box_04', x,y,z, (bay.w or 0.0) + 20.0)
    if ent then table.insert(spawned[bayIndex], ent) end
  end

  -- 50+ contracts: scrap pile
  if score >= 50 then
    local x,y,z = at(-1.2, -1.6, -0.2)
    local ent = safeCreate('prop_scrap_2_crate', x,y,z, (bay.w or 0.0) - 35.0)
    if ent then table.insert(spawned[bayIndex], ent) end
  end

  -- 200+ contracts: tool bench + oil can
  if score >= 200 then
    local x1,y1,z1 = at(2.0, -1.8, -0.2)
    local e1 = safeCreate('prop_tool_bench02', x1,y1,z1, (bay.w or 0.0) + 90.0)
    if e1 then table.insert(spawned[bayIndex], e1) end

    local x2,y2,z2 = at(2.2, -1.2, 0.35)
    local e2 = safeCreate('prop_oilcan_01a', x2,y2,z2, (bay.w or 0.0) + 10.0)
    if e2 then table.insert(spawned[bayIndex], e2) end
  end

  -- 500+ contracts: rubber pile (visual "busy shop")
  if score >= 500 then
    local x,y,z = at(-2.0, 1.8, -0.2)
    local ent = safeCreate('prop_rub_pile_05', x,y,z, (bay.w or 0.0) + 15.0)
    if ent then table.insert(spawned[bayIndex], ent) end
  end

  -- Mastery bonus: if the player has been grinding tools, add a small rack.
  if masteryScore >= 18 then
    local x,y,z = at(0.8, -2.4, -0.2)
    local ent = safeCreate('prop_toolchest_05', x,y,z, (bay.w or 0.0) + 180.0)
    if ent then table.insert(spawned[bayIndex], ent) end
  end
end

function V.ApplyFromData(data, activeSession)
  if not activeSession or not activeSession.bayIndex then
    if currentBay then clearBay(currentBay) end
    currentBay = nil
    return
  end

  local bayIndex = activeSession.bayIndex
  if currentBay ~= bayIndex then
    if currentBay then clearBay(currentBay) end
    currentBay = bayIndex
  end

  local score = totalContracts(data and data.progress)
  local masteryScore = masterySum(data and data.toolMastery)
  spawnForBay(bayIndex, score, masteryScore)
end
