-- Mobile workspace v2.2. Lists own their scrolling; headers never scroll.
local ffi=require('ffi')
local U,M=DSP.ui,DSP.mobile
local V={screen='home',kind='sell',tab='items',source='inventory',nav=false,
    pages={},searches={},scrolls={},cache={},errors={}}
DSP.ui21=V;DSP.ui22=V
local function u(s)return DSP.utf8(tostring(s or ''))end
function V.inline(gap)imgui.SameLine(0,gap or 6)end
function V.text(s)imgui.Text(u(s))end
function V.muted(s)imgui.TextDisabled(u(s))end
function V.green(s)imgui.TextColored(DSP.theme.col('good',1),u(s))end
function V.red(s)imgui.TextColored(DSP.theme.col('bad',1),u(s))end
function V.fit(s,width)
    s=tostring(s or '')
    if not imgui.CalcTextSize then return s end
    if imgui.CalcTextSize(u(s)).x<=width then return s end
    -- Source is CP1251 on device, UTF-8 in headless tests: truncate at a boundary.
    local cut=s
    while #cut>0 and imgui.CalcTextSize(u(cut..'...')).x>width do
        cut=cut:sub(1,-2)
    end
    return cut..'...'
end
function V.button(label,id,width,active,primary,height)
    if active or primary then imgui.PushStyleColor(imgui.Col.Button,DSP.theme.col('accent',primary and 1 or .30))end
    if primary then imgui.PushStyleColor(imgui.Col.Text,DSP.theme.col('bg',1))end
    local avail=imgui.GetContentRegionAvail().x
    local w=width or -1
    if w>0 then w=math.max(1,math.min(w,avail)) end
    local visible=label
    if w>0 then visible=V.fit(label,math.max(1,w-16))end
    local hit=imgui.Button(u(visible)..'##v22_'..id,imgui.ImVec2(w,height or 42))
    if primary then imgui.PopStyleColor(1)end
    if active or primary then imgui.PopStyleColor(1)end
    -- A finger that moved to scroll must not activate the row on release.
    return hit and not V.dragged
end
function V.text_button(label,id,width,active,height)
    imgui.PushStyleColor(imgui.Col.Button,imgui.ImVec4(0,0,0,0))
    imgui.PushStyleVarVec2(imgui.StyleVar.ButtonTextAlign,imgui.ImVec2(.02,.5))
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding,imgui.ImVec2(8,0))
    local hit=V.button(label,id,width,active,false,height)
    imgui.PopStyleVar(2);imgui.PopStyleColor(1)
    return hit
end
function V.apply_font(pixels)
    if not imgui.SetWindowFontScale then return end
    -- A child inherits its ancestors' scales in native ImGui. Reset its local
    -- multiplier, measure that inherited size, then apply only the missing ratio.
    imgui.SetWindowFontScale(1)
    local inherited=imgui.GetFontSize and imgui.GetFontSize()or 16
    imgui.SetWindowFontScale((pixels or V.font_pixels or 18)/math.max(1,inherited))
end
function V.heading(title,right,width)
    local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
    local avail=imgui.GetContentRegionAvail().x
    V.apply_font((V.font_pixels or 18)*1.13)
    V.text(title)
    V.apply_font()
    if right then V.at(x+math.max(0,avail-width),y);right()end
    V.at(x,y+46)
end
function V.search(key,hint,width)
    local b=V.searches[key]
    if not b then b=imgui.new.char[160]();V.searches[key]=b end
    imgui.SetNextItemWidth(width or -1)
    local edited=imgui.InputTextWithHint('##v22_query_'..key,u(hint),b,160)
    if edited then V.reset_list(key)end
    return DSP.trim(DSP.to_cp(ffi.string(b))),edited
end
function V.memo(key,signature,build)
    local c=V.cache[key]
    if not c or c.signature~=signature then c={signature=signature,value=build()};V.cache[key]=c end
    return c.value
end
function V.reset_list(key)V.scrolls[key]={pending=0,reset=true,y=0}end
function V.queue_scroll(key,direction,height)
    local s=V.scrolls[key] or {y=0};V.scrolls[key]=s
    s.pending=(s.pending or 0)+direction*math.max(96,math.floor((height or s.height or 260)*.75))
