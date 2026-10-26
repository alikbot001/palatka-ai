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
local function item_card(kind,it,index)
    M.text(tostring(index)..'. '..tostring(it.name or '?'))
    if (tonumber(it.price) or 0)>0 then
        M.toggle('Выставлять##item'..kind..index,it,'enabled',true)
    else M.text('Нужна ваша цена. Позиция отключена до заполнения.'); it.enabled=false end
    imgui.Columns(2,'##edit_item'..kind..index,false)
    if M.number('Цена ($)','price'..kind..index,it,'price',1,300) then
        it.needs_price=nil; DSP.save_settings()
    end
    imgui.NextColumn()
    M.number('Количество','qty'..kind..index,it,'qty',1,230)
    imgui.Columns(1)
    if not U.trade_advanced then imgui.Separator(); return false end
    if M.button('-1$','minus'..kind..index,135) then set_price(kind,it,(tonumber(it.price) or 0)-1) end
    M.inline()
    if M.button('Рынок','market'..kind..index,180) then
        local row=DSP.presets.find_row(it)
        if row then
            local price=kind=='buy' and DSP.market.buy_target(row) or DSP.market.sell_target(row)
            if price>0 then set_price(kind,it,price) else DSP.notify('Нет цены для этой стороны рынка') end
        else DSP.notify('Товар не найден в базе рынка') end
    end
    M.inline()
    if M.button('+10 000','plus'..kind..index,180) then set_price(kind,it,(tonumber(it.price) or 0)+10000) end
    M.inline()
    if M.button('Удалить','remove'..kind..index,180) then DSP.presets.remove(kind,index); return true end
    imgui.Separator()
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
function U.trade_tab()
    local kind=U.preset_kind or 'buy'
    local p=kind=='buy' and DSP.settings.buy_preset or DSP.settings.sell_preset
    if M.button('СКУПКА','kind_buy',220,kind=='buy','segment') then U.preset_kind='buy' end
    M.inline()
    if M.button('ПРОДАЖА','kind_sell',220,kind=='sell','segment') then U.preset_kind='sell' end
    imgui.Separator()
    local running=DSP.auto.buy_running or DSP.auto.sell_running
    if DSP.presets.list then
        local list=DSP.presets.list(kind)
        local selected=DSP.presets.selected(kind)
        if M.button('<','preset_prev',70) and not running then
            DSP.presets.select(kind,selected>1 and selected-1 or #list)
        end
        M.inline()
        M.button(p.name or 'Мой набор','current_preset',320,false)
        M.inline()
        if M.button('>','preset_next',70) and not running then DSP.presets.select(kind,selected<#list and selected+1 or 1) end
    else M.title(p.name or 'Мой набор') end
    if not running then
        M.inline()
        if M.button('+ Товары','trade_add',220) then U.trade_advanced=true; U.trade_section='inventory' end
    end
    local action=running and 'ОСТАНОВИТЬ' or (U.trade_advanced and DSP.settings.dry_run and 'ПРОВЕРИТЬ' or 'ВЫСТАВИТЬ')
    if M.button(action,'run_'..kind,360,true,'primary') then
        if not running and not U.trade_advanced then DSP.settings.dry_run=false; DSP.save_settings() end
        if DSP.auto.buy_running then DSP.auto.stop_buy()
        elseif DSP.auto.sell_running then DSP.auto.stop_sell()
        elseif kind=='buy' then DSP.auto.start_buy() else DSP.auto.start_sell() end
    end
    if running then
        M.text(DSP.auto.status_text())
        if DSP.auto.progress then M.text(tostring(DSP.auto.progress.done or 0)..' / '..tostring(DSP.auto.progress.total or 0)) end
        return
    end
    if M.button(U.trade_advanced and 'Скрыть дополнительные' or 'Дополнительно','trade_advanced',380) then
        U.trade_advanced=not U.trade_advanced
        if not U.trade_advanced then U.trade_section='items' end
    end
    local section=U.trade_advanced and (U.trade_section or 'items') or 'items'
    if U.trade_advanced then
        for _,v in ipairs({{'items','Товары'},{'inventory','Инвентарь'},{'manual','Вручную'},{'library','Наборы / импорт'}}) do
            if M.button(v[2],'trade_section'..v[1],220,section==v[1]) then U.trade_section=v[1] end
            if v[1]~='library' then M.inline() end
        end
        M.toggle('Проверить без отправки',DSP.settings,'dry_run',true)
        if M.button('Обновить цены по рынку','recalc',400) then DSP.presets.recalc(kind); M.buffers=setmetatable({}, {__mode='k'}) end
    end
    imgui.Separator()
    if section=='library' then preset_library(kind,p)
    elseif section=='inventory' then inventory(kind)
    elseif section=='manual' then manual_entry(kind)
    else
        if #p.items==0 then
            M.text('Выберите свой набор или добавьте товары.')
            if M.button('Взять мои наборы из Market Helper','empty_import',650) then
                report(DSP.presets.import_mh()); U.trade_section='items'
            end
            if M.button('Добавить товары','empty_add',420) then U.trade_advanced=true; U.trade_section='inventory' end
        end
        for i,it in ipairs(p.items) do if item_card(kind,it,i) then break end end
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
