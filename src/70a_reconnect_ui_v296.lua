-- Palatka AI 2.9.6: touch-friendly reconnect management.
-- Settings button -> dedicated workspace screen; no always-on overlay.
local R,V,M=DSP.reconnect,DSP.ui22,DSP.mobile
if not R or not V or V._reconnect_ui_v296 then return true end
V._reconnect_ui_v296=true
local old_tools=V.tools
local function b(label,id,width,active)
    return V.button(label,'rec296_'..id,width,active,false,39)
end
local function update(key,value)
    local ok,why=R.set(key,value)
    if ok then V.reconnect_error=nil else V.reconnect_error=tostring(why)end
end
local function toggle(key,label)
    local c=R.config()
    if b((c[key]and '[x] 'or'[ ] ')..label,'toggle_'..key,-1,c[key])then
        update(key,not c[key])
    end
end
local function number(key,label,step,unit)
    local c=R.config()
    V.muted(label)
    local x=math.min(80,math.max(44,imgui.GetContentRegionAvail().x/4))
    if b('-','dec_'..key,x)then update(key,c[key]-step)end
    V.inline(4,x)
    V.text(tostring(c[key])..' '..(unit or'с'))
    V.inline(5,x)
    if b('+','inc_'..key,x)then update(key,c[key]+step)end
end
local function header()
    V.heading('Реконнект / Спавн',function()
        if b('Назад','go_back',105)then V.set_screen('settings')end
    end,127)
    local c=R.config()
    V.muted('Сервер: '..tostring(R.server_key()or'не определён'))
    V.muted('Состояние: '..tostring(R.status or'выключен'))
    if V.reconnect_error then V.red(V.reconnect_error)end
    if b('Реконнект сейчас','manual',math.min(220,imgui.GetContentRegionAvail().x))then
        local ok,why=R.manual()
        if not ok then V.reconnect_error=tostring(why)else V.reconnect_error=nil end
    end
    V.inline(5,160)
    if b('Остановить','stop',150)then R.stop('Отменено пользователем')end
end
local function general()
    local c=R.config()
    toggle('enabled','Авто-реконнект (по умолчанию выключен)')
    toggle('on_lost','После потери соединения / тайм-аута')
    toggle('on_closed','После закрытия соединения сервером')
    toggle('on_rejected','После отказа в подключении')
    V.muted('При бане, кике, пароле и капче автоматизация останавливается.')
    V.muted('Если игра полностью закрылась, Lua не сможет запустить её заново.')
    V.muted('Периоды ожидания:')
    number('initial_delay','Первое подключение после обрыва',1)
    number('min_delay','Начальная задержка повторов',2)
    number('max_delay','Максимальная пауза (экспоненциально)',10)
    number('jitter','Случайная добавка к паузе',1)
    number('max_attempts','Ограничение числа попыток',1,'раз')
    number('connect_timeout','Тайм-аут подключения',5)
end
local function spawns()
    local c=R.config()
    toggle('spawn_enabled','Автоматически выбрать сохранённый спавн')
    number('spawn_delay','Пауза до ответа на диалог',1)
    V.muted('Режим точного выбора: только реально обнаруженные пункты SA-MP.')
    V.muted('CEF-окна нельзя безопасно выбирать без подтверждённого API.')
    V.muted('Сначала войди в игру и открой меню выбора спавна.')
    local p=R.profile()
    local selected=p and p.spawn_label or nil
    V.muted('Сохранено для этого сервера: '..tostring(selected or'вручную'))
    if b('Сбросить выбор','clear_spawn',205)then
        local ok,why=R.select_spawn(nil)
        if not ok then V.reconnect_error=tostring(why)else V.reconnect_error=nil end
    end
    local opts=R.options or{}
    if not R.server_key()then
        V.muted('Адрес сервера не определён: сначала подключись в лаунчере.')
        return
    end
    if #opts==0 then
        V.muted('Пункты пока не получены из SA-MP-диалога.')
        return
    end
    V.muted('Пункты из последнего меню спавна:')
    for i,row in ipairs(opts)do
        if b((selected==row.label and'[x] 'or'[ ] ')..
            tostring(row.label),'spawn_'..i,-1,selected==row.label)then
            local ok,why=R.select_spawn(row.label)
            if not ok then V.reconnect_error=tostring(why)else V.reconnect_error=nil end
        end
    end
end
local function diag()
    local c=R.config()
    V.muted('Статус: '..tostring(R.status or'Ожидание'))
    V.muted('Последняя причина: '..tostring(R.last_reason or'—'))
    V.muted('Попытки: '..tostring(R.attempts or 0)..'/'..tostring(c.max_attempts))
    if R.state=='scheduled'then
        V.muted('Следующая попытка через '..math.max(0,(R.next_at or 0)-os.time())..' с')
    end
    V.muted('API подключения: '..(type(sampConnectToServer)=='function'and'обнаружен' or'недоступен'))
    V.muted('SA-MP-диалоги: '..tostring(#(R.options or{}))..' пунктов')
    if R.dialog_id then V.muted('ID последнего меню спавна: '..tostring(R.dialog_id))end
    V.muted('Команды: /prc (вручную), /prc status, /prc stop')
    V.muted('Ник и пароль не хранятся. Авторизацию проходишь в игре.')
    V.muted('При ошибке игры проверь standalone.log и client.log.')
    if b('Обновить адрес текущего сервера','refresh_server',-1)then
        if not R.remember_address()then
            V.reconnect_error='Не удалось получить адрес от клиента'
        else V.reconnect_error=nil end
    end
end
V.reconnect_tab=V.reconnect_tab or 1
function R.draw_ui()
    header()
    local pages={{'Основное',general},{'Спавн',spawns},{'Статус',diag}}
    local w=math.max(62,(imgui.GetContentRegionAvail().x-12)/3)
    for i,page in ipairs(pages)do
        if b(page[1],'page_'..i,w,V.reconnect_tab==i)then
            V.reconnect_tab=i
        end
        if i<3 then V.inline(6,w)end
    end
    V.list('reconnect296',function()
        pages[V.reconnect_tab][2]()
    end,{footer=false})
end
function V.tools(screen)
    if screen=='reconnect'then return R.draw_ui()end
    if screen=='settings'then
        local w=imgui.GetContentRegionAvail().x
        if b('Реконнект / выбор спавна','settings_entry',math.min(300,w))then
            V.set_screen('reconnect')
            return
        end
    end
    if old_tools then return old_tools(screen)end
end
return true
