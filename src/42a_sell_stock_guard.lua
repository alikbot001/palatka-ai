-- v2.9.12: adapt the sell launch to confirmed inventory slots.
-- The user preset is a maximum; this module NEVER changes saved settings.
local A,T=DSP.auto,DSP.trade_v16
if not (A and T and type(A.start_sell)=='function' and type(T.validate)=='function')then return false end
local S=DSP.sell_stock_guard or {}
DSP.sell_stock_guard=S
if S.installed then return true end
local MAX=9007199254740991
local function positive(v)
    local n=tonumber(v)
    if n and n==n and n>0 and n<=MAX and n%1==0 then return n end
end
local function base(name)return (tostring(name or ''):gsub('%s*%(%+%d+%)%s*$',''))end
local function matches(p,inv)
    return inv.name==p.name or ((tonumber(p.ench)or 0)==0 and inv.name==base(p.name))
end
-- A broken/incomplete snapshot must NOT silently authorize a sale.
function S.plan(items,inventory)
    if type(items)~='table' or type(inventory)~='table' or #inventory==0 or A.scanning then return nil end
    local slots,owners={},{}
    for _,inv in ipairs(inventory)do
        if type(inv)~='table' or type(inv.name)~='string'
            or type(inv.stacks)~='table' or #inv.stacks==0 then return nil end
        for _,st in ipairs(inv.stacks)do
            if type(st)~='table' or type(st.slot)~='number' or st.slot<0
                or st.slot>1000 or st.slot%1~=0 then return nil end
            local n=positive(st.count)
            if not n then return nil end
            if slots[st.slot]==nil then slots[st.slot]=n;owners[st.slot]=inv.name
            elseif slots[st.slot]~=n or owners[st.slot]~=inv.name then return nil end
        end
    end
    local changes,summary={},{adjusted=0,skipped=0,requested=0,planned=0}
    for _,p in ipairs(items)do
        if type(p)~='table' then return nil end
        if p.enabled~=false and type(p.name)=='string' and p.name~='' then
            local qty,price=positive(p.qty),positive(p.price)
            -- Preserve validation of corrupt qty, price and visible edits.
            if qty and price then
                summary.requested=summary.requested+qty
                local left=qty
                for _,inv in ipairs(inventory)do
                    if left<=0 then break end
                    if matches(p,inv)then
                        for _,st in ipairs(inv.stacks)do
                            if left<=0 then break end
                            local take=math.min(slots[st.slot] or 0,left)
                            slots[st.slot]=(slots[st.slot] or 0)-take
                            left=left-take
                        end
                    end
                end
                local actual=qty-left
                summary.planned=summary.planned+actual
                if actual<qty then
                    changes[#changes+1]={row=p,qty=actual}
                    if actual==0 then summary.skipped=summary.skipped+1
                    else summary.adjusted=summary.adjusted+1 end
                end
            end
        end
    end
    return changes,summary
end
local function with_stock(fn)
    local p=DSP.settings and DSP.settings.sell_preset
    local changes,summary=S.plan(type(p)=='table' and p.items or nil,A.inv)
    -- An unverified, empty, corrupt or concurrently scanning inventory is NOT
    -- permission to launch the original sell engine with unadjusted preset qty.
    if not changes then return false,'inventory snapshot unavailable or invalid' end
    local old={}
    for i,c in ipairs(changes or {})do
        old[i]={row=c.row,qty=c.row.qty,enabled=c.row.enabled}
        if c.qty>0 then c.row.qty=c.qty else c.row.enabled=false end
    end
    -- start_sell snapshots qty/price/slot before scheduling any network worker.
    local ok,a,b,c=pcall(fn)
    for i=#old,1,-1 do
        local prev=old[i];prev.row.qty=prev.qty;prev.row.enabled=prev.enabled
    end
    return ok,a,b,c,summary
end
local validate=T.validate
T.validate=function(kind)
    if kind~='sell' then return validate(kind)end
    local ok,a,b,c=with_stock(function()return validate(kind)end)
    if not ok then
        if DSP.flog then DSP.flog('SELL validation: '..tostring(a))end
        return false,{'sell inventory validation error'},0
    end
    return a,b,c
end
if type(T.totals)=='function'then
    local totals=T.totals
    T.totals=function(kind)
        if kind~='sell' then return totals(kind)end
        local ok,result=with_stock(function()return totals(kind)end)
        if ok then return result end
        if DSP.flog then DSP.flog('SELL totals: '..tostring(result))end
        return totals(kind)
    end
end
local start=A.start_sell
A.start_sell=function(...)
    local args={...}
    local ok,result,_,_,summary=with_stock(function()return start(unpack(args))end)
    if not ok then
        if DSP.flog then DSP.flog('SELL launch: '..tostring(result))end
        if DSP.notify then DSP.notify('Sale launch failed; check log')end
        return false
    end
    if result and summary and (summary.adjusted>0 or summary.skipped>0) and DSP.add_log then
        DSP.add_log('Sale adapted to stock: '..summary.planned..' / '..summary.requested..
            '; reduced '..summary.adjusted..', absent '..summary.skipped)
    end
    return result
end
S.installed=true
return true
