-- Palatka AI 2.8.1 smart storage library beta. Native mimgui only.
PALATKA_UPDATE_VERSION = '2.8.1'
return function(DSP)
  local function module_storage()
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
    if s:find('\232\237\226\229\237\242\224\240\252',1,true) or s:find('\200\237\226\229\237\242\224\240\252',1,true) then return 'inventory' end
    if s:find('\225\224\227\224\230\237\232\234',1,true) or s:find('\193\224\227\224\230\237\232\234',1,true) then return 'trunk' end
    if s:find('\248\234\224\244',1,true) or s:find('\216\234\224\244',1,true) then return 'cabinet' end
    if s:find('\241\234\235\224\228',1,true) or s:find('\209\234\235\224\228',1,true) or s:find('\245\240\224\237\232\235\232\249\229',1,true) or s:find('\213\240\224\237\232\235\232\249\229',1,true) then return 'warehouse' end
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
    name,qty=s:match('^(.-)%s*%(%s*([%d%., ]+)%s*\248\242%.?%s*%)%s*$')
    if not name then name,qty=s:match('^(.-)%s*%[%s*([%d%., ]+)%s*\248\242%.?%s*%]%s*$') end
    if not name then name,qty=s:match('^(.-)%s*[%-%\151:]%s*([%d%., ]+)%s*\248\242%.?%s*$')end
    if not name then name,qty=s:match('^(.-)%s+[x\245X\213]%s*([%d%., ]+)%s*$')end
    if not name then name,qty=s:match('^(.-)%s*%([x\245X\213]%s*([%d%., ]+)%)%s*$')end
    if not name then
        -- Legitimate unlabeled line: show unknown count, never silently x1.
        if s:find('%$',1,true) or s:find('\194\251\225\229\240\232\242\229',1,true) or s:find('\205\224\231\224\228',1,true)
            or DSP.lower(s):find('\226\236\229\241\242\232\236\238\241\242\252',1,true) or s:match('^[-=]+$')
            or s:find('\206\242\234\240\251\242\252',1,true) or s:find('\199\224\234\240\251\242\252',1,true)
            or s:find('\199\224\225\240\224\242\252',1,true) or s:find('\207\238\235\238\230\232\242\252',1,true) then return nil end
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
        if not ok then S.last_error='\205\229 \243\228\224\235\238\241\252 \241\238\245\240\224\237\232\242\252 \241\237\232\236\238\234: '..tostring(err) end
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
                if n:find('\228\240\238\226',1,true) or n:find('\236\229\242\224\235\235',1,true) or n:find('\234\224\236\229\237\252',1,true)
                    or n:find('\235\229\237',1,true) or n:find('\245\235\238\239',1,true) then return 1 end
                if n:find('\235\224\240\229\246',1,true) or n:find('\234\229\233\241',1,true) then return 2 end
                if n:find('\228\229\242\224\235\252 \242\254\237\232\237\227\224',1,true) then return 3 end
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
        title='\207\238\241\235\229\228\237\232\233 \238\242\234\240\251\242\251\233 \225\224\227\224\230\237\232\234',
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
    -- Small updates cannot be assigned to the current vehicle reliably.
    -- Leave the last complete 180-slot snapshot untouched.
    if #items<=5 and T.snapshot then
        T.status='unverified_delta'
        T.last_error='\215\224\241\242\232\247\237\238\229 \232\231\236\229\237\229\237\232\229 \239\240\238\239\243\249\229\237\238: ID \236\224\248\232\237\251 \237\229\232\231\226\229\241\242\229\237. \206\242\234\240\238\233 \225\224\227\224\230\237\232\234 \231\224\237\238\226\238.'
        return false
    end
    T.status='unknown_partial'
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
    T.status='waiting'
    return true
end

function S.find_snapshot(id)
    if not id then return nil end
    for i,saved in ipairs(S.snapshots or {}) do
        if tostring(saved.id)==tostring(id) then return saved,i end
    end
    return nil
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
            return false,'\210\224\234\238\229 \237\224\231\226\224\237\232\229 \243\230\229 \229\241\242\252. \206\242\234\240\238\233 \229\227\238 \232 \226\251\225\229\240\232 \171\206\225\237\238\226\232\242\252\187.'
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
        return false,'\205\229\242 \239\238\235\237\238\227\238 \237\238\226\238\227\238 \241\234\224\237\224'
    end
    if not target or target.source~='packet220_trunk_named' then
        return false,'\209\238\245\240\224\237\184\237\237\251\233 \225\224\227\224\230\237\232\234 \237\229 \237\224\233\228\229\237'
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
    if T.requested_at and now-T.requested_at>60 then
        T.requested_at=nil
        T.update_target_id=nil
        if T.status=='waiting' or T.status=='receiving' then
            T.status='no_packets'
            T.last_error='No complete trunk snapshot within 60 seconds. Open the trunk normally.'
        end
    end
    return T
end

  end
  module_storage()

  local function module_probe()
-- Opt-in, read-only observer for unknown InventoryScreen containers.
-- Does not send packets, click slots or assume undocumented type => kind mappings.
local S = DSP.storage
local P = {armed=false, status='idle', entries={}, order={}, observed=0, ignored_trunk=0, ignored_stall=0}
DSP.storage_probe = P
local MAX_SECONDS, MAX_SLOTS, MAX_SAMPLES, MAX_BYTES = 60, 180, 8, 100000
local allowed = {inventory=true, cabinet=true, warehouse=true}

local function integer(value, maximum, minimum)
    local n=tonumber(value)
    minimum=minimum or 0
    if n and n==n and n%1==0 and n>=minimum and n<=maximum then return n end
    return nil
end
local function observed_slot(item)
    if type(item)~='table' then return nil end
    local slot=integer(item.slot,MAX_SLOTS-1)
    local id=integer(item.item or item.id,2000000000)
    if not slot or not id then return nil end
    local qty=id==0 and 0 or integer(item.amount or item.count,2000000000)
    local ench=integer(item.enchant or item.ench or 0,100) or 0
    return {slot=slot,id=id,qty=qty,ench=ench}
