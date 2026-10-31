-- Compact floating assistant for an entire arbitrage session (not one route).
-- Controls never send trades; all execution acknowledgement is explicit.
local A=DSP.arb_agent
local M=DSP.market
local U=DSP.ui
local V=DSP.ui22
local function cp(v)return DSP.utf8(tostring(v or''))end
local function btn(label,id,w,h)
    return imgui.Button(cp(label)..'##arb_agent_'..id,imgui.ImVec2(w or -1,h or 34))
end
local function text(s)imgui.Text(cp(s))end
local function muted(s)imgui.TextDisabled(cp(s))end
local function good(s)imgui.TextColored(DSP.theme.col('good',1),cp(s))end
local function bad(s)imgui.TextColored(DSP.theme.col('bad',1),cp(s))end
local function fmt(n)return DSP.money(tonumber(n)or 0)end
local function notify(msg)
    A.ui_message=tostring(msg or'')
    if DSP.flog then DSP.flog('ARB AGENT: '..A.ui_message)end
end
local function selected(s)
    local i=math.min(math.max(1,tonumber(s.focus)or 1),math.max(1,#s.routes))
    return s.routes[i],i
end
local function flag(e)
    if e.skipped then return 'ПРОПУЩЕНО' end
    if e.sold==e.qty then return 'ЗАВЕРШЕНО' end
    if e.bought==0 then return 'КУПИТЬ' end
    if e.bought<e.qty then return 'ДОКУПИТЬ' end
    return 'СДАТЬ'
end
local function geometry(sw,sh)
    local p=DSP.settings.arb_agent_window or{}
    local maxw=math.max(220,sw-16)
    local maxh=math.max(180,sh-16)
    local w=DSP.clamp(tonumber(p.w)or math.min(360,maxw),math.min(280,maxw),maxw)
    local h=DSP.clamp(tonumber(p.h)or math.min(440,maxh),math.min(280,maxh),maxh)
    return {w=w,h=h,x=DSP.clamp(tonumber(p.x)or(sw-w-10),0,math.max(0,sw-w)),
        y=DSP.clamp(tonumber(p.y)or math.max(8,sh*.16),0,math.max(0,sh-h))}
end
local function save_geometry(g,dx,dy,dw,dh,io)
    local sw,sh=io.DisplaySize.x,io.DisplaySize.y
    local x=DSP.clamp(g.x+(dx or 0),0,math.max(0,sw-g.w))
    local y=DSP.clamp(g.y+(dy or 0),0,math.max(0,sh-g.h))
    local w=DSP.clamp(g.w+(dw or 0),math.min(280,sw-16),sw-x)
    local h=DSP.clamp(g.h+(dh or 0),math.min(280,sh-16),sh-y)
    DSP.settings.arb_agent_window={x=x,y=y,w=w,h=h}
    if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
end
local function header(s,g,io)
    local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
    if btn('АРБИТРАЖ / MOVE','drag',math.max(65,g.w-119),32)then end
    if imgui.IsItemActive()and io.MouseDelta then
        local d=io.MouseDelta
        if d.x~=0 or d.y~=0 then save_geometry(g,d.x,d.y,0,0,io)end
    end
    imgui.SameLine(0,4)
    if btn(A.queue_expanded and '−' or '+','queue_toggle',33,32)then
        A.queue_expanded=not A.queue_expanded
    end
    imgui.SameLine(0,4)
    if btn('X','close',34,32)then A.show(false)end
end
local function summary(s)
    local st=A.stats()
    good('Сделок: '..st.done..' / '..st.routes..'  |  В работе: '..st.pending)
    text('Куплено: '..st.bought..'  ·  Сдано: '..st.sold)
    good('Прибыль ~ '..fmt(st.profit_estimate))
    muted('Расчёт по ценам плана, не подтверждённая касса')
    local updated=M.state and M.state.updated or 0
    muted('API: '..(M.freshness and M.freshness()or'нет данных')..' · обзор каждые 60 с')
end
local function queue(s)
    local visible={}
    for i,e in ipairs(s.routes)do
        if not e.skipped and e.sold<e.qty then visible[#visible+1]=i end
    end
    if #visible==0 then
        good('Активных маршрутов нет. Новые появятся при обновлении.')
        return
    end
    local take=math.min(6,#visible)
    for j=1,take do
        local i=visible[j]
        local e=s.routes[i]
        local label=(i==s.focus and '● 'or'')..tostring(i)..'. '..e.name..
            '  '..(e.sold>0 and('сдано '..e.sold..'/'..e.qty)or flag(e))
        if btn(label,'route_'..i,-1,30)then A.focus(i);A.qty_key=nil end
    end
    if #visible>take then muted('Ещё маршрутов: '..(#visible-take)..' · переключай стрелками')end
end
-- Normal ImGui input is used intentionally: unavailable native exotic widgets
-- must not make the floating assistant impossible to close.
function A.draw()
    local s=A.active()
    if not s then A.show(false);return end
    if A.review_market then A.review_market()end
    local io=imgui.GetIO()
    local g=geometry(io.DisplaySize.x,io.DisplaySize.y)
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    local colors=DSP.theme.push_window()
    imgui.SetNextWindowBgAlpha(.90)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(7,6))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,5))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,6)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoResize+imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoScrollbar
    if imgui.Begin('##palatka_arbitrage_agent',nil,flags)then
        if imgui.SetWindowFontScale then
            imgui.SetWindowFontScale(1)
            local fs=imgui.GetFontSize()
            imgui.SetWindowFontScale(math.min(1.15,15/math.max(1,fs)))
        end
        header(s,g,io)
        imgui.Separator()
        if imgui.BeginChild('##arb_agent_scroll',imgui.ImVec2(0,-40),false)then
            summary(s)
            imgui.Separator()
            if A.queue_expanded then queue(s);imgui.Separator()end
            local e,index=selected(s)
            if e then
                text('МАРШРУТ '..index..' / '..#s.routes..' · '..flag(e))
                text(V.fit(e.name,math.max(100,imgui.GetContentRegionAvail().x-8)))
                muted('План: '..e.qty..' шт. · ожидание ~ '..fmt(e.proposed_profit))
                muted('Куплено '..e.bought..' / '..e.qty..' · Продано '..e.sold..' / '..e.qty)
                -- Confirming each step updates the local offer ledger, never cash history.
                if e.skipped then
                    if btn('Вернуть','restore',-1)then A.skip(index,false)end
                else
                    local side=e.bought<e.qty and'buy'or'sell'
                    local remaining=side=='buy'and(e.qty-e.bought)or(e.bought-e.sold)
                    if remaining>0 then
                        local shop=side=='buy'and e.seller_shop or e.buyer_shop
                        local owner=side=='buy'and e.seller_owner or e.buyer_owner
                        local unit=side=='buy'and e.buy_price or e.sell_price
                        text(side=='buy'and'КУПИТЬ' or'СДАТЬ')
                        text('Лавка #'..shop..' · '..owner)
                        text('x'..remaining..' · '..fmt(unit)..'/шт.')
                        if btn('Найти лавку #'..shop,'target',-1)then
                            if not M.mark_shop(shop)then notify('Метка недоступна')end
                        end
                        local input_key=e.id..':'..side
                        if A.qty_key~=input_key then A.qty_key=input_key;A.qty_field=imgui.new.int(remaining)end
                        muted('Подтвердить количество:')
                        imgui.SetNextItemWidth(math.min(160,imgui.GetContentRegionAvail().x))
                        imgui.InputInt('##arb_agent_qty',A.qty_field,1,10)
                        if btn(side=='buy'and'КУПЛЕНО' or'ПРОДАНО','confirm',-1,39)then
                            local ok,why=A.confirm(index,side,A.qty_field[0])
                            if ok then A.qty_key=nil;notify('Подтверждено: '..e.name)
                            else notify(tostring(why))end
                        end
                        local hint=A.hint
                        if hint and hint.route_id==e.id and hint.side==side then
                            muted('Похожий чек: '..hint.qty..' шт. (не автозачёт)')
                            if btn('Подтвердить чек','accept_receipt',-1)then
                                local ok,why=A.confirm(index,side,hint.qty)
                                if ok then A.qty_key=nil;notify('Чек подтверждён')
                                else notify(tostring(why))end
                            end
                        end
                    else good('Маршрут выполнен')end
                end
            else
                muted('Маршруты появятся после сканирования рынка')
            end
        end
        imgui.EndChild()
        if A.ui_message then muted(V.fit(A.ui_message,math.max(80,g.w-32)))end
        if btn('◀','previous',47,30)then A.next(-1);A.qty_key=nil end
        imgui.SameLine(0,5)
        if btn('▶','next',47,30)then A.next(1);A.qty_key=nil end
        imgui.SameLine(0,5)
        local e,i=selected(s)
        if e and btn('Пропустить','skip',100,30)then A.skip(i,true);A.next(1);A.qty_key=nil end
        imgui.SameLine(0,5)
        if btn('Меню','main',65,30)then
            if U and U.set_open then U.set_open(true)end
            if V and V.set_screen then V.set_screen('arbitrage')end
        end
        -- Bottom-right corner belongs to resize, not to gameplay.
        imgui.SetCursorPos(imgui.ImVec2(g.w-44,g.h-34))
        btn('//','size',30,27)
        if imgui.IsItemActive()and io.MouseDelta then
            local d=io.MouseDelta
            if d.x~=0 or d.y~=0 then save_geometry(g,0,0,d.x,d.y,io)end
        end
    end
    imgui.End()
    imgui.PopStyleVar(3)
    if colors and colors>0 then imgui.PopStyleColor(colors)end
end
return true
