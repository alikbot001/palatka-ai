-- v2.9.3 touch scrolling override. Keeps legacy CP1251 UI modules byte-identical.
local M,V=DSP.mobile,DSP.ui22
if not M or not V then return true end
M._touch_scroll_states=M._touch_scroll_states or {}
function M.touch_scroll(io,screen)
    if not imgui.IsWindowHovered or not imgui.GetScrollY or not imgui.SetScrollY then return end
    screen=tostring(screen or 'default')
    local st=M._touch_scroll_states[screen]
    if not st then st={velocity=0,travel=0,was_down=false};M._touch_scroll_states[screen]=st end
    local held=false
    if io and io.MouseDown then
        local ok,value=pcall(function()return io.MouseDown[0]end)
        held=ok and value and true or false
    end
    local flags=0
    pcall(function() flags=(imgui.HoveredFlags and imgui.HoveredFlags.ChildWindows) or 0 end)
    local hovered=false
    local ok_hover=pcall(function() hovered=imgui.IsWindowHovered(flags) end)
    if not ok_hover then pcall(function() hovered=imgui.IsWindowHovered() end) end
    local max=imgui.GetScrollMaxY and imgui.GetScrollMaxY()or 1000000
    local current=imgui.GetScrollY()or 0
    local dy=io and io.MouseDelta and(io.MouseDelta.y or 0)or 0
    local dx=io and io.MouseDelta and(io.MouseDelta.x or 0)or 0
    if held then
        if not st.was_down then st.travel=0;st.velocity=0 end
        st.was_down=true
        if not hovered or(io and io.WantTextInput)then st.velocity=0;return end
        st.travel=st.travel+math.abs(dy)+math.abs(dx)
        local active=false
        pcall(function() active=imgui.IsAnyItemActive() and true or false end)
        if active and(st.travel<8 or math.abs(dy)<math.abs(dx)*1.20)then return end
        if math.abs(dy)>.01 then
            local step=-dy
            imgui.SetScrollY(DSP.clamp(current+step,0,max))
            st.velocity=st.velocity*.35+step*.65
        end
        return
    end
    if st.was_down then st.was_down=false;st.travel=0 end
    if math.abs(st.velocity)>.08 then
        local y=DSP.clamp(current+st.velocity,0,max)
        imgui.SetScrollY(y)
        if y<=0 or y>=max then st.velocity=0
        else
            local dt=io and tonumber(io.DeltaTime)or(1/60)
            st.velocity=st.velocity*math.pow(.86,math.max(.25,dt*60))
        end
    else st.velocity=0 end
end
function V.list(key,draw,options)
    V.track_touch(imgui.GetIO())
    local o=options or{};local footer=o.footer~=false
    local avail=imgui.GetContentRegionAvail()
    local reserved=footer and(o.footer_height or 42)or 0
    local max_height=math.max(30,avail.y-reserved)
    local h=o.height and o.height>0 and math.min(o.height,max_height)or max_height
    local s=V.scrolls[key]or{pending=0,y=0};V.scrolls[key]=s;s.height=h
    if imgui.BeginChild('##v22_list_'..key,imgui.ImVec2(0,h),false,imgui.WindowFlags.NoScrollbar)then
        V.apply_font()
        if s.reset then imgui.SetScrollY(0);s.reset=false end
        if(s.pending or 0)~=0 then
            imgui.SetScrollY(DSP.clamp((imgui.GetScrollY()or 0)+s.pending,0,imgui.GetScrollMaxY()or 0));s.pending=0
        end
        s.y=imgui.GetScrollY()or 0
        local ok,err=xpcall(function()draw(imgui.GetContentRegionAvail().x,h,s.y)end,debug.traceback)
        if not ok then imgui.EndChild();error(err,0)end
        M.touch_scroll(imgui.GetIO(),'v293_'..key)
    end
    imgui.EndChild()
    if footer then
        if o.toolbar then imgui.Separator();o.toolbar(key)
        elseif o.scroll_buttons==true then
            imgui.Separator();V.scroll_buttons(key)
            if type(o.footer)=='function'then V.inline();o.footer()
            elseif o.count then V.inline();V.muted(tostring(o.count)..' записей')end
        elseif type(o.footer)=='function'then imgui.Separator();o.footer()
        elseif o.count then imgui.Separator();V.muted(tostring(o.count)..' записей')end
    end
end
return true
