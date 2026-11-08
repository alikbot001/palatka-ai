-- MCR-inspired mobile workspace. Additive to the stable 2.9.16 trading runtime.
-- Only the window shell and navigation change; all native trade dialogs remain in place.
local V,U,M=DSP.ui21,DSP.ui,DSP.mobile
if V._mcr_workspace then return end
V._mcr_workspace=true

local function rgba(r,g,b,a) return imgui.ImVec4(r/255,g/255,b/255,a or 1) end
local function push_palette()
    local palette={
        {'WindowBg',246,237,220},{'ChildBg',249,241,226},
        {'PopupBg',250,242,228},{'Text',51,50,41},
        {'TextDisabled',117,104,88},{'Button',206,185,160},
        {'ButtonHovered',186,164,137},{'ButtonActive',157,138,110},
        {'FrameBg',239,225,204},{'FrameBgHovered',227,207,179},
        {'FrameBgActive',221,200,173},{'Border',198,179,150},
        {'Separator',200,181,153},{'Header',211,193,167},
        {'HeaderHovered',195,174,145},{'HeaderActive',174,154,126},
        {'ScrollbarBg',236,223,201},{'ScrollbarGrab',169,147,118},
        {'ScrollbarGrabHovered',148,128,103},{'ScrollbarGrabActive',125,107,84},
        {'CheckMark',85,110,59},
    }
    local count=0
    for _,entry in ipairs(palette)do
        local col=imgui.Col[entry[1]]
        if col then
            imgui.PushStyleColor(col,rgba(entry[2],entry[3],entry[4]))
            count=count+1
        end
    end
    return count
end

-- The old button helper uses the dark Carbon accent, so replace only its
-- color selection. IDs, hit sizes and drag suppression stay compatible.
function V.button(label,id,width,active,primary,height)
    local n=0
    if active or primary then
        imgui.PushStyleColor(imgui.Col.Button,active and rgba(115,137,76) or rgba(104,128,67))
        imgui.PushStyleColor(imgui.Col.ButtonHovered,rgba(124,147,85))
        imgui.PushStyleColor(imgui.Col.ButtonActive,rgba(88,109,59))
        imgui.PushStyleColor(imgui.Col.Text,rgba(255,251,241))
        n=4
    end
    local avail=imgui.GetContentRegionAvail().x
    local w=width or -1
    if w>0 then w=math.max(1,math.min(w,avail))end
    local visible=tostring(label or '')
    if w>0 then visible=V.fit(visible,math.max(1,w-14))end
    local pressed=imgui.Button(DSP.utf8(visible)..'##v22_'..tostring(id),imgui.ImVec2(w,height or 42))
    if n>0 then imgui.PopStyleColor(n)end
    return pressed and not V.dragged
end

local primary={
    {'palatka','Пресет'}, {'lavki','Лавка'}, {'arbitrage','Лавки'},
    {'logs','Логи'}, {'more','Ещё'},
}
local catalog={
    {'storage','Хранилища'}, {'resale','Перепродажа'},
    {'promo','Автопиар'}, {'scan','Скан лавки'},
    {'market','Рынок API'}, {'search','Поиск'},
    {'calculator','Калькулятор'}, {'stats','Статистика'},
    {'notes','Блокнот'}, {'lombard','Ломбард'},
    {'history','История'}, {'settings','Настройки'},
}
local special={more=true,advanced=true,updates=true}
local original_set_screen=V.set_screen
V.set_screen=function(id)
    if special[id] then
        if U._notes_dirty and M.save_notes and not M.save_notes()then return false end
        V.screen=id;V.nav=false
        return true
    end
    return original_set_screen(id)
end

local function set(id)
    if V.set_screen(id) then V.mcr_error=nil end
end
local function refresh_market()
    if not (DSP.market and DSP.market.pull and DSP.market.state)then
        V.mcr_error='Рынок пока недоступен';return
    end
    if DSP.market.state.status=='loading' then
        V.mcr_error='Обновление уже выполняется';return
    end
    local sid=(DSP.detect_server and DSP.detect_server()) or DSP.market.state.sid or DSP.settings.server
    local ok,err=pcall(DSP.market.pull,sid)
    if not ok then V.mcr_error='Ошибка обновления: '..tostring(err)
    else V.mcr_error='Запрос обновления цен отправлен' end
