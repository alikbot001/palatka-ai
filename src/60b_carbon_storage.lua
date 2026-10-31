-- Safe container analyzer; cannot read bespoke game UIs without a packet parser.
local ffi=require('ffi')
local V,S,M=DSP.ui21,DSP.storage,DSP.mobile
V.storage_sort='value'
V.storage_selected=1
local function b(s,id,w,on,primary)return V.button(s,'storage_'..id,w,on,primary)end
-- One task per panel: scanner, snapshots, manual fallback. This avoids the
-- previous giant fixed header which pushed the item list off small screens.
function V.storage_screen()
    V.heading('Хранилища',function()
        if DSP.storage_beta_rollback and b('CRR ОТКАТ','beta_rollback',145,false,true) then
            V.open_popup('CRR откат','storage_beta_rollback')
        end
    end,DSP.storage_beta_rollback and 149 or 0)

    -- Old versions used "snapshots/manual". Collapse them into the two-task UI.
    if V.storage_tab=='snapshots' then V.storage_tab='library' end
    if V.storage_tab=='manual' then V.storage_tab='scan' end
    V.storage_tab=V.storage_tab or 'scan'
    V.storage_scan_mode=(V.storage_scan_mode=='inventory') and 'trunk' or (V.storage_scan_mode or 'trunk')
    V.storage_library_page=V.storage_library_page or 'list'

    local width=imgui.GetContentRegionAvail().x
    local tabw=math.max(120,(width-6)/2)
    for i,tab in ipairs({{'scan','СКАН'},{'library','МОИ ХРАНИЛИЩА'}})do
        if b(tab[2],'tab_'..tab[1],tabw,V.storage_tab==tab[1],V.storage_tab==tab[1])then
            V.storage_tab=tab[1]
            if tab[1]=='library' then V.storage_library_page='list' end
            V.reset_list('storage_scan_panel')
        end
        if i==1 then V.inline(6)end
    end
    imgui.Separator()

    if V.storage_tab=='scan' then
        V.list('storage_scan_panel',function(w)
            local options={{'trunk','Багажник'},{'cabinet','Шкаф'},{'warehouse','Склад'}}
            local bw=math.max(92,(w-12)/3)
            for i,item in ipairs(options)do
                if b(item[2],'choose_'..item[1],bw,V.storage_scan_mode==item[1],V.storage_scan_mode==item[1])then
                    if S.cancel_trunk_scan and V.storage_scan_mode=='trunk' and item[1]~='trunk' then
                        S.cancel_trunk_scan()
                    end
                    V.storage_scan_mode=item[1]
                    V.probe_error=nil
                    V.reset_list('storage_scan_panel')
                end
                if i<3 then V.inline(6)end
            end
            imgui.Separator()

            if V.storage_scan_mode~='trunk' then
                if V.storage_probe_panel then V.storage_probe_panel(w,V.storage_scan_mode)
                else V.red('Сканер этого хранилища недоступен.') end
                return
            end

            local t=(S.trunk_state and S.trunk_state()) or S.trunk or {}
            local active=t.requested_at~=nil or t.status=='waiting_open' or
                t.status=='receiving' or t.status=='need_reopen'

            V.apply_font((V.font_pixels or 18)*1.18)
            V.text('НОВЫЙ СКАН БАГАЖНИКА')
            V.apply_font()

            if active then
                if t.status=='receiving' then
                    V.green('ПОЛУЧАЮ ДАННЫЕ: '..tostring(t.received or 0)..' / 180')
                    V.muted('Не закрывай багажник, пока не будет 180 / 180.')
                elseif t.status=='need_reopen' then
                    V.red('НУЖНО ЗАНОВО ОТКРЫТЬ БАГАЖНИК')
                    V.text('Закрой багажник полностью и открой его ещё раз.')
                    V.muted('Перемещение предметов внутри уже открытого багажника даёт только частичные изменения.')
                else
                    V.green('СКАН ЗАПУЩЕН')
                    V.text('Если багажник уже открыт — закрой его.')
                    V.text('Затем открой багажник заново обычным способом.')
                    V.muted('Жду полный снимок 180 / 180 слотов.')
                end
                V.muted('Получено: '..tostring(t.received or 0)..' / 180')
                if b('ОТМЕНИТЬ СКАН','cancel_trunk',math.min(w,240))then
                    S.cancel_trunk_scan()
                end
                V.muted('Предыдущий результат во время нового скана не показывается.')
                return
            end

            if t.status=='no_packets' or t.status=='incomplete' then
                V.red('НОВЫЙ СКАН НЕ ПОЛУЧЕН')
                V.text('Закрой багажник, нажми «Начать новый скан» и открой его заново.')
            elseif t.last_error and t.status~='saved' then
                V.red(V.fit(tostring(t.last_error),w))
            end

            if b('НАЧАТЬ НОВЫЙ СКАН','start_trunk',math.min(w,320),false,true)then
                S.begin_trunk_scan()
                V.storage_error=nil
                return
            end
            V.muted('Важно: скан запускается ДО повторного открытия багажника.')

            if t.snapshot and t.status=='saved' then
                imgui.Separator()
                V.green('ГОТОВО · 180 / 180')
                V.text('Занято слотов: '..tostring(t.snapshot.occupied_slots or 0))
                V.text('Всего предметов: '..tostring(t.snapshot.count_known or 0))
                local sig=tostring(t.last_saved_at or t.snapshot.observed_at)..'/'..
                    tostring(DSP.market and DSP.market.state and DSP.market.state.version or '')
                local info=V.memo('storage_trunk_summary',sig,function()return S.evaluate(t.snapshot)end)
                if not info.cross_server then
                    V.green('Оценка скупки: '..DSP.money(info.sell_to_buyers))
                end

                local update_target=t.completed_update_target_id and S.find_snapshot(t.completed_update_target_id)
                if update_target then
                    V.text('Обновить: '..tostring(update_target.title))
                    if b('ПРИМЕНИТЬ К '..tostring(update_target.title),'apply_update',math.min(w,320),false,true)then
                        local ok,updated=S.apply_latest_to_saved(update_target.id)
                        if ok then
                            local _,idx=S.find_snapshot(updated.id)
                            V.storage_selected=idx or 1
                            V.storage_library_page='detail'
                            V.storage_tab='library'
                            return
                        else V.storage_error=tostring(updated) end
                    end
                    if b('СОХРАНИТЬ КАК НОВОЕ','save_update_new',math.min(w,290))then
                        V.storage_name_target=t.snapshot
                        V.storage_name_buf=imgui.new.char[128]()
                        V.storage_name_error=nil
                        V.open_popup('Сохранить багажник','storage_trunk_name')
                    end
                else
                    if b('СОХРАНИТЬ КАК НОВОЕ','save_new',math.min(w,290),false,true)then
                        V.storage_name_target=t.snapshot
                        V.storage_name_buf=imgui.new.char[128]()
                        V.storage_name_error=nil
                        V.open_popup('Сохранить багажник','storage_trunk_name')
                    end
                end
                if b('ОЧИСТИТЬ ПОСЛЕДНИЙ СКАН','clear_live',math.min(w,290))then
                    local ok,err=S.clear_live_snapshot()
                    if not ok then V.storage_error=tostring(err) end
                end
            end

            if V.storage_error then V.red(V.fit(V.storage_error,w)) end
            imgui.Separator()
            if b((t.autoscan_enabled and 'Автоскан: ВКЛ' or 'Автоскан: ВЫКЛ'),
                 'toggle_auto',math.min(w,210),t.autoscan_enabled)then
                local ok,err=S.set_trunk_autoscan(not t.autoscan_enabled)
                if not ok then V.storage_error=tostring(err) end
            end
            V.muted('Автоскан ловит полный снимок при открытии багажника. Он не угадывает машину по посадке в авто.')
        end,{footer=false})
        return
    end

    local snapshots=S.snapshots or {}
    local library=S.library and S.library() or {}

    if V.storage_library_page=='list' then
        V.apply_font((V.font_pixels or 18)*1.24)
        V.text('МОИ ХРАНИЛИЩА')
        V.apply_font()
        V.muted('Только сохранённые записи. Последний скан сюда не подмешивается.')
        if b('+ НОВЫЙ СКАН','library_new_scan',math.min(230,width),false,true)then
            V.storage_tab='scan'
            V.storage_scan_mode='trunk'
            S.begin_trunk_scan()
            V.reset_list('storage_scan_panel')
            return
        end
        if #library==0 then
            V.muted('Пока ничего не сохранено.')
            V.muted('Просканируй багажник и выбери «Сохранить как новое».')
            return
        end
        V.list_rows('storage_library',library,88,function(entry,i)
            local snap=entry.snapshot
            local kind=snap.kind=='trunk'and'Багажник' or snap.kind=='cabinet'and'Шкаф'
                or snap.kind=='warehouse'and'Склад' or'Хранилище'
            V.row('storage_library_'..i,88,function(rw,x,y)
                V.at(x,y)
                V.apply_font((V.font_pixels or 18)*1.16)
                if V.text_button(V.fit(tostring(snap.title or kind),rw),'storage_library_open_'..i,rw,false,36)then
                    V.storage_selected=entry.index
                    V.storage_library_page='detail'
                    V.reset_list('storage_items')
                end
                V.apply_font()
                V.at(x,y+43)
                local info=S.evaluate(snap)
                V.muted(V.fit(kind..' · '..tostring(snap.count_known or 0)..' шт. · '..DSP.money(info.sell_to_buyers),rw))
            end)
        end,{footer=function()V.muted('Сохранено: '..#library..' / '..tostring(S.max_saved or 20))end})
        return
    end

    local current=snapshots[V.storage_selected or 1]
    if not current or current.source=='packet220_trunk' then
        V.storage_library_page='list'
        return
    end
    if b('< МОИ ХРАНИЛИЩА','library_back',math.min(230,width))then
        V.storage_library_page='list'
        return
    end

    V.apply_font((V.font_pixels or 18)*1.34)
    V.text(V.fit(tostring(current.title or 'Без названия'),width))
    V.apply_font()
    local kind=current.kind=='trunk'and'Багажник' or current.kind=='cabinet'and'Шкаф'
        or current.kind=='warehouse'and'Склад' or'Хранилище'
    V.muted(kind..' · '..os.date('%d.%m.%Y %H:%M',current.observed_at or os.time()))

    if current.source=='packet220_trunk_named' then
        if b('ОБНОВИТЬ СКАН','library_update',math.min(240,width),false,true)then
            S.begin_trunk_scan(current.id)
            V.storage_tab='scan'
            V.storage_scan_mode='trunk'
            return
        end
    end
    if b('Переименовать','rename',math.min(180,width))then
        V.storage_label_target=current
        V.storage_label_buf=imgui.new.char[128]()
        ffi.copy(V.storage_label_buf,DSP.utf8(tostring(current.title or '')):sub(1,120))
        V.storage_label_error=nil
        V.open_popup('Название снимка','storage_rename')
    end
    if b('УДАЛИТЬ','delete_one',math.min(150,width))then
        V.storage_delete_target=current
        V.storage_delete_error=nil
        V.open_popup('Удалить хранилище','storage_delete_one')
    end

    local rows,info=S.sorted(current,V.storage_sort)
    V.text('Предметов: '..info.total_qty..' шт.')
    if current.kind=='trunk' then
        V.muted('Занято слотов: '..tostring(current.occupied_slots or #current.rows)..' / 180')
    elseif current.source=='packet220_probe' then
        V.red('Предварительный снимок: полный формат этого хранилища ещё проверяется.')
    end
    V.green('Оценка скупки: '..DSP.money(info.sell_to_buyers))
    V.muted('По объявлениям: '..DSP.money(info.ask_value)..' · не чистая прибыль')

    V.list_rows('storage_items',rows,82,function(it,i)
        V.row('storage_item_'..i,82,function(rw,x,y)
            V.at(x,y);V.text(V.fit(it.name,rw))
            V.at(x,y+30)
            V.muted(V.fit('Количество: '..(it.qty and tostring(it.qty)..' шт.'or'неизвестно'),rw))
            V.at(x,y+56)
            local total=(it.bid and it.qty)and DSP.money(it.bid*it.qty)or'нет оценки'
            V.muted(V.fit('Скупают: '..(it.bid and DSP.money(it.bid)or'?')..' / шт. · '..total,rw))
        end)
    end,{footer=false})
end

-- Deletion is a real modal confirmation; cancellation never changes snapshots.
local old_popups=V.popups
function V.popups()
    if old_popups then old_popups()end
    V.popup('CRR откат','storage_beta_rollback',function()
        V.text('Вернуть стабильную Palatka AI с обычным интерфейсом?')
        V.muted('Тестовый сканер будет отключён. Настройки, пресеты и снимки не удаляются.')
        if b('ПОДТВЕРДИТЬ ОТКАТ','beta_rollback_confirm',230,false,true)then
            local ok,err=DSP.storage_beta_rollback()
            if ok then
                imgui.CloseCurrentPopup()
            else
                V.storage_rollback_error=tostring(err)
            end
        end
        V.inline()
        if b('Отмена','beta_rollback_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_rollback_error then V.red(V.fit(V.storage_rollback_error,imgui.GetContentRegionAvail().x))end
    end,{w=480,h=260})
    V.popup('Сохранить багажник','storage_trunk_name',function()
        local target=V.storage_name_target
        if not target then V.red('Нет полного снимка багажника.');return end
        V.text('Введи своё название сохранённого снимка')
        V.muted('Например: Моя машина с ларцами / Машина с ресурсами.')
        V.muted('Следующее открытие другого багажника НЕ будет иметь это название автоматически.')
        imgui.SetNextItemWidth(-1)
        imgui.InputText('##storage_trunk_named_input',V.storage_name_buf,128)
        if b('Сохранить под названием','save_named_trunk',math.min(240,imgui.GetContentRegionAvail().x),false,true)then
            local name=DSP.to_cp(ffi.string(V.storage_name_buf))
            local ok,snapshot=S.save_named_trunk(target,name)
            if ok then
                V.storage_name_target=nil
                V.storage_name_error=nil
                V.storage_tab='library'
                V.storage_library_page='detail'
                for i,saved in ipairs(S.snapshots or {})do
                    if saved==snapshot then V.storage_selected=i;break end
                end
                imgui.CloseCurrentPopup()
            else
                V.storage_name_error=tostring(snapshot)
            end
        end
        if b('Отмена','cancel_named_trunk',120)then imgui.CloseCurrentPopup()end
        if V.storage_name_error then V.red(V.fit(V.storage_name_error,imgui.GetContentRegionAvail().x))end
    end,{w=460,h=330})
    V.popup('Своя цена','storage_price',function()
        local target,row=V.storage_price_target,V.storage_price_row
        if not target or not row then V.muted('Нет выбранного предмета');return end
        V.text(V.fit(row.name,imgui.GetContentRegionAvail().x))
        V.muted('Цена за одну штуку для расчёта этого снимка. 0 = цена API.')
        M.compact_number(V.storage_price_buf,'value','storage_price_value',math.min(250,imgui.GetContentRegionAvail().x),0)
        if b('Сохранить','price_apply',135,false,true)then
            local ok,err=S.set_manual_price(target,row,V.storage_price_buf.value)
            if ok then V.reset_list('storage_items');V.storage_price_target=nil;imgui.CloseCurrentPopup()
            else V.storage_price_error=err end
        end
        V.inline();if b('Отмена','price_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_price_error then V.red(V.storage_price_error)end
    end,{w=460,h=260})
    V.popup('Название снимка','storage_rename',function()
        local target=V.storage_label_target
        if not target then return end
        V.muted('Это имя только для снимка. ID машины автоматически не определяется.')
        imgui.SetNextItemWidth(-1)
        imgui.InputText('##storage_name_input',V.storage_label_buf,128)
        if b('Сохранить','rename_apply',135,false,true)then
            local label=DSP.to_cp(ffi.string(V.storage_label_buf))
            local ok,result=S.set_snapshot_label(target,label)
            if ok then
                V.storage_label_target=nil
                if type(result)=='table' then
                    for i,saved in ipairs(S.snapshots or {})do
                        if saved==result then V.storage_selected=i;break end
                    end
                    V.storage_library_page='detail'
                end
                imgui.CloseCurrentPopup()
            else V.storage_label_error=result end
        end
        V.inline();if b('Отмена','rename_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_label_error then V.red(V.storage_label_error)end
    end,{w=460,h=240})
    V.popup('Удалить хранилище','storage_delete_one',function()
        local target=V.storage_delete_target
        if not target then V.muted('Хранилище уже не выбрано.');return end
        V.text('Удалить «'..tostring(target.title or 'Без названия')..'»?')
        V.muted('Удаляется только запись Palatka AI. Предметы в игре не меняются.')
        if b('УДАЛИТЬ','delete_one_confirm',150,false,true)then
            local ok,err=S.delete_snapshot(target)
            if ok then
                V.storage_delete_target=nil
                V.storage_delete_error=nil
                V.storage_selected=1
                V.storage_library_page='list'
                imgui.CloseCurrentPopup()
            else V.storage_delete_error=tostring(err) end
        end
        V.inline()
        if b('Отмена','delete_one_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_delete_error then V.red(V.storage_delete_error)end
    end,{w=470,h=250})
    V.popup('Очистить снимки?','storage_clear',function()
        V.text('Удалить сохранённые снимки шкафов и багажников?')
        V.muted('Предметы в игре останутся без изменений.')
        if b('Удалить снимки','confirm_clear',170,false,true)then
            local old=S.snapshots
            S.snapshots={};S.last_signature=nil;S.last_snapshot=nil;V.storage_selected=1;V.storage_library_page='list'
            local old_trunk=S.trunk and S.trunk.snapshot
            if S.trunk then S.trunk.snapshot=nil;S.trunk.pending=nil;S.trunk.status='idle';S.trunk.received=0 end
            if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
            if DSP.save_settings and not DSP.save_settings() then
                S.snapshots=old
                if S.trunk then S.trunk.snapshot=old_trunk;S.trunk.status='saved' end
                if DSP.settings then DSP.settings.storage_snapshots=old end
                V.storage_error='Не удалось сохранить удаление';return
            end
            imgui.CloseCurrentPopup()
        end
        V.inline()
        if b('Отмена','cancel_clear',120)then imgui.CloseCurrentPopup()end
    end,{w=480,h=230})
end
