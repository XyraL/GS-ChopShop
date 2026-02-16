--========================================
-- GS-ChopShop Client
-- ox_target part-based chop + search radius
--========================================

local activeContract = nil -- { tier, model, plate, startedAt, expiresAt, searchCenter, searchRadius, found }
local activeSession  = nil -- { netId, bayIndex, done = { [stepKey]=true } }

local foundOnce = false
local inPartAction = false

local searchBlip = nil
local searchBlipCenter = nil
local bayZones = {}
local bayRouteBlip = nil
local lastAutoBegin = 0


local sessionNetId = nil
local sessionVeh = nil

local getNextRequiredStep

getNextRequiredStep = function()
  if not activeSession or not activeSession.requiredList then return nil end
  activeSession.done = activeSession.done or {}

  for _, k in ipairs(activeSession.requiredList) do
    if k ~= "final" and not activeSession.done[k] then
      return k
    end
  end

  for _, k in ipairs(activeSession.requiredList) do
    if k == "final" and not activeSession.done.final then
      return "final"
    end
  end

  return nil
end

_G.getNextRequiredStep = getNextRequiredStep

--========================================
-- PART DEFINITIONS
--========================================
local PARTS = {
  { key = "door_lf",  label = "Remove Driver Door",        bone = "door_dside_f",  time = 4500, icon = "fa-solid fa-door-open" },
  { key = "door_rf",  label = "Remove Passenger Door",     bone = "door_pside_f",  time = 4500, icon = "fa-solid fa-door-open" },
  { key = "door_lr",  label = "Remove Rear Left Door",     bone = "door_dside_r",  time = 4500, icon = "fa-solid fa-door-open" },
  { key = "door_rr",  label = "Remove Rear Right Door",    bone = "door_pside_r",  time = 4500, icon = "fa-solid fa-door-open" },
  { key = "hood",     label = "Remove Hood",               bone = "bonnet",        time = 5000, icon = "fa-solid fa-screwdriver-wrench" },
  { key = "trunk",    label = "Remove Trunk",              bone = "boot",          time = 5000, icon = "fa-solid fa-screwdriver-wrench" },
  { key = "wheel_lf", label = "Remove Front Left Wheel",   bone = "wheel_lf",      time = 4200, icon = "fa-solid fa-tire" },
  { key = "wheel_rf", label = "Remove Front Right Wheel",  bone = "wheel_rf",      time = 4200, icon = "fa-solid fa-tire" },
  { key = "wheel_lr", label = "Remove Rear Left Wheel",    bone = "wheel_lr",      time = 4200, icon = "fa-solid fa-tire" },
  { key = "wheel_rr", label = "Remove Rear Right Wheel",   bone = "wheel_rr",      time = 4200, icon = "fa-solid fa-tire" },
  { key = "engine",   label = "Pull Engine",               bone = "engine",        time = 6500, icon = "fa-solid fa-gears" },
}


-- Build quick lookup for part keys
local PART_KEY_SET = {}
for _, p in ipairs(PARTS) do PART_KEY_SET[p.key] = true end
local PRE_KEY_SET = {}

-- Pre-steps
local PRE_STEPS = {
  { key = "vin_scratch", label = "Scratch VIN",        time = 6000, icon = "fa-solid fa-id-card",       bones = { "windscreen", "window_lf" } },
  { key = "plate_front", label = "Remove Front Plate", time = 3500, icon = "fa-solid fa-screwdriver",   bones = { "bumper_f", "bonnet" } },
  { key = "plate_rear",  label = "Remove Rear Plate",  time = 3500, icon = "fa-solid fa-screwdriver",   bones = { "platelight", "boot" } },
}

for _, s in ipairs(PRE_STEPS) do PRE_KEY_SET[s.key] = true end

--========================================
-- SMALL HELPERS
--========================================
local function trimPlate(p)
  return (p or ""):gsub("%s+", "")
end

local function hasOxLib()
  return (Config and Config.UseOxLib) and GetResourceState("ox_lib") == "started" and lib ~= nil
end

local function notify(msg, nType)
  nType = nType or "inform"
  if hasOxLib() and lib.notify then
    lib.notify({ title = "Chop Shop", description = msg, type = nType })
    return
  end

  -- fallback (QB). Guard in case QBCore isn't running.
  local ok = pcall(function()
    TriggerEvent("QBCore:Notify", msg, nType)
  end)
  if not ok then
    print(("[GS-ChopShop] NOTIFY (%s): %s"):format(nType, msg))
  end
end

local function getVehFromNet(netId)
  if not netId then return nil end
  local ent = NetworkGetEntityFromNetworkId(netId)
  if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
  return nil
end

local function removeSearchBlips()
  if searchBlip and DoesBlipExist(searchBlip) then RemoveBlip(searchBlip) end
  if searchBlipCenter and DoesBlipExist(searchBlipCenter) then RemoveBlip(searchBlipCenter) end
  searchBlip = nil
  searchBlipCenter = nil
end


local function removeBayBlip()
  if bayRouteBlip and DoesBlipExist(bayRouteBlip) then RemoveBlip(bayRouteBlip) end
  bayRouteBlip = nil
end

local function setBayBlip()
  removeBayBlip()
  local bays = Config.Bays or Config.ChopSpots or {}
  if type(bays) ~= 'table' or #bays == 0 then return end

  -- choose nearest bay to the player for routing
  local p = GetEntityCoords(PlayerPedId())
  local bestI, bestD = 1, 999999.0
  for i, bay in ipairs(bays) do
    local dx = p.x - bay.x
    local dy = p.y - bay.y
    local d = (dx*dx + dy*dy)
    if d < bestD then bestD, bestI = d, i end
  end

  local bay = bays[bestI]
  bayRouteBlip = AddBlipForCoord(bay.x, bay.y, bay.z)
  SetBlipSprite(bayRouteBlip, 50) -- garage
  SetBlipScale(bayRouteBlip, 0.85)
  SetBlipColour(bayRouteBlip, 1)
  SetBlipRoute(bayRouteBlip, true)
  BeginTextCommandSetBlipName("STRING")
  AddTextComponentString("Salvage Yard Bay")
  EndTextCommandSetBlipName(bayRouteBlip)
