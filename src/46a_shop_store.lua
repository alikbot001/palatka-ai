-- Central local shop store: atomic snapshots, LRU retention, search index and price history.
DSP.shop_store = DSP.shop_store or {}
local S=DSP.shop_store
local MAX=9007199254740991
local function lower(v) local s=tostring(v or '');return DSP.lower and DSP.lower(s) or s:lower() end
S.schema=1
S.path=(DSP.dir or '.')..'/shop_store_v1.json'
S.data=S.data or {schema=S.schema,servers={},legacy_settings_migrated=false}
S.version=S.version or 0
S._dirty=false
S._index={}
S._index_version={}
local function number(v,min,max)
    local n=tonumber(v)
    if n and n==n and n%1==0 and n>=(min or 0) and n<=(max or MAX) then return math.floor(n) end
end
local function sid(v)
    local n=number(v,1) or number(DSP.settings and DSP.settings.server,1)
        or number(DSP.market and DSP.market.state and DSP.market.state.sid,1) or 0
    return n
end
local function cfg()
    DSP.settings.max_local_shops=math.max(20,math.min(300,number(DSP.settings.max_local_shops,20,300) or 80))
    DSP.settings.local_offer_ttl_minutes=math.max(5,math.min(1440,number(DSP.settings.local_offer_ttl_minutes,5,1440) or 60))
    DSP.settings.price_history_days=math.max(1,math.min(30,number(DSP.settings.price_history_days,1,30) or 7))
    return DSP.settings.max_local_shops,DSP.settings.local_offer_ttl_minutes*60,DSP.settings.price_history_days*86400
end
local function server(server_id)
    local key=tostring(sid(server_id));local root=S.data.servers
    if type(root[key])~='table' then root[key]={shops={},order={},history={},version=0} end
    local s=root[key]
    if type(s.shops)~='table'then s.shops={}end;if type(s.order)~='table'then s.order={}end
    if type(s.history)~='table'then s.history={}end;s.version=tonumber(s.version)or 0
    return s,key
end
local function owner(v)
    local x=DSP.clean_text and DSP.clean_text(v or '') or tostring(v or '')
    x=x:match('%-%s*([%w_]+)') or x:match('^([%w_]+)') or x
    x=DSP.trim and DSP.trim(x) or x
    return x
end
local function identity(snapshot)
    local n=number(snapshot and snapshot.num,1)
    if n then return 'num:'..n,'number',n end
    local o=owner(snapshot and snapshot.owner)
    if o~='' then return 'owner:'..lower(o),'owner',nil end
    return 'anon:'..tostring(snapshot and snapshot.generation or 0)..':'..tostring(snapshot and snapshot.opened or os.time()),'anonymous',nil
end
local function remove_order(order,key)
    for i=#order,1,-1 do if order[i]==key then table.remove(order,i) end end
