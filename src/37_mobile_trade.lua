-- Active preset editor: never recreate a keyboard input on every frame.
local ffi=require('ffi')
local M=DSP.mobile
local U=DSP.ui
local function report(ok,detail)
    DSP.notify(ok and ('Готово: '..tostring(detail or '')) or ('Ошибка: '..tostring(detail or '')))
end
local function set_price(kind,it,value)
    it.price=math.max(1,math.floor(value))
    it.needs_price=nil
    M.refresh_buffer(it,'price')
    DSP.save_settings()
end
-- Market Helper-style row: toggle, name, market guidance, price, quantity, delete.
-- The editor lives in a fixed-height preset panel, not in the global scroll body.
local function item_card(kind,it,index)
    local id=kind..'_'..index
    local valid=(tonumber(it.price) or 0)>0 and (tonumber(it.qty) or 0)>0
    if not valid and it.enabled then it.enabled=false end
    imgui.Separator()
    local enabled=it.enabled~=false
    if imgui.Checkbox and imgui.new and imgui.new.bool then
        local tick=imgui.new.bool(enabled)
        if imgui.Checkbox('##trade_enabled_'..id,tick) then
            it.enabled=tick[0]; if M.defer_save then M.defer_save() else DSP.save_settings() end
        end
    else
        M.toggle('Выставлять##'..id,it,'enabled',valid)
    end
    M.inline()
    if imgui.SameLine then
        -- Thumbnail is optional; it never blocks the row or breaks missing images.
        M.thumbnail(it,34)
        M.inline()
    end
    M.text(tostring(it.name or '?'))
    local row=DSP.presets.find_row and DSP.presets.find_row(it)
    if row then
        local buy=row.buy and row.buy.max or 0
        local sell=row.sell and row.sell.min or 0
        M.text('Рынок: продают '..DSP.money(sell)..' / скупают '..DSP.money(buy))
    end
    local available=imgui.GetContentRegionAvail and imgui.GetContentRegionAvail().x or 700
    local price_w=math.max(110,math.floor(available*.42))
    local qty_w=math.max(80,math.floor(available*.28))
    imgui.TextDisabled(DSP.utf8('Цена ($/шт.)'))
    M.inline()
    imgui.TextDisabled(DSP.utf8('Количество'))
    imgui.SetNextItemWidth(price_w)
    if M.compact_number(it,'price','p_'..id,price_w,1) then it.needs_price=nil end
    M.inline()
    M.compact_number(it,'qty','q_'..id,qty_w,1)
    M.inline()
    if M.button('X','delete_'..id,62) then
        DSP.presets.remove(kind,index)
        return true
    end
    if not valid then M.text('Не выставляется: укажите цену и количество.') end
    return false
end
local function preset_library(kind,p)
    if not DSP.presets.list then return end
    U.preset_name_buf=U.preset_name_buf or imgui.new.char[128]()
    M.title('Наборы товаров')
    local list=DSP.presets.list(kind)
    for i,entry in ipairs(list) do
        if M.button(entry.name or ('Набор '..i),'preset'..kind..i,300,DSP.presets.selected(kind)==i) then
            report(DSP.presets.select(kind,i))
        end
    end
    imgui.SetNextItemWidth(360)
    imgui.InputTextWithHint('##preset_name',DSP.utf8('Название набора'),U.preset_name_buf,128)
    if M.button('Создать набор','create_preset',250) then report(DSP.presets.create(kind,DSP.to_cp(ffi.string(U.preset_name_buf)))) end
    M.inline()
    if M.button('Переименовать','rename_preset',280) then report(DSP.presets.rename(kind,DSP.presets.selected(kind),DSP.to_cp(ffi.string(U.preset_name_buf)))) end
    if M.button('Удалить этот набор','delete_preset',350) then
        U.confirm_delete=not U.confirm_delete
    end
    if U.confirm_delete then
        M.text('Удалить выбранный набор товаров?')
        if M.button('Да, удалить набор','confirm_delete',350) then
            report(DSP.presets.delete(kind,DSP.presets.selected(kind))); U.confirm_delete=false
        end
    end
    imgui.Separator()
    if M.button('Импорт Market Helper','import_mh',350) then report(DSP.presets.import_mh()) end
    M.inline()
    if DSP.presets.export_file and M.button('Экспорт набора','export_preset',300) then report(DSP.presets.export_file(kind)) end
    if DSP.presets.import_file then
        U.import_path_buf=U.import_path_buf or imgui.new.char[512]()
        imgui.SetNextItemWidth(math.min(800,imgui.GetContentRegionAvail().x))
        imgui.InputTextWithHint('##import_path',DSP.utf8('Полный путь к JSON файлу набора'),U.import_path_buf,512)
        if M.button('Импорт файла','import_file',300) then report(DSP.presets.import_file(DSP.to_cp(ffi.string(U.import_path_buf)),kind)) end
    end
