Alerts = {
  last = {}, -- src -> os.time()
}

local function canAlert(src)
  local last = Alerts.last[src] or 0
  return (os.time() - last) >= (Config.PDAlert.cooldownSeconds or 60)
end

-- Returns true if an alert was actually fired (useful for bonus objectives)
function Alerts.Try(src, tierKey, coords, plate, model, chanceMult)
  if not Config.PDAlert.enabled then return false end
  if not canAlert(src) then return false end

  local chance = Config.PDAlert.chance[tierKey] or 0
  chanceMult = tonumber(chanceMult or 1.0) or 1.0
  chance = math.floor(chance * chanceMult)
  if chance < 0 then chance = 0 end
  local roll = math.random(1, 100)
  if roll > chance then return false end

  Alerts.last[src] = os.time()

  -- Dispatch stub (swap to ps-dispatch/qb-dispatch later)
  TriggerEvent('gs-chopshop:pdAlert', {
    coords = coords,
    plate = plate,
    model = model,
    tier = tierKey,
    message = ("Possible vehicle chop in progress (%s) Plate: %s"):format(model, plate)
  })

  return true
end

-- Default handler (prints). Replace with your dispatch integration.
AddEventHandler('gs-chopshop:pdAlert', function(data)
  print(("^1[gs-chopshop]^0 PD ALERT: %s @ (%.2f, %.2f, %.2f)"):format(
    data.message,
    data.coords.x, data.coords.y, data.coords.z
  ))
end)
