-- Local scanned routes are kept separate from unverified API opportunities.
local V = DSP.ui21
local A = DSP.local_arb
local M = DSP.market
local function b(label,id,w,active) return V.button(label,'local_arb_'..id,w,active) end
local function elapsed(at,now)
    local n=math.max(0,now-(tonumber(at)or 0))
    return tostring(math.floor(n/60))..' мин назад'
end
local function txt(s,w) return V.fit(s,math.max(1,w)) end
function V.local_arbitrage_view()
    local now=os.time()
    local stats=A.stats(now)
    local auto=DSP.settings.auto_shop_scan~=false
    if b(auto and 'АВТОСКАН: ВКЛ' or 'АВТОСКАН: ВЫКЛ','auto_toggle',180) then
        DSP.settings.auto_shop_scan=not auto
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
        else DSP.save_settings() end
        auto=not auto
    end
    V.inline()
    V.muted('Сканирует при открытии лавки, без кнопки и без API')
    local saver=DSP.settings.fps_saver==true
    if b(saver and 'ЭКОНОМИЯ FPS: ВКЛ' or 'ЭКОНОМИЯ FPS: ВЫКЛ','fps_toggle',200) then
        DSP.settings.fps_saver=not saver
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
        else DSP.save_settings() end
    end
    V.inline()
    V.muted('Отключает дополнительные окна и иконки, автоскан остаётся')
    local last=DSP.live and DSP.live.auto_scan
    if last and (last.at or 0)>0 then
        V.muted('Последний скан: лавка #'..tostring(last.shop)..' | '..tostring(last.items)..' позиций | '..elapsed(last.at,now))
    end
    V.green('ИЗ СКАНОВ В ИГРЕ · БЕЗ API')
    V.muted('Лавок: '..stats.shops..' · предложений: '..stats.offers..' · память: 60 мин')
    V.muted('Сохраняются цены только ОТКРЫТЫХ лавок с известным номером. Проверяй наличие перед сделкой.')
    local query,changed=V.search('local_arb','Название предмета или номер лавки',-1)
    if changed then V.reset_list('local_arb_items');V.reset_list('local_offer_search') end
    if query~='' and DSP.shop_store and DSP.shop_store.search then
        local matches=DSP.shop_store.search(query,nil,stats.server)
        V.green('\xc2\xf1\xe5 \xef\xf0\xe5\xe4\xeb\xee\xe6\xe5\xed\xe8\xff \xe8\xe7 \xf1\xea\xe0\xed\xee\xe2: '..tostring(#matches))
        V.list_rows('local_offer_search',matches,78,function(ref,i)
            local o,sh=ref.offer or{},ref.shop or{}
            V.row('local_offer_'..i,78,function(w,x,y)
                local side=ref.side=='buy' and '\xf1\xea\xf3\xef\xea\xe0' or '\xef\xf0\xee\xe4\xe0\xe6\xe0'
                V.at(x,y+1);V.text(txt(tostring(o.name or '?')..'  ['..side..']',w))
                V.at(x,y+27);V.muted(txt('\xeb\xe0\xe2\xea\xe0 #'..tostring(sh.num or '?')..' \xb7 '..DSP.money(tonumber(o.price) or 0)..'/\xf8\xf2. \xb7 x'..tostring(o.qty or '?'),w))
                V.at(x,y+51);V.muted(txt(tostring(sh.owner or '?')..' \xb7 '..elapsed(sh.at,now),w))
            end)
        end,{height=math.min(260,math.max(92,#matches*78)),footer=false})
        V.muted('\xcf\xee\xe8\xf1\xea \xe2\xfb\xf8\xe5 \xe8\xe4\xb8\xf2 \xef\xee \xef\xee\xeb\xed\xee\xec\xf3 \xe8\xed\xe4\xe5\xea\xf1\xf3 \xf1\xea\xe0\xed\xee\xe2; \xed\xe8\xe6\xe5 -- \xf2\xee\xeb\xfc\xea\xee \xe2\xfb\xe3\xee\xe4\xed\xfb\xe5 \xe0\xf0\xe1\xe8\xf2\xf0\xe0\xe6\xed\xfb\xe5 \xef\xe0\xf0\xfb.')
    end
    local revision=table.concat({A.revision,math.floor(now/10),DSP.settings.tax_bp or 200,
        M.missing_revision or 0,DSP.lower(query)},'|')
    local routes=V.memo('local_arb_routes',revision,function()
        local all=A.routes(now)
        local q=DSP.lower(query)
        if q==''then return all end
        local out={}
        for _,r in ipairs(all) do
            local hay=DSP.lower(tostring(r.name or '')..' '..tostring(r.seller_shop)..' '..tostring(r.buyer_shop))
            if hay:find(q,1,true) then out[#out+1]=r end
        end
        return out
    end)
    V.muted('Найдено связок: '..tostring(#routes)..' · порядок: прибыль за 1 шт.')
    if #routes==0 then V.muted('Нет выгодных пар из твоих сканов за последний час.') end
    V.list_rows('local_arb_items',routes,142,function(r,i)
        V.row('local_route_'..i,142,function(w,x,y)
            local text_width=math.max(130,w-134)
            V.at(x,y+1);V.text(txt((r.name or 'ID:'..r.id)..' +'..tostring(r.ench or 0),text_width))
            V.at(x,y+28);V.muted(txt('КУПИТЬ: #'..r.seller_shop..' · '..DSP.money(r.buy_price)..'/шт.',text_width))
            V.at(x,y+51);V.muted(txt('СДАТЬ: #'..r.buyer_shop..' · '..DSP.money(r.sell_price)..'/шт.',text_width))
            V.at(x,y+75);V.green(txt('~ +'..DSP.money(r.profit_unit)..'/шт. после комиссии',text_width))
            V.at(x,y+100)
            V.muted(txt('Скан: '..elapsed(r.seller_at,now)..' / '..elapsed(r.buyer_at,now),w))
            V.at(x+math.max(0,w-124),y+33)
            if b('Маршрут >','open_'..i,118) then
                V.local_route={server=stats.server,route=r}
                V.open_popup('Маршрут из скана','local_route')
            end
        end)
    end,{footer=function()
        V.muted('Потенциальные цены, НЕ реальные продажи. Неизвестные объёмы не суммируются.')
    end})
end
local previous=V.popups
function V.popups()
    if previous then previous() end
    V.popup('Маршрут из скана','local_route',function()
        local selected=V.local_route
        if not selected or selected.server~=A.stats().server then
            V.red('Сменился сервер. Выбери маршрут заново.')
            if b('Закрыть','changed_close',150) then imgui.CloseCurrentPopup()end
            return
        end
        local r=selected.route
        local age=os.time()
        if age-r.seller_at>=A.ttl or age-r.buyer_at>=A.ttl then
            V.red('Данные устарели. Открой лавки заново.')
            if b('Закрыть','stale_close',150)then imgui.CloseCurrentPopup()end
            return
        end
        V.text(txt(r.name or '?',imgui.GetContentRegionAvail().x))
        V.green('ИСТОЧНИК: локальный скан в игре, не API')
        V.text('1. КУПИТЬ в лавке #'..r.seller_shop..' ('..tostring(r.seller_owner or '?')..')')
        V.muted(DSP.money(r.buy_price)..' за штуку · '..elapsed(r.seller_at,age))
        V.text('2. СДАТЬ в лавку #'..r.buyer_shop..' ('..tostring(r.buyer_owner or '?')..')')
        V.muted(DSP.money(r.sell_price)..' за штуку · '..elapsed(r.buyer_at,age))
        V.text('Поступления после комиссии: '..DSP.money(r.net_unit)..' за штуку')
        V.green('Потенциальная прибыль: +'..DSP.money(r.profit_unit)..' за штуку')
        if r.qty and r.profit_total then
            V.muted('Известный лимит: до '..r.qty..' шт. · потолок прибыли ~ '..DSP.money(r.profit_total))
        else
            V.muted('Количество неизвестно: итоговую прибыль не рассчитываем.')
        end
        V.red('Скан НЕ гарантирует, что предложение ещё существует!')
        if b('Метка продавца','seller_marker',155) then M.mark_shop(r.seller_shop)end
        V.inline();if b('Метка скупщика','buyer_marker',155) then M.mark_shop(r.buyer_shop)end
        if b('Нет лавки #'..r.seller_shop,'seller_missing',195) then
            M.mark_shop_missing(r.seller_shop,30);if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
            imgui.CloseCurrentPopup()
        end
        V.inline();if b('Нет лавки #'..r.buyer_shop,'buyer_missing',195) then
            M.mark_shop_missing(r.buyer_shop,30);if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
            imgui.CloseCurrentPopup()
        end
        V.cancel('local_route')
    end,{w=710,h=440})
end
return true