end
local function inventory(kind)
    M.text('Инвентарь: '..tostring(DSP.auto.inv_status or 'не сканирован'))
    if M.button('Сканировать инвентарь','scan_inventory',400) then DSP.auto.scan_inventory() end
    M.text('Откройте инвентарь в игре; добавляйте товары в нужную сторону торговли.')
    for i,it in ipairs(DSP.auto.inv or {}) do
        M.text(tostring(it.name or '?')..' x'..tostring(it.count or 0))
        local name=tostring(it.name or '')
        local ench=tonumber(it.ench) or tonumber(name:match('%(%+(%d+)%)%s*$')) or 0
        local base=name:gsub('%s+%(%+%d+%)%s*$','')
        local row=DSP.market.row_for(base,ench)
        if row then
            if M.button('В скупку','inv_buy'..i,240) then report(DSP.presets.add(row,'buy')) end
            M.inline()
            if M.button('В продажу','inv_sell'..i,240) then report(DSP.presets.add(row,'sell')) end
        else
            M.text('Рыночной цены нет. Добавьте товар и задайте свою цену в наборе.')
            for _,side in ipairs({'buy','sell'}) do
                local label=side=='buy' and 'В скупку / задать цену' or 'В продажу / задать цену'
                if M.button(label,'inv_unknown_'..side..i,430) then
                    local ok,err=DSP.presets.add_manual(side,{name=base,ench=ench,price=0,
                        qty=math.max(1,tonumber(it.count or it.qty) or 1),enabled=false,needs_price=true})
                    report(ok,err)
                    if ok then U.preset_kind=side; U.trade_section='items' end
                end
                if side=='buy' then M.inline() end
            end
        end
        imgui.Separator()
    end
end
local function manual_entry(kind)
    U.manual_item=U.manual_item or {ench=0,price=1,qty=1}
    U.manual_name=U.manual_name or imgui.new.char[256]()
    local item=U.manual_item
    M.title('ДОБАВИТЬ ТОВАР ВРУЧНУЮ')
    M.text('Точное название как в игре. Рыночная база не требуется.')
    imgui.SetNextItemWidth(math.min(850,imgui.GetContentRegionAvail().x))
    imgui.InputTextWithHint('##manual_name',DSP.utf8('Название товара'),U.manual_name,256)
    M.number('Заточка, 0 = без заточки','manual_ench',item,'ench',0,300)
    M.number('Ваша цена за 1 шт. ($)','manual_price',item,'price',1,350)
    M.number('Количество','manual_qty',item,'qty',1,300)
    if M.button('Добавить в '..(kind=='buy' and 'скупку' or 'продажу'),'manual_add',480) then
        local draft={name=DSP.to_cp(ffi.string(U.manual_name)),enabled=true}
        for _,field in ipairs({{'ench',0},{'price',1},{'qty',1}}) do
            if not M.apply_number(draft,field[1],M.edit_buffer(item,field[1]),field[2]) then
                DSP.notify('Проверьте заточку, цену и количество'); return
            end
        end
        local ok,err=DSP.presets.add_manual(kind,draft)
        report(ok,err)
        if ok then U.trade_section='items'; ffi.fill(U.manual_name,256) end
    end
