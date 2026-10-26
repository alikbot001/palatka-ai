-- Phone journal: one stable anchor, fixed controls, and readable event cards.
local C=DSP.craglog
local function cp(s) return DSP.utf8(tostring(s or '')) end
local function text(s) imgui.TextWrapped(cp(s)) end
local function button(label,id,w,active)
    if active then imgui.PushStyleColor(imgui.Col.Button,DSP.theme.col('accent',.7)) end
    local hit=imgui.Button(cp(label)..'##mini_'..id,imgui.ImVec2(w,54))
    if active then imgui.PopStyleColor(1) end
    return hit
end
local function inline() imgui.SameLine(0,8) end
local function state() return DSP.settings.craglog end
local function header(g)
    local s=state()
    local handle=s.pinned and 'ЖУРНАЛ / ЗАКРЕПЛЁН' or 'ЖУРНАЛ / ПЕРЕТАЩИТЬ'
    button(handle,'handle',g.w-300,false)
    if not s.pinned and imgui.IsItemActive() and imgui.IsMouseDragging(0) then
        local delta=imgui.GetIO().MouseDelta
        C.drag(delta.x,delta.y)
    end
    if not imgui.IsMouseDown(0) then C.end_drag() end
    inline()
    if button(s.pinned and 'PIN: ДА' or 'PIN: НЕТ','pin',120,s.pinned) then C.set_pinned(not s.pinned) end
    inline()
    if button(s.minimized and '+' or '-','collapse',60) then C.set_minimized(not s.minimized) end
    inline()
    if button('X','close',60) then s.open=false; DSP.save_settings() end
end
local function filters(g)
    local s=state()
    for i,pair in ipairs({{'all','Все'},{'loot','Тайники'},{'payday','PayDay'},
                           {'sales','Продажи'},{'buys','Скупка'},{'income','Доходы'}}) do
        if button(pair[2],'filter_'..pair[1],(g.w-42)/3,s.filter==pair[1]) then
            s.filter=pair[1]; C.scroll=0; DSP.save_settings()
        end
        if i%3~=0 then inline() end
    end
end
local function row_card(entry)
    local kind=entry.kind or entry.type
    local tag=kind=='item' and 'НАГРАДА' or kind=='cash' and 'ДЕНЬГИ' or kind=='opening' and 'ТАЙНИК'
        or entry.type=='payday' and 'PAYDAY' or entry.type=='income' and 'ДОХОД' or 'СДЕЛКА'
    imgui.TextColored(DSP.theme.col('accent',1),cp(os.date('%H:%M:%S',entry.ts or 0)..'  '..tag))
    text(C.describe(entry))
    if entry.source then
        text('Источник: '..entry.source..(entry.association=='inferred' and ' (по чату)' or ''))
    end
    imgui.Separator()
end
function C.draw()
    local io=imgui.GetIO()
    local g=C.geometry(io.DisplaySize.x,io.DisplaySize.y)
    local s=state()
    C.active_geometry=g
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(.96)
    local colors=DSP.theme.push_overlay(.98)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,16)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,9)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(12,12))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(8,8))
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+imgui.WindowFlags.NoMove
        +imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoFocusOnAppearing
    if imgui.Begin('##palatka_mini_journal',nil,flags) then
        if imgui.SetWindowFontScale then imgui.SetWindowFontScale(1.15) end
        header(g)
        if not s.minimized then
            filters(g)
            local events=C.filtered(s.filter or 'all')
            local per=3
            C.scroll=math.max(0,math.min(C.scroll,math.max(0,#events-per)))
            local start=#events-C.scroll
            text('Последние события: '..#events..' / '..C.ring_cap..'   |   PIN фиксирует положение')
            if button('ВВЕРХ / НОВЕЕ','up',(g.w-40)/2,C.scroll>0) then C.scroll=math.max(0,C.scroll-per) end
            inline()
            if button('ВНИЗ / СТАРШЕ','down',(g.w-40)/2,start>per) then C.scroll=math.min(math.max(0,#events-per),C.scroll+per) end
            start=#events-C.scroll
            local shown=imgui.BeginChild('##mini_cards',imgui.ImVec2(0,0),false)
            if shown then
                if #events==0 then
                    text('Здесь появятся сделки, деньги и награды из игрового чата.')
                    text('Полная история доступна в главном меню.')
                end
                for i=start,math.max(1,start-per+1),-1 do if events[i] then row_card(events[i]) end end
                if C.last_error then text('Ошибка записи: '..C.last_error) end
            end
            imgui.EndChild()
        end
    end
    imgui.End()
    imgui.PopStyleVar(4)
    if colors and colors>0 then imgui.PopStyleColor(colors) end
end
return true
