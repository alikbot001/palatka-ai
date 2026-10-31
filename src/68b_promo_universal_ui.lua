-- Native Palatka workspace for universal auto-promo. No MCR UI dependencies.
local ffi=require('ffi')
local V,M,P=DSP.ui22,DSP.mobile,DSP.promo
local function b(s,id,w,on)return V.button(s,'unipromo_'..id,w,on)end
local function save()return DSP.save_settings and DSP.save_settings()~=false end
local function input(id,hint,buffer,length)
    imgui.SetNextItemWidth(-1)
    return imgui.InputTextWithHint('##unipromo_'..id,DSP.utf8(hint),buffer,length)
end
local function fill(buf,value,max)
    local raw=DSP.to_u8(tostring(value or''))
    ffi.fill(buf,max);ffi.copy(buf,raw:sub(1,max-1))
end
local function open_editor(i)
    local row=P.settings().templates[i]
    V.unipromo_edit_index=i
    V.unipromo_name=V.unipromo_name or imgui.new.char[80]()
    V.unipromo_line=V.unipromo_line or imgui.new.char[512]()
    fill(V.unipromo_name,row and row.name or 'Новая строка',80)
    fill(V.unipromo_line,row and row.text or '/fam ',512)
    V.unipromo_interval={value=row and tonumber(row.interval)or 180}
    V.unipromo_error=nil
    V.open_popup('Добавить команду','unipromo_edit')
end
local function pretty(s,w)
    return V.fit(tostring(s or ''),math.max(40,w))
