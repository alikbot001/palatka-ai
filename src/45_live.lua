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
    -- v1.2 hotfix: Lua 5.5 forbids reassigning for-loop variables.
    -- Use a separate local `ln` instead of reassigning `line`.
    -- (LuaJIT 5.1 permits it but lupa's Lua 5.5 sandbox test enforces the rule.)
    for raw_line in tostring(text or ''):gsub('{[%x]+}', ''):gmatch('[^\r\n]+') do
        local line = strip(raw_line)
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

function L.on_dialog(dialog_id, style, title, b1, b2, text)
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
        -- Chat message capture for item drops
        local prev_chat = sampev.onChatMessage
        sampev.onChatMessage = function(message, author, answer)
            if DSP.logs and DSP.logs.log_chat then
                DSP.logs.log_chat(message)
            end
            if prev_chat then return prev_chat(message, author, answer) end
        end
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

-- =========================================================================
-- v1.2 Stage 3: PayDay detector + Telegram trigger.
--
-- Arizona RP sends a chat message at the start of every in-game hour
-- containing "PayDay" (or localized variant). When we see it, we:
--   1. Compute today's profit summary via DSP.logs.profit_summary('day')
--   2. Push a PayDay marker into the craglog ring buffer
--   3. Send a UTF-8 Telegram message with the day's stats
--   4. Throttle by remembering the last payday epoch (avoid dupes within
--      the same in-game hour)
-- =========================================================================

local PAYDAY_PATTERNS = {
    'PayDay',
    'ПэйДэй',
    'ПейДей',
    'вы получили зарплату',
    'Вам начислена заработная плата',
}

function L.check_payday_message(text)
    if not text or text == '' then return false end
    if not DSP.settings.tg_payday_enabled then return false end
    local s = DSP.lower(text)
    local hit = false
    for _, pat in ipairs(PAYDAY_PATTERNS) do
        if s:find(DSP.lower(pat), 1, true) then
            hit = true
            break
        end
    end
    if not hit then return false end
    -- Throttle: don't fire twice within the same real-world hour.
    local ts = os.time()
    if ts - (tonumber(DSP.settings.tg_payday_last) or 0) < 1800 then
        return false
    end
    DSP.settings.tg_payday_last = ts
    DSP.save_settings()
    -- Build daily summary
    local summary = DSP.logs.profit_summary('day')
    -- Push marker to craglog ring buffer + file
    if DSP.craglog and DSP.craglog.log_payday then
        pcall(DSP.craglog.log_payday, summary)
    end
    DSP.add_log(string.format('PayDay: %d сделок, %s%s',
        summary.count,
        summary.profit >= 0 and '+' or '',
        DSP.money(summary.profit)))
    -- Telegram notification (UTF-8 over HTTP)
    if DSP.settings.tg_notify and DSP.settings.tg_bot_token and DSP.settings.tg_chat_id then
        local msg = '[palatka ai] PayDay ' .. os.date('%H:%M') .. '\n'
            .. 'Сделок за день: ' .. summary.count .. '\n'
            .. 'Прибыль: ' .. (summary.profit >= 0 and '+' or '') .. DSP.money(summary.profit) .. '\n'
            .. 'Получено: ' .. DSP.money(summary.total_get) .. '\n'
            .. 'Отдано: ' .. DSP.money(summary.total_give) .. '\n'
            .. 'ROI: ' .. string.format('%.1f%%', summary.roi) .. '\n'
            .. 'Средняя сделка: ' .. DSP.money(summary.avg_profit)
        if DSP.logs and DSP.logs.send_telegram then
            pcall(DSP.logs.send_telegram, msg)
        end
    end
    return true
end
