-- Original MCR-inspired compact workspace. Palatka models and packet handlers remain authoritative.
-- No third-party authentication, network requests or trade packet code is imported.
local U,V,M,T = DSP.ui,DSP.ui22,DSP.mobile,DSP.trade_v16
local Classic={source='inventory',search='',edit=nil}
DSP.mcr_classic=Classic
if DSP.settings.ui_style==nil then DSP.settings.ui_style='mcr' end
if DSP.settings.mcr_classic_alpha==nil then DSP.settings.mcr_classic_alpha=.94 end
local function cp(s)return DSP.utf8(tostring(s or ''))end
local function button(s,id,w,active,h)return V.button(s,'mcr_'..id,w,active,false,h or 38)end
local function save()if M and M.defer_save then M.defer_save()end end
local function busy()return DSP.auto.sell_running or DSP.auto.buy_running end
local function current()return V.kind=='sell' and DSP.settings.sell_preset or DSP.settings.buy_preset end
local function navigate(id)V.set_screen(id);Classic.edit=nil end
local navigation={
 {'palatka','Торговля'},{'lavki','Лавки ЦР'},{'arbitrage','Арбитраж'},
 {'resale','Перепродажа'},{'scan','Сканер'},{'market','Рынок'},
 {'storage','Хранилища'},{'lombard','Ломбард'},{'logs','Журнал'},
 {'calculator','Калькулятор'},{'stats','Статистика'},{'settings','Настройки'},
 {'search','Поиск'},{'promo','Автопиар'},{'home','Обзор'}
}
local function side_panel(width,height)
    if imgui.BeginChild('##mcr_left',imgui.ImVec2(width,height),true,imgui.WindowFlags.NoScrollbar)then
        V.apply_font()
        if button('P','home',-1,V.screen=='home',42)then navigate('home')end
        V.muted('МЕНЮ')
        V.list_rows('mcr_nav',navigation,43,function(entry,i)
            local short=entry[2]
            if width<110 then
                local names={palatka='Торг.',lavki='Лавки',arbitrage='Арбитр.',resale='Перепр.',scan='Скан',
                  market='Рынок',storage='Склад',lombard='Ломб.',logs='Логи',calculator='Счёт',
                  stats='Стат.',settings='Опции',search='Поиск',promo='Пиар',home='Обзор'}
                short=names[entry[1]] or short
            end
            if button(short,'nav_'..i,-1,V.screen==entry[1],40)then navigate(entry[1])end
        end,{height=math.max(60,imgui.GetContentRegionAvail().y-54),footer=true,footer_height=44})
    end
    imgui.EndChild()
