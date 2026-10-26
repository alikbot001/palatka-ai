-- 2.1 trading: compact item rows, no multi-screen form maze.
local ffi=require('ffi')
local V,M=DSP.ui21,DSP.mobile
local T=DSP.trade_v16
local function active() return DSP.auto.buy_running or DSP.auto.sell_running end
local function preset() return V.kind=='sell' and DSP.settings.sell_preset or DSP.settings.buy_preset end
local function report(ok,msg)
    DSP.notify(ok and tostring(msg or 'Готово') or ('Не удалось: '..tostring(msg or '?')))
end
local function click(label,id,w,on) return V.button(label,'trade_'..id,w,on) end
function V.trade_add(source,it)
    if source=='inventory' then return T.add_from_inventory(V.kind,it) end
    return T.add_from_catalog(V.kind,it)
end
local function add_entry(it,i)
    local found=DSP.presets.find(V.kind,DSP.item_key(it.name or it.display or '',it.ench or 0))
    local w=imgui.GetContentRegionAvail().x
    -- Use a line, not a card; image slot is optional and does not hold up scrolling.
    if imgui.Columns and w>480 then
        imgui.Columns(2,'##v21_inv_cols_'..i,false)
        imgui.SetColumnWidth(0,math.max(180,w-160))
        M.thumbnail(it,24);V.inline(6)
        V.text(tostring(it.display or it.name or '?'))
        if it.count or it.qty then V.inline();V.muted('x'..tostring(it.count or it.qty)) end
        imgui.NextColumn()
        if click(found and '[x] Добавлен' or '+ Добавить','add_'..i,-1,found~=nil) then
            local ok,err=V.trade_add(V.source,it)
            report(ok,ok and 'Предмет в пресете' or err)
        end
        imgui.Columns(1)
    else
        M.thumbnail(it,23);V.inline();V.text(tostring(it.display or it.name or '?')..'  x'..tostring(it.count or it.qty or 1))
        V.inline();if click(found and '[x]' or '+','add_'..i,75,found~=nil) then
            local ok,err=V.trade_add(V.source,it);report(ok,ok and 'Добавлено' or err)
        end
    end
    imgui.Separator()
