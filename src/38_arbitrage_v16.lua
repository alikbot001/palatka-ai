-- Compact item-centric arbitrage. No manual alteration of API quantities.
local M,U=DSP.mobile,DSP.ui
local function b(label,id,w,active) return M.button(label,'arb16_'..id,w,active) end
local function title(g) return tostring(g.name or '?') end
local function offer_id(o) return tostring(o.shop)..':'..tostring(o.price)..':'..tostring(o.owner) end
local function route_id(g,r) return tostring(g.key)..'|'..offer_id(r.sell_offer)..'>'..offer_id(r.buy_offer) end
DSP.arb_v16=DSP.arb_v16 or {}
local function safe_integer(value)
    local n=tonumber(value)
    if not n or n~=n or n<0 or n>9007199254740991 then return nil end
    return math.floor(n)
end
function DSP.arb_v16.manual_pair(seller,buyer,budget,tax_bp)
    if not seller or not buyer then return nil end
    if seller.shop~=nil and buyer.shop~=nil and tostring(seller.shop)==tostring(buyer.shop) then return nil end
    if (seller.ench or 0)~=(buyer.ench or 0) then return nil end
    local p1,p2=safe_integer(seller.price),safe_integer(buyer.price)
    local q1,q2=safe_integer(seller.qty),safe_integer(buyer.qty)
    if not p1 or not p2 or p1<=0 or p2<=0 or not q1 or not q2 then return nil end
    local count=math.min(q1,q2,math.floor(9007199254740991/math.max(p1,p2)))
    budget=safe_integer(budget) or 0
    if budget>0 then count=math.min(count,math.floor(budget/p1)) end
    local cost=p1*count
    local tax=tonumber(tax_bp) or 200
    if tax~=tax or tax==math.huge or tax==-math.huge then tax=200 end
    local factor=10000-math.max(0,math.min(10000,math.floor(tax)))
    local gross=p2*count
    local revenue=math.floor(gross/10000)*factor+math.floor((gross%10000)*factor/10000)
    return {qty=count,cost=cost,revenue=revenue,profit=revenue-cost}
