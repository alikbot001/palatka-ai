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

-- Requests runs in an effil worker, never in the UI/render callback.
-- Return only primitive values: this also works with effil builds that do not
-- serialize ordinary Lua tables between Lua states reliably.
function _G.dsp_http_get(url)
    local ok_req, requests = pcall(require, 'requests')
    if not ok_req or not requests or type(requests.request) ~= 'function' then
        return 0, '', 'requests unavailable in network worker'
    end
    local function request_one(target)
        local ok, resp = pcall(requests.request, 'GET', target, nil)
        if not ok then return 0, '', 'connect: ' .. tostring(resp) end
        if not resp then return 0, '', 'empty HTTP response' end
        local status = tonumber(resp.status_code) or 0
        local body = resp.text or resp.content or ''
        if type(body) ~= 'string' then body = tostring(body or '') end
        local headers = resp.headers or {}
        local redirect = headers.Location or headers.location
        return status, body, nil, redirect
    end
    local status, body, err, redirect = request_one(url)
    -- Respect a single HTTPS redirect on the same host (no plaintext HTTP
    -- downgrade, and no accidental delivery of API parameters to new hosts).
    if (status == 301 or status == 302 or status == 303 or status == 307 or status == 308)
        and type(redirect) == 'string' and redirect ~= '' then
        local original_host = url:match('^https://([^/:?]+)')
        local redirect_host = redirect:match('^https://([^/:?]+)')
        if original_host and redirect_host and original_host:lower() == redirect_host:lower() then
            return request_one(redirect)
        end
        return status, body, 'redirect blocked (different host or insecure scheme)'
    end
    return status, body, err
end

-- Compatible with older mocks that returned one table, and with real effil's
-- multiple return values. thread:get() is *not* an HTTP status indicator.
local function effil_result(thread)
    local ok, first, second, third = pcall(function() return thread:get() end)
    if not ok then return nil, 'worker result: ' .. tostring(first) end
    if type(first) == 'table' or type(first) == 'userdata' then
        return {
            code = tonumber(first.code or first[1]) or 0,
            body = tostring(first.body or first[2] or ''),
            err = first.err or first[3],
        }
    end
    if type(first) == 'number' then
        return {code = tonumber(first) or 0, body = tostring(second or ''), err = third}
    end
    if first == false then return nil, tostring(second or 'network worker failed') end
    return nil, 'unexpected network result: ' .. type(first)
end

function DSP.http_get(url, cb)
    local ok_effil, effil = pcall(require, 'effil')
    if not ok_effil or not effil or type(effil.thread) ~= 'function' then
        return cb(nil, 'effil unavailable', 0)
    end
    if not lua_thread or type(lua_thread.create) ~= 'function' or not wait then
        return cb(nil, 'Lua thread scheduler unavailable', 0)
    end
    local ok_th, thread = pcall(function() return effil.thread(_G.dsp_http_get)(url) end)
    if not ok_th or not thread then
        return cb(nil, 'worker start: ' .. tostring(thread), 0)
    end
    local ok_scheduler, scheduler_err = pcall(lua_thread.create, function()
        local deadline = os.time() + 45
        local finished = false
        local function finish(body, err, code)
            if finished then return end
            finished = true
            local ok_cb, cb_err = pcall(cb, body, err, code)
            if not ok_cb and DSP.flog then DSP.flog('HTTP callback error: ' .. tostring(cb_err)) end
        end
        while not finished do
            wait(50)
            if os.time() >= deadline then
                pcall(function() thread:cancel() end)
                return finish(nil, 'timeout after 45s', 0)
            end
            local ok_status, status, status_err = pcall(function() return thread:status() end)
            if not ok_status or not status then
                return finish(nil, 'worker status: ' .. tostring(status_err or status), 0)
            end
            if status == 'completed' then
                local res, err = effil_result(thread)
                if not res then return finish(nil, err, 0) end
                if res.code ~= 200 then
                    if res.code == 0 and res.err then
                        return finish(nil, 'Сеть: ' .. tostring(res.err), 0)
                    end
                    local hint = res.err and (' · ' .. tostring(res.err)) or ''
                    if res.code == 401 or res.code == 403 then
                        hint = ' · доступ к API не разрешён или требуется авторизация'
                    elseif res.code == 404 then
                        hint = ' · endpoint не найден'
                    elseif res.code == 429 then
                        hint = ' · лимит запросов'
                    end
                    return finish(nil, 'HTTP ' .. tostring(res.code) .. hint, res.code)
                end
                if res.body == '' then return finish(nil, 'empty response', 200) end
                return finish(res.body, nil, 200)
            end
            if status == 'canceled' then return finish(nil, 'request canceled', 0) end
            if status == 'error' or status == 'failed' then
                return finish(nil, 'worker failed: ' .. tostring(status_err or 'unknown'), 0)
            end
        end
    end)
    if not ok_scheduler then return cb(nil, 'scheduler failed: ' .. tostring(scheduler_err), 0) end
end

function DSP.player_nick()
    local nick = ''
    -- Some Android builds cannot resolve PLAYER_PED before first spawn.
    -- Use a native local-player id when available; never fake an identity.
    pcall(function()
        if sampGetPlayerIdByCharHandle and PLAYER_PED then
            local ok, pid = sampGetPlayerIdByCharHandle(PLAYER_PED)
            if ok and pid ~= nil and sampGetPlayerNickname then
                nick = sampGetPlayerNickname(pid) or ''
            end
        end
    end)
    if nick == '' then pcall(function()
        if sampGetLocalPlayerId and sampGetPlayerNickname then
            local id = sampGetLocalPlayerId()
            if id ~= nil then nick = sampGetPlayerNickname(id) or '' end
        end
    end) end
    if nick == '' then pcall(function()
        if sampGetCurrentPlayerName then nick = sampGetCurrentPlayerName() or '' end
    end) end
    if type(nick) ~= 'string' then nick = '' end
    if nick:find('[%c]') then nick = '' end
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