end
local function refresh_inventory()
    if not (DSP.auto and DSP.auto.scan_inventory)then
        V.mcr_error='Сканирование недоступно';return
    end
    local ok,started=pcall(DSP.auto.scan_inventory)
    if not ok then V.mcr_error='Ошибка сканирования: '..tostring(started)
    elseif started==false then V.mcr_error='Сканирование занято или торговая очередь активна'
    else V.mcr_error='Сканирование запущено. Откройте инвентарь лавки.'end
end
local function context_action(action)
    if action=='refresh_inventory' then refresh_inventory()
    elseif action=='refresh_market' then refresh_market()
    elseif action=='preset' then set('palatka');V.tab='preset'
    elseif action=='sell' then set('palatka');V.kind='sell';V.tab='items'
    elseif action=='buy' then set('palatka');V.kind='buy';V.tab='items'
    elseif action=='launch' then set('palatka');V.tab='preset';V.open_popup('Выставление','launch')
    elseif action=='settings_view' then V.tools_section=1;set('settings')
    elseif action=='settings_trade' then V.tools_section=2;set('settings')
    elseif action=='settings_data' then V.tools_section=3;set('settings')
    elseif action=='settings_telegram' then V.tools_section=4;set('settings')
    else set(action) end
end
local function context_entries()
    if V.screen=='palatka' then
        return {{'Обновить','refresh_inventory'},{'Пресеты','preset'},{'Продажа','sell'},
            {'Скупка','buy'},{'Выставить','launch'},{'Функции','settings_trade'}}
    elseif V.screen=='lavki' or V.screen=='market' or V.screen=='scan' then
        return {{'Обновить','refresh_market'},{'Лавки','lavki'},{'Рынок','market'},
            {'Скан','scan'},{'Настройки','settings_data'}}
    elseif V.screen=='logs' or V.screen=='history' or V.screen=='stats' then
        return {{'Логи','logs'},{'История','history'},{'Статистика','stats'},
            {'Блокнот','notes'},{'Telegram','settings_telegram'}}
    elseif V.screen=='settings' or V.screen=='advanced' then
        return {{'Интерфейс','settings_view'},{'Торговля','settings_trade'},
            {'Данные','settings_data'},{'Дополнительно','advanced'},
            {'Обновления','updates'}}
    else
        return {{'Обновить','refresh_market'},{'Настройки','settings'},
            {'Блокнот','notes'},{'Калькулятор','calculator'},
            {'Обновления','updates'}}
    end
end

local function tile_grid(rows,key)
    local width=math.max(1,imgui.GetContentRegionAvail().x)
    local columns=width>=440 and 3 or 2
    local width_per=math.max(70,(width-(columns-1)*7)/columns)
    for i,entry in ipairs(rows)do
        if V.button(entry[2],'mcr_tile_'..key..i,width_per,false,false,67)then set(entry[1])end
        if i%columns~=0 and i<#rows then imgui.SameLine(0,7)end
    end
end
function V.mcr_more()
    V.heading('Разделы')
    V.muted('Основные действия — слева. Остальные инструменты доступны здесь.')
    imgui.Separator()
    V.list('mcr_more',function()
        tile_grid(catalog,'more')
    end,{footer=false})
end
function V.mcr_updates()
    V.heading('Обновления')
    V.list('mcr_updates',function(w)
        V.text('Установлена Palatka AI v'..tostring(DSP.version))
        V.muted('Обновить данные рынка можно отдельной кнопкой справа.')
        V.muted('Обновить инвентарь можно на вкладке «Пресет».')
        imgui.Separator()
        V.text('Обновление самого Lua-скрипта')
        V.muted('Стабильный выпуск: GitHub / alikbot001 / palatka-ai')
        V.muted('Файл выпуска: palatka_ai.lua')
        V.muted('Манифест обновлений: version.json')
        V.muted('Автоматическая замена выполняемого Lua без проверки загрузчика отключена.')
        if V.button('Обновить цены сейчас','mcr_refresh_from_updates',math.min(w,275),false,true)then refresh_market()end
        if V.mcr_error then V.muted(V.fit(V.mcr_error,w))end
    end,{footer=false})
end
local function switch(label,key,default)
    local current=DSP.settings[key]
    if current==nil then current=default end
    if V.button((current and '[x] 'or'[ ] ')..label,'mcr_toggle_'..key,-1)then
        DSP.settings[key]=not current;M.defer_save()
    end
