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
    local titles={cabinet='Шкаф',warehouse='Склад'}
    local now=os.time()
    local snap={id='probe_'..tostring(now)..'_'..tostring(index),
        kind=P.kind,title=titles[P.kind]..' (наблюдение; не проверено)',
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
