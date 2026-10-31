-- Market Helper pattern: template title and editable chat commands in one panel.
local ffi=require('ffi')
local V,M,P=DSP.ui22,DSP.mobile,DSP.promo
if V._promo291_installed then return true end
V._promo291_installed=true
local function button(label,id,w,on)return V.button(label,'mhpromo_'..id,w,on)end
local function txt(s)return DSP.utf8(tostring(s or''))end
local function buff(str,n)
    local b=imgui.new.char[n]()
    local raw=DSP.to_u8(tostring(str or''))
    ffi.fill(b,n);ffi.copy(b,raw:sub(1,n-1))
    return b
end
local function open_editor(index)
    local t=P.settings().templates[index]
    local rows={}
    local buffers={}
    for i,r in ipairs(t and t.rows or{})do
        rows[i]={text=r.text,interval=r.interval,auto=r.auto~=false}
        buffers[i]=buff(r.text,512)
    end
    V.mhpromo_edit={index=index,name=buff(t and t.name or'Новый шаблон',96),
        rows=rows,buffers=buffers,enabled=t==nil or t.auto~=false,
        interval_min={value=t and t.interval_min or 0},interval_max={value=t and t.interval_max or 0},
        auto_limit={value=t and t.auto_limit or 0},random_line=t and t.random_line==true or false}