end
function V.promo_screen()
    local settings=P.settings()
    V.heading('Автопиар · Palatka AI',function()
        if P.running then
            if b('ПАУЗА','stop',118,true)then P.stop()end
        else
            if b('ЗАПУСК','start',118,true)then
                local ok,why=P.start()
                V.unipromo_error=ok and nil or tostring(why)
            end
        end
    end,135)
    V.muted('Любая игровая /команда. Строки идут по очереди; отдельная пауза после каждой.')
    V.muted('Не ускоряет серверные ограничения чата. Автовозобновление только при включении.')
    V.text('Статус: '..(P.running and (P.pause_reason or'Запущен')or'Остановлен'))
    V.muted('Отправлено: '..tostring(P.session_count)..(settings.continuous and ' | циклический режим' or ' / 12 за запуск'))
    if P.running and P.next_at and P.next_at>0 then
        V.muted('Следующая отправка через '..tostring(math.max(0,P.next_at-os.time()))..' с')
    end
    if P.last_command then V.muted(pretty('Последняя: '..P.last_command,imgui.GetContentRegionAvail().x))end
    if V.unipromo_error or P.last_error then V.red(pretty(V.unipromo_error or P.last_error,imgui.GetContentRegionAvail().x))end
    if b(settings.continuous and 'Цикл: БЕЗ ЛИМИТА' or 'Цикл: 12 сообщений',
        'continuous',234,settings.continuous)then
        local ok,err=P.set_option('continuous',not settings.continuous)
        if not ok then V.unipromo_error=err end
    end
    V.inline(5)
    if b(settings.resume_on_login and 'При входе: ВКЛ' or 'При входе: ВЫКЛ',
        'resume',230,settings.resume_on_login)then
        local ok,err=P.set_option('resume_on_login',not settings.resume_on_login)
        if not ok then V.unipromo_error=err end
    end
    V.muted('После входа: задержка '..tostring(settings.start_delay)..' с · при отключении отправка на паузе.')
    for i,v in ipairs({10,20,30,60})do
        if b(v..' с','start_delay_'..i,82,settings.start_delay==v)then
            local ok,err=P.set_option('start_delay',v)
            if not ok then V.unipromo_error=err end
        end
        if i<4 then V.inline(5)end
    end
    if b('+ Добавить строку','add',200,true)then open_editor(nil)end
    V.inline(5)
    if b('ОСТАНОВИТЬ','stop2',135,P.running)then P.stop()end
    local rows=settings.templates
    V.muted('Строк: '..#rows..' / '..P.MAX_TEMPLATES..' · интервал 60–3600 с после строки.')
    V.list_rows('unipromo_lines',rows,124,function(it,i)
        V.row('unipromo_row_'..i,124,function(w,x,y)
            V.at(x,y)
            V.text(pretty(tostring(i)..'. '..tostring(it.name or 'Строка'),w-165))
            V.at(x,y+25)
            V.muted(pretty(it.text or'',w-165))
            V.at(x,y+49)
            V.muted('Пауза после: '..tostring(it.interval or 180)..' сек')
            V.at(x,y+73)
            if b(it.auto and 'ВКЛ' or 'ВЫКЛ','line_on_'..i,77,it.auto)then
                it.auto=not it.auto
                if not save()then it.auto=not it.auto;V.unipromo_error='Не удалось сохранить'end
            end
            V.inline(4)
            if b('Вверх','line_up_'..i,71)then P.move(i,-1)end
            V.inline(4)
            if b('Вниз','line_down_'..i,71)then P.move(i,1)end
            V.at(x+w-155,y+10)
            if b('Изменить','line_edit_'..i,150)then open_editor(i)end
            V.at(x+w-155,y+65)
            if b('Удалить','line_del_'..i,150)then
                V.unipromo_delete=i;V.open_popup('Удалить команду','unipromo_delete')
            end
        end)
    end,{footer=function()
        V.muted('Пиар выполняет только указанные тобой команды, с соблюдением заданных пауз.')
    end})
end
local previous_popups=V.popups
function V.popups()
    if previous_popups then previous_popups()end
    V.popup('Добавить команду','unipromo_edit',function()
        V.text('Название строки')
        input('name','Например: Семейный чат',V.unipromo_name,80)
        V.text('Команда с аргументами')
        input('line','Например: /fam Продам ларцы',V.unipromo_line,512)
        V.muted('Можно /f, /fam, /vr, /ad, /family и любую другую /команду игры.')
        V.muted('Если команда открывает меню, оно может мешать игре при каждом цикле.')
        if b('Вставить {shop}','shopmacro',163)then
            local raw=ffi.string(V.unipromo_line)
            local suffix=' {shop}'
            if #raw+#suffix<511 then fill(V.unipromo_line,raw..suffix,512)end
        end
        V.muted('Макрос {shop} вставляет кликабельный номер своей лавки при отправке.')
        V.text('Интервал после этой строки, секунд')
        for _,seconds in ipairs({60,120,180,300,600})do
            if b(tostring(seconds),'interval_'..seconds,69,V.unipromo_interval.value==seconds)then
                V.unipromo_interval.value=seconds
            end
            V.inline(4)
        end
        M.compact_number(V.unipromo_interval,'value','unipromo_interval',180,60)
        if V.unipromo_error then V.red(tostring(V.unipromo_error))end
        if b('Сохранить строку','save',182,true)then
            local name=DSP.to_cp(ffi.string(V.unipromo_name))
            local line=DSP.to_cp(ffi.string(V.unipromo_line))
            local ok,err
            if V.unipromo_edit_index then
                ok,err=P.update(V.unipromo_edit_index,name,line,V.unipromo_interval.value)
            else
                ok,err=P.add(name,line,V.unipromo_interval.value)
            end
            if ok then V.unipromo_error=nil;imgui.CloseCurrentPopup()
            else V.unipromo_error=tostring(err)end
        end
        V.inline(6);V.cancel('unipromo_edit')
    end,{w=680,h=470,resizable=true})
    V.popup('Удалить команду','unipromo_delete',function()
        V.text('Удалить эту строку из расписания?')
        if b('Да, удалить','delete_confirm',174)then
            if P.remove(V.unipromo_delete)then imgui.CloseCurrentPopup()
            else V.unipromo_error='Ошибка сохранения'end
        end
        V.inline(6);V.cancel('unipromo_delete')
    end,{w=470,h=240})
end
return true
