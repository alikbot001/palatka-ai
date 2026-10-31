-- Observed stalls are separate from API snapshots and never rewrite preset prices implicitly.
local ffi=require('ffi')
local V=DSP.ui21
local S={side='sell',selected={sell={},buy={}}}
V.scan_selection=S.selected
local function b(label,id,width,active)return V.button(label,'scan_'..id,width,active)end
local function count(side)
    local n=0;for _ in pairs(S.selected[side])do n=n+1 end;return n
end
local function picked(side)
    local result={};for key,value in pairs(S.selected[side])do result[key]=value end;return result
end
local function snapshot()
    return DSP.shop_scan and DSP.shop_scan.snapshot()or{sell={},buy={},revision=0,updated=0}
end
local function identity(scan)
    return table.concat({tostring(scan.owner or ''),tostring(scan.num or ''),tostring(scan.generation or 0),tostring(scan.server or '')},'/')
end
local function synchronize(scan)
    local current=identity(scan)
    if S.identity~=current then
        S.identity=current;S.selected={sell={},buy={}};V.scan_selection=S.selected
        S.revision=nil;S.items={sell={},buy={}};S.manager_side=nil
    end
    if S.revision~=scan.revision then
        S.revision=scan.revision
        for _,side in ipairs({'sell','buy'})do
            local valid={}
            for _,row in ipairs(scan[side]or{})do
                valid[row.key]=tostring(row.item_id or row.id or '')..'/'..DSP.item_key(row.name or '',row.ench or 0)
            end
            for key in pairs(S.selected[side])do
                if not valid[key]or valid[key]~=S.items[side][key]then S.selected[side][key]=nil end
            end
            S.items[side]=valid
        end
    end
end
local function choose_operation(action)
    if count(S.side)==0 then DSP.notify('Выберите позиции лавки');return end
    local scan=snapshot()
    S.modal={action=action,side=S.side,target_side=S.side,index=DSP.presets.selected(S.side),
        selected=picked(S.side),mode='existing',identity=S.identity,revision=S.revision,
        generation=scan.generation,server=scan.server}
    S.markup=imgui.new.char[64]();ffi.copy(S.markup,'0',1)
    S.name=imgui.new.char[128]();S.error=nil
    V.open_popup(action=='prices'and'Обновить цены'or'Перенести в пресет','scan_preset')
end
-- The stall content must remain usable when the main window is resized.
-- For narrow widths, name, count and unit price take separate lines.
local function item_row(row,i)
    local narrow=V.compact(imgui.GetContentRegionAvail().x)
    local height=narrow and 86 or 60
    V.row('scan_'..tostring(row.key),height,function(w,x,y)
        local selected=S.selected[S.side][row.key]
        if b(selected and 'x' or ' ','select_'..tostring(row.key),38,selected) then
            S.selected[S.side][row.key]=not selected or nil
        end
        if w>=102 then
            V.at(x+44,y+3);DSP.mobile.thumbnail(row,30)
        end
        local text_x=x+(w>=102 and 82 or 43)
        local remaining=math.max(40,w-(w>=102 and 90 or 50))
        V.at(text_x,y+1)
        V.text(V.fit(row.name or row.display or '?',narrow and remaining or math.max(50,remaining-160)))
        V.at(text_x,y+26)
        V.muted(V.fit(row.qty_known and (tostring(row.qty)..' \xf8\xf2.')
            or '\xca\xee\xeb\xe8\xf7\xe5\xf1\xf2\xe2\xee: ?',remaining))
        local amount=tonumber(row.price) and row.price>0 and (DSP.money(row.price)..'/\xf8\xf2.')
            or '\xd6\xe5\xed\xe0: ?'
        if narrow then
            V.at(text_x,y+52)
            V.text(V.fit(amount,remaining))
        else
            V.at(x+math.max(0,w-154),y+9)
            V.text(V.fit(amount,148))
        end
    end)
