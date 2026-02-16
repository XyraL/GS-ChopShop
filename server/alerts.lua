Alerts = {
  last = {}, -- src -> os.time()
}

local function canAlert(src)
  local last = Alerts.last[src] or 0
  return (os.time() - last) >= (Config.PDAlert.cooldownSeconds or 60)
end

function Alerts.Try(src, tierKey, coords, plate, model, chanceMult)
  if not Config.PDAlert.enabled then return end
  if not canAlert(src) then return end

  local chance = Config.PDAlert.chance[tierKey] or 0
  chanceMult = tonumber(chanceMult or 1.0) or 1.0
  chance = math.floor(chance * chanceMult)
  if chance < 0 then chance = 0 end
  local roll = math.random(1, 100)
  if roll > chance then return end

  Alerts.last[src] = os.time()

  -- Dispatch stub (ps-dispatch/qb-dispatch)
  TriggerEvent('gs-chopshop:pdAlert', {
    coords = coords,
    plate = plate,
    model = model,
    tier = tierKey,
    message = ("Possible vehicle chop in progress (%s) Plate: %s"):format(model, plate)
  })
end

-- Default handler (prints). Replace with your dispatch integration.
AddEventHandler('gs-chopshop:pdAlert', function(data)
  print(("^1[gs-chopshop]^0 PD ALERT: %s @ (%.2f, %.2f, %.2f)"):format(
    data.message,
    data.coords.x, data.coords.y, data.coords.z
  ))
end)
