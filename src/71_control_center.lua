-- Palatka AI 2.9.7: user control center for safe, persistent timing and status.
-- Only explicitly wired controls are editable. No automatic trade starts.
DSP.controls=DSP.controls or {}
local C,V,M=DSP.controls,DSP.ui22,DSP.mobile
local limits={
    sell_step_pause_ms={100,5000,260,'Пауза между выставлениями, мс'},
    buy_step_pause_ms={0,5000,0,'Пауза между позициями скупки, мс'},
    promo_global_cooldown_s={30,3600,30,'Пауза между циклами рекламы, сек'},
    promo_session_limit={1,200,12,'Лимит команд за сессию'},
    refresh_seconds={180,3600,300,'Обновление рынка API, сек'},
    local_offer_ttl_minutes={5,1440,60,'Актуальность локальной лавки, мин'},
    max_local_shops={20,300,80,'Лавок в локальном кэше'},
    promo_start_delay={10,120,20,'Пауза после входа, сек'}
}
C.limits=limits
local function target(key)
    if key=='promo_start_delay'then
        DSP.settings.promo=DSP.settings.promo or{}
        return DSP.settings.promo,'start_delay'
    end
    if key=='refresh_seconds'or key=='local_offer_ttl_minutes'or key=='max_local_shops'then
        return DSP.settings,key
    end
    DSP.settings.control_center=DSP.settings.control_center or{}
    return DSP.settings.control_center,key
end
function C.get(key)
    local spec=limits[key];if not spec then return nil end
    local t,k=target(key)
    local v=tonumber(t[k])
    if not v or v~=v or v%1~=0 or v<spec[1]or v>spec[2]then return spec[3]end
    return v
end
function C.set(key,value)
    local spec=limits[key];if not spec then return false,'Неизвестная настройка'end
    local n=tonumber(value)
    if not n or n~=n or n%1~=0 or n<spec[1]or n>spec[2]then
        return false,'Допустимо: '..spec[1]..' - '..spec[2]
    end
    local t,k=target(key);local previous=t[k]
    t[k]=n
    local ok,err=DSP.save_settings()
    if not ok then t[k]=previous;return false,'Не удалось сохранить: '..tostring(err)end
    if key=='refresh_seconds' and DSP.market and DSP.market.state then
        DSP.market.state.filter_version=-1
    end
    return true
end
local ordered={'sell_step_pause_ms','buy_step_pause_ms','promo_global_cooldown_s',
    'promo_session_limit','promo_start_delay','refresh_seconds',
    'local_offer_ttl_minutes','max_local_shops'}
function C.profile(name)
    local profiles={
        default={260,0,30,12,20,300,60,80},
        cautious={800,800,300,12,30,600,30,80},
        relaxed={1200,1500,600,6,45,900,20,60}
    }
    local values=profiles[name];if not values then return false,'Профиль не найден'end
    local previous={}
    for i,key in ipairs(ordered)do
        local t,k=target(key)
        previous[i]={t,k,t[k]};t[k]=values[i]
    end
    local ok,err=DSP.save_settings()
    if not ok then
        for _,p in ipairs(previous)do p[1][p[2]]=p[3]end
        return false,'Не удалось сохранить профиль: '..tostring(err)
    end
    C._editors={}
    return true
