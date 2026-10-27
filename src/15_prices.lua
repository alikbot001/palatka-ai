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
    if base and (tonumber(base.ench) or 0) == ench then return base, false, 'api_base' end
    e = DSP.db.learned[key]
    if e then return e, true, 'shop' end
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


-- Display-only price references. They are prices from observed shop offers,
-- never an average of completed sales. No IO, network calls or sorting in UI.
local function valid_quote(side)
    if type(side) ~= 'table' then return nil end
    local price = tonumber(side.med)
    local count = tonumber(side.count) or 0
    if price and price == price and price >= 1 and price <= 9007199254740991
        and count > 0 then return math.floor(price) end
    return nil
end

function DSP.db.reference_prices(name, ench)
    local out = {market=nil, buy=nil, today=nil,
        today_reason='Нет подтверждённых данных о завершённых продажах за сегодня',
        source='Нет данных рынка', updated=0}
    local st = DSP.market and DSP.market.state or {}
    local sid = tonumber(DSP.settings and DSP.settings.server)
    if sid and tonumber(st.sid) and sid ~= tonumber(st.sid) then
        out.source = 'Снимок рынка относится к другому серверу'
        return out
    end
    local row = DSP.market and DSP.market.row_for and DSP.market.row_for(name, ench)
    if not row and DSP.db.get then
        local old = DSP.db.get(name, ench)
        if old and (not sid or tonumber(old.sid) == sid) then row = old end
    end
    if row then
        out.market = valid_quote(row.sell)
        out.buy = valid_quote(row.buy)
        out.updated = tonumber(row.updated) or tonumber(st.updated) or 0
    end
    if out.market or out.buy then
        out.source = 'Наблюдаемые объявления, не завершённые сделки'..(out.updated>0 and (' · '..os.date('%d.%m %H:%M',out.updated)) or '')
    end
    local marker = DSP.market and DSP.market.load_cr_marker and DSP.market.load_cr_marker(tonumber(st.sid))
    if (tonumber(ench) or 0) == 0 and marker and tonumber(marker.sid)==tonumber(st.sid) then
        local key=DSP.lower(DSP.clean_text(name or ''))
        for _,item in ipairs(marker.items or {}) do
            if DSP.lower(DSP.clean_text(item.name or ''))==key then
                local cp_price=tonumber(item.sell_med)
                if cp_price and cp_price>0 then
                    out.market=math.floor(cp_price)
                    out.source='Средняя цена ЦР, снимок от '..os.date('%d.%m %H:%M',marker.saved_at or 0)
                end
                break
            end
        end
        local history=marker.histories and marker.histories[key]
        if history and history.day==os.date('%Y-%m-%d') then
            local avg=tonumber(history.avg)
            if avg and avg>0 and (tonumber(history.qty) or 0)>0 then
                out.today=math.floor(avg)
                out.today_reason='По истории продаж ЦР за сегодня ('..history.qty..' шт.)'
            end
        end
    end
    return out
end

function DSP.db.apply_reference(item, side)
    if type(item) ~= 'table' then return false, 'не выбран предмет' end
    local q = DSP.db.reference_prices(item.name or '', item.ench)
    local n = q[side]
    if not n then
        return false, side == 'today' and q.today_reason
            or 'Нет наблюдаемой цены для этой кнопки на текущем сервере'
    end
    item.price = n
    item.needs_price = nil
    item.enabled = true
    return true, 'Цена подставлена из снимка рынка, проверьте актуальность'
end
