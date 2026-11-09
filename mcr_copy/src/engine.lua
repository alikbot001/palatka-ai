-- Pure, read-only quote allocation. A route is an estimate, never a trade.
local E={MAX=9007199254740991}
local function integer(v,minimum,maximum)
    local n=tonumber(v)
    if n and n==n and n%1==0 and n>=(minimum or 0) and n<=(maximum or E.MAX) then return n end
end
E.integer=integer
local function safe_product(a,b)
    if a<=math.floor(E.MAX/b) then return a*b end
end
local function shop_key(server,shop)return tostring(server)..'/'..tostring(shop)end
function E.new()return{shops={},revision=0}end
local function side(rows)
    if type(rows)~='table' then return nil,'invalid offers'end
    -- The public mobile feed contains shops with almost 300 rows per side.
    if #rows>512 then return nil,'too many offers in one snapshot'end
    local out,seen={},{}
    for _,v in ipairs(rows)do
        if type(v)~='table' then return nil,'invalid offer'end
        local price=integer(v.price,1)
        if not price then return nil,'invalid price'end
        local id=tostring(v.id or '')
        if id=='' then return nil,'missing item identity'end
        local variant=v.variant~=nil and tostring(v.variant) or nil
        local qty=integer(v.qty,1,1000000000)
        local currency=tostring(v.currency or '')
        if currency=='' then return nil,'missing currency'end
        local key=id..'\031'..tostring(variant)..'\031'..currency
        local duplicate=key..'\031'..price
        if seen[duplicate] then
            -- An identical row repeated by an API cannot multiply stock.
            local old=seen[duplicate]
            old.qty=old.qty and qty and math.max(old.qty,qty) or nil
        else
            local r={key=key,id=id,variant=variant,currency=currency,
                name=tostring(v.name or id),price=price,qty=qty,
                bonus_level=integer(v.bonus_level,0),embedded_item_id=integer(v.embedded_item_id,0)}
            seen[duplicate]=r;out[#out+1]=r
        end
    end
    return out
end
function E.observe(state,snapshot)
    if type(snapshot)~='table' then return false,'invalid snapshot'end
    local server=tostring(snapshot.server or '')
    local shop=integer(snapshot.shop,1,1000000000)
    local at=integer(snapshot.at,1)
    if server=='' or not shop or not at then return false,'missing server/shop/time'end
    local sells,err=side(snapshot.sell or{});if not sells then return false,err end
    local buys;buys,err=side(snapshot.buy or{});if not buys then return false,err end
    local key=shop_key(server,shop)
    local old=state.shops[key]
    if old and (old.at>at or old.at==at and old.source=='local' and snapshot.source~='local')then
        return true,'older snapshot ignored'
    end
    state.shops[key]={server=server,shop=shop,at=at,source=tostring(snapshot.source or 'import'),
        owner=tostring(snapshot.owner or ''),sell=sells,buy=buys}
    state.revision=state.revision+1
    -- Bound persistent state without relying on a rendering frame.
    local keys={};for k,s in pairs(state.shops)do keys[#keys+1]={key=k,at=s.at}end
    if #keys>128 then
        table.sort(keys,function(a,b)return a.at==b.at and a.key<b.key or a.at<b.at end)
        for i=1,#keys-128 do state.shops[keys[i].key]=nil end
    end
    return true
end
function E.net(gross,bp)
    local factor=10000-bp
    return math.floor(gross/10000)*factor+math.floor((gross%10000)*factor/10000)
end
function E.routes(state,server,now,options,yield_fn)
    options=options or{}
    local tax=integer(options.tax_bp or 200,0,10000)
    local ttl=integer(options.ttl or 3600,1,86400)
    local budget=integer(options.budget or 0,0)
    if not tax or not ttl or not budget then return{},'invalid options'end
    local groups={}
    for _,s in pairs(state.shops)do
        if s.server==tostring(server) and s.at<=now and now-s.at<=ttl then
            for _,spec in ipairs({{'sell','sellers'},{'buy','buyers'}})do
                for i,o in ipairs(s[spec[1]])do
                    if o.qty and o.variant then
                        local g=groups[o.key]or{sellers={},buyers={}};groups[o.key]=g
                        g[spec[2]][#g[spec[2]]+1]={shop=s,offer=o,left=o.qty,index=i}
                    end
                end
            end
        end
    end
    local pairs_,steps,limited={},0,false
    local groupkeys={};for key in pairs(groups)do groupkeys[#groupkeys+1]=key end
    table.sort(groupkeys)
    for _,key in ipairs(groupkeys)do
        local g=groups[key]
        table.sort(g.sellers,function(a,b)return a.shop.shop<b.shop.shop end)
        table.sort(g.buyers,function(a,b)return a.shop.shop<b.shop.shop end)
        for _,a in ipairs(g.sellers)do
            for _,b in ipairs(g.buyers)do
                if a.shop.shop~=b.shop.shop and E.net(b.offer.price,tax)>a.offer.price then
                    pairs_[#pairs_+1]={a=a,b=b,gain=E.net(b.offer.price,tax)-a.offer.price}
                end
                steps=steps+1;if yield_fn and steps%128==0 then yield_fn()end
                if steps>=20000 then limited=true;break end
            end
            if limited then break end
        end
        if limited then break end
    end
    table.sort(pairs_,function(a,b)
        if a.gain~=b.gain then return a.gain>b.gain end
        if a.a.offer.key~=b.a.offer.key then return a.a.offer.key<b.a.offer.key end
        if a.a.shop.shop~=b.a.shop.shop then return a.a.shop.shop<b.a.shop.shop end
        return a.b.shop.shop<b.b.shop.shop
    end)
    local result,spent={},0
    for _,p in ipairs(pairs_)do
        local a,b=p.a,p.b
        local n=math.min(a.left,b.left)
        if budget>0 then n=math.min(n,math.floor((budget-spent)/a.offer.price))end
        local cost=n>0 and safe_product(a.offer.price,n)
        local gross=n>0 and safe_product(b.offer.price,n)
        if cost and gross and spent<=E.MAX-cost then
            local net=E.net(gross,tax)
            if net>cost then
                result[#result+1]={name=a.offer.name,id=a.offer.id,variant=a.offer.variant,
                    currency=a.offer.currency,qty=n,seller=a.shop,buyer=b.shop,
                    seller_qty=a.offer.qty,buyer_qty=b.offer.qty,
                    buy_price=a.offer.price,sell_price=b.offer.price,cost=cost,gross=gross,
                    fee=gross-net,net=net,profit=net-cost}
                a.left=a.left-n;b.left=b.left-n;spent=spent+cost
            end
        end
    end
    return result,limited and 'Достигнут лимит 20000 сравнений; список неполный' or nil
end
return E
