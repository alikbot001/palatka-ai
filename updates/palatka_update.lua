-- Palatka AI 2.8.3: compatible trunk sizes, suggestion dialog and settings protection.
PALATKA_UPDATE_VERSION = '2.8.3'
return function(DSP)
  -- Install settings guard before any other overlay can save preferences.
  local function module_settings_safety()
-- Palatka Settings Safety: protect user preferences on every OTA update.
-- Install after core; do not replace, reset or filter unknown setting keys.
local G = DSP.settings_safety or {}
DSP.settings_safety = G
if not G.installed then
    local path = DSP.settings_path
    local original_save = DSP.save_settings

    local function read_all(filename)
        local f=io.open(filename,'rb')
        if not f then return nil end
        local data=f:read('*a')
        f:close()
        return data
    end
    local function valid_json(raw)
        if type(raw)~='string' or #raw==0 then return false end
        local ok,result=pcall(decodeJson,raw)
        return ok and type(result)=='table'
    end
    local function write_bytes(filename,data)
        local f,err=io.open(filename,'wb')
        if not f then return false,tostring(err or 'cannot open') end
        local wrote,e=f:write(data)
        local closed,close_err=f:close()
        if not wrote or not closed then return false,tostring(e or close_err) end
        local copy=read_all(filename)
        if copy~=data then return false,'verification mismatch' end
        return true
    end
    local function backup_valid(source,target)
        local raw=read_all(source)
        if not raw or not valid_json(raw) then return false,'invalid source' end
        local tmp=target..'.tmp'
        local ok,err=write_bytes(tmp,raw)
        if not ok then return false,err end
        -- Moving the last valid backup aside must never delete it.
        local existing=read_all(target)
        if existing and valid_json(existing) then
            local keep=target..'.previous'
            pcall(os.remove,keep)
            local moved= os.rename(target,keep)
            if not moved then pcall(os.remove,tmp);return false,'cannot rotate backup' end
        end
        local renamed,e=os.rename(tmp,target)
        if not renamed then
            pcall(os.remove,tmp)
            if existing and valid_json(existing) then pcall(os.rename,target..'.previous',target) end
            return false,tostring(e or 'cannot store backup')
        end
        return true
    end

    -- Back up the last known-good settings, including fields from future
    -- versions, BEFORE installing new default keys in any subsequent update.
    function G.checkpoint(tag)
        if type(path)~='string' then return false,'settings path missing' end
        local raw=read_all(path)
        if not raw then return true,'no settings yet' end
        if not valid_json(raw) then return false,'settings invalid: no overwrite' end
        local safe=tostring(tag or 'before_update'):gsub('[^%w_%-]','_')
        local snapshot=path..'.checkpoint_'..safe
        if read_all(snapshot) then return true,snapshot end
        local ok,e=write_bytes(snapshot..'.tmp',raw)
        if not ok then return false,e end
        local renamed,err=os.rename(snapshot..'.tmp',snapshot)
        if not renamed then return false,tostring(err or 'checkpoint rename failed') end
        return true,snapshot
    end

    -- File may be corrupt after a crash: NEVER save defaults over it.
    function DSP.save_settings()
        if type(path)~='string' or type(DSP.settings)~='table' then
            return false,'invalid settings state'
        end
        local existing=read_all(path)
        if existing and not valid_json(existing) then
            if DSP.flog then pcall(DSP.flog,'SETTINGS SAFETY: existing JSON corrupt; refusing overwrite') end
            return false,'Existing settings invalid; preserved for recovery'
        end
        local ok,json=pcall(encodeJson,DSP.settings)
        if not ok or not valid_json(json) then return false,'settings encoding invalid' end
        local temp=path..'.safe_new'
        local wrote,err=write_bytes(temp,json)
        if not wrote then return false,err end
        if existing then
            local saved,why=backup_valid(path,path..'.bak')
            if not saved then pcall(os.remove,temp);return false,'backup failed: '..tostring(why) end
            -- Android does not guarantee rename-over-existing.
            local old=path..'.old'
            pcall(os.remove,old)
            local moved,why2=os.rename(path,old)
            if not moved then pcall(os.remove,temp);return false,'cannot move old settings: '..tostring(why2) end
            local placed,why3=os.rename(temp,path)
            if not placed then
                pcall(os.rename,old,path)
                pcall(os.remove,temp)
                return false,'cannot replace settings: '..tostring(why3)
            end
            pcall(os.remove,old)
        else
            local placed,why=os.rename(temp,path)
            if not placed then pcall(os.remove,temp);return false,'cannot install settings: '..tostring(why) end
        end
        return true
    end

    -- Old files can contain a richer schema than the current build.
    -- Do not enumerate or discard unknown settings during an update.
    G.installed=true
    G.original_save=original_save
    local ok,detail=G.checkpoint('v283')
    if DSP.flog then
        pcall(DSP.flog,'SETTINGS SAFETY checkpoint: '..tostring(ok)..' '..tostring(detail))
    end
end

  end
  module_settings_safety()

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
    while #S.snapshots>S.max_saved+1 do table.remove(S.snapshots)end
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
    -- Live scans are deliberately NOT in S.snapshots. Allow naming only the
    -- current live result; stale objects from previous scans are rejected.
    if snapshot.source=='packet220_trunk' and S.trunk and S.trunk.snapshot==snapshot then
        return S.save_named_trunk(snapshot,label)
    end
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
local VALID_CAPACITY = {[30]=true,[60]=true,[90]=true,[120]=true,[150]=true,[180]=true}
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
    local capacity=tonumber(obj.capacity or obj.slotCount or obj.totalSlots)
    if not VALID_CAPACITY[capacity] then capacity=nil end
    return normalized,capacity
end

local function active_snapshot()
    for _, s in ipairs(S.snapshots or {}) do
        if s.source == 'packet220_trunk' and s.kind == 'trunk' then return s end
    end
    return nil
end

local function build_rows(slots, capacity)
    local rows, count, occupied = {}, 0, 0
    for i=0,(capacity or TRUNK_SLOTS)-1 do
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

