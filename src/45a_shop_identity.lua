-- v2.3.0: robust stall identity resolver.
-- Sources are ordered by confidence: packet -> dialog -> textdraw/3D label -> owner memory.
-- This mirrors what a real client exposes instead of requiring shopNum in one packet.
DSP.shop_identity = DSP.shop_identity or {}
local I = DSP.shop_identity
I.labels = I.labels or {}
I.dialog = I.dialog or {num=nil,at=0}
I.textdraw = I.textdraw or {num=nil,at=0}
I.last = I.last or {num=nil,source=nil,at=0}
I.MAX_NEAR = 7.0
I.MEM_TTL = 3600
I.last_label_refresh = I.last_label_refresh or 0

local function now() return os.time() end
local function valid_num(v)
    local n=tonumber(v)
    if not n or n~=n or n%1~=0 or n<1 or n>99999 then return nil end
    return math.floor(n)
end
local function server_id()
    local n=tonumber(DSP.settings and DSP.settings.server) or 0
    if n<=0 and DSP.market and DSP.market.state then n=tonumber(DSP.market.state.sid) or 0 end
    return math.floor(n)
end
local function clean_owner(v)
    local s=DSP.clean_text and DSP.clean_text(tostring(v or '')) or tostring(v or '')
    s=s:match('%-%s*([%w_]+)') or s:match('^([%w_]+)') or s
    return DSP.trim and DSP.trim(s) or s
end
local function root()
    if type(DSP.settings.shop_identity_memory)~='table' then DSP.settings.shop_identity_memory={} end
    local sid=tostring(server_id())
    if type(DSP.settings.shop_identity_memory[sid])~='table' then DSP.settings.shop_identity_memory[sid]={} end
    return DSP.settings.shop_identity_memory[sid]
end
local function remember(owner,num,source)
    owner=clean_owner(owner);num=valid_num(num)
    if owner=='' or not num then return false end
    local r=root();local key=DSP.lower(owner)
    local prev=r[key]
    if type(prev)~='table' or prev.num~=num or prev.source~=source then
        r[key]={owner=owner,num=num,source=source or 'unknown',at=now()}
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
        elseif DSP.save_settings then DSP.save_settings() end
    else prev.at=now() end
    local my=DSP.player_nick and DSP.player_nick() or ''
    if my~='' and DSP.lower(my)==DSP.lower(owner) then
        DSP.settings.own_shop_num_saved=num
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save() end
    end
    return true
end
function I.memory(owner)
    owner=clean_owner(owner)
    if owner=='' then return nil end
    local rec=root()[DSP.lower(owner)]
    if type(rec)=='table' and valid_num(rec.num) and now()-(tonumber(rec.at) or 0)<=I.MEM_TTL then
        return valid_num(rec.num),rec.source or 'memory',rec.at
    end
    return nil
end
local function player_pos()
    if not getCharCoordinates or not PLAYER_PED then return nil end
    local ok,x,y,z=pcall(getCharCoordinates,PLAYER_PED)
    if not ok or type(x)~='number' or type(y)~='number' then return nil end
    return x,y,z or 0
end
local function label_number(text)
    text=tostring(text or '')
    local n=text:match('#%s*(%d+)') or text:match('\185%s*(%d+)')
    return valid_num(n)
end
local function looks_like_shop(text)
    local s=DSP.lower and DSP.lower(DSP.clean_text and DSP.clean_text(text or '') or tostring(text or '')) or tostring(text or ''):lower()
    return s:find(DSP.lower and DSP.lower('\xcb\xe0\xe2\xea\xe0') or '\xcb\xe0\xe2\xea\xe0',1,true)
        or s:find('shop',1,true) or s:find('stall',1,true)
end
function I.observe_label(id,text,x,y,z)
    local num=label_number(text)
    if not num or not looks_like_shop(text) then return false end
    I.labels[tostring(id)]={num=num,x=tonumber(x),y=tonumber(y),z=tonumber(z) or 0,at=now(),text=tostring(text or '')}
    return true
end
function I.nearest(max_distance)
    local px,py,pz=player_pos();if not px then return nil end
    local best_d,best=tonumber(max_distance) or I.MAX_NEAR,nil
    for id,row in pairs(I.labels) do
        if type(row)~='table' or now()-(tonumber(row.at) or 0)>120 then I.labels[id]=nil
        elseif type(row.x)=='number' and type(row.y)=='number' then
            local dz=(tonumber(row.z) or pz)-pz
            local d=math.sqrt((row.x-px)^2+(row.y-py)^2+dz^2)
            if d<best_d then best_d,best=d,row end
        end
    end
    return best and best.num or nil,best_d,best
end
-- Refresh streamed 3D stall labels outside ImGui callbacks. A full 0..2047
-- scan is intentionally background-only and yields in small batches.
function I.refresh_nearby_labels()
    if not sampGet3dTextInfoById then return 0 end
    local px,py,pz=player_pos(); if not px then return 0 end
    local found=0
    for id=0,2047 do
        local ok,text,_,x,y,z=pcall(sampGet3dTextInfoById,id)
        if ok and text and type(x)=='number' and type(y)=='number' and looks_like_shop(text) then
            local num=label_number(text)
            if num then
                local d=math.sqrt((x-px)^2+(y-py)^2+((z or pz)-pz)^2)
                if d<=24 then
                    I.labels[tostring(id)]={num=num,x=x,y=y,z=z or 0,at=now(),text=tostring(text)}
                    found=found+1
                end
            end
        end
        if wait and id%128==127 then wait(0) end
    end
    I.last_label_refresh=now()
    return found