end

local function setSearchBlips(center, radius)
  removeSearchBlips()
  if not center or not radius then return end

  searchBlip = AddBlipForRadius(center.x, center.y, center.z, radius + 0.0)
  SetBlipAlpha(searchBlip, (Config.Search and Config.Search.blipAlpha) or 120)
  SetBlipColour(searchBlip, (Config.Search and Config.Search.blipColor) or 1)
  -- Center marker intentionally disabled (no pinpoint markers, zone only)
end


local function canSkillCheck()
  return GetResourceState("ox_lib") == "started" and lib and lib.skillCheck ~= nil
end

local function doSkill(stepKey)
  -- Minigames are optional and do NOT scale by tier.
  if not (Config.V3 and Config.V3.minigames and Config.V3.minigames.enabled) then return true end
  if not canSkillCheck() then return true end

  local profile
  local keys = { 'w', 'a', 's', 'd' }

  if stepKey == 'plate_front' or stepKey == 'plate_rear' then
    profile = { 'easy' }
  elseif stepKey:find('wheel') then
    profile = { 'easy', 'easy' }
  elseif stepKey:find('door') then
    profile = { 'medium' }
  elseif stepKey == 'engine' then
    profile = { 'medium', 'medium', 'hard' }
  elseif stepKey == 'cut_shell' then
    profile = { 'medium', 'hard' }
  elseif stepKey == 'final' then
    profile = { 'medium' }
  else
    profile = { 'easy', 'easy' }
  end

  return lib.skillCheck(profile, keys) == true
end

local function progressBar(label, ms, animDict, animName)
  local ped = PlayerPedId()

  if animDict and animName then
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(0) end
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, ms, 1, 0, false, false, false)
  end

  if GetResourceState("ox_lib") == "started" and lib and lib.progressBar then
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

  if GetResourceState("progressbar") == "started" then
    local done, cancelled = false, false
    TriggerEvent("progressbar:client:progress", {
      name = "gs_chopshop",
      duration = ms,
      label = label,
      useWhileDead = false,
      canCancel = true,
      controlDisables = {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true
      },
    }, function(wasCancelled)
      cancelled = wasCancelled
      done = true
    end)

    while not done do Wait(50) end
    ClearPedTasks(ped)
    return not cancelled
  end

  -- last-resort fallback
  Wait(ms)
  ClearPedTasks(ped)
  return true
end

local function adjustedTime(ms, isFinal)
  ms = tonumber(ms) or 0
  if ms <= 0 then return 0 end
  if not activeSession then return ms end
  local mult = tonumber(activeSession.timeMult or 1.0) or 1.0
  if isFinal then
    mult = mult * (tonumber(activeSession.finalMult or 1.0) or 1.0)
  end
  local out = math.floor(ms * mult)
  if out < 450 then out = 450 end
  return out
end

local function getAnimForStep(stepKey)

  -- Plates + wheels: kneeling mechanic
  if stepKey == 'plate_front' or stepKey == 'plate_rear'
    or stepKey == 'wheel_lf' or stepKey == 'wheel_rf' or stepKey == 'wheel_lr' or stepKey == 'wheel_rr' then
    return 'amb@world_human_vehicle_mechanic@male@base', 'base'
  end

  -- VIN scratch: inspection vibe
  if stepKey == 'vin_scratch' then
    return 'amb@world_human_clipboard@male@base', 'base'
  end

  -- Engine pull: standing mechanic
  if stepKey == 'engine' then
    return 'amb@world_human_vehicle_mechanic@male@base', 'base'
  end

  -- Moving shell: safe mechanic idle 
  if stepKey == 'move_shell' then
    return 'amb@world_human_vehicle_mechanic@male@idle_a', 'idle_a'
  end

  -- Cutting: welding
  if stepKey == 'cut_shell' then
    return 'amb@world_human_welding@male@base', 'base'
  end

  -- Final dispose: hammering
  if stepKey == 'final' then
    return 'amb@world_human_hammering@male@base', 'base'
  end

  -- Doors / hood / trunk: repair loop
  if stepKey == 'hood' or stepKey == 'trunk'
    or stepKey == 'door_lf' or stepKey == 'door_rf' or stepKey == 'door_lr' or stepKey == 'door_rr' then
    return 'mini@repair', 'fixing_a_ped'
  end

  -- Fallback
  return 'mini@repair', 'fixing_a_ped'
end


local function doPartVisuals(veh, key)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end

  if key == "hood" then
    SetVehicleDoorOpen(veh, 4, false, true)
    Wait(200)
    SetVehicleDoorBroken(veh, 4, true)
  elseif key == "trunk" then
    SetVehicleDoorOpen(veh, 5, false, true)
    Wait(200)
    SetVehicleDoorBroken(veh, 5, true)
  elseif key == "door_lf" then
    SetVehicleDoorBroken(veh, 0, true)
  elseif key == "door_rf" then
    SetVehicleDoorBroken(veh, 1, true)
  elseif key == "door_lr" then
    SetVehicleDoorBroken(veh, 2, true)
  elseif key == "door_rr" then
    SetVehicleDoorBroken(veh, 3, true)
  elseif key == "wheel_lf" then
    SetVehicleTyreBurst(veh, 0, true, 1000.0)
  elseif key == "wheel_rf" then
    SetVehicleTyreBurst(veh, 1, true, 1000.0)
  elseif key == "wheel_lr" then
    SetVehicleTyreBurst(veh, 4, true, 1000.0)
  elseif key == "wheel_rr" then
    SetVehicleTyreBurst(veh, 5, true, 1000.0)
  elseif key == "engine" then
    SetVehicleDoorOpen(veh, 4, false, true)
    Wait(300)
    SetVehicleEngineHealth(veh, 0.0)
    SetVehiclePetrolTankHealth(veh, 0.0)
    SetVehicleEngineOn(veh, false, true, true)
  end
