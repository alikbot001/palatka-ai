-- Market cards preserve buy/sell meaning and never truncate the item name.
local ffi=require('ffi')
local M=DSP.mobile
local U=DSP.ui
local function add(row,kind)
    local ok,err=DSP.presets.add(row,kind)
    DSP.notify(ok and 'Добавлено в набор' or tostring(err))
end
local function mark(o,id,label)
    if M.button(label..' #'..tostring(o.shop),id,330) then DSP.market.mark_shop(o.shop) end
end
local function offers(row,kind)
    local side=kind=='buy' and row.sell or row.buy
    M.title(kind=='buy' and 'КУПИТЬ СЕБЕ (лавка продаёт)' or 'ПРОДАТЬ СВОЁ (лавка скупает)')
    for i,o in ipairs(side.offers or {}) do
        M.text(DSP.money(o.price)..' x'..tostring(o.qty)..' | '..tostring(o.owner or '?'))
        local fresh=DSP.market.offer_freshness(o.ts)
        M.text('Свежесть: '..tostring(fresh))
        mark(o,'offer'..row.key..kind..i,'Найти лавку')
        imgui.Separator()
    end
    if #(side.offers or {})==0 then M.text('Предложений нет') end
end
function U.detail(row)
    M.title('КАРТОЧКА ТОВАРА')
    M.text(row.display)
    M.text(DSP.market.market_label_for(row) or '')
    if M.button('Добавить в мою скупку','detail_add_buy',400) then add(row,'buy') end
    M.inline()
    if M.button('Добавить в мою продажу','detail_add_sell',420) then add(row,'sell') end
    offers(row,'buy')
    offers(row,'sell')