local function item_units(value)
    local n = tonumber(value)
    if not n or n ~= n or n < 0 or n == math.huge or n > 9007199254740991 then
        return 0
    end
    return math.floor(n)
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
    -- One stall may expose multiple slots of the same item at the same price.
    -- They are one actionable stock pool; different prices stay separate.
    side.offer_index = side.offer_index or {}
    local slot_key = tostring(offer.shop) .. '\0' .. tostring(offer.price)
    local existing = side.offer_index[slot_key]
    if existing then
        existing.qty = existing.qty + offer.qty
        existing.slots = (existing.slots or 1) + 1
    else
        offer.slots = 1
        side.offer_index[slot_key] = offer
        side.offers[#side.offers + 1] = offer
    end
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
end

function DSP.market.rebuild(payload, sid)
    sid = tonumber(sid) or DSP.market.state.sid
    local shops = type(payload) == 'table' and payload.shops or {}
    local map = {}
    local offers_n, shops_n = 0, 0
    local newest, oldest = 0, 0
    -- v1.2 hotfix: yield to the scheduler every 50 shops when called from
    -- a coroutine (http_get callback path). When called sync (load_cache path
    -- at script init), coroutine.running() returns nil and we don't yield.
    -- This prevents the 2500-row rebuild from blocking the render thread
    -- for ~1 second on Samsung A15 -> game freeze -> system kill.
    local co = (coroutine and coroutine.running and coroutine.running()) or nil
    local can_yield = co ~= nil and wait ~= nil
    local yield_count = 0
    for shop_idx, shop in ipairs(shops) do
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
                local qty = item_units(slot.qty)
                if name ~= '' and price > 0 and qty > 0 then
                    has_slot = true
                    offers_n = offers_n + 1
                    -- v1.2 Stage 2 fix: shop.sell_slots = лавка ПРОДАЁТ игроку -> player BUYS.
                    -- Store in row.sell (лавка продаёт) so the UI label matches the data
                    -- AND finish_side's asc sort + best=min gives the cheapest price
                    -- for the player to buy at.
                    add_offer(map, name, sanitize_ench(slot.ench), {
                        side = 'sell', price = price, qty = qty,
                        owner = owner, shop = shop_num,
                        ench = sanitize_ench(slot.ench),
                        ts = ts,
                    })
                end
            end
            for _, slot in ipairs(shop.buy_slots or {}) do
                local name = DSP.to_cp(slot.name or '')
                local price = tonumber(slot.price) or 0
                local qty = item_units(slot.qty)
                if name ~= '' and price > 0 and qty > 0 then
                    has_slot = true
                    offers_n = offers_n + 1
                    -- v1.2 Stage 2 fix: shop.buy_slots = лавка СКУПАЕТ у игрока -> player SELLS.
                    -- Store in row.buy (лавка скупает); finish_side sorts desc, best=max
                    -- so row.buy.best = the highest buyback price (best for the player to sell to).
                    add_offer(map, name, sanitize_ench(slot.ench), {
                        side = 'buy', price = price, qty = qty,
                        owner = owner, shop = shop_num,
                        ench = sanitize_ench(slot.ench),
                        ts = ts,
                    })
                end
            end
            if has_slot then shops_n = shops_n + 1 end
        end
        -- Yield to scheduler every 50 shops if we're in a coroutine.
        -- pcall protects against wait() being called across C boundaries.
        if can_yield and shop_idx % 50 == 0 then
            pcall(wait, 0)
            yield_count = yield_count + 1
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
    -- v1.2 hotfix: invalidate arbitrage cache. The market data changed,
    -- so the cached arbitrage list is now stale and must be recomputed
    -- on the next call to arbitrage_filtered().
    DSP.market.arb_dirty = true
    DSP.market.arb_cache = nil
    DSP.market.arb_cache_version = -1
    if yield_count > 0 then
        DSP.flog('REBUILD chunked: shops=' .. tostring(#shops) .. ' yields=' .. tostring(yield_count))
    end
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

local function query_value(s)
    -- Nicknames normally contain ASCII, but URLs must never concatenate a
    -- raw nickname or version string containing &, ?, #, + or spaces.
    return (tostring(s or ''):gsub('([^%w%-%._~])', function(c)
        return string.format('%%%02X', string.byte(c))
    end))
end

function DSP.market.url(sid)
    local url = DSP.market.api .. '?server=' .. query_value(sid)
        .. '&ver=' .. query_value(DSP.version)
    local nick = DSP.player_nick()
    if nick ~= '' then url = url .. '&nick=' .. query_value(nick) end
    return url
end

function DSP.market.clear_for_server(sid)
    local st = DSP.market.state
    if tonumber(st.sid) == tonumber(sid) then return end
    st.rows, st.by_key = {}, {}
    st.shops, st.offers, st.updated, st.oldest, st.saved_at = 0, 0, 0, 0, 0
    st.filter_cache, st.filter_version = nil, -1
    st.version = (st.version or 0) + 1
    st.sid = sid
    st.pending_sid = nil
    st.request_generation = (st.request_generation or 0) + 1
    st.error = nil
    st.failures, st.next_auto_retry = 0, 0
    DSP.market.invalidate_arbitrage()
end

local function market_request_error(sid, err, code, done)
    local st = DSP.market.state
    st.error = tostring(err or 'ошибка сети')
    st.last_http_code = tonumber(code) or 0
    st.failed_at = os.time()
    st.failures = math.min(8, (tonumber(st.failures) or 0) + 1)
    -- Do not hammer a broken/private endpoint. Manual 'Обновить' is still
    -- allowed. Keep the last valid same-server cache visible, clearly stale.
    local delay = math.min(900, 30 * (2 ^ (st.failures - 1)))
    if code == 429 then delay = math.max(delay, 300) end
    if code == 401 or code == 403 or code == 404 then delay = 900 end
    st.next_auto_retry = os.time() + delay
    st.status = (st.rows and #st.rows > 0) and 'cache' or 'error'
    DSP.flog('PULL error sid=' .. tostring(sid) .. ' code=' .. tostring(code or 0)
        .. ' retry_in=' .. delay .. 's ' .. st.error)
    DSP.add_log('Рынок: ' .. st.error .. (st.status == 'cache' and ' (показан старый снимок)' or ''), 'error')
    if done then done(false, st.error) end
end

function DSP.market.pull(sid, done)
    local st = DSP.market.state
    sid = tonumber(sid) or st.sid
    -- A server switch invalidates the previous request. Late responses are
    -- ignored instead of silently contaminating the next server's market.
    if st.status == 'loading' and tonumber(st.pending_sid) == sid then return false, 'already loading' end
    DSP.market.clear_for_server(sid)
    st.request_generation = (st.request_generation or 0) + 1
    local generation = st.request_generation
    st.pending_sid = sid
    st.sid = sid
    st.status = 'loading'
    st.last_request = os.time()
    st.error = nil
    st.nick = DSP.player_nick()
    DSP.add_log('Запрос рынка Mobile ' .. tostring(sid) .. '...')
    DSP.flog('PULL start sid=' .. tostring(sid) .. ' generation=' .. tostring(generation))
    DSP.http_get(DSP.market.url(sid), function(body, err, code)
        if generation ~= st.request_generation or tonumber(st.sid) ~= sid then
            DSP.flog('PULL ignored stale response sid=' .. tostring(sid))
            return
        end
        if not body then return market_request_error(sid, err, code, done) end
        if body:match('^%s*<![Dd][Oo][Cc][Tt][Yy][Pp][Ee]') or body:match('^%s*<[Hh][Tt][Mm][Ll]') then
            return market_request_error(sid, 'API вернул HTML вместо JSON (ошибка шлюза или защита сайта)', code, done)
        end
        local ok_json, payload = pcall(decodeJson, body)
        if not ok_json or type(payload) ~= 'table' then
            return market_request_error(sid, 'API вернул некорректный JSON', code, done)
        end
        if payload.ok == false or payload.success == false then
            return market_request_error(sid, 'API отказал: ' .. tostring(payload.error or payload.message or 'unknown'), code, done)
        end
        if type(payload.shops) ~= 'table' then
            return market_request_error(sid, 'API изменил формат: отсутствует shops', code, done)
        end
        -- Do not replace a known-good snapshot when rebuild fails.
        local previous = {rows=st.rows, by_key=st.by_key, shops=st.shops,
            offers=st.offers, updated=st.updated, oldest=st.oldest,
            version=st.version, filter_cache=st.filter_cache,
            filter_version=st.filter_version}
        local ok_rebuild, rebuild_err = pcall(DSP.market.rebuild, payload, sid)
        if not ok_rebuild then
            for k, v in pairs(previous) do st[k] = v end
            return market_request_error(sid, 'API parsing: ' .. tostring(rebuild_err), code, done)
        end
        st.failures, st.next_auto_retry, st.failed_at = 0, 0, nil
        st.last_http_code, st.pending_sid = 200, nil
        -- Cache write is best-effort; never turn a successful refresh into a
        -- network failure simply because phone storage is unavailable.
        local ok_cache, cache_err = pcall(DSP.market.save_cache, sid, body)
        if not ok_cache then DSP.flog('PULL cache error: ' .. tostring(cache_err)) end
        DSP.settings.server = sid
        local ok_save, save_err = pcall(DSP.save_settings)
        if not ok_save then DSP.flog('PULL settings error: ' .. tostring(save_err)) end
        DSP.flog(string.format('PULL ok shops=%d offers=%d rows=%d newest=%d',
            st.shops, st.offers, #st.rows, st.updated))
        DSP.add_log(string.format('Рынок: %d лавок, %d офферов, свежесть %s',
            st.shops, st.offers, DSP.market.freshness()))
        if done then done(true) end
    end)
    return true
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
    local tax = DSP.clamp(tonumber(DSP.settings.tax_bp) or 200, 0, 10000)
    return math.max(0, math.floor(resale * (10000 - tax) / 10000 * (1 - margin / 100)))
end

function DSP.market.sell_target(row, undercut)
    undercut = tonumber(undercut) or tonumber(DSP.settings.undercut) or 2
    -- Compete with other sellers, not the shops buying from the player.
    local comp = row and row.sell and row.sell.min or 0
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
    DSP.market.clear_for_server(sid)
    -- Never substitute Mobile II data for a missing cache on another server.
    if not DSP.market.load_cache(sid) then
        DSP.market.state.status = 'idle'
        DSP.market.state.rows, DSP.market.state.by_key = {}, {}
    end
    DSP.market.pull(sid)
end

-- =========================================================================
-- v1.2 Stage 2: 100% arbitrage + Item Finder + shops list.
-- =========================================================================

-- Freshness label for an offer. Returns (text, palette_key).
--   ts < 3 min: ('СВЕЖО (<3m)', 'good')  -- green
--   ts < 10 min: ('5m назад', 'warn')    -- yellow (text is approximate)
--   ts >= 10 min or 0: ('Устарело', 'muted')  -- gray
function DSP.market.offer_freshness(ts)
    if not ts or ts <= 0 then return 'Устарело', 'muted' end
    local age = math.max(0, os.time() - ts)
    if age < 180 then
        return string.format('СВЕЖО (<%dm)', math.floor(age / 60) + 1), 'good'
    end
    if age < 600 then
        return string.format('%dm назад', math.floor(age / 60)), 'warn'
    end
    return 'Устарело', 'muted'
end

-- Build cross-shop arbitrage opportunities.
-- Iterates row.sell.offers (лавка A продаёт cheap) + row.buy.offers
-- (лавка B скупает expensive), pairs them when A.shop ~= B.shop AND
-- B.price > A.price (otherwise negative profit).
-- Key includes @ench (set in DSP.item_key), so +0 stock is never matched
-- against +12 buyback.
--
-- v1.2 hotfix: лавки старше STALE_AFTER секунд (default 1800 = 30 мин)
-- отсекаются как неактуальные, чтобы не ловить фантомный арбитраж по
-- устаревшим данным из кэша va-ta.com.
local STALE_AFTER = 1800

-- v1.2 hotfix: ARBITRAGE CACHE.
-- In v1.2 we computed arbitrage() EVERY frame inside arbitrage_tab().
-- That ran 800 rows * 25 sell * 25 buy = ~500k iterations + table.sort,
-- 60 times per second -> game froze solid on Samsung A15.
--
-- Fix: compute arbitrage lazily. Cache the result + a version stamp.
-- Invalidate the cache only when:
--   * market.state.version changes (rebuild() bumped it)
--   * arb_filters change (budget / min_profit / min_roi / sort)
--   * arb_dirty flag is set (force re-compute)
--
-- arbitrage_filtered() reads from the cache, returning the cached array
-- in O(1) without re-sorting. The 60 FPS frame cost is now < 0.1 ms.
DSP.market.arb_cache = nil
DSP.market.arb_cache_version = -1
DSP.market.arb_cache_filter_sig = ''
DSP.market.arb_dirty = true

-- Compute the cache key signature from active filters. Used to detect
-- when the user changed filters and we need to re-filter (but not re-scan).
local function arb_filter_signature()
    local f = DSP.settings.arb_filters or {}
    return string.format('%d|%d|%d|%d',
        tonumber(f.budget) or 0,
        tonumber(f.min_profit) or 0,
        tonumber(f.min_roi) or 0,
        tonumber(f.sort) or 1)
end

-- Each result entry contains:
--   name, ench            -- display label and enchant level
--   sell_offer, buy_offer -- the matched offer objects (with .ts, .shop, .owner)
--   p_buy, p_sell         -- unit prices (player pays p_buy, receives p_sell)
--   qty_seller, qty_buyer -- qty offered by A and demanded by B
--   tradable_qty          -- min(qty_seller, qty_buyer) = realistic party size
--   total_cost            -- tradable_qty * p_buy (what player needs on hand)
--   net_revenue           -- math.floor(tradable_qty * p_sell * (10000 - tax_bp) / 10000)
--                          -- integer CR tax (basis points), no float drift
--   net_profit            -- net_revenue - total_cost (whole-cycle profit)
--   roi                   -- net_profit / total_cost * 100 (percent)
--   sell_age, buy_age     -- raw timestamps for freshness display
function DSP.market.arbitrage()
    local out = {}
    local tax_bp = tonumber(DSP.settings.tax_bp) or 200
    if tax_bp < 0 or tax_bp > 1000 then tax_bp = 200 end
    local now = os.time()
    for _, row in ipairs(DSP.market.state.rows or {}) do
        if row.sell.count > 0 and row.buy.count > 0 then
            for _, sell_offer in ipairs(row.sell.offers) do
                -- v1.2 hotfix: skip stale offers (>= 30 min old).
                -- Avoids phantom arbitrage from stale va-ta.com cache.
                if (tonumber(sell_offer.ts) or 0) == 0
                    or (now - sell_offer.ts) <= STALE_AFTER then
                    for _, buy_offer in ipairs(row.buy.offers) do
                        if (tonumber(buy_offer.ts) or 0) == 0
                            or (now - buy_offer.ts) <= STALE_AFTER then
                            -- Strict same-name + same-ench check via row key (already
                            -- enforced by map keying, but double-check in case of
                            -- legacy data).
                            if (sell_offer.ench or 0) == (buy_offer.ench or 0)
                                and sell_offer.shop ~= buy_offer.shop then
                                local p_buy = tonumber(sell_offer.price) or 0
                                local p_sell = tonumber(buy_offer.price) or 0
                                if p_sell > p_buy and p_buy > 0 then
                                    local qty_seller = tonumber(sell_offer.qty) or 0
                                    local qty_buyer = tonumber(buy_offer.qty) or 0
                                    local tradable_qty = math.min(qty_seller, qty_buyer)
                                    if tradable_qty > 0 then
                                        local total_cost = tradable_qty * p_buy
                                        local net_revenue = math.floor(
                                            tradable_qty * p_sell * (10000 - tax_bp) / 10000)
                                        local net_profit = net_revenue - total_cost
                                        if net_profit > 0 then
                                            local roi = total_cost > 0
                                                and (net_profit / total_cost * 100) or 0
                                            out[#out + 1] = {
                                                row = row,
                                                name = row.display,
                                                ench = row.ench,
                                                sell_offer = sell_offer,
                                                buy_offer = buy_offer,
                                                p_buy = p_buy,
                                                p_sell = p_sell,
                                                qty_seller = qty_seller,
                                                qty_buyer = qty_buyer,
                                                tradable_qty = tradable_qty,
                                                total_cost = total_cost,
                                                net_revenue = net_revenue,
                                                net_profit = net_profit,
                                                roi = roi,
                                                sell_age = sell_offer.ts or 0,
                                                buy_age = buy_offer.ts or 0,
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- Sort ONCE here, by net_profit desc (default sort id = 1).
    -- arbitrage_filtered() will re-sort only if sort != 1 OR filter changed.
    table.sort(out, function(a, b)
        if (a.net_profit or 0) ~= (b.net_profit or 0) then
            return (a.net_profit or 0) > (b.net_profit or 0)
        end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- Apply active arbitrage filters from DSP.settings.arb_filters.
-- Returns a CACHED array (filtered + sorted) so the UI can render a slice.
-- v1.2 hotfix: cache by (market.version, filter_signature). Re-computes only
-- when either changes -- NOT every frame. Per-frame cost dropped from
-- ~500ms (worst case) to <0.1ms (cache hit).
function DSP.market.arbitrage_filtered()
    local f = DSP.settings.arb_filters or { budget = 0, min_profit = 0, min_roi = 0, sort = 1 }
    local sig = arb_filter_signature()
    local mver = tonumber(DSP.market.state.version) or 0
    -- Cache hit: same market version + same filters + not dirty.
    if DSP.market.arb_cache
        and DSP.market.arb_cache_version == mver
        and DSP.market.arb_cache_filter_sig == sig
        and not DSP.market.arb_dirty then
        return DSP.market.arb_cache
    end
    -- Cache miss: rebuild. This is the heavy pass (~500k iterations on a
    -- full 800-row market). Runs ONCE per market update or filter change,
    -- NOT per frame.
    local all = DSP.market.arbitrage()
    local out = {}
    local budget = tonumber(f.budget) or 0
    local min_profit = tonumber(f.min_profit) or 0
    local min_roi = tonumber(f.min_roi) or 0
    for _, e in ipairs(all) do
        if budget > 0 and (e.total_cost or 0) > budget then
            -- skip: not enough on hands
        elseif min_profit > 0 and (e.net_profit or 0) < min_profit then
            -- skip: profit too low
        elseif min_roi > 0 and (e.roi or 0) < min_roi then
            -- skip: ROI too low
        else
            out[#out + 1] = e
        end
    end
    local sort = tonumber(f.sort) or 1
    -- Re-sort only if sort != default (default already sorted by arbitrage()).
    if sort ~= 1 then
        table.sort(out, function(a, b)
            if sort == 2 then
                -- per-unit profit
                local pa = a.p_sell - a.p_buy
                local pb = b.p_sell - b.p_buy
                if pa ~= pb then return pa > pb end
            elseif sort == 3 then
                -- ROI
                if (a.roi or 0) ~= (b.roi or 0) then return (a.roi or 0) > (b.roi or 0) end
            end
            return tostring(a.name) < tostring(b.name)
        end)
    end
    DSP.market.arb_cache = out
    DSP.market.arb_cache_version = mver
    DSP.market.arb_cache_filter_sig = sig
    DSP.market.arb_dirty = false
    return out
end

-- Force the arbitrage cache to be invalidated. Call after arbitrage filter
-- changes (UI buttons) or after manual market cache replacement.
function DSP.market.invalidate_arbitrage()
    DSP.market.arb_dirty = true
end

-- Item Finder: search rows by partial name (case-insensitive).
-- Returns matching rows (each with full .sell / .buy offer lists already
-- sorted by finish_side).
function DSP.market.find_item(query)
    local q = DSP.lower(DSP.trim(query))
    if q == '' then return {} end
    local out = {}
    for _, row in ipairs(DSP.market.state.rows or {}) do
        if DSP.lower(row.display):find(q, 1, true) then
            out[#out + 1] = row
        end
    end
    return out
end

-- Group all offers by shop. Returns array of
--   { num, owner, ts (max), sell_count, buy_count, sell_offers = [], buy_offers = [] }
-- where sell_offers = [{ row, offer }] (лавка ПРОДАЁТ to player)
-- and   buy_offers  = [{ row, offer }] (лавка СКУПАЕТ from player)
-- Sorted by ts desc (freshest first).
function DSP.market.shops_list()
    local shops = {}
    for _, row in ipairs(DSP.market.state.rows or {}) do
        for _, offer in ipairs(row.sell.offers) do
            local num = tostring(offer.shop or '?')
            local s = shops[num]
            if not s then
                s = { num = num, owner = offer.owner or '?', ts = offer.ts or 0,
                      sell_count = 0, buy_count = 0,
                      sell_offers = {}, buy_offers = {} }
                shops[num] = s
            end
            if (offer.ts or 0) > s.ts then s.ts = offer.ts end
            s.sell_count = s.sell_count + 1
            s.sell_offers[#s.sell_offers + 1] = { row = row, offer = offer }
        end
        for _, offer in ipairs(row.buy.offers) do
            local num = tostring(offer.shop or '?')
            local s = shops[num]
            if not s then
                s = { num = num, owner = offer.owner or '?', ts = offer.ts or 0,
                      sell_count = 0, buy_count = 0,
                      sell_offers = {}, buy_offers = {} }
                shops[num] = s
            end
            if (offer.ts or 0) > s.ts then s.ts = offer.ts end
            s.buy_count = s.buy_count + 1
            s.buy_offers[#s.buy_offers + 1] = { row = row, offer = offer }
        end
    end
    local arr = {}
    for _, s in pairs(shops) do arr[#arr + 1] = s end
    table.sort(arr, function(a, b)
        if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) > (b.ts or 0) end
        return tostring(a.num) < tostring(b.num)
    end)
    return arr
end

-- Send the /findilavka N command to mark a shop on the GPS map.
-- This is the standard Arizona Mobile command for highlighting a CR shop.
function DSP.market.mark_shop(shop_num)
    if shop_num == nil then return false end
    local cmd = '/findilavka ' .. tostring(shop_num)
    if sampSendChat then
        local ok = pcall(sampSendChat, cmd)
        if ok then
            DSP.add_log('Метка лавки: ' .. tostring(shop_num))
            return true
        end
    end
    return false
end

-- Copy a shop's buyback list (buy_slots = items лавка скупает у игрока)
-- into the player's BUY preset (so the player выставляет the same buyback
-- in their own лавка).
-- Args:
--   shop_num   -- the shop number whose buy offers to copy
--   preset_name -- override name for the new preset (optional)
--   markup     -- price markup in $ to apply (default 1, i.e. +1$ to outbid)
-- Returns: count of items copied, or nil + error
function DSP.market.copy_shop_skupka(shop_num, preset_name, markup)
    markup = tonumber(markup) or 1
    local shops = DSP.market.shops_list()
    local target
    for _, s in ipairs(shops) do
        if tostring(s.num) == tostring(shop_num) then
            target = s
            break
        end
    end
    if not target then return nil, 'лавка не найдена' end
    if target.buy_count == 0 then return nil, 'у лавки нет скупки' end
    local p = DSP.settings.buy_preset
    if not p.items then p.items = {} end
    if preset_name then p.name = preset_name
    elseif p.name == 'Скупка' then
        p.name = 'Скупка_' .. tostring(target.owner)
    end
    local added = 0
    for _, entry in ipairs(target.buy_offers) do
        local row = entry.row
        local offer = entry.offer
        -- Skip if already in preset (matched by row key including @ench)
        local exists = false
        for _, it in ipairs(p.items) do
            if it.key == row.key then exists = true break end
        end
        if not exists then
            local price = math.max(1, math.floor((tonumber(offer.price) or 0) + markup))
            p.items[#p.items + 1] = {
                key = row.key,
                name = row.display,
                ench = row.ench or 0,
                price = price,
                qty = 1,
                enabled = true,
            }
            added = added + 1
        end
    end
    DSP.save_settings()
    DSP.add_log(string.format('Скопировано скупки: лавка #%s, +%d поз. (markup +%d$)',
        tostring(shop_num), added, markup))
    return added
end

-- =========================================================================
-- v1.2 Stage 3 hotfix: CR marker scan (dialog 15073) + median market prices.
-- =========================================================================

-- Path to the CR-marker snapshot file for a given server id.
function DSP.market.cr_marker_path(sid)
    sid = tonumber(sid) or DSP.market.state.sid or 102
    return DSP.dir .. '/prices_server_' .. tostring(sid) .. '.json'
end

-- Live scan state. Set by scan_cr_marker(), read by on_cr_marker_dialog()
-- in 40_auto.lua when dialog 15073 fires.
DSP.market._cr_cache = DSP.market._cr_cache or {}
DSP.market.cr_marker_seen_at = DSP.market.cr_marker_seen_at or 0
DSP.market.cr_scan_state = {
    active = false,
    page = 0,
    total = 0,
    items = {},
    status = 'не сканирован',
    started_at = 0,
}

-- Kick off the CR marker scan. The user must be standing on the CR
-- checkpoint that opens dialog 15073. We arm the scan state; the actual
-- page-flipping happens in on_cr_marker_dialog() when 40_auto.lua fires
-- the sampev.onShowDialog hook.
function DSP.market.scan_cr_marker()
    if DSP.market.cr_scan_state.active then
        DSP.notify('Скан ЦР: уже идёт, дождитесь окончания')
        return false
    end
    DSP.market.cr_scan_state.active = true
    DSP.market.cr_scan_state.sid = tonumber(DSP.market.state.sid)
    DSP.market.cr_scan_state.page = 0
    DSP.market.cr_scan_state.total = 0
    DSP.market.cr_scan_state.items = {}
    DSP.market.cr_scan_state.last_page_text = nil
    DSP.market.cr_scan_state.started_at = os.time()
    DSP.market.cr_scan_state.status = 'ожидание диалога 15073 (встаньте на метку ЦР)'
    DSP.add_log('Скан ЦР: запущен, встаньте на метку средних цен ЦР')
    -- Auto-expire after 60 seconds if no dialog fires.
    if lua_thread and wait then
        lua_thread.create(function()
            local deadline = os.time() + 60
            while DSP.market.cr_scan_state.active and os.time() < deadline do
                wait(500)
            end
            if DSP.market.cr_scan_state.active then
                DSP.market.cr_scan_state.active = false
                DSP.market.cr_scan_state.status = 'таймаут ЦР (стр. '..DSP.market.cr_scan_state.page..'), старые данные сохранены'
                DSP.add_log('Скан ЦР: таймаут, снимок не заменён', 'error')
            end
        end)
    end
    return true
end

-- Save the CR marker snapshot. Format mirrors the in-memory rows map so
-- that load_cr_marker can rehydrate rows without API calls.
function DSP.market.load_cr_marker(sid)
    sid = tonumber(sid) or DSP.market.state.sid or 102
    local cached = DSP.market._cr_cache[sid]
    if cached ~= nil then return cached or nil end
    local f = io.open(DSP.market.cr_marker_path(sid), 'rb')
    if not f then DSP.market._cr_cache[sid]=false;return nil end
    local raw = f:read('*a')
    f:close()
    local ok, pack = pcall(decodeJson, raw)
    if not ok or type(pack) ~= 'table' or (tonumber(pack.sid) and tonumber(pack.sid) ~= sid) then
        DSP.market._cr_cache[sid]=false;return nil
    end
    DSP.market._cr_cache[sid]=pack
    return pack
end

function DSP.market.save_cr_marker(sid)
    sid = tonumber(sid) or DSP.market.state.sid or 102
    local old = DSP.market.load_cr_marker(sid)
    local s = DSP.market.cr_scan_state
    local pack = {
        saved_at = os.time(), sid = sid,
        items = s.sid == sid and #s.items>0 and s.items or (old and old.items or {}),
        page = s.page, total = s.total,
        histories = (old and old.histories) or {},
    }
    local ok, json = pcall(encodeJson, pack)
    if not ok or not json then DSP.flog('CR MARKER save failed: '..tostring(json));return false end
    local f = io.open(DSP.market.cr_marker_path(sid), 'wb')
    if not f then return false end
    local wrote = f:write(json)
    local closed = f:close()
    if not wrote or not closed then return false end
    DSP.market._cr_cache[sid] = pack
    DSP.flog(string.format('CR MARKER saved sid=%d items=%d page=%d',sid,#pack.items,pack.page))
    return true
end

-- Incoming 15073 list and its history detail are trusted only as server
-- observations, not proof that an offered item is still available now.
function DSP.market.mark_cr_dialog()
    DSP.market.cr_marker_seen_at = os.time()
    DSP.market.cr_marker_seen_sid = tonumber(DSP.market.state.sid)
end

-- CP price formats observed in the Market Helper 15073 scanner:
-- $61.300, :CASH:61300, K61.3, KK1.25, M2.5.
function DSP.market.parse_cr_price(raw)
    local v = DSP.clean_text(raw or ''):gsub('^:CASH:', '')
    v = v:gsub('^%$%s*',''):gsub('%s*%$$',''):gsub('%s+','')
    local unit, number = v:match('^([ККМKkMm]+)([%d%.,]+)$')
    local multiplier
    if unit then
        if unit=='КК' or unit=='KK' or unit=='kk' or unit=='Kk' or unit=='kK' then multiplier=1000000
        elseif unit=='М' or unit=='M' or unit=='m' then multiplier=1000000000
        elseif unit=='К' or unit=='K' or unit=='k' then multiplier=1000
        else return nil end
        local n=tonumber((number:gsub(',','.')))
        if not n then return nil end
        v=n*multiplier
    else
        if not v:match('^[%d%.,]+$') then return nil end
        -- Each 3-digit group in 12.345.678 is a thousands separator.
        if v:match('^%d%d?%d?[%.,]%d%d%d') then v=v:gsub('[%.,]','')
        elseif v:find('[%.,]') then return nil end
        v=tonumber(v)
    end
    if type(v)~='number' or v~=v or v<1 or v>9007199254740991 then return nil end
    return math.floor(v+0.000001)
end

function DSP.market.parse_cr_list_line(line)
    local s = DSP.clean_text(line or '')
    local name, raw = s:match('^(.-)%s*	+%s*(.+)$')
    if not name then name,raw = s:match('^(.-)%s%s+([^%s].-)%s*$') end
    if not name or not raw then return nil end
    name = DSP.trim(name:gsub('^%d+[%.%)]%s*',''))
    if name=='' or name=='Поиск по названию' or name:find('Следующая',1,true)
        or name:find('Предыдущая',1,true) then return nil end
    local p = DSP.market.parse_cr_price(raw)
    if not p then return nil end
    return name,p
end

-- Passively observes the history detail opened by the player at CR.
-- No automatic purchases, server responses or UI actions are sent here.
function DSP.market.observe_cr_detail(title, text)
    local seen = tonumber(DSP.market.cr_marker_seen_at) or 0
    if seen<=0 or os.time()-seen>120 then return false end
    local sid = tonumber(DSP.market.state.sid)
    if not sid or sid ~= tonumber(DSP.market.cr_marker_seen_sid) then return false end
    local t = DSP.clean_text(title or '')
    if not t:find('Продажа товара',1,true) then return false end
    local name = t:match("'([^']+)'") or t:match('"([^"]+)"')
    if not name or name=='' then return false end
    local nowday = os.date('%Y-%m-%d')
    local total_value,total_qty=0,0
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        local dt,qty_s,price_s=line:match('(%d%d%d%d%-%d%d%-%d%d)%s+([%d]+)%s+([^|]+)')
        if dt == nowday and qty_s and price_s then
            local qty=tonumber(qty_s)
            local price=DSP.market.parse_cr_price(price_s)
            if qty and qty%1==0 and qty>0 and qty<=100000000 and price
                and total_value <= 9007199254740991 - qty*price then
                total_value=total_value+qty*price
                total_qty=total_qty+qty
            end
        end
    end
    if total_qty<=0 then return false end
    local old=DSP.market.load_cr_marker(sid) or {sid=sid,items={},histories={}}
    old.histories=old.histories or {}
    old.histories[DSP.lower(DSP.clean_text(name))]={day=nowday,qty=total_qty,
        avg=math.floor(total_value/total_qty),ts=os.time()}
    -- Preserve the full current scan on save; do not replace with an empty one.
    DSP.market._cr_cache[sid]=old
    return DSP.market.save_cr_marker(sid)
end

-- Called from 40_auto.lua's on_dialog when sampev.onShowDialog fires with
-- id == 15073. Parses the dialog text for items + average prices, then
-- sends "Next page" response or finalizes the scan.
--
-- We try several formats because Arizona Mobile dialog text varies:
--   "Item name ........ $X (sell) / $Y (buy) | qty: N"
--   "1. Item name — sell: $X / buy: $Y"
--   "Item name | средняя: $X | скупка: $Y | остаток: N"
-- Anything we can't parse, we log + skip (no crash).
function DSP.market.on_cr_marker_dialog(text)
    if not DSP.market.cr_scan_state.active then return false end
    local s=DSP.market.cr_scan_state
    if s.sid and s.sid ~= tonumber(DSP.market.state.sid) then
        s.active=false;s.status='сервер изменился, скан остановлен'
        return false
    end
    if s.last_page_text==text then
        s.status='Повтор той же страницы; ожидается обновление сервера'
        return true
    end
    s.last_page_text=text
    s.page=s.page+1
    local found={}
    for i,it in ipairs(s.items) do found[DSP.lower(it.name)]=i end
    local parsed=0
    local line_no=0
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        line_no=line_no+1
        if line_no>3 then
            local name,price=DSP.market.parse_cr_list_line(line)
            if name and price then
                local key=DSP.lower(name)
                local row={name=name,sell_med=price,buy_med=nil,ts=os.time(),source='cr_average'}
                if found[key] then s.items[found[key]]=row
                else s.items[#s.items+1]=row;found[key]=#s.items end
                parsed=parsed+1
            end
        end
    end
    s.status=string.format('Сканирование: стр. %d, %d товаров',s.page,#s.items)
    DSP.flog('CR MARKER page='..s.page..' parsed='..parsed..' total='..#s.items)
    local next_idx=nil
    local n=0
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        n=n+1
        local c=DSP.clean_text(line)
        if n>1 and (c:find('Следующая страница',1,true) or c=='Далее') then
            next_idx=n-2 -- 15073's first row is the header, per Market Helper.
            break
        end
    end
    if next_idx and sampSendDialogResponse and sampGetCurrentDialogId then
        local did=sampGetCurrentDialogId()
        if lua_thread and wait then
            lua_thread.create(function()
                wait(150)
                if not s.active then return end
                pcall(sampSendDialogResponse,did,1,next_idx,'')
            end)
        else pcall(sampSendDialogResponse,did,1,next_idx,'') end
        return true
    end
    s.active=false
    if parsed<=0 and #s.items==0 then
        s.status='Не распознан список ЦР: нужны реальные строки 15073'
        DSP.add_log('Скан ЦР: формат не распознан; старые данные сохранены','error')
    else
        s.status=string.format('Готово: %d товаров на %d стр.',#s.items,s.page)
        DSP.market.save_cr_marker(DSP.market.state.sid)
        DSP.add_log('Скан ЦР: готово, '..#s.items..' товаров','ok')
    end
    if sampSendDialogResponse and sampGetCurrentDialogId then
        pcall(sampSendDialogResponse,sampGetCurrentDialogId(),0,0,'')
    end
    return true
end

-- Compute median market prices from the live va-ta.com data (DSP.market.state).
-- Returns { sell_med, buy_med, sell_min, sell_max, buy_min, buy_max, shops_n }
-- for a given row. Used when no CR marker snapshot is available.
function DSP.market.median_prices(row)
    if not row then return nil end
    local function side_stats(side)
        if not side or side.count == 0 then
            return { med = 0, min = 0, max = 0, shops_n = 0 }
        end
        local n = #side.prices
        if n == 0 then
            return { med = side.med or 0, min = side.min or 0, max = side.max or 0, shops_n = side.shop_n or 0 }
        end
        -- prices is already sorted asc by finish_side, so median is the middle element.
        local mid = math.floor((n + 1) / 2)
        return {
            med = side.prices[mid],
            min = side.prices[1],
            max = side.prices[n],
            shops_n = side.shop_n or 0,
        }
    end
    return {
        sell = side_stats(row.sell),
        buy = side_stats(row.buy),
    }
end

-- Format the "Рынок сервера #N: Продажа ~X$ | Скупка ~Y$ (на основе N лавок)"
-- header line for a given row. Falls back to CR marker snapshot if available,
-- else uses live median from va-ta.com data.
function DSP.market.market_label_for(row)
    if not row then return '' end
    local sid = tonumber(DSP.market.state.sid) or 0
    -- Try CR marker snapshot first
    local marker = DSP.market.load_cr_marker(sid)
    if marker and marker.items then
        for _, it in ipairs(marker.items) do
            if DSP.lower(it.name or '') == DSP.lower(row.name or '') then
                return string.format('Рынок ЦР #%d: Продажа ~%s | Скупка ~%s (метка %s)',
                    sid, DSP.money(it.sell_med or 0), DSP.money(it.buy_med or 0),
                    os.date('%d.%m %H:%M', marker.saved_at or 0))
            end
        end
    end
    -- Fall back to live va-ta.com medians
    local med = DSP.market.median_prices(row)
    if not med then return '' end
    local sell = med.sell or { med = 0, shops_n = 0 }
    local buy = med.buy or { med = 0, shops_n = 0 }
    if sell.med == 0 and buy.med == 0 then return '' end
    local shops = math.max(sell.shops_n or 0, buy.shops_n or 0)
    return string.format('Рынок #%d: Продажа ~%s | Скупка ~%s (на основе %d лавок)',
        sid, DSP.money(sell.med), DSP.money(buy.med), shops)
end


-- Quantity is not a single trustworthy number. Older mobile clients can send
-- one *slot* as qty=1 to /shops/push even when the game contains a large stack.
-- Keep API snapshots immutable until the player explicitly confirms a live
-- observation. No network requests, parsing of unrelated packets or IO here.
local function quantity_integer(v)
    local n=tonumber(v)
    if n and n==n and n>=0 and n<=9007199254740991 and n%1==0 then return n end
end
function DSP.market.format_units(n)
    local v=quantity_integer(n)
    if not v then return '?' end
    return tostring(v):reverse():gsub('(%d%d%d)','%1 '):reverse():gsub('^ ','')
end
function DSP.market.live_offer_quantity(row, side, offer)
    if not row or (side~='sell' and side~='buy') or not offer then return nil end
    local s=DSP.live and DSP.live.shop
    if not s or not s.num or tostring(s.num)=='' or tostring(s.num)~=tostring(offer.shop) then return nil end
    local sid=tonumber(DSP.market.state.sid)
    if not sid or tonumber(s.server)~=sid or (s.menu_closed or 0)>0 then return nil end
    if not s.owner or s.owner=='' then return nil end
    local owner=DSP.lower(DSP.trim(tostring(offer.owner or '')))
    if owner~='' and owner~='?' and DSP.lower(DSP.trim(s.owner))~=owner then return nil end
    local stamp=tonumber(s.items_updated) or 0
    if stamp<=0 or stamp>os.time()+60 or os.time()-stamp>120 then return nil end
    local wanted=row.key or DSP.item_key(row.name or row.display or '',row.ench or 0)
    local total,matched,unknown=0,0,false
    for _,it in ipairs(s[side] or {}) do
        if DSP.item_key(it.name or '',it.ench or 0)==wanted and tonumber(it.price)==tonumber(offer.price) then
            matched=matched+1
            local n=it.qty_known==true and quantity_integer(it.qty) or nil
            if not n then unknown=true else total=total+n end
        end
    end
    if matched==0 or unknown then return nil end
    return total,{source='game',shop=s.num,seen_at=stamp,slots=matched}
end
function DSP.market.quantity_info(row,side,offer)
    local api=quantity_integer(offer and (offer.snapshot_qty or offer.qty))
    local live,meta=DSP.market.live_offer_quantity(row,side,offer)
    return {api=api,shown=quantity_integer(offer and offer.qty),
        verified=offer and offer.verified_at~=nil or false,
        live=live,live_meta=meta,
        disagreement=live~=nil and api~=nil and live~=api}
end
