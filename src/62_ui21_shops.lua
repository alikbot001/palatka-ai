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
    if w>200 then V.inline();V.muted('Объём API непроверен; 1 может означать слот')end
end
-- Each market card has a genuine large touch action; no tiny title hitbox.
local function group_row(g,i)
    V.row('shop_group_'..i,84,function(w,x,y)
        M.thumbnail({name=g.row.display,id=g.row.id},34)
        V.at(x+44,y+2);V.text(V.fit(g.row.display,w-222))
        V.at(x+44,y+28);V.muted(V.fit(g.shops..' лавок · '..DSP.market.format_units(g.qty)..
            ' шт. по API (не проверено)',w-222))
        V.at(x+44,y+54);V.text(V.fit('Лучшая цена: '..DSP.money(g.best)..'/шт.',w-222))
        V.at(x+w-165,y+16)
        if b('Предложения >','item_'..i,160)then
            V.shop_item=g.row.key;V.reset_list('shop_offers_'..V.shops_mode)
        end
    end)
end
local function offer_row(o,i)
    V.row('shop_offer_'..i,86,function(w,x,y)
        local left=math.max(120,w-258)
        V.at(x,y+2);V.text(V.fit('#'..tostring(o.shop)..' · '..tostring(o.owner or '?'),left))
        V.at(x,y+27);V.muted(V.fit('По API '..DSP.market.format_units(o.qty)..' шт. · '..
            DSP.market.offer_freshness(o.ts),left))
        V.at(x,y+52);V.text(V.fit(DSP.money(o.price)..'/шт.',left))
        V.at(x+w-246,y+15)
        if b('Подробнее','detail_'..i,142)then
            V.offer_detail=o;V.offer_detail_row=V.shop_item;V.offer_detail_side=V.shops_mode
            V.open_popup('Предложение','offer')
        end
        V.inline(4)
        if b('Метка','pin_'..i,96)then DSP.market.mark_shop(o.shop)end
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
            V.text(V.fit(e.row.display,w-170));V.muted(DSP.market.format_units(e.offer.qty)..' шт. (API, не проверено)')
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
    if V.shop_version~=sig then
        -- A local quantity confirmation bumps the model revision without
        -- replacing its source offers; keep the current item card open.
        local server_changed=V.shop_sid~=nil and V.shop_sid~=st.sid
        V.shop_sid=st.sid;V.shop_version=sig
        if server_changed then V.shop_item=nil;V.shop_detail=nil
        elseif V.shop_item and not (st.by_key and st.by_key[V.shop_item]) then V.shop_item=nil end
    end
    if V.shop_detail then return stall_view()end
    if V.shop_item and b('< К товарам','back_items',140)then V.shop_item=nil end
    if V.shop_item then V.inline()end
    local received=tonumber(st.received_at)or 0
    local status=st.status=='loading' and 'Обновление API...' or
        ((st.status=='cache'and 'Кэш · 'or '')..(received>0 and ('Получено '..os.date('%H:%M:%S',received)) or 'Сохранённый снимок')..
        ' · данные: '..DSP.market.freshness())
    V.muted(V.fit(status,imgui.GetContentRegionAvail().x-114))
    V.inline();if b(st.status=='loading' and 'Загрузка...' or 'Обновить','refresh',108)then DSP.market.pull(st.sid)end
    if st.error then V.red(V.fit('API: '..tostring(st.error),imgui.GetContentRegionAvail().x))end
    if st.error then
        local message=st.error
        if st.next_auto_retry and st.next_auto_retry>os.time() then
            message=message..' · повтор через '..tostring(st.next_auto_retry-os.time())..'с'
        end
        V.red(V.fit(message,imgui.GetContentRegionAvail().x))
    end
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
            V.list_rows('shop_offers_'..V.shops_mode,group.offers,86,offer_row,{footer=footer})
        else V.muted('Нет предложений с этим фильтром')end
    else
        if not st.error then V.muted(#groups..' предметов · '..(V.shops_mode=='sell'and'Купить у игроков'or'Продать игрокам'))end
        V.list_rows('shops_'..V.shops_mode,groups,84,group_row,{footer=footer})
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
        local current=DSP.market.state.by_key and DSP.market.state.by_key[V.offer_detail_row]
        local same=false
        local side=current and current[V.offer_detail_side]
        for _,active in ipairs(side and side.offers or {})do if active==o then same=true;break end end
        if not same then
            V.red('Предложение устарело. Закройте окно и обновите список.')
            if b('Закрыть','modal_close',150)then imgui.CloseCurrentPopup()end
            return
        end
        local avail=imgui.GetContentRegionAvail().y
        V.list('offer_detail_panel',function()
        V.text('#'..tostring(o.shop)..' · '..tostring(o.owner or'?'))
        V.text('Цена за штуку: '..DSP.money(o.price))
        local row=DSP.market.state.by_key and DSP.market.state.by_key[V.offer_detail_row]
        local info=DSP.market.quantity_info(row,V.offer_detail_side,o)
        V.text('Количество API: '..DSP.market.format_units(info.api)..' шт. (не проверено)')
        if info.api==1 then V.red('1 по API может означать один слот, а не один предмет!')end
        if info.live~=nil then
            V.text('Открытая лавка: '..DSP.market.format_units(info.live)..' шт. (игровой пакет)')
            if info.disagreement then V.red('Источники расходятся — не используйте API как точный остаток')end
            if b('Принять количество из игры','accept_game_qty',-1)then
                local ok,err=DSP.market.confirm_offer_quantity(row,V.offer_detail_side,o,info.live,'game')
                if not ok then DSP.notify(err) end
            end
        else V.muted('Откройте эту лавку для сверки. При необходимости проверьте вручную.') end
        if V.shop_qty_offer~=o then
            V.shop_qty_offer=o;V.shop_qty_input={value=tonumber(o.qty) or 0}
        end
        V.muted('Если видели точный остаток в игре, введите его:')
        M.compact_number(V.shop_qty_input,'value','shop_verified_qty',165,0)
        V.inline();if b('Подтвердить вручную','confirm_qty',215)then
            local ok,err=DSP.market.confirm_offer_quantity(row,V.offer_detail_side,o,V.shop_qty_input.value,'manual')
            if not ok then DSP.notify(err) end
        end
        V.muted(DSP.market.offer_freshness(o.ts));V.muted('Цены и объёмы из API могут устареть')
        end,{height=math.max(80,avail-72),footer=function()
            if b('Лавка целиком','open_stall',170)then
                V.shop_detail=tostring(o.shop);imgui.CloseCurrentPopup()
            end
            V.inline();if b('Метка','modal_pin',96)then DSP.market.mark_shop(o.shop)end
            V.inline();if b('Закрыть','modal_close',120)then imgui.CloseCurrentPopup()end
        end})
    end,{w=700,h=490})
end
