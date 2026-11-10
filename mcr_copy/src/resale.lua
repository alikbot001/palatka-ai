-- Asking-price estimates and reported sale aggregates remain separate evidence.
return function(E)
local R={}
local MAX=E.MAX
local priority={market_sales=1,own_sales=2,buy_orders=3,unknown=4}
local function owner(shop)
    return tostring(shop.owner or ''):lower():match('^%s*(.-)%s*$')
end
local function merchant(shop)
    local name=owner(shop)
    return name~='' and 'owner:'..name or 'shop:'..tostring(shop.shop)
end
local function same(a,b)
    return a.shop==b.shop or owner(a)~='' and owner(a)==owner(b)
end
local function add(a,b)return a>MAX-b and MAX or a+b end
local function product(a,b)
    if b>0 and a<=math.floor(MAX/b)then return a*b end
end
-- Compare rational numbers using Euclidean quotients, without large products.
local function ge(a,b,c,d)
    local reverse=false
    while true do
        local x,y=math.floor(a/b),math.floor(c/d)
        if x~=y then return reverse and x<y or not reverse and x>y end
        local ar,cr=a%b,c%d
        if ar==0 or cr==0 then
            if ar==cr then return true end
            return reverse and ar==0 or not reverse and ar~=0
        end
        a,b,c,d=b,ar,d,cr;reverse=not reverse
    end
end
local function roi(profit,cost)
    local whole=math.floor(profit/cost)
    if whole>math.floor(MAX/10000)then return MAX end
    local lo,hi=0,9999
    while lo<hi do
        local mid=lo+math.floor((hi-lo+1)/2)
        if ge(profit%cost,cost,mid,10000)then lo=mid else hi=mid-1 end
    end
    return add(whole*10000,lo)
end
local function settings(o)
    if type(o)~='table' or type(o.currency)~='string' or o.currency=='' then return end
    local p={currency=o.currency,popular_only=o.popular_only~=false,own_sales=o.own_sales or {},
        market_sales=type(o.market_sales)=='table' and o.market_sales or {}}
    for _,spec in ipairs({{'ttl',3600,1,86400},{'tax_bp',200,0,10000},
        {'budget',0,0,MAX},{'min_roi_bp',1000,0,MAX},{'max_qty',10,1,1000000000},
        {'min_peers',3,3,128},{'undercut_bp',100,0,10000}})do
        local v=o[spec[1]];if v==nil then v=spec[2]end
        p[spec[1]]=E.integer(v,spec[3],spec[4]);if not p[spec[1]]then return end
    end
    if type(p.own_sales)~='table' then return end
    return p
