-- Stall browser. Cached source offers remain distinct from allocated trade plans.
local V,M=DSP.ui21,DSP.mobile
V.shops_mode='sell';V.shops_sort='price'
local function b(s,id,w,on)return V.button(s,'shops_'..id,w,on)end
local function contains(s,q)return DSP.lower(tostring(s or '')):find(q,1,true)~=nil end
local function price_less(a,b,mode,reverse)
    if a~=b then
        local asc=mode=='sell';if reverse then asc=not asc end
        if asc then return a<b else return a>b end
    end
end
function V.shops_result(rows,mode,query,version)
    local sort=V.shops_sort or 'price'
    local stamp=table.concat({tostring(DSP.market.state.sid),tostring(version),mode,DSP.lower(query or ''),sort},'|')
    if V.shops_stamp==stamp then return V.shops_groups end
    local out={};local q=DSP.lower(query or ''):gsub('^#',''):gsub('^№%s*','')
    for _,r in ipairs(rows or {})do
        local offers=(r[mode]and r[mode].offers)or{};local subset={}
        for _,o in ipairs(offers)do
            if q==''or contains(r.display,q)or contains(o.owner,q)or contains(o.shop,q)then subset[#subset+1]=o end
        end
        if #subset>0 then
            local qty,shops,best=0,{},nil
            for _,o in ipairs(subset)do
                qty=qty+math.max(0,math.floor(tonumber(o.qty)or 0));shops[tostring(o.shop)]=true
                local p=tonumber(o.price)or 0
                if not best or price_less(p,best,mode,false)then best=p end
            end
            local n=0;for _ in pairs(shops)do n=n+1 end
            table.sort(subset,function(a,b)
                if sort=='qty_desc'and a.qty~=b.qty then return a.qty>b.qty end
                if a.price~=b.price then return price_less(a.price,b.price,mode,sort=='price_reverse')end
                return tostring(a.shop)<tostring(b.shop)
            end)
            out[#out+1]={row=r,offers=subset,qty=qty,shops=n,count=#subset,best=best}
        end
    end
    table.sort(out,function(a,b)
        if sort=='qty_desc'and a.qty~=b.qty then return a.qty>b.qty end
        if a.best~=b.best then return price_less(a.best,b.best,mode,sort=='price_reverse')end
        return tostring(a.row.display)<tostring(b.row.display)
    end)
    V.shops_stamp=stamp;V.shops_groups=out;return out
end
local function sort_toggle()
    if b(V.shops_sort=='price'and'Цена' or V.shops_sort=='price_reverse'and'Цена обр.'or'Кол-во','sort',120)then
        V.shops_sort=V.shops_sort=='price'and'price_reverse'or V.shops_sort=='price_reverse'and'qty_desc'or'price'
    end
end
local function footer()
    sort_toggle();local w=imgui.GetContentRegionAvail().x
    if w>200 then V.inline();V.muted('Снимок API · наличие не гарантировано')end
end
local function group_row(g,i)
    V.row('shop_group_'..i,56,function(w,x,y)
        M.thumbnail({name=g.row.display,id=g.row.id},32)
        V.at(x+42,y-3)
        if V.text_button(V.fit(g.row.display,w-212),'shops_item_'..i,w-204,false,30)then V.shop_item=g.row.key;V.reset_list('shop_offers_'..V.shops_mode)end
        V.at(x+42,y+27);V.muted(g.shops..' лавок · '..g.qty..' шт. по API')
        V.at(x+w-154,y+6)
        if b(DSP.money(g.best)..' >','price_'..i,154)then V.shop_item=g.row.key;V.reset_list('shop_offers_'..V.shops_mode)end
    end)
end
local function offer_row(o,i)
    V.row('shop_offer_'..i,58,function(w,x,y)
        V.text(V.fit('#'..tostring(o.shop)..' · '..tostring(o.owner or '?'),w-260))
        V.at(x,y+24);V.muted(V.fit('API: '..tostring(o.qty)..' шт. · '..DSP.market.offer_freshness(o.ts),w-240))
        V.at(x+w-246,y+5)
        if b(DSP.money(o.price)..' >','detail_'..i,176)then V.offer_detail=o;V.open_popup('Предложение','offer')end
        V.at(x+w-64,y+5);if b('Метка','pin_'..i,64)then DSP.market.mark_shop(o.shop)end
    end)
end
local function stall_view()
    local st=DSP.market.state;local stamp=tostring(st.sid)..'/'..tostring(st.version)
    if V.cached_shop_stamp~=stamp then V.cached_shops=DSP.market.shops_list();V.cached_shop_stamp=stamp end
    local shop
    for _,s in ipairs(V.cached_shops or{})do if tostring(s.num)==tostring(V.shop_detail)then shop=s;break end end
    if b('< Назад','back_stall',112)then V.shop_detail=nil;return end
    V.inline();V.text(shop and V.fit('Лавка #'..shop.num..' · '..shop.owner,imgui.GetContentRegionAvail().x)or'Лавка обновилась')
    if not shop then return end
    local side=V.shops_mode
    if b('Продаёт','stall_sell',126,side=='sell')then V.shops_mode='sell'end
    V.inline();if b('Скупает','stall_buy',126,side=='buy')then V.shops_mode='buy'end
    V.inline();if b('Метка','mark_stall',100)then DSP.market.mark_shop(shop.num)end
    local entries=shop[V.shops_mode..'_offers']or{}
    V.list_rows('stall_'..tostring(shop.num)..V.shops_mode,entries,56,function(e,i)
        V.row('stall_item_'..i,56,function(w,x,y)
            V.text(V.fit(e.row.display,w-170));V.muted(tostring(e.offer.qty)..' шт. (API)')
            V.at(x+w-160,y+8);V.text(DSP.money(e.offer.price))
        end)
    end,{footer=function()
        if V.shops_mode=='buy'and b('Скопировать +1$','copy_shop',210)then
            local n,err=DSP.market.copy_shop_skupka(shop.num,nil,1);DSP.notify(n and('Скопировано: '..n)or tostring(err))
        end
    end})
end
local function api_browser()
    local st=DSP.market.state;local sig=tostring(st.sid)..'/'..tostring(st.version)
    if V.shop_version~=sig then V.shop_version=sig;V.shop_item=nil;V.shop_detail=nil end
    if V.shop_detail then return stall_view()end
    if V.shop_item and b('< К товарам','back_items',140)then V.shop_item=nil end
    if V.shop_item then V.inline()end
    V.muted(V.fit(DSP.market.freshness(),imgui.GetContentRegionAvail().x-114))
    V.inline();if b('Обновить','refresh',108)then DSP.market.pull(st.sid)end
    if st.status=='error'then V.red(V.fit(st.error or'Ошибка обновления',imgui.GetContentRegionAvail().x))end
    if b('Продают','sell',120,V.shops_mode=='sell')then V.shops_mode='sell'end
    V.inline();if b('Скупают','buy',120,V.shops_mode=='buy')then V.shops_mode='buy'end
    V.inline();local query,edited=V.search('shops','Предмет, ник, # лавки',-1)
    if edited then V.reset_list('shops_'..V.shops_mode);V.reset_list('shop_offers_'..V.shops_mode)end
    local groups=V.shops_result(st.rows,V.shops_mode,query,st.version)
    if V.shop_item then
        local group
        for _,g in ipairs(groups)do if g.row.key==V.shop_item then group=g;break end end
        if group then
            V.text(V.fit(group.row.display,imgui.GetContentRegionAvail().x))
            V.list_rows('shop_offers_'..V.shops_mode,group.offers,58,offer_row,{footer=footer})
        else V.muted('Нет предложений с этим фильтром')end
    else
        V.muted(#groups..' предметов · '..(V.shops_mode=='sell'and'Купить у игроков'or'Продать игрокам'))
        V.list_rows('shops_'..V.shops_mode,groups,56,group_row,{footer=footer})
    end
end
function V.shops()
    V.shops_source=V.shops_source or 'api'
    V.heading('Лавки',function()
        if b('API','source_api',70,V.shops_source=='api')then V.shops_source='api'end
        V.inline()
        if b('Скан лавки','source_scan',142,V.shops_source=='scan')then V.shops_source='scan'end
        V.inline()
        local enabled=DSP.settings.marker_3d_enabled~=false
        if b(enabled and '3D: вкл' or '3D: выкл','marker_toggle',112,enabled)then
            if DSP.shop_marker and DSP.shop_marker.set_enabled then
                DSP.shop_marker.set_enabled(not enabled)
            else DSP.notify('3D-метка пока недоступна')end
        end
    end,336)
    if DSP.shop_marker and DSP.shop_marker.status then
        V.muted(V.fit(DSP.shop_marker.status(),imgui.GetContentRegionAvail().x))
    end
    if V.shops_source=='scan'then
        if V.shop_scan_view then return V.shop_scan_view()end
        V.muted('Откройте лавку в игре для получения списка.')
        return
    end
    return api_browser()
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    V.popup('Предложение','offer',function()
        local o=V.offer_detail;if not o then return end
        V.text('#'..tostring(o.shop)..' · '..tostring(o.owner or'?'))
        V.text('Цена за штуку: '..DSP.money(o.price));V.text('Объём API: '..tostring(o.qty))
        V.muted(DSP.market.offer_freshness(o.ts));V.muted('Данные снимка не гарантируют наличие')
        if b('Лавка целиком','open_stall',185)then V.shop_detail=tostring(o.shop);imgui.CloseCurrentPopup()end
        V.inline();if b('Метка','modal_pin',100)then DSP.market.mark_shop(o.shop)end
        if b('Закрыть','modal_close',140)then imgui.CloseCurrentPopup()end
    end,{w=620,h=290})
end