end
local function items_tab()
    if click('Инвентарь','inventory',133,V.source=='inventory') then V.source='inventory';V.pages.items=1 end
    V.inline()
    if click('Каталог','catalog',115,V.source=='catalog') then V.source='catalog';V.pages.items=1 end
    V.inline()
    if click('Скан','scan',85) then DSP.auto.scan_inventory() end
    local query=V.search('items',V.source=='inventory' and 'Поиск в инвентаре...' or 'Поиск предмета...',-1)
    local entries={}
    if V.source=='inventory' then
        for _,it in ipairs(DSP.auto.inv or {}) do
            if query=='' or DSP.lower(tostring(it.name or '')):find(DSP.lower(query),1,true) then
                entries[#entries+1]=it
            end
        end
    elseif query~='' then
        local signature=(DSP.market.state.version or 0)..'/'..DSP.lower(query)
        if signature~=V.catalog_signature then
            V.catalog_signature=signature
            V.catalog_rows=DSP.market.find_item(query)
        end
        entries=V.catalog_rows or {}
    end
    local from,to=V.selected_page('items',#entries,16)
    for i=from,to do add_entry(entries[i],i) end
    if #entries==0 then V.muted(V.source=='inventory' and 'Нет предметов. Откройте инвентарь и нажмите «Скан».' or 'Введите название предмета для поиска.') end
    V.pager('items',#entries,16)
    if click('+ Вручную','manual_open',140) then
        if imgui.OpenPopup then imgui.OpenPopup(DSP.utf8('Новый предмет')..'##v21_manual') end
    end
end
local function preset_entry(it,i)
    local width=imgui.GetContentRegionAvail().x
    local id=V.kind..i
    if width>500 and imgui.Columns then
        imgui.Columns(4,'##v21_preset_columns_'..id,false)
        imgui.SetColumnWidth(0,width*.45)
        imgui.SetColumnWidth(1,width*.21)
        imgui.SetColumnWidth(2,width*.21)
    end
    local enabled=imgui.new.bool(it.enabled~=false)
    if imgui.Checkbox('##v21_en_'..id,enabled) then
        it.enabled=enabled[0] and (tonumber(it.price) or 0)>0 or false
        M.defer_save()
    end
    V.inline(4);M.thumbnail(it,23);V.inline(5)
    V.text(tostring(it.name or '?'))
    if width>500 then imgui.NextColumn() else V.inline() end
    local pw=width>500 and math.max(73,width*.17) or math.max(65,width*.19)
    if M.compact_number(it,'price','v21_price_'..id,pw,0) then
        it.needs_price=(tonumber(it.price) or 0)<=0 or nil
        it.enabled=(tonumber(it.price) or 0)>0
        M.defer_save()
    end
    if width>500 then imgui.NextColumn() else V.inline() end
    M.compact_number(it,'qty','v21_qty_'..id,pw,1)
    if width>500 then imgui.NextColumn() else V.inline() end
    if click('x','delete_'..id,width>500 and 48 or 42) then
        V.remove_pending={kind=V.kind,index=i,name=it.name}
        imgui.OpenPopup(DSP.utf8('Удалить позицию')..'##v21_remove')
    end
    if width>500 then imgui.Columns(1) end
    if V.kind=='buy' and V.buy_expanded==i then
        for _,n in ipairs({1,10,100}) do
            if click(tostring(n),'qty_choice_'..id..'_'..n,58) then
                it.qty=n;M.refresh_buffer(it,'qty');M.defer_save()
            end
            V.inline()
        end
        if click('Макс','max_choice_'..id,82) then
            V.max_pending=it
            imgui.OpenPopup(DSP.utf8('Лимит скупки')..'##v21_max')
        end
    end
    if V.kind=='buy' then
        if click(V.buy_expanded==i and 'Скрыть быстрый ввод' or '1 / 10 / 100 / Макс','qty_toggle_'..id,210) then
            V.buy_expanded=V.buy_expanded==i and nil or i
        end
    end
    imgui.Separator()
end
local function preset_tab()
    local p=preset()
    V.text('Набор: '..tostring(p.name or 'Основной'))
    V.inline()
    if click('Сменить','manage',120) then
        imgui.OpenPopup(DSP.utf8('Наборы')..'##v21_presets')
    end
    V.muted('Предмет                                Цена / шт.        Штук')
    local items=p.items or {}
    local from,to=V.selected_page('preset',#items,15)
    for i=from,to do preset_entry(items[i],i) end
    if #items==0 then V.muted('Пусто. Нажмите «Предметы» и добавьте товары.') end
    V.pager('preset',#items,15)
end
local function begin_listing()
    local ok,issues=T.validate(V.kind)
    if not ok then
        report(false,table.concat(issues,'; '))
        V.tab='preset'
        return
    end
    if V.kind=='sell' then DSP.auto.start_sell() else DSP.auto.start_buy() end
end
function V.trade()
    V.text('Торговля')
    V.inline()
    if click('Продажа','mode_sell',120,V.kind=='sell') then V.kind='sell';V.pages.items=1 end
    V.inline()
    if click('Скупка','mode_buy',120,V.kind=='buy') then V.kind='buy';V.pages.items=1 end
    if click('Предметы','tab_items',math.max(140,imgui.GetContentRegionAvail().x*.28),V.tab=='items') then V.tab='items' end
    V.inline()
    if click('Мой пресет ('..#(preset().items or {})..')','tab_preset',math.max(155,imgui.GetContentRegionAvail().x*.28),V.tab=='preset') then V.tab='preset' end
    imgui.Separator()
    if V.tab=='items' then items_tab() else preset_tab() end
end
function V.trade_footer(w)
    local p=preset()
    local count,without=0,0
    for _,it in ipairs(p.items or {}) do
        count=count+1
        if (tonumber(it.price) or 0)<=0 then without=without+1 end
    end
    if w>640 then
        V.muted(count..' поз. · '..without..' без цены')
        V.inline()
    end
    if click('^','foot_up',47) then M.queue_scroll(-1) end
    V.inline()
    if click('v','foot_down',47) then M.queue_scroll(1) end
    V.inline()
    if active() then
        if click('ОСТАНОВИТЬ','stop',210,true) then
            if DSP.auto.sell_running then DSP.auto.stop_sell() else DSP.auto.stop_buy() end
        end
    else
        if click('Выставить  ›','launch',math.max(140,math.min(245,w*.29)),true) then
            imgui.OpenPopup(DSP.utf8('Выставление')..'##v21_launch')
        end
    end
end
local function popup(title,id,fn)
    local key=DSP.utf8(title)..'##v21_'..id
    if imgui.BeginPopupModal and imgui.BeginPopupModal(key,nil,imgui.WindowFlags.AlwaysAutoResize) then
        fn();imgui.EndPopup()
    end
end
local function cancel() if click('Отмена','cancel',132) then imgui.CloseCurrentPopup() end end
function V.trade_popups()
    popup('Выставление','launch',function()
        local ok,issues,total=T.validate(V.kind)
        V.text('Выставление: '..(V.kind=='sell' and 'Продажа' or 'Скупка'))
        V.muted('Выбрано позиций: '..DSP.presets.active_count(V.kind)..' · сумма '..DSP.money(total))
        if not ok then for i=1,math.min(3,#issues) do V.red(issues[i]) end end
        cancel();V.inline()
        if click('Проверить','show_review',160) then
            imgui.CloseCurrentPopup();V.review_pending=true
        end
        V.inline()
        if click('Быстро выставить','fast',191,ok) then
            if ok then begin_listing();imgui.CloseCurrentPopup() else report(false,table.concat(issues,'; ')) end
        end
    end)
    popup('Проверка списка','review',function()
        local ok,issues,total=T.validate(V.kind)
        for _,it in ipairs(preset().items or {}) do
            if it.enabled~=false then V.text(it.name..'  x'..it.qty..'  · '..DSP.money(it.price)) end
        end
        V.text('Всего: '..DSP.money(total))
        for _,e in ipairs(issues) do V.red(e) end
        cancel();V.inline()
        if click('Подтвердить','review_start',170,ok) then
            if ok then begin_listing();imgui.CloseCurrentPopup() else report(false,table.concat(issues,'; ')) end
        end
    end)
    popup('Удалить позицию','remove',function()
        V.text('Удалить '..tostring(V.remove_pending and V.remove_pending.name or '?')..'?')
        cancel();V.inline()
        if click('Удалить','remove_yes',145) then
            local p=V.remove_pending
            if p then DSP.presets.remove(p.kind,p.index) end
            V.remove_pending=nil;imgui.CloseCurrentPopup()
        end
    end)
    popup('Лимит скупки','max',function()
        local it=V.max_pending
        if it then
            it._v21_max=it._v21_max or {value=it.qty or 1}
            M.number('Лимит, шт.','max_trade',it._v21_max,'value',1,180)
        end
        cancel();V.inline()
        if click('Сохранить','max_save',155) and it then
            it.qty=math.floor(tonumber(it._v21_max.value) or 1)
            M.refresh_buffer(it,'qty');M.defer_save();imgui.CloseCurrentPopup()
        end
    end)
    popup('Наборы','presets',function()
        local kind=V.kind
        for i,p in ipairs(DSP.presets.list(kind) or {}) do
            if click(p.name or ('Набор '..i),'select_preset_'..i,260,DSP.presets.selected(kind)==i) then
                DSP.presets.select(kind,i);V.pages.preset=1
            end
        end
        V.preset_name=V.preset_name or imgui.new.char[128]()
        imgui.SetNextItemWidth(250)
        imgui.InputTextWithHint('##v21_preset_name',DSP.utf8('Название набора'),V.preset_name,128)
        local name=DSP.to_cp(ffi.string(V.preset_name))
        if click('+ Создать','preset_new',120) then report(DSP.presets.create(kind,name)) end
        V.inline();if click('Переименовать','preset_rename',154) then
            report(DSP.presets.rename(kind,DSP.presets.selected(kind),name))
        end
        if click('Экспорт','preset_export',120) then report(DSP.presets.export_file(kind)) end
        V.inline();if click('Импорт Market Helper','preset_import',198) then report(DSP.presets.import_mh()) end
        if click('Удалить набор','preset_delete',190) then
            imgui.OpenPopup(DSP.utf8('Подтвердить удаление')..'##v21_del_preset')
        end
        popup('Подтвердить удаление','del_preset',function()
            V.text('Безвозвратно удалить выбранный набор?')
            cancel();V.inline()
            if click('Удалить','del_yes',130) then
                report(DSP.presets.delete(kind,DSP.presets.selected(kind)))
                imgui.CloseCurrentPopup()
            end
        end)
        if click('Закрыть','preset_close',160) then imgui.CloseCurrentPopup() end
    end)
    popup('Новый предмет','manual',function()
        V.manual_name=V.manual_name or imgui.new.char[192]()
        imgui.SetNextItemWidth(270)
        imgui.InputTextWithHint('##v21_manual_name',DSP.utf8('Название предмета'),V.manual_name,192)
        cancel();V.inline()
        if click('+ Добавить','manual_save',160) then
            local ok,msg=T.add_from_catalog(V.kind,{name=DSP.trim(DSP.to_cp(ffi.string(V.manual_name)))})
            report(ok,ok and 'Добавлен без цены' or msg)
            if ok then imgui.CloseCurrentPopup() end
        end
    end)
end
local previous_popups=V.popups
V.popups=function()
    if V.review_pending then
        V.review_pending=false
        imgui.OpenPopup(DSP.utf8('Проверка списка')..'##v21_review')
    end
    V.trade_popups()
    if previous_popups then previous_popups() end
end
