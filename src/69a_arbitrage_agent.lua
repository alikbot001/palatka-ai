-- Palatka Arbitrage Session: many routes, local execution ledger and a floating guide.
-- Read-only game integration: confirmation is manual, receipt matching only suggests.
-- This module never submits purchase/sale packets and never edits the remote API.
DSP.arb_agent=DSP.arb_agent or {}
local A=DSP.arb_agent
local M=DSP.market
local MAX=9007199254740991
local function num(v,lo,hi)
    local n=tonumber(v)
    if n and n==n and n%1==0 and n>=(lo or 0)and n<=(hi or MAX)then return math.floor(n)end
end
local function server()
    local detected
    if type(DSP.detect_server)=='function'then
        local ok,id=pcall(DSP.detect_server)
        if ok then detected=num(id,1)end
    end
    return detected or num(M.state and M.state.sid,1)
        or num(DSP.settings and DSP.settings.server,1)or 0
end
local function cycle_start(ts)
    local date=os.date('*t',ts or os.time())
    date.hour,date.min,date.sec=5,0,0
    local start=os.time(date)
    return(ts or os.time())<start and(start-86400)or start
end
local function part(v)
    local s=tostring(v or '')
    return tostring(#s)..':'..s
end
local function eq(a,b)
    if DSP.lower then return DSP.lower(tostring(a or''))==DSP.lower(tostring(b or''))end
    return tostring(a or''):lower()==tostring(b or''):lower()
end
local function key(sid,row,side,o)
    if not row or not o then return nil end
    local fields={sid,side,row.key or row.item_key or row.name or'',o.shop,o.owner,o.price,o.ts or 0}
    local out={}
    for i,v in ipairs(fields)do out[i]=part(v)end
    return table.concat(out,'|')
end
A.quote_key=key
A.path=(DSP.dir or '.')..'/arb_agent_v1.json'
A.data=A.data or {schema=1,session=nil,consumed={},history={}}
A.revision=A.revision or 0
A.hint=nil
local function safe_data(d)
    return type(d)=='table'and d.schema==1 and type(d.consumed)=='table'
        and type(d.history)=='table'and (d.session==nil or type(d.session)=='table')
end
function A.load()
    local f=io.open(A.path,'rb')
    if not f then return false end
    local raw=f:read('*a')or'';f:close()
    local ok,d=pcall(decodeJson,raw)
    if not ok or not safe_data(d)then return false end
    A.data=d
    if A.data.session and type(A.data.session.routes)~='table'then A.data.session=nil end
    return true
end
function A.save()
    local ok,raw=pcall(encodeJson,A.data)
    if not ok or type(raw)~='string'then return false,'encode'end
    local tmp=A.path..'.tmp'
    local f,err=io.open(tmp,'wb')
    if not f then return false,err end
    local wrote,why=f:write(raw);local closed,close_err=f:close()
    if not wrote or not closed then os.remove(tmp);return false,why or close_err or'write'end
    local renamed,rename_err=os.rename(tmp,A.path)
    if not renamed then os.remove(tmp);return false,rename_err or'rename'end
    return true
end
local function changed()
    A.revision=A.revision+1
    local ok,err=A.save()
    A.save_error=not ok and tostring(err)or nil
    if not ok and DSP.flog then DSP.flog('ARB AGENT save failed: '..tostring(err))end
    if M.invalidate_arbitrage then M.invalidate_arbitrage()end
    return ok,err
end
local function active()
    local s=A.data.session
    if not s or s.ended or s.sid~=server()
        or(num(s.started,0)or 0)<cycle_start(os.time())then return nil end
    return s
end
function A.active()return active()end
function A.is_open()
    return DSP.settings.arb_agent_open==true and active()~=nil
end
function A.show(value)
    DSP.settings.arb_agent_open=value~=false
    if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
    elseif DSP.save_settings then DSP.save_settings()end
end
function A.stop()
    local s=active()
    if not s then return false,'Нет активной сессии'end
    s.ended=os.time()
    A.show(false)
    return changed()
end
local function record_snapshot(route,sid)
    if type(route)~='table'or not route.sell_offer or not route.buy_offer
        or not route.row then return nil end
    local q=num(route.tradable_qty,1,1000000000)
    local cost=num(route.p_buy,1,MAX)
    local price=num(route.p_sell,1,MAX)
    if not q or not cost or not price or price<=cost or q*math.max(cost,price)>MAX then return nil end
    local row=route.row
    local sell=route.sell_offer
    local buy=route.buy_offer
    local cut=cycle_start(os.time())
    -- Do not requeue a previous server-day quote after the expected 05:00 restart.
    local sell_at,buy_at=num(sell.ts,1),num(buy.ts,1)
    if (sell_at and sell_at<cut)or(buy_at and buy_at<cut)then return nil end
    local sk=key(sid,row,'sell',sell)
    local bk=key(sid,row,'buy',buy)
    local ts=os.time()
    local entry={
        id='',sid=sid,name=tostring(route.name or row.display or row.name or'?'),
        item_key=tostring(row.key or''),ench=num(row.ench,0,1000)or 0,
        qty=q,bought=0,sold=0,buy_price=cost,sell_price=price,
        seller_shop=tostring(sell.shop or'?'),buyer_shop=tostring(buy.shop or'?'),
        seller_owner=tostring(sell.owner or'?'),buyer_owner=tostring(buy.owner or'?'),
        seller_quote=sk,buyer_quote=bk,
        seller_ts=num(sell.ts,0)or 0,buyer_ts=num(buy.ts,0)or 0,
        proposed_profit=num(route.net_profit,0)or 0,created=ts
    }
    entry.id=sk..'>'..bk
    return entry
end
local function route_pending(e)
    return not e.skipped and e.sold<e.qty
end
local function count_open(s)
    local n=0
    for _,e in ipairs(s.routes)do if route_pending(e)then n=n+1 end end
    return n
end
local function append_routes(routes,cap)
    local s=active()
    if not s then return 0 end
    local seen={}
    for _,e in ipairs(s.routes)do seen[e.id]=true end
    local fresh=0;local open=count_open(s)
    for _,r in ipairs(routes or{})do
        if open>=(cap or 24)or #s.routes>=250 then break end
        local entry=record_snapshot(r,s.sid)
        if entry and not seen[entry.id]then
            seen[entry.id]=true
            s.routes[#s.routes+1]=entry
            open=open+1;fresh=fresh+1
        end
    end
    if fresh>0 then changed()end
    return fresh
end
function A.start(routes)
    if server()==0 then return false,'Сервер ещё не определён'end
    local s=active()
    if not s then
        A.data.session={sid=server(),started=os.time(),routes={},focus=1,last_review=0,
            tax_bp=num(DSP.settings.tax_bp,0,10000)or 200}
    end
    local n=append_routes(routes,24)
    if n==0 and #A.data.session.routes==0 then
        A.data.session=nil
        return false,'Новых пригодных маршрутов пока нет'
    end
    A.show(true)
    return true,n
end
function A.add_plan(plan)
    local routes=plan and plan.routes
    if type(routes)~='table'or#routes==0 then return false,'В плане нет маршрутов'end
    return A.start(routes)
end
function A.start_market()
    if M.state.status=='cache'or M.state.status=='error'then
        return false,'Нет свежего рынка; проверьте API или локальный скан'
    end
    local groups,status
    if M.arbitrage_grouped_ui then groups,status=M.arbitrage_grouped_ui()
    else groups=M.arbitrage_grouped();status='ready'end
    if status~='ready'or not groups then return false,'Рынок ещё рассчитывается'end
    local routes={}
    for _,g in ipairs(groups)do for _,r in ipairs(g.routes or{})do routes[#routes+1]=r end end
    table.sort(routes,function(a,b)return(tonumber(a.net_profit)or 0)>(tonumber(b.net_profit)or 0)end)
    return A.start(routes)
end
-- A locally scanned route can join the same session if both quantities are known.
-- The local quote identity is separate from remote API identities.
function A.add_local_route(r)
    if type(r)~='table' or not num(r.qty,1,1000000000)then
        return false,'Скан не подтвердил количество с обеих сторон'
    end
    local item_key=tostring(r.id or'?')..':'..tostring(r.ench or 0)
    local row={key=item_key,display=r.name,ench=r.ench or 0}
    local sell={shop=r.seller_shop,owner=r.seller_owner,price=r.buy_price,ts=r.seller_at}
    local buy={shop=r.buyer_shop,owner=r.buyer_owner,price=r.sell_price,ts=r.buyer_at}
    local p={row=row,name=r.name,sell_offer=sell,buy_offer=buy,
        tradable_qty=r.qty,p_buy=r.buy_price,p_sell=r.sell_price,net_profit=r.profit_total or 0}
    return A.add_plan({routes={p}})
end
function A.get(index)
    local s=active()
    return s and s.routes[index],s
end
function A.focus(index)
    local s=active()
    if not s then return false end
    index=num(index,1,#s.routes)
    if not index then return false end
    s.focus=index
    A.save()
    return true
end
function A.next(step)
    local s=active()
    if not s or #s.routes==0 then return false end
    local count=#s.routes;local i=num(s.focus,1,count)or 1
    for _=1,count do
        i=((i-1+(step or 1))%count)+1
        if route_pending(s.routes[i])then return A.focus(i)end
    end
    return A.focus(i)
end
function A.stats()
    local s=active();local out={routes=0,done=0,skipped=0,bought=0,sold=0,
        pending=0,profit_estimate=0,spent_estimate=0}
    if not s then return out end
    out.routes=#s.routes
    local bp=num(s.tax_bp,0,10000)or num(DSP.settings.tax_bp,0,10000)or 200
    local factor=10000-bp
    for _,e in ipairs(s.routes)do
        local b=num(e.bought,0)or 0;local sold=num(e.sold,0)or 0
        out.bought=out.bought+b;out.sold=out.sold+sold
        if e.skipped then out.skipped=out.skipped+1
        elseif sold==e.qty then out.done=out.done+1
        else out.pending=out.pending+1 end
        -- Confirming a trade does not prove the actual receipt amount.
        -- These figures remain estimates at originally quoted prices/tax.
        local gross=sold*e.sell_price
        local revenue=math.floor(gross/10000)*factor+math.floor((gross%10000)*factor/10000)
        out.profit_estimate=out.profit_estimate+revenue-sold*e.buy_price
        out.spent_estimate=out.spent_estimate+b*e.buy_price
    end
    return out
end
local function consumed_entry(quote)
    return A.data.consumed[quote]
end
local function consume(quote,n,at)
    local c=consumed_entry(quote)or{qty=0,at=0}
    c.qty=(num(c.qty,0)or 0)+n;c.at=at
    A.data.consumed[quote]=c
end
function A.confirm(index,side,amount)
    local e,s=A.get(index)
    if not e or not s then return false,'Нет такой сделки'end
    if e.skipped then return false,'Сделка пропущена'end
    if side~='buy'and side~='sell'then return false,'Неизвестный тип'end
    local limit=side=='buy'and(e.qty-e.bought)or(e.bought-e.sold)
    local q=num(amount,1,limit)
    if not q then return false,'Количество превышает оставшийся лимит'end
    local at=os.time()
    if side=='buy'then
        e.bought=e.bought+q;e.bought_at=at
        consume(e.seller_quote,q,at)
    else
        e.sold=e.sold+q;e.sold_at=at
        consume(e.buyer_quote,q,at)
    end
    s.last_action=at
    A.data.history[#A.data.history+1]={
        session_started=s.started,route_id=e.id,side=side,qty=q,
        item=e.name,at=at,method='manual',price=side=='buy'and e.buy_price or e.sell_price
    }
    if #A.data.history>1000 then table.remove(A.data.history,1)end
    if A.hint and A.hint.route_id==e.id and A.hint.side==side then A.hint=nil end
    changed()
    if e.sold==e.qty then A.next(1)end
    return true,q
end
function A.skip(index,value)
    local e=A.get(index);if not e then return false end
    e.skipped=value~=false
    changed()
    return true
end
function A.remaining(row,side,offer,base,meta)
    local q=num(base,0)or 0
    local quote=key(server(),row,side,offer)
    local c=quote and consumed_entry(quote)
    if not c then return q,meta end
    local last=num(c.at,0)or 0
    if last<cycle_start(os.time())then return q,meta end
    -- A newer complete game observation supersedes our local bookkeeping.
    if meta and(meta.source=='recent_scan'or meta.source=='game_observed')
        and (num(meta.at,0)or 0)>last then return q,meta end
    return math.max(0,q-(num(c.qty,0)or 0)),{source='local_execution',at=last}
end
local base_offer_qty=M.offer_quantity
if type(base_offer_qty)=='function'and not A._quantity_hook then
    M.offer_quantity=function(row,side,offer,now)
        local q,meta=base_offer_qty(row,side,offer,now)
        return A.remaining(row,side,offer,q,meta)
    end
    A._quantity_hook=true
end
local function matches_receipt(entry,side,name,amount)
    if not eq(entry.name,name)or entry.skipped then return false end
    local limit=side=='buy'and(entry.qty-entry.bought)or(entry.bought-entry.sold)
    local unit=side=='buy'and entry.buy_price or entry.sell_price
    return limit>0 and amount>0 and amount%unit==0 and amount/unit<=limit
end
function A.observe_receipt(side,name,amount)
    if side~='buy'and side~='sell'then return false end
    amount=num(amount,1);if not amount then return false end
    local s=active()
    if not s then return false end
    local matched,qty=nil,nil
    for i,e in ipairs(s.routes)do
        if matches_receipt(e,side,name,amount)then
            if matched then A.hint=nil;return false end -- ambiguous
            matched=i;qty=amount/(side=='buy'and e.buy_price or e.sell_price)
        end
    end
    if matched then
        A.hint={index=matched,route_id=s.routes[matched].id,side=side,
            qty=qty,amount=amount,at=os.time()}
        return true
    end
    return false
end
local log_market=DSP.craglog and DSP.craglog.log_market
if type(log_market)=='function'and not A._receipt_hook then
    DSP.craglog.log_market=function(direction,item,amount,raw)
        local ok,err=log_market(direction,item,amount,raw)
        if ok then pcall(A.observe_receipt,direction,item,amount)end
        return ok,err
    end
    A._receipt_hook=true
end
function A.review_market()
    local s=active();if not s then return false end
    local now=os.time()
    if now-(num(s.last_review,0)or 0)<60 then return false end
    s.last_review=now
    -- 60-second review is LOCAL; it never bypasses market API backoff.
    if M.state.status~='live'then return false end
    local groups,status
    if M.arbitrage_grouped_ui then groups,status=M.arbitrage_grouped_ui()
    else groups=M.arbitrage_grouped();status='ready'end
    if status~='ready'or not groups then return false end
    local routes={}
    for _,g in ipairs(groups)do for _,r in ipairs(g.routes or{})do routes[#routes+1]=r end end
    table.sort(routes,function(a,b)return(tonumber(a.net_profit)or 0)>(tonumber(b.net_profit)or 0)end)
    return append_routes(routes,24)>0
end
function A.install()
    if A.installed then return end
    A.installed=true
    A.load()
    -- Keep a finished session available in history but never reactivate it.
    if imgui and imgui.OnFrame then
        imgui.OnFrame(A.is_open,function()
            local ok,err=xpcall(A.draw,debug.traceback)
            if not ok then
                if DSP.flog then DSP.flog('ARB AGENT UI: '..tostring(err))end
                A.show(false)
            end
        end)
    end
end
return true
