-- UI 2.1 grouped arbitrage: raw snapshot vs planned volume are separate.
-- No write-back or manual overriding of API quantities.
local ffi=require('ffi')
local V,M=DSP.ui21,DSP.mobile
V.arb_tab='sell'
V.arb_chosen={}
local function b(s,id,w,on) return V.button(s,'arb_'..id,w,on) end
local function key(o) return tostring(o.shop)..'/'..tostring(o.price)..'/'..tostring(o.owner) end
local function routekey(g,r)
    return tostring(g.key)..'/'..key(r.sell_offer)..'>'..key(r.buy_offer)
end
function V.arb_group(groups)
    for _,g in ipairs(groups or {}) do if g.key==V.arb_item then return g end end
end
local function plan(g)
    local out={qty=0,cost=0,revenue=0,profit=0,routes={}}
    for _,r in ipairs(g.routes or {}) do
        if V.arb_chosen[routekey(g,r)] then
            out.qty=out.qty+(tonumber(r.tradable_qty) or 0)
            out.cost=out.cost+(tonumber(r.total_cost) or 0)
            out.revenue=out.revenue+(tonumber(r.net_revenue) or 0)
            out.profit=out.profit+(tonumber(r.net_profit) or 0)
            out.routes[#out.routes+1]=r
        end
    end
    if V.arb_extra_enabled and #out.routes>0 then
        out.profit=out.profit-math.max(0,tonumber(V.arb_extra and V.arb_extra.value) or 0)
    end
    return out
end
local function selected(g)
    local from,to=V.selected_page('arb_offers',#(V.arb_tab=='sell' and g.sellers or g.buyers),12)
    local offers=V.arb_tab=='sell' and g.sellers or g.buyers
    for i=from,to do
        local o=offers[i]
        local itemkey=key(o)
        local checked=(V.arb_tab=='sell' and V.arb_seller or V.arb_buyer)==itemkey
        local label='#'..tostring(o.shop)..'  '..tostring(o.owner or '?')..
            '  x'..tostring(o.qty or 0)..' · '..DSP.money(o.price)..'/шт.'
        if b(label,'offer_'..i,-1,checked) then
            if V.arb_tab=='sell' then V.arb_seller=(checked and nil or itemkey)
            else V.arb_buyer=(checked and nil or itemkey) end
        end
        if b('Метка','pin_'..i,91) then DSP.market.mark_shop(o.shop) end
        V.inline();V.muted('API · '..DSP.market.offer_freshness(o.ts))
        imgui.Separator()
    end
    V.pager('arb_offers',#offers,12)
end
local function route_view(g)
    local p=plan(g)
    if b('‹ Назад','route_back',130) then V.arb_route=false;return end
    V.text('Маршрут · '..p.qty..' шт. / '..DSP.money(p.profit))
    if #p.routes==0 then V.muted('Отметьте подходящие связки или нажмите «Лучший план».') end
    for i,r in ipairs(p.routes) do
        V.text(i..'. Купить x'..tostring(r.tradable_qty)..' · #'..tostring(r.sell_offer.shop))
        V.inline();if b('Метка','route_sell_'..i,97) then DSP.market.mark_shop(r.sell_offer.shop) end
        V.text('     Продать x'..tostring(r.tradable_qty)..' · #'..tostring(r.buy_offer.shop))
        V.inline();if b('Метка','route_buy_'..i,97) then DSP.market.mark_shop(r.buy_offer.shop) end
        imgui.Separator()
    end
end
local function detail(g)
    if V.arb_route then return route_view(g) end
    if b('‹ Назад','back',140) then V.arb_item=nil;return end
    V.inline();V.text(tostring(g.name))
    V.muted('Продают '..g.supply..' шт.  ·  Скупают '..g.demand..' шт.  (снимок API)')
    V.muted('План: '..g.planned..' шт.  ·  +'..DSP.money(g.profit)..'  ·  '..DSP.market.freshness())
    if b('Продают','tab_sell',math.max(130,imgui.GetContentRegionAvail().x*.30),V.arb_tab=='sell') then
        V.arb_tab='sell';V.pages.arb_offers=1
    end
    V.inline()
    if b('Скупают','tab_buy',math.max(130,imgui.GetContentRegionAvail().x*.30),V.arb_tab=='buy') then
        V.arb_tab='buy';V.pages.arb_offers=1
    end
    selected(g)
    -- Explicit pair is an alternative estimate, not part of the allocated plan.
    if V.arb_seller and V.arb_buyer then
        local s,k
        for _,o in ipairs(g.sellers) do if key(o)==V.arb_seller then s=o end end
        for _,o in ipairs(g.buyers) do if key(o)==V.arb_buyer then k=o end end
        local f=DSP.settings.arb_filters or {}
        local pair=DSP.arb_v16.manual_pair(s,k,f.budget,DSP.settings.tax_bp)
        if pair then
            V.text('Выбранная пара: '..pair.qty..' шт.')
            V.muted('Купить '..DSP.money(pair.cost)..' · Выручка '..DSP.money(pair.revenue))
            V.green('Прибыль пары: '..DSP.money(pair.profit))
        end
    end
    if b('Лучший план','auto',153) then
        V.arb_chosen={}
        for _,r in ipairs(g.routes or {}) do V.arb_chosen[routekey(g,r)]=true end
        V.arb_seller=nil;V.arb_buyer=nil
    end
    V.inline()
    if b('Очистить','clear',112) then V.arb_chosen={};V.arb_seller=nil;V.arb_buyer=nil end
    V.inline()
    if b('Связки','show_routes',106) then V.arb_routes_expand=not V.arb_routes_expand end
    if V.arb_routes_expand then
        local routes=g.routes or {}
        local from,to=V.selected_page('arb_routes',#routes,12)
        for i=from,to do
            local r=routes[i]
            local id=routekey(g,r)
            local checked=V.arb_chosen[id] and true or false
            if b((checked and '[x]' or '+')..'  #'..r.sell_offer.shop..' -> #'..r.buy_offer.shop..
                '  x'..r.tradable_qty..'  +'..DSP.money(r.net_profit),'route_'..i,-1,checked) then
                V.arb_chosen[id]=not checked or nil
            end
        end
        V.pager('arb_routes',#routes,12)
    end
    V.arb_extra=V.arb_extra or {value=0}
    if b(V.arb_extra_enabled and '[x] Доп. расходы' or 'Доп. расходы','expenses',171,V.arb_extra_enabled) then
        V.arb_extra_enabled=not V.arb_extra_enabled
    end
    if V.arb_extra_enabled then M.number('Расход ($)','arb_extra',V.arb_extra,'value',0,130) end
    local p=plan(g)
    V.text('Выбрано: x'..p.qty..'   Затраты: '..DSP.money(p.cost)..'   Выручка: '..DSP.money(p.revenue))
    V.green('Чистая прибыль: '..DSP.money(p.profit))
end
function V.arbitrage()
    local st=DSP.market.state
    local sig=tostring(st.sid)..':'..tostring(st.version or 0)
    if sig~=V.arb_signature then
        V.arb_signature=sig
        V.arb_item=nil
        V.arb_chosen={}
        V.arb_seller=nil;V.arb_buyer=nil
        V.arb_route=false
    end
    local groups=DSP.market.arbitrage_grouped()
    if V.arb_item then
        local g=V.arb_group(groups)
        if g then return detail(g) end
        V.arb_item=nil
    end
    V.text('Арбитраж')
    V.inline();V.muted(DSP.market.freshness())
    V.inline();if b('Обн.','refresh',55) then DSP.market.pull(st.sid) end
    local query=V.search('arb','Поиск предмета...',-1)
    if b('Фильтры','filters',115,V.arb_filters) then V.arb_filters=not V.arb_filters end
    if V.arb_filters then
        local f=DSP.settings.arb_filters or {};DSP.settings.arb_filters=f
        local changed=M.number('Бюджет','budget',f,'budget',0,145)
        changed=M.number('Мин. прибыль','minprofit',f,'min_profit',0,145) or changed
        if changed then DSP.market.invalidate_arbitrage();M.defer_save() end
    end
    local q=DSP.lower(query or '')
    local filtered={}
    for _,g in ipairs(groups) do
        if q=='' or DSP.lower(g.name):find(q,1,true) then filtered[#filtered+1]=g end
    end
    V.muted(#filtered..' предметов · план, не фактическая сделка')
    local from,to=V.selected_page('arb',#filtered,16)
    for i=from,to do
        local g=filtered[i]
        M.thumbnail({name=g.name,id=g.row and g.row.id},23);V.inline()
        if b(tostring(g.name)..'  x'..g.planned..'  +'..DSP.money(g.profit)..'  ›','group_'..i,-1) then
            V.arb_item=g.key;V.arb_tab='sell';V.pages.arb_offers=1
            V.arb_routes_expand=false;V.arb_route=false
            V.arb_chosen={};V.arb_seller=nil;V.arb_buyer=nil
        end
        imgui.Separator()
    end
    if #filtered==0 then V.muted('Связок нет или данные рынка устарели.') end
    V.pager('arb',#filtered,16)
end
function V.arb_footer(w)
    if V.arb_item and not V.arb_route then
        if b('^','up',48) then M.queue_scroll(-1) end
        V.inline();if b('v','down',48) then M.queue_scroll(1) end
        V.inline();if b('Маршрут ›','route',170,true) then V.arb_route=true end
    else
        if b('^','up',57) then M.queue_scroll(-1) end
        V.inline();if b('v','down',57) then M.queue_scroll(1) end
        V.inline();V.muted('По данным API, не гарантия наличия')
    end
end
