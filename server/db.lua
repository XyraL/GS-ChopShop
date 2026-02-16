DB = {}
DB.Ready = false

local warned = false
local function warnOnce(msg)
  if warned then return end
  warned = true
  print(('^1[gs-chopshop]^0 DB disabled: %s'):format(msg))
end

local function hasMySQLAwait()
  return type(MySQL) == 'table'
    and type(MySQL.query) == 'table'
    and type(MySQL.query.await) == 'function'
end

local function hasOxExports()
  return exports and exports.oxmysql
    and type(exports.oxmysql.execute) == 'function'
    and type(exports.oxmysql.query) == 'function'
end

local function await_cb(method, sql, params)
  local p = promise.new()
  local fn = exports.oxmysql[method]

  fn(exports.oxmysql, sql, params or {}, function(result)
    p:resolve(result)
  end)
  return Citizen.Await(p)
end

local function exec(sql, params)
  params = params or {}
  if hasMySQLAwait() then
    return MySQL.query.await(sql, params)
  end
  if hasOxExports() then
    return await_cb('execute', sql, params)
  end
  warnOnce('oxmysql not found')
  return nil
end

local function query(sql, params)
  params = params or {}
  if hasMySQLAwait() then
    return MySQL.query.await(sql, params)
  end
  if hasOxExports() then
    return await_cb('query', sql, params) or {}
  end
  warnOnce('oxmysql not found')
  return {}
end

local function scalar(sql, params)
  params = params or {}
  if type(MySQL) == 'table' and MySQL.scalar and type(MySQL.scalar.await) == 'function' then
    return MySQL.scalar.await(sql, params)
  end
  if hasOxExports() and type(exports.oxmysql.scalar) == 'function' then
    return await_cb('scalar', sql, params)
  end
  warnOnce('oxmysql not found')
  return nil
end

