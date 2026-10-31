-- Opt-in storage packet diagnostics inside the existing native mimgui screen.
-- No WebView or duplicated game event subscriptions.
local V = DSP.ui21
local P = DSP.storage_probe
local function button(label,id,width,active)
    return V.button(label,'probe_'..id,width,active)
end
function V.storage_probe_panel(width)
    if not P then return end
    width=math.max(190,tonumber(width) or 300)
    local w=math.min(width,290)
    local state=P.state()
    imgui.Separator()
    V.text('ПОИСК ИНВЕНТАРЯ И КОНТЕЙНЕРОВ')
    V.muted(V.fit('Режим наблюдения: только входящие пакеты. Никаких кликов и перемещений.',width))
    V.muted('Выбери тип, запусти сбор, закрой окно Palatka и открой контейнер в игре.')
    if not state.armed then
        if button('Наблюдать: личный инвентарь','arm_inventory',w) then P.arm('inventory',40);V.probe_selected=1 end
        if button('Наблюдать: шкаф','arm_cabinet',w) then P.arm('cabinet',40);V.probe_selected=1 end
        if button('Наблюдать: склад','arm_warehouse',w) then P.arm('warehouse',40);V.probe_selected=1 end
    else
        V.green('Сбор включён: '..math.max(0,state.until_ts-os.time())..' сек. Осталось')
        if button('Закончить сбор и проверить','stop',w) then P.stop() end
    end
    V.muted('Кандидатов: '..#state.order..' · пакетов: '..state.observed..' · багажник исключён: '..state.ignored_trunk..' · лавка исключена: '..(state.ignored_stall or 0))
    if not state.armed and state.status=='review' then
        if button('Создать безопасный отчёт','export',w) then
            local ok,path=P.export_report()
            if ok then V.probe_report_path=path;V.probe_error=nil
            else V.probe_error=tostring(path) end
        end
        if V.probe_report_path then
            V.muted(V.fit('Отчёт: '..V.probe_report_path,width))
        end
    end
    if #state.order==0 then
        V.muted('Нет подходящих данных. Нативный экран мог использовать другой формат.')
        return
    end
    V.probe_selected=math.max(1,math.min(#state.order,V.probe_selected or 1))
    local selected=V.probe_selected
    if button('Кандидат '..selected..' / '..#state.order..' (следующий)','next',w)then
        selected=selected%#state.order+1;V.probe_selected=selected
    end
    local info=P.preview(selected)
    if not info then return end
    local e=info.entry
    V.text('Пакет: тип '..e.type..', канал '..e.sub..' · слотов замечено: '..e.count)
    V.muted('Предметов: '..info.occupied..' · количество известно: '..info.known)
    V.muted('Неизвестных количеств: '..info.unknown_qty..' · полнота НЕ подтверждена')
    for i=1,math.min(4,#info.rows)do
        local it=info.rows[i]
        V.muted(V.fit(it.name..' · '..(it.qty and tostring(it.qty)..' шт.' or 'количество неизвестно'),width))
    end
    if #info.rows>4 then V.muted('Другие предметы будут в сохранённом наблюдении.') end
    if not state.armed then
        if button('Сохранить непроверенное наблюдение','save',w)then
            local ok,err=P.save(selected)
            if ok then
                V.probe_error=nil;V.storage_tab='snapshots';V.storage_selected=1
            else V.probe_error=tostring(err)end
        end
    end
    V.red(V.fit('Важно: тип контейнера указан вручную. Полный состав и ID владельца не подтверждены.',width))
    if V.probe_error then V.red(V.fit(V.probe_error,width))end
end
