-- Palatka 1.6: single-column Market Helper workflow, touch-first.
-- Trading engine remains in 40_auto, 41_trade_listing and 42_trade_buy.
local ffi=require('ffi')
local U,M=DSP.ui,DSP.mobile
local T={}
DSP.trade_v16=T
U.v16_side=U.v16_side or 'sell'
U.v16_tab=U.v16_tab or 'items'
U.v16_source=U.v16_source or 'inventory'
U.v16_page=U.v16_page or 1

local function busy() return DSP.auto.buy_running or DSP.auto.sell_running end
local function current(kind) return kind=='sell' and DSP.settings.sell_preset or DSP.settings.buy_preset end
local function quantity(v) return math.max(1,math.floor(tonumber(v) or 1)) end
local function safe_key(it)
    local name=tostring(it.name or it.display or '')
    local ench=tonumber(it.ench) or tonumber(name:match('%(%+(%d+)%)%s*$')) or 0
    local base=name:gsub('%s+%(%+%d+%)%s*$','')
    return base,ench,DSP.item_key(base,ench)
end
function T.add_from_inventory(kind,it)
    if busy() then return false,'остановите выставление' end
    local base,ench,key=safe_key(it)
    local count=quantity(it.count or it.qty)
    local index,exists=DSP.presets.find(kind,key)
    if exists then
        -- Re-tapping updates quantity; it MUST NOT overwrite the user's price.
        if kind=='sell' then exists.qty=count end
        M.refresh_buffer(exists,'qty')
        M.defer_save()
        return true,'количество обновлено'
    end
    local ok,err=DSP.presets.add_manual(kind,{name=base,ench=ench,qty=kind=='sell' and count or 1,
        price=0,enabled=false,needs_price=true})
    return ok,err
end
function T.add_from_catalog(kind,it)
    if busy() then return false,'остановите выставление' end
    local base,ench,key=safe_key(it)
    if DSP.presets.find(kind,key) then return true,'уже в пресете' end
    return DSP.presets.add_manual(kind,{name=base,ench=ench,qty=1,price=0,
        enabled=false,needs_price=true})
