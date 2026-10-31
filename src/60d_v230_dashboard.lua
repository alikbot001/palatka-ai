-- v2.3.0 unified dashboard. Keep the useful subsystems, but make the home
-- screen answer the questions a trader has immediately: which stall, was it
-- scanned, what can I do next, and what happened recently.
local V=DSP.ui21
local function metric(period)
    local ok,r=pcall(function() return DSP.craglog.summary(period or 'day') end)
    return ok and type(r)=='table' and r or {}
end
local function identity_status()
    local shop=DSP.live and DSP.live.shop or {}
    if DSP.shop_identity and DSP.shop_identity.resolve and (#(shop.sell or {})+#(shop.buy or {}))>0 then
        pcall(DSP.shop_identity.resolve,shop)
    end
    local n=tonumber(shop.num)
    local owner=tostring(shop.owner or '')
    if n then return '#'..tostring(n),tostring(shop.num_source or 'packet'),owner end
    if DSP.shop_identity and DSP.shop_identity.own_shop_number then
        local ok,num,src=pcall(DSP.shop_identity.own_shop_number)
        if ok and num then return '#'..tostring(num),tostring(src or 'saved'),owner end
    end
    return '—','не определён',owner
end
local function scan_stats()
    if DSP.local_arb and DSP.local_arb.stats then
        local ok,r=pcall(DSP.local_arb.stats,os.time())
        if ok and type(r)=='table' then return r end
    end
    return {shops=0,offers=0,mapped=0,unmapped=0}
end
local function small_card(id,title,value,sub,w)
    if imgui.BeginChild('##v230_card_'..id,imgui.ImVec2(w,84),true,imgui.WindowFlags.NoScrollbar) then
        V.apply_font()
        V.muted(V.fit(title,w-18))
        V.green(V.fit(value,w-18))
        V.muted(V.fit(sub or '',w-18))
    end
    imgui.EndChild()
end
function V.home()
    V.heading('Palatka AI · Центр',function()
        if V.button('Обновить рынок','v230_refresh',126,false,true) and DSP.market and DSP.market.state.status~='loading' then
            DSP.market.pull(DSP.detect_server() or DSP.market.state.sid or DSP.settings.server)
        end
    end,140)
    V.list('v230_home',function(w)
        local stall,stall_src,owner=identity_status()
        local ss=scan_stats()
        local r=metric('day')
        local compact=V.compact(w)
        local cols=compact and 2 or 4
        local gap=6
        local cw=math.max(92,(w-gap*(cols-1))/cols)
        local cards={
            {'stall','Текущая лавка',stall,stall_src},
            {'scans','Мои сканы',tostring(ss.shops or 0)..' лавок',tostring(ss.offers or 0)..' предложений'},
            {'mapped','С номерами',tostring(ss.mapped or 0),tostring(ss.unmapped or 0)..' без ID'},
            {'net','Учёт сегодня',r.net and DSP.money(r.net) or '—','чистый денежный итог'},
        }
        for i,c in ipairs(cards) do
            small_card(c[1],c[2],c[3],c[4],cw)
            if i%cols~=0 and i<#cards then V.inline(gap,cw) end
        end

        imgui.Spacing()
        local live=DSP.live and DSP.live.shop or {}
        local state,items=DSP.live and DSP.live.scan_state and DSP.live.scan_state(live)
        if state=='saved' then V.green('Автоскан: сохранено · '..tostring(items or 0)..' позиций')
        elseif state=='saved_unmapped' then V.green('Автоскан: сохранено без номера · '..tostring(items or 0)..' позиций')
        elseif state=='pending' then V.muted('Автоскан: получаю пакет лавки...')
        elseif state=='disabled' then V.red('Автоскан выключен')
        elseif (items or 0)>0 then V.muted('Автоскан: '..tostring(state or 'ожидание')..' · '..tostring(items)..' позиций')
        else V.muted('Подойди к лавке и открой её — скан сохранится автоматически') end
        if owner~='' then V.muted(V.fit('Владелец: '..owner,w)) end

        imgui.Separator()
        V.text('Основные действия')
        local actions={
            {'Торговля','palatka'},{'Мои сканы','scan'},{'Арбитраж','arbitrage'},
            {'Моя лавка','lavki'},{'Авто-пиар','promo'},{'Журнал','logs'},
        }
        local acols=compact and 2 or 3
        local aw=math.max(90,(w-gap*(acols-1))/acols)
        for i,a in ipairs(actions) do
            if V.button(a[1],'v230_go_'..a[2],aw,a[2]=='palatka',a[2]=='palatka') then V.set_screen(a[2]) end
            if i%acols~=0 and i<#actions then V.inline(gap,aw) end
        end

        imgui.Separator()
        V.text('Торговля')
        local mode=(DSP.settings and DSP.settings.dry_run) and 'ТЕСТ' or 'РЕАЛЬНО'
        local inv=#((DSP.auto and DSP.auto.inv) or {})
        local trade=DSP.auto and DSP.auto.status or 'готово'
        V.muted(V.fit('Режим: '..mode..' · инвентарь: '..tostring(inv)..' · '..tostring(trade),w))
        local tw=math.max(110,(w-6)/2)
        if V.button('Продажа по пресету','v230_sell',tw,false,true) then
            if DSP.auto and DSP.auto.safe_start then DSP.auto.safe_start('sell') end
        end
        V.inline(6,tw)
        if V.button('Скупка по пресету','v230_buy',tw,false,true) then
            if DSP.auto and DSP.auto.safe_start then DSP.auto.safe_start('buy') end
        end

        imgui.Separator()
        V.text('Последние события')
        local recent=DSP.craglog and DSP.craglog.ring_recent and DSP.craglog.ring_recent(compact and 3 or 5) or {}
        if #recent==0 then V.muted('Пока нет записей в мини-журнале') end
        for j=#recent,1,-1 do
            local e=recent[j]
            if e then
                V.row('v230_evt_'..j,40,function(ww,x,y)
                    V.at(x,y+2)
                    local desc=(DSP.craglog.describe and DSP.craglog.describe(e)) or e.kind or 'Событие'
                    V.muted(V.fit(os.date('%H:%M',e.ts or os.time())..' · '..tostring(desc),ww-6))
                end)
            end
        end

        imgui.Separator()
        local st=DSP.market and DSP.market.state or {}
        V.muted(V.fit('API: '..tostring(st.status or '?')..' · сервер: '..tostring(st.sid or '?')
            ..' · авто-пиар: '..((DSP.promo and DSP.promo.running) and 'включён' or 'выключен'),w))
    end,{footer=function()
        V.muted('Palatka AI v'..tostring(DSP.version)..' · локальные сканы отдельно от API')
    end})
end
return true