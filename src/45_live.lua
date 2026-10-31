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

local function mono_ms()
    if getGameTimer then
        local ok,v=pcall(getGameTimer)
        if ok and type(v)=='number' then return v end
    end
    return os.time()*1000
end

local function decode(raw)
    raw = tostring(raw or ''):gsub('%z+$', '')
    if raw == '' then return nil end
    local ok, d = pcall(decodeJson, raw)
    if ok and type(d) == 'table' then return d end
    return nil
end

-- Decimal punctuation belongs to the number when there is a k/kk/m suffix.
-- Without a suffix, accept grouped thousands (1.500.000 or 1,500,000).
function DSP.money_val(s)
    s = tostring(s or ''):gsub('{[%x]+}', ''):gsub('%s+', '')
    local low = s:lower()
    local mult = 1
    if low:find('kk', 1, true) or low:find('êê', 1, true) then
        mult = 1000000
    elseif low:find('m', 1, true) or low:find('ì', 1, true) then
        mult = 1000000
    elseif low:find('k', 1, true) or low:find('ê', 1, true) then
        mult = 1000
    end
    local number = s:match('(%d[%d%,%.]*)')
    if not number then return 0 end
    local separators = select(2, number:gsub('[%,%.]', ''))
    if separators > 0 then
        local groups = {}
        for group in number:gmatch('%d+') do groups[#groups + 1] = group end
        local grouped = #groups > 1 and #groups[1] <= 3
        for i = 2, #groups do if #groups[i] ~= 3 then grouped = false end end
        if mult == 1 and grouped then
            number = table.concat(groups)
        elseif separators == 1 then
            number = number:gsub(',', '.')
        elseif grouped then
            number = table.concat(groups)
        else
            return 0 -- malformed or ambiguous mixed separators
        end
    end
    local n = tonumber(number)
    if not n or n ~= n or n < 0 then return 0 end
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
        complete = false, _recorded = false,
    }
    DSP.flog('TRADE reset partner=' .. tostring(partner or ''))
end

local function trade_fingerprint(t)
    local function items_key(items)
        local parts = {}
        for _, it in ipairs(items or {}) do
            parts[#parts + 1] = table.concat({tostring(it.id or ''),
                tostring(it.name or ''), tostring(it.ench or 0), tostring(it.qty or 1)}, ':')
        end
        table.sort(parts)
        return table.concat(parts, ';')
    end
    return table.concat({tostring(t.partner), tostring(t.money_give), tostring(t.money_get),
        items_key(t.give), items_key(t.get)}, '|')
end

-- Both packet confirmation and result dialog go through this single guard.
function L.record_trade_once(t)
    if not t or t._recorded then return false end
    if #(t.give or {}) == 0 and #(t.get or {}) == 0
        and (t.money_give or 0) <= 0 and (t.money_get or 0) <= 0 then return false end
    local fingerprint, ts = trade_fingerprint(t), now()
    local last = L.last_recorded
    if last and last.fingerprint == fingerprint and ts - last.at <= 5 then
        t._recorded = true -- retransmitted result after another start event
        return false
    end
    if not (DSP.logs and DSP.logs.record_trade) then return false end
    t._recorded = true -- before callback: protects reentrant and duplicate events
    L.last_recorded = {fingerprint=fingerprint, at=ts}
    local ok, err = pcall(DSP.logs.record_trade, t.partner, t.give, t.get,
        t.money_give, t.money_get, 'accepted')
    if not ok then
        -- A logging callback may have partially persisted the trade; never retry blindly.
        DSP.flog('TRADE record failed, manual review needed: '..tostring(err))
    end
    return ok
end

local function shop_server()
    return tonumber(DSP.settings and DSP.settings.server) or tonumber(DSP.market and DSP.market.state and DSP.market.state.sid) or 0
end
local function shop_changed(s)
    L.shop_revision=(L.shop_revision or 0)+1;s.revision=L.shop_revision