local function save_snapshot(slots, source_reason, capacity)
    local ts=os.time()
    capacity=capacity or TRUNK_SLOTS
    local rows, total, occupied = build_rows(slots,capacity)
    local requested_at=T.requested_at
    local update_target_id=T.update_target_id
    local snap={
        id='trunk_live_'..tostring(ts)..'_'..tostring((T.scan_generation or 0)+1),
        kind='trunk',
        -- No persistent vehicle identity in observed packet. This is ALWAYS the last opened trunk.
        title='\207\238\241\235\229\228\237\232\233 \238\242\234\240\251\242\251\233 \225\224\227\224\230\237\232\234',
        source='packet220_trunk', identity_verified=false,
        observed_at=ts, updated_at=ts, server=DSP.market and DSP.market.state and DSP.market.state.sid or nil,
        slots_count=capacity, occupied_slots=occupied,count_known=total,
        rows=rows, slots=slots, update_kind=source_reason,
    }
    -- A scan is IN MEMORY ONLY. A user-named copy is the sole path to the
    -- persistent library. Never write an unnamed scan to storage_snapshots.
    T.snapshot=snap
    T.last_update=ts
    T.status='saved'
    T.received=capacity
    T.occupied=occupied
    T.total=total
    T.last_saved_at=ts
    if requested_at then
        T.last_completed_request_at=ts
        T.requested_at=nil
        T.completed_update_target_id=update_target_id
        T.update_target_id=nil
    end
    T.last_error=nil
    T.last_warning=nil
    T.scan_generation=(T.scan_generation or 0)+1
    T.review_generation=T.scan_generation
    T.review_needed=true
    if DSP.flog then DSP.flog('TRUNK '..source_reason..' slots='..capacity..' occupied='..occupied..' count='..total) end
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
    local items,declared_capacity=parse_payload(raw)
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
        T.pending={slots={},seen={},count=0,started=ts,last_at=ts,
            capacity=declared_capacity or T.selected_capacity or TRUNK_SLOTS}
        T.status='receiving';T.received=0;T.last_error=nil
    end
    if T.pending then
        local p=T.pending
        p.last_at=ts
        if declared_capacity then p.capacity=declared_capacity end
        -- Never finalize a user-selected 30-slot scan if the packet explicitly
        -- includes slots outside its capacity: the observed layout is larger.
        for _,v in ipairs(items) do
            if v.slot>=p.capacity then
                p.capacity=TRUNK_SLOTS
            end
        end
        for _,v in ipairs(items) do
            if not p.seen[v.slot] then p.seen[v.slot]=true;p.count=p.count+1 end
            p.slots[v.slot+1]=v
        end
        T.received=p.count
        if p.count>=p.capacity then
            -- Full means all expected slots in THIS layout were seen. If the
            -- server does not declare capacity, the player explicitly chooses
            -- their car's capacity (30/180), not automatic guessing.
            local complete=true
            for i=1,p.capacity do if not p.slots[i] then complete=false;break end end
            if complete then
                T.pending=nil
                save_snapshot(p.slots,'full',p.capacity)
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
            T.last_error='\207\238\235\237\251\233 \241\237\232\236\238\234 \237\229 \239\240\232\248\184\235. \199\224\234\240\238\233 \225\224\227\224\230\237\232\234 \232 \238\242\234\240\238\233 \229\227\238 \231\224\237\238\226\238.'
        elseif T.snapshot then
            -- Do not hide a previously valid full scan just because a single
            -- slot changed while the player was inside the trunk.
            T.last_warning='\200\231\236\229\237\229\237\232\229 \238\242\228\229\235\252\237\251\245 \241\235\238\242\238\226 \237\229 \239\240\232\236\229\237\229\237\238. \196\235\255 \237\238\226\251\245 \228\224\237\237\251\245 \238\242\234\240\238\233 \225\224\227\224\230\237\232\234 \231\224\237\238\226\238.'
        end
        return false
    end
    T.status=T.requested_at and 'need_reopen' or 'unknown_partial'
    if T.requested_at then
        T.last_error='\207\238\235\243\247\229\237\224 \242\238\235\252\234\238 \247\224\241\242\252. \199\224\234\240\238\233 \225\224\227\224\230\237\232\234 \232 \238\242\234\240\238\233 \231\224\237\238\226\238.'
    end
    return false
end

-- Load the most recently persisted trunk as read-only history after restart.
-- Old versions may have stored a nameless live scan. Do not resurrect it
-- in the new unsaved session; named library entries remain untouched.
T.snapshot=nil
T.autoscan_enabled=not (DSP.settings and DSP.settings.storage_trunk_autoscan==false)
T.selected_capacity=VALID_CAPACITY[tonumber(DSP.settings and DSP.settings.storage_trunk_capacity)]
    and tonumber(DSP.settings.storage_trunk_capacity) or 180

function S.set_trunk_capacity(cap)
    cap=tonumber(cap)
    if not VALID_CAPACITY[cap] then return false,'\205\229\228\238\239\243\241\242\232\236\224\255 \226\236\229\241\242\232\236\238\241\242\252' end
    if T.requested_at then return false,'\209\237\224\247\224\235\224 \238\241\242\224\237\238\226\232 \242\229\234\243\249\232\233 \241\234\224\237' end
    local previous=T.selected_capacity
    T.selected_capacity=cap
    if DSP.settings then DSP.settings.storage_trunk_capacity=cap end
    if DSP.save_settings then
        local ok,saved,err=pcall(DSP.save_settings)
        if not ok or not saved then
            T.selected_capacity=previous
            if DSP.settings then DSP.settings.storage_trunk_capacity=previous end
            return false,tostring(err or saved or '\206\248\232\225\234\224 \241\238\245\240\224\237\229\237\232\255')
        end
    end
    return true
