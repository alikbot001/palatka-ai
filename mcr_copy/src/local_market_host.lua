-- Bind local/public read models to the original MCR views. Never impersonate
-- MCR HTTP responses: these statuses describe locally computed view data.
(function()
local A=PalatkaMCR
local P=A.market
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
local function read(state,build)
    lIl_l__l(state,listStatusResponses.WAIT)
    local server=A.host.server()
    A.refresh_market(function(ok,err)
        if server~=A.host.server()then
            lIl_l__l(state,listStatusResponses.FAILURE,'Сервер изменился');return
        end
        local data=shops()
        if not ok and #data==0 then
            lIl_l__l(state,listStatusResponses.FAILURE,'База Market Helper: '..tostring(err));return
        end
        local result,why=build(data)
        if not result then lIl_l__l(state,listStatusResponses.FAILURE,why);return end
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
    if not same_server(server)then lIl_l__l(i,listStatusResponses.FAILURE,'Выберите текущий мобильный сервер');return end
    read(i,function(data)
        local out={};for _,s in ipairs(data)do out[#out+1]=shop(s)end
        return{count=#out,shops=out}
    end)
end
function lI_II_ll(query,server)
    if not same_server(server)then lIl_l__l(X,listStatusResponses.FAILURE,'Выберите текущий мобильный сервер');return end
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
        lIl_l__l(V,listStatusResponses.FAILURE,'Выберите лавку текущего сервера');return
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
        lIl_l__l(state,listStatusResponses.FAILURE,'Доступны снимки текущего мобильного сервера');return
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
            u8('Скупка, средняя'),u8('Продажа, шт.'),u8('Скупка, шт.')}}}
        for n=start,math.min(#filtered,start+limit-1)do
            local r=filtered[n]
            rows[#rows+1]={row_number=n+4,values={u8(r.name),r.currency,
                r.sell.avg and lI______(r.sell.avg)or'-',r.buy.avg and lI______(r.buy.avg)or'-',
                r.sell.offers>0 and r.sell.qty==0 and'?'or tostring(r.sell.qty),
                r.buy.offers>0 and r.buy.qty==0 and'?'or tostring(r.buy.qty)}}
        end
        x6.startRow=start;x6.pageLimit=limit;x6.returnedRows=#rows-1;x6.totalRows=#filtered
        if query then x6.searchRows=rows;x6.totalFound=#filtered else x6.rows=rows end
        llIIIlll(rows);llIIIl_l(rows)
        avgPriceTableInfoText=u8('Средние цены объявлений Market Helper и своих сканов. Текущий сервер, свежесть до 1 часа. Это не история сделок.')
        return{rows=rows,total_rows=#filtered}
    end)
end
function llIIllll(start)price_table(nil,start)end
function llIIlll_(query)
    query=tostring(query or'');if query==''then price_table(nil,1)else price_table(query,1)end
end
function llIIll__()if not x6.requested then llIIllll(1)end end
function lIl_IIlI(name,vc)
    stateAvgPriceLavok.nameItem=name
    if (vc==true)~=(A.host.currency()=='VC$')then
        lIl_l__l(stateAvgPriceLavok,listStatusResponses.FAILURE,'Выберите текущий мобильный сервер');return
    end
    read(stateAvgPriceLavok,function(data)
        local match
        for _,r in ipairs(P.prices(data))do
            if r.name==name and r.currency==A.host.currency()then
                if match then return nil,'Уточните ID товара в таблице цен'end
                match=r
            end
        end
        if not match then return nil,'Нет свежих снимков этого товара'end
        local out={}
        for _,s in ipairs(data)do
            local row={username=u8(s.owner),LavkaUid=s.shop,serverId=s.server,itemsSell={},itemsBuy={}}
            for _,side in ipairs({'sell','buy'})do
                for _,o in ipairs(s[side])do
                    if P.title(o)==name and o.qty and o.currency==A.host.currency()then
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
function lIl___Il(name,approved,server)
    Y6.status='wait';Y6.nameItem=name
    if not same_server(server)then Y6.status='false';Y6.result='Цены доступны для текущего мобильного сервера';return end
    local state={}
    read(state,function(data)
        local result={sell_data={},buy_data={}}
        local matches={}
        for _,r in ipairs(P.prices(data))do
            if r.name==name and r.currency==A.host.currency()then matches[#matches+1]=r end
        end
        if #matches~=1 then
            Y6.status='false';Y6.result=#matches==0 and'Нет свежих снимков этого товара' or'Уточните ID и модификацию товара в таблице цен'
            return result
        end
        for _,r in ipairs(matches)do
            for _,side in ipairs({'sell','buy'})do
                if r[side].avg then
                    result[side..'_data'][#result[side..'_data']+1]={date=os.date('%Y-%m-%d'),
                        avg_price=r[side].avg,total_quantity=r[side].qty}
                end
            end
        end
        Y6.status='true';Y6.result=result
        return result
    end)
    -- The generic view's failure is converted to the native item-price state.
    A.host.run(function()
        while state.status==listStatusResponses.WAIT do wait(10)end
        if state.status==listStatusResponses.FAILURE then Y6.status='false';Y6.result=state.result end
    end)
end
end)()
