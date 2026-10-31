-- Floating journal: fixed controls surround a persistent, touch-scrollable list.
local C=DSP.craglog
local selected
local function u(s) return DSP.utf8(tostring(s or '')) end
local function button(label,id,w,on)
    if on then imgui.PushStyleColor(imgui.Col.Button,DSP.theme.col('accent',.65)) end
    local hit=imgui.Button(u(label)..'##journal22_'..id,imgui.ImVec2(w,42))
    if on then imgui.PopStyleColor(1) end
    return hit
end
local function config()
    DSP.settings.craglog=DSP.settings.craglog or {}
    local s=DSP.settings.craglog
    s.v16_filter_pos=math.max(1,math.min(7,math.floor(tonumber(s.v16_filter_pos) or 1)))
    return s
end
local filters={{'all','Все'},{'loot','Награды'},{'payday','PayDay'},
    {'sales','Продажи'},{'buys','Скупка'},{'income','Доходы'},{'other','Другие'}}
function C.detail_lines(e)
    local lines={os.date('%d.%m.%Y %H:%M:%S',e.ts or os.time()),C.describe(e)}
    if e.source then lines[#lines+1]='Источник: '..tostring(e.source) end
    if e.association then lines[#lines+1]='Определение: '..tostring(e.association) end
    if e.type=='payday' or e.kind=='payday' then
        lines[#lines+1]=e.income and ('Начислено: '..DSP.money(e.income)) or 'Начисления: не распознаны'
        lines[#lines+1]=e.expense and ('Списано: '..DSP.money(e.expense)) or 'Списания: не распознаны'
        for _,part in ipairs(e.details or {}) do lines[#lines+1]=tostring(part.raw or '') end
        lines[#lines+1]='Торговый итог за день: '..DSP.money(e.profit or 0)
    end
    if e.raw then lines[#lines+1]='Сообщение: '..tostring(e.raw) end
    return lines
end
function C.geometry(sw,sh)
    local s=config()
    local w=math.min(math.max(390,math.min(550,sw*.24)),sw-16)
    local h=math.min(math.max(330,math.min(480,sh*.43)),sh-16)
    local x=math.max(8,math.min(tonumber(s.x)or 24,sw-w-8))
    local y=math.max(8,math.min(tonumber(s.y)or 120,sh-h-8))
    return{x=x,y=y,w=w,h=s.minimized and 56 or h,touch=42,max_x=sw-w-8,max_y=sh-h-8}
end
function C.mini_reserved()
    local line=imgui.GetTextLineHeight and imgui.GetTextLineHeight()or 16
    return 42+46+50+4*(line+3)+14
end
local function totals(g,period,loot)
    local V=DSP.ui22 or DSP.ui21
    local summary=C.summary(period)
    local x=imgui.GetCursorPosX();local y=imgui.GetCursorPosY()
    local line=(imgui.GetTextLineHeight and imgui.GetTextLineHeight()or 16)+3
    local rows={{'Доход',summary.income},{'Расход',summary.expense},{'Итог',summary.net}}
    for i,row in ipairs(rows)do
        V.at(x,y+(i-1)*line);V.muted(row[1]);V.at(x+88,y+(i-1)*line)
        if i==2 then V.red('-'..DSP.money(row[2]))elseif row[2]>=0 then V.green('+'..DSP.money(row[2]))else V.red(DSP.money(row[2]))end
    end
    V.at(x,y+3*line)
    V.muted(V.fit('Добыча '..loot.qty..' шт. · ~ '..DSP.money(loot.estimated)..(loot.unpriced_qty>0 and(' · без цены '..loot.unpriced_qty)or''),g.w-26))
end
local function content(g,s)
    local V=DSP.ui22 or DSP.ui21
    if not V or not V.list then imgui.TextWrapped(u('Журнал загружается'));return end
    s.summary_period=s.summary_period or 'session';s.mini_mode=s.mini_mode or 'loot'
    local period=s.summary_period
    local loot=C.loot_summary and C.loot_summary(period)or{items={},qty=0,estimated=0,unpriced_qty=0}
    local height=math.max(48,g.h-C.mini_reserved())
    if selected and C.event_visible and not selected.events and not C.event_visible(selected)then selected=nil end
    if selected then
        if button('< Назад','back',128)then selected=nil;return end
        local entry=selected
        if entry.events then
            V.list_rows('mini_loot_receipts',entry.events,52,function(e,i,w)
                local title=os.date('%d.%m %H:%M',e.ts or 0)..' · x'..tostring(e.qty or e.count or 1)..' · '..tostring(e.source or 'Неизвестный источник')
                if button(V.fit(title,w-12),'receipt_'..i,w)and not V.dragged then selected=e end
            end,{height=height})
        else
            V.list('mini_detail',function()
                for _,line in ipairs(C.detail_lines(entry))do imgui.TextWrapped(u(line))end
            end,{height=height})
        end
        totals(g,period,loot);return
    end
    if button(s.mini_mode=='loot'and'Добыча'or'События','mode',100,s.mini_mode=='loot')then
        s.mini_mode=s.mini_mode=='loot'and'events'or'loot'
    end
    imgui.SameLine(0,4)
    local pos=s.v16_filter_pos
    local filterw=g.w-100-124-22
    if s.mini_mode=='events'then
        if button(filters[pos][2]..' >','category',filterw)then pos=pos%#filters+1;s.v16_filter_pos=pos end
    elseif button('Все предметы >','all_loot',filterw)then
        DSP.ui.set_open(true);V.set_screen('logs');V.journal_mode='loot';V.journal_period=period
    end
    imgui.SameLine(0,4)
    local label=period=='session'and'Сессия'or period=='day'and'Сегодня'or'Всё время'
    if button(label..' >','period',124,true)then
        s.summary_period=period=='session'and'day'or period=='day'and'all'or'session'
    end
    if s.mini_mode=='loot'then
        V.list_rows('mini_loot_'..period,loot.items,52,function(row,i,w)
            V.row('mini_loot_'..i,52,function(rw,x,y)
                V.at(x,y-2)
                if V.text_button(V.fit(row.name..'  x'..row.qty,rw-146),'journal22_loot_'..i,rw-140,false)then selected=row end
                V.at(x+rw-138,y+12)
                if row.estimated>0 then V.green('~ '..DSP.money(row.estimated))else V.muted('Нет цены')end
            end)
        end,{height=height})
    else
        local events=C.filtered(filters[pos][1]);local newest={}
        local from=C.period_start and C.period_start(period)or 0
        for i=#events,1,-1 do if(events[i].ts or 0)>=from then newest[#newest+1]=events[i]end end
        V.list_rows('mini_'..filters[pos][1]..'_'..period,newest,52,function(e,i,w)
            local text=os.date('%H:%M',e.ts or 0)..'  '..(C.event_title and C.event_title(e)or C.describe(e))
            if button(V.fit(text,w-12),'event_'..i,w)and not V.dragged then selected=e end
        end,{height=height})
    end
    totals(g,period,loot)
end
function C.draw()
    local io=imgui.GetIO();local s=config();local V=DSP.ui22 or DSP.ui21
    local g=C.geometry(io.DisplaySize.x,io.DisplaySize.y);C.active_geometry=g
    local previous_scale=V and V.font_pixels
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(1)
    local colors=DSP.theme.push_window and DSP.theme.push_window()or DSP.theme.push_overlay(1)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,10)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,6)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(7,7))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,4))
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+imgui.WindowFlags.NoMove
        +imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoScrollbar
    if imgui.Begin('##palatka_journal22',nil,flags)then
        if V and V.apply_font then V.font_pixels=22*(tonumber(DSP.ui.d)or 1.25)/1.25;V.apply_font()end
        if V and V.text_button then V.text_button('Журнал','journal_drag',math.max(70,g.w-160))else button('Журнал','drag',math.max(70,g.w-160))end
        if not s.pinned and imgui.IsItemActive and imgui.IsItemActive()and imgui.IsMouseDragging(0)then local d=io.MouseDelta;C.drag(d.x,d.y)end
        if not imgui.IsMouseDown(0)then C.end_drag()end
        imgui.SameLine(0,4);if button(s.pinned and '*'or'o','pin',42,s.pinned)then C.set_pinned(not s.pinned)end
        imgui.SameLine(0,4);if button(s.minimized and'+'or'-','collapse',42)then C.set_minimized(not s.minimized)end
        imgui.SameLine(0,4);if button('X','close',42)then s.open=false;DSP.save_settings()end
        if not s.minimized then content(g,s)end
    end
    imgui.End();imgui.PopStyleVar(4)
    if V then V.font_pixels=previous_scale end
    if colors and colors>0 then imgui.PopStyleColor(colors)end
end