end
function I.observe_dialog(dialog_id,title,text)
    if tonumber(dialog_id)~=3040 and tonumber(dialog_id)~=15072 then return false end
    local clean=DSP.clean_text and DSP.clean_text(title or '') or tostring(title or '')
    local n=label_number(clean) or valid_num(clean:match('(%d+)%s*$'))
    if not n then return false end
    I.dialog={num=n,at=now(),generation=DSP.live and DSP.live.shop and DSP.live.shop.generation or 0}
    I.last={num=n,source='dialog',at=now()}
    return true
end
function I.observe_textdraw(id,data)
    local text=type(data)=='table' and data.text or data
    local n=label_number(text)
    if n and looks_like_shop(text) then
        I.textdraw={num=n,at=now(),id=id,generation=DSP.live and DSP.live.shop and DSP.live.shop.generation or 0}
        I.last={num=n,source='textdraw',at=now()}
        return true
    end
    return false
end
function I.resolve(shop)
    shop=shop or (DSP.live and DSP.live.shop) or {}
    local explicit=valid_num(shop.num)
    if explicit then
        shop.num=tostring(explicit);shop.num_source=shop.num_source or 'packet'
        remember(shop.owner,explicit,shop.num_source)
        return explicit,shop.num_source
    end
    local generation=shop.generation or 0
    if I.dialog.num and now()-(I.dialog.at or 0)<=6 and (I.dialog.generation==0 or I.dialog.generation==generation) then
        shop.num=tostring(I.dialog.num);shop.num_source='dialog';remember(shop.owner,I.dialog.num,'dialog')
        return I.dialog.num,'dialog'
    end
    if I.textdraw.num and now()-(I.textdraw.at or 0)<=6 and (I.textdraw.generation==0 or I.textdraw.generation==generation) then
        shop.num=tostring(I.textdraw.num);shop.num_source='textdraw';remember(shop.owner,I.textdraw.num,'textdraw')
        return I.textdraw.num,'textdraw'
    end
    local near,d=I.nearest(I.MAX_NEAR)
    if near then
        shop.num=tostring(near);shop.num_source='3d';shop.num_distance=d;remember(shop.owner,near,'3d')
        I.last={num=near,source='3d',at=now()}
        return near,'3d'
    end
    local mem,src=I.memory(shop.owner)
    if mem then
        shop.num=tostring(mem);shop.num_source='memory:'..tostring(src)
        return mem,shop.num_source
    end
    return nil,'unknown'
end
function I.own_shop_number()
    local shop=DSP.live and DSP.live.shop
    local nick=DSP.player_nick and DSP.player_nick() or ''
    if shop and nick~='' and DSP.lower(clean_owner(shop.owner))==DSP.lower(nick) then
        local n,src=I.resolve(shop);if n then return n,src end
    end
    local saved=valid_num(DSP.settings and DSP.settings.own_shop_num_saved)
    if saved then return saved,'saved' end
    return nil,'unknown'
end
function I.attach_current(reason)
    local shop=DSP.live and DSP.live.shop
    if not shop then return nil end
    local before=tostring(shop.num or '')
    local n,src=I.resolve(shop)
    if n and before~=tostring(n) and DSP.live and DSP.live.queue_shop_autoscan and (shop.items_updated or 0)>0 then
        if DSP.flog then DSP.flog('SHOP identity resolved #'..tostring(n)..' source='..tostring(src)..' reason='..tostring(reason or '')) end
        DSP.live.queue_shop_autoscan()
    end
    return n,src
end
function I.install()
    if I.installed then return end;I.installed=true
    local L=DSP.live
    if L then
        local owner=L.handle_shop_owner
        if owner then L.handle_shop_owner=function(raw) local r={owner(raw)};pcall(I.attach_current,'owner_packet');return unpack(r) end end
        local items=L.handle_shop_items
        if items then L.handle_shop_items=function(raw) local r={items(raw)};pcall(I.attach_current,'items_packet');return unpack(r) end end
    end
    if lua_thread and lua_thread.create and wait then
        lua_thread.create(function()
            wait(900)
            while true do
                local ok,err=pcall(I.refresh_nearby_labels)
                if not ok and DSP.flog then DSP.flog('SHOP ID 3D refresh: '..tostring(err)) end
                pcall(I.attach_current,'3d_refresh')
                wait(1800)
            end
        end)
    end
    local ok,sampev=pcall(require,'samp.events')
    if not ok or not sampev then return end
    local prev_dlg=sampev.onShowDialog
    sampev.onShowDialog=function(id,style,title,b1,b2,text)
        pcall(I.observe_dialog,id,title,text);pcall(I.attach_current,'dialog')
        if prev_dlg then return prev_dlg(id,style,title,b1,b2,text) end
    end
    local prev_td=sampev.onShowTextDraw
    sampev.onShowTextDraw=function(id,data)
        pcall(I.observe_textdraw,id,data);pcall(I.attach_current,'textdraw')
        if prev_td then return prev_td(id,data) end
    end
    local prev_3d=sampev.onCreate3DText
    sampev.onCreate3DText=function(id,color,pos,dist,los,player,vehicle,text)
        if type(pos)=='table' then pcall(I.observe_label,id,text,pos.x,pos.y,pos.z)
        else pcall(I.observe_label,id,text) end
        if prev_3d then return prev_3d(id,color,pos,dist,los,player,vehicle,text) end
    end
end
return true