end
local function all_items(query)
    local q=DSP.lower(query or '')
    local source=Classic.source=='inventory' and (DSP.auto.inv or{}) or (DSP.items.by_id or{})
    local sig=table.concat({Classic.source,tostring(source),tostring(#(DSP.auto.inv or{})),q},'|')
    return V.memo('mcr_items',sig,function()
        local rows={}
        if Classic.source=='inventory'then
            for _,it in ipairs(DSP.auto.inv or{})do
                if q=='' or DSP.lower(it.name or''):find(q,1,true)then rows[#rows+1]=it end
            end
        else
            for id,name in pairs(DSP.items.by_id or{})do
                if type(name)=='string' and name~='-' and not name:find('DELETED',1,true)
                    and(q=='' or DSP.lower(name):find(q,1,true) or tostring(id)==q)then
                    rows[#rows+1]={id=id,name=name}
                end
            end
            table.sort(rows,function(a,b)return a.name<b.name end)
        end
        return rows
    end)
end
local function available_row(it,i)
    V.row('mcr_available_'..i,52,function(w,x,y)
        local title=V.fit(it.display or it.name or '?',math.max(40,w-12))
        if V.text_button(title,'mcr_add_'..i,-1,false,27)and not busy()then
            local ok,msg
            if Classic.source=='inventory'then ok,msg=T.add_from_inventory(V.kind,it)
            else ok,msg=T.add_from_catalog(V.kind,it)end
            if not ok then DSP.notify(tostring(msg or 'Нельзя добавить'))end
        end
        V.at(x,y+26)
        V.muted(Classic.source=='inventory'and('В наличии: '..tostring(it.count or it.qty or 0))or('ID '..tostring(it.id or '?')))
    end)
end
local function selected_row(it,i)
    V.row('mcr_selected_'..i,58,function(w,x,y)
        local title=V.fit(it.name or '?',math.max(40,w-14))
        if V.text_button(title,'mcr_edit_'..i,-1,false,28)then
            Classic.edit=it;V.open_popup('Позиция','mcr_edit')
        end
        V.at(x,y+28)
        local label=(it.enabled==false and '[OFF] 'or'')..
            'x'..tostring(it.qty or'?')..' · '..DSP.money(tonumber(it.price)or 0)
        V.muted(V.fit(label,math.max(40,w-14)))
    end)
end
local function trade_panel()
    local w=imgui.GetContentRegionAvail().x
    V.heading('Торговля',function()
        if button('Продажа','sell',91,V.kind=='sell')then V.kind='sell'end
        V.inline()
        if button('Скупка','buy',91,V.kind=='buy')then V.kind='buy'end
    end,202)
    local pres=current()
    V.muted(V.fit('Набор: '..tostring(pres.name or 'Основной'),w))
    local cols=w>=430
    if cols then
        local left=math.max(110,math.floor(w*.46))
        local right=math.max(110,w-left-6)
        if imgui.BeginChild('##mcr_stock',imgui.ImVec2(left,0),true)then
            V.apply_font()
            if button(Classic.source=='inventory'and'Инвентарь >'or'Каталог >','source',-1)then
                Classic.source=Classic.source=='inventory'and'catalog'or'inventory'
                V.reset_list('mcr_stock_list')
            end
            local query,edited=V.search('mcr_stock','Поиск предмета',-1)
            if edited then V.reset_list('mcr_stock_list')end
            V.list_rows('mcr_stock_list',all_items(query),52,available_row,{footer=true,footer_height=45})
        end
        imgui.EndChild()
        V.inline(6,120)
        if imgui.BeginChild('##mcr_preset',imgui.ImVec2(0,0),true)then
            V.apply_font()
            V.text('Выставляемые товары')
            V.muted(tostring(#(pres.items or{}))..' позиций · нажми для правки')
            V.list_rows('mcr_preset_list',pres.items or{},58,selected_row,{footer=true,footer_height=45})
        end
        imgui.EndChild()
    else
        Classic.tab=Classic.tab or 'stock'
        if button('Инвентарь','stocktab',110,Classic.tab=='stock')then Classic.tab='stock'end
        V.inline()
        if button('Набор ('..#(pres.items or{})..')','presettab',120,Classic.tab=='preset')then Classic.tab='preset'end
        if Classic.tab=='stock'then
            if button(Classic.source=='inventory'and'Инвентарь >'or'Каталог >','source',-1)then
                Classic.source=Classic.source=='inventory'and'catalog'or'inventory'
            end
            local query,edited=V.search('mcr_stock','Поиск предмета',-1)
            if edited then V.reset_list('mcr_stock_list')end
            V.list_rows('mcr_stock_list',all_items(query),52,available_row,{footer=true})
        else
            V.list_rows('mcr_preset_list',pres.items or{},58,selected_row,{footer=true})
        end
    end
end
local function action_panel(width,height)
    if imgui.BeginChild('##mcr_right',imgui.ImVec2(width,height),true,imgui.WindowFlags.NoScrollbar)then
        V.apply_font()
        if V.screen=='palatka'then
            V.muted('ДЕЙСТВИЯ')
            if button('Наборы','presets',-1)then V.open_popup('Наборы','presets')end
            if button('Скан','scan_inv',-1)then
                if DSP.auto and DSP.auto.scan_inventory then DSP.auto.scan_inventory()end
            end
            if busy()then
                if button('СТОП','stop',-1,true)then
                    if DSP.auto.sell_running then DSP.auto.stop_sell()else DSP.auto.stop_buy()end
                end
            else
                if button('Выставить','launch',-1,true,52)then V.open_popup('Выставление','launch')end
            end
            local r=T.totals(V.kind)
            imgui.Separator()
            V.muted(r.complete and (V.kind=='buy'and'Бюджет' or 'Выручка')or'Проверь цены')
            if r.complete then
                V.text(DSP.money(V.kind=='buy'and r.required_funds or r.gross))
                if V.kind=='sell'then V.muted('Чистыми ~');V.text(DSP.money(r.net))end
            end
        else
            V.muted('БЫСТРО')
            if button('Торговля','to_trade',-1)then navigate('palatka')end
            if button('Лавки','to_shops',-1)then navigate('lavki')end
            if button('Журнал','to_logs',-1)then navigate('logs')end
        end
        imgui.Separator()
        if button('Наш UI','carbon',-1)then DSP.settings.ui_style='carbon';save()end
        if button('Мини-лог','mini',-1)then
            DSP.settings.craglog.open=not DSP.settings.craglog.open;save()
        end
    end
    imgui.EndChild()
end
local function other_panel()
    local id=V.screen
    if id=='home'then V.home()
    elseif id=='lavki'then V.shops()
    elseif id=='scan'then V.shops_source='scan';V.shops()
    elseif id=='market'then V.shops_source='api';V.shops()
    elseif id=='arbitrage'then V.arbitrage()
    elseif id=='resale'then V.flip_screen()
    elseif id=='storage'then V.storage_screen()
    elseif id=='logs'then V.journal()
    elseif id=='calculator'then V.calculator()
    elseif id=='history'then V.journal_mode='events';V.journal()
    elseif id=='promo'then V.promo_screen()
    elseif V.tools then V.tools(id)
    else DSP.screens.draw(id)end
end
local function edit_popup()
    local it=Classic.edit
    if not it then return end
    V.text(tostring(it.name or '?'))
    V.muted('Цена за штуку')
    if not busy()then M.compact_number(it,'price','mcr_edit_price',190,0)
    else V.text(DSP.money(it.price or 0))end
    V.muted('Количество')
    if not busy()then M.compact_number(it,'qty','mcr_edit_qty',160,1)
    else V.text(tostring(it.qty or 0))end
    if not busy()then
        if button(it.enabled==false and'Включить' or 'Выключить','toggle_item',140,it.enabled~=false)then
            it.enabled=it.enabled==false and(tonumber(it.price)or 0)>0 or false;save()
        end
        V.inline()
        if button('Удалить','remove_item',130)then
            V.remove_pending={kind=V.kind,item=it}
            imgui.CloseCurrentPopup()
            V.open_popup('Удалить позицию','remove')
        end
    end
    if button('Готово','edit_done',130)then imgui.CloseCurrentPopup()end
end
local old_popups=V.popups
function V.popups()
    if old_popups then old_popups()end
    V.popup('Позиция','mcr_edit',edit_popup,{w=470,h=310})
end
local original_draw=U.draw
function Classic.draw()
    if V and V.track_touch then V.track_touch(imgui.GetIO())end
    local io=imgui.GetIO();local sz=io.DisplaySize
    local g=V.geometry(sz.x,sz.y)
    -- MCR's compact default, but keep user-resized Palatka geometry unchanged.
    if not DSP.settings.mobile_window then
        g.w=math.min(g.w,850);g.h=math.min(g.h,470)
        g.x=(sz.x-g.w)*.5;g.y=(sz.y-g.h)*.5
    end
    if not V.initialized then
        V.screen=(U.screen and U.screen~='palatka')and U.screen or'palatka'
        V.initialized=true
    end
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    local colors=DSP.theme.push_window()
    imgui.SetNextWindowBgAlpha(DSP.settings.mcr_classic_alpha)
    -- Warm beige MCR accent on native ImGui, without overwriting Palatka's saved theme.
    imgui.PushStyleColor(imgui.Col.Button,imgui.ImVec4(.26,.25,.23,1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered,imgui.ImVec4(.40,.36,.30,1))
    imgui.PushStyleColor(imgui.Col.ButtonActive,imgui.ImVec4(.48,.41,.33,1))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(7,7))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,5))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,5)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoResize+imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoScrollbar
    M.flush_save(false)
    if imgui.Begin('##palatka_mcr_classic',U.open_ref,flags)then
        V.font_pixels=V.font_scale_for(1,g.w,U.d)
        V.apply_font()
        local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
        local labelw=math.max(75,g.w-178)
        V.text_button('MCR CLASSIC  /  PALATKA AI', 'mcr_window_drag',labelw,false,31)
        if imgui.IsItemActive() and io.MouseDelta then
            local d=io.MouseDelta
            if d.x~=0 or d.y~=0 then
                DSP.settings.mobile_window={x=DSP.clamp(g.x+d.x,0,sz.x-g.w),
                    y=DSP.clamp(g.y+d.y,0,sz.y-g.h),w=g.w,h=g.h};save()
            end
        end
        V.at(x+g.w-143,y)
        if button('МЕНЮ','menu',81,V.nav,31)then V.nav=not V.nav end
        V.at(x+g.w-55,y)
        if button('X','close',39,false,31)then U.set_open(false)end
        V.at(x,y+39);imgui.Separator()
        local available=imgui.GetContentRegionAvail()
        local left=math.min(102,math.max(78,g.w*.14))
        local right=math.min(124,math.max(88,g.w*.16))
        if V.nav and g.w<550 then
            side_panel(math.max(160,available.x),available.y-35)
        else
            side_panel(left,available.y-35)
            V.inline(5,120)
            local center=math.max(100,available.x-left-right-14)
            if imgui.BeginChild('##mcr_workspace',imgui.ImVec2(center,available.y-35),false)then
                V.apply_font()
                local ok,err=xpcall(function()
                    if V.screen=='palatka' then trade_panel()else other_panel()end
                end,debug.traceback)
                if not ok then
                    V.errors[V.screen]=err;DSP.flog('MCR Classic UI: '..tostring(err))
                    V.red('Ошибка экрана. См. standalone.log')
                end
            end
            imgui.EndChild()
            V.inline(5,80)
            action_panel(right,available.y-35)
        end
        V.at(x,math.max(y+39,g.h-42))
        V.muted(V.fit('Palatka AI · Mobile 2 · '..tostring(DSP.auto.status or 'готов'),math.max(100,g.w-58)))
        if V.popup_pending then
            local p=V.popup_pending;V.popup_pending=nil;imgui.OpenPopup(cp(p.title)..'##v22_'..p.id)
        end
        if V.popups then V.popups()end
        V.resize_grip(g,io)
    end
    imgui.End()
    imgui.PopStyleVar(3);imgui.PopStyleColor(3)
    if colors and colors>0 then imgui.PopStyleColor(colors)end
    if U.open_ref and not U.open_ref[0]then M.flush_save(true);U.open=false end
end
function U.draw()
    if DSP.settings.ui_style=='mcr' then return Classic.draw()end
    return original_draw()
end
return true
