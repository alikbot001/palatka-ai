-- Touch shell. Keep the lower game interaction strip outside this window.
local ffi = require('ffi')
DSP.mobile = {}
local M = DSP.mobile
function M.scale() return tonumber(DSP.ui.d) or 1.25 end
function M.geometry(sw, sh)
    local saved=DSP.settings.mobile_window or {}
    local s=math.min(sw/2340,sh/1080)
    return {x=sw*.03,y=sh*.03,w=DSP.clamp(tonumber(saved.w) or sw*.80,math.min(1100,sw),sw),
        h=DSP.clamp(tonumber(saved.h) or sh*.70,math.min(550,sh),sh),nav=math.max(176,214*s),touch=math.max(56,60*s)}
end
function M.window_position(sw,sh)
    local g=M.geometry(sw,sh)
    local saved=DSP.settings.mobile_window or {x=g.x,y=g.y}
    return {x=DSP.clamp(tonumber(saved.x) or g.x,0,math.max(0,sw-g.w)),
        y=DSP.clamp(tonumber(saved.y) or g.y,0,math.max(0,sh-g.h)),w=g.w,h=g.h}
end
function M.move_window(dx,dy,sw,sh)
    local pos=M.window_position(sw,sh)
    pos.x=pos.x+dx;pos.y=pos.y+dy;DSP.settings.mobile_window=pos
    DSP.settings.mobile_window=M.window_position(sw,sh)
    M.window_dirty=true;M.position_pending=true
end
function M.resize_window(dx,dy,sw,sh)
    local p=M.window_position(sw,sh)
    local right=p.x+p.w
    local w=DSP.clamp(p.w-dx,math.min(1100,sw),right)
    DSP.settings.mobile_window={x=right-w,y=p.y,w=w,h=DSP.clamp(p.h+dy,math.min(550,sh-p.y),sh-p.y)}
    M.window_dirty=true;M.position_pending=true
end
local function mix(a,b,t)
    return imgui.ImVec4(a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t,1)
end
function M.paint_button(role,active)
    local t=DSP.theme.get()
    local primary=role=='primary'
    local bg=primary and t.accent or {t.panel[1]+.05,t.panel[2]+.05,t.panel[3]+.05}
    if active and not primary then bg={t.panel[1]*.8+t.accent[1]*.2,t.panel[2]*.8+t.accent[2]*.2,t.panel[3]*.8+t.accent[3]*.2} end
    if role=='quiet' then bg=t.panel end
    imgui.PushStyleColor(imgui.Col.Button,mix(bg,bg,0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered,mix(bg,t.text,.10))
    imgui.PushStyleColor(imgui.Col.ButtonActive,mix(bg,t.accent,.30))
    imgui.PushStyleColor(imgui.Col.Text,primary and DSP.theme.col('bg',1) or DSP.theme.col(active and 'accent' or 'text',1))
end
function M.queue_scroll(direction)
    local h=(M.content_height or 480)
    -- Full visible page per press. The user never has to catch the scrollbar.
    local step=math.max(260,math.floor(h*.8))
    M.scroll_delta=(M.scroll_delta or 0)+direction*step
end
-- Accept vertical finger movement on empty areas or plain text in a scrolling
-- child. Never steal drags from text fields, sliders and other active controls.
function M.touch_scroll(io,screen)
    if not imgui.IsWindowHovered or not imgui.GetScrollY or not imgui.SetScrollY then return end
    local hovered=imgui.IsWindowHovered()
    local held=false
    if io and io.MouseDown then
        local ok,value=pcall(function() return io.MouseDown[0] end)
        held=ok and value and true or false
    end
    if not held then M._touch_active=false; M._touch_screen=nil;return end
    if not hovered then return end
    local active=imgui.IsAnyItemActive and imgui.IsAnyItemActive() or false
    if active then return end
    local delta=io.MouseDelta and io.MouseDelta.y or 0
    if M._touch_screen~=screen then M._touch_screen=screen;M._touch_active=true end
    if M._touch_active and math.abs(delta)>.01 then
        local max=imgui.GetScrollMaxY and imgui.GetScrollMaxY() or 100000
        imgui.SetScrollY(DSP.clamp((imgui.GetScrollY() or 0)-delta*1.15,0,max))
    end
end
-- UI edits are saved after a short idle period instead of writing JSON once
-- per keystroke (a noticeable delay on low-end Android storage).
function M.defer_save()
    M._save_pending=true
    M._last_edit=os.time()
end
function M.flush_save(force)
    if M._save_pending and (force or os.time()-(M._last_edit or 0)>=2) then
        M._save_pending=not DSP.save_settings()
    end
end
function M.scroll_rail(height)
    local h=math.max(48,(height-80)/2)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding,imgui.ImVec2(8,5))
    M.paint_button('rail',false)
    if imgui.Button(DSP.utf8('ВВЕРХ')..'##mobile_rail_up',imgui.ImVec2(-1,h)) then M.queue_scroll(-1) end
    if imgui.Button(DSP.utf8('ВНИЗ')..'##mobile_rail_down',imgui.ImVec2(-1,h)) then M.queue_scroll(1) end
    local step=tonumber(DSP.settings.scroll_step) or 300
    local name=step<=150 and 'короткий' or step<=300 and 'средний' or 'длинный'
    if imgui.Button(DSP.utf8('Шаг\n'..name)..'##scroll_step',imgui.ImVec2(-1,60)) then
        DSP.settings.scroll_step=step<=150 and 300 or step<=300 and 600 or 150
        DSP.save_settings()
    end
    imgui.PopStyleColor(4)
    imgui.PopStyleVar(1)