end
function T.validate(kind)
    local problems,items,total={},current(kind).items or {},0
    local inventory={}
    if kind=='sell' then
        for _,item in ipairs(DSP.auto.inv or {}) do
            local _,_,key=safe_key(item)
            inventory[key]=(inventory[key] or 0)+math.max(0,tonumber(item.count or item.qty) or 0)
        end
    end
    for _,it in ipairs(items) do
        if it.enabled~=false then
            local price,qty=tonumber(it.price) or 0,tonumber(it.qty) or 0
            if price<1 or price~=math.floor(price) or qty<1 or qty~=math.floor(qty) then
                problems[#problems+1]=it.name..': проверьте цену и количество'
            else
                if kind=='sell' then
                    local _,_,key=safe_key(it)
                    local avail=inventory[key] or 0
                    if qty>avail then problems[#problems+1]=it.name..': в инвентаре '..math.floor(avail)..' шт.' end
                    inventory[key]=math.max(0,avail-qty)
                end
                total=total+price*qty
            end
        end
    end
    if kind=='sell' and #(DSP.auto.inv or {})==0 then
        problems[#problems+1]='сначала просканируйте инвентарь'
    end
    if DSP.presets.active_count(kind)==0 then problems[#problems+1]='нет включённых позиций' end
    return #problems==0,problems,total
end
local function start(kind)
    local ok,issues=T.validate(kind)
    if not ok then DSP.notify(table.concat(issues,'; '));return false end
    return kind=='sell' and DSP.auto.start_sell() or DSP.auto.start_buy()
end
local function control(label,id,width,active,role)
    return M.button(label,'v16_'..id,width,active,role)
end
local function pager(count,per)
    local pages=math.max(1,math.ceil(count/per))
    U.v16_page=math.min(pages,math.max(1,U.v16_page or 1))
    local w=math.max(80,math.min(142,(imgui.GetContentRegionAvail().x-24)/3))
    if control('<','previous',w) then U.v16_page=math.max(1,U.v16_page-1) end
    M.inline()
    if control(U.v16_page..' / '..pages,'counter',w) then U.v16_page=1 end
    M.inline()
    if control('>','next',w) then U.v16_page=math.min(pages,U.v16_page+1) end
    return (U.v16_page-1)*per+1,math.min(U.v16_page*per,count)
end
local function inventory_list(kind)
    if control('Инвентарь','source_inventory',200,U.v16_source=='inventory') then U.v16_source='inventory';U.v16_page=1 end
    M.inline()
    if control('Каталог','source_catalog',160,U.v16_source=='catalog') then U.v16_source='catalog';U.v16_page=1 end
    local entries={}
    if U.v16_source=='inventory' then
        if control('Сканировать','scan',220) then DSP.auto.scan_inventory() end
        M.inline();M.text(tostring(DSP.auto.inv_status or 'Нет данных'))
        entries=DSP.auto.inv or {}
    else
        U.catalog_search=U.catalog_search or imgui.new.char[128]()
        imgui.SetNextItemWidth(math.min(500,imgui.GetContentRegionAvail().x))
        if imgui.InputTextWithHint('##v16_search',DSP.utf8('Поиск предмета'),U.catalog_search,128) then U.v16_page=1 end
        local query=DSP.to_cp(ffi.string(U.catalog_search))
        if query~='' then
            local revision=tostring(DSP.market.state.version or 0)..':'..DSP.lower(query)
            if U.v16_catalog_revision~=revision then
                U.v16_catalog_revision=revision
                U.v16_catalog_rows=DSP.market.find_item(query) or {}
            end
            entries=U.v16_catalog_rows or {}
        end
    end
    M.text('Предметов: '..#entries)
    local from,to=pager(#entries,7)
    for i=from,to do
        local it=entries[i]
        if it then
            imgui.Separator()
            M.thumbnail(it,26);M.inline()
            local name=tostring(it.display or it.name or '?')
            local amount=U.v16_source=='inventory' and (' x'..tostring(it.count or it.qty or 1)) or ''
            M.text(name..amount)
            if control('+','add_'..i,125) then
                local ok,msg
                if U.v16_source=='inventory' then ok,msg=T.add_from_inventory(kind,it)
                else ok,msg=T.add_from_catalog(kind,it) end
                DSP.notify(ok and 'В пресете: '..name or tostring(msg))
            end
        end
    end
    if #entries==0 then M.text('Нет предметов. Откройте инвентарь или используйте поиск.') end
    if control(U.v16_manual and 'Скрыть ручной ввод' or '+ Ввести название вручную','manual_toggle',300) then
        U.v16_manual=not U.v16_manual
    end
    if U.v16_manual then
        U.v16_manual_name=U.v16_manual_name or imgui.new.char[256]()
        imgui.SetNextItemWidth(math.min(450,imgui.GetContentRegionAvail().x))
        imgui.InputTextWithHint('##v16_manual_name',DSP.utf8('Название предмета как в игре'),U.v16_manual_name,256)
        if control('Добавить без цены','manual_add',220) then
            local name=DSP.to_cp(ffi.string(U.v16_manual_name))
            local ok,msg=T.add_from_catalog(kind,{name=name})
            DSP.notify(ok and 'Добавлено. Цена вводится в пресете.' or tostring(msg))
        end
    end
    M.text('Цена вводится в «Мой пресет»; рыночная не подставляется.')
end
local function preset_row(kind,it,i)
    local width=imgui.GetContentRegionAvail().x
    imgui.Separator()
    local v=imgui.new.bool(it.enabled~=false)
    if imgui.Checkbox('##v16_enabled_'..i,v) then
        it.enabled=v[0] and (tonumber(it.price) or 0)>0 or false; M.defer_save()
    end
    M.inline();M.thumbnail(it,24);M.inline()
    M.text(tostring(it.name or '?'))
    local n=math.max(90,math.min(180,math.floor(width*.27)))
    imgui.TextDisabled(DSP.utf8('Цена'))
    imgui.SetNextItemWidth(n)
    if M.compact_number(it,'price','v16_price_'..kind..i,n,0) then
        it.needs_price=(it.price==0) or nil
        it.enabled=it.price>0
    end
    M.inline()
    imgui.TextDisabled(DSP.utf8('Штук'))
    imgui.SetNextItemWidth(n)
    M.compact_number(it,'qty','v16_qty_'..kind..i,n,1)
    if kind=='buy' then
        for _,nqty in ipairs({1,10,100}) do
            if control(tostring(nqty),'qty_'..i..'_'..nqty,76) then
                it.qty=nqty;M.refresh_buffer(it,'qty');M.defer_save()
            end
            M.inline()
        end
        if control('Макс','qty_max_'..i,95) then
            -- Server-specific max cannot be guessed. Use an explicit per-item cap.
            U.v16_max_item=it
            if imgui.OpenPopup then imgui.OpenPopup(DSP.utf8('Макс. количество')..'##v16_max') end
        end
    end
    if control('Удалить','remove_'..i,150) then
        U.v16_remove_pending={kind=kind,index=i,name=it.name}
        if imgui.OpenPopup then imgui.OpenPopup(DSP.utf8('Удалить позицию')..'##v16_remove') end
    end
end
local function dialogs()
    if not imgui.BeginPopupModal then return end
    local max_popup=DSP.utf8('Макс. количество')..'##v16_max'
    if imgui.BeginPopupModal(max_popup,nil,imgui.WindowFlags.AlwaysAutoResize) then
        local it=U.v16_max_item
        if it then
            it._v16_max=it._v16_max or {count=it.max_qty or it.qty or 1}
            M.text('Укажите точный лимит для этого предмета.')
            M.number('Максимум, шт.','max_amount',it._v16_max,'count',1,190)
            if control('Применить','max_apply',160) then
                it.max_qty=it._v16_max.count
                it.qty=it.max_qty
                M.refresh_buffer(it,'qty')
                M.defer_save()
                imgui.CloseCurrentPopup()
            end
        end
        M.inline()
        if control('Отмена','max_cancel',145) then imgui.CloseCurrentPopup() end
        imgui.EndPopup()
    end
    local id=DSP.utf8('Удалить позицию')..'##v16_remove'
    if imgui.BeginPopupModal(id,nil,imgui.WindowFlags.AlwaysAutoResize) then
        M.text('Убрать '..tostring(U.v16_remove_pending and U.v16_remove_pending.name or 'предмет')..' из пресета?')
        if control('Отмена','remove_cancel',140) then imgui.CloseCurrentPopup() end
        M.inline()
        if control('Удалить','remove_confirm',160) then
            local p=U.v16_remove_pending
            if p then DSP.presets.remove(p.kind,p.index) end
            U.v16_remove_pending=nil
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end
end
local function library_controls(kind)
    local list=DSP.presets.list(kind)
    local i=DSP.presets.selected(kind)
    local p=current(kind)
    M.text('Пресет: '..tostring(p.name))
    if control('<','preset_prev',70) and not busy() then DSP.presets.select(kind,i>1 and i-1 or #list) end
    M.inline()
    if control('>','preset_next',70) and not busy() then DSP.presets.select(kind,i<#list and i+1 or 1) end
    M.inline()
    if control('Пресеты','preset_manage',160) then U.v16_library=not U.v16_library end
    if not U.v16_library then return end
    U.v16_name=U.v16_name or imgui.new.char[128]()
    imgui.SetNextItemWidth(math.min(320,imgui.GetContentRegionAvail().x))
    imgui.InputTextWithHint('##v16_preset_name',DSP.utf8('Название пресета'),U.v16_name,128)
    local name=DSP.to_cp(ffi.string(U.v16_name))
    if control('Создать','preset_create',146) then DSP.presets.create(kind,name) end
    M.inline()
    if control('Переименовать','preset_rename',200) then DSP.presets.rename(kind,DSP.presets.selected(kind),name) end
    M.inline()
    if control('Экспорт','preset_export',130) then local ok,msg=DSP.presets.export_file(kind);DSP.notify(tostring(msg or ok)) end
    if control('Импорт Market Helper','preset_import_mh',270) then
        local ok,msg=DSP.presets.import_mh();DSP.notify(ok and 'Импортировано' or tostring(msg))
    end
    U.v16_import=U.v16_import or imgui.new.char[384]()
    imgui.SetNextItemWidth(math.min(420,imgui.GetContentRegionAvail().x))
    imgui.InputTextWithHint('##v16_import_path',DSP.utf8('Путь к JSON пресета'),U.v16_import,384)
    if control('Импорт JSON','preset_import_json',195) then
        local ok,msg=DSP.presets.import_file(DSP.to_cp(ffi.string(U.v16_import)),kind)
        DSP.notify(ok and 'Импортировано' or tostring(msg))
    end
    if control('Удалить пресет','preset_remove',220) then
        if imgui.OpenPopup then imgui.OpenPopup(DSP.utf8('Удалить пресет')..'##v16_preset') end
    end
    local popup=DSP.utf8('Удалить пресет')..'##v16_preset'
    if imgui.BeginPopupModal and imgui.BeginPopupModal(popup,nil,imgui.WindowFlags.AlwaysAutoResize) then
        M.text('Безвозвратно удалить выбранный пресет?')
        if control('Отмена','preset_cancel',150) then imgui.CloseCurrentPopup() end
        M.inline()
        if control('Удалить','preset_confirm',160) then
            local ok,err=DSP.presets.delete(kind,DSP.presets.selected(kind))
            if not ok then DSP.notify(err) end
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end
end
local function review(kind)
    local popup=DSP.utf8('Проверка выставления')..'##v16_review'
    if imgui.BeginPopupModal and imgui.BeginPopupModal(popup,nil,imgui.WindowFlags.AlwaysAutoResize) then
        M.title('Проверить список')
        local ok,issues,total=T.validate(kind)
        local shown=0
        for _,it in ipairs(current(kind).items or {}) do
            if it.enabled~=false then
                M.text(tostring(it.name)..'  x'..tostring(it.qty)..'  '..DSP.money(it.price))
                shown=shown+1
                if shown>=12 then M.text('Остальные позиции: '..(DSP.presets.active_count(kind)-shown));break end
            end
        end
        M.text('Итого: '..DSP.money(total))
        for _,problem in ipairs(issues) do
            imgui.TextColored(DSP.theme.col('bad',1),DSP.utf8(problem))
        end
        if control('Отмена','review_cancel',160) then imgui.CloseCurrentPopup() end
        M.inline()
        if control('Выставить','review_confirm',200,ok,'primary') then
            if ok then start(kind);imgui.CloseCurrentPopup() else DSP.notify('Исправьте ошибки выше') end
        end
        imgui.EndPopup()
    end
end
local function my_preset(kind)
    library_controls(kind)
    local items=current(kind).items or {}
    M.text('Позиций: '..#items..'  |  Включено: '..DSP.presets.active_count(kind))
    local from,to=pager(#items,5)
    for i=from,to do preset_row(kind,items[i],i) end
    if #items==0 then M.text('Пресет пуст. Добавьте предметы во вкладке «Предметы».') end
end
function U.trade_tab()
    local kind=U.v16_side
    if control('ПРОДАЖА','sell',210,kind=='sell') then U.v16_side='sell';kind='sell';U.v16_page=1 end
    M.inline()
    if control('СКУПКА','buy',200,kind=='buy') then U.v16_side='buy';kind='buy';U.v16_page=1 end
    local tab=U.v16_tab
    if control('Предметы','items',200,tab=='items') then U.v16_tab='items';tab='items';U.v16_page=1 end
    M.inline()
    if control('Мой пресет','preset',200,tab=='preset') then U.v16_tab='preset';tab='preset';U.v16_page=1 end
    imgui.Separator()
    local h=math.max(150,(imgui.GetContentRegionAvail().y or 450)-145)
    M.child('v16_trade_'..tab,0,h,function()
        if tab=='items' then inventory_list(kind) else my_preset(kind) end
    end)
    if busy() then
        M.text(DSP.auto.status_text())
        if control('ОСТАНОВИТЬ','stop',240,true,'primary') then
            if DSP.auto.buy_running then DSP.auto.stop_buy() else DSP.auto.stop_sell() end
        end
    else
        M.text('Выставление: '..(DSP.settings.dry_run and 'тест' or 'реальное'))
        if control('Тест / Реально','dry_toggle',205) then
            DSP.settings.dry_run=not DSP.settings.dry_run;M.defer_save()
        end
        M.inline()
        if control('Быстро выставить','fast',250,true,'primary') then start(kind) end
        M.inline()
        if control('Проверить список','review',245) then
            if imgui.OpenPopup then imgui.OpenPopup(DSP.utf8('Проверка выставления')..'##v16_review') end
        end
    end
    dialogs()
    review(kind)
end
U.palatka_tab=U.trade_tab