end
function R.rank(state,server,now,options,yield_fn)
    local p=settings(options)
    now=E.integer(now,1)
    if not p or not now or type(state)~='table' or type(state.shops)~='table' then
        return {},'invalid options/state'
    end
    local steps=0
    local function checkpoint(force)
        steps=steps+1
        return not yield_fn or not(force or steps%128==0) or yield_fn()~=false
    end
    if not checkpoint(true)then return {},'cancelled'end
    local groups={}
    for _,shop in pairs(state.shops)do
        if shop.server==tostring(server) and shop.at<=now and now-shop.at<=p.ttl then
            for _,side in ipairs({'sell','buy'})do
                for _,o in ipairs(shop[side])do
                    if o.variant and o.currency==p.currency then
                        local g=groups[o.key]or {asks={},peers={},buyers={}}
                        groups[o.key]=g
                        local m=merchant(shop)
                        if side=='sell' then
                            if o.qty then g.asks[#g.asks+1]={shop=shop,offer=o}end
                            local old=g.peers[m]
                            if not old or o.price<old.price then
                                g.peers[m]={shop=shop,price=o.price,valid_until=add(shop.at,p.ttl)}
                            elseif o.price==old.price then
                                old.valid_until=math.min(old.valid_until,add(shop.at,p.ttl))
                            end
                        elseif o.qty then
                            local b=g.buyers[m]or {shop=shop,orders={},prices={}}
                            g.buyers[m]=b
                            local old=b.prices[o.price]
                            if old then
                                old.qty=math.max(old.qty,o.qty)
                                old.valid_until=math.min(old.valid_until,add(shop.at,p.ttl))
                            else
                                local order={price=o.price,qty=o.qty,valid_until=add(shop.at,p.ttl)}
                                b.orders[#b.orders+1]=order;b.prices[o.price]=order
                            end
                        end
                    end
                    if not checkpoint()then return {},'cancelled'end
                end
            end
        end
    end
    -- A suffix of declared quantities permits bounded per-merchant demand queries.
    for _,g in pairs(groups)do
        for _,b in pairs(g.buyers)do
            table.sort(b.orders,function(a,c)return a.price<c.price end)
            local qty,expiry=0,MAX
            for i=#b.orders,1,-1 do
                qty=add(qty,b.orders[i].qty);b.orders[i].total=qty
                expiry=math.min(expiry,b.orders[i].valid_until);b.orders[i].valid_until=expiry
                if not checkpoint()then return {},'cancelled'end
            end
        end
    end
    local candidates={}
    for key,g in pairs(groups)do
        for _,a in ipairs(g.asks)do
            local prices={}
            local valid_until=add(a.shop.at,p.ttl)
            for _,peer in pairs(g.peers)do
                if not same(a.shop,peer.shop)then
                    prices[#prices+1]=peer.price;valid_until=math.min(valid_until,peer.valid_until)
                end
                if not checkpoint()then return {},'cancelled'end
            end
            if #prices>=p.min_peers then
                table.sort(prices)
                local mid=math.floor((#prices+1)/2)
                local reference=prices[mid]
                if #prices%2==0 then reference=reference+math.floor((prices[mid+1]-reference)/2)end
                local peer_price,history_price=reference,nil
                local evidence={kind='unknown',buyer_shops=0,buyer_qty=0,own_events=0,own_qty=0,
                    market_qty_30d=0}
                for _,b in pairs(g.buyers)do
                    if not same(a.shop,b.shop)then
                        local lo,hi=1,#b.orders+1
                        while lo<hi do
                            local m=lo+math.floor((hi-lo)/2)
                            if b.orders[m].price>=a.offer.price then hi=m else lo=m+1 end
                        end
                        if b.orders[lo]then
                            evidence.buyer_shops=evidence.buyer_shops+1
                            evidence.buyer_qty=add(evidence.buyer_qty,b.orders[lo].total)
                            valid_until=math.min(valid_until,b.orders[lo].valid_until)
                        end
                    end
                    if not checkpoint()then return {},'cancelled'end
                end
                local own=p.own_sales[key]
                if type(own)=='table' and E.integer(own.last_at,1,now)
                    and now-own.last_at<=604800
                    and (own.valid_until==nil or E.integer(own.valid_until,now))then
                    evidence.own_events=E.integer(own.events,0)or 0
                    evidence.own_qty=E.integer(own.qty,0)or 0
                    valid_until=math.min(valid_until,own.valid_until or MAX,add(own.last_at,604800))
                end
                local sales=p.market_sales[key]
                if type(sales)=='table' and E.integer(sales.qty_30d,0)
                    and E.integer(sales.updated_at,1,now) and E.integer(sales.valid_until,now)then
                    evidence.market_qty_30d=E.integer(sales.qty_30d,0)
                    evidence.market_updated_at=E.integer(sales.updated_at,1,now)
                    evidence.market_source='va-ta.com/market'
                    valid_until=math.min(valid_until,sales.valid_until)
                    history_price=E.integer(sales.reference_price,1)
                    if history_price then reference=math.min(reference,history_price)end
                end
                local target=E.net(reference,p.undercut_bp)
                if evidence.market_qty_30d>=300 then evidence.kind='market_sales'
                elseif evidence.own_events>=3 and evidence.own_qty>=20 then evidence.kind='own_sales'
                elseif evidence.buyer_shops>=2 and evidence.buyer_qty>=20 then evidence.kind='buy_orders'end
                if target>a.offer.price and (not p.popular_only or evidence.kind~='unknown')then
                    candidates[#candidates+1]={a=a,key=key,target=target,reference=reference,
                        peer_price=peer_price,history_price=history_price,
                        peer_count=#prices,popularity=evidence,valid_until=valid_until,
                        unit_gain=E.net(target,p.tax_bp)-a.offer.price}
                end
            end
        end
    end
    table.sort(candidates,function(a,b)
        local x,y=a.popularity,b.popularity
        if x.kind~=y.kind then return priority[x.kind]<priority[y.kind]end
        if x.market_qty_30d~=y.market_qty_30d then return x.market_qty_30d>y.market_qty_30d end
        if x.own_events~=y.own_events then return x.own_events>y.own_events end
        if x.own_qty~=y.own_qty then return x.own_qty>y.own_qty end
        if x.buyer_shops~=y.buyer_shops then return x.buyer_shops>y.buyer_shops end
        if x.buyer_qty~=y.buyer_qty then return x.buyer_qty>y.buyer_qty end
        if a.unit_gain~=b.unit_gain then return a.unit_gain>b.unit_gain end
        if a.key~=b.key then return a.key<b.key end
        if a.a.shop.shop~=b.a.shop.shop then return a.a.shop.shop<b.a.shop.shop end
        return a.a.offer.price<b.a.offer.price
    end)
    local rows,used,spent={},{},0
    for _,c in ipairs(candidates)do
        local a=c.a
        local n=math.min(a.offer.qty,p.max_qty-(used[c.key]or 0),
            math.floor(MAX/a.offer.price),math.floor(MAX/c.target))
        if p.budget>0 then n=math.min(n,math.floor((p.budget-spent)/a.offer.price))end
        n=math.min(n,math.floor((MAX-spent)/a.offer.price))
        local cost,gross=product(a.offer.price,n),product(c.target,n)
        if cost and gross then
            local net=E.net(gross,p.tax_bp)
            local profit=net-cost
            if profit>0 and ge(profit,cost,p.min_roi_bp,10000)then
                rows[#rows+1]={id=a.offer.id,variant=a.offer.variant,name=a.offer.name,
                    currency=a.offer.currency,qty=n,seller=a.shop,seller_qty=a.offer.qty,
                    buy_price=a.offer.price,sell_price=c.target,reference_price=c.reference,
                    peer_price=c.peer_price,history_price=c.history_price,
                    peer_count=c.peer_count,cost=cost,gross=gross,fee=gross-net,net=net,
                    profit=profit,roi_bp=roi(profit,cost),popularity=c.popularity,valid_until=c.valid_until}
                used[c.key]=(used[c.key]or 0)+n;spent=spent+cost
            end
        end
        if not checkpoint()then return {},'cancelled'end
    end
    if not checkpoint(true)then return {},'cancelled'end
    return rows
end
return R
end
