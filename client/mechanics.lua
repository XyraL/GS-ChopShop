--========================================
-- GS-ChopShop V5: Arcade-Mechanical Chop Feel
-- Randomized per-part micro skill + fast tactile progress.
-- B + slight C: random minigames per part + slight easier zones via upgrades (approximated via time multiplier).
--========================================

local M = {}

-- Expose globally (FiveM doesn't guarantee require() across files)
_G.GS_CHOP_MECH = M

-- Tool mastery snapshot (set by server). Structure:
-- { wrench={xp,level}, impact={...}, socket={...}, cutter={...}, final={...} }
M._mastery = {}

function M.SetMastery(m)
  if type(m) ~= 'table' then return end
  M._mastery = m
end

local function getToolForCategory(cat)
  if cat == 'door' or cat == 'panel' or cat == 'vin' or cat == 'plate' or cat == 'move' then return 'wrench' end
  if cat == 'wheel' then return 'impact' end
  if cat == 'engine' then return 'socket' end
  if cat == 'cut' then return 'cutter' end
  if cat == 'final' then return 'final' end
  return 'wrench'
end

local function getMasteryLevel(toolKey)
  local node = M._mastery and M._mastery[toolKey]
  local lvl = (node and tonumber(node.level)) or 1
  if lvl < 1 then lvl = 1 end
  if lvl > 5 then lvl = 5 end
  return lvl
end

local function hasOxLib()
  return GetResourceState('ox_lib') == 'started' and lib ~= nil
end

local function canSkillCheck()
  return hasOxLib() and lib.skillCheck ~= nil
end

-- Fallback minigame for older ox_lib builds (or servers that disabled skillCheck)
-- Keeps the "arcade mechanical" feel even when lib.skillCheck isn't available.
local function draw2d(text)
  SetTextFont(4)
  SetTextScale(0.45, 0.45)
  SetTextColour(255, 255, 255, 215)
  SetTextCentre(true)
  BeginTextCommandDisplayText('STRING')
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandDisplayText(0.5, 0.82)
end

local function rand01()
  -- math.random() without args returns a float in [0,1) in FiveM's Lua runtime
  local r = math.random()
  if type(r) ~= 'number' then return 0.5 end
  if r < 0 then r = 0 end
  if r >= 1 then r = 0.999 end
  return r
end

local function fallbackSkill(mini, diff)
  diff = tostring(diff or 'medium')
  local tol = (diff == 'easy') and 180 or (diff == 'hard' and 95 or 130)

  -- bolt: timing press
  if mini == 'bolt' then
    local start = GetGameTimer()
    local dur = 1600
    local target = 700 + math.floor((rand01() * 650))

    while (GetGameTimer() - start) < dur do
      Wait(0)
      DisableControlAction(0, 38, true) -- E
      local t = (GetGameTimer() - start)
      local pct = math.floor((t / dur) * 100)
      draw2d(('ALIGN THE BOLT  |  Press ~g~E~s~ near the mark  [%d%%]'):format(pct))

      if IsDisabledControlJustPressed(0, 38) then
        return math.abs(t - target) <= tol
      end
    end

    return false
  end

  -- rapid: mash
  if mini == 'rapid' then
    local need = (diff == 'easy') and 5 or (diff == 'hard' and 9 or 7)
    local start = GetGameTimer()
    local dur = 1500
    local c = 0
    while (GetGameTimer() - start) < dur do
      Wait(0)
      DisableControlAction(0, 38, true)
      draw2d(('RAPID REMOVE  |  Tap ~g~E~s~  (%d/%d)'):format(c, need))
      if IsDisabledControlJustPressed(0, 38) then
        c = c + 1
        if c >= need then return true end
      end
    end
    return false
  end

  -- torque: hold
  local hold = (diff == 'easy') and 650 or (diff == 'hard' and 1050 or 850)
  local start = GetGameTimer()
  local heldAt = nil
  while (GetGameTimer() - start) < (hold + 900) do
    Wait(0)
    DisableControlAction(0, 38, true)
    local now = GetGameTimer()
    local down = IsDisabledControlPressed(0, 38)
    if down and not heldAt then heldAt = now end
    if not down then heldAt = nil end
    local prog = heldAt and math.min(100, math.floor(((now - heldAt) / hold) * 100)) or 0
    draw2d(('APPLY TORQUE  |  Hold ~g~E~s~  [%d%%]'):format(prog))
    if heldAt and (now - heldAt) >= hold then
      return true
    end
  end
  return false
end

local function canProgress()
  return hasOxLib() and lib.progressBar ~= nil
end

-- Small internal RNG that is stable enough for per-part variety.
local function rand01()
  local t = GetGameTimer() % 2147483647
  t = (t * 1103515245 + 12345) % 2147483647
  return (t / 2147483647)
end

-- Map stepKey to a part category (drives timings + FX + minigame selection weights)
local function getCategory(stepKey)
  stepKey = tostring(stepKey or '')
  if stepKey == 'vin_scratch' then return 'vin' end
  if stepKey == 'plate_front' or stepKey == 'plate_rear' then return 'plate' end
  if stepKey == 'move_shell' then return 'move' end
  if stepKey == 'cut_shell' then return 'cut' end
  if stepKey == 'final' then return 'final' end
  if stepKey == 'engine' then return 'engine' end
  if stepKey:find('wheel') then return 'wheel' end
  if stepKey:find('door') then return 'door' end
  if stepKey == 'hood' or stepKey == 'trunk' then return 'panel' end
  return 'generic'
end

-- Arcade base times (ms). These are BEFORE any session multipliers.
local BASE_MS = {
  door  = 2400,
  panel = 2600,
  wheel = 2200,
  engine = 3000,
  vin   = 2300,
  plate = 2000,
  move  = 2000,
  cut   = 2800,
  final = 2500,
  generic = 2400,
}

-- Slight C: approximate "better tools/upgrades" by reading session timeMult.
-- Faster sessions get slightly easier checks; slower sessions get slightly harder checks.
local function adjustDifficulty(diff, sessionTimeMult)
  sessionTimeMult = tonumber(sessionTimeMult) or 1.0
  local order = { easy = 1, medium = 2, hard = 3 }
  local inv = { [1] = 'easy', [2] = 'medium', [3] = 'hard' }
  local v = order[diff] or 2

  if sessionTimeMult <= 0.92 then
    v = math.max(1, v - 1) -- slightly easier
  elseif sessionTimeMult >= 1.10 then
    v = math.min(3, v + 1) -- slightly harder
  end
  return inv[v]
end

-- Slight C extension: mastery can nudge difficulty down by 1 step at higher levels.
local function applyMasteryDifficulty(diff, masteryLevel)
  local order = { easy = 1, medium = 2, hard = 3 }
  local inv = { [1] = 'easy', [2] = 'medium', [3] = 'hard' }
  local v = order[diff] or 2

  if masteryLevel >= 4 then
    v = math.max(1, v - 1)
  end
  return inv[v]
end

-- Choose one of 3 micro-minigames per part.
-- Implemented via ox_lib skillCheck profiles.
local function pickMini(stepKey)
  local cat = getCategory(stepKey)

  local r = rand01()
  if cat == 'wheel' then
    if r < 0.55 then return 'rapid' end
    if r < 0.80 then return 'bolt' end
    return 'torque'
  elseif cat == 'engine' or cat == 'cut' then
    if r < 0.55 then return 'torque' end
    if r < 0.80 then return 'bolt' end
    return 'rapid'
  elseif cat == 'plate' or cat == 'vin' then
    if r < 0.70 then return 'bolt' end
    return 'rapid'
  else
    if r < 0.45 then return 'bolt' end
    if r < 0.75 then return 'torque' end
    return 'rapid'
  end
end

local function profileForMini(mini, baseDiff, sessionTimeMult)
  baseDiff = adjustDifficulty(baseDiff, sessionTimeMult)

  if mini == 'bolt' then
    return { baseDiff }
  elseif mini == 'torque' then
    local d = baseDiff
    if d == 'easy' then d = 'medium'
    elseif d == 'medium' then d = 'hard' end
    d = adjustDifficulty(d, sessionTimeMult)
    return { d }
  else
    local d = baseDiff
    if d == 'hard' then d = 'medium' end
    d = adjustDifficulty(d, sessionTimeMult)
    return { d, d }
  end
end

local function getKeys()
  return { 'w', 'a', 's', 'd' }
end

local function playBurstFx(veh, boneName)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end
  if not (Config and Config.V3 and Config.V3.fx and Config.V3.fx.sparks) then return end

  local bone = boneName and GetEntityBoneIndexByName(veh, boneName) or -1
  local pos
  if bone and bone ~= -1 then
    pos = GetWorldPositionOfEntityBone(veh, bone)
  else
    pos = GetEntityCoords(veh)
  end

  -- Throttle to avoid FX spam on fast loops
  M._lastFxAt = M._lastFxAt or 0
  local now = GetGameTimer()
  if now - (M._lastFxAt or 0) < 140 then return end
  M._lastFxAt = now

  UseParticleFxAssetNextCall('core')
  StartParticleFxNonLoopedAtCoord('ent_sht_steam', pos.x, pos.y, pos.z + 0.25, 0.0, 0.0, 0.0, 0.7, false, false, false)
end

local function playToolSound(cat, success, perfect)
  -- Use vanilla soundsets to avoid shipping extra audio.
  -- These are quick stingers only.
  local s = nil
  local set = 'DLC_HEIST_FLEECA_SOUNDSET'

  if cat == 'wheel' then
    s = success and 'Drill_Pin_Break' or 'Drill_Pin_Fail'
  elseif cat == 'engine' then
    s = success and 'Drill_Pin_Break' or 'Drill_Pin_Fail'
  elseif cat == 'cut' then
    set = 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS'
    s = success and 'Success' or 'Error'
  else
    s = success and 'Drill_Pin_Break' or 'Drill_Pin_Fail'
  end

  if perfect then
    -- a slightly brighter ping when perfect
    PlaySoundFrontend(-1, 'HACKING_SUCCESS', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS', true)
  end

  if s then
    PlaySoundFrontend(-1, s, set, true)
  end
end

local function microCameraBump(strength)
  strength = tonumber(strength) or 0.03
  -- ultra subtle
  ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', strength)
end

local function progress(label, ms, animDict, animName)
  local ped = PlayerPedId()

  if animDict and animName then
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(0) end
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, ms, 1, 0, false, false, false)
  end

  if canProgress() then
    local ok = lib.progressBar({
      duration = ms,
      label = label,
      useWhileDead = false,
      canCancel = true,
      disable = { move = true, car = true, combat = true },
    })
    ClearPedTasks(ped)
    return ok
  end

  Wait(ms)
  ClearPedTasks(ped)
  return true
end

-- Public API
-- args = { veh, stepKey, label, baseMs, sessionTimeMult, animDict, animName, bone }
-- returns ok(bool), reason(string|nil)
function M.DoStep(args)
  args = args or {}
  local stepKey = tostring(args.stepKey or '')
  local label = tostring(args.label or 'Working')
  local cat = getCategory(stepKey)

  local sessionTimeMult = tonumber(args.sessionTimeMult) or 1.0

  local toolKey = getToolForCategory(cat)
  local masteryLevel = getMasteryLevel(toolKey)

  local ms = BASE_MS[cat] or (tonumber(args.baseMs) or 2400)
  ms = math.floor(ms * sessionTimeMult)
  -- Mastery speed: up to ~5% at level 5
  local masterySpeed = 1.0 - ((masteryLevel - 1) * 0.0125)
  if masterySpeed < 0.95 then masterySpeed = 0.95 end
  ms = math.floor(ms * masterySpeed)
  if ms < 650 then ms = 650 end
  if ms > 4200 then ms = 4200 end

  local didSkill = false
  if Config and Config.V3 and Config.V3.minigames and Config.V3.minigames.enabled then
    local mini = pickMini(stepKey)
    local baseDiff = 'medium'
    if cat == 'vin' or cat == 'plate' or cat == 'move' then baseDiff = 'easy' end
    if cat == 'engine' or cat == 'cut' then baseDiff = 'hard' end

    baseDiff = applyMasteryDifficulty(baseDiff, masteryLevel)
    didSkill = true

    local ok
    if canSkillCheck() then
      local profile = profileForMini(mini, baseDiff, sessionTimeMult)
      ok = (lib.skillCheck(profile, getKeys()) == true)
    else
      ok = fallbackSkill(mini, baseDiff)
    end
    if not ok then
      playToolSound(cat, false, false)
      microCameraBump(0.02)
      return false, 'skill'
    end
    -- perfect isn't exposed by ox_lib, so we approximate: higher mastery = more likely perfect feel.
    local perfect = (masteryLevel >= 4)
    playToolSound(cat, true, perfect)
    microCameraBump(perfect and 0.04 or 0.03)

    -- Report mastery XP on success (server)
    TriggerServerEvent('gs-chopshop:server:toolMastery:add', toolKey, perfect)
  end

  if cat == 'door' or cat == 'panel' or cat == 'wheel' or cat == 'engine' or cat == 'cut' then
    playBurstFx(args.veh, args.bone)
  end

  local ok = progress(label, ms, args.animDict, args.animName)
  if not ok then
    return false, 'cancel'
  end

  -- If minigames are disabled, still grant mastery XP on completion.
  if not didSkill then
    TriggerServerEvent('gs-chopshop:server:toolMastery:add', toolKey, false)
  end

  return true
end