end
local function arrow(key,up)
    local p=imgui.GetCursorScreenPos and imgui.GetCursorScreenPos()
    local draw=p and imgui.GetWindowDrawList and imgui.GetColorU32
    local hit=V.button(draw and '' or (up and '^' or 'v'),(up and 'scroll_up_'or'scroll_down_')..key,60)
    if draw then
        local x,y=p.x+30,p.y+21;local d=up and -1 or 1
        imgui.GetWindowDrawList():AddTriangleFilled(imgui.ImVec2(x-8,y-d*4),
            imgui.ImVec2(x+8,y-d*4),imgui.ImVec2(x,y+d*7),imgui.GetColorU32(imgui.Col.Text))
    end
    return hit
end
function V.scroll_buttons(key)
    local s=V.scrolls[key] or {}
    if imgui.PushButtonRepeat then imgui.PushButtonRepeat(true)end
    if arrow(key,true)then V.queue_scroll(key,-1,s.height)end
    V.inline()
    if arrow(key,false)then V.queue_scroll(key,1,s.height)end
    if imgui.PopButtonRepeat then imgui.PopButtonRepeat()end
end

function V.visible_range(count,row_height,scroll,height)
    local first=math.max(1,math.floor(scroll/row_height))
    return first,math.min(count,math.ceil((scroll+height)/row_height)+2)
end
function V.list(key,draw,options)
    V.track_touch(imgui.GetIO())
    local o=options or {};local footer=o.footer~=false
    local avail=imgui.GetContentRegionAvail()
    local h=o.height and o.height>0 and o.height or math.max(36,avail.y-(footer and (o.footer_height or 50) or 0))
    local s=V.scrolls[key] or {pending=0,y=0};V.scrolls[key]=s;s.height=h
    local flags=imgui.WindowFlags.NoScrollbar
    if imgui.BeginChild('##v22_list_'..key,imgui.ImVec2(0,h),false,flags)then
        V.apply_font()
        if s.reset then imgui.SetScrollY(0);s.reset=false end
        if (s.pending or 0)~=0 then
            imgui.SetScrollY(DSP.clamp((imgui.GetScrollY()or 0)+s.pending,0,imgui.GetScrollMaxY()or 0));s.pending=0
        end
        s.y=imgui.GetScrollY()or 0
        local ok,err=xpcall(function()draw(imgui.GetContentRegionAvail().x,h,s.y)end,debug.traceback)
        if not ok then imgui.EndChild();error(err,0)end
        if M.touch_scroll then M.touch_scroll(imgui.GetIO(),'v22_'..key)end
    end
    imgui.EndChild()
    if footer then
        imgui.Separator()
        if o.toolbar then o.toolbar(key)else
            V.scroll_buttons(key)
            if type(o.footer)=='function'then V.inline();o.footer()
            elseif o.count then V.inline();V.muted(tostring(o.count)..' записей')end
        end
    end