end

local function allNonFinalDoneClient()
  if not activeSession or not activeSession.done then return false end

  if activeSession.requiredList then
    for _, k in ipairs(activeSession.requiredList) do
      if not activeSession.done[k] then
        return false
      end
    end
    return true
  end

  -- Fallback: config-driven (legacy)
  for _, s in ipairs(Config.AdvancedSteps or {}) do
    if s.key ~= "final" and not activeSession.done[s.key] then
      return false
    end
  end
  return true
end

--========================================
-- TARGET CLEANUP / BUILD
--========================================
local function clearSessionTargets()
  inPartAction = false
  sessionNetId = nil

  if GetResourceState("ox_target") ~= "started" then
    sessionVeh = nil
    return
  end

  if sessionVeh and DoesEntityExist(sessionVeh) then
    pcall(function()
      exports.ox_target:removeLocalEntity(sessionVeh)
    end)
  end
  sessionVeh = nil
end

local function stepEnabled(stepKey)
  local function contractForces(k)
    if not activeContract or not activeContract.modifiers then return false end
    k = tostring(k)
    local map = {
      require_vin = { vin_scratch = true },
      plates_mandatory = { plate_front = true, plate_rear = true },
      cut_required = { move_shell = true, cut_shell = true },
    }
    for i = 1, #activeContract.modifiers do
      local m = activeContract.modifiers[i]
      local id = m and m.id
      if id and map[id] and map[id][k] then return true end
    end
    return false
  end

  if stepKey == "vin_scratch" then
    return (Config.V2 and Config.V2.vinScratch) or contractForces(stepKey)
  end
  if stepKey == "plate_front" or stepKey == "plate_rear" then
    return (Config.V2 and Config.V2.removePlates) or contractForces(stepKey)
  end
  return true
end

local STEP_BONES_CLIENT = {
  door_lf = { "door_dside_f" },
  door_rf = { "door_pside_f" },
  door_lr = { "door_dside_r" },
  door_rr = { "door_pside_r" },
  hood = { "bonnet" },
  trunk = { "boot" },
  wheel_lf = { "wheel_lf" },
  wheel_rf = { "wheel_rf" },
  wheel_lr = { "wheel_lr" },
  wheel_rr = { "wheel_rr" },
  engine = { "engine" },
  vin_scratch = { "windscreen", "window_lf" },
  plate_front = { "bumper_f", "bonnet" },
  plate_rear  = { "platelight", "boot" },
}

local function stepApplicableToVehicleClient(veh, stepKey)
  local bones = STEP_BONES_CLIENT[stepKey]
  if not bones then return true end
  for _, b in ipairs(bones) do
    local bi = GetEntityBoneIndexByName(veh, b)
    if bi and bi ~= -1 then
      return true
    end
  end
  return false
end