end
function L.reset_shop(owner, num)
    L._auto_scan_pending=false
    L._auto_scan_stable_ticks=0
    L.shop_generation=(L.shop_generation or 0)+1
    L.shop = {
        owner = owner or '', num = tostring(num or ''),
        sell = {}, buy = {}, seen = {},
        opened = now(), updated = now(), items_updated = 0, menu_closed = 0,generation=L.shop_generation,server=shop_server(),
        fragment_count=0,last_fragment_ms=0,scan_complete=false,
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
        if t._recorded or t.partner ~= partner or now() - (t.updated or 0) > 300 then
            L.reset_trade(partner)
        else
            t.partner = partner
            t.updated = now()
        end
        return
    end
    if not t or t.opened == 0 then L.reset_trade(t and t.partner or '?') end
    t = L.trade
    if t._recorded then return end
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
        if t.complete then L.record_trade_once(t) end
    elseif sub == 6 then
        local sg = tonumber(raw:match('"self"%s*:%s*{[^}]-"value"%s*:%s*(%d+)'))
        local tg = tonumber(raw:match('"target"%s*:%s*{[^}]-"value"%s*:%s*(%d+)'))
        if sg then t.money_give = sg end
        if tg then t.money_get = tg end
        t.updated = now()
        DSP.flog('TRADE sub6 give=' .. tostring(t.money_give) .. ' get=' .. tostring(t.money_get))
        if t.complete then L.record_trade_once(t) end
    elseif sub == 4 then
        local sc = tonumber(raw:match('"self"%s*:%s*{[^}]-"confirm"%s*:%s*(%d+)')) or 0
        local tc = tonumber(raw:match('"target"%s*:%s*{[^}]-"confirm"%s*:%s*(%d+)')) or 0
        local sa = tonumber(raw:match('"self"%s*:%s*{[^}]-"accept"%s*:%s*(%d+)')) or 0
        local ta = tonumber(raw:match('"target"%s*:%s*{[^}]-"accept"%s*:%s*(%d+)')) or 0
        if sa == 1 and ta == 1 and sc == 1 and tc == 1 then
            t.complete = true
            DSP.flog('TRADE complete partner=' .. tostring(t.partner))
            L.record_trade_once(t)
        end
        t.updated = now()
    end
end

-- Auto-capture happens AFTER the game's stall packets settle, not in the
-- network packet callback. This prevents stalls on large 100-180 slot menus.
-- The menu must be opened; proximity alone contains no confirmed prices.
L.auto_scan = {shop='',items=0,at=0,attempts=0}
L.scan_diagnostics = {reason='idle', generation=0, at=0}
-- Truthful per-opening scan state; visible even when the game does not
-- supply a usable numeric stall ID. Such menus are NOT added to routes.
function L.scan_state(shop)
    local s = shop or L.shop or {}
    local n = #(s.sell or {}) + #(s.buy or {})
    if DSP.settings and DSP.settings.auto_shop_scan == false then return 'disabled',n end
    if n == 0 then return 'empty',0 end
    if tonumber(s.server or 0) ~= shop_server() or tonumber(s.server or 0) == 0 then return 'server',n end
    if DSP.shop_identity and DSP.shop_identity.resolve then pcall(DSP.shop_identity.resolve,s) end
    local diagnostic=L.scan_diagnostics
    if diagnostic and diagnostic.generation==s.generation and diagnostic.reason=='error' then
        return 'error',n
    end
    if L._auto_scan_pending then return 'pending',n end
    local has,row=false,nil
    if DSP.local_arb and DSP.local_arb.has_shop then
        local ok,a,b=pcall(DSP.local_arb.has_shop,s)
        if ok then has,row=a,b end
    end
    if has then
        return tonumber(row and row.num or s.num) and 'saved' or 'saved_unmapped',n
    end
    return 'not_saved',n
end
local function scan_diag(reason, s, detail)
    s=s or L.shop or {}
    local previous=L.scan_diagnostics
    local generation=s.generation or 0
    if not previous or previous.reason~=reason or previous.generation~=generation then
        if DSP.flog then DSP.flog('SCAN STATUS '..tostring(reason)..' generation='..tostring(generation)
            ..' shop='..tostring(s.num or '')..' sell='..tostring(#(s.sell or {}))
            ..' buy='..tostring(#(s.buy or {}))..' server='..tostring(s.server or '')
            .. (detail and (' detail='..tostring(detail)) or '')) end
    end
    L.scan_diagnostics={reason=reason,generation=generation,at=os.time(),detail=detail}
end
function L.commit_shop_autoscan(defer_io)
    if not L._auto_scan_pending or (DSP.settings and DSP.settings.auto_shop_scan==false) then
        return false,'disabled'
    end
    local s=L.shop
    if not s or (s.items_updated or 0)<=0 or (#(s.sell or {})+#(s.buy or {}))==0 then
        scan_diag('empty',s);return false,'empty'
    end
    if tonumber(s.server)~=shop_server() or tonumber(s.server)==0 then
        scan_diag('server',s);return false,'server'
    end
    if DSP.shop_identity and DSP.shop_identity.resolve then
        local ok,n,src=pcall(DSP.shop_identity.resolve,s)
        if ok and n then s.num=tostring(n);s.num_source=src or s.num_source end
    end
    local count=#(s.sell or {})+#(s.buy or {})
    local learned=0
    if DSP.shop_scan and DSP.shop_scan.learn then
        local ok,r=pcall(DSP.shop_scan.learn,{defer_save=defer_io==true})
        if ok and type(r)=='table' and r.ok then learned=r.count or 0
        elseif DSP.flog then DSP.flog('AUTO SCAN learn error: '..tostring(ok and r and r.error or r)) end
    end
    local arb=DSP.local_arb
    if not(arb and arb.observe and arb.has_shop)then scan_diag('error',s,'shop store unavailable');return false,'error' end
    local ok,r,detail,saved_row=pcall(arb.observe,s,os.time())
    if not ok or (not r and detail~='unchanged') then scan_diag('error',s,ok and detail or r);return false,'error' end
    local verified,row=arb.has_shop(s)
    row=row or saved_row
    if not verified then scan_diag('error',s,'missing saved snapshot');return false,'error' end
    L._auto_scan_pending=false;L._auto_scan_stable_ticks=0;s.scan_complete=true
    -- Recalculate plans once a stable shop scan has been observed.
    -- Never mutate API stock and never claim a complete authoritative snapshot.
    if DSP.market and DSP.market.invalidate_arbitrage then DSP.market.invalidate_arbitrage() end
    L.auto_scan.shop=tostring((row and row.num)or s.num or '')
    L.auto_scan.identity=tostring((row and row.identity)or s.local_identity or '')
    L.auto_scan.owner=tostring((row and row.owner)or s.owner or '')
    L.auto_scan.mapped=tonumber((row and row.num)or s.num)~=nil
    L.auto_scan.num_source=tostring((row and row.number_source)or s.num_source or 'unknown')
    L.auto_scan.items=count;L.auto_scan.at=os.time();L.auto_scan.attempts=(L.auto_scan.attempts or 0)+1
    L.auto_scan.learned=learned;L.auto_scan.server=s.server;L.auto_scan.generation=s.generation
    L.auto_scan.sell=#(s.sell or {});L.auto_scan.buy=#(s.buy or {})
    if not defer_io and arb.flush then pcall(arb.flush) end
    scan_diag(L.auto_scan.mapped and 'saved' or 'saved_unmapped',s)
    return true,count,row
end
function L.queue_shop_autoscan()
    if DSP.settings and DSP.settings.auto_shop_scan==false then return end
    L._auto_scan_pending=true;L._auto_scan_stable_ticks=0
    if L.shop then scan_diag('pending',L.shop) end
    -- Unit-test/minimal hosts without a scheduler still get a deterministic commit.
    if not(lua_thread and lua_thread.create and wait) then L.commit_shop_autoscan(true) end
end
function L.tick_shop_autoscan()
    if DSP.db and DSP.db._dirty and type(DSP.db.save)=='function' and os.time()-(DSP.db.last_save or 0)>=10 then DSP.db.save(false) end
    if DSP.settings and DSP.settings.auto_shop_scan==false then L._auto_scan_pending=false;return end
    if not L._auto_scan_pending then return end
    local s=L.shop or {}
    local quiet=tonumber(DSP.settings and DSP.settings.scan_quiet_ms)or 650
    quiet=math.max(250,math.min(2500,quiet))
    local last=tonumber(s.last_fragment_ms)or 0
    if getGameTimer then
        if last>0 and mono_ms()-last<quiet then return end
        local grace=tonumber(DSP.settings and DSP.settings.identity_grace_ms)or 1500
        grace=math.max(0,math.min(5000,grace))
        if (not tonumber(s.num)) and tostring(s.owner or '')=='' and last>0 and mono_ms()-last<grace then return end
    else
        if L._auto_scan_last_revision==(s.revision or 0) then L._auto_scan_stable_ticks=(L._auto_scan_stable_ticks or 0)+1
        else L._auto_scan_last_revision=s.revision or 0;L._auto_scan_stable_ticks=0 end
        if (L._auto_scan_stable_ticks or 0)<2 then return end
    end
    L.commit_shop_autoscan(true)
end

local function shop_number(obj,key)
    local raw=obj:match('"'..key..'"%s*:%s*"([^" ]+)"') or obj:match('"'..key..'"%s*:%s*([%+%-%.%deE]+)')
    local n=tonumber(raw)
    if n and n==n and n>=0 and n<=9007199254740991 and n%1==0 then return n end
end
function L.parse_shop_item(obj, side, ordinal)
    local s=L.ensure_shop();local row=nil
    if type(obj)=='table' and DSP.item_registry and DSP.item_registry.from_node then
        row=DSP.item_registry.from_node(obj,side,ordinal)
    else
        local raw=tostring(obj or '')
        local item_raw=raw:match('"item"%s*:%s*"([^"]+)"') or raw:match('"item"%s*:%s*(%d+)')
        if item_raw then
            local node={item=item_raw,slot=shop_number(raw,'slot'),enchant=shop_number(raw,'enchant'),
                price=shop_number(raw,'price'),count=shop_number(raw,'count'),qty=shop_number(raw,'qty'),
                quantity=shop_number(raw,'quantity'),text=raw:match('"text"%s*:%s*"([^"]*)"')or''}
            if DSP.item_registry and DSP.item_registry.from_node then row=DSP.item_registry.from_node(node,side,ordinal) end
        end
    end
    if not row and type(obj)=='string' then
        local raw=tostring(obj or '')
        local item_raw=raw:match('\"item\"%s*:%s*\"([^\"]+)\"') or raw:match('\"item\"%s*:%s*(%d+)')
        if item_raw then
            local ench=shop_number(raw,'enchant') or 0
            local it=L.item_from_id(item_raw,ench,1)
            local slot=shop_number(raw,'slot')
            local price=shop_number(raw,'price')
            local qty=shop_number(raw,'count') or shop_number(raw,'qty') or shop_number(raw,'quantity')
            if it and price and price>0 then
                local key=side..':'..(slot and ('slot:'..tostring(slot)) or ('item:'..tostring(it.id)..':'..tostring(it.ench)..':p'..tostring(price)))
                row={key=key,slot=slot,name=it.name,ench=it.ench,id=it.id,item_id=it.id,price=price,qty=qty,qty_known=qty~=nil,slot_count=1,ordinal=ordinal}
            end
        end
    end
    if not row then return false end
    local list=side=='sell' and s.sell or s.buy
    local previous=s.seen[row.key]
    if previous and previous.id==row.id and previous.ench==row.ench and previous.price==row.price and previous.qty==row.qty then return false end
    if previous then for i,e in ipairs(list)do if e==previous then list[i]=row;break end end
    else list[#list+1]=row end
    s.seen[row.key]=row;shop_changed(s);return true
end

local function decoded_shop_nodes(raw)
    if not(DSP.item_registry and DSP.item_registry.decode_nodes)then return {},nil end
    local ok,nodes,root=pcall(function()local a,b=DSP.item_registry.decode_nodes(raw);return a,b end)
    if not ok then return {},nil end
    return nodes or {},root
end
function L.handle_shop_items(raw)
    local decoded_nodes,decoded=decoded_shop_nodes(raw)
    local tp=decoded and tonumber(decoded.type or decoded.interface_type or decoded.kind)or tonumber(tostring(raw or ''):match('"type"%s*:%s*(%d+)'))or 0
    if tp~=13 and tp~=28 then return end
    local s=L.ensure_shop();if s.server~=shop_server()then L.reset_shop('','');s=L.shop end
    local first_slot=nil
    if #decoded_nodes>0 then first_slot=tonumber(decoded_nodes[1].slot or decoded_nodes[1].slot_id or decoded_nodes[1].slotId) end
    first_slot=first_slot or tonumber(tostring(raw or ''):match('"slot"%s*:%s*(%d+)'))
    local stale=now()-(s.items_updated or 0)>10
    if first_slot==0 and((s.menu_closed or 0)>0 or((s.items_updated or 0)>0 and stale))then L.reset_shop('','');s=L.shop end
    s.updated=now();s.items_updated=s.updated;if s.opened==0 then s.opened=s.updated end;s.menu_closed=0;s.scan_complete=false
    local side=tp==13 and'sell'or'buy';local parsed=0
    if #decoded_nodes>0 then
        for i,node in ipairs(decoded_nodes)do if L.parse_shop_item(node,side,i)then parsed=parsed+1 end end
    else
        -- Compatibility fallback for malformed/non-JSON packets.
        local i=0
        for obj in tostring(raw or ''):gmatch('{([^}]+)}')do
            if obj:find('"item"',1,true)then i=i+1;if L.parse_shop_item(obj,side,i)then parsed=parsed+1 end end
        end
    end
    if parsed>0 then
        s.fragment_count=(tonumber(s.fragment_count)or 0)+1;s.last_fragment_ms=mono_ms();L.queue_shop_autoscan()
        if DSP.flog then DSP.flog('SHOP fragment side='..side..' parsed='..parsed..' total='..(#s.sell+#s.buy)..' fragment='..s.fragment_count)end
    end
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
    -- Owner metadata may arrive after all item packets; schedule another
    -- auto-scan only when a menu contains actual offers.
    if (s.items_updated or 0)>0 then L.queue_shop_autoscan() end
end

function L.handle(iface, sub, raw)
    -- Passive discovery subscriber. Never consumes the packet or changes trade logic.
    if iface==52 and DSP.storage_probe and DSP.storage_probe.on_packet then
        local ok,err=pcall(DSP.storage_probe.on_packet,sub,raw)
        if not ok and DSP.flog then DSP.flog('STORAGE probe error: '..tostring(err)) end
    end
    -- Own-stall inventory acknowledgement. Real sale listing must first open
    -- the stall inventory, just like the native UI does.
    if iface==52 and sub==2 and DSP.auto then
        local _tp=tonumber(tostring(raw or ''):match('"type"%s*:%s*(%d+)')) or 0
        if _tp==1 then
            DSP.auto.stall_inventory_ready=true
            DSP.auto.stall_inventory_seen_at=os.time()
            if DSP.flog then DSP.flog('TRADE stall inventory ready (iface52/type1)') end
        end
    end
    -- Route only confirmed vehicle trunk inventory (type=8). Other iface 52
    -- packets must continue through the existing shop/player handler.
    if iface == 52 and DSP.storage and DSP.storage.on_inventory_packet
        and tonumber(tostring(raw):match('"type"%s*:%s*(%d+)')) == 8 then
        local ok, err = pcall(DSP.storage.on_inventory_packet, sub, raw)
        if not ok and DSP.flog then DSP.flog('TRUNK packet error: '..tostring(err)) end
        return
    end
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
        if tp == 3 and title:find('Ìåí', 1, true) then
            local s = L.ensure_shop()
            if (s.menu_closed or 0)>0 then L.reset_shop('','');s=L.shop end
            s.updated = now()
            if s.opened == 0 then s.opened = s.updated end
            s.menu_closed = 0
        end
    elseif iface == 255 then
        -- Finalize pending game data before the menu becomes closed. The save
        -- itself is deferred; disk writes during a network callback cause lag.
        if L._auto_scan_pending then L.commit_shop_autoscan(L._auto_scan_worker==true) end
        if L.shop and (L.shop.menu_closed or 0)==0 then
            L.shop.menu_closed=now();shop_changed(L.shop)
            if DSP.market and DSP.market.invalidate_arbitrage then DSP.market.invalidate_arbitrage() end
        end
        if DSP.local_arb and DSP.local_arb.flush and not L._auto_scan_worker then
            -- Test/fallback hosts do not run the background save coroutine.
            local ok,err=pcall(DSP.local_arb.flush)
            if not ok then DSP.flog('LOCAL ARB flush error: '..tostring(err)) end
        end
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
    local original_offset = nil
    if type(raknetBitStreamGetReadOffset)=='function' then
        local o,v = pcall(raknetBitStreamGetReadOffset, bs)
        if o then original_offset = v end
    end
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
    if original_offset ~= nil and type(raknetBitStreamSetReadOffset)=='function' then
        pcall(raknetBitStreamSetReadOffset, bs, original_offset)
    else
        pcall(raknetBitStreamResetReadPointer, bs)
    end
end

function L.parse_dialog_trade(title, text)
    local partner = strip(title or ''):match('Ðåçóëüòàò ñäåëêè ñ (.-)%s*$') or ''
    if partner == '' then return end
    local t = L.trade
    if not t or t.opened == 0 or t.partner ~= partner then L.reset_trade(partner) end
    t = L.trade
    if t._recorded then return end
    local sec = ''
    local give, get = {}, {}
    -- v1.2 hotfix: Lua 5.5 forbids reassigning for-loop variables.
    -- Use a separate local `ln` instead of reassigning `line`.
    -- (LuaJIT 5.1 permits it but lupa's Lua 5.5 sandbox test enforces the rule.)
    for raw_line in tostring(text or ''):gsub('{[%x]+}', ''):gmatch('[^\r\n]+') do
        local line = strip(raw_line)
        if line:find('Ïåðåä', 1, true) then
            sec = 'give'
        elseif line:find('Ïîëó÷', 1, true) then
            sec = 'get'
        elseif line:find('Êîìèñ', 1, true) then
            sec = ''
        elseif (sec == 'give' or sec == 'get') and line ~= '' and line ~= '-' then
            local money = DSP.money_val(line)
            local is_money = (line:find('%$') or line:lower():find('êê') or line:lower():find('kk')) and money > 0
            if is_money then
                if sec == 'give' then t.money_give = money else t.money_get = money end
            else
                local nm, qty = line:match('^(.-)%s*[xXõÕ]%s*(%d+)%s*$')
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
    if DSP.storage and DSP.storage.on_dialog then
        local ok,err=pcall(DSP.storage.on_dialog,dialog_id,style,title,text)
        if not ok then DSP.flog('STORAGE dialog: '..tostring(err))end
    end
    if dialog_id == 28148 then
        L.parse_dialog_trade(title, text)
        -- Also check for trade result in dialog text
        local txt = DSP.clean_text(text or '')
        local low_txt = DSP.lower and DSP.lower(txt) or txt
        if low_txt:find('ñäåëêà', 1, true) or low_txt:find('îáìåí', 1, true) then
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
                    -- Packet and dialog acknowledgements share one idempotency guard.
                    L.record_trade_once(t)
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
    if lua_thread and lua_thread.create and wait then
        L._auto_scan_worker=true
        local ok,err=pcall(function()
            lua_thread.create(function()
                while true do
                    wait(200)
                    local good,why=pcall(L.tick_shop_autoscan)
                    if not good then DSP.flog('AUTO SCAN tick: '..tostring(why)) end
                end
            end)
        end)
        if not ok then L._auto_scan_worker=false;DSP.flog('AUTO SCAN worker: '..tostring(err)) end
    end
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
        local function capture(text,is_server)
            if type(text) ~= 'string' or text == '' then return end
            local ts = os.time()
            -- Do not use ordinary player chat to mark stalls nonexistent.
            -- Also handle a server reply even if the same text was logged via
            -- another chat event less than a second earlier.
            if is_server and DSP.market and DSP.market.on_shop_lookup_feedback then
                local success, err=pcall(DSP.market.on_shop_lookup_feedback,text,ts)
                if not success then DSP.flog('FINDILAVKA feedback error: '..tostring(err)) end
            end
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
            capture(text,true)
            if prev_server then return prev_server(color, text) end
        end
        local prev_chat = sampev.onChatMessage
        sampev.onChatMessage = function(message, author, answer)
            capture(message,false)
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
-- speculative market valuations. Reward 'Âû ïîëó÷èëè $' is handled by R.parse.
function L.check_income_message(text)
    local s=DSP.lower(DSP.clean_text(text or ''))
    local words={
        'âû çàðàáîòàëè', 'äîõîä îò áèçíåñà', 'äîõîä îò àðåíäû',
        'äîõîä ñ äåïîçèòà', 'âàì âûïëà÷åíà çàðïëàòà', 'çàðïëàòà çà ðàáîòó',
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
    for _,side in ipairs({{'sell','ïðîäàëè'},{'buy','êóïèëè'}}) do
        local verb=side[2]
        item,amount=s:match('^Âû '..verb..' (.-) çà %$([%d%., ]+)')
        if not item then item,amount=s:match('^Âû '..verb..' (.-) çà ([%d%., ]+)%$') end
        if item and amount then dir=side[1];break end
    end
    if not dir then
        item,amount=s:match('^Èãðîê .- êóïèë ó âàñ (.-) çà %$([%d%., ]+)')
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
    'ÏýéÄýé',
    'ÏåéÄåé',
    'âû ïîëó÷èëè çàðïëàòó',
    'Âàì íà÷èñëåíà çàðàáîòíàÿ ïëàòà',
}

function L.check_payday_message(text)
    if not text or text == '' then return false end
    local s=DSP.lower(DSP.clean_text(text)):gsub('^[%s|]+','')
    if s:find('%[%d+%]:')or s:match('^%[')then return false end
    local hit=s:match('^payday%s*[!:%.]*$')or s:match('^payday%s*[:%-]')
    for _,header in ipairs({'ÁÀÍÊÎÂÑÊÈÉ ×ÅÊ','âû ïîëó÷èëè çàðïëàòó','âàì íà÷èñëåíà çàðàáîòíàÿ ïëàòà','ÏýéÄýé','ÏåéÄåé'})do
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
    DSP.add_log(string.format('PayDay: %d ñäåëîê, %s%s',
        summary.count,
        summary.profit >= 0 and '+' or '',
        DSP.money(summary.profit)))
    -- Telegram notification (UTF-8 over HTTP)
    if DSP.settings.tg_payday_enabled and DSP.settings.tg_notify and DSP.settings.tg_bot_token and DSP.settings.tg_chat_id then
        local msg = '[palatka ai] PayDay ' .. os.date('%H:%M') .. '\n'
            .. 'Ñäåëîê çà äåíü: ' .. summary.count .. '\n'
            .. 'Ïðèáûëü: ' .. (summary.profit >= 0 and '+' or '') .. DSP.money(summary.profit) .. '\n'
            .. 'Ïîëó÷åíî: ' .. DSP.money(summary.total_get) .. '\n'
            .. 'Îòäàíî: ' .. DSP.money(summary.total_give) .. '\n'
            .. 'ROI: ' .. string.format('%.1f%%', summary.roi) .. '\n'
            .. 'Ñðåäíÿÿ ñäåëêà: ' .. DSP.money(summary.avg_profit)
        if DSP.logs and DSP.logs.send_telegram then
            pcall(DSP.logs.send_telegram, msg)
        end
    end
    return true
end
