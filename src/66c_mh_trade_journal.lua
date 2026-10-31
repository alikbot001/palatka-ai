-- Market Helper-inspired trade log: concise receipts and totals, no loot/stat dashboard.
-- All events originate from Palatka's verified journal; no invented transactions.
local C,V=DSP.craglog,DSP.ui22
local function u(s)return DSP.utf8(tostring(s or''))end
local function b(s,id,w,active)return V.button(s,'trade291_'..id,w,active,false,38)end
local function money(n)return DSP.money(math.floor(tonumber(n)or 0))end
local function kind(e)
    if e.type=='market' then return e.direction=='sell' and 'sell' or e.direction=='buy' and 'buy'end
    if e.type=='trade' then
        local get,give=tonumber(e.money_get)or 0,tonumber(e.money_give)or 0
        if get>0 and give==0 then return 'sell' end
        if give>0 and get==0 then return 'buy' end
    end
end
local function value(e,k)
    if e.type=='market' then return tonumber(e.amount)or 0 end
    return tonumber(k=='sell' and e.money_get or e.money_give)or 0
end
local function description(e,k)
    if e.type=='market' then return tostring(e.item_name or e.item or'?') end
    local items=k=='sell'and e.items_give or e.items_get
    if type(items)=='table'and #items>0 then
        local parts={}
        for i=1,math.min(2,#items)do
            local it=items[i];parts[#parts+1]=tostring(it.name or'?')..' x'..tostring(it.qty or 1)
        end
        return table.concat(parts,', ')
    end
    return tostring(e.partner or 'Торговая операция')
end
function C.trade_rows(period)
    local list={}
    local today=os.date('%d.%m.%Y')
    for _,e in ipairs(C.ring_recent(C.ring_count))do
        local k=kind(e)
        if k and (not C.event_visible or C.event_visible(e)) then
            local when=tonumber(e.ts)or 0
            if period~='today' or os.date('%d.%m.%Y',when)==today then
                list[#list+1]={kind=k,ts=when,name=description(e,k),amount=value(e,k),
                    qty=tonumber(e.qty)or 1,source=e.source or'game'}
            end
        end
    end
    return list
end
function C.trade_totals(rows)
    local summary={sells=0,buys=0,sell_count=0,buy_count=0}
    for _,e in ipairs(rows)do
        if e.kind=='sell'then
            summary.sells=summary.sells+e.amount;summary.sell_count=summary.sell_count+1
        else
            summary.buys=summary.buys+e.amount;summary.buy_count=summary.buy_count+1
        end
    end
    return summary
end
local function stats(t)
    V.green('Продано: '..money(t.sells)..' ('..t.sell_count..')')
    V.muted('Куплено: '..money(t.buys)..' ('..t.buy_count..')')
end
local function show_row(row,compact)
    local tag=row.kind=='sell'and '[+] 'or '[-] '
    local val=(row.kind=='sell'and '+' or '-')..money(row.amount)
    local stamp=os.date(compact and'%H:%M' or'%d.%m %H:%M',row.ts)
    local line=tag..stamp..'  '..row.name..'  '..val
    if compact then line=V.fit(line,math.max(100,imgui.GetContentRegionAvail().x-9))end
    imgui.TextColored(DSP.theme.col(row.kind=='sell'and'good'or'accent',1),u(line))
end
function V.journal()
    V.heading('Журнал сделок',function()
        if b('Мини-окно','mini',160)then C.set_minimized(false);DSP.settings.craglog.open=true;DSP.save_settings()end
    end,178)
    V.muted('Подтверждённые продажи и покупки. Без наград и лишней статистики.')
    V.journal_trade_period=V.journal_trade_period or'today'
    if b('Сегодня','today',136,V.journal_trade_period=='today')then V.journal_trade_period='today'end
    V.inline(6)
    if b('Всё время','all',145,V.journal_trade_period=='all')then V.journal_trade_period='all'end
    local rows=C.trade_rows(V.journal_trade_period)
    local totals=C.trade_totals(rows)
    stats(totals)
    local reverse={}
    for i=#rows,1,-1 do reverse[#reverse+1]=rows[i]end
    V.list_rows('simple_trade_'..V.journal_trade_period,reverse,62,function(e,i)
        V.row('trade_'..i,62,function(w,x,y)
            V.at(x,y)
            if e.kind=='sell'then V.green('ПРОДАЖА  +'..money(e.amount))
            else V.red('ПОКУПКА  -'..money(e.amount))end
            V.at(x,y+27)
            V.muted(V.fit(os.date('%H:%M',e.ts)..'  '..e.name,w-14))
        end)
    end,{count=#reverse})
end
local function config()
    DSP.settings.craglog=DSP.settings.craglog or{}
    return DSP.settings.craglog
end
-- Existing timestamps and ring persist. Only the mobile presentation changes.
local previous_geometry=C.geometry
function C.geometry(sw,sh)
    local s=config()
    if not s.trade_compact_initialized then
        s.trade_compact_initialized=true
        s.w=math.min(math.max(360,sw*.37),math.max(360,sw-16))
        s.h=math.min(305,math.max(280,sh-16))
    end
    return previous_geometry(sw,sh)
end
function C.draw()
    local io=imgui.GetIO();local s=config();local g=C.geometry(io.DisplaySize.x,io.DisplaySize.y)
    C.active_geometry=g
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    if not C._trade_size_set then imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always);C._trade_size_set=true end
    imgui.SetNextWindowBgAlpha(.78)
    local colors=DSP.theme.push_window()
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,10)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(8,7))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,5))
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse
    if imgui.Begin('##palatka_trade_journal',nil,flags)then
        if V.apply_font then V.apply_font()end
        if b('Сделки · переместить','move',math.max(95,g.w-143))then end
        if not s.pinned and imgui.IsItemActive()and io.MouseDelta then
            C.drag(io.MouseDelta.x,io.MouseDelta.y)
        end
        if not imgui.IsMouseDown(0)then C.end_drag()end
        imgui.SameLine(0,5)
        if b(s.pinned and'P' or'pin','pin',46,s.pinned)then C.set_pinned(not s.pinned)end
        imgui.SameLine(0,5)
        if b('X','close',45)then s.open=false;DSP.save_settings()end
        local filter=s.trade_period or'today'
        local rows=C.trade_rows(filter)
        local total=C.trade_totals(rows)
        if b('Сегодня','today',116,filter=='today')then s.trade_period='today';DSP.save_settings()end
        imgui.SameLine(0,5)
        if b('Все','all',86,filter=='all')then s.trade_period='all';DSP.save_settings()end
        imgui.Separator()
        if imgui.BeginChild('##trade291_scroll',imgui.ImVec2(0,-60),false)then
            if #rows==0 then V.muted('Подтверждённых сделок пока нет.')end
            local max=math.min(#rows,60)
            for i=#rows,#rows-max+1,-1 do
                local e=rows[i]
                if e then show_row(e,true)end
            end
        end
        imgui.EndChild()
        imgui.Separator()
        V.green('Продано '..money(total.sells)..' · '..total.sell_count)
        V.muted('Куплено '..money(total.buys)..' · '..total.buy_count)
        C.remember_size(imgui.GetWindowSize().x,imgui.GetWindowSize().y)
    end
    imgui.End()
    if C.end_resize then C.end_resize()end
    imgui.PopStyleVar(3)
    if colors and colors>0 then imgui.PopStyleColor(colors)end
end
return true
