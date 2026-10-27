-- One item per row. Details are a real modal, allocations use raw offer IDs.
local V,M=DSP.ui21,DSP.mobile
V.arb_tab='sell';V.arb_revision=0
local function b(s,id,w,on)return V.button(s,'arb_'..id,w,on)end
local function offerkey(o)return DSP.market.offer_key(o)end
function V.arb_group(groups)
    for _,g in ipairs(groups or{})do if g.key==V.arb_item then return g end end
end
local function choose_all(g)
    V.arb_sellers={};V.arb_buyers={}
    for _,o in ipairs(g.sellers)do V.arb_sellers[offerkey(o)]=true end
    for _,o in ipairs(g.buyers)do V.arb_buyers[offerkey(o)]=true end
    V.arb_revision=V.arb_revision+1
end
-- Unlike "select all", the auto-plan is an action: it selects offers actually
-- used by the allocator and immediately opens its route and financial result.
local function best_plan(g)
    local p=DSP.market.plan_offers(g,nil,nil,{
        extra=V.arb_extra_enabled and V.arb_extra and V.arb_extra.value or 0})
    if p.qty<=0 then
        V.arb_best_error='Нет выгодного маршрута при текущих фильтрах'
        return
    end
    V.arb_sellers={};V.arb_buyers={}
    for _,r in ipairs(p.routes)do
        V.arb_sellers[offerkey(r.sell_offer)]=true
        V.arb_buyers[offerkey(r.buy_offer)]=true
    end
    V.arb_best_error=nil
    V.arb_revision=V.arb_revision+1
    V.arb_route=true
end
function V.arb_plan(g)
    local f=DSP.settings.arb_filters or{}
    local sig=table.concat({tostring(g),V.arb_revision,DSP.settings.tax_bp or 200,
        f.budget or 0,f.min_profit or 0,f.min_roi or 0,f.max_age or 1800,
        V.arb_extra_enabled and(V.arb_extra and V.arb_extra.value or 0)or 0},'|')
    if os.time()>=(V.arb_plan_expiry or 0)then V.cache.arb_plan=nil end
    return V.memo('arb_plan',sig,function()
        local now,until_ts=os.time(),math.huge
        local age=tonumber(f.max_age)or 1800
        for _,offers in ipairs({g.sellers,g.buyers})do for _,o in ipairs(offers)do
            local ts=tonumber(o.ts)or 0
            if age>0 and ts>0 and ts+age+1>now then until_ts=math.min(until_ts,ts+age+1)end
        end end
        V.arb_plan_expiry=until_ts
        local p=DSP.market.plan_offers(g,V.arb_sellers or{},V.arb_buyers or{},
            {extra=V.arb_extra_enabled and V.arb_extra.value or 0})
        return p
    end)
end
local function offer_row(o,i)
    local selected=V.arb_tab=='sell'and V.arb_sellers or V.arb_buyers
    local key=offerkey(o);local checked=selected and selected[key]
    V.row('arb_offer_'..V.arb_tab..i,100,function(w,x,y)
        local right=math.max(155,w-170)
        V.at(x,y+1);V.text(V.fit('#'..tostring(o.shop)..' · '..tostring(o.owner or'?'),right-8))
        local count=DSP.market.format_units(o.qty)
        local row=V.arb_detail_group and V.arb_detail_group.row
        local live_qty=DSP.market.live_offer_quantity(row,V.arb_tab,o)
        local status=o.qty_source=='game' and 'проверено: игра' or
            o.qty_source=='manual' and 'проверено вручную' or 'API, не подтверждено'
        V.at(x,y+26);V.muted(V.fit(count..' шт. · '..status..
            (live_qty and (' · Игра: '..DSP.market.format_units(live_qty)) or ''),right-8))
        V.at(x,y+52);V.text(V.fit(DSP.money(o.price)..'/шт. · '..DSP.market.offer_freshness(o.ts),right-8))
        if o.qty==1 and not o.verified_at then
            V.at(x,y+76);V.muted(V.fit('Внимание: 1 может быть количеством слотов',right-8))
        end
        V.at(x+right,y+1)
        if b(checked and 'Снять выбор' or 'Выбрать','select_'..i,160,checked)then
            selected[key]=not checked or nil;V.arb_revision=V.arb_revision+1
        end
        V.at(x+right,y+49)
        if b('Уточнить','verify_'..V.arb_tab..i,92,false)then
            V.arb_verify={offer=o,side=V.arb_tab,source=live_qty and 'game' or 'manual'}
            V.arb_verify_value={qty=live_qty or tonumber(o.qty) or 0}
        end
        V.inline(4)
        if b('Метка','pin_'..i,64,false)then DSP.market.mark_shop(o.shop)end
    end)
