-- MCR-style compact workspace for Android.  No additional renderer/window:
-- the existing UI21 shell remains the only owner of input, modal and drawing.
-- This module is loaded after legacy screens so their business handlers survive.
local V=DSP.ui21
local old_shops=V.shops

local function go(id)
    if id=='updates' then
        V.set_screen('settings')
        V.open_popup('Обновление Palatka AI','channel_manager')
    elseif id=='presets' then
        V.set_screen('presets')
    elseif id=='scan' then
        V.shops_source='scan'
        V.set_screen('scan')
    else
        V.set_screen(id)
    end
end

-- Icon tiles have a separate, short label directly underneath the hit target.
-- Only safe, real destinations are included; no placeholder API buttons.
local function tiles(key,entries,columns,w)
    local gap=6
    local cols=math.max(1,math.min(columns,#entries))
    local cell=math.max(49,math.floor((w-(cols-1)*gap)/cols))
    local first_x=imgui.GetCursorPosX()
    local first_y=imgui.GetCursorPosY()
    for i,entry in ipairs(entries) do
        local col=(i-1)%cols
        local row=math.floor((i-1)/cols)
        local x=first_x+col*(cell+gap)
        local y=first_y+row*67
        V.at(x,y)
        if V.button(entry[3],'mcr_'..key..'_'..i,cell,false,false,38) then go(entry[2])end
        V.at(x,y+41)
        V.muted(V.fit(entry[1],cell-3))
    end
    V.at(first_x,first_y+math.ceil(#entries/cols)*67+3)
end

local home={
    {'Пресеты','presets','P'}, {'Автопиар','promo','A'},
    {'Цены','market','S'}, {'Настройки','settings','*'},
    {'Лавка','palatka','L'}, {'Арбитраж','arbitrage','R'},
    {'Хранилища','storage','H'}, {'Интерфейс','settings','UI'},
    {'Перепродажа','resale','
function V.home()
    V.heading('Palatka AI',function()
        if V.button('Обновить рынок','mcr_home_refresh',145,false,true,33)then
            if DSP.market and DSP.market.pull and DSP.market.state.status~='loading' then
                DSP.market.pull(DSP.detect_server() or DSP.market.state.sid or DSP.settings.server)
            end
        end
    end,155)
    V.list('mcr_home_tiles',function(w)
        tiles('home',home,w>=435 and 4 or 2,w)
        imgui.Separator()
        V.muted('Рынок: '..tostring(DSP.market.state.status or 'неизвестно')..
            ' · сервер: '..tostring(DSP.market.state.sid or '?'))
        V.muted('Предложения API — снимки, не подтверждённые сделки.')
        V.muted('Лавка — мои объявления; Лавки — чужие предложения.')
    end,{footer=false})
end

local more={
    {'Арбитраж','arbitrage','R'}, {'Перепродажа','resale','$'},
    {'Автопиар','promo','A'}, {'Ломбард','lombard','L'},
    {'Хранилища','storage','H'}, {'Скан лавки','scan','S'},
    {'Статистика','stats','%'}, {'Калькулятор','calculator','+'},
    {'Цены','market','P'}, {'Поиск','search','?'},
    {'Заметки','notes','N'}, {'История','history','J'},
    {'Обновления','updates','U'}, {'Настройки','settings','*'},
}
function V.more()
    V.heading('Ещё')
    V.muted('Все инструменты Palatka AI. Разделы без отдельного дублирующего меню.')
    local w=imgui.GetContentRegionAvail().x
    if V.button('Первая страница','mcr_more_1',(w-6)/2,V.more_page~=2,false,30) then V.more_page=1 end
    V.inline(6)
    if V.button('Вторая страница','mcr_more_2',(w-6)/2,V.more_page==2,false,30) then V.more_page=2 end
    local p=V.more_page or 1
    V.list('mcr_more_tiles',function(rw)
        local page={}
        for i=(p-1)*8+1,math.min(#more,p*8)do page[#page+1]=more[i]end
        tiles('more_'..p,page,rw>=435 and 4 or 2,rw)
    end,{footer=false})
end

-- Keep the existing detail, scan, pin and confirmation actions, but make
-- browsing the two economic directions possible without swapping screens.
-- sell = other player sells -> I BUY (expense).
-- buy  = other player buys  -> I SELL (income).
local market_cache={}
local function render_market_side(mode,items,width)
    local label=mode=='sell'and'Продажа в лавках (купить)'or'Скупка в лавках (продать)'
    V.text(V.fit(label,width-8))
    imgui.Separator()
    local listkey='mcr_market_'..mode
    V.list_rows(listkey,items,72,function(group,i)
        V.row(listkey..'_'..i,72,function(w,x,y)
            local title=V.fit(group.row.display or '?',w-7)
            V.at(x,y)
            if V.text_button(title,listkey..'_open_'..i,w,false,32)then
                V.shops_source='api'
                V.shops_mode=mode
                V.shop_item=group.row.key
                V.reset_list('shop_offers_'..mode)
            end
            V.at(x,y+31)
            V.muted(V.fit((group.shops or 0)..' лавок · '..tostring(group.count or 0)..
                ' предложений',w))
            V.at(x,y+49)
            V.muted(V.fit('От '..DSP.money(group.best or 0)..'/шт. · API',w))
        end)
    end,{footer=false})
end
local function dual_market()
    local st=DSP.market and DSP.market.state or {}
    V.heading('Чужие лавки',function()
        if V.button('Обновить','mcr_market_refresh',108,false,true,33)then
            if DSP.market and DSP.market.pull and st.status~='loading' then DSP.market.pull(st.sid)end
        end
    end,115)
    local region=imgui.GetContentRegionAvail()
    V.muted(V.fit('Сервер: '..tostring(st.sid or '?')..
        ' · '..tostring(DSP.market.freshness and DSP.market.freshness()or 'без данных')..
        ' · API не подтверждает текущие остатки',region.x))
    if st.error then V.red(V.fit('Ошибка API: '..tostring(st.error),region.x))end
    local q,edited=V.search('mcr_market','Название, владелец или номер лавки',-1)
    if edited then
        V.reset_list('mcr_market_sell')
        V.reset_list('mcr_market_buy')
    end
    local signature=table.concat({tostring(st.sid),tostring(st.version),
        tostring(st.rows),q,tostring(V.shops_sort)},'|')
    if market_cache.signature~=signature then
        -- Shops_result historically held a single-mode cache. Request both
        -- modes explicitly and keep snapshots separate for this screen.
        V.shops_stamp=nil
        local sells=V.shops_result(st.rows or{},'sell',q,st.version)
        V.shops_stamp=nil
        local buys=V.shops_result(st.rows or{},'buy',q,st.version)
        market_cache={signature=signature,sell=sells,buy=buys}
    end
    local space=imgui.GetContentRegionAvail()
    local half=math.max(95,math.floor((space.x-7)/2))
    local height=math.max(45,space.y-4)
    if imgui.BeginChild('##mcr_side_sell',imgui.ImVec2(half,height),true)then
        V.apply_font()
        render_market_side('sell',market_cache.sell or{},half)
    end
    imgui.EndChild()
    V.inline(7)
    if imgui.BeginChild('##mcr_side_buy',imgui.ImVec2(0,height),true)then
        V.apply_font()
        render_market_side('buy',market_cache.buy or{},math.max(85,space.x-half-7))
    end
    imgui.EndChild()
end

-- Small right context rail modeled after the reference screenshot.
-- All tiles invoke existing business logic, never pretend a server accepted a trade.
function V.context_actions()
    local actions={}
    local function add(label,symbol,callback)
        actions[#actions+1]={label,symbol,callback}
    end
    if V.screen=='palatka' then
        add('Поиск','?',function()V.tab='items' end)
        add('Выставить','+',function()
            if DSP.auto.sell_running or DSP.auto.buy_running then return end
            V.open_popup('Выставление','launch')
        end)
        add('Обновить','R',function()
            if not (DSP.auto.sell_running or DSP.auto.buy_running) then
                DSP.auto.scan_inventory()
            end
        end)
        add('Пресеты','P',function()V.open_popup('Наборы','presets')end)
        if DSP.auto.sell_running or DSP.auto.buy_running then
            add('Стоп','X',function()
                if DSP.auto.sell_running then DSP.auto.stop_sell()
                else DSP.auto.stop_buy()end
            end)
        end
    elseif V.screen=='lavki' or V.screen=='market' then
        add('Поиск','?',function()
            V.shop_item=nil;V.shop_detail=nil;V.shops_source='api'
        end)
        add('Обновить','R',function()
            local st=DSP.market.state
            if st.status~='loading' then DSP.market.pull(st.sid)end
        end)
        add('Скан','S',function()
            V.shops_source='scan';V.shop_item=nil;V.shop_detail=nil
        end)
    elseif V.screen=='logs' then
        add('История','J',function()V.set_screen('history')end)
        add('Статистика','%',function()V.set_screen('stats')end)
    elseif V.screen=='more' then
        add('Настройки','*',function()V.set_screen('settings')end)
        add('Обновления','U',function()go('updates')end)
    end
    local w=math.max(39,imgui.GetContentRegionAvail().x)
    local x0,y0=imgui.GetCursorPosX(),imgui.GetCursorPosY()
    for i,e in ipairs(actions)do
        local y=y0+(i-1)*65
        V.at(x0,y)
        if V.button(e[2],'mcr_rail_'..V.screen..'_'..i,w,false,false,36)then e[3]()end
        V.at(x0,y+38)
        V.muted(V.fit(e[1],w-2))
    end
    V.at(x0,y0+#actions*65)
end

if type(old_shops)=='function' then
    V.shops=function(...)
        V.shops_source=V.shops_source or 'api'
        if V.shops_source=='scan' or V.shop_item or V.shop_detail
            or imgui.GetContentRegionAvail().x<450 then
            return old_shops(...)
        end
        return dual_market()
    end
end
return true
}, {'Чужие лавки','lavki','N'},
    {'Логи','logs','J'}, {'Калькулятор','calculator','+'},
}
function V.home()
    V.heading('Palatka AI',function()
        if V.button('Обновить рынок','mcr_home_refresh',145,false,true,33)then
            if DSP.market and DSP.market.pull and DSP.market.state.status~='loading' then
                DSP.market.pull(DSP.detect_server() or DSP.market.state.sid or DSP.settings.server)
            end
        end
    end,155)
    V.list('mcr_home_tiles',function(w)
        tiles('home',home,w>=435 and 4 or 2,w)
        imgui.Separator()
        V.muted('Рынок: '..tostring(DSP.market.state.status or 'неизвестно')..
            ' · сервер: '..tostring(DSP.market.state.sid or '?'))
        V.muted('Предложения API — снимки, не подтверждённые сделки.')
        V.muted('Лавка — мои объявления; Лавки — чужие предложения.')
    end,{footer=false})
end

local more={
    {'Арбитраж','arbitrage','R'}, {'Перепродажа','resale','$'},
    {'Автопиар','promo','A'}, {'Ломбард','lombard','L'},
    {'Хранилища','storage','H'}, {'Скан лавки','scan','S'},
    {'Статистика','stats','%'}, {'Калькулятор','calculator','+'},
    {'Цены','market','P'}, {'Поиск','search','?'},
    {'Заметки','notes','N'}, {'История','history','J'},
    {'Обновления','updates','U'}, {'Настройки','settings','*'},
}
function V.more()
    V.heading('Ещё')
    V.muted('Все инструменты Palatka AI. Разделы без отдельного дублирующего меню.')
    local w=imgui.GetContentRegionAvail().x
    if V.button('Первая страница','mcr_more_1',(w-6)/2,V.more_page~=2,false,30) then V.more_page=1 end
    V.inline(6)
    if V.button('Вторая страница','mcr_more_2',(w-6)/2,V.more_page==2,false,30) then V.more_page=2 end
    local p=V.more_page or 1
    V.list('mcr_more_tiles',function(rw)
        local page={}
        for i=(p-1)*8+1,math.min(#more,p*8)do page[#page+1]=more[i]end
        tiles('more_'..p,page,rw>=435 and 4 or 2,rw)
    end,{footer=false})
end

-- Keep the existing detail, scan, pin and confirmation actions, but make
-- browsing the two economic directions possible without swapping screens.
-- sell = other player sells -> I BUY (expense).
-- buy  = other player buys  -> I SELL (income).
local market_cache={}
local function render_market_side(mode,items,width)
    local label=mode=='sell'and'Продажа в лавках (купить)'or'Скупка в лавках (продать)'
    V.text(V.fit(label,width-8))
    imgui.Separator()
    local listkey='mcr_market_'..mode
    V.list_rows(listkey,items,72,function(group,i)
        V.row(listkey..'_'..i,72,function(w,x,y)
            local title=V.fit(group.row.display or '?',w-7)
            V.at(x,y)
            if V.text_button(title,listkey..'_open_'..i,w,false,32)then
                V.shops_source='api'
                V.shops_mode=mode
                V.shop_item=group.row.key
                V.reset_list('shop_offers_'..mode)
            end
            V.at(x,y+31)
            V.muted(V.fit((group.shops or 0)..' лавок · '..tostring(group.count or 0)..
                ' предложений',w))
            V.at(x,y+49)
            V.muted(V.fit('От '..DSP.money(group.best or 0)..'/шт. · API',w))
        end)
    end,{footer=false})
end
local function dual_market()
    local st=DSP.market and DSP.market.state or {}
    V.heading('Чужие лавки',function()
        if V.button('Обновить','mcr_market_refresh',108,false,true,33)then
            if DSP.market and DSP.market.pull and st.status~='loading' then DSP.market.pull(st.sid)end
        end
    end,115)
    local region=imgui.GetContentRegionAvail()
    V.muted(V.fit('Сервер: '..tostring(st.sid or '?')..
        ' · '..tostring(DSP.market.freshness and DSP.market.freshness()or 'без данных')..
        ' · API не подтверждает текущие остатки',region.x))
    if st.error then V.red(V.fit('Ошибка API: '..tostring(st.error),region.x))end
    local q,edited=V.search('mcr_market','Название, владелец или номер лавки',-1)
    if edited then
        V.reset_list('mcr_market_sell')
        V.reset_list('mcr_market_buy')
    end
    local signature=table.concat({tostring(st.sid),tostring(st.version),
        tostring(st.rows),q,tostring(V.shops_sort)},'|')
    if market_cache.signature~=signature then
        -- Shops_result historically held a single-mode cache. Request both
        -- modes explicitly and keep snapshots separate for this screen.
        V.shops_stamp=nil
        local sells=V.shops_result(st.rows or{},'sell',q,st.version)
        V.shops_stamp=nil
        local buys=V.shops_result(st.rows or{},'buy',q,st.version)
        market_cache={signature=signature,sell=sells,buy=buys}
    end
    local space=imgui.GetContentRegionAvail()
    local half=math.max(95,math.floor((space.x-7)/2))
    local height=math.max(45,space.y-4)
    if imgui.BeginChild('##mcr_side_sell',imgui.ImVec2(half,height),true)then
        V.apply_font()
        render_market_side('sell',market_cache.sell or{},half)
    end
    imgui.EndChild()
    V.inline(7)
    if imgui.BeginChild('##mcr_side_buy',imgui.ImVec2(0,height),true)then
        V.apply_font()
        render_market_side('buy',market_cache.buy or{},math.max(85,space.x-half-7))
    end
    imgui.EndChild()
end

if type(old_shops)=='function' then
    V.shops=function(...)
        V.shops_source=V.shops_source or 'api'
        if V.shops_source=='scan' or V.shop_item or V.shop_detail
            or imgui.GetContentRegionAvail().x<450 then
            return old_shops(...)
        end
        return dual_market()
    end
end
return true
