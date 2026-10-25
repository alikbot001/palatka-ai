-- Trade logging, profit tracking, stall drops, crate sources.
DSP.logs = DSP.logs or {}
DSP.logs.installed = false
DSP.logs.trade_logs = {}
DSP.logs.stall_logs = {}
DSP.logs.crate_logs = {}

local ok_lfs, lfs = pcall(require, 'lfs')

DSP.db = DSP.db or {}

DSP.settings.trades = DSP.settings.trades or {}
DSP.settings.stalls = DSP.settings.stalls or {}
DSP.settings.crates = DSP.settings.crates or {}
DSP.settings.stats_tab = DSP.settings.stats_tab or 'day'

local LOG_DIR = DSP.dir .. '/logs'

-- v1.2 fix: moved `name_ench` declaration ABOVE `parse_chat_drop`.
-- In v1.1 this was a latent bug: parse_chat_drop referenced `name_ench` as a
-- local, but `local function name_ench` was declared later in the file, so
-- Lua's lexical scoping meant parse_chat_drop saw `name_ench` as a global
-- (which is nil since the local never escapes to _G). The first call would
-- crash with "attempt to call a nil value". Declaring it here first ensures
-- both functions see the same local upvalue.
local function name_ench(s)
    s = DSP.clean_text(s or '')
    local base, e = s:match('^(.-)%s*%(%+(%d+)%)%s*$')
    if base and base ~= '' then return base, tonumber(e) or 0 end
    return s, 0
end

local function mkdir_p(p)
    if not ok_lfs or not lfs then return end
    if type(lfs.attributes) == 'function' then
        local ok, attr = pcall(lfs.attributes, p)
        if not ok then
            pcall(lfs.mkdir, p)
        end
    end
end

