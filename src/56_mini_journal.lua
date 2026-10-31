-- Compact MCR-inspired trade overlay; journal/event semantics stay in Palatka.
local C=DSP.craglog
local function cp(s)return DSP.utf8(tostring(s or ''))end
local function state()
    DSP.settings.craglog=DSP.settings.craglog or {}
    return DSP.settings.craglog
end
local function changed()if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end end
local function button(label,id,w)
    return imgui.Button(cp(label)..'##compact_log_'..id,imgui.ImVec2(w,28))
end
local function short(s,max_width)
    s=tostring(s or '')
    if not imgui.CalcTextSize then return s end
    if imgui.CalcTextSize(cp(s)).x<=max_width then return s end
    local l,r=0,#s
    while l<r do
        local m=math.floor((l+r+1)/2)
        if imgui.CalcTextSize(cp(s:sub(1,m)..'...')).x<=max_width then l=m else r=m-1 end
    end
    return s:sub(1,l)..'...'
end
local function draw_header(s,g)
    local width=imgui.GetContentRegionAvail().x
    local right=s.click_through and 0 or 116
    if button(s.minimized and 'J  /  ОТКРЫТЬ' or 'J  /  ТОРГОВЫЙ ЖУРНАЛ',
        'drag',math.max(65,width-right))then
        if s.minimized then C.set_minimized(false)end
    end
    if not s.pinned and not s.click_through and imgui.IsItemActive() and imgui.GetIO().MouseDelta then
        local d=imgui.GetIO().MouseDelta
        if d.x~=0 or d.y~=0 then C.drag(d.x,d.y)end
    end
    if not imgui.IsMouseDown(0)then C.end_drag()end
    if not s.click_through then
        imgui.SameLine(0,4)
        if button(s.minimized and '+' or '-','collapse',33)then C.set_minimized(not s.minimized)end
        imgui.SameLine(0,4)
        if button('X','close',33)then s.open=false;changed()end
    end
end
local function draw_compact(s,g)
    local events=C.filtered(s.filter or 'all')
    local n=#events
    local lines=s.lines or 4
    if n==0 then
        imgui.TextDisabled(cp('Нет новых событий. История сохранена в Palatka AI.'))
    end
    for i=n,math.max(1,n-lines+1),-1 do
        local e=events[i]
        if e then
            local when=os.date('%H:%M',e.ts or os.time())
            local desc=C.describe(e)
            local label=when..'  '..desc
            imgui.Text(cp(short(label,math.max(80,imgui.GetContentRegionAvail().x-8))))
        end
    end
    if C.last_error then
        imgui.TextColored(DSP.theme.col('bad',1),cp(short('Журнал: '..C.last_error,g.w-16)))
    end
end
local function draw_expanded(s,g)
    local summary=C.summary('day')
    imgui.TextDisabled(cp('Приход '..DSP.money(summary.income)..' | Расход '..DSP.money(summary.expense)))
    imgui.TextColored(DSP.theme.col('good',1),cp('Итог за сегодня: '..DSP.money(summary.net)))
    for _,row in ipairs({{'all','Все'},{'sales','Продажи'},{'buys','Скупка'},{'loot','Добыча'}})do
        if button(row[2],'filter_'..row[1],92)then s.filter=row[1];changed()end
        imgui.SameLine(0,4)
    end
    imgui.NewLine()
    if imgui.BeginChild('##compact_log_events',imgui.ImVec2(0,0),false)then
        draw_compact(s,g)
    end
    imgui.EndChild()
end
function C.draw()
    local s=state()
    if s.compact==nil then s.compact=true end
    if s.alpha==nil then s.alpha=.28 end
    s.alpha=math.max(.08,math.min(1,tonumber(s.alpha)or .28))
    local io=imgui.GetIO()
    local g=C.geometry(io.DisplaySize.x,io.DisplaySize.y)
    C.active_geometry=g
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    if s.compact or s.minimized or not C._window_size_initialized then
        imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    else
        imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Appearing)
        if imgui.SetNextWindowSizeConstraints then
            imgui.SetNextWindowSizeConstraints(imgui.ImVec2(250,100),
                imgui.ImVec2(math.max(250,io.DisplaySize.x-16),math.max(100,io.DisplaySize.y-16)))
        end
    end
    C._window_size_initialized=true
    local colors=DSP.theme.push_overlay(1)
    imgui.SetNextWindowBgAlpha(s.alpha)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,5)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(7,5))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(4,2))
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse+
        imgui.WindowFlags.NoFocusOnAppearing
    if s.compact or s.minimized then flags=flags+imgui.WindowFlags.NoResize+imgui.WindowFlags.NoScrollbar end
    if s.click_through then flags=flags+imgui.WindowFlags.NoInputs end
    if imgui.Begin('##palatka_mini_journal',nil,flags)then
        if imgui.SetWindowFontScale then
            local base=imgui.GetFontSize and imgui.GetFontSize()or 16
            imgui.SetWindowFontScale(math.min(1,14/math.max(1,base)))
        end
        if not s.click_through then draw_header(s,g)end
        if not s.minimized then
            if s.compact then draw_compact(s,g)else draw_expanded(s,g)end
        end
    end
    if not s.compact and not s.minimized and imgui.GetWindowSize then
        local wh=imgui.GetWindowSize();C.remember_size(wh.x,wh.y)
    end
    C.end_resize()
    imgui.End()
    imgui.PopStyleVar(3)
    if colors and colors>0 then imgui.PopStyleColor(colors)end
end
return true
