-- Bind local/public read models to the original MCR views. Never impersonate
-- MCR HTTP responses: these statuses describe locally computed view data.
(function()
local A=PalatkaMCR
local P=A.market
local active_price_name
local choice_cache
local generations=setmetatable({},{__mode='k'})
local pending_states=setmetatable({},{__mode='k'})
local function advance(view)
    generations[view]=(generations[view]or 0)+1
    return generations[view]
end
local function reject(state,message)
    advance(state);lIl_l__l(state,listStatusResponses.FAILURE,message)
end
local function selected(name,selector)
    local saved=A.price_identity
    if not selector and saved and saved.server==A.host.server()and saved.selector.currency==A.host.currency()
        and P.same_name(saved.name,name)then return saved.selector end
    return selector
end
local function is_match(row,name,selector)
    return(P.same_name(row.name,name)or P.same_name(row.lookup_name or row.name,name))and row.currency==A.host.currency()
        and(not selector or tostring(selector.id)==row.id and selector.variant==row.variant and selector.currency==row.currency)
end
local function shops()
    return P.shops(A.state,A.host.server(),A.host.now(),A.options.ttl)
end
local function same_server(server)
    if server==nil or server==''then return true end
    if tostring(server)==A.host.server()then return true end
    local sid=A.host.market_server_id and A.host.market_server_id()
    if sid and tonumber(server)==sid then return true end
    return A.host.normalize_server and A.host.normalize_server(server)==A.host.server()or false
end
local function read(state,build,view,failed)
    view=view or state
    local previous=pending_states[view]
    if previous and previous~=state and previous.status==listStatusResponses.WAIT then
        lIl_l__l(previous,listStatusResponses.FAILURE,'Запрос заменён')
    end
    pending_states[view]=state
    local token=advance(view)
    lIl_l__l(state,listStatusResponses.WAIT)
    local server=A.host.server()
    A.refresh_market(function(ok,err)
        if generations[view]~=token then return end
        local function failure(message)
            lIl_l__l(state,listStatusResponses.FAILURE,message)
            if failed then failed(message)end
        end
        if server~=A.host.server()then
            failure('Сервер изменился');return
        end
        local data=shops()
        if not ok and #data==0 then
            failure('База Market Helper: '..tostring(err));return
        end
        local result,why=build(data)
        if not result then failure(why);return end
        state.source='Market Helper / локальные снимки';state.time=A.host.now()
        lIl_l__l(state,listStatusResponses.SUCCESS,result)
    end)
end
local function item(o,side)
    local name=P.title(o)
    if o.embedded_item_id and o.variant and o.variant:match('^%d+:%d+$')then
        name=lI_IIllI(o.name,o.bonus_level or 0)
    end
    return{item_id=tonumber(o.id),item_name=name,quantity=o.qty,price=o.price,
        item_type=side,bonus_level=o.bonus_level,variant=o.variant,currency=o.currency,
        embedded_item_id=o.embedded_item_id,
        embedded_item_text=o.embedded_item_id and lI_IIlII(o.embedded_item_id)or nil}
end
local function shop(s,query)
    local out={shop_id=s.shop,nickname=s.owner,nickname_label=s.owner,
        server=s.server,server_name=A.server_label(),source=s.source,updated_at=s.at,
        updated_at_text='Market Helper / скан | '..math.max(0,A.host.now()-s.at)..' с',
        sell_count=#s.sell,buy_count=#s.buy,items={}}
    for _,side in ipairs({'sell','buy'})do
        for _,o in ipairs(s[side])do
            local name=P.title(o)
            if o.qty and(not query or string.rlower(name):find(string.rlower(query),1,true))then
                out.items[#out.items+1]=item(o,side)
            end
        end
    end
    return out
end
function lI_II_I_(server)
    if not same_server(server)then reject(i,'Выберите текущий мобильный сервер');return end
    read(i,function(data)
        local out={};for _,s in ipairs(data)do out[#out+1]=shop(s)end
        return{count=#out,shops=out}
    end)
end
function lI_II_ll(query,server)
    if not same_server(server)then reject(X,'Выберите текущий мобильный сервер');return end
    query=tostring(query or'')
    read(X,function(data)
        local out={}
        for _,s in ipairs(data)do
            local row=shop(s,query)
            if #row.items>0 then out[#out+1]=row end
        end
        return{count=#out,shops=out}
    end)
end
function lI_II_lI(number,server)
    if tostring(server)~=A.host.server()then
        reject(V,'Выберите лавку текущего сервера');return
    end
    read(V,function(data)
        for _,s in ipairs(data)do
            if s.shop==tonumber(number)then
                local row=shop(s);return{shop=row,items=row.items}
            end
        end
        return{shop={shop_id=number,nickname='Нет свежего снимка'},items={}}
    end)
end
function lI_II___(vc)
    vc=vc==nil and lI__ll__()or vc
    local state=lII_llll(vc)
    if vc~=(A.host.currency()=='VC$')then
        reject(state,'Доступны снимки текущего мобильного сервера');return
    end
    state.server=lI__l_Il(vc)
    read(state,function(data)
        local out={}
        for _,s in ipairs(data)do
            local row={LavkaUid=s.shop,username=u8(s.owner),serverId=s.server,
                items_sell={},count_sell={},price_sell={},items_buy={},count_buy={},price_buy={}}
            for _,side in ipairs({'sell','buy'})do
                for _,o in ipairs(s[side])do
                    if o.qty then
                        local n=#row['items_'..side]+1
                        row['items_'..side][n]=u8(P.title(o))
                        row['count_'..side][n]=o.qty;row['price_'..side][n]=o.price
                    end
                end
            end
            out[#out+1]=row
        end
        return out
    end)
end
local function price_table(query,start)
    local state=query and h6 or r6
    x6.requested=true;x6.isSearchMode=query~=nil;x6.lastQuery=query or''
    read(state,function(data)
        local all=P.prices(data);local filtered={}
        for _,r in ipairs(all)do
            if not query or string.rlower(r.name):find(string.rlower(query),1,true)then filtered[#filtered+1]=r end
        end
        start=math.max(1,tonumber(start)or 1)
        local limit=math.max(1,math.min(100,tonumber(x6.pageLimit)or 100))
        local rows={{row_number=3,values={u8('Предмет'),u8('Валюта'),u8('Продажа, средняя'),
            u8('Скупка, средняя'),u8('Продажа, шт.'),u8('Скупка, шт.'),'ID',u8('Модификация')}}}
        for n=start,math.min(#filtered,start+limit-1)do
            local r=filtered[n]
            rows[#rows+1]={row_number=n+4,values={u8(r.name),r.currency,
                r.sell.avg and lI______(r.sell.avg)or'-',r.buy.avg and lI______(r.buy.avg)or'-',
                r.sell.offers>0 and r.sell.qty==0 and'?'or tostring(r.sell.qty),
                r.buy.offers>0 and r.buy.qty==0 and'?'or tostring(r.buy.qty),r.id,r.variant or'?'}}
        end
        x6.startRow=start;x6.pageLimit=limit;x6.returnedRows=#rows-1;x6.totalRows=#filtered
        if query then x6.searchRows=rows;x6.totalFound=#filtered else x6.rows=rows end
        llIIIlll(rows);llIIIl_l(rows)
        avgPriceTableInfoText=u8('Средние цены объявлений Market Helper и своих сканов. Текущий сервер, свежесть до 1 часа. Это не история сделок.')
        return{rows=rows,total_rows=#filtered}
    end,x6)
end
function llIIllll(start)price_table(nil,start)end
function llIIlll_(query)
    query=tostring(query or'');if query==''then price_table(nil,1)else price_table(query,1)end
end
function llIIll__()if not x6.requested then llIIllll(1)end end
function lIl_IIlI(name,vc,selector)
    active_price_name=name;selector=selected(name,selector)
    stateAvgPriceLavok.nameItem=name
    if (vc==true)~=(A.host.currency()=='VC$')then
        reject(stateAvgPriceLavok,'Выберите текущий мобильный сервер');return
    end
    read(stateAvgPriceLavok,function(data)
        local match
        for _,r in ipairs(P.prices(data))do
            if is_match(r,name,selector)then
                if match then return nil,'Выберите ID и модификацию товара кнопкой над ценами'end
                match=r
            end
        end
        if not match then return nil,'Нет свежих снимков этого товара'end
        if match.sell.overflow or match.buy.overflow then return nil,'Сумма цен объявлений превышает точный числовой предел'end
        local out={}
        for _,s in ipairs(data)do
            local row={username=u8(s.owner),LavkaUid=s.shop,serverId=s.server,itemsSell={},itemsBuy={}}
            for _,side in ipairs({'sell','buy'})do
                for _,o in ipairs(s[side])do
                    if o.id==match.id and o.variant==match.variant and o.qty and o.currency==match.currency then
                        local target=side=='sell'and row.itemsSell or row.itemsBuy
                        target[#target+1]={name=u8(P.title(o)),price=o.price,count=o.qty}
                    end
                end
            end
            if #row.itemsSell+#row.itemsBuy>0 then out[#out+1]=row end
        end
        stateAvgPriceLavok.avg_sell_price=match.sell.avg or 0
        stateAvgPriceLavok.avg_buy_price=match.buy.avg or 0
        return out
    end)
end
lIl_III_=lIl_IIlI
function lIl___Il(name,approved,server,selector)
    active_price_name=name;selector=selected(name,selector)
    Y6.status='wait';Y6.nameItem=name
    if not same_server(server)then advance(Y6);Y6.status='false';Y6.result='Цены доступны для текущего мобильного сервера';return end
    local state={}
    read(state,function(data)
        local result={sell_data={},buy_data={}}
        local matches={}
        for _,r in ipairs(P.prices(data))do
            if is_match(r,name,selector)then matches[#matches+1]=r end
        end
        if #matches~=1 then
            Y6.status='false';Y6.result=#matches==0 and'Нет свежих снимков этого товара' or'Выберите ID и модификацию товара кнопкой над ценами'
            return result
        end
        if matches[1].sell.overflow or matches[1].buy.overflow then
            return nil,'Сумма цен объявлений превышает точный числовой предел'
        end
        for _,r in ipairs(matches)do
            for _,side in ipairs({'sell','buy'})do
                if r[side].avg then
                    result[side..'_data'][#result[side..'_data']+1]={date=os.date('%Y-%m-%d'),
                        avg_price=r[side].avg,total_quantity=r[side].qty,total_value=r[side].sum,
                        source='asking-price'}
                end
            end
        end
        Y6.status='true';Y6.result=result
        return result
    end,Y6,function(message)Y6.status='false';Y6.result=message end)
end
function A.draw_price_identity_selector()
    if not active_price_name then return end
    local server,currency,now=A.host.server(),A.host.currency(),A.host.now()
    local cached=choice_cache
    if not cached or cached.state~=A.state or cached.revision~=A.state.revision
        or cached.server~=server or cached.currency~=currency or cached.name~=active_price_name
        or now<cached.at or now>=cached.expires then
        cached={state=A.state,revision=A.state.revision,server=server,currency=currency,
            name=active_price_name,at=now,expires=now+A.options.ttl,choices={}}
        choice_cache=cached
        -- Price windows render every frame; compute choices only in the host worker.
        A.host.run(function()
            if choice_cache~=cached or A.host.server()~=server or A.host.currency()~=currency
                or A.state~=cached.state or A.state.revision~=cached.revision then return end
            local data=shops()
            for _,s in ipairs(data)do cached.expires=math.min(cached.expires,s.at+A.options.ttl+1)end
            for _,row in ipairs(P.prices(data))do
                if is_match(row,cached.name)then cached.choices[#cached.choices+1]=row end
            end
            cached.ready=true
        end)
    end
    if not cached.ready then return end
    local choices=cached.choices
    if #choices<2 then
        local saved=selected(active_price_name)
        if #choices==0 or not saved or is_match(choices[1],active_price_name,saved)then return end
    end
    local B=A.host.imgui
    B.TextWrapped(u8('Выберите товар: ID / модификация / валюта'))
    for _,row in ipairs(choices)do
        local label='#'..row.id..' | '..tostring(row.variant or'?')..' | '..row.currency
        if B.Button(u8(label))and(not A.host.can_click or A.host.can_click())then
            local selector={id=row.id,variant=row.variant,currency=row.currency}
            A.price_identity={name=active_price_name,server=A.host.server(),selector=selector}
            lIl_IIlI(active_price_name,A.host.currency()=='VC$',selector)
            lIl___Il(active_price_name,nil,nil,selector)
        end
    end
end
end)()
