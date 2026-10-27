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

local function shop_server()
    return tonumber(DSP.settings and DSP.settings.server) or tonumber(DSP.market and DSP.market.state and DSP.market.state.sid) or 0
end
local function shop_changed(s)
    L.shop_revision=(L.shop_revision or 0)+1;s.revision=L.shop_revision
end
function L.reset_shop(owner, num)
    L.shop_generation=(L.shop_generation or 0)+1
    L.shop = {
        owner = owner or '', num = tostring(num or ''),
        sell = {}, buy = {}, seen = {},
        opened = now(), updated = now(), items_updated = 0, menu_closed = 0,generation=L.shop_generation,server=shop_server(),
    }
    shop_changed(L.shop)
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

local function shop_number(obj,key)
    local raw=obj:match('"'..key..'"%s*:%s*"([^" ]+)"') or obj:match('"'..key..'"%s*:%s*([%+%-%.%deE]+)')
    local n=tonumber(raw)
    if n and n==n and n>=0 and n<=9007199254740991 and n%1==0 then return n end
end
function L.parse_shop_item(obj, side)
    local s=L.ensure_shop()
    local item_raw=obj:match('"item"%s*:%s*"([^"]+)"') or obj:match('"item"%s*:%s*(%d+)')
    if not item_raw then return end
    local slot,ench=shop_number(obj,'slot'),shop_number(obj,'enchant') or 0
    local it=L.item_from_id(item_raw,ench,1)
    local key=side..':'..(slot and tostring(slot) or ('item:'..tostring(it and it.id or item_raw)..':'..tostring(it and it.ench or ench)))
    local list=side=='sell' and s.sell or s.buy
    local previous=s.seen[key]
    local text=obj:match('"text"%s*:%s*"([^"]*)"') or ''
    local raw_price=text:match('%$%s*([%d%., ]+)') or text:match('([%d][%d%., ]*)%s*%$')
    local text_price=raw_price and tonumber((raw_price:gsub('[^%d]','')))
    local price=shop_number(obj,'price') or math.max(text_price or 0,shop_number(obj,'amount') or 0)
    local qty=shop_number(obj,'count') or shop_number(obj,'qty') or shop_number(obj,'quantity')
    if qty==nil then
        -- Read only explicitly labelled units, never infer stack size from
        -- a price or an inventory slot. Accept 45000 and 45.000/45 000 шт.
        local label=text:match('%(([%d%., ]+)%s*шт%.?%)')
            or text:match('([%d][%d%., ]*)%s*шт%.?')
        if label then
            label=label:match('^%s*(.-)%s*$')
            local parts={};for digits in label:gmatch('%d+')do parts[#parts+1]=digits end
            local valid=#parts>0
            if #parts>1 then
                if #parts[1]>3 then valid=false end
                for i=2,#parts do if #parts[i]~=3 then valid=false end end
            end
            if valid then qty=tonumber(table.concat(parts)) end
        end
    end
    if tonumber(item_raw)==0 or price==0 or qty==0 then
        if previous then
            for i,e in ipairs(list) do if e==previous then table.remove(list,i);break end end
            s.seen[key]=nil;shop_changed(s)
        end
        return
    end
    if not it or not price or price<=0 or price>9007199254740991 or price%1~=0 then return end
    if qty and (qty>9007199254740991 or qty<0 or qty%1~=0) then qty=nil end
    if previous and previous.id==it.id and previous.ench==it.ench and previous.price==price and previous.qty==qty then return end
    local row={key=key,slot=slot,name=it.name,ench=it.ench,id=it.id,item_id=it.id,price=price,
        qty=qty,qty_known=qty~=nil,slot_count=1}
    if previous then
        for i,e in ipairs(list) do if e==previous then list[i]=row;break end end
    else list[#list+1]=row end
    s.seen[key]=row;shop_changed(s)
    if DSP.shop_scan then
        local result=DSP.shop_scan.learn()
        if not result.ok then DSP.flog('SHOP learn: '..tostring(result.error)) end
    else DSP.db.learn(it.id,it.ench,price,side) end
end

function L.handle_shop_items(raw)
    local tp = tonumber(raw:match('"type"%s*:%s*(%d+)')) or 0
    if tp ~= 13 and tp ~= 28 then return end
    local s = L.ensure_shop()
    if s.server~=shop_server() then L.reset_shop('','');s=L.shop end
    local first_slot = tonumber(raw:match('"slot"%s*:%s*(%d+)'))
    local stale = now() - (s.items_updated or 0) > 10
    -- A slot-0 packet can start a different stall before its owner metadata.
    -- Never carry the previous stall identity into this new generation. If the
    -- owner packet arrived first, reset_shop() already cleared items_updated;
    -- it belongs to the new generation and must *not* be discarded here.
    if first_slot == 0 and ((s.menu_closed or 0) > 0 or
        ((s.items_updated or 0) > 0 and stale)) then
        L.reset_shop('', '')
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
    if not s or s.updated == 0 or s.server~=shop_server() or (s.menu_closed or 0)>0 or (s.owner ~= '' and s.owner ~= owner)
        or (num and s.num~='' and s.num~=tostring(num)) then
        L.reset_shop(owner, num);s=L.shop
    else
        if s.owner~=owner or (num and s.num~=tostring(num)) then shop_changed(s) end
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
            if (s.menu_closed or 0)>0 then L.reset_shop('','');s=L.shop end
            s.updated = now()
            if s.opened == 0 then s.opened = s.updated end
            s.menu_closed = 0
        end
    elseif iface == 255 then
        if L.shop and (L.shop.menu_closed or 0)==0 then L.shop.menu_closed=now();shop_changed(L.shop) end
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
        -- SA-MP server notifications use onServerMessage(color, text).
        -- onChatMessage is for player chat in some event implementations.
        -- Process both with same short-lived deduplication guard.
        local last_chat_text, last_chat_at = nil, 0
        local function capture(text)
            if type(text) ~= 'string' or text == '' then return end
            local ts = os.time()
            if last_chat_text == text and ts - last_chat_at <= 1 then return end
            last_chat_text, last_chat_at = text, ts
            if DSP.logs and DSP.logs.log_chat then
                local success, err = pcall(DSP.logs.log_chat, text)
                if not success then DSP.flog('CHAT capture error: '..tostring(err)) end
            end
        end
        L.capture_server_chat = capture
        local prev_server = sampev.onServerMessage
        sampev.onServerMessage = function(color, text)
            capture(text)
            if prev_server then return prev_server(color, text) end
        end
        local prev_chat = sampev.onChatMessage
        sampev.onChatMessage = function(message, author, answer)
            capture(message)
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

-- Recognize only explicit cash receipt messages, not account balances or
-- speculative market valuations. Reward 'Вы получили $' is handled by R.parse.
function L.check_income_message(text)
    local s=DSP.lower(DSP.clean_text(text or ''))
    local words={
        'вы заработали', 'доход от бизнеса', 'доход от аренды',
        'доход с депозита', 'вам выплачена зарплата', 'зарплата за работу',
    }
    local label
    for _,word in ipairs(words) do
        if s:find(DSP.lower(word),1,true)==1 then label=word; break end
    end
    if not label then return false end
    local sum=s:match('%$%s*([%d%., ]+)')
    if not sum then sum=s:match('([%d][%d%., ]*)%s*%$') end
    local amount=sum and DSP.money_val(sum) or 0
    if amount<=0 then return false end
    if DSP.craglog and DSP.craglog.log_income then
        pcall(DSP.craglog.log_income,label,amount,text)
    end
    return true
end

-- Conservative bazaar receipt parser. Ignores offers and listed prices.
function L.check_market_message(raw)
    local s=DSP.clean_text(raw or '')
    local dir, item, amount
    for _,side in ipairs({{'sell','продали'},{'buy','купили'}}) do
        local verb=side[2]
        item,amount=s:match('^Вы '..verb..' (.-) за %$([%d%., ]+)')
        if not item then item,amount=s:match('^Вы '..verb..' (.-) за ([%d%., ]+)%$') end
        if item and amount then dir=side[1];break end
    end
    if not dir then
        item,amount=s:match('^Игрок .- купил у вас (.-) за %$([%d%., ]+)')
        if item then dir='sell' end
    end
    local cash=amount and DSP.money_val(amount) or 0
    if not dir or not item or item=='' or cash<=0 then return false end
    if DSP.craglog and DSP.craglog.log_market then
        pcall(DSP.craglog.log_market,dir,item,cash,raw)
    end
    return true
end

local PAYDAY_PATTERNS = {
    'PayDay',
    'ПэйДэй',
    'ПейДей',
    'вы получили зарплату',
    'Вам начислена заработная плата',
}

function L.check_payday_message(text)
    if not text or text == '' then return false end
    local s=DSP.lower(DSP.clean_text(text)):gsub('^[%s|]+','')
    if s:find('%[%d+%]:')or s:match('^%[')then return false end
    local hit=s:match('^payday%s*[!:%.]*$')or s:match('^payday%s*[:%-]')
    for _,header in ipairs({'БАНКОВСКИЙ ЧЕК','вы получили зарплату','вам начислена заработная плата','ПэйДэй','ПейДей'})do
        if s:find(DSP.lower(header),1,true)==1 then hit=true;break end
    end
    if not hit then return false end
    -- Throttle: don't fire twice within the same real-world hour.
    local ts = os.time()
    if L.last_payday_recorded and ts - L.last_payday_recorded < 1800 then
        return false
    end
    L.last_payday_recorded = ts
    DSP.settings.tg_payday_last = ts
    DSP.save_settings()
    -- Build daily summary
    local summary = DSP.logs.profit_summary('day')
    -- Push marker to craglog ring buffer + file
    if DSP.craglog and DSP.craglog.log_payday then
        pcall(DSP.craglog.log_payday, summary, text)
    end
    DSP.add_log(string.format('PayDay: %d сделок, %s%s',
        summary.count,
        summary.profit >= 0 and '+' or '',
        DSP.money(summary.profit)))
    -- Telegram notification (UTF-8 over HTTP)
    if DSP.settings.tg_payday_enabled and DSP.settings.tg_notify and DSP.settings.tg_bot_token and DSP.settings.tg_chat_id then
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
