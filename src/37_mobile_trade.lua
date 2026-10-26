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
-- Compact, single-card editor: icon + inline price/amount + direct deletion.
local function item_card(kind,it,index)
    local id=kind..'_'..index
    local valid=(tonumber(it.price) or 0)>0 and (tonumber(it.qty) or 0)>0
    if not valid then it.enabled=false end
    imgui.Separator()
    imgui.Columns(4,'##itemrow'..id,false)
    M.thumbnail(it,64)
    imgui.NextColumn()
    M.text(tostring(it.name or '?')..((tonumber(it.ench) or 0)>0 and (' (+'..it.ench..')') or ''))
    M.toggle('Вкл.##'..id,it,'enabled',valid)
    imgui.NextColumn()
    imgui.TextDisabled(DSP.utf8('Цена за 1 шт.'))
    if M.compact_number(it,'price','price_'..id,150,1) then it.needs_price=nil end
    imgui.NextColumn()
    imgui.TextDisabled(DSP.utf8('Штук'))
    M.compact_number(it,'qty','qty_'..id,120,1)
    if M.button('-','qty_sub_'..id,60) then
        it.qty=math.max(1,(tonumber(it.qty) or 1)-1)
        M.refresh_buffer(it,'qty'); DSP.save_settings()
    end
    M.inline()
    if M.button('+','qty_add_'..id,60) then
        it.qty=math.min(1000000,(tonumber(it.qty) or 1)+1)
        M.refresh_buffer(it,'qty'); DSP.save_settings()
    end
    M.inline()
    if M.button('X','delete_'..id,60) then
        imgui.Columns(1)
        DSP.presets.remove(kind,index)
        return true
    end
    imgui.Columns(1)
    if not valid then M.text('Укажите цену и количество; позиция пока отключена.') end
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

function U.trade_tab()
    U.preset_kind=U.preset_kind or 'buy'
    local kind=U.preset_kind
    M.title('ТОРГОВЛЯ')
    if M.button('СКУПКА','kind_buy',260,kind=='buy','segment') then U.preset_kind='buy'; kind='buy' end
    M.inline()
    if M.button('ПРОДАЖА','kind_sell',260,kind=='sell','segment') then U.preset_kind='sell'; kind='sell' end
    local p=kind=='buy' and DSP.settings.buy_preset or DSP.settings.sell_preset
    local running=DSP.auto.buy_running or DSP.auto.sell_running
    imgui.Separator()
    local list=DSP.presets.list and DSP.presets.list(kind) or {{name=p.name}}
    local selected=DSP.presets.selected and DSP.presets.selected(kind) or 1
    M.text('Набор: '..tostring(p.name or 'Мой набор'))
    if M.button('<','preset_prev',62) and not running then
        DSP.presets.select(kind,selected>1 and selected-1 or #list)
    end
    M.inline()
    if M.button('>','preset_next',62) and not running then
        DSP.presets.select(kind,selected<#list and selected+1 or 1)
    end
    M.inline()
    if M.button('+ Добавить','trade_add',220,(U.trade_section=='catalog' or U.trade_section=='inventory' or U.trade_section=='manual')) and not running then
        U.trade_section=U.trade_section=='catalog' and 'items' or 'catalog'
    end
    M.inline()
    if M.button('Наборы','trade_library',170,U.trade_section=='library') then
        U.trade_section=U.trade_section=='library' and 'items' or 'library'
    end
    local section=U.trade_section or 'items'
    if section=='library' then
        preset_library(kind,p)
    elseif section=='catalog' or section=='inventory' or section=='manual' then
        if M.button('Поиск','source_catalog',170,section=='catalog') then U.trade_section='catalog'; section='catalog' end
        M.inline()
        if M.button('Инвентарь','source_inventory',230,section=='inventory') then U.trade_section='inventory'; section='inventory' end
        M.inline()
        if M.button('По названию','source_manual',240,section=='manual') then U.trade_section='manual'; section='manual' end
        M.inline()
        if M.button('Вернуться к списку','source_close',300) then U.trade_section='items'; section='items' end
        imgui.Separator()
        if section=='catalog' then catalog_picker(kind)
        elseif section=='inventory' then inventory(kind)
        elseif section=='manual' then manual_entry(kind) end
    else
        M.text('ПРЕДМЕТЫ   |   Активно: '..tostring(DSP.presets.active_count(kind)))
        if #p.items==0 then M.text('Пока пусто. Нажмите «+ Добавить», выберите предмет и задайте цену.') end
        for i,it in ipairs(p.items) do if item_card(kind,it,i) then break end end
        imgui.Separator()
        local positions,subtotal=0,0
        for _,it in ipairs(p.items) do
            if it.enabled~=false and (tonumber(it.price) or 0)>0 and (tonumber(it.qty) or 0)>0 then
                positions=positions+1
                subtotal=subtotal+(tonumber(it.price) or 0)*(tonumber(it.qty) or 0)
            end
        end
        M.text('Активных позиций: '..positions..'   |   Сумма: '..DSP.money(subtotal))
        if not running then M.toggle('Проверить без выставления',DSP.settings,'dry_run',true) end
        if running then
            M.text(DSP.auto.status_text())
            if DSP.auto.progress then M.text(tostring(DSP.auto.progress.done or 0)..' из '..tostring(DSP.auto.progress.total or 0)) end
        end
        local label=running and 'ОСТАНОВИТЬ' or (DSP.settings.dry_run and 'ПРОВЕРИТЬ НАБОР' or 'ВЫСТАВИТЬ '..(kind=='buy' and 'СКУПКУ' or 'ПРОДАЖУ'))
        if M.button(label,'run_'..kind,550,true,'primary') then
            if DSP.auto.buy_running then DSP.auto.stop_buy()
            elseif DSP.auto.sell_running then DSP.auto.stop_sell()
            elseif positions==0 then DSP.notify('Нет включённых товаров с ценой и количеством')
            elseif kind=='buy' then DSP.auto.start_buy() else DSP.auto.start_sell() end
        end
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
