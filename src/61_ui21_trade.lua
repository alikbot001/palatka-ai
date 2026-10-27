-- Trade view: two tabs, inline editing, fixed actions; execution stays in auto.
local ffi=require('ffi')
local V,M,T=DSP.ui21,DSP.mobile,DSP.trade_v16
local function busy()return DSP.auto.buy_running or DSP.auto.sell_running end
local function preset()return V.kind=='sell'and DSP.settings.sell_preset or DSP.settings.buy_preset end
local function b(s,id,w,on)return V.button(s,'trade_'..id,w,on)end
local function money(n)
    local text=string.format('%.0f',math.abs(n)):reverse():gsub('(%d%d%d)','%1.'):reverse():gsub('^%.','')
    return (n<0 and '-$'or'$')..text
end
local function report(ok,msg)DSP.notify(ok and tostring(msg or 'Готово')or('Не удалось: '..tostring(msg or '?')))end
function V.trade_add(source,it)
    if source=='inventory'then return T.add_from_inventory(V.kind,it)end
    return T.add_from_catalog(V.kind,it)
end
local function launch()
    local ok,issues=T.validate(V.kind)
    if not ok then V.tab='preset';report(false,table.concat(issues,'; '));return end
    if V.kind=='sell'then DSP.auto.start_sell()else DSP.auto.start_buy()end
end
local function footer_height()return math.ceil((imgui.GetFontSize and imgui.GetFontSize()or 16)*2+62)end
local function footer(key)
    local r=T.totals(V.kind)
    local w=imgui.GetContentRegionAvail().x
    local first,second
    if not r.complete then
        first=(V.kind=='buy'and'Бюджет'or'Выручка')..' — итог не рассчитан'
        second=r.overflow and 'Сумма вне точного диапазона' or r.invalid_tax and 'Проверьте комиссию' or ('Проверьте цену / количество: '..r.invalid..' поз.')
    elseif V.kind=='buy'then
        first='Бюджет скупки '..money(r.required_funds)
        second=r.positions..' поз. · '..r.qty..' шт. · Без комиссии продажи'
    else
        first='Выручка '..money(r.gross)..' · Комиссия ~ '..money(r.commission)
        second='Чистыми ~ '..money(r.net)..' · Прибыль '..(r.profit and '~ '..money(r.profit)or'— нет себестоимости')
    end
    V.text(V.fit(first,w));V.muted(V.fit(second,w))
    local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
    local info=(DSP.settings.dry_run and 'ТЕСТ'or'РЕАЛЬНО')
    if V.kind=='sell'and r.complete then info=r.positions..' поз. · '..r.qty..' шт. · '..info end
    V.muted(V.fit(info,math.max(1,w-406)))
    V.at(x+math.max(0,w-398),y);V.scroll_buttons(key);V.inline()
    if V.tab=='items'then
        if b(V.source=='inventory'and'Инвентарь'or'Каталог','source_menu',112)then V.open_popup('Предметы','source_menu')end
    else
        if b('Наборы','manage',112)then V.open_popup('Наборы','presets')end
    end
    V.inline()
    if busy()then
        if b('Остановить','stop',146,true)then
            if DSP.auto.sell_running then DSP.auto.stop_sell()else DSP.auto.stop_buy()end
        end
    elseif V.button('Выставить >','trade_launch',146,false,true)then V.open_popup('Выставление','launch')end
end

local function item_row(it,i,w)
    local _,found=DSP.presets.find(V.kind,DSP.item_key(it.name or it.display or '',it.ench or 0))
    V.row('inventory_'..i,58,function(rw,x,y)
        M.thumbnail(it,32)
        V.at(x+42,y-3)
        if V.text_button(V.fit(it.display or it.name or '?',rw-190),'trade_name_add_'..i,rw-180,false,28)then report(V.trade_add(V.source,it))end
        V.at(x+42,y+26);V.muted(V.source=='inventory'and('В инвентаре · '..tostring(it.count or it.qty or 0)..' шт.')or('ID '..tostring(it.id or '?')))
        V.at(x+rw-134,y+2)
        if b(found and 'Добавлен' or '+ Добавить','add_'..i,134,found~=nil)then
            report(V.trade_add(V.source,it))
        end
    end)