end

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
    T.review_needed=false
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
    if type(snapshot)~='table' then return false,'\213\240\224\237\232\235\232\249\229 \237\229 \226\251\225\240\224\237\238' end
    if snapshot.source=='packet220_trunk' then
        return S.clear_live_snapshot()
    end
    local index=nil
    for i,saved in ipairs(S.snapshots or {})do
        if saved==snapshot then index=i;break end
    end
    if not index then return false,'\213\240\224\237\232\235\232\249\229 \243\230\229 \243\228\224\235\229\237\238' end
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
    local old_state={snapshot=T.snapshot,occupied=T.occupied,total=T.total,received=T.received,
        last_saved_at=T.last_saved_at,last_completed_request_at=T.last_completed_request_at,
        status=T.status}
    T.snapshot=nil;T.occupied=nil;T.total=nil;T.received=0
    T.last_saved_at=nil;T.last_completed_request_at=nil
    if not T.requested_at then T.status=T.autoscan_enabled and 'idle' or 'disabled' end
    if DSP.save_settings then
        local called,ok,err=pcall(DSP.save_settings)
        if not called or not ok then
            S.snapshots=prior
            if DSP.settings then DSP.settings.storage_snapshots=prior_saved end
            for k,v in pairs(old_state)do T[k]=v end
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

-- Candidate detection is only a suggestion, never a vehicle identifier.
-- Compare item IDs and enchantments across slots, not slot positions or amounts.
-- Only fully saved, named type-8 trunk snapshots are eligible.
local function trunk_types(snapshot)
    local keys, count={},0
    for _,row in ipairs(snapshot and snapshot.rows or {}) do
        local id=tonumber(row.id)
        if id and id>0 and id%1==0 then
            local enchant=tonumber(row.ench) or 0
            local key=tostring(id)..':'..tostring(enchant)
            if not keys[key] then keys[key]=true;count=count+1 end
        end
    end
    return keys,count
end

function S.match_saved_trunks(snapshot)
    if type(snapshot)~='table' or snapshot.kind~='trunk'
        or snapshot.source~='packet220_trunk' or not VALID_CAPACITY[snapshot.slots_count]
        or type(snapshot.rows)~='table' then return {} end
    local current,total=trunk_types(snapshot)
    if total==0 then return {} end
    local matches={}
    for _,saved in ipairs(S.snapshots or {}) do
        if saved.source=='packet220_trunk_named' and saved.kind=='trunk'
            and type(saved.rows)=='table'
            and (snapshot.server==nil or saved.server==nil
                 or tostring(snapshot.server)==tostring(saved.server)) then
            local previous,count=trunk_types(saved)
            if count>0 then
                local common=0
                for key in pairs(current)do if previous[key] then common=common+1 end end
                if common>0 then
                    local union=total+count-common
                    matches[#matches+1]={
                        id=saved.id,title=saved.title,shared=common,
                        current_types=total,saved_types=count,
                        similarity=math.floor(100*common/math.max(1,union)+.5),
                        observed_at=tonumber(saved.observed_at) or 0
                    }
                end
            end
        end
    end
    table.sort(matches,function(a,b)
        if a.similarity~=b.similarity then return a.similarity>b.similarity end
        if a.shared~=b.shared then return a.shared>b.shared end
        if a.observed_at~=b.observed_at then return a.observed_at>b.observed_at end
        return tostring(a.id)<tostring(b.id)
    end)
    return matches
end

