-- Passive native pawnshop menu inspection. The packet layout is NOT
-- verified against a real pawnshop dump; all entries are observational only.
local L=DSP.lombard
if not L then return false end
local P={active=false,status='idle',until_ts=0,packets=0,tagged=0,
    ignored=0,candidates={},items={},order={},verified_label=false}
L.packet_probe=P
local MAX_BYTES,MAX_ROWS,MAX_CANDIDATES=100000,180,12
local function int(v,cap)
    local n=tonumber(v)
    if n and n==n and n>=0 and n<=cap and n%1==0 then return n end
end
local function lower(s)
    s=tostring(s or '')
    return DSP.lower and DSP.lower(s) or s:lower()
end
local function pawn_text(s)
    s=lower(s)
    return s:find('\xeb\xee\xec\xe1\xe0\xf0\xe4',1,true)~=nil
        or s:find('\208\187\208\190\208\188\208\177\208\176\209\128\208\180',1,true)~=nil
        or s:find('pawnshop',1,true)~=nil or s:find('pawn',1,true)~=nil
end
function P.arm(seconds)
    local duration=int(seconds or 35,60) or 35
    if duration<5 then duration=35 end
    P.active=true;P.status='listening';P.until_ts=os.time()+duration
    P.packets=0;P.tagged=0;P.ignored=0;P.candidates={};P.items={};P.order={}
    P.verified_label=false
    return true
end
function P.stop()
    P.active=false;P.status='review';return true
end
function P.state()
    if P.active and os.time()>P.until_ts then P.stop() end
    return P
end
local function has_known_game_name(item)
    return type(item)=='table' and type(item.name)=='string' and item.name~=''
end
local function recognize(item,index,tag)
    if type(item)~='table' then return nil end
    local explicit_price=int(item.price or item.cost or item.unit_price or item.unitPrice,9007199254740991)
    if not explicit_price or explicit_price<1 then return nil end
    local row
    if DSP.item_registry and DSP.item_registry.from_node then
        local ok,value=pcall(DSP.item_registry.from_node,item,'buy',index)
        if ok and value then row=value end
    end
    if not row and has_known_game_name(item) and L.parse_dialog then
        local lines=L.parse_dialog(tag or '',item.name..'\t'..tostring(explicit_price))
        row=lines[1]
    end
    if not row then return nil end
    row.side='buy'
    row.price=explicit_price
    return row
end
local function nodes(obj)
    if type(obj)~='table' then return nil end
    if type(obj.items)=='table' then return obj.items end
    if type(obj.rows)=='table' then return obj.rows end
    if type(obj.data)=='table' then
        if type(obj.data.items)=='table' then return obj.data.items end
        if type(obj.data.rows)=='table' then return obj.data.rows end
    end
end
function L.on_packet(iface,sub,raw)
    local active=P.state().active
    if type(raw)~='string' or #raw<2 or #raw>MAX_BYTES then return false end
    -- A labeled pawnshop packet may be observed passively. Unknown packet
    -- layouts are explored only during the explicit 35-second scan window.
    if not active and not pawn_text(raw) then return false end
    local ok,obj=pcall(decodeJson,raw:gsub('%z+$',''))
    if not ok or type(obj)~='table' then return false end
    local packet_type=int(obj.type,255)
    if packet_type==8 or packet_type==13 or packet_type==28 or
        (packet_type==1 and tonumber(sub)==2) or tonumber(iface)==57 then
        P.ignored=P.ignored+1;return false
    end
    local label=tostring(obj.title or obj.header or obj.caption or obj.name or
        (type(obj.data)=='table' and obj.data.title) or '')
    local labeled=pawn_text(label)
    if not active and not labeled then return false end
    local slot_list=nodes(obj)
    if not slot_list then
        if active then
            P.packets=P.packets+1
            if #P.candidates<MAX_CANDIDATES then
                P.candidates[#P.candidates+1]={iface=tonumber(iface),sub=tonumber(sub),
                    type=packet_type,rows=0,label=labeled}
            end
        end
        return false
    end
    if #slot_list>MAX_ROWS then return false end
    P.packets=P.packets+1
    if labeled then P.tagged=P.tagged+1;P.verified_label=true end
    local accepted=0
    for i,item in ipairs(slot_list)do
        local row=recognize(item,i,label)
        if row then
            local key=tostring(row.key or row.name)..':'..tostring(row.price)
            if not P.items[key] then P.order[#P.order+1]=key end
            P.items[key]=row;accepted=accepted+1
        end
    end
    if #P.candidates<MAX_CANDIDATES then
        P.candidates[#P.candidates+1]={iface=tonumber(iface),sub=tonumber(sub),
            type=packet_type,rows=accepted,label=labeled}
    end
    -- Never write any native observation automatically: the server has not
    -- supplied a proven end-of-list marker or stable pawnshop session ID.
    if accepted>0 then P.status='preview_ready' end
    return accepted>0
end
function P.preview()
    local rows={}
    for _,key in ipairs(P.order)do
        local row=P.items[key]
        if row then rows[#rows+1]=row end
    end
    return rows
end
function P.save()
    if P.state().active then return false,'stop the scan first' end
    local rows=P.preview()
    if #rows==0 then return false,'no recognized priced items' end
    if not L.save_observation then return false,'pawnshop store unavailable' end
    local ok,result=L.save_observation(rows,'packet_unverified')
    if ok then P.status='saved_unverified' end
    return ok,result
end
function P.report()
    -- Metadata only; never include names, IDs, raw JSON or account data.
    local candidates={}
    for _,c in ipairs(P.candidates)do
        candidates[#candidates+1]={iface=c.iface,sub=c.sub,
            type=c.type,rows=c.rows,labeled=c.label}
    end
    return {schema=1,packets=P.packets,tagged=P.tagged,ignored=P.ignored,
        candidates=candidates}
end
return true
