-- Long-lived pawnshop scanner. Pawnshop data is intentionally separate from
-- the 80-row local ShopStore LRU: a pawnshop is a server economy source, not a stall.
DSP.lombard = DSP.lombard or {}
local L=DSP.lombard
L.schema=1
L.path=(DSP.dir or '.')..'/lombard_store_v1.json'
L.data=L.data or {schema=L.schema,servers={}}
L.session=L.session or nil
L.auto_scan=false
L._dirty=false
L._installed=false
L._last_dialog=nil
L.history_days=365
L.max_history_per_item=512
local MAX=9007199254740991
local CP_LOMBARD='\xeb\xee\xec\xe1\xe0\xf0\xe4'
local UTF_LOMBARD='\208\187\208\190\208\188\208\177\208\176\209\128\208\180'
local CP_NEXT='\xf1\xeb\xe5\xe4\xf3\xfe\xf9'
local CP_MORE='\xe4\xe0\xeb\xe5\xe5'
local CP_PREV='\xef\xf0\xe5\xe4\xfb\xe4'
local CP_SEARCH='\xef\xee\xe8\xf1\xea'
local CP_BALANCE='\xe1\xe0\xeb\xe0\xed\xf1'
local CP_EXIT='\xe2\xfb\xf5\xee\xe4'
local CP_BACK='\xed\xe0\xe7\xe0\xe4'
local CP_BUY='\xf1\xea\xf3\xef'      -- skyp / skypka prefix
local CP_PURCHASE='\xef\xee\xea\xf3\xef' -- pokup prefix
local CP_SELL='\xef\xf0\xee\xe4\xe0' -- proda prefix
local function lower(v)
    local x=tostring(v or '')
    return DSP.lower and DSP.lower(x) or x:lower()
end
local function clean(v)
    local x=tostring(v or '')
    if DSP.clean_text then x=DSP.clean_text(x) else x=x:gsub('{%x+}','') end
    x=x:gsub('\r',''):gsub('^%s+',''):gsub('%s+$','')
    return x
end
local function current_sid()
    local s=tonumber(DSP.market and DSP.market.state and DSP.market.state.sid)
    if s==nil then s=tonumber(DSP.settings and DSP.settings.server) end
    return math.floor(s or 0)
end
local function srv(server_id)
    local k=tostring(tonumber(server_id) or current_sid())
    local root=L.data.servers
    if type(root[k])~='table' then root[k]={latest={at=0,items={}},history={},scans={}} end
    local r=root[k]
    if type(r.latest)~='table' then r.latest={at=0,items={}} end
    if type(r.latest.items)~='table' then r.latest.items={} end
    if type(r.history)~='table' then r.history={} end
    if type(r.scans)~='table' then r.scans={} end
    return r,k
end
local function is_lombard_text(v)
    local q=lower(clean(v))
    return q:find(CP_LOMBARD,1,true)~=nil or q:find(UTF_LOMBARD,1,true)~=nil or q:find('pawn',1,true)~=nil
end
function L.is_dialog(title,text)
    return is_lombard_text(title) or is_lombard_text(text)
end
local function side_from(title,text)
    local q=lower(clean(title)..' '..clean(text))
    if q:find(CP_BUY,1,true) or q:find(CP_PURCHASE,1,true) then return 'buy' end
    if q:find(CP_SELL,1,true) then return 'sell' end
    return 'quote'
end
local function parse_price(v)
    if DSP.market and DSP.market.parse_cr_price then
        local ok,p=pcall(DSP.market.parse_cr_price,v)
        if ok and tonumber(p) and p>0 then return math.floor(p) end
    end
    local q=tostring(v or ''):gsub('{%x+}',''):gsub('%s','')
    q=q:gsub('^%$',''):gsub('%$$',''):gsub('[,.]','')
    local p=tonumber(q);if p and p>0 and p<=MAX then return math.floor(p) end
end
local function normalize_name(v)
    local n=clean(v)
    n=n:gsub('^%[%d+%]%s*','')
    n=n:gsub('%s+%(%s*ID%s*:%s*%d+%s*%)%s*$','')
    n=n:gsub('%s+%[[xX]%d+%]%s*$','')
    n=n:gsub('%s+[xX]%s*%d+%s*$','')
    n=n:gsub('^%s+',''):gsub('%s+$','')
    return n
