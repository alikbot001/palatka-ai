local ffi=require('ffi')
local M=DSP.mobile
local U=DSP.ui
local function date(ts) return os.date('%d.%m.%Y %H:%M:%S',tonumber(ts) or 0) end
M.history_revision={trades=0,stalls=0}
local history_cache={}
function M.history_rows(kind)
    local source=DSP.settings[kind] or {}
    local revision=M.history_revision[kind]
    local cached=history_cache[kind]
    if cached and cached.source==source and cached.revision==revision then return cached.rows end
    local rows={}
    for _,entry in pairs(source) do rows[#rows+1]=entry end
    table.sort(rows,function(a,b) return (a.ts or 0)>(b.ts or 0) end)
    history_cache[kind]={source=source,revision=revision,rows=rows}
    return rows
end
-- Invalidate only when events mutate logs; unchanged frames reuse sorted rows.
for name,kinds in pairs({record_trade={'trades'},stall_dropped={'stalls'},clear_trades={'trades','stalls'},load={'trades','stalls'}}) do
    local original=DSP.logs[name]
    if original then
        DSP.logs[name]=function(...)
            for _,kind in ipairs(kinds) do M.history_revision[kind]=M.history_revision[kind]+1 end
            return original(...)
        end
    end
end
function U.crate_log()
    if not DSP.rewards then M.text('История наград недоступна'); return end
    U.reward_filter=U.reward_filter or {search=''}
    U.reward_search=U.reward_search or imgui.new.char[256]()
    local filter=U.reward_filter
    imgui.SetNextItemWidth(math.min(700,imgui.GetContentRegionAvail().x))
    if imgui.InputTextWithHint('##reward_search',DSP.utf8('Найти предмет или источник'),U.reward_search,256) then
        filter.search=DSP.to_cp(ffi.string(U.reward_search)); DSP.screens.set_page('rewards',1)
    end
    U.reward_source=U.reward_source or imgui.new.char[256]()
    imgui.SetNextItemWidth(math.min(700,imgui.GetContentRegionAvail().x))
    if imgui.InputTextWithHint('##reward_source',DSP.utf8('Источник содержит (например: Vice City)'),U.reward_source,256) then
        filter.source_contains=DSP.to_cp(ffi.string(U.reward_source)); DSP.screens.set_page('rewards',1)
    end
    for _,period in ipairs({{0,'Все даты'},{86400,'24 часа'},{604800,'7 дней'}}) do
        if M.button(period[2],'reward_period'..period[1],260,(U.reward_period or 0)==period[1]) then
            U.reward_period=period[1]
            filter.from_ts=period[1]>0 and os.time()-period[1] or nil
            DSP.screens.set_page('rewards',1)
        end
        if period[1]~=604800 then M.inline() end
    end
    for _,pair in ipairs({{'all','Все'},{'item','Предметы'},{'cash','Деньги'},{'opening','Открытия'}}) do
        if M.button(pair[2],'reward_kind'..pair[1],220,(filter.kind or 'all')==pair[1]) then
            filter.kind=pair[1]~='all' and pair[1] or nil; DSP.screens.set_page('rewards',1)
        end
        if pair[1]~='opening' then M.inline() end
    end
    local summary=DSP.rewards.summary(filter)
    M.text('Открытий: '..tostring(summary.openings)..' | Предметов: '..tostring(summary.items)
        ..' | Деньги: '..DSP.money(summary.cash or 0))
    M.text('Рыночная оценка: '..DSP.money(summary.estimated_value or 0)
        ..' | Без цены: '..tostring(summary.unknown_items)..' записей')
    filter.page=DSP.screens.page_of('rewards'); filter.page_size=10
    local result=DSP.rewards.query(filter)
    local first=DSP.screens.pager(result.total or 0,10,'rewards')
    local current=math.floor((first-1)/10)+1
    if current~=filter.page then filter.page=current; result=DSP.rewards.query(filter) end
    if result.error then M.text('Ошибка истории: '..tostring(result.error)) end
    if (result.corrupt_lines or 0)>0 then M.text('Повреждённых строк: '..result.corrupt_lines) end
    if (result.total or 0)==0 then M.text('Наград пока нет. История пополняется из сообщений игрового чата.') end
    for _,e in ipairs(result.entries or {}) do
        M.title(date(e.ts)..' / '..tostring(e.source or 'Источник неизвестен'))
        if e.kind=='opening' then M.text('Открыт тайник / ларец')
        elseif e.kind=='cash' then M.text('Получено денег: '..DSP.money(e.cash or 0))
        else
            M.text(tostring(e.item_name or '?')..' x'..tostring(e.qty or 1)..((e.ench or 0)>0 and (' (+'..e.ench..')') or ''))
            if e.price_known and not (DSP.rewards and DSP.rewards.is_temporary and DSP.rewards.is_temporary(e)) then
                M.text('Оценка: '..DSP.money(e.estimated_value or 0)..' | За шт.: '..DSP.money(e.unit_price or 0))
                M.text('База: '..tostring(e.price_source or '?')..' | Метка цены: '..(e.price_ts and date(e.price_ts) or 'время неизвестно'))
            else M.text('Цена неизвестна. Оценка не включена в сумму.') end
        end
        if e.association=='inferred' then M.text('Источник определён по соседнему сообщению чата') end
        if e.association=='unknown' then M.text('Источник награды не определён') end
        M.text(e.raw or '')
        imgui.Separator()
    end
end
function U.log_tab()
    M.title('ИСТОРИЯ')
    for _,v in ipairs({{'crates','Награды / тайники'},{'trades','Сделки'},{'chat','Чат'}}) do
        if M.button(v[2],'history_'..v[1],330,U.tab_detail==v[1]) then U.tab_detail=v[1] end
        if v[1]~='chat' then M.inline() end
    end
    imgui.Separator()
    if U.tab_detail=='crates' then U.crate_log()
    elseif U.tab_detail=='chat' then
        local chat=DSP.settings.chat_logs or {}
        local first,last=DSP.screens.pager(#chat,12,'chat_history')
        for i=first,last do
            local e=chat[#chat-i+1]
            M.text(date(e.ts)..' | '..tostring(e.text or '')); imgui.Separator()
        end
    else
        local trades=M.history_rows('trades')
        M.title('СДЕЛКИ / '..#trades)
        local first,last=DSP.screens.pager(#trades,8,'trade_history')
        for i=first,last do
            local e=trades[i]
            M.title(date(e.ts)..' | '..tostring(e.partner or '?'))
            M.text(e.item_summary or '')
            M.text('Получено '..DSP.money(e.total_get or 0)..' | Отдано '..DSP.money(e.total_give or 0)
                ..' | Прибыль '..DSP.money(e.profit or 0)); imgui.Separator()
        end
        local stalls=M.history_rows('stalls')
        M.title('ЛАВКИ / '..#stalls)
        first,last=DSP.screens.pager(#stalls,8,'stall_history')
        for i=first,last do
            local e=stalls[i]
            M.text(date(e.ts)..' | Лавка #'..tostring(e.shop_num or '?')..' '..tostring(e.owner or '')..' '..tostring(e.action or ''))
        end
    end
end
-- v1.4 unified event timeline, with independent event/payday/income filters.
function U.log_tab()
    local C=DSP.craglog
    M.title('ЖУРНАЛ СОБЫТИЙ')
    M.text('Сделки, деньги, открытия и PayDay в одном месте.')
    U.journal_filter=U.journal_filter or 'all'
    local tabs={{'all','Все'},{'loot','Тайники'},{'payday','PayDay'},
                {'sales','Продажи'},{'buys','Скупка'},{'income','Доходы'}}
    for i,pair in ipairs(tabs) do
        if M.button(pair[2],'journal_'..pair[1],190,U.journal_filter==pair[1]) then
            U.journal_filter=pair[1]
            DSP.screens.set_page('journal_events',1)
        end
        if i%3~=0 then M.inline() end
    end
    imgui.Separator()
    if not C then M.text('Журнал ещё не загружен'); return end
    local all=C.filtered('all')
    local since=os.time()-86400
    local sales,buys,paydays,crates,income,profit=0,0,0,0,0,0
    for _,e in ipairs(all) do
        if (tonumber(e.ts) or 0)>=since then
            if e.type=='payday' then paydays=paydays+1
            elseif e.type=='income' then income=income+(tonumber(e.amount) or 0)
            elseif e.kind=='cash' then income=income+(tonumber(e.cash) or 0)
            elseif e.kind=='opening' then crates=crates+1
            elseif e.type=='market' then
                if e.direction=='sell' then sales=sales+1 else buys=buys+1 end
            elseif e.type=='trade' then
                profit=profit+(tonumber(e.profit) or 0)
                if (tonumber(e.money_get) or 0)>0 then sales=sales+1 end
                if (tonumber(e.money_give) or 0)>0 then buys=buys+1 end
            end
        end
    end
    M.text('За 24 ч | Продажи: '..sales..' | Скупки: '..buys..' | Тайники: '..crates..' | PayDay: '..paydays)
    M.text('Торговый итог (оценка): '..DSP.money(profit)..' | Полученные деньги: '..DSP.money(income))
    M.text('Торговый итог может включать рыночную стоимость вещей, а не наличные.')
    imgui.Separator()
    local events=C.filtered(U.journal_filter)
    table.sort(events,function(a,b) return (tonumber(a.ts) or 0)>(tonumber(b.ts) or 0) end)
    local first,last=DSP.screens.pager(#events,7,'journal_events')
    if #events==0 then M.text('Пока нет записей этого типа. Новые события появятся после сообщений сервера.') end
    for i=first,last do
        local e=events[i]
        if e then
            local kind=e.kind or e.type
            local heading=e.type=='payday' and 'PAYDAY' or e.type=='income' and 'ДОХОД'
                or kind=='opening' and 'ТАЙНИК' or kind=='item' and 'ПРЕДМЕТ'
                or kind=='cash' and 'ДЕНЬГИ' or e.type=='market' and (e.direction=='sell' and 'ПРОДАЖА' or 'СКУПКА') or 'СДЕЛКА'
            M.title(date(e.ts)..'    '..heading)
            M.text(C.describe(e))
            if e.source and e.source~='' then M.text('Источник: '..tostring(e.source)) end
            imgui.Separator()
        end
    end
    if M.button('Подробно: тайники и награды','journal_details',430) then
        U.journal_details=not U.journal_details
    end
    if U.journal_details then U.crate_log() end
    if M.button(U.legacy_trade_open and 'Скрыть старые сделки' or 'История старых сделок',
            'journal_legacy',340,U.legacy_trade_open) then
        U.legacy_trade_open=not U.legacy_trade_open
    end
    if M.button(U.journal_chat_open and 'Скрыть сообщения чата' or 'Сообщения чата (диагностика)',
            'journal_raw_chat',400,U.journal_chat_open) then
        U.journal_chat_open=not U.journal_chat_open
    end
    if U.journal_chat_open then
        local chat=DSP.settings.chat_logs or {}
        local first,last=DSP.screens.pager(#chat,12,'chat_history')
        for i=first,last do
            local e=chat[#chat-i+1]
            if e then M.text(date(e.ts)..' | '..tostring(e.text or '')) end
        end
    end
    if U.legacy_trade_open then
        local trades=M.history_rows('trades')
        M.title('СТАРЫЕ СДЕЛКИ / '..#trades)
        local left,right=DSP.screens.pager(#trades,7,'legacy_trade_history')
        for i=left,right do
            local trade=trades[i]
            M.text(date(trade.ts)..' | '..tostring(trade.partner or '?'))
            M.text(trade.item_summary or '')
            M.text('Получено: '..DSP.money(trade.total_get or 0)..'  |  Отдано: '..DSP.money(trade.total_give or 0))
            imgui.Separator()
        end
    end
    if C.last_error then M.text('Ошибка файла журнала: '..tostring(C.last_error)) end
end
local function save_notes()
    local f,err=io.open(DSP.notes_path,'w')
    if not f then DSP.notify('Не удалось сохранить заметки: '..tostring(err)); return false end
    local ok,write_err=f:write(ffi.string(U.notes_buf))
    local closed,close_err=f:close()
    if not ok or not closed then DSP.notify('Ошибка сохранения заметок: '..tostring(write_err or close_err)); return false end
    U._notes_dirty=false
    return true
end
M.save_notes=save_notes
function U.notes_tab()
    M.title('ЗАМЕТКИ')
    M.text(U._notes_dirty and 'Есть несохранённые изменения' or 'Сохранено')
    if M.button('Сохранить заметку','save_notes',340) then save_notes() end
    M.text('Ваш список закупок, планы и цены. Автосохранение после паузы во вводе.')
    local avail=imgui.GetContentRegionAvail()
    if imgui.InputTextMultiline('##mobile_notes',U.notes_buf,8192,imgui.ImVec2(avail.x,math.max(160,avail.y-20)),0) then
        U._notes_dirty=true; U._notes_last_edit=os.clock()
    end
end
-- Save before closing, including when an Android keyboard temporarily changes the viewport.
local set_open=U.set_open
function U.set_open(value)
    if not value and U._notes_dirty and U.notes_buf then M.save_notes() end
    set_open(value)
end
function U.settings_tab()
    M.title('НАСТРОЙКИ')
    U.settings_section=U.settings_section or 'appearance'
    for _,v in ipairs({{'appearance','Вид'},{'trade','Торговля'},{'data','Данные'},{'tools','Инструменты'}}) do
        if M.button(v[2],'settings_'..v[1],270,U.settings_section==v[1]) then U.settings_section=v[1] end
        if v[1]~='tools' then M.inline() end
    end
    imgui.Separator()
    local section=U.settings_section
    if section=='appearance' then
        M.text('Цветовая тема')
        for _,id in ipairs({'ocean_blue','dark_amber','amoled','cyberpunk','purple','emerald'}) do
            local theme=DSP.theme.list[id]
            if M.button(theme.name,'theme_'..id,400,DSP.theme.current==id) then DSP.theme.set(id) end
        end
        M.text('Прозрачность')
        for _,v in ipairs({.8,.9,.97,1}) do
            if M.button(tostring(math.floor(v*100))..'%','opacity'..v,170,math.abs(DSP.theme.opacity-v)<.01) then DSP.theme.set_opacity(v) end
            if v~=1 then M.inline() end
        end
        M.text('Размер текста')
        for _,v in ipairs({1,1.25,1.5}) do
            if M.button(tostring(v),'scale'..v,180,M.scale()==v) then U.d=v; DSP.settings.dpi=v; DSP.save_settings() end
            if v~=1.5 then M.inline() end
        end
        M.toggle('Оценка трейда',DSP.settings,'overlay_trade',true)
        M.toggle('Оценка лавки',DSP.settings,'overlay_shop',true)
        M.toggle('Оверлей поверх окон',DSP.settings,'overlay_top',true)
        if DSP.settings.craglog then
            M.toggle('Показывать мини-журнал',DSP.settings.craglog,'open',false)
            if M.toggle('Закрепить мини-журнал',DSP.settings.craglog,'pinned',false) then
                if DSP.craglog and DSP.craglog.set_pinned then DSP.craglog.set_pinned(DSP.settings.craglog.pinned) end
            end
        end
    elseif section=='trade' then
        M.number('Комиссия в базисных пунктах (100 = 1%)','tax',DSP.settings,'tax_bp',0,300)
        M.number('Маржа скупки (%)','margin',DSP.settings,'margin',0,300)
        M.number('Снижение цены продажи (%)','undercut',DSP.settings,'undercut',0,300)
        M.number('Количество скупки по умолчанию','default_qty',DSP.settings,'auto_buy_qty',1,300)
        M.toggle('Тест выставления без отправки',DSP.settings,'dry_run',true)
        M.text('Проверьте комиссию вашего аккаунта: расчёт арбитража использует это значение.')
    elseif section=='data' then
        M.text('Сервер рынка')
        for _,server in ipairs(DSP.market.servers) do
            if M.button(server.name,'server'..server.id,400,DSP.market.state.sid==server.id) then
                DSP.market.state.sid=server.id; DSP.settings.server=server.id
                U.selected=nil; DSP.save_settings(); DSP.market.pull(server.id)
            end
        end
        M.number('Обновление рынка (сек)','refresh_seconds',DSP.settings,'refresh_seconds',180,300)
        M.toggle('Записывать награды и тайники',DSP.settings,'log_chat_drops',true)
        M.text('Скан рыночной метки ЦР: '..tostring(DSP.market.cr_scan_state.status or 'не сканирован'))
        if DSP.market.cr_scan_state.active then
            if M.button('Остановить скан ЦР','stop_cr',400) then
                DSP.market.cr_scan_state.active=false; DSP.market.cr_scan_state.status='остановлено'
            end
        elseif M.button('Сканировать метку ЦР','scan_cr',450) then DSP.market.scan_cr_marker() end
        M.text('Для скана подойдите к рыночной метке и откройте диалог цен.')
    else
        if M.button('Калькулятор сделки','calculator',430) then U.settings_tool='calculator' end
        M.inline()
        if M.button('Диагностика','diagnostics',360) then U.settings_tool='diagnostics' end
        if U.settings_tool=='calculator' then U.calculator_tab()
        else
            M.text('Версия '..tostring(DSP.version)..' | Данные: '..DSP.dir)
            M.text('Источник рынка: '..tostring(DSP.market.api))
            for i=1,math.min(20,#DSP.log) do M.text((DSP.log[i].t or '')..' '..tostring(DSP.log[i].text)) end
        end
    end
    imgui.Separator()
    if M.button('Сохранить настройки','save_settings',420) then DSP.save_settings(); DSP.save_ui_state(); DSP.notify('Настройки сохранены') end
end
