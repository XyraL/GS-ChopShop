DB = {}
DB.Ready = false

-- DB Compatibility Layer
-- Supports oxmysql via the global MySQL wrapper (preferred) or direct exports.oxmysql.
-- If neither exists, functions become no-ops and print a warning once.

local warned = false
local function warnOnce(msg)
  if warned then return end
  warned = true
  print(('^1[gs-chopshop]^0 DB disabled: %s'):format(msg))
end

-- Some servers expose MySQL.query.await as a function on a table.
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

-- Wrap oxmysql callbacks into awaitables (most reliable across versions).
local function await_cb(method, sql, params)
  local p = promise.new()
  local fn = exports.oxmysql[method]
  -- Call as a method (pass self) to avoid 'query is object' errors on some oxmysql builds.
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

-- Expose raw helpers for other scripts
DB.Exec = exec
DB.Query = query
DB.Scalar = scalar

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
  -- Backfill older installs: add rep column if missing
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
      PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  -- Ensure upgrade columns exist for every key in Config.Upgrades
  -- (safe migration; adds missing INT columns with default 0)
  local okCols, cols = pcall(function()
    return query([[SHOW COLUMNS FROM gs_chopshop_upgrades;]], {})
  end)
  local existing = {}
  if okCols and cols then
    for _, c in ipairs(cols) do existing[c.Field] = true end
  end

  for key, _ in pairs(Config.Upgrades or {}) do
    if key ~= 'priceAccount' and key ~= 'priceMult' then
      if not existing[key] then
        exec(("ALTER TABLE gs_chopshop_upgrades ADD COLUMN `%s` INT NOT NULL DEFAULT 0;"):format(key))
      end
    end
  end

  -- Operator profiles (alias + privacy). We show aliases in UI so seized tablets
  -- don't expose real character/player names.
  exec([[ 
    CREATE TABLE IF NOT EXISTS `gs_chopshop_profiles` (
      `citizenid` VARCHAR(64) NOT NULL,
      `alias` VARCHAR(32) NULL,
      `privacy` TINYINT(1) NOT NULL DEFAULT 1,
      PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  -- Backfill: add syndicate_name column for player-created syndicates (cosmetic + future hooks)
  local sc = query([[SHOW COLUMNS FROM `gs_chopshop_profiles` LIKE "syndicate_name";]])
  if not sc or not sc[1] then
    exec([[ALTER TABLE `gs_chopshop_profiles` ADD COLUMN `syndicate_name` VARCHAR(32) NULL;]])
  end


  
  exec([[
    CREATE TABLE IF NOT EXISTS `gs_chopshop_roles` (
      `citizenid` VARCHAR(64) NOT NULL,
      `role` VARCHAR(16) NULL,
      PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  -- Tool Mastery (individual progression)
  exec([[
    CREATE TABLE IF NOT EXISTS `gs_chopshop_tool_mastery` (
      `citizenid` VARCHAR(64) NOT NULL,
      `data` LONGTEXT NULL,
      `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  exec([[
    CREATE TABLE IF NOT EXISTS `gs_chopshop_syndicate` (
      `citizenid` VARCHAR(64) NOT NULL,
      `level` INT NOT NULL DEFAULT 0,
      `influence` INT NOT NULL DEFAULT 0,
      PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

	  -- Ensure shared syndicate tables exist (used by the Syndicate tab)
	  if DB.EnsureSyndicateSchema then
	    DB.EnsureSyndicateSchema()
	  end

  print("^2[gs-chopshop]^0 DB ready (tables ensured).")
  DB.Ready = true
end

--==============================
-- Tool Mastery (JSON)
--==============================

function DB.GetToolMastery(cid)
  local rows = query([[SELECT data FROM gs_chopshop_tool_mastery WHERE citizenid = ? LIMIT 1;]], { cid })
  if rows and rows[1] and rows[1].data and rows[1].data ~= '' then
    local ok, decoded = pcall(json.decode, rows[1].data)
    if ok and type(decoded) == 'table' then return decoded end
  end
  return nil
end

function DB.SetToolMastery(cid, masteryTable)
  local enc = nil
  if masteryTable ~= nil then
    local ok, j = pcall(json.encode, masteryTable)
    if ok then enc = j end
  end
  exec([[INSERT INTO gs_chopshop_tool_mastery (citizenid, data)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE data = VALUES(data);]], { cid, enc })
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
    alias = alias:gsub("[^%w_%- ]", "")
    alias = alias:sub(1, 32)
    if alias == "" then alias = nil end
  end
  exec([[INSERT INTO gs_chopshop_profiles (citizenid, alias, privacy)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE alias = VALUES(alias), privacy = VALUES(privacy);]],
    { cid, alias, privacy })
end

function DB.GetSyndicateName(cid)
  local rows = query([[SELECT syndicate_name FROM gs_chopshop_profiles WHERE citizenid = ? LIMIT 1;]], { cid })
  return rows and rows[1] and rows[1].syndicate_name or nil
end



-- New syndicate system (shared syndicates)
function DB.EnsureSyndicateSchema()
  -- Core syndicate tables
  exec([[CREATE TABLE IF NOT EXISTS gs_chopshop_syndicates (
        id INT NOT NULL AUTO_INCREMENT,
        name VARCHAR(32) NOT NULL,
        owner_cid VARCHAR(64) NOT NULL,
        level INT NOT NULL DEFAULT 0,
        influence INT NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uniq_name (name)
      );]], {})

  -- Migrations: prestige ladder for syndicates
  local colPrestige = query([[SHOW COLUMNS FROM `gs_chopshop_syndicates` LIKE "prestige";]], {})
  if not colPrestige or not colPrestige[1] then
    exec([[ALTER TABLE `gs_chopshop_syndicates` ADD COLUMN `prestige` INT NOT NULL DEFAULT 0;]], {})
  end

  local colPrestigePts = query([[SHOW COLUMNS FROM `gs_chopshop_syndicates` LIKE "prestige_points";]], {})
  if not colPrestigePts or not colPrestigePts[1] then
    exec([[ALTER TABLE `gs_chopshop_syndicates` ADD COLUMN `prestige_points` INT NOT NULL DEFAULT 0;]], {})
  end

  local colWinStreak = query([[SHOW COLUMNS FROM `gs_chopshop_syndicates` LIKE "bm_win_streak";]], {})
  if not colWinStreak or not colWinStreak[1] then
    exec([[ALTER TABLE `gs_chopshop_syndicates` ADD COLUMN `bm_win_streak` INT NOT NULL DEFAULT 0;]], {})
  end

  -- Black Market War: event state + leaderboard points
  exec([[CREATE TABLE IF NOT EXISTS `gs_chopshop_bm_event` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `theme` VARCHAR(64) NOT NULL,
        `started_at` INT NOT NULL,
        `ends_at` INT NOT NULL,
        `rotation_seconds` INT NOT NULL DEFAULT 1200,
        `meta` TEXT NULL,
        PRIMARY KEY (`id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], {})

  exec([[CREATE TABLE IF NOT EXISTS `gs_chopshop_bm_points` (
        `event_id` INT NOT NULL,
        `syndicate_id` INT NOT NULL,
        `points` INT NOT NULL DEFAULT 0,
        `perfect_runs` INT NOT NULL DEFAULT 0,
        `elite_completed` INT NOT NULL DEFAULT 0,
        `dynasty_completed` INT NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`event_id`, `syndicate_id`),
        KEY `idx_event_points` (`event_id`, `points`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], {})

  -- Members, vault, perks...
exec([[CREATE TABLE IF NOT EXISTS gs_chopshop_syndicate_members (
        syndicate_id INT NOT NULL,
        citizenid VARCHAR(64) NOT NULL,
        rank INT NOT NULL DEFAULT 1,
        joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (syndicate_id, citizenid),
        KEY idx_cid (citizenid)
      );]], {})

  exec([[CREATE TABLE IF NOT EXISTS gs_chopshop_syndicate_vault (
        syndicate_id INT NOT NULL,
        balance INT NOT NULL DEFAULT 0,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (syndicate_id)
      );]], {})

  exec([[CREATE TABLE IF NOT EXISTS gs_chopshop_syndicate_vault_tx (
        id INT NOT NULL AUTO_INCREMENT,
        syndicate_id INT NOT NULL,
        citizenid VARCHAR(64) NOT NULL,
        amount INT NOT NULL,
        kind VARCHAR(16) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_syn (syndicate_id)
      );]], {})

  exec([[CREATE TABLE IF NOT EXISTS gs_chopshop_syndicate_perks (
        syndicate_id INT NOT NULL,
        perk VARCHAR(32) NOT NULL,
        level INT NOT NULL DEFAULT 0,
        PRIMARY KEY (syndicate_id, perk)
      );]], {})

  -- Migrations: add optional fields to vault transactions
  local colReason = query([[SHOW COLUMNS FROM `gs_chopshop_syndicate_vault_tx` LIKE "reason";]], {})
  if not colReason or not colReason[1] then
    exec([[ALTER TABLE `gs_chopshop_syndicate_vault_tx` ADD COLUMN `reason` VARCHAR(64) NULL;]], {})
  end
  local colMeta = query([[SHOW COLUMNS FROM `gs_chopshop_syndicate_vault_tx` LIKE "meta";]], {})
  if not colMeta or not colMeta[1] then
    exec([[ALTER TABLE `gs_chopshop_syndicate_vault_tx` ADD COLUMN `meta` TEXT NULL;]], {})
  end

  -- Syndicate settings (routing + branding)
  exec([[CREATE TABLE IF NOT EXISTS `gs_chopshop_syndicate_settings` (
        `syndicate_id` INT NOT NULL,
        `routing_enabled` TINYINT(1) NOT NULL DEFAULT 0,
        `routing_percent` FLOAT NOT NULL DEFAULT 0.15,
        `branding` TEXT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`syndicate_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], {})

  -- Syndicate aggregate stats
  exec([[CREATE TABLE IF NOT EXISTS `gs_chopshop_syndicate_stats` (
        `syndicate_id` INT NOT NULL,
        `contracts_completed` INT NOT NULL DEFAULT 0,
        `earnings_total` BIGINT NOT NULL DEFAULT 0,
        `influence_total` INT NOT NULL DEFAULT 0,
        `best_payout` INT NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`syndicate_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], {})

  -- Syndicate operations (one active op at a time, simple + readable)
  exec([[CREATE TABLE IF NOT EXISTS `gs_chopshop_syndicate_ops` (
        `syndicate_id` INT NOT NULL,
        `op_id` VARCHAR(32) NULL,
        `active_until` INT NOT NULL DEFAULT 0,
        `cooldown_until` INT NOT NULL DEFAULT 0,
        `meta` TEXT NULL,
        PRIMARY KEY (`syndicate_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], {})

end

function DB.GetPlayerSyndicate(cid)
  local rows = query([[SELECT s.id, s.name, s.owner_cid, s.level, s.influence, s.prestige, s.prestige_points, s.bm_win_streak, m.rank
                       FROM gs_chopshop_syndicate_members m
                       JOIN gs_chopshop_syndicates s ON s.id = m.syndicate_id
                       WHERE m.citizenid = ? LIMIT 1;]], { cid })
  local r = rows and rows[1] or nil
  if not r then return nil end
  return {
    id = tonumber(r.id) or 0,
    name = r.name,
    owner = r.owner_cid,
    level = tonumber(r.level or 0) or 0,
    influence = tonumber(r.influence or 0) or 0,
    prestige = tonumber(r.prestige or 0) or 0,
    prestigePoints = tonumber(r.prestige_points or 0) or 0,
    bmWinStreak = tonumber(r.bm_win_streak or 0) or 0,
    rank = tonumber(r.rank or 1) or 1,
  }
end

function DB.GetSyndicateMembers(syndId)
  -- Join QB/QBX players table to resolve character display names.
  local rows = query([[SELECT m.citizenid, m.rank, p.charinfo
                       FROM gs_chopshop_syndicate_members m
                       LEFT JOIN players p ON p.citizenid = m.citizenid
                       WHERE m.syndicate_id = ?
                       ORDER BY m.rank DESC, m.citizenid ASC;]], { syndId })
  local out = {}
  for i=1, #(rows or {}) do
    local r = rows[i]
    local display = r.citizenid
    if r.charinfo and type(r.charinfo) == 'string' and r.charinfo ~= '' then
      local ok, info = pcall(json.decode, r.charinfo)
      if ok and type(info) == 'table' then
        local fn = tostring(info.firstname or '')
        local ln = tostring(info.lastname or '')
        local full = (fn .. ' ' .. ln):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
        if full ~= '' then display = full end
      end
    end
    out[#out+1] = {
      citizenid = r.citizenid,
      rank = tonumber(r.rank or 1) or 1,
      displayName = display,
    }
  end
  return out
end

function DB.SetMemberRank(syndId, cid, rank)
  rank = tonumber(rank or 1) or 1
  exec([[UPDATE gs_chopshop_syndicate_members SET rank = ? WHERE syndicate_id = ? AND citizenid = ?;]], { rank, syndId, cid })
end

function DB.CreateSyndicate(ownerCid, name)
  name = tostring(name or '')
  name = name:gsub("[^%w_%- ]", "")
  name = name:sub(1, 32)
  if name == '' then return nil, 'invalid' end

  exec([[INSERT INTO gs_chopshop_syndicates (name, owner_cid, level, influence)
        VALUES (?, ?, 0, 0);]], { name, ownerCid })

  local id = DB.Scalar([[SELECT id FROM gs_chopshop_syndicates WHERE name = ? LIMIT 1;]], { name })
  id = tonumber(id or 0) or 0
  if id <= 0 then return nil, 'create_failed' end

  exec([[INSERT INTO gs_chopshop_syndicate_members (syndicate_id, citizenid, rank)
        VALUES (?, ?, 3)
        ON DUPLICATE KEY UPDATE rank = VALUES(rank);]], { id, ownerCid })
  return id
end

function DB.AddMember(syndId, cid, rank)
  rank = tonumber(rank or 1) or 1
  exec([[INSERT INTO gs_chopshop_syndicate_members (syndicate_id, citizenid, rank)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE rank = VALUES(rank);]], { syndId, cid, rank })
end

function DB.RemoveMember(syndId, cid)
  exec([[DELETE FROM gs_chopshop_syndicate_members WHERE syndicate_id = ? AND citizenid = ?;]], { syndId, cid })
end

function DB.DeleteSyndicate(syndId)
  exec([[DELETE FROM gs_chopshop_syndicate_members WHERE syndicate_id = ?;]], { syndId })
  exec([[DELETE FROM gs_chopshop_syndicates WHERE id = ?;]], { syndId })
end

function DB.EnsureVaultRow(syndId)
  exec([[INSERT IGNORE INTO gs_chopshop_syndicate_vault (syndicate_id, balance) VALUES (?, 0);]], { syndId })
end

function DB.GetVault(syndId)
  DB.EnsureVaultRow(syndId)
  local bal = DB.Scalar([[SELECT balance FROM gs_chopshop_syndicate_vault WHERE syndicate_id = ? LIMIT 1;]], { syndId })
  return tonumber(bal or 0) or 0
end

function DB.AddVaultTx(syndId, cid, amount, kind, reason, meta)
  amount = math.floor(tonumber(amount or 0) or 0)
  if amount == 0 then return end
  kind = tostring(kind or 'deposit')
  reason = reason ~= nil and tostring(reason) or nil
  if reason ~= nil then reason = reason:sub(1, 64) end
  if meta ~= nil and type(meta) ~= 'string' then
    local ok, enc = pcall(json.encode, meta)
    meta = ok and enc or nil
  end
  exec([[INSERT INTO gs_chopshop_syndicate_vault_tx (syndicate_id, citizenid, amount, kind, reason, meta) VALUES (?, ?, ?, ?, ?, ?);]],
    { syndId, cid, amount, kind, reason, meta })
end

function DB.GetVaultTx(syndId, limit)
  limit = math.floor(tonumber(limit or 10) or 10)
  if limit < 1 then limit = 1 end
  if limit > 25 then limit = 25 end
  return query([[SELECT citizenid, amount, kind, reason, created_at FROM gs_chopshop_syndicate_vault_tx
                 WHERE syndicate_id = ?
                 ORDER BY id DESC
                 LIMIT ]] .. limit .. ';', { syndId })
end

function DB.DepositToVault(syndId, cid, amount)
  amount = math.floor(tonumber(amount or 0) or 0)
  if amount <= 0 then return false, 'invalid' end
  DB.EnsureVaultRow(syndId)
  exec([[UPDATE gs_chopshop_syndicate_vault SET balance = balance + ? WHERE syndicate_id = ?;]], { amount, syndId })
  DB.AddVaultTx(syndId, cid, amount, 'deposit', nil, nil)
  return true
end


function DB.WithdrawFromVault(syndId, cid, amount)
  amount = math.floor(tonumber(amount or 0) or 0)
  if amount <= 0 then return false, 'invalid' end

  DB.EnsureVaultRow(syndId)
  local bal = DB.GetVault(syndId)
  if bal < amount then return false, 'insufficient' end
  exec([[UPDATE gs_chopshop_syndicate_vault SET balance = balance - ? WHERE syndicate_id = ?;]], { amount, syndId })
  DB.AddVaultTx(syndId, cid, amount, 'withdraw', nil, nil)
  return true
end

function DB.GetSyndicatePerks(syndId)
  local rows = query([[SELECT perk, level FROM gs_chopshop_syndicate_perks WHERE syndicate_id = ?;]], { syndId })
  local out = {}
  for i=1, #(rows or {}) do
    local r = rows[i]
    out[tostring(r.perk)] = tonumber(r.level or 0) or 0
  end
  return out
end

function DB.SetSyndicatePerk(syndId, perk, level)
  perk = tostring(perk or '')
  level = math.floor(tonumber(level or 0) or 0)
  if perk == '' then return end
  exec([[INSERT INTO gs_chopshop_syndicate_perks (syndicate_id, perk, level)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE level = VALUES(level);]], { syndId, perk, level })
end

function DB.AddSyndicateInfluence(syndId, amount)
  amount = math.floor(tonumber(amount or 0) or 0)
  if amount == 0 then return end
  exec([[UPDATE gs_chopshop_syndicates SET influence = influence + ? WHERE id = ?;]], { amount, syndId })
end

function DB.SetSyndicateStats(syndId, level, influence)
  level = math.floor(tonumber(level or 0) or 0)
  influence = math.floor(tonumber(influence or 0) or 0)
  exec([[UPDATE gs_chopshop_syndicates SET level = ?, influence = ? WHERE id = ?;]], { level, influence, syndId })
end
function DB.SetSyndicateName(cid, name)
  if name ~= nil then
    name = tostring(name)
    name = name:gsub("[^%w_%- ]", "")
    name = name:sub(1, 32)
    if name == "" then name = nil end
  end
  exec([[INSERT INTO gs_chopshop_profiles (citizenid, alias, privacy, syndicate_name)
        VALUES (?, NULL, 1, ?)
        ON DUPLICATE KEY UPDATE syndicate_name = VALUES(syndicate_name);]], { cid, name })
end

function DB.GetRole(cid)
  local rows = query([[SELECT role FROM gs_chopshop_roles WHERE citizenid = ? LIMIT 1;]], { cid })
  return rows and rows[1] and rows[1].role or nil
end

function DB.SetRole(cid, role)
  exec([[INSERT INTO gs_chopshop_roles (citizenid, role)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE role = VALUES(role);]], { cid, role })
end

function DB.GetSyndicate(cid)
  local rows = query([[SELECT level, influence FROM gs_chopshop_syndicate WHERE citizenid = ? LIMIT 1;]], { cid })
  local r = rows and rows[1] or nil
  return {
    level = tonumber(r and r.level or 0) or 0,
    influence = tonumber(r and r.influence or 0) or 0,
  }
end

function DB.AddInfluence(cid, amount)
  amount = math.floor(tonumber(amount or 0) or 0)
  if amount == 0 then return end
  exec([[INSERT INTO gs_chopshop_syndicate (citizenid, level, influence)
        VALUES (?, 0, 0)
        ON DUPLICATE KEY UPDATE citizenid=citizenid;]], { cid })
  exec([[UPDATE gs_chopshop_syndicate SET influence = influence + ? WHERE citizenid = ?;]], { amount, cid })
end

function DB.SetSyndicate(cid, level, influence)
  level = math.floor(tonumber(level or 0) or 0)
  influence = math.floor(tonumber(influence or 0) or 0)
  exec([[INSERT INTO gs_chopshop_syndicate (citizenid, level, influence)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE level = VALUES(level), influence = VALUES(influence);]], { cid, level, influence })
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
  -- Build a dynamic SELECT so new upgrades work without a hard-coded list.
  local keys = {}
  for k, _ in pairs(Config.Upgrades or {}) do
    if k ~= 'priceAccount' and k ~= 'priceMult' then
      keys[#keys+1] = k
    end
  end
  table.sort(keys)

  if #keys == 0 then return {} end

  local sel = table.concat(keys, ', ')
  local rows = query(('SELECT %s FROM gs_chopshop_upgrades WHERE citizenid = ? LIMIT 1;'):format(sel), { cid })
  local out = rows and rows[1] or {}
  -- normalize missing keys
  for _, k in ipairs(keys) do
    out[k] = tonumber(out[k] or 0) or 0
  end
  return out
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

-- Top Groups (Syndicates)
-- Used for leaderboard to show "Top Operators" + "Top Groups".
-- Sort: prestige points (desc) -> prestige (desc) -> earnings (desc)
function DB.GetTopSyndicates(limit)
  limit = limit or 10
  return query([[
    SELECT
      s.id,
      s.name,
      s.level,
      s.prestige,
      s.prestige_points,
      COALESCE(st.contracts_completed, 0) AS contracts_completed,
      COALESCE(st.earnings_total, 0) AS earnings_total
    FROM gs_chopshop_syndicates s
    LEFT JOIN gs_chopshop_syndicate_stats st ON st.syndicate_id = s.id
    ORDER BY s.prestige_points DESC, s.prestige DESC, st.earnings_total DESC
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


-- Helpers for identifier resolution/debugging
function DB.HasTierRow(cid)
  local c = scalar('SELECT COUNT(*) FROM gs_chopshop_tiers WHERE citizenid = ?;', { cid })
  return (tonumber(c) or 0) > 0
end

function DB.HasAnyRow(cid)
  -- Check tiers first (fast). If not present, check stats/upgrades.
  if DB.HasTierRow(cid) then return true end
  local s = scalar('SELECT COUNT(*) FROM gs_chopshop_stats WHERE citizenid = ?;', { cid })
  if (tonumber(s) or 0) > 0 then return true end
  local u = scalar('SELECT COUNT(*) FROM gs_chopshop_upgrades WHERE citizenid = ?;', { cid })
  return (tonumber(u) or 0) > 0
end


--==============================
-- Syndicate Settings / Stats / Ops
--==============================
function DB.GetSyndicateSettings(syndId)
  local rows = query([[SELECT routing_enabled, routing_percent, branding FROM gs_chopshop_syndicate_settings WHERE syndicate_id = ? LIMIT 1;]], { syndId })
  local r = rows and rows[1] or nil
  local branding = nil
  if r and r.branding and r.branding ~= '' then
    local ok, obj = pcall(json.decode, r.branding)
    branding = (ok and obj) or nil
  end
  return {
    routingEnabled = r and (tonumber(r.routing_enabled or 0) or 0) == 1 or false,
    routingPercent = tonumber(r and r.routing_percent or 0.15) or 0.15,
    branding = branding or {},
  }
end

function DB.SetSyndicateSettings(syndId, opts)
  opts = opts or {}
  local re = opts.routingEnabled and 1 or 0
  local rp = tonumber(opts.routingPercent or 0.15) or 0.15
  local branding = opts.branding
  if branding ~= nil and type(branding) ~= 'string' then
    local ok, enc = pcall(json.encode, branding)
    branding = ok and enc or nil
  end
  exec([[INSERT INTO gs_chopshop_syndicate_settings (syndicate_id, routing_enabled, routing_percent, branding)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE routing_enabled = VALUES(routing_enabled), routing_percent = VALUES(routing_percent), branding = VALUES(branding);]],
    { syndId, re, rp, branding })
end

function DB.GetSyndicateStatsAgg(syndId)
  local rows = query([[SELECT contracts_completed, earnings_total, influence_total, best_payout FROM gs_chopshop_syndicate_stats WHERE syndicate_id = ? LIMIT 1;]], { syndId })
  local r = rows and rows[1] or nil
  return {
    contractsCompleted = tonumber(r and r.contracts_completed or 0) or 0,
    earningsTotal = tonumber(r and r.earnings_total or 0) or 0,
    influenceTotal = tonumber(r and r.influence_total or 0) or 0,
    bestPayout = tonumber(r and r.best_payout or 0) or 0,
  }
end

function DB.AddSyndicateStatsAgg(syndId, delta)
  delta = delta or {}
  local dc = math.floor(tonumber(delta.contractsCompleted or 0) or 0)
  local de = math.floor(tonumber(delta.earningsTotal or 0) or 0)
  local di = math.floor(tonumber(delta.influenceTotal or 0) or 0)
  local best = math.floor(tonumber(delta.bestPayout or 0) or 0)

  exec([[INSERT INTO gs_chopshop_syndicate_stats (syndicate_id, contracts_completed, earnings_total, influence_total, best_payout)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
          contracts_completed = contracts_completed + VALUES(contracts_completed),
          earnings_total = earnings_total + VALUES(earnings_total),
          influence_total = influence_total + VALUES(influence_total),
          best_payout = GREATEST(best_payout, VALUES(best_payout));]],
    { syndId, dc, de, di, best })
end

function DB.GetSyndicateOp(syndId)
  local rows = query([[SELECT op_id, active_until, cooldown_until, meta FROM gs_chopshop_syndicate_ops WHERE syndicate_id = ? LIMIT 1;]], { syndId })
  local r = rows and rows[1] or nil
  local meta = nil
  if r and r.meta and r.meta ~= '' then
    local ok, obj = pcall(json.decode, r.meta)
    meta = (ok and obj) or nil
  end
  return {
    opId = r and r.op_id or nil,
    activeUntil = tonumber(r and r.active_until or 0) or 0,
    cooldownUntil = tonumber(r and r.cooldown_until or 0) or 0,
    meta = meta or {},
  }
end

function DB.SetSyndicateOp(syndId, opId, activeUntil, cooldownUntil, meta)
  opId = opId ~= nil and tostring(opId) or nil
  activeUntil = math.floor(tonumber(activeUntil or 0) or 0)
  cooldownUntil = math.floor(tonumber(cooldownUntil or 0) or 0)
  if meta ~= nil and type(meta) ~= 'string' then
    local ok, enc = pcall(json.encode, meta)
    meta = ok and enc or nil
  end
  exec([[INSERT INTO gs_chopshop_syndicate_ops (syndicate_id, op_id, active_until, cooldown_until, meta)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE op_id=VALUES(op_id), active_until=VALUES(active_until), cooldown_until=VALUES(cooldown_until), meta=VALUES(meta);]],
    { syndId, opId, activeUntil, cooldownUntil, meta })
end


--==============================
-- Black Market War DB helpers
--==============================
function DB.GetActiveBMEvent()
  local rows = query([[SELECT id, theme, started_at, ends_at, rotation_seconds, meta FROM gs_chopshop_bm_event ORDER BY id DESC LIMIT 1;]], {})
  local r = rows and rows[1] or nil
  if not r then return nil end
  local meta = {}
  if r.meta and r.meta ~= '' then
    local ok, obj = pcall(json.decode, r.meta)
    if ok and type(obj) == 'table' then meta = obj end
  end
  return {
    id = tonumber(r.id) or 0,
    theme = r.theme,
    startedAt = tonumber(r.started_at) or 0,
    endsAt = tonumber(r.ends_at) or 0,
    rotationSeconds = tonumber(r.rotation_seconds) or 1200,
    meta = meta,
  }
end

function DB.CreateBMEvent(theme, startedAt, endsAt, rotationSeconds, meta)
  theme = tostring(theme or 'BLACK MARKET')
  startedAt = math.floor(tonumber(startedAt or 0) or 0)
  endsAt = math.floor(tonumber(endsAt or 0) or 0)
  rotationSeconds = math.floor(tonumber(rotationSeconds or 1200) or 1200)
  if meta ~= nil and type(meta) ~= 'string' then
    local ok, enc = pcall(json.encode, meta)
    meta = ok and enc or nil
  end
  exec([[INSERT INTO gs_chopshop_bm_event (theme, started_at, ends_at, rotation_seconds, meta) VALUES (?, ?, ?, ?, ?);]],
    { theme, startedAt, endsAt, rotationSeconds, meta })
  local id = scalar([[SELECT id FROM gs_chopshop_bm_event ORDER BY id DESC LIMIT 1;]], {})
  return tonumber(id or 0) or 0
end

function DB.AddBMPoints(eventId, syndId, delta)
  delta = delta or {}
  local pts = math.floor(tonumber(delta.points or 0) or 0)
  local pr  = math.floor(tonumber(delta.perfectRuns or 0) or 0)
  local ec  = math.floor(tonumber(delta.eliteCompleted or 0) or 0)
  local dc  = math.floor(tonumber(delta.dynastyCompleted or 0) or 0)
  exec([[INSERT INTO gs_chopshop_bm_points (event_id, syndicate_id, points, perfect_runs, elite_completed, dynasty_completed)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
          points = points + VALUES(points),
          perfect_runs = perfect_runs + VALUES(perfect_runs),
          elite_completed = elite_completed + VALUES(elite_completed),
          dynasty_completed = dynasty_completed + VALUES(dynasty_completed);]],
    { eventId, syndId, pts, pr, ec, dc })
end


function DB.AddBMPointsBatch(eventId, deltas)
  -- deltas: array of { syndicate_id / syndId, points, perfectRuns, eliteCompleted, dynastyCompleted }
  if type(deltas) ~= 'table' or #deltas == 0 then return end

  local parts = {}
  local params = {}

  for i=1,#deltas do
    local d = deltas[i] or {}
    local sid = math.floor(tonumber(d.syndicate_id or d.syndId or 0) or 0)
    if sid > 0 then
      local pts = math.floor(tonumber(d.points or 0) or 0)
      local pr  = math.floor(tonumber(d.perfectRuns or d.perfect_runs or 0) or 0)
      local ec  = math.floor(tonumber(d.eliteCompleted or d.elite_completed or 0) or 0)
      local dc  = math.floor(tonumber(d.dynastyCompleted or d.dynasty_completed or 0) or 0)

      parts[#parts+1] = '(?, ?, ?, ?, ?, ?)' 
      params[#params+1] = eventId
      params[#params+1] = sid
      params[#params+1] = pts
      params[#params+1] = pr
      params[#params+1] = ec
      params[#params+1] = dc
    end
  end

  if #parts == 0 then return end

  exec('INSERT INTO gs_chopshop_bm_points (event_id, syndicate_id, points, perfect_runs, elite_completed, dynasty_completed) VALUES ' .. table.concat(parts, ',') ..
       ' ON DUPLICATE KEY UPDATE points = points + VALUES(points), perfect_runs = perfect_runs + VALUES(perfect_runs), elite_completed = elite_completed + VALUES(elite_completed), dynasty_completed = dynasty_completed + VALUES(dynasty_completed);',
       params)
end

function DB.GetBMLeaderboard(eventId, limit)
  limit = math.floor(tonumber(limit or 10) or 10)
  if limit < 1 then limit = 1 end
  if limit > 25 then limit = 25 end
  return query([[SELECT p.syndicate_id, s.name, p.points, p.perfect_runs, p.elite_completed, p.dynasty_completed
                 FROM gs_chopshop_bm_points p
                 JOIN gs_chopshop_syndicates s ON s.id = p.syndicate_id
                 WHERE p.event_id = ?
                 ORDER BY p.points DESC, p.elite_completed DESC, p.perfect_runs DESC
                 LIMIT ]]..limit..';', { eventId })
end



function DB.GetSyndicateById(syndId)
  local rows = query([[SELECT id, name, owner_cid, level, influence, prestige FROM gs_chopshop_syndicates WHERE id = ? LIMIT 1;]], { syndId })
  local r = rows and rows[1] or nil
  if not r then return nil end
  return {
    id = tonumber(r.id) or 0,
    name = r.name,
    ownerCid = r.owner_cid,
    level = tonumber(r.level or 0) or 0,
    influence = tonumber(r.influence or 0) or 0,
    prestige = tonumber(r.prestige or 0) or 0,
  }
end
--==============================
-- Syndicate prestige helpers
--==============================
function DB.GetSyndicatePrestige(syndId)
  local rows = query([[SELECT prestige, prestige_points, bm_win_streak FROM gs_chopshop_syndicates WHERE id = ? LIMIT 1;]], { syndId })
  local r = rows and rows[1] or nil
  return {
    prestige = tonumber(r and r.prestige or 0) or 0,
    points = tonumber(r and r.prestige_points or 0) or 0,
    winStreak = tonumber(r and r.bm_win_streak or 0) or 0,
  }
end

function DB.AddSyndicatePrestigePoints(syndId, amount)
  amount = math.floor(tonumber(amount or 0) or 0)
  if amount == 0 then return end
  exec([[UPDATE gs_chopshop_syndicates SET prestige_points = prestige_points + ? WHERE id = ?;]], { amount, syndId })
end


function DB.AddSyndicatePrestigePointsBatch(deltas)
  -- deltas: array of { syndicate_id / syndId, amount }
  if type(deltas) ~= 'table' or #deltas == 0 then return end

  local parts = {}
  local params = {}

  for i=1,#deltas do
    local d = deltas[i] or {}
    local sid = math.floor(tonumber(d.syndicate_id or d.syndId or 0) or 0)
    local amt = math.floor(tonumber(d.amount or 0) or 0)
    if sid > 0 and amt ~= 0 then
      parts[#parts+1] = '(?, ?)' 
      params[#params+1] = amt
      params[#params+1] = sid
    end
  end

  if #parts == 0 then return end

  -- Use a temp derived table to update multiple rows.
  local sql = 'UPDATE gs_chopshop_syndicates s JOIN (SELECT ? AS amt, ? AS id' 
  for i=2,#parts do
    sql = sql .. ' UNION ALL SELECT ?, ?'
  end
  sql = sql .. ') x ON x.id = s.id SET s.prestige_points = s.prestige_points + x.amt;'

  exec(sql, params)
end

function DB.SetSyndicatePrestige(syndId, prestige, points)
  prestige = math.floor(tonumber(prestige or 0) or 0)
  points = math.floor(tonumber(points or 0) or 0)
  exec([[UPDATE gs_chopshop_syndicates SET prestige = ?, prestige_points = ? WHERE id = ?;]], { prestige, points, syndId })
end

function DB.SetSyndicateWinStreak(syndId, streak)
  streak = math.floor(tonumber(streak or 0) or 0)
  exec([[UPDATE gs_chopshop_syndicates SET bm_win_streak = ? WHERE id = ?;]], { streak, syndId })
end


function DB.PrestigeResetSyndicate(syndId, newLevel, keepPct)
  -- Resets group progression for a new prestige cycle.
  -- keepPct is 0.0-1.0 of vault funds retained.
  syndId = math.floor(tonumber(syndId or 0) or 0)
  if syndId <= 0 then return end

  newLevel = math.floor(tonumber(newLevel or 1) or 1)
  if newLevel < 0 then newLevel = 0 end

  keepPct = tonumber(keepPct or 0.25) or 0.25
  if keepPct < 0.0 then keepPct = 0.0 end
  if keepPct > 1.0 then keepPct = 1.0 end

  -- Reset level/influence
  exec([[UPDATE gs_chopshop_syndicates SET level = ?, influence = 0 WHERE id = ?;]], { newLevel, syndId })

  -- Reset perk tree
  exec([[DELETE FROM gs_chopshop_syndicate_perks WHERE syndicate_id = ?;]], { syndId })

  -- Adjust vault balance
  DB.EnsureVaultRow(syndId)
  local bal = DB.GetVault(syndId) or 0
  local kept = math.floor((tonumber(bal) or 0) * keepPct)
  if kept < 0 then kept = 0 end
  if kept ~= bal then
    exec([[UPDATE gs_chopshop_syndicate_vault SET balance = ? WHERE syndicate_id = ?;]], { kept, syndId })
    -- ledger entry (use kind=prestige)
    local removed = bal - kept
    if removed > 0 then
      DB.AddVaultTx(syndId, 'SYSTEM', removed, 'prestige', nil, nil)
    end
  end
end

