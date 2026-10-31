-- Simplified read-only cabinet / warehouse observer.
-- Personal inventory scan intentionally removed from the UI.
local V = DSP.ui21
local P = DSP.storage_probe
local labels={cabinet='ШКАФ',warehouse='СКЛАД'}
local descriptions={cabinet='шкаф',warehouse='склад'}
local function button(label,id,width,active,primary)
    return V.button(label,'probe_'..id,width,active,primary)
end

function V.storage_probe_panel(width,kind)
    width=math.max(190,tonumber(width) or 300)
    local w=math.min(width,315)
    if not P then V.red('Сканер этого контейнера недоступен.');return end
    if not labels[kind] then V.red('Неизвестный тип хранилища.');return end
    local state=P.state()

    V.apply_font((V.font_pixels or 18)*1.15)
    V.text(labels[kind])
    V.apply_font()

    if state.armed and state.kind~=kind then
        V.red('Сейчас идёт скан другого хранилища.')
        if button('Остановить текущий скан','stop_other',w,false,true)then P.stop()end
        return
    end

    if state.kind~=kind and not state.armed then
        V.muted('Нажми «Начать скан», затем закрой Palatka AI и открой '..descriptions[kind]..' в игре.')
        if button('НАЧАТЬ СКАН','arm_'..kind,w,false,true)then
            P.arm(kind,40)
            V.probe_selected=1
            V.probe_error=nil
        end
        return
    end

    if state.armed then
        V.green('СКАН ЗАПУЩЕН')
        V.muted('Открой '..descriptions[kind]..' в игре. После этого вернись сюда.')
        V.muted('Осталось: '..math.max(0,state.until_ts-os.time())..' сек.')
        if button('ЗАВЕРШИТЬ И ПОКАЗАТЬ','stop',w,false,true)then P.stop()end
        return
    end

    if #state.order==0 then
        V.red('Содержимое не распознано.')
        V.muted('Попробуй запустить скан ещё раз и заново открыть '..descriptions[kind]..'.')
        if button('ПОВТОРИТЬ СКАН','arm_'..kind,w,false,true)then
            P.arm(kind,40);V.probe_selected=1;V.probe_error=nil
        end
        return
    end

    V.probe_selected=math.max(1,math.min(#state.order,V.probe_selected or 1))
    local selected=V.probe_selected
    if #state.order>1 then
        V.muted('Найдено несколько вариантов: '..selected..' / '..#state.order)
        if button('Следующий вариант','next',w)then
            selected=selected%#state.order+1
            V.probe_selected=selected
        end
    end

    local info,err=P.preview(selected)
    if not info then V.red(tostring(err));return end

    V.green('НАЙДЕНО: '..tostring(info.occupied)..' занятых слотов')
    V.text('Подтверждено предметов: '..tostring(info.known))
    if info.unknown_qty>0 then
        V.muted('Без точного количества: '..tostring(info.unknown_qty)..' строк')
    end

    if DSP.storage and DSP.storage.evaluate then
        local estimate=DSP.storage.evaluate({kind=kind,rows=info.rows,
            server=DSP.market and DSP.market.state and DSP.market.state.sid})
        if not estimate.cross_server then
            V.green('Оценка скупки: '..DSP.money(estimate.sell_to_buyers))
            if estimate.missing_prices>0 then
                V.muted('Нет цен для '..estimate.missing_prices..' строк')
            end
        end
    end

    V.red('Пока это предварительный скан: полный формат '..descriptions[kind]..' ещё проверяется.')
    if button('СОХРАНИТЬ РЕЗУЛЬТАТ','save',w,false,true)then
        local ok,saved=P.save(selected)
        if ok then
            V.probe_error=nil
            V.storage_tab='library'
            V.storage_library_page='list'
        else
            V.probe_error=tostring(saved)
        end
    end
    if button('ПОВТОРИТЬ СКАН','arm_'..kind,w)then
        P.arm(kind,40);V.probe_selected=1;V.probe_error=nil
    end
    if V.probe_error then V.red(V.fit(V.probe_error,width))end
end