-- Keep manually named copies independent from the latest automatically opened
-- vehicle. The packet has no trusted vehicle ID: do NOT auto-assign old labels
-- when a different trunk is opened.
function S.save_named_trunk(snapshot,label)
    if type(snapshot)~='table' or snapshot.source~='packet220_trunk' then
        return false,'select a confirmed full trunk snapshot'
    end
    if not snapshot.rows or not VALID_CAPACITY[snapshot.slots_count] then
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
        slots_count=snapshot.slots_count,occupied_slots=snapshot.occupied_slots,
        count_known=snapshot.count_known,rows=rows}
    for _,existing in ipairs(S.snapshots or {}) do
        if existing.source~='packet220_trunk' and DSP.lower(tostring(existing.title or ''))==DSP.lower(name) then
            return false,'\210\224\234\238\229 \237\224\231\226\224\237\232\229 \243\230\229 \229\241\242\252. \206\242\234\240\238\233 \229\227\238 \232 \226\251\225\229\240\232 \171\206\225\237\238\226\232\242\252\187.'
        end
    end
    local prior=S.snapshots
    local prior_saved=DSP.settings and DSP.settings.storage_snapshots
    local fresh={named}
    for _,existing in ipairs(prior) do
        -- Old releases wrote a nameless live scan into settings. Keep ONLY
        -- deliberately saved user records in the persistent library.
        if existing.source~='packet220_trunk' then
            fresh[#fresh+1]=existing
            if #fresh>=S.max_saved then break end
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
    T.review_needed=false
    S.sort_cache=setmetatable({},{__mode='k'})
    return true,named
end

function S.apply_latest_to_saved(target_id)
    local live=T.snapshot
    local target=S.find_snapshot(target_id)
    if not live or live.source~='packet220_trunk' or not VALID_CAPACITY[live.slots_count] then
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
    target.slots_count=live.slots_count
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
    T.review_needed=false
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
            T.last_error='\207\238\235\237\251\233 \241\237\232\236\238\234 180/180 \237\229 \239\238\235\243\247\229\237. \199\224\239\243\241\242\232 \241\234\224\237 \232 \231\224\237\238\226\238 \238\242\234\240\238\233 \225\224\227\224\230\237\232\234.'
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
local allowed = {cabinet=true, warehouse=true}

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
    local titles={cabinet='\216\234\224\244',warehouse='\209\234\235\224\228'}
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
        if #replacement>=(S.max_saved or 20)+1 then break end
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
-- Simplified read-only cabinet / warehouse observer.
-- Personal inventory scan intentionally removed from the UI.
local V = DSP.ui21
local P = DSP.storage_probe
local labels={cabinet='\216\202\192\212',warehouse='\209\202\203\192\196'}
local descriptions={cabinet='\248\234\224\244',warehouse='\241\234\235\224\228'}
local function button(label,id,width,active,primary)
    return V.button(label,'probe_'..id,width,active,primary)
end

function V.storage_probe_panel(width,kind)
    width=math.max(190,tonumber(width) or 300)
    local w=math.min(width,315)
    if not P then V.red('\209\234\224\237\229\240 \253\242\238\227\238 \234\238\237\242\229\233\237\229\240\224 \237\229\228\238\241\242\243\239\229\237.');return end
    if not labels[kind] then V.red('\205\229\232\231\226\229\241\242\237\251\233 \242\232\239 \245\240\224\237\232\235\232\249\224.');return end
    local state=P.state()

    V.apply_font((V.font_pixels or 18)*1.15)
    V.text(labels[kind])
    V.apply_font()

    if state.armed and state.kind~=kind then
        V.red('\209\229\233\247\224\241 \232\228\184\242 \241\234\224\237 \228\240\243\227\238\227\238 \245\240\224\237\232\235\232\249\224.')
        if button('\206\241\242\224\237\238\226\232\242\252 \242\229\234\243\249\232\233 \241\234\224\237','stop_other',w,false,true)then P.stop()end
        return
    end

    if state.kind~=kind and not state.armed then
        V.muted('\205\224\230\236\232 \171\205\224\247\224\242\252 \241\234\224\237\187, \231\224\242\229\236 \231\224\234\240\238\233 Palatka AI \232 \238\242\234\240\238\233 '..descriptions[kind]..' \226 \232\227\240\229.')
        if button('\205\192\215\192\210\220 \209\202\192\205','arm_'..kind,w,false,true)then
            P.arm(kind,40)
            V.probe_selected=1
            V.probe_error=nil
        end
        return
    end

    if state.armed then
        V.green('\209\202\192\205 \199\192\207\211\217\197\205')
        V.muted('\206\242\234\240\238\233 '..descriptions[kind]..' \226 \232\227\240\229. \207\238\241\235\229 \253\242\238\227\238 \226\229\240\237\232\241\252 \241\254\228\224.')
        V.muted('\206\241\242\224\235\238\241\252: '..math.max(0,state.until_ts-os.time())..' \241\229\234.')
        if button('\199\192\194\197\208\216\200\210\220 \200 \207\206\202\192\199\192\210\220','stop',w,false,true)then P.stop()end
        return
    end

    if #state.order==0 then
        V.red('\209\238\228\229\240\230\232\236\238\229 \237\229 \240\224\241\239\238\231\237\224\237\238.')
        V.muted('\207\238\239\240\238\225\243\233 \231\224\239\243\241\242\232\242\252 \241\234\224\237 \229\249\184 \240\224\231 \232 \231\224\237\238\226\238 \238\242\234\240\251\242\252 '..descriptions[kind]..'.')
        if button('\207\206\194\210\206\208\200\210\220 \209\202\192\205','arm_'..kind,w,false,true)then
            P.arm(kind,40);V.probe_selected=1;V.probe_error=nil
        end
        return
    end

    V.probe_selected=math.max(1,math.min(#state.order,V.probe_selected or 1))
    local selected=V.probe_selected
    if #state.order>1 then
        V.muted('\205\224\233\228\229\237\238 \237\229\241\234\238\235\252\234\238 \226\224\240\232\224\237\242\238\226: '..selected..' / '..#state.order)
        if button('\209\235\229\228\243\254\249\232\233 \226\224\240\232\224\237\242','next',w)then
            selected=selected%#state.order+1
            V.probe_selected=selected
        end
    end

    local info,err=P.preview(selected)
    if not info then V.red(tostring(err));return end

    V.green('\205\192\201\196\197\205\206: '..tostring(info.occupied)..' \231\224\237\255\242\251\245 \241\235\238\242\238\226')
    V.text('\207\238\228\242\226\229\240\230\228\229\237\238 \239\240\229\228\236\229\242\238\226: '..tostring(info.known))
    if info.unknown_qty>0 then
        V.muted('\193\229\231 \242\238\247\237\238\227\238 \234\238\235\232\247\229\241\242\226\224: '..tostring(info.unknown_qty)..' \241\242\240\238\234')
    end

    if DSP.storage and DSP.storage.evaluate then
        local estimate=DSP.storage.evaluate({kind=kind,rows=info.rows,
            server=DSP.market and DSP.market.state and DSP.market.state.sid})
        if not estimate.cross_server then
            V.green('\206\246\229\237\234\224 \241\234\243\239\234\232: '..DSP.money(estimate.sell_to_buyers))
            if estimate.missing_prices>0 then
                V.muted('\205\229\242 \246\229\237 \228\235\255 '..estimate.missing_prices..' \241\242\240\238\234')
            end
        end
    end

    V.red('\207\238\234\224 \253\242\238 \239\240\229\228\226\224\240\232\242\229\235\252\237\251\233 \241\234\224\237: \239\238\235\237\251\233 \244\238\240\236\224\242 '..descriptions[kind]..' \229\249\184 \239\240\238\226\229\240\255\229\242\241\255.')
    if button('\209\206\213\208\192\205\200\210\220 \208\197\199\211\203\220\210\192\210','save',w,false,true)then
        local ok,saved=P.save(selected)
        if ok then
            V.probe_error=nil
            V.storage_tab='library'
            V.storage_library_page='list'
        else
            V.probe_error=tostring(saved)
        end
    end
    if button('\207\206\194\210\206\208\200\210\220 \209\202\192\205','arm_'..kind,w)then
        P.arm(kind,40);V.probe_selected=1;V.probe_error=nil
    end
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
        if DSP.storage_beta_rollback and b('CRR \206\210\202\192\210','beta_rollback',145,false,true) then
            V.open_popup('CRR \238\242\234\224\242','storage_beta_rollback')
        end
    end,DSP.storage_beta_rollback and 149 or 0)

    -- Old versions used "snapshots/manual". Collapse them into the two-task UI.
    if V.storage_tab=='snapshots' then V.storage_tab='library' end
    if V.storage_tab=='manual' then V.storage_tab='scan' end
    V.storage_tab=V.storage_tab or 'scan'
    V.storage_scan_mode=(V.storage_scan_mode=='inventory') and 'trunk' or (V.storage_scan_mode or 'trunk')
    V.storage_library_page=V.storage_library_page or 'list'

    local width=imgui.GetContentRegionAvail().x
    local tabw=math.max(120,(width-6)/2)
    for i,tab in ipairs({{'scan','\209\202\192\205'},{'library','\204\206\200 \213\208\192\205\200\203\200\217\192'}})do
        if b(tab[2],'tab_'..tab[1],tabw,V.storage_tab==tab[1],V.storage_tab==tab[1])then
            V.storage_tab=tab[1]
            if tab[1]=='library' then V.storage_library_page='list' end
            V.reset_list('storage_scan_panel')
        end
        if i==1 then V.inline(6)end
    end
    imgui.Separator()

    if V.storage_tab=='scan' then
        V.list('storage_scan_panel',function(w)
            local options={{'trunk','\193\224\227\224\230\237\232\234'},{'cabinet','\216\234\224\244'},{'warehouse','\209\234\235\224\228'}}
            local bw=math.max(92,(w-12)/3)
            for i,item in ipairs(options)do
                if b(item[2],'choose_'..item[1],bw,V.storage_scan_mode==item[1],V.storage_scan_mode==item[1])then
                    if S.cancel_trunk_scan and V.storage_scan_mode=='trunk' and item[1]~='trunk' then
                        S.cancel_trunk_scan()
                    end
                    V.storage_scan_mode=item[1]
                    V.probe_error=nil
                    V.reset_list('storage_scan_panel')
                end
                if i<3 then V.inline(6)end
            end
            imgui.Separator()

            if V.storage_scan_mode~='trunk' then
                if V.storage_probe_panel then V.storage_probe_panel(w,V.storage_scan_mode)
                else V.red('\209\234\224\237\229\240 \253\242\238\227\238 \245\240\224\237\232\235\232\249\224 \237\229\228\238\241\242\243\239\229\237.') end
                return
            end

            local t=(S.trunk_state and S.trunk_state()) or S.trunk or {}
            -- A review appears once per NEW completed 180-slot scan, and only
            -- when existing saved trunks share at least one item ID/enchant.
            if t.review_needed and t.review_generation
                and V.storage_match_generation~=t.review_generation
                and t.snapshot and t.status=='saved' and S.match_saved_trunks then
                V.storage_match_generation=t.review_generation
                local matches=S.match_saved_trunks(t.snapshot)
                if #matches>0 then
                    V.storage_match_review={
                        generation=t.review_generation, matches=matches, selected=1
                    }
                    V.open_popup('\207\238\245\238\230\232\233 \225\224\227\224\230\237\232\234','storage_match_confirm')
                else
                    t.review_needed=false
                end
            end
            local active=t.requested_at~=nil or t.status=='waiting_open' or
                t.status=='receiving' or t.status=='need_reopen'

            V.apply_font((V.font_pixels or 18)*1.18)
            V.text('\205\206\194\219\201 \209\202\192\205 \193\192\195\192\198\205\200\202\192')
            V.apply_font()

            if active then
                if t.status=='receiving' then
                    V.green('\207\206\203\211\215\192\222 \196\192\205\205\219\197: '..tostring(t.received or 0)..' / 180')
                    V.muted('\205\229 \231\224\234\240\251\226\224\233 \225\224\227\224\230\237\232\234, \239\238\234\224 \237\229 \225\243\228\229\242 180 / 180.')
                elseif t.status=='need_reopen' then
                    V.red('\205\211\198\205\206 \199\192\205\206\194\206 \206\210\202\208\219\210\220 \193\192\195\192\198\205\200\202')
                    V.text('\199\224\234\240\238\233 \225\224\227\224\230\237\232\234 \239\238\235\237\238\241\242\252\254 \232 \238\242\234\240\238\233 \229\227\238 \229\249\184 \240\224\231.')
                    V.muted('\207\229\240\229\236\229\249\229\237\232\229 \239\240\229\228\236\229\242\238\226 \226\237\243\242\240\232 \243\230\229 \238\242\234\240\251\242\238\227\238 \225\224\227\224\230\237\232\234\224 \228\224\184\242 \242\238\235\252\234\238 \247\224\241\242\232\247\237\251\229 \232\231\236\229\237\229\237\232\255.')
                else
                    V.green('\209\202\192\205 \199\192\207\211\217\197\205')
                    V.text('\197\241\235\232 \225\224\227\224\230\237\232\234 \243\230\229 \238\242\234\240\251\242 \151 \231\224\234\240\238\233 \229\227\238.')
                    V.text('\199\224\242\229\236 \238\242\234\240\238\233 \225\224\227\224\230\237\232\234 \231\224\237\238\226\238 \238\225\251\247\237\251\236 \241\239\238\241\238\225\238\236.')
                    V.muted('\198\228\243 \239\238\235\237\251\233 \241\237\232\236\238\234 180 / 180 \241\235\238\242\238\226.')
                end
                V.muted('\207\238\235\243\247\229\237\238: '..tostring(t.received or 0)..' / 180')
                if b('\206\210\204\197\205\200\210\220 \209\202\192\205','cancel_trunk',math.min(w,240))then
                    S.cancel_trunk_scan()
                end
                V.muted('\207\240\229\228\251\228\243\249\232\233 \240\229\231\243\235\252\242\224\242 \226\238 \226\240\229\236\255 \237\238\226\238\227\238 \241\234\224\237\224 \237\229 \239\238\234\224\231\251\226\224\229\242\241\255.')
                return
            end

            if t.status=='no_packets' or t.status=='incomplete' then
                V.red('\205\206\194\219\201 \209\202\192\205 \205\197 \207\206\203\211\215\197\205')
                V.text('\199\224\234\240\238\233 \225\224\227\224\230\237\232\234, \237\224\230\236\232 \171\205\224\247\224\242\252 \237\238\226\251\233 \241\234\224\237\187 \232 \238\242\234\240\238\233 \229\227\238 \231\224\237\238\226\238.')
            elseif t.last_error and t.status~='saved' then
                V.red(V.fit(tostring(t.last_error),w))
            end

            if b('\205\192\215\192\210\220 \205\206\194\219\201 \209\202\192\205','start_trunk',math.min(w,320),false,true)then
                S.begin_trunk_scan()
                V.storage_error=nil
                return
            end
            V.muted('\194\224\230\237\238: \241\234\224\237 \231\224\239\243\241\234\224\229\242\241\255 \196\206 \239\238\226\242\238\240\237\238\227\238 \238\242\234\240\251\242\232\255 \225\224\227\224\230\237\232\234\224.')

            if t.snapshot and t.status=='saved' then
                imgui.Separator()
                V.green('\195\206\210\206\194\206 \183 180 / 180')
                if t.last_warning then V.muted(V.fit(t.last_warning,w)) end
                V.text('\199\224\237\255\242\238 \241\235\238\242\238\226: '..tostring(t.snapshot.occupied_slots or 0))
                V.text('\194\241\229\227\238 \239\240\229\228\236\229\242\238\226: '..tostring(t.snapshot.count_known or 0))
                local sig=tostring(t.last_saved_at or t.snapshot.observed_at)..'/'..
                    tostring(DSP.market and DSP.market.state and DSP.market.state.version or '')
                local info=V.memo('storage_trunk_summary',sig,function()return S.evaluate(t.snapshot)end)
                if not info.cross_server then
                    V.green('\206\246\229\237\234\224 \241\234\243\239\234\232: '..DSP.money(info.sell_to_buyers))
                end

                if t.review_needed and V.storage_match_review
                    and V.storage_match_review.generation==t.review_generation then
                    if b('\207\206\213\206\198\200\197 \193\192\195\192\198\205\200\202\200','show_matches',math.min(w,290),false,true)then
                        V.open_popup('\207\238\245\238\230\232\233 \225\224\227\224\230\237\232\234','storage_match_confirm')
                    end
                end
                local update_target=t.completed_update_target_id and S.find_snapshot(t.completed_update_target_id)
                if update_target then
                    V.text('\206\225\237\238\226\232\242\252: '..tostring(update_target.title))
                    if b('\207\208\200\204\197\205\200\210\220 \202 '..tostring(update_target.title),'apply_update',math.min(w,320),false,true)then
                        local ok,updated=S.apply_latest_to_saved(update_target.id)
                        if ok then
                            local _,idx=S.find_snapshot(updated.id)
                            V.storage_selected=idx or 1
                            V.storage_library_page='detail'
                            V.storage_tab='library'
                            return
                        else V.storage_error=tostring(updated) end
                    end
                    if b('\209\206\213\208\192\205\200\210\220 \202\192\202 \205\206\194\206\197','save_update_new',math.min(w,290))then
                        V.storage_name_target=t.snapshot
                        V.storage_name_buf=imgui.new.char[128]()
                        V.storage_name_error=nil
                        V.open_popup('\209\238\245\240\224\237\232\242\252 \225\224\227\224\230\237\232\234','storage_trunk_name')
                    end
                else
                    if b('\209\206\213\208\192\205\200\210\220 \202\192\202 \205\206\194\206\197','save_new',math.min(w,290),false,true)then
                        V.storage_name_target=t.snapshot
                        V.storage_name_buf=imgui.new.char[128]()
                        V.storage_name_error=nil
                        V.open_popup('\209\238\245\240\224\237\232\242\252 \225\224\227\224\230\237\232\234','storage_trunk_name')
                    end
                end
                if b('\206\215\200\209\210\200\210\220 \207\206\209\203\197\196\205\200\201 \209\202\192\205','clear_live',math.min(w,290))then
                    local ok,err=S.clear_live_snapshot()
                    if not ok then V.storage_error=tostring(err) end
                end
            end

            if V.storage_error then V.red(V.fit(V.storage_error,w)) end
            imgui.Separator()
            if b((t.autoscan_enabled and '\192\226\242\238\241\234\224\237: \194\202\203' or '\192\226\242\238\241\234\224\237: \194\219\202\203'),
                 'toggle_auto',math.min(w,210),t.autoscan_enabled)then
                local ok,err=S.set_trunk_autoscan(not t.autoscan_enabled)
                if not ok then V.storage_error=tostring(err) end
            end
            V.muted('\192\226\242\238\241\234\224\237 \235\238\226\232\242 \239\238\235\237\251\233 \241\237\232\236\238\234 \239\240\232 \238\242\234\240\251\242\232\232 \225\224\227\224\230\237\232\234\224. \206\237 \237\229 \243\227\224\228\251\226\224\229\242 \236\224\248\232\237\243 \239\238 \239\238\241\224\228\234\229 \226 \224\226\242\238.')
        end,{footer=false})
        return
    end

    local snapshots=S.snapshots or {}
    local library=S.library and S.library() or {}

    if V.storage_library_page=='list' then
        V.apply_font((V.font_pixels or 18)*1.24)
        V.text('\204\206\200 \213\208\192\205\200\203\200\217\192')
        V.apply_font()
        V.muted('\210\238\235\252\234\238 \241\238\245\240\224\237\184\237\237\251\229 \231\224\239\232\241\232. \207\238\241\235\229\228\237\232\233 \241\234\224\237 \241\254\228\224 \237\229 \239\238\228\236\229\248\232\226\224\229\242\241\255.')
        if b('+ \205\206\194\219\201 \209\202\192\205','library_new_scan',math.min(230,width),false,true)then
            V.storage_tab='scan'
            V.storage_scan_mode='trunk'
            S.begin_trunk_scan()
            V.reset_list('storage_scan_panel')
            return
        end
        V.muted('\207\206\200\209\202: \239\238 \237\224\231\226\224\237\232\254 \245\240\224\237\232\235\232\249\224 \232\235\232 \239\240\229\228\236\229\242\224')
        local query=V.search and V.search('storage_all','\205\224\231\226\224\237\232\229 \232\235\232 \239\240\229\228\236\229\242...',math.min(380,width)) or ''
        query=DSP.lower(DSP.trim(query or ''))
        local filtered={}
        local grand,missing=0,0
        for _,entry in ipairs(library)do
            local snap=entry.snapshot
            local found=query=='' or DSP.lower(tostring(snap.title or '')):find(query,1,true)~=nil
            if not found then
                for _,it in ipairs(snap.rows or {})do
                    if DSP.lower(tostring(it.name or '')):find(query,1,true)then found=true;break end
                end
            end
            if found then filtered[#filtered+1]=entry end
            local value=S.evaluate(snap)
            if value.cross_server then missing=missing+1
            else grand=grand+(value.sell_to_buyers or 0) end
        end
        V.text('\213\240\224\237\232\235\232\249: '..#library..' | \237\224\233\228\229\237\238: '..#filtered)
        V.green('\209\243\236\236\224 \238\246\229\237\238\234: '..DSP.money(grand))
        if missing>0 then V.muted('\193\229\231 \238\246\229\237\234\232: '..missing..' (\228\240\243\227\238\233 \241\229\240\226\229\240)') end
        V.muted('\221\242\238 \241\243\236\236\224 \238\246\229\237\238\234 \241\237\232\236\234\238\226, \237\229 \240\229\224\235\252\237\224\255 \239\240\232\225\251\235\252.')
        if #filtered==0 then
            V.muted(query=='' and '\207\238\234\224 \237\229\242 \241\238\245\240\224\237\184\237\237\251\245 \245\240\224\237\232\235\232\249.' or '\205\232\247\229\227\238 \237\229 \237\224\233\228\229\237\238.')
            return
        end
        V.list_rows('storage_library',filtered,95,function(entry,i)
            local snap=entry.snapshot
            local kind=snap.kind=='trunk'and'\193\224\227\224\230\237\232\234' or snap.kind=='cabinet'and'\216\234\224\244'
                or snap.kind=='warehouse'and'\209\234\235\224\228' or'\213\240\224\237\232\235\232\249\229'
            V.row('storage_library_'..i,95,function(rw,x,y)
                V.at(x,y)
                V.apply_font((V.font_pixels or 18)*1.12)
                V.text(V.fit(tostring(snap.title or kind),rw))
                V.apply_font()
                V.at(x,y+43)
                local value=S.evaluate(snap)
                V.muted(V.fit(kind..' \183 '..tostring(snap.count_known or 0)..' \248\242. \183 '..
                    DSP.money(value.sell_to_buyers),rw))
                V.at(x,y)
                local hit
                if imgui.InvisibleButton then
                    hit=imgui.InvisibleButton('##open_storage_card',imgui.ImVec2(rw,84))
                else
                    hit=V.text_button(tostring(snap.title or kind),'storage_open_fallback',rw,false,84)
                end
                if hit and not V.dragged then
                    V.storage_selected=entry.index
                    V.storage_library_page='detail'
                    V.reset_list('storage_items')
                end
            end)
        end,{footer=function()V.muted('\209\238\245\240\224\237\229\237\238: '..#library..' / '..tostring(S.max_saved or 20))end})
        return
    end

    local current=snapshots[V.storage_selected or 1]
    if not current or current.source=='packet220_trunk' then
        V.storage_library_page='list'
        return
    end
    if b('< \204\206\200 \213\208\192\205\200\203\200\217\192','library_back',math.min(230,width))then
        V.storage_library_page='list'
        return
    end

    V.apply_font((V.font_pixels or 18)*1.34)
    V.text(V.fit(tostring(current.title or '\193\229\231 \237\224\231\226\224\237\232\255'),width))
    V.apply_font()
    local kind=current.kind=='trunk'and'\193\224\227\224\230\237\232\234' or current.kind=='cabinet'and'\216\234\224\244'
        or current.kind=='warehouse'and'\209\234\235\224\228' or'\213\240\224\237\232\235\232\249\229'
    V.muted(kind..' \183 '..os.date('%d.%m.%Y %H:%M',current.observed_at or os.time()))

    if current.source=='packet220_trunk_named' then
        if b('\206\193\205\206\194\200\210\220 \209\202\192\205','library_update',math.min(240,width),false,true)then
            S.begin_trunk_scan(current.id)
            V.storage_tab='scan'
            V.storage_scan_mode='trunk'
            return
        end
    end
    if b('\207\229\240\229\232\236\229\237\238\226\224\242\252','rename',math.min(180,width))then
        V.storage_label_target=current
        V.storage_label_buf=imgui.new.char[128]()
        ffi.copy(V.storage_label_buf,DSP.utf8(tostring(current.title or '')):sub(1,120))
        V.storage_label_error=nil
        V.open_popup('\205\224\231\226\224\237\232\229 \241\237\232\236\234\224','storage_rename_v283')
    end
    if b('\211\196\192\203\200\210\220','delete_one',math.min(150,width))then
        V.storage_delete_target=current
        V.storage_delete_error=nil
        V.open_popup('\211\228\224\235\232\242\252 \245\240\224\237\232\235\232\249\229','storage_delete_one')
    end

    local rows,info=S.sorted(current,V.storage_sort)
    V.text('\207\240\229\228\236\229\242\238\226: '..info.total_qty..' \248\242.')
    if current.kind=='trunk' then
        V.muted('\199\224\237\255\242\238 \241\235\238\242\238\226: '..tostring(current.occupied_slots or #current.rows)..' / 180')
    elseif current.source=='packet220_probe' then
        V.red('\207\240\229\228\226\224\240\232\242\229\235\252\237\251\233 \241\237\232\236\238\234: \239\238\235\237\251\233 \244\238\240\236\224\242 \253\242\238\227\238 \245\240\224\237\232\235\232\249\224 \229\249\184 \239\240\238\226\229\240\255\229\242\241\255.')
    end
    V.green('\206\246\229\237\234\224 \241\234\243\239\234\232: '..DSP.money(info.sell_to_buyers))
    V.muted('\207\238 \238\225\250\255\226\235\229\237\232\255\236: '..DSP.money(info.ask_value)..' \183 \237\229 \247\232\241\242\224\255 \239\240\232\225\251\235\252')

    V.list_rows('storage_items',rows,82,function(it,i)
        V.row('storage_item_'..i,82,function(rw,x,y)
            V.at(x,y);V.text(V.fit(it.name,rw))
            V.at(x,y+30)
            V.muted(V.fit('\202\238\235\232\247\229\241\242\226\238: '..(it.qty and tostring(it.qty)..' \248\242.'or'\237\229\232\231\226\229\241\242\237\238'),rw))
            V.at(x,y+56)
            local total=(it.bid and it.qty)and DSP.money(it.bid*it.qty)or'\237\229\242 \238\246\229\237\234\232'
            V.muted(V.fit('\209\234\243\239\224\254\242: '..(it.bid and DSP.money(it.bid)or'?')..' / \248\242. \183 '..total,rw))
        end)
    end,{footer=false})
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
    V.popup('\207\238\245\238\230\232\233 \225\224\227\224\230\237\232\234','storage_match_confirm',function()
        local review=V.storage_match_review
        local t=S.trunk_state()
        if not review or not t.snapshot or not t.review_needed
            or review.generation~=t.review_generation then
            V.muted('\221\242\238\242 \241\234\224\237 \243\230\229 \238\225\240\224\225\238\242\224\237 \232\235\232 \231\224\236\229\237\184\237 \237\238\226\251\236.')
            if b('\199\224\234\240\251\242\252','match_stale',120)then imgui.CloseCurrentPopup()end
            return
        end
        local matches=review.matches or {}
        if #matches==0 then
            V.muted('\209\238\245\240\224\237\184\237\237\251\245 \239\238\245\238\230\232\245 \225\224\227\224\230\237\232\234\238\226 \237\229\242.')
            if b('\199\224\234\240\251\242\252','match_empty',120)then imgui.CloseCurrentPopup()end
            return
        end
        review.selected=math.max(1,math.min(#matches,review.selected or 1))
        local match=matches[review.selected]
        local saved=S.find_snapshot(match.id)
        if not saved then
            V.red('\221\242\224 \241\238\245\240\224\237\184\237\237\224\255 \231\224\239\232\241\252 \243\228\224\235\229\237\224.')
            if b('\199\224\234\240\251\242\252','match_deleted',120)then imgui.CloseCurrentPopup()end
            return
        end
        V.apply_font((V.font_pixels or 18)*1.22)
        V.text(V.fit(tostring(saved.title or '\193\224\227\224\230\237\232\234'),imgui.GetContentRegionAvail().x))
        V.apply_font()
        V.text('\221\242\238 \242\238\242 \230\229 \225\224\227\224\230\237\232\234?')
        V.green('\209\238\226\239\224\228\224\229\242 \242\232\239\238\226 \239\240\229\228\236\229\242\238\226: '..match.shared)
        V.muted('\207\238\245\238\230\229\241\242\252 \241\238\241\242\224\226\224: '..match.similarity..'% \183 \253\242\238 \205\197 \226\229\240\238\255\242\237\238\241\242\252 \232 \237\229 ID \236\224\248\232\237\251.')
        V.muted('\207\238\228\242\226\229\240\228\232\242\252, \234\224\234\224\255 \236\224\248\232\237\224 \238\242\234\240\251\242\224, \236\238\230\229\248\252 \242\238\235\252\234\238 \242\251.')
        if #matches>1 then
            V.muted('\194\224\240\232\224\237\242 '..review.selected..' \232\231 '..#matches)
            if b('\196\208\211\195\206\201 \207\206\213\206\198\200\201','match_next',math.min(230,imgui.GetContentRegionAvail().x))then
                review.selected=review.selected%#matches+1
            end
        end
        imgui.Separator()
        if b('\196\192, \221\210\206 '..tostring(saved.title),'match_yes',math.min(310,imgui.GetContentRegionAvail().x),false,true)then
            local ok,updated=S.apply_latest_to_saved(saved.id)
            if ok then
                local _,idx=S.find_snapshot(updated.id)
                V.storage_selected=idx or 1
                V.storage_library_page='detail'
                V.storage_tab='library'
                V.storage_match_error=nil
                imgui.CloseCurrentPopup()
            else
                V.storage_match_error=tostring(updated)
            end
        end
        if b('\205\197\210, \221\210\206 \205\206\194\219\201','match_no_new',math.min(280,imgui.GetContentRegionAvail().x))then
            local snap=t.snapshot
            V.storage_name_target=snap
            V.storage_name_buf=imgui.new.char[128]()
            V.storage_name_error=nil
            t.review_needed=false
            imgui.CloseCurrentPopup()
            V.open_popup('\209\238\245\240\224\237\232\242\252 \225\224\227\224\230\237\232\234','storage_trunk_name')
        end
        if b('\205\197 \211\194\197\208\197\205 \183 \207\206\199\198\197','match_later',math.min(240,imgui.GetContentRegionAvail().x))then
            imgui.CloseCurrentPopup()
        end
        if V.storage_match_error then
            V.red(V.fit(V.storage_match_error,imgui.GetContentRegionAvail().x))
        end
    end,{w=495,h=410})
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
                V.storage_tab='library'
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
    V.popup('\205\224\231\226\224\237\232\229 \241\237\232\236\234\224','storage_rename_v283',function()
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
    end,{w=640,h=300})
    V.popup('\211\228\224\235\232\242\252 \245\240\224\237\232\235\232\249\229','storage_delete_one',function()
        local target=V.storage_delete_target
        if not target then V.muted('\213\240\224\237\232\235\232\249\229 \243\230\229 \237\229 \226\251\225\240\224\237\238.');return end
        V.text('\211\228\224\235\232\242\252 \171'..tostring(target.title or '\193\229\231 \237\224\231\226\224\237\232\255')..'\187?')
        V.muted('\211\228\224\235\255\229\242\241\255 \242\238\235\252\234\238 \231\224\239\232\241\252 Palatka AI. \207\240\229\228\236\229\242\251 \226 \232\227\240\229 \237\229 \236\229\237\255\254\242\241\255.')
        if b('\211\196\192\203\200\210\220','delete_one_confirm',150,false,true)then
            local ok,err=S.delete_snapshot(target)
            if ok then
                V.storage_delete_target=nil
                V.storage_delete_error=nil
                V.storage_selected=1
                V.storage_library_page='list'
                imgui.CloseCurrentPopup()
            else V.storage_delete_error=tostring(err) end
        end
        V.inline()
        if b('\206\242\236\229\237\224','delete_one_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_delete_error then V.red(V.storage_delete_error)end
    end,{w=470,h=250})
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

  -- Read-only cabinet/warehouse observation alongside unchanged trade hooks.
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
          if V.storage_scan_mode=='inventory' then V.storage_scan_mode='trunk' end
          V.storage_scan_mode=V.storage_scan_mode or 'trunk'
          V.storage_library_page='list'
          if V.reset_list then V.reset_list('storage_scan_panel') end
        end
        return previous(id)
      end
      V._storage_screen_wrapped=true
    end
  end

  DSP.version='2.8.3'
  if DSP.flog then DSP.flog('Scanner beta v2.8.3 with settings safety; CRR rollback -> 2.7.0') end
  return true
end