end
local function number(label,key,min,max)
    V.muted(label)
    if M.compact_number(DSP.settings,key,'mcr_num_'..key,math.min(260,imgui.GetContentRegionAvail().x),min)then
        local n=tonumber(DSP.settings[key]) or min
        DSP.settings[key]=math.max(min,math.min(max,math.floor(n)))
        M.defer_save()
    end
end
function V.mcr_advanced()
    V.heading('Дополнительные настройки')
    V.list('mcr_advanced',function(w)
        V.text('Сканирование и кэш')
        switch('Автоматически сохранять открытые лавки','auto_shop_scan',true)
        number('Максимум сохранённых лавок (20–300)','max_local_shops',20,300)
        number('Срок актуальности снимка (мин., 1–1440)','local_offer_ttl_minutes',1,1440)
        number('Тихое окно сканирования (мс, 200–5000)','scan_quiet_ms',200,5000)
        number('Ожидание идентификации (мс, 300–10000)','identity_grace_ms',300,10000)
        imgui.Separator()
        V.text('Производительность и журнал')
        switch('Экономия FPS','fps_saver',false)
        switch('Запись наград и тайников','log_chat_drops',true)
        number('История цен (дней, 1–30)','price_history_days',1,30)
    end,{footer=function()
        if V.button('Сохранить настройки','mcr_advanced_save',math.min(245,w or 245),false,true)then
            if DSP.save_settings()then
                if DSP.save_ui_state then DSP.save_ui_state()end
                V.mcr_error='Настройки сохранены'
            else V.mcr_error='Не удалось сохранить настройки'end
        end
    end})
end

local previous_tools=V.tools
V.tools=function(screen)
    if screen=='advanced' then return V.mcr_advanced()end
    if screen=='settings' then
        -- Direct category selection replaces repeated next/previous taps.
        local cats={{1,'Интерфейс'},{2,'Торговля'},{3,'Данные'},{4,'Telegram'},{5,'Диагностика'}}
        local available=imgui.GetContentRegionAvail().x
        local per=available>=540 and 5 or 3
        local bw=math.max(70,(available-(per-1)*5)/per)
        for i,row in ipairs(cats)do
            if V.button(row[2],'mcr_settings_cat_'..i,bw,V.tools_section==row[1],false,36)then
                V.tools_section=row[1];V.reset_list('settings')
            end
            if i%per~=0 and i<#cats then imgui.SameLine(0,5)end
        end
        return previous_tools(screen)
    end
    return previous_tools(screen)
end

local original_geometry=V.geometry
V.geometry=function(sw,sh)
    local saved=DSP.settings.mobile_window
    if type(saved)=='table' and saved.w then return original_geometry(sw,sh)end
    local g=original_geometry(sw,sh)
    g.w=math.min(sw,math.max(math.min(sw,380),math.min(sw*.67,790)))
    g.h=math.min(sh,math.max(math.min(sh,275),math.min(sh*.80,465)))
    g.x=math.max(0,(sw-g.w)*.5)
    g.y=math.max(math.min(18,sh-g.h),(sh-g.h)*.44)
    return g
end
local function header(g,io)
    local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
    if V.button('P','mcr_home',41,true,false,35)then set('more')end
    V.at(x+47,y)
    local width=math.max(75,g.w-47-54)
    V.text_button('PALATKA AI   v'..tostring(DSP.version)..'   |   MOVE','mcr_drag',width,false,35)
    if imgui.IsItemActive() and io.MouseDelta then
        local d=io.MouseDelta
        if d.x~=0 or d.y~=0 then
            DSP.settings.mobile_window={
                x=DSP.clamp(g.x+d.x,0,math.max(0,io.DisplaySize.x-g.w)),
                y=DSP.clamp(g.y+d.y,0,math.max(0,io.DisplaySize.y-g.h)),
                w=g.w,h=g.h}
            M.defer_save()
        end
    end
    V.at(g.w-48,y)
    if V.button('X','mcr_close',38,false,false,35)then U.set_open(false)end
    V.at(x,y+40)
end
local function navigation()
    for i,row in ipairs(primary)do
        local active=V.screen==row[1] or (row[1]=='more' and (V.screen=='home' or V.screen=='settings'
            or V.screen=='advanced' or V.screen=='updates' or V.screen=='storage'))
        if V.button(row[2],'mcr_nav_'..i,-1,active,false,53)then set(row[1])end
    end
end
local function actions()
    for i,row in ipairs(context_entries())do
        local label= row[1]
        if V.button(label,'mcr_action_'..i,-1,false,false,47)then context_action(row[2])end
    end
