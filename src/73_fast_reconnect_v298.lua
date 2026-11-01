-- Palatka AI v2.9.8: Fast REC with only real observed spawn choices.
-- No fake destinations, memory writes, token handling, or blind packet IDs.
local R,V=DSP.reconnect,DSP.ui22
if not (R and V) then return true end
if R._fast_rec298 then return true end
R._fast_rec298=true
local function config()
    DSP.settings.fast_rec=DSP.settings.fast_rec or{}
    local o=DSP.settings.fast_rec
    if o.enabled==nil then o.enabled=true end
    return o
end
local function persist()
    if DSP.save_settings then return DSP.save_settings()~=false end
    return true
end
local function clean(s)
    return tostring(s or''):gsub('{%x%x%x%x%x%x}',''):gsub('^%s+',''):gsub('%s+$','')
end
local function same(a,b)
    local fn=DSP.lower or string.lower
    return fn(clean(a))==fn(clean(b))
end
local function current_profile()
    if not R.server_key or not R.server_key()then return nil end
    return R.profile and R.profile()or nil
end
local function actual_options()
    local t={}
    for _,entry in ipairs(R.options or{})do
        if type(entry)=='table' and type(entry.label)=='string' and entry.label~=''then
            t[#t+1]=entry.label
        end
    end
    return t
end
function R.fast_spawns()
    local p=current_profile()
    if not p then return {} end
    -- Never draw fabricated default names: only verified real dialog options.
    local result,seen={},{}
    for _,label in ipairs(p.known_spawns or{})do
        if type(label)=='string'and #label>0 and #label<=100 then
            local lower=(DSP.lower or string.lower)(label)
            if not seen[lower]then
                seen[lower]=true;result[#result+1]=label
            end
        end
    end
    return result
end
local observe=R.observe_dialog
function R.observe_dialog(id,style,title,content,at)
    local result=observe(id,style,title,content,at)
    if result then
        local p=current_profile()
        local options=actual_options()
        if p and #options>0 and #options<=32 then
            local changed=#(p.known_spawns or{})~=#options
            if not changed then
                for i,label in ipairs(options)do
                    if not same(label,p.known_spawns[i])then changed=true;break end
                end
            end
            if changed then
                local before=p.known_spawns
                p.known_spawns=options
                if not persist()then p.known_spawns=before end
            end
        end
    end
    return result
end
function R.fast(label,at)
    local p=current_profile()
    if not p then return false,'Адрес сервера пока не определён'end
    local confirmed=false
    for _,known in ipairs(R.fast_spawns())do
        if same(known,label)then label=known;confirmed=true;break end
    end
    if not confirmed then return false,'Точка не подтверждена игровым меню'end
    local old_label=p.spawn_label
    local opts=R.config()
    local prev_auto=opts.spawn_enabled
    p.spawn_label=label
    opts.spawn_enabled=true
    if not persist()then
        p.spawn_label=old_label;opts.spawn_enabled=prev_auto
        return false,'Не удалось сохранить выбранную точку'
    end
    local ok,why=R.manual(at)
    if not ok then return false,why end
    return true
end
-- Fix false positives: immediately after /reconnect the old spawned flag
-- may still describe the previous session. Only a fresh onSpawn event or a
-- real observed disconnect/reconnect can confirm success.
local previous_tick=R.tick
function R.tick(at)
    at=at or os.time()
    local pending=R.state=='connecting'
    if pending then
        local spawned=false
        if type(sampIsLocalPlayerSpawned)=='function'then
            local ok,value=pcall(sampIsLocalPlayerSpawned)
            spawned=ok and value==true
            if ok and not value then R._fast_disconnected=true end
        end
        if spawned and not R._fast_disconnected then
            local old_connected=R.connected
            R.connected=function()return false end
            local worked,result=pcall(previous_tick,at)
            R.connected=old_connected
            if not worked then error(result) end
            -- Do not claim success just because /reconnect was submitted.
            if R.state=='connecting' and at-(R.started_at or at)>=12 then
                R.status='Ожидание подтверждения нового подключения'
            end
            return result
        end
    end
    local prior=R.state
    local result=previous_tick(at)
    if prior~='connecting' and R.state=='connecting'then
        R._fast_disconnected=false
    end
    return result
end
-- Collect real spawns while the list is visible. No synthetic fallback.
-- The original reconnect module's onShowDialog handler calls R.observe_dialog,
-- so the adapter above also works when loaded as an OTA on v2.9.6/2.9.7.
function R.fast_visible(value)
    local c=config();if value==nil then return c.enabled~=false end
    local before=c.enabled;c.enabled=value==true
    if not persist()then c.enabled=before;return false end
    return true
end
function R.fast_status()
    local c=R.config()
    return tostring(R.status or'ожидание')..' | '..tostring(R.attempts or 0)..
        '/'..tostring(c.max_attempts or 0)
end
local function u(s)return DSP.utf8(tostring(s or''))end
local function pbutton(label,id,width)
    return imgui.Button(u(label)..'##fast298_'..id,imgui.ImVec2(width,38))
end
local function float_ui()
    local c=config()
    if not c.enabled then return end
    if not imgui or not imgui.GetIO then return end
    local io=imgui.GetIO()
    local sw,sh=io.DisplaySize.x,io.DisplaySize.y
    if sw<120 or sh<100 then return end
    local expanded=c.open==true
    local w=expanded and math.min(345,sw-20) or 65
    local items=R.fast_spawns()
    local h=expanded and math.min(sh-20,math.max(190,154+math.min(#items,6)*43)) or 59
    local x=tonumber(c.x)or(sw-w-9)
    local y=tonumber(c.y)or(sh*.42)
    x=math.max(4,math.min(sw-w-4,x));y=math.max(4,math.min(sh-h-4,y))
    imgui.SetNextWindowPos(imgui.ImVec2(x,y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(w,h),imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(.9)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+
        imgui.WindowFlags.NoMove+imgui.WindowFlags.NoSavedSettings+
        imgui.WindowFlags.NoScrollbar
    local opened=imgui.Begin('##palatka_fast_rec298',nil,flags)
    if opened then
        if pbutton(expanded and'Закрыть' or'REC','open',expanded and 132 or 47)then
            c.open=not expanded
        end
        if imgui.IsItemActive and imgui.IsItemActive() and io.MouseDelta then
            local dx,dy=io.MouseDelta.x,io.MouseDelta.y
            if math.abs(dx)+math.abs(dy)>1 then
                c.x=x+dx;c.y=y+dy
                if DSP.mobile and DSP.mobile.defer_save then
                    DSP.mobile.defer_save()
                end
            end
        end
        if expanded then
            imgui.TextWrapped(u('Fast REC: '..R.fast_status()))
            if pbutton('Обычный реконнект','manual',math.max(150,w-18))then
                local ok,why=R.manual()
                R.fast_error=not ok and tostring(why)or nil
            end
            if #items==0 then
                imgui.TextWrapped(u('Открой реальное меню спавна в игре. Его точки появятся здесь.'))
            else
                for i=1,math.min(6,#items)do
                    if pbutton(items[i],'spawn_'..i,math.max(150,w-18))then
                        local ok,why=R.fast(items[i])
                        R.fast_error=not ok and tostring(why)or nil
                    end
                end
            end
            if R.fast_error then imgui.TextWrapped(u('Ошибка: '..R.fast_error))end
            if pbutton('Настройки и остальные точки','settings',math.max(150,w-18))then
                if DSP.mobile and DSP.mobile.set_open then DSP.mobile.set_open(true)end
                V.set_screen('reconnect')
                c.open=false
            end
        end
    end
    imgui.End()
end
if imgui and imgui.OnFrame then
    imgui.OnFrame(function()return R.fast_visible()end,function()
        local ok,why=xpcall(float_ui,debug.traceback)
        if not ok and DSP.flog and R._fast_ui_error~=why then
            R._fast_ui_error=why
            DSP.flog('FAST REC UI: '..tostring(why))
        end
    end)
end
local old_ui=R.draw_ui
if type(old_ui)=='function'then
    R.draw_ui=function(...)
        V.muted('Fast REC: значок REC у края экрана')
        if V.button(R.fast_visible() and'Скрыть REC' or'Показать REC',
                'fast298_toggle',170)then
            R.fast_visible(not R.fast_visible())
        end
        local points=R.fast_spawns()
        if #points>0 then
            V.muted('Из реального меню: '..#points..' точек')
            for i,label in ipairs(points)do
                if V.button('REC: '..label,'fast298_point_'..i,-1)then
                    local ok,why=R.fast(label)
                    R.fast_error=not ok and tostring(why)or nil
                end
            end
        end
        if R.fast_error then V.red(R.fast_error)end
        return old_ui(...)
    end
end
return true