local function computeRequiredListForVehicle(veh)
  local list = {}
  if not veh or veh == 0 or not DoesEntityExist(veh) then return list end

  for _, s in ipairs(Config.AdvancedSteps or {}) do
    local k = tostring(s.key or "")
    if k ~= "" and k ~= "final" and stepEnabled(k) and stepApplicableToVehicleClient(veh, k) then
      list[#list + 1] = k
    end
  end
  return list
end


local function buildVehiclePartTargets(netId)
  if GetResourceState("ox_target") ~= "started" then
    notify("ox_target is required for advanced chop interactions.", "error")
    return
  end

  sessionNetId = netId
  sessionVeh = getVehFromNet(netId)

  if not sessionVeh then
    print("[GS-ChopShop] buildVehiclePartTargets: vehicle missing for netId:", netId)
    return
  end

  -- wipe old if any
  pcall(function()
    exports.ox_target:removeLocalEntity(sessionVeh)
  end)

  local opts = {}


local requiredSet = {}
if activeSession and activeSession.requiredList then
  for _, k in ipairs(activeSession.requiredList) do
    requiredSet[k] = true
  end
end

local function isRequired(stepKey)
  -- if server didn't send a list, assume all steps are allowed
  if not activeSession or not activeSession.requiredList then return true end
  return requiredSet[stepKey] == true
end

local function boneExists(boneName)
  if not sessionVeh or not DoesEntityExist(sessionVeh) then return false end
  if not boneName then return true end
  local bi = GetEntityBoneIndexByName(sessionVeh, boneName)
  return bi and bi ~= -1
end

local function anyBoneExists(bones)
  if not bones then return true end
  for _, b in ipairs(bones) do
    if boneExists(b) then return true end
  end
  return false
end


  -- Pre steps
  for _, step in ipairs(PRE_STEPS) do
    if stepEnabled(step.key) then
      opts[#opts+1] = {
        name = "gs_chop_" .. step.key,
        icon = step.icon,
        label = step.label,
        bones = step.bones,
        distance = 2.0,
        canInteract = function()
          if inPartAction then return false end
          if not activeContract or not activeSession then return false end
          if not activeSession.netId or activeSession.netId ~= netId then return false end
          if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
          if activeSession.done and activeSession.done[step.key] then return false end
          if Config.V3 and Config.V3.enforceStepOrder then
            local nextKey = getNextRequiredStep()
            if nextKey and nextKey ~= step.key then return false end
          end
          return true
        end,
        onSelect = function()
          if inPartAction then return end
          inPartAction = true

          if not doSkill(step.key) then
            notify('Failed. Try again.', 'error')
            inPartAction = false
            return
          end

          local d,a = getAnimForStep(step.key)
          local ok = progressBar(step.label, adjustedTime(step.time, step.key == 'cut_shell' or step.key == 'final'), d, a)
          if ok then
            TriggerServerEvent("gs-chopshop:server:completeStep", step.key)
          else
            notify("Canceled.", "error")
          end

          inPartAction = false
        end
      }
    end
  end

  -- Parts
  for _, part in ipairs(PARTS) do
    if isRequired(part.key) and boneExists(part.bone) then
      opts[#opts+1] = {
      name = "gs_chop_" .. part.key,
      icon = part.icon or "fa-solid fa-screwdriver-wrench",
      label = part.label,
      bones = part.bone and { part.bone } or nil,
      distance = 2.0,
      canInteract = function()
        if inPartAction then return false end
        if not activeContract or not activeSession then return false end
        if not activeSession.netId or activeSession.netId ~= netId then return false end
        if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
        if activeSession.done and activeSession.done[part.key] then return false end
        if Config.V3 and Config.V3.enforceStepOrder then
          local nextKey = getNextRequiredStep()
          if nextKey and nextKey ~= part.key then return false end
        end
        return true
      end,
      onSelect = function()
        if inPartAction then return end
        if not activeSession or not activeSession.done then return end
        if activeSession.done[part.key] then return end

        local veh = getVehFromNet(sessionNetId)
        if not veh then
          notify("Vehicle missing.", "error")
          return
        end

        inPartAction = true
        if not doSkill('cut_shell') then
          inPartAction = false
          notify('Failed. Try again.', 'error')
          return
        end
        local d,a = getAnimForStep(part.key)
        local ok = progressBar(part.label, adjustedTime(part.time, false), d, a)
        if not ok then
          inPartAction = false
          notify("Canceled.", "error")
          return
        end

        TriggerServerEvent("gs-chopshop:server:completeStep", part.key)

        inPartAction = false
      end
    }
    end
  end

  -- V3 workflow: cut shell (vehicle interaction)
  if Config.V3 and Config.V3.enableMoveCutCrush and isRequired('cut_shell') and boneExists('bonnet') then
    opts[#opts+1] = {
      name = 'gs_chop_cut_shell',
      icon = 'fa-solid fa-fire',
      label = 'Cut Shell',
      bones = { 'bonnet' },
      distance = 2.8,
      canInteract = function()
        if inPartAction then return false end
        if not activeContract or not activeSession then return false end
        if not activeSession.netId or activeSession.netId ~= netId then return false end
        if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
        if activeSession.done and activeSession.done.cut_shell then return false end
        if Config.V3 and Config.V3.enforceStepOrder then
          local nextKey = getNextRequiredStep()
          if nextKey and nextKey ~= 'cut_shell' then return false end
        end
        return true
      end,
      onSelect = function()
        if inPartAction then return end
        local veh = getVehFromNet(sessionNetId)
        if not veh then
          notify('Vehicle missing.', 'error')
          return
        end

        inPartAction = true
      if not doSkill('final') then
          inPartAction = false
          notify('Failed. Try again.', 'error')
          return
        end
        local ok = progressBar('Cutting shell', 7500, 'amb@world_human_welding@male@base', 'base')
        if not ok then
          inPartAction = false
          notify('Canceled.', 'error')
          return
        end

        if Config.V3 and Config.V3.fx and Config.V3.fx.sparks then
          local pos = GetEntityCoords(veh)
          UseParticleFxAssetNextCall('core')
          StartParticleFxNonLoopedAtCoord('ent_sht_steam', pos.x, pos.y, pos.z + 0.5, 0.0, 0.0, 0.0, 1.0, false, false, false)
        end

        TriggerServerEvent('gs-chopshop:server:completeStep', 'cut_shell')
        inPartAction = false
      end
    }
  end

  -- Final option on the VEHICLE
  local useConverter = Config.V2 and Config.V2.useConverterFinale
  if not useConverter then
    opts[#opts+1] = {
      name = "gs_chop_final",
      icon = "fa-solid fa-trash",
      label = "Dispose Shell",
      distance = 3.0,
      canInteract = function()
        if inPartAction then return false end
        if not activeContract or not activeSession then return false end
        if not allNonFinalDoneClient() then return false end
        if Config.V3 and Config.V3.enforceStepOrder then
          local nextKey = getNextRequiredStep()
          if nextKey and nextKey ~= 'final' then return false end
        end
        if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
        return true
      end,
      onSelect = function()
        if inPartAction then return end
        if not allNonFinalDoneClient() then
          notify("Strip all parts first.", "error")
          return
        end

        inPartAction = true
        if not doSkill('move_shell') then
        notify('Failed. Try again.', 'error')
        inPartAction = false
        return
      end
      local ok = progressBar("Disposing shell", 6000, "amb@world_human_hammering@male@base", "base")
        if ok then
          TriggerServerEvent("gs-chopshop:server:completeStep", "final")
        else
          notify("Canceled.", "error")
        end
        inPartAction = false
      end
    }
  end

  exports.ox_target:addLocalEntity(sessionVeh, opts)
end

local function rebuildBayZones()
  if GetResourceState("ox_target") ~= "started" then
    return
  end

  -- remove old zones
  for _, id in ipairs(bayZones) do
    pcall(function()
      exports.ox_target:removeZone(id)
    end)
  end
  bayZones = {}

  local bays = Config.Bays or Config.ChopSpots or {}
  for i, bay in ipairs(bays) do
    local id = exports.ox_target:addSphereZone({
      coords = vec3(bay.x, bay.y, bay.z),
      radius = (bay.radius or 4.0),
      debug = false,
      options = {
        {
          name = ("gs_chop_move_%d"):format(i),
          icon = "fa-solid fa-location-crosshairs",
          label = "Push Shell to Cut Line",
          distance = 2.0,
          canInteract = function()
            if not (Config.V3 and Config.V3.enableMoveCutCrush) then return false end
            if not activeContract or not activeSession then return false end
            if activeSession.bayIndex ~= i then return false end
            if not activeSession.requiredList then return false end
            if activeSession.done and activeSession.done.move_shell then return false end
            if Config.V3 and Config.V3.enforceStepOrder then
              local nextKey = getNextRequiredStep()
              if nextKey and nextKey ~= 'move_shell' then return false end
            end
            if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
            -- only show if move_shell is required for this session
            local required = false
            for _, k in ipairs(activeSession.requiredList) do
              if k == 'move_shell' then required = true break end
            end
            if not required then return false end
            return true
          end,
          onSelect = function()
            if inPartAction then return end
            if not activeSession or not activeSession.netId then return end

            local veh = getVehFromNet(activeSession.netId)
            if not veh then
              notify('Contract vehicle missing.', 'error')
              return
            end

            -- must be near the bay
            local vpos = GetEntityCoords(veh)
            local bpos = vec3(bay.x, bay.y, bay.z)
            if #(vpos - bpos) > 10.0 then
              notify('Bring the vehicle into your bay first.', 'error')
              return
            end

            -- must be near the cut line point
            local off = (Config.V3 and Config.V3.cutLine and Config.V3.cutLine.offsetForward) or 2.2
            local rad = (Config.V3 and Config.V3.cutLine and Config.V3.cutLine.radius) or 3.0
            local h = math.rad((bay.w or 0.0) + 0.0)
            local cut = vec3(bay.x + (math.cos(h) * off), bay.y + (math.sin(h) * off), bay.z)

            local dist = #(vpos - cut)
            if dist > rad then
              notify(("Push the shell onto the cut line (%.1fm away). Then hop out and align."):format(dist), 'error')
              return
            end

            inPartAction = true
            if not doSkill('move_shell') then
              inPartAction = false
              notify('Failed. Try again.', 'error')
              return
            end
            local ok = progressBar('Aligning shell', 2000, 'mini@repair', 'fixing_a_ped')
            if ok then
              TriggerServerEvent('gs-chopshop:server:completeStep', 'move_shell')
            else
              notify('Canceled.', 'error')
            end
            inPartAction = false
          end,
        },
      }
    })

    bayZones[#bayZones+1] = id
  end

end -- rebuildBayZones

--========================================
-- CONTRACT FLOW EVENTS
--========================================

RegisterNetEvent("gs-chopshop:client:notify", function(msg, nType)
  notify(msg, nType)
end)

RegisterNetEvent('gs-chopshop:client:forkliftSpawned', function(netId)
  notify('Forklift spawned at the yard.', 'success')
end)

RegisterNetEvent("gs-chopshop:client:beginSearch", function(c)
  activeContract = c
  foundOnce = false

  if activeContract and activeContract.searchCenter and activeContract.searchRadius then
    setSearchBlips(activeContract.searchCenter, activeContract.searchRadius)
  end


  if Config.V3 and Config.V3.hints and Config.V3.hints.enabled then
    local nextKey = getNextRequiredStep()
    if nextKey == 'move_shell' then
      notify('All parts stripped. Push the shell onto the cut line marker.', 'inform')
    elseif nextKey == 'engine' then
      notify('Keep stripping parts. Engine is next.', 'inform')
    elseif nextKey == 'cut_shell' then
      notify('Shell positioned. Cut it open at the hood.', 'inform')
    elseif nextKey == 'final' then
      notify('Almost done. Dispose the shell for payout.', 'inform')
    end
  end
end)


RegisterNetEvent("gs-chopshop:client:foundAck", function()
  foundOnce = true
  if activeContract then activeContract.found = true end
  removeSearchBlips()
  setBayBlip()

  if Config.V3 and Config.V3.hints and Config.V3.hints.enabled then
    local nextKey = getNextRequiredStep()
    if nextKey == 'move_shell' then
      notify('All parts stripped. Push the shell onto the cut line marker.', 'inform')
    elseif nextKey == 'engine' then
      notify('Keep stripping parts. Engine is next.', 'inform')
    elseif nextKey == 'cut_shell' then
      notify('Shell positioned. Cut it open at the hood.', 'inform')
    elseif nextKey == 'final' then
      notify('Almost done. Dispose the shell for payout.', 'inform')
    end
  end
end)


RegisterNetEvent("gs-chopshop:client:contractCanceled", function()
  activeContract = nil
  activeSession = nil
  foundOnce = false
  removeSearchBlips()
  removeBayBlip()
  clearSessionTargets()
  notify("Contract canceled.", "error")

  -- Refresh tablet data after cancel
  CreateThread(function()
    Wait(250)
    TriggerServerEvent('gs-chopshop:server:requestData')
  end)
end)

RegisterNetEvent("gs-chopshop:client:contractCompleted", function(cash)
  -- NUI completion cinematic
  pcall(function()
    SendNUIMessage({
      type = 'completeCinematic',
      cash = tonumber(cash) or 0,
      tier = activeContract and activeContract.tier or nil,
      plate = activeContract and activeContract.plate or nil,
      model = activeContract and activeContract.model or nil,
      modifiers = activeContract and activeContract.modifiers or {},
    })
  end)

  activeContract = nil
  activeSession = nil
  foundOnce = false
  removeSearchBlips()
  removeBayBlip()
  clearSessionTargets()
  notify(("Contract complete. +$%d"):format(tonumber(cash) or 0), "success")

  -- Refresh tablet data (history/progress) after completion
  CreateThread(function()
    Wait(600)
    TriggerServerEvent('gs-chopshop:server:requestData')
  end)
end)

RegisterNetEvent("gs-chopshop:client:chopSessionStarted", function(data)
  if not data or not data.netId then
    print("[GS-ChopShop] chopSessionStarted missing data/netId")
    return
  end

  activeSession = activeSession or {}
  activeSession.netId = data.netId
  activeSession.bayIndex = data.bayIndex
  activeSession.done = data.done or {}
  activeSession.requiredList = data.required or data.requiredList or nil
  activeSession.timeMult = data.timeMult or activeSession.timeMult or 1.0
  activeSession.finalMult = data.finalMult or activeSession.finalMult or 1.0

  -- Hardening: if server sends no required list (or empty), compute locally from the vehicle so order + gating works.
  if (not activeSession.requiredList) or (#activeSession.requiredList == 0) then
    local veh = getVehFromNet(data.netId)
    local t = GetGameTimer() + 1500
    while (not veh or veh == 0 or not DoesEntityExist(veh)) and GetGameTimer() < t do
      Wait(50)
      veh = getVehFromNet(data.netId)
    end
    if veh and veh ~= 0 and DoesEntityExist(veh) then
      activeSession.requiredList = computeRequiredListForVehicle(veh)
    end
  end

  buildVehiclePartTargets(data.netId)
  notify("Chop started. Strip the vehicle.", "inform")

  if Config.V3 and Config.V3.hints and Config.V3.hints.enabled and Config.V3.enableMoveCutCrush then
    notify('After stripping, align the shell on the cut line marker.', 'inform')
  end
end)

RegisterNetEvent("gs-chopshop:client:stepAck", function(stepKey)
  if not activeSession then return end
  activeSession.done = activeSession.done or {}
  activeSession.done[stepKey] = true


  -- Apply visuals only after server ack to prevent desync
  if PART_KEY_SET and PART_KEY_SET[stepKey] then
    local veh = getVehFromNet(activeSession.netId)
    if veh then
      doPartVisuals(veh, stepKey)
    end
  end

  if stepKey ~= "final" then
    notify("Step complete.", "success")
  else
    -- server will also send contractCompleted normally
    clearSessionTargets()
  end


  if Config.V3 and Config.V3.hints and Config.V3.hints.enabled then
    local nextKey = getNextRequiredStep()
    if nextKey == 'move_shell' then
      notify('All parts stripped. Push the shell onto the cut line marker.', 'inform')
    elseif nextKey == 'engine' then
      notify('Keep stripping parts. Engine is next.', 'inform')
    elseif nextKey == 'cut_shell' then
      notify('Shell positioned. Cut it open at the hood.', 'inform')
    elseif nextKey == 'final' then
      notify('Almost done. Dispose the shell for payout.', 'inform')
    end
  end
end)


RegisterNetEvent("gs-chopshop:client:receiveData", function(data)
  -- tablet refresh support
  if data and data.contract then
    activeContract = data.contract
    foundOnce = activeContract.found and true or false

    if activeContract and not foundOnce and activeContract.searchCenter and activeContract.searchRadius then
      setSearchBlips(activeContract.searchCenter, activeContract.searchRadius)
    else
      removeSearchBlips()
    end
  else
    activeContract = nil
    foundOnce = false
    removeSearchBlips()
  end

  if data and data.session then
    activeSession = activeSession or {}

    activeSession.netId = data.session.netId
    activeSession.bayIndex = data.session.bayIndex
    activeSession.done = data.session.done or activeSession.done or {}

    -- NUI + ordering expects an ARRAY here.
    local incomingList = data.session.requiredList or data.session.required
    if type(incomingList) == 'table' and #incomingList > 0 then
      activeSession.requiredList = incomingList
    elseif not activeSession.requiredList or #activeSession.requiredList == 0 then
      -- Fallback: compute locally if still missing
      local veh = activeSession.netId and getVehFromNet(activeSession.netId) or nil
      if veh and veh ~= 0 and DoesEntityExist(veh) then
        activeSession.requiredList = computeRequiredListForVehicle(veh)
      end
    end

    if activeSession.netId then
      buildVehiclePartTargets(activeSession.netId)
    end
  else
    activeSession = nil
    clearSessionTargets()
  end
end)

--========================================
-- VEHICLE SPAWN (CLIENT-SIDE)
--========================================
RegisterNetEvent("gs-chopshop:client:spawnContractVehicle", function(data)
  if Config.Debug then
    print("[GS-ChopShop] client spawnContractVehicle fired", json.encode(data))
  end

  if not data or not data.model or not data.plate or not data.searchCenter or not data.searchRadius then
    if Config.Debug then
      print("[GS-ChopShop] spawnContractVehicle missing data", json.encode(data))
    end
    notify("Spawn data missing.", "error")
    TriggerServerEvent("gs-chopshop:server:registerSpawnedVehicle", nil, data and data.plate or "")
    return
  end

  local modelName = data.model
  local plateWanted = trimPlate(data.plate)
  local center = data.searchCenter
  local radius = tonumber(data.searchRadius) or ((Config.Search and Config.Search.radius) or 180.0)

  local model = joaat(modelName)
  if not model or model == 0 then
    notify("Invalid vehicle model.", "error")
    TriggerServerEvent("gs-chopshop:server:registerSpawnedVehicle", nil, plateWanted)
    return
  end

  RequestModel(model)
  local t = GetGameTimer() + 8000
  while not HasModelLoaded(model) and GetGameTimer() < t do Wait(0) end
  if not HasModelLoaded(model) then
    notify("Model load failed.", "error")
    TriggerServerEvent("gs-chopshop:server:registerSpawnedVehicle", nil, plateWanted)
    return
  end

  local function randInCircle(r)
    local ang = math.random() * math.pi * 2
    local dist = math.sqrt(math.random()) * r
    return math.cos(ang) * dist, math.sin(ang) * dist
  end

  local spawn = nil
  for i = 1, 40 do
    local ox, oy = randInCircle(radius)
    local x = center.x + ox
    local y = center.y + oy
    local z = center.z + 50.0

    local ok, outPos, outHeading = GetClosestVehicleNodeWithHeading(x, y, z, 1, 3.0, 0)
    if ok then
      local dx = outPos.x - center.x
      local dy = outPos.y - center.y
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist <= radius then
        spawn = { x = outPos.x, y = outPos.y, z = outPos.z, h = outHeading }
        break
      end
    end
    Wait(0)
  end

  if not spawn then
    local ok, outPos, outHeading = GetClosestVehicleNodeWithHeading(center.x, center.y, center.z + 50.0, 1, 3.0, 0)
    if ok then
      spawn = { x = outPos.x, y = outPos.y, z = outPos.z, h = outHeading }
    else
      spawn = { x = center.x, y = center.y, z = center.z + 1.0, h = math.random(0, 359) + 0.0 }
    end
  end

  local veh = CreateVehicle(model, spawn.x, spawn.y, spawn.z, spawn.h, true, true)
  if veh == 0 or not DoesEntityExist(veh) then
    print(("[GS-ChopShop] CreateVehicle FAILED model=%s at %.2f %.2f %.2f"):format(modelName, spawn.x, spawn.y, spawn.z))
    notify("Vehicle spawn failed.", "error")
    TriggerServerEvent("gs-chopshop:server:registerSpawnedVehicle", nil, plateWanted)
    return
  end

  SetEntityAsMissionEntity(veh, true, true)
  SetVehicleHasBeenOwnedByPlayer(veh, true)
  SetVehicleOnGroundProperly(veh)
  SetVehicleDoorsLocked(veh, 1)
  SetVehicleEngineOn(veh, false, true, true)
  SetVehicleNumberPlateText(veh, plateWanted)

  local p = GetEntityCoords(veh)
  if Config.Debug then
    print(("[GS-ChopShop] spawned %s plate=%s at %.2f %.2f %.2f (center %.2f %.2f r=%.1f)"):format(
      modelName, plateWanted, p.x, p.y, p.z, center.x, center.y, radius
    ))
  end

  local netId = NetworkGetNetworkIdFromEntity(veh)
  SetNetworkIdExistsOnAllMachines(netId, true)
  SetNetworkIdCanMigrate(netId, false)

  TriggerServerEvent("gs-chopshop:server:registerSpawnedVehicle", netId, plateWanted, { x = p.x, y = p.y, z = p.z })
  SetModelAsNoLongerNeeded(model)
end)

--========================================
-- REQUIRED-STEP MARKERS
--========================================

local function drawStepMarker(stepKey)
  if not stepKey or not activeSession or not activeSession.netId then return end
  local veh = getVehFromNet(activeSession.netId)
  if not veh then return end

  local pos
  -- Bone-based markers for part steps
  local bone = nil
  for _, p in ipairs(PARTS) do
    if p.key == stepKey then bone = p.bone break end
  end
  if not bone then
    for _, s in ipairs(PRE_STEPS) do
      if s.key == stepKey and s.bones and s.bones[1] then
        bone = s.bones[1]
        break
      end
    end
  end

  if bone then
    local bi = GetEntityBoneIndexByName(veh, bone)
    if bi and bi ~= -1 then
      pos = GetWorldPositionOfEntityBone(veh, bi)
    end
  end

  if not pos then
    pos = GetEntityCoords(veh)
  end

  -- Red arrow marker hovering near the required spot
  DrawMarker(2, pos.x, pos.y, pos.z + 0.65, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.25, 0.25, 0.25, 220, 30, 30, 180, false, true, 2, false, nil, nil, false)
end

CreateThread(function()
  while true do
    if activeContract and activeSession and Config.V4 and Config.V4.guides and Config.V4.guides.showNextStepArrow and Config.V3 and Config.V3.enforceStepOrder then
      local nextKey = getNextRequiredStep()
      if nextKey then
        drawStepMarker(nextKey)
        Wait(0)
      else
        Wait(250)
      end
    else
      Wait(500)
    end
  end
end)

--========================================
-- FOUND VEHICLE DETECTOR
--========================================
CreateThread(function()
  while true do
    Wait(600)

    if not activeContract or foundOnce or (activeContract and activeContract.found) then
      goto continue
    end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
      local veh = GetVehiclePedIsIn(ped, false)
      if veh ~= 0 then
        local plate = trimPlate(GetVehicleNumberPlateText(veh))
        if plate == trimPlate(activeContract.plate) then
          foundOnce = true
          removeSearchBlips()
          notify("Contract vehicle found.", "success")
          TriggerServerEvent("gs-chopshop:server:markFound", VehToNet(veh), plate)
          if activeContract then activeContract.found = true end
        end
      end
    end

    ::continue::
  end
end)

--========================================
-- CUT LINE MARKER (HELPER)
--========================================
CreateThread(function()
  while true do
    Wait(0)

    if not (Config.V3 and Config.V3.enableMoveCutCrush and Config.V3.cutLine and Config.V3.cutLine.enabled) then
      Wait(750)
      goto continue
    end

    if not activeSession or not activeSession.netId or not activeSession.bayIndex then
      Wait(500)
      goto continue
    end

    if activeSession.done and activeSession.done.move_shell then
      Wait(500)
      goto continue
    end

    -- only show if move_shell is required
    local required = false
    if activeSession.requiredList then
      for _, k in ipairs(activeSession.requiredList) do
        if k == 'move_shell' then required = true break end
      end
    end
    if not required then
      Wait(750)
      goto continue
    end

    local bay = (Config.Bays and Config.Bays[activeSession.bayIndex])
    if not bay then
      Wait(750)
      goto continue
    end

    local off = Config.V3.cutLine.offsetForward or 2.2
    local h = math.rad((bay.w or 0.0) + 0.0)
    local x = bay.x + (math.cos(h) * off)
    local y = bay.y + (math.sin(h) * off)
    local z = bay.z + 0.15

    local m = Config.V3.cutLine.marker or {}
    DrawMarker(m.type or 1, x, y, z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, m.scale or 1.25, m.scale or 1.25, m.height or 0.25, 255, 255, 255, 140, false, false, 2, false, nil, nil, false)

    ::continue::
  end
end)



--========================================
-- GUIDE MARKERS (NEXT STEP ARROWS)
--========================================

local function drawArrowAt(pos)
  if not pos then return end
  DrawMarker(2, pos.x, pos.y, pos.z + 1.25, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.35, 0.35, 0.35, 180, 180, 255, 220, false, true, 2, false, nil, nil, false)
end

CreateThread(function()
  while true do
    Wait(0)
    if not (Config.V4 and Config.V4.guides and Config.V4.guides.enabled) then
      Wait(750)
    else
      if not activeContract or not activeSession or not activeSession.netId then
        Wait(500)
      else
        local ped = PlayerPedId()
        local ppos = GetEntityCoords(ped)
        local drawDist = (Config.V4.guides.markerDrawDist or 35.0) + 0.0

        local nextKey = getNextRequiredStep()
        if nextKey then
          local veh = getVehFromNet(activeSession.netId)
          if veh and DoesEntityExist(veh) then
            -- Cut line marker for move_shell (push stage)
            if nextKey == "move_shell" and Config.V3 and Config.V3.cutLine and Config.V3.cutLine.enabled and Config.V4.guides.showCutLineMarker then
              local bay = (Config.Bays or Config.ChopSpots or {})[activeSession.bayIndex or 1]
              if bay then
                local off = (Config.V3.cutLine.offsetForward or 2.2) + 0.0
                local h = math.rad((bay.w or 0.0) + 0.0)
                local cut = vec3(bay.x + (math.cos(h) * off), bay.y + (math.sin(h) * off), bay.z)
                if #(ppos - cut) <= drawDist then
                  DrawMarker(1, cut.x, cut.y, cut.z - 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.4, 1.4, 0.35, 90, 190, 255, 180, false, true, 2, false, nil, nil, false)
                  if Config.V4.guides.showNextStepArrow then
                    drawArrowAt(cut)
                  end
                end
              end
            else
              -- Arrow over next part bone / front of vehicle
              local partPos = nil
              for _, p in ipairs(PARTS) do
                if p.key == nextKey and p.bone then
                  local bi = GetEntityBoneIndexByName(veh, p.bone)
                  if bi and bi ~= -1 then
                    partPos = GetWorldPositionOfEntityBone(veh, bi)
                  end
                  break
                end
              end
              if not partPos then
                -- pre steps bones
                for _, s in ipairs(PRE_STEPS) do
                  if s.key == nextKey and s.bones and s.bones[1] then
                    local bi = GetEntityBoneIndexByName(veh, s.bones[1])
                    if bi and bi ~= -1 then
                      partPos = GetWorldPositionOfEntityBone(veh, bi)
                    end
                    break
                  end
                end
              end
              if not partPos and nextKey == "cut_shell" then
                local bi = GetEntityBoneIndexByName(veh, "bonnet")
                if bi and bi ~= -1 then partPos = GetWorldPositionOfEntityBone(veh, bi) end
              end
              if not partPos and nextKey == "final" then
                partPos = GetEntityCoords(veh)
              end

              if partPos and #(ppos - partPos) <= drawDist and Config.V4.guides.showNextStepArrow then
                drawArrowAt(partPos)
              end
            end
          end
        end
      end
    end
  end
end)

-- Auto-begin chop when driving the contract vehicle into a bay
CreateThread(function()
  while true do
    Wait(350)

    if not activeContract or not activeContract.found then
      goto continue
    end
    if activeSession then
      goto continue
    end

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then goto continue end

    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then goto continue end
    if GetPedInVehicleSeat(veh, -1) ~= ped then goto continue end

    local plate = trimPlate(GetVehicleNumberPlateText(veh))
    if plate ~= trimPlate(activeContract.plate) then goto continue end

    -- find bay within radius
    local bays = Config.Bays or Config.ChopSpots or {}
    local p = GetEntityCoords(veh)
    for i, bay in ipairs(bays) do
      local r = (bay.radius or 4.0)
      local dx = p.x - bay.x
      local dy = p.y - bay.y
      local dz = p.z - bay.z
      if (dx*dx + dy*dy + dz*dz) <= (r*r) then
        local nowt = GetGameTimer()
        if nowt - lastAutoBegin > 2500 then
          lastAutoBegin = nowt
          notify('Bay reached. Starting chop...', 'inform')
          TriggerServerEvent('gs-chopshop:server:beginChop', VehToNet(veh), i, computeRequiredListForVehicle(veh))
        end
        break
      end
    end

    ::continue::
  end
end)

-- STARTUP / STOP
--========================================
CreateThread(function()
  Wait(500)
  rebuildBayZones()
end)

AddEventHandler("onClientResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end
  Wait(500)
  rebuildBayZones()
end)

AddEventHandler("onResourceStop", function(res)
  if res ~= GetCurrentResourceName() then return end
  removeSearchBlips()
  removeBayBlip()
  clearSessionTargets()

  if GetResourceState("ox_target") == "started" then
    for _, id in ipairs(bayZones) do
      pcall(function()
        exports.ox_target:removeZone(id)
      end)
    end
  end
end)