end
local function editor(e)
    V.heading('Пиар / Редактор',function()
        if button('Назад','back',120)then V.mhpromo_edit=nil end
    end,142)
    V.text('Название шаблона')
    imgui.SetNextItemWidth(-1)
    imgui.InputText('##mhpromo_name',e.name,96)
    V.muted('Каждая строка — отдельная игровая команда; отправляются по очереди.')
    V.muted('Как в Market Helper: название, строки и настройки одного шаблона.')
    local rm=nil
    if imgui.BeginChild('##mhpromo_rows',imgui.ImVec2(0,math.max(135,math.min(290,imgui.GetContentRegionAvail().y-225))),true)then
        for i,row in ipairs(e.rows)do
            imgui.PushID(i)
            V.muted('Строка '..i)
            imgui.SetNextItemWidth(-1)
            if imgui.InputTextWithHint('##line',txt('/vr Текст рекламы'),
                e.buffers[i],512)then
                row.text=DSP.to_cp(ffi.string(e.buffers[i]))
            end
            V.muted('Пауза после, секунд')
            M.compact_number(row,'interval','mhpromo_delay_'..i,145,60)
            V.inline(4)
            if button(row.auto~=false and 'ВКЛ' or 'ВЫКЛ','on_'..i,68,row.auto~=false)then
                row.auto=not(row.auto~=false)
            end
            V.inline(4)
            if button('Удалить','rm_'..i,94)then rm=i end
            V.inline(4)
            if button('^','up_'..i,42) and i>1 then
                e.rows[i],e.rows[i-1]=e.rows[i-1],e.rows[i]
                e.buffers[i],e.buffers[i-1]=e.buffers[i-1],e.buffers[i]
            end
            V.inline(4)
            if button('v','down_'..i,42) and i<#e.rows then
                e.rows[i],e.rows[i+1]=e.rows[i+1],e.rows[i]
                e.buffers[i],e.buffers[i+1]=e.buffers[i+1],e.buffers[i]
            end
            imgui.Separator()
            imgui.PopID()
        end
    end
    imgui.EndChild()
    if rm then table.remove(e.rows,rm);table.remove(e.buffers,rm)end
    if button('+ Добавить строку','add',225,true)then
        if #e.rows<24 then
            e.rows[#e.rows+1]={text='/vr ',interval=180,auto=true}
            e.buffers[#e.buffers+1]=buff('/vr ',512)
        else e.error='Не более 24 строк'end
    end
    V.inline(6)
    if button('Вставить лавку','shop',160)then
        local i=#e.rows
        if i>0 then
            local value=ffi.string(e.buffers[i])
            if #value<495 then
                e.buffers[i]=buff(DSP.to_cp(value..' {shop}'),512)
                e.rows[i].text=DSP.to_cp(ffi.string(e.buffers[i]))
            end
        end
    end
    V.muted('Макрос {shop} вставляет кликабельную ссылку на свою лавку.')
    if button(e.random_line and'Случайная строка: ВКЛ' or'Случайная строка: ВЫКЛ',
        'random',235,e.random_line)then e.random_line=not e.random_line end
    V.muted('Интервал повтора: 0 = индивидуальный интервал каждой строки.')
    V.muted('Минимум повтора, сек:')
    M.compact_number(e.interval_min,'value','mhpromo_imin',160,0)
    V.inline(6)
    V.muted('Максимум, сек:')
    M.compact_number(e.interval_max,'value','mhpromo_imax',160,0)
    V.muted('Лимит отправок шаблона: 0 = без лимита')
    M.compact_number(e.auto_limit,'value','mhpromo_limit',170,0)
    if e.error then V.red(e.error)end
    if button('СОХРАНИТЬ ШАБЛОН','save',250,true)then
        local name=DSP.to_cp(ffi.string(e.name)):match('^%s*(.-)%s*$')
        local ok,reason=P.save_template(e.index,name,e.rows,e.enabled)
        if ok then
            local list=P.settings().templates
            local idx=e.index or #list
            local saved,err=P.save_template_options(idx,{
                interval_min=e.interval_min.value,interval_max=e.interval_max.value,
                auto_limit=e.auto_limit.value,random_line=e.random_line})
            if saved then V.mhpromo_edit=nil else e.error=tostring(err)end
        else e.error=tostring(reason)end
    end
    V.inline(4)
    if button('Отмена','cancel',120)then V.mhpromo_edit=nil end
end
function V.promo_screen()
    if V.mhpromo_edit then
        return V.list('mhpromo_editor_scroll',function()editor(V.mhpromo_edit)end,{footer=true})
    end
    local settings=P.settings()
    V.heading('Автопиар · Palatka',function()
        if button('+ Шаблон','new',155,true)then open_editor(nil)end
    end,172)
    if P.running then
        if button('СТОП','stop',127,true)then P.stop()end
    else
        if button('ПУСК','start',127,true)then
            local ok,why=P.start()
            V.mhpromo_error=ok and nil or tostring(why)
        end
    end
    V.inline(5)
    if button(settings.continuous and 'Цикл: ВКЛ' or 'Цикл: ВЫКЛ',
        'loop',152,settings.continuous)then
        P.set_option('continuous',not settings.continuous)
    end
    V.inline(5)
    if button(settings.resume_on_login and'При входе: ВКЛ' or'При входе: ВЫКЛ',
        'resume',191,settings.resume_on_login)then
        P.set_option('resume_on_login',not settings.resume_on_login)
    end
    V.muted('Отправлено: '..tostring(P.session_count)..
        (settings.continuous and' | без лимита' or' / 12')..
        ' | '..(P.running and(P.pause_reason or'работает')or'выключен'))
    if V.mhpromo_error then V.red(V.mhpromo_error)end
    V.muted('Шаблоны со строками /vr, /fam, /gd, /s, /ad и других чатов.')
    V.list_rows('mhpromo_templates',settings.templates,96,function(t,i)
        V.row('mhpromo_t_'..i,96,function(w,x,y)
            V.at(x,y);V.text(V.fit(t.name or'Шаблон',math.max(80,w-155)))
            V.at(x,y+27);V.muted(#(t.rows or{})..' строк')
            V.at(x,y+53)
            if button(t.auto~=false and'Авто: ВКЛ' or'Авто: ВЫКЛ',
                'enable_'..i,132,t.auto~=false)then
                local was=t.auto;t.auto=not(t.auto~=false)
                if DSP.save_settings and DSP.save_settings()==false then t.auto=was end
            end
            V.at(x+w-143,y+4)
            if button('Изменить','edit_'..i,140)then open_editor(i)end
            V.at(x+w-143,y+52)
            if button('Удалить','del_'..i,140)then
                V.mhpromo_del=i;V.open_popup('Удалить шаблон','mhpromo_delete')
            end
        end)
    end)
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    V.popup('Удалить шаблон','mhpromo_delete',function()
        V.text('Удалить шаблон со всеми строками?')
        if button('Да','yes',105)then
            if P.remove(V.mhpromo_del)then imgui.CloseCurrentPopup()end
        end
        V.inline(5);V.cancel('mhpromo_delete')
    end,{w=415,h=225})
end
return true
