-- Market search and item-centric arbitrage; labels are from the player's point of view.
local ffi=require('ffi')
local M=DSP.mobile
local U=DSP.ui
local function add(row,kind)
    local ok,err=DSP.presets.add(row,kind)
    DSP.notify(ok and 'Добавлено в набор' or tostring(err))
end
local function mark(offer,id)
    if M.button('Отметить #'..tostring(offer.shop),'mark_'..id,210) then
        DSP.market.mark_shop(offer.shop)
    end
end
local function offer_list(row,kind)
    local side=kind=='sell' and row.sell or row.buy
    M.title(kind=='sell' and 'ПРОДАЮТ ВАМ' or 'СКУПАЮТ У ВАС')
    if #(side.offers or {})==0 then M.text('Нет предложений') end
    for i,o in ipairs(side.offers or {}) do
        M.text('#'..tostring(o.shop)..'  '..tostring(o.owner or '?')..'    '..DSP.money(o.price)..' / шт.')
        local status=DSP.market.offer_freshness(o.ts)
        M.text('Количество по снимку: '..tostring(o.qty)..' шт.  |  '..tostring(status))
        mark(o,row.key..kind..i)
        imgui.Separator()
    end
end
function U.detail(row)
    M.title('ПРЕДМЕТ')
    M.thumbnail({name=row.display,id=row.id},48)
    M.text(row.display)
    M.text(DSP.market.market_label_for(row) or '')
    if M.button('+ В скупку','detail_add_buy',200) then add(row,'buy') end
    M.inline()
    if M.button('+ В продажу','detail_add_sell',230) then add(row,'sell') end
    offer_list(row,'sell')
    offer_list(row,'buy')
