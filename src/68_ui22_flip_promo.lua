-- v2.2.4: practical reseller workstation / separate user opt-in promotion UI.
local ffi=require('ffi')
local V,M,F,P=DSP.ui22,DSP.mobile,DSP.flip,DSP.promo
local function b(label,id,width,active,primary)return V.button(label,'flip24_'..id,width,active,primary)end
local function save()if not DSP.save_settings()then V.flip_error='Не удалось сохранить настройки';return false end
    if M.defer_save then M.defer_save() end;return true end
local function money(n)return DSP.money(n or 0)end
local function fixed(s,w)return V.fit(tostring(s),math.max(1,w))end
local function row_price(r,w)
    return fixed('Спрос: '..money(r.buy and r.buy.best or 0)..' · Предложения: '..money(r.sell and r.sell.med or 0),w)
end
local function risk_label(n)
    return ({[0]='низкий',[1]='умеренный',[2]='высокий',[3]='очень высокий'})[n]or'нет оценки'
end
local function data_groups()
    if DSP.market.arbitrage_grouped_ui then return DSP.market.arbitrage_grouped_ui() end
    return DSP.market.arbitrage_grouped() or{},'ready'
end
local function open_arb(item)
    local g=item.group
    if not g then return end
    local st=DSP.market.state or{}
    V.arb_item=g.key;V.arb_snapshot=tostring(st.sid)..'/'..tostring(st.version)
    V.arb_server=st.sid;V.arb_detail_group=g;V.arb_snapshot_time=os.time()
    V.arb_route=false;V.arb_tab='sell';V.arb_best_error=nil;V.arb_verify=nil
    V.arb_sellers={};V.arb_buyers={};V.arb_revision=(V.arb_revision or 0)+1
    for _,o in ipairs(g.sellers or{})do V.arb_sellers[DSP.market.offer_key(o)]=true end
    for _,o in ipairs(g.buyers or{})do V.arb_buyers[DSP.market.offer_key(o)]=true end
    V.open_popup('Арбитраж','arb_details')
