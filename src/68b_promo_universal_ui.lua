-- Native Palatka promo: template = name + multiple individually timed commands.
local ffi=require('ffi')
local V,M,P=DSP.ui22,DSP.mobile,DSP.promo
local function b(s,id,w,on)return V.button(s,'unipromo_'..id,w,on)end
local function fit(s,w)return V.fit(tostring(s or''),math.max(60,w))end
local function fill(buf,value,max)
    local raw=DSP.to_u8(tostring(value or''))
    ffi.fill(buf,max);ffi.copy(buf,raw:sub(1,max-1))
end
local function input(id,hint,buffer,length)
    imgui.SetNextItemWidth(-1)
    return imgui.InputTextWithHint('##unipromo_'..id,DSP.utf8(hint),buffer,length)
end
local function save()
    if DSP.save_settings then return DSP.save_settings()~=false end
    return false
end
local function begin_template(index)
    local t=P.settings().templates[index]
    V.unipromo_editor=true;V.unipromo_edit_index=index
    V.unipromo_name=V.unipromo_name or imgui.new.char[128]()
    fill(V.unipromo_name,t and t.name or'',128)
    local rows={}
    for _,v in ipairs(t and t.rows or{})do
        rows[#rows+1]={text=v.text,interval=v.interval,auto=v.auto~=false}
    end
    V.unipromo_draft={rows=rows,auto=t and t.auto~=false or true}
    V.unipromo_error=nil
end
local function begin_line(index)
    V.unipromo_line_index=index
    V.unipromo_line=V.unipromo_line or imgui.new.char[512]()
    local row=V.unipromo_draft.rows[index]
    fill(V.unipromo_line,row and row.text or'/vr ',512)
    V.unipromo_line_interval={value=row and row.interval or 180}
    V.unipromo_line_enabled=row and row.auto~=false or true
    V.unipromo_line_error=nil
    V.open_popup('Строка рекламы','unipromo_line')
end
local function summary(settings)
    if P.running then
        if b('ОСТАНОВИТЬ','stop',170,true)then P.stop()end
    else
        if b('ЗАПУСТИТЬ','start',170,true)then
            local ok,err=P.start()
            V.unipromo_error=ok and nil or tostring(err)
        end
    end
    V.inline(5)
    if b(settings.continuous and'Цикл: БЕЗ ЛИМИТА' or'Цикл: 12 сообщений',
        'continuous',216,settings.continuous)then
        local ok,err=P.set_option('continuous',not settings.continuous)
        if not ok then V.unipromo_error=err end
    end
    if b(settings.resume_on_login and'После входа: ВКЛ' or'После входа: ВЫКЛ',
        'resume',216,settings.resume_on_login)then
        local ok,err=P.set_option('resume_on_login',not settings.resume_on_login)
        if not ok then V.unipromo_error=err end
    end
    V.inline(5)
    V.muted('Задержка перед стартом: '..tostring(settings.start_delay)..' сек.')
    for i,n in ipairs({10,20,30,60})do
        if b(n..'с','startup_'..i,62,settings.start_delay==n)then
            local ok,err=P.set_option('start_delay',n)
            if not ok then V.unipromo_error=err end
        end
        if i<4 then V.inline(4)end
    end
    V.muted('Статус: '..(P.running and(P.pause_reason or'работает')or'остановлен'))
    V.muted('Сообщений: '..tostring(P.session_count)..
        (settings.continuous and' | без лимита' or' / 12')..
        '  ·  следующий шаг через '..math.max(0,(P.next_at or 0)-os.time())..'с')
end
local function template_editor()
    local draft=V.unipromo_draft
    V.heading(V.unipromo_edit_index and'Редактирование шаблона' or'Создание шаблона',function()
        if b('Назад','back',112)then V.unipromo_editor=false end
    end,135)
    V.text('Название шаблона')
    input('template_name','Например: Реклама ЦР',V.unipromo_name,128)
    V.muted('Добавь отдельную строку на каждый игровой чат или команду.')
    if b('+ Добавить строку','add_line',205,true)then begin_line(nil)end
    V.inline(6)
    if b('Сохранить шаблон','save_template',205,true)then
        local name=DSP.to_cp(ffi.string(V.unipromo_name)):match('^%s*(.-)%s*$')
        local ok,why=P.save_template(V.unipromo_edit_index,name,draft.rows,draft.auto)
        if ok then V.unipromo_editor=false;V.unipromo_error=nil
        else V.unipromo_error=tostring(why)end
    end
    if V.unipromo_error then V.red(V.unipromo_error)end
    if #draft.rows==0 then
        V.muted('В шаблоне пока нет строк. Нажми «Добавить строку».')
    else
        V.muted('В шаблоне '..#draft.rows..' строк. Отправка по очереди с разными интервалами.')
    end
    V.list_rows('unipromo_template_lines',draft.rows,112,function(row,i)
        V.row('unipromo_step_'..i,112,function(w,x,y)
            V.at(x,y)
            V.text(fit(i..'. '..(row.text or''),w-170))
            V.at(x,y+29)
            V.muted('Интервал после: '..tostring(row.interval or 180)..' сек.')
            V.at(x,y+61)
            if b(row.auto~=false and'ВКЛ' or'ВЫКЛ','row_toggle_'..i,67,row.auto~=false)then
                row.auto=not(row.auto~=false)
            end
            V.inline(4)
            if b('Вверх','row_up_'..i,69)and i>1 then
                draft.rows[i],draft.rows[i-1]=draft.rows[i-1],draft.rows[i]
            end
            V.inline(4)
            if b('Вниз','row_down_'..i,69)and i<#draft.rows then
                draft.rows[i],draft.rows[i+1]=draft.rows[i+1],draft.rows[i]
            end
            V.at(x+w-150,y+6)
            if b('Изменить','row_edit_'..i,146)then begin_line(i)end
            V.at(x+w-150,y+60)
            if b('Удалить','row_remove_'..i,146)then
                table.remove(draft.rows,i)
            end
        end)
    end,{footer=function()
        V.muted('Пример: /vr Продам товары · /fam Продам товары · /gd Продам товары')
    end})
end
function V.promo_screen()
    local settings=P.settings()
    if V.unipromo_editor then return template_editor()end
    V.heading('Автопиар · Palatka AI',function()
        if b('+ Создать шаблон','new_template',195,true)then begin_template(nil)end
    end,211)
    V.muted('Один шаблон содержит несколько строк рекламы для разных чатов.')
    summary(settings)
    if V.unipromo_error then V.red(V.unipromo_error)end
    V.muted('Шаблоны: '..#settings.templates..' / '..P.MAX_TEMPLATES)
    V.list_rows('unipromo_templates',settings.templates,119,function(t,i)
        V.row('unipromo_template_'..i,119,function(w,x,y)
            local count=#(t.rows or{})
            V.at(x,y)
            V.text(fit(t.name or'Без названия',w-162))
            V.at(x,y+28)
            V.muted('Строк: '..count..' · '..(t.auto~=false and'активен' or'выключен'))
            if count>0 then
                V.at(x,y+53)
                V.muted(fit((t.rows[1]or{}).text or'',w-170))
            end
            V.at(x,y+81)
            if b(t.auto~=false and'ВКЛ' or'ВЫКЛ','template_toggle_'..i,79,t.auto~=false)then
                t.auto=not(t.auto~=false)
                if not save()then t.auto=not(t.auto~=false)end
            end
            V.inline(5)
            if b('Удалить','template_remove_'..i,91)then
                V.unipromo_delete=i;V.open_popup('Удалить шаблон','unipromo_delete')
            end
            V.at(x+w-150,y+10)
            if b('Настроить','template_edit_'..i,146,true)then begin_template(i)end
        end)
    end,{footer=function()
        V.muted('Бесконечный цикл и автовозобновление включаются только вручную.')
    end})
end
local old_popups=V.popups
function V.popups()
    if old_popups then old_popups()end
    V.popup('Строка рекламы','unipromo_line',function()
        V.text('Команда / сообщение в одну строку')
        input('line_command','/vr Продам товары на ЦР',V.unipromo_line,512)
        V.muted('Например: /vr ..., /fam ..., /gd ..., /f ..., /ad ...')
        V.text('Интервал после этой строки, секунд')
        for i,n in ipairs({60,120,180,300,600})do
            if b(n..'с','interval_'..i,61,V.unipromo_line_interval.value==n)then
                V.unipromo_line_interval.value=n
            end
            if i<5 then V.inline(5)end
        end
        M.compact_number(V.unipromo_line_interval,'value','unipromo_line_interval',190,60)
        if V.unipromo_line_error then V.red(V.unipromo_line_error)end
        if b('Добавить / сохранить','line_save',225,true)then
            local command=DSP.to_cp(ffi.string(V.unipromo_line)):match('^%s*(.-)%s*$')
            local ok,err=P.validate(command)
            if ok and #P.lines(command)==1 then
                local row={text=command,interval=math.max(60,math.min(3600,
                    math.floor(tonumber(V.unipromo_line_interval.value)or 180))),
                    auto=V.unipromo_line_enabled~=false}
                if V.unipromo_line_index then
                    V.unipromo_draft.rows[V.unipromo_line_index]=row
                else
                    V.unipromo_draft.rows[#V.unipromo_draft.rows+1]=row
                end
                V.unipromo_line_error=nil
                imgui.CloseCurrentPopup()
            else
                V.unipromo_line_error=err or'Одна команда на строку'
            end
        end
        V.inline(6);V.cancel('unipromo_line')
    end,{w=660,h=400,resizable=true})
    V.popup('Удалить шаблон','unipromo_delete',function()
        V.text('Удалить шаблон целиком вместе со строками?')
        if b('Да, удалить','remove_template',160)then
            local ok=P.remove(V.unipromo_delete)
            if ok then imgui.CloseCurrentPopup()else V.unipromo_error='Ошибка сохранения'end
        end
        V.inline(6);V.cancel('unipromo_delete')
    end,{w=460,h=250})
end
return true