end
function C.stop_all()
    local errors={}
    if DSP.auto then
        if DSP.auto.sell_running and DSP.auto.stop_sell then
            local ok,err=pcall(DSP.auto.stop_sell)
            if not ok then errors[#errors+1]=tostring(err)end
        end
        if DSP.auto.buy_running and DSP.auto.stop_buy then
            local ok,err=pcall(DSP.auto.stop_buy)
            if not ok then errors[#errors+1]=tostring(err)end
        end
    end
    if DSP.promo and DSP.promo.stop and (DSP.promo.running or DSP.promo._batch) then
        local ok,err=pcall(DSP.promo.stop)
        if not ok then errors[#errors+1]=tostring(err)end
    end
    if #errors>0 then return false,table.concat(errors,'; ')end
    return true
end
local function status()
    local a,p=DSP.auto or{},DSP.promo or{}
    local left=p.queue_left and p.queue_left()or nil
    local lines={
        'Продажа: '..(a.sell_running and 'работает' or 'выключена')..
            ' | Скупка: '..(a.buy_running and 'работает' or 'выключена'),
        'Операция: '..tostring(a.status or 'готово'),
        'Авто-пиар: '..(p.running and 'работает' or 'выключен')..
            ' | Команд: '..tostring(p.session_count or 0)..
            (left and (' | следующая через '..left..' с')or''),
        'Рынок: '..tostring(DSP.market and DSP.market.state and DSP.market.state.status or 'нет данных')
    }
    return lines
end
local function b(title,id,w,on,primary)
    return V.button(title,'control297_'..id,w,on,primary,39)
end
local function edit_field(key)
    local spec=limits[key]
    C._editors=C._editors or{}
    local item=C._editors[key]
    if not item then item={value=C.get(key)};C._editors[key]=item end
    V.muted(spec[4]..'  ['..spec[1]..'..'..spec[2]..']')
    local edited=M.compact_number(item,'value','ctl297_'..key,165,spec[1])
    if edited then
        local ok,err=C.set(key,item.value)
        if not ok then
            C.error=err
            item.value=C.get(key)
            M.refresh_buffer(item,'value')
        else C.error=nil end
    end
end
local function toggle(label,obj,key,default)
    local on=obj[key]
    if on==nil then on=default end
    if b(label..': '..(on and 'ВКЛ' or 'ВЫКЛ'),'toggle_'..key,230,on)then
        local old=obj[key]
        obj[key]=not on
        local ok,err=DSP.save_settings()
        if not ok then obj[key]=old;C.error='Не удалось сохранить: '..tostring(err)
        else C.error=nil end
    end
end
function C.draw()
    V.heading('Управление Palatka AI')
    V.muted('Изменение параметров не запускает команды. Стандартные значения можно вернуть.')
    if b('Остановить торговлю и пиар','stop_all',300,false,true)then
        local ok,err=C.stop_all();C.error=not ok and err or nil
    end
    V.inline(5)
    if b('Стандарт','preset_default',130)then
        local ok,err=C.profile('default');C.error=not ok and err or nil
    end
    if b('Бережный','preset_cautious',140)then
        local ok,err=C.profile('cautious');C.error=not ok and err or nil
    end
    V.inline(5)
    if b('Медленный','preset_relaxed',140)then
        local ok,err=C.profile('relaxed');C.error=not ok and err or nil
    end
    if C.error then V.red(C.error)end
    V.list('control_center_fields',function()
        V.text('Текущий статус')
        for _,line in ipairs(status())do V.muted(line)end
        if DSP.auto and DSP.auto.progress then
            local pr=DSP.auto.progress
            V.muted('Прогресс: '..tostring(pr.done or 0)..' / '..tostring(pr.total or 0)..
                ' | ошибок: '..tostring(pr.failed or 0))
        end
        imgui.Separator()
        V.text('Выставление лавки и скупка')
        toggle('ТЕСТ без игровых команд',DSP.settings,'dry_run',true)
        edit_field('sell_step_pause_ms')
        edit_field('buy_step_pause_ms')
        V.muted('Реальное выставление запускается вручную во вкладке Торговля.')
        if b('Перейти к торговле','trade',225)then V.set_screen('palatka')end
        imgui.Separator()
        V.text('Авто-пиар')
        DSP.settings.promo=DSP.settings.promo or{}
        toggle('Возобновлять после входа',DSP.settings.promo,'resume_on_login',false)
        toggle('Повторять без лимита',DSP.settings.promo,'continuous',false)
        edit_field('promo_global_cooldown_s')
        edit_field('promo_session_limit')
        edit_field('promo_start_delay')
        V.muted('Интервалы, паузы строк и лимиты шаблонов задаются в редакторе авто-пиара.')
        V.muted('Соблюдай ограничения сервера: отправка из Lua не подтверждает приём.')
        if b('Открыть авто-пиар','promo',225)then V.set_screen('promo')end
        imgui.Separator()
        V.text('Лавки и данные')
        edit_field('refresh_seconds')
        edit_field('local_offer_ttl_minutes')
        edit_field('max_local_shops')
        V.muted('TTL означает свежесть скана, а не удаление истории.')
        if b('Открыть список лавок','shops',225)then V.set_screen('lavki')end
        imgui.Separator()
        V.text('Ломбард')
        local ls=DSP.lombard and DSP.lombard.stats and DSP.lombard.stats()
        if ls then V.muted('В базе: '..tostring(ls.items)..' | страниц: '..tostring(ls.pages))end
        if b('Открыть ломбард','lombard',225)then V.set_screen('lombard')end
        V.muted('Нативный скан запускается вручную у меню ломбарда.')
    end,{footer=false})
end
V.control_screen=C.draw
return true
