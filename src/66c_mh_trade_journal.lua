-- v2.9.3 Market Helper-style trade journal: verified sales/buys only.
local C,V=DSP.craglog,DSP.ui22
if C._trade293_installed then return true end
C._trade293_installed=true
local function u(s)return DSP.utf8(tostring(s or''))end
local function b(s,id,w,on)return V.button(s,'trade293_'..id,w,on,false,38)end
local function money(n)return DSP.money(math.floor(tonumber(n)or 0))end
local function low(s)return(DSP.lower or string.lower)(tostring(s or''))end
local function kind(e)
    if e.type=='market'then return e.direction=='sell'and'sell'or e.direction=='buy'and'buy'end
    if e.type=='trade'then
        local get,give=tonumber(e.money_get)or 0,tonumber(e.money_give)or 0
        if get>0 and give==0 then return'sell'end
        if give>0 and get==0 then return'buy'end
    end
end
local function items(e,k)return k=='sell'and(e.items_give or{})or(e.items_get or{})end
local function raw_qty(raw)
    local s=tostring(raw or'')
    return tonumber(s:match('[xX]%s*(%d+)')or s:match('(%d+)%s*[xX]')
        or s:match('(%d+)%s*шт')or s:match('(%d+)%s*øò'))
end
local function quantity(e,k)
    local q=tonumber(e.qty or e.count)
    if q and q>0 then return math.floor(q),e.qty_exact~=false end
    if e.type=='trade'then
        local n=0;for _,it in ipairs(items(e,k))do n=n+(tonumber(it.qty)or 1)end
        if n>0 then return n,true end
    end
    q=raw_qty(e.raw)
    if q and q>0 then return math.floor(q),false end
    return 1,false
end
local function amount(e,k)
    if e.type=='market'then return tonumber(e.amount)or 0 end
    return tonumber(k=='sell'and e.money_get or e.money_give)or 0