end
-- Fast add flow: type part of the name, tap the match, edit on one screen.
local function catalog_picker(kind)
    U.catalog_search=U.catalog_search or imgui.new.char[128]()
    imgui.SetNextItemWidth(math.min(760,imgui.GetContentRegionAvail().x))
    imgui.InputTextWithHint('##catalog_quick_search',DSP.utf8('Найти товар по названию...'),U.catalog_search,128)
    local query=DSP.to_cp(ffi.string(U.catalog_search))
    if DSP.trim(query)=='' then
        M.text('Введите несколько букв названия товара из базы рынка.')
        return
    end
    local rows=DSP.market.find_item(query)
    M.text('Найдено: '..#rows..' | Показаны первые 12')
    for i=1,math.min(12,#rows) do
        local row=rows[i]
        imgui.Separator()
        imgui.Columns(2,'##catalog_row'..i,false)
        M.thumbnail({name=row.display,id=row.id},48)
        M.text(row.display)
        imgui.NextColumn()
        if M.button('+ Добавить','catalog_add'..i,240) then
            local ok,err=DSP.presets.add(row,kind)
            if not ok and err=='нет цены для расчёта' then
                ok,err=DSP.presets.add_manual(kind,{
                    name=row.name or row.display,ench=row.ench or 0,key=row.key,
                    price=0,qty=1,enabled=false,needs_price=true,
                })
            end
            report(ok,err)
            if ok then U.trade_section='items' end
        end
        imgui.Columns(1)
    end
    if #rows==0 then M.text('Нет в рынке. Перейдите на «Вручную» и укажите цену.') end
end

-- Compact two-column editor based on the practical Market Helper workflow.
-- Inventory/catalog on the left, active preset on the right. No nested navigation
-- is needed to add a product; the primary action is pinned below the lists.
U.trade_picker=U.trade_picker or 'inventory'
U.trade_picker_page=U.trade_picker_page or 1
U.trade_preset_page=U.trade_preset_page or 1
local function pane(id,width,height,draw)
    if M.child then M.child(id,width,height,draw) else draw() end
end
local function page_buttons(key,count,per)
    local pages=math.max(1,math.ceil(count/per))
    local v=math.max(1,math.min(pages,tonumber(U[key]) or 1))
    U[key]=v
    if M.button('<','mh_prev_'..key,76) then U[key]=math.max(1,v-1);v=U[key] end
    M.inline()
    if M.button(v..' / '..pages,'mh_pages_'..key,90) then U[key]=1;v=1 end
    M.inline()
    if M.button('>','mh_next_'..key,76) then U[key]=math.min(pages,v+1);v=U[key] end
    return (v-1)*per+1,math.min(count,v*per)
end
local function catalog_rows(query)
    query=DSP.trim(query or '')
    if query=='' then return {} end
    local sid=DSP.market and DSP.market.state and DSP.market.state.sid or 0
    local stamp=DSP.market and DSP.market.state and (tostring(DSP.market.state.rows)..':'..tostring(DSP.market.state.version or 0)) or '0'
    local key=tostring(sid)..':'..tostring(stamp)..':'..DSP.lower(query)
    if U._catalog_key~=key then
        U._catalog_key=key
        U._catalog_rows=DSP.market.find_item(query) or {}
    end
    return U._catalog_rows or {}
end
local function picker_row(kind,it,idx,source)
    imgui.Separator()
    M.thumbnail(it,30)
    M.inline()
    M.text(tostring(it.display or it.name or '?')..(source=='inventory' and (' x'..tostring(it.count or it.qty or 1)) or ''))
    if M.button('+ В набор','mh_pick_'..source..idx,185) then
        local ok,err
        if source=='inventory' then
            local name=tostring(it.name or '')
            local ench=tonumber(it.ench) or tonumber(name:match('%(%+(%d+)%)%s*$')) or 0
            local base=name:gsub('%s+%(%+%d+%)%s*$','')
            local row=DSP.market.row_for(base,ench)
            if row then ok,err=DSP.presets.add(row,kind)
            else ok,err=DSP.presets.add_manual(kind,{name=base,ench=ench,price=0,
                qty=math.max(1,tonumber(it.count or it.qty) or 1),enabled=false,needs_price=true}) end
        else
            ok,err=DSP.presets.add(it,kind)
            if not ok and err=='нет цены для расчёта' then
                ok,err=DSP.presets.add_manual(kind,{name=it.name or it.display,ench=it.ench or 0,
                    price=0,qty=1,enabled=false,needs_price=true})
            end
        end
        report(ok,err)
        if ok then U.trade_preset_page=math.max(1,math.ceil(#DSP.presets.items(kind)/5)) end
    end
end
function U.trade_tab()
    U.preset_kind=U.preset_kind or 'buy'
    U.trade_section=U.trade_section or 'items'
    local kind=U.preset_kind
    local running=DSP.auto.buy_running or DSP.auto.sell_running
    -- Keep advanced management accessible without occupying the everyday workspace.
    if U.trade_section=='library' then
        if M.button('< Назад к торговле','mh_back_library',250) then U.trade_section='items' end
        preset_library(kind)
        return
    elseif U.trade_section=='manual' then
        if M.button('< Назад к торговле','mh_back_manual',250) then U.trade_section='items' end
        manual_entry(kind)
        return
    end
    if M.button('СКУПКА','kind_buy',210,kind=='buy','segment') then
        U.preset_kind='buy';kind='buy';U.trade_preset_page=1
    end
    M.inline()
    if M.button('ПРОДАЖА','kind_sell',210,kind=='sell','segment') then
        U.preset_kind='sell';kind='sell';U.trade_preset_page=1
    end
    local p=kind=='buy' and DSP.settings.buy_preset or DSP.settings.sell_preset
    local list=DSP.presets.list(kind)
    local selected=DSP.presets.selected(kind)
    M.text('Набор: '..tostring(p.name or 'Основной'))
    if M.button('<','preset_prev',68) and not running then
        DSP.presets.select(kind,selected>1 and selected-1 or #list)
    end
    M.inline()
    if M.button('>','preset_next',68) and not running then
        DSP.presets.select(kind,selected<#list and selected+1 or 1)
    end
    M.inline()
    if M.button('Пресеты','trade_library',160) then U.trade_section='library';return end
    M.inline()
    if M.button('Добавить вручную','trade_manual',230) then U.trade_section='manual';return end
    -- Shared availability: on smaller windows switch between the two panels
    -- instead of crushing numeric controls into unreadable columns.
    local available=imgui.GetContentRegionAvail and imgui.GetContentRegionAvail() or {x=900,y=600}
    local total_width=available and available.x or 900
    local height=available and available.y or 540
    local per=math.max(2,math.min(5,math.floor((height-125)/130)))
    local picker=U.trade_picker or 'inventory'
    local two=total_width>=980 and M.child~=nil
    local panel_h=math.max(160,height-102)
    if not two then
        if M.button('Добавить товар','mh_switch_picker',190,U.trade_narrow_picker) then U.trade_narrow_picker=true end
        M.inline()
        if M.button('Мой набор','mh_switch_preset',180,not U.trade_narrow_picker) then U.trade_narrow_picker=false end
    end
    local function draw_picker()
        if M.button('Инвентарь','mh_source_inv',182,picker=='inventory') then picker='inventory';U.trade_picker=picker;U.trade_picker_page=1 end
        M.inline()
        if M.button('Поиск','mh_source_catalog',144,picker=='catalog') then picker='catalog';U.trade_picker=picker;U.trade_picker_page=1 end
        local entries={}
        if picker=='inventory' then
            if M.button('Сканировать','scan_inventory',180) then DSP.auto.scan_inventory() end
            M.text('Инвентарь: '..tostring(DSP.auto.inv_status or 'не сканирован'))
            entries=DSP.auto.inv or {}
        else
            U.catalog_search=U.catalog_search or imgui.new.char[128]()
            imgui.SetNextItemWidth(math.min(430,imgui.GetContentRegionAvail().x))
            if imgui.InputTextWithHint('##catalog_quick_search',DSP.utf8('Название предмета...'),U.catalog_search,128) then
                U.trade_picker_page=1
            end
            entries=catalog_rows(DSP.to_cp(ffi.string(U.catalog_search)))
            if #entries==0 then M.text('Введите название предмета.') end
        end
        M.text('Найдено: '..tostring(#entries))
        local start,finish=page_buttons('trade_picker_page',#entries,per)
        for i=start,finish do picker_row(kind,entries[i],i,picker) end
    end
    local function draw_preset()
        local current=kind=='buy' and DSP.settings.buy_preset or DSP.settings.sell_preset
        local positions,subtotal=0,0
        for _,it in ipairs(current.items or {}) do
            if it.enabled~=false and (tonumber(it.price) or 0)>0 and (tonumber(it.qty) or 0)>0 then
                positions=positions+1;subtotal=subtotal+it.price*it.qty
            end
        end
        M.text('В наборе: '..#current.items..' | Активных: '..positions..' | '..DSP.money(subtotal))
        local start,finish=page_buttons('trade_preset_page',#current.items,per)
        for i=start,finish do if item_card(kind,current.items[i],i) then break end end
        if #current.items==0 then M.text('Добавьте предмет слева: он сразу появится в наборе.') end
        U.trade_active_positions=positions
    end
    if two then
        local left=math.max(340,math.floor(total_width*.39))
        pane('mh_inventory',left,panel_h,draw_picker)
        M.inline()
        pane('mh_preset',0,panel_h,draw_preset)
    elseif U.trade_narrow_picker then
        pane('mh_picker_single',0,panel_h,draw_picker)
    else
        pane('mh_preset_single',0,panel_h,draw_preset)
    end
    -- Always-visible controls, independent of either list's scrolling position.
    if running then M.text(DSP.auto.status_text())
    else M.toggle('Тест без выставления',DSP.settings,'dry_run',true) end
    local label=running and 'ОСТАНОВИТЬ' or (DSP.settings.dry_run and 'ПРОВЕРИТЬ НАБОР' or 'ВЫСТАВИТЬ '..(kind=='buy' and 'СКУПКУ' or 'ПРОДАЖУ'))
    if M.button(label,'run_'..kind,500,true,'primary') then
        if DSP.auto.buy_running then DSP.auto.stop_buy()
        elseif DSP.auto.sell_running then DSP.auto.stop_sell()
        elseif DSP.presets.active_count(kind)==0 then DSP.notify('Включите товары с ценой и количеством')
        elseif kind=='buy' then DSP.auto.start_buy() else DSP.auto.start_sell() end
    end
end
U.palatka_tab=U.trade_tab
function U.auto_tab()
    M.title('АВТОМАТИЗАЦИЯ')
    M.text(DSP.auto.status_text())
    M.text('Автоматизация выставляет товары. Счётчик показывает подтверждённые позиции, а не завершённые сделки.')
    if DSP.auto.progress then
        local p=DSP.auto.progress
        M.text('Обработано '..tostring(p.done or 0)..' из '..tostring(p.total or 0)..' | Ошибок '..tostring(p.failed or 0))
    end
    for _,kind in ipairs({'buy','sell'}) do
        local running=kind=='buy' and DSP.auto.buy_running or kind=='sell' and DSP.auto.sell_running
        local label=kind=='buy' and 'СКУПКИ' or 'ПРОДАЖИ'
        M.title(label)
        M.text('Позиций: '..DSP.presets.active_count(kind))
        if M.button((running and 'СТОП ' or 'СТАРТ ')..label,'auto_'..kind,400,running) then
            if kind=='buy' then
                if running then DSP.auto.stop_buy() else DSP.auto.start_buy() end
            else
                if running then DSP.auto.stop_sell() else DSP.auto.start_sell() end
            end
        end
    end
    M.toggle('Тест без отправки',DSP.settings,'dry_run',true)
    M.text('Последние события')
    for i=1,math.min(15,#DSP.log) do M.text((DSP.log[i].t or '')..' '..tostring(DSP.log[i].text)) end
end