end
local function decode_candidate(raw)
    if type(raw)~='string' or #raw<2 or #raw>MAX_BYTES then return nil end
    local ok,obj=pcall(decodeJson,raw:gsub('%z+$',''))
    if not ok or type(obj)~='table' or type(obj.items)~='table' then return nil end
    local packet_type=integer(obj.type,255)
    if not packet_type or #obj.items<1 or #obj.items>MAX_SLOTS then return nil end
    local slots,seen={},{}
    for _,item in ipairs(obj.items)do
        local v=observed_slot(item)
        if not v or seen[v.slot] then return nil end
        seen[v.slot]=true
        slots[#slots+1]=v
    end
    -- A declared capacity is diagnostic metadata, not proof of identity.
    local cap=integer(obj.capacity or obj.slotCount or obj.totalSlots,MAX_SLOTS,1)
    return packet_type,slots,cap
end

function P.arm(kind, seconds)
    if not allowed[kind] then return false,'unknown kind' end
    local dur=integer(seconds or 40,MAX_SECONDS,5) or 40
    P.armed=true;P.status='armed';P.kind=kind;P.started=os.time()
    P.until_ts=P.started+dur;P.entries={};P.order={}
    P.observed=0;P.ignored_trunk=0;P.ignored_stall=0;P.last_error=nil
    return true
end
function P.stop()
    if P.armed then P.armed=false;P.status='review';return true end
    return false
end
function P.state()
    if P.armed and os.time()>P.until_ts then P.armed=false;P.status='review' end
    return P
end
function P.on_packet(sub,raw)
    if not P.state().armed then return false end
    local namespace=integer(sub,255)
    if namespace~=0 and namespace~=2 then return false end
    local typ,slots,capacity=decode_candidate(raw)
    if not typ then return false end
    -- type 8 is the independently observed vehicle trunk, never a cupboard.
    if typ==8 then P.ignored_trunk=P.ignored_trunk+1;return false end
    -- The existing trade handler identifies type 1/sub 2 as stall inventory.
    if typ==1 and namespace==2 then P.ignored_stall=P.ignored_stall+1;return false end
    local key=tostring(typ)..'/'..tostring(namespace)
    local row=P.entries[key]
    if not row then
        if #P.order>=MAX_SAMPLES then return false end
        row={type=typ,sub=namespace,slots={},seen={},count=0,packet_count=0,
             capacity=capacity,started=os.time(),last_at=os.time()}
        P.entries[key]=row;P.order[#P.order+1]=row
    end
    -- A fresh batch starting with slot 0 cannot silently merge with an old view.
    if row.seen[0] and slots[1].slot==0 and #slots>=8 then
        row.slots={};row.seen={};row.count=0;row.started=os.time()
    end
    if capacity and row.capacity and row.capacity~=capacity then
        row.slots={};row.seen={};row.count=0;row.started=os.time()
    end
    row.capacity=capacity or row.capacity
    row.packet_count=row.packet_count+1
    row.last_at=os.time()
    for _,v in ipairs(slots) do
        if not row.seen[v.slot] then row.seen[v.slot]=true;row.count=row.count+1 end
        row.slots[v.slot]=v
    end
    P.observed=P.observed+1
    return true
end
function P.preview(index)
    local entry=P.order[tonumber(index) or 0]
    if not entry then return nil,'candidate not found' end
    local rows,occupied,known,missing={},0,0,0
    for i=0,MAX_SLOTS-1 do
        local v=entry.slots[i]
        if v and v.id>0 then
            occupied=occupied+1
            local name=DSP.items and DSP.items.name and DSP.items.name(v.id)
                or ('ID:'..tostring(v.id))
            if type(name)~='string' or name=='' then name='ID:'..tostring(v.id) end
            rows[#rows+1]={slot=i,id=v.id,ench=v.ench,name=name,
                qty=v.qty,quantity_confirmed=v.qty~=nil}
            if v.qty==nil then missing=missing+1 else known=known+v.qty end
        end
    end
    return {entry=entry,rows=rows,occupied=occupied,known=known,unknown_qty=missing,
        complete_unverified=entry.capacity~=nil and entry.count==entry.capacity}
end
function P.save(index)
    if P.state().armed then return false,'stop capture before saving' end
    local view,err=P.preview(index)
    if not view then return false,err end
    if #view.rows==0 then return false,'no occupied items observed' end
    if not allowed[P.kind] then return false,'unknown kind' end
    local titles={inventory='\203\232\247\237\251\233 \232\237\226\229\237\242\224\240\252',cabinet='\216\234\224\244',warehouse='\209\234\235\224\228'}
    local now=os.time()
    local snap={id='probe_'..tostring(now)..'_'..tostring(index),
        kind=P.kind,title=titles[P.kind]..' (\237\224\225\235\254\228\229\237\232\229; \237\229 \239\240\238\226\229\240\229\237\238)',
        source='packet220_probe',identity_verified=false,complete_verified=false,
        observed_at=now,server=DSP.market and DSP.market.state and DSP.market.state.sid,
        packet_type=view.entry.type,packet_sub=view.entry.sub,
        slots_observed=view.entry.count,slots_reported=view.entry.capacity,
        rows=view.rows,count_known=view.known,occupied_slots=view.occupied}
    local previous=S.snapshots
    local previous_saved=DSP.settings and DSP.settings.storage_snapshots
    -- Keep explicitly saved observations (including their chosen names).
    -- They are history, never proof that the same cabinet was opened again.
    local replacement={snap}
    for _,old in ipairs(previous or {})do
        replacement[#replacement+1]=old
        if #replacement>=8 then break end
    end
    S.snapshots=replacement
    if DSP.settings then DSP.settings.storage_snapshots=replacement end
    if DSP.save_settings then
        local ok,saved,save_error=pcall(DSP.save_settings)
        if not ok or not saved then
            S.snapshots=previous
            if DSP.settings then DSP.settings.storage_snapshots=previous_saved end
            return false,tostring(save_error or saved or 'save failed')
        end
    end
    S.sort_cache=setmetatable({},{__mode='k'})
    return true,snap
end

-- Explicit local diagnostics export. Metadata only: no raw JSON, item names,
-- item IDs, account identifiers, chat, tokens or individual item quantities.
function P.export_report()
    if P.state().armed then return false,'stop capture before export' end
    if type(encodeJson)~='function' or type(DSP.dir)~='string' then
        return false,'JSON export unavailable'
    end
    local candidates={}
    for _,e in ipairs(P.order)do
        candidates[#candidates+1]={type=e.type,sub=e.sub,slots_observed=e.count,
            declared_slots=e.capacity,packets=e.packet_count}
    end
    local report={schema=1,source='Palatka AI read-only probe',kind_label=P.kind,
        duration_seconds=math.max(0,(P.until_ts or 0)-(P.started or 0)),
        packets=P.observed,ignored_trunk=P.ignored_trunk,
        ignored_stall=P.ignored_stall,candidates=candidates}
    local ok,body=pcall(encodeJson,report)
    if not ok or type(body)~='string' then return false,'JSON encoding failed' end
    local path=DSP.dir..'/storage_probe_report.json'
    local file,err=io.open(path,'wb')
    if not file then return false,tostring(err or 'cannot open report') end
    local wrote,write_err=file:write(body)
    file:close()
    if not wrote then return false,tostring(write_err or 'write failed') end
    return true,path
end

  end
  module_probe()

  local function module_probe_ui()
-- Contextual controls inside Storage > Scan (native mimgui).
-- The selector lives in 60b_carbon_storage.lua; never capture another kind silently.
local V = DSP.ui21
local P = DSP.storage_probe
local labels={inventory='\200\205\194\197\205\210\192\208\220',cabinet='\216\202\192\212',warehouse='\209\202\203\192\196'}
local function button(label,id,width,active)
    return V.button(label,'probe_'..id,width,active)
end
function V.storage_probe_panel(width,kind)
    width=math.max(190,tonumber(width) or 300)
    local w=math.min(width,315)
    if not P then V.red('\204\238\228\243\235\252 \241\234\224\237\232\240\238\226\224\237\232\255 \237\229 \243\241\242\224\237\238\226\235\229\237.');return end
    kind=labels[kind] and kind or 'inventory'
    local state=P.state()
    V.text(labels[kind]..' \183 \240\229\230\232\236 \237\224\225\235\254\228\229\237\232\255')
    if state.armed and state.kind~=kind then
        V.red('\209\237\224\247\224\235\224 \231\224\226\229\240\248\232 \241\234\224\237 \228\240\243\227\238\227\238 \234\238\237\242\229\233\237\229\240\224.')
        if button('\206\241\242\224\237\238\226\232\242\252 \239\240\229\228\251\228\243\249\232\233 \241\234\224\237','stop_other',w)then P.stop()end
        return
    end
    if state.kind~=kind and not state.armed then
        -- A previous capture must never be presented as the current container.
        V.muted('\221\242\238 \238\242\228\229\235\252\237\251\233 \241\234\224\237. \205\224\230\236\232 \171\205\224\247\224\242\252\187, \231\224\242\229\236 \238\242\234\240\238\233 \226\251\225\240\224\237\237\251\233 \234\238\237\242\229\233\237\229\240.')
        if button('\205\224\247\224\242\252 \241\234\224\237: '..labels[kind],'arm_'..kind,w,true)then
            P.arm(kind,40);V.probe_selected=1;V.probe_error=nil;V.probe_report_path=nil
        end
        return
    end
    if state.armed then
        V.green('\192\234\242\232\226\229\237 \183 \238\241\242\224\235\238\241\252 '..math.max(0,state.until_ts-os.time())..' \241\229\234.')
        V.muted('\199\224\234\240\238\233 Palatka AI \232 \238\242\234\240\238\233 '..(kind=='inventory' and '\235\232\247\237\251\233 \232\237\226\229\237\242\224\240\252' or kind=='cabinet' and '\248\234\224\244' or '\241\234\235\224\228')..' \226 \232\227\240\229.')
        if button('\199\224\226\229\240\248\232\242\252 \232 \239\238\234\224\231\224\242\252 \237\224\233\228\229\237\237\238\229','stop',w,true)then P.stop()end
    else
        V.muted('\209\234\224\237 \231\224\226\229\240\248\184\237. \196\224\237\237\251\229 \237\232\230\229 \239\240\229\228\226\224\240\232\242\229\235\252\237\251\229.')
        if button('\207\238\226\242\238\240\232\242\252 \241\234\224\237','arm_'..kind,w)then
            P.arm(kind,40);V.probe_selected=1;V.probe_error=nil;V.probe_report_path=nil
            return
        end
    end
    V.muted('\207\224\234\229\242\251: '..tostring(state.observed or 0)..' \183 \234\224\237\228\232\228\224\242\251: '..#state.order)
    V.muted('\207\240\238\239\243\249\229\237\238: \225\224\227\224\230\237\232\234 '..tostring(state.ignored_trunk or 0)..
        ', \235\224\226\234\224 '..tostring(state.ignored_stall or 0))
    if not state.armed and state.status=='review' then
        if button('\209\238\245\240\224\237\232\242\252 \242\229\245\237\232\247\229\241\234\232\233 \238\242\247\184\242','export',w)then
            local ok,path=P.export_report()
            if ok then V.probe_report_path=path;V.probe_error=nil
            else V.probe_error=tostring(path)end
        end
        if V.probe_report_path then V.muted(V.fit(V.probe_report_path,width))end
    end
    if #state.order==0 then
        if not state.armed then
            V.red('\207\238\228\245\238\228\255\249\232\245 \239\224\234\229\242\238\226 \237\229\242. \200\237\226\229\237\242\224\240\252 \236\238\227 \239\240\232\233\242\232 \228\240\243\227\232\236 \244\238\240\236\224\242\238\236.')
        end
        if V.probe_error then V.red(V.fit(V.probe_error,width))end
        return
    end
    V.probe_selected=math.max(1,math.min(#state.order,V.probe_selected or 1))
    local selected=V.probe_selected
    if button('\202\224\237\228\232\228\224\242 '..selected..' / '..#state.order..' >','next',w)then
        selected=selected%#state.order+1;V.probe_selected=selected
    end
    local info,err=P.preview(selected)
    if not info then V.red(tostring(err));return end
    local e=info.entry
    V.text('type='..e.type..', sub='..e.sub..' \183 \241\235\238\242\238\226 \239\238\235\243\247\229\237\238 '..e.count)
    V.muted('\206\225\237\224\240\243\230\229\237\238 \241\235\238\242\238\226: '..e.count..
        (e.capacity and (' / '..e.capacity) or ' / \239\238\235\237\224\255 \184\236\234\238\241\242\252 \237\229\232\231\226\229\241\242\237\224'))
    V.muted('\205\224\233\228\229\237\238 \239\240\229\228\236\229\242\237\251\245 \241\235\238\242\238\226: '..info.occupied)
    V.muted('\207\238\228\242\226\229\240\230\228\229\237\238 \229\228\232\237\232\246: '..info.known..' \183 \225\229\231 \247\232\241\235\224: '..info.unknown_qty)
    if DSP.storage and DSP.storage.evaluate then
        local estimate=DSP.storage.evaluate({kind=kind,rows=info.rows,
            server=DSP.market and DSP.market.state and DSP.market.state.sid})
        if not estimate.cross_server then
            V.green('\206\246\229\237\234\224 \241\234\243\239\234\232 \237\224\233\228\229\237\237\238\227\238: '..DSP.money(estimate.sell_to_buyers))
            V.muted('\207\238 \238\225\250\255\226\235\229\237\232\255\236: '..DSP.money(estimate.ask_value)..' (\237\229 \247\232\241\242\224\255 \239\240\232\225\251\235\252)')
            if estimate.missing_prices>0 then
                V.muted('\205\229\242 \246\229\237 \228\235\255 '..estimate.missing_prices..' \241\242\240\238\234')
            end
        end
    end
    for i=1,math.min(4,#info.rows)do
        local it=info.rows[i]
        V.muted(V.fit(it.name..' \183 '..(it.qty and tostring(it.qty)..' \248\242.' or '\234\238\235\232\247\229\241\242\226\238 \237\229\232\231\226\229\241\242\237\238'),width))
    end
    if #info.rows>4 then V.muted('\206\241\242\224\235\252\237\251\229 \239\240\229\228\236\229\242\251 \239\238\255\226\255\242\241\255 \226 \241\239\232\241\234\229 \241\237\232\236\234\224.')end
    if not state.armed then
        if button('\209\238\245\240\224\237\232\242\252 \234\224\234 \237\229\239\240\238\226\229\240\229\237\237\251\233 \241\237\232\236\238\234','save',w,true)then
            local ok,saved=P.save(selected)
            if ok then
                V.probe_error=nil;V.storage_tab='snapshots';V.storage_selected=1
                -- Use the existing native rename dialog on the following frame.
                V.storage_ask_name=true
            else V.probe_error=tostring(saved)end
        end
    end
    V.red(V.fit('\221\242\238 \237\229 \239\238\235\237\251\233 \241\234\224\237: \242\232\239 \234\238\237\242\229\233\237\229\240\224 \226\251\225\240\224\237 \226\240\243\247\237\243\254, ID \226\235\224\228\229\235\252\246\224 \237\229\232\231\226\229\241\242\229\237.',width))
    if V.probe_error then V.red(V.fit(V.probe_error,width))end
end

  end
  module_probe_ui()

  local function install_beta_rollback()
    local U=DSP.updater
    local stable=[==[
-- Palatka AI v2.7.0: restore the native v2.5.2 mimgui interface.
-- This rollback release intentionally contains no WebUI hooks or browser UI.
-- The update manager reloads the base Lua after installing this overlay.
PALATKA_UPDATE_VERSION = '2.7.0'

return function(DSP)
    -- Best effort: clean up a WebView retained by the previous overlay.
    local W = DSP.webui
    if W and type(W.hide) == 'function' then pcall(W.hide) end
    local ok, web = pcall(require, 'webviews')
    if ok and web then
        local id = 95253
        if type(web.setClickable) == 'function' then pcall(web.setClickable, id, false) end
        if type(web.setVisible) == 'function' then pcall(web.setVisible, id, false) end
        if type(web.setPos) == 'function' then pcall(web.setPos, id, -99999, -99999) end
        if type(web.setSize) == 'function' then pcall(web.setSize, id, 1, 1) end
    end
    -- Leave presets, settings, market cache, saved storages and trading runtime untouched.
    DSP.version = '2.7.0'
    if DSP.flog then pcall(DSP.flog, 'Rollback to native mimgui UI (v2.5.2 base)') end
    return true
end

]==]
    local function restore()
      if not U or type(U.update_path)~='string' then return false,'Updater path unavailable' end
      local dest=U.update_path
      local temp=dest..'.crr_tmp'
      local backup=dest..'.crr_beta_backup'
      local f,err=io.open(temp,'wb')
      if not f then return false,tostring(err or 'cannot create rollback file') end
      local wrote,write_err=f:write(stable)
      local closed,close_err=f:close()
      if not wrote or not closed then
        pcall(os.remove,temp)
        return false,tostring(write_err or close_err or 'rollback write failed')
      end
      pcall(os.remove,backup)
      local kept,keep_err=os.rename(dest,backup)
      if not kept then pcall(os.remove,temp);return false,'backup failed: '..tostring(keep_err) end
      local placed,move_err=os.rename(temp,dest)
      if not placed then
        pcall(os.rename,backup,dest)
        pcall(os.remove,temp)
        return false,'restore failed: '..tostring(move_err)
      end
      if U.state then U.state.status='rolled_back';U.state.error=nil end
      if DSP.notify then pcall(DSP.notify,'CRR: stable 2.7.0 restored') end
      if lua_thread and lua_thread.create and wait and thisScript then
        lua_thread.create(function()
          wait(650)
          local sc=thisScript()
          if sc and sc.reload then sc:reload() end
        end)
      end
      return true
    end
    DSP.storage_beta_rollback=restore
    if U then U.rollback=restore end
  end
  install_beta_rollback()

  local function module_storage_ui()
-- Safe container analyzer; cannot read bespoke game UIs without a packet parser.
local ffi=require('ffi')
local V,S,M=DSP.ui21,DSP.storage,DSP.mobile
V.storage_sort='value'
V.storage_selected=1
local function b(s,id,w,on,primary)return V.button(s,'storage_'..id,w,on,primary)end
-- One task per panel: scanner, snapshots, manual fallback. This avoids the
-- previous giant fixed header which pushed the item list off small screens.
function V.storage_screen()
    V.heading('\213\240\224\237\232\235\232\249\224',function()
        if DSP.storage_beta_rollback then
            if b('CRR \206\210\202\192\210','beta_rollback',145,false,true) then
                V.open_popup('CRR \238\242\234\224\242','storage_beta_rollback')
            end
        elseif b('\209\234\224\237\229\240','quick_scan',105) then
            V.storage_tab='scan'
            V.reset_list('storage_scan_panel')
        end
    end,DSP.storage_beta_rollback and 149 or 109)
    local capstate,capcount,caperr=S.textdraw_state()
    V.storage_tab=V.storage_tab or 'scan'
    V.storage_scan_mode=V.storage_scan_mode or 'trunk'
    local w=imgui.GetContentRegionAvail().x
    local compact_tabs=w<270
    local tabw=compact_tabs and math.max(100,w) or math.max(78,(w-12)/3)
    for i,tab in ipairs({{'scan','\209\234\224\237'}, {'snapshots','\209\237\232\236\234\232'}, {'manual','\194\226\238\228'}})do
        if b(tab[2],'tab_'..tab[1],tabw,V.storage_tab==tab[1],V.storage_tab==tab[1])then
            V.storage_tab=tab[1];V.reset_list('storage_scan_panel')
        end
        if i<3 and not compact_tabs then V.inline(5)end
    end
    imgui.Separator()
    if V.storage_tab=='scan' then
        V.list('storage_scan_panel',function(width)
            local options={{'trunk','\193\224\227\224\230\237\232\234'},{'inventory','\200\237\226\229\237\242\224\240\252'},
                           {'cabinet','\216\234\224\244'},{'warehouse','\209\234\235\224\228'}}
            V.text('\215\242\238 \237\243\230\237\238 \239\240\238\226\229\240\232\242\252?')
            local stack_buttons=width<230
            local bw=stack_buttons and width or math.max(92,math.floor((width-12)/2))
            for i,item in ipairs(options)do
                if b(item[2],'choose_'..item[1],bw,V.storage_scan_mode==item[1],V.storage_scan_mode==item[1])then
                    V.storage_scan_mode=item[1]
                    V.probe_error=nil
                    V.reset_list('storage_scan_panel')
                end
                if i%2==1 and not stack_buttons then V.inline(6)end
            end
            imgui.Separator()
            if V.storage_scan_mode=='trunk' then
                local t=(S.trunk_state and S.trunk_state()) or S.trunk or {}
                local statuses={idle='\206\230\232\228\224\229\242 \238\242\234\240\251\242\232\255',receiving='\207\238\235\243\247\229\237\232\229 \228\224\237\237\251\245',
                    saved='\207\238\241\235\229\228\237\232\233 \225\224\227\224\230\237\232\234 \241\238\245\240\224\237\184\237',saved_from_disk='\197\241\242\252 \241\242\224\240\251\233 \241\237\232\236\238\234',
                    incomplete='\205\229\228\238\241\242\224\242\238\247\237\238 \241\235\238\242\238\226',unknown_partial='\207\238\235\243\247\229\237\224 \235\232\248\252 \247\224\241\242\252',
                    unverified_delta='\205\229\239\240\238\226\229\240\229\237\237\238\229 \232\231\236\229\237\229\237\232\229',save_error='\206\248\232\225\234\224 \241\238\245\240\224\237\229\237\232\255',
                    no_packets='\207\238\235\237\251\233 \241\237\232\236\238\234 \237\229 \239\238\235\243\247\229\237'}
                V.text('\193\192\195\192\198\205\200\202 \183 \241\234\224\237\232\240\238\226\224\237\232\229')
                if b((t.autoscan_enabled and '\192\226\242\238\241\234\224\237: \194\202\203' or '\192\226\242\238\241\234\224\237: \194\219\202\203'),
                     'toggle_trunk_auto',math.min(width,250),t.autoscan_enabled,t.autoscan_enabled) then
                    local ok,err=S.set_trunk_autoscan(not t.autoscan_enabled)
                    if not ok then V.storage_error=tostring(err) else V.storage_error=nil end
                end
                if b('\199\192\207\211\209\210\200\210\220 \209\202\192\205 \193\192\195\192\198\205\200\202\192','start_trunk',math.min(width,330),false,true)then
                    S.begin_trunk_scan()
                    V.storage_error=nil
                end
                V.muted('1. \199\224\239\243\241\242\232 \241\234\224\237, \231\224\242\229\236 \231\224\234\240\238\233 \238\234\237\238 Palatka AI.')
                V.muted('2. \206\242\234\240\238\233 \225\224\227\224\230\237\232\234 \226 \232\227\240\229 \232 \226\229\240\237\232\241\252 \226 \253\242\238 \236\229\237\254.')
                V.muted('\192\226\242\238\241\234\224\237 \236\238\230\229\242 \241\238\245\240\224\237\255\242\252 \239\238\235\237\251\229 \241\237\232\236\234\232 \225\229\231 \234\237\238\239\234\232 \231\224\239\243\241\234\224.')
                V.text('\209\242\224\242\243\241: '..(statuses[t.status] or (t.status=='waiting' and '\206\230\232\228\224\254 \238\242\234\240\251\242\232\255 \225\224\227\224\230\237\232\234\224') or
                    t.status=='disabled' and '\192\226\242\238\241\234\224\237 \226\251\234\235\254\247\229\237' or tostring(t.status or '\238\230\232\228\224\237\232\229')))
                V.muted('\207\224\234\229\242\251 type 8: '..tostring(t.raw_packet_events or 0)..
                    ' \183 \240\224\231\238\225\240\224\237\238: '..tostring(t.packet_events or 0))
                if (t.invalid_packet_events or 0)>0 then
                    V.red('\206\248\232\225\234\232 \244\238\240\236\224\242\224 \239\224\234\229\242\238\226: '..tostring(t.invalid_packet_events))
                end
                V.muted('\209\235\238\242\238\226: '..tostring(t.received or 0)..' / 180')
                if t.last_packet_at then
                    V.muted('\207\238\241\235\229\228\237\232\233 \239\224\234\229\242: '..os.date('%H:%M:%S',t.last_packet_at))
                else
                    V.muted('\207\238\234\224 \237\229 \238\225\237\224\240\243\230\229\237\238 \239\224\234\229\242\238\226 \225\224\227\224\230\237\232\234\224 \226 \253\242\238\233 \241\229\241\241\232\232.')
                end
                if t.occupied then
                    V.text('\199\224\237\255\242\251\245 \241\235\238\242\238\226: '..tostring(t.occupied)..' \183 \239\240\229\228\236\229\242\238\226: '..tostring(t.total or 0))
                end
                if t.last_error then V.red(V.fit(tostring(t.last_error),width))end
                if V.storage_error then V.red(V.fit(V.storage_error,width))end
                if t.snapshot then
                    if t.status=='saved' then
                        V.green('\209\202\192\205 \199\192\194\197\208\216\168\205: 180 / 180 \209\203\206\210\206\194')
                    elseif t.requested_at then
                        V.red('\205\238\226\251\233 \241\234\224\237 \229\249\184 \237\229 \231\224\226\229\240\248\184\237. \205\232\230\229 \239\240\229\228\251\228\243\249\232\233 \241\237\232\236\238\234.')
                    end
                    V.muted('\194\240\229\236\255 \241\237\232\236\234\224: '..os.date('%d.%m %H:%M:%S',t.snapshot.observed_at))
                    V.text('\207\238\241\235\229\228\237\232\233 \225\224\227\224\230\237\232\234: '..tostring(t.snapshot.occupied_slots or 0)..' \231\224\237\255\242\251\245 \241\235\238\242\238\226')
                    V.text('\194\241\229\227\238 \229\228\232\237\232\246 \239\240\229\228\236\229\242\238\226: '..tostring(t.snapshot.count_known or 0))
                    local sig=tostring(t.last_saved_at or t.snapshot.observed_at)..'/'..
                        tostring(t.packet_events or 0)..'/'..
                        tostring(DSP.market and DSP.market.state and DSP.market.state.version or '')
                    local info=V.memo('storage_trunk_summary',sig,function()return S.evaluate(t.snapshot)end)
                    if info.cross_server then
                        V.red('\209\237\232\236\238\234 \228\240\243\227\238\227\238 \241\229\240\226\229\240\224: \240\251\237\238\247\237\224\255 \238\246\229\237\234\224 \237\229 \224\234\242\243\224\235\252\237\224.')
                    else
                        V.green('\207\238 \246\229\237\224\236 \241\234\243\239\234\232: '..DSP.money(info.sell_to_buyers))
                        V.muted('\207\238 \238\225\250\255\226\235\229\237\232\255\236: '..DSP.money(info.ask_value)..' (\237\229 \228\238\245\238\228 \232 \237\229 \239\240\232\225\251\235\252)')
                        if info.missing_prices>0 then
                            V.muted('\205\229\242 \246\229\237 \228\235\255 '..info.missing_prices..' \241\242\240\238\234.')
                        end
                    end
                    local update_target=t.completed_update_target_id and S.find_snapshot(t.completed_update_target_id)
                    if update_target then
                        V.green('\195\206\210\206\194\206 \196\203\223 \206\193\205\206\194\203\197\205\200\223: '..tostring(update_target.title))
                        V.muted('\205\238\226\251\233 \241\234\224\237 \229\249\184 \205\197 \231\224\239\232\241\224\237 \239\238\226\229\240\245 \241\238\245\240\224\237\184\237\237\238\227\238 \245\240\224\237\232\235\232\249\224.')
                        if b('\207\208\200\204\197\205\200\210\220 \202 '..tostring(update_target.title),'apply_update',math.min(width,330),false,true)then
                            local ok,updated=S.apply_latest_to_saved(update_target.id)
                            if ok then
                                local _,idx=S.find_snapshot(updated.id)
                                V.storage_selected=idx or 1
                                V.storage_library_page='detail'
                                V.storage_tab='snapshots'
                                V.storage_error=nil
                                return
                            else
                                V.storage_error=tostring(updated)
                            end
                        end
                        if b('\209\206\213\208\192\205\200\210\220 \202\192\202 \205\206\194\206\197','save_update_as_new',math.min(width,300))then
                            V.storage_name_target=t.snapshot
                            V.storage_name_buf=imgui.new.char[128]()
                            V.storage_name_error=nil
                            V.open_popup('\209\238\245\240\224\237\232\242\252 \225\224\227\224\230\237\232\234','storage_trunk_name')
                        end
                    else
                        if b('\209\206\213\208\192\205\200\210\220 \202\192\202 \205\206\194\206\197','name_trunk',math.min(width,300),false,true)then
                            V.storage_name_target=t.snapshot
                            V.storage_name_buf=imgui.new.char[128]()
                            V.storage_name_error=nil
                            V.open_popup('\209\238\245\240\224\237\232\242\252 \225\224\227\224\230\237\232\234','storage_trunk_name')
                        end
                    end
                    V.muted('\205\224\231\226\224\237\232\229 \231\224\234\240\229\239\235\255\229\242\241\255 \231\224 \241\238\245\240\224\237\184\237\237\238\233 \231\224\239\232\241\252\254, \237\229 \231\224 \239\238\241\235\229\228\237\232\236 \241\234\224\237\238\236.')
                    if b('\206\242\234\240\251\242\252 \239\238\241\235\229\228\237\232\233 \241\234\224\237','view_trunk',math.min(width,280))then
                        V.storage_tab='snapshots'
                        V.storage_library_page='detail'
                        for i,snap in ipairs(S.snapshots or {})do
                            if snap==t.snapshot or (snap.source=='packet220_trunk' and snap.kind=='trunk') then
                                V.storage_selected=i;break
                            end
                        end
                    end
                end
                V.muted('\207\238\241\224\228\234\224 \226 \224\226\242\238\236\238\225\232\235\252 \237\229 \238\231\237\224\247\224\229\242 \238\242\234\240\251\242\232\229 \225\224\227\224\230\237\232\234\224.')
            elseif V.storage_probe_panel then
                V.storage_probe_panel(width,V.storage_scan_mode)
            else
                V.red('\196\232\224\227\237\238\241\242\232\234\224 \253\242\238\227\238 \234\238\237\242\229\233\237\229\240\224 \237\229\228\238\241\242\243\239\237\224 \226 \228\224\237\237\238\233 \241\225\238\240\234\229.')
            end
            if b('\204\206\200 \213\208\192\205\200\203\200\217\192','show_snapshots',math.min(width,260),false,true)then
                V.storage_tab='snapshots';V.storage_library_page='list'
            end
            if b('\194\226\229\241\242\232 \241\239\232\241\238\234 \226\240\243\247\237\243\254','manual_open',math.min(width,250))then
                V.storage_tab='manual'
                V.storage_manual_kind=V.storage_scan_mode
            end
        end,{footer=function()
            V.muted('\202\237\238\239\234\232 \237\232\230\229: \235\232\241\242\224\242\252 \241\239\232\241\238\234. \205\232\234\224\234\232\245 \232\227\240\238\226\251\245 \234\235\232\234\238\226 \241\234\224\237\229\240 \237\229 \238\242\239\240\224\226\235\255\229\242.')
        end})
        return
    end
    if V.storage_tab=='manual' then
        V.list('storage_manual_panel',function(width)
            V.muted('\197\241\235\232 \232\227\240\238\226\238\233 \232\237\242\229\240\244\229\233\241 \237\229 \226\251\228\224\184\242 \241\238\228\229\240\230\232\236\238\229 \247\229\240\229\231 \241\238\225\251\242\232\255,')
            V.muted('\236\238\230\237\238 \226\241\242\224\226\232\242\252 \241\239\232\241\238\234 \226\240\243\247\237\243\254 \151 \253\242\238 \237\229 \232\227\240\238\226\238\233 \241\234\224\237.')
            V.storage_manual_kind=V.storage_manual_kind or 'trunk'
            local stack_buttons=width<230
            local bw=stack_buttons and width or math.max(90,math.floor((width-12)/2))
            for i,t in ipairs({{'trunk','\193\224\227\224\230\237\232\234'},{'inventory','\200\237\226\229\237\242\224\240\252'},
                               {'cabinet','\216\234\224\244'},{'warehouse','\209\234\235\224\228'}})do
                if b(t[2],'manual_'..t[1],bw,V.storage_manual_kind==t[1],V.storage_manual_kind==t[1])then V.storage_manual_kind=t[1]end
                if i%2==1 and not stack_buttons then V.inline(6)end
            end
            V.storage_input=V.storage_input or imgui.new.char[8192]()
            V.muted('\212\238\240\236\224\242: \196\240\238\226\224 x45000  \232\235\232  \196\240\238\226\224 (45000 \248\242.)')
            imgui.InputTextMultiline('##storage_text',V.storage_input,8192,imgui.ImVec2(-1,100))
            if b('\209\238\245\240\224\237\232\242\252 \241\237\232\236\238\234','manual_accept',math.min(width,220),false,true)then
                local kind=V.storage_manual_kind
                local title=kind=='trunk'and'\193\224\227\224\230\237\232\234 (\240\243\247\237\238\233 \241\239\232\241\238\234)' or kind=='inventory'and'\200\237\226\229\237\242\224\240\252 (\240\243\247\237\238\233 \241\239\232\241\238\234)'
                    or kind=='cabinet'and'\216\234\224\244 (\240\243\247\237\238\233 \241\239\232\241\238\234)' or '\209\234\235\224\228 (\240\243\247\237\238\233 \241\239\232\241\238\234)'
                local ok,err=S.accept(kind,title,DSP.to_cp(ffi.string(V.storage_input)),nil,'manual')
                if ok then V.storage_tab='snapshots';V.storage_selected=1;V.storage_error=nil
                else V.storage_error=err end
            end
            if V.storage_error then V.red(tostring(V.storage_error))end
        end,{footer=false})
        return
    end
    local snapshots=S.snapshots
    V.storage_library_page=V.storage_library_page or 'list'
    local library=S.library and S.library() or {}
    local live=nil
    local live_index=nil
    for i,snap in ipairs(snapshots)do
        if snap.source=='packet220_trunk' then live=snap;live_index=i;break end
    end
    if V.storage_library_page=='list' then
        if b('+ \209\202\192\205\200\208\206\194\192\210\220 \205\206\194\206\197','library_new_scan',math.min(290,imgui.GetContentRegionAvail().x),false,true)then
            V.storage_tab='scan'
            V.storage_scan_mode='trunk'
            S.begin_trunk_scan()
            V.reset_list('storage_scan_panel')
            return
        end
        V.apply_font((V.font_pixels or 18)*1.24)
        V.text('\204\206\200 \213\208\192\205\200\203\200\217\192')
        V.apply_font()
        V.muted('\207\238\241\235\229\228\237\232\233 \241\234\224\237 \238\242\228\229\235\252\237\238. \209\238\245\240\224\237\184\237\237\251\229 \237\224\231\226\224\237\232\255 \237\229 \239\229\240\229\231\224\239\232\241\251\226\224\254\242\241\255.')
        if live then
            local info=S.evaluate(live)
            V.text('\207\206\209\203\197\196\205\200\201 \209\202\192\205 \183 \205\197 \209\206\213\208\192\205\168\205')
            V.muted(os.date('%d.%m %H:%M',live.observed_at)..' \183 '..tostring(live.occupied_slots or 0)..' \231\224\237\255\242\251\245 \241\235\238\242\238\226')
            V.green('\206\246\229\237\234\224 \241\234\243\239\234\232: '..DSP.money(info.sell_to_buyers))
            if b('\206\242\234\240\251\242\252 \239\238\241\235\229\228\237\232\233 \241\234\224\237','library_live',math.min(300,imgui.GetContentRegionAvail().x),false,true)then
                V.storage_selected=live_index
                V.storage_library_page='detail'
                V.reset_list('storage_items')
                return
            end
            imgui.Separator()
        end
        if #library==0 then
            V.muted('\209\238\245\240\224\237\184\237\237\251\245 \245\240\224\237\232\235\232\249 \239\238\234\224 \237\229\242.')
            V.muted('\207\238\241\235\229 \239\238\235\237\238\227\238 \241\234\224\237\224 \226\251\225\229\240\232 \171\209\238\245\240\224\237\232\242\252 \234\224\234 \237\238\226\238\229\187 \232 \231\224\228\224\233 \232\236\255.')
        else
            V.list_rows('storage_library',library,76,function(entry,i,w)
                local snap=entry.snapshot
                local kind=snap.kind=='trunk'and'\193\224\227\224\230\237\232\234' or snap.kind=='cabinet'and'\216\234\224\244'
                    or snap.kind=='warehouse'and'\209\234\235\224\228' or snap.kind=='inventory'and'\200\237\226\229\237\242\224\240\252' or'\213\240\224\237\232\235\232\249\229'
                V.row('storage_library_'..i,76,function(rw,x,y)
                    V.at(x,y)
                    V.apply_font((V.font_pixels or 18)*1.12)
                    if V.text_button(V.fit(tostring(snap.title or kind),rw),'storage_library_open_'..i,rw,false,34)then
                        V.storage_selected=entry.index
                        V.storage_library_page='detail'
                        V.reset_list('storage_items')
                    end
                    V.apply_font()
                    V.at(x,y+39)
                    V.muted(V.fit(kind..' \183 '..os.date('%d.%m %H:%M',snap.observed_at or os.time())..
                        ' \183 '..tostring(snap.count_known or 0)..' \248\242.',rw))
                end)
            end,{count=#library,footer=function()
                V.muted('\209\238\245\240\224\237\229\237\238: '..#library..' / '..tostring(S.max_saved or 20))
            end})
        end
        if b('\211\228\224\235\232\242\252 \226\241\229 \241\238\245\240\224\237\184\237\237\251\229','clear_snapshots',math.min(250,imgui.GetContentRegionAvail().x))then
            V.open_popup('\206\247\232\241\242\232\242\252 \241\237\232\236\234\232?','storage_clear')
        end
        return
    end

    if #snapshots==0 then V.storage_library_page='list';return end
    V.storage_selected=math.max(1,math.min(#snapshots,V.storage_selected or 1))
    local current=snapshots[V.storage_selected]
    if not current then V.storage_library_page='list';return end
    if b('< \204\206\200 \213\208\192\205\200\203\200\217\192','library_back',math.min(230,imgui.GetContentRegionAvail().x))then
        V.storage_library_page='list'
        return
    end
    V.apply_font((V.font_pixels or 18)*1.32)
    V.text(V.fit(tostring(current.title or '\193\229\231 \237\224\231\226\224\237\232\255'),imgui.GetContentRegionAvail().x))
    V.apply_font()
    local is_live=current.source=='packet220_trunk'
    local is_named_trunk=current.source=='packet220_trunk_named'
    if is_live then
        V.green('\207\206\209\203\197\196\205\200\201 \209\202\192\205 \183 \205\197 \209\206\213\208\192\205\168\205')
    else
        V.muted('\209\206\213\208\192\205\168\205\205\206\197 \213\208\192\205\200\203\200\217\197')
    end
    V.muted(os.date('%d.%m.%Y %H:%M',current.observed_at or os.time()))
    if is_live then
        if b('\209\206\213\208\192\205\200\210\220 \202\192\202 \205\206\194\206\197','library_save_live',math.min(300,imgui.GetContentRegionAvail().x),false,true)then
            V.storage_name_target=current
            V.storage_name_buf=imgui.new.char[128]()
            V.storage_name_error=nil
            V.open_popup('\209\238\245\240\224\237\232\242\252 \225\224\227\224\230\237\232\234','storage_trunk_name')
        end
    elseif is_named_trunk then
        if b('\206\193\205\206\194\200\210\220 \221\210\206\210 \193\192\195\192\198\205\200\202','library_update_named',math.min(310,imgui.GetContentRegionAvail().x),false,true)then
            S.begin_trunk_scan(current.id)
            V.storage_tab='scan'
            V.storage_scan_mode='trunk'
            V.reset_list('storage_scan_panel')
            return
        end
        if b('\207\229\240\229\232\236\229\237\238\226\224\242\252','rename',math.min(180,imgui.GetContentRegionAvail().x))then
            V.storage_label_target=current
            V.storage_label_buf=imgui.new.char[128]()
            ffi.copy(V.storage_label_buf,DSP.utf8(tostring(current.title or '')):sub(1,120))
            V.storage_label_error=nil
            V.open_popup('\205\224\231\226\224\237\232\229 \241\237\232\236\234\224','storage_rename')
        end
    else
        if b('\207\229\240\229\232\236\229\237\238\226\224\242\252','rename',math.min(180,imgui.GetContentRegionAvail().x))then
            V.storage_label_target=current
            V.storage_label_buf=imgui.new.char[128]()
            ffi.copy(V.storage_label_buf,DSP.utf8(tostring(current.title or '')):sub(1,120))
            V.storage_label_error=nil
            V.open_popup('\205\224\231\226\224\237\232\229 \241\237\232\236\234\224','storage_rename')
        end
    end

    local controlw=math.max(110,(imgui.GetContentRegionAvail().x-8)/2)
    if b(V.storage_sort=='value'and'\209\238\240\242\232\240\238\226\234\224: \238\246\229\237\234\224'or V.storage_sort=='qty'and'\209\238\240\242\232\240\238\226\234\224: \234\238\235\232\247\229\241\242\226\238'
        or V.storage_sort=='price'and'\209\238\240\242\232\240\238\226\234\224: \246\229\237\224'or V.storage_sort=='category'and'\209\238\240\242\232\240\238\226\234\224: \234\224\242\229\227\238\240\232\232' or '\209\238\240\242\232\240\238\226\234\224: \192\150\223',
        'sort',math.min(controlw*2+8,imgui.GetContentRegionAvail().x))then
        V.storage_sort=V.storage_sort=='value'and'qty'or V.storage_sort=='qty'and'price'
            or V.storage_sort=='price'and'category'or V.storage_sort=='category'and'name'or'value'
        V.reset_list('storage_items')
    end
    local rows,info=S.sorted(current,V.storage_sort)
    V.text('\207\238\228\242\226\229\240\230\228\229\237\238: '..info.total_qty..' \248\242. \183 \237\229\232\231\226\229\241\242\237\238: '..info.unknown_qty..' \241\242\240\238\234')
    if current.kind=='trunk' then
        V.muted(tostring(current.slots_count or 180)..' \241\235\238\242\238\226 \183 '..tostring(current.occupied_slots or #current.rows)..' \231\224\237\255\242\238')
    end
    if current.source=='packet220_probe' then
        V.red('\205\197\207\206\203\205\219\201 \209\205\200\204\206\202: \242\232\239 \234\238\237\242\229\233\237\229\240\224 \239\238\234\224 \237\229 \239\238\228\242\226\229\240\230\228\184\237.')
    end
    V.green('\206\246\229\237\234\224 \241\234\243\239\234\232: '..DSP.money(info.sell_to_buyers))
    V.muted('\207\238 \238\225\250\255\226\235\229\237\232\255\236: '..DSP.money(info.ask_value)..' \183 \253\242\238 \237\229 \247\232\241\242\224\255 \239\240\232\225\251\235\252')
    if info.cross_server then V.red('\196\240\243\227\238\233 \241\229\240\226\229\240: \246\229\237\251 \241\234\240\251\242\251')end
    V.list_rows('storage_items',rows,94,function(it,i)
        V.row('storage_item_'..i,94,function(ww,x,y)
            local textwidth=math.max(80,ww-118)
            V.at(x,y);V.text(V.fit(it.name,textwidth))
            V.at(x,y+27);V.muted(V.fit('\202\238\235\232\247\229\241\242\226\238: '..(it.qty and tostring(it.qty)..' \248\242.'or'\237\229\232\231\226\229\241\242\237\238')..' / '..tostring(it.slots or 1)..' \241\235\238\242\238\226',textwidth))
            V.at(x,y+56)
            local total=(it.bid and it.qty)and DSP.money(it.bid*it.qty)or'\237\229\242 \238\246\229\237\234\232'
            V.muted(V.fit((it.manual_price and '\209\226\238\255 \246\229\237\224: ' or '\209\234\243\239\224\254\242: ')..(it.bid and DSP.money(it.bid)or'?')..' / \248\242. \183 '..total,textwidth))
            V.at(x+math.max(0,ww-107),y+16)
            if b('\209\226\238\255 \246\229\237\224','edit_price_'..i,106,it.manual_price)then
                V.storage_price_target=current
                V.storage_price_row=it
                V.storage_price_buf={value=it.manual_price and it.bid or 0}
                V.storage_price_error=nil
                V.open_popup('\209\226\238\255 \246\229\237\224','storage_price')
            end
        end)
    end,{footer=function()V.muted('\209\234\224\237 \237\229 \239\229\240\229\236\229\249\224\229\242 \239\240\229\228\236\229\242\251 \226 \232\227\240\229.')end})
end

-- Deletion is a real modal confirmation; cancellation never changes snapshots.
local old_popups=V.popups
function V.popups()
    if old_popups then old_popups()end
    V.popup('CRR \238\242\234\224\242','storage_beta_rollback',function()
        V.text('\194\229\240\237\243\242\252 \241\242\224\225\232\235\252\237\243\254 Palatka AI \241 \238\225\251\247\237\251\236 \232\237\242\229\240\244\229\233\241\238\236?')
        V.muted('\210\229\241\242\238\226\251\233 \241\234\224\237\229\240 \225\243\228\229\242 \238\242\234\235\254\247\184\237. \205\224\241\242\240\238\233\234\232, \239\240\229\241\229\242\251 \232 \241\237\232\236\234\232 \237\229 \243\228\224\235\255\254\242\241\255.')
        if b('\207\206\196\210\194\197\208\196\200\210\220 \206\210\202\192\210','beta_rollback_confirm',230,false,true)then
            local ok,err=DSP.storage_beta_rollback()
            if ok then
                imgui.CloseCurrentPopup()
            else
                V.storage_rollback_error=tostring(err)
            end
        end
        V.inline()
        if b('\206\242\236\229\237\224','beta_rollback_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_rollback_error then V.red(V.fit(V.storage_rollback_error,imgui.GetContentRegionAvail().x))end
    end,{w=480,h=260})
    V.popup('\209\238\245\240\224\237\232\242\252 \225\224\227\224\230\237\232\234','storage_trunk_name',function()
        local target=V.storage_name_target
        if not target then V.red('\205\229\242 \239\238\235\237\238\227\238 \241\237\232\236\234\224 \225\224\227\224\230\237\232\234\224.');return end
        V.text('\194\226\229\228\232 \241\226\238\184 \237\224\231\226\224\237\232\229 \241\238\245\240\224\237\184\237\237\238\227\238 \241\237\232\236\234\224')
        V.muted('\205\224\239\240\232\236\229\240: \204\238\255 \236\224\248\232\237\224 \241 \235\224\240\246\224\236\232 / \204\224\248\232\237\224 \241 \240\229\241\243\240\241\224\236\232.')
        V.muted('\209\235\229\228\243\254\249\229\229 \238\242\234\240\251\242\232\229 \228\240\243\227\238\227\238 \225\224\227\224\230\237\232\234\224 \205\197 \225\243\228\229\242 \232\236\229\242\252 \253\242\238 \237\224\231\226\224\237\232\229 \224\226\242\238\236\224\242\232\247\229\241\234\232.')
        imgui.SetNextItemWidth(-1)
        imgui.InputText('##storage_trunk_named_input',V.storage_name_buf,128)
        if b('\209\238\245\240\224\237\232\242\252 \239\238\228 \237\224\231\226\224\237\232\229\236','save_named_trunk',math.min(240,imgui.GetContentRegionAvail().x),false,true)then
            local name=DSP.to_cp(ffi.string(V.storage_name_buf))
            local ok,snapshot=S.save_named_trunk(target,name)
            if ok then
                V.storage_name_target=nil
                V.storage_name_error=nil
                V.storage_tab='snapshots'
                V.storage_library_page='detail'
                for i,saved in ipairs(S.snapshots or {})do
                    if saved==snapshot then V.storage_selected=i;break end
                end
                imgui.CloseCurrentPopup()
            else
                V.storage_name_error=tostring(snapshot)
            end
        end
        if b('\206\242\236\229\237\224','cancel_named_trunk',120)then imgui.CloseCurrentPopup()end
        if V.storage_name_error then V.red(V.fit(V.storage_name_error,imgui.GetContentRegionAvail().x))end
    end,{w=460,h=330})
    V.popup('\209\226\238\255 \246\229\237\224','storage_price',function()
        local target,row=V.storage_price_target,V.storage_price_row
        if not target or not row then V.muted('\205\229\242 \226\251\225\240\224\237\237\238\227\238 \239\240\229\228\236\229\242\224');return end
        V.text(V.fit(row.name,imgui.GetContentRegionAvail().x))
        V.muted('\214\229\237\224 \231\224 \238\228\237\243 \248\242\243\234\243 \228\235\255 \240\224\241\247\184\242\224 \253\242\238\227\238 \241\237\232\236\234\224. 0 = \246\229\237\224 API.')
        M.compact_number(V.storage_price_buf,'value','storage_price_value',math.min(250,imgui.GetContentRegionAvail().x),0)
        if b('\209\238\245\240\224\237\232\242\252','price_apply',135,false,true)then
            local ok,err=S.set_manual_price(target,row,V.storage_price_buf.value)
            if ok then V.reset_list('storage_items');V.storage_price_target=nil;imgui.CloseCurrentPopup()
            else V.storage_price_error=err end
        end
        V.inline();if b('\206\242\236\229\237\224','price_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_price_error then V.red(V.storage_price_error)end
    end,{w=460,h=260})
    V.popup('\205\224\231\226\224\237\232\229 \241\237\232\236\234\224','storage_rename',function()
        local target=V.storage_label_target
        if not target then return end
        V.muted('\221\242\238 \232\236\255 \242\238\235\252\234\238 \228\235\255 \241\237\232\236\234\224. ID \236\224\248\232\237\251 \224\226\242\238\236\224\242\232\247\229\241\234\232 \237\229 \238\239\240\229\228\229\235\255\229\242\241\255.')
        imgui.SetNextItemWidth(-1)
        imgui.InputText('##storage_name_input',V.storage_label_buf,128)
        if b('\209\238\245\240\224\237\232\242\252','rename_apply',135,false,true)then
            local label=DSP.to_cp(ffi.string(V.storage_label_buf))
            local ok,result=S.set_snapshot_label(target,label)
            if ok then
                V.storage_label_target=nil
                if type(result)=='table' then
                    for i,saved in ipairs(S.snapshots or {})do
                        if saved==result then V.storage_selected=i;break end
                    end
                    V.storage_library_page='detail'
                end
                imgui.CloseCurrentPopup()
            else V.storage_label_error=result end
        end
        V.inline();if b('\206\242\236\229\237\224','rename_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_label_error then V.red(V.storage_label_error)end
    end,{w=460,h=240})
    V.popup('\206\247\232\241\242\232\242\252 \241\237\232\236\234\232?','storage_clear',function()
        V.text('\211\228\224\235\232\242\252 \241\238\245\240\224\237\184\237\237\251\229 \241\237\232\236\234\232 \248\234\224\244\238\226 \232 \225\224\227\224\230\237\232\234\238\226?')
        V.muted('\207\240\229\228\236\229\242\251 \226 \232\227\240\229 \238\241\242\224\237\243\242\241\255 \225\229\231 \232\231\236\229\237\229\237\232\233.')
        if b('\211\228\224\235\232\242\252 \241\237\232\236\234\232','confirm_clear',170,false,true)then
            local old=S.snapshots
            S.snapshots={};S.last_signature=nil;S.last_snapshot=nil;V.storage_selected=1;V.storage_library_page='list'
            local old_trunk=S.trunk and S.trunk.snapshot
            if S.trunk then S.trunk.snapshot=nil;S.trunk.pending=nil;S.trunk.status='idle';S.trunk.received=0 end
            if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
            if DSP.save_settings and not DSP.save_settings() then
                S.snapshots=old
                if S.trunk then S.trunk.snapshot=old_trunk;S.trunk.status='saved' end
                if DSP.settings then DSP.settings.storage_snapshots=old end
                V.storage_error='\205\229 \243\228\224\235\238\241\252 \241\238\245\240\224\237\232\242\252 \243\228\224\235\229\237\232\229';return
            end
            imgui.CloseCurrentPopup()
        end
        V.inline()
        if b('\206\242\236\229\237\224','cancel_clear',120)then imgui.CloseCurrentPopup()end
    end,{w=480,h=230})
end

  end
  module_storage_ui()

  do
    local live=DSP.live
    if live and type(live.handle)=='function' and not live._storage_probe_wrapped then
      local previous=live.handle
      live.handle=function(iface,sub,raw)
        if iface==52 and DSP.storage_probe and DSP.storage_probe.on_packet then
          local ok,err=pcall(DSP.storage_probe.on_packet,sub,raw)
          if not ok and DSP.flog then DSP.flog('STORAGE observer: '..tostring(err)) end
        end
        return previous(iface,sub,raw)
      end
      live._storage_probe_wrapped=true
    end
  end

  do
    local V=DSP.ui21
    if V and type(V.set_screen)=='function' and not V._storage_screen_wrapped then
      local previous=V.set_screen
      V.set_screen=function(id)
        if id=='storage' then
          V.storage_tab='scan'
          V.storage_scan_mode=V.storage_scan_mode or 'trunk'
          V.storage_library_page='list'
          if V.reset_list then V.reset_list('storage_scan_panel') end
        end
        return previous(id)
      end
      V._storage_screen_wrapped=true
    end
  end

  DSP.version='2.8.1'
  if DSP.flog then DSP.flog('Smart storage library beta 2.8.1 loaded; menu rollback -> 2.7.0') end
  return true
end
