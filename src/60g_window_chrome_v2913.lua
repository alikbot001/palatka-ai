-- v2.9.13: full free title-strip dragging and centered window openings.
-- Additive to the stable shell: no duplicate ImGui window or input overlay.
local V,U,M=DSP.ui21,DSP.ui,DSP.mobile
if not (V and U and type(V.geometry)=='function'
    and type(V.text_button)=='function' and type(V.popup)=='function') then
    return false
end
if V._window_chrome_2913 then return true end
local function viewport()
    if not (imgui and imgui.GetIO)then return nil end
    local ok,io=pcall(imgui.GetIO)
    if not ok or not io or not io.DisplaySize then return nil end
    local w,h=tonumber(io.DisplaySize.x),tonumber(io.DisplaySize.y)
    if not w or not h or w<=0 or h<=0 then return nil end
    return w,h
end
local function centered(sw,sh,w,h)
    return math.max(0,(sw-w)*.5),math.max(0,(sh-h)*.5)
end
-- Leave a visible 18-pixel strip above the main title bar. This also
-- recovers offscreen/negative saved positions after screen rotation.
local old_geometry=V.geometry
V.geometry=function(sw,sh)
    local g=old_geometry(sw,sh)
    local available=math.max(0,sh-g.h)
    local top=math.min(18,available)
    g.y=DSP.clamp(tonumber(g.y)or top,top,available)
    g.x=DSP.clamp(tonumber(g.x)or 0,0,math.max(0,sw-g.w))
    return g
end
-- The shell already checks IsItemActive and MouseDelta immediately after
-- carbon_title. Widen THAT SAME native button into all unoccupied header
-- space; do not add an overlapping invisible hitbox or hijack menu/X.
local old_text_button=V.text_button
V.text_button=function(label,id,width,active,height)
    if id=='carbon_title' then
        local sw,sh=viewport()
        if sw and imgui.GetCursorPosX then
            local g=V.geometry(sw,sh)
            local cursor=tonumber(imgui.GetCursorPosX())or 0
            -- Matches shell header's menu_x=(window width-56)-85.
            local free=g.w-141-cursor-8
            width=math.max(1,free)
        end
        -- A tap on the drag surface must not navigate to Home.
        -- The independent P brand button remains the Home shortcut.
        old_text_button(label,id,width,active,height)
        return false
    end
    return old_text_button(label,id,width,active,height)
end
-- Reopening the MAIN window starts centered, retaining its resized size.
-- During an open session the user's drag position remains untouched.
if type(U.set_open)=='function' then
    local old_set_open=U.set_open
    U.set_open=function(open)
        if open and not U.open then
            local sw,sh=viewport()
            if sw then
                local g=V.geometry(sw,sh)
                local x,y=centered(sw,sh,g.w,g.h)
                local top=math.min(18,math.max(0,sh-g.h))
                DSP.settings.mobile_window={x=x,y=math.max(top,y),w=g.w,h=g.h}
                if M and M.defer_save then M.defer_save()end
            end
        end
        return old_set_open(open)
    end
end
-- A modal is centered on EACH opening, rather than reusing stale x/y
-- from its last drag. Once open it remains draggable by its native strip.
local old_open_popup=V.open_popup
local recenter,popup_open={},{}
V.open_popup=function(title,id,...)
    recenter[id]=true
    return old_open_popup(title,id,...)
end
local old_popup=V.popup
V.popup=function(title,id,draw,size)
    size=size or {}
    local key=DSP.utf8(tostring(title or ''))..'##v22_'..tostring(id)
    local opened=false
    if imgui.IsPopupOpen then
        local ok,visible=pcall(imgui.IsPopupOpen,key)
        opened=ok and visible==true
    elseif recenter[id] then opened=true end
    if opened and (recenter[id] or not popup_open[id]) then
        local sw,sh=viewport()
        if sw then
            local saved=type(DSP.settings.ui_windows)=='table' and DSP.settings.ui_windows[id] or nil
            local remembered=V.popup_sizes and V.popup_sizes[id] or nil
            local w=tonumber((remembered and remembered.w)or(saved and saved.w)or size.w)or 620
            local h=tonumber((remembered and remembered.h)or(saved and saved.h)or size.h)or 410
            w=math.max(1,math.min(w,math.max(1,sw-24)))
            h=math.max(1,math.min(h,math.max(1,sh-24)))
            local x,y=centered(sw,sh,w,h)
            V.popup_positions=V.popup_positions or {}
            V.popup_positions[id]={x=x,y=y}
        end
        recenter[id]=nil
    end
    popup_open[id]=opened
    return old_popup(title,id,draw,size)
end
V._window_chrome_2913=true
return true
