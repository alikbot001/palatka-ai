-- Read-only inventory analysis for classic SA-MP cabinet/trunk dialogs.
-- Does not issue game commands, move items, infer missing counts or inspect memory.
DSP.storage = DSP.storage or {}
local S = DSP.storage
S.snapshots = S.snapshots or (DSP.settings and DSP.settings.storage_snapshots) or {}
S.last_error = nil
S.max_rows = 180
S.max_saved = 20

local function normal(s)
    s = DSP.clean_text(tostring(s or ''))
    return s:gsub('\t',' '):gsub(' +',' ')
end
local function int(s)
    if not s then return nil end
    s=tostring(s):gsub('[%s%.%,]','')
    if not s:match('^%d+$') then return nil end
    local n=tonumber(s)
    if not n or n<1 or n>2000000000 or n%1~=0 then return nil end
    return n
end
local function kind_of(title)
    local s=DSP.lower(normal(title))
    if s:find('инвентарь',1,true) or s:find('Инвентарь',1,true) then return 'inventory' end
    if s:find('багажник',1,true) or s:find('Багажник',1,true) then return 'trunk' end
    if s:find('шкаф',1,true) or s:find('Шкаф',1,true) then return 'cabinet' end
    if s:find('склад',1,true) or s:find('Склад',1,true) or s:find('хранилище',1,true) or s:find('Хранилище',1,true) then return 'warehouse' end
    return nil
end
S.kind_of = kind_of
function S.parse_line(raw)
    local s=normal(raw)
    -- Strip only UI list position, not arbitrary numeric prefixes or item IDs.
    s=s:gsub('^%s*%d+[%.%)]%s+','')
    if s=='' or #s>320 then return nil end
    local name,qty
    -- An explicit unit is mandatory: 'slot #1' is NOT one item.
    name,qty=s:match('^(.-)%s*%(%s*([%d%., ]+)%s*шт%.?%s*%)%s*$')
    if not name then name,qty=s:match('^(.-)%s*%[%s*([%d%., ]+)%s*шт%.?%s*%]%s*$') end
    if not name then name,qty=s:match('^(.-)%s*[%-%—:]%s*([%d%., ]+)%s*шт%.?%s*$')end
    if not name then name,qty=s:match('^(.-)%s+[xхXХ]%s*([%d%., ]+)%s*$')end
    if not name then name,qty=s:match('^(.-)%s*%([xхXХ]%s*([%d%., ]+)%)%s*$')end
    if not name then
        -- Legitimate unlabeled line: show unknown count, never silently x1.
        if s:find('%$',1,true) or s:find('Выберите',1,true) or s:find('Назад',1,true)
            or DSP.lower(s):find('вместимость',1,true) or s:match('^[-=]+$')
            or s:find('Открыть',1,true) or s:find('Закрыть',1,true)
            or s:find('Забрать',1,true) or s:find('Положить',1,true) then return nil end
        name=s
    end
    name=DSP.trim(name or '')
    if name=='' or #name>125 then return nil end
    if name:match('^%d+$') then return nil end
    local count=int(qty)
    -- Explicitly malformed quantities are not accepted as reliable numeric values.
    return {name=name,qty=count,quantity_confirmed=count~=nil,raw=raw}