end
local function selected_plan(g)
    local plan={qty=0,cost=0,revenue=0,profit=0,routes={}}
    for _,r in ipairs(g.routes or {}) do
        if U.v16_arb_selected and U.v16_arb_selected[route_id(g,r)] then
            plan.qty=plan.qty+(tonumber(r.tradable_qty) or 0)
            plan.cost=plan.cost+(tonumber(r.total_cost) or 0)
            plan.revenue=plan.revenue+(tonumber(r.net_revenue) or 0)
            plan.profit=plan.profit+(tonumber(r.net_profit) or 0)
            plan.routes[#plan.routes+1]=r
        end
    end
    if U.v16_arb_use_extra and #plan.routes>0 then
        plan.profit=plan.profit-(tonumber(U.v16_arb_expenses and U.v16_arb_expenses.extra) or 0)
    end
    return plan
end
local function auto_select(g)
    U.v16_arb_selected=U.v16_arb_selected or {}
    for _,r in ipairs(g.routes or {}) do
        U.v16_arb_selected[route_id(g,r)]=true
    end
end
local function render_offer(g,offer,side,index)
    local v=side=='sell' and U.v16_arb_seller or U.v16_arb_buyer
    local id=offer_id(offer)
    local label='#'..tostring(offer.shop)..'  '..tostring(offer.owner or '?')..'  '
        ..DSP.money(offer.price)..' x'..tostring(offer.qty or 0)
    if b(label,'offer_'..side..index,-1,id==v) then
        if side=='sell' then U.v16_arb_seller=v==id and nil or id
        else U.v16_arb_buyer=v==id and nil or id end
    end
    if b('Метка','pin_'..side..index,115) then DSP.market.mark_shop(offer.shop) end
    M.inline();M.text('API: '..DSP.market.offer_freshness(offer.ts))
end
local function detail(g)
    if b('< К списку','back',205) then U.v16_arb_detail=nil;return end
    M.inline();M.title(title(g))
    M.text('Продают '..g.supply..' шт. / Скупают '..g.demand..' шт.')
    M.text('План '..g.planned..' шт.  |  +'..DSP.money(g.profit))
    if b('Продают','sellers',165,U.v16_arb_tab~='buy') then U.v16_arb_tab='sell' end
    M.inline()
    if b('Скупают','buyers',165,U.v16_arb_tab=='buy') then U.v16_arb_tab='buy' end
    local side=U.v16_arb_tab=='buy' and 'buy' or 'sell'
    local offers=(side=='sell' and g.sellers or g.buyers) or {}
    local pages=math.max(1,math.ceil(#offers/5))
    U.v16_arb_offer_page=math.min(pages,math.max(1,U.v16_arb_offer_page or 1))
    for i=(U.v16_arb_offer_page-1)*5+1,math.min(#offers,U.v16_arb_offer_page*5) do
        render_offer(g,offers[i],side,i)
    end
    if b('<','offer_prev',100) then U.v16_arb_offer_page=math.max(1,U.v16_arb_offer_page-1) end
    M.inline()
    M.text(U.v16_arb_offer_page..' / '..pages)
    M.inline()
    if b('>','offer_next',100) then U.v16_arb_offer_page=math.min(pages,U.v16_arb_offer_page+1) end
    -- Exact selected pair or a selection of allocated routes. Existing allocator
    -- guarantees routes use disjoint stock and demand; no new duplicate consumption.
    if U.v16_arb_seller and U.v16_arb_buyer then
        local seller,buyer
        for _,o in ipairs(g.sellers or {}) do
            if offer_id(o)==U.v16_arb_seller then seller=o;break end
        end
        for _,o in ipairs(g.buyers or {}) do
            if offer_id(o)==U.v16_arb_buyer then buyer=o;break end
        end
        local f=DSP.settings.arb_filters or {}
        local estimate=DSP.arb_v16.manual_pair(seller,buyer,f.budget,DSP.settings.tax_bp)
        if estimate then
            M.title('Выбранная пара: '..estimate.qty..' шт.')
            M.text('Затраты: '..DSP.money(estimate.cost)..' | Выручка: '..DSP.money(estimate.revenue))
            M.text('Прибыль: '..DSP.money(estimate.profit)..' (отдельный сценарий)')
            M.text('Не прибавляется к общему плану, чтобы не учитывать один лот дважды.')
        end
    end
    if b('Лучший план','auto',198) then auto_select(g);U.v16_arb_seller=nil;U.v16_arb_buyer=nil end
    M.inline()
    if b('Очистить','clear',155) then
        U.v16_arb_selected={};U.v16_arb_seller=nil;U.v16_arb_buyer=nil
    end
    M.title('Подходящие сделки')
    local displayed=0
    for i,r in ipairs(g.routes or {}) do
        local seller=offer_id(r.sell_offer)
        local buyer=offer_id(r.buy_offer)
        if (not U.v16_arb_seller or seller==U.v16_arb_seller)
            and (not U.v16_arb_buyer or buyer==U.v16_arb_buyer) then
            local key=route_id(g,r)
            local marked=U.v16_arb_selected and U.v16_arb_selected[key]
            local label=(marked and '[x] ' or '[ ] ')..'#'..r.sell_offer.shop..' -> #'..r.buy_offer.shop
                ..' | '..r.tradable_qty..' шт. | +'..DSP.money(r.net_profit)
            if b(label,'route_'..i,-1,marked) then
                U.v16_arb_selected=U.v16_arb_selected or {}
                U.v16_arb_selected[key]=not marked or nil
            end
            displayed=displayed+1
            if displayed>=6 then break end
        end
    end
    if displayed==0 then M.text('Подходящей связки нет. Уберите фильтр продавца/скупщика.') end
    U.v16_arb_expenses=U.v16_arb_expenses or {extra=0}
    if b(U.v16_arb_use_extra and 'Доп. расходы: да' or 'Доп. расходы: нет','extra',250) then
        U.v16_arb_use_extra=not U.v16_arb_use_extra
    end
    if U.v16_arb_use_extra then M.number('Расход на план ($)','additional_expense',U.v16_arb_expenses,'extra',0,180) end
    local plan=selected_plan(g)
    M.text('Купить: '..plan.qty..' шт.  |  Расход: '..DSP.money(plan.cost))
    M.text('Выручка после комиссии: '..DSP.money(plan.revenue))
    imgui.TextColored(DSP.theme.col(plan.profit>=0 and 'good' or 'bad',1),
        DSP.utf8('Чистая прибыль: '..DSP.money(plan.profit)))
    if b(U.v16_arb_route and 'Скрыть маршрут' or 'Маршрут','route_view',210) then
        U.v16_arb_route=not U.v16_arb_route
    end
    if U.v16_arb_route then
        for i,r in ipairs(plan.routes) do
            M.text(i..'. Купить '..r.tradable_qty..' шт. в #'..r.sell_offer.shop)
            if b('Метка продавца','sell_route_'..i,200) then DSP.market.mark_shop(r.sell_offer.shop) end
            M.text('   Продать '..r.tradable_qty..' шт. в #'..r.buy_offer.shop)
            if b('Метка скупщика','buy_route_'..i,200) then DSP.market.mark_shop(r.buy_offer.shop) end
        end
    end
end
function U.arbitrage_tab()
    local state=DSP.market.state or {}
    U.v16_arb_selected=U.v16_arb_selected or {}
    local sig=tostring(state.sid)..':'..tostring(state.version or 0)
    if U.v16_arb_signature~=sig then
        U.v16_arb_selected={};U.v16_arb_detail=nil;U.v16_arb_signature=sig
    end
    if U.v16_arb_detail then
        for _,g in ipairs(DSP.market.arbitrage_grouped()) do
            if g.key==U.v16_arb_detail then detail(g);return end
        end
        U.v16_arb_detail=nil
    end
    M.text('Рынок: '..DSP.market.freshness()..' | '..tostring(state.status or '?'))
    if b('Обновить','refresh',170) then DSP.market.pull(state.sid) end
    M.inline()
    if b(U.v16_arb_filters and 'Скрыть фильтры' or 'Фильтры','filters',170) then
        U.v16_arb_filters=not U.v16_arb_filters
    end
    if U.v16_arb_filters then
        local f=DSP.settings.arb_filters or {};DSP.settings.arb_filters=f
        if M.number('Бюджет','arb_budget',f,'budget',0,190) then DSP.market.invalidate_arbitrage() end
        if M.number('Минимум прибыли','arb_profit',f,'min_profit',0,190) then DSP.market.invalidate_arbitrage() end
    end
    local groups=DSP.market.arbitrage_grouped()
    U.v16_arb_search=U.v16_arb_search or imgui.new.char[128]()
    imgui.SetNextItemWidth(math.min(500,imgui.GetContentRegionAvail().x))
    imgui.InputTextWithHint('##arb16_search',DSP.utf8('Поиск предмета'),U.v16_arb_search,128)
    local query=DSP.lower(DSP.trim(DSP.to_cp(require('ffi').string(U.v16_arb_search))))
    local shown={}
    for _,g in ipairs(groups) do
        if query=='' or DSP.lower(g.name):find(query,1,true) then shown[#shown+1]=g end
    end
    M.text('Предметов: '..#shown)
    local from,to=DSP.screens.pager(#shown,7,'arbitrage')
    for i=from,to do
        local g=shown[i]
        M.thumbnail({name=g.name,id=g.row and g.row.id},26);M.inline()
        local label=g.name..'  '..g.planned..' шт.  +'..DSP.money(g.profit)
        if b(label,'item_'..i,-1) then
            U.v16_arb_detail=g.key;U.v16_arb_tab='sell';U.v16_arb_offer_page=1
            U.v16_arb_seller=nil;U.v16_arb_buyer=nil
            U.v16_arb_selected={}
        end
    end
    if #shown==0 then M.text('Связок нет — проверьте фильтры и свежесть данных.') end
end
