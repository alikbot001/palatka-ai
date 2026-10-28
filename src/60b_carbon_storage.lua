-- Safe container analyzer; cannot read bespoke game UIs without a packet parser.
local ffi=require('ffi')
local V,S=DSP.ui21,DSP.storage
V.storage_sort='value'
V.storage_selected=1
local function b(s,id,w,on,primary)return V.button(s,'storage_'..id,w,on,primary)end
-- One task per panel: scanner, snapshots, manual fallback. This avoids the
-- previous giant fixed header which pushed the item list off small screens.
function V.storage_screen()
    V.heading('Хранилища',function()
        if b('Очистить','clear',105)then V.open_popup('Очистить снимки?','storage_clear')end
    end,109)
    local capstate,capcount,caperr=S.textdraw_state()
    V.storage_tab=V.storage_tab or (#S.snapshots>0 and 'snapshots' or 'scan')
    local w=imgui.GetContentRegionAvail().x
    local tabw=math.max(78,(w-12)/3)
    for i,tab in ipairs({{'scan','Скан'}, {'snapshots','Снимки'}, {'manual','Ввод'}})do
        if b(tab[2],'tab_'..tab[1],tabw,V.storage_tab==tab[1],V.storage_tab==tab[1])then
            V.storage_tab=tab[1];V.reset_list('storage_scan_panel')
        end
        if i<3 then V.inline(5)end
    end
    imgui.Separator()
    if V.storage_tab=='scan' then
        V.list('storage_scan_panel',function(width)
            V.text('Диагностика игрового хранилища')
            V.muted('Поддерживаются SA-MP Dialog и TextDraw. Нативный UI может быть недоступен.')
            V.muted('1. Закройте багажник / шкаф / склад в игре.')
            V.muted('2. Включите сбор и откройте нужное игровое окно.')
            V.muted('3. Закройте игровое окно и завершите сбор.')
            if b(capstate=='armed' and 'Сбор активен (35 с)' or 'Начать сбор (35 с)', 'td_arm',math.min(width,240),capstate=='armed',capstate~='armed')then
                S.arm_textdraw(35);V.storage_error=nil
            end
            if capstate=='armed' or capstate=='expired' then
                if b('Завершить и разобрать','td_finish',math.min(width,240),false,true)then
                    local ok,err=S.finish_textdraw()
                    if ok then V.storage_selected=1;V.storage_tab='snapshots';V.storage_error=nil
                    else V.storage_error=err end
                end
            end
            local T=S.td_session or {}
            V.muted('Событий: '..tostring(T.events or 0)..' · строк текста: '..tostring(capcount)..' · уникальных: '..tostring(T.unique or 0))
            V.muted('Состояние: '..tostring(capstate))
            if caperr or V.storage_error then V.red(V.fit(tostring(V.storage_error or caperr),width))end
            V.muted('0 событий: возможен нативный интерфейс, не TextDraw.')
            V.muted('Текстовые ID сами по себе не доказывают количество предметов.')
            if b('Ручной ввод списка','go_manual',math.min(width,220))then V.storage_tab='manual'end
        end,{footer=function()V.muted('Скан только читает. Никаких игровых перемещений.')end})
        return
    end
    if V.storage_tab=='manual' then
        V.list('storage_manual_panel',function(width)
            V.muted('Если игровой интерфейс не выдаёт содержимое через события,')
            V.muted('можно вставить список вручную — это не игровой скан.')
            V.storage_manual_kind=V.storage_manual_kind or 'trunk'
            local bw=math.max(72,(width-12)/3)
            for i,t in ipairs({{'trunk','Багажник'},{'cabinet','Шкаф'},{'warehouse','Склад'}})do
                if b(t[2],'manual_'..t[1],bw,V.storage_manual_kind==t[1])then V.storage_manual_kind=t[1]end
                if i<3 then V.inline(5)end
            end
            V.storage_input=V.storage_input or imgui.new.char[8192]()
            V.muted('Формат: Дрова x45000  или  Дрова (45000 шт.)')
            imgui.InputTextMultiline('##storage_text',V.storage_input,8192,imgui.ImVec2(-1,100))
            if b('Сохранить снимок','manual_accept',math.min(width,220),false,true)then
                local kind=V.storage_manual_kind
                local title=kind=='trunk'and'Багажник (ручной список)' or kind=='cabinet'and'Шкаф (ручной список)' or 'Склад (ручной список)'
                local ok,err=S.accept(kind,title,DSP.to_cp(ffi.string(V.storage_input)),nil,'manual')
                if ok then V.storage_tab='snapshots';V.storage_selected=1;V.storage_error=nil
                else V.storage_error=err end
            end
            if V.storage_error then V.red(tostring(V.storage_error))end
        end,{footer=false})
        return
    end
    local snapshots=S.snapshots
    if #snapshots==0 then
        V.muted('Снимков нет: обычный игровой диалог пока не распознан.')
        if b('Открыть диагностику','scan_open',220,false,true)then V.storage_tab='scan'end
        return
    end
    V.storage_selected=math.max(1,math.min(#snapshots,V.storage_selected or 1))
    local current=snapshots[V.storage_selected]
    local controlw=math.max(90,(imgui.GetContentRegionAvail().x-8)/2)
    if b('Снимок '..V.storage_selected..' / '..#snapshots,'next',controlw)then
        V.storage_selected=V.storage_selected%#snapshots+1;V.reset_list('storage_items')
    end
    V.inline(7)
    if b(V.storage_sort=='value'and'Оценка'or V.storage_sort=='qty'and'Количество'
        or V.storage_sort=='price'and'Цена'or V.storage_sort=='category'and'Категории' or 'А–Я',
        'sort',controlw)then
        V.storage_sort=V.storage_sort=='value'and'qty'or V.storage_sort=='qty'and'price'
            or V.storage_sort=='price'and'category'or V.storage_sort=='category'and'name'or'value'
        V.reset_list('storage_items')
    end
    local rows,info=S.sorted(current,V.storage_sort)
    V.muted(V.fit(current.title..' · '..os.date('%d.%m %H:%M',current.observed_at)..
        (current.source=='manual'and' · вручную' or current.source=='textdraw'and' · TextDraw' or' · Dialog'),imgui.GetContentRegionAvail().x))
    V.text('Подтверждено: '..info.total_qty..' шт. · неизвестно: '..info.unknown_qty..' строк')
    V.green('Оценка скупки: '..DSP.money(info.sell_to_buyers))
    V.muted('Не прибыль · продажа по объявлениям: '..DSP.money(info.ask_value))
    if info.cross_server then V.red('Другой сервер: цены скрыты')end
    V.list_rows('storage_items',rows,84,function(it,i)
        V.row('storage_item_'..i,84,function(ww,x,y)
            V.at(x,y);V.text(V.fit(it.name,ww-10))
            V.at(x,y+27);V.muted('Количество: '..(it.qty and tostring(it.qty)..' шт.'or'неизвестно'))
            V.at(x,y+53)
            local total=(it.bid and it.qty)and DSP.money(it.bid*it.qty)or'нет оценки'
            V.muted(V.fit('Скупают: '..(it.bid and DSP.money(it.bid)or'?')..' / шт. · '..total,ww-10))
        end)
    end,{footer=function()V.muted('Только сортировка Palatka AI, не предметов игры.')end})
end

-- Deletion is a real modal confirmation; cancellation never changes snapshots.
local old_popups=V.popups
function V.popups()
    if old_popups then old_popups()end
    V.popup('Очистить снимки?','storage_clear',function()
        V.text('Удалить сохранённые снимки шкафов и багажников?')
        V.muted('Предметы в игре останутся без изменений.')
        if b('Удалить снимки','confirm_clear',170,false,true)then
            local old=S.snapshots
            S.snapshots={};S.last_signature=nil;S.last_snapshot=nil;V.storage_selected=1
            if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
            if DSP.save_settings and not DSP.save_settings() then
                S.snapshots=old
                if DSP.settings then DSP.settings.storage_snapshots=old end
                V.storage_error='Не удалось сохранить удаление';return
            end
            imgui.CloseCurrentPopup()
        end
        V.inline()
        if b('Отмена','cancel_clear',120)then imgui.CloseCurrentPopup()end
    end,{w=480,h=230})
end