end
local function toolbar(scan,key)
    local w=imgui.GetContentRegionAvail().x
    local actions={
        {label='\xc2\xf1\xe5',id='scan_select_all',width=62},
        {label='\xd1\xe1\xf0\xee\xf1',id='scan_select_none',width=82},
        {label='^',id='scan_scroll_up_'..key,width=55},
        {label='v',id='scan_scroll_down_'..key,width=55},
        {label='\xcc\xee\xe8 \xef\xf0\xe5\xf1\xe5\xf2\xfb',id='scan_presets',width=142},
        {label='\xc2 \xef\xf0\xe5\xf1\xe5\xf2',id='scan_copy',width=134},
        {label='\xce\xe1\xed\xee\xe2\xe8\xf2\xfc \xf6\xe5\xed\xfb',id='scan_prices',width=164},
    }
    -- A compact window only needs one primary action line at once. The
    -- extra controls stay accessible after tapping 'Actions'.
    if w<470 then
        local toggle=V.actions({{label=S.tools_open and ' - ' or ' + ',id='scan_more',width=60},
            {label='\xc2\xfb\xe1\xf0\xe0\xed\xee '..count(S.side),id='scan_sel_count',width=142}})
        if toggle.scan_more then S.tools_open=not S.tools_open end
        if not S.tools_open then
            local nav=V.actions({actions[3],actions[4]})
            if nav[actions[3].id]then V.queue_scroll(key,-1)end
            if nav[actions[4].id]then V.queue_scroll(key,1)end
            return
        end
    end
    local hits=V.actions(actions)
    if hits.scan_select_all then
        for _,row in ipairs(scan[S.side]or{})do S.selected[S.side][row.key]=true end
    end
    if hits.scan_select_none then S.selected[S.side]={};V.scan_selection=S.selected end
    if hits[actions[3].id] then V.queue_scroll(key,-1)end
    if hits[actions[4].id] then V.queue_scroll(key,1)end
    if hits.scan_presets then V.kind=S.manager_side or S.side;V.open_popup('\xcd\xe0\xe1\xee\xf0\xfb','presets')end
    if hits.scan_copy then choose_operation('copy')end
    if hits.scan_prices then choose_operation('prices')end
