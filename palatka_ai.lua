-- Palatka AI, built from src/*.lua (independent of Market Helper)
script_name('palatka ai')
script_author('palatka ai')
script_version('1.1.0')

if not imgui then imgui = require('mimgui') end
DSP = DSP or {}

local function __mod_00_core()
-- Palatka AI core: state, settings, encoding, formatting.
DSP = DSP or {}
DSP.version = '1.1.0'
DSP.name = 'palatka ai'
-- Palette (spec section 3.4)
DSP.acc = { 0.92, 0.60, 0.15 }            -- amber / gold accent
DSP.colors = {
    bg = { 0.08, 0.08, 0.11, 0.98 },       -- deep graphite window
    accent = { 0.92, 0.60, 0.15, 1.00 },
    buy = { 0.18, 0.80, 0.35, 1.00 },      -- skupka / profit (emerald)
    sell = { 0.92, 0.45, 0.18, 1.00 },     -- sale / expense (orange)
    scam = { 0.90, 0.22, 0.22, 1.00 },     -- overprice / scam (scarlet)
}

local encoding = require('encoding')
encoding.default = 'CP1251'
DSP.u8 = encoding.UTF8

function DSP.to_cp(s)
    if type(s) ~= 'string' or s == '' then return s or '' end
    local ok, r = pcall(function() return DSP.u8:decode(s) end)
    return ok and r or s
end

function DSP.to_u8(s)
    if type(s) ~= 'string' or s == '' then return s or '' end
    local ok, r = pcall(function() return DSP.u8:encode(s) end)
    return ok and r or s
end

function DSP.utf8(s)
    return DSP.to_u8(tostring(s or ''))
end

function DSP.lower(s)
    s = tostring(s or '')
    s = s:gsub('[\192-\223]', function(c)
        return string.char(string.byte(c) + 32)
    end)
    s = s:gsub('\168', '\184')
    return s:lower()
end

function DSP.trim(s)
    return (tostring(s or ''):match('^%s*(.-)%s*$')) or ''
end

function DSP.money(n)
    n = math.floor(tonumber(n) or 0)
    local neg = n < 0
    if neg then n = -n end
    local s = tostring(n)
    s = s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return (neg and '-$' or '$') .. s
end

function DSP.quantile(sorted, p)
    local n = #sorted
    if n == 0 then return 0 end
    local idx = math.ceil(p * n)
    if idx < 1 then idx = 1 elseif idx > n then idx = n end
    return sorted[idx]
end

function DSP.clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function DSP.now()
    return os.time()
end

function DSP.mkdir(path)
    if type(path) ~= 'string' or path == '' then return end
    if doesDirectoryExist and doesDirectoryExist(path) then return end
    if createDirectory then pcall(createDirectory, path) end
end

DSP.dir = (getWorkingDirectory():gsub('\\', '/')):gsub('/$', '') .. '/PalatkaAI'
DSP.mkdir(DSP.dir)

DSP.log_path = DSP.dir .. '/standalone.log'
DSP.settings_path = DSP.dir .. '/standalone_settings.json'
DSP.legacy_items_path = DSP.dir .. '/arz_items.json'
DSP.market_path = function(sid)
    return DSP.dir .. '/market_' .. tostring(sid) .. '.json'
end

DSP.settings = {
    server = 102,
    sort = 1,
    margin = 10,
    undercut = 2,
    only_profit = false,
    liquid = false,
    dry_run = true,
    per_page = 20,
    auto_buy_qty = 1,
    dpi = 1.0,
    dpi_auto = true,
    tax = 3,
    delay_ms = 500,
    fab = true,
    scam_ratio = 3,
    auto_open_stall = true,
    avg_autoscan = true,
    overlay_trade = true,
    overlay_shop = true,
    overlay_top = true,
    stats_mode = 'day',
    tg_bot_token = '',
    tg_chat_id = '',
    tg_notify = false,
    log_chat_drops = true,
    chat_logs = {},
    trades = {},
    stalls = {},
    crates = {},
    buy_preset = { name = 'Скупка', items = {} },
    sell_preset = { name = 'Продажа', items = {} },
}

function DSP.save_settings()
    local ok, json = pcall(encodeJson, DSP.settings)
    if not ok or not json then return false end
    local f = io.open(DSP.settings_path, 'w')
    if not f then return false end
    f:write(json)
    f:close()
    return true
end

function DSP.load_settings()
    local f = io.open(DSP.settings_path, 'rb')
    if not f then return false end
    local raw = f:read('*a')
    f:close()
    local ok, d = pcall(decodeJson, raw)
    if not ok or type(d) ~= 'table' then return false end
    for k, v in pairs(d) do DSP.settings[k] = v end
    if type(DSP.settings.buy_preset) ~= 'table' then
        DSP.settings.buy_preset = { name = 'Скупка', items = {} }
    end
    if type(DSP.settings.sell_preset) ~= 'table' then
        DSP.settings.sell_preset = { name = 'Продажа', items = {} }
    end
    DSP.settings.buy_preset.items = DSP.settings.buy_preset.items or {}
    DSP.settings.sell_preset.items = DSP.settings.sell_preset.items or {}
    return true
end

DSP.log = {}
DSP.log_seq = 0

function DSP.flog(msg)
    local f = io.open(DSP.log_path, 'a')
    if not f then return end
    f:write(os.date('%H:%M:%S ') .. tostring(msg) .. '\n')
    f:close()
end

local function hex(s)
    return (tostring(s or ''):gsub('.', function(c) return string.format('%02X', string.byte(c)) end))
end

function DSP.enc_selftest()
    local cp = DSP.to_u8('Тест')
    local utf = DSP.to_cp(string.char(0xD0,0xA2,0xD0,0xB5,0xD1,0x81,0xD1,0x82))
    DSP.flog('enc cp=' .. hex(cp) .. ' utf=' .. hex(utf))
end

function DSP.add_log(text, kind)
    DSP.log_seq = DSP.log_seq + 1
    table.insert(DSP.log, 1, {
        id = DSP.log_seq,
        t = os.date('%H:%M:%S'),
        text = text,
        kind = kind or 'info',
    })
    while #DSP.log > 250 do table.remove(DSP.log) end
end

function DSP.notify(text)
    DSP.add_log(text)
    DSP.flog('NOTIFY ' .. tostring(text))
    if mh_notify then
        pcall(mh_notify, text, 0xFFFFFF)
    elseif sampAddChatMessage then
        pcall(sampAddChatMessage, '[Palatka AI] ' .. text, 0xFFAAFF)
    end
end

-- Cut long item names for card layouts (byte-safe for CP1251).
function DSP.truncate_text(s, n)
    s = tostring(s or '')
    n = tonumber(n) or 28
    if #s <= n then return s end
    return s:sub(1, math.max(1, n - 2)) .. '..'
end

function DSP.item_name(name, ench)
    name = tostring(name or '')
    ench = tonumber(ench) or 0
    if ench > 0 then return name .. ' (+' .. tostring(ench) .. ')' end
    return name
end

function DSP.item_key(name, ench)
    return DSP.lower(name) .. '|' .. tostring(tonumber(ench) or 0)
end

DSP.load_settings()
DSP.flog('--- load v' .. DSP.version .. ' ---')
DSP.enc_selftest()

end
__mod_00_core()

local function __mod_05_items()
-- Item catalog: numeric item id -> CP1251 name.
DSP.items = DSP.items or { by_id = {}, loaded = false }

local function valid_utf8(s)
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        if c < 0x80 then
            i = i + 1
        elseif c >= 0xC2 and c <= 0xDF then
            local c2 = s:byte(i + 1)
            if not c2 or c2 < 0x80 or c2 > 0xBF then return false end
            i = i + 2
        elseif c >= 0xE0 and c <= 0xEF then
            local c2, c3 = s:byte(i + 1), s:byte(i + 2)
            if not c2 or not c3 or c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF then return false end
            i = i + 3
        elseif c >= 0xF0 and c <= 0xF4 then
            local c2, c3, c4 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
            if not c2 or not c3 or not c4
                or c2 < 0x80 or c2 > 0xBF
                or c3 < 0x80 or c3 > 0xBF
                or c4 < 0x80 or c4 > 0xBF then return false end
            i = i + 4
        else
            return false
        end
    end
    return true
end

function DSP.text_cp(s)
    if type(s) ~= 'string' or s == '' then return s or '' end
    if s:find('[\194-\244]') and valid_utf8(s) then
        local ok, r = pcall(function() return DSP.u8:decode(s) end)
        if ok and r and r ~= '' then return r end
    end
    return s
end

function DSP.clean_text(s)
    s = DSP.text_cp(tostring(s or ''))
    return (s:gsub('{[%x]+}', ''):match('^%s*(.-)%s*$')) or ''
end

function DSP.parse_item_id(raw, ench)
    local base, e = 0, 0
    if type(raw) == 'number' then
        base = math.floor(raw)
    else
        local s = tostring(raw or '')
        base = tonumber(s:match('^(%d+)')) or 0
        e = tonumber(s:match('%((%d+)%)')) or 0
    end
    local e_field = tonumber(ench)
    if e_field and e_field > 0 then e = e_field end
    e = e or 0
    if e < 0 or e > 20 then e = 0 end
    return base, math.floor(e)
end

function DSP.items.name(id)
    id = tonumber(id) or 0
    local nm = DSP.items.by_id[id]
    if nm and nm ~= '' then return DSP.clean_text(nm) end
    return 'ID:' .. tostring(id)
end

function DSP.items.display(raw, ench)
    local id, e = DSP.parse_item_id(raw, ench)
    return DSP.item_name(DSP.items.name(id), e), id, e
end

local function parse_flat(raw)
    local data = {}
    for k, v in tostring(raw or ''):gmatch('"(%d+)"%s*:%s*"([^"]*)"') do
        data[k] = v
    end
    return data
end

function DSP.items.load()
    local root = (getWorkingDirectory() or '.'):gsub('\\', '/'):gsub('/$', '')
    local paths = {
        DSP.dir .. '/items_data.json',
        DSP.dir .. '/arz_items.json',
        root .. '/MarketHelper/items_data.json',
        root .. '/MarketHelper/arz_items.json',
    }
    for _, path in ipairs(paths) do
        local f = io.open(path, 'rb')
        if f then
            local raw = f:read('*a') or ''
            f:close()
            local ok, data = pcall(decodeJson, raw)
            if not ok or type(data) ~= 'table' then
                data = parse_flat(raw)
                ok = next(data) ~= nil
            end
            local n = 0
            if ok and type(data) == 'table' then
                for k, v in pairs(data) do
                    local id = tonumber(k)
                    if id and type(v) == 'string' and v ~= '' then
                        DSP.items.by_id[id] = v
                        n = n + 1
                    end
                end
            end
            if n == 0 then
                data = parse_flat(raw)
                for k, v in pairs(data) do
                    local id = tonumber(k)
                    if id and type(v) == 'string' and v ~= '' then
                        DSP.items.by_id[id] = v
                        n = n + 1
                    end
                end
            end
            if n > 0 then
                DSP.items.loaded = true
                DSP.flog('ITEMS loaded=' .. tostring(n) .. ' path=' .. path)
                return true
            end
            DSP.flog('ITEMS parse failed path=' .. path)
        end
    end
    DSP.flog('ITEMS missing catalog')
    return false
end

end
__mod_05_items()

local function __mod_10_market()
-- Live lavka market: pull, enchant-aware stats, cache, shops list, arbitrage.
--
-- DATA MODEL (player's point of view, see PALATKA_AI_MASTER_PROMPT.md section 4):
--   shop.sell_slots -> row.sell : the shop SELLS, the player BUYS here (player's cost).
--                                 best = MIN price (cheapest place to buy).
--   shop.buy_slots  -> row.buy  : the shop BUYS, the player SELLS here (player's revenue).
--                                 best = MAX price (most expensive place to sell).
--   Net profit = floor(P_sell * (1 - tax)) - P_buy, where P_buy comes ONLY from
--   sell_slots and P_sell comes ONLY from buy_slots.
DSP.market = DSP.market or {}

if DSP.settings.tax == nil then DSP.settings.tax = 3 end
if DSP.settings.scam_ratio == nil then DSP.settings.scam_ratio = 3 end

-- CR commission in percent (1 = ADD VIP, 2 = Titan/Premium, 3-4 = without VIP).
function DSP.market.tax_pct()
    local t = tonumber(DSP.settings.tax) or 3
    if t < 0 then t = 0 elseif t > 20 then t = 20 end
    return t
end

-- Revenue after CR commission for a sale at `price`.
function DSP.market.net(price)
    price = tonumber(price) or 0
    if price <= 0 then return 0 end
    return math.floor(price * (1 - DSP.market.tax_pct() / 100))
end

-- Net profit of buying at p_buy (a sell_slot) and selling at p_sell (a buy_slot).
function DSP.market.profit(p_buy, p_sell)
    return DSP.market.net(p_sell) - (tonumber(p_buy) or 0)
end

DSP.market.api = 'https://va-ta.com/api/shops/pull'
DSP.market.state = {
    sid = DSP.settings.server or 102,
    status = 'idle',
    error = nil,
    rows = {},
    by_key = {},
    shops = 0,
    offers = 0,
    updated = 0,
    saved_at = 0,
    version = 0,
    filter_cache = nil,
    filter_version = -1,
    page = 1,
    shop_list = {},
    arb_cache = nil,
    arb_version = -1,
}

DSP.market.servers = {
    { id = 101, name = 'Mobile I' },
    { id = 102, name = 'Mobile II' },
    { id = 103, name = 'Mobile III' },
}

function _G.dsp_http_get(url)
    local ok, requests = pcall(require, 'requests')
    if not ok or not requests then return { code = 0, body = '', err = 'requests missing' } end
    local ok2, resp = pcall(requests.request, 'GET', url)
    if not ok2 or not resp then return { code = 0, body = '', err = 'request failed: ' .. tostring(resp) } end
    return { code = tonumber(resp.status_code) or 0, body = tostring(resp.text or ''), err = nil }
end

local function effil_result(thread)
    local ok_get, result = pcall(function() return thread:get() end)
    if not ok_get then
        return nil, tostring(result)
    end
    if type(result) == 'table' or type(result) == 'userdata' then
        local code = tonumber(result.code or result[1] or 0)
        local body = tostring(result.body or result[2] or '')
        local werr = result.err or result[3]
        return { code = code, body = body, err = werr }, nil
    end
    if type(result) == 'number' then
        return { code = result, body = '', err = nil }, nil
    end
    return nil, 'unexpected result type: ' .. type(result)
end

function DSP.http_get(url, cb)
    local ok, effil = pcall(require, 'effil')
    if not ok or not effil then
        return cb(nil, 'effil missing')
    end
    local ok_th, thread = pcall(function() return effil.thread(_G.dsp_http_get)(url) end)
    if not ok_th or not thread then
        return cb(nil, 'thread create: ' .. tostring(thread))
    end
    lua_thread.create(function()
        local deadline = os.time() + 60
        while true do
            wait(25)
            if os.time() > deadline then
                pcall(function() thread:cancel() end)
                return cb(nil, 'timeout')
            end
            local ok_status, status, err = pcall(function() return thread:status() end)
            if not ok_status then
                return cb(nil, 'thread status error')
            end
            if status == 'completed' or status == 'canceled' then
                local res, rerr = effil_result(thread)
                if not res then
                    return cb(nil, 'get: ' .. tostring(rerr))
                end
                if res.code ~= 200 then
                    return cb(nil, 'HTTP ' .. tostring(res.code) .. (res.err and (' ' .. tostring(res.err)) or ''))
                end
                if type(res.body) ~= 'string' or res.body == '' then
                    return cb(nil, 'empty response')
                end
                return cb(res.body, nil)
            end
            if status == 'error' or status == 'failed' then
                local e = tostring(err or 'thread error')
                if type(err) == 'table' and err.message then e = err.message end
                return cb(nil, e)
            end
        end
    end)
end

function DSP.player_nick()
    local nick = ''
    pcall(function()
        local ok, pid = sampGetPlayerIdByCharHandle(PLAYER_PED)
        if ok then nick = sampGetPlayerNickname(pid) or '' end
    end)
    if nick == '' then pcall(function() nick = sampGetCurrentPlayerName() or '' end) end
    if nick == '' then nick = 'DsPic' end
    return nick
end

function DSP.detect_server()
    local name = ''
    pcall(function() name = sampGetCurrentServerName() or '' end)
    name = DSP.lower(name)
    if name ~= '' then
        if name:find('mobile%s*iii') or name:find('mobile%s*3') then return 103 end
        if name:find('mobile%s*ii') or name:find('mobile%s*2') then return 102 end
        if name:find('mobile%s*i') or name:find('mobile%s*1') then return 101 end
    end
    return nil
end

local function sanitize_ench(v)
    local e = tonumber(v) or 0
    if e < 0 or e > 20 then e = 0 end
    return math.floor(e)
end

local function add_offer(map, name, ench, offer)
    if name == '' or offer.price <= 0 then return end
    local key = DSP.item_key(name, ench)
    local row = map[key]
    if not row then
        row = {
            key = key,
            name = name,
            ench = ench,
            display = DSP.item_name(name, ench),
            sell = { offers = {}, prices = {}, n = 0, qty = 0, shops = {} },
            buy = { offers = {}, prices = {}, n = 0, qty = 0, shops = {} },
        }
        map[key] = row
    end
    local side = offer.side == 'sell' and row.sell or row.buy
    side.n = side.n + 1
    side.qty = side.qty + offer.qty
    side.prices[#side.prices + 1] = offer.price
    side.shops[offer.shop] = true
    side.offers[#side.offers + 1] = offer
end

local function finish_side(side, asc)
    table.sort(side.prices)
    local n = #side.prices
    side.count = n
    if n == 0 then
        side.min, side.max, side.p25, side.med, side.p75 = 0, 0, 0, 0, 0
        side.best = 0
        return
    end
    side.min = side.prices[1]
    side.max = side.prices[n]
    side.p25 = DSP.quantile(side.prices, 0.25)
    side.med = DSP.quantile(side.prices, 0.50)
    side.p75 = DSP.quantile(side.prices, 0.75)
    side.best = asc and side.min or side.max
    table.sort(side.offers, function(a, b)
        if a.price ~= b.price then
            if asc then
                return a.price < b.price
            else
                return a.price > b.price
            end
        end
        return (a.qty or 0) > (b.qty or 0)
    end)
    local shop_n = 0
    for _ in pairs(side.shops) do shop_n = shop_n + 1 end
    side.shop_n = shop_n
    while #side.offers > 25 do table.remove(side.offers) end
end

-- Profit of the best pair for an item row: buy at the cheapest sell_slot,
-- sell into the most expensive buy_slot, minus CR commission.
function DSP.market.row_profit(row)
    if row.sell.count > 0 and row.buy.count > 0 then
        row.profit = DSP.market.profit(row.sell.min, row.buy.max)
        row.profit_med = DSP.market.profit(row.sell.med, row.buy.med)
        row.profit_pct = row.sell.min > 0 and (row.profit / row.sell.min * 100) or 0
    else
        row.profit, row.profit_med, row.profit_pct = 0, 0, 0
    end
    return row.profit
end

-- Re-apply commission after the tax setting changes.
function DSP.market.recompute()
    local st = DSP.market.state
    for _, row in ipairs(st.rows or {}) do DSP.market.row_profit(row) end
    st.version = st.version + 1
    st.filter_version = -1
    st.arb_version = -1
end

function DSP.market.rebuild(payload, sid)
    sid = tonumber(sid) or DSP.market.state.sid
    local shops = type(payload) == 'table' and payload.shops or {}
    local map = {}
    local offers_n, shops_n = 0, 0
    local newest, oldest = 0, 0
    local shop_list = {}
    for _, shop in ipairs(shops) do
        local ssid = tonumber(shop.server_id)
        if not ssid or ssid == sid then
            local owner = DSP.to_cp(shop.owner or '?')
            local shop_num = tostring(shop.shop_num or '?')
            local ts = tonumber(shop.updated_at or 0) or 0
            if ts > 0 then
                if newest == 0 or ts > newest then newest = ts end
                if oldest == 0 or ts < oldest then oldest = ts end
            end
            local has_slot = false
            local card = { owner = owner, shop_num = shop_num, updated = ts, sell = {}, buy = {} }
            -- sell_slots: the shop SELLS -> the player BUYS here (cost) -> row.sell
            for _, slot in ipairs(shop.sell_slots or {}) do
                local name = DSP.to_cp(slot.name or '')
                local price = tonumber(slot.price) or 0
                local qty = tonumber(slot.qty) or 0
                if name ~= '' and price > 0 then
                    has_slot = true
                    offers_n = offers_n + 1
                    local ench = sanitize_ench(slot.ench)
                    add_offer(map, name, ench, {
                        side = 'sell', price = price, qty = qty,
                        owner = owner, shop = shop_num, ench = ench,
                    })
                    card.sell[#card.sell + 1] = { name = name, ench = ench, price = price, qty = qty,
                        key = DSP.item_key(name, ench), display = DSP.item_name(name, ench) }
                end
            end
            -- buy_slots: the shop BUYS -> the player SELLS here (revenue) -> row.buy
            for _, slot in ipairs(shop.buy_slots or {}) do
                local name = DSP.to_cp(slot.name or '')
                local price = tonumber(slot.price) or 0
                local qty = tonumber(slot.qty) or 0
                if name ~= '' and price > 0 then
                    has_slot = true
                    offers_n = offers_n + 1
                    local ench = sanitize_ench(slot.ench)
                    add_offer(map, name, ench, {
                        side = 'buy', price = price, qty = qty,
                        owner = owner, shop = shop_num, ench = ench,
                    })
                    card.buy[#card.buy + 1] = { name = name, ench = ench, price = price, qty = qty,
                        key = DSP.item_key(name, ench), display = DSP.item_name(name, ench) }
                end
            end
            if has_slot then
                shops_n = shops_n + 1
                shop_list[#shop_list + 1] = card
            end
        end
    end
    local rows = {}
    for _, row in pairs(map) do
        finish_side(row.sell, true)   -- player buys: cheapest first
        finish_side(row.buy, false)   -- player sells: most expensive first
        DSP.market.row_profit(row)
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b)
        if (a.profit or 0) ~= (b.profit or 0) then return (a.profit or 0) > (b.profit or 0) end
        if (a.sell.best or 0) ~= (b.sell.best or 0) then return (a.sell.best or 0) < (b.sell.best or 0) end
        return a.display < b.display
    end)
    table.sort(shop_list, function(a, b)
        local na, nb = tonumber(a.shop_num), tonumber(b.shop_num)
        if na and nb and na ~= nb then return na < nb end
        if (na ~= nil) ~= (nb ~= nil) then return na ~= nil end
        if a.shop_num ~= b.shop_num then return tostring(a.shop_num) < tostring(b.shop_num) end
        return tostring(a.owner) < tostring(b.owner)
    end)
    DSP.market.state.shop_list = shop_list
    DSP.market.state.arb_version = -1
    DSP.market.state.rows = rows
    DSP.market.state.by_key = map
    DSP.market.state.sid = sid
    DSP.market.state.shops = shops_n
    DSP.market.state.offers = offers_n
    DSP.market.state.updated = newest
    DSP.market.state.oldest = oldest
    DSP.market.state.version = DSP.market.state.version + 1
    DSP.market.state.filter_version = -1
    DSP.market.state.error = nil
    DSP.market.state.status = 'live'
    if DSP.db and DSP.db.set_rows then
        local ok_db, err_db = pcall(DSP.db.set_rows, rows, sid)
        if not ok_db then DSP.flog('DB set error: ' .. tostring(err_db)) end
    end
end

function DSP.market.freshness()
    local ts = DSP.market.state.updated
    if not ts or ts <= 0 then return 'нет данных' end
    local age = math.max(0, os.time() - ts)
    if age < 60 then return age .. ' сек' end
    if age < 3600 then return math.floor(age / 60) .. ' мин' end
    if age < 86400 then return math.floor(age / 3600) .. ' ч' end
    return math.floor(age / 86400) .. ' дн'
end

function DSP.market.url(sid)
    return DSP.market.api
        .. '?server=' .. tostring(sid)
        .. '&nick=' .. tostring(DSP.player_nick())
        .. '&ver=' .. tostring(DSP.version)
end

function DSP.market.pull(sid, done)
    sid = tonumber(sid) or DSP.market.state.sid
    if DSP.market.state.status == 'loading' then return end
    DSP.market.state.sid = sid
    DSP.market.state.status = 'loading'
    DSP.market.state.error = nil
    DSP.market.state.nick = DSP.player_nick()
    DSP.add_log('Запрос рынка Mobile ' .. tostring(sid) .. '...')
    DSP.flog('PULL start sid=' .. tostring(sid) .. ' nick=' .. DSP.player_nick())
    DSP.http_get(DSP.market.url(sid), function(body, err)
        if not body then
            DSP.flog('PULL error: ' .. tostring(err))
            DSP.market.state.status = 'error'
            DSP.market.state.error = tostring(err or 'ошибка')
            DSP.add_log('Рынок: ' .. DSP.market.state.error, 'error')
            if #DSP.market.state.rows == 0 and DSP.avg and DSP.avg.apply_to_market then
                if DSP.avg.apply_to_market(sid) then
                    DSP.add_log('Рынок: нет сети, использую офлайн-снимок средних цен ЦР', 'error')
                end
            end
            if done then done(false, err) end
            return
        end
        DSP.flog('PULL body bytes=' .. tostring(#body) .. ' head=' .. body:sub(1, 80):gsub('[\r\n]', ' '))
        local ok, payload = pcall(decodeJson, body)
        if not ok or type(payload) ~= 'table' then
            DSP.flog('PULL decode error: ' .. tostring(payload))
            DSP.market.state.status = 'error'
            DSP.market.state.error = 'JSON: ' .. tostring(payload)
            DSP.add_log('Рынок: JSON ' .. tostring(payload), 'error')
            if done then done(false, payload) end
            return
        end
        pcall(function() DSP.market.save_cache(sid, body) end)
        DSP.market.state.sid = sid
        DSP.settings.server = sid
        DSP.save_settings()
        DSP.market.rebuild(payload, sid)
        DSP.flog(string.format('PULL ok shops=%d offers=%d rows=%d newest=%d',
            DSP.market.state.shops, DSP.market.state.offers, #DSP.market.state.rows, DSP.market.state.updated))
        DSP.add_log(string.format('Рынок: %d лавок, %d офферов, свежесть %s',
            DSP.market.state.shops, DSP.market.state.offers, DSP.market.freshness()))
        if done then done(true) end
    end)
end

function DSP.market.save_cache(sid, body)
    local payload = encodeJson({ saved_at = os.time(), body = body })
    if not payload then return end
    local f = io.open(DSP.market_path(sid), 'w')
    if not f then return end
    f:write(payload)
    f:close()
end

function DSP.market.rebuild_legacy(pack, sid)
    local function side(src, asc)
        src = src or {}
        local min = tonumber(src.min) or 0
        local max = tonumber(src.max) or 0
        local n = tonumber(src.n) or #(src.offers or {})
        return {
            min = min, max = max,
            p25 = tonumber(src.p25) or min,
            med = tonumber(src.med) or min,
            p75 = tonumber(src.p75) or max,
            best = tonumber(src.best) or (asc and min or max),
            count = n, qty = tonumber(src.qty) or 0,
        }
    end
    local rows, map = {}, {}
    for _, it in ipairs(pack.items or {}) do
        local name = DSP.clean_text(it.name or it.key or '')
        if name ~= '' then
            local sell, buy = side(it.sell, true), side(it.buy, false)
            local key = DSP.item_key(name, 0)
            local row = {
                key = key, name = name, ench = 0,
                display = DSP.item_name(name, 0),
                sell = sell, buy = buy,
            }
            DSP.market.row_profit(row)
            rows[#rows + 1] = row
            map[key] = row
        end
    end
    table.sort(rows, function(a, b)
        if (a.profit or 0) ~= (b.profit or 0) then return (a.profit or 0) > (b.profit or 0) end
        return a.display < b.display
    end)
    DSP.market.state.rows = rows
    DSP.market.state.by_key = map
    DSP.market.state.sid = tonumber(sid) or DSP.market.state.sid
    DSP.market.state.shops = tonumber(pack.shops) or 0
    DSP.market.state.offers = tonumber(pack.offers) or 0
    DSP.market.state.updated = tonumber(pack.newest) or tonumber(pack.ts) or 0
    DSP.market.state.oldest = tonumber(pack.oldest) or 0
    DSP.market.state.version = DSP.market.state.version + 1
    DSP.market.state.filter_version = -1
    DSP.market.state.error = nil
    DSP.market.state.status = 'cache'
    DSP.market.state.shop_list = {}
    DSP.market.state.arb_version = -1
    if DSP.db and DSP.db.set_rows then
        local ok_db, err_db = pcall(DSP.db.set_rows, rows, sid)
        if not ok_db then DSP.flog('DB legacy error: ' .. tostring(err_db)) end
    end
end

function DSP.market.load_cache(sid)
    sid = tonumber(sid) or DSP.market.state.sid
    local f = io.open(DSP.market_path(sid), 'rb')
    if not f then return false end
    local raw = f:read('*a')
    f:close()
    local ok, pack = pcall(decodeJson, raw)
    if not ok or type(pack) ~= 'table' then return false end
    if type(pack.body) == 'string' then
        local ok2, payload = pcall(decodeJson, pack.body)
        if not ok2 or type(payload) ~= 'table' then return false end
        DSP.market.state.sid = sid
        DSP.market.rebuild(payload, sid)
        DSP.market.state.saved_at = tonumber(pack.saved_at) or 0
        DSP.market.state.status = 'cache'
        return true
    end
    if type(pack.items) == 'table' then
        DSP.market.rebuild_legacy(pack, sid)
        DSP.market.state.saved_at = tonumber(pack.ts) or 0
        return true
    end
    if type(pack.shops) == 'table' then
        DSP.market.rebuild(pack, sid)
        DSP.market.state.saved_at = tonumber(pack.saved_at) or 0
        DSP.market.state.status = 'cache'
        return true
    end
    return false
end

function DSP.market.filtered()
    local st = DSP.market.state
    if st.filter_version == st.version and st.filter_cache then
        return st.filter_cache
    end
    local q = DSP.lower(DSP.trim(DSP.ui and DSP.ui.search or ''))
    local out = {}
    for _, row in ipairs(st.rows) do
        local ok = true
        if q ~= '' and not DSP.lower(row.display):find(q, 1, true) then ok = false end
        if ok and DSP.settings.only_profit and (row.profit or 0) <= 0 then ok = false end
        if ok and DSP.settings.liquid then
            if row.sell.count < 2 or row.buy.count < 2 then ok = false end
        end
        if ok then out[#out + 1] = row end
    end
    local sort = tonumber(DSP.settings.sort) or 1
    table.sort(out, function(a, b)
        if sort == 2 then
            if (a.sell.best or 0) ~= (b.sell.best or 0) then return (a.sell.best or 0) < (b.sell.best or 0) end
        elseif sort == 3 then
            if (a.buy.best or 0) ~= (b.buy.best or 0) then return (a.buy.best or 0) > (b.buy.best or 0) end
        elseif sort == 4 then
            if (a.profit_pct or 0) ~= (b.profit_pct or 0) then return (a.profit_pct or 0) > (b.profit_pct or 0) end
        elseif sort == 5 then
            local an, bn = a.sell.count + a.buy.count, b.sell.count + b.buy.count
            if an ~= bn then return an > bn end
        else
            if (a.profit or 0) ~= (b.profit or 0) then return (a.profit or 0) > (b.profit or 0) end
        end
        return a.display < b.display
    end)
    st.filter_cache = out
    st.filter_version = st.version
    return out
end

-- Price for OUR buy preset: what we can pay a player so that reselling into
-- the best shop buy_slot still leaves `margin` % after CR commission.
function DSP.market.buy_target(row, margin)
    margin = tonumber(margin) or tonumber(DSP.settings.margin) or 10
    local resale = DSP.market.net(row and row.buy and row.buy.max or 0)
    if resale <= 0 then return 0 end
    return math.max(0, math.floor(resale * (1 - margin / 100)))
end

-- Price for OUR sell preset: slightly below the cheapest competing sell_slot,
-- but never below what the best shop would pay us directly (buy_slot max).
function DSP.market.sell_target(row, undercut)
    undercut = tonumber(undercut) or tonumber(DSP.settings.undercut) or 2
    local ask = row and row.sell and row.sell.min or 0
    local bid = row and row.buy and row.buy.max or 0
    local target = 0
    if ask > 0 then target = math.max(1, math.floor(ask * (1 - undercut / 100))) end
    if bid > target then target = bid end
    return target
end

function DSP.market.invalidate()
    DSP.market.state.filter_version = -1
    DSP.ui.page = 1
end

function DSP.market.row_for(name, ench)
    return DSP.market.state.by_key[DSP.item_key(name, ench)]
end

function DSP.market.load()
    local sid = DSP.detect_server() or DSP.settings.server or 102
    DSP.market.state.sid = sid
    if not DSP.market.load_cache(sid) then
        DSP.market.load_cache(102)
    end
    DSP.market.pull(sid)
end


-- ---------------------------------------------------------------------------
-- Anti-scam: a price that differs from the market median by more than
-- `scam_ratio` times (3x by default) in either direction is suspicious.
-- Returns true, ratio when suspicious.
function DSP.market.scam_check(name, ench, price, side)
    price = tonumber(price) or 0
    if price <= 0 then return false, 1 end
    local ratio_lim = tonumber(DSP.settings.scam_ratio) or 3
    if ratio_lim < 1.5 then ratio_lim = 1.5 end
    local row = DSP.market.row_for(name, ench)
    local ref = 0
    if row then
        local s = side == 'buy' and row.buy or row.sell
        if s and (s.count or 0) >= 3 then ref = s.med or 0 end
        if ref <= 0 and row.sell and (row.sell.count or 0) >= 3 then ref = row.sell.med or 0 end
    end
    if ref <= 0 and DSP.avg and DSP.avg.get then
        local a = DSP.avg.get(name)
        if a then ref = (side == 'buy' and a.buy or a.sell) or 0 end
    end
    if ref <= 0 then return false, 1 end
    local r = price > ref and price / ref or ref / price
    return r >= ratio_lim, r
end

-- ---------------------------------------------------------------------------
-- Arbitrage pairs: buy in shop A (A.sell_slots) -> sell to shop B (B.buy_slots).
-- Only sell_slots are ever used as a purchase source and only buy_slots as a
-- sale target; A and B must be different shops; only profit > 0 is returned.
function DSP.market.arbitrage()
    local st = DSP.market.state
    if st.arb_cache and st.arb_version == st.version then return st.arb_cache end
    local out = {}
    for _, row in ipairs(st.rows or {}) do
        local sells, buys = row.sell.offers or {}, row.buy.offers or {}
        if #sells > 0 and #buys > 0 then
            local per_item = 0
            for i = 1, math.min(#sells, 10) do
                local a = sells[i]
                local any = false
                for j = 1, math.min(#buys, 10) do
                    local b = buys[j]
                    local same = a.shop == b.shop and a.owner == b.owner
                    if not same then
                        local unit = DSP.market.profit(a.price, b.price)
                        if unit <= 0 then break end
                        any = true
                        local qa, qb = tonumber(a.qty) or 1, tonumber(b.qty) or 1
                        if qa < 1 then qa = 1 end
                        if qb < 1 then qb = 1 end
                        local qty = math.min(qa, qb)
                        local scam_a = DSP.market.scam_check(row.name, row.ench, a.price, 'sell')
                        local scam_b = DSP.market.scam_check(row.name, row.ench, b.price, 'buy')
                        out[#out + 1] = {
                            key = row.key, display = row.display, name = row.name, ench = row.ench,
                            buy_shop = a.shop, buy_owner = a.owner, buy_price = a.price, buy_qty = qa,
                            sell_shop = b.shop, sell_owner = b.owner, sell_price = b.price, sell_qty = qb,
                            unit = unit, qty = qty, total = unit * qty,
                            roi = a.price > 0 and (unit / a.price * 100) or 0,
                            scam = (scam_a or scam_b) and true or false,
                        }
                        per_item = per_item + 1
                        if per_item >= 6 then break end
                    end
                end
                if per_item >= 6 or DSP.market.profit(a.price, buys[1].price) <= 0 then break end
            end
        end
    end
    table.sort(out, function(x, y)
        if x.unit ~= y.unit then return x.unit > y.unit end
        if x.total ~= y.total then return x.total > y.total end
        if x.display ~= y.display then return x.display < y.display end
        if x.buy_shop ~= y.buy_shop then return tostring(x.buy_shop) < tostring(y.buy_shop) end
        return tostring(x.sell_shop) < tostring(y.sell_shop)
    end)
    st.arb_cache = out
    st.arb_version = st.version
    return out
end

function DSP.market.find_shop(shop_num, owner)
    for _, card in ipairs(DSP.market.state.shop_list or {}) do
        if tostring(card.shop_num) == tostring(shop_num)
            and (owner == nil or card.owner == owner) then
            return card
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Mark a shop: GPS command + 3D tracer target (drawn by DSP.tracer, 50_overlay).
DSP.tracer = DSP.tracer or { target = nil }

function DSP.market.mark_shop(shop_num, owner)
    shop_num = tostring(shop_num or '')
    if shop_num == '' or shop_num == '?' then
        DSP.notify('Нет номера лавки')
        return false
    end
    local cmd = '/findilavka ' .. shop_num
    if sampSendChat then pcall(sampSendChat, cmd) end
    DSP.tracer.target = {
        shop_num = shop_num,
        owner = owner and tostring(owner) or nil,
        since = os.time(),
        expires = os.time() + 180,
        pos = nil,
    }
    DSP.add_log('Метка: ' .. cmd .. (owner and (' (' .. tostring(owner) .. ')') or ''), 'ok')
    return true
end

end
__mod_10_market()

local function __mod_15_prices()
-- Persistent price base: API stats + learned shop observations.
DSP.db = DSP.db or {}
DSP.db.path = DSP.dir .. '/standalone_prices.json'
DSP.db.by_key = {}
DSP.db.by_base = {}
DSP.db.learned = {}
DSP.db.saved_at = 0
DSP.db.sid = 0
DSP.db.last_save = 0

local function zero_side()
    return { min = 0, max = 0, p25 = 0, med = 0, p75 = 0, best = 0, count = 0, qty = 0 }
end

local function copy_side(side)
    side = side or {}
    return {
        min = tonumber(side.min) or 0,
        max = tonumber(side.max) or 0,
        p25 = tonumber(side.p25) or 0,
        med = tonumber(side.med) or 0,
        p75 = tonumber(side.p75) or 0,
        best = tonumber(side.best) or 0,
        count = tonumber(side.count) or #(side.prices or {}),
        qty = tonumber(side.qty) or 0,
    }
end

function DSP.db.rebuild_base()
    local base = {}
    for key, e in pairs(DSP.db.by_key) do
        local b = DSP.lower(e.name or '')
        local old = base[b]
        local score = (e.sell and e.sell.count or 0) + (e.buy and e.buy.count or 0)
        local old_score = old and ((old.sell and old.sell.count or 0) + (old.buy and old.buy.count or 0)) or -1
        if not old or score > old_score or (score == old_score and (e.ench or 0) == 0) then
            base[b] = e
        end
    end
    DSP.db.by_base = base
end

function DSP.db.save(force)
    local now = os.clock()
    if not force and now - (DSP.db.last_save or 0) < 5 then return false end
    DSP.db.last_save = now
    DSP.db.saved_at = os.time()
    local pack = {
        saved_at = DSP.db.saved_at,
        sid = DSP.db.sid or 0,
        by_key = DSP.db.by_key,
        learned = DSP.db.learned,
    }
    local ok, json = pcall(encodeJson, pack)
    if not ok or not json then return false end
    local f = io.open(DSP.db.path, 'w')
    if not f then return false end
    f:write(json)
    f:close()
    return true
end

function DSP.db.set_rows(rows, sid)
    local map = {}
    local updated = DSP.market.state.updated or 0
    for _, r in ipairs(rows or {}) do
        map[r.key] = {
            key = r.key,
            name = r.name,
            ench = tonumber(r.ench) or 0,
            display = r.display,
            sell = copy_side(r.sell),
            buy = copy_side(r.buy),
            updated = updated,
            sid = tonumber(sid) or 0,
        }
    end
    DSP.db.by_key = map
    DSP.db.sid = tonumber(sid) or 0
    DSP.db.updated = updated
    DSP.db.rebuild_base()
    DSP.db.save(true)
    DSP.flog('DB rows=' .. tostring(#(rows or {})) .. ' sid=' .. tostring(sid))
end

function DSP.db.load()
    local f = io.open(DSP.db.path, 'rb')
    if not f then return false end
    local raw = f:read('*a') or ''
    f:close()
    local ok, pack = pcall(decodeJson, raw)
    if not ok or type(pack) ~= 'table' then return false end
    if type(pack.by_key) == 'table' then DSP.db.by_key = pack.by_key end
    if type(pack.learned) == 'table' then DSP.db.learned = pack.learned end
    DSP.db.saved_at = tonumber(pack.saved_at) or 0
    DSP.db.sid = tonumber(pack.sid) or 0
    DSP.db.rebuild_base()
    DSP.flog('DB loaded keys=' .. tostring((function() local n=0; for _ in pairs(DSP.db.by_key) do n=n+1 end; return n end)()))
    return true
end

function DSP.db.get(name, ench)
    name = DSP.clean_text(name or '')
    if name == '' or name:find('^ID:') then return nil, false, 'none' end
    ench = tonumber(ench) or 0
    if ench < 0 or ench > 20 then ench = 0 end
    local key = DSP.item_key(name, ench)
    local e = DSP.db.by_key[key]
    if e then return e, true, 'api' end
    local base = DSP.db.by_base[DSP.lower(name)]
    if base then return base, false, 'api_base' end
    e = DSP.db.learned[key]
    if e then return e, true, 'shop' end
    e = DSP.db.learned[DSP.item_key(name, 0)]
    if e then return e, false, 'shop_base' end
    return nil, false, 'none'
end

function DSP.db.learn(raw, ench, price, side)
    price = tonumber(price) or 0
    if price <= 0 then return end
    local disp, id, e = DSP.items.display(raw, ench)
    local name = DSP.items.name(id)
    if not name or name == '' or name:find('^ID:') then return end
    local key = DSP.item_key(name, e)
    local entry = DSP.db.learned[key]
    if not entry then
        entry = {
            key = key,
            name = name,
            display = disp,
            ench = e,
            sell = zero_side(),
            buy = zero_side(),
            updated = os.time(),
            sid = DSP.market.state.sid or 0,
        }
        DSP.db.learned[key] = entry
    end
    entry.updated = os.time()
    if side == 'sell' then
        if entry.sell.min <= 0 or price < entry.sell.min then entry.sell.min = price end
        entry.sell.best = entry.sell.min
        entry.sell.med = entry.sell.min
        entry.sell.count = (entry.sell.count or 0) + 1
    else
        if price > entry.buy.max then entry.buy.max = price end
        entry.buy.best = entry.buy.max
        entry.buy.med = entry.buy.max
        entry.buy.count = (entry.buy.count or 0) + 1
    end
    DSP.db.save(false)
end

function DSP.db.freshness()
    local ts = DSP.db.updated or DSP.db.saved_at or 0
    if ts <= 0 then return 'нет базы' end
    local age = math.max(0, os.time() - ts)
    if age < 60 then return age .. ' сек' end
    if age < 3600 then return math.floor(age / 60) .. ' мин' end
    if age < 86400 then return math.floor(age / 3600) .. ' ч' end
    return math.floor(age / 86400) .. ' дн'
end

-- ---------------------------------------------------------------------------
-- Offline source #2: CR average-price pickup (dialog 15073, "Средняя цена товаров").
-- Auto-pages through "Следующая страница", stores a snapshot in
-- config/PalatkaAI/prices_server_{SID}.json and is used when the API is down.
DSP.avg = DSP.avg or { items = {}, sid = 0, saved_at = 0, scanning = false, pages = 0 }
DSP.avg.DIALOG_ID = 15073

local function avg_dir()
    local root = (getWorkingDirectory() or '.'):gsub('\\', '/'):gsub('/$', '')
    DSP.mkdir(root .. '/config')
    DSP.mkdir(root .. '/config/PalatkaAI')
    return root .. '/config/PalatkaAI'
end

function DSP.avg.path(sid)
    return avg_dir() .. '/prices_server_' .. tostring(tonumber(sid) or 0) .. '.json'
end

local function num(s)
    local d = tostring(s or ''):gsub('[^%d]', '')
    return tonumber(d) or 0
end

-- Parse one page. Returns list of {name, sell, buy, volume} and next-page index or nil.
function DSP.avg.parse_page(style, text)
    local out, next_idx = {}, nil
    local idx = 0
    local first = true
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        local is_header = first and tonumber(style) == 5
        first = false
        if not is_header then
            local clean = DSP.clean_text(line)
            if clean:find('Следующая страница', 1, true) then
                next_idx = idx
            elseif not clean:find('Предыдущая страница', 1, true) then
                local cols = {}
                for c in (clean .. '\t'):gmatch('([^\t]*)\t') do cols[#cols + 1] = DSP.trim(c) end
                local name = cols[1] or ''
                local nums = {}
                for i = 2, #cols do
                    local v = num(cols[i])
                    if v > 0 then nums[#nums + 1] = v end
                end
                if name ~= '' and #nums > 0 then
                    out[#out + 1] = { name = name, sell = nums[1] or 0, buy = nums[2] or 0, volume = nums[3] or 0 }
                end
            end
            idx = idx + 1
        end
    end
    return out, next_idx
end

function DSP.avg.save(sid)
    sid = tonumber(sid) or DSP.avg.sid or 0
    local list = {}
    for _, it in pairs(DSP.avg.items) do list[#list + 1] = it end
    local ok, json = pcall(encodeJson, { saved_at = os.time(), sid = sid, items = list })
    if not ok or not json then return false end
    local f = io.open(DSP.avg.path(sid), 'w')
    if not f then return false end
    f:write(json)
    f:close()
    DSP.avg.saved_at = os.time()
    return true
end

function DSP.avg.load(sid)
    sid = tonumber(sid) or (DSP.market and DSP.market.state.sid) or 0
    local f = io.open(DSP.avg.path(sid), 'rb')
    if not f then return false end
    local raw = f:read('*a')
    f:close()
    local ok, pack = pcall(decodeJson, raw)
    if not ok or type(pack) ~= 'table' or type(pack.items) ~= 'table' then return false end
    DSP.avg.items = {}
    for _, it in ipairs(pack.items) do
        if type(it) == 'table' and it.name then DSP.avg.items[DSP.lower(it.name)] = it end
    end
    DSP.avg.sid = sid
    DSP.avg.saved_at = tonumber(pack.saved_at) or 0
    return true
end

function DSP.avg.get(name)
    if not name then return nil end
    return DSP.avg.items[DSP.lower(DSP.clean_text(name))]
end

function DSP.avg.count()
    local n = 0
    for _ in pairs(DSP.avg.items) do n = n + 1 end
    return n
end

-- Build market rows from the snapshot (used when the API is unavailable).
function DSP.avg.apply_to_market(sid)
    if DSP.avg.count() == 0 and not DSP.avg.load(sid) then return false end
    local items = {}
    for _, it in pairs(DSP.avg.items) do
        items[#items + 1] = {
            name = it.name,
            sell = { min = it.sell, max = it.sell, med = it.sell, n = it.sell > 0 and 1 or 0 },
            buy = { min = it.buy, max = it.buy, med = it.buy, n = it.buy > 0 and 1 or 0 },
        }
    end
    if #items == 0 then return false end
    DSP.market.rebuild_legacy({ items = items, ts = DSP.avg.saved_at, newest = DSP.avg.saved_at }, sid)
    DSP.market.state.status = 'offline'
    return true
end

function DSP.avg.on_dialog(id, style, title, text)
    local t = DSP.clean_text(title or '')
    if id ~= DSP.avg.DIALOG_ID and not t:find('Средняя цена', 1, true) then return false end
    local page, next_idx = DSP.avg.parse_page(style, text)
    local sid = (DSP.market and DSP.market.state.sid) or DSP.settings.server or 0
    if DSP.avg.sid ~= sid then DSP.avg.items = {}; DSP.avg.sid = sid; DSP.avg.pages = 0 end
    for _, it in ipairs(page) do DSP.avg.items[DSP.lower(it.name)] = it end
    DSP.avg.pages = (DSP.avg.pages or 0) + 1
    DSP.avg.save(sid)
    DSP.add_log('Средние цены ЦР: стр. ' .. DSP.avg.pages .. ', всего ' .. DSP.avg.count() .. ' товаров', 'ok')
    if next_idx and DSP.settings.avg_autoscan ~= false and lua_thread and sampSendDialogResponse then
        DSP.avg.scanning = true
        lua_thread.create(function()
            wait((tonumber(DSP.settings.delay_ms) or 500) + math.random(50, 120))
            pcall(sampSendDialogResponse, id, 1, next_idx, '')
        end)
    else
        DSP.avg.scanning = false
    end
    return true
end

end
__mod_15_prices()

local function __mod_05_trades()
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

-- ---------------------------------------------------------------------------
-- Helpers declared BEFORE any use (a `local function` is only visible below
-- its definition; calling it earlier resolves to a nil global and crashes).
local function name_ench(s)
    s = DSP.clean_text(s or '')
    local base, e = s:match('^(.-)%s*%(%+(%d+)%)%s*$')
    if base and base ~= '' then return base, tonumber(e) or 0 end
    return s, 0
end

local function url_encode(s)
    if not s then return '' end
    s = tostring(s):gsub('([^%w%.%-_~])', function(c)
        return string.format('%%%02X', string.byte(c))
    end)
    return s
end

local TG_EVENTS = { sales = true, kick = true, drops = true, admin = true, trades = true, manual = true }

DSP.settings.tg_events = type(DSP.settings.tg_events) == 'table' and DSP.settings.tg_events or {}
for k, _ in pairs(TG_EVENTS) do
    if DSP.settings.tg_events[k] == nil then DSP.settings.tg_events[k] = (k ~= 'admin') end
end

-- Build the Telegram sendMessage URL. Game strings are CP1251; Telegram only
-- accepts UTF-8, so the text is converted exactly once here.
function DSP.logs.tg_url(msg)
    local token = DSP.trim(DSP.settings.tg_bot_token or '')
    local chat = DSP.trim(DSP.settings.tg_chat_id or '')
    if token == '' or chat == '' then return nil end
    local text = DSP.to_u8(tostring(msg or ''))
    return 'https://api.telegram.org/bot' .. token
        .. '/sendMessage?chat_id=' .. url_encode(chat)
        .. '&disable_web_page_preview=1'
        .. '&text=' .. url_encode(text)
end

-- event: 'sales' | 'kick' | 'drops' | 'admin' | 'trades' | 'manual'
local function send_telegram(msg, event)
    if not DSP.settings.tg_notify then return false end
    event = event or 'manual'
    if event ~= 'manual' and DSP.settings.tg_events[event] == false then return false end
    local url = DSP.logs.tg_url(msg)
    if not url then return false end
    if DSP.http_get then
        -- async (effil thread + lua_thread polling): no game micro-freezes
        local ok = pcall(DSP.http_get, url, function(body, err)
            if not body then DSP.flog('TG error: ' .. tostring(err)) end
        end)
        return ok
    end
    return false
end

-- Market value of an item: what a shop pays (best buy_slot), else cheapest ask.
local function value_of(name, ench, qty)
    qty = math.max(1, tonumber(qty) or 1)
    local e = DSP.db and DSP.db.get and DSP.db.get(name, ench)
    local unit = 0
    if e then
        if e.buy and (e.buy.max or 0) > 0 then unit = e.buy.max
        elseif e.sell and (e.sell.min or 0) > 0 then unit = e.sell.min end
    end
    if unit <= 0 and DSP.avg and DSP.avg.get then
        local a = DSP.avg.get(name)
        if a then unit = (a.buy and a.buy > 0) and a.buy or (a.sell or 0) end
    end
    return unit * qty, unit
end

-- Cost of one crate/stash: the cheapest place to buy it (sell_slot min).
local function crate_cost(crate)
    local e = DSP.db and DSP.db.get and DSP.db.get(crate, 0)
    if e and e.sell and (e.sell.min or 0) > 0 then return e.sell.min end
    if e and e.buy and (e.buy.max or 0) > 0 then return e.buy.max end
    if DSP.avg and DSP.avg.get then
        local a = DSP.avg.get(crate)
        if a then return (a.sell and a.sell > 0) and a.sell or (a.buy or 0) end
    end
    return 0
end

DSP.logs.session = DSP.logs.session or { started = os.time(), opens = {}, open_n = 0, spent = 0, value = 0, drops = {} }

function DSP.logs.reset_session()
    DSP.logs.session = { started = os.time(), opens = {}, open_n = 0, spent = 0, value = 0, drops = {} }
end

local last_save = 0
local function save_soon(force)
    local now = os.time()
    if force or now - last_save >= 5 then
        last_save = now
        DSP.db.save_trades()
    end
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
        send_telegram(msg, 'trades')
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

function DSP.logs.crate_opened(item_name, price, count, crate, ench)
    count = math.max(1, tonumber(count) or 1)
    ench = tonumber(ench) or 0
    local total, unit = value_of(item_name, ench, count)
    if (tonumber(price) or 0) > 0 then unit = tonumber(price); total = unit * count end
    local entry = {
        type = 'crate',
        ts = os.time(),
        item_name = tostring(item_name or ''),
        ench = ench,
        crate = crate and tostring(crate) or nil,
        price = unit or 0,
        value = total or 0,
        count = count,
        server = DSP.settings.server or 102,
    }
    local k = tostring(entry.ts)
    while DSP.settings.crates[k] do k = k .. '_' end
    DSP.settings.crates[k] = entry
    table.insert(DSP.logs.crate_logs, 1, entry)
    -- session payback: spent (crate price) vs dropped (market value)
    local ss = DSP.logs.session
    if crate and crate ~= '' then
        ss.opens[crate] = (ss.opens[crate] or 0) + 1
        ss.open_n = ss.open_n + 1
        ss.spent = ss.spent + crate_cost(crate)
    end
    ss.value = ss.value + (entry.value or 0)
    table.insert(ss.drops, 1, entry)
    while #ss.drops > 200 do table.remove(ss.drops) end
    save_soon()
    DSP.add_log('Дроп: +' .. tostring(count) .. 'x ' .. tostring(item_name)
        .. (crate and (' из ' .. crate) or '') .. ' ~ ' .. DSP.money(entry.value), 'ok')
    send_telegram('[palatka ai] Дроп: +' .. tostring(count) .. 'x ' .. DSP.item_name(item_name, ench)
        .. (crate and (' из ' .. crate) or '') .. ' (~' .. DSP.money(entry.value) .. ')', 'drops')
    return entry
end

function DSP.logs.session_summary()
    local ss = DSP.logs.session
    return { opens = ss.opens, open_n = ss.open_n, spent = ss.spent, value = ss.value,
        profit = ss.value - ss.spent, drops = ss.drops, started = ss.started }
end

local function day_key(ts, mode)
    if mode == 'hour' then return os.date('%Y-%m-%d %H:00', ts) end
    if mode == 'day' then return os.date('%Y-%m-%d', ts) end
    if mode == 'week' then
        local d = os.date('*t', ts)
        local w = math.floor((d.yday - 1) / 7) + 1
        return string.format('%04d-W%02d', d.year, w)
    end
    if mode == 'month' then
        local d = os.date('*t', ts)
        return string.format('%04d-%02d', d.year, d.month)
    end
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

-- ---------------------------------------------------------------------------
-- Server message parsers (sampev.onServerMessage(color, text), CP1251 text).
-- Patterns from PALATKA_AI_MASTER_PROMPT.md section 5, tab 5.
local function money_num(s)
    local digits = tostring(s or ''):gsub('[^%d]', '')
    return tonumber(digits) or 0
end

local function strip_prefix(s)
    s = DSP.clean_text(s or '')
    -- drop leading tags like "[Информация]" / "[Лавка]" / "(( ... ))"
    for _ = 1, 3 do
        local rest = s:match('^%b[]%s*(.+)$')
        if not rest then break end
        s = rest
    end
    return s
end

local function split_qty(item)
    item = DSP.trim(item or '')
    local nm, q = item:match('^(.-)%s*%((%d+)%s*шт%.?%)$')
    if nm then return DSP.trim(nm), tonumber(q) or 1 end
    nm, q = item:match('^(.-)%s*[xXхХ]%s*(%d+)$')
    if nm then return DSP.trim(nm), tonumber(q) or 1 end
    return item, 1
end

-- Returns an event table or nil.
function DSP.logs.parse_server_message(text)
    local s = strip_prefix(text)
    if s == '' then return nil end
    local buyer, item, qty, money = s:match('^(.+) купил у вас (.+) %((%d+) шт%.%), вы получили %$([%d%.,%s]+)')
    if buyer then
        return { kind = 'sale', partner = DSP.trim(buyer), item = DSP.trim(item), qty = tonumber(qty) or 1, money = money_num(money) }
    end
    local item2, qty2, seller, money2 = s:match('^Вы купили (.+) %((%d+) шт%.%) у игрока (.+) за %$([%d%.,%s]+)')
    if item2 then
        return { kind = 'purchase', partner = DSP.trim(seller), item = DSP.trim(item2), qty = tonumber(qty2) or 1, money = money_num(money2) }
    end
    local crate, item3, qty3 = s:match('^Вам выпало из (.+): (.+) %((%d+) шт%.%)')
    if crate then
        return { kind = 'drop', crate = DSP.trim(crate), item = DSP.trim(item3), qty = tonumber(qty3) or 1 }
    end
    local crate4, rest = s:match('^Вы открыли (.+) и получили (.+)$')
    if crate4 then
        local nm, q = split_qty((rest:gsub('[%.!]+$', '')))
        return { kind = 'drop', crate = DSP.trim(crate4), item = nm, qty = q }
    end
    local low = DSP.lower(s)
    if low:find('лавк', 1, true) and (low:find('кикнут', 1, true) or low:find('закрыт', 1, true)
        or low:find('истекл', 1, true) or low:find('слетел', 1, true) or low:find('освобожден', 1, true)) then
        return { kind = 'kick', text = s }
    end
    if low:find('администратор', 1, true) and (low:find('телепорт', 1, true) or low:find('рядом', 1, true)
        or low:find('слежк', 1, true) or low:find('наблюд', 1, true)) then
        return { kind = 'admin', text = s }
    end
    return nil
end

-- Backward compatible: only drop events.
function DSP.logs.parse_chat_drop(text)
    local ev = DSP.logs.parse_server_message(text)
    if not ev or ev.kind ~= 'drop' then return nil end
    local base, ench = name_ench(ev.item)
    return { name = base, ench = ench, qty = ev.qty, crate = ev.crate }
end

local function push_chat_log(kind, text)
    table.insert(DSP.settings.chat_logs, { ts = os.time(), text = text, kind = kind })
    while #DSP.settings.chat_logs > 500 do table.remove(DSP.settings.chat_logs, 1) end
end

function DSP.logs.record_sale(ev)
    DSP.settings.sales = type(DSP.settings.sales) == 'table' and DSP.settings.sales or {}
    local base, ench = name_ench(ev.item)
    local e = { ts = os.time(), kind = ev.kind, partner = ev.partner, item = base, ench = ench,
        qty = ev.qty, money = ev.money }
    table.insert(DSP.settings.sales, 1, e)
    while #DSP.settings.sales > 1000 do table.remove(DSP.settings.sales) end
    if ev.kind == 'sale' then
        DSP.add_log('Продажа: ' .. ev.item .. ' x' .. ev.qty .. ' -> ' .. ev.partner .. ' +' .. DSP.money(ev.money), 'ok')
        send_telegram('[palatka ai] Продано: ' .. ev.item .. ' x' .. ev.qty .. ' игроку ' .. ev.partner
            .. ', получено ' .. DSP.money(ev.money), 'sales')
    else
        DSP.add_log('Покупка: ' .. ev.item .. ' x' .. ev.qty .. ' у ' .. ev.partner .. ' -' .. DSP.money(ev.money))
        send_telegram('[palatka ai] Куплено: ' .. ev.item .. ' x' .. ev.qty .. ' у ' .. ev.partner
            .. ' за ' .. DSP.money(ev.money), 'sales')
    end
    return e
end

-- Entry point for every server message. Returns the parsed event (or nil).
function DSP.logs.on_server_message(color, text)
    local ev = DSP.logs.parse_server_message(text)
    if not ev then return nil end
    if ev.kind == 'sale' or ev.kind == 'purchase' then
        DSP.logs.record_sale(ev)
        push_chat_log(ev.kind, strip_prefix(text))
        save_soon()
    elseif ev.kind == 'drop' then
        if DSP.settings.log_chat_drops ~= false then
            local base, ench = name_ench(ev.item)
            DSP.logs.crate_opened(base, 0, ev.qty, ev.crate, ench)
            push_chat_log('drop', strip_prefix(text))
        end
    elseif ev.kind == 'kick' then
        push_chat_log('kick', ev.text)
        DSP.add_log('Лавка: ' .. ev.text, 'error')
        send_telegram('[palatka ai] Лавка: ' .. ev.text, 'kick')
        save_soon()
    elseif ev.kind == 'admin' then
        push_chat_log('admin', ev.text)
        DSP.add_log('Админ: ' .. ev.text, 'error')
        send_telegram('[palatka ai] Админ: ' .. ev.text, 'admin')
    end
    return ev
end

-- Kept for older callers.
function DSP.logs.log_chat(text)
    return DSP.logs.on_server_message(-1, text)
end

function DSP.logs.send_telegram(msg, event)
    return send_telegram(msg, event or 'manual')
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
    local ok, sampev = pcall(require, 'samp.events')
    if not ok or not sampev then return end
    DSP.logs.installed = true
    -- System messages (sales, drops, kicks) arrive via onServerMessage(color, text),
    -- not onChatMessage (that one is player chat: playerId, text).
    local prev = sampev.onServerMessage
    sampev.onServerMessage = function(color, text)
        local okp, err = pcall(DSP.logs.on_server_message, color, text)
        if not okp then DSP.flog('LOGS parse error: ' .. tostring(err)) end
        if prev then return prev(color, text) end
    end
    DSP.flog('LOGS onServerMessage hook installed')
end

function DSP.logs.load()
    DSP.db.load_trades()
end

return true

end
__mod_05_trades()

local function __mod_20_presets()
-- Own buy/sell presets, independent from Market Helper.
DSP.presets = {}

local function preset(kind)
    if kind == 'sell' then return DSP.settings.sell_preset end
    return DSP.settings.buy_preset
end

function DSP.presets.items(kind)
    return preset(kind).items
end

function DSP.presets.find(kind, key)
    for i, it in ipairs(preset(kind).items) do
        if it.key == key or DSP.item_key(it.name, it.ench) == key then return i, it end
    end
    return nil
end

function DSP.presets.add(row, kind)
    if not row then return false, 'нет выбранного товара' end
    kind = kind == 'sell' and 'sell' or 'buy'
    local p = preset(kind)
    local price
    if kind == 'buy' then
        price = DSP.market.buy_target(row)
    else
        price = DSP.market.sell_target(row)
    end
    if price <= 0 then return false, 'нет цены для расчёта' end
    local idx, it = DSP.presets.find(kind, row.key)
    if it then
        it.price = price
        it.name = row.display
        it.ench = row.ench
        it.enabled = true
        DSP.save_settings()
        DSP.add_log('Обновлено в ' .. p.name .. ': ' .. row.display)
        return true
    end
    table.insert(p.items, {
        key = row.key,
        name = row.display,
        ench = row.ench or 0,
        price = price,
        qty = 1,
        enabled = true,
    })
    DSP.save_settings()
    DSP.add_log('Добавлено в ' .. p.name .. ': ' .. row.display .. ' по ' .. DSP.money(price))
    return true
end

function DSP.presets.remove(kind, idx)
    local p = preset(kind)
    local it = table.remove(p.items, idx)
    if it then
        DSP.save_settings()
        DSP.add_log('Удалено из ' .. p.name .. ': ' .. it.name)
    end
end

function DSP.presets.clear(kind)
    local p = preset(kind)
    p.items = {}
    DSP.save_settings()
    DSP.add_log(p.name .. ': список очищен')
end

function DSP.presets.recalc(kind)
    local p = preset(kind)
    local changed, missing = 0, 0
    for _, it in ipairs(p.items) do
        local row = DSP.market.row_for(it.name, it.ench)
        if not row then
            local base = it.name:gsub('%s+%(%+%d+%)$', '')
            row = DSP.market.row_for(base, it.ench)
        end
        if row then
            local price
            if kind == 'buy' then
                price = DSP.market.buy_target(row)
            else
                price = DSP.market.sell_target(row)
            end
            if price > 0 then
                it.price = price
                it.key = row.key
                changed = changed + 1
            else
                missing = missing + 1
            end
        else
            missing = missing + 1
        end
    end
    DSP.save_settings()
    DSP.add_log(string.format('%s: пересчитано %d, без данных %d', p.name, changed, missing))
    return changed, missing
end

function DSP.presets.find_row(it)
    local row = DSP.market.row_for(it.name, it.ench)
    if not row then
        local base = it.name:gsub('%s+%(%+%d+%)$', '')
        row = DSP.market.row_for(base, it.ench)
    end
    return row
end

function DSP.presets.estimate(it, kind)
    local row = DSP.presets.find_row(it)
    if not row then return nil end
    if kind == 'buy' then
        -- We buy from players at it.price and resell into the best shop buy_slot.
        if (row.buy.max or 0) <= 0 then return nil end
        return (DSP.market.net(row.buy.max) - it.price) * (it.qty or 1), row
    end
    -- We sell at it.price; the alternative is buying it at the cheapest sell_slot.
    if (row.sell.min or 0) <= 0 then return nil end
    return (DSP.market.net(it.price) - row.sell.min) * (it.qty or 1), row
end

function DSP.presets.active_count(kind)
    local n = 0
    for _, it in ipairs(preset(kind).items) do
        if it.enabled then n = n + 1 end
    end
    return n
end

function DSP.presets.import_mh()
    local candidates = {
        (getWorkingDirectory():gsub('\\', '/')) .. '/MarketHelper/MarketHelper_settings.json',
        (getWorkingDirectory():gsub('\\', '/')) .. '/MarketHelper/settings.json',
    }
    local raw
    for _, path in ipairs(candidates) do
        local f = io.open(path, 'rb')
        if f then raw = f:read('*a'); f:close(); break end
    end
    if not raw then return false, 'настройки Market Helper не найдены' end
    local ok, d = pcall(decodeJson, raw)
    if not ok or type(d) ~= 'table' then return false, 'не удалось прочитать JSON' end
    local imported = 0
    local function pull(src, kind)
        if type(src) ~= 'table' then return end
        for _, it in ipairs(src) do
            local name = it.name or it.nm or it.item
            local ench = tonumber(it.ench or it.enchant or 0) or 0
            local price = tonumber(it.price or it.max_price or it.maxPrice or 0) or 0
            local qty = tonumber(it.qty or it.count or 1) or 1
            if name and price > 0 then
                local key = DSP.item_key(DSP.text_cp(name), ench)
                local idx = DSP.presets.find(kind, key)
                if not idx then
                    table.insert(preset(kind).items, {
                        key = key,
                        name = DSP.item_name(DSP.text_cp(name), ench),
                        ench = ench,
                        price = price,
                        qty = qty,
                        enabled = it.enabled ~= false,
                    })
                    imported = imported + 1
                end
            end
        end
    end
    pull(d.buy_preset and d.buy_preset.items, 'buy')
    pull(d.sell_preset and d.sell_preset.items, 'sell')
    pull(d.autobuy_items, 'buy')
    pull(d.autosell_items, 'sell')
    if imported == 0 then return false, 'в настройках MH нет подходящих списков' end
    DSP.save_settings()
    DSP.add_log('Импорт из Market Helper: ' .. imported .. ' поз.')
    return true, imported
end


-- ---------------------------------------------------------------------------
-- Named preset library (section 5, tab 1): [Скупка: Ресурсы], [Скупка: Ларцы],
-- [Продажа: Склад] + presets copied from other shops. The active working sets
-- remain DSP.settings.buy_preset / sell_preset (used by the auto engine).
local function deep_items(items)
    local out = {}
    for _, it in ipairs(items or {}) do
        out[#out + 1] = {
            key = it.key, name = it.name, ench = it.ench or 0,
            price = tonumber(it.price) or 0, qty = tonumber(it.qty) or 1,
            enabled = it.enabled ~= false,
        }
    end
    return out
end

function DSP.presets.library()
    local lib = DSP.settings.preset_lib
    if type(lib) ~= 'table' or #lib == 0 then
        lib = {
            { name = 'Скупка: Ресурсы', kind = 'buy', items = {} },
            { name = 'Скупка: Ларцы', kind = 'buy', items = {} },
            { name = 'Продажа: Склад', kind = 'sell', items = {} },
        }
        DSP.settings.preset_lib = lib
    end
    return lib
end

function DSP.presets.lib_find(name)
    for i, p in ipairs(DSP.presets.library()) do
        if p.name == name then return i, p end
    end
    return nil
end

-- Make a library preset the active working set of its kind.
function DSP.presets.activate(idx)
    local p = DSP.presets.library()[idx]
    if not p then return false, 'нет пресета' end
    local kind = p.kind == 'sell' and 'sell' or 'buy'
    local target = { name = p.name, items = deep_items(p.items) }
    if kind == 'sell' then DSP.settings.sell_preset = target else DSP.settings.buy_preset = target end
    DSP.settings.active_preset = DSP.settings.active_preset or {}
    DSP.settings.active_preset[kind] = p.name
    DSP.save_settings()
    DSP.add_log('Активный пресет: ' .. p.name .. ' (' .. #target.items .. ' поз.)', 'ok')
    return true, kind
end

-- Save the active working set back into the library (create or overwrite).
function DSP.presets.save_active(kind, name)
    kind = kind == 'sell' and 'sell' or 'buy'
    local src = preset(kind)
    name = DSP.trim(name or src.name or '')
    if name == '' then name = kind == 'sell' and 'Продажа' or 'Скупка' end
    local idx, p = DSP.presets.lib_find(name)
    if p then
        p.items = deep_items(src.items)
        p.kind = kind
    else
        table.insert(DSP.presets.library(), { name = name, kind = kind, items = deep_items(src.items) })
    end
    src.name = name
    DSP.save_settings()
    return true
end

-- Copy a shop's buy_slots (what that shop BUYS) into a new buy preset.
-- bump: 0, 1 or 1000 -> outbid every price by that amount.
-- Returns ok, preset_or_error.
function DSP.presets.copy_shop_buy(card, name, bump)
    if type(card) ~= 'table' then return false, 'нет лавки' end
    local slots = card.buy or {}
    if #slots == 0 then return false, 'эта лавка ничего не скупает' end
    bump = math.max(0, math.floor(tonumber(bump) or 0))
    name = DSP.trim(name or '')
    if name == '' then name = 'Скупка_' .. tostring(card.owner or '?') end
    local items, seen = {}, {}
    for _, sl in ipairs(slots) do
        local nm = DSP.trim(sl.name or '')
        local price = math.floor(tonumber(sl.price) or 0)
        if nm ~= '' and price > 0 then
            local ench = tonumber(sl.ench) or 0
            local key = DSP.item_key(nm, ench)
            if seen[key] then
                local it = items[seen[key]]
                if price + bump > it.price then it.price = price + bump end
                it.qty = it.qty + math.max(1, tonumber(sl.qty) or 1)
            else
                items[#items + 1] = {
                    key = key, name = DSP.item_name(nm, ench), ench = ench,
                    price = price + bump, qty = math.max(1, tonumber(sl.qty) or 1),
                    enabled = true,
                }
                seen[key] = #items
            end
        end
    end
    if #items == 0 then return false, 'нет валидных позиций' end
    local idx, p = DSP.presets.lib_find(name)
    if p then
        p.items, p.kind = items, 'buy'
    else
        table.insert(DSP.presets.library(), { name = name, kind = 'buy', items = items })
        idx = #DSP.presets.library()
    end
    DSP.presets.activate(idx)
    DSP.add_log('Скупка скопирована: ' .. name .. ' (' .. #items .. ' поз.' .. (bump > 0 and (', +' .. bump .. '$') or '') .. ')', 'ok')
    return true, DSP.presets.library()[idx]
end

-- Add an item from the catalog with a manual price/qty.
function DSP.presets.add_manual(kind, name, ench, price, qty)
    kind = kind == 'sell' and 'sell' or 'buy'
    name = DSP.trim(name or '')
    price = math.floor(tonumber(price) or 0)
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    if name == '' then return false, 'нет названия' end
    if price <= 0 then return false, 'цена должна быть > 0' end
    ench = tonumber(ench) or 0
    local key = DSP.item_key(name, ench)
    local p = preset(kind)
    local _, it = DSP.presets.find(kind, key)
    if it then
        it.price, it.qty, it.enabled = price, qty, true
    else
        table.insert(p.items, { key = key, name = DSP.item_name(name, ench), ench = ench,
            price = price, qty = qty, enabled = true })
    end
    DSP.save_settings()
    DSP.add_log('Каталог -> ' .. (kind == 'buy' and 'скупка' or 'продажа') .. ': ' .. name .. ' ' .. DSP.money(price) .. ' x' .. qty, 'ok')
    return true
end

-- Money needed to fill the whole active buy preset.
function DSP.presets.budget(kind)
    local total = 0
    for _, it in ipairs(preset(kind or 'buy').items) do
        if it.enabled ~= false then
            total = total + (tonumber(it.price) or 0) * math.max(1, tonumber(it.qty) or 1)
        end
    end
    return total
end

end
__mod_20_presets()

local function __mod_30_ui()
-- Clickable DS-market style UI.
local ffi = require('ffi')

local function count_keys(t)
    if not t then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function to_sorted_array(t)
    local arr = {}
    if type(t) == 'table' then
        for _, v in pairs(t) do
            if type(v) == 'table' then arr[#arr + 1] = v end
        end
    end
    table.sort(arr, function(a, b)
        return (a.ts or 0) < (b.ts or 0)
    end)
    return arr
end

DSP.ui = DSP.ui or {}
DSP.ui.open = false
DSP.ui.tab = 1
DSP.ui.search = ''
DSP.ui.selected = nil
DSP.ui.page = 1
DSP.ui.preset_kind = 'buy'
DSP.ui.margin_dirty = false
DSP.ui.d = 1.0
DSP.ui.search_buf = nil
DSP.ui.open_ref = nil
DSP.ui.chk = {}
DSP.ui.calc_buy = 1000
DSP.ui.calc_sell = 1000
DSP.ui.calc_qty = 1
DSP.ui.stat_mode = 'day'
DSP.ui.tab_detail = 'trades'

local ACC = DSP.acc

local function col(r, g, b, a)
    return imgui.ImVec4(r, g, b, a or 1)
end

local function acc_col(a)
    return col(ACC[1], ACC[2], ACC[3], a)
end

local function d()
    return DSP.ui.d or 1.0
end

-- Touch target height: minimum 40 * dpi (spec section 3.3)
local function bh()
    return 40 * (DSP.ui.d or 1.0)
end
DSP.ui.bh = bh

-- Static (persistent) imgui bool refs: never allocated per frame.
DSP.ui.refs = DSP.ui.refs or {}
local function ref_bool(key, value)
    local r = DSP.ui.refs[key]
    if not r then
        r = imgui.new.bool(value and true or false)
        DSP.ui.refs[key] = r
    else
        r[0] = value and true or false
    end
    return r
end
DSP.ui.ref_bool = ref_bool

-- Adaptive DPI (spec section 3.1); manual override 0.8x..1.5x from settings.
function DSP.ui.compute_dpi()
    if DSP.settings.dpi_auto == false then
        return DSP.clamp(tonumber(DSP.settings.dpi) or 1.0, 0.8, 1.5)
    end
    local dpi = 1.0
    if MONET_DPI_SCALE ~= nil then
        dpi = tonumber(MONET_DPI_SCALE) or 1.0
    elseif getScreenResolution then
        local ok, sw = pcall(getScreenResolution)
        sw = ok and tonumber(sw) or 0
        dpi = sw > 1920 and 1.3 or (sw > 1280 and 1.1 or 1.0)
    end
    return DSP.clamp(dpi, 0.8, 2.0)
end

function DSP.ui.screen_size()
    local sw, sh = 0, 0
    if getScreenResolution then
        local ok, w, h = pcall(getScreenResolution)
        if ok then sw, sh = tonumber(w) or 0, tonumber(h) or 0 end
    end
    if (sw <= 0 or sh <= 0) and imgui.GetIO then
        local ok, io = pcall(imgui.GetIO)
        if ok and io and io.DisplaySize then sw, sh = io.DisplaySize.x or 0, io.DisplaySize.y or 0 end
    end
    if sw <= 0 then sw = 2340 end
    if sh <= 0 then sh = 1080 end
    return sw, sh
end

local function trunc(s, n)
    s = tostring(s or '')
    if #s > n then return s:sub(1, n - 1) .. '.' end
    return s
end

local function checkbox(label, key)
    local b = ref_bool('set_' .. key, DSP.settings[key])
    if imgui.Checkbox(label, b) then
        DSP.settings[key] = b[0]
        DSP.save_settings()
        DSP.market.state.filter_version = -1
        DSP.ui.page = 1
    end
end

local function nav(label, id)
    local active = DSP.ui.tab == id
    if active then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.72)) end
    if imgui.Button(label, imgui.ImVec2(-1, bh())) then
        DSP.ui.tab = id
        DSP.ui.page = 1
    end
    if active then imgui.PopStyleColor(1) end
    imgui.Spacing()
end

-- Tab ids
DSP.ui.TAB = {
    STALL = 1, SHOPS = 2, ARB = 3, MARKET = 4, CATALOG = 5,
    LOGS = 6, SETTINGS = 7, AUTO = 8, CALC = 9, STATS = 10,
}

-- Called from 45_live when the server opens the stall management dialog.
function DSP.ui.on_stall_dialog(dialog_id, title)
    DSP.ui.stall_prompt = { at = os.time(), dialog = dialog_id }
    DSP.ui.tab = DSP.ui.TAB.STALL
    DSP.ui.set_open(true)
    DSP.add_log('Лавка занята: выберите пресет и нажмите НАЧАТЬ ВЫСТАВЛЕНИЕ', 'ok')
end

function DSP.ui.set_open(v)
    DSP.ui.open = v and true or false
    if DSP.ui.open_ref then DSP.ui.open_ref[0] = DSP.ui.open end
end

function DSP.ui.toggle()
    DSP.ui.set_open(not DSP.ui.open)
end

function DSP.ui.init()
    DSP.ui.d = DSP.ui.compute_dpi()
    DSP.ui.open_ref = imgui.new.bool(false)
    DSP.ui.btn_visible = DSP.settings.fab ~= false
    DSP.ui.delay_ref = imgui.new.int(tonumber(DSP.settings.delay_ms) or 500)
    DSP.ui.dpi_ref = imgui.new.float(DSP.clamp(tonumber(DSP.settings.dpi) or 1.0, 0.8, 1.5))
    DSP.ui.preset_name_buf = imgui.new.char[64]()
    if DSP.screens and DSP.screens.init then DSP.screens.init() end
    DSP.ui.search_buf = imgui.new.char[128]()
    DSP.ui.chk.only_profit = imgui.new.bool(DSP.settings.only_profit and true or false)
    DSP.ui.chk.liquid = imgui.new.bool(DSP.settings.liquid and true or false)
    DSP.ui.chk.dry_run = imgui.new.bool(DSP.settings.dry_run ~= false)
    DSP.ui.calc_buy_ref = imgui.new.int(1000)
    DSP.ui.calc_sell_ref = imgui.new.int(1000)
    DSP.ui.calc_qty_ref = imgui.new.int(1)
    DSP.ui.stat_mode = DSP.settings.stats_mode or 'day'
    DSP.ui.chk.tg_notify = imgui.new.bool(DSP.settings.tg_notify and true or false)
    DSP.ui.chk.log_drops = imgui.new.bool(DSP.settings.log_chat_drops ~= false)
    DSP.ui.tg_token_buf = imgui.new.char[256]()
    DSP.ui.tg_chat_buf = imgui.new.char[64]()
    if DSP.settings.tg_bot_token then ffi.copy(DSP.ui.tg_token_buf, DSP.settings.tg_bot_token, #DSP.settings.tg_bot_token) end
    if DSP.settings.tg_chat_id then ffi.copy(DSP.ui.tg_chat_buf, DSP.settings.tg_chat_id, #DSP.settings.tg_chat_id) end
    if sampRegisterChatCommand then
        sampRegisterChatCommand('crr', function() DSP.ui.toggle() end)
    end
    DSP.add_log('palatka ai v' .. DSP.version .. ' загружен')
end

function DSP.ui.header()
    local st = DSP.market.state
    imgui.TextColored(acc_col(1), DSP.utf8('DS РЫНОК'))
    imgui.SameLine(0, 14 * d())
    imgui.TextDisabled(DSP.utf8('Mobile ' .. tostring(st.sid)))
    imgui.SameLine(0, 14 * d())
    local status = st.status == 'loading' and 'обновление...'
        or st.status == 'error' and ('ошибка: ' .. tostring(st.error))
        or st.status == 'cache' and 'кэш'
        or 'live'
    local sc = st.status == 'error' and col(1, 0.35, 0.35) or col(0.55, 0.9, 0.55)
    imgui.TextColored(sc, DSP.utf8(status))
    imgui.SameLine(0, 14 * d())
    imgui.TextDisabled(DSP.utf8(string.format('Лавок: %d  |  Офферов: %d  |  Свежесть: %s',
        st.shops or 0, st.offers or 0, DSP.market.freshness())))
    local bw = 130 * d()
    local avail = imgui.GetContentRegionAvail().x
    if avail > bw + 10 then
        imgui.SameLine(imgui.GetWindowWidth() - bw - 24 * d())
    else
        imgui.SameLine(0, 10 * d())
    end
    if st.status == 'loading' then
        imgui.TextDisabled(DSP.utf8('...'))
    elseif imgui.Button(DSP.utf8('ОБНОВИТЬ'), imgui.ImVec2(bw, bh())) then
        DSP.market.pull(st.sid)
    end
    imgui.Separator()
end

function DSP.ui.server_buttons()
    imgui.TextDisabled(DSP.utf8('Сервер:'))
    imgui.SameLine(0, 8 * d())
    for _, s in ipairs(DSP.market.servers) do
        local active = DSP.market.state.sid == s.id
        if active then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
        if imgui.Button(s.name, imgui.ImVec2(92 * d(), bh())) then
            if DSP.market.state.sid ~= s.id then
                DSP.market.state.sid = s.id
                DSP.settings.server = s.id
                DSP.save_settings()
                DSP.ui.selected = nil
                DSP.ui.page = 1
                DSP.market.pull(s.id)
            end
        end
        if active then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()
end

function DSP.ui.market_tab()
    DSP.ui.header()
    DSP.ui.server_buttons()

    imgui.SetNextItemWidth(320 * d())
    if imgui.InputTextWithHint('##dsp_search', DSP.utf8('Поиск по названию...'), DSP.ui.search_buf, 128) then
        DSP.ui.search = ffi.string(DSP.ui.search_buf)
        DSP.market.state.filter_version = -1
        DSP.ui.page = 1
    end
    imgui.SameLine(0, 12 * d())
    if imgui.Checkbox(DSP.utf8('Только с профитом'), DSP.ui.chk.only_profit) then
        DSP.settings.only_profit = DSP.ui.chk.only_profit[0]
        DSP.save_settings()
        DSP.market.state.filter_version = -1
        DSP.ui.page = 1
    end
    imgui.SameLine(0, 12 * d())
    if imgui.Checkbox(DSP.utf8('Ликвидные (2+ оффера)'), DSP.ui.chk.liquid) then
        DSP.settings.liquid = DSP.ui.chk.liquid[0]
        DSP.save_settings()
        DSP.market.state.filter_version = -1
        DSP.ui.page = 1
    end

    local rows = DSP.market.filtered()
    local per = math.max(5, tonumber(DSP.settings.per_page) or 20)
    local pages = math.max(1, math.ceil(#rows / per))
    if DSP.ui.page > pages then DSP.ui.page = pages end
    if DSP.ui.page < 1 then DSP.ui.page = 1 end
    local from = (DSP.ui.page - 1) * per + 1
    local to = math.min(#rows, DSP.ui.page * per)
    local sel = DSP.ui.selected and DSP.market.state.by_key[DSP.ui.selected] or nil

    imgui.TextDisabled(DSP.utf8(string.format('Найдено: %d  |  стр. %d/%d  |  сортировка: %s',
        #rows, DSP.ui.page, pages,
        (tonumber(DSP.settings.sort) == 2 and 'дешёвые'
            or tonumber(DSP.settings.sort) == 3 and 'дорогая скупка'
            or tonumber(DSP.settings.sort) == 4 and 'процент'
            or tonumber(DSP.settings.sort) == 5 and 'офферы'
            or 'выгода'))))

    local avail = imgui.GetContentRegionAvail()
    local detail_h = sel and (196 * d()) or 0
    local table_h = math.max(150 * d(), avail.y - detail_h - 92 * d())
    local cw = avail.x
    if cw < 600 * d() then cw = 600 * d() end
    local widths = {
        math.floor(cw * 0.38), math.floor(cw * 0.15), math.floor(cw * 0.15),
        math.floor(cw * 0.16), math.floor(cw * 0.08), math.floor(cw * 0.08),
    }

    if imgui.BeginChild('##dsp_mkt_table', imgui.ImVec2(-1, table_h), true) then
        imgui.Columns(6, '##dsp_hdr', false)
        for i = 0, 5 do imgui.SetColumnWidth(i, widths[i + 1]) end
        imgui.TextDisabled(DSP.utf8('ТОВАР'))
        imgui.NextColumn(); imgui.TextDisabled(DSP.utf8('СКУПКА'))
        imgui.NextColumn(); imgui.TextDisabled(DSP.utf8('ПРОДАЖА'))
        imgui.NextColumn(); imgui.TextDisabled(DSP.utf8('ВЫГОДА'))
        imgui.NextColumn(); imgui.TextDisabled(DSP.utf8('КОЛ-ВО'))
        imgui.NextColumn(); imgui.TextDisabled(DSP.utf8('ОФФ.'))
        imgui.NextColumn()
        imgui.Separator()
        imgui.Columns(1)

        imgui.Columns(6, '##dsp_rows', false)
        for i = 0, 5 do imgui.SetColumnWidth(i, widths[i + 1]) end
        for i = from, to do
            local row = rows[i]
            local selected = DSP.ui.selected == row.key
            local label = DSP.utf8(row.display) .. '##dsp_r' .. tostring(i)
            if imgui.Selectable(label, selected,
                imgui.SelectableFlags.SpanAllColumns + imgui.SelectableFlags.AllowDoubleClick,
                imgui.ImVec2(0, 28 * d())) then
                DSP.ui.selected = row.key
            end
            imgui.NextColumn()
            if row.buy.count > 0 then
                imgui.TextColored(col(0.45, 0.9, 0.55), DSP.money(row.buy.best))
            else
                imgui.TextDisabled('-')
            end
            imgui.NextColumn()
            if row.sell.count > 0 then
                imgui.TextColored(col(1.0, 0.72, 0.35), DSP.money(row.sell.best))
            else
                imgui.TextDisabled('-')
            end
            imgui.NextColumn()
            if row.sell.count > 0 and row.buy.count > 0 then
                local pc = row.profit > 0 and col(0.45, 0.95, 0.55)
                    or row.profit < 0 and col(1, 0.4, 0.4) or col(0.7, 0.7, 0.7)
                local ps = (row.profit > 0 and '+' or '') .. DSP.money(row.profit)
                imgui.TextColored(pc, ps)
                imgui.SameLine(0, 5 * d())
                imgui.TextDisabled(string.format('%.0f%%', row.profit_pct or 0))
            else
                imgui.TextDisabled('-')
            end
            imgui.NextColumn()
            imgui.TextDisabled(string.format('%d/%d', row.sell.qty, row.buy.qty))
            imgui.NextColumn()
            imgui.TextDisabled(string.format('%d/%d', row.sell.count, row.buy.count))
            imgui.NextColumn()
        end
        imgui.Columns(1)
        if #rows == 0 then
            imgui.Spacing()
            imgui.TextDisabled(DSP.utf8('Нет строк под фильтр. Нажмите ОБНОВИТЬ.'))
        end
    end
    imgui.EndChild()

    if imgui.Button(DSP.utf8('<< В начало'), imgui.ImVec2(120 * d(), bh())) then DSP.ui.page = 1 end
    imgui.SameLine(0, 6 * d())
    if imgui.Button(DSP.utf8('< Вверх'), imgui.ImVec2(110 * d(), bh())) then DSP.ui.page = DSP.ui.page - 1 end
    imgui.SameLine(0, 10 * d())
    imgui.TextDisabled(string.format('%d / %d', DSP.ui.page, pages))
    imgui.SameLine(0, 10 * d())
    if imgui.Button(DSP.utf8('Вниз >'), imgui.ImVec2(110 * d(), bh())) then DSP.ui.page = DSP.ui.page + 1 end
    imgui.SameLine(0, 6 * d())
    if imgui.Button(DSP.utf8('В конец >>'), imgui.ImVec2(120 * d(), bh())) then DSP.ui.page = pages end
    imgui.SameLine(0, 14 * d())
    imgui.TextDisabled(DSP.utf8('Строк на странице:'))
    imgui.SameLine(0, 6 * d())
    if imgui.Button('-', imgui.ImVec2(0, bh())) then DSP.settings.per_page = math.max(10, per - 5); DSP.save_settings(); DSP.ui.page = 1 end
    imgui.SameLine(0, 4 * d())
    imgui.Text(tostring(per))
    imgui.SameLine(0, 4 * d())
    if imgui.Button('+', imgui.ImVec2(0, bh())) then DSP.settings.per_page = math.min(50, per + 5); DSP.save_settings(); DSP.ui.page = 1 end

    if sel then
        imgui.Separator()
        DSP.ui.detail(sel)
    end
end

function DSP.ui.detail(row)
    imgui.TextColored(acc_col(1), DSP.utf8(trunc(row.display, 42)))
    imgui.SameLine(0, 14 * d())
    local pc = row.profit > 0 and col(0.45, 0.95, 0.55) or col(1, 0.5, 0.5)
    imgui.TextColored(pc, DSP.utf8('выгода ') .. (row.profit > 0 and '+' or '') .. DSP.money(row.profit))
    imgui.SameLine(0, 10 * d())
    imgui.TextDisabled(string.format('(%+.1f%%)', row.profit_pct or 0))
    imgui.SameLine(0, 20 * d())
    if imgui.Button(DSP.utf8('закрыть'), imgui.ImVec2(0, bh())) then DSP.ui.selected = nil end
    imgui.Spacing()
    local h = 100 * d()
    if imgui.BeginChild('##dsp_d_sell', imgui.ImVec2(-1, h), true) then
        imgui.TextDisabled(DSP.utf8('КУПИТЬ ДЕШЕВЛЕ (лавка продаёт)'))
        for i = 1, math.min(3, #row.sell.offers) do
            local o = row.sell.offers[i]
            imgui.TextColored(col(1.0, 0.75, 0.4), DSP.money(o.price))
            imgui.SameLine(0, 8 * d())
            imgui.TextDisabled(DSP.utf8(string.format('x%d  #%s  %s', o.qty, o.shop, trunc(o.owner, 18))))
        end
        if #row.sell.offers == 0 then imgui.TextDisabled('-') end
    end
    imgui.EndChild()
    if imgui.BeginChild('##dsp_d_buy', imgui.ImVec2(-1, h), true) then
        imgui.TextDisabled(DSP.utf8('ПРОДАТЬ ДОРОЖЕ (лавка скупает)'))
        for i = 1, math.min(3, #row.buy.offers) do
            local o = row.buy.offers[i]
            imgui.TextColored(col(0.45, 0.9, 0.55), DSP.money(o.price))
            imgui.SameLine(0, 8 * d())
            imgui.TextDisabled(DSP.utf8(string.format('x%d  #%s  %s', o.qty, o.shop, trunc(o.owner, 18))))
        end
        if #row.buy.offers == 0 then imgui.TextDisabled('-') end
    end
    imgui.EndChild()
    local bw = 210 * d()
    local bt = DSP.market.buy_target(row)
    local st = DSP.market.sell_target(row)
    if imgui.Button(DSP.utf8('+ В скупку  ' .. DSP.money(bt)), imgui.ImVec2(bw, bh())) then
        local ok, err = DSP.presets.add(row, 'buy')
        if not ok then DSP.notify('Скупка: ' .. tostring(err)) end
    end
    imgui.SameLine(0, 10 * d())
    if imgui.Button(DSP.utf8('+ В продажу  ' .. DSP.money(st)), imgui.ImVec2(bw, bh())) then
        local ok, err = DSP.presets.add(row, 'sell')
        if not ok then DSP.notify('Продажа: ' .. tostring(err)) end
    end
end

local C_GREEN = function(a) return col(0.18, 0.80, 0.35, a or 1) end
local C_ORANGE = function(a) return col(0.92, 0.45, 0.18, a or 1) end
local C_RED = function(a) return col(0.90, 0.22, 0.22, a or 1) end

-- One-tap listing panel: preset switcher, START/STOP, progress, budget.
function DSP.ui.stall_panel(kind)
    local sp = DSP.ui.stall_prompt
    if sp and os.time() - (sp.at or 0) < 600 then
        imgui.TextColored(C_GREEN(), DSP.utf8('Лавка занята! Выберите пресет и нажмите НАЧАТЬ ВЫСТАВЛЕНИЕ.'))
        imgui.SameLine(0, 8 * d())
        if imgui.Button(DSP.utf8('Скрыть##dsp_sp_hide'), imgui.ImVec2(0, bh())) then DSP.ui.stall_prompt = nil end
    end
    -- preset library
    local lib = DSP.presets.library()
    local active = DSP.settings.active_preset or {}
    local avail_w = imgui.GetContentRegionAvail().x
    local x = 0
    for i, pr in ipairs(lib) do
        local label = DSP.utf8('[' .. pr.name .. ']##dsp_lib' .. i)
        local w = math.max(120 * d(), math.min(260 * d(), (imgui.CalcTextSize(label).x or 100) + 24 * d()))
        if x > 0 and x + w < avail_w then imgui.SameLine(0, 6 * d()) else x = 0 end
        local is_act = active[pr.kind] == pr.name
        if is_act then imgui.PushStyleColor(imgui.Col.Button, pr.kind == 'sell' and C_ORANGE(0.75) or C_GREEN(0.65)) end
        if imgui.Button(label, imgui.ImVec2(w, bh())) then
            local ok, k = DSP.presets.activate(i)
            if ok then DSP.ui.preset_kind = k end
        end
        if is_act then imgui.PopStyleColor(1) end
        x = x + w + 6 * d()
    end
    -- save the active set as named preset
    imgui.SetNextItemWidth(220 * d())
    imgui.InputTextWithHint('##dsp_pre_name', DSP.utf8('Имя пресета...'), DSP.ui.preset_name_buf, 64)
    imgui.SameLine(0, 6 * d())
    if imgui.Button(DSP.utf8('Сохранить как пресет##dsp_pre_save'), imgui.ImVec2(0, bh())) then
        local nm = DSP.to_cp(ffi.string(DSP.ui.preset_name_buf))
        DSP.presets.save_active(kind, nm)
        DSP.notify('Пресет сохранён: ' .. (DSP.trim(nm) ~= '' and nm or (kind == 'sell' and DSP.settings.sell_preset.name or DSP.settings.buy_preset.name)))
    end
    -- start / stop
    local running = DSP.auto.buy_running or DSP.auto.sell_running
    if running then
        imgui.PushStyleColor(imgui.Col.Button, C_RED(0.85))
        if imgui.Button(DSP.utf8('СТОП##dsp_stop_all'), imgui.ImVec2(160 * d(), bh())) then
            if DSP.auto.buy_running then DSP.auto.stop_buy() end
            if DSP.auto.sell_running then DSP.auto.stop_sell() end
        end
        imgui.PopStyleColor(1)
    else
        imgui.PushStyleColor(imgui.Col.Button, acc_col(0.85))
        if imgui.Button(DSP.utf8('НАЧАТЬ ВЫСТАВЛЕНИЕ##dsp_start'), imgui.ImVec2(260 * d(), bh())) then
            if kind == 'buy' then DSP.auto.start_buy() else DSP.auto.start_sell() end
        end
        imgui.PopStyleColor(1)
    end
    imgui.SameLine(0, 10 * d())
    local pg = DSP.auto.progress or {}
    local frac = DSP.auto.progress_frac and DSP.auto.progress_frac() or 0
    if imgui.ProgressBar then
        imgui.ProgressBar(frac, imgui.ImVec2(-1, bh()),
            DSP.utf8(string.format('%d/%d  (%d%%)', pg.done or 0, pg.total or 0, math.floor(frac * 100))))
    else
        imgui.Text(string.format('%d%%', math.floor(frac * 100)))
    end
    -- budget control (buy presets only)
    if kind == 'buy' and DSP.auto.budget_check then
        local need, have, missing = DSP.auto.budget_check()
        if need > 0 then
            if missing > 0 and have > 0 then
                imgui.TextColored(C_RED(), DSP.utf8('Внимание: не хватает ' .. DSP.money(missing):gsub('^%$', '') .. '$ для полной скупки!'))
            else
                imgui.TextDisabled(DSP.utf8('Бюджет скупки: ' .. DSP.money(need) .. (have > 0 and ('  |  на руках: ' .. DSP.money(have)) or '')))
            end
        end
    end
    imgui.TextDisabled(DSP.utf8(string.format('Задержка: %d мс + 50..120 мс  |  dry-run: %s',
        tonumber(DSP.settings.delay_ms) or 500, DSP.settings.dry_run and 'ВКЛ' or 'ВЫКЛ')))
end

function DSP.ui.trade_tab()
    local kind = DSP.ui.preset_kind
    local p = kind == 'buy' and DSP.settings.buy_preset or DSP.settings.sell_preset

    imgui.TextColored(acc_col(1), DSP.utf8('ПАЛАТКА'))
    imgui.SameLine(0, 18 * d())
    if kind == 'buy' then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
    if imgui.Button(DSP.utf8('СКУПКА'), imgui.ImVec2(130 * d(), bh())) then DSP.ui.preset_kind = 'buy' end
    if kind == 'buy' then imgui.PopStyleColor(1) end
    imgui.SameLine(0, 6 * d())
    if kind == 'sell' then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
    if imgui.Button(DSP.utf8('ПРОДАЖА'), imgui.ImVec2(130 * d(), bh())) then DSP.ui.preset_kind = 'sell' end
    if kind == 'sell' then imgui.PopStyleColor(1) end
    imgui.SameLine(0, 18 * d())
    imgui.TextDisabled(DSP.utf8(string.format('%s: %d поз.', p.name or kind, #p.items)))
    imgui.Separator()
    DSP.ui.stall_panel(kind)
    imgui.Separator()

    local avail = imgui.GetContentRegionAvail()
    local inv_h = math.min(220 * d(), avail.y * 0.55)
    local pre_h = avail.y - inv_h - 40 * d()

    -- Preset items list
    if imgui.BeginChild('##dsp_trade_presets', imgui.ImVec2(-1, pre_h), true) then
        if #p.items == 0 then
            imgui.TextDisabled(DSP.utf8('Пусто. Сканируйте инвентарь и добавляйте товары.'))
        end
        for i, it in ipairs(p.items) do
            local en = ref_bool('pre_en_' .. kind .. '_' .. i, it.enabled ~= false)
            if imgui.Checkbox('##dsp_en' .. i, en) then
                it.enabled = en[0]
                DSP.save_settings()
            end
            imgui.SameLine(0, 8 * d())
            imgui.Text(DSP.utf8(trunc(it.name, 36)))
            imgui.SameLine(0, 12 * d())
            imgui.TextColored(kind == 'buy' and col(0.45, 0.9, 0.55) or col(1.0, 0.72, 0.38),
                DSP.money(it.price))
            imgui.SameLine(0, 8 * d())
            imgui.TextDisabled(DSP.utf8('x' .. tostring(it.qty or 1)))
            local est = DSP.presets.estimate(it, kind)
            if est then
                local ec = est >= 0 and col(0.45, 0.95, 0.5) or col(1, 0.42, 0.38)
                imgui.SameLine(0, 8 * d())
                imgui.TextColored(ec, DSP.utf8((est >= 0 and '+' or '') .. DSP.money(est)))
            end
            imgui.SameLine(0, 6 * d())
            if imgui.Button(DSP.utf8('+все##dsp_all' .. i), imgui.ImVec2(0, bh())) then
                it.qty = math.max(1, it.qty or 1)
                DSP.save_settings()
            end
            imgui.SameLine(0, 3 * d())
            if imgui.Button(DSP.utf8('х-##dsp_del' .. i), imgui.ImVec2(0, bh())) then
                DSP.presets.remove(kind, i)
                break
            end
            imgui.Spacing()
        end
    end
    imgui.EndChild()
    imgui.Separator()

    -- Inventory scan section
    imgui.TextDisabled(DSP.utf8('СКАН ИНВЕНТАРЯ: ' .. (DSP.auto.inv_status or 'не сканирован')))
    if imgui.Button(DSP.utf8('СКАНИРОВАТЬ'), imgui.ImVec2(120 * d(), bh())) then
        DSP.auto.scan_inventory()
    end
    imgui.SameLine(0, 8 * d())
    imgui.TextDisabled(DSP.utf8('позиций: ' .. tostring(#(DSP.auto.inv or {}))))

    if DSP.auto and DSP.auto.inv and #DSP.auto.inv > 0 then
        if imgui.BeginChild('##dsp_trade_inv', imgui.ImVec2(-1, inv_h), true) then
            for _, inv_item in ipairs(DSP.auto.inv or {}) do
                imgui.Text(DSP.utf8(trunc(inv_item.name or '', 34)))
                imgui.SameLine(0, 8 * d())
                imgui.TextDisabled(DSP.utf8('x' .. tostring(inv_item.count or 0)))
                imgui.SameLine(0, 8 * d())
                local row = DSP.market.row_for(inv_item.name, 0)
                local price_text = '-'
                local price_color = col(0.7, 0.7, 0.7)
                if row then
                    if kind == 'buy' then
                        local bp = DSP.market.buy_target(row)
                        if bp > 0 then price_text = DSP.money(bp); price_color = col(0.45, 0.9, 0.55) end
                    else
                        local sp = DSP.market.sell_target(row)
                        if sp > 0 then price_text = DSP.money(sp); price_color = col(1.0, 0.72, 0.38) end
                    end
                end
                imgui.TextColored(price_color, price_text)
                imgui.SameLine(0, 8 * d())
                if row then
                    local rev = row.buy and row.buy.max or 0
                    local cost = row.sell and row.sell.min or 0
                    local pct = cost > 0 and ((rev / cost - 1) * 100) or 0
                    imgui.TextDisabled(string.format('%+.0f%%', pct))
                end
                imgui.SameLine(0, 6 * d())
                if imgui.Button(DSP.utf8('+скуп##dsp_inv_buy_' .. inv_item.name), imgui.ImVec2(0, bh())) then
                    if row then
                        local ok, err = DSP.presets.add(row, 'buy')
                        DSP.notify(ok and 'OK' or ('Ошибка: ' .. tostring(err)))
                    end
                end
                imgui.SameLine(0, 3 * d())
                if imgui.Button(DSP.utf8('+прод##dsp_inv_sell_' .. inv_item.name), imgui.ImVec2(0, bh())) then
                    if row then
                        local ok, err = DSP.presets.add(row, 'sell')
                        DSP.notify(ok and 'OK' or ('Ошибка: ' .. tostring(err)))
                    end
                end
                imgui.Spacing()
            end
        end
        imgui.EndChild()
    end

    -- Action bar
    if imgui.Button(DSP.utf8('ПЕРЕСЧИТАТЬ'), imgui.ImVec2(160 * d(), bh())) then
        DSP.presets.recalc(kind)
    end
    imgui.SameLine(0, 8 * d())
    if imgui.Button(DSP.utf8('ИМПОРТ ИЗ MH'), imgui.ImVec2(140 * d(), bh())) then
        local ok, err = DSP.presets.import_mh()
        DSP.notify(ok and ('Импорт: ' .. tostring(err)) or ('Импорт: ' .. tostring(err)))
    end
    imgui.SameLine(0, 8 * d())
    if imgui.Button(DSP.utf8('ОЧИСТИТЬ'), imgui.ImVec2(110 * d(), bh())) then DSP.presets.clear(kind) end
    imgui.SameLine(0, 12 * d())
    if kind == 'buy' then
        if DSP.auto.buy_running then
            if imgui.Button(DSP.utf8('СТОП СКУПКИ'), imgui.ImVec2(140 * d(), bh())) then DSP.auto.stop_buy() end
        else
            if imgui.Button(DSP.utf8('СТАРТ СКУПКИ'), imgui.ImVec2(140 * d(), bh())) then DSP.auto.start_buy() end
        end
    else
        if DSP.auto.sell_running then
            if imgui.Button(DSP.utf8('СТОП ПРОДАЖИ'), imgui.ImVec2(140 * d(), bh())) then DSP.auto.stop_sell() end
        else
            if imgui.Button(DSP.utf8('СТАРТ ПРОДАЖИ'), imgui.ImVec2(140 * d(), bh())) then DSP.auto.start_sell() end
        end
    end
    imgui.SameLine(0, 10 * d())
    imgui.TextDisabled(DSP.utf8('dry-run: ') .. (DSP.settings.dry_run and 'ON' or 'OFF'))
end

function DSP.ui.auto_tab()
    imgui.TextColored(acc_col(1), DSP.utf8('АВТО'))
    imgui.Separator()
    local st = DSP.auto and DSP.auto.status_text and DSP.auto.status_text() or 'движок не загружен'
    imgui.TextDisabled(DSP.utf8(st))
    imgui.Spacing()

    if imgui.BeginChild('##dsp_auto_buy', imgui.ImVec2(-1, 150 * d()), true) then
        imgui.TextColored(col(0.45, 0.9, 0.55), DSP.utf8('АВТО-СКУПКА'))
        imgui.TextDisabled(DSP.utf8(string.format('Пресет: %d поз.  |  маржа: %d%%  |  кол-во: %d',
            DSP.presets.active_count('buy'), tonumber(DSP.settings.margin) or 10,
            tonumber(DSP.settings.auto_buy_qty) or 1)))
        if DSP.auto.buy_running then
            if imgui.Button(DSP.utf8('СТОП'), imgui.ImVec2(140 * d(), bh())) then DSP.auto.stop_buy() end
        else
            if imgui.Button(DSP.utf8('СТАРТ'), imgui.ImVec2(140 * d(), bh())) then DSP.auto.start_buy() end
        end
        imgui.SameLine(0, 12 * d())
        if imgui.Button(DSP.utf8('ПЕРЕСЧИТАТЬ'), imgui.ImVec2(160 * d(), bh())) then DSP.presets.recalc('buy') end
        imgui.SameLine(0, 16 * d())
        if imgui.Checkbox(DSP.utf8('dry-run (без покупок)'), DSP.ui.chk.dry_run) then
            DSP.settings.dry_run = DSP.ui.chk.dry_run[0]
            DSP.save_settings()
        end
    end
    imgui.EndChild()
    imgui.Spacing()
    if imgui.BeginChild('##dsp_auto_sell', imgui.ImVec2(-1, 150 * d()), true) then
        imgui.TextColored(col(1.0, 0.72, 0.35), DSP.utf8('АВТО-ПРОДАЖА'))
        imgui.TextDisabled(DSP.utf8(string.format('Пресет: %d поз.  |  undercut: %d%%  |  инвентарь: %s',
            DSP.presets.active_count('sell'), tonumber(DSP.settings.undercut) or 2,
            DSP.auto.inv_status or 'не сканирован')))
        if DSP.auto.sell_running then
            if imgui.Button(DSP.utf8('СТОП'), imgui.ImVec2(140 * d(), bh())) then DSP.auto.stop_sell() end
        else
            if imgui.Button(DSP.utf8('СТАРТ'), imgui.ImVec2(140 * d(), bh())) then DSP.auto.start_sell() end
        end
        imgui.SameLine(0, 12 * d())
        if imgui.Button(DSP.utf8('СКАН ИНВЕНТАРЯ'), imgui.ImVec2(180 * d(), bh())) then DSP.auto.scan_inventory() end
        imgui.SameLine(0, 12 * d())
        if imgui.Button(DSP.utf8('ПЕРЕСЧИТАТЬ'), imgui.ImVec2(160 * d(), bh())) then DSP.presets.recalc('sell') end
    end
    imgui.EndChild()
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Последние события:'))
    if imgui.BeginChild('##dsp_auto_log', imgui.ImVec2(-1, 0), true) then
        for i = 1, math.min(8, #DSP.log) do
            local e = DSP.log[i]
            imgui.TextDisabled(e.t)
            imgui.SameLine(0, 8 * d())
            local c = e.kind == 'error' and col(1, 0.4, 0.4)
                or e.kind == 'ok' and col(0.45, 0.9, 0.55) or col(0.8, 0.8, 0.8)
            imgui.TextColored(c, DSP.utf8(e.text))
        end
    end
    imgui.EndChild()
end

function DSP.ui.log_tab()
    imgui.TextColored(acc_col(1), DSP.utf8('ЖУРНАЛ'))
    imgui.SameLine(0, 30 * d())
    imgui.TextDisabled(DSP.utf8('Сделки: ' .. tostring(count_keys(DSP.settings.trades))))
    imgui.SameLine(0, 12 * d())
    imgui.TextDisabled(DSP.utf8('Лавки: ' .. tostring(count_keys(DSP.settings.stalls))))
    imgui.SameLine(0, 12 * d())
    imgui.TextDisabled(DSP.utf8('Ларцы: ' .. tostring(count_keys(DSP.settings.crates))))
    imgui.SameLine(0, 12 * d())
    imgui.TextDisabled(DSP.utf8('Чат: ' .. tostring(#(DSP.settings.chat_logs or {}))))
    imgui.SameLine(0, 20 * d())
    if imgui.Button(DSP.utf8('очистить лог'), imgui.ImVec2(0, bh())) then DSP.log = {} end
    imgui.SameLine(0, 8 * d())
    if imgui.Button(DSP.utf8('очистить сделки'), imgui.ImVec2(0, bh())) then DSP.logs.clear_trades() end
    imgui.SameLine(0, 8 * d())
    if imgui.Button(DSP.utf8('очистить чат'), imgui.ImVec2(0, bh())) then DSP.settings.chat_logs = {}; DSP.db.save(true) end
    imgui.Separator()

    if DSP.ui.tab_detail == 'crates' then
        DSP.ui.crate_log()
    elseif DSP.ui.tab_detail == 'chat' then
        DSP.ui.chat_log()
    else
        DSP.ui.trade_log()
    end
    imgui.Spacing()
    local r1 = DSP.ui.tab_detail == 'trades'
    if r1 then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.72)) end
    if imgui.Button(DSP.utf8('Сделки + лавки'), imgui.ImVec2(160 * d(), bh())) then DSP.ui.tab_detail = 'trades' end
    if r1 then imgui.PopStyleColor(1) end
    imgui.SameLine(0, 8 * d())
    local r2 = DSP.ui.tab_detail == 'crates'
    if r2 then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.72)) end
    if imgui.Button(DSP.utf8('Ларцы'), imgui.ImVec2(120 * d(), bh())) then DSP.ui.tab_detail = 'crates' end
    if r2 then imgui.PopStyleColor(1) end
    imgui.SameLine(0, 8 * d())
    local r3 = DSP.ui.tab_detail == 'chat'
    if r3 then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.72)) end
    if imgui.Button(DSP.utf8('Чат'), imgui.ImVec2(120 * d(), bh())) then DSP.ui.tab_detail = 'chat' end
    if r3 then imgui.PopStyleColor(1) end
end

function DSP.ui.trade_log()
    if not DSP.settings.trades or #DSP.settings.trades == 0 then
        imgui.TextDisabled(DSP.utf8('Сделки не записаны'))
    else
        if imgui.BeginChild('##dsp_trade_log', imgui.ImVec2(-1, 360 * d()), true) then
            local sorted = to_sorted_array(DSP.settings.trades)
            for i = #sorted, 1, -1 do
                local e = sorted[i]
                local t = os.date('%H:%M:%S', e.ts or 0)
                imgui.TextDisabled(t)
                imgui.SameLine(0, 8 * d())
                local sign = e.profit and e.profit >= 0 and col(0.45, 0.9, 0.55) or col(1, 0.4, 0.4)
                local pstr = e.profit and ((e.profit > 0 and '+' or '') .. DSP.money(e.profit)) or '-'
                imgui.TextColored(sign, DSP.utf8(string.format('%s | %s -> %s | %s',
                    t, e.partner or '?', e.item_summary or 'N/A', pstr)))
                imgui.TextDisabled(DSP.utf8(string.format('  получено: %s | отдано: %s',
                    DSP.money(e.total_get or 0), DSP.money(e.total_give or 0))))
            end
        end
        imgui.EndChild()
    end

    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Стенды (сканирование лавок):'))
    if imgui.BeginChild('##dsp_stall_log', imgui.ImVec2(-1, 120 * d()), true) then
        local stalls = to_sorted_array(DSP.settings.stalls)
        if #stalls == 0 then
            imgui.TextDisabled(DSP.utf8('Стенды не сканированы'))
        else
            for i = #stalls, 1, -1 do
                local e = stalls[i]
                local t = os.date('%H:%M:%S', e.ts or 0)
                imgui.TextDisabled(string.format('%s  [#%s %s] %s',
                    t, tostring(e.shop_num or '?'), DSP.to_cp(e.owner or '?'), e.action or ''))
            end
        end
    end
    imgui.EndChild()
end

function DSP.ui.crate_log()
    if not DSP.settings.crates or #DSP.settings.crates == 0 then
        imgui.TextDisabled(DSP.utf8('Ларцы не открывались'))
    else
        if imgui.BeginChild('##dsp_crate_log', imgui.ImVec2(-1, 360 * d()), true) then
            local sorted = to_sorted_array(DSP.settings.crates)
            for i = #sorted, 1, -1 do
                local e = sorted[i]
                local t = os.date('%H:%M:%S', e.ts or 0)
                imgui.TextDisabled(t)
                imgui.SameLine(0, 8 * d())
                imgui.TextColored(col(1.0, 0.72, 0.4), DSP.utf8(e.item or '?'))
                imgui.SameLine(0, 8 * d())
                imgui.TextDisabled(DSP.utf8('x' .. tostring(e.qty or 1)))
                imgui.SameLine(0, 8 * d())
                if e.ench and e.ench > 0 then
                    imgui.TextDisabled(DSP.utf8('+' .. tostring(e.ench)))
                end
            end
        end
        imgui.EndChild()
    end
end

function DSP.ui.chat_log()
    if not DSP.settings.chat_logs or #DSP.settings.chat_logs == 0 then
        imgui.TextDisabled(DSP.utf8('Чат-сообщения не записаны'))
        return
    end
    if imgui.BeginChild('##dsp_chat_log', imgui.ImVec2(-1, 0), true) then
        for i = #DSP.settings.chat_logs, 1, -1 do
            local e = DSP.settings.chat_logs[i]
            local t = os.date('%H:%M:%S', e.ts or 0)
            imgui.TextDisabled(t)
            imgui.SameLine(0, 8 * d())
            local drop = DSP.logs and DSP.logs.parse_chat_drop and DSP.logs.parse_chat_drop(e.text)
            local clr = drop and col(1.0, 0.72, 0.4) or col(0.8, 0.8, 0.9)
            imgui.TextColored(clr, DSP.utf8(e.text or ''))
        end
    end
    imgui.EndChild()
end

function DSP.ui.settings_tab()
    imgui.TextColored(acc_col(1), DSP.utf8('НАСТРОЙКИ'))
    imgui.Separator()
    DSP.ui.server_buttons()
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Сортировка рынка:'))
    local sorts = { 'выгода', 'дешёвые', 'дорогая скупка', 'процент', 'офферы' }
    for i, name in ipairs(sorts) do
        local act = (tonumber(DSP.settings.sort) or 1) == i
        if act then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
        if imgui.Button(DSP.utf8(name), imgui.ImVec2(150 * d(), bh())) then
            DSP.settings.sort = i
            DSP.save_settings()
            DSP.market.state.filter_version = -1
            DSP.ui.page = 1
        end
        if act then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8(string.format('Маржа скупки: %d%%', tonumber(DSP.settings.margin) or 10)))
    if imgui.Button('-5##dsp_margm', imgui.ImVec2(0, bh())) then DSP.settings.margin = math.max(0, (tonumber(DSP.settings.margin) or 10) - 5); DSP.save_settings() end
    imgui.SameLine(0, 4 * d())
    if imgui.Button('+5##dsp_margp', imgui.ImVec2(0, bh())) then DSP.settings.margin = math.min(80, (tonumber(DSP.settings.margin) or 10) + 5); DSP.save_settings() end
    imgui.SameLine(0, 12 * d())
    imgui.TextDisabled(DSP.utf8(string.format('Undercut продажи: %d%%', tonumber(DSP.settings.undercut) or 2)))
    if imgui.Button('-1##dsp_ucm', imgui.ImVec2(0, bh())) then DSP.settings.undercut = math.max(0, (tonumber(DSP.settings.undercut) or 2) - 1); DSP.save_settings() end
    imgui.SameLine(0, 4 * d())
    if imgui.Button('+1##dsp_ucp', imgui.ImVec2(0, bh())) then DSP.settings.undercut = math.min(50, (tonumber(DSP.settings.undercut) or 2) + 1); DSP.save_settings() end
    imgui.Spacing()
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Оверлей при трейде/лавке:'))
    checkbox(DSP.utf8('оценка трейда'), 'overlay_trade')
    imgui.SameLine(0, 12 * d())
    checkbox(DSP.utf8('скан лавки'), 'overlay_shop')
    imgui.SameLine(0, 12 * d())
    checkbox(DSP.utf8('поверх окон'), 'overlay_top')
    imgui.Spacing()
    -- CR commission
    imgui.TextDisabled(DSP.utf8('Комиссия ЦР (учитывается в прибыли и арбитраже):'))
    local taxes = { { 1, '1% ADD VIP' }, { 2, '2% Titan/Premium' }, { 3, '3% без VIP' }, { 4, '4% без VIP' } }
    for _, t in ipairs(taxes) do
        local act = DSP.market.tax_pct() == t[1]
        if act then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
        if imgui.Button(DSP.utf8(t[2]) .. '##dsp_tax' .. t[1], imgui.ImVec2(0, bh())) then
            DSP.settings.tax = t[1]
            DSP.save_settings()
            DSP.market.recompute()
        end
        if act then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()
    imgui.Spacing()
    -- anti-cheat delay
    imgui.TextDisabled(DSP.utf8('Задержка выставления (античит), мс:'))
    imgui.SetNextItemWidth(math.min(420 * d(), imgui.GetContentRegionAvail().x))
    if imgui.SliderInt('##dsp_delay', DSP.ui.delay_ref, 300, 1000) then
        DSP.settings.delay_ms = DSP.clamp(DSP.ui.delay_ref[0], 300, 1000)
        DSP.save_settings()
    end
    imgui.Spacing()
    -- floating button
    if imgui.Checkbox(DSP.utf8('Плавающая кнопка [CR] на экране'), ref_bool('set_fab', DSP.settings.fab ~= false)) then
        DSP.settings.fab = DSP.ui.refs.set_fab[0]
        DSP.ui.btn_visible = DSP.settings.fab
        DSP.save_settings()
    end
    if imgui.Checkbox(DSP.utf8('Открывать меню при занятии лавки'), ref_bool('set_auto_stall', DSP.settings.auto_open_stall ~= false)) then
        DSP.settings.auto_open_stall = DSP.ui.refs.set_auto_stall[0]
        DSP.save_settings()
    end
    if imgui.Checkbox(DSP.utf8('Авто-листание диалога средних цен ЦР'), ref_bool('set_avg_scan', DSP.settings.avg_autoscan ~= false)) then
        DSP.settings.avg_autoscan = DSP.ui.refs.set_avg_scan[0]
        DSP.save_settings()
    end
    imgui.Spacing()
    -- anti-scam
    imgui.TextDisabled(DSP.utf8('Анти-скам: отклонение от средней цены в'))
    for _, r in ipairs({ 3, 4, 5 }) do
        imgui.SameLine(0, 6 * d())
        local act = (tonumber(DSP.settings.scam_ratio) or 3) == r
        if act then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
        if imgui.Button(r .. 'x##dsp_scam' .. r, imgui.ImVec2(60 * d(), bh())) then
            DSP.settings.scam_ratio = r
            DSP.save_settings()
            DSP.market.state.arb_version = -1
        end
        if act then imgui.PopStyleColor(1) end
    end
    imgui.Spacing()
    -- DPI
    imgui.TextDisabled(DSP.utf8(string.format('Масштаб интерфейса: %.2fx', DSP.ui.d or 1)))
    if imgui.Checkbox(DSP.utf8('авто (MONET_DPI_SCALE / разрешение экрана)'), ref_bool('set_dpi_auto', DSP.settings.dpi_auto ~= false)) then
        DSP.settings.dpi_auto = DSP.ui.refs.set_dpi_auto[0]
        DSP.ui.d = DSP.ui.compute_dpi()
        DSP.save_settings()
    end
    if DSP.settings.dpi_auto == false then
        imgui.SetNextItemWidth(math.min(420 * d(), imgui.GetContentRegionAvail().x))
        if imgui.SliderFloat('##dsp_dpi', DSP.ui.dpi_ref, 0.8, 1.5, '%.2fx') then
            DSP.settings.dpi = DSP.clamp(DSP.ui.dpi_ref[0], 0.8, 1.5)
            DSP.save_settings()
        end
        imgui.SameLine(0, 6 * d())
        if imgui.Button(DSP.utf8('Применить##dsp_dpi_apply'), imgui.ImVec2(0, bh())) then
            DSP.ui.d = DSP.ui.compute_dpi()
        end
    end
    imgui.NewLine()
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Статистика по умолчанию:'))
    local modes = {
        { key = 'hour', label = 'Час' },
        { key = 'day', label = 'День' },
        { key = 'week', label = 'Неделя' },
        { key = 'month', label = 'Месяц' },
        { key = 'all', label = 'Все время' },
    }
    for _, m in ipairs(modes) do
        local act = DSP.settings.stats_mode == m.key
        if act then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
        if imgui.Button(DSP.utf8(m.label), imgui.ImVec2(100 * d(), bh())) then
            DSP.settings.stats_mode = m.key
            DSP.save_settings()
        end
        if act then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Telegram-уведомления:'))
    if imgui.Checkbox(DSP.utf8('включить'), DSP.ui.chk.tg_notify) then
        DSP.settings.tg_notify = DSP.ui.chk.tg_notify[0]
        DSP.save_settings()
    end
    local tg_ev = DSP.settings.tg_events or {}
    DSP.settings.tg_events = tg_ev
    local evs = {
        { 'sales', 'Уведомлять о продажах' },
        { 'kick', 'Уведомлять о слёте лавки / кике' },
        { 'drops', 'Уведомлять о дропах из ларцов' },
        { 'admin', 'Уведомлять о приближении админа' },
        { 'trades', 'Уведомлять о трейдах' },
    }
    for _, e in ipairs(evs) do
        if imgui.Checkbox(DSP.utf8(e[2]) .. '##dsp_tgev_' .. e[1], ref_bool('tg_ev_' .. e[1], tg_ev[e[1]] ~= false)) then
            tg_ev[e[1]] = DSP.ui.refs['tg_ev_' .. e[1]][0]
            DSP.save_settings()
        end
    end
    if imgui.Button(DSP.utf8('Тест Telegram##dsp_tg_test'), imgui.ImVec2(0, bh())) then
        local ok = DSP.logs.send_telegram('[palatka ai] Тестовое сообщение', 'manual')
        DSP.notify(ok and 'Telegram: отправлено' or 'Telegram: проверьте токен, Chat ID и галочку')
    end
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Bot Token:'))
    imgui.PushItemWidth(300 * d())
    local changed = imgui.InputText('##dsp_tg_token', DSP.ui.tg_token_buf, 256)
    imgui.PopItemWidth()
    if changed then
        DSP.settings.tg_bot_token = ffi.string(DSP.ui.tg_token_buf)
        DSP.save_settings()
    end
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Chat ID:'))
    imgui.PushItemWidth(160 * d())
    local changed2 = imgui.InputText('##dsp_tg_chat', DSP.ui.tg_chat_buf, 64)
    imgui.PopItemWidth()
    if changed2 then
        DSP.settings.tg_chat_id = ffi.string(DSP.ui.tg_chat_buf)
        DSP.save_settings()
    end
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Логи чата и выпадов:'))
    if imgui.Checkbox(DSP.utf8('записывать выпады'), DSP.ui.chk.log_drops) then
        DSP.settings.log_chat_drops = DSP.ui.chk.log_drops[0]
        DSP.save_settings()
    end
    if imgui.Button(DSP.utf8('ЭКСПОРТ В TELEGRAM'), imgui.ImVec2(200 * d(), bh())) then
        if DSP.logs and DSP.logs.export_logs then DSP.logs.export_logs() end
    end
    imgui.SameLine(0, 12 * d())
    if imgui.Button(DSP.utf8('СОХРАНИТЬ'), imgui.ImVec2(160 * d(), bh())) then
        DSP.save_settings()
        DSP.notify('Настройки сохранены')
    end
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Данные: ' .. DSP.dir))
    imgui.TextDisabled(DSP.utf8('API: ' .. DSP.market.api))
end

function DSP.ui.calculator_tab()
    imgui.TextColored(acc_col(1), DSP.utf8('КАЛЬКУЛЯТОР'))
    imgui.SameLine(0, 14 * d())
    imgui.TextDisabled(DSP.utf8('Арбитражный калькулятор'))
    imgui.Separator()

    local avail = imgui.GetContentRegionAvail()
    local w = math.min(avail.x, 520 * d())

    if imgui.BeginChild('##dsp_calc_card', imgui.ImVec2(-1, 260 * d()), true) then
        imgui.PushItemWidth(w * 0.55)
        imgui.TextDisabled(DSP.utf8('Цена покупки:'))
        imgui.SameLine(0, 8 * d())
        imgui.InputInt(DSP.utf8('buy##price'), DSP.ui.calc_buy_ref, 1000, 10000)

        imgui.Spacing()
        imgui.TextDisabled(DSP.utf8('Цена продажи:'))
        imgui.SameLine(0, 8 * d())
        imgui.InputInt(DSP.utf8('sell##price'), DSP.ui.calc_sell_ref, 1000, 10000)

        imgui.Spacing()
        imgui.TextDisabled(DSP.utf8('Кол-во:'))
        imgui.SameLine(0, 8 * d())
        imgui.InputInt(DSP.utf8('qty##calc'), DSP.ui.calc_qty_ref, 1, 10)

        imgui.PopItemWidth()
    end
    imgui.EndChild()

    imgui.Spacing()
    local buy_p = DSP.ui.calc_buy_ref[0]
    local sell_p = DSP.ui.calc_sell_ref[0]
    local qty = DSP.ui.calc_qty_ref[0]
    local profit = (sell_p - buy_p) * qty
    local pct = buy_p > 0 and ((sell_p - buy_p) / buy_p * 100) or 0

    if imgui.BeginChild('##dsp_calc_result', imgui.ImVec2(-1, 140 * d()), true) then
        imgui.TextDisabled(DSP.utf8('Сумма вложений:'))
        imgui.SameLine(0, 20 * d())
        imgui.Text(DSP.money(buy_p * qty))

        imgui.Spacing()
        imgui.TextDisabled(DSP.utf8('Ожидаемая выручка:'))
        imgui.SameLine(0, 20 * d())
        imgui.Text(DSP.money(sell_p * qty))

        imgui.Spacing()
        local pc = profit >= 0 and col(0.45, 0.95, 0.5) or col(1, 0.42, 0.38)
        imgui.TextDisabled(DSP.utf8('Прибыль:'))
        imgui.SameLine(0, 30 * d())
        imgui.TextColored(pc, DSP.utf8((profit >= 0 and '+' or '') .. DSP.money(profit)))
        imgui.SameLine(0, 10 * d())
        imgui.TextColored(pc, string.format('%+.1f%%', pct))

        imgui.Spacing()
        imgui.TextDisabled(DSP.utf8('На штуку:'))
        imgui.SameLine(0, 24 * d())
        imgui.TextColored(pc, DSP.utf8((sell_p - buy_p >= 0 and '+' or '')
            .. DSP.money(sell_p - buy_p)))

        local bw = 160 * d()
        if imgui.Button(DSP.utf8('ОЧИСТИТЬ'), imgui.ImVec2(bw, bh())) then
            DSP.ui.calc_buy_ref[0] = 1000
            DSP.ui.calc_sell_ref[0] = 1000
            DSP.ui.calc_qty_ref[0] = 1
        end
    end
    imgui.EndChild()
end

function DSP.ui.statistics_tab()
    imgui.TextColored(acc_col(1), DSP.utf8('СТАТИСТИКА'))
    imgui.SameLine(0, 14 * d())
    imgui.TextDisabled(DSP.utf8('Прибыль по периодам'))
    imgui.Separator()

    local modes = {
        { key = 'hour', label = 'Час' },
        { key = 'day', label = 'День' },
        { key = 'week', label = 'Неделя' },
        { key = 'month', label = 'Месяц' },
        { key = 'all', label = 'Все время' },
    }
    for _, m in ipairs(modes) do
        local active = DSP.ui.stat_mode == m.key
        if active then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
        if imgui.Button(DSP.utf8(m.label), imgui.ImVec2(90 * d(), bh())) then
            DSP.ui.stat_mode = m.key
        end
        if active then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()

    local summary = DSP.logs.profit_summary(DSP.ui.stat_mode)
    local avail = imgui.GetContentRegionAvail()
    local stat_h = avail.y - 30 * d()

    if imgui.BeginChild('##dsp_stat_summary', imgui.ImVec2(-1, 90 * d()), true) then
        imgui.TextDisabled(DSP.utf8(string.format('Сделок: %d', summary.count)))
        imgui.SameLine(0, 16 * d())
        imgui.Text(DSP.money(summary.total_get))
        imgui.SameLine(0, 4 * d())
        imgui.TextDisabled(DSP.utf8('получено'))
        imgui.SameLine(0, 16 * d())
        imgui.Text(DSP.money(summary.total_give))
        imgui.SameLine(0, 4 * d())
        imgui.TextDisabled(DSP.utf8('отдано'))
        imgui.Spacing()
        local pc = summary.profit >= 0 and col(0.45, 0.95, 0.5) or col(1, 0.42, 0.38)
        imgui.TextColored(pc, DSP.utf8('Прибыль: ' .. (summary.profit >= 0 and '+' or '') .. DSP.money(summary.profit)))
        imgui.SameLine(0, 16 * d())
        imgui.TextDisabled(string.format('ROI: %+.1f%%', summary.roi))
        imgui.SameLine(0, 16 * d())
        imgui.TextDisabled(DSP.utf8('Средняя: ' .. DSP.money(summary.avg_profit)))
    end
    imgui.EndChild()

    imgui.Spacing()
    if imgui.BeginChild('##dsp_stat_buckets', imgui.ImVec2(-1, stat_h - 100 * d()), true) then
        if #summary.sorted_keys == 0 then
            imgui.TextDisabled(DSP.utf8('Нет данных. Совершите сделки чтобы увидеть статистику.'))
        end
        for _, k in ipairs(summary.sorted_keys) do
            local b = summary.buckets[k]
            if b then
                local pc = b.profit >= 0 and col(0.45, 0.95, 0.5) or col(1, 0.42, 0.38)
                imgui.Text(DSP.utf8(k))
                imgui.SameLine(0, 20 * d())
                imgui.TextColored(pc, DSP.utf8((b.profit >= 0 and '+' or '') .. DSP.money(b.profit)))
                imgui.SameLine(0, 10 * d())
                imgui.TextDisabled(string.format('%d сдел.', b.count))
            end
            imgui.Spacing()
        end
    end
    imgui.EndChild()
end

function DSP.ui.draw()
    local dpi = d()
    local sw, sh = DSP.ui.screen_size()
    -- Mobile: the window is never wider than 1000 px (and never wider than the screen).
    local max_w = math.max(320, math.min(1000, sw - 20))
    local max_h = math.max(240, sh - 20)
    local w0 = max_w
    local h0 = math.min(max_h, 720 * dpi)
    if imgui.SetNextWindowSizeConstraints then
        imgui.SetNextWindowSizeConstraints(imgui.ImVec2(320, 240), imgui.ImVec2(max_w, max_h))
    end
    imgui.SetNextWindowSize(imgui.ImVec2(w0, h0), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowBgAlpha(0.98)
    imgui.PushStyleColor(imgui.Col.WindowBg, col(0.08, 0.08, 0.11, 0.98))
    imgui.PushStyleColor(imgui.Col.TitleBg, col(0.08, 0.08, 0.11, 1))
    imgui.PushStyleColor(imgui.Col.TitleBgActive, col(ACC[1] * 0.30, ACC[2] * 0.30, ACC[3] * 0.30, 1))
    imgui.PushStyleColor(imgui.Col.Border, acc_col(0.8))
    imgui.PushStyleColor(imgui.Col.Button, col(0.15, 0.15, 0.20, 1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, acc_col(0.75))
    imgui.PushStyleColor(imgui.Col.ButtonActive, acc_col(0.95))
    imgui.PushStyleColor(imgui.Col.Header, acc_col(0.45))
    imgui.PushStyleColor(imgui.Col.HeaderHovered, acc_col(0.65))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12 * dpi)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 8 * dpi)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 9 * dpi)
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(8 * dpi, 8 * dpi))

    local T = DSP.ui.TAB
    local flags = imgui.WindowFlags.NoCollapse
    if imgui.Begin(DSP.utf8(' palatka ai v' .. DSP.version .. ' ') .. '##dsp_main_wnd', DSP.ui.open_ref, flags) then
        local ww = imgui.GetWindowWidth()
        local side_w = math.min(150 * dpi, ww * 0.24)
        if imgui.BeginChild('##dsp_side', imgui.ImVec2(side_w, 0), true) then
            imgui.TextColored(acc_col(1), DSP.utf8('PALATKA AI'))
            imgui.Separator()
            nav(DSP.utf8('ПАЛАТКА'), T.STALL)
            nav(DSP.utf8('ЛАВКИ ЦР'), T.SHOPS)
            nav(DSP.utf8('АРБИТРАЖ'), T.ARB)
            nav(DSP.utf8('РЫНОК'), T.MARKET)
            nav(DSP.utf8('КАТАЛОГ'), T.CATALOG)
            nav(DSP.utf8('ЛОГИ'), T.LOGS)
            nav(DSP.utf8('НАСТРОЙКИ'), T.SETTINGS)
            nav(DSP.utf8('АВТО'), T.AUTO)
            nav(DSP.utf8('КАЛЬК'), T.CALC)
            nav(DSP.utf8('СТАТ'), T.STATS)
            imgui.Separator()
            imgui.TextDisabled(DSP.utf8(string.format('лавок: %d', DSP.market.state.shops or 0)))
            imgui.TextDisabled(DSP.utf8('свежесть: ' .. DSP.market.freshness()))
        end
        imgui.EndChild()
        imgui.SameLine(0, 8 * dpi)
        if imgui.BeginChild('##dsp_main', imgui.ImVec2(0, 0), false) then
            local tab = DSP.ui.tab
            local ok, err = pcall(function()
                if tab == T.STALL then DSP.ui.trade_tab()
                elseif tab == T.SHOPS then DSP.screens.shops_tab()
                elseif tab == T.ARB then DSP.screens.arbitrage_tab()
                elseif tab == T.CATALOG then DSP.screens.catalog_tab()
                elseif tab == T.LOGS then DSP.ui.log_tab()
                elseif tab == T.SETTINGS then DSP.ui.settings_tab()
                elseif tab == T.AUTO then DSP.ui.auto_tab()
                elseif tab == T.CALC then DSP.ui.calculator_tab()
                elseif tab == T.STATS then DSP.ui.statistics_tab()
                else DSP.ui.market_tab() end
            end)
            if not ok then
                -- never leave the frame unbalanced; show the error instead of crashing
                DSP.flog('UI tab error: ' .. tostring(err))
                imgui.TextColored(col(0.90, 0.22, 0.22), DSP.utf8('Ошибка вкладки: ') .. tostring(err))
            end
        end
        imgui.EndChild()
    end
    imgui.End()
    imgui.PopStyleVar(4)
    imgui.PopStyleColor(9)
    if DSP.ui.open_ref and DSP.ui.open_ref[0] == false then
        DSP.ui.open = false
    end
end

-- Floating action button [CR]: 60x60 * dpi, translucent, always on top.
function DSP.ui.draw_fab()
    local dpi = d()
    local size = 60 * dpi
    local sw, sh = DSP.ui.screen_size()
    imgui.SetNextWindowPos(imgui.ImVec2(sw - size - 12 * dpi, sh * 0.35), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(imgui.ImVec2(size, size), imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(0.0)
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoBackground
        + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoSavedSettings
        + imgui.WindowFlags.NoScrollWithMouse
    if imgui.WindowFlags.NoFocusOnAppearing then flags = flags + imgui.WindowFlags.NoFocusOnAppearing end
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, size / 2)
    imgui.PushStyleColor(imgui.Col.Button, col(0.08, 0.08, 0.11, 0.55))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, acc_col(0.70))
    imgui.PushStyleColor(imgui.Col.ButtonActive, acc_col(0.95))
    imgui.PushStyleColor(imgui.Col.Text, acc_col(1))
    if imgui.Begin('##dsp_fab', nil, flags) then
        if imgui.Button('[CR]', imgui.ImVec2(size, size)) then DSP.ui.toggle() end
    end
    imgui.End() -- ALWAYS paired with Begin, even when Begin returns false
    imgui.PopStyleColor(4)
    imgui.PopStyleVar(2)
end

function DSP.ui.install()
    DSP.ui.init()
    imgui.OnFrame(function()
        return DSP.ui.btn_visible ~= false and DSP.settings.fab ~= false and not DSP.ui.open
            and not (isPauseMenuActive and isPauseMenuActive())
    end, function(player)
        player.HideCursor = false
        DSP.ui.draw_fab()
    end)
    imgui.OnFrame(function() return DSP.ui.open end, function()
        DSP.ui.draw()
    end)
end

end
__mod_30_ui()

local function __mod_35_screens()
-- New screens from PALATKA_AI_MASTER_PROMPT.md section 5:
--   Tab 2 "ЛАВКИ ЦР"  : per-shop cards, [Отметить лавку], detail (green buy / orange sell),
--                        [Скопировать скупку] -> preset (+1$ / +1000$ outbid)
--   Tab 3 "АРБИТРАЖ"  : A.sell_slot -> B.buy_slot pairs with net profit after commission,
--                        anti-scam highlighting, find-shop buttons
--   Tab 4 "КАТАЛОГ"   : local item base, instant search, [+ В скупку] / [+ В продажу]
-- All imgui buffers are allocated once in DSP.screens.init() (called from DSP.ui.init()).
local ffi = require('ffi')

DSP.screens = DSP.screens or {}
local S = DSP.screens
S.inited = false
S.expanded = {}
S.copying = nil
S.copy_bump = 0
S.shops_page = 1
S.arb_page = 1
S.cat_page = 1
S.cat_cat = 1
S.cat_edit = nil

local function d() return (DSP.ui and DSP.ui.d) or 1.0 end
local function bh() return 40 * d() end
local function col(c, a) return imgui.ImVec4(c[1], c[2], c[3], a or c[4] or 1) end
local function u(s) return DSP.utf8(s) end

local C = DSP.colors

local function set_buf(buf, size, text_cp)
    ffi.fill(buf, size, 0)
    local s = DSP.to_u8(tostring(text_cp or ''))
    if #s > size - 1 then s = s:sub(1, size - 1) end
    ffi.copy(buf, s, #s)
end

function S.init()
    S.shops_buf = imgui.new.char[128]()
    S.cat_buf = imgui.new.char[128]()
    S.copy_buf = imgui.new.char[64]()
    S.cat_price = imgui.new.int(0)
    S.cat_qty = imgui.new.int(1)
    S.arb_hide_scam = imgui.new.bool(false)
    S.shops_only_buy = imgui.new.bool(false)
    S.inited = true
end

local function ensure()
    if not S.inited then S.init() end
end

local function age_text(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return 'нет данных' end
    local a = math.max(0, os.time() - ts)
    if a < 60 then return a .. ' сек назад' end
    if a < 3600 then return math.floor(a / 60) .. ' мин назад' end
    if a < 86400 then return math.floor(a / 3600) .. ' ч назад' end
    return math.floor(a / 86400) .. ' дн назад'
end

local function pager(id, page, pages)
    if imgui.Button(u('<##' .. id .. '_prev'), imgui.ImVec2(70 * d(), bh())) then page = page - 1 end
    imgui.SameLine(0, 8 * d())
    imgui.Text(string.format('%d / %d', page, pages))
    imgui.SameLine(0, 8 * d())
    if imgui.Button(u('>##' .. id .. '_next'), imgui.ImVec2(70 * d(), bh())) then page = page + 1 end
    if page < 1 then page = 1 end
    if page > pages then page = pages end
    return page
end

-- max characters that fit into `w` pixels (rough, for truncation)
local function fit_chars(w)
    return math.max(8, math.floor(w / (7.5 * d())))
end

-- ---------------------------------------------------------------------------
-- TAB 2: shops of the server
local shop_cache = { q = nil, version = -1, only_buy = nil, list = {} }

local function filtered_shops()
    local st = DSP.market.state
    local q = DSP.lower(DSP.trim(DSP.to_cp(ffi.string(S.shops_buf))))
    local only_buy = S.shops_only_buy[0]
    if shop_cache.q == q and shop_cache.version == st.version and shop_cache.only_buy == only_buy then
        return shop_cache.list
    end
    local out = {}
    for _, card in ipairs(st.shop_list or {}) do
        local ok = true
        if only_buy and #card.buy == 0 then ok = false end
        if ok and q ~= '' then
            ok = DSP.lower(card.owner):find(q, 1, true) ~= nil or tostring(card.shop_num) == q
            if not ok then
                for _, it in ipairs(card.sell) do if DSP.lower(it.name):find(q, 1, true) then ok = true; break end end
            end
            if not ok then
                for _, it in ipairs(card.buy) do if DSP.lower(it.name):find(q, 1, true) then ok = true; break end end
            end
        end
        if ok then out[#out + 1] = card end
    end
    shop_cache = { q = q, version = st.version, only_buy = only_buy, list = out }
    return out
end

local function slot_rows(list, side, w)
    local chars = fit_chars(w - 16 * d())
    if #list == 0 then imgui.TextDisabled('-') end
    for i, it in ipairs(list) do
        local scam = false
        if side == 'sell' then scam = DSP.market.scam_check(it.name, it.ench, it.price, 'sell') end
        local name = DSP.truncate_text(it.display or it.name, chars)
        if scam then
            imgui.TextColored(col(C.scam), u(name))
            imgui.TextColored(col(C.scam), u('[ВНИМАНИЕ: ВОЗМОЖНЫЙ СКАМ / ОВЕРПРАЙС]'))
        else
            imgui.Text(u(name))
        end
        imgui.TextColored(col(side == 'buy' and C.buy or C.sell), DSP.money(it.price))
        imgui.SameLine(0, 10 * d())
        imgui.TextDisabled(u('x' .. tostring(it.qty or 0)))
        if i < #list then imgui.Separator() end
    end
end

local function copy_panel(card, key)
    imgui.TextColored(col(C.accent), u('Копирование скупки в пресет'))
    imgui.SetNextItemWidth(math.min(300 * d(), imgui.GetContentRegionAvail().x))
    imgui.InputText('##dsp_copy_name_' .. key, S.copy_buf, 64)
    local bumps = { { 0, 'как есть' }, { 1, '+1$' }, { 1000, '+1000$' } }
    for _, b in ipairs(bumps) do
        local act = S.copy_bump == b[1]
        if act then imgui.PushStyleColor(imgui.Col.Button, col(C.accent, 0.75)) end
        if imgui.Button(u(b[2]) .. '##dsp_bump' .. b[1] .. key, imgui.ImVec2(110 * d(), bh())) then S.copy_bump = b[1] end
        if act then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()
    if imgui.Button(u('Сохранить пресет##dsp_copy_ok') .. key, imgui.ImVec2(200 * d(), bh())) then
        local ok, res = DSP.presets.copy_shop_buy(card, DSP.to_cp(ffi.string(S.copy_buf)), S.copy_bump)
        if ok then
            DSP.notify('Пресет "' .. res.name .. '" сохранён: ' .. #res.items .. ' поз. Займите лавку и нажмите НАЧАТЬ ВЫСТАВЛЕНИЕ.')
            S.copying = nil
            DSP.ui.preset_kind = 'buy'
        else
            DSP.notify('Копирование: ' .. tostring(res))
        end
    end
    imgui.SameLine(0, 8 * d())
    if imgui.Button(u('Отмена##dsp_copy_cancel') .. key, imgui.ImVec2(120 * d(), bh())) then S.copying = nil end
end

local function shop_card(card, idx)
    local key = tostring(card.shop_num) .. '_' .. tostring(card.owner)
    local expanded = S.expanded[key]
    local copying = S.copying == key
    local avail_w = imgui.GetContentRegionAvail().x
    local wide = avail_w >= 640 * d()
    local head_h = 22 * d() * 2 + bh() + 34 * d()
    local block_h = 190 * d()
    local h = head_h
    if copying then h = h + 22 * d() + bh() * 3 + 30 * d() end
    if expanded then h = h + (wide and (block_h + 12 * d()) or (block_h * 2 + 20 * d())) end
    imgui.PushStyleColor(imgui.Col.Border, col(C.accent, 0.55))
    if imgui.BeginChild('##dsp_shop_card_' .. idx, imgui.ImVec2(-1, h), true) then
        local title = string.format('[Лавка #%s] %s', tostring(card.shop_num), DSP.truncate_text(card.owner, 24))
        imgui.TextColored(col(C.accent), u(title))
        imgui.SameLine(0, 10 * d())
        imgui.TextDisabled(u(age_text(card.updated)))
        imgui.TextDisabled(u(string.format('Слотов продажи: %d  |  слотов скупки: %d', #card.sell, #card.buy)))
        if imgui.Button(u('[>] Отметить лавку##dsp_mark') .. idx, imgui.ImVec2(190 * d(), bh())) then
            DSP.market.mark_shop(card.shop_num, card.owner)
        end
        imgui.SameLine(0, 6 * d())
        if imgui.Button(u(expanded and 'Свернуть' or 'Подробнее') .. '##dsp_exp' .. idx, imgui.ImVec2(130 * d(), bh())) then
            S.expanded[key] = not expanded or nil
        end
        imgui.SameLine(0, 6 * d())
        if #card.buy > 0 then
            if imgui.Button(u('[+] Скопировать скупку##dsp_copy') .. idx, imgui.ImVec2(230 * d(), bh())) then
                S.copying = key
                S.copy_bump = 0
                set_buf(S.copy_buf, 64, 'Скупка_' .. tostring(card.owner))
            end
        else
            imgui.TextDisabled(u('скупки нет'))
        end
        if copying then copy_panel(card, key) end
        if expanded then
            local bw = wide and (imgui.GetContentRegionAvail().x - 8 * d()) / 2 or -1
            local bw_px = wide and bw or imgui.GetContentRegionAvail().x
            imgui.PushStyleColor(imgui.Col.Border, col(C.buy, 0.9))
            if imgui.BeginChild('##dsp_shop_buy_' .. idx, imgui.ImVec2(bw, block_h), true) then
                imgui.TextColored(col(C.buy), u('СКУПКА: игрок покупает у вас'))
                imgui.Separator()
                slot_rows(card.buy, 'buy', bw_px)
            end
            imgui.EndChild()
            imgui.PopStyleColor(1)
            if wide then imgui.SameLine(0, 8 * d()) end
            imgui.PushStyleColor(imgui.Col.Border, col(C.sell, 0.9))
            if imgui.BeginChild('##dsp_shop_sell_' .. idx, imgui.ImVec2(bw, block_h), true) then
                imgui.TextColored(col(C.sell), u('ПРОДАЖА: игрок продаёт вам'))
                imgui.Separator()
                slot_rows(card.sell, 'sell', bw_px)
            end
            imgui.EndChild()
            imgui.PopStyleColor(1)
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor(1)
end

function S.shops_tab()
    ensure()
    DSP.ui.header()
    imgui.SetNextItemWidth(math.min(340 * d(), imgui.GetContentRegionAvail().x))
    if imgui.InputTextWithHint('##dsp_shops_q', u('Ник, номер лавки или товар...'), S.shops_buf, 128) then
        S.shops_page = 1
    end
    imgui.SameLine(0, 10 * d())
    if imgui.Checkbox(u('только со скупкой'), S.shops_only_buy) then S.shops_page = 1 end
    local list = filtered_shops()
    local per = 6
    local pages = math.max(1, math.ceil(#list / per))
    if S.shops_page > pages then S.shops_page = pages end
    imgui.TextDisabled(u(string.format('Лавок: %d  (всего на сервере: %d)', #list, #(DSP.market.state.shop_list or {}))))
    local avail = imgui.GetContentRegionAvail()
    if imgui.BeginChild('##dsp_shops_list', imgui.ImVec2(-1, math.max(120 * d(), avail.y - bh() - 14 * d())), false) then
        if #list == 0 then
            imgui.TextDisabled(u('Нет лавок. Нажмите ОБНОВИТЬ (нужен интернет и va-ta.com).'))
        end
        local from = (S.shops_page - 1) * per + 1
        for i = from, math.min(#list, from + per - 1) do
            shop_card(list[i], i)
            imgui.Spacing()
        end
    end
    imgui.EndChild()
    S.shops_page = pager('dsp_shops', S.shops_page, pages)
end

-- ---------------------------------------------------------------------------
-- TAB 3: arbitrage
function S.arbitrage_tab()
    ensure()
    DSP.ui.header()
    local all = DSP.market.arbitrage()
    local list = all
    if S.arb_hide_scam[0] then
        list = {}
        for _, a in ipairs(all) do if not a.scam then list[#list + 1] = a end end
    end
    imgui.TextColored(col(C.accent), u('АРБИТРАЖ'))
    imgui.SameLine(0, 10 * d())
    imgui.TextDisabled(u(string.format('связок: %d  |  комиссия ЦР: %d%%  |  купить в лавке A (её продажа) -> сдать в лавку B (её скупка)',
        #list, DSP.market.tax_pct())))
    if imgui.Checkbox(u('скрыть подозрительные (анти-скам)'), S.arb_hide_scam) then S.arb_page = 1 end
    local per = 6
    local pages = math.max(1, math.ceil(#list / per))
    if S.arb_page > pages then S.arb_page = pages end
    local avail = imgui.GetContentRegionAvail()
    if imgui.BeginChild('##dsp_arb_list', imgui.ImVec2(-1, math.max(120 * d(), avail.y - bh() - 14 * d())), false) then
        if #list == 0 then
            imgui.TextDisabled(u('Выгодных связок нет (или рынок не загружен). Убыточные сделки не показываются.'))
        end
        local chars = fit_chars(imgui.GetContentRegionAvail().x - 24 * d())
        local from = (S.arb_page - 1) * per + 1
        for i = from, math.min(#list, from + per - 1) do
            local a = list[i]
            local h = 22 * d() * 4 + bh() + 40 * d() + (a.scam and 22 * d() or 0)
            imgui.PushStyleColor(imgui.Col.Border, a.scam and col(C.scam) or col(C.accent, 0.55))
            if imgui.BeginChild('##dsp_arb_' .. i, imgui.ImVec2(-1, h), true) then
                imgui.TextColored(col(C.accent), u('Предмет: ' .. DSP.truncate_text(a.display, chars - 9)))
                if a.scam then
                    imgui.TextColored(col(C.scam), u('[ВНИМАНИЕ: ВОЗМОЖНЫЙ СКАМ / ОВЕРПРАЙС] цена далека от средней'))
                end
                imgui.TextColored(col(C.sell), u(DSP.truncate_text(string.format('Купить в [Лавке #%s] у %s за %s (x%d)',
                    a.buy_shop, a.buy_owner, DSP.money(a.buy_price), a.buy_qty), chars)))
                imgui.TextColored(col(C.buy), u(DSP.truncate_text(string.format('-> Сдать в [Лавку #%s] игроку %s за %s (x%d)',
                    a.sell_shop, a.sell_owner, DSP.money(a.sell_price), a.sell_qty), chars)))
                imgui.TextColored(col(C.buy), u(string.format('Чистая прибыль: +%s (%.1f%%)  |  x%d = +%s',
                    DSP.money(a.unit), a.roi, a.qty, DSP.money(a.total))))
                if imgui.Button(u('[>] Найти лавку покупки##dsp_arb_b') .. i, imgui.ImVec2(250 * d(), bh())) then
                    DSP.market.mark_shop(a.buy_shop, a.buy_owner)
                end
                imgui.SameLine(0, 8 * d())
                if imgui.Button(u('[>] Найти лавку сдачи##dsp_arb_s') .. i, imgui.ImVec2(240 * d(), bh())) then
                    DSP.market.mark_shop(a.sell_shop, a.sell_owner)
                end
            end
            imgui.EndChild()
            imgui.PopStyleColor(1)
            imgui.Spacing()
        end
    end
    imgui.EndChild()
    S.arb_page = pager('dsp_arb', S.arb_page, pages)
end

-- ---------------------------------------------------------------------------
-- TAB 4: item catalog
S.CATS = {
    { 'Все', nil },
    { 'Ларцы', { 'ларец', 'ларц', 'тайник', 'кейс', 'сундук', 'подарок' } },
    { 'Скины', { 'скин' } },
    { 'Аксессуары', { 'аксессуар', 'шар', 'маск', 'очки', 'шляп', 'кепк', 'рюкзак', 'часы', 'крыл', 'нимб', 'серьг', 'цепь', 'кольцо', 'браслет', 'шарф', 'бейсболк' } },
    { 'Ресурсы', { 'руда', 'металл', 'ткань', 'бумаг', 'дерев', 'доск', 'уголь', 'камен', 'нефть', 'семен', 'ресурс', 'слит', 'кирпич', 'хлопок', 'сыр', 'стекл', 'песок', 'резин', 'пластик', 'материал' } },
    { 'Транспорт', { 'транспорт', 'автомобил', 'мотоцикл', 'вертол', 'лодк', 'диск', 'номер' } },
    { 'Оружие', { 'deagle', 'm4', 'ak-47', 'ak47', 'дробовик', 'пистолет', 'винтовк', 'оружи', 'патрон', 'нож', 'бита' } },
}

local function categorize(lname)
    for i = 2, #S.CATS do
        for _, kw in ipairs(S.CATS[i][2]) do
            if lname:find(kw, 1, true) then return i end
        end
    end
    return #S.CATS + 1 -- "прочее"
end

function S.catalog_all()
    if S.cat_all and S.cat_all_n == (DSP.items.loaded and 1 or 0) then return S.cat_all end
    local all = {}
    for id, nm in pairs(DSP.items.by_id or {}) do
        local name = DSP.clean_text(nm)
        if name ~= '' then
            local l = DSP.lower(name)
            all[#all + 1] = { id = id, name = name, lname = l, cat = categorize(l) }
        end
    end
    table.sort(all, function(a, b)
        if a.lname ~= b.lname then return a.lname < b.lname end
        return a.id < b.id
    end)
    S.cat_all = all
    S.cat_all_n = DSP.items.loaded and 1 or 0
    return all
end

local cat_cache = { q = nil, cat = nil, n = -1, list = {} }

function S.catalog_filter(q_cp, cat)
    local all = S.catalog_all()
    local q = DSP.lower(DSP.trim(q_cp or ''))
    cat = cat or 1
    if cat_cache.q == q and cat_cache.cat == cat and cat_cache.n == #all then return cat_cache.list end
    local out = {}
    local qid = tonumber(q)
    for _, it in ipairs(all) do
        local ok = (cat == 1) or it.cat == cat
        if ok and q ~= '' then ok = it.lname:find(q, 1, true) ~= nil or (qid ~= nil and it.id == qid) end
        if ok then out[#out + 1] = it end
    end
    cat_cache = { q = q, cat = cat, n = #all, list = out }
    return out
end

local function suggest_price(kind, name)
    local row = DSP.market.row_for(name, 0)
    if row then
        local p = kind == 'buy' and DSP.market.buy_target(row) or DSP.market.sell_target(row)
        if p > 0 then return p end
    end
    local a = DSP.avg and DSP.avg.get and DSP.avg.get(name)
    if a then return kind == 'buy' and (a.buy or 0) or (a.sell or 0) end
    return 0
end

function S.catalog_tab()
    ensure()
    imgui.TextColored(col(C.accent), u('КАТАЛОГ ПРЕДМЕТОВ'))
    imgui.SameLine(0, 10 * d())
    imgui.TextDisabled(u(string.format('в базе: %d', #S.catalog_all())))
    imgui.SetNextItemWidth(math.min(360 * d(), imgui.GetContentRegionAvail().x))
    if imgui.InputTextWithHint('##dsp_cat_q', u('Название или ID...'), S.cat_buf, 128) then S.cat_page = 1 end
    for i, c in ipairs(S.CATS) do
        if i > 1 then imgui.SameLine(0, 4 * d()) end
        local act = S.cat_cat == i
        if act then imgui.PushStyleColor(imgui.Col.Button, col(C.accent, 0.7)) end
        if imgui.Button(u(c[1]) .. '##dsp_cat' .. i, imgui.ImVec2(0, bh())) then S.cat_cat = i; S.cat_page = 1 end
        if act then imgui.PopStyleColor(1) end
    end
    -- inline add editor
    local ed = S.cat_edit
    if ed then
        imgui.PushStyleColor(imgui.Col.Border, col(ed.kind == 'buy' and C.buy or C.sell))
        if imgui.BeginChild('##dsp_cat_edit', imgui.ImVec2(-1, bh() * 2 + 52 * d()), true) then
            imgui.TextColored(col(ed.kind == 'buy' and C.buy or C.sell),
                u((ed.kind == 'buy' and 'В скупку: ' or 'В продажу: ') .. DSP.truncate_text(ed.name, 40)))
            imgui.SetNextItemWidth(200 * d())
            imgui.InputInt(u('цена$##dsp_cat_price'), S.cat_price, 1000, 100000)
            if ed.kind == 'buy' then
                imgui.SameLine(0, 10 * d())
                imgui.SetNextItemWidth(140 * d())
                imgui.InputInt(u('кол-во##dsp_cat_qty'), S.cat_qty, 1, 10)
            end
            if imgui.Button(u('Добавить##dsp_cat_ok'), imgui.ImVec2(160 * d(), bh())) then
                local ok, err = DSP.presets.add_manual(ed.kind, ed.name, 0, S.cat_price[0],
                    ed.kind == 'buy' and S.cat_qty[0] or 1)
                if ok then S.cat_edit = nil else DSP.notify('Каталог: ' .. tostring(err)) end
            end
            imgui.SameLine(0, 8 * d())
            if imgui.Button(u('Отмена##dsp_cat_cancel'), imgui.ImVec2(120 * d(), bh())) then S.cat_edit = nil end
        end
        imgui.EndChild()
        imgui.PopStyleColor(1)
    end
    local list = S.catalog_filter(DSP.to_cp(ffi.string(S.cat_buf)), S.cat_cat)
    local per = 25
    local pages = math.max(1, math.ceil(#list / per))
    if S.cat_page > pages then S.cat_page = pages end
    imgui.TextDisabled(u(string.format('Найдено: %d', #list)))
    local avail = imgui.GetContentRegionAvail()
    if imgui.BeginChild('##dsp_cat_list', imgui.ImVec2(-1, math.max(120 * d(), avail.y - bh() - 14 * d())), true) then
        if #list == 0 then imgui.TextDisabled(u('Ничего не найдено (или нет файла arz_items.json).')) end
        local btn_w = 130 * d()
        local text_w = imgui.GetContentRegionAvail().x - btn_w * 2 - 24 * d()
        local chars = fit_chars(text_w)
        local from = (S.cat_page - 1) * per + 1
        for i = from, math.min(#list, from + per - 1) do
            local it = list[i]
            imgui.TextDisabled(string.format('%5d', it.id))
            imgui.SameLine(0, 8 * d())
            imgui.Text(u(DSP.truncate_text(it.name, chars - 7)))
            imgui.SameLine(math.max(0, imgui.GetWindowWidth() - btn_w * 2 - 24 * d()))
            if imgui.Button(u('+ В скупку##dsp_cb') .. it.id, imgui.ImVec2(btn_w, bh())) then
                S.cat_edit = { kind = 'buy', name = it.name, id = it.id }
                S.cat_price[0] = suggest_price('buy', it.name)
                S.cat_qty[0] = 1
            end
            imgui.SameLine(0, 6 * d())
            if imgui.Button(u('+ В продажу##dsp_cs') .. it.id, imgui.ImVec2(btn_w, bh())) then
                S.cat_edit = { kind = 'sell', name = it.name, id = it.id }
                S.cat_price[0] = suggest_price('sell', it.name)
                S.cat_qty[0] = 1
            end
        end
    end
    imgui.EndChild()
    S.cat_page = pager('dsp_cat', S.cat_page, pages)
end

end
__mod_35_screens()

local function __mod_40_auto()
-- Auto-buy / auto-sell engines: inventory scan + server dialogs.
DSP.auto = DSP.auto or {}
DSP.auto.buy_running = false
DSP.auto.sell_running = false
DSP.auto.scanning = false
DSP.auto.inv = {}
DSP.auto.inv_status = 'не сканирован'
DSP.auto.sell_confirmed = false
DSP.auto.sell_forbidden = false
DSP.auto.sell_no_slots = false
DSP.auto.status = 'готов'
DSP.auto._prev_dialog = nil

local function log(s, kind) DSP.add_log(s, kind) end

if DSP.settings.delay_ms == nil then DSP.settings.delay_ms = 500 end
pcall(math.randomseed, os.time())
DSP.auto.progress = { kind = nil, done = 0, total = 0 }

-- Anti-cheat pacing between listed slots: (delay_ms or 500) + random(50..120) ms.
function DSP.auto.delay_ms()
    local base = tonumber(DSP.settings.delay_ms) or 500
    if base < 300 then base = 300 elseif base > 1000 then base = 1000 end
    return base + math.random(50, 120)
end

function DSP.auto.pace()
    wait(DSP.auto.delay_ms())
end

function DSP.auto.set_progress(kind, done, total)
    DSP.auto.progress = { kind = kind, done = done or 0, total = total or 0 }
end

-- 0..1 progress of the running listing
function DSP.auto.progress_frac()
    local p = DSP.auto.progress
    if not p or (p.total or 0) <= 0 then return 0 end
    return math.max(0, math.min(1, p.done / p.total))
end

function DSP.auto.player_money()
    local m = 0
    if getPlayerMoney then
        local ok, v = pcall(getPlayerMoney, PLAYER_HANDLE)
        if not ok or not v then ok, v = pcall(getPlayerMoney) end
        if ok then m = tonumber(v) or 0 end
    end
    return m
end

-- Returns needed, have, missing (missing > 0 means not enough money).
function DSP.auto.budget_check()
    local need = DSP.presets and DSP.presets.budget and DSP.presets.budget('buy') or 0
    local have = DSP.auto.player_money()
    return need, have, math.max(0, need - have)
end

function DSP.auto.status_text()
    return DSP.auto.status .. '  |  инвентарь: ' .. DSP.auto.inv_status
end

local function clean(s)
    return (tostring(s or ''):gsub('{%x+}', ''))
end

function DSP.dialog_clean(s)
    s = tostring(s or '')
    local ok, cp = pcall(function() return require('encoding').CP1251:encode(s) end)
    if ok and cp and cp ~= '' and not s:find('[\192-\255]') then s = cp end
    return clean(s)
end

local function base_name(name)
    return (tostring(name or ''):gsub('%s*%(%+%d+%)%s*$', ''))
end

local function has_qty(text)
    return tostring(text or ''):find('Количество', 1, true) ~= nil
end

local function close_dialog()
    if sampIsDialogActive() then
        pcall(sampSendDialogResponse, sampGetCurrentDialogId(), 0, 0, '')
        local t = os.clock() + 0.35
        while os.clock() < t and sampIsDialogActive() do wait(25) end
    end
end

local function wait_dialog(ids, ms)
    local t = os.clock() + (ms or 2000) / 1000
    while os.clock() < t do
        wait(30)
        if sampIsDialogActive() then
            local id = sampGetCurrentDialogId()
            if not ids then return id end
            for _, want in ipairs(ids) do
                if id == want then return id end
            end
        end
    end
    return nil
end

local function wait_text(id, ms)
    local t = os.clock() + (ms or 800) / 1000
    local prev, stable = '', 0
    while os.clock() < t do
        wait(30)
        if not sampIsDialogActive() or sampGetCurrentDialogId() ~= id then
            return prev
        end
        local cur = sampGetDialogText() or ''
        if cur ~= '' then
            if cur == prev then
                stable = stable + 1
                if stable >= 2 then return cur end
            else
                stable = 0
            end
            prev = cur
        end
    end
    return prev
end

function _G.dsp_click_slot(interfaceid, id, subid, json_str)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 63)
    raknetBitStreamWriteInt8(bs, interfaceid)
    raknetBitStreamWriteInt32(bs, id)
    raknetBitStreamWriteInt32(bs, subid)
    raknetBitStreamWriteInt16(bs, #json_str)
    raknetBitStreamWriteString(bs, json_str)
    raknetSendBitStreamEx(bs, 1, 7, 1)
    raknetDeleteBitStream(bs)
end

local function parse_inventory(text)
    local raw = {}
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        local clean_line = clean(line)
        local slot_s, name, cnt_s
        slot_s, name, cnt_s = clean_line:match('%[(%d+)%]%s+(.-)%s+%{[^}]*%}%[(%d+)%s+')
        if not slot_s then
            slot_s, name, cnt_s = clean_line:match('%[(%d+)%]%s+(.-)%s+%[(%d+)%s+')
        end
        if not slot_s then
            slot_s, name, cnt_s = clean_line:match('%[(%d+)%]%s+(.-)%s+%[(%d+)%]')
        end
        if slot_s and name and cnt_s then
            name = name:match('^%s*(.-)%s*$') or name
            if name ~= '' and name ~= 'Пусто' then
                table.insert(raw, { slot = tonumber(slot_s), name = name, count = tonumber(cnt_s) or 1 })
            end
        end
    end
    local grouped, by_name = {}, {}
    for _, it in ipairs(raw) do
        local g = by_name[it.name]
        if not g then
            g = { name = it.name, count = 0, stacks = {} }
            by_name[it.name] = g
            table.insert(grouped, g)
        end
        g.count = g.count + it.count
        table.insert(g.stacks, { slot = it.slot, count = it.count })
    end
    return grouped
end

function DSP.auto.scan_inventory()
    if DSP.auto.scanning then return end
    DSP.auto.scanning = true
    DSP.auto.inv = {}
    DSP.auto.inv_status = 'сканирование...'
    log('Инвентарь: открываю /mm...')
    sampSendChat('/mm')
    lua_thread.create(function()
        local deadline = os.clock() + 25
        while DSP.auto.scanning and os.clock() < deadline do wait(50) end
        if DSP.auto.scanning then
            DSP.auto.scanning = false
            DSP.auto.inv_status = 'таймаут'
            log('Инвентарь: таймаут. Откройте инвентарь через /mm вручную и повторите.', 'error')
        end
    end)
end

local function inventory_dialog(id, text)
    if id == 25494 or id == 25493 then return true end
    local t = clean(text)
    return (t:find('%[%d+%]') ~= nil and (t:find('%[%d+ шт%]') ~= nil or t:find('Инвентарь:') ~= nil))
        or t:find('Следующая страница', 1, true) ~= nil
        or t:find('Предыдущая страница', 1, true) ~= nil
end

function DSP.auto.on_dialog(id, style, title, b1, b2, text)
    if DSP.auto.scanning then
        if id == 722 or id == 600 or id == 235 then
            lua_thread.create(function()
                wait(120)
                pcall(sampSendDialogResponse, id, 1, 0, '')
            end)
            return true
        end
        if inventory_dialog(id, text) then
            local items = parse_inventory(text)
            for _, it in ipairs(items) do
                local found = false
                for _, old in ipairs(DSP.auto.inv) do
                    if old.name == it.name then
                        old.count = old.count + it.count
                        for _, st in ipairs(it.stacks) do table.insert(old.stacks, st) end
                        found = true
                        break
                    end
                end
                if not found then table.insert(DSP.auto.inv, it) end
            end
            DSP.auto.inv_status = #DSP.auto.inv .. ' поз. (' ..
                (function() local n = 0; for _, x in ipairs(DSP.auto.inv) do n = n + x.count end; return n end)() .. ' шт)'
            local next_idx
            local line_no = 0
            for ln in tostring(text or ''):gmatch('[^\n]+') do
                line_no = line_no + 1
                if line_no > 1 and ln:find('Следующая страница', 1, true) then
                    next_idx = line_no - 2
                    break
                end
            end
            if next_idx then
                log('Инвентарь: ' .. DSP.auto.inv_status .. ', дальше...')
                lua_thread.create(function()
                    wait(140)
                    pcall(sampSendDialogResponse, id, 1, next_idx, '')
                end)
            else
                DSP.auto.scanning = false
                log('Инвентарь готов: ' .. DSP.auto.inv_status, 'ok')
                lua_thread.create(function()
                    wait(100)
                    pcall(sampSendDialogResponse, id, 0, 0, '')
                    wait(160)
                    pcall(_G.dsp_click_slot, 52, -1, 4, '""')
                end)
            end
            return true
        end
    end
    if DSP.auto.sell_running then
        local t = clean(text)
        if t:find('Успешно выставлено на продажу', 1, true) then
            DSP.auto.sell_confirmed = true
        end
        if t:find('нельзя выставлять', 1, true) or t:find('Запрещено', 1, true) then
            DSP.auto.sell_forbidden = true
            DSP.auto.sell_confirmed = true
        end
        if t:find('нет свободных мест', 1, true) or t:find('Нет свободных мест', 1, true) then
            DSP.auto.sell_no_slots = true
            DSP.auto.sell_confirmed = true
        end
    end
    return false
end

function DSP.auto.install()
    local ok, sampev = pcall(require, 'samp.events')
    if not ok or not sampev then
        log('Авто: samp.events недоступен', 'error')
        return
    end
    DSP.auto._prev_dialog = sampev.onShowDialog
    sampev.onShowDialog = function(id, style, title, b1, b2, text)
        local prev = DSP.auto._prev_dialog
        local ret
        if prev then
            local r = { pcall(prev, id, style, title, b1, b2, text) }
            if r[1] then ret = r[2] end
        end
        local intercept = DSP.auto.on_dialog(id, style, title, b1, b2, text)
        if intercept then return false end
        return ret
    end
end

local function queue_sell()
    local queue = {}
    for _, p in ipairs(DSP.settings.sell_preset.items) do
        if p.enabled ~= false and (tonumber(p.price) or 0) > 0 then
            local target = base_name(p.name)
            local left = tonumber(p.qty) or 1
            for _, inv in ipairs(DSP.auto.inv) do
                if inv.name == target or inv.name == p.name then
                    for _, st in ipairs(inv.stacks) do
                        if left <= 0 then break end
                        local take = math.min(st.count, left)
                        if take > 0 then
                            table.insert(queue, {
                                name = p.name, base = target, price = p.price,
                                qty = take, slot = st.slot,
                            })
                            left = left - take
                        end
                    end
                    break
                end
            end
        end
    end
    return queue
end

function DSP.auto.start_sell()
    if DSP.auto.sell_running then return end
    if DSP.auto.buy_running then return end
    local items = DSP.settings.sell_preset.items
    local n = 0
    for _, it in ipairs(items) do if it.enabled ~= false then n = n + 1 end end
    if n == 0 then DSP.notify('Продажа: пресет пуст'); return end
    if #DSP.auto.inv == 0 then
        DSP.notify('Продажа: сначала просканируйте инвентарь')
        return
    end
    local queue = queue_sell()
    if #queue == 0 then DSP.notify('Продажа: в инвентаре нет позиций из пресета'); return end
    DSP.auto.sell_running = true
    DSP.auto.sell_confirmed = false
    DSP.auto.sell_forbidden = false
    DSP.auto.sell_no_slots = false
    DSP.auto.status = 'продажа...'
    log('Продажа: ' .. #queue .. ' стек(ов)')
    lua_thread.create(function()
        local done = 0
        DSP.auto.set_progress('sell', 0, #queue)
        for qi, it in ipairs(queue) do
            if not DSP.auto.sell_running then break end
            DSP.auto.set_progress('sell', qi - 1, #queue)
            DSP.auto.status = 'продажа: ' .. it.name .. ' (' .. done .. '/' .. #queue .. ')'
            local json = '{"amount":' .. it.qty .. ',"id":0,"slot":' .. it.slot .. ',"type":1}'
            local got = false
            for attempt = 1, 3 do
                close_dialog()
                DSP.auto.sell_confirmed = false
                pcall(_G.dsp_click_slot, 60, -1, 2, json)
                local id = wait_dialog({ 26547 }, 1800)
                if id then
                    local txt = DSP.dialog_clean(wait_text(id, 700))
                    local base = base_name(it.base)
                    if txt:find(base, 1, true) then
                        got = true
                        break
                    end
                    log('Продажа: диалог не тот (' .. tostring(attempt) .. '): ' .. txt:sub(1, 60), 'error')
                    close_dialog()
                end
                wait(180)
            end
            if got then
                local txt = DSP.dialog_clean(sampGetDialogText() or '')
                local resp = has_qty(txt) and (tostring(it.qty) .. ',' .. tostring(it.price))
                    or tostring(it.price)
                if DSP.settings.dry_run then
                    log('dry-run: продал бы ' .. it.name .. ' x' .. it.qty .. ' @ ' .. DSP.money(it.price))
                    close_dialog()
                else
                    DSP.auto.sell_confirmed = false
                    pcall(sampSendDialogResponse, 26547, 1, 0, resp)
                    local t = os.clock() + 4
                    while not DSP.auto.sell_confirmed and os.clock() < t do wait(40) end
                    pcall(sampSendDialogResponse, 26547, 0, 0, '')
                    if DSP.auto.sell_no_slots then
                        log('Продажа: нет свободных мест', 'error')
                        DSP.auto.sell_running = false
                        break
                    end
                    if DSP.auto.sell_forbidden then
                        log('Продажа: запрещено для ' .. it.name, 'error')
                    elseif DSP.auto.sell_confirmed then
                        done = done + 1
                        log('Продано: ' .. it.name .. ' x' .. it.qty .. ' @ ' .. DSP.money(it.price), 'ok')
                    else
                        log('Продажа: нет подтверждения для ' .. it.name, 'error')
                    end
                end
                DSP.auto.pace()
            else
                log('Продажа: не открылся диалог для ' .. it.name .. ' (slot ' .. it.slot .. ')', 'error')
                close_dialog()
            end
            DSP.auto.set_progress('sell', qi, #queue)
        end
        DSP.auto.sell_running = false
        DSP.auto.status = 'продажа: ' .. done .. '/' .. #queue
        log('Продажа завершена: ' .. done .. '/' .. #queue, 'ok')
        DSP.auto.scan_inventory()
    end)
end

function DSP.auto.stop_sell()
    DSP.auto.sell_running = false
    DSP.auto.status = 'продажа остановлена'
    close_dialog()
    log('Продажа остановлена')
end

local function find_list_index(text, name)
    local want = base_name(name):lower()
    local idx = 0
    for line in tostring(text or ''):gmatch('[^\n]+') do
        local nm = clean(line):match('^%d+[%.%)%s]+(.-)%s*$')
            or clean(line):match('^%s*(.-)%s*$')
        if nm and nm:lower():find(want, 1, true) then return idx end
        idx = idx + 1
    end
    local first = want:match('^(%S+)')
    if first and #first >= 4 then
        idx = 0
        for line in tostring(text or ''):gmatch('[^\n]+') do
            if clean(line):lower():find(first, 1, true) then return idx end
            idx = idx + 1
        end
    end
    return nil
end

local function open_shop_menu()
    close_dialog()
    pcall(_G.dsp_click_slot, 8, 7, -1, '')
    return wait_dialog({ 3040 }, 2500) ~= nil
end

local function buy_one(it, pi, total)
    DSP.auto.status = 'скупка: ' .. it.name .. ' (' .. pi .. '/' .. total .. ')'
    if not sampIsDialogActive() or sampGetCurrentDialogId() ~= 3040 then
        if not open_shop_menu() then
            log('Скупка: меню не открылось для ' .. it.name, 'error')
            return false
        end
    end
    wait_text(3040, 350)
    pcall(sampSendDialogResponse, 3040, 1, 2, '')
    local id = wait_dialog({ 25663 }, 3000)
    if not id then
        log('Скупка: строка поиска не открылась', 'error')
        return false
    end
    wait_text(25663, 700)
    local search = base_name(it.name):sub(1, 24)
    pcall(sampSendDialogResponse, 25663, 1, 0, search)
    id = wait_dialog({ 25664 }, 3500)
    if not id then
        log('Скупка: результаты не открылись: ' .. it.name, 'error')
        return false
    end
    local list_text = DSP.dialog_clean(wait_text(25664, 500))
    local idx = find_list_index(list_text, it.name)
    if not idx then
        log('Скупка: не найдено: ' .. it.name, 'error')
        close_dialog()
        return false
    end
    pcall(sampSendDialogResponse, 25664, 1, idx, '')
    id = wait_dialog({ 26560, 26563 }, 3000)
    if not id then
        log('Скупка: диалог цены не открылся: ' .. it.name, 'error')
        return false
    end
    if id == 26560 then
        pcall(sampSendDialogResponse, id, 1, 0, '')
        id = wait_dialog({ 26563 }, 2000)
    end
    if id ~= 26563 then return false end
    wait_text(26563, 500)
    local txt = DSP.dialog_clean(sampGetDialogText() or '')
    local base = base_name(it.name)
    if not txt:find(base, 1, true) then
        local first = base:lower():match('^(%S+)')
        if not (first and #first >= 4 and txt:lower():find(first, 1, true)) then
            log('Скупка: в диалоге другой товар: ' .. it.name, 'error')
            close_dialog()
            return false
        end
    end
    local qty = tonumber(it.qty) or 1
    if qty < 1 then qty = 1 end
    local resp = has_qty(txt) and (tostring(qty) .. ',' .. tostring(it.price))
        or tostring(it.price)
    if DSP.settings.dry_run then
        log('dry-run: купил бы ' .. it.name .. ' x' .. qty .. ' @ ' .. DSP.money(it.price))
        close_dialog()
        return 'dry'
    end
    pcall(sampSendDialogResponse, 26563, 1, 0, resp)
    log('Скупка: ' .. it.name .. ' x' .. qty .. ' @ ' .. DSP.money(it.price), 'ok')
    local t = os.clock() + 0.7
    while os.clock() < t and sampIsDialogActive() do wait(30) end
    return 'bought'
end

function DSP.auto.start_buy()
    if DSP.auto.buy_running then return end
    if DSP.auto.sell_running then return end
    local list = {}
    for _, it in ipairs(DSP.settings.buy_preset.items) do
        if it.enabled ~= false and (tonumber(it.price) or 0) > 0 then table.insert(list, it) end
    end
    if #list == 0 then DSP.notify('Скупка: пресет пуст или цены 0'); return end
    local need, have, missing = DSP.auto.budget_check()
    if missing > 0 and have > 0 then
        DSP.notify('Внимание: не хватает ' .. DSP.money(missing):gsub('^%$', '') .. '$ для полной скупки!')
    end
    DSP.auto.buy_running = true
    DSP.auto.status = 'скупка...'
    log('Скупка: ' .. #list .. ' позиций' .. (DSP.settings.dry_run and ' (dry-run)' or ''))
    lua_thread.create(function()
        if not open_shop_menu() then
            log('Скупка: лавка не открылась. Подойдите к лавке.', 'error')
            DSP.auto.buy_running = false
            DSP.auto.status = 'скупка: ошибка'
            return
        end
        local bought, dry = 0, 0
        DSP.auto.set_progress('buy', 0, #list)
        for pi, it in ipairs(list) do
            if not DSP.auto.buy_running then break end
            local ok = buy_one(it, pi, #list)
            if ok == 'bought' then bought = bought + 1
            elseif ok == 'dry' then dry = dry + 1 end
            close_dialog()
            DSP.auto.set_progress('buy', pi, #list)
            if pi < #list and DSP.auto.buy_running then
                DSP.auto.pace()
                if not open_shop_menu() then break end
            end
        end
        DSP.auto.buy_running = false
        DSP.auto.status = 'скупка: ' .. bought .. '/' .. #list .. (dry > 0 and (' (dry ' .. dry .. ')') or '')
        log('Скупка завершена: ' .. bought .. '/' .. #list, 'ok')
    end)
end

function DSP.auto.stop_buy()
    DSP.auto.buy_running = false
    DSP.auto.status = 'скупка остановлена'
    close_dialog()
    log('Скупка остановлена')
end

end
__mod_40_auto()

local function __mod_45_live()
-- Live game hooks: trade (iface 57) and lavka (iface 60/52) parsing.
DSP.live = DSP.live or {}
local L = DSP.live

L.trade = { partner = '', give = {}, get = {}, money_give = 0, money_get = 0,
            opened = 0, updated = 0, complete = false }
L.shop  = { owner = '', num = '', sell = {}, buy = {}, seen = {},
            opened = 0, updated = 0, items_updated = 0, menu_closed = 0 }

local function now()
    return os.time()
end

local function decode(raw)
    raw = tostring(raw or ''):gsub('%z+$', '')
    if raw == '' then return nil end
    local ok, d = pcall(decodeJson, raw)
    if ok and type(d) == 'table' then return d end
    return nil
end

function DSP.money_val(s)
    s = tostring(s or ''):gsub('{[%x]+}', ''):gsub('%s+', '')
    if s == '' then return 0 end
    local mult = 1
    local low = s:lower()
    if low:find('кк', 1, true) or low:find('kk', 1, true) then
        mult = 1000000
        s = s:gsub('[Кк]к', ''):gsub('[Kk]k', '')
    elseif low:find('кк', 1, true) == nil and (low:find('к', 1, true) or low:find('k', 1, true)) then
        mult = 1000
        s = s:gsub('[Кк]', ''):gsub('[Kk]', '')
    elseif low:find('м', 1, true) or low:find('m', 1, true) then
        mult = 1000000
        s = s:gsub('[Мм]', ''):gsub('[Mm]', '')
    end
    s = s:gsub('%$', ''):gsub('%.', ''):gsub(',', '.')
    local n = tonumber(s:match('(%d+%.?%d*)'))
    if not n then return 0 end
    return math.floor(n * mult)
end

local function strip(s)
    return DSP.clean_text(s or '')
end

local function name_ench(s)
    s = strip(s)
    local base, e = s:match('^(.-)%s*%((%d+)%)%s*$')
    if base and base ~= '' then return strip(base), tonumber(e) or 0 end
    return s, 0
end

function L.item_from_id(raw, ench, qty)
    local id, e = DSP.parse_item_id(raw, ench)
    if id <= 0 then return nil end
    local nm = DSP.items.name(id)
    if nm:find('^ID:') then return nil end
    return { name = nm, ench = e, qty = math.max(1, tonumber(qty) or 1), id = id }
end

function L.reset_trade(partner)
    L.trade = {
        partner = partner or '',
        give = {}, get = {},
        money_give = 0, money_get = 0,
        opened = now(), updated = now(),
        complete = false,
    }
    DSP.flog('TRADE reset partner=' .. tostring(partner or ''))
end

function L.reset_shop(owner, num)
    L.shop = {
        owner = owner or '', num = tostring(num or ''),
        sell = {}, buy = {}, seen = {},
        opened = now(), updated = now(), items_updated = 0, menu_closed = 0,
    }
    DSP.flog('SHOP reset owner=' .. tostring(owner or '') .. ' num=' .. tostring(num or ''))
end

function L.ensure_shop()
    if not L.shop or L.shop.updated == 0 then L.reset_shop('', '') end
    return L.shop
end

function L.merge_side(list, items, replace)
    if replace then
        for i = #list, 1, -1 do list[i] = nil end
    end
    local idx = {}
    for _, it in ipairs(list) do idx[it.id .. '|' .. tostring(it.ench or 0)] = it end
    for _, it in ipairs(items) do
        local k = it.id .. '|' .. tostring(it.ench or 0)
        local ex = idx[k]
        if ex then
            ex.qty = it.qty
        else
            list[#list + 1] = it
            idx[k] = it
        end
    end
end

function L.parse_trade_items(raw, kind)
    local items = {}
    for obj in tostring(raw or ''):gmatch('{([^}]+)}') do
        local item_raw = obj:match('"item"%s*:%s*"([^"]+)"') or obj:match('"item"%s*:%s*(%d+)')
        if item_raw then
            local ench = tonumber(obj:match('"enchant"%s*:%s*(%d+)')) or 0
            local qty = tonumber(obj:match('"amount"%s*:%s*(%d+)'))
                or tonumber(obj:match('"count"%s*:%s*(%d+)')) or 1
            local it = L.item_from_id(item_raw, ench, qty)
            if it then items[#items + 1] = it end
        end
    end
    return items
end

function L.handle_trade(sub, raw)
    local t = L.trade
    if sub == 0 then
        local d = decode(raw)
        local partner = d and (d.name or d.owner or d.nick) or raw:match('"name"%s*:%s*"([^"]+)"')
        partner = partner and strip(partner):match('^(.-)%s*%(%d+%)%s*$') or strip(partner or '')
        if partner == '' then partner = '?' end
        if t.partner ~= partner or now() - (t.updated or 0) > 300 then
            L.reset_trade(partner)
        else
            t.partner = partner
            t.updated = now()
        end
        return
    end
    if not t or t.opened == 0 then L.reset_trade(t and t.partner or '?') end
    t = L.trade
    if sub == 2 then
        local tp = tonumber(raw:match('"type"%s*:%s*(%d+)')) or 0
        local items = L.parse_trade_items(raw, tp)
        if tp == 3 then
            L.merge_side(t.give, items, true)
        elseif tp == 4 then
            L.merge_side(t.get, items, false)
        else
            return
        end
        t.updated = now()
        DSP.flog('TRADE sub2 type=' .. tostring(tp) .. ' n=' .. tostring(#items))
    elseif sub == 6 then
        local sg = tonumber(raw:match('"self"%s*:%s*{[^}]-"value"%s*:%s*(%d+)'))
        local tg = tonumber(raw:match('"target"%s*:%s*{[^}]-"value"%s*:%s*(%d+)'))
        if sg then t.money_give = sg end
        if tg then t.money_get = tg end
        t.updated = now()
        DSP.flog('TRADE sub6 give=' .. tostring(t.money_give) .. ' get=' .. tostring(t.money_get))
    elseif sub == 4 then
        local sc = tonumber(raw:match('"self"%s*:%s*{[^}]-"confirm"%s*:%s*(%d+)')) or 0
        local tc = tonumber(raw:match('"target"%s*:%s*{[^}]-"confirm"%s*:%s*(%d+)')) or 0
        local sa = tonumber(raw:match('"self"%s*:%s*{[^}]-"accept"%s*:%s*(%d+)')) or 0
        local ta = tonumber(raw:match('"target"%s*:%s*{[^}]-"accept"%s*:%s*(%d+)')) or 0
        if sa == 1 and ta == 1 and sc == 1 and tc == 1 then
            t.complete = true
            DSP.flog('TRADE complete partner=' .. tostring(t.partner))
            if DSP.logs and DSP.logs.record_trade then
                DSP.logs.record_trade(t.partner, t.give, t.get, t.money_give, t.money_get, 'accepted')
            end
        end
        t.updated = now()
    end
end

function L.parse_shop_item(obj, side)
    local s = L.ensure_shop()
    local item_raw = obj:match('"item"%s*:%s*"([^"]+)"') or obj:match('"item"%s*:%s*(%d+)')
    if not item_raw then return end
    local ench = tonumber(obj:match('"enchant"%s*:%s*(%d+)')) or 0
    local amount = tonumber(obj:match('"amount"%s*:%s*(%d+)')) or 0
    local text = obj:match('"text"%s*:%s*"([^"]*)"')
    local text_price = text and DSP.money_val(text) or 0
    local price = text_price > amount and text_price or amount
    if price <= 0 then return end
    local it = L.item_from_id(item_raw, ench, 1)
    if not it then return end
    local key = tostring(it.id) .. '|' .. tostring(price) .. '|' .. tostring(it.ench or 0)
    local list = side == 'sell' and s.sell or s.buy
    local ex = s.seen[key]
    if ex then
        ex.qty = ex.qty + 1
    else
        local e = { name = it.name, ench = it.ench, id = it.id, price = price, qty = 1 }
        s.seen[key] = e
        list[#list + 1] = e
    end
    DSP.db.learn(it.id, it.ench, price, side)
end

function L.handle_shop_items(raw)
    local tp = tonumber(raw:match('"type"%s*:%s*(%d+)')) or 0
    if tp ~= 13 and tp ~= 28 then return end
    local s = L.ensure_shop()
    local first_slot = tonumber(raw:match('"slot"%s*:%s*(%d+)'))
    local stale = now() - (s.items_updated or 0) > 10
    if first_slot == 0 and ((s.menu_closed or 0) > 0 or stale) then
        local keep_owner = now() - (s.updated or 0) <= 2 and s.owner or ''
        local keep_num = keep_owner ~= '' and s.num or ''
        L.reset_shop(keep_owner, keep_num)
        s = L.shop
    end
    s.updated = now()
    s.items_updated = s.updated
    if s.opened == 0 then s.opened = s.updated end
    s.menu_closed = 0
    local side = tp == 13 and 'sell' or 'buy'
    local n = 0
    for obj in tostring(raw or ''):gmatch('{([^}]+)}') do
        if obj:find('"item"', 1, true) then
            L.parse_shop_item(obj, side)
            n = n + 1
        end
    end
    if n > 0 then DSP.flog('SHOP items type=' .. tostring(tp) .. ' n=' .. tostring(n)) end
end

function L.handle_shop_owner(raw)
    local d = decode(raw)
    local owner = d and (d.name or d.owner or d.nick) or raw:match('"name"%s*:%s*"([^"]+)"')
    owner = strip(owner or '')
    owner = owner:match('%-%s*([%w_]+)') or owner:match('^([%w_]+)') or owner
    if owner == '' then return end
    local num = nil
    if d then num = d.shopNum or d.shopId or d.lavkaId or d.shop_num end
    num = num or raw:match('"shopNum"%s*:%s*(%d+)')
        or raw:match('"shopId"%s*:%s*(%d+)')
        or raw:match('"lavkaId"%s*:%s*(%d+)')
        or raw:match('"shopNum"%s*:%s*"(%d+)"')
        or raw:match('"shopId"%s*:%s*"(%d+)"')
        or raw:match('"lavkaId"%s*:%s*"(%d+)"')
    local s = L.shop
    if not s or s.updated == 0 or (s.owner ~= '' and s.owner ~= owner) then
        L.reset_shop(owner, num)
    else
        s.owner = owner
        s.num = tostring(num or s.num or '')
        s.updated = now()
        s.menu_closed = 0
    end
    DSP.flog('SHOP owner=' .. tostring(owner) .. ' num=' .. tostring(num or '?'))
    if DSP.logs and DSP.logs.stall_dropped then
        DSP.logs.stall_dropped(owner, num or '', 'opened', (s.sell and #s.sell) or 0)
    end
end

function L.handle(iface, sub, raw)
    if iface == 60 and sub == 1 then
        L.handle_shop_owner(raw)
    elseif iface == 52 and sub == 2 then
        L.handle_shop_items(raw)
    elseif iface == 57 then
        L.handle_trade(sub, raw)
    elseif iface == 60 and sub == 0 then
        local tp = tonumber(raw:match('"type"%s*:%s*(%d+)')) or 0
        if tp == 13 or tp == 28 then
            L.handle_shop_items(raw)
        end
    elseif iface == 8 and sub == 15 then
        local tp = tonumber(raw:match('"type"%s*:%s*(%d+)')) or 0
        local title = strip(raw:match('"title"%s*:%s*"([^"]*)"') or '')
        if tp == 3 and title:find('Мен', 1, true) then
            local s = L.ensure_shop()
            s.updated = now()
            if s.opened == 0 then s.opened = s.updated end
            s.menu_closed = 0
        end
    elseif iface == 255 then
        if L.shop then L.shop.menu_closed = now() end
    end
end

function L.read_json(bs)
    local len = raknetBitStreamReadInt16(bs)
    if not len or len <= 0 then return nil end
    local enc = raknetBitStreamReadInt8(bs) or 0
    if enc ~= 0 then
        return raknetBitStreamDecodeString(bs, len + enc)
    end
    return raknetBitStreamReadString(bs, len)
end

function L.on_receive(packet_id, bs)
    if packet_id ~= 220 then return end
    pcall(raknetBitStreamResetReadPointer, bs)
    local ok, err = pcall(function()
        raknetBitStreamIgnoreBits(bs, 8)
        local marker = raknetBitStreamReadInt8(bs)
        if marker ~= 84 then return end
        local iface = raknetBitStreamReadInt8(bs)
        local sub = raknetBitStreamReadInt8(bs)
        local raw = L.read_json(bs)
        if raw and raw ~= '' then L.handle(iface, sub, raw) end
    end)
    if not ok then DSP.flog('LIVE packet error: ' .. tostring(err)) end
    pcall(raknetBitStreamResetReadPointer, bs)
end

function L.parse_dialog_trade(title, text)
    local partner = strip(title or ''):match('Результат сделки с (.-)%s*$') or ''
    if partner == '' then return end
    local t = L.trade
    if not t or t.opened == 0 or t.partner ~= partner then L.reset_trade(partner) end
    t = L.trade
    local sec = ''
    local give, get = {}, {}
    for line in tostring(text or ''):gsub('{[%x]+}', ''):gmatch('[^\r\n]+') do
        line = strip(line)
        if line:find('Перед', 1, true) then
            sec = 'give'
        elseif line:find('Получ', 1, true) then
            sec = 'get'
        elseif line:find('Комис', 1, true) then
            sec = ''
        elseif (sec == 'give' or sec == 'get') and line ~= '' and line ~= '-' then
            local money = DSP.money_val(line)
            local is_money = (line:find('%$') or line:lower():find('кк') or line:lower():find('kk')) and money > 0
            if is_money then
                if sec == 'give' then t.money_give = money else t.money_get = money end
            else
                local nm, qty = line:match('^(.-)%s*[xXхХ]%s*(%d+)%s*$')
                if not nm then nm, qty = line:match('^(.-)%s*%((%d+)%s*[^%)]*%)%s*$') end
                if not nm then nm, qty = line, '1' end
                local base, e = name_ench(nm)
                if base ~= '' then
                    local it = { name = base, ench = e, qty = tonumber(qty) or 1, id = 0 }
                    if sec == 'give' then give[#give + 1] = it else get[#get + 1] = it end
                end
            end
        end
    end
    if #give > 0 or #get > 0 or t.money_give > 0 or t.money_get > 0 then
        if #give > 0 then t.give = give end
        if #get > 0 then t.get = get end
        t.updated = now()
        DSP.flog('TRADE dialog partner=' .. partner .. ' give=' .. #give .. ' get=' .. #get
            .. ' money=' .. tostring(t.money_give) .. '/' .. tostring(t.money_get))
    end
end

local STALL_TITLES = { 'Управление лавкой', 'Настройка палатки', 'Управление палаткой', 'Настройка лавки' }

function L.is_stall_dialog(title)
    local t = DSP.clean_text(title or '')
    for _, w in ipairs(STALL_TITLES) do
        if t:find(w, 1, true) then return true end
    end
    return false
end

function L.on_dialog(dialog_id, style, title, b1, b2, text)
    -- CR average price pickup (offline price source)
    if DSP.avg and DSP.avg.on_dialog then
        local ok_avg, err_avg = pcall(DSP.avg.on_dialog, dialog_id, style, title, text)
        if not ok_avg then DSP.flog('AVG dialog error: ' .. tostring(err_avg)) end
    end
    -- Stall taken -> offer one-tap preset listing
    if L.is_stall_dialog(title) and DSP.settings.auto_open_stall ~= false
        and DSP.ui and DSP.ui.on_stall_dialog then
        DSP.ui.on_stall_dialog(dialog_id, title)
    end
    if dialog_id == 28148 then
        L.parse_dialog_trade(title, text)
        -- Also check for trade result in dialog text
        local txt = DSP.clean_text(text or '')
        if txt:find('сделка', 1, true) or txt:find('Обмен', 1, true) then
            local t = L.trade
            if t and t.give and t.get then
                local items_given, items_received = {}, {}
                for _, it in ipairs(t.give or {}) do
                    table.insert(items_given, { name = it.name, ench = it.ench, qty = it.qty })
                end
                for _, it in ipairs(t.get or {}) do
                    table.insert(items_received, { name = it.name, ench = it.ench, qty = it.qty })
                end
                if (#items_given > 0 or #items_received > 0 or t.money_give > 0 or t.money_get > 0) then
                    if not t._recorded then
                        t._recorded = true
                        if DSP.logs and DSP.logs.record_trade then
                            DSP.logs.record_trade(t.partner or '?', items_given, items_received,
                                t.money_give, t.money_get, 'accepted')
                        end
                    end
                end
            end
        end
    elseif dialog_id == 8248 then
        if L.trade then L.trade.updated = now() end
    end
end

function L.install()
    if L.installed then return end
    L.installed = true
    if addEventHandler then
        addEventHandler('onReceivePacket', L.on_receive)
        DSP.flog('LIVE receive hook installed')
    end
    local ok, sampev = pcall(require, 'samp.events')
    if ok and sampev then
        -- Server messages (sales/drops/kicks) are hooked in 05_trades.lua
        -- via sampev.onServerMessage (DSP.logs.install).
        local prev = sampev.onShowDialog
        sampev.onShowDialog = function(dialog_id, style, title, b1, b2, text)
            pcall(L.on_dialog, dialog_id, style, title, b1, b2, text)
            if prev then return prev(dialog_id, style, title, b1, b2, text) end
        end
        DSP.flog('LIVE dialog hook installed')
    end
end

function L.trade_age()
    if not L.trade or L.trade.updated == 0 then return 9999 end
    return now() - L.trade.updated
end

function L.shop_age()
    if not L.shop or L.shop.updated == 0 then return 9999 end
    return now() - L.shop.updated
end

end
__mod_45_live()

local function __mod_50_overlay()
-- Automatic trade/lavka evaluation overlay.
DSP.overlay = DSP.overlay or {}
DSP.overlay.shop_tab = 1
DSP.overlay.trade_closed = 0
DSP.overlay.shop_closed = 0
DSP.overlay.focus_trade = 0
DSP.overlay.focus_shop = 0

if DSP.settings.overlay_shop == nil then DSP.settings.overlay_shop = true end
if DSP.settings.overlay_trade == nil then DSP.settings.overlay_trade = true end
if DSP.settings.overlay_top == nil then DSP.settings.overlay_top = true end

local function d()
    return tonumber(DSP.ui and DSP.ui.d) or tonumber(DSP.settings.dpi) or 1.25
end

local function col(r, g, b, a)
    return imgui.ImVec4(r, g, b, a or 1)
end

local function u(s)
    return DSP.utf8(s)
end

local GREEN = col(0.45, 0.95, 0.45)
local YELLOW = col(1.0, 0.82, 0.30)
local RED = col(1.0, 0.42, 0.38)
local GRAY = col(0.62, 0.64, 0.70)
local BLUE = col(0.55, 0.72, 1.0)

local function base_label()
    local sid = tonumber(DSP.db.sid) or 0
    local cur = tonumber(DSP.market.state and DSP.market.state.sid) or 0
    local fresh = DSP.db.freshness()
    if sid > 0 and cur > 0 and sid ~= cur then
        return 'M' .. sid .. ' (текущий M' .. cur .. ')'
    end
    return sid > 0 and ('M' .. sid .. ' ' .. fresh) or fresh
end

local function item_price(it)
    local e = DSP.db.get(it.name, it.ench)
    if not e or not e.sell or not e.sell.min or e.sell.min <= 0 then return nil end
    return e.sell.min
end

function DSP.overlay.trade_sum()
    local t = DSP.live.trade
    local get_v, give_v, miss_get, miss_give = 0, 0, 0, 0
    for _, it in ipairs(t.get or {}) do
        local p = item_price(it)
        if p then get_v = get_v + p * (it.qty or 1) else miss_get = miss_get + 1 end
    end
    for _, it in ipairs(t.give or {}) do
        local p = item_price(it)
        if p then give_v = give_v + p * (it.qty or 1) else miss_give = miss_give + 1 end
    end
    local total_get = get_v + (t.money_get or 0)
    local total_give = give_v + (t.money_give or 0)
    local delta = total_get - total_give
    local pct = total_give > 0 and (delta / total_give * 100) or 0
    return total_get, total_give, delta, pct, miss_get, miss_give, get_v, give_v
end

function DSP.overlay.trade_ratio()
    local t = DSP.live.trade
    local _, _, _, _, _, _, get_v, give_v = DSP.overlay.trade_sum()
    local mg, mr = t.money_give or 0, t.money_get or 0
    if mr > 0 and mg == 0 and give_v > 0 then return mr / give_v, 'sale' end
    if mg > 0 and mr == 0 and get_v > 0 then return mg / get_v, 'buy' end
    local total_get = get_v + mr
    local total_give = give_v + mg
    if total_give > 0 then return total_get / total_give, 'swap' end
    return nil, 'none'
end

function DSP.overlay.show_trade()
    if DSP.settings.overlay_trade == false then return false end
    local t = DSP.live.trade
    if not t or (t.opened or 0) == 0 then return false end
    local age = DSP.live.trade_age()
    if t.complete and age > 60 then return false end
    if age > 600 then return false end
    if DSP.overlay.trade_closed == t.opened then return false end
    return (#(t.give or {}) > 0 or #(t.get or {}) > 0
        or (t.money_give or 0) > 0 or (t.money_get or 0) > 0)
end

function DSP.overlay.show_shop()
    if DSP.settings.overlay_shop == false then return false end
    local s = DSP.live.shop
    if not s or (s.opened or 0) == 0 then return false end
    if DSP.overlay.shop_closed == s.opened then return false end
    if (s.menu_closed or 0) > 0 then return false end
    if DSP.live.shop_age() > 300 then return false end
    return #(s.sell or {}) > 0 or #(s.buy or {}) > 0
end

local function close_btn(id)
    imgui.SameLine(0, 8 * d())
    if imgui.SmallButton('X##' .. id) then return true end
    return false
end

local function trade_item_row(it, kind)
    local e = DSP.db.get(it.name, it.ench)
    local qty = it.qty or 1
    local disp = DSP.item_name(it.name, it.ench)
    imgui.Text(u(disp .. '  x' .. tostring(qty)))
    if not e or not e.sell or not e.sell.min or e.sell.min <= 0 then
        imgui.SameLine(0, 6 * d())
        imgui.TextColored(GRAY, u('нет базы'))
        return
    end
    local unit = e.sell.min
    local sum = unit * qty
    imgui.SameLine(0, 6 * d())
    imgui.TextColored(BLUE, u(DSP.money(unit)))
    imgui.SameLine(0, 6 * d())
    imgui.TextColored(GRAY, u('=' .. DSP.money(sum)))
    if kind == 'get' then
        imgui.SameLine(0, 6 * d())
        imgui.TextDisabled(u('рынок ' .. DSP.money(e.sell.med or unit)))
    end
end

function DSP.overlay.draw_trade()
    local t = DSP.live.trade
    local sw, sh = imgui.GetIO().DisplaySize.x, imgui.GetIO().DisplaySize.y
    local w = math.min(sw * 0.40, 480 * d())
    imgui.SetNextWindowPos(imgui.ImVec2(sw - 8 * d(), 76 * d()), imgui.Cond.FirstUseEver, imgui.ImVec2(1, 0))
    imgui.SetNextWindowSize(imgui.ImVec2(w, 0), imgui.Cond.FirstUseEver)
    if DSP.settings.overlay_top ~= false then imgui.SetNextWindowFocus() end
    imgui.SetNextWindowBgAlpha(0.97)
    imgui.PushStyleColor(imgui.Col.WindowBg, col(0.055, 0.06, 0.085, 0.97))
    imgui.PushStyleColor(imgui.Col.Border, col(0.35, 0.36, 0.72, 0.95))
    local open = imgui.new.bool(true)
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoSavedSettings
        + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoNav
    if imgui.Begin('##dsp_trade_overlay', open, flags) then
        imgui.TextColored(BLUE, u('ТРЕЙД  ' .. (t.partner ~= '' and t.partner or '?')))
        if close_btn('dsp_trade_close') then DSP.overlay.trade_closed = t.opened end
        imgui.SameLine(0, 12 * d())
        imgui.TextDisabled(u('база: ' .. base_label()))
        imgui.Separator()

        local total_get, total_give, delta, pct, miss_get, miss_give, get_v, give_v = DSP.overlay.trade_sum()
        local ratio, mode = DSP.overlay.trade_ratio()
        local vc, vt = YELLOW, 'НОРМ'
        if miss_get + miss_give > 0 and total_get == 0 and total_give == 0 then
            vc, vt = GRAY, 'НЕТ БАЗЫ'
        elseif miss_get + miss_give > 0 and total_get == 0 then
            vc, vt = GRAY, 'НЕТ ЦЕНЫ ПОЛУЧАЕМОГО'
        elseif ratio then
            if ratio >= 1.10 then vc, vt = GREEN, 'ВЫГОДНО'
            elseif ratio < 0.90 then vc, vt = RED, 'НЕВЫГОДНО' end
        end
        imgui.TextColored(vc, u(vt .. (ratio and string.format('  %.0f%% рынка', ratio * 100) or '')))
        imgui.Text(u('Получаете: ' .. DSP.money(total_get) .. '   Отдаёте: ' .. DSP.money(total_give)))
        imgui.TextColored(delta >= 0 and GREEN or RED,
            u('Итог: ' .. (delta >= 0 and '+' or '') .. DSP.money(delta) .. string.format('  (%+.0f%%)', pct)))
        if (t.money_get or 0) > 0 and (t.money_give or 0) == 0 and give_v > 0 then
            local r = (t.money_get or 0) / give_v
            local c, s
            if r < 0.85 then c, s = RED, 'СКУП НИЖЕ РЫНКА'
            elseif r <= 1.10 then c, s = YELLOW, 'НОРМ ЦЕНА'
            else c, s = GREEN, 'ОВЕР — ВЫГОДНО ВАМ' end
            imgui.TextColored(c, u(string.format('Скуп: %.0f%% рынка — %s', r * 100, s)))
        elseif (t.money_give or 0) > 0 and (t.money_get or 0) == 0 and get_v > 0 then
            local r = (t.money_give or 0) / get_v
            local c, s
            if r < 0.85 then c, s = GREEN, 'ДЕШЕВО — БРАТЬ'
            elseif r <= 1.10 then c, s = YELLOW, 'НОРМ ЦЕНА'
            else c, s = RED, 'ОВЕР — ПЕРЕПЛАТА' end
            imgui.TextColored(c, u(string.format('Покупка: %.0f%% рынка — %s', r * 100, s)))
        end
        imgui.Separator()

        local half = math.floor((w - 28 * d()) / 2)
        local h = math.min(230 * d(), sh * 0.38)
        imgui.BeginChild('##dsp_trade_give', imgui.ImVec2(half, h), true)
        imgui.TextColored(RED, u('ВЫ ОТДАЁТЕ'))
        for _, it in ipairs(t.give or {}) do trade_item_row(it, 'give') end
        if (t.money_give or 0) > 0 then imgui.TextColored(RED, u('Деньги: -' .. DSP.money(t.money_give))) end
        if #(t.give or {}) == 0 and (t.money_give or 0) == 0 then imgui.TextDisabled(u('—')) end
        imgui.EndChild()
        imgui.SameLine(0, 8 * d())
        imgui.BeginChild('##dsp_trade_get', imgui.ImVec2(half, h), true)
        imgui.TextColored(GREEN, u('ВЫ ПОЛУЧАЕТЕ'))
        for _, it in ipairs(t.get or {}) do trade_item_row(it, 'get') end
        if (t.money_get or 0) > 0 then imgui.TextColored(GREEN, u('Деньги: +' .. DSP.money(t.money_get))) end
        if #(t.get or {}) == 0 and (t.money_get or 0) == 0 then imgui.TextDisabled(u('—')) end
        imgui.EndChild()
        if miss_get + miss_give > 0 then
            imgui.TextColored(YELLOW, u('Нет базы: ' .. tostring(miss_get + miss_give) .. ' поз. — обнови рынок'))
        end
        if imgui.SmallButton(u('ОБНОВИТЬ БАЗУ##dsp_trade_refresh')) then
            DSP.market.pull(DSP.market.state.sid)
        end
    end
    imgui.End()
    imgui.PopStyleColor(2)
    if not open[0] then DSP.overlay.trade_closed = t.opened end
end

local function shop_verdict_sell(price, e)
    if not e or not e.sell or not e.sell.min or e.sell.min <= 0 then return GRAY, 'НЕТ БАЗЫ', 0 end
    local low = e.sell.min
    local p25 = e.sell.p25 or low
    local med = e.sell.med or low
    local pct = med > 0 and (price / med * 100) or 0
    if price <= low * 1.02 or (p25 > 0 and price <= p25) then return GREEN, 'ДЕШЕВО — БРАТЬ', pct end
    if price <= med * 1.05 then return YELLOW, 'НОРМ', pct end
    return RED, 'ОВЕР', pct
end

local function shop_verdict_buy(price, e)
    if not e or not e.sell or not e.sell.min or e.sell.min <= 0 then return GRAY, 'НЕТ БАЗЫ', 0 end
    local low = e.sell.min
    local med = e.sell.med or low
    local pct = med > 0 and (price / med * 100) or 0
    if price >= med then return GREEN, 'ВЫГОДНО СДАТЬ', pct end
    if price >= low then return YELLOW, 'НОРМ', pct end
    return RED, 'НИЖЕ РЫНКА', pct
end

function DSP.overlay.draw_shop()
    local s = DSP.live.shop
    local sw, sh = imgui.GetIO().DisplaySize.x, imgui.GetIO().DisplaySize.y
    local w = math.min(sw * 0.46, 560 * d())
    imgui.SetNextWindowPos(imgui.ImVec2(sw - 8 * d(), 76 * d()), imgui.Cond.FirstUseEver, imgui.ImVec2(1, 0))
    imgui.SetNextWindowSize(imgui.ImVec2(w, 0), imgui.Cond.FirstUseEver)
    if DSP.settings.overlay_top ~= false then imgui.SetNextWindowFocus() end
    imgui.SetNextWindowBgAlpha(0.97)
    imgui.PushStyleColor(imgui.Col.WindowBg, col(0.055, 0.06, 0.085, 0.97))
    imgui.PushStyleColor(imgui.Col.Border, col(0.28, 0.62, 0.48, 0.95))
    local open = imgui.new.bool(true)
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoSavedSettings
        + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoNav
    if imgui.Begin('##dsp_shop_overlay', open, flags) then
        imgui.TextColored(GREEN, u('ЛАВКА  #' .. tostring(s.num or '?') .. '  ' .. tostring(s.owner or '?')))
        if close_btn('dsp_shop_close') then DSP.overlay.shop_closed = s.opened end
        imgui.SameLine(0, 12 * d())
        imgui.TextDisabled(u('база: ' .. base_label()))
        imgui.Separator()

        local sell_n, buy_n = #(s.sell or {}), #(s.buy or {})
        if imgui.Button(u('ПРОДАЖА (' .. sell_n .. ')##dsp_shop_sell')) then DSP.overlay.shop_tab = 1 end
        imgui.SameLine(0, 6 * d())
        if imgui.Button(u('СКУПКА (' .. buy_n .. ')##dsp_shop_buy')) then DSP.overlay.shop_tab = 2 end
        imgui.Separator()

        local rows = {}
        if DSP.overlay.shop_tab == 1 then
            for _, it in ipairs(s.sell or {}) do
                local e = DSP.db.get(it.name, it.ench)
                local c, label, pct = shop_verdict_sell(it.price, e)
                local profit = e and e.buy and e.buy.max and e.buy.max > 0 and (DSP.market.net(e.buy.max) - it.price) or 0
                rows[#rows + 1] = { it = it, e = e, c = c, label = label, pct = pct,
                    profit = profit, side = 'sell' }
            end
        else
            for _, it in ipairs(s.buy or {}) do
                local e = DSP.db.get(it.name, it.ench)
                local c, label, pct = shop_verdict_buy(it.price, e)
                local profit = e and e.sell and e.sell.min and e.sell.min > 0 and (DSP.market.net(it.price) - e.sell.min) or 0
                rows[#rows + 1] = { it = it, e = e, c = c, label = label, pct = pct,
                    profit = profit, side = 'buy' }
            end
        end
        table.sort(rows, function(a, b)
            local pa, pb = a.profit or 0, b.profit or 0
            if pa ~= pb then return pa > pb end
            return (a.pct or 0) < (b.pct or 0)
        end)

        local h = math.min(340 * d(), sh * 0.55)
        if imgui.BeginChild('##dsp_shop_list', imgui.ImVec2(-1, h), true) then
            if #rows == 0 then
                imgui.TextDisabled(u('  Нет товаров. Открой меню товаров лавки.'))
            end
            for _, r in ipairs(rows) do
                local it = r.it
                imgui.TextColored(r.c, u(r.label))
                imgui.SameLine(0, 6 * d())
                imgui.Text(u(DSP.item_name(it.name, it.ench) .. '  x' .. tostring(it.qty or 1)))
                imgui.SameLine(0, 6 * d())
                imgui.TextColored(BLUE, u(DSP.money(it.price)))
                if r.e and r.e.sell and r.e.sell.min and r.e.sell.min > 0 then
                    imgui.SameLine(0, 6 * d())
                    imgui.TextDisabled(u('рынок ' .. DSP.money(r.e.sell.min)
                        .. '/' .. DSP.money(r.e.sell.med or r.e.sell.min)))
                    if r.profit and r.profit ~= 0 then
                        imgui.SameLine(0, 6 * d())
                        imgui.TextColored(r.profit > 0 and GREEN or RED,
                            u((r.profit > 0 and 'профит ' or 'минус ') .. DSP.money(math.abs(r.profit))))
                    end
                end
            end
        end
        imgui.EndChild()
        if imgui.SmallButton(u('ОБНОВИТЬ БАЗУ##dsp_shop_refresh')) then
            DSP.market.pull(DSP.market.state.sid)
        end
    end
    imgui.End()
    imgui.PopStyleColor(2)
    if not open[0] then DSP.overlay.shop_closed = s.opened end
end

function DSP.overlay.install()
    if DSP.overlay.installed then return end
    DSP.overlay.installed = true
    imgui.OnFrame(function()
        return DSP.overlay.show_trade() or DSP.overlay.show_shop()
    end, function()
        if DSP.overlay.show_trade() then DSP.overlay.draw_trade() end
        if DSP.overlay.show_shop() then DSP.overlay.draw_shop() end
    end)
end


-- ---------------------------------------------------------------------------
-- 3D tracer for [Отметить лавку] (spec 5.2). The target is set by DSP.market.mark_shop:
-- we look for a 3D text of the shop (owner nick or "лавка №N") within 35 m and draw a
-- line from the player to it plus a circle on top. Everything is pcall-guarded because
-- the 3D-text API differs between MoonLoader and MonetLoader builds.
DSP.tracer = DSP.tracer or { target = nil }
DSP.tracer.RADIUS = 35

function DSP.tracer.match(text, t)
    local clean = DSP.clean_text(text or '')
    if clean == '' or not t then return false end
    if t.owner and t.owner ~= '' and clean:find(t.owner, 1, true) then return true end
    local low = DSP.lower(clean)
    if low:find('лавк', 1, true) or low:find('палатк', 1, true) then
        for n in clean:gmatch('[№#]%s*(%d+)') do
            if n == tostring(t.shop_num) then return true end
        end
    end
    return false
end

function DSP.tracer.scan()
    local t = DSP.tracer.target
    if not t then return end
    if os.time() > (t.expires or 0) then
        DSP.tracer.target = nil
        return
    end
    if not (sampIs3dTextDefined and sampGet3dTextInfoById and getCharCoordinates and PLAYER_PED) then return end
    local px, py, pz = getCharCoordinates(PLAYER_PED)
    local best, bestd
    for id = 0, 2047 do
        if sampIs3dTextDefined(id) then
            local text, _, x, y, z = sampGet3dTextInfoById(id)
            if x and DSP.tracer.match(text, t) then
                local dist = math.sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2)
                if dist <= DSP.tracer.RADIUS and (not bestd or dist < bestd) then
                    best, bestd = { x = x, y = y, z = z }, dist
                end
            end
        end
    end
    t.pos, t.dist = best, bestd
end

function DSP.tracer.draw()
    local t = DSP.tracer.target
    if not (t and t.pos and imgui.GetBackgroundDrawList and convert3DCoordsToScreen) then return end
    local dl = imgui.GetBackgroundDrawList()
    local px, py, pz = getCharCoordinates(PLAYER_PED)
    local x1, y1 = convert3DCoordsToScreen(px, py, pz)
    local tx, ty, tz = t.pos.x, t.pos.y, t.pos.z
    if isPointOnScreen and not isPointOnScreen(tx, ty, tz, 1.0) then return end
    local x2, y2 = convert3DCoordsToScreen(tx, ty, tz)
    if not (x1 and x2) then return end
    local c = DSP.colors.accent
    local u32 = imgui.GetColorU32Vec4(imgui.ImVec4(c[1], c[2], c[3], 0.95))
    local dpi = (DSP.ui and DSP.ui.d) or 1
    dl:AddLine(imgui.ImVec2(x1, y1), imgui.ImVec2(x2, y2), u32, 3 * dpi)
    dl:AddCircle(imgui.ImVec2(x2, y2), 18 * dpi, u32, 24, 3 * dpi)
    dl:AddText(imgui.ImVec2(x2 + 22 * dpi, y2 - 8 * dpi), u32,
        DSP.utf8(string.format('Лавка #%s  %.0f м', tostring(t.shop_num), t.dist or 0)))
end

function DSP.tracer.install()
    if lua_thread and wait then
        lua_thread.create(function()
            while true do
                wait(500)
                local ok, err = pcall(DSP.tracer.scan)
                if not ok then DSP.flog('tracer scan: ' .. tostring(err)) end
            end
        end)
    end
    if imgui and imgui.OnFrame then
        imgui.OnFrame(function()
            local t = DSP.tracer.target
            return t ~= nil and t.pos ~= nil
        end, function(player)
            player.HideCursor = true
            pcall(DSP.tracer.draw)
        end)
    end
end

end
__mod_50_overlay()

local function __mod_99_main()
-- Main entry: catalog, price base, market, UI, live hooks, overlay.
if not imgui then
    local ok, m = pcall(require, 'mimgui')
    if ok then imgui = m end
end

DSP.items.load()
DSP.db.load()
DSP.logs.load()
DSP.market.load()
if DSP.avg and DSP.avg.load then pcall(DSP.avg.load, DSP.market.state.sid) end
DSP.auto.install()
DSP.ui.install()
DSP.live.install()
DSP.overlay.install()
DSP.tracer.install()
DSP.logs.install()
DSP.notify('palatka ai v' .. DSP.version .. ': /crr')

if lua_thread and wait and DSP.detect_server then
    lua_thread.create(function()
        while true do
            wait(10000)
            local sid = DSP.detect_server()
            local nick = DSP.player_nick()
            local nick_changed = nick ~= 'DsPic' and nick ~= (DSP.market.state.nick or '')
            if DSP.market.state.status ~= 'loading'
                and ((sid and sid ~= (DSP.market.state.sid or 0)) or nick_changed) then
                sid = sid or DSP.market.state.sid
                DSP.flog('MARKET refresh sid=' .. tostring(sid) .. ' nick=' .. tostring(nick))
                DSP.market.pull(sid)
            end
        end
    end)
end

end
__mod_99_main()

