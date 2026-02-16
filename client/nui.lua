local uiOpen = false
local allowOpenUntil = 0

local function hardClose()
  uiOpen = false
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)
  SendNUIMessage({ type = "toggle", state = false })
end

local function openUI()
  if uiOpen then return end
  uiOpen = true
  SetNuiFocus(true, true)
  SetNuiFocusKeepInput(false)
  SendNUIMessage({ type = "toggle", state = true })
end

-- hard reset so it never auto opens on join/resource start
AddEventHandler('onClientResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  Wait(200)
  hardClose()
end)

AddEventHandler('playerSpawned', function()
  Wait(400)
  hardClose()
end)

-- server arms opening for a short window 
RegisterNetEvent('gs-chopshop:client:armOpen', function()
  allowOpenUntil = GetGameTimer() + 2000
end)

RegisterNetEvent('gs-chopshop:client:openTablet', function()
  if GetGameTimer() > allowOpenUntil then
    print("^1[gs-chopshop]^0 blocked auto-open (not armed)")
    return
  end
  openUI()
  TriggerServerEvent('gs-chopshop:server:requestData')
end)

RegisterNetEvent('gs-chopshop:client:receiveData', function(data)
  SendNUIMessage({ type = "data", data = data })
end)

RegisterNUICallback("close", function(_, cb)
  hardClose()
  cb(true)
end)

RegisterNUICallback("startContract", function(body, cb)
  TriggerServerEvent('gs-chopshop:server:startContract', body.tier)
  cb(true)
end)

RegisterNUICallback("cancelContract", function(_, cb)
  TriggerServerEvent('gs-chopshop:server:cancelContract')
  cb(true)
end)

RegisterNUICallback("refresh", function(_, cb)
  TriggerServerEvent('gs-chopshop:server:requestData')
  cb(true)
end)

RegisterNUICallback("buyUpgrade", function(body, cb)
  local id = body and body.id or 'unknown'
  TriggerServerEvent('gs-chopshop:server:buyUpgrade', id)
  CreateThread(function()
    Wait(250)
    TriggerServerEvent('gs-chopshop:server:requestData')
  end)
  cb(true)
end)

CreateThread(function()
  while true do
    if uiOpen then
      if IsControlJustPressed(0, 322) or IsControlJustPressed(0, 200) then
        hardClose()
      end
      Wait(0)
    else
      Wait(250)
    end
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
  end
end)