end
local function scan_summary(scan)
    local arb=DSP.local_arb
    local now=os.time()
    local stats=arb and arb.stats and arb.stats(now) or {shops=0,offers=0,mapped=0,unmapped=0}
    local scan_state,observed=DSP.live and DSP.live.scan_state and DSP.live.scan_state(scan)
    local saved_state=(scan_state=='saved' or scan_state=='saved_unmapped')
    local confirmed,saved_row=false,nil
    if arb and arb.has_shop then
        local ok,a,b=pcall(arb.has_shop,scan)
        if ok then confirmed,saved_row=a,b end
    end
    local w=math.max(30,imgui.GetContentRegionAvail().x)
    imgui.Separator()
    if confirmed and saved_state then
        local mapped=tonumber((saved_row and saved_row.num) or scan.num)
        if mapped then
            V.green(V.fit('Скан сохранён · лавка #'..tostring(mapped)
                ..' · ID: '..tostring((saved_row and saved_row.number_source) or scan.num_source or 'packet'),w))
        else
            V.green(V.fit('Скан сохранён · номер лавки пока не определён',w))
        end
    elseif scan_state=='pending' then
        V.muted(V.fit('Автоскан: получаю данные лавки...',w))
    elseif scan_state=='disabled' then
        V.muted(V.fit('Автоскан выключен',w))
    elseif scan_state=='empty' then
        V.muted(V.fit('В открытой лавке пока не распознаны товары',w))
    elseif scan_state=='server' then
        V.muted(V.fit('Скан не сохранён: сервер не определён',w))
    elseif scan_state=='error' then
        V.muted(V.fit('Ошибка сохранения скана · см. standalone.log',w))
    else
        V.muted(V.fit('Скан получен, сохранение ещё не подтверждено',w))
    end

    V.muted(V.fit('В базе: '..tostring(stats.shops or 0)..' лавок · '
        ..tostring(stats.offers or 0)..' предложений · с ID: '..tostring(stats.mapped or 0)
        ..' · без ID: '..tostring(stats.unmapped or 0),w))
    V.muted(V.fit('Текущая лавка: '..#(scan.sell or {})..' продажа · '..#(scan.buy or {})..' скупка',w))

    if not saved_state then
        if (observed or 0)>0 then V.muted(V.fit('Получено позиций: '..tostring(observed)..' · ожидаю запись в базу',w)) end
        return
    end
    local current_num=tonumber((saved_row and saved_row.num) or scan.num)
    if not current_num then
        V.muted(V.fit('Локальная база обновлена. Для GPS и маршрута нужен номер лавки; скрипт продолжит искать его по диалогу, TextDraw и 3D-надписи.',w))
        return
    end

    local cache_signature=table.concat({tostring(stats.server),tostring(arb and arb.revision or 0),
        tostring(math.floor(now/30)),tostring(DSP.market and DSP.market.missing_revision or 0),
        tostring(DSP.settings and DSP.settings.tax_bp or 200),tostring(current_num)},':')
    local best=V.memo('scan_best_routes',cache_signature,function()
        local found={buy=nil,sell=nil}
        for _,r in ipairs(arb and arb.routes and arb.routes(now) or {})do
            if tostring(r.seller_shop)==tostring(current_num) and
                (not found.buy or r.profit_unit>found.buy.profit_unit)then found.buy=r end
            if tostring(r.buyer_shop)==tostring(current_num) and
                (not found.sell or r.profit_unit>found.sell.profit_unit)then found.sell=r end
        end
        return found
    end)
    local function advice(kind,r)
        if not r then return (kind=='buy' and 'Лучше купить' or 'Лучше продать')..': пока нет пары' end
        local destination=kind=='buy' and r.buyer_shop or r.seller_shop
        local price=kind=='buy' and r.buy_price or r.sell_price
        return (kind=='buy' and 'Лучше купить' or 'Лучше продать')..': '..tostring(r.name or 'ID:'..r.id)
            ..' · '..DSP.money(price)..'/шт. · -> #'..tostring(destination)
            ..' · ~ +'..DSP.money(r.profit_unit)..'/шт.'
    end
    V.green(V.fit(advice('buy',best.buy),w))
    V.green(V.fit(advice('sell',best.sell),w))
    V.muted(V.fit('Подсказки рассчитаны по твоим локальным сканам; цены могли измениться после просмотра лавок.',w))
end
function V.shop_scan_view()
    local scan=snapshot();synchronize(scan)
    local title=(scan.num and('#'..tostring(scan.num)..' \xb7 ')or'')..tostring(scan.owner or '')
    if title==''then title='\xce\xf2\xea\xf0\xee\xe9\xf2\xe5 \xeb\xe0\xe2\xea\xf3 \xe2 \xe8\xe3\xf0\xe5' end
    local stamp=(tonumber(scan.updated)or 0)>0 and os.date('%H:%M:%S',scan.updated)or'\xed\xe5\xf2 \xf1\xed\xe8\xec\xea\xe0'
    V.muted(V.fit(title..' \xb7 '..stamp..(scan.closed and' \xb7 \xe7\xe0\xea\xf0\xfb\xf2\xe0, \xf1\xee\xf5\xf0\xe0\xed\xb8\xed \xf1\xed\xe8\xec\xee\xea'or''),imgui.GetContentRegionAvail().x))
    local tabs=V.actions({
        {label='\xcf\xf0\xee\xe4\xe0\xb8\xf2',id='scan_sell',width=124,active=S.side=='sell'},
        {label='\xd1\xea\xf3\xef\xe0\xe5\xf2',id='scan_buy',width=124,active=S.side=='buy'}
    })
    if tabs.scan_sell then S.side='sell';S.manager_side=nil end
    if tabs.scan_buy then S.side='buy';S.manager_side=nil end
    V.muted('\xcd\xe0\xe1\xeb\xfe\xe4\xe0\xeb\xee\xf1\xfc \xe2 \xe8\xe3\xf0\xe5')
    local source_rows=scan[S.side]or{}
    local query,changed='',false
    if V.search then query,changed=V.search('scan_current_'..S.side,'\xcf\xee\xe8\xf1\xea \xef\xee \xf2\xe5\xea\xf3\xf9\xe5\xe9 \xeb\xe0\xe2\xea\xe5',-1) end
    local lower=DSP.lower or string.lower
    local q=lower(DSP.clean_text and DSP.clean_text(query) or query)
    local rows={}
    for _,row in ipairs(source_rows)do
        local hay=lower(DSP.clean_text and DSP.clean_text(tostring(row.name or row.display or '')..' '..tostring(row.item_id or row.id or '')) or tostring(row.name or row.display or ''))
        if q=='' or hay:find(q,1,true) then rows[#rows+1]=row end
    end
    local key='scan_items_'..S.side
    if changed then V.reset_list(key) end
    V.muted('\xcd\xe0\xe9\xe4\xe5\xed\xee \xef\xee\xe7\xe8\xf6\xe8\xe9: '..tostring(#rows)..' / '..tostring(#source_rows))
    local w=imgui.GetContentRegionAvail().x
    local compact=V.compact(w)
    -- Leave space for scan result and tips below the scrollable list.
    local toolbar_h=compact and (S.tools_open and 206 or 108) or 110
    local summary_h=140
    V.list_rows(key,rows,compact and 86 or 60,item_row,
        {footer_height=toolbar_h+summary_h,toolbar=function()toolbar(scan,key)end})
    scan_summary(scan)
end
local function library_body(modal)
    if modal.action=='copy'then
        if b('В продажу','target_sell',132,modal.target_side=='sell')then
            modal.target_side='sell';modal.index=DSP.presets.selected('sell')
        end
        V.inline();if b('В скупку','target_buy',132,modal.target_side=='buy')then
            modal.target_side='buy';modal.index=DSP.presets.selected('buy')
        end
        if b('Существующий','existing',170,modal.mode=='existing')then modal.mode='existing'end
        V.inline();if b('Новый набор','new',148,modal.mode=='new')then modal.mode='new'end
    end
    if modal.mode=='new'then
        imgui.SetNextItemWidth(-1)
        imgui.InputTextWithHint('##v22_scan_preset_name',DSP.utf8('Название нового набора'),S.name,128)
    else
        local list=DSP.presets.list(modal.target_side)or{}
        V.list_rows('scan_preset_library_'..modal.target_side,list,46,function(p,i)
            if b(p.name or('Набор '..i),'preset_'..i,-1,modal.index==i)then modal.index=i end
        end,{height=96,footer=false})
    end
    if modal.action=='copy'then
        local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
        V.muted('Надбавка, $/шт.');V.at(x+164,y-3)
        imgui.SetNextItemWidth(112);imgui.InputText('##v22_scan_markup',S.markup,64)
        V.at(x,y+40)
        imgui.TextWrapped(DSP.utf8('Существующие цены сохраняются. Неизвестное количество: лимит 1. Продажа выключена до проверки инвентаря.'))
    else imgui.TextWrapped(DSP.utf8('Только цены совпавших выбранных предметов. Количество, себестоимость и остальные поля сохраняются.'))end
end
local function confirm(modal)
    local domain=DSP.shop_scan
    if not domain then S.error='Скан лавки пока недоступен';return end
    local current=snapshot()
    if identity(current)~=modal.identity or current.revision~=modal.revision then
        S.error='Снимок изменился. Закройте окно и выберите позиции снова.';return
    end
    local result
    local options={selected=modal.selected,expected_revision=modal.revision,
        expected_generation=modal.generation,expected_server=modal.server}
    if modal.action=='prices'then
        result=domain.apply_prices(modal.side,modal.index,options)
    else
        local raw=ffi.string(S.markup)
        local markup=tonumber(raw)
        if not raw:match('^[+-]?%d+$')or not markup or math.abs(markup)>9007199254740991 then
            S.error='Надбавка должна быть целым числом долларов';return
        end
        options.target_side=modal.target_side;options.markup=markup
        if modal.mode=='new'then options.name=DSP.trim(DSP.to_cp(ffi.string(S.name)))
        else options.index=modal.index end
        result=domain.copy_to_preset(modal.side,options)
    end
    if type(result)~='table'or not result.ok then
        S.error=type(result)=='table'and result.error or'Не удалось сохранить пресет';return
    end
    DSP.notify((modal.action=='prices'and'Обновлено цен: 'or'Добавлено позиций: ')..tostring(result.count or 0))
    S.manager_side=modal.target_side
    S.modal=nil;S.error=nil;imgui.CloseCurrentPopup()
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    local modal=S.modal
    if not modal then return end
    V.popup(modal.action=='prices'and'Обновить цены'or'Перенести в пресет','scan_preset',function()
        local height=math.max(36,imgui.GetContentRegionAvail().y-78)
        V.list('scan_preset_body',function()library_body(modal)end,{height=height,footer=false})
        if S.error then V.red(V.fit(S.error,imgui.GetContentRegionAvail().x))
        else V.muted('Только выбранные позиции текущего снимка')end
        V.cancel('scan_preset');V.inline()
        if b(modal.action=='prices'and'Обновить цены'or'Перенести','confirm',184)then confirm(modal)end
    end,{w=620,h=450})
end