end
function S.parse_text(kind,title,text,ts)
    if not S.kind_of(title) or S.kind_of(title)~=kind then return nil,'not a container dialog' end
    if type(text)~='string' then return nil,'not text' end
    local rows,by_name={},{}
    for line in (text..'\n'):gmatch('(.-)\r?\n')do
        if #rows>=S.max_rows then break end
        local r=S.parse_line(line)
        if r then
            local key=DSP.item_key(r.name,0)
            if not by_name[key] then
                rows[#rows+1]=r;by_name[key]=r
            else
                -- Repeated view of the same item in one dialog is ambiguous;
                -- keep separate slots, never fabricate an aggregate count.
                rows[#rows+1]=r
            end
        end
    end
    if #rows==0 then return nil,'no item lines' end
    return {kind=kind,title=normal(title),rows=rows,observed_at=ts or os.time(),
        source='dialog',count_known=0}
end
function S.accept(kind,title,text,ts,source)
    local snap,err=S.parse_text(kind,title,text,ts)
    if not snap then S.last_error=err;return false,err end
    snap.source=source=='manual' and 'manual' or source=='textdraw' and 'textdraw' or 'dialog'
    for _,r in ipairs(snap.rows)do
        if r.qty then snap.count_known=snap.count_known+r.qty end
    end
    local signature=kind..'|'..snap.source..'|'..snap.title..'|'..text
    if S.last_signature==signature and S.last_snapshot and math.abs((ts or os.time())-(S.last_ts or 0))<=3 then
        -- Repeated same dialog callback does not add slots or duplicate snapshots.
        return true,S.last_snapshot
    end
    snap.id=tostring(ts or os.time())..'_'..tostring(#S.snapshots+1)
    snap.server=DSP.market and DSP.market.state and DSP.market.state.sid or nil
    table.insert(S.snapshots,1,snap)
    while #S.snapshots>8 do table.remove(S.snapshots)end
    S.last_signature=signature;S.last_snapshot=snap;S.last_ts=ts or os.time();S.last_error=nil
    if DSP.settings and DSP.save_settings then
        DSP.settings.storage_snapshots=S.snapshots
        local ok,err=DSP.save_settings()
        if not ok then S.last_error='Не удалось сохранить снимок: '..tostring(err) end
    end
    return true,snap
end
function S.on_dialog(id,style,title,text)
    local kind=kind_of(title)
    if not kind then return false end
    local ok,err=S.accept(kind,title,text)
    if ok then DSP.flog('STORAGE read-only '..kind..' rows='..#S.snapshots[1].rows..' dialog='..tostring(id))
    else DSP.flog('STORAGE unavailable '..tostring(err))end
    return ok
end
local function market_lookup(name,ench)
    local row=DSP.market and DSP.market.row_for and DSP.market.row_for(name,ench or 0)
    if not row then return nil,nil end
    local buy=row.buy and tonumber(row.buy.max)
    local sell=row.sell and tonumber(row.sell.min)
    if buy and buy<=0 then buy=nil end
    if sell and sell<=0 then sell=nil end
    return buy,sell
end
S.market_lookup=market_lookup
function S.item_group_key(row)
    if tonumber(row.id) and tonumber(row.id)>0 then
        return 'id:'..tostring(math.floor(tonumber(row.id)))..':'..tostring(tonumber(row.ench) or 0)
    end
    return 'name:'..DSP.item_key(row.name or '',tonumber(row.ench) or 0)
end
function S.set_manual_price(snapshot, row, amount)
    local n=tonumber(amount)
    if not n or n~=n or n<0 or n>9007199254740991 or n%1~=0 then return false,'invalid price' end
    local found=false
    for _,s in ipairs(S.snapshots or{}) do if s==snapshot then found=true;break end end
    if not found then return false,'stale snapshot' end
    local key=S.item_group_key(row)
    snapshot.manual_prices=snapshot.manual_prices or {}
    local previous=snapshot.manual_prices[key]
    local sid=tostring(snapshot.server or (DSP.market and DSP.market.state and DSP.market.state.sid) or 0)
    DSP.settings.storage_prices=DSP.settings.storage_prices or {}
    DSP.settings.storage_prices[sid]=DSP.settings.storage_prices[sid] or {}
    local global=DSP.settings.storage_prices[sid]
    local old_global=global[key]
    global[key]=n>0 and n or nil
    snapshot.manual_prices[key]=n>0 and n or nil
    if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
    if DSP.save_settings then
        local called,ok,err=pcall(DSP.save_settings)
        if not called or not ok then
            snapshot.manual_prices[key]=previous
            global[key]=old_global
            return false,tostring(err or ok or 'save error')
        end
    end
    S.sort_cache=setmetatable({},{__mode='k'})
    return true
end
function S.set_snapshot_label(snapshot,label)
    if type(label)~='string' then return false,'invalid label' end
    label=DSP.trim(DSP.clean_text(label))
    if #label>66 or label=='' then return false,'name must be 1-66 bytes' end
    local found=false
    for _,saved in ipairs(S.snapshots or{})do if saved==snapshot then found=true;break end end
    if not found then return false,'stale snapshot' end
    -- The live trunk is disposable by design. Renaming it must create a
    -- persistent library entry, otherwise the next scan would erase the name.
    if snapshot.source=='packet220_trunk' then
        if not S.save_named_trunk then return false,'archive function unavailable' end
        return S.save_named_trunk(snapshot,label)
    end
    local previous=snapshot.title
    snapshot.title=label
    if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
    if DSP.save_settings then
        local called,ok,err=pcall(DSP.save_settings)
        if not called or not ok then snapshot.title=previous;return false,tostring(err or ok or 'save error')end
    end
    return true,snapshot
end
function S.evaluate(snapshot,lookup)
    lookup=lookup or market_lookup
    local res={total_qty=0,known_qty_rows=0,unknown_qty=0,missing_prices=0,
        sell_to_buyers=0,ask_value=0,estimated_rows=0,rows={},cross_server=false}
    local current=DSP.market and DSP.market.state and DSP.market.state.sid
    local wrong_server=snapshot and snapshot.server and current and tonumber(snapshot.server)~=tonumber(current)
    res.cross_server=not not wrong_server
    local by_key={}
    for i,src in ipairs(snapshot and snapshot.rows or{})do
        local key=S.item_group_key(src)
        local row=by_key[key]
        if not row then
            row={key=key,name=src.name,ench=src.ench or 0,id=src.id,qty=0,
                bid=nil,ask=nil,index=i,slots=0,unknown_slots=0}
            by_key[key]=row;res.rows[#res.rows+1]=row
            if not wrong_server then row.bid,row.ask=lookup(src.name,src.ench or 0) end
            local prices=DSP.settings and DSP.settings.storage_prices
            local server=tostring(snapshot.server or (DSP.market and DSP.market.state and DSP.market.state.sid) or 0)
            local shared=prices and prices[server]
            local manual=(snapshot.manual_prices and snapshot.manual_prices[key]) or (shared and shared[key])
            if manual and tonumber(manual) and tonumber(manual)>0 then
                row.bid=tonumber(manual);row.manual_price=true
            end
        end
        row.slots=row.slots+1
        if src.qty then
            row.qty=row.qty+src.qty
            res.total_qty=res.total_qty+src.qty
            res.known_qty_rows=res.known_qty_rows+1
            if row.bid then res.sell_to_buyers=res.sell_to_buyers+row.bid*src.qty;res.estimated_rows=res.estimated_rows+1
            else res.missing_prices=res.missing_prices+1 end
            if row.ask then res.ask_value=res.ask_value+row.ask*src.qty end
        else
            row.unknown_slots=row.unknown_slots+1
            res.unknown_qty=res.unknown_qty+1
        end
    end
    for _,row in ipairs(res.rows) do if row.unknown_slots>0 and row.qty==0 then row.qty=nil end end
    return res
end

S.sort_cache=setmetatable({},{__mode='k'})
function S.sorted(snapshot,mode,lookup)
    if not lookup and snapshot then
        local st=DSP.market and DSP.market.state or {}
        local key=tostring(mode)..'/'..tostring(st.sid)..'/'..tostring(st.version)
        local entry=S.sort_cache[snapshot]
        if entry and entry.key==key then return entry.rows,entry.info end
    end
    local info=S.evaluate(snapshot,lookup)
    local sorted=info.rows
    table.sort(sorted,function(a,b)
        if mode=='category' then
            local function cat(n)
                n=DSP.lower(tostring(n or ''))
                if n:find('дров',1,true) or n:find('металл',1,true) or n:find('камень',1,true)
                    or n:find('лен',1,true) or n:find('хлоп',1,true) then return 1 end
                if n:find('ларец',1,true) or n:find('кейс',1,true) then return 2 end
                if n:find('деталь тюнинга',1,true) then return 3 end
                return 4
            end
            if cat(a.name)~=cat(b.name)then return cat(a.name)<cat(b.name)end
        elseif mode=='qty' then
            if (a.qty or -1)~=(b.qty or -1)then return(a.qty or -1)>(b.qty or -1)end
        elseif mode=='value' then
            local av=a.bid and a.qty and a.bid*a.qty or -1
            local bv=b.bid and b.qty and b.bid*b.qty or -1
            if av~=bv then return av>bv end
        elseif mode=='price' then
            if (a.bid or -1)~=(b.bid or -1)then return(a.bid or -1)>(b.bid or -1)end
        end
        return tostring(a.name)<tostring(b.name)
    end)
    if not lookup and snapshot then
        local st=DSP.market and DSP.market.state or {}
        S.sort_cache[snapshot]={key=tostring(mode)..'/'..tostring(st.sid)..'/'..tostring(st.version),rows=sorted,info=info}
    end
    return sorted,info
end

-- Palatka AI v2.2.13 / Packet220 inventory trunk only (type=8).
-- Runs within __mod_47_storage, after the original storage/sorting functions.
-- No packet injection, commands, memory hooks or automatic inventory actions.
S.trunk = S.trunk or {status='idle', received=0, last_error=nil}
local T = S.trunk
local TRUNK_TYPE, TRUNK_SLOTS = 8, 180
local PENDING_TIMEOUT = 15       -- seconds to receive the 180-slot full snapshot
-- Partial slot changes are intentionally not applied without vehicle identity.

local function valid_slot(v)
    local n = tonumber(v)
    if n and n % 1 == 0 and n >= 0 and n < TRUNK_SLOTS then return n end
    return nil
end

local function valid_count(v)
    local n = tonumber(v)
    if n and n == n and n >= 0 and n <= 2000000000 and n % 1 == 0 then return n end
    return nil
end

local function sanitized_slot(it)
    if type(it) ~= 'table' then return nil end
    local slot = valid_slot(it.slot)
    if slot == nil then return nil end
    local id = it.item == nil and 0 or tonumber(it.item)
    if not id or id ~= id or id < 0 or id > 2000000000 or id % 1 ~= 0 then return nil end
    local amount = id > 0 and valid_count(it.amount) or 0
    return {slot=slot,item_id=id,qty=amount,
        ench=tonumber(it.enchant) or 0,empty=(id == 0)}
end

local function parse_payload(raw)
    if type(raw) ~= 'string' or #raw == 0 or #raw > 100000 then return nil end
    -- StringCompressor occasionally returns an extra trailing NUL byte.
    raw = raw:gsub('%z+$','')
    local ok, obj = pcall(decodeJson, raw)
    if not ok or type(obj) ~= 'table' or tonumber(obj.type) ~= TRUNK_TYPE
        or type(obj.items) ~= 'table' or #obj.items > TRUNK_SLOTS then return nil end
    local normalized, used = {}, {}
    for _, item in ipairs(obj.items) do
        local sl = sanitized_slot(item)
        if not sl or used[sl.slot] then return nil end
        used[sl.slot] = true
        normalized[#normalized+1] = sl
    end
    return normalized
end

local function active_snapshot()
    for _, s in ipairs(S.snapshots or {}) do
        if s.source == 'packet220_trunk' and s.kind == 'trunk' then return s end
    end
    return nil
end

local function build_rows(slots)
    local rows, count, occupied = {}, 0, 0
    for i=0,TRUNK_SLOTS-1 do
        local v = slots[i+1]
        if v and v.item_id and v.item_id > 0 then
            local name = DSP.items and DSP.items.name and DSP.items.name(v.item_id)
                or ('ID:'..tostring(v.item_id))
            if type(name) ~= 'string' or name == '' then name='ID:'..tostring(v.item_id) end
            rows[#rows+1] = {
                slot=i,id=v.item_id,name=name,ench=v.ench or 0,
                qty=v.qty,quantity_confirmed=v.qty ~= nil,
            }
            occupied=occupied+1
            if v.qty then count=count+v.qty end
        end
    end
    return rows,count,occupied
end

local function save_snapshot(slots, source_reason)
    local ts=os.time()
    local rows, total, occupied = build_rows(slots)
    local previous = active_snapshot()
    local requested_at=T.requested_at
    local update_target_id=T.update_target_id
    local snap={
        id=previous and previous.id or ('trunk_latest_'..tostring(ts)),
        kind='trunk',
        -- No persistent vehicle identity in observed packet. This is ALWAYS the last opened trunk.
        title='Последний открытый багажник',
        source='packet220_trunk', identity_verified=false,
        observed_at=ts, updated_at=ts, server=DSP.market and DSP.market.state and DSP.market.state.sid or nil,
        slots_count=TRUNK_SLOTS, occupied_slots=occupied,count_known=total,
        rows=rows, slots=slots, update_kind=source_reason,
    }
    -- One latest trunk, not a fabricated history of unique cars. Preserve manual and legacy snapshots.
    local new_list={snap}
    for _, old in ipairs(S.snapshots or {}) do
        if old.source ~= 'packet220_trunk' then
            new_list[#new_list+1]=old
            if #new_list >= 8 then break end
        end
    end
    -- Keep the old verified snapshot until the new one is safely persisted.
    local old_list=S.snapshots
    local old_saved=DSP.settings and DSP.settings.storage_snapshots
    local old_snap,old_updated=T.snapshot,T.last_update
    local old_occ,old_total=T.occupied,T.total
    local old_saved_at,old_completed_at=T.last_saved_at,T.last_completed_request_at
    S.snapshots=new_list
    if DSP.settings then DSP.settings.storage_snapshots=new_list end
    T.snapshot=snap;T.last_update=ts;T.status='saved';T.received=TRUNK_SLOTS
    T.occupied=occupied;T.total=total
    T.last_saved_at=ts
    if requested_at then
        T.last_completed_request_at=ts
        T.requested_at=nil
        T.completed_update_target_id=update_target_id
        T.update_target_id=nil
    end
    if DSP.save_settings then
        local called,ok,err=pcall(DSP.save_settings)
        if not called or not ok then
            S.snapshots=old_list
            if DSP.settings then DSP.settings.storage_snapshots=old_saved end
            T.snapshot=old_snap;T.last_update=old_updated
            T.occupied=old_occ;T.total=old_total
            T.last_saved_at=old_saved_at
            T.last_completed_request_at=old_completed_at
            T.requested_at=requested_at
            T.update_target_id=update_target_id
            T.completed_update_target_id=nil
            T.status='save_error'
            T.last_error=tostring(called and (err or 'save_settings returned false') or ok)
            if DSP.flog then DSP.flog('TRUNK save failed: '..T.last_error) end
            return false
        end
    end
    T.last_error=nil
    if DSP.flog then DSP.flog('TRUNK '..source_reason..' slots=180 occupied='..occupied..' count='..total) end
    return true
end

-- No vehicle/container ID is exposed by the observed packets. A partial
-- update could belong to an entirely different trunk. Never merge it into
-- a previously saved snapshot without a verified identity.

-- Only handles JSON with type=8; never processes other inventory blocks (market/player/etc).
function S.on_inventory_packet(sub, raw)
    -- Real trunk full snapshots use subid=0. subid=2 carries a separate slot
    -- namespace for other inventory blocks; never merge it with trunk slots.
    if tonumber(sub)~=0 then return false end
    T.raw_packet_events=(T.raw_packet_events or 0)+1
    T.last_raw_packet_at=os.time()
    if not (T.autoscan_enabled or T.requested_at) then return false end
    local items=parse_payload(raw)
    if not items or #items == 0 then
        T.invalid_packet_events=(T.invalid_packet_events or 0)+1
        T.last_error='type 8 received; payload could not be decoded'
        return false
    end
    local ts=os.time()
    -- Observed incoming payload; do not claim the trunk window is open.
    T.packet_events=(T.packet_events or 0)+1
    T.last_packet_at=ts
    if T.pending and (ts-T.pending.started)>PENDING_TIMEOUT then
        T.pending=nil;T.status='incomplete';T.last_error='Incomplete 180-slot batch timed out'
    end
    -- A trunk may arrive in chunks whose first chunk is not slot 0.
    -- type=8 is already the confirmed trunk namespace; large batches start a
    -- fresh capture, while tiny <=5 slot deltas remain ignored.
    local starts_capture=(not T.pending and #items>5)
    local explicit_restart=(T.pending and #items>5 and items[1] and items[1].slot==0 and T.pending.seen[0])
    local stale_restart=(T.pending and #items>5 and T.pending.last_at and (ts-T.pending.last_at)>3)
    if starts_capture or explicit_restart or stale_restart then
        T.pending={slots={},seen={},count=0,started=ts,last_at=ts}
        T.status='receiving';T.received=0;T.last_error=nil
    end
    if T.pending then
        local p=T.pending
        p.last_at=ts
        for _,v in ipairs(items) do
            if not p.seen[v.slot] then p.seen[v.slot]=true;p.count=p.count+1 end
            p.slots[v.slot+1]=v
        end
        T.received=p.count
        if p.count==TRUNK_SLOTS then
            -- Full snapshot is committed only after ALL slots 0..179 were seen.
            local complete=true
            for i=1,TRUNK_SLOTS do if not p.slots[i] then complete=false;break end end
            if complete then
                T.pending=nil
                save_snapshot(p.slots,'full')
            end
        end
        return true
    end
    -- If the user started a new scan while the trunk was already open,
    -- the game usually sends only tiny slot deltas when an item moves. Those
    -- deltas are not a full second trunk and must never replace the old scan.
    if #items<=5 then
        if T.requested_at then
            T.saw_delta_after_request=true
            T.status='need_reopen'
            T.last_error='Полный снимок не пришёл. Закрой багажник и открой его заново.'
        elseif T.snapshot then
            T.status='unverified_delta'
            T.last_error='Частичное изменение пропущено: ID машины неизвестен.'
        end
        return false
    end
    T.status=T.requested_at and 'need_reopen' or 'unknown_partial'
    if T.requested_at then
        T.last_error='Получена только часть. Закрой багажник и открой заново.'
    end
    return false
end

-- Load the most recently persisted trunk as read-only history after restart.
T.snapshot=active_snapshot()
T.autoscan_enabled=not (DSP.settings and DSP.settings.storage_trunk_autoscan==false)
if T.snapshot then T.status='saved_from_disk';T.occupied=T.snapshot.occupied_slots;T.total=T.snapshot.count_known end

-- The normal UI uses these methods; no additional game commands are needed.
function S.set_trunk_autoscan(enabled)
    local value=not not enabled
    local prior=T.autoscan_enabled
    T.autoscan_enabled=value
    if DSP.settings then DSP.settings.storage_trunk_autoscan=value end
    if DSP.save_settings then
        local ok,saved,err=pcall(DSP.save_settings)
        if not ok or not saved then
            T.autoscan_enabled=prior
            if DSP.settings then DSP.settings.storage_trunk_autoscan=prior end
            return false,tostring(err or saved or 'save failed')
        end
    end
    if not value and not T.requested_at then
        T.pending=nil
        T.status='disabled'
    elseif value and T.status=='disabled' then
        T.status='idle'
    end
    return true
end

function S.begin_trunk_scan(update_target_id)
    T.pending=nil
    T.received=0
    T.last_error=nil
    T.last_completed_request_at=nil
    T.completed_update_target_id=nil
    T.update_target_id=update_target_id
    T.requested_at=os.time()
    T.scan_started_at=T.requested_at
    T.scan_raw_start=T.raw_packet_events or 0
    T.scan_packet_start=T.packet_events or 0
    T.saw_delta_after_request=false
    T.status='waiting_open'
    return true
end

function S.cancel_trunk_scan()
    T.pending=nil
    T.received=0
    T.requested_at=nil
    T.update_target_id=nil
    T.completed_update_target_id=nil
    T.saw_delta_after_request=false
    T.status=T.autoscan_enabled and 'idle' or 'disabled'
    T.last_error=nil
    return true
end

function S.find_snapshot(id)
    if not id then return nil end
    for i,saved in ipairs(S.snapshots or {}) do
        if tostring(saved.id)==tostring(id) then return saved,i end
    end
    return nil
end

function S.delete_snapshot(snapshot)
    if type(snapshot)~='table' then return false,'Хранилище не выбрано' end
    if snapshot.source=='packet220_trunk' then
        return S.clear_live_snapshot()
    end
    local index=nil
    for i,saved in ipairs(S.snapshots or {})do
        if saved==snapshot then index=i;break end
    end
    if not index then return false,'Хранилище уже удалено' end
    local prior=S.snapshots
    local prior_saved=DSP.settings and DSP.settings.storage_snapshots
    local fresh={}
    for i,saved in ipairs(prior)do if i~=index then fresh[#fresh+1]=saved end end
    S.snapshots=fresh
    if DSP.settings then DSP.settings.storage_snapshots=fresh end
    if DSP.save_settings then
        local called,ok,err=pcall(DSP.save_settings)
        if not called or not ok then
            S.snapshots=prior
            if DSP.settings then DSP.settings.storage_snapshots=prior_saved end
            return false,tostring(err or ok or 'save error')
        end
    end
    S.sort_cache=setmetatable({},{__mode='k'})
    return true
end

function S.clear_live_snapshot()
    local prior=S.snapshots
    local prior_saved=DSP.settings and DSP.settings.storage_snapshots
    local fresh={}
    for _,saved in ipairs(prior or {})do
        if saved.source~='packet220_trunk' then fresh[#fresh+1]=saved end
    end
    S.snapshots=fresh
    if DSP.settings then DSP.settings.storage_snapshots=fresh end
    local old_snapshot=T.snapshot
    T.snapshot=nil;T.occupied=nil;T.total=nil;T.received=0
    T.last_saved_at=nil;T.last_completed_request_at=nil
    if not T.requested_at then T.status=T.autoscan_enabled and 'idle' or 'disabled' end
    if DSP.save_settings then
        local called,ok,err=pcall(DSP.save_settings)
        if not called or not ok then
            S.snapshots=prior
            if DSP.settings then DSP.settings.storage_snapshots=prior_saved end
            T.snapshot=old_snapshot
            return false,tostring(err or ok or 'save error')
        end
    end
    S.sort_cache=setmetatable({},{__mode='k'})
    return true
end

function S.library()
    local rows={}
    for i,saved in ipairs(S.snapshots or {}) do
        if saved.source~='packet220_trunk' then
            rows[#rows+1]={snapshot=saved,index=i}
        end
    end
    return rows
end

-- Keep manually named copies independent from the latest automatically opened
-- vehicle. The packet has no trusted vehicle ID: do NOT auto-assign old labels
-- when a different trunk is opened.
function S.save_named_trunk(snapshot,label)
    if type(snapshot)~='table' or snapshot.source~='packet220_trunk' then
        return false,'select a confirmed full trunk snapshot'
    end
    if not snapshot.rows or snapshot.slots_count~=TRUNK_SLOTS then
        return false,'incomplete trunk snapshot'
    end
    local name=DSP.trim(DSP.clean_text(tostring(label or '')))
    if name=='' or #name>66 or name:find('[%c]') then
        return false,'name must contain 1-66 characters without controls'
    end
    S._named_seq=(S._named_seq or 0)+1
    local ts=os.time()
    local rows={}
    for i,r in ipairs(snapshot.rows) do
        rows[i]={slot=r.slot,id=r.id,name=r.name,ench=r.ench,
            qty=r.qty,quantity_confirmed=r.quantity_confirmed}
    end
    local named={id='trunk_saved_'..tostring(ts)..'_'..tostring(S._named_seq),
        title=name,kind='trunk',source='packet220_trunk_named',
        identity_verified=false,complete_verified=true,
        observed_at=snapshot.observed_at,server=snapshot.server,
        slots_count=TRUNK_SLOTS,occupied_slots=snapshot.occupied_slots,
        count_known=snapshot.count_known,rows=rows}
    for _,existing in ipairs(S.snapshots or {}) do
        if existing.source~='packet220_trunk' and DSP.lower(tostring(existing.title or ''))==DSP.lower(name) then
            return false,'Такое название уже есть. Открой его и выбери «Обновить».'
        end
    end
    local prior=S.snapshots
    local prior_saved=DSP.settings and DSP.settings.storage_snapshots
    local fresh={}
    if prior[1] and prior[1].source=='packet220_trunk' then
        fresh[#fresh+1]=prior[1]
    end
    fresh[#fresh+1]=named
    for _,existing in ipairs(prior) do
        if existing~=named and existing~=fresh[1] then
            fresh[#fresh+1]=existing
            if #fresh>=S.max_saved+1 then break end
        end
    end
    S.snapshots=fresh
    if DSP.settings then DSP.settings.storage_snapshots=fresh end
    if DSP.save_settings then
        local ok,saved,err=pcall(DSP.save_settings)
        if not ok or not saved then
            S.snapshots=prior
            if DSP.settings then DSP.settings.storage_snapshots=prior_saved end
            return false,tostring(err or saved or 'save failed')
        end
    end
    T.completed_update_target_id=nil
    S.sort_cache=setmetatable({},{__mode='k'})
    return true,named
end

function S.apply_latest_to_saved(target_id)
    local live=T.snapshot
    local target=S.find_snapshot(target_id)
    if not live or live.source~='packet220_trunk' or live.slots_count~=TRUNK_SLOTS then
        return false,'Нет полного нового скана'
    end
    if not target or target.source~='packet220_trunk_named' then
        return false,'Сохранённый багажник не найден'
    end
    local backup={
        rows=target.rows,observed_at=target.observed_at,server=target.server,
        occupied_slots=target.occupied_slots,count_known=target.count_known,
        slots_count=target.slots_count,updated_at=target.updated_at
    }
    local rows={}
    for i,row in ipairs(live.rows or {}) do
        rows[i]={slot=row.slot,id=row.id,name=row.name,ench=row.ench,
            qty=row.qty,quantity_confirmed=row.quantity_confirmed}
    end
    target.rows=rows
    target.observed_at=live.observed_at
    target.updated_at=os.time()
    target.server=live.server
    target.occupied_slots=live.occupied_slots
    target.count_known=live.count_known
    target.slots_count=TRUNK_SLOTS
    if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
    if DSP.save_settings then
        local called,ok,err=pcall(DSP.save_settings)
        if not called or not ok then
            for k,v in pairs(backup) do target[k]=v end
            if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
            return false,tostring(err or ok or 'save error')
        end
    end
    T.completed_update_target_id=nil
    S.sort_cache=setmetatable({},{__mode='k'})
    return true,target
end

-- Refresh timeout status when the scanner panel is drawn, even if no more packets arrive.
function S.trunk_state()
    local now=os.time()
    if T.pending and now-T.pending.started>PENDING_TIMEOUT then
        T.pending=nil;T.status='incomplete';T.last_error='Incomplete 180-slot batch timed out'
    end
    if T.requested_at and now-T.requested_at>45 then
        T.requested_at=nil
        T.update_target_id=nil
        if T.status=='waiting_open' or T.status=='receiving' or T.status=='need_reopen' then
            T.status='no_packets'
            T.last_error='Полный снимок 180/180 не получен. Запусти скан и заново открой багажник.'
        end
    end
    return T
end
