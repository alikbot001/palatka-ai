-- Carbon Trade 02: real landing screen with persistent sections and action tiles.
local V=DSP.ui21
local function metrics()
    local ok,r=pcall(function()return DSP.craglog.summary('day')end)
    return ok and type(r)=='table'and r or {}
end
function V.home()
    V.heading('Главная',function()
        if V.button('Обновить','carbon_refresh',126,false,true)then
            if DSP.market and DSP.market.state.status~='loading' then
                DSP.market.pull(DSP.detect_server() or DSP.market.state.sid or DSP.settings.server)
            end
        end
    end,130)
    V.list('carbon_home',function(w)
        V.muted('Обзор · данные игры и рынка; отсутствие источника не заменяется демонстрацией')
        local cw=math.max(90,(w-8)/3)
        if V.button('Найти сделку','carbon_quick_arb',cw,false,true)then V.set_screen('arbitrage')end
        V.inline(4)
        if V.button('Моя лавка','carbon_quick_shop',cw)then V.set_screen('lavki')end
        V.inline(4)
        if V.button('Сканировать','carbon_quick_storage',cw)then V.set_screen('scan')end
        imgui.Separator()
        local r=metrics()
        local cards={
            {'Денежный итог сегодня',r.net and DSP.money(r.net)or'Нет данных', 'из журнала'},
            {'Получено денег',r.income and DSP.money(r.income)or'Нет данных','это не прибыль'},
            {'Расходы',r.expense and DSP.money(r.expense)or'Нет данных','по журналу'},
            {'Рыночных позиций',tostring(#((DSP.market and DSP.market.state.rows)or{})),DSP.market.freshness()},
        }
        for i=1,4,2 do
            local cw2=math.max(90,(w-9)/2)
            for n=0,1 do
                local c=cards[i+n]
                if imgui.BeginChild('##carbon_metric_'..(i+n),imgui.ImVec2(cw2,91),true,imgui.WindowFlags.NoScrollbar)then
                    V.apply_font()
                    V.muted(V.fit(c[1],cw2-25))
                    V.green(V.fit(c[2],cw2-25))
                    V.muted(V.fit(c[3],cw2-25))
                    if imgui.GetWindowDrawList and imgui.GetWindowPos and imgui.GetColorU32 then
                        local dl=imgui.GetWindowDrawList()
                        local pos=imgui.GetWindowPos()
                        if dl and dl.AddLine then
                            dl:AddLine(imgui.ImVec2(pos.x+1,pos.y+1),imgui.ImVec2(pos.x+cw2-2,pos.y+1),
                                imgui.GetColorU32(imgui.Col.CheckMark),2)
                        end
                    end
                end
                imgui.EndChild()
                if n==0 then V.inline(8)end
            end
        end
        V.text('Быстрый доступ')
        local links={{'Арбитраж','arbitrage'},{'Продажа / скупка','palatka'},
            {'Скан лавки','scan'},{'Перепродажа','resale'},
            {'Авто-пиар','promo'},{'Журнал','logs'}}
        local cols=w>=560 and 3 or 2
        local cell=(w-8*(cols-1))/cols
        for i,entry in ipairs(links)do
            if V.button(entry[1],'carbon_link_'..i,cell)then V.set_screen(entry[2])end
            if i%cols~=0 and i<#links then V.inline(8)end
        end
        imgui.Separator()
        V.text('Последние события')
        local recent=DSP.craglog and DSP.craglog.ring_recent and DSP.craglog.ring_recent(4) or {}
        if #recent==0 then V.muted('Записей за сессию пока нет')end
        for j=#recent,1,-1 do
            local event=recent[j]
            if event then
                V.row('carbon_recent_'..j,43,function(ww,x,y)
                    V.at(x,y);V.muted(V.fit(os.date('%H:%M',event.ts or os.time())..' · '..
                        tostring((DSP.craglog.describe and DSP.craglog.describe(event)) or event.kind or 'Событие'),ww-12))
                end)
            end
        end
        imgui.Separator()
        V.text('Состояние системы')
        local st=DSP.market.state
        V.muted('API: '..tostring(st.status or '?')..' · Сервер: '..tostring(st.sid or '?'))
        V.muted('Данные могут устареть. Рыночная стоимость имущества не равна заработку.')
        if V.button('Цены / источники','carbon_link_prices',w)then V.set_screen('resale');V.flip_tab='prices'end
    end,{footer=function() V.muted('Carbon Trade · Главная · данные без вымысла')end})
end