end
function V.list_rows(key,rows,row_height,draw,options)
    V.list(key,function(w,h,y)
        local first,last=V.visible_range(#rows,row_height,y,h)
        local start=imgui.GetCursorPosY()
        -- Cursor positioning preserves a full virtual extent without drawing hidden rows.
        for i=first,last do
            imgui.SetCursorPosY(start+(i-1)*row_height)
            draw(rows[i],i,w)
        end
        imgui.SetCursorPosY(start+#rows*row_height)
        imgui.Dummy(imgui.ImVec2(1,1))
        if #rows==0 then imgui.SetCursorPosY(start);V.muted('Нет записей')end
    end,options)
end
function V.row(id,height,draw)
    local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
    local w=imgui.GetContentRegionAvail().x
    if imgui.GetWindowDrawList and imgui.GetCursorScreenPos and imgui.GetColorU32 then
        local p=imgui.GetCursorScreenPos()
        local custom=DSP.carbon_draw and DSP.carbon_draw.row and DSP.carbon_draw.row(p.x,p.y,w,height-4)
        if not custom then
            local dl=imgui.GetWindowDrawList()
            dl:AddRectFilled(p,imgui.ImVec2(p.x+w,p.y+height-4),imgui.GetColorU32(imgui.Col.FrameBg),6)
            if dl.AddRect then dl:AddRect(p,imgui.ImVec2(p.x+w,p.y+height-4),imgui.GetColorU32(imgui.Col.Border),6)end
        end
    end
    imgui.PushIDStr(id);imgui.SetCursorPos(imgui.ImVec2(x+8,y+5))
    local ok,err=xpcall(function()draw(w-16,x+8,y+5)end,debug.traceback)
    imgui.PopID();if not ok then error(err,0)end;imgui.SetCursorPos(imgui.ImVec2(x,y+height))
end
function V.at(x,y)imgui.SetCursorPos(imgui.ImVec2(x,y))end
-- One consistent window chrome for every modal: close at the top-right.
-- A modal can always be dismissed without traversing a sequence of Back buttons.
-- Keep the native ImGui resize grip enabled (NoResize is intentionally absent).
function V.popup(title,id,draw,size)
    size=size or {}
    local sz=imgui.GetIO().DisplaySize
    imgui.SetNextWindowPos(imgui.ImVec2(sz.x*.5,sz.y*.5),imgui.Cond.Appearing,imgui.ImVec2(.5,.5))
    imgui.SetNextWindowSize(imgui.ImVec2(math.min(size.w or 620,sz.x-24),math.min(size.h or 410,sz.y-24)),imgui.Cond.Appearing)
    local flags=imgui.WindowFlags.NoTitleBar + (size.resizable and imgui.WindowFlags.NoScrollbar or 0)
    if imgui.BeginPopupModal(u(title)..'##v22_'..id,nil,flags)then
        V.apply_font()
        local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
        local avail=imgui.GetContentRegionAvail().x
        V.text(V.fit(title,math.max(60,avail-55)))
        -- Position independent of the previous widgets; old 'Закрыть' buttons remain
        -- for compatibility, but every modal gets exactly the same close affordance.
        V.at(x+math.max(0,avail-42),y)
        local close=V.button('X','modal_x_'..id,40,false,false,34)
        V.at(x,y+39)
        imgui.Separator()
        if close then
            imgui.CloseCurrentPopup()
        elseif size.resizable then
            V.list('modal_'..id,function()draw()end,{footer=true})
        else
            draw()
        end
        imgui.EndPopup()
    end
end
function V.open_popup(title,id)
    -- Open and Begin must share an ImGui ID stack, even for a row inside a child.
    V.popup_pending={title=title,id=id}
end
function V.cancel(id)
    if V.button('Отмена','cancel_'..id,120)then imgui.CloseCurrentPopup()end
end
function V.geometry(sw,sh)
    local p=DSP.settings.mobile_window or {}
    local w=DSP.clamp(tonumber(p.w)or math.min(sw*.93,1120),math.min(sw,560),sw)
    local h=DSP.clamp(tonumber(p.h)or sh*.88,math.min(sh,330),sh)
    return {w=w,h=h,x=DSP.clamp(tonumber(p.x)or (sw-w)*.5,0,math.max(0,sw-w)),
        y=DSP.clamp(tonumber(p.y)or (sh-h)*.35,0,math.max(0,sh-h))}
end
local nav={{'palatka','Торговля'},{'lavki','Лавки'},{'arbitrage','Арбитраж'},
 {'resale','Перепродажа'},{'promo','Авто-пиар'},{'scan','Скан лавки'},
 {'search','Поиск товара'},{'calculator','Калькулятор'},{'logs','Журнал'},
 {'stats','Статистика'},{'notes','Заметки'},{'storage','Хранилища'},
 {'market','Рынок'},{'history','История'},{'settings','Настройки'}}
function V.set_screen(id)
    if U._notes_dirty and M.save_notes and not M.save_notes()then return false end
    V.screen=id;V.nav=false
    if DSP.screens and DSP.screens.set then DSP.screens.set(id)end
end
local function header(g,io)
    local x0,y0=imgui.GetCursorPosX(),imgui.GetCursorPosY()
    -- Absolute positions: the global X never escapes the right edge, even when
    -- the server label becomes long or the user narrows the window.
    local close_x=g.w-56
    local menu_x=close_x-85
    if V.button('P','carbon_brand',40,false,true,36)then V.set_screen('home')end
    V.at(x0+47,y0)
    if V.text_button('PALATKA AI','carbon_title',121,false,36)then V.set_screen('home')end
    if imgui.IsItemActive() and io.MouseDelta then
        local d=io.MouseDelta
        if d.x~=0 or d.y~=0 then
            DSP.settings.mobile_window={x=DSP.clamp(g.x+d.x,0,io.DisplaySize.x-g.w),
                y=DSP.clamp(g.y+d.y,0,io.DisplaySize.y-g.h),w=g.w,h=g.h}
            M.defer_save()
        end
    end
    V.at(x0+175,y0+11);V.muted('v'..tostring(DSP.version or '2.2'))
    if g.w>850 then
        V.at(math.max(x0+240,menu_x-244),y0+11)
        V.muted(V.fit('Arizona #'..tostring(DSP.market.state.sid or '?')..' · '..DSP.market.freshness(),230))
    end
    V.at(menu_x,y0)
    if V.button('Меню','menu',78,V.nav,false,36)then V.nav=not V.nav end
    V.at(close_x,y0)
    if V.button('X','close',40,false,false,36)then
        U.set_open(false)
    end
    V.at(x0,y0+44)
end
-- A real bottom-right drag handle: unlike the old top-bar [] button, it follows
-- the edge being resized. No native overlay, no FFI pointer arithmetic.
function V.resize_grip(g,io)
    local x,y=g.w-46,g.h-44
    V.at(x,y)
    local pos=imgui.GetCursorScreenPos and imgui.GetCursorScreenPos()
    V.button(' ','global_resize_grip',32,false,false,31)
    if pos and imgui.GetWindowDrawList and imgui.GetColorU32 then
        local dl=imgui.GetWindowDrawList()
        local col=imgui.GetColorU32(imgui.Col.Text)
        for i=0,2 do
            dl:AddLine(imgui.ImVec2(pos.x+15+i*5,pos.y+25),
                imgui.ImVec2(pos.x+27,pos.y+13+i*5),col,1.6)
        end
    end
    if imgui.IsItemActive() and io.MouseDelta then
        local d=io.MouseDelta
        if d.x~=0 or d.y~=0 then
            local w=DSP.clamp(g.w+d.x,math.min(560,io.DisplaySize.x),io.DisplaySize.x-g.x)
            local h=DSP.clamp(g.h+d.y,math.min(330,io.DisplaySize.y),io.DisplaySize.y-g.y)
            DSP.settings.mobile_window={x=g.x,y=g.y,w=w,h=h}
            M.defer_save()
        end
    end
end
function V.track_touch(io)
    local frame=imgui.GetFrameCount and imgui.GetFrameCount()
    if frame and V.touch_frame==frame then return end
    V.touch_frame=frame
    local down=io.MouseDown and io.MouseDown[0]
    if down then
        if not V.was_down then V.travel=0;V.dragged=false end
        local delta=io.MouseDelta or {x=0,y=0}
        V.travel=(V.travel or 0)+math.abs(delta.y)+math.abs(delta.x)
        V.dragged=V.travel>10
    elseif not V.was_down then V.dragged=false end
    V.was_down=down
end
function V.font_scale_for(base,width,dpi)
    return 18*(tonumber(dpi)or 1.25)/1.25*math.min(1.35,math.max(1,width/1000))/math.max(1,base)
end
function U.draw()
    if DSP.carbon_draw then DSP.carbon_draw.begin_frame() end
    local io=imgui.GetIO();local sz=io.DisplaySize;local g=V.geometry(sz.x,sz.y)
    if not V.initialized then V.screen=(U.screen and U.screen~='palatka') and U.screen or 'home';V.initialized=true end
    V.track_touch(io)
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    local colors=DSP.theme.push_window()
    imgui.SetNextWindowBgAlpha(DSP.theme.opacity or .97)
    if not V.style_reported and imgui.GetStyle then
        local c=imgui.GetStyle().Colors[imgui.Col.WindowBg]
        if c then DSP.flog(string.format('UI22 native bg %.3f %.3f %.3f %.3f colors=%d',c.x,c.y,c.z,c.w,colors or 0))end
        V.style_reported=true
    end
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(9,7))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(6,5))
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding,imgui.ImVec2(8,10))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,5)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,5)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoScrollbar
    M.flush_save(false)
    if imgui.Begin('##palatka_mobile',U.open_ref,flags)then
        -- Shared native atlases differ between loaders; normalize actual pixels.
        V.font_pixels=V.font_scale_for(1,g.w,U.d)
        V.apply_font()
        header(g,io);imgui.Separator()
        local wide=g.w>=650
        local show_side=V.nav or wide
        local drawer_only=V.nav and not wide
        if show_side then
            local h=imgui.GetContentRegionAvail().y-48
            if imgui.BeginChild('##v22_carbon_nav',imgui.ImVec2(drawer_only and 0 or math.min(182,g.w*.25),h),true,imgui.WindowFlags.NoScrollbar)then
                V.apply_font()
                V.muted('НАВИГАЦИЯ')
                if V.button('Главная','carbon_home_nav',-1,V.screen=='home',V.screen=='home',43)then V.set_screen('home')end
                V.list_rows('navigation',nav,44,function(e,i)
                    local symbols={palatka='= ',lavki='# ',arbitrage='> ',resale='* ',promo='@ ',scan='[] ',
                        search='? ',calculator='+ ',logs='| ',stats='% ',notes='- ',storage='[] ',market='$ ',history=': ',settings=': '}
                    if V.button((symbols[e[1]] or ' ')..e[2],'nav_'..i,-1,V.screen==e[1],V.screen==e[1],42)then V.set_screen(e[1])end
                end,{height=math.max(70,imgui.GetContentRegionAvail().y-85),footer=true})
                if imgui.GetContentRegionAvail().y>25 then V.muted('  PALATKA AI · LIVE')end
            end
            imgui.EndChild()
            if not drawer_only then V.inline(4)end
        end
        if not drawer_only then
            -- Workspace and global footer are separate, as in the supplied Carbon HTML.
            if imgui.BeginChild('##v22_workspace',imgui.ImVec2(0,-48),false,imgui.WindowFlags.NoScrollbar)then
                V.apply_font()
                local ok,err=xpcall(function()
                    if V.screen=='home'then V.home()
                    elseif V.screen=='storage'then V.storage_screen()
                    elseif V.screen=='scan'then V.shops_source='scan';V.shops()
                    elseif V.screen=='market'then V.shops_source='api';V.shops()
                    elseif V.screen=='history'then V.journal_mode='events';V.journal()
                    elseif V.screen=='palatka'then V.trade()
                    elseif V.screen=='lavki'then V.shops()
                    elseif V.screen=='arbitrage'then V.arbitrage()
                    elseif V.screen=='resale'then V.flip_screen()
                    elseif V.screen=='promo'then V.promo_screen()
                    elseif V.screen=='logs'then V.journal()
                    elseif V.screen=='calculator'then V.calculator()
                    elseif V.tools then V.tools(V.screen)
                    else DSP.screens.draw(V.screen)end
                end,debug.traceback)
                if not ok then
                    V.last_error=err
                    if V.errors[V.screen]~=err then DSP.flog('UI22 '..err)end
                    V.errors[V.screen]=err;V.red('Ошибка экрана. Подробности в standalone.log')
                end
            end
            imgui.EndChild()
            imgui.Separator()
            if V.button('Окна','carbon_windows',100,false,true,38)then V.nav=not V.nav end
            V.inline()
            local remain=imgui.GetContentRegionAvail().x
            V.muted(V.fit('Palatka AI · '..tostring(DSP.market.state.status or 'offline')..' · без автоматических сделок',math.max(40,remain-6)))
        end
        if V.popup_pending then
            local p=V.popup_pending;V.popup_pending=nil;imgui.OpenPopup(u(p.title)..'##v22_'..p.id)
        end
        if V.popups then V.popups()end
        V.resize_grip(g,io)
    end
    imgui.End();imgui.PopStyleVar(5)
    if colors and colors>0 then imgui.PopStyleColor(colors)end
    if U.open_ref and not U.open_ref[0]then M.flush_save(true);U.open=false end
end
-- Compatibility entry points preserve old commands and numbered screens.
local old_set=DSP.screens.set
DSP.screens.set=function(id)V.screen=id or 'palatka';return old_set(id)end
function V.selected_page(key,n,per)
    local max=math.max(1,math.ceil(n/per));local page=math.max(1,math.min(max,V.pages[key]or 1))
    V.pages[key]=page;return(page-1)*per+1,math.min(n,page*per),page,max
end
