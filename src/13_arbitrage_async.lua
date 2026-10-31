-- Prepare cold market plans cooperatively, outside the ImGui render callback.
local M=DSP.market
local empty={}
local ready,ready_key,deadline,failed_key,working=nil,nil,0,nil,nil
local epoch=0
local invalidate=M.invalidate_arbitrage
function M.invalidate_arbitrage(...)
    epoch=epoch+1
    return invalidate(...)
end
local function signature()
    local f=DSP.settings.arb_filters or{}
    return table.concat({M.state.sid or 0,M.state.version or 0,M.state.status or '',epoch,DSP.settings.tax_bp or 200,
        f.budget or 0,f.min_profit or 0,f.min_roi or 0,f.sort or 1,f.max_age or 300,
        tostring(f.include_unknown~=false),tostring(f.allow_partial~=false),f.max_qty or 0,f.safety_pct or 0,
        f.tax_bp or 'global', f.min_unit_profit or 0, f.max_buy_price or 0,
        f.min_stock or 0, f.shop_mode or 0,M.missing_revision or 0},'|')
end
local function expiry()
    local age=math.max(0,tonumber((DSP.settings.arb_filters or{}).max_age)or 1800)
    local now,until_ts=os.time(),math.huge
    for _,record in pairs(M.missing_shops or{})do
        local d=M.missing_deadline and M.missing_deadline(record) or tonumber(record) or 0
        if d>now then until_ts=math.min(until_ts,d)end
    end
    for _,row in ipairs(M.state.rows or{})do
        for _,side in ipairs({row.sell,row.buy})do
            for _,o in ipairs(side.offers or{})do
                local ts=tonumber(o.ts)or 0
                if age>0 and ts>0 and ts+age+1>now then until_ts=math.min(until_ts,ts+age+1)end
                if ts>now+60 then until_ts=math.min(until_ts,ts-60)end
            end
        end
    end
    return until_ts
end
local cancelled={}
local function run(key)
    local owner=coroutine.running()
    local next_yield=os.clock()+.004
    local ticks=0
    local function checkpoint(force)
        ticks=ticks+1
        if not force and ticks%128~=0 then return end
        if key~=signature()then error(cancelled,0)end
        if os.clock()>=next_yield then
            wait(0);next_yield=os.clock()+.004
            if key~=signature()then error(cancelled,0)end
        end
    end
    local function sort(rows,less)
        -- A native table.sort over every candidate would still block a frame.
        local n=#rows;local chunk=512
        for first=1,n,chunk do
            local part={};local last=math.min(n,first+chunk-1)
            for i=first,last do part[#part+1]=rows[i]end
            table.sort(part,less)
            for i=first,last do rows[i]=part[i-first+1]end
            checkpoint(true)
        end
        local buffer={};local span=chunk
        while span<n do
            for first=1,n,span*2 do
                local mid=math.min(first+span,n+1);local last=math.min(first+span*2-1,n)
                local a,b=first,mid
                for i=first,last do
                    if a<mid and(b>last or not less(rows[b],rows[a]))then buffer[i]=rows[a];a=a+1
                    else buffer[i]=rows[b];b=b+1 end
                    checkpoint()
                end
                for i=first,last do rows[i]=buffer[i]end
                checkpoint(true)
            end
            span=span*2
        end
    end
    local hook={owner=owner,checkpoint=checkpoint,sort=sort}
    wait(0)
    local valid_until=expiry()
    M.arb_yield=hook
    local ok,result=pcall(function()
        checkpoint(true)
        local groups=M.arbitrage_grouped()
        checkpoint(true)
        return groups
    end)
    if M.arb_yield==hook then M.arb_yield=nil end
    working=nil
    if key~=signature()or result==cancelled or os.time()>=valid_until then return end
    if ok then ready,ready_key,deadline=result,key,valid_until;failed_key=nil;M.arb_ui_error=nil
    else
        failed_key=key;M.arb_ui_error=tostring(result)
        if DSP.flog then DSP.flog('Arbitrage prepare: '..M.arb_ui_error)end
    end
end
function M.arbitrage_grouped_ui()
    local key=signature()
    if ready and ready_key==key and os.time()<deadline then return ready,'ready'end
    if failed_key==key then return empty,'error'end
    if lua_thread and lua_thread.create and wait then
        if not working then
            working=key
            local ok,err=pcall(lua_thread.create,function()run(key)end)
            if not ok then working=nil;failed_key=key;M.arb_ui_error=tostring(err);return empty,'error'end
        end
        return empty,'loading'
    end
    -- Console/tests without the game scheduler keep the original synchronous API.
    local ok,groups=pcall(M.arbitrage_grouped)
    if not ok then failed_key=key;M.arb_ui_error=tostring(groups);return empty,'error'end
    ready,ready_key,deadline=groups,key,expiry()
    return groups,'ready'
end