end
function M.text(s) imgui.TextWrapped(DSP.utf8(tostring(s or ''))) end
function M.title(s) imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8(s)) end
-- Images are optional; official item icons can be installed as
-- PalatkaAI/icons/items/<id>.png. Bundled category pictures are fallbacks.
M.icon_textures={}
M.icon_attempted={}
function M.item_icon_kind(it)
    local raw=tostring(it.name or '')
    if it._icon_raw==raw and it._icon_kind then return it._icon_kind end
    local n=DSP.lower(DSP.clean_text(raw))
    if n:find('аптеч',1,true) or n:find('бинт',1,true) or n:find('медицин',1,true) then it._icon_raw=raw;it._icon_kind='medical';return 'medical' end
    if n:find('патрон',1,true) or n:find('пистолет',1,true) or n:find('deagle',1,true) then return 'ammo' end
    if n:find('рюкзак',1,true) or n:find('сумка',1,true) then return 'bag' end
    if n:find('металл',1,true) or n:find('слиток',1,true) then return 'metal' end
    if n:find('пластик',1,true) or n:find('провод',1,true) or n:find('микросхем',1,true) then return 'electronics' end
    if n:find('бронежилет',1,true) then return 'armor' end
    if n:find('ключ',1,true) or n:find('отмычк',1,true) then return 'tool' end
    return 'other'
