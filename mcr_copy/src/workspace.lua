-- Compose optional analyzers and a separate durable manual ledger.
return function(A,E,R,P,D)
A.resale_options={min_roi_bp=1000,max_qty=10,popular_only=true}
A.purchase_state=P.new();A.book_revision=0
local invalidate,compute,load,refresh=A.invalidate,A.compute,A.load,A.refresh_market
function A.refresh_popularity(done,force)
    local h=A.host;local server,currency=h.server(),h.currency()
    if not h.fetch_popularity or not D or currency~='SA$'then done(false);return end
    local sid=h.market_server_id()
    if A.demand_pending and A.demand_pending.server==server and A.demand_pending.currency==currency then
        A.demand_pending.waiters[#A.demand_pending.waiters+1]=done;return
    end
    if not force and A.market_sales_server==server and A.market_sales_currency==currency
        and A.market_sales_at and h.now()>=A.market_sales_at and h.now()-A.market_sales_at<900 then
        h.run(function()done(true)end);return
    end
    local request={server=server,currency=currency,waiters={done}};A.demand_pending=request
    h.run(function()
        if A.demand_pending~=request or server~=h.server()or currency~=h.currency()then
            if A.demand_pending==request then A.demand_pending=nil end
            for _,callback in ipairs(request.waiters)do callback(false)end
            return
        end
        h.fetch_popularity(sid,function(pack,why)
            local current=A.demand_pending==request and server==h.server()and currency==h.currency()
            if A.demand_pending==request then A.demand_pending=nil end
            local rows
            if current and pack then rows,why=D.parse(pack,h.now(),currency,h.unique_item,h.to_cp)end
            if rows then
                A.market_sales=rows;A.market_sales_server=server;A.market_sales_currency=currency
                A.market_sales_at=h.now();A.demand_error=nil
            elseif current then A.demand_error=tostring(why or'Статистика недоступна')end
            for _,callback in ipairs(request.waiters)do callback(rows~=nil)end
            if rows and A.follow_market then A.compute()end
        end)
    end)
end
function A.refresh_market(done,force)
    A.refresh_popularity(function()end,force)
    refresh(done,force)
end
function A.invalidate()
    invalidate();A.resale_results={};A.resale_selected=nil;A.resale_details=false;A.resale_busy=false
end
function A.load_book()
    A.book_loaded=false
    local ok,raw,why=pcall(A.host.read,'purchases.json')
    if not ok or why then A.book_error='Закупки: '..tostring(why or raw);return false end
    local next_state
    if raw==nil then next_state=P.new()
    else
        local decoded,pack=pcall(A.host.decode,raw)
        if not decoded then A.book_error='Закупки JSON: '..tostring(pack);return false end
        next_state,why=P.validate(pack)
        if not next_state then A.book_error='Закупки: '..tostring(why);return false end
    end
    A.purchase_state=next_state;A.book_loaded=true;A.book_error=nil
    A.book_revision=A.book_revision+1;A.book_view_key=nil
    return true
end
function A.load()load();A.load_book()end
function A.purchases_view()
    if not A.book_loaded then return{lots={},error=A.book_error,loading=not A.book_error}end
    local h=A.host;local server,currency=h.server(),h.currency()
    local key=server..'/'..currency..'/'..A.book_revision
    if A.book_view_key~=key then
        A.book_view_key=key;A.book_cache={lots={},loading=true}
        local state=A.purchase_state
        h.run(function()
            if key~=A.book_view_key or state~=A.purchase_state then return end
            A.book_cache=P.view(state,server,currency)
        end)
    end
    return A.book_cache
end
local function record(action,params,done)
    if A.book_busy then return false,'Сохранение уже идёт'end
    if not A.book_loaded then return false,A.book_error or'Журнал ещё загружается'end
    local h=A.host;local server,currency=h.server(),h.currency()
    if server==''then return false,'Сначала подключитесь к серверу'end
    local data={};for k,v in pairs(params)do data[k]=v end
    data.server=server;data.currency=currency;data.at=h.now()
    local revision,state_before=A.book_revision,A.purchase_state
    A.book_busy=true
    h.run(function()
        local function finish(ok,value)
            A.book_busy=false;A.book_notice=ok and'Запись сохранена' or tostring(value)
            if done then done(ok,value)end
        end
        if server~=h.server()or currency~=h.currency()then finish(false,'Сервер изменился');return end
        if not A.book_loaded or revision~=A.book_revision or state_before~=A.purchase_state then
            finish(false,A.book_error or'Журнал изменился; повторите запись');return
        end
        local state,row=action(A.purchase_state,data)
        if not state then finish(false,row);return end
        local ok,raw=pcall(h.encode,state)
        if not ok then finish(false,'Не удалось подготовить запись: '..tostring(raw));return end
        local written,saved,err=pcall(h.write,'purchases.json',raw)
        if not written or not saved then finish(false,'Не удалось сохранить: '..tostring(err or saved));return end
        A.purchase_state=state;A.book_revision=A.book_revision+1;A.book_view_key=nil
        finish(true,row)
    end)
    return true
end
function A.record_purchase(params,done)
    return record(function(state,p)return P.buy(state,p)end,params,done)
end
function A.record_sale(lot_id,params,done)
    return record(function(state,p)
        local lot
        for _,row in ipairs(state.lots)do if row.id==lot_id then lot=row;break end end
        if not lot or lot.server~=p.server or lot.currency~=p.currency then return nil,'Партия другого сервера или валюты'end
        return P.sell(state,lot_id,{qty=p.qty,net_total=p.net_total,at=p.at,note=p.note})
    end,params,done)
end
function A.compute()
    compute()
    local h=A.host;local server,currency=h.server(),h.currency()
    local token,revision=A.generation,A.state.revision
    local options={};for k,v in pairs(A.resale_options)do options[k]=v end
    options.currency=currency;options.budget=A.options.budget;options.tax_bp=A.options.tax_bp;options.ttl=A.options.ttl
    options.own_sales=A.book_loaded and P.evidence(A.purchase_state,server,currency,h.now())or{}
    options.market_sales={}
    if A.market_sales_server==server and A.market_sales_currency==currency then
        for key,row in pairs(A.market_sales or{})do
            if row.valid_until>=h.now()and row.updated_at<=h.now()then options.market_sales[key]=row end
        end
    end
    A.resale_busy=true
    h.run(function()
        if token~=A.generation then return end
        if server~=h.server()or currency~=h.currency()then A.resale_busy=false;return end
        local rows,why=R.rank(A.state,server,h.now(),options,function()
            h.yield()
            return token==A.generation and server==h.server()and currency==h.currency()
        end)
        if token~=A.generation then return end
        A.resale_busy=false
        if server~=h.server()or currency~=h.currency()or revision~=A.state.revision then return end
        A.resale_results=rows;A.resale_server=server;A.resale_currency=currency
        A.resale_at=h.now();A.resale_revision=revision;A.resale_error=why
    end)
end
function A.current_resale()
    local h=A.host;local now=h.now()
    if A.resale_server~=h.server()or A.resale_currency~=h.currency()
        or A.resale_revision~=A.state.revision or not A.resale_at or now<A.resale_at
        or now-A.resale_at>A.options.ttl then return{}end
    for _,row in ipairs(A.resale_results or{})do
        if now<row.seller.at or now>(row.valid_until or row.seller.at+A.options.ttl)then return{}end
    end
    return A.resale_results or{}
end
function A.select_resale(index)
    if not A.current_resale()[index]then return false end
    A.resale_selected=index;A.resale_details=true;return true
end
function A.track_resale()
    local row=A.current_resale()[A.resale_selected]
    if not row or row.seller.server~=A.host.server()then return false end
    A.host.find(row.seller.shop,row.seller.server);return true
end
return A
end
