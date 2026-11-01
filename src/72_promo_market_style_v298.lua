-- Palatka AI v2.9.8: compact Market Helper-style promotion screen.
-- Fresh implementation using Palatka models and native mobile mimgui.
-- Existing templates and per-template options are preserved.
local V,M,P=DSP.ui22,DSP.mobile,DSP.promo
if not (V and M and P) then return true end
if V._promo_mobile_298 then return true end
V._promo_mobile_298=true
local ffi=require('ffi')
local function b(label,id,width,active)
    return V.button(label,'pm298_'..id,width,active,false,39)
end
local function str(v)return DSP.to_u8(tostring(v or''))end
local function buffer(value,size)
    local buf=imgui.new.char[size]()
    local text=DSP.to_u8(tostring(value or''))
    ffi.fill(buf,size)
    ffi.copy(buf,text:sub(1,size-1))
    return buf
end
local function save()
    if DSP.save_settings then return DSP.save_settings()~=false end
    return true
end
local function toggle_auto(i)
    local t=P.settings().templates[i]
    if not t then return end
    local old=t.auto
    t.auto=(t.auto==false)
    t.auto_count=0;t._promo_due=nil
    if not save()then t.auto=old;V.promo298_error='Ошибка сохранения';return end
    if t.auto then
        -- In MH an auto_limit=0 means unrestricted template cycles. Preserve
        -- per-template limits and server pacing, not an unrelated 12-chat cap.
        local opts=P.settings()
        if not opts.continuous then
            local ok,why=P.set_option('continuous',true)
            if not ok then V.promo298_error=tostring(why);return end
        end
        if not P.running then
            local ok,why=P.start()
            if not ok then V.promo298_error=tostring(why)end
        end
    else
        local any=false
        for _,v in ipairs(P.settings().templates)do
            if v.auto~=false then any=true;break end
        end
        if not any and P.running then P.stop()end
    end