end
function M.thumbnail(it, size)
    size=size or 66
    local id=tonumber(it.id or it.item_id) or (DSP.items and DSP.items.id_for_name and DSP.items.id_for_name(it.name))
    local category=M.item_icon_kind(it)
    local paths={}
    if id and id>0 then paths[1]=DSP.dir..'/icons/items/'..math.floor(id)..'.png' end
    paths[#paths+1]=DSP.dir..'/icons/categories/'..category..'.png'
    if (imgui.CreateTextureFromFile or imgui.CreateTextureFromFileInMemory) and imgui.Image then
        for _,path in ipairs(paths) do
            local texture=M.icon_textures[path]
            if not texture and not M.icon_attempted[path] then
                M.icon_attempted[path]=true
                local f=io.open(path,'rb')
                if f then f:close()
                    local ok,result=false,nil
                    if imgui.CreateTextureFromFile then
                        ok,result=pcall(imgui.CreateTextureFromFile,path)
                    end
                    if (not ok or not result) and imgui.CreateTextureFromFileInMemory then
                        local src=io.open(path,'rb')
                        if src then
                            local raw=src:read('*a');src:close()
                            local data=ffi.new('uint8_t[?]',#raw)
                            ffi.copy(data,raw,#raw)
                            ok,result=pcall(imgui.CreateTextureFromFileInMemory,data,#raw)
                        end
                    end
                    if ok and result then M.icon_textures[path]=result; texture=result end
                end
            end
            if texture then
                local ok=pcall(imgui.Image,texture,imgui.ImVec2(size,size))
                if ok then return true end
            end
        end
    end
    -- Don't display the wrong item's artwork when no matching icon is available.
    imgui.TextColored(DSP.theme.col('muted',1),DSP.utf8('[ '..string.upper(category:sub(1,2))..' ]'))
    return false
end
function M.compact_number(it,key,id,width,minimum)
    local buf=M.edit_buffer(it,key)
    imgui.SetNextItemWidth(width or 140)
    if imgui.InputText('##compact_'..id,buf,64) then
        if M.apply_number(it,key,buf,minimum or 1) then M.defer_save(); return true end
    end
    return false
end

function M.button(label, id, width, active, role)
    M.paint_button(role or 'secondary',active)
    if role=='nav' then imgui.PushStyleVarVec2(imgui.StyleVar.ButtonTextAlign,imgui.ImVec2(.12,.5)) end
    local text=DSP.utf8(label)
    local measured=imgui.CalcTextSize(text).x+40
    local available=imgui.GetContentRegionAvail().x
    if width and width>0 then
        width=math.max(width,measured)
        if available<width then imgui.NewLine(); available=imgui.GetContentRegionAvail().x end
        width=math.min(width,available)
    end
    local hit = imgui.Button(text..'##mobile_'..id,
        imgui.ImVec2(width or -1, (M.layout and M.layout.touch) or 60))
    imgui.PopStyleColor(4)
    if role=='nav' then imgui.PopStyleVar(1) end
    return hit
end
function M.inline() imgui.SameLine(0, 12) end
function M.child(id, w, h, fn)
    local shown = imgui.BeginChild('##mobile_'..id, imgui.ImVec2(w or 0, h or 0), true)
    if shown then
        fn()
        M.touch_scroll(imgui.GetIO(),'child_'..id)
    end
    imgui.EndChild()
end
function M.toggle(label, parent, key, default)
    local value = parent[key]
    if value == nil then value=default end
    local b=imgui.new.bool(value and true or false)
    if imgui.Checkbox(DSP.utf8(label), b) then parent[key]=b[0]; DSP.save_settings(); return true end
    return false
end
M.buffers = setmetatable({}, {__mode='k'})
function M.edit_buffer(item, key)
    local cache=M.buffers[item]
    if not cache then cache={}; M.buffers[item]=cache end
    if not cache[key] then
        cache[key]=imgui.new.char[64]()
        local value=tostring(item[key] or 0)
        ffi.copy(cache[key], value, math.min(#value, 63))
    end
    return cache[key]
end
function M.apply_number(item,key,buf,minimum)
    local raw=ffi.string(buf)
    if not raw:match('^%d+$') then return false end
    local n=tonumber(raw)
    if not n or n < (minimum or 0) or n > 9007199254740991 then return false end
    item[key]=math.floor(n)
    return true
end
function M.number(label,id,item,key,minimum,width)
    imgui.TextDisabled(DSP.utf8(label))
    local buf=M.edit_buffer(item,key)
    imgui.SetNextItemWidth(width or 250)
    if imgui.InputText('##mobile_num_'..id,buf,64) then
        if M.apply_number(item,key,buf,minimum) then DSP.save_settings(); return true end
    end
    if not ffi.string(buf):match('^%d+$') then
        imgui.TextColored(DSP.theme.col('bad',1), DSP.utf8('Введите целое положительное число'))
    end
    return false
end
function M.refresh_buffer(item,key)
    if M.buffers[item] then M.buffers[item][key]=nil end
end
local set_screen = DSP.screens.set
function DSP.screens.set(id)
    local found=false
    for _,e in ipairs(DSP.screens.list) do if e.id==id then found=true end end
    set_screen(found and id or 'palatka')
    M.reset_scroll=true
end
DSP.screens.list[1].label='ПАЛАТКА'
DSP.screens.list[2].label='ЛАВКИ'
DSP.screens.list[6].label='СТАТИСТИКА'
DSP.screens.list[5].label='ИСТОРИЯ'
-- Four primary actions; less-used utilities remain under "More".
-- The original screen ids and routing remain unchanged for compatibility.
function DSP.screens.topbar()
    M.title('PALATKA  /  v'..tostring(DSP.version))
    imgui.Separator()
    local primary={
        {'palatka','Моя лавка'},
        {'arbitrage','Арбитраж'},
        {'logs','Журнал'},
        {'search','Поиск товара'},
    }
    for i,e in ipairs(primary) do
        if M.button(e[2],'nav_main_'..i,-1,DSP.ui.screen==e[1],'nav') then DSP.screens.set(e[1]) end
    end
    imgui.Separator()
    if M.button(M.more_open and 'Скрыть остальное' or 'Ещё', 'nav_more',-1,M.more_open,'nav') then
        M.more_open=not M.more_open
    end
    if M.more_open then
        for i,e in ipairs({
            {'lavki','Все лавки'},
            {'stats','Статистика'},
            {'notes','Заметки'},
            {'settings','Настройки'},
        }) do
            if M.button(e[2],'nav_extra_'..i,-1,DSP.ui.screen==e[1],'nav') then DSP.screens.set(e[1]) end
        end
    end
end
function M.draw_pager(total,per,id)
    total=math.max(0,tonumber(total) or 0)
    per=math.max(1,tonumber(per) or 8)
    local pages=math.max(1, math.ceil(total/per))
    local page=math.min(pages,DSP.screens.page_of(id))
    local width=math.min(230,(imgui.GetContentRegionAvail().x-24)/3)
    if M.button('< Назад','prev'..id,width) then page=math.max(1,page-1) end
    M.inline()
    local prefix=id=='trade_history' and 'Сделки ' or id=='stall_history' and 'Лавки ' or ''
    if M.button(prefix..page..' / '..pages,'page'..id,width) then page=1 end
    M.inline()
    if M.button('Вперёд >','next'..id,width) then page=math.min(pages,page+1) end
    DSP.screens.set_page(id,page)
    return (page-1)*per+1, math.min(total,page*per)
end
function DSP.screens.pager(total,per,id)
    if M.sticky then
        M.footers=M.footers or {}
        local found=false
        for _,entry in ipairs(M.footers) do
            if entry.id==id then entry.total=total; entry.per=per; found=true end
        end
        if not found then M.footers[#M.footers+1]={total=total,per=per,id=id} end
        local page=math.min(DSP.screens.page_of(id),math.max(1,math.ceil(total/per)))
        DSP.screens.set_page(id,page)
        return (page-1)*per+1,math.min(total,page*per)
    end
    return M.draw_pager(total,per,id)
end
local function workspace()
    local screen=DSP.ui.screen
    local entry=DSP.screens.list[DSP.screens.index_by_id(screen)]
    -- One compact header; the previous UI spent 150 px on a redundant scroll rail.
    imgui.TextColored(DSP.theme.col('text',1),DSP.utf8(entry.label))
    M.inline()
    if M.button('Закрыть','header_close',165) then DSP.ui.set_open(false) end
    M.footers={}
    local height=math.max(120,imgui.GetContentRegionAvail().y-66)
    M.content_height=height
    M.child('body_'..screen,0,height,function()
        if M.reset_scroll then
            if imgui.SetScrollY then imgui.SetScrollY(0) end
            M.reset_scroll=false
        end
        if (M.scroll_delta or 0)~=0 then
            local current=imgui.GetScrollY and imgui.GetScrollY() or 0
            local limit=imgui.GetScrollMaxY and imgui.GetScrollMaxY() or 1000000
            if imgui.SetScrollY then imgui.SetScrollY(DSP.clamp(current+M.scroll_delta,0,limit)) end
            M.scroll_delta=0
        end
        M.sticky=true
        DSP.screens.draw(screen)
        M.sticky=false
        M.touch_scroll(imgui.GetIO(),screen)
    end)
    if #M.footers>0 then
        for i,entry in ipairs(M.footers) do
            if i>1 then M.inline() end
            M.draw_pager(entry.total,entry.per,entry.id)
        end
    else
        if M.button('Листать вверх','content_page_up',225) then M.queue_scroll(-1) end
        M.inline()
        if M.button('Листать вниз','content_page_down',225) then M.queue_scroll(1) end
    end
end
function DSP.ui.header()
    local st=DSP.market.state
    M.title('РЫНОК / '..tostring(st.sid))
    M.text(string.format('%s | %d лавок | %d предложений | %s',
        st.status=='loading' and 'Загрузка' or st.status=='error' and 'Ошибка обновления' or 'База рынка',
        st.shops or 0,st.offers or 0,DSP.market.freshness()))
    if st.status=='error' then M.text(st.error or '') end
    if M.button('Обновить рынок','refresh',260) then DSP.market.pull(st.sid) end
    imgui.Separator()
end
function DSP.ui.draw()
    local io=imgui.GetIO()
    local sz=io and io.DisplaySize or {x=2340,y=1080}
    local g=M.geometry(sz.x,sz.y)
    M.layout=g
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    local pos=M.window_position(sz.x,sz.y)
    local changed=M.last_viewport~=tostring(sz.x)..':'..tostring(sz.y)
    imgui.SetNextWindowPos(imgui.ImVec2(pos.x,pos.y),
        (M.position_pending or changed) and imgui.Cond.Always or imgui.Cond.FirstUseEver)
    M.position_pending=false; M.last_viewport=tostring(sz.x)..':'..tostring(sz.y)
    imgui.SetNextWindowBgAlpha(DSP.theme.opacity)
    local colors=DSP.theme.push_window()
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding,imgui.ImVec2(14,11))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(10,8))
    if DSP.ui.tab~=DSP.screens.index_by_id(DSP.ui.screen) then DSP.screens.set_index(DSP.ui.tab) end
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,14)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,10)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding,12)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize
        +imgui.WindowFlags.NoSavedSettings
    M.flush_save(false)
    if imgui.Begin('##palatka_mobile',DSP.ui.open_ref,flags) then
        if imgui.SetWindowFontScale then imgui.SetWindowFontScale(1.05 * M.scale() / 1.25) end
        M.paint_button('quiet',false)
        imgui.Button(DSP.utf8('PALATKA AI   /   ДВИГАТЬ ОКНО'),imgui.ImVec2(-1,42))
        imgui.PopStyleColor(4)
        local handle_active=false
        if imgui.IsItemActive and imgui.IsItemActive() then
            handle_active=true
            local delta=io.MouseDelta or {x=0,y=0}
            if delta.x~=0 or delta.y~=0 then M.move_window(delta.x,delta.y,sz.x,sz.y) end
        end
        if imgui.GetWindowPos and not M.position_pending then
            local actual=imgui.GetWindowPos()
            if actual and (actual.x~=pos.x or actual.y~=pos.y) then
                DSP.settings.mobile_window={x=actual.x,y=actual.y,w=g.w,h=g.h}
                local clamped=M.window_position(sz.x,sz.y)
                if clamped.x~=actual.x or clamped.y~=actual.y then
                    DSP.settings.mobile_window=clamped; M.position_pending=true
                end
                M.window_dirty=true
            end
        end
        local content_height=math.max(200,imgui.GetContentRegionAvail().y-50)
        M.child('navigation',g.nav,content_height,DSP.screens.topbar)
        M.inline()
        M.child('content_'..DSP.ui.screen,0,content_height,workspace)
        M.paint_button('quiet',false)
        imgui.Button(DSP.utf8('/  Размер окна'),imgui.ImVec2(220,40))
        imgui.PopStyleColor(4)
        if imgui.IsItemActive and imgui.IsItemActive() then
            handle_active=true
            local delta=io.MouseDelta or {x=0,y=0}
            if delta.x~=0 or delta.y~=0 then M.resize_window(delta.x,delta.y,sz.x,sz.y) end
        end
        if M.window_dirty and not handle_active then M.window_dirty=not DSP.save_settings() end
    end
    imgui.End()
    imgui.PopStyleVar(5)
    if colors and colors>0 then imgui.PopStyleColor(colors) end
    if DSP.ui.open_ref and not DSP.ui.open_ref[0] then M.flush_save(true); DSP.ui.open=false end
end
-- The old settings screen remains complete and scrolls vertically in the content child.
-- Wrap rows on wider settings selectors instead of forcing them beyond the edge.
