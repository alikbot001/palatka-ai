-- Compatibility facade over the central ShopStore.
DSP.local_arb = DSP.local_arb or {}
local A=DSP.local_arb
if not DSP.shop_store and loadfile then local f=loadfile('src/46a_shop_store.lua');if f then pcall(f) end end
local MAX=9007199254740991
A.revision=A.revision or 0
A.max_shops=A.max_shops or 80
A.ttl=A.ttl or 3600
A._seen=A._seen or {}
A._sig=A._sig or {}
local function num(v,min,max)local n=tonumber(v);if n and n==n and n%1==0 and n>=(min or 0) and n<=(max or MAX)then return math.floor(n)end end
local function sid()return num(DSP.settings and DSP.settings.server,1)or num(DSP.market and DSP.market.state and DSP.market.state.sid,1)or 0 end
local function sync()
    local _,ttl=80,3600
    if DSP.shop_store then
        local st=DSP.shop_store.stats and DSP.shop_store.stats(sid())
        if st then A.max_shops=st.capacity or 80;A.ttl=st.ttl or ttl;A.revision=st.version or A.revision end
        A._dirty=DSP.shop_store._dirty
    end
end
function A.observe(shop,timestamp)
    if not DSP.shop_store or not DSP.shop_store.commit then return false,'store unavailable'end
    local ok,count,row=DSP.shop_store.commit(shop,timestamp)
    sync()
    if not DSP.dir then
        DSP.settings.local_arbitrage_scans=DSP.settings.local_arbitrage_scans or {}
        local servers=DSP.shop_store.data and DSP.shop_store.data.servers or {}
        for k,v in pairs(servers) do DSP.settings.local_arbitrage_scans[k]=type(v)=='table' and (v.shops or {}) or {} end
    end
    if ok then A.revision=A.revision+1;return true,count,row end
    if count=='unchanged' then return false,'unchanged',row end
    return false,count
end

function A.flush()
    -- Isolated regression hosts do not provide encodeJson/filesystem runtime.
    if not DSP.dir then
        if DSP.save_settings then local ok=select(1,DSP.save_settings());return ok~=false end
        return true
    end
    if not DSP.shop_store or not DSP.shop_store.flush then return true end
    local ok,err=DSP.shop_store.flush();sync();return ok,err
end

function A.has_shop(shop)
    if not DSP.shop_store or not DSP.shop_store.has then return false end
    return DSP.shop_store.has(shop)
end
function A.has_observation(number,server_id)
    if not DSP.shop_store or not DSP.shop_store.get_by_num then return false end
    local row=DSP.shop_store.get_by_num(number,server_id);if not row then return false end
    local st=DSP.shop_store.stats(server_id);return os.time()-(row.at or 0)>=0 and os.time()-(row.at or 0)<(st.ttl or 3600)
end
function A.stats(timestamp)
    local st=DSP.shop_store and DSP.shop_store.stats and DSP.shop_store.stats(sid(),timestamp)or{shops=0,offers=0,mapped=0,unmapped=0,capacity=80,ttl=3600,server=sid()}
    A.max_shops=st.capacity or 80;A.ttl=st.ttl or 3600;A.revision=st.version or A.revision;return st
end
function A.recent(timestamp)
    local rows=DSP.shop_store and DSP.shop_store.active and DSP.shop_store.active(sid(),timestamp)or{}
    local out={};for i=#rows,1,-1 do out[#out+1]=rows[i]end;return out
end
local function net_price(price,factor)return math.floor(price/10000)*factor+math.floor((price%10000)*factor/10000)end
function A.routes(timestamp)
    timestamp=timestamp or os.time()
    local result,seen={},{}
    local sellers,buyers={},{}
    local market=DSP.market
    local shops=DSP.shop_store and DSP.shop_store.active and DSP.shop_store.active(sid(),timestamp) or {}
    for _,shop in ipairs(shops) do
        if num(shop.num,1) and not (market and market.is_shop_missing and market.is_shop_missing(shop.num,timestamp)) then
            for _,pair in ipairs({{shop.sell,sellers},{shop.buy,buyers}}) do
                for _,offer in ipairs(pair[1] or {}) do
                    local id=num(offer.id,1)
                    local ench=num(offer.ench or 0,0,10000)
                    local price=num(offer.price,1)
                    if id and ench and price then
                        local k=tostring(id)..':'..tostring(ench)
                        local bucket=pair[2][k]
                        if not bucket then bucket={};pair[2][k]=bucket end
                        bucket[#bucket+1]={num=shop.num,owner=shop.owner,at=shop.at,id=id,ench=ench,
                            name=offer.name,price=price,qty=num(offer.qty,1,1000000000)}
                    end
                end
            end
        end
    end
    local af=DSP.settings.arb_filters or {}
    local tax=math.max(0,math.min(10000,num(af.tax_bp,0,10000) or num(DSP.settings.tax_bp,0,10000) or 200))
    local factor=10000-tax
    for _,collection in ipairs({sellers,buyers}) do
        local ascending=collection==sellers
        for item,quotes in pairs(collection) do
            local best={}
            for _,q in ipairs(quotes) do
                local k=tostring(q.num)
                local prev=best[k]
                if not prev or (ascending and q.price<prev.price) or (not ascending and q.price>prev.price) then best[k]=q end
            end
            local unique={}
            for _,q in pairs(best) do unique[#unique+1]=q end
            collection[item]=unique
        end
    end
    for item,asks in pairs(sellers) do
        table.sort(asks,function(a,b)return a.price<b.price end)
        local bids=buyers[item] or {}
        table.sort(bids,function(a,b)return a.price>b.price end)
        for i=1,math.min(#asks,12) do
            local seller=asks[i]
            for j=1,math.min(#bids,12) do
                local buyer=bids[j]
                if tostring(seller.num)~=tostring(buyer.num) then
                    local net=net_price(buyer.price,factor)
                    local unit=net-seller.price
                    if unit>0 then
                        local key=table.concat({item,seller.num,buyer.num,seller.price,buyer.price},'|')
                        if not seen[key] then
                            seen[key]=true
                            local count=(seller.qty and buyer.qty) and math.min(seller.qty,buyer.qty) or nil
                            local total=count and unit<=math.floor(MAX/count) and unit*count or nil
                            result[#result+1]={name=seller.name or buyer.name,id=seller.id,ench=seller.ench,
                                seller_shop=seller.num,seller_owner=seller.owner,seller_at=seller.at,
                                buyer_shop=buyer.num,buyer_owner=buyer.owner,buyer_at=buyer.at,
                                buy_price=seller.price,sell_price=buyer.price,net_unit=net,profit_unit=unit,
                                qty=count,profit_total=total,source='local_scan',fee_bp=tax}
                        end
                    end
                end
            end
        end
    end
    table.sort(result,function(a,b)
        if a.profit_unit~=b.profit_unit then return a.profit_unit>b.profit_unit end
        return (a.seller_at+a.buyer_at)>(b.seller_at+b.buyer_at)
    end)
    for i=#result,501,-1 do result[i]=nil end
    return result
end

function A.install()
    if A.installed then return end;A.installed=true
    if DSP.shop_store and DSP.shop_store.install then DSP.shop_store.install()end;sync()
end
return true