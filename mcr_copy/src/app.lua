-- Adapters and lifecycle; file access/calculation always run outside rendering.
return function(E)
local A={engine=E,state=E.new(),results={},options={tax_bp=200,budget=0,ttl=3600},
    page=1,generation=0,dirty=false,busy=false,status='Нет снимков'}
function A.install(host)A.host=host end
local function fields(row,h)
    local id=row.item_id or row.id
    if not id or tostring(id)=='' then return nil end
    return {id=tostring(id),name=tostring(row[h.fields.name] or h.name(id) or id),
        variant=tostring(row.ench or row.bonus_level or 0)..':'..tostring(row.unic_id or 0),
        currency=h.currency(),price=row[h.fields.price],qty=row[h.fields.qty]}
end
function A.invalidate()
    A.generation=A.generation+1;A.results={};A.selected=nil;A.route_details=false;A.page=1;A.busy=false
end
-- Display labels never participate in server identity or cache lookup.
function A.server_label()
    local sid=A.host.market_server_id and A.host.market_server_id()
    if sid==101 or sid==102 or sid==103 then return 'Arizona Mobile '..(sid-100)end
    local name=A.host.server_name and A.host.server_name()or ''
    name=tostring(name):gsub('{%x%x%x%x%x%x}',''):gsub('[%c]',' ')
    if name==''or name:find('[/\\]')or name:find('://',1,true)then return 'Текущий сервер'end
    return name
end
function A.select_route(index)
    if not A.current_results()[index]then return false end
    A.selected=index;A.route_details=true;return true
end
function A.selected_route()return A.current_results()[A.selected]end
function A.track_selected(side)
    local route=A.selected_route()
    if not route then A.error='Выберите актуальный маршрут';return false end
    local shop=side=='buy'and route.seller or side=='sell'and route.buyer
    if not shop or shop.server~=A.host.server()then return false end
    A.host.find(shop.shop,shop.server);return true