end
local function push_order(order,key) remove_order(order,key);order[#order+1]=key end
local function find_owner(shops,want)
    want=owner(want);if want==''then return nil end;want=lower(want)
    for k,row in pairs(shops)do if type(row)=='table'and lower(owner(row.owner))==want then return k,row end end
end
local function copy_offer(row,side)
    if type(row)~='table'then return nil end
    local id=number(row.item_id or row.id,1);local ench=number(row.ench or 0,0,10000)or 0;local price=number(row.price,1)
    if not id or not price then return nil end
    local qty=row.qty_known and number(row.qty,1,1000000000)or nil
    local name=tostring(row.name or (DSP.items and DSP.items.name and DSP.items.name(id)) or '')
    if name==''then return nil end
    local item_key=(DSP.item_registry and DSP.item_registry.key and DSP.item_registry.key(id,ench))or(tostring(id)..':'..ench)
    return {id=id,item_id=id,ench=ench,name=name,price=price,qty=qty,qty_known=qty~=nil,
        side=side,slot=number(row.slot,0),key=tostring(row.key or ''),item_key=item_key,
        search=(DSP.item_registry and DSP.item_registry.search_text and DSP.item_registry.search_text(name,ench))or lower(name)}
end
local function copy_side(rows,side)
    local out,seen={},{}
    for _,row in ipairs(rows or {})do
        local r=copy_offer(row,side)
        if r then
            local k=(r.slot and ('slot:'..r.slot))or(r.item_key..':'..r.price)
            if not seen[k]then seen[k]=#out+1;out[#out+1]=r else
                local old=out[seen[k]]
                if r.qty_known and (not old.qty_known or (r.qty or 0)>(old.qty or 0))then old.qty=r.qty;old.qty_known=true end
            end
        end
    end
    table.sort(out,function(a,b)
        if (a.slot or 999999)~=(b.slot or 999999)then return(a.slot or 999999)<(b.slot or 999999)end
        if a.name~=b.name then return a.name<b.name end
        return a.price<b.price
    end)
    return out
end
local function bump(srv,key)
    srv.version=(srv.version or 0)+1;S.version=S.version+1;S._dirty=true;S._index_version[key]=nil
end
local function add_history(srv,shop_key,row,at)
    local item=row.item_key;if not item then return end
    local h=srv.history[item];if type(h)~='table'then h={sell={},buy={}};srv.history[item]=h end
    local list=h[row.side];if type(list)~='table'then list={};h[row.side]=list end
    local prev=list[#list]
    if prev and prev.shop==shop_key and prev.price==row.price and prev.qty==row.qty and at-(prev.at or 0)<600 then prev.at=at;return end
    list[#list+1]={shop=shop_key,price=row.price,qty=row.qty,at=at,name=row.name,ench=row.ench,id=row.id}
    local _,_,keep=cfg();local cutoff=at-keep
    local first=1;while first<=#list and ((list[first].at or 0)<cutoff or #list-first+1>240)do first=first+1 end
    if first>1 then for i=1,first-1 do table.remove(list,1)end end
end
local function migrate_identity(srv,snapshot,new_key)
    local old=snapshot.local_identity
    if old and old~=new_key and srv.shops[old]then
        local oldrow=srv.shops[old];srv.shops[old]=nil;remove_order(srv.order,old)
        if not srv.shops[new_key]then srv.shops[new_key]=oldrow end
    end
    if new_key:sub(1,4)=='num:' then
        local k,row=find_owner(srv.shops,snapshot.owner)
        if k and k~=new_key then
            if not srv.shops[new_key]then srv.shops[new_key]=row end
            srv.shops[k]=nil;remove_order(srv.order,k)
        end
    end
end
local function same_rows(a,b)
    if #(a or {})~=#(b or {}) then return false end
    for i=1,#(a or {}) do
        local x,y=a[i],b[i]
        if not y or x.id~=y.id or x.ench~=y.ench or x.price~=y.price or x.qty~=y.qty or x.slot~=y.slot or x.side~=y.side then return false end
    end
    return true
end
function S.commit(snapshot,timestamp)
    if type(snapshot)~='table'then return false,'invalid snapshot'end
    local server_id=sid(snapshot.server);if server_id==0 then return false,'server'end
    local sells,buys=copy_side(snapshot.sell,'sell'),copy_side(snapshot.buy,'buy')
    if #sells+#buys==0 then return false,'empty'end
    local srv,skey=server(server_id);local key,kind,num=identity(snapshot);migrate_identity(srv,snapshot,key)
    local old=srv.shops[key];local at=number(timestamp,1)or os.time()
    local clean_owner=owner(snapshot.owner)
    if old and old.num==num and old.owner==clean_owner and same_rows(old.sell,sells) and same_rows(old.buy,buys) then
        old.at=at;old.last_seen=at;old.scan_seq=(old.scan_seq or 0)+1;old.number_source=snapshot.num_source or old.number_source
        old.generation=snapshot.generation or old.generation;old.opened=snapshot.opened or old.opened;old.fragment_count=snapshot.fragment_count or old.fragment_count
        push_order(srv.order,key);snapshot.local_identity=key;bump(srv,skey)
        return false,'unchanged',old
    end
    local row={identity=key,identity_kind=kind,num=num,owner=clean_owner,number_source=snapshot.num_source,
        at=at,last_seen=at,first_seen=old and old.first_seen or at,scan_seq=(old and old.scan_seq or 0)+1,
        generation=snapshot.generation or 0,opened=snapshot.opened or 0,server=server_id,sell=sells,buy=buys,
        complete=true,fragment_count=snapshot.fragment_count or 0}
    srv.shops[key]=row;push_order(srv.order,key);snapshot.local_identity=key
    for _,r in ipairs(sells)do add_history(srv,key,r,at)end;for _,r in ipairs(buys)do add_history(srv,key,r,at)end
    local max=cfg();while #srv.order>max do local victim=table.remove(srv.order,1);srv.shops[victim]=nil end
    bump(srv,skey);return true,#sells+#buys,row
end
function S.has(snapshot)
    if type(snapshot)~='table'then return false end
    local srv=server(snapshot.server);local key=snapshot.local_identity
    if key and srv.shops[key]then return true,srv.shops[key] end
    local n=number(snapshot.num,1);if n and srv.shops['num:'..n]then return true,srv.shops['num:'..n]end
    local k,row=find_owner(srv.shops,snapshot.owner);if k then return true,row end
    return false
end
function S.get_by_num(num,server_id)
    local n=number(num,1);if not n then return nil end;local srv=server(server_id);return srv.shops['num:'..n]
end
function S.stats(server_id,timestamp)
    local srv=server(server_id);local _,ttl=cfg();local now=timestamp or os.time();local shops,offers,mapped,unmapped=0,0,0,0
    for _,row in pairs(srv.shops)do if type(row)=='table'and now-(row.at or 0)>=0 and now-(row.at or 0)<ttl then
        shops=shops+1;offers=offers+#(row.sell or{})+#(row.buy or{});if row.num then mapped=mapped+1 else unmapped=unmapped+1 end
    end end
    return{shops=shops,offers=offers,mapped=mapped,unmapped=unmapped,capacity=cfg(),version=srv.version,server=sid(server_id),ttl=ttl}
end
function S.active(server_id,timestamp)
    local srv=server(server_id);local _,ttl=cfg();local now=timestamp or os.time();local out={}
    for _,key in ipairs(srv.order)do local row=srv.shops[key];if row and now-(row.at or 0)>=0 and now-(row.at or 0)<ttl then out[#out+1]=row end end
    return out
end
local function rebuild_index(server_id)
    local srv,skey=server(server_id);if S._index_version[skey]==srv.version and S._index[skey]then return S._index[skey]end
    local idx={all={},by_item={}}
    for _,shop in ipairs(S.active(server_id))do
        for _,side in ipairs({'sell','buy'})do for _,r in ipairs(shop[side]or{})do
            local ref={shop=shop,offer=r,side=side};idx.all[#idx.all+1]=ref
            local b=idx.by_item[r.item_key];if not b then b={};idx.by_item[r.item_key]=b end;b[#b+1]=ref
        end end
    end
    S._index[skey]=idx;S._index_version[skey]=srv.version;return idx
end
function S.search(query,side,server_id)
    query=lower(DSP.clean_text and DSP.clean_text(query or '') or query or '');local out={}
    for _,ref in ipairs(rebuild_index(server_id).all)do
        if(not side or ref.side==side)and(query==''or tostring(ref.offer.search or ''):find(query,1,true))then out[#out+1]=ref end
    end
    table.sort(out,function(a,b)
        if a.offer.name~=b.offer.name then return a.offer.name<b.offer.name end
        if a.side~=b.side then return a.side<b.side end
        return a.offer.price<b.offer.price
    end);return out
end
local function robust_stats(refs,now)
    local points,vals={},{}
    for _,ref in ipairs(refs or{})do
        local p=number(ref.offer.price,1)
        if p then
            local age=math.max(0,now-(ref.shop.at or now));local q=number(ref.offer.qty,1)or 1
            points[#points+1]={price=p,age=age,qty=q};vals[#vals+1]=p
        end
    end
    if #vals==0 then return nil end
    table.sort(vals)
    local raw_samples=#vals
    local lo=vals[math.max(1,math.floor((#vals-1)*.25)+1)]
    local hi=vals[math.min(#vals,math.floor((#vals-1)*.75)+1)]
    local iqr=math.max(1,hi-lo);local min_allowed,max_allowed=lo-1.5*iqr,hi+1.5*iqr
    local kept,sum,w_sum={},0,0
    for _,pt in ipairs(points)do
        if #vals<4 or(pt.price>=min_allowed and pt.price<=max_allowed)then
            kept[#kept+1]=pt.price
            local w=math.min(math.sqrt(pt.qty),10)*math.exp(-math.log(2)*pt.age/21600)
            sum=sum+pt.price*w;w_sum=w_sum+w
        end
    end
    if #kept==0 then kept=vals end
    table.sort(kept);local med=kept[math.ceil(#kept/2)]
    return{avg=math.floor(w_sum>0 and sum/w_sum or med),median=med,min=kept[1],max=kept[#kept],
        samples=#kept,raw_samples=raw_samples,outliers=raw_samples-#kept}
end
function S.item_stats(item_key,side,server_id)
    local refs=rebuild_index(server_id).by_item[item_key]or{};local use={};for _,r in ipairs(refs)do if not side or r.side==side then use[#use+1]=r end end
    return robust_stats(use,os.time())
end
function S.price_history(item_key,side,server_id)
    local srv=server(server_id);local h=srv.history[item_key];if not h then return{}end;return h[side]or{}
end
function S.flush()
    if not S._dirty then return true end
    local ok,json=pcall(encodeJson,S.data);if not ok or type(json)~='string'then return false,'encode'end
    local tmp=S.path..'.tmp';local f=io.open(tmp,'wb');if not f then return false,'open'end
    local a,b=f:write(json),f:close();if not a or not b then return false,'write'end
    local r,e=os.rename(tmp,S.path);if not r then return false,e end;S._dirty=false;return true
end
function S.load()
    local f=io.open(S.path,'rb');if not f then return false end;local raw=f:read('*a')or'';f:close()
    local ok,d=pcall(decodeJson,raw);if ok and type(d)=='table'and type(d.servers)=='table'then
        S.data=d;S.data.schema=S.schema
        if S.data.legacy_settings_migrated==nil then S.data.legacy_settings_migrated=false end
        return true
    end
    return false
end
local function legacy_rows()
    local legacy=DSP.settings and DSP.settings.local_arbitrage_scans
    if type(legacy)~='table'then return{}end
    local out={}
    for server_key,bucket in pairs(legacy)do
        if type(bucket)=='table'then
            for _,row in pairs(bucket)do
                if type(row)=='table'and(type(row.sell)=='table'or type(row.buy)=='table')then
                    out[#out+1]={server=number(row.server,1)or number(server_key,1),row=row}
                end
            end
        end
    end
    return out
end
function S.migrate_legacy_settings()
    if S.data.legacy_settings_migrated==true then return 0 end
    local migrated=0
    for _,entry in ipairs(legacy_rows())do
        local r=entry.row
        local snapshot={server=entry.server,num=r.num,owner=r.owner,generation=r.generation,opened=r.opened,
            number_source=r.number_source,local_identity=r.identity or r.local_identity,sell=r.sell or{},buy=r.buy or{},
            fragment_count=r.fragment_count}
        local ok,why=S.commit(snapshot,number(r.at or r.last_seen,1)or os.time())
        if ok or why=='unchanged'then migrated=migrated+1 end
    end
    S.data.legacy_settings_migrated=true;S._dirty=true
    if migrated>0 and DSP.flog then DSP.flog('SHOP STORE migrated legacy scans='..tostring(migrated))end
    return migrated
end
function S.install()
    if S.installed then return end;S.installed=true;S.load();S.migrate_legacy_settings()
    -- Persist migration before starting normal debounce so an interrupted first
    -- run does not leave the new store half-created. The legacy settings remain
    -- untouched as a rollback source.
    if S._dirty and encodeJson then pcall(S.flush)end
    if lua_thread and lua_thread.create and wait then lua_thread.create(function()while true do wait(3000);if S._dirty then pcall(S.flush)end end end)end
end
return true