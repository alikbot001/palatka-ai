-- Native resale view; provenance distinguishes history, orders and estimates.
return function(A)
local g=A.ui
local settings
local function popularity(row,full)
    local p=row.popularity
    if p.kind=='market_sales'then
        local label='Продано за 30 дней: '..g.money(p.market_qty_30d)..' шт.'
        if full then
            g.wrapped('По данным Market Helper | '..label)
            g.wrapped('Обновление источника: '..g.age(p.market_updated_at)..' назад')
        else g.caption(label)end
    elseif p.kind=='own_sales'then
        g.wrapped('Ваши записи за 7 дней: '..g.money(p.own_qty)..' шт. / '..p.own_events..' продаж')
    elseif p.kind=='buy_orders'then
        g.wrapped('Заявки на скупку: '..p.buyer_shops..' лавки, '..g.money(p.buyer_qty)..' шт.')
    else g.wrapped('Скорость продаж неизвестна')end
    if full then g.wrapped('Заявки показывают спрос, а прошлые продажи не гарантируют будущий сбыт.')end
end
local function entry(row,index)
    local B=A.host.imgui
    g.caption(row.name);g.caption('ID '..row.id..' | '..row.currency..' за шт.')
    g.wrapped('Купить в лавке #'..row.seller.shop..': '..g.money(row.buy_price))
    g.wrapped('Цель продажи: '..g.money(row.sell_price))
    g.wrapped('Прибыль: ~'..g.money(row.profit)..' '..row.currency)
    g.wrapped('Объём: '..g.money(row.qty)..' шт. | +'..string.format('%.1f',row.roi_bp/100)..'%')
    popularity(row,false)
    if g.button('Посмотреть расчёт##pa_resale_'..index,B.ImVec2(-1,0))then A.select_resale(index)end
end
local function details(row)
    local B=A.host.imgui
    g.item_title(row);B.Separator()
    g.quote('1. Купить у продавца',row.seller,row.buy_price,row.currency)
    g.wrapped('Есть по снимку: '..g.money(row.seller_qty)..' шт.')
    if g.button('Найти лавку #'..row.seller.shop..'##pa_resale_find',B.ImVec2(-1,0))then A.track_resale()end
    B.Separator();g.wrapped('2. Оценка перепродажи')
    g.wrapped('Другие продавцы: '..row.peer_count..' | '..g.money(row.peer_price or row.reference_price)..' '..row.currency)
    if row.history_price then g.wrapped('Цена рынка по источнику: '..g.money(row.history_price)..' '..row.currency)end
    g.wrapped('Цель продажи: '..g.money(row.sell_price)..' '..row.currency..' за шт.')
    popularity(row,true);B.Separator()
    g.wrapped('3. Расчёт на '..g.money(row.qty)..' шт.')
    for _,field in ipairs({{'Затраты','cost'},{'Выручка','gross'},{'Комиссия','fee'},{'После комиссии','net'}})do
        g.wrapped(field[1]..': '..g.money(row[field[2]])..' '..row.currency)
    end
    g.wrapped('Доходность: ~'..string.format('%.2f',row.roi_bp/100)..'% после комиссии')
    if A.open_purchase and g.button('Записать закупку##pa_note_purchase',B.ImVec2(-1,0))then A.open_purchase(row)end
    g.wrapped('Запись закупки — ручная заметка. Скрипт не покупает товар и не выставляет его автоматически.')
end
function A.workspace_rows(tab)
    if tab=='resale'then return A.current_resale()end
    A.current_book_view=A.purchases_view()
    return A.current_book_view.lots or{}
end
function A.workspace_body(tab,rows,selected,show_details)
    if tab=='purchases'then
        if A.draw_purchases then A.draw_purchases(rows,A.current_book_view or{})end
        return
    end
    if show_details then details(selected)
    elseif #rows>0 then g.list(rows,'pa_resale_row',entry,2)
    elseif A.busy or A.resale_busy then g.wrapped('Считаю цены и спрос...')
    else
        g.wrapped('Подходящих вариантов пока нет')
        local r=A.resale_report
        if #(A.resale_results or{})>0 then g.wrapped('Срок данных истёк. Обновите расчёт.')
        elseif not r then g.wrapped('Нажмите «Обновить расчёт», чтобы загрузить лавки.')
        elseif r.offers==0 then g.wrapped('Свежих предложений с ценой и количеством на этом сервере нет.')
        else
            g.wrapped('Проверено: '..r.shops..' лавок, '..r.offers..' предложений.')
            for _,field in ipairs({{'Мало независимых продавцов','no_reference'},{'Нет разницы в цене','no_margin'},
                {'Фильтр спроса','no_demand'},{'Порог прибыли','below_roi'},{'Бюджет или лимит количества','budget_or_qty'}})do
                if (r[field[2]]or 0)>0 then g.wrapped(field[1]..': '..r[field[2]])end
            end
        end
        g.wrapped('Порог: '..string.format('%.1f',A.resale_options.min_roi_bp/100)..'% после комиссии. Ходовость учитывается первой; скорость без статистики неизвестна.')
        if g.button('Обновить расчёт##pa_resale_refresh',A.host.imgui.ImVec2(-1,0))then g.calculate(true)end
    end
    if A.resale_error then g.wrapped(A.resale_error)end
    if A.demand_error then g.wrapped('Статистика 30 дней недоступна: '..A.demand_error)end
end
local function ready()
    if settings then return end
    local B=A.host.imgui
    settings={roi=B.new.float(A.resale_options.min_roi_bp/100),qty=B.new.char[32](tostring(A.resale_options.max_qty)),
        popular=B.new.bool(A.resale_options.popular_only)}
end
function A.resale_settings()
    ready();local B=A.host.imgui
    g.wrapped('Перепродажа: минимальная прибыль, %')
    if B.InputFloat('##pa_resale_roi',settings.roi,1,5,'%.1f')then A.follow_market=false;A.invalidate()end
    g.wrapped('Максимум штук на один товар')
    if B.InputText('##pa_resale_qty',settings.qty,32)then A.follow_market=false;A.invalidate()end
    if B.Checkbox(A.host.utf8('Только с признаками спроса'),settings.popular)then A.follow_market=false;A.invalidate()end
end
function A.apply_resale_settings()
    ready()
    local roi=tonumber(settings.roi[0]);local raw=A.host.input_string(settings.qty)
    local qty=raw:match('^%d+$')and A.engine.integer(raw,1,1000000000)
    if not roi or roi~=roi or roi<0 or roi>100 or not qty then return false,'Неверный порог прибыли или количество'end
    A.resale_options.min_roi_bp=math.floor(roi*100+0.5);A.resale_options.max_qty=qty
    A.resale_options.popular_only=settings.popular[0]==true
    return true
end
return A
end