end
local function opportunities()
    local groups,status=data_groups()
    if status=='loading' then V.muted('Расчёт рынка...')end
    if status=='error' then V.red('Ошибка подготовки рынка')end
    V.muted('Найдено по снимку API. Это НЕ совершённые сделки и НЕ гарантированный остаток.')
    local query,edited=V.search('flip','Предмет или название...',-1)
    if edited then V.reset_list('flip_results')end
    local snap=F.rank(groups)
    local visible=V.memo('flip_results',snap.version..'|'..DSP.lower(query),function()
        local out={};local needle=DSP.lower(query)
        for _,x in ipairs(snap.rows)do if needle==''or DSP.lower(x.name):find(needle,1,true)then out[#out+1]=x end end
        return out
    end)
    local sum=snap.summary
    V.muted(fixed('План: '..sum.count..' связок · Вложить '..money(sum.cost)..' · Прибыль ~ '..money(sum.profit),imgui.GetContentRegionAvail().x))
    if sum.limited then V.muted('Резерв капитала '..money(sum.reserve)..' · Свободно '..money(sum.unallocated))end
    V.list_rows('flip_results',visible,112,function(x,i)
        V.row('flip_'..i,112,function(w,l,t)
            M.thumbnail({name=x.name,id=x.group.row and x.group.row.id},30)
            V.at(l+40,t);V.text(fixed(x.name,w-205))
            V.at(l+40,t+27);V.muted(fixed('КУПИТЬ #'..tostring(x.seller_shop)..' '..money(x.buy_price)..' · СДАТЬ #'..tostring(x.buyer_shop)..' '..money(x.sell_price),w-205))
            V.at(l+40,t+54);V.green(fixed('~ +'..money(x.profit)..' · '..string.format('%.1f',x.roi)..'% · '..x.qty..' шт.',w-205))
            V.at(l+40,t+80);V.muted(fixed('Риск: '..risk_label(x.risk)..' · '..(x.reason~='' and x.reason or 'проверьте в игре'),w-205))
            V.at(l+w-158,t+4)
            if b('Разобрать >','detail_'..i,154)then
                V.flip_focus=x;V.open_popup('Разбор сделки','flip_detail')
            end
            V.at(l+w-158,t+57)
            if b('Маршрут','route_'..i,154)then open_arb(x)end
        end)
    end,{footer=function()V.muted('Скорость продажи неизвестна: число скупщиков не равно реальному обороту.')end})
end
local function portfolio()
    local s=F.settings()
    V.muted('Бюджет — сумма доступных денег. Ноль означает расчёт без ограничения.')
    V.muted('Капитал для торговли ($)')
    if M.compact_number(s,'capital','flip_capital',210,0)then F.invalidate();save()end
    V.muted('Резерв на непредвиденные расходы')
    for _,pct in ipairs({0,10,20,30})do
        if b(pct..'%','reserve_'..pct,70,s.reserve_pct==pct)then s.reserve_pct=pct;F.invalidate();save()end
        V.inline(4)
    end
    V.text('Максимум на один предмет')
    for _,pct in ipairs({20,35,50,100})do
        if b(pct..'%','exposure_'..pct,74,s.max_position_pct==pct)then s.max_position_pct=pct;F.invalidate();save()end
        V.inline(4)
    end
    V.text('Минимальный ROI')
    for _,pct in ipairs({0,5,10,20})do
        if b(pct..'%','roi_'..pct,74,s.min_roi==pct)then s.min_roi=pct;F.invalidate();save()end
        V.inline(4)
    end
    V.text('Показывать риск до уровня')
    for _,x in ipairs({{1,'Умер.'},{2,'Высок.'},{3,'Все'}})do
        if b(x[2],'risk_'..x[1],100,s.max_risk==x[1])then s.max_risk=x[1];F.invalidate();save()end
        V.inline(4)
    end
    V.text('Рейтинг по:')
    for _,x in ipairs({{'profit','Прибыль'},{'roi','ROI'},{'unit','За шт.'}})do
        if b(x[2],'sort_'..x[1],115,s.sort==x[1])then s.sort=x[1];F.invalidate();save()end
        V.inline(4)
    end
    V.muted('Ограничения считаются на весь план, не отдельно на каждый маршрут.')
end
local function watchlist()
    local s=F.settings()
    if b(s.alerts and 'Оповещения: ВКЛ' or 'Оповещения: ВЫКЛ','watch_enabled',225,s.alerts)then
        s.alerts=not s.alerts;save()
    end
    V.muted('Цена из API; не значит, что лот ещё доступен. Не чаще одного уведомления в 5 минут.')
    local rows={}
    for key,rule in pairs(s.watch)do rows[#rows+1]={key=key,rule=rule}end
    table.sort(rows,function(a,b)return a.key<b.key end)
    V.list_rows('flip_watch',rows,96,function(x,i)
        V.row('watch_'..i,96,function(w,l,t)
            V.at(l,t);V.text(fixed(x.rule.name,w-150))
            V.at(l,t+30);V.muted(fixed('Порог '..money(x.rule.max_price)..' · сервер '..tostring(x.rule.server),w-150))
            local st=DSP.market.state or{}
            local actual=(st.by_key or{})[x.key]
            V.at(l,t+56);V.muted(actual and row_price(actual,w-150)or'На текущем снимке отсутствует')
            V.at(l+w-142,t+22)
            if b('Удалить','watch_delete_'..i,138)then
                V.flip_remove_watch=x.key;V.open_popup('Удалить наблюдение?','flip_watch_delete')
            end
        end)
    end,{footer=function()V.muted('Не выполняет покупок и не отправляет дополнительные запросы.')end})
end
local function pricing()
    local query,edited=V.search('flip_prices','Предмет для настройки цены',-1)
    if edited then V.reset_list('flip_prices')end
    local needle=DSP.lower(query)
    local st=DSP.market.state or{}
    local rows=V.memo('flip_price_rows',tostring(st.version)..'|'..needle,function()
        local out={}
        for _,r in ipairs(st.rows or{})do
            if r.sell and r.sell.count>0 and (needle=='' or DSP.lower(r.display):find(needle,1,true)) then out[#out+1]=r end
            if #out>=180 then break end
        end
        return out
    end)
    V.muted('Быстро / рынок / маржа — цены ОБЪЯВЛЕНИЙ; без известной себестоимости прибыль неизвестна.')
    V.list_rows('flip_prices',rows,100,function(r,i)
        V.row('price_'..i,100,function(w,l,t)
            V.at(l,t);V.text(fixed(r.display,w-170))
            V.at(l,t+30);V.muted(row_price(r,w-170))
            local fast=F.suggest_price(r,'fast');local regular=F.suggest_price(r,'market');local premium=F.suggest_price(r,'premium')
            V.at(l,t+60);V.muted(fixed('Быстро '..money(fast)..' · Рынок '..money(regular)..' · Маржа '..money(premium),w-170))
            V.at(l+w-160,t+26)
            if b('Настроить >','price_select_'..i,156)then
                V.flip_price_row=r;V.flip_cost={value=0};V.flip_cost_known=false
                V.open_popup('Цена для пресета','flip_price_modal')
            end
        end)
    end,{footer=function()V.muted('Последние 180 строк списка; используй поиск. Новых HTTP-запросов нет.')end})
end
local function earnings()
    local today=F.cash_summary(DSP.settings.trades,true)
    local all=F.cash_summary(DSP.settings.trades,false)
    V.text('Подтверждённые денежные потоки')
    for _,x in ipairs({{'Сегодня',today},{'Всего',all}})do
        V.text(x[1]..' · записей '..x[2].trades)
        V.muted('Получено денег '..money(x[2].cash_in)..' · Отдано '..money(x[2].cash_out))
        V.muted('Движение наличных '..money(x[2].cash_net))
        V.muted('Трейдов с предметами/оценкой: '..x[2].valued_trades)
    end
    V.red('Движение наличных НЕ равно прибыли: стоимость предметов и незакрытые позиции не учтены.')
    if b('Открыть полный журнал >','journal',265)then V.set_screen('logs')end
end
function V.flip_screen()
    local tabs={{'opportunities','Сделки'},{'portfolio','Капитал'},{'watch','Охота'},
        {'pricing','Цены'},{'earnings','Итоги'}}
    V.flip_tab=V.flip_tab or 'opportunities'
    V.heading('Перепродажа',function()
        if b('Арбитраж >','main_arb',146)then V.set_screen('arbitrage')end
    end,148)
    local w=imgui.GetContentRegionAvail().x
    local compact=w<700
    if compact then
        local current=1
        for i,x in ipairs(tabs)do if x[1]==V.flip_tab then current=i end end
        if b('<','flip_tab_prev',46)then current=(current-2)%#tabs+1 end
        V.inline(3)
        if b(tabs[current][2],'flip_tab_name',160,true)then current=current%#tabs+1 end
        V.inline(3)
        if b('>','flip_tab_next',46)then current=current%#tabs+1 end
        V.flip_tab=tabs[current][1]
    else
        for i,x in ipairs(tabs)do
            if b(x[2],'flip_tab_'..i,math.floor((w-24)/5),V.flip_tab==x[1])then
                V.flip_tab=x[1];V.reset_list('flip_results')
            end
            if i<#tabs then V.inline(6)end
        end
    end
    if V.flip_error then V.red(V.flip_error)end
    if V.flip_tab=='opportunities'then opportunities()
    elseif V.flip_tab=='portfolio'then V.list('flip_portfolio',function()portfolio()end)
    elseif V.flip_tab=='watch'then watchlist()
    elseif V.flip_tab=='pricing'then pricing()
    else V.list('flip_earnings',function()earnings()end)end
end
local function fill_buffer(buf,value,max)
    local utf=DSP.to_u8(tostring(value or ''))
    ffi.fill(buf,max);ffi.copy(buf,utf:sub(1,max-1))
end
local function input_buffer(label,id,buf,max)
    imgui.SetNextItemWidth(-1)
    return imgui.InputTextWithHint('##prom24_'..id,DSP.utf8(label),buf,max)
end
local function promo_edit(index)
    local item=P.settings().templates[index]
    V.promo_edit_index=index
    if not V.promo_name then V.promo_name=imgui.new.char[80]();V.promo_text=imgui.new.char[768]()end
    fill_buffer(V.promo_name,item and item.name or '',80)
    fill_buffer(V.promo_text,item and item.text or '/vr ',768)
    V.promo_interval={value=item and item.interval or 300}
    V.open_popup('Шаблон рекламы','promo_edit')
end
function V.promo_screen()
    V.text('Авто-пиар · Палатка AI')
    local total=P.session_count
    V.muted('Отправлено за сессию: '..total..' / '..P.MAX_SESSION..' · интервал минимум '..P.MIN_INTERVAL..' сек.')
    V.muted('Активируется вручную. Строки /vr, /fam, /gd, /s, /ad идут по очереди.')
    V.muted('Доступность каналов зависит от сервера, прав игрока и ограничений чата.')
    if P.running then
        if b('ОСТАНОВИТЬ','promo_stop',185,true,true)then P.stop()end
    else
        if b('Запустить авто-пиар','promo_start',210,false,true)then
            local ok,err=P.start();V.promo_error=ok and nil or err
        end
    end
    V.inline();if b('+ Шаблон','promo_new',155)then promo_edit(nil)end
    if V.promo_error or P.last_error then V.red(tostring(V.promo_error or P.last_error))end
    local rows=P.settings().templates
    V.list_rows('promo_list',rows,126,function(it,i)
        V.row('promo_row_'..i,126,function(w,l,t)
            V.at(l,t);V.text(fixed((it.auto and '[x] ' or '[ ] ')..it.name,w-170))
            V.at(l,t+28);V.muted(fixed(it.text,w-170))
            V.at(l,t+54);V.muted('Каждые '..tostring(it.interval or 300)..'с · '..#P.lines(it.text)..' строк по очереди')
            V.at(l,t+80)
            if b(it.auto and 'Авто: да' or 'Авто: нет','promo_toggle_'..i,118,it.auto)then
                it.auto=not it.auto
                if not save()then it.auto=not it.auto end
            end
            V.inline(4);if b('Отправить','promo_send_'..i,134)then
                local ok,err=P.send_once(i)
                V.promo_error=ok and nil or err
            end
            V.at(l+w-155,t+8)
            if b('Изменить','promo_edit_'..i,151)then promo_edit(i)end
            V.at(l+w-155,t+63)
            if b('Удалить','promo_del_'..i,151)then
                V.promo_delete=i;V.open_popup('Удалить шаблон?','promo_delete')
            end
        end)
    end,{footer=function()V.muted('Не отправляет сообщений, пока не нажата кнопка запуска.')end})
end
local previous_popups=V.popups
function V.popups()
    if previous_popups then previous_popups()end
    V.popup('Разбор сделки','flip_detail',function()
        local x=V.flip_focus
        if not x then imgui.CloseCurrentPopup();return end
        local st=DSP.market.state or{}
        if x.group and (x.group.row~=(st.by_key or{})[x.key]) then
            V.red('Рынок изменился. Откройте предложение заново.');V.cancel('flip_detail');return
        end
        V.text(x.name)
        V.muted('Купить '..x.qty..' шт. в #'..tostring(x.seller_shop)..' по '..money(x.buy_price))
        V.muted('Продать в скупку #'..tostring(x.buyer_shop)..' по '..money(x.sell_price))
        V.text('Затраты '..money(x.cost))
        V.text('Валовая выручка '..money(x.gross))
        V.text('Комиссия ~ '..money(x.fee))
        V.text('После комиссии ~ '..money(x.revenue))
        V.green('Потенциальная прибыль ~ '..money(x.profit)..' · ROI '..string.format('%.1f%%',x.roi))
        V.red('Риск '..risk_label(x.risk)..': '..x.reason)
        V.muted('Интерес рынка: '..F.market_interest(x.group and x.group.row))
        V.muted('Сверьте количества и готовность скупщика в игре ДО покупки.')
        if b('Метка продавца','flip_detail_sell',187)then DSP.market.mark_shop(x.seller_shop)end
        V.inline();if b('Метка скупщика','flip_detail_buy',188)then DSP.market.mark_shop(x.buyer_shop)end
        V.muted('Отслеживать цену входа (за шт.)')
        V.flip_watch_price=V.flip_watch_price or {value=x.buy_price}
        M.compact_number(V.flip_watch_price,'value','flip_watch_target',170,1)
        if b('Следить за ценой','flip_watch_add',208)then
            local ok,err=F.watch_set(x.key,x.name,V.flip_watch_price.value)
            V.flip_error=ok and nil or err
        end
        V.inline();V.cancel('flip_detail')
    end,{w=690,h=500,resizable=true})
    V.popup('Цена для пресета','flip_price_modal',function()
        local r=V.flip_price_row
        if not r then imgui.CloseCurrentPopup();return end
        V.text(r.display)
        local evidence=F.price_evidence(r)
        V.muted('API '..(evidence.api and money(evidence.api)or'нет')..' · Скупка '..(evidence.buy and money(evidence.buy)or'нет'))
        V.muted('ЦР '..(evidence.cr and money(evidence.cr)or'нет')..' · Открытая лавка '..(evidence.opened and money(evidence.opened)or'нет'))
        V.muted('Продано сегодня: '..(evidence.today and (money(evidence.today)..' · '..tostring(evidence.today_qty)..' шт.')or'нет подтверждённой истории'))
        V.muted('Неизвестная себестоимость не подменяется нулём.')
        if b(V.flip_cost_known and 'Себестоимость известна' or 'Себестоимость неизвестна','cost_toggle',300,V.flip_cost_known)then V.flip_cost_known=not V.flip_cost_known end
        if V.flip_cost_known then M.compact_number(V.flip_cost,'value','flip_cost_input',180,0)end
        local w=imgui.GetContentRegionAvail().x
        for i,mode in ipairs({{'fast','Быстро'},{'market','Рынок'},{'premium','Маржа'}})do
            local price,info=F.suggest_price(r,mode[1],V.flip_cost_known and V.flip_cost.value or nil)
            if b(mode[2]..' '..money(price),'price_mode_'..i,math.max(95,(w-16)/3))then
                if price then
                    V.flip_chosen_price=price;V.flip_chosen_key=r.key
                else V.flip_error=info end
            end
            if i<3 then V.inline(6)end
        end
        for _,pair in ipairs({{'cr','ЦР',evidence.cr},{'today','Сегодня',evidence.today},{'opened','Лавка',evidence.opened}})do
            if pair[3] and b(pair[2]..' '..money(pair[3]),'evidence_'..pair[1],174)then
                V.flip_chosen_price=pair[3];V.flip_chosen_key=r.key
            end
            V.inline(4)
        end
        V.text('Выбранная цена: '..(V.flip_chosen_key==r.key and money(V.flip_chosen_price) or 'нет'))
        V.muted('Подставление возможно только для существующей позиции активного пресета.')
        if b('Применить в продажу','price_apply',235)then
            local found=DSP.presets.find('sell',r.key)
            if not found then V.flip_error='Сначала добавьте предмет в пресет продажи'
            elseif V.flip_chosen_key~=r.key then V.flip_error='Выберите цену'
            elseif V.flip_cost_known and math.floor(V.flip_chosen_price*(10000-math.max(0,math.min(10000,tonumber(DSP.settings.tax_bp)or 200)))/10000)<(tonumber(V.flip_cost.value)or 0) then
                V.flip_error='Цена ниже себестоимости после комиссии'
            else
                local ok,err=DSP.presets.update('sell',found,{price=V.flip_chosen_price})
                V.flip_error=ok and nil or err
                if ok then imgui.CloseCurrentPopup()end
            end
        end
        V.inline();V.cancel('flip_price_modal')
        if V.flip_error then V.red(V.flip_error)end
    end,{w=650,h=485,resizable=true})
    V.popup('Удалить наблюдение?','flip_watch_delete',function()
        V.text('Удалить наблюдение?')
        if b('Удалить','watch_delete_confirm',160)then
            local ok,err=F.watch_remove(V.flip_remove_watch)
            V.flip_error=ok and nil or err
            if ok then imgui.CloseCurrentPopup()end
        end
        V.inline();V.cancel('flip_watch_delete')
    end,{w=450,h=230})
    V.popup('Удалить шаблон?','promo_delete',function()
        V.text('Удалить выбранный шаблон?')
        if b('Удалить','promo_delete_yes',170)then
            local ok=P.remove(V.promo_delete)
            if ok then imgui.CloseCurrentPopup()else V.promo_error='Не удалось сохранить удаление'end
        end
        V.inline();V.cancel('promo_delete')
    end,{w=460,h=240})
    V.popup('Шаблон рекламы','promo_edit',function()
        V.text('Название шаблона');input_buffer('Название','name',V.promo_name,80)
        V.muted('Несколько строк: /vr, /fam, /gd, /s или /ad — по одной раз в интервал.')
        imgui.SetNextItemWidth(-1)
        imgui.InputTextMultiline('##prom24_text',V.promo_text,768,imgui.ImVec2(-1,116))
        if b('Вставить лавку','promo_insert_shop',206)then
            local raw=ffi.string(V.promo_text)
            local marker=' {лавка}'
            if #raw+#marker<767 then fill_buffer(V.promo_text,raw..marker,768) end
        end
        local shop,reason=P.own_shop_number()
        V.muted('Моя лавка: '..(shop and tostring(shop) or 'не задан')..' ('..reason..')')
        local ps=P.settings()
        V.promo_shop_number=V.promo_shop_number or {value=tonumber(ps.shop_number) or 0}
        M.compact_number(V.promo_shop_number,'value','promo_shop_num',126,0)
        V.inline(4)
        if b('Запомнить №','promo_shop_save',160)then
            local ok,err=P.set_shop_number(V.promo_shop_number.value)
            V.promo_error=ok and nil or err
        end
        V.muted('Маркер {лавка} -> кликабельное :lavkaID:. {номер} -> просто цифры.')
        V.text('Интервал в секундах: 180–3600')
        M.compact_number(V.promo_interval,'value','promo_interval',175,180)
        if b('Сохранить','promo_save_edit',168,true)then
            local name=DSP.to_cp(ffi.string(V.promo_name))
            local text=DSP.to_cp(ffi.string(V.promo_text))
            local ok,err
            if V.promo_edit_index then
                ok,err=P.update(V.promo_edit_index,name,text,V.promo_interval.value)
            else ok,err=P.add(name,text,V.promo_interval.value)end
            if ok then V.promo_error=nil;imgui.CloseCurrentPopup()
            else V.promo_error=err end
        end
        V.inline();V.cancel('promo_edit')
        if V.promo_error then V.red(V.promo_error)end
    end,{w=650,h=550,resizable=true})
end
