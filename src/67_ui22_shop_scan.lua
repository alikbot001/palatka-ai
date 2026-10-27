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
local function item_row(row,i)
    V.row('scan_'..tostring(row.key),58,function(w,x,y)
        local selected=S.selected[S.side][row.key]
        if b(selected and 'x'or' ','select_'..tostring(row.key),38,selected)then
            S.selected[S.side][row.key]=not selected or nil
        end
        V.at(x+44,y+4);DSP.mobile.thumbnail(row,30)
        V.at(x+82,y+1);V.text(V.fit(row.name or row.display or '?',w-240))
        V.at(x+82,y+25)
        V.muted(row.qty_known and(tostring(row.qty)..' шт.')or'Количество неизвестно')
        V.at(x+w-144,y+9)
        if tonumber(row.price)and row.price>0 then V.text(V.fit(DSP.money(row.price)..'/шт.',144))
        else V.muted('Цена неизвестна')end
    end)
end
local function toolbar(scan,key)
    local w=imgui.GetContentRegionAvail().x
    if b('Все','select_all',62)then
        for _,row in ipairs(scan[S.side]or{})do S.selected[S.side][row.key]=true end
    end
    V.inline();if b('Сброс','select_none',82)then S.selected[S.side]={};V.scan_selection=S.selected end
    V.inline();V.muted('Выбрано '..count(S.side))
    if w>530 then
        V.inline();if b('Мои пресеты','presets',142)then V.kind=S.manager_side or S.side;V.open_popup('Наборы','presets')end
    end
    V.scroll_buttons(key);V.inline()
    if b('В пресет','copy',134)then choose_operation('copy')end
    V.inline();if b('Обновить цены','prices',164)then choose_operation('prices')end
end
function V.shop_scan_view()
    local scan=snapshot();synchronize(scan)
    local title=(scan.num and('#'..tostring(scan.num)..' · ')or'')..tostring(scan.owner or '')
    if title==''then title='Откройте лавку в игре' end
    local stamp=(tonumber(scan.updated)or 0)>0 and os.date('%H:%M:%S',scan.updated)or'нет снимка'
    V.muted(V.fit(title..' · '..stamp..(scan.closed and' · закрыта, сохранён снимок'or''),imgui.GetContentRegionAvail().x))
    if b('Продаёт','sell',124,S.side=='sell')then S.side='sell';S.manager_side=nil end
    V.inline();if b('Скупает','buy',124,S.side=='buy')then S.side='buy';S.manager_side=nil end
    V.inline();V.muted('Наблюдалось в игре')
    local rows=scan[S.side]or{};local key='scan_items_'..S.side
    V.list_rows(key,rows,58,item_row,{footer_height=96,toolbar=function()toolbar(scan,key)end})
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
