-- UI 2.1: one compact touch workspace. Engine remains unchanged.
-- Visual reference: docs/design/REFERENCE_UI.html. This module owns ONLY
-- navigation/window layout, never market parsing or trade execution.
local ffi=require('ffi')
local U,M=DSP.ui,DSP.mobile
local V={screen='palatka',kind='sell',tab='items',source='inventory',nav=false,
    pages={},searches={},drawers={},show_review=false,show_preset_manage=false}
DSP.ui21=V
local function u(s) return DSP.utf8(tostring(s or '')) end
local function cp(s) return DSP.to_cp(tostring(s or '')) end
function V.button(label,id,width,active,primary,height)
    local accent=DSP.theme.col('accent',.88)
    if active or primary then imgui.PushStyleColor(imgui.Col.Button,accent) end
    local avail=(imgui.GetContentRegionAvail and imgui.GetContentRegionAvail().x) or 700
    local w=width or -1
    if w>0 then w=math.max(24,math.min(w,math.max(24,avail))) end
    local hit=imgui.Button(u(label)..'##v21_'..id,imgui.ImVec2(w,height or 35))
    if active or primary then imgui.PopStyleColor(1) end
    return hit
end
function V.inline(spacing) imgui.SameLine(0,spacing or 5) end
function V.text(s) imgui.Text(u(s)) end
function V.muted(s) imgui.TextDisabled(u(s)) end
function V.green(s) imgui.TextColored(DSP.theme.col('good',1),u(s)) end
function V.red(s) imgui.TextColored(DSP.theme.col('bad',1),u(s)) end
function V.search(key,hint,width)
    local b=V.searches[key]
    if not b then b=imgui.new.char[160]();V.searches[key]=b end
    imgui.SetNextItemWidth(width or math.max(110,imgui.GetContentRegionAvail().x))
    local edited=imgui.InputTextWithHint('##v21_query_'..key,u(hint),b,160)
    if edited then V.pages[key]=1 end
    return DSP.trim(cp(ffi.string(b))),edited
end
function V.selected_page(key,n,per)
    local max=math.max(1,math.ceil(n/per))
    local page=math.max(1,math.min(max,V.pages[key] or 1))
    V.pages[key]=page
    return (page-1)*per+1,math.min(n,page*per),page,max
end
function V.pager(key,count,per)
    local _,_,page,max=V.selected_page(key,count,per)
    if max<=1 then return end
    local w=math.min(105,math.max(60,imgui.GetContentRegionAvail().x/4))
    if V.button('‹','prev_'..key,w,false,false,30) then V.pages[key]=math.max(1,page-1) end
    V.inline();V.muted(page..' / '..max);V.inline()
    if V.button('›','next_'..key,w,false,false,30) then V.pages[key]=math.min(max,page+1) end
end
function V.set_screen(id)
    V.screen=id
    V.nav=false
    if DSP.screens and DSP.screens.set then DSP.screens.set(id) end
    M.reset_scroll=true
end
local nav={{'palatka','Торговля'},{'lavki','Лавки'},{'arbitrage','Арбитраж'},
    {'search','Поиск товара'},{'calculator','Калькулятор'},
    {'logs','История'},{'stats','Статистика'},{'notes','Заметки'},
    {'settings','Настройки'}}
local function drawer()
    for i,entry in ipairs(nav) do
        if V.button(entry[2],'menu_'..i,-1,V.screen==entry[1],false,38) then
            V.set_screen(entry[1])
        end
    end
end
-- Do not override M.geometry globally: other overlays have their own sizes.
function V.geometry(sw,sh)
    local stored=DSP.settings.mobile_window or {}
    local w=DSP.clamp(tonumber(stored.w) or math.min(sw*.91,1140),math.min(sw,570),math.min(sw,1450))
    local h=DSP.clamp(tonumber(stored.h) or math.min(sh*.78,610),math.min(sh,320),math.min(sh,790))
    local x=DSP.clamp(tonumber(stored.x) or (sw-w)*.07,0,math.max(0,sw-w))
    local y=DSP.clamp(tonumber(stored.y) or (sh-h)*.08,0,math.max(0,sh-h))
    return {x=x,y=y,w=w,h=h}