end
local function item_rows(query)
    local q=DSP.lower(query)
    local source=V.source=='inventory'and DSP.auto.inv or DSP.items.by_id
    local sig=table.concat({V.source,tostring(source),tostring(#(DSP.auto.inv or {})),q,tostring(DSP.market.state.version)},'|')
    return V.memo('items_rows',sig,function()
        local out={}
        if V.source=='inventory'then
            -- Inventory tables are replaced by the scanner, not edited by rendering.
            for _,it in ipairs(DSP.auto.inv or {})do
                if q==''or DSP.lower(it.name or ''):find(q,1,true)then out[#out+1]=it end
            end
        else
            for id,name in pairs(DSP.items.by_id or {})do
                if name~='-'and DSP.trim(name)~=''and not name:find('DELETED',1,true)and(q==''or DSP.lower(name):find(q,1,true)or tostring(id)==q)then out[#out+1]={id=id,name=name}end
            end
            if #out==0 and q~=''then out=DSP.market.find_item(query)or {}end
            table.sort(out,function(a,b)return tostring(a.name or a.display)<tostring(b.name or b.display)end)
        end
        return out
    end)
end
local function items(query,edited)
    local listkey='items_'..V.kind..'_'..V.source
    if edited then V.reset_list(listkey)end
    V.list_rows(listkey,item_rows(query),58,item_row,{toolbar=footer,footer_height=footer_height()})
end

local function preset_row(it,i)
    V.row('preset_'..V.kind..i,56,function(w,x,y)
        local namew=math.max(80,w-318)
        V.at(x,y)
        if busy()then V.muted(it.enabled~=false and '[x]'or'[ ]')
        elseif b(it.enabled~=false and 'x'or' ','enabled_'..i,42,it.enabled~=false)then
            it.enabled=it.enabled==false and(tonumber(it.price)or 0)>0 or false;M.defer_save()
        end
        V.at(x+48,y+2);M.thumbnail(it,30)
        V.at(x+86,y+8)
        if V.text_button(V.fit(it.name or '?',namew-92),'trade_name_'..i,namew-86,false,36)then V.item_info=it;V.open_popup('Предмет','item_info')end
        local px=x+namew+6
        V.at(px,y)
        if busy()then V.text(DSP.money(it.price))else
            if M.compact_number(it,'price','v22_price_'..V.kind..i,122,0)then
                it.needs_price=(tonumber(it.price)or 0)<=0 or nil;it.enabled=(tonumber(it.price)or 0)>0
            end
        end
        V.at(px+128,y)
        if busy()then V.text(tostring(it.qty))else M.compact_number(it,'qty','v22_qty_'..V.kind..i,76,1)end
        V.at(px+210,y)
        if V.kind=='buy'then
            if b('...','quantity_'..i,44)and not busy()then V.qty_item=it;V.open_popup('Количество','quantity')end
            V.at(px+260,y)
        end
        if b('x','remove_'..i,42)and not busy()then V.remove_pending={kind=V.kind,item=it};V.open_popup('Удалить позицию','remove')end
    end)
end
local function my_preset()
    local p=preset()
    local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
    local w=imgui.GetContentRegionAvail().x
    local px=x+8+math.max(80,w-16-318)+6
    V.at(px,y);V.muted('Цена');V.at(px+128,y);V.muted('Шт.')
    V.at(x,y+24)
    V.list_rows('preset_'..V.kind..'_'..tostring(p),p.items or{},56,preset_row,{toolbar=footer,footer_height=footer_height()})
end
function V.trade()
    V.heading('Торговля',function()
        if b('Продажа','sell',112,V.kind=='sell')then V.kind='sell'end
        V.inline();if b('Скупка','buy',112,V.kind=='buy')then V.kind='buy'end
    end,230)
    local w=imgui.GetContentRegionAvail().x
    local tabs=w*.56;local each=(tabs-6)/2
    if b('Предметы','items_tab',each,V.tab=='items')then V.tab='items'end
    V.inline();if b('Мой пресет · '..#(preset().items or{}),'preset_tab',each,V.tab=='preset')then V.tab='preset'end
    V.inline()
    if V.tab=='items'then
        local query,edited=V.search('items','Поиск предмета или ID',-1)
        items(query,edited)
    else
        if b(V.fit(preset().name or'Основной',w-tabs-28)..' >','manage',-1)then V.open_popup('Наборы','presets')end
        my_preset()
    end
end

local function remove_position()
    local p=V.remove_pending;if not p then return end
    V.text('Удалить '..tostring(p.item.name)..'?')
    V.cancel('remove');V.inline()
    if b('Удалить','confirm_remove',132)then
        for i,it in ipairs(DSP.presets.items(p.kind))do if it==p.item then DSP.presets.remove(p.kind,i);break end end
        V.remove_pending=nil;imgui.CloseCurrentPopup()
    end
end
local function presets_popup()
    local kind=V.kind
    local list=DSP.presets.list(kind)or{}
    V.list_rows('preset_library_'..kind,list,46,function(p,i)
        if b(p.name,'select_'..i,-1,DSP.presets.selected(kind)==i)then report(DSP.presets.select(kind,i))end
    end,{height=math.max(48,math.min(110,imgui.GetContentRegionAvail().y-240))})
    V.preset_name=V.preset_name or imgui.new.char[128]()
    imgui.SetNextItemWidth(-1);imgui.InputTextWithHint('##v22_preset_name',DSP.utf8('Название набора'),V.preset_name,128)
    local name=DSP.to_cp(ffi.string(V.preset_name))
    if b('+ Создать','preset_create',130)then report(DSP.presets.create(kind,name))end
    V.inline();if b('Переименовать','preset_rename',166)then report(DSP.presets.rename(kind,DSP.presets.selected(kind),name))end
    if b('Экспорт','preset_export',110)then report(DSP.presets.export_file(kind))end
    V.inline();if b('Market Helper','preset_mh',151)then report(DSP.presets.import_mh())end
    V.inline();if b('Удалить','preset_delete',116)then
        V.delete_preset={kind=kind,index=DSP.presets.selected(kind)};imgui.OpenPopup(DSP.utf8('Удалить набор')..'##v22_del_preset')
    end
    V.popup('Удалить набор','del_preset',function()
        V.text('Безвозвратно удалить выбранный набор?');V.cancel('del_preset');V.inline()
        if b('Удалить','del_preset_yes',142)then local p=V.delete_preset;report(DSP.presets.delete(p.kind,p.index));imgui.CloseCurrentPopup()end
    end,{w=560,h=170})
    if b('Импорт JSON...','json_popup',160)then imgui.OpenPopup(DSP.utf8('Импорт JSON')..'##v22_import')end
    V.inline();if b('Закрыть','presets_close',116)then imgui.CloseCurrentPopup()end
    V.popup('Импорт JSON','import',function()
        V.import_path=V.import_path or imgui.new.char[384]()
        imgui.SetNextItemWidth(-1);imgui.InputTextWithHint('##v22_import_path',DSP.utf8('Путь к файлу JSON'),V.import_path,384)
        V.cancel('import');V.inline()
        if b('Импортировать','import_file',180)then report(DSP.presets.import_file(DSP.to_cp(ffi.string(V.import_path)),kind))end
    end,{w=620,h=180})
end
local old=V.popups
function V.popups()
    if old then old()end
    V.popup('Предметы','source_menu',function()
        if b('Инвентарь','inventory',-1,V.source=='inventory')then V.source='inventory';imgui.CloseCurrentPopup()end
        if b('Каталог','catalog',-1,V.source=='catalog')then V.source='catalog';imgui.CloseCurrentPopup()end
        if b('Просканировать инвентарь','scan',-1)then DSP.auto.scan_inventory();imgui.CloseCurrentPopup()end
        if b('+ Ввести название вручную','manual',-1)then imgui.CloseCurrentPopup();V.open_popup('Новый предмет','manual')end
        if b('Закрыть','source_close',140)then imgui.CloseCurrentPopup()end
    end,{w=620,h=300})
    V.popup('Выставление','launch',function()
        local ok,issues,total=T.validate(V.kind)
        V.text((V.kind=='sell'and'Продажа' or'Скупка')..' · '..(DSP.settings.dry_run and 'ТЕСТ' or 'РЕАЛЬНО'))
        V.text('Позиций: '..DSP.presets.active_count(V.kind)..' · '..DSP.money(total))
        V.list('launch_issues',function()for _,s in ipairs(issues)do V.red(s)end end,{height=100})
        V.cancel('launch');V.inline()
        if b('Проверить','review',128)then imgui.CloseCurrentPopup();V.open_popup('Проверка списка','review')end
        V.inline();if b('Выставить','fast',142,ok)and ok then launch();imgui.CloseCurrentPopup()end
    end)
    V.popup('Проверка списка','review',function()
        local ok,issues,total=T.validate(V.kind)
        V.list_rows('review_items',preset().items or{},48,function(it)
            V.text(V.fit(it.name,300));V.muted(tostring(it.qty)..' шт. · '..DSP.money(it.price)..(it.enabled==false and ' · выключен'or''))
        end,{height=185})
        V.text('Всего: '..DSP.money(total));if not ok then V.red(V.fit(table.concat(issues,'; '),550))end
        V.cancel('review');V.inline();if b('Подтвердить','review_start',176,ok)and ok then launch();imgui.CloseCurrentPopup()end
    end)
    V.popup('Удалить позицию','remove',remove_position,{w=620,h=200})
    V.popup('Наборы','presets',presets_popup)
    V.popup('Новый предмет','manual',function()
        V.manual_name=V.manual_name or imgui.new.char[192]()
        imgui.SetNextItemWidth(-1);imgui.InputTextWithHint('##v22_manual',DSP.utf8('Название как в игре'),V.manual_name,192)
        V.cancel('manual');V.inline()
        if b('+ Добавить','manual_add',150)then
            local ok,msg=T.add_from_catalog(V.kind,{name=DSP.trim(DSP.to_cp(ffi.string(V.manual_name)))})
            report(ok,msg);if ok then imgui.CloseCurrentPopup()end
        end
    end,{w=620,h=180})
    V.popup('Предмет','item_info',function()
        local it=V.item_info
        if it then
            imgui.TextWrapped(DSP.utf8(it.name or '?'))
            if V.kind=='sell'then
                V.muted('Себестоимость за шт. · 0 = бесплатно')
                if busy()then V.text(it.cost_price~=nil and DSP.money(it.cost_price)or'Не задана')
                else M.compact_number(it,'cost_price','v22_cost',190,0)end
                V.muted(it.cost_price==nil and 'Не задана: прибыль неизвестна' or 'Прибыль учитывает комиссию продажи')
                if b('Неизвестна','cost_unknown',146)and not busy()then
                    it.cost_price=nil;M.refresh_buffer(it,'cost_price');M.defer_save()
                end
                V.inline()
            end
        end
        if b('Закрыть','info_close',140)then imgui.CloseCurrentPopup()end
    end,{w=620,h=280})
    V.popup('Количество','quantity',function()
        local it=V.qty_item;if not it then return end
        V.text(V.fit(it.name,530));M.compact_number(it,'qty','popup_qty',180,1)
        for _,n in ipairs({1,10,100})do
            if b(tostring(n),'quick_qty_'..n,72)and not busy()then it.qty=n;M.refresh_buffer(it,'qty');M.defer_save()end
            V.inline()
        end
        if b('Макс','max_qty',100)then
            it._v22_limit=it._v22_limit or{qty=it.max_qty or it.qty};V.limit_open=true
        end
        if V.limit_open then
            V.muted('Укажите лимит скупки');local lim=it._v22_limit
            M.compact_number(lim,'qty','limit_qty',180,1)
            if b('Применить лимит','apply_limit',220)and not busy()then it.max_qty=lim.qty;it.qty=lim.qty;M.refresh_buffer(it,'qty');M.defer_save()end
        end
        if b('Готово','qty_done',140)then V.limit_open=false;imgui.CloseCurrentPopup()end
    end)
end
