-- Arizona Market-inspired floating journal: compact timeline, detail on tap.
local C=DSP.craglog
local function u(s) return DSP.utf8(tostring(s or '')) end
local function button(label,id,w,on)
    if on then imgui.PushStyleColor(imgui.Col.Button,DSP.theme.col('accent',.65)) end
    local hit=imgui.Button(u(label)..'##journal16_'..id,imgui.ImVec2(w,40))
    if on then imgui.PopStyleColor(1) end
    return hit
end
local function config()
    local s=DSP.settings.craglog
    s.v16_category=s.v16_category or 'all'
    s.v16_page=s.v16_page or 1
    s.v16_hidden=s.v16_hidden or {}
    return s
end
local filters={{'all','Все'},{'loot','Награды'},{'payday','PayDay'},
    {'sales','Продажи'},{'buys','Скупка'},{'income','Деньги'},{'other','Другие'}}
local function desc(e)
    if e.kind=='opening' then return 'Открытие: '..tostring(e.source or 'неизвестный источник') end
    if e.kind=='item' then return tostring(e.item_name or 'неизвестный предмет')..' x'..tostring(e.qty or 1) end
    return C.describe(e)
end
function C.geometry(sw,sh)
    local s=config()
    local w=math.max(410,math.min(620,sw*.29))
    local h=math.max(280,math.min(510,sh*.49))
    w=math.min(w,sw-16);h=math.min(h,sh-16)
    local x=math.max(8,math.min(tonumber(s.x) or 24,sw-w-8))
    local y=math.max(8,math.min(tonumber(s.y) or 120,sh-h-8))
    return {x=x,y=y,w=w,h=s.minimized and 56 or h,touch=40,max_x=sw-w-8,max_y=sh-h-8}
end
function C.draw()
    local io=imgui.GetIO()
    local g=C.geometry(io.DisplaySize.x,io.DisplaySize.y)
    local s=config();C.active_geometry=g
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(.97)
    local colors=DSP.theme.push_overlay(.98)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,9)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,6)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(7,7))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,4))
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+imgui.WindowFlags.NoMove
        +imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse
    if imgui.Begin('##palatka_journal16',nil,flags) then
        if button('ЖУРНАЛ','drag',math.max(80,g.w-200)) then end
        if not s.pinned and imgui.IsItemActive and imgui.IsItemActive() and imgui.IsMouseDragging(0) then
            local d=io.MouseDelta;C.drag(d.x,d.y)
        end
        if not imgui.IsMouseDown(0) then C.end_drag() end
        imgui.SameLine(0,4)
        if button(s.minimized and '+' or '-','collapse',54) then C.set_minimized(not s.minimized) end
        imgui.SameLine(0,4)
        if button('X','close',48) then s.open=false;DSP.save_settings() end
        if not s.minimized then
            if s.v16_detail then
                if button('< Назад','back',140) then s.v16_detail=nil;DSP.save_settings() end
                local entry
                for _,v in ipairs(C.ring_recent(C.ring_count)) do if v==s.v16_detail then entry=v;break end end
                -- In-memory selected entry stays valid until script reload; no dummy info.
                entry=entry or s.v16_detail
                if entry then
                    imgui.TextColored(DSP.theme.col('accent',1),u(os.date('%d.%m %H:%M:%S',entry.ts or os.time())))
                    imgui.TextWrapped(u(desc(entry)))
                    if entry.source then imgui.TextWrapped(u('Источник: '..tostring(entry.source))) end
                    if entry.association then imgui.TextWrapped(u('Определение: '..tostring(entry.association))) end
                    if entry.raw then imgui.TextWrapped(u('Сообщение: '..tostring(entry.raw))) end
                    if entry.kind=='payday' then
                        imgui.TextWrapped(u(entry.amount and ('Начисления: '..DSP.money(entry.amount)) or 'Начисления: не распознаны'))
                        imgui.TextWrapped(u('Торговый итог: '..DSP.money(entry.profit or 0)))
                    end
                end
            else
                local w=(g.w-18)/3
                -- Page through category filters instead of six giant permanent buttons.
                if button('<','category_left',52) then
                    s.v16_filter_pos=math.max(1,(s.v16_filter_pos or 1)-1)
                end
                imgui.SameLine(0,4)
                local pos=s.v16_filter_pos or 1
                local option=filters[pos] or filters[1]
                if button(option[2],'category',math.max(150,g.w-132),true) then
                    s.v16_filter_pos=pos%#filters+1
                    s.v16_page=1
                end
                imgui.SameLine(0,4)
                if button('>','category_right',52) then
                    s.v16_filter_pos=pos%#filters+1
                    s.v16_page=1
                end
                pos=s.v16_filter_pos or 1;option=filters[pos] or filters[1]
                local events=C.filtered(option[1])
                local pages=math.max(1,math.ceil(#events/5))
                s.v16_page=math.min(pages,math.max(1,s.v16_page))
                imgui.TextDisabled(u('# '..#events..'  |  '..s.v16_page..' / '..pages))
                local latest=#events-(s.v16_page-1)*5
                local first=math.max(1,latest-4)
                if #events==0 then imgui.TextWrapped(u('Записей пока нет')) end
                for i=latest,first,-1 do
                    local e=events[i]
                    if e then
                        local txt=os.date('%H:%M',e.ts or os.time())..'  '..desc(e)
                        if button(txt,'event_'..i,-1) then s.v16_detail=e end
                    end
                end
                if button('НОВЕЕ','new',math.max(145,(g.w-22)/2)) then
                    s.v16_page=math.max(1,s.v16_page-1)
                end
                imgui.SameLine(0,4)
                if button('СТАРШЕ','old',math.max(145,(g.w-22)/2)) then
                    s.v16_page=math.min(pages,s.v16_page+1)
                end
                -- Optional display filters. Never silently discard recorded events.
            end
        end
    end
    imgui.End()
    imgui.PopStyleVar(4)
    if colors and colors>0 then imgui.PopStyleColor(colors) end
end