function DB.Init()
  if not hasMySQLAwait() and not hasOxExports() then
    warnOnce('oxmysql/MySQL wrapper not available at init (check dependency/start order)')
    DB.Ready = false
    return
  end
  exec([[
    CREATE TABLE IF NOT EXISTS `gs_chopshop_stats` (
      `citizenid` VARCHAR(64) NOT NULL,
      `name` VARCHAR(128) NOT NULL,
      `chops` INT NOT NULL DEFAULT 0,
      `earnings` INT NOT NULL DEFAULT 0,
      `rep` INT NOT NULL DEFAULT 0,
      PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  local repCol = query([[SHOW COLUMNS FROM `gs_chopshop_stats` LIKE 'rep';]])
  if not repCol or not repCol[1] then
    exec([[ALTER TABLE `gs_chopshop_stats` ADD COLUMN `rep` INT NOT NULL DEFAULT 0;]])
  end

  exec([[
  CREATE TABLE IF NOT EXISTS `gs_chopshop_tiers` (
    `citizenid` VARCHAR(64) NOT NULL,
    `tier1` INT NOT NULL DEFAULT 0,
    `tier2` INT NOT NULL DEFAULT 0,
    `tier3` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`citizenid`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]])

  exec([[
    CREATE TABLE IF NOT EXISTS `gs_chopshop_history` (
      `id` INT NOT NULL AUTO_INCREMENT,
      `citizenid` VARCHAR(64) NOT NULL,
      `tier` VARCHAR(16) NOT NULL,
      `model` VARCHAR(64) NOT NULL,
      `earned` INT NOT NULL DEFAULT 0,
      `success` TINYINT(1) NOT NULL DEFAULT 1,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`),
      KEY `cid_idx` (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  exec([[
    CREATE TABLE IF NOT EXISTS `gs_chopshop_upgrades` (
      `citizenid` VARCHAR(64) NOT NULL,
      `chop_speed` INT NOT NULL DEFAULT 0,
      `clean_payout` INT NOT NULL DEFAULT 0,
      `heat_dampener` INT NOT NULL DEFAULT 0,
      `scanner` INT NOT NULL DEFAULT 0,
      `auto_dispatch` INT NOT NULL DEFAULT 0,
      PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  local function ensureUpgCol(col, ddl)
    local c = query(([[SHOW COLUMNS FROM `gs_chopshop_upgrades` LIKE '%s';]]):format(col))
    if not c or not c[1] then
      exec(([[ALTER TABLE `gs_chopshop_upgrades` ADD COLUMN %s;]]):format(ddl))
    end
  end

  ensureUpgCol('tech_hand', '`tech_hand` INT NOT NULL DEFAULT 0')
  ensureUpgCol('runner_instinct', '`runner_instinct` INT NOT NULL DEFAULT 0')
  ensureUpgCol('broker_cut', '`broker_cut` INT NOT NULL DEFAULT 0')

  ensureUpgCol('shop_lift', '`shop_lift` INT NOT NULL DEFAULT 0')
  ensureUpgCol('shop_dampening', '`shop_dampening` INT NOT NULL DEFAULT 0')
  ensureUpgCol('shop_compactor', '`shop_compactor` INT NOT NULL DEFAULT 0')
  ensureUpgCol('shop_shredder', '`shop_shredder` INT NOT NULL DEFAULT 0')

  ensureUpgCol('net_fence', '`net_fence` INT NOT NULL DEFAULT 0')
  ensureUpgCol('net_forgery', '`net_forgery` INT NOT NULL DEFAULT 0')
  ensureUpgCol('net_parts', '`net_parts` INT NOT NULL DEFAULT 0')

  exec([[
    CREATE TABLE IF NOT EXISTS `gs_chopshop_profiles` (
      `citizenid` VARCHAR(64) NOT NULL,
      `alias` VARCHAR(32) NULL,
      `privacy` TINYINT(1) NOT NULL DEFAULT 1,
      PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  print("^2[gs-chopshop]^0 DB ready (tables ensured).")
  DB.Ready = true
end

function DB.GetProfile(cid)
  local rows = query([[SELECT alias, privacy FROM gs_chopshop_profiles WHERE citizenid = ? LIMIT 1;]], { cid })
  return rows and rows[1] or { alias = nil, privacy = 1 }
end

function DB.SetProfile(cid, alias, privacy)
  privacy = (tonumber(privacy) or 1)
  if privacy ~= 0 then privacy = 1 end
  if alias ~= nil then
    alias = tostring(alias)
    alias = alias:gsub('[^%w_%- ]', '')
    alias = alias:sub(1, 32)
    if alias == '' then alias = nil end
  end
  exec([[INSERT INTO gs_chopshop_profiles (citizenid, alias, privacy)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE alias = VALUES(alias), privacy = VALUES(privacy);]],
    { cid, alias, privacy })
end

function DB.PeekIds(limit)
  limit = limit or 10
  return query([[
    SELECT citizenid, tier1, tier2, tier3
    FROM gs_chopshop_tiers
    ORDER BY (tier1 + tier2 + tier3) DESC
    LIMIT ?;
  ]], { limit })
end

function DB.Scalar(sql, params)
  params = params or {}
  if MySQL and MySQL.scalar and MySQL.scalar.await then
    return MySQL.scalar.await(sql, params)
  end

  local p = promise.new()
  exports.oxmysql:scalar(sql, params, function(result)
    p:resolve(result)
  end)
  return Citizen.Await(p)
end

function DB.GetUpgrades(cid)
  local rows = query([[SELECT chop_speed, clean_payout, heat_dampener, scanner, auto_dispatch, tech_hand, runner_instinct, broker_cut, shop_lift, shop_dampening, shop_compactor, shop_shredder, net_fence, net_forgery, net_parts
    FROM gs_chopshop_upgrades WHERE citizenid = ? LIMIT 1;]], { cid })
  return rows and rows[1] or {
    chop_speed = 0,
    clean_payout = 0,
    heat_dampener = 0,
    scanner = 0,
    auto_dispatch = 0,

    tech_hand = 0,
    runner_instinct = 0,
    broker_cut = 0,

    shop_lift = 0,
    shop_dampening = 0,
    shop_compactor = 0,
    shop_shredder = 0,

    net_fence = 0,
    net_forgery = 0,
    net_parts = 0,
  }
end

function DB.SetUpgrade(cid, key, level)
  exec([[INSERT INTO gs_chopshop_upgrades (citizenid) VALUES (?)
    ON DUPLICATE KEY UPDATE citizenid=citizenid;]], { cid })
  exec(("UPDATE gs_chopshop_upgrades SET %s = ? WHERE citizenid = ?;"):format(key), { level, cid })
end

function DB.AddResult(cid, name, tier, model, earned, success, repGain)
  success = success and 1 or 0
  repGain = tonumber(repGain or 0) or 0
  exec([[
    INSERT INTO gs_chopshop_stats (citizenid, name, chops, earnings, rep)
    VALUES (?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      name = VALUES(name),
      chops = chops + ?,
      earnings = earnings + ?,
      rep = rep + ?;
  ]], { cid, name, success == 1 and 1 or 0, earned, repGain, success == 1 and 1 or 0, earned, repGain })

  exec([[
    INSERT INTO gs_chopshop_history (citizenid, tier, model, earned, success)
    VALUES (?, ?, ?, ?, ?);
  ]], { cid, tier, model, earned, success })
end

function DB.GetTop(limit)
  limit = limit or 10
  return query([[
    SELECT
      COALESCE(p.alias, CONCAT('Operator-', RIGHT(s.citizenid, 4))) AS display,
      s.citizenid, s.chops, s.earnings, s.rep
    FROM gs_chopshop_stats s
    LEFT JOIN gs_chopshop_profiles p ON p.citizenid = s.citizenid
    ORDER BY s.chops DESC, s.earnings DESC
    LIMIT ?;
  ]], { limit })
end

function DB.GetHistory(cid, limit)
  limit = limit or 10
  return query([[
    SELECT tier, model, earned, success, created_at
    FROM gs_chopshop_history
    WHERE citizenid = ?
    ORDER BY id DESC
    LIMIT ?;
  ]], { cid, limit })
end

function DB.AddTierProgress(cid, tierKey)
  local col = tierKey
  exec([[
    INSERT INTO gs_chopshop_tiers (citizenid, tier1, tier2, tier3)
    VALUES (?, 0, 0, 0)
    ON DUPLICATE KEY UPDATE citizenid=citizenid;
  ]], { cid })

  exec(("UPDATE gs_chopshop_tiers SET %s = %s + 1 WHERE citizenid = ?;"):format(col, col), { cid })
end

function DB.GetTierProgress(cid)
  local rows = query("SELECT tier1, tier2, tier3 FROM gs_chopshop_tiers WHERE citizenid = ? LIMIT 1;", { cid })
  return rows and rows[1] or { tier1 = 0, tier2 = 0, tier3 = 0 }
end
function DB.GetRep(cid)
  local r = scalar("SELECT rep FROM gs_chopshop_stats WHERE citizenid = ? LIMIT 1;", { cid })
  return tonumber(r) or 0
end

function DB.HasTierRow(cid)
  local c = scalar('SELECT COUNT(*) FROM gs_chopshop_tiers WHERE citizenid = ?;', { cid })
  return (tonumber(c) or 0) > 0
end

function DB.HasAnyRow(cid)

  if DB.HasTierRow(cid) then return true end
  local s = scalar('SELECT COUNT(*) FROM gs_chopshop_stats WHERE citizenid = ?;', { cid })
  if (tonumber(s) or 0) > 0 then return true end
  local u = scalar('SELECT COUNT(*) FROM gs_chopshop_upgrades WHERE citizenid = ?;', { cid })
  return (tonumber(u) or 0) > 0
end