end
function U.finder_tab()
    U.header()
    imgui.SetNextItemWidth(math.min(800,imgui.GetContentRegionAvail().x))
    if imgui.InputTextWithHint('##mobile_search',DSP.utf8('Название товара...'),U.finder_search_buf,128) then
        U.finder_query=DSP.to_cp(ffi.string(U.finder_search_buf)); DSP.screens.set_page('search',1)
    end
    if M.button('Очистить поиск','clear_search',300) then
        ffi.fill(U.finder_search_buf,128); U.finder_query=''; DSP.screens.set_page('search',1)
    end
    local matches=DSP.market.find_item(U.finder_query)
    M.text('Найдено товаров: '..#matches)
    if U.selected then
        local row=DSP.market.state.by_key[U.selected]
        if M.button('< К результатам','back_search',340) then U.selected=nil end
        if row then U.detail(row) end
        return
    end
    local first,last=DSP.screens.pager(#matches,6,'search')
    if #matches==0 then M.text('Введите название или обновите рынок. Источники могут временно не отвечать.') end
    for i=first,last do
        local row=matches[i]
        M.text(row.display)
        M.text('Купить себе: '..(row.sell.count>0 and DSP.money(row.sell.best) or 'нет продавцов')
            ..' | Продать своё: '..(row.buy.count>0 and DSP.money(row.buy.best) or 'нет скупщиков'))
        if M.button('Все предложения','open_item'..i,350) then U.selected=row.key end
        M.inline()
        if M.button('+ В скупку','search_buy'..i,260) then add(row,'buy') end
        M.inline()
        if M.button('+ В продажу','search_sell'..i,280) then add(row,'sell') end
        imgui.Separator()
    end
end
-- A touch-first arbitrage plan: stock, demand and allocated quantity stay distinct.
function U.arbitrage_tab()
    U.header()
    local f=DSP.settings.arb_filters or {}
    DSP.settings.arb_filters=f
    M.title('АРБИТРАЖ / ПЛАН СДЕЛОК')
    local state=DSP.market.state
    local tax=(tonumber(DSP.settings.tax_bp) or 200)/100
    M.text(string.format('Комиссия %.2f%% | Mobile %s | данные: %s',
        tax,tostring(state.sid),DSP.market.freshness()))
    if state.status=='cache' or state.status=='error' then
        imgui.TextColored(DSP.theme.col('warn',1),
            DSP.utf8('ВНИМАНИЕ: офлайн-база. Перед сделкой обновите рынок.'))
    else
        M.text('Остатки берутся из последнего снимка рынка. Перед сделкой проверьте лавку.')
    end
    local changed=false
    if M.button(U.arb_controls and 'Скрыть настройки' or 'Настроить бюджет и фильтры',
            'arb_controls',470,false,'primary') then U.arb_controls=not U.arb_controls end
    if U.arb_controls then
        M.title('ЛИМИТЫ')
        changed=M.number('Общий бюджет ($), 0 = без лимита','arb_budget',f,'budget',0,380) or changed
        changed=M.number('Макс. шт. на одну связку, 0 = всё','arb_maxqty',f,'max_qty',0,380) or changed
        changed=M.number('Минимальная прибыль на связку ($)','arb_profit',f,'min_profit',0,380) or changed
        changed=M.number('Минимальная доходность (%)','arb_roi',f,'min_roi',0,380) or changed
        changed=M.number('Возраст предложения (сек), 0 = любой','arb_age',f,'max_age',0,380) or changed
        changed=M.toggle('Покупать доступную часть партии',f,'allow_partial',true) or changed
        changed=M.toggle('Показывать предложения без времени',f,'include_unknown',true) or changed
        M.title('СОРТИРОВКА')
        for i,label in ipairs({'Общая прибыль','Прибыль / шт.','Доходность (%)'}) do
            if M.button(label,'arb_sort'..i,300,(tonumber(f.sort) or 1)==i) then
                f.sort=i; changed=true
            end
            if i<3 then M.inline() end
        end
        if changed then DSP.market.invalidate_arbitrage(); DSP.save_settings(); DSP.screens.set_page('arbitrage',1) end
    end
    local rows=DSP.market.arbitrage_filtered()
    local total_cost,total_profit,total_qty=0,0,0
    for _,e in ipairs(rows) do
        total_cost=total_cost+(e.total_cost or 0)
        total_profit=total_profit+(e.net_profit or 0)
        total_qty=total_qty+(e.tradable_qty or 0)
    end
    imgui.Separator()
    M.title('НАЙДЕНО: '..#rows..'  |  ОБЪЁМ: '..total_qty..' ШТ.')
    M.text('Общие затраты: '..DSP.money(total_cost))
    imgui.TextColored(DSP.theme.col('good',1),
        DSP.utf8('Чистая прибыль плана: +'..DSP.money(total_profit)))
    M.text('Объём каждого продавца и скупщика учитывается только один раз.')
    if (tonumber(f.budget) or 0)>0 then
        M.text('Лимит: '..DSP.money(f.budget)..' | Остаток: '..DSP.money(math.max(0,f.budget-total_cost)))
    end
    local first,last=DSP.screens.pager(#rows,6,'arbitrage')
    if #rows==0 then M.text('Сделок нет. Обновите рынок или ослабьте фильтры.') end
    for i=first,last do
        local e=rows[i]
        imgui.Separator()
        M.title(tostring(i)..'. '..tostring(e.name))
        imgui.TextColored(DSP.theme.col('good',1),
            DSP.utf8('ПРИБЫЛЬ  +'..DSP.money(e.net_profit or 0)..
                '     ROI  '..string.format('%.1f%%',e.roi or 0)))
        M.text('Купить '..tostring(e.tradable_qty or 0)..' шт. за '..DSP.money(e.total_cost or 0))
        M.text('Продаёт: '..tostring(e.qty_seller or e.sell_offer.qty or 0)..
            ' шт. / '..DSP.money(e.p_buy)..' за шт. | лавка #'..tostring(e.sell_offer.shop))
        M.text('Скупает: '..tostring(e.qty_buyer or e.buy_offer.qty or 0)..
            ' шт. / '..DSP.money(e.p_sell)..' за шт. | лавка #'..tostring(e.buy_offer.shop))
        M.text('Продавец: '..tostring(e.sell_offer.owner or '?')..
            ' | Скупщик: '..tostring(e.buy_offer.owner or '?'))
        if e.partial or e.shared_stock then
            imgui.TextColored(DSP.theme.col('warn',1),DSP.utf8(
                'Выделено '..tostring(e.tradable_qty)..' из '..tostring(e.available_qty or 0)..
                ' возможных шт. (лимит / другие сделки)'))
        end
        local gross=(e.tradable_qty or 0)*(e.p_sell or 0)
        M.text('Выручка: '..DSP.money(gross)..' | Комиссия: '..DSP.money(gross-(e.net_revenue or 0)))
        local a=DSP.market.offer_freshness(e.sell_age or e.sell_offer.ts)
        local b=DSP.market.offer_freshness(e.buy_age or e.buy_offer.ts)
        M.text('Обновление: продавец — '..tostring(a)..', скупщик — '..tostring(b))
        if M.button('1. Отметить лавку продавца #'..tostring(e.sell_offer.shop),
                'arb_sell'..i,540,false,'secondary') then
            DSP.market.mark_shop(e.sell_offer.shop)
        end
        if M.button('2. Отметить лавку скупщика #'..tostring(e.buy_offer.shop),
                'arb_buy'..i,540,false,'secondary') then
            DSP.market.mark_shop(e.buy_offer.shop)
        end
    end
end
U.market_tab=U.arbitrage_tab
-- Shop list uses a vertical card for each stall, then opens the full item search.
function U.lavki_tab()
    U.header()
    local shops=DSP.market.shops_list()
    local first,last=DSP.screens.pager(#shops,6,'lavki')
    if #shops==0 then M.text('Лавки не загружены. Обновите рынок.') end
    for i=first,last do
        local shop=shops[i]
        local number=shop.num or '?'
        M.title('ЛАВКА #'..tostring(number))
        M.text(shop.owner or '?')
        local fresh=DSP.market.offer_freshness(shop.ts or shop.updated_at)
        M.text('Свежесть: '..tostring(fresh))
        if M.button('Найти лавку #'..tostring(number),'shop_mark'..i,400) then DSP.market.mark_shop(number) end
        if (shop.buy_count or 0)>0 and M.button('Скопировать скупку +1$','copy_shop'..i,460) then
            local n,err=DSP.market.copy_shop_skupka(number,nil,1)
            DSP.notify(n and ('Скопировано позиций: '..n) or tostring(err))
        end
        local expanded=U.lavki_expanded[number]
        if M.button(expanded and 'Скрыть товары' or 'Показать товары','expand_shop'..i,400) then
            U.lavki_expanded[number]=not expanded
        end
        if expanded then
            for _,side in ipairs({'sell','buy'}) do
                M.title(side=='sell' and 'Продаёт вам:' or 'Скупает у вас:')
                for _,entry in ipairs(shop[side..'_offers'] or {}) do
                    local it=entry.offer
                    M.text(entry.row.display..' | '..DSP.money(it.price or 0)..' x'..tostring(it.qty or 0))
                end
            end
        end
        imgui.Separator()
    end
end