end
local function route_rows(p)
    return function(r,i)
        V.row('route_'..i,100,function(w,x,y)
            V.text(V.fit('КУПИТЬ '..r.tradable_qty..' шт. у лавки #'..tostring(r.sell_offer.shop)..' · '..DSP.money(r.p_buy)..'/шт.',w))
            V.at(x,y+26);V.text(V.fit('ПРОДАТЬ скупщику #'..tostring(r.buy_offer.shop)..' · '..DSP.money(r.p_sell)..'/шт.',w))
            V.at(x,y+52)
            if b('К продавцу','route_sell_'..i,140)then DSP.market.mark_shop(r.sell_offer.shop)end
            V.inline();if b('К скупщику','route_buy_'..i,144)then DSP.market.mark_shop(r.buy_offer.shop)end
            V.inline();V.green('~ +'..DSP.money(r.net_profit))
            if r.same_shop then
                V.at(x,y+78);V.red('Одна лавка: возможность обратной сделки проверьте в игре')
            end
        end)
    end
end
local function finance(p)
    local available=imgui.GetContentRegionAvail().x
    V.muted(V.fit('Закупка (затраты): '..DSP.money(p.cost)..' · Валовая выручка: '..DSP.money(p.gross),available))
    V.muted(V.fit('Комиссия: '..DSP.money(p.fee)..' · Чистая выручка: '..DSP.money(p.revenue),available))
    local profit_label=V.fit('ПРИБЫЛЬ после закупки, комиссии и расходов: '..DSP.money(p.profit),available)
    if p.profit>=0 then V.green(profit_label)else V.red(profit_label)end
    if p.extra>0 then V.muted(V.fit('Дополнительные расходы: '..DSP.money(p.extra)..' (учтены один раз)',available))end