end
local function skip_line(line)
    local q=lower(clean(line))
    if q=='' then return true end
    if q:find(CP_LOMBARD,1,true) or q:find(UTF_LOMBARD,1,true) then return true end
    if q:find(CP_NEXT,1,true) or q:find(CP_MORE,1,true) or q:find(CP_PREV,1,true)
        or q:find(CP_SEARCH,1,true) or q:find(CP_BALANCE,1,true)
        or q:find(CP_EXIT,1,true) or q:find(CP_BACK,1,true) then return true end
    if q=='>>' or q=='<<' then return true end
    return false
end
local function fields(line)
    local t={}
    for x in tostring(line or ''):gmatch('[^\t]+') do t[#t+1]=clean(x) end
    return t
end
local function parse_line(line,title)
    local raw=clean(line)
    if skip_line(raw) then return nil end
    local fs=fields(raw)
    local price,price_i
    if #fs>1 then
        for i=#fs,2,-1 do
            local p=parse_price(fs[i])
            if p then price,price_i=p,i;break end
        end
    end
    local name
    if price then
        local acc={};for i=1,price_i-1 do if fs[i]~='' then acc[#acc+1]=fs[i] end end
        name=table.concat(acc,' ')
    else
        local prefix,token=raw:match('^(.-)%s+(:CASH:[%d%.,]+)%s*$')
        if not prefix then prefix,token=raw:match('^(.-)%s+(%$[%d%.,]+)%s*$') end
        if not prefix then prefix,token=raw:match('^(.-)%s+([%d][%d%.,]*%s*[KkMm])%s*$') end
        if not prefix then prefix,token=raw:match('^(.-)%s+([%d][%d%.,]*)%s*$') end
        if prefix and token then price=parse_price(token);name=prefix end
    end
    name=normalize_name(name or '')
    if not price or name=='' or #name<2 then return nil end
    -- Avoid treating pure service/menu labels as items.
    if name:match('^%d+$') then return nil end
    local ench=tonumber(name:match('%(%+(%d+)%)')) or 0
    local base=name:gsub('%s*%(%+%d+%)%s*$','')
    local id=nil
    if DSP.items and DSP.items.id_for_name then
        local ok,v=pcall(DSP.items.id_for_name,base);if ok then id=tonumber(v) end
    end
    local side=side_from(title,raw)
    local key=(DSP.item_key and DSP.item_key(base,ench) or lower(base)..':'..ench)..':'..side
    return {name=name,base_name=base,item_id=id,ench=ench,price=price,side=side,key=key,raw_index=0}
end
function L.parse_dialog(title,text)
    local out,seen={},{}
    local idx=0
    for line in tostring(text or ''):gmatch('[^\n]+') do
        local r=parse_line(line,title);if r then
            r.raw_index=idx
            local k=r.key..':'..tostring(r.price)
            if not seen[k] then seen[k]=true;out[#out+1]=r end
        end
        idx=idx+1
    end
    return out
end
local function page_hash(title,text)
    local s=clean(title)..'\n'..clean(text)
    local h=2166136261
    for i=1,#s do h=(h*16777619+s:byte(i))%4294967296 end
    return string.format('%08x',h)
end
local function new_session(id,title)
    L.session={id=tonumber(id) or -1,title=clean(title),started=os.time(),last=os.time(),pages={},items={},order={},history_seen={}}
    return L.session
end
local function get_session(id,title)
    local now=os.time();local s=L.session
    if not s or now-(s.last or 0)>20 or (s.id~=tonumber(id) and tonumber(id)~=nil) then s=new_session(id,title) end
    s.last=now;if clean(title)~='' then s.title=clean(title) end
    return s
end
local function history_add(root,item,at,session)
    if session.history_seen[item.key] then return end
    session.history_seen[item.key]=true
    local h=root.history[item.key]
    if type(h)~='table' then h={name=item.name,side=item.side,item_id=item.item_id,ench=item.ench,points={}};root.history[item.key]=h end
    if type(h.points)~='table' then h.points={} end
    h.name=item.name;h.side=item.side;h.item_id=item.item_id or h.item_id;h.ench=item.ench or h.ench
    local prev=h.points[#h.points]
    if prev and prev.price==item.price and at-(prev.at or 0)<21600 then prev.at=at
    else h.points[#h.points+1]={at=at,price=item.price} end
    local cutoff=at-(tonumber(L.history_days) or 365)*86400
    while #h.points>0 and ((h.points[1].at or 0)<cutoff or #h.points>(tonumber(L.max_history_per_item) or 512)) do table.remove(h.points,1) end
end
local function commit_session(session,source)
    if not session then return false,'session' end
    local root,skey=srv(current_sid());local at=os.time();local items={}
    for _,k in ipairs(session.order) do local r=session.items[k];if r then items[#items+1]=r;history_add(root,r,at,session) end end
    table.sort(items,function(a,b) if a.name~=b.name then return a.name<b.name end;if a.side~=b.side then return a.side<b.side end;return a.price<b.price end)
    root.latest={at=at,started=session.started,title=session.title,items=items,pages=session.page_count or 0,source=source or 'dialog'}
    root.scans[#root.scans+1]={at=at,count=#items,pages=session.page_count or 0,source=source or 'dialog'}
    while #root.scans>180 do table.remove(root.scans,1) end
    L._dirty=true
    if DSP.flog then DSP.flog(('LOMBARD commit sid=%s items=%d pages=%d'):format(skey,#items,session.page_count or 0)) end
    return true,#items
end
function L.observe_dialog(id,style,title,b1,b2,text)
    if not L.is_dialog(title,text) then return false end
    L._last_dialog={id=id,style=style,title=title,b1=b1,b2=b2,text=text,at=os.time()}
    local s=get_session(id,title);local h=page_hash(title,text)
    if not s.pages[h] then
        s.pages[h]=true;s.page_count=(s.page_count or 0)+1
        local rows=L.parse_dialog(title,text)
        for _,r in ipairs(rows) do
            local k=r.key
            local old=s.items[k]
            if not old then s.items[k]=r;s.order[#s.order+1]=k
            elseif r.price~=old.price then
                -- Same item can legitimately appear more than once at different prices.
                local k2=k..':p'..tostring(r.price)
                if not s.items[k2] then r.key=k2;s.items[k2]=r;s.order[#s.order+1]=k2 end
            end
        end
        commit_session(s,L.auto_scan and 'auto_pages' or 'passive')
    end
    return true
end
local function next_index(text)
    local i=0
    for line in tostring(text or ''):gmatch('[^\n]+') do
        local q=lower(clean(line))
        if q:find(CP_NEXT,1,true) or q:find(CP_MORE,1,true) or q=='>>' then return i end
        i=i+1
    end
    return nil
end
local function schedule_next(id,text)
    if not L.auto_scan then return end
    local idx=next_index(text);if idx==nil then
        L.auto_scan=false
        if DSP.notify then DSP.notify('Lombard scan complete: '..tostring(L.stats().items)..' items') end
        return
    end
    if not lua_thread or not lua_thread.create or not wait then return end
    lua_thread.create(function()
        wait(120)
        if L.auto_scan and sampIsDialogActive and sampIsDialogActive() and sampGetCurrentDialogId and sampGetCurrentDialogId()==id then
            pcall(sampSendDialogResponse,id,1,idx,'')
        end
    end)
end
function L.stats(server_id)
    local root=srv(server_id);local hist=0;for _ in pairs(root.history) do hist=hist+1 end
    return {items=#(root.latest.items or {}),last=root.latest.at or 0,pages=root.latest.pages or 0,history_items=hist,scans=#root.scans,server=tonumber(server_id) or current_sid()}
end
function L.search(query,server_id)
    local root=srv(server_id);local q=lower(clean(query));local out={}
    for _,r in ipairs(root.latest.items or {}) do
        if q=='' or lower(r.name):find(q,1,true) then out[#out+1]=r end
    end
    table.sort(out,function(a,b) if a.name~=b.name then return a.name<b.name end;return a.price<b.price end)
    return out
end
function L.history(item_key,server_id)
    local root=srv(server_id);local h=root.history[item_key];return h and h.points or {}
end
function L.links(query,server_id)
    local out={};if not DSP.shop_store or not DSP.shop_store.search then return out end
    local sidv=tonumber(server_id) or current_sid()
    for _,p in ipairs(L.search(query,sidv)) do
        local refs=DSP.shop_store.search(p.base_name or p.name,nil,sidv)
        local best_sell,best_buy
        for _,ref in ipairs(refs or {}) do
            local price=tonumber(ref.offer and ref.offer.price)
            if price then
                if ref.side=='sell' and (not best_sell or price<best_sell.price) then best_sell={price=price,shop=ref.shop and ref.shop.num,owner=ref.shop and ref.shop.owner} end
                if ref.side=='buy' and (not best_buy or price>best_buy.price) then best_buy={price=price,shop=ref.shop and ref.shop.num,owner=ref.shop and ref.shop.owner} end
            end
        end
        out[#out+1]={pawn=p,best_shop_sell=best_sell,best_shop_buy=best_buy,
            diff_from_shop_sell=best_sell and (p.price-best_sell.price) or nil,
            diff_to_shop_buy=best_buy and (best_buy.price-p.price) or nil}
    end
    return out
end
function L.flush()
    if not L._dirty then return true end
    local ok,json=pcall(encodeJson,L.data);if not ok or type(json)~='string' then return false,'encode' end
    local tmp=L.path..'.tmp';local f=io.open(tmp,'wb');if not f then return false,'open' end
    local a,b=f:write(json),f:close();if not a or not b then return false,'write' end
    local r,e=os.rename(tmp,L.path);if not r then return false,e end
    L._dirty=false;return true
end
function L.load()
    local f=io.open(L.path,'rb');if not f then return false end
    local raw=f:read('*a') or '';f:close();local ok,d=pcall(decodeJson,raw)
    if ok and type(d)=='table' and type(d.servers)=='table' then L.data=d;L.data.schema=L.schema;return true end
    return false
end
function L.command(param)
    param=clean(param or '')
    local st=L.stats()
    if param=='' then
        if DSP.notify then DSP.notify(('Lombard: items=%d pages=%d history=%d scans=%d'):format(st.items,st.pages,st.history_items,st.scans)) end
        return
    end
    local rows=L.search(param);if DSP.notify then DSP.notify('Lombard search "'..param..'": '..#rows) end
    for i=1,math.min(#rows,5) do local r=rows[i];if DSP.notify then DSP.notify((r.side or 'quote')..' '..r.name..' '..DSP.money(r.price)) end end
end
function L.start_auto()
    if not sampIsDialogActive or not sampIsDialogActive() then if DSP.notify then DSP.notify('Lombard: open pawnshop dialog first') end;return false end
    local id=sampGetCurrentDialogId and sampGetCurrentDialogId() or -1
    local title=sampGetDialogTitle and sampGetDialogTitle() or ''
    local text=sampGetDialogText and sampGetDialogText() or ''
    if not L.is_dialog(title,text) then if DSP.notify then DSP.notify('Lombard: current dialog not recognized') end;return false end
    L.session=nil;L.auto_scan=true;L.observe_dialog(id,0,title,'','',text);schedule_next(id,text)
    if DSP.notify then DSP.notify('Lombard auto scan started') end;return true
end
function L.install()
    if L._installed then return end;L._installed=true
    pcall(L.load)
    if sampRegisterChatCommand then
        pcall(sampRegisterChatCommand,'crrlombard',L.command)
        pcall(sampRegisterChatCommand,'crrlombardscan',function() L.start_auto() end)
    end
    local ok,sampev=pcall(require,'samp.events')
    if ok and sampev then
        local prev=sampev.onShowDialog
        sampev.onShowDialog=function(id,style,title,b1,b2,text)
            local seen=false;local good,ret=pcall(L.observe_dialog,id,style,title,b1,b2,text);if good then seen=ret end
            if seen then schedule_next(id,text) end
            if prev then return prev(id,style,title,b1,b2,text) end
        end
    end
    if lua_thread and lua_thread.create and wait then
        lua_thread.create(function() while true do wait(2500);if L._dirty then pcall(L.flush) end end end)
    end
end
return true