-- Safe container analyzer; cannot read bespoke game UIs without a packet parser.
local ffi=require('ffi')
local V,S=DSP.ui21,DSP.storage
V.storage_sort='value'
V.storage_selected=1
local function b(s,id,w,on,primary)return V.button(s,'storage_'..id,w,on,primary)end
function V.storage_screen()
    V.heading('Хранилища',function()
        if b('Очистить','clear',105)then V.open_popup('Очистить снимки?','storage_clear')end
    end,109)
    V.muted('Багажник · шкаф · склад | пассивное чтение, без действий с вещами')
    local capstate,capcount,caperr=S.textdraw_state()
    if b(capstate=='armed' and 'Сбор TextDraw активен' or 'Начать сбор интерфейса','td_arm',250,capstate=='armed')then
        S.arm_textdraw(35)
    end
    if capstate=='armed' or capstate=='expired' then
        V.inline()
        if b('Завершить и разобрать','td_finish',230,false,true)then
            local ok,err=S.finish_textdraw()
            if ok then V.storage_selected=1;V.storage_error=nil else V.storage_error=err end
        end
    end
    V.muted('Сначала запустите сбор, откройте багажник в игре, закройте его, затем завершите сбор.')
    V.muted('TextDraw-событий: '..tostring(capcount)..' · состояние: '..tostring(capstate))
    if caperr then V.red(V.fit(tostring(caperr),imgui.GetContentRegionAvail().x))end
    V.muted('Если событий 0 — окно может быть нативным; нужен лог интерфейса MonetLoader.')
    if b(V.storage_manual and 'Скрыть ввод' or 'Вставить список','manual_toggle',190)then
        V.storage_manual=not V.storage_manual
    end
    if V.storage_manual then
        V.storage_manual_kind=V.storage_manual_kind or 'trunk'
        if b('Багажник','manual_trunk',110,V.storage_manual_kind=='trunk')then V.storage_manual_kind='trunk'end
        V.inline();if b('Шкаф','manual_cabinet',100,V.storage_manual_kind=='cabinet')then V.storage_manual_kind='cabinet'end
        V.inline();if b('Склад','manual_warehouse',100,V.storage_manual_kind=='warehouse')then V.storage_manual_kind='warehouse'end
        V.storage_input=V.storage_input or imgui.new.char[8192]()
        V.muted('По строке на предмет: Дрова x45000 / Дрова (45000 шт.)')
        imgui.InputTextMultiline('##storage_text',V.storage_input,8192,imgui.ImVec2(-1,100))
        if b('Разобрать список','manual_accept',180,false,true)then
            local kind=V.storage_manual_kind
            local title=kind=='trunk'and'Багажник (ручной список)' or kind=='cabinet'and'Шкаф (ручной список)' or 'Склад (ручной список)'
            local ok,err=S.accept(kind,title,DSP.to_cp(ffi.string(V.storage_input)),nil,'manual')
            if ok then V.storage_manual=false;V.storage_selected=1
            else V.storage_error=err end
        end
        if V.storage_error then V.red(tostring(V.storage_error))end
    end
    local snapshots=S.snapshots
    if #snapshots==0 then
        V.text('Снимков пока нет. Откройте шкаф или багажник в игре.')
        V.muted('Автоматически читаются только классические текстовые диалоги SA-MP.')
        V.muted('Кастомный UI может не отдавать данные — тогда нужен игровой дамп.')
    else
        V.storage_selected=math.max(1,math.min(#snapshots,V.storage_selected or 1))
        local current=snapshots[V.storage_selected]
        if b('Снимок '..V.storage_selected..' / '..#snapshots,'next',170)then
            V.storage_selected=V.storage_selected%#snapshots+1;V.reset_list('storage_items')
        end
        V.inline()
        if b(V.storage_sort=='value'and'Сорт.: оценка' or V.storage_sort=='qty'and'Сорт.: количество'
            or V.storage_sort=='price'and'Сорт.: цена' or V.storage_sort=='category'and'Сорт.: категории' or'Сорт.: название','sort',220)then
            V.storage_sort=V.storage_sort=='value'and'qty'or V.storage_sort=='qty'and'price'
                or V.storage_sort=='price'and'category'or V.storage_sort=='category'and'name'or'value';V.reset_list('storage_items')
        end
        local rows,info=S.sorted(current,V.storage_sort)
        V.muted(V.fit(current.title..' · '..os.date('%d.%m %H:%M',current.observed_at)..
            (current.source=='manual' and ' · ручной ввод' or current.source=='textdraw' and ' · TextDraw' or ' · игровой диалог'),imgui.GetContentRegionAvail().x))
        V.text('Подтверждено: '..info.total_qty..' шт. · неизвестное количество: '..info.unknown_qty..' строк')
        V.green('Оценка по скупке: '..DSP.money(info.sell_to_buyers))
        V.muted('Прибыль: неизвестна (нет подтверждённой себестоимости)')
        V.muted('По объявлениям продажи: '..DSP.money(info.ask_value)..' · без цены: '..info.missing_prices)
        if info.cross_server then V.red('Другой сервер: оценки цен отключены')end
        V.muted('Это не прибыль и не гарантированный доход. Котировки могут устареть.')
        V.list_rows('storage_items',rows,88,function(it,i)
            V.row('storage_item_'..i,88,function(w,x,y)
                V.at(x,y);V.text(V.fit(it.name,w-10))
                V.at(x,y+28);V.muted('Остаток: '..(it.qty and tostring(it.qty)..' шт.' or 'неизвестен'))
                V.at(x,y+55)
                local total=(it.bid and it.qty)and DSP.money(it.bid*it.qty)or'нет оценки'
                V.muted(V.fit('Скупают: '..(it.bid and DSP.money(it.bid)or'?')..' / шт. · '..total,w-10))
            end)
        end,{footer=function()V.muted('Сортировка не перемещает игровые предметы.')end})
    end
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
