FW = {
  name = nil,
  core = nil,
}

local function detect()
  if Config.Framework ~= "auto" then return Config.Framework end
  if GetResourceState('qbx_core') == 'started' then return 'qbox' end
  if GetResourceState('qb-core') == 'started' then return 'qbcore' end
  return 'qbcore'
end

function FW.Init()
  FW.name = detect()

  if FW.name == 'qbox' then
    FW.core = exports['qbx_core']
  else
    FW.core = exports['qb-core']:GetCoreObject()
  end

  Util.Debug("Framework:", FW.name)
end

function FW.GetPlayer(src)
  if FW.name == 'qbox' then
    return FW.core:GetPlayer(src)
  else
    return FW.core.Functions.GetPlayer(src)
  end
end

function FW.GetCid(player)
  if not player then return nil end
  if FW.name == 'qbox' then
    return player.PlayerData.citizenid
  else
    return player.PlayerData.citizenid
  end
end

function FW.GetName(player)
  if not player then return "Unknown" end
  local pd = player.PlayerData
  if pd and pd.charinfo then
    return (pd.charinfo.firstname or "") .. " " .. (pd.charinfo.lastname or "")
  end
  return pd and pd.name or "Unknown"
end

function FW.AddMoney(player, account, amount)
  if not player or not amount then return end
  if FW.name == 'qbox' then

    player.Functions.AddMoney(account, amount, "chopshop")
  else
    player.Functions.AddMoney(account, amount, "chopshop")
  end
end

function FW.RemoveMoney(player, account, amount)
  if not player or not amount then return false end
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return true end
  if player.Functions and player.Functions.RemoveMoney then
    return player.Functions.RemoveMoney(account, amount, "chopshop")
  end
  return false
end

function FW.GetMoney(player, account)
  if not player or not account then return 0 end
  local md = player.PlayerData and player.PlayerData.money
  if md and md[account] ~= nil then return tonumber(md[account]) or 0 end
  return 0
end

local function detectInventory()
  if Config.Inventory ~= "auto" then return Config.Inventory end
  if GetResourceState('ox_inventory') == 'started' then return 'ox' end
  if GetResourceState('ps-inventory') == 'started' then return 'ps' end
  return 'qb'
end

FW.inv = detectInventory()

function FW.AddItem(src, name, amount, metadata)
  amount = amount or 1
  metadata = metadata or {}

  if FW.inv == 'ox' then
    return exports.ox_inventory:AddItem(src, name, amount, metadata)
  elseif FW.inv == 'ps' then
    return exports['ps-inventory']:AddItem(src, name, amount, false, metadata)
  else
    local player = FW.GetPlayer(src)
    if not player then return false end
    return player.Functions.AddItem(name, amount, false, metadata)
  end
end

function FW.HasItem(src, name, amount)
  amount = amount or 1
  if FW.inv == 'ox' then
    local count = exports.ox_inventory:GetItemCount(src, name)
    return (count or 0) >= amount
  elseif FW.inv == 'ps' then
    return exports['ps-inventory']:HasItem(src, name, amount)
  else
    local player = FW.GetPlayer(src)
    if not player then return false end
    local item = player.Functions.GetItemByName(name)
    return item and (item.amount or 0) >= amount
  end
end

function FW.RegisterUsableItem(itemName, cb)
  if FW.name == 'qbox' then

    local ok = pcall(function()
      exports['qbx_core']:CreateUseableItem(itemName, cb)
    end)
    if ok then return end
  end

  FW.core.Functions.CreateUseableItem(itemName, cb)
end
GS = GS or {}
GS.Bridge = {}

local function hasRes(name)
  return GetResourceState(name) == 'started'
end

function GS.Bridge.getPlayer(src)
  if hasRes('qbx_core') and exports.qbx_core and exports.qbx_core.GetPlayer then
    return exports.qbx_core:GetPlayer(src)
  end
  return nil
end

function GS.Bridge.getJob(src)
  local ply = GS.Bridge.getPlayer(src)
  if ply and ply.PlayerData and ply.PlayerData.job then
    return ply.PlayerData.job.name, ply.PlayerData.job.grade and ply.PlayerData.job.grade.level or 0
  end
  return nil, 0
end

function GS.Bridge.notify(src, msg, nType)
  if src == 0 then
    print(('[gs-chopshop] %s'):format(msg))
    return
  end
  TriggerClientEvent('ox_lib:notify', src, { title = 'Chop Shop', description = msg, type = nType or 'inform' })
end

function GS.Bridge.hasItem(src, item, count)
  count = count or 1
  if hasRes('ox_inventory') and exports.ox_inventory then
    local c = exports.ox_inventory:Search(src, 'count', item)
    return (c or 0) >= count
  end
  if hasRes('qb-inventory') and exports['qb-inventory'] then

    local ply = GS.Bridge.getPlayer(src)
    if not ply then return false end
    local it = ply.Functions and ply.Functions.GetItemByName and ply.Functions.GetItemByName(item)
    return it and (it.amount or 0) >= count
  end
  return false
end

function GS.Bridge.addItem(src, item, count, metadata)
  count = count or 1
  if hasRes('ox_inventory') and exports.ox_inventory then
    return exports.ox_inventory:AddItem(src, item, count, metadata)
  end
  local ply = GS.Bridge.getPlayer(src)
  if ply and ply.Functions and ply.Functions.AddItem then
    return ply.Functions.AddItem(item, count, false, metadata)
  end
  return false
end

function GS.Bridge.removeItem(src, item, count)
  count = count or 1
  if hasRes('ox_inventory') and exports.ox_inventory then
    return exports.ox_inventory:RemoveItem(src, item, count)
  end
  local ply = GS.Bridge.getPlayer(src)
  if ply and ply.Functions and ply.Functions.RemoveItem then
    return ply.Functions.RemoveItem(item, count)
  end
  return false
end

function GS.Bridge.pdNotify(payload)
  if not Config.PDNotify.Enabled then return end

  if GetResourceState('qbx_dispatch') == 'started' then
    TriggerEvent('qbx_dispatch:server:notify', {
      jobs = Config.PDNotify.Jobs,
      title = payload.title,
      message = payload.message,
      coords = payload.coords,
      icon = 'car',
    })
    return
  end

  for _, id in ipairs(GetPlayers()) do
    local job = GS.Bridge.getJob(tonumber(id))
    if job then
      for _, pdJob in ipairs(Config.PDNotify.Jobs) do
        if job == pdJob then
          TriggerClientEvent('ox_lib:notify', tonumber(id), {
            title = payload.title,
            description = payload.message,
            type = 'warning'
          })
          break
        end
      end
    end
  end
end