end
function A.capture(snapshot)
    local h=A.host
    if type(snapshot)~='table' then return false,'invalid snapshot'end
    local server=h.server()
    if snapshot.ip_server and snapshot.ip_server~='' and h.normalize_server then
        local reported=h.normalize_server(snapshot.ip_server)
        if reported~=server then return false,'snapshot from different server'end
    end
    local s={shop=snapshot.shop_num,owner=snapshot.owner,server=server,
        at=snapshot.scanned_at or h.now(),source='local',sell={},buy={}}
    for _,p in ipairs({{'sell_items','sell'},{'buy_items','buy'}})do
        if snapshot[p[1]]~=nil and type(snapshot[p[1]])~='table'then return false,'invalid side'end
        for _,row in ipairs(snapshot[p[1]] or{})do
            if type(row)~='table'then return false,'invalid item'end
            local r=fields(row,h)
            if not r then return false,'missing item id'end
            s[p[2]][#s[p[2]]+1]=r
        end
    end
    local ok,err=E.observe(A.state,s)
    if ok then A.dirty=true;A.invalidate();A.status='Снимок лавки сохранён в память' end
    if ok and not A.save_pending then
        A.save_pending=true
        h.run(function()A.save_pending=false;A.flush()end)
    end
    return ok,err
end
function A.capture_external(data)
    if type(data)~='table' or type(data.shop)~='table' or type(data.items)~='table'then return false end
    local h=A.host;local shop=data.shop
    local server=shop.server
    if server==nil then return false,'unknown server'end
    local s={shop=shop.shop_id,owner=shop.nickname,server=tostring(server),
        at=tonumber(shop.ostime or shop.updated_at),source='mcr-cloud',sell={},buy={}}
    if not s.at then return false,'unknown quote time'end
    for _,row in ipairs(data.items)do
        local side=row.item_type=='sell' and'sell'or row.item_type=='buy'and'buy'
        if not side then return false,'unknown side'end
        if not row.item_id then return false,'missing item id'end
        s[side][#s[side]+1]={id=tostring(row.item_id),name=row.item_name,
            variant=tostring(row.bonus_level or 0)..':'..tostring(row.embedded_item_id or 0),
            currency=row.currency or h.currency(),price=row.price,qty=row.quantity}
    end
    return A.import({schema=1,shops={s}})
end
function A.import(pack)
    if type(pack)~='table' or pack.schema~=1 or type(pack.shops)~='table'then
        return false,'ожидается schema=1, shops=[]'
    end
    -- Validate every record before publishing any changes.
    local next_state=E.new()
    for key,value in pairs(A.state.shops)do next_state.shops[key]=value end
    next_state.revision=A.state.revision
    for _,s in ipairs(pack.shops)do
        local ok,err=E.observe(next_state,s)
        if not ok then return false,err end
    end
    A.state=next_state;A.dirty=true;A.invalidate();A.status='Внешние снимки добавлены'
    return true
end
function A.flush()
    if not A.dirty then return true end
    local shops={};for _,s in pairs(A.state.shops)do shops[#shops+1]=s end
    local ok,data=pcall(A.host.encode,{schema=1,shops=shops})
    if not ok then A.error=tostring(data);return false,A.error end
    local saved,err=A.host.write('market.json',data)
    if not saved then A.error='Сохранение: '..tostring(err);return false,A.error end
    A.dirty=false;return true
end
function A.read_import()
    A.host.run(function()
        local raw,err=A.host.read('import.json')
        if not raw then A.error='Импорт: '..tostring(err or 'нет файла import.json');return end
        local ok,pack=pcall(A.host.decode,raw)
        if not ok then A.error='JSON: '..tostring(pack);return end
        local imported,why=A.import(pack)
        if not imported then A.error='Импорт: '..tostring(why);return end
        A.error=nil;A.flush()
    end)
end
function A.read_market_cache()
    A.host.run(function()
        local server=A.host.server()
        local sid=A.host.market_server_id()
        if not sid then A.error='Мобильный сервер не определён';return end
        local raw,err=A.host.read_market_cache(sid)
        if not raw then A.error='Кэш рынка: '..tostring(err or 'нет сохранённой базы');return end
        local ok,data=pcall(A.host.decode,raw)
        if not ok then A.error='Кэш рынка JSON: '..tostring(data);return end
        if type(data)=='table'and type(data.body)=='string'then
            ok,data=pcall(A.host.decode,data.body)
            if not ok then A.error='Ответ рынка JSON: '..tostring(data);return end
        end
        if server~=A.host.server()then A.error='Сервер изменился';return end
        local pack=A.external.vata(data,sid,server,A.host.currency(),A.host.to_cp)
        if #pack.shops==0 then A.error='В кэше нет полных снимков этого сервера';return end
        local imported,why=A.import(pack)
        if not imported then A.error=tostring(why);return end
        A.status='Импортировано лавок: '..#pack.shops;A.error=nil;A.flush()
    end)
end
function A.load()
    local raw,err=A.host.read('market.json')
    if not raw then if err then A.error=tostring(err)end;return end
    local ok,pack=pcall(A.host.decode,raw)
    if not ok then A.error='Локальная база JSON: '..tostring(pack);return end
    local imported,why=A.import(pack)
    if not imported then A.error='Локальная база: '..tostring(why)end
end
function A.calculate()
    A.invalidate();A.busy=true;A.error=nil
    local token=A.generation;local revision=A.state.revision;local server=A.host.server()
    local options={};for k,v in pairs(A.options)do options[k]=v end
    A.host.run(function()
        local rows,err=E.routes(A.state,server,A.host.now(),options,function()
            A.host.yield()
        end)
        if token~=A.generation then return end
        A.busy=false
        if server~=A.host.server() or revision~=A.state.revision then
            A.status='Данные изменились — рассчитайте заново';return
        end
        A.results=rows;A.result_server=server;A.result_at=A.host.now()
        A.status='Маршрутов: '..#rows
        if err then A.error=err end
        A.flush()
    end)
end
function A.start()
    if A.started then return end;A.started=true
    A.host.register('parb',A.host.open)
    A.host.run(function()A.load()end)
end
function A.current_results()
    if A.result_server~=A.host.server() or A.result_at and A.host.now()-A.result_at>A.options.ttl then
        return{}
    end
    -- A quote can expire before the calculation as a whole does.
    for _,r in ipairs(A.results)do
        local now=A.host.now()
        if now-r.seller.at>A.options.ttl or now-r.buyer.at>A.options.ttl then return{}end
    end
    return A.results
end
return A
end