end
function V.mode_header()
    local w=imgui.GetContentRegionAvail().x
    if V.button(V.nav and 'x' or 'Меню','drawer',53,V.nav,false,31) then V.nav=not V.nav end
    V.inline()
    V.button('PALATKA AI  v2.1','drag',177,false,false,31)
    if imgui.IsItemActive and imgui.IsItemActive() then
        local io=imgui.GetIO()
        local delta=io.MouseDelta or {x=0,y=0}
        if delta.x~=0 or delta.y~=0 then
            local size=io.DisplaySize
            local g=V.geometry(size.x,size.y)
            local p=DSP.settings.mobile_window or {}
            p.x=DSP.clamp(g.x+delta.x,0,math.max(0,size.x-g.w))
            p.y=DSP.clamp(g.y+delta.y,0,math.max(0,size.y-g.h))
            p.w,p.h=g.w,g.h
            DSP.settings.mobile_window=p
            M.defer_save()
        end
    end
    if w>520 then
        V.inline();V.muted('• '..tostring(DSP.market.state.sid or '?')..'  ·  '..DSP.market.freshness())
    end
    V.inline()
    if V.button('x','close',45,false,false,31) then U.set_open(false) end
end
function V.footer()
    local w=imgui.GetContentRegionAvail().x
    if V.screen=='palatka' and V.trade_footer then
        return V.trade_footer(w)
    end
    if V.screen=='arbitrage' and V.arb_footer then return V.arb_footer(w) end
    if V.screen=='lavki' and V.shops_footer then return V.shops_footer(w) end
    if V.button('^','up',math.min(62,w*.16)) then M.queue_scroll(-1) end
    V.inline()
    if V.button('v','down',math.min(62,w*.16)) then M.queue_scroll(1) end
    V.inline()
    V.muted('Свайп по списку')
end
local prev_draw=U.draw
function U.draw()
    local io=imgui.GetIO()
    local size=io.DisplaySize
    local g=V.geometry(size.x,size.y)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(.97)
    local colors=DSP.theme.push_window()
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(8,7))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,4))
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding,imgui.ImVec2(7,4))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,9)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,5)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+
        imgui.WindowFlags.NoMove+imgui.WindowFlags.NoSavedSettings
    if U.tab~=DSP.screens.index_by_id(V.screen) then U.tab=DSP.screens.index_by_id(V.screen) end
    M.flush_save(false)
    if imgui.Begin('##palatka_mobile',U.open_ref,flags) then
        if imgui.SetWindowFontScale then imgui.SetWindowFontScale(.91) end
        V.mode_header()
        imgui.Separator()
        local remaining=imgui.GetContentRegionAvail().y
        local content_h=math.max(105,remaining-46)
        if V.nav then
            local navw=math.min(190,math.max(130,g.w*.23))
            M.child('v21_nav',navw,content_h,drawer)
            V.inline()
        end
        local shown=imgui.BeginChild('##v21_content_'..V.screen,
            imgui.ImVec2(0,content_h),false)
        if shown then
            if M.reset_scroll and imgui.SetScrollY then imgui.SetScrollY(0);M.reset_scroll=false end
            if M.scroll_delta and M.scroll_delta~=0 and imgui.SetScrollY then
                imgui.SetScrollY(DSP.clamp((imgui.GetScrollY() or 0)+M.scroll_delta,0,
                    (imgui.GetScrollMaxY and imgui.GetScrollMaxY()) or 1e7))
                M.scroll_delta=0
            end
            local ok,err=pcall(function()
                if V.screen=='palatka' then V.trade()
                elseif V.screen=='lavki' then V.shops()
                elseif V.screen=='arbitrage' then V.arbitrage()
                elseif V.screen=='calculator' then V.calculator()
                elseif V.screen=='logs' then V.journal()
                else DSP.screens.draw(V.screen) end
            end)
            if not ok then
                DSP.flog('UI21 screen '..tostring(V.screen)..' '..tostring(err))
                V.red('Ошибка экрана. См. standalone.log')
            end
            M.touch_scroll(io,'v21_content_'..V.screen)
        end
        imgui.EndChild()
        imgui.Separator()
        V.button('Размер','resize',74,false,false,35)
        if imgui.IsItemActive and imgui.IsItemActive() then
            local delta=io.MouseDelta or {x=0,y=0}
            if delta.x~=0 or delta.y~=0 then
                local right=g.x+g.w
                local new_w=DSP.clamp(g.w-delta.x,math.min(size.x,570),math.min(size.x,1450))
                local new_h=DSP.clamp(g.h+delta.y,math.min(size.y,320),math.min(size.y,790))
                DSP.settings.mobile_window={x=math.max(0,right-new_w),y=g.y,w=new_w,h=new_h}
                M.defer_save()
            end
        end
        V.inline(4)
        V.footer()
        if V.popups then V.popups() end
    end
    imgui.End()
    imgui.PopStyleVar(5)
    if colors and colors>0 then imgui.PopStyleColor(colors) end
    if U.open_ref and not U.open_ref[0] then M.flush_save(true); U.open=false end
end
-- Support legacy page switching commands, without two competing nav systems.
local old_set=DSP.screens.set
DSP.screens.set=function(id)
    if id then V.screen=id end
    return old_set(id)
end