end
local function new_editor(index)
    local t=index and P.settings().templates[index] or nil
    local edit={index=index,name=buffer(t and t.name or'Новый шаблон',96),
        rows={},linebuf={},waiting=imgui.new.float(tonumber(t and t.waiting)or 1.5),
        min=imgui.new.int(tonumber(t and t.interval_min)or 300),
        max=imgui.new.int(tonumber(t and t.interval_max)or 0),
        limit=imgui.new.int(tonumber(t and t.auto_limit)or 0),
        random=t and t.random_line==true or false,
        auto=t and t.auto~=false or false}
    if t then
        for _,r in ipairs(t.rows or{})do
            edit.rows[#edit.rows+1]={text=r.text or'',auto=r.auto~=false,interval=r.interval or 300}
        end
    else
        edit.rows[1]={text='/s ',auto=true,interval=300}
    end
    for i,r in ipairs(edit.rows)do edit.linebuf[i]=buffer(r.text,512)end
    V.promo298_edit=edit
end
local function modify_number(label,ptr,id,lo,hi,step)
    V.muted(label..': '..tostring(ptr[0])..(id=='wait' and' с' or''))
    if b('-','minus_'..id,66)then ptr[0]=math.max(lo,ptr[0]-step)end
    V.inline(4,66)
    if b('+','plus_'..id,66)then ptr[0]=math.min(hi,ptr[0]+step)end
    ptr[0]=math.max(lo,math.min(hi,ptr[0]))
end
local function editor(e)
    V.heading('Автопиар / Редактор',function()
        if b('Назад','back',100)then V.promo298_edit=nil end
    end,110)
    if e.error then V.red(e.error)end
    if b('Сохранить шаблон','save_editor',224,true)then
        local name=DSP.to_cp(ffi.string(e.name)):match('^%s*(.-)%s*$')
        for i,r in ipairs(e.rows)do r.text=DSP.to_cp(ffi.string(e.linebuf[i]))end
        local ok,index=P.save_template(e.index,name,e.rows,e.auto)
        if ok then
            local more,why=P.save_template_options(index,{
                interval_min=e.min[0],interval_max=e.max[0],
                waiting=e.waiting[0],auto_limit=e.limit[0],random_line=e.random})
            if more then V.promo298_edit=nil;V.promo298_error=nil
            else e.error=tostring(why)end
        else e.error=tostring(index)end
    end
    V.list('pm298_editor',function()
        V.text('Название')
        imgui.SetNextItemWidth(-1)
        imgui.InputText('##pm298_title',e.name,96)
        V.muted('Каждая строка — отдельная команда. Не более 24 строк.')
        local remove
        for i,r in ipairs(e.rows)do
            V.text('Строка '..i)
            imgui.SetNextItemWidth(-1)
            imgui.InputText('##pm298_line_'..i,e.linebuf[i],512)
            if b(r.auto and'Строка ВКЛ' or'Строка ВЫКЛ','line_toggle_'..i,145,r.auto)then
                r.auto=not r.auto
            end
            V.inline(5,92)
            if b('Удалить','line_remove_'..i,92)then remove=i end
            imgui.Separator()
        end
        if remove and #e.rows>1 then
            table.remove(e.rows,remove);table.remove(e.linebuf,remove)
        end
        if b('+ Строка','line_add',165,true)then
            if #e.rows<24 then
                e.rows[#e.rows+1]={text='/s ',auto=true,interval=300}
                e.linebuf[#e.linebuf+1]=buffer('/s ',512)
            else e.error='Достигнут лимит строк'end
        end
        V.inline(5,162)
        if b('<lavka>','insert_lavka',155)then
            local i=#e.rows
            if i>0 then
                local prev=DSP.to_cp(ffi.string(e.linebuf[i]))
                if #prev<460 then
                    e.rows[i].text=prev..' <lavka>'
                    e.linebuf[i]=buffer(e.rows[i].text,512)
                end
            end
        end
        V.muted('<lavka> — номер твоей лавки, если он обнаружен.')
        V.text('Интервалы')
        modify_number('Пауза между строками (0.5-10 c)',e.waiting,'wait',.5,10,.5)
        modify_number('Минимальный интервал (сек)',e.min,'min',30,3600,30)
        modify_number('Максимум (0 = без случайности)',e.max,'max',0,3600,30)
        modify_number('Лимит циклов (0 = без лимита)',e.limit,'limit',0,1000,1)
        if b(e.random and'Случайная строка: ДА' or'Случайная строка: НЕТ',
                'random',235,e.random)then e.random=not e.random end
        if b(e.auto and'Авто: включено' or'Авто: выключено',
                'edited_auto',235,e.auto)then e.auto=not e.auto end
        V.muted('Интервал выбирается отдельно для каждого шаблона.')
    end,{footer=true})
end
local function countdown(t)
    if t.auto==false then return 'Авто выключено'end
    local low=tonumber(t.interval_min)or 0
    if low<=0 then low=tonumber((t.rows or{})[1] and t.rows[1].interval)or 300 end
    local high=tonumber(t.interval_max)or 0
    local period=high>low and(low..'-'..high)or tostring(low)
    local due=tonumber(t._promo_due)
    if not due then
        local last=tonumber(t.last_sent)or 0
        due=last>0 and last+low or os.time()
    end
    return 'Интервал '..period..'с | осталось '..math.max(0,due-os.time())..'с'
end
function V.promo_screen()
    if V.promo298_edit then return editor(V.promo298_edit)end
    local s=P.settings()
    V.heading('Автопиар',function()
        if b('+ Шаблон','new',155,true)then new_editor(nil)end
    end,160)
    V.muted('Как в Market Helper: Пуск / Авто / Редактировать')
    if P.running then
        if b('Остановить всё','stop_all',173,true)then P.stop()end
    else
        if b('Запустить авто','start_all',173,true)then
            if not s.continuous then P.set_option('continuous',true)end
            local ok,why=P.start()
            V.promo298_error=not ok and tostring(why)or nil
        end
    end
    V.inline(5,130)
    if b('Настройки','promo_settings',130)then V.set_screen('settings')end
    V.muted('Состояние: '..(P.running and(P.pause_reason or'работает')or'выключен')..
        ' | отправлено: '..tostring(P.session_count or 0))
    if V.promo298_error or P.last_error then V.red(tostring(V.promo298_error or P.last_error))end
    if #s.templates==0 then
        V.muted('Нет шаблонов. Нажми + Шаблон.')
        return
    end
    V.list_rows('pm298_templates',s.templates,128,function(t,i)
        V.row('pm298_t_'..i,128,function(w,x,y)
            V.at(x,y)
            V.text(V.fit(t.name or'Шаблон',math.max(105,w-18)))
            V.at(x,y+28)
            V.muted(V.fit(#(t.rows or{})..' строк | '..countdown(t),math.max(100,w-18)))
            local bw=math.max(78,math.floor((w-24)/3))
            V.at(x,y+64)
            if b('Пуск','send_'..i,bw)then
                local ok,why=P.send_template_once(i)
                V.promo298_error=not ok and tostring(why)or nil
            end
            V.inline(5,bw)
            if b(t.auto~=false and'Авто: ВКЛ' or'Авто: ВЫКЛ','auto_'..i,bw,t.auto~=false)then
                toggle_auto(i)
            end
            V.inline(5,bw)
            if b('Изменить','edit_'..i,bw)then new_editor(i)end
        end)
    end,{footer=true})
end
local expand=P.expand
function P.expand(text)
    if type(text)=='string' and text:find('<lavka>',1,true)then
        local number,why=P.own_shop_number()
        if not number then return nil,tostring(why or'Номер лавки неизвестен')end
        text=text:gsub('<lavka>',':lavka'..tostring(number)..':')
    end
    return expand(text)
end
-- The earlier 2.9.7 OTA put control shortcuts in home/trade. Hide those,
-- without replacing the working home/trade renderers.
if not V._pm298_button_wrap then
    V._pm298_button_wrap=true
    local original=V.button
    V.button=function(label,id,...)
        if type(id)=='string' and id:find('^v297_control_') then return false end
        return original(label,id,...)
    end
end
if not V._pm298_nav_wrap then
    V._pm298_nav_wrap=true
    local original=V.list_rows
    V.list_rows=function(key,rows,...)
        if key=='navigation' and type(rows)=='table' then
            local filtered={}
            for _,item in ipairs(rows)do
                if type(item)~='table' or item[1]~='control' then
                    filtered[#filtered+1]=item
                end
            end
            return original(key,filtered,...)
        end
        return original(key,rows,...)
    end
end
return true
