Util = {}

function Util.Debug(...)
  if Config.Debug then
    print("^3[gs-chopshop]^0", ...)
  end
end

function Util.RandInt(min, max)
  return math.random(min, max)
end

function Util.Pick(t)
  if type(t) ~= "table" or #t == 0 then return nil end
  return t[math.random(1, #t)]
end

function Util.Distance(a, b)
  local ax, ay, az = a.x or a[1], a.y or a[2], a.z or a[3]
  local bx, by, bz = b.x or b[1], b.y or b[2], b.z or b[3]
  local dx, dy, dz = ax - bx, ay - by, az - bz
  return math.sqrt(dx*dx + dy*dy + dz*dz)
end

function Util.MakePlate()
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local nums = "0123456789"
  local function rstr(set, n)
    local s = {}
    for i=1,n do
      local idx = math.random(1, #set)
      s[i] = set:sub(idx, idx)
    end
    return table.concat(s)
  end
  return (rstr(chars, 3) .. rstr(nums, 3)):upper()
end
