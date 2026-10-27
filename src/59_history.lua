-- Full history for the main journal; the floating overlay keeps its bounded ring.
local C=DSP.craglog
C.history_revision=C.history_revision or 0
if not C._history_hooks then
    local push=C.ring_push
    C.ring_push=function(e)
        local result=push(e)
        C.history_revision=C.history_revision+1
        return result
    end
    local observe=C.observe_payday
    if observe then
        C.observe_payday=function(text)
            local accepted=observe(text)
            if accepted then C.history_revision=C.history_revision+1 end
            return accepted
        end
    end
    C._history_hooks=true
end
function C.category(e)
    if e.type=='payday' or e.kind=='payday' then return 'payday' end
    if e.type=='market' then return e.direction=='sell' and 'sales' or 'buys' end
    if e.kind=='income' or e.type=='income' or e.kind=='cash' then return 'income' end
    if e.kind=='item' or e.kind=='opening' or e.kind=='unknown' or e.type=='crate' then return 'loot' end
    if (tonumber(e.money_get) or 0)>0 and (tonumber(e.money_give) or 0)==0 then return 'sales' end
    if (tonumber(e.money_give) or 0)>0 and (tonumber(e.money_get) or 0)==0 then return 'buys' end
    return 'other'
end
local signature,rows,search_cache,search_keys=nil,{},{},{}
local function current_signature()
    return table.concat({C.history_revision,DSP.logs and DSP.logs.revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,C.visibility_revision or 0},':')
end
local function copy(e)
    local out={}
    for key,value in pairs(e) do out[key]=value end
    if e.details then
        out.details={}
        for i,part in ipairs(e.details) do out.details[i]=part end
    end
    if (out.type=='payday' or out.kind=='payday') and DSP.payday_restore then DSP.payday_restore(out) end
    return out
end
local function visible(e)
    return not C.event_visible or C.event_visible(e)
end
local function rebuild()
    rows,search_cache,search_keys={},{},{}
    local by_key,markers,patches={},{},{}
    C.history_error=nil;C.history_corrupt_lines=0
    local function add(e)
        if type(e)~='table' or e.kind=='association' or e.type=='journal_deleted' or not visible(e) then return end
        if e.type=='payday_detail' then patches[#patches+1]=e;return end
        local row=copy(e);local key=C.event_key(row)
        if by_key[key] then rows[by_key[key]]=row
        else rows[#rows+1]=row;by_key[key]=#rows end
    end
    local f,err=io.open(DSP.events_log_path,'r')
    if f then
        for line in f:lines() do
            if line~='' then
                local ok,e=pcall(decodeJson,line)
                if ok and type(e)=='table' and (e.type or e.kind) then add(e)
                else C.history_corrupt_lines=C.history_corrupt_lines+1 end
            end
        end
        f:close()
    elseif err then
        -- A fresh install has no event file yet; existing sources still remain available.
        C.history_error=err
    end
    for _,trade in pairs(DSP.settings.trades or {}) do add(trade) end
    if DSP.rewards and DSP.rewards.query then
        local page=1
        repeat
            local result=DSP.rewards.query({page=page,page_size=200})
            for _,e in ipairs(result.entries) do add(e) end
            if result.error then C.history_error=result.error end
            page=page+1
        until page>result.pages
    end
    for _,e in ipairs(rows) do
        if (e.type=='payday' or e.kind=='payday') and e.id then markers[e.id]=e end
    end
    for _,patch in ipairs(patches) do
        local parent,part=markers[patch.payday_id],patch.detail
        if parent and part and (part.direction=='income' or part.direction=='expense' or part.direction=='meta') then
            parent.details=parent.details or {};local duplicate=false
            for _,old in ipairs(parent.details) do
                if old.raw==part.raw and old.amount==part.amount and old.direction==part.direction then duplicate=true;break end
            end
            if not duplicate then
                parent.details[#parent.details+1]=part
                local incoming,outgoing=part.direction=='income' and (tonumber(part.amount) or 0) or 0,part.direction=='expense' and (tonumber(part.amount) or 0) or 0
                if DSP.payday_contribution then incoming,outgoing=DSP.payday_contribution(part) end
                parent.income,parent.expense=(parent.income or 0)+incoming,(parent.expense or 0)+outgoing
                parent.amount=(parent.income or 0)-(parent.expense or 0)
            end
        end
    end
    table.sort(rows,function(a,b)
        local at,bt=tonumber(a.ts) or 0,tonumber(b.ts) or 0
        if at~=bt then return at>bt end
        local aq,bq=tonumber(a.seq) or 0,tonumber(b.seq) or 0
        if aq~=bq then return aq>bq end
        return C.event_key(a)<C.event_key(b)
    end)
    signature=current_signature()
end
local function haystack(e)
    local parts={C.describe(e),e.raw or '',e.item_name or e.item or '',e.source or '',e.partner or '',e.label or ''}
    for _,part in ipairs(e.details or {}) do parts[#parts+1]=part.raw or '' end
    for _,side in ipairs({'items_get','items_give'}) do
        for _,item in ipairs(e[side] or {}) do parts[#parts+1]=item.name or '' end
    end
    return (DSP.lower or string.lower)(table.concat(parts,' '))
end
function C.history(filter,query)
    if signature~=current_signature() then rebuild() end
    filter=filter or 'all';query=(DSP.lower or string.lower)(tostring(query or ''))
    local key=tostring(#filter)..':'..filter..':'..query
    if search_cache[key] then return search_cache[key] end
    local result={}
    for _,e in ipairs(rows) do
        local matches=filter=='all' or C.category(e)==filter or (filter=='loot' and e.kind=='cash')
        if matches and (query=='' or haystack(e):find(query,1,true)) then result[#result+1]=e end
    end
    search_cache[key]=result;search_keys[#search_keys+1]=key
    if #search_keys>8 then search_cache[table.remove(search_keys,1)]=nil end
    return result
end
return true