local function file_write(path, data)
    local f = io.open(path, 'w')
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function file_read(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local raw = f:read('*a')
    f:close()
    return raw
end

function DSP.db.save_trades()
    local pack = {
        trades = DSP.settings.trades or {},
        stalls = DSP.settings.stalls or {},
        crates = DSP.settings.crates or {},
        chat_logs = DSP.settings.chat_logs or {},
        saved_at = os.time(),
    }
    local ok, json = pcall(encodeJson, pack)
    if not ok or not json then return false end
    local f = io.open(DSP.dir .. '/trades.json', 'w')
    if not f then return false end
    f:write(json)
    f:close()
    return true
end

function DSP.db.load_trades()
    local raw = file_read(DSP.dir .. '/trades.json')
    if not raw then return false end
    local ok, pack = pcall(decodeJson, raw)
    if not ok or type(pack) ~= 'table' then return false end
    DSP.settings.trades = pack.trades or {}
    DSP.settings.stalls = pack.stalls or {}
    DSP.settings.crates = pack.crates or {}
    DSP.settings.chat_logs = pack.chat_logs or {}
    local n_trade, n_stall, n_crate = 0, 0, 0
    for _, e in pairs(DSP.settings.trades) do DSP.logs.trade_logs[#DSP.logs.trade_logs + 1] = e; n_trade = n_trade + 1 end
    for _, e in pairs(DSP.settings.stalls) do DSP.logs.stall_logs[#DSP.logs.stall_logs + 1] = e; n_stall = n_stall + 1 end
    for _, e in pairs(DSP.settings.crates) do DSP.logs.crate_logs[#DSP.logs.crate_logs + 1] = e; n_crate = n_crate + 1 end
    table.sort(DSP.logs.trade_logs, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    table.sort(DSP.logs.stall_logs, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    table.sort(DSP.logs.crate_logs, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    DSP.flog('TRADES loaded trades=' .. tostring(n_trade) .. ' stalls=' .. tostring(n_stall) .. ' crates=' .. tostring(n_crate))
    return true
end

function DSP.logs.save_daily_log()
    mkdir_p(LOG_DIR)
    local today = os.date('%Y-%m-%d', os.time())
    local lines = {}
    for _, e in ipairs(DSP.logs.trade_logs) do
        if os.date('%Y-%m-%d', e.ts or 0) == today then
            local t = type(e) == 'table' and e
            if t and t.type == 'trade' then
                table.insert(lines, string.format('[TRADE] %s | %s -> получено: %s, отдано: %s, прибыль: %s (%+.1f%%) | %s',
                    os.date('%H:%M:%S', t.ts or 0),
                    t.partner or '?',
                    DSP.money(t.total_get or 0),
                    DSP.money(t.total_give or 0),
                    DSP.money(t.profit or 0),
                    t.delta_pct or 0,
                    t.kind or ''))
            end
        end
    end
    file_write(LOG_DIR .. '/' .. today .. '.log', table.concat(lines, '\n') .. '\n')
end

function DSP.logs.record_trade(partner, items_give, items_get, money_give, money_get, result)
    local total_give = tonumber(money_give or 0)
    local total_get = tonumber(money_get or 0)
    for _, it in ipairs(items_give or {}) do
        local e = DSP.db.get(it.name, it.ench)
        if e and e.buy and e.buy.max and e.buy.max > 0 then
            total_give = total_give + e.buy.max * (it.qty or 1)
        end
    end
    for _, it in ipairs(items_get or {}) do
        local e = DSP.db.get(it.name, it.ench)
        if e and e.buy and e.buy.max and e.buy.max > 0 then
            total_get = total_get + e.buy.max * (it.qty or 1)
        end
    end
    local profit = total_get - total_give
    local delta_pct = total_give > 0 and (profit / total_give * 100) or 0
    local kind = profit > 0 and 'profit' or (profit < 0 and 'loss' or 'neutral')

    local entry = {
        type = 'trade',
        ts = os.time(),
        partner = tostring(partner or '?'),
        kind = kind,
        total_get = total_get,
        total_give = total_give,
        profit = profit,
        delta_pct = delta_pct,
        items_give = items_give or {},
        items_get = items_get or {},
        money_give = tonumber(money_give or 0) or 0,
        money_get = tonumber(money_get or 0) or 0,
        server = DSP.settings.server or 102,
    }
    local entry_id = tostring(entry.ts)
    DSP.settings.trades[entry_id] = entry
    DSP.db.save_trades()
    DSP.logs.save_daily_log()
    -- v1.2 Stage 3: push to craglog ring buffer + append-only file.
    -- Independent of save_daily_log which rewrites today's file each trade.
    if DSP.craglog and DSP.craglog.log_trade then
        pcall(DSP.craglog.log_trade, entry)
    end
    if DSP.live and DSP.live.reset_trade then DSP.live.reset_trade(partner) end
    DSP.notify('СДЕЛКА: ' .. DSP.money(profit) .. ' (' .. string.format('%+.1f%%', delta_pct) .. ')', kind == 'profit' and 'ok' or 'error')
    DSP.add_log('СДЕЙКА с ' .. tostring(partner) .. ': ' .. DSP.money(profit) .. ' (' .. DSP.money(total_get) .. '/' .. DSP.money(total_give) .. ')',
        kind == 'profit' and 'ok' or 'error')
    -- Telegram notification for trade
    if DSP.settings.tg_notify and DSP.settings.tg_bot_token and DSP.settings.tg_chat_id then
        local emoji = profit > 0 and '[+]' or (profit < 0 and '[-]' or '[=]')
        local msg = '[palatka ai] Сделка ' .. emoji .. ' '
            .. DSP.money(profit) .. ' с ' .. tostring(partner or '?')
            .. ' (получено: ' .. DSP.money(total_get) .. ', отдано: ' .. DSP.money(total_give) .. ')'
        send_telegram(msg)
    end
end

function DSP.logs.stall_dropped(owner, shop_num, item_name, price)
    local entry = {
        type = 'stall',
        ts = os.time(),
        owner = tostring(owner or '?'),
        shop_num = tostring(shop_num or '?'),
        item_name = tostring(item_name or ''),
        price = tonumber(price) or 0,
        server = DSP.settings.server or 102,
    }
    DSP.settings.stalls[tostring(entry.ts)] = entry
    DSP.db.save_trades()
    DSP.logs.save_daily_log()
    DSP.add_log('Лавка пала: ' .. tostring(owner) .. '#' .. tostring(shop_num)
        .. ' / ' .. tostring(item_name) .. ' @ ' .. DSP.money(entry.price), 'ok')
end

function DSP.logs.crate_opened(item_name, price, count, source, ench)
    local entry = {
        type = 'crate',
        ts = os.time(),
        item_name = tostring(item_name or ''),
        item = tostring(item_name or ''),
        price = tonumber(price) or 0,
        count = tonumber(count) or 1,
        qty = tonumber(count) or 1,
        crate_type = tostring(source or 'тайник'),
        source = tostring(source or 'тайник'),
        ench = tonumber(ench) or 0,
        server = DSP.settings.server or 102,
    }
    DSP.settings.crates[tostring(entry.ts)] = entry
    DSP.db.save_trades()
    DSP.logs.save_daily_log()
    DSP.add_log('Тайник (' .. entry.source .. '): +' .. tostring(entry.count) .. 'x ' .. tostring(item_name)
        .. ' @ ' .. DSP.money(entry.price), 'ok')
    -- v1.2 Stage 3: push to craglog ring buffer + crates.log file.
    if DSP.craglog and DSP.craglog.log_crate then
        pcall(DSP.craglog.log_crate, entry)
    end
    -- Telegram notification for crate drop
    if DSP.settings.tg_notify and DSP.settings.tg_bot_token and DSP.settings.tg_chat_id then
        send_telegram('[palatka ai] [+] ' .. entry.source .. ': +' .. tostring(entry.count)
            .. 'x ' .. tostring(item_name) .. (entry.ench and entry.ench > 0 and (' +' .. tostring(entry.ench)) or ''))
    end
end

local function day_key(ts, mode)
    if mode == 'hour' then return os.date('%Y-%m-%d %H:00', ts) end
    if mode == 'day' then return os.date('%Y-%m-%d', ts) end
    if mode == 'week' then
        local d = os.date('*t', ts)
        local w = math.floor((d.yday - 1) / 7) + 1
        return string.format('%04d-W%02d', d.year, w)
    end
    if mode == 'month' then return string.format('%04d-%02d', d.year, d.month) end
    return 'all'
end

function DSP.logs.stats(mode)
    mode = mode or 'day'
    local buckets = {}
    for _, e in pairs(DSP.settings.trades or {}) do
        if e and e.type == 'trade' then
            local key = day_key(e.ts or 0, mode)
            local b = buckets[key] or { count = 0, profit = 0, total_get = 0, total_give = 0 }
            b.count = b.count + 1
            b.profit = b.profit + (e.profit or 0)
            b.total_get = b.total_get + (e.total_get or 0)
            b.total_give = b.total_give + (e.total_give or 0)
            buckets[key] = b
        end
    end
    return buckets
end

function DSP.logs.profit_summary(mode)
    local buckets = DSP.logs.stats(mode)
    local total_count, total_profit, total_get, total_give = 0, 0, 0, 0
    local sorted_keys = {}
    for k, _ in pairs(buckets) do table.insert(sorted_keys, k) end
    table.sort(sorted_keys, function(a, b) return a > b end)
    for _, k in ipairs(sorted_keys) do
        local b = buckets[k]
        total_count = total_count + b.count
        total_profit = total_profit + b.profit
        total_get = total_get + b.total_get
        total_give = total_give + b.total_give
    end
    return {
        count = total_count,
        profit = total_profit,
        avg_profit = total_count > 0 and math.floor(total_profit / total_count) or 0,
        total_get = total_get,
        total_give = total_give,
        roi = total_give > 0 and (total_profit / total_give * 100) or 0,
        buckets = buckets,
        sorted_keys = sorted_keys,
    }
end

function DSP.logs.trade_detail(idx)
    local i = 0
    for _, e in pairs(DSP.settings.trades or {}) do
        i = i + 1
        if i == idx and e then return e end
    end
    return nil
end

function DSP.logs.clear_trades()
    DSP.settings.trades = {}
    DSP.settings.stalls = {}
    DSP.settings.crates = {}
    DSP.settings.chat_logs = {}
    DSP.logs.trade_logs = {}
    DSP.logs.stall_logs = {}
    DSP.logs.crate_logs = {}
    DSP.db.save_trades()
    DSP.add_log('Все логи сделок очищены')
end

local function url_encode(s)
    if not s then return '' end
    s = tostring(s):gsub('([^%w%.%-_])', function(c)
        local b = string.byte(c)
        return '%' .. string.format('%02X', b)
    end)
    return s
end

local function send_telegram(msg)
    if not DSP.settings.tg_notify or not DSP.settings.tg_bot_token or not DSP.settings.tg_chat_id then
        return
    end
    msg = tostring(msg or '')
    local url = 'https://api.telegram.org/bot' .. DSP.settings.tg_bot_token
        .. '/sendMessage?chat_id=' .. DSP.settings.tg_chat_id
        .. '&text=' .. url_encode(msg)
    if DSP.http_get then
        pcall(DSP.http_get, url, function(_, _) end)
    end
end

function DSP.logs.parse_chat_drop(text)
    local s = DSP.clean_text(text or '')
    if s == '' then return nil end
    -- v1.2 Stage 3: 6 strict patterns per ТЗ.
    -- Each pattern captures (source, item, qty) variants.
    -- The leading source field feeds the per-tайник stats table
    -- (Тайник VC, Тайник Илона Маска, etc.).
    local patterns = {
        -- 1. "Вам выпало из {source}: {item} ({qty} шт.)"
        { '^Вам выпало из (.+): (.+) %((%d+) шт%.%)', 3 },
        -- 2. "Вы открыли {source} и получили {item}"
        { '^Вы открыли (.+) и получили (.+)', 2 },
        -- 3. "Вам выпало: {item} ({qty} шт.)"
        { '^Вам выпало: (.+) %((%d+) шт%.%)', 2 },
        -- 4. "Вам выпал[оа]? {item}" (муж/жен/ср род)
        { '^Вам выпал[оа]? (.+)', 1 },
        -- 5. "Вы использовали {source} и получили {item}"
        { '^Вы использовали (.+) и получили (.+)', 2 },
        -- 6. "Вы успешно открыли {source} и вам выпало {item}"
        { '^Вы успешно открыли (.+) и вам выпало (.+)', 2 },
    }
    for _, pat in ipairs(patterns) do
        local m = { s:match(pat[1]) }
        if m[1] then
            local source, item, qty
            if pat[2] == 3 then
                source = m[1]
                item = m[2]
                qty = tonumber(m[3]) or 1
            elseif pat[2] == 2 then
                source = m[1]
                item = m[2]
                qty = 1
            else
                source = 'тайник'
                item = m[1]
                qty = 1
            end
            item = DSP.clean_text(item or '')
            local base, e = name_ench(item)
            if base and base ~= '' then item, e = base, e end
            return {
                name = item,
                ench = e or 0,
                qty = qty,
                source = DSP.clean_text(source or 'тайник'),
            }
        end
    end
    return nil
end

function DSP.logs.log_chat(text)
    if not DSP.settings.log_chat_drops then return end
    local s = DSP.clean_text(text or '')
    if s == '' then return end
    -- v1.2 Stage 3: PayDay detection. The hook in 45_live.lua checks the
    -- message for the payday marker and triggers Telegram. The detection
    -- function lives in 45_live.lua to keep this module focused on logging.
    if DSP.live and DSP.live.check_payday_message then
        pcall(DSP.live.check_payday_message, s)
    end
    -- Check for item drop messages (now with source + ench propagation)
    local drop = DSP.logs.parse_chat_drop(s)
    if drop and drop.name and drop.name ~= '' then
        DSP.logs.crate_opened(drop.name, 0, drop.qty, drop.source, drop.ench)
    end
    -- Store in chat log
    local entry = {
        ts = os.time(),
        text = s,
        kind = 'chat',
    }
    table.insert(DSP.settings.chat_logs, entry)
    while #DSP.settings.chat_logs > 500 do
        table.remove(DSP.settings.chat_logs, 1)
    end
    DSP.db.save_trades()
end

function DSP.logs.send_telegram(msg)
    send_telegram(msg)
end

function DSP.logs.export_logs()
    local today = DSP.logs.profit_summary('all')
    local msg = '[palatka ai] Статистика:\n'
        .. 'Сделок: ' .. today.count .. '\n'
        .. 'Прибыль: ' .. DSP.money(today.profit) .. '\n'
        .. 'Получено: ' .. DSP.money(today.total_get) .. '\n'
        .. 'Отдано: ' .. DSP.money(today.total_give) .. '\n'
        .. 'ROI: ' .. string.format('%.1f%%', today.roi) .. '\n'
        .. 'Средняя сделка: ' .. DSP.money(today.avg_profit)
    DSP.logs.send_telegram(msg)
end

function DSP.logs.install()
    if DSP.logs.installed then return end
    DSP.logs.installed = true
end

function DSP.logs.load()
    DSP.db.load_trades()
end

return true