end
function U.finder_tab()
    U.header()
    imgui.SetNextItemWidth(math.min(740,imgui.GetContentRegionAvail().x))
    if imgui.InputTextWithHint('##mobile_search',DSP.utf8('Найти предмет...'),U.finder_search_buf,128) then
        U.finder_query=DSP.to_cp(ffi.string(U.finder_search_buf))
        DSP.screens.set_page('search',1)
    end
    if U.selected then
        if M.button('< К списку','back_search',210) then U.selected=nil end
        local row=DSP.market.state.by_key[U.selected]
        if row then U.detail(row) end
        return
    end
    local matches=DSP.market.find_item(U.finder_query)
    M.text('Предметов: '..#matches)
    local first,last=DSP.screens.pager(#matches,7,'search')
    if #matches==0 then M.text('Нет предложений. Проверьте название или обновите рынок.') end
    for i=first,last do
        local row=matches[i]
        imgui.Separator()
        M.thumbnail({name=row.display,id=row.id},44)
        M.text(row.display)
        M.text('Купить: '..(row.sell.count>0 and DSP.money(row.sell.best) or 'нет')..
            '   |   Продать: '..(row.buy.count>0 and DSP.money(row.buy.best) or 'нет'))
        if M.button('Смотреть лавки','open_item'..i,215) then U.selected=row.key end
        M.inline()
        if M.button('+ В скупку','search_buy'..i,180) then add(row,'buy') end
        M.inline()
        if M.button('+ В продажу','search_sell'..i,210) then add(row,'sell') end
    end
end

local function route_key(group,e)
    -- Same-price slots in the same shop are merged in the market model.
    return tostring(DSP.market.state.sid)..'|'..tostring(group.key)..'|'
        ..tostring(e.sell_offer.shop)..':'..tostring(e.p_buy)..'>'
        ..tostring(e.buy_offer.shop)..':'..tostring(e.p_sell)
end
local function summarize_selection(groups)
    local s={qty=0,cost=0,profit=0,count=0}
    for _,g in ipairs(groups) do
        for _,e in ipairs(g.routes) do
            if U.arb_selected[route_key(g,e)] then
                s.qty=s.qty+(e.tradable_qty or 0)
                s.cost=s.cost+(e.total_cost or 0)
                s.profit=s.profit+(e.net_profit or 0)
                s.count=s.count+1
            end
        end
    end
    return s
end
local function offer_card(g,o,kind,i)
    local shop=tostring(o.shop or '?')
    local age=DSP.market.offer_freshness(o.ts)
    M.text('#'..shop..'  '..tostring(o.owner or '?')..'    '..DSP.money(o.price)..' / шт.')
    if o.snapshot_qty~=nil then
        M.text('Снимок API: '..tostring(o.snapshot_qty)..' шт. | Проверено вами: '..tostring(o.qty)..' шт.')
    else
        M.text('По снимку: '..tostring(o.qty or 0)..' шт. | '..tostring(age))
    end
    mark(o,'group'..g.key..kind..i)
    if kind=='buy' then
        local id='verify_'..tostring(g.key)..'_'..tostring(o.shop)..'_'..i
        if M.button('Проверил в игре: исправить число','verify_open_'..id,365) then
            U.arb_qty_editor_key=id
            U.arb_qty_buf=imgui.new.char[32]()
            local value=tostring(o.qty or 0)
            ffi.copy(U.arb_qty_buf,value,math.min(#value,31))
        end
        if U.arb_qty_editor_key==id and U.arb_qty_buf then
            imgui.SetNextItemWidth(math.min(250,imgui.GetContentRegionAvail().x))
            imgui.InputTextWithHint('##verify_qty_'..id,DSP.utf8('Сколько скупает в игре?'),U.arb_qty_buf,32)
            if M.button('Подтвердить шт.','verify_save_'..id,230) then
                local raw=ffi.string(U.arb_qty_buf)
                local ok,err=DSP.market.confirm_offer_quantity(g.row,'buy',o,raw:match('^%d+$') and tonumber(raw) or -1)
                if ok then U.arb_qty_editor_key=nil; DSP.notify('Количество уточнено. План пересчитан.')
                else DSP.notify(tostring(err)) end
            end
            M.inline()
            if M.button('Отмена','verify_cancel_'..id,150) then U.arb_qty_editor_key=nil end
        end
    end
end
local function route_card(g,e,i)
    local key=route_key(g,e)
    local v=imgui.new.bool(U.arb_selected[key] and true or false)
    if imgui.Checkbox(DSP.utf8('В мой план##route_'..key),v) then
        U.arb_selected[key]=v[0] or nil
    end
    M.text('КУПИТЬ   #'..tostring(e.sell_offer.shop)..'  ->  ПРОДАТЬ   #'..tostring(e.buy_offer.shop))
    M.text('Эта связка: '..tostring(e.tradable_qty)..' шт. | Цена: '..DSP.money(e.p_buy)..' -> '..DSP.money(e.p_sell))
    local gross=(e.tradable_qty or 0)*(e.p_sell or 0)
    M.text('Расход: '..DSP.money(e.total_cost or 0)..' | Выручка после комиссии: '..DSP.money(e.net_revenue or 0))
    M.text('Комиссия: '..DSP.money(gross-(e.net_revenue or 0)))
    imgui.TextColored(DSP.theme.col('good',1),DSP.utf8('Прибыль: +'..DSP.money(e.net_profit)))
    M.text('Продавец: '..tostring(e.qty_seller)..' шт. | Скупщик: '..tostring(e.qty_buyer)..' шт.')
    if (e.tradable_qty or 0)<(e.available_qty or 0) then
        M.text('Меньше максимума: бюджет или объём уже распределён в другие сделки.')
    end
    if M.button('К продавцу #'..tostring(e.sell_offer.shop),'route_sell'..key,220) then
        DSP.market.mark_shop(e.sell_offer.shop)
    end
    M.inline()
    if M.button('К скупщику #'..tostring(e.buy_offer.shop),'route_buy'..key,220) then
        DSP.market.mark_shop(e.buy_offer.shop)
    end
end
local function render_group(g,idx)
    imgui.Separator()
    M.thumbnail({name=g.name,id=g.row.id},46)
    M.title(tostring(idx)..'. '..g.name)
    M.text('ПРОДАЮТ  '..g.supply..' шт. / '..g.seller_count..' предлож.   |   СКУПАЮТ  '..g.demand..' шт. / '..g.buyer_count..' предлож.')
    imgui.TextColored(DSP.theme.col('good',1),
        DSP.utf8('План: '..g.planned..' шт.     Прибыль: +'..DSP.money(g.profit)))
    local expanded=U.arb_expanded[g.key]
    if M.button(expanded and 'Скрыть подробности' or 'Все продавцы, скупщики и маршруты',
        'expand_group'..g.key,440,expanded) then
        U.arb_expanded[g.key]=not expanded
        expanded=not expanded
    end
    if not expanded then return end
    M.text('Источник: снимок рынка. Объёмы в игре могли измениться.')
    M.title('КТО ПРОДАЁТ — '..g.supply..' ШТ. ВСЕГО')
    for i,o in ipairs(g.sellers) do offer_card(g,o,'sell',i); imgui.Separator() end
    M.title('КТО СКУПАЕТ — '..g.demand..' ШТ. ВСЕГО')
    for i,o in ipairs(g.buyers) do offer_card(g,o,'buy',i); imgui.Separator() end
    M.title('РЕАЛЬНЫЙ ПЛАН / '..#g.routes..' СВЯЗОК')
    M.text('Только выгодные пары, без повторного расходования остатков.')
    for i,e in ipairs(g.routes) do route_card(g,e,i); imgui.Separator() end
    if M.button('Выбрать все связки предмета','select_item'..g.key,310) then
        for _,e in ipairs(g.routes) do U.arb_selected[route_key(g,e)]=true end
    end
    M.inline()
    if M.button('Снять выбор','unselect_item'..g.key,175) then
        for _,e in ipairs(g.routes) do U.arb_selected[route_key(g,e)]=nil end
    end
end
function U.arbitrage_tab()
    U.header()
    local f=DSP.settings.arb_filters or {}
    DSP.settings.arb_filters=f
    U.arb_selected=U.arb_selected or {}
    U.arb_expanded=U.arb_expanded or {}
    local st=DSP.market.state
    local signature=tostring(st.sid)..'/'..tostring(st.version)..'/'..tostring(f.budget)..'/'..tostring(f.max_qty)..'/'..tostring(f.min_profit)..'/'..tostring(f.min_roi)
    if signature~=U.arb_selection_signature then
        U.arb_selected={}; U.arb_selection_signature=signature
    end
    M.title('АРБИТРАЖ')
    M.text('По предметам — несколько продавцов объединены в одну карточку.')
    if st.status~='live' then
        imgui.TextColored(DSP.theme.col('warn',1),DSP.utf8(
            'Внимание: источник не подтверждён как LIVE. Проверьте актуальность лавок.'))
    end
    imgui.SetNextItemWidth(math.min(610,imgui.GetContentRegionAvail().x))
    U.arb_search_buf=U.arb_search_buf or imgui.new.char[128]()
    if imgui.InputTextWithHint('##arb_search',DSP.utf8('Поиск предмета...'),U.arb_search_buf,128) then
        DSP.screens.set_page('arbitrage',1)
    end
    if M.button(U.arb_controls and 'Скрыть фильтры' or 'Фильтры',
        'arb_controls',180,U.arb_controls) then U.arb_controls=not U.arb_controls end
    if U.arb_controls then
        local changed=false
        changed=M.number('Бюджет на ВСЕ сделки ($). 0 = без лимита','arb_budget',f,'budget',0,290) or changed
        changed=M.number('Лимит на маршрут (шт.). 0 = без лимита','arb_maxqty',f,'max_qty',0,290) or changed
        changed=M.number('Мин. прибыль за маршрут ($)','arb_profit',f,'min_profit',0,290) or changed
        changed=M.number('Мин. ROI (%)','arb_roi',f,'min_roi',0,290) or changed
        changed=M.number('Макс. возраст снимка (сек.)','arb_age',f,'max_age',0,290) or changed
        changed=M.toggle('Разрешить частичные сделки',f,'allow_partial',true) or changed
        changed=M.toggle('Включать записи без времени',f,'include_unknown',true) or changed
        if changed then DSP.market.invalidate_arbitrage(); DSP.save_settings(); DSP.screens.set_page('arbitrage',1) end
    end
    local groups=DSP.market.arbitrage_grouped()
    local totals=DSP.market.arbitrage_group_totals(groups)
    M.text(tostring(totals.items)..' предметов | '..tostring(totals.routes)..' маршрутов | '..tostring(totals.planned)..' шт. в плане')
    imgui.TextColored(DSP.theme.col('good',1),DSP.utf8('Ожидаемая прибыль: +'..DSP.money(totals.profit)))
    M.text('Важно: «Скупают» = спрос по снимку, «План» = сколько рассчитано для сделок.')
    M.text('Фактическое количество проверяйте в игре: рынок может устареть.')
    local query=DSP.lower(DSP.trim(DSP.to_cp(ffi.string(U.arb_search_buf))))
    local visible={}
    for _,g in ipairs(groups) do
        if query=='' or DSP.lower(g.name):find(query,1,true) then visible[#visible+1]=g end
    end
    if #visible==0 then M.text('Совпадений нет. Обновите рынок или ослабьте фильтры.') end
    local first,last=DSP.screens.pager(#visible,4,'arbitrage')
    for i=first,last do render_group(visible[i],i) end
    imgui.Separator()
    local chosen=summarize_selection(groups)
    M.title('МОЙ ПЛАН  /  '..chosen.count..' СВЯЗОК')
    M.text('Выбрано: '..chosen.qty..' шт. | Нужно денег: '..DSP.money(chosen.cost))
    imgui.TextColored(DSP.theme.col('good',1),DSP.utf8('Прибыль: +'..DSP.money(chosen.profit)))
    M.text('Выбор — чеклист для похода по лавкам; покупки не выполняются автоматически.')
end
U.market_tab=U.arbitrage_tab
function U.lavki_tab()
    U.header()
    local shops=DSP.market.shops_list()
    local first,last=DSP.screens.pager(#shops,7,'lavki')
    if #shops==0 then M.text('Лавки не загружены. Обновите рынок.') end
    for i=first,last do
        local shop=shops[i]
        local number=shop.num or '?'
        imgui.Separator()
        M.title('ЛАВКА #'..tostring(number)..'  |  '..tostring(shop.owner or '?'))
        local fresh=DSP.market.offer_freshness(shop.ts or shop.updated_at)
        M.text('Данные: '..tostring(fresh)..'  |  Продаёт: '..tostring(shop.sell_count or 0)..'  |  Скупает: '..tostring(shop.buy_count or 0))
        if M.button('Отметить на карте','shop_mark'..i,225) then DSP.market.mark_shop(number) end
        M.inline()
        if M.button(U.lavki_expanded[number] and 'Свернуть' or 'Товары','expand_shop'..i,195) then
            U.lavki_expanded[number]=not U.lavki_expanded[number]
        end
        if (shop.buy_count or 0)>0 and M.button('Копировать скупку +1$','copy_shop'..i,320) then
            local n,err=DSP.market.copy_shop_skupka(number,nil,1)
            DSP.notify(n and ('Скопировано позиций: '..n) or tostring(err))
        end
        if U.lavki_expanded[number] then
            for _,side in ipairs({'sell','buy'}) do
                M.title(side=='sell' and 'Продаёт вам:' or 'Скупает у вас:')
                for _,entry in ipairs(shop[side..'_offers'] or {}) do
                    local it=entry.offer
                    M.text(entry.row.display..'  |  '..DSP.money(it.price or 0)..' за шт. | '..tostring(it.qty or 0)..' шт.')
                end
            end
        end
    end
end