end
local function description(e,k)
    if e.type=='market'then return tostring(e.item_name or e.item or'?')end
    local parts={}
    for i,it in ipairs(items(e,k))do
        if i>3 then parts[#parts+1]='...';break end
        parts[#parts+1]=tostring(it.name or'?')..' x'..tostring(it.qty or 1)
    end
    return #parts>0 and table.concat(parts,', ')or tostring(e.partner or'Торговая операция')
end
local function period_from(period,now)
    now=now or os.time()
    if period=='hour'then return now-3600 end
    if period=='day'or period=='today'then local d=os.date('*t',now);d.hour,d.min,d.sec=0,0,0;return os.time(d)end
    if period=='week'then return now-7*86400 end
    if period=='month'then return now-30*86400 end
    return 0
end
local function events()
    if C.history then
        local h=C.history('all','');local out={}
        for i=#h,1,-1 do out[#out+1]=h[i]end
        return out
    end
    return C.ring_recent(C.ring_count)
end
function C.trade_rows(period,query,side)
    local list={};local from=period_from(period or'day');local q=low(query)
    for _,e in ipairs(events())do
        local k=kind(e);local ts=tonumber(e.ts)or 0
        if k and ts>=from and(not side or side=='all'or side==k)
            and(not C.event_visible or C.event_visible(e))then
            local name=description(e,k)
            if q==''or low(name):find(q,1,true)or low(e.partner):find(q,1,true)then
                local count,exact=quantity(e,k)
                list[#list+1]={kind=k,ts=ts,name=name,amount=amount(e,k),qty=count,
                    qty_exact=exact,partner=e.partner,source=e.source or'game'}
            end
        end
    end
    return list
end
function C.trade_totals(rows)
    local s={sells=0,buys=0,sell_count=0,buy_count=0,sell_qty=0,buy_qty=0,approx=false}
    for _,e in ipairs(rows or{})do
        if e.kind=='sell'then s.sells=s.sells+(e.amount or 0);s.sell_count=s.sell_count+1;s.sell_qty=s.sell_qty+(e.qty or 1)
        else s.buys=s.buys+(e.amount or 0);s.buy_count=s.buy_count+1;s.buy_qty=s.buy_qty+(e.qty or 1)end
        if e.qty_exact==false then s.approx=true end
    end
    return s
end
local function period_buttons(key,current)
    local opts={{'hour','Час'},{'day','День'},{'week','Неделя'},{'month','Месяц'},{'all','Всё'}}
    local w=math.max(56,(imgui.GetContentRegionAvail().x-24)/5)
    for i,p in ipairs(opts)do
        if b(p[2],key..p[1],w,current==p[1])then current=p[1]end
        if i<#opts then V.inline(6,w)end
    end
    return current
end
local function show_row(row,compact)
    local sign=row.kind=='sell'and'+'or'-'
    local action=row.kind=='sell'and'ПРОДАЖА'or'ПОКУПКА'
    local stamp=os.date(compact and'%H:%M'or'%d.%m %H:%M',row.ts)
    local text=action..' '..sign..money(row.amount)..' | '..stamp..' '..row.name..
        ' x'..tostring(row.qty or 1)..(row.qty_exact==false and'~'or'')
    if compact then text=V.fit(text,math.max(100,imgui.GetContentRegionAvail().x-9))end
    imgui.TextColored(DSP.theme.col(row.kind=='sell'and'good'or'accent',1),u(text))
end
function V.journal()
    V.heading('Журнал продаж / скупки',function()
        if b('Мини-окно','mini',150)then C.set_minimized(false);DSP.settings.craglog.open=true;DSP.save_settings()end
    end,166)
    V.muted('Только подтверждённые игрой сделки. Награды и PayDay вынесены в статистику.')
    V.journal_trade_period=period_buttons('main_',V.journal_trade_period or'day')
    V.journal_trade_side=V.journal_trade_side or'all'
    local sw=math.max(82,(imgui.GetContentRegionAvail().x-12)/3)
    for i,p in ipairs({{'all','Все'},{'sell','Продажи'},{'buy','Скупка'}})do
        if b(p[2],'side_'..p[1],sw,V.journal_trade_side==p[1])then V.journal_trade_side=p[1]end
        if i<3 then V.inline(6,sw)end
    end
    local query=V.search('trade293','Поиск товара или ника',-1)
    local rows=C.trade_rows(V.journal_trade_period,query,V.journal_trade_side)
    local total=C.trade_totals(rows)
    V.green('Продажи: '..money(total.sells)..' · '..total.sell_qty..' шт. · '..total.sell_count..' сделок')
    V.muted('Скупка: '..money(total.buys)..' · '..total.buy_qty..' шт. · '..total.buy_count..' сделок')
    if total.approx then V.muted('~ В старых рыночных чеках количество иногда не сохранялось отдельно.')end
    local reverse={};for i=#rows,1,-1 do reverse[#reverse+1]=rows[i]end
    V.list_rows('trade293_'..V.journal_trade_period..'_'..V.journal_trade_side,reverse,72,function(e,i)
        V.row('trade_'..i,72,function(w,x,y)
            V.at(x,y+1)
            if e.kind=='sell'then V.green('ПРОДАЖА +'..money(e.amount))else V.text('ПОКУПКА -'..money(e.amount))end
            V.at(x,y+29);V.muted(V.fit(os.date('%d.%m %H:%M',e.ts)..' · '..e.name..' · '..e.qty..' шт.',w-12))
        end)
    end,{count=#reverse,footer=function()V.muted('Свайпните список вверх/вниз — стрелки прокрутки не нужны.')end})
end
local function cfg()DSP.settings.craglog=DSP.settings.craglog or{};return DSP.settings.craglog end
local previous_geometry=C.geometry
function C.geometry(sw,sh)
    local s=cfg()
    if not s.trade_compact_initialized then
        s.trade_compact_initialized=true;s.w=math.min(math.max(390,sw*.39),math.max(390,sw-16));s.h=math.min(330,math.max(285,sh-16))
    end
    return previous_geometry(sw,sh)
end
function C.draw()
    local io=imgui.GetIO();local s=cfg();local g=C.geometry(io.DisplaySize.x,io.DisplaySize.y);C.active_geometry=g
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always);imgui.SetNextWindowBgAlpha(.82)
    local colors=DSP.theme.push_window()
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,8);imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(8,7));imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,5))
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove+imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse+(s.pinned and imgui.WindowFlags.NoResize or 0)
    if imgui.Begin('##palatka_trade_journal',nil,flags)then
        if V.apply_font then V.apply_font()end
        if b(s.pinned and'ЖУРНАЛ · ЗАКРЕПЛЁН'or'ЖУРНАЛ · ПЕРЕМЕСТИТЬ','move',math.max(120,g.w-170),s.pinned)then end
        if not s.pinned and imgui.IsItemActive()and io.MouseDelta then C.drag(io.MouseDelta.x,io.MouseDelta.y)end
        if not imgui.IsMouseDown(0)then C.end_drag()end
        imgui.SameLine(0,5);if b(s.pinned and'PIN'or'pin','pin',47,s.pinned)then C.set_pinned(not s.pinned)end
        imgui.SameLine(0,5);if b(s.minimized and'+'or'-','fold',38,s.minimized)then C.set_minimized(not s.minimized)end
        imgui.SameLine(0,5);if b('X','close',40)then s.open=false;DSP.save_settings()end
        if not s.minimized then
            s.trade_period=s.trade_period or'day'
            local ww=math.max(55,(imgui.GetContentRegionAvail().x-12)/3)
            for i,p in ipairs({{'day','День'},{'week','Неделя'},{'all','Всё'}})do
                if b(p[2],'float_'..p[1],ww,s.trade_period==p[1])then s.trade_period=p[1];DSP.save_settings()end
                if i<3 then imgui.SameLine(0,6)end
            end
            local rows=C.trade_rows(s.trade_period,'','all');local total=C.trade_totals(rows)
            imgui.Separator()
            if imgui.BeginChild('##trade293_scroll',imgui.ImVec2(0,-55),false,imgui.WindowFlags.NoScrollbar)then
                if #rows==0 then V.muted('Подтверждённых сделок пока нет.')end
                for i=#rows,math.max(1,#rows-119),-1 do show_row(rows[i],true)end
                if DSP.mobile and DSP.mobile.touch_scroll then DSP.mobile.touch_scroll(io,'trade_float')end
            end
            imgui.EndChild();imgui.Separator()
            V.green('Продано '..money(total.sells)..' · '..total.sell_qty..' шт.')
            V.muted('Куплено '..money(total.buys)..' · '..total.buy_qty..' шт.')
            C.remember_size(imgui.GetWindowSize().x,imgui.GetWindowSize().y)
        end
    end
    imgui.End();if C.end_resize then C.end_resize()end
    imgui.PopStyleVar(3);if colors and colors>0 then imgui.PopStyleColor(colors)end
end
return true
