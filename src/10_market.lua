-- Live lavka market: pull, enchant-aware stats, cache.
DSP.market = DSP.market or {}

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

function DSP.market.rebuild(payload, sid)
    sid = tonumber(sid) or DSP.market.state.sid
    local shops = type(payload) == 'table' and payload.shops or {}
    local map = {}
    local offers_n, shops_n = 0, 0
    local newest, oldest = 0, 0
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
            for _, slot in ipairs(shop.sell_slots or {}) do
                local name = DSP.to_cp(slot.name or '')
                local price = tonumber(slot.price) or 0
                local qty = tonumber(slot.qty) or 0
                if name ~= '' and price > 0 then
                    has_slot = true
                    offers_n = offers_n + 1
                    add_offer(map, name, sanitize_ench(slot.ench), {
                        side = 'buy', price = price, qty = qty,
                        owner = owner, shop = shop_num,
                        ench = sanitize_ench(slot.ench),
                    })
                end
            end
            for _, slot in ipairs(shop.buy_slots or {}) do
                local name = DSP.to_cp(slot.name or '')
                local price = tonumber(slot.price) or 0
                local qty = tonumber(slot.qty) or 0
                if name ~= '' and price > 0 then
                    has_slot = true
                    offers_n = offers_n + 1
                    add_offer(map, name, sanitize_ench(slot.ench), {
                        side = 'sell', price = price, qty = qty,
                        owner = owner, shop = shop_num,
                        ench = sanitize_ench(slot.ench),
                    })
                end
            end
            if has_slot then shops_n = shops_n + 1 end
        end
    end
    local rows = {}
    for _, row in pairs(map) do
        finish_side(row.sell, true)
        finish_side(row.buy, false)
        if row.sell.count > 0 and row.buy.count > 0 then
            row.profit = row.buy.max - row.sell.min
            row.profit_med = row.buy.med - row.sell.med
            row.profit_pct = row.sell.min > 0 and (row.profit / row.sell.min * 100) or 0
        else
            row.profit, row.profit_med, row.profit_pct = 0, 0, 0
        end
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b)
        if (a.profit or 0) ~= (b.profit or 0) then return (a.profit or 0) > (b.profit or 0) end
        if (a.sell.best or 0) ~= (b.sell.best or 0) then return (a.sell.best or 0) < (b.sell.best or 0) end
        return a.display < b.display
    end)
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
            row.profit = (sell.count > 0 and buy.count > 0) and (buy.max - sell.min) or 0
            row.profit_med = (sell.count > 0 and buy.count > 0) and (buy.med - sell.med) or 0
            row.profit_pct = sell.min > 0 and (row.profit / sell.min * 100) or 0
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

function DSP.market.buy_target(row, margin)
    margin = tonumber(margin) or tonumber(DSP.settings.margin) or 10
    local resale = row and row.buy and row.buy.max or 0
    if resale <= 0 then return 0 end
    return math.max(0, math.floor(resale * (1 - margin / 100)))
end

function DSP.market.sell_target(row, undercut)
    undercut = tonumber(undercut) or tonumber(DSP.settings.undercut) or 2
    -- List slightly below best buy offer (max what shops pay)
    local comp = row and row.buy and row.buy.max or 0
    if comp <= 0 then return 0 end
    return math.max(1, math.floor(comp * (1 - undercut / 100)))
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
