-- Market Helper inspired trading log: simple movable translucent feed.
-- Uses original Palatka journal events; never fabricates trade receipts.
local C=DSP.craglog
local function t(s)return DSP.utf8(tostring(s or''))end
local function prefs()
    DSP.settings.craglog=DSP.settings.craglog or{}
    local s=DSP.settings.craglog
    s.mh_log_lines=math.max(3,math.min(16,math.floor(tonumber(s.mh_log_lines)or 8)))
    s.mh_log_alpha=math.max(.12,math.min(.95,tonumber(s.mh_log_alpha)or .58))
    return s
end
local function is_trade(e)
    return e.type=='market'and(e.direction=='sell'or e.direction=='buy')
end
function C.trade_feed(limit)
    limit=math.max(1,math.min(40,math.floor(tonumber(limit)or 8)))
    local rows={}
    -- Oldest to newest ring order; render newest first without touching ledger.
    for _,e in ipairs(C.ring_recent(C.ring_count))do
        if is_trade(e)and(not C.event_visible or C.event_visible(e))then
            rows[#rows+1]=e
        end
    end
    local result={}
    for i=#rows,math.max(1,#rows-limit+1),-1 do result[#result+1]=rows[i]end
    return result
end
function C.trade_feed_line(e)
    local selling=e.direction=='sell'
    local label=selling and'Продажа' or'Скупка'
    local sign=selling and'+' or'-'
    local qty=tonumber(e.qty)or tonumber(e.count)
    local name=tostring(e.item_name or e.item or'?')
    return os.date('%H:%M',tonumber(e.ts)or os.time())..'  '..label..
        ': '..name..(qty and (' x'..math.floor(qty))or'')..
        '  '..sign..DSP.money(e.amount or 0)
end
local function trade_geometry(sw,sh,s)
    local maxw=math.max(180,sw-12)
    local maxh=math.max(90,sh-12)
    local w=math.min(maxw,math.max(math.min(maxw,250),tonumber(s.w)or math.min(445,maxw)))
    local h=math.min(maxh,math.max(math.min(maxh,120),tonumber(s.h)or math.min(210,maxh)))
    local x=math.max(4,math.min(tonumber(s.x)or 18,sw-w-4))
    local y=math.max(4,math.min(tonumber(s.y)or math.max(14,sh*.24),sh-h-4))
    return{x=x,y=y,w=w,h=s.minimized and 33 or h,
        max_x=math.max(4,sw-w-4),max_y=math.max(4,sh-h-4)}
end
function C.draw()
    local s=prefs()
    local io=imgui.GetIO()
    local g=trade_geometry(io.DisplaySize.x,io.DisplaySize.y,s)
    C.active_geometry=g
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.FirstUseEver)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoSavedSettings
    if s.minimized then
        imgui.SetNextWindowSize(imgui.ImVec2(g.w,37),imgui.Cond.Always)
        flags=flags+imgui.WindowFlags.NoResize
    end
    imgui.SetNextWindowBgAlpha(s.mh_log_alpha)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(7,5))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(4,4))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,4)
    if imgui.Begin('##palatka_trade_feed',nil,flags)then
        local avail=imgui.GetContentRegionAvail().x
        if imgui.Button(t('ТОРГОВЫЙ ЖУРНАЛ')..'##trade_feed_drag',
            imgui.ImVec2(math.max(70,avail-56),26))then end
        if imgui.IsItemActive()and imgui.IsMouseDragging(0)and not s.pinned then
            local d=io.MouseDelta;C.drag(d.x,d.y)
        end
        if not imgui.IsMouseDown(0)then C.end_drag()end
        imgui.SameLine(0,4)
        if imgui.Button(s.minimized and'+'or'-'..'##trade_feed_fold',imgui.ImVec2(24,26))then
            C.set_minimized(not s.minimized)
        end
        imgui.SameLine(0,3)
        if imgui.Button('x##trade_feed_close',imgui.ImVec2(24,26))then
            s.open=false;DSP.save_settings()
        end
        if not s.minimized then
            imgui.Separator()
            if imgui.BeginChild('##trade_feed_lines',imgui.ImVec2(0,-2),false)then
                local entries=C.trade_feed(s.mh_log_lines)
                if #entries==0 then
                    imgui.TextDisabled(t('Продажи и скупка появятся здесь после подтверждения игрой'))
                end
                for _,e in ipairs(entries)do
                    local color=e.direction=='sell'
                        and imgui.ImVec4(.40,.94,.48,1)
                        or imgui.ImVec4(.40,.73,1,1)
                    imgui.TextColored(color,t(C.trade_feed_line(e)))
                end
            end
            imgui.EndChild()
            if imgui.GetWindowSize then
                local p=imgui.GetWindowSize()
                if not s.pinned and
                    (math.abs((s.w or 0)-p.x)>1 or math.abs((s.h or 0)-p.y)>1)then
                    s.w=math.floor(p.x+.5);s.h=math.floor(p.y+.5)
                    C.size_dirty=true
                end
            end
        end
    end
    imgui.End()
    imgui.PopStyleVar(3)
    C.end_resize()
end
return true
