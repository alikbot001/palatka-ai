-- Contextual controls inside Storage > Scan (native mimgui).
-- The selector lives in 60b_carbon_storage.lua; never capture another kind silently.
local V = DSP.ui21
local P = DSP.storage_probe
local labels={inventory='ИНВЕНТАРЬ',cabinet='ШКАФ',warehouse='СКЛАД'}
local function button(label,id,width,active)
    return V.button(label,'probe_'..id,width,active)
end
function V.storage_probe_panel(width,kind)
    width=math.max(190,tonumber(width) or 300)
    local w=math.min(width,315)
    if not P then V.red('Модуль сканирования не установлен.');return end
    kind=labels[kind] and kind or 'inventory'
    local state=P.state()
    V.text(labels[kind]..' · режим наблюдения')
    if state.armed and state.kind~=kind then
        V.red('Сначала заверши скан другого контейнера.')
        if button('Остановить предыдущий скан','stop_other',w)then P.stop()end
        return
    end
    if state.kind~=kind and not state.armed then
        -- A previous capture must never be presented as the current container.
        V.muted('Это отдельный скан. Нажми «Начать», затем открой выбранный контейнер.')
        if button('Начать скан: '..labels[kind],'arm_'..kind,w,true)then
            P.arm(kind,40);V.probe_selected=1;V.probe_error=nil;V.probe_report_path=nil
        end
        return
    end
    if state.armed then
        V.green('Активен · осталось '..math.max(0,state.until_ts-os.time())..' сек.')
        V.muted('Закрой Palatka AI и открой '..(kind=='inventory' and 'личный инвентарь' or kind=='cabinet' and 'шкаф' or 'склад')..' в игре.')
        if button('Завершить и показать найденное','stop',w,true)then P.stop()end
    else
        V.muted('Скан завершён. Данные ниже предварительные.')
        if button('Повторить скан','arm_'..kind,w)then
            P.arm(kind,40);V.probe_selected=1;V.probe_error=nil;V.probe_report_path=nil
            return
        end
    end
    V.muted('Пакеты: '..tostring(state.observed or 0)..' · кандидаты: '..#state.order)
    V.muted('Пропущено: багажник '..tostring(state.ignored_trunk or 0)..
        ', лавка '..tostring(state.ignored_stall or 0))
    if not state.armed and state.status=='review' then
        if button('Сохранить технический отчёт','export',w)then
            local ok,path=P.export_report()
            if ok then V.probe_report_path=path;V.probe_error=nil
            else V.probe_error=tostring(path)end
        end
        if V.probe_report_path then V.muted(V.fit(V.probe_report_path,width))end
    end
    if #state.order==0 then
        if not state.armed then
            V.red('Подходящих пакетов нет. Инвентарь мог прийти другим форматом.')
        end
        if V.probe_error then V.red(V.fit(V.probe_error,width))end
        return
    end
    V.probe_selected=math.max(1,math.min(#state.order,V.probe_selected or 1))
    local selected=V.probe_selected
    if button('Кандидат '..selected..' / '..#state.order..' →','next',w)then
        selected=selected%#state.order+1;V.probe_selected=selected
    end
    local info,err=P.preview(selected)
    if not info then V.red(tostring(err));return end
    local e=info.entry
    V.text('type='..e.type..', sub='..e.sub..' · слотов получено '..e.count)
    V.muted('Найдено предметных слотов: '..info.occupied)
    V.muted('Подтверждено единиц: '..info.known..' · без числа: '..info.unknown_qty)
    for i=1,math.min(4,#info.rows)do
        local it=info.rows[i]
        V.muted(V.fit(it.name..' · '..(it.qty and tostring(it.qty)..' шт.' or 'количество неизвестно'),width))
    end
    if #info.rows>4 then V.muted('Остальные предметы появятся в списке снимка.')end
    if not state.armed then
        if button('Сохранить как непроверенный снимок','save',w,true)then
            local ok,saved=P.save(selected)
            if ok then
                V.probe_error=nil;V.storage_tab='snapshots';V.storage_selected=1
            else V.probe_error=tostring(saved)end
        end
    end
    V.red(V.fit('Это не полный скан: тип контейнера выбран вручную, ID владельца неизвестен.',width))
    if V.probe_error then V.red(V.fit(V.probe_error,width))end
end
