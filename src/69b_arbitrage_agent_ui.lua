-- Palatka AI arbitration companion: native Carbon controls, compact game-safe panel.
-- All trades remain manually acknowledged; no packet, teleport or server automation.
local A,M,V=DSP.arb_agent,DSP.market,DSP.ui22
local function u(s)return DSP.utf8(tostring(s or ''))end
local function label(s)imgui.Text(u(s))end
local function quiet(s)imgui.TextDisabled(u(s))end
local function green(s)imgui.TextColored(DSP.theme.col('good',1),u(s))end
local function red(s)imgui.TextColored(DSP.theme.col('bad',1),u(s))end
local function b(name,id,w,active) return V.button(name,'agent291_'..id,w,active,false,38)end
local function money(v)return DSP.money(tonumber(v)or 0)end
local function selected(s)
    local index=math.max(1,math.min(tonumber(s.focus)or 1,#s.routes))
    return s.routes[index],index
end
local function status(e)
    if e.unavailable_reason=='shop_missing' then return 'Нет лавки' end
    if e.unavailable_reason=='item_missing' then return 'Нет предмета' end
    if e.unavailable_reason=='owner_changed' then return 'Смена владельца' end
    if e.skipped then return 'Пропущено' end
    if e.sold>=e.qty then return 'Завершено' end
    if e.bought<e.qty then return 'Покупка' end
    return 'Продажа'
end
local function rect(io)
    DSP.settings.arb_agent_window=DSP.settings.arb_agent_window or{}
    local p=DSP.settings.arb_agent_window
    local sw,sh=io.DisplaySize.x,io.DisplaySize.y
    local w=DSP.clamp(tonumber(p.w)or 440,math.min(305,sw-16),math.max(305,sw-16))
    local h=DSP.clamp(tonumber(p.h)or 390,math.min(250,sh-16),math.max(250,sh-16))
    return {w=w,h=h,x=DSP.clamp(tonumber(p.x)or(sw-w-12),0,math.max(0,sw-w)),
        y=DSP.clamp(tonumber(p.y)or 110,0,math.max(0,sh-h))}
end
local function drag(g,io,resize)
    local d=io.MouseDelta
    if not d or (d.x==0 and d.y==0) then return end
    local w=resize and DSP.clamp(g.w+d.x,math.min(305,io.DisplaySize.x-16),io.DisplaySize.x-g.x)or g.w
    local h=resize and DSP.clamp(g.h+d.y,math.min(250,io.DisplaySize.y-16),io.DisplaySize.y-g.y)or g.h
    local x=resize and g.x or DSP.clamp(g.x+d.x,0,io.DisplaySize.x-w)
    local y=resize and g.y or DSP.clamp(g.y+d.y,0,io.DisplaySize.y-h)
    DSP.settings.arb_agent_window={x=x,y=y,w=w,h=h}
    A._geometry_dirty=true
end
local function notice(msg)A.ui_message=msg end
local function route_queue(s)
    local total=#s.routes
    if total==0 then return end
    local pages=math.max(1,math.ceil(total/4))
    A.queue_page=DSP.clamp(tonumber(A.queue_page)or 1,1,pages)
    quiet('Маршруты: '..total..'  |  Страница '..A.queue_page..'/'..pages)
    local from=(A.queue_page-1)*4+1
    for i=from,math.min(total,from+3)do
        local e=s.routes[i]
        if b(V.fit(i..'. '..e.name..' · '..status(e),math.max(100,imgui.GetContentRegionAvail().x-20)),
            'route_'..i,-1,s.focus==i)then
            A.focus(i);A.qty_key=nil
        end
    end
    if pages>1 then
        if b('Ранее','pageprev',110)then A.queue_page=math.max(1,A.queue_page-1)end
        imgui.SameLine(0,8)
        if b('Далее','pagenext',110)then A.queue_page=math.min(pages,A.queue_page+1)end
    end
end
local function route_info(e,index,total)
    if not e then quiet('Новых маршрутов пока нет');return end
    quiet('Сделка '..index..' из '..total..' · '..status(e))
    label(V.fit(e.name,math.max(120,imgui.GetContentRegionAvail().x-12)))
    quiet('План '..e.qty..' шт.  |  Ожидаемая прибыль ~ '..money(e.proposed_profit))
    quiet('Куплено '..e.bought..' · Продано '..e.sold)
    if e.skipped then
        if e.bought>e.sold then red('Товаров на руках: '..(e.bought-e.sold)..' шт.')end
        quiet('Маршрут остаётся в сессии. Можно вернуть его или перейти дальше.')
        local half=math.max(105,math.floor((imgui.GetContentRegionAvail().x-6)/2))
        if b('Вернуть маршрут','restore',half)then
            local ok,err
            if e.unavailable_reason then ok,err=A.restore_unavailable(index)else ok=A.skip(index,false)end
            notice(ok and 'Маршрут снова активен' or tostring(err or 'Не удалось вернуть маршрут'))
        end
        imgui.SameLine(0,6)
        if b('Следующий','skipped_next',half)then A.next(1);A.qty_key=nil end
        return
    end
    if e.sold>=e.qty then green('Сделка завершена');return end
    local buying=e.bought<e.qty
    local side=buying and 'buy' or 'sell'
    local shop=buying and e.seller_shop or e.buyer_shop
    local owner=buying and e.seller_owner or e.buyer_owner
    local price=buying and e.buy_price or e.sell_price
    local remaining=buying and(e.qty-e.bought)or(e.bought-e.sold)
    if remaining<=0 then return end
    green(buying and 'Купить' or 'Продать')
    label('Лавка #'..shop..' · '..tostring(owner or'?'))
    quiet('Осталось '..remaining..' шт.  |  '..money(price)..' / шт.')
    if b('Метка на лавку #'..shop,'mark',-1)then
        if not M.mark_shop(shop)then notice('Метка недоступна')end
    end
    if b('Нет лавки','missing_shop',145)then
        local ok,err=A.mark_unavailable(index,'shop')
        notice(ok and 'Лавка исключена из планов' or tostring(err))
    end
    imgui.SameLine(0,6)
    if b('Нет предмета','missing_item',160)then
        local ok,err=A.mark_unavailable(index,'item')
        notice(ok and 'Предложение исключено' or tostring(err))
    end
    local key=e.id..':'..side
    if A.qty_key~=key then A.qty_key=key;A.qty_field=imgui.new.int(remaining)end
    quiet('Подтверждение количества:')
    imgui.SetNextItemWidth(math.min(160,imgui.GetContentRegionAvail().x))
    imgui.InputInt('##agent291_qty',A.qty_field,1,10)
    if b(buying and 'Подтвердить покупку' or 'Подтвердить продажу','confirm',-1,true)then
        local ok,err=A.confirm(index,side,A.qty_field[0])
        if ok then A.qty_key=nil;notice('Количество записано')else notice(tostring(err))end
    end
    local hint=A.hint
    if hint and hint.route_id==e.id and hint.side==side then
        quiet('Обнаружен похожий чек: '..hint.qty..' шт.')
        if b('Принять данные чека','receipt',-1)then
            local ok,err=A.confirm(index,side,hint.qty)
            if ok then A.qty_key=nil;notice('Чек подтверждён')else notice(tostring(err))end
        end
    end
end
function A.draw()
    local s=A.active()
    if not s then A.show(false);return end
    if A.review_market then A.review_market()end
    local io=imgui.GetIO()
    local g=rect(io)
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(.94)
    local color_count=DSP.theme.push_window()
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(9,8))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(6,6))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,9)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse
    if imgui.Begin('##palatka_arbitrage_agent',nil,flags)then
        if V.apply_font then V.apply_font()end
        if b('Арбитраж · переместить','handle',math.max(100,g.w-112))then end
        if imgui.IsItemActive() and io.MouseDelta then drag(g,io,false)end
        imgui.SameLine(0,5)
        if b(A.queue_expanded and '-' or '+','queue',40)then A.queue_expanded=not A.queue_expanded end
        imgui.SameLine(0,5)
        if b('X','close',43)then A.show(false)end
        local st=A.stats()
        quiet('Завершено '..st.done..'/'..st.routes..' · В работе '..st.pending)
        green('Ожидаемый результат ~ '..money(st.profit_estimate))
        quiet('Мини-агент Palatka / сборка 2.9.2')
        imgui.Separator()
        if A.queue_expanded then
            route_queue(s)
            if not A.end_confirm then
                if b('Закончить сессию','end',-1)then A.end_confirm=true end
            else
                red('Завершить сессию?')
                if b('Завершить','endyes',140)then A.stop();A.end_confirm=false end
                imgui.SameLine(0,5)
                if b('Отмена','endno',130)then A.end_confirm=false end
            end
            imgui.Separator()
        end
        if imgui.BeginChild('##agent291_content',imgui.ImVec2(0,-80),false,imgui.WindowFlags.NoScrollbar)then
            local e,i=selected(s)
            route_info(e,i,#s.routes)
            if DSP.mobile and DSP.mobile.touch_scroll then DSP.mobile.touch_scroll(io,'arb_agent_content')end
        end
        imgui.EndChild()
        if A.ui_message then quiet(V.fit(A.ui_message,math.max(120,g.w-35)))end
        if A.save_error then red('Не сохранено: '..tostring(A.save_error))end
        if b('< Предыдущая','prev',math.max(105,math.floor((g.w-36)/2)))then A.next(-1);A.qty_key=nil end
        imgui.SameLine(0,6)
        if b('Следующая >','next',math.max(105,math.floor((g.w-36)/2)))then A.next(1);A.qty_key=nil end
        -- Native ImGui drag-resize grip, visually aligned to Palatka corners.
        imgui.SetCursorPos(imgui.ImVec2(g.w-39,g.h-36))
        if b('//','resize',29)then end
        if imgui.IsItemActive()and io.MouseDelta then drag(g,io,true)end
    end
    imgui.End()
    imgui.PopStyleVar(3)
    if color_count and color_count>0 then imgui.PopStyleColor(color_count)end
    if A._geometry_dirty and not imgui.IsMouseDown(0)then
        A._geometry_dirty=false
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
    end
end
return true