end
local function details(g)
    local p=V.arb_plan(g)
    V.text(V.fit(g.name,imgui.GetContentRegionAvail().x))
    V.muted('Продают '..(g.row.sell.qty or g.supply)..' · Скупают '..(g.row.buy.qty or g.demand)..' · План '..p.qty..' шт.')
    local changed=V.arb_snapshot~=tostring(DSP.market.state.sid)..'/'..tostring(DSP.market.state.version)
    V.muted(V.fit('Снимок '..os.date('%H:%M:%S',V.arb_snapshot_time or os.time())..
        (changed and ' · есть новые данные, откройте заново'or ' · API, наличие проверьте в игре'),imgui.GetContentRegionAvail().x))
    finance(p)
    local f=DSP.settings.arb_filters or {}
    V.muted('План условный: доступность не забронирована. Запас спроса: '
        ..tostring(f.safety_pct or 0)..'%; обновите и проверьте скупку перед закупкой.')
    if V.arb_route then
        if b('< Предложения','back_offers',170)then V.arb_route=false end
        V.list_rows('arb_routes_'..g.key,p.routes,100,route_rows(p),{footer=function()
            if p.profit>=0 then V.green(DSP.money(p.profit)..' чистой прибыли')
            else V.red(DSP.money(p.profit)..' итогового убытка')end
        end})
        return
    end
    local tw=imgui.GetContentRegionAvail().x
    if b('Продают · купить '..#g.sellers,'sell',tw*.23,V.arb_tab=='sell')then V.arb_tab='sell'end
    V.inline();if b('Скупают · продать '..#g.buyers,'buy',tw*.23,V.arb_tab=='buy')then V.arb_tab='buy'end
    V.inline();if b('Лучший план >','best',tw*.27)then best_plan(g)end
    V.inline();if b('Сброс','none',-1)then V.arb_sellers={};V.arb_buyers={};V.arb_revision=V.arb_revision+1 end
    V.arb_extra=V.arb_extra or{value=0}
    if b(V.arb_extra_enabled and 'x Расходы' or '+ Расходы','extra',136,V.arb_extra_enabled)then V.arb_extra_enabled=not V.arb_extra_enabled end
    if V.arb_extra_enabled then V.inline();M.compact_number(V.arb_extra,'value','arb_extra',130,0)end
    if V.arb_best_error then V.red(V.arb_best_error)end
    if V.arb_verify and V.arb_verify_value then
        local vr=V.arb_verify
        V.muted('Укажите количество, фактически проверенное в игре: #'..tostring(vr.offer.shop)..' · '..tostring(vr.side=='buy' and 'скупает' or 'продаёт'))
        V.inline();M.compact_number(V.arb_verify_value,'qty','arb_verify_qty',104,0)
        V.inline();if b('Применить','verify_save',112)then
            local game_now=DSP.market.live_offer_quantity(g.row,vr.side,vr.offer)
            local source=vr.source=='game' and game_now==V.arb_verify_value.qty and 'game' or 'manual'
            local ok,err=DSP.market.confirm_offer_quantity(g.row,vr.side,vr.offer,V.arb_verify_value.qty,source)
            if ok then
                V.arb_verify=nil;V.arb_verify_value=nil
                V.arb_revision=V.arb_revision+1;V.arb_route=false
                V.arb_snapshot=tostring(DSP.market.state.sid)..'/'..tostring(DSP.market.state.version)
            else V.arb_best_error=tostring(err)end
        end
        V.inline();if b('Отмена','verify_cancel',98)then V.arb_verify=nil;V.arb_verify_value=nil end
    end
    local offers=V.arb_tab=='sell'and g.sellers or g.buyers
    local height=math.max(48,imgui.GetContentRegionAvail().y-110)
    V.list_rows('arb_'..g.key..'_'..V.arb_tab,offers,100,offer_row,{height=height,footer=function()
        if b('Маршрут >','route',142,true)then V.arb_route=true end
        V.inline();if b('Закрыть','close_details',116)then imgui.CloseCurrentPopup()end
    end})
end
function V.arbitrage()
    local st=DSP.market.state
    V.text('Арбитраж');V.inline();V.muted('Снимок: '..DSP.market.freshness())
    V.inline();if b('Обновить','refresh',120)then DSP.market.pull(st.sid)end
    local query,edited=V.search('arb','Поиск предмета',-1)
    if edited then V.reset_list('arb_main')end
    if b('Фильтры','filters',120,V.arb_filters)then V.arb_filters=not V.arb_filters end
    if V.arb_filters then
        local f=DSP.settings.arb_filters or{};DSP.settings.arb_filters=f
        V.inline();V.muted('Бюджет');V.inline()
        local changed=M.compact_number(f,'budget','arb_budget',122,0)
        V.inline();V.muted('Мин. прибыль');V.inline()
        changed=M.compact_number(f,'min_profit','arb_minprofit',122,0)or changed
        V.inline();V.muted('Резерв спроса %');V.inline()
        if b(tostring(f.safety_pct or 0)..'%','reserve',64)then
            f.safety_pct=({[0]=10,[10]=20,[20]=0})[f.safety_pct or 0] or 10
            changed=true
        end
        V.inline();if b('Свежесть '..tostring(math.floor((f.max_age or 600)/60))..'м','age',142)then
            f.max_age=({[300]=600,[600]=1800,[1800]=300})[f.max_age or 600] or 300
            changed=true
        end
        if changed then DSP.market.invalidate_arbitrage();V.arb_revision=V.arb_revision+1;DSP.save_settings()end
    end
    local groups,status
    if DSP.market.arbitrage_grouped_ui then groups,status=DSP.market.arbitrage_grouped_ui()else groups=DSP.market.arbitrage_grouped()end
    if status=='loading'then V.muted('Расчёт рынка...')elseif status=='error'then V.red('Ошибка расчёта. См. журнал')end
    local sig=tostring(groups)..'|'..DSP.lower(query)
    local filtered=V.memo('arb_rows',sig,function()
        local out={};local q=DSP.lower(query)
        for _,g in ipairs(groups)do if q==''or DSP.lower(g.name):find(q,1,true)then out[#out+1]=g end end
        return out
    end)
    V.list_rows('arb_main',filtered,92,function(g,i)
        V.row('arb_group_'..i,92,function(w,x,y)
            M.thumbnail({name=g.name,id=g.row and g.row.id},34)
            V.at(x+44,y+2);V.text(V.fit(g.name,w-220))
            V.at(x+44,y+29);V.muted(V.fit('Купить: '..DSP.market.format_units(g.supply)..
                ' · Сдать: '..DSP.market.format_units(g.demand)..' шт. (API)',w-220))
            V.at(x+44,y+54);V.muted(V.fit('План '..DSP.market.format_units(g.planned)..
                ' шт. · Оценка прибыли '..DSP.money(g.profit),w-220))
            V.at(x+w-164,y+15)
            if b('Предложения >','group_'..i,160,false)then
                V.arb_item=g.key;V.arb_snapshot=tostring(st.sid)..'/'..tostring(st.version)
                V.arb_server=st.sid;V.arb_detail_group=g;V.arb_snapshot_time=os.time()
                V.arb_route=false;V.arb_tab='sell';V.arb_best_error=nil;V.arb_verify=nil;choose_all(g);V.open_popup('Арбитраж','arb_details')
            end
        end)
    end,{footer=function()V.muted('Оценка по API, не гарантированная прибыль. Количество у скупщика может уменьшиться.')end})
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    V.popup('Арбитраж','arb_details',function()
        local st=DSP.market.state
        if V.arb_server~=st.sid then
            V.text('Выбран другой сервер');V.muted('Откройте предмет повторно для нового расчёта')
            if b('Закрыть','stale_close',150)then imgui.CloseCurrentPopup()end
            return
        end
        -- Never keep showing the old route after a market refresh: source
        -- offer tables are replaced, not updated in place.
        if V.arb_snapshot~=tostring(st.sid)..'/'..tostring(st.version)
            or st.status=='loading' then
            V.red('Данные изменились или обновляются. Старый маршрут заблокирован.')
            if b('Пересчитать','refresh_selected',164)then
                local groups,status
                if DSP.market.arbitrage_grouped_ui then
                    groups,status=DSP.market.arbitrage_grouped_ui()
                else groups=DSP.market.arbitrage_grouped()end
                if status~='loading' then
                    local g=V.arb_group(groups)
                    if g then
                        V.arb_detail_group=g;choose_all(g);V.arb_route=false
                        V.arb_verify=nil;V.arb_snapshot=tostring(st.sid)..'/'..tostring(st.version)
                        V.arb_snapshot_time=os.time()
                    else V.arb_best_error='После обновления подходящий маршрут отсутствует'end
                end
            end
            V.inline();if b('Закрыть','stale_close_version',140)then imgui.CloseCurrentPopup()end
            return
        end
        local g=V.arb_detail_group
        if g then details(g)else
            V.muted('Связка больше не проходит фильтры')
            if b('Закрыть','empty_close',140)then imgui.CloseCurrentPopup()end
        end
    end,{w=850,h=560})
end
