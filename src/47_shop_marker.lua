-- Local world-anchored stall label. Coordinates come from server markers/labels.
DSP.shop_marker={cache={}}
local M=DSP.shop_marker
if DSP.settings.marker_3d_enabled==nil then DSP.settings.marker_3d_enabled=true end
local function valid_number(n)
    local text=tostring(n or '')
    return text:match('^%d+$') and tonumber(text)>0 and tonumber(text)<=99999 and text or nil
end
local function coordinate(p)
    if not p then return nil end
    local x,y,z=tonumber(p.x),tonumber(p.y),tonumber(p.z)
    for _,v in ipairs({x or math.huge,y or math.huge,z or math.huge})do
        if v~=v or math.abs(v)>100000 then return nil end
    end
    return{x=x,y=y,z=z}
end
function M.set_enabled(value)
    DSP.settings.marker_3d_enabled=value==true
    if DSP.mobile.defer_save then DSP.mobile.defer_save()end
end
function M.clear()M.target=nil end
function M.active()
    if M.target and M.target.sid~=DSP.market.state.sid then M.target=nil;M.cache={} end
    return DSP.settings.marker_3d_enabled and M.target and M.target.position and true or false
end
function M.observe_label(id,color,position,distance,test_los,player,vehicle,text)
    local clean=DSP.clean_text(tostring(text or ''))
    if not DSP.lower(clean):find(DSP.lower('лавк'),1,true)then return end
    local num=valid_number(clean:match('#%s*(%d+)')or clean:match('№%s*(%d+)'))
    local p=coordinate(position)
    if not num or not p then return end
    p.source='label';p.sid=DSP.market.state.sid
    M.cache[num]=p
    if M.target and M.target.num==num and M.target.sid==p.sid then M.target.position=p end
end
function M.observe_checkpoint(position)
    local t=M.target
    if not t or t.sid~=DSP.market.state.sid or os.time()>(t.pending_until or 0)then return end
    -- /findilavka is not the only producer of onSetCheckpoint. SA-MP does not
    -- attach a stall number to this event, so even the first checkpoint after
    -- the command may belong to a mission or another script. Remember it only
    -- for diagnostics; it is NOT a verified world position of this stall.
    local p=coordinate(position)
    if p then t.unverified_checkpoint=p end
end
function M.status()
    if not DSP.settings.marker_3d_enabled then return '3D: выключена' end
    local t=M.target
    if not t or t.sid~=DSP.market.state.sid then return '3D: лавка не выбрана' end
    if t.position then return '3D: лавка #'..t.num..' · точная подпись' end
    if os.time()<=(t.pending_until or 0) then
        return '3D: ищем подпись лавки #'..t.num..' (GPS не подтверждён)'
    end
    return '3D: координаты лавки #'..t.num..' не подтверждены'
end
local function find_streamed_labels(num)
    if not lua_thread or not wait or not sampIs3dTextDefined or not sampGet3dTextInfoById then return end
    local target=M.target
    lua_thread.create(function()
        for id=0,2047 do
            if M.target~=target or target.num~=num then return end
            if sampIs3dTextDefined(id)then
                local ok,text,color,x,y,z=pcall(sampGet3dTextInfoById,id)
                if ok then M.observe_label(id,color,{x=x,y=y,z=z},0,false,0,0,text)end
            end
            if id%32==31 then wait(25)end
        end
    end)
end
function M.project(projector,p,sw,sh)
    local ok,visible,x,y,depth=pcall(projector,p.x,p.y,p.z+1)
    if not ok or visible==false or type(x)~='number'or type(y)~='number'then return nil end
    if x~=x or y~=y or (depth and depth<=0)or x<0 or x>sw or y<0 or y>sh then return nil end
    return{x=x,y=y}
end
function M.draw()
    if not M.active()or not convert3DCoordsToScreenEx then return end
    local io=imgui.GetIO();local t=M.target
    local p=M.project(convert3DCoordsToScreenEx,t.position,io.DisplaySize.x,io.DisplaySize.y)
    if not p then return end
    local label='Лавка #'..t.num
    if getCharCoordinates and PLAYER_PED then
        local x,y,z=getCharCoordinates(PLAYER_PED)
        local d=math.sqrt((x-t.position.x)^2+(y-t.position.y)^2+(z-t.position.z)^2)
        label=label..' · '..math.floor(d)..' м'
    end
    label=DSP.utf8(label)
    local size=imgui.CalcTextSize(label);local dl=imgui.GetForegroundDrawList()
    local x,y=p.x-size.x/2,p.y-size.y-22
    dl:AddRectFilled(imgui.ImVec2(x-10,y-6),imgui.ImVec2(x+size.x+10,y+size.y+6),0xee201810,6)
    dl:AddText(imgui.ImVec2(x,y),0xffffffff,label,nil)
    dl:AddCircleFilled(imgui.ImVec2(p.x,p.y),5,0xffffb45c,12)
end
function M.install()
    if M.installed then return end;M.installed=true
    local original=DSP.market.mark_shop
    DSP.market.mark_shop=function(num)
        num=valid_number(num);if not num then return false end
        local old=M.target
        local p=M.cache[num]
        M.target={num=num,sid=DSP.market.state.sid,pending_until=os.time()+12,
            position=p and p.sid==DSP.market.state.sid and p or nil}
        local ok=original(num)
        if not ok then M.target=old;return false end
        find_streamed_labels(num)
        return true
    end
    local ok,events=pcall(require,'samp.events')
    if ok and events then
        local prev_cp,prev_label=events.onSetCheckpoint,events.onCreate3DText
        events.onSetCheckpoint=function(position,size)
            M.observe_checkpoint(position)
            if prev_cp then return prev_cp(position,size)end
        end
        events.onCreate3DText=function(id,color,pos,dist,los,player,vehicle,text)
            M.observe_label(id,color,pos,dist,los,player,vehicle,text)
            if prev_label then return prev_label(id,color,pos,dist,los,player,vehicle,text)end
        end
    end
    if imgui and imgui.OnFrame then imgui.OnFrame(M.active,function()
        local good,err=xpcall(M.draw,debug.traceback)
        if not good and M.error~=err then M.error=err;DSP.flog('3D marker: '..tostring(err))end
    end)end
end
