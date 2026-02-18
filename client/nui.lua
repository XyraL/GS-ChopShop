local uiOpen = false
local allowOpenUntil = 0

local function requestDataDelayed(ms)
  CreateThread(function()
    Wait(ms or 250)
    TriggerServerEvent('gs-chopshop:server:requestData')
  end)
end

local function hardClose()
  uiOpen = false
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)
  SendNUIMessage({ type = 'toggle', state = false })
end

local function openUI()
  if uiOpen then return end
  uiOpen = true
  SetNuiFocus(true, true)
  SetNuiFocusKeepInput(false)
  SendNUIMessage({ type = 'toggle', state = true })
end

AddEventHandler('onClientResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  Wait(200)
  hardClose()
end)

AddEventHandler('playerSpawned', function()
  Wait(400)
  hardClose()
end)

RegisterNetEvent('gs-chopshop:client:armOpen', function()
  allowOpenUntil = GetGameTimer() + 2000
end)

RegisterNetEvent('gs-chopshop:client:openTablet', function()
  if GetGameTimer() > allowOpenUntil then
    print('^1[gs-chopshop]^0 blocked auto-open (not armed)')
    return
  end
  openUI()
  TriggerServerEvent('gs-chopshop:server:requestData')
end)

RegisterNetEvent('gs-chopshop:client:receiveData', function(data)
  SendNUIMessage({ type = 'data', data = data })
end)

RegisterNetEvent('gs-chopshop:client:forceRefresh', function()
  TriggerServerEvent('gs-chopshop:server:requestData')
end)

RegisterNetEvent('gs-chopshop:client:syndicateInvite', function(payload)
  payload = payload or {}
  local syndId = payload.syndicateId
  local name = payload.name or 'Syndicate'

  if lib and lib.alertDialog then
    local res = lib.alertDialog({
      header = 'Syndicate Invite',
      content = ('Join %s?'):format(name),
      centered = true,
      cancel = true,
      labels = { confirm = 'Join', cancel = 'Decline' }
    })
    if res == 'confirm' then
      TriggerServerEvent('gs-chopshop:server:syndicate:acceptInvite', syndId)
      requestDataDelayed(300)
    end
  else
    SendNUIMessage({ type = 'syndInvite', data = { syndicateId = syndId, name = name } })
  end
end)

RegisterNUICallback('close', function(_, cb)
  hardClose()
  cb(true)
end)

RegisterNUICallback('refresh', function(_, cb)
  TriggerServerEvent('gs-chopshop:server:requestData')
  cb(true)
end)

RegisterNUICallback('startContract', function(body, cb)
  TriggerServerEvent('gs-chopshop:server:startContract', body and body.tier)
  cb(true)
end)

RegisterNUICallback('startSpecialContract', function(_, cb)
  TriggerServerEvent('gs-chopshop:server:startSpecialContract')
  cb(true)
end)

RegisterNUICallback('cancelContract', function(_, cb)
  TriggerServerEvent('gs-chopshop:server:cancelContract')
  cb(true)
end)

RegisterNUICallback('saveProfile', function(body, cb)
  local alias = body and body.alias or nil
  local privacy = body and body.privacy or 1
  TriggerServerEvent('gs-chopshop:server:setProfile', alias, privacy)
  cb(true)
end)

-- Co-op removed
RegisterNUICallback('coopInviteNearest', function(_, cb)
  TriggerEvent('gs-chopshop:client:notify', 'Co-op removed. Use Syndicate invites.', 'inform')
  cb(true)
end)

RegisterNUICallback('buyUpgrade', function(body, cb)
  local id = body and body.id or nil
  if id then TriggerServerEvent('gs-chopshop:server:buyUpgrade', id) end
  requestDataDelayed(250)
  cb(true)
end)

RegisterNUICallback('syndDisband', function(_, cb)
  TriggerServerEvent('gs-chopshop:server:syndicate:disband')
  requestDataDelayed(350)
  cb(true)
end)

RegisterNUICallback('syndLeave', function(_, cb)
  TriggerServerEvent('gs-chopshop:server:syndicate:leave')
  requestDataDelayed(350)
  cb(true)
end)

RegisterNUICallback('syndInvite', function(body, cb)
  local target = body and body.target or nil
  TriggerServerEvent('gs-chopshop:server:syndicate:invite', target)
  cb(true)
end)

RegisterNUICallback('syndAcceptInvite', function(body, cb)
  local id = body and body.syndicateId or nil
  TriggerServerEvent('gs-chopshop:server:syndicate:acceptInvite', id)
  requestDataDelayed(350)
  cb(true)
end)

RegisterNUICallback('syndSetRank', function(body, cb)
  local cid = body and body.citizenid or nil
  local rank = body and body.rank or nil
  TriggerServerEvent('gs-chopshop:server:syndicate:setRank', cid, rank)
  requestDataDelayed(350)
  cb(true)
end)

RegisterNUICallback('syndKick', function(body, cb)
  local cid = body and body.citizenid or nil
  TriggerServerEvent('gs-chopshop:server:syndicate:kick', cid)
  requestDataDelayed(350)
  cb(true)
end)


RegisterNUICallback('syndVaultDeposit', function(body, cb)
  local amt = body and body.amount or 0
  TriggerServerEvent('gs-chopshop:server:syndicate:deposit', amt)
  -- DB writes can take a moment; give it a little more breathing room
  -- Some MariaDB setups can be a bit slow (especially on first run). Give it time.
  requestDataDelayed(1600)
  cb(true)
end)

RegisterNUICallback('syndVaultWithdraw', function(body, cb)
  local amt = body and body.amount or 0
  TriggerServerEvent('gs-chopshop:server:syndicate:withdraw', amt)
  requestDataDelayed(1600)
  cb(true)
end)

RegisterNUICallback('syndBuyPerk', function(body, cb)
  local id = body and body.id or nil
  TriggerServerEvent('gs-chopshop:server:syndicate:buyPerk', id)
  requestDataDelayed(450)
  cb(true)
end)

RegisterNUICallback('syndSetRouting', function(body, cb)
  local enabled = body and body.enabled or false
  local percent = body and body.percent or nil
  TriggerServerEvent('gs-chopshop:server:syndicate:setRouting', enabled, percent)
  requestDataDelayed(1600)
  cb(true)
end)

RegisterNUICallback('syndSetBranding', function(body, cb)
  TriggerServerEvent('gs-chopshop:server:syndicate:setBranding', body and body.branding or {})
  requestDataDelayed(1600)
  cb(true)
end)

RegisterNUICallback('syndStartOp', function(body, cb)
  TriggerServerEvent('gs-chopshop:server:syndicate:startOp', body and body.id or nil)
  requestDataDelayed(450)
  cb(true)
end)


-- Legacy (co-op roles removed)
RegisterNUICallback('setRole', function(_, cb)
  TriggerServerEvent('gs-chopshop:server:setRole')
  cb(true)
end)

RegisterNUICallback('createSyndicate', function(body, cb)
  local name = body and body.name or nil
  TriggerServerEvent('gs-chopshop:server:createSyndicate', name)
  requestDataDelayed(350)
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

-- Black Market War
RegisterNUICallback('bmAcceptContract', function(body, cb)
  TriggerServerEvent('gs-chopshop:server:bm:accept', body and body.id or nil)
  cb({ ok = true })
end)

-- Syndicate prestige ladder
RegisterNUICallback('syndPrestigeUp', function(_, cb)
  TriggerServerEvent('gs-chopshop:server:syndicate:prestigeUp')
  cb({ ok = true })
end)