end
local function workspace()
    if V.screen=='more' or V.screen=='home' then return V.mcr_more()
    elseif V.screen=='updates' then return V.mcr_updates()
    elseif V.screen=='advanced' then return V.mcr_advanced()
    elseif V.screen=='storage' then return V.storage_screen()
    elseif V.screen=='scan' then V.shops_source='scan';return V.shops()
    elseif V.screen=='market' then V.shops_source='api';return V.shops()
    elseif V.screen=='history' then V.journal_mode='events';return V.journal()
    elseif V.screen=='palatka' then return V.trade()
    elseif V.screen=='lavki' then return V.shops()
    elseif V.screen=='arbitrage' then return V.arbitrage()
    elseif V.screen=='resale' then return V.flip_screen()
    elseif V.screen=='promo' then return V.promo_screen()
    elseif V.screen=='logs' then return V.journal()
    elseif V.screen=='calculator' then return V.calculator()
    elseif V.tools then return V.tools(V.screen)
    else return DSP.screens.draw(V.screen)end
end
function U.draw()
    if DSP.carbon_draw then DSP.carbon_draw.begin_frame()end
    local io=imgui.GetIO();local sz=io.DisplaySize;local g=V.geometry(sz.x,sz.y)
    if not V.initialized then
        V.screen=(U.screen and U.screen~='palatka') and U.screen or 'palatka'
        V.initialized=true
    end
    V.track_touch(io)
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    local colors=push_palette()
    imgui.SetNextWindowBgAlpha(.97)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(8,7))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,5))
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding,imgui.ImVec2(7,7))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,5)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,5)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+
        imgui.WindowFlags.NoMove+imgui.WindowFlags.NoSavedSettings+
        imgui.WindowFlags.NoScrollbar+(imgui.WindowFlags.NoScrollWithMouse or 0)
    M.flush_save(false)
    if imgui.Begin('##palatka_mobile',U.open_ref,flags)then
        V.font_pixels=V.font_scale_for(1,g.w,U.d);V.apply_font()
        header(g,io);imgui.Separator()
        local left=math.min(94,math.max(69,g.w*.13))
        local right=g.w>=570 and math.min(110,g.w*.16) or 0
        local body_h=math.max(45,imgui.GetContentRegionAvail().y-49)
        if imgui.BeginChild('##mcr_nav',imgui.ImVec2(left,body_h),true,imgui.WindowFlags.NoScrollbar)then
            V.apply_font();navigation()
        end
        imgui.EndChild()
        imgui.SameLine(0,5)
        if imgui.BeginChild('##mcr_body',imgui.ImVec2(right>0 and -(right+9) or 0,body_h),false,0)then
            V.apply_font()
            local ok,err=xpcall(workspace,debug.traceback)
            if not ok then
                V.last_error=err
                if V.errors[V.screen]~=err then DSP.flog('MCR UI: '..tostring(err))end
                V.errors[V.screen]=err
                V.red('Ошибка экрана. Подробности в standalone.log')
            end
        end
        imgui.EndChild()
        if right>0 then
            imgui.SameLine(0,5)
            if imgui.BeginChild('##mcr_actions',imgui.ImVec2(0,body_h),true,imgui.WindowFlags.NoScrollbar)then
                V.apply_font();actions()
            end
            imgui.EndChild()
        end
        imgui.Separator()
        if V.button('Обновить','mcr_bottom_refresh',116,false,true,35)then
            if V.screen=='palatka' then refresh_inventory() else refresh_market()end
        end
        imgui.SameLine(0,8)
        local available=imgui.GetContentRegionAvail().x
        local status=(DSP.market and DSP.market.state and DSP.market.state.status)or 'offline'
        V.muted(V.fit(V.mcr_error or ('Рынок: '..tostring(status)..'  |  v'..tostring(DSP.version)),math.max(30,available-12)))
        if V.popup_pending then
            local p=V.popup_pending;V.popup_pending=nil
            imgui.OpenPopup(DSP.utf8(p.title)..'##v22_'..p.id)
        end
        if V.popups then V.popups()end
        V.resize_grip(g,io)
    end
    imgui.End();imgui.PopStyleVar(5)
    if colors>0 then imgui.PopStyleColor(colors)end
    if U.open_ref and not U.open_ref[0]then M.flush_save(true);U.open=false end
end
