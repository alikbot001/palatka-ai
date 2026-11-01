-- Palatka AI 2.9.4 OTA: Market Helper UX, touch scroll, journal, statistics and arbitrage fixes.
PALATKA_UPDATE_VERSION = '2.9.10'
return function(DSP)
  -- v2.8.6: Independent, additive UI + multi-deal arbitration patch.
  local function install_v286()
    if DSP._v286_installed then DSP.version='2.8.6'; return true end
    local ok,err=pcall(function()
      local function _v286_local_routes()
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
            for _,pair in ipairs({{shop.sell,sellers,'sell'},{shop.buy,buyers,'buy'}}) do
                for _,offer in ipairs(pair[1] or {}) do
                    local id=num(offer.id,1)
                    local ench=num(offer.ench or 0,0,10000)
                    local price=num(offer.price,1)
                    if id and ench and price then
                        local k=tostring(id)..':'..tostring(ench)
                        local available=num(offer.qty,1,1000000000)
                        if available and DSP.arb_agent and DSP.arb_agent.remaining then
                            available=DSP.arb_agent.remaining({key=k},pair[3],
                                {shop=shop.num,owner=shop.owner,price=price,ts=shop.at},
                                available,{source='recent_scan',at=shop.at})
                        end
                        if available==nil or available>0 then
                            local bucket=pair[2][k]
                            if not bucket then bucket={};pair[2][k]=bucket end
                            bucket[#bucket+1]={num=shop.num,owner=shop.owner,at=shop.at,id=id,ench=ench,
                                name=offer.name,price=price,qty=available}
                        end
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
      end
      _v286_local_routes()
      local function _v286_arbitrage_ui()
-- One item per row. Details are a real modal, allocations use raw offer IDs.
local V,M=DSP.ui21,DSP.mobile
V.arb_tab='sell';V.arb_revision=0;V.arb_sort='az'
local function b(s,id,w,on)return V.button(s,'arb_'..id,w,on)end
local function offerkey(o)return DSP.market.offer_key(o)end
function V.arb_group(groups)
    for _,g in ipairs(groups or{})do if g.key==V.arb_item then return g end end
end
local function choose_all(g)
    V.arb_sellers={};V.arb_buyers={}
    for _,o in ipairs(g.sellers)do V.arb_sellers[offerkey(o)]=true end
    for _,o in ipairs(g.buyers)do V.arb_buyers[offerkey(o)]=true end
    V.arb_revision=V.arb_revision+1
end
-- Unlike "select all", the auto-plan is an action: it selects offers actually
-- used by the allocator and immediately opens its route and financial result.
local function best_plan(g)
    local p=DSP.market.plan_offers(g,nil,nil,{
        extra=V.arb_extra_enabled and V.arb_extra and V.arb_extra.value or 0})
    if p.qty<=0 then
        V.arb_best_error='\205\229\242 \226\251\227\238\228\237\238\227\238 \236\224\240\248\240\243\242\224 \239\240\232 \242\229\234\243\249\232\245 \244\232\235\252\242\240\224\245'
        return
    end
    V.arb_sellers={};V.arb_buyers={}
    for _,r in ipairs(p.routes)do
        V.arb_sellers[offerkey(r.sell_offer)]=true
        V.arb_buyers[offerkey(r.buy_offer)]=true
    end
    V.arb_best_error=nil
    V.arb_revision=V.arb_revision+1
    V.arb_route=true
end
function V.arb_plan(g)
    local f=DSP.settings.arb_filters or{}
    local sig=table.concat({tostring(g),V.arb_revision,DSP.settings.tax_bp or 200,
        f.budget or 0,f.min_profit or 0,f.min_roi or 0,f.max_age or 300,
        f.max_qty or 0,f.safety_pct or 0,f.tax_bp or 'global',
        f.min_unit_profit or 0,f.max_buy_price or 0,f.min_stock or 0,f.shop_mode or 0,
        tostring(f.allow_partial~=false),tostring(f.include_unknown~=false),
        V.arb_extra_enabled and(V.arb_extra and V.arb_extra.value or 0)or 0,
        DSP.market.missing_revision or 0,DSP.arb_agent and DSP.arb_agent.revision or 0},'|')
    if os.time()>=(V.arb_plan_expiry or 0)then V.cache.arb_plan=nil end
    return V.memo('arb_plan',sig,function()
        local now,until_ts=os.time(),math.huge
        local age=tonumber(f.max_age)or 300
        for _,offers in ipairs({g.sellers,g.buyers})do for _,o in ipairs(offers)do
            local ts=tonumber(o.ts)or 0
            if age>0 and ts>0 and ts+age+1>now then until_ts=math.min(until_ts,ts+age+1)end
        end end
        V.arb_plan_expiry=until_ts
        local p=DSP.market.plan_offers(g,V.arb_sellers or{},V.arb_buyers or{},
            {extra=V.arb_extra_enabled and V.arb_extra.value or 0})
        return p
    end)
end
local function offer_row(o,i)
    local selected=V.arb_tab=='sell'and V.arb_sellers or V.arb_buyers
    local key=offerkey(o);local checked=selected and selected[key]
    local missing=DSP.market.is_shop_missing and DSP.market.is_shop_missing(o.shop,os.time(),o.ts)
    V.row('arb_offer_'..V.arb_tab..i,100,function(w,x,y)
        local right=math.max(155,w-170)
        V.at(x,y+1);V.text(V.fit('#'..tostring(o.shop)..' \183 '..tostring(o.owner or'?'),right-8))
        local count=DSP.market.format_units(o.qty)
        local row=V.arb_detail_group and V.arb_detail_group.row
        local live_qty=DSP.market.live_offer_quantity(row,V.arb_tab,o)
        local status=o.qty_source=='game' and '\239\240\238\226\229\240\229\237\238: \232\227\240\224' or
            o.qty_source=='manual' and '\239\240\238\226\229\240\229\237\238 \226\240\243\247\237\243\254' or 'API, \237\229 \239\238\228\242\226\229\240\230\228\229\237\238'
        V.at(x,y+26);V.muted(V.fit(count..' \248\242. \183 '..status..
            (live_qty and (' \183 \200\227\240\224: '..DSP.market.format_units(live_qty)) or ''),right-8))
        V.at(x,y+52);V.text(V.fit(DSP.money(o.price)..'/\248\242. \183 '..DSP.market.offer_freshness(o.ts),right-8))
        if missing then
            V.at(x,y+76);V.red('\203\224\226\234\224 \237\229\228\238\241\242\243\239\237\224: \232\241\234\235\254\247\229\237\224 \232\231 \239\235\224\237\224')
        elseif o.qty==1 and not o.verified_at then
            V.at(x,y+76);V.muted(V.fit('\194\237\232\236\224\237\232\229: 1 \236\238\230\229\242 \225\251\242\252 \234\238\235\232\247\229\241\242\226\238\236 \241\235\238\242\238\226',right-8))
        end
        V.at(x+right,y+1)
        if not missing and b(checked and '\209\237\255\242\252 \226\251\225\238\240' or '\194\251\225\240\224\242\252','select_'..i,160,checked)then
            selected[key]=not checked or nil;V.arb_revision=V.arb_revision+1
        end
        V.at(x+right,y+49)
        if b('\211\242\238\247\237\232\242\252','verify_'..V.arb_tab..i,80,false)then
            V.arb_verify={offer=o,side=V.arb_tab,source=live_qty and 'game' or 'manual'}
            V.arb_verify_value={qty=live_qty or tonumber(o.qty) or 0}
        end
        V.inline(4)
        if b(missing and '\194\229\240\237\243\242\252' or '\205\229\242 \235\224\226\234\232','gone_'..V.arb_tab..i,82,missing)then
            if missing then DSP.market.restore_shop(o.shop) else DSP.market.mark_shop_missing(o.shop,30)end
            V.arb_revision=V.arb_revision+1;V.arb_route=false;V.cache.arb_plan=nil;M.defer_save()
        end
    end)
end
local function route_rows(p)
    return function(r,i)
        V.row('route_'..i,100,function(w,x,y)
            V.text(V.fit('\202\211\207\200\210\220 '..r.tradable_qty..' \248\242. \243 \235\224\226\234\232 #'..tostring(r.sell_offer.shop)..' \183 '..DSP.money(r.p_buy)..'/\248\242.',w))
            V.at(x,y+26);V.text(V.fit('\207\208\206\196\192\210\220 \241\234\243\239\249\232\234\243 #'..tostring(r.buy_offer.shop)..' \183 '..DSP.money(r.p_sell)..'/\248\242.',w))
            V.at(x,y+52)
            if b('\202 \239\240\238\228\224\226\246\243','route_sell_'..i,140)then DSP.market.mark_shop(r.sell_offer.shop)end
            V.inline();if b('\202 \241\234\243\239\249\232\234\243','route_buy_'..i,144)then DSP.market.mark_shop(r.buy_offer.shop)end
            V.inline();V.green('~ +'..DSP.money(r.net_profit))
            if r.same_shop then
                V.at(x,y+78);V.red('\206\228\237\224 \235\224\226\234\224: \226\238\231\236\238\230\237\238\241\242\252 \238\225\240\224\242\237\238\233 \241\228\229\235\234\232 \239\240\238\226\229\240\252\242\229 \226 \232\227\240\229')
            end
        end)
    end
end
local function finance(p,compact)
    -- Planned, not executed. Display each money component explicitly.
    V.muted('\208\224\241\247\184\242 \239\238 \231\224\255\226\234\224\236 API, \237\229 \241\238\226\229\240\248\184\237\237\224\255 \241\228\229\235\234\224')
    V.text('\199\224\234\243\239\234\224: -'..DSP.money(p.cost or 0))
    V.text('\207\240\238\228\224\230\224, \228\238 \234\238\236\232\241\241\232\232: +'..DSP.money(p.gross or 0))
    V.muted('\202\238\236\232\241\241\232\255 (\239\240\232\237\255\242\224\255): -'..DSP.money(p.fee or 0))
    V.muted('\207\238\241\242\243\239\235\229\237\232\255 \239\238\241\235\229 \234\238\236\232\241\241\232\232: '..DSP.money(p.revenue or 0))
    if (p.extra or 0)>0 then V.muted('\196\238\239. \240\224\241\245\238\228\251: -'..DSP.money(p.extra))end
    local result='\206\198\200\196\192\197\204\192\223 \207\208\200\193\219\203\220: '..DSP.money(p.profit or 0)
    if (p.profit or 0)>=0 then V.green(result)else V.red(result)end
end

local function details(g)
    local p=V.arb_plan(g)
    local compact=imgui.GetContentRegionAvail().y<400
    V.arb_extra=V.arb_extra or{value=0}
    local function extra_control()
        if b(V.arb_extra_enabled and 'x \208\224\241\245\238\228\251' or '+ \208\224\241\245\238\228\251','extra',136,V.arb_extra_enabled)then V.arb_extra_enabled=not V.arb_extra_enabled end
        if V.arb_extra_enabled then V.inline();M.compact_number(V.arb_extra,'value','arb_extra',130,0)end
    end
    V.text(V.fit(g.name,imgui.GetContentRegionAvail().x-(compact and 290 or 0)))
    if compact then V.inline();extra_control()end
    V.muted('\207\240\238\228\224\254\242 '..(g.row.sell.qty or g.supply)..' \183 \209\234\243\239\224\254\242 '..(g.row.buy.qty or g.demand)..' \183 \207\235\224\237 '..p.qty..' \248\242.')
    local changed=V.arb_snapshot~=tostring(DSP.market.state.sid)..'/'..tostring(DSP.market.state.version)
    if not compact then V.muted(V.fit('\209\237\232\236\238\234 '..os.date('%H:%M:%S',V.arb_snapshot_time or os.time())..
        (changed and ' \183 \229\241\242\252 \237\238\226\251\229 \228\224\237\237\251\229, \238\242\234\240\238\233\242\229 \231\224\237\238\226\238'or ' \183 API, \237\224\235\232\247\232\229 \239\240\238\226\229\240\252\242\229 \226 \232\227\240\229'),imgui.GetContentRegionAvail().x))end
    finance(p,compact)
    local f=DSP.settings.arb_filters or {}
    if not compact then V.muted('\207\235\224\237 \243\241\235\238\226\237\251\233: \228\238\241\242\243\239\237\238\241\242\252 \237\229 \231\224\225\240\238\237\232\240\238\226\224\237\224. \199\224\239\224\241 \241\239\240\238\241\224: '
        ..tostring(f.safety_pct or 0)..'%; \238\225\237\238\226\232\242\229 \232 \239\240\238\226\229\240\252\242\229 \241\234\243\239\234\243 \239\229\240\229\228 \231\224\234\243\239\234\238\233.')end
    if V.arb_verify and V.arb_verify_value then
        local vr=V.arb_verify
        V.muted(V.fit('\212\224\234\242\232\247\229\241\234\232 \239\240\238\226\229\240\229\237\238 \226 \232\227\240\229: #'..tostring(vr.offer.shop)..' \183 '..tostring(vr.side=='buy' and '\241\234\243\239\224\229\242' or '\239\240\238\228\224\184\242'),imgui.GetContentRegionAvail().x))
        M.compact_number(V.arb_verify_value,'qty','arb_verify_qty',130,0)
        V.inline();if b('\207\240\232\236\229\237\232\242\252','verify_save',112)then
            local game_now=DSP.market.live_offer_quantity(g.row,vr.side,vr.offer)
            local source=vr.source=='game' and game_now==V.arb_verify_value.qty and 'game' or 'manual'
            local ok,err=DSP.market.confirm_offer_quantity(g.row,vr.side,vr.offer,V.arb_verify_value.qty,source)
            if ok then
                V.arb_verify=nil;V.arb_verify_value=nil
                V.arb_revision=V.arb_revision+1;V.arb_route=false
                V.arb_snapshot=tostring(DSP.market.state.sid)..'/'..tostring(DSP.market.state.version)
            else V.arb_best_error=tostring(err)end
        end
        V.inline();if b('\206\242\236\229\237\224','verify_cancel',98)then V.arb_verify=nil;V.arb_verify_value=nil end
        if V.arb_best_error then V.red(V.fit(V.arb_best_error,imgui.GetContentRegionAvail().x))end
        return
    end
    if V.arb_route then
        if b('< \207\240\229\228\235\238\230\229\237\232\255','back_offers',170)then V.arb_route=false end
        V.inline()
        if DSP.arb_agent and b('\194 \204\200\205\200-\192\195\197\205\210','route_to_agent',176,true)then
            local ok,why=DSP.arb_agent.add_plan(p)
            if ok then
                DSP.arb_agent.show(true)
                imgui.CloseCurrentPopup()
            else DSP.notify('\192\227\229\237\242: '..tostring(why))end
        end
        V.list_rows('arb_routes_'..g.key,p.routes,100,route_rows(p),{footer=function()
            if p.profit>=0 then V.green(DSP.money(p.profit)..' \247\232\241\242\238\233 \239\240\232\225\251\235\232')
            else V.red(DSP.money(p.profit)..' \232\242\238\227\238\226\238\227\238 \243\225\251\242\234\224')end
        end})
        return
    end
    local tw=imgui.GetContentRegionAvail().x
    if b('\207\240\238\228\224\254\242 \183 \234\243\239\232\242\252 '..#g.sellers,'sell',tw*.23,V.arb_tab=='sell')then V.arb_tab='sell'end
    V.inline();if b('\209\234\243\239\224\254\242 \183 \239\240\238\228\224\242\252 '..#g.buyers,'buy',tw*.23,V.arb_tab=='buy')then V.arb_tab='buy'end
    V.inline();if b('\203\243\247\248\232\233 \239\235\224\237 >','best',tw*.27)then best_plan(g)end
    V.inline();if b('\209\225\240\238\241','none',-1)then V.arb_sellers={};V.arb_buyers={};V.arb_revision=V.arb_revision+1 end
    if not compact then extra_control()end
    if V.arb_best_error then V.red(V.arb_best_error)end
    local offers=V.arb_tab=='sell'and g.sellers or g.buyers
    V.list_rows('arb_'..g.key..'_'..V.arb_tab,offers,100,offer_row,{footer=function()
        if b('\204\224\240\248\240\243\242 >','route',142,true)then V.arb_route=true end
        V.inline();if b('\199\224\234\240\251\242\252','close_details',116)then imgui.CloseCurrentPopup()end
    end})
end
function V.arbitrage()
    local st=DSP.market.state
    V.text('\192\240\225\232\242\240\224\230');V.inline();V.muted('\209\237\232\236\238\234: '..DSP.market.freshness())
    if DSP.arb_agent then
        V.inline()
        if b(DSP.arb_agent.active()and'\204\200\205\200-\192\195\197\205\210 >'or'\205\192\215\192\210\220 \209\197\209\209\200\222','session_start',190,true)then
            local ok,why
            if DSP.arb_agent.active()then DSP.arb_agent.show(true);ok=true
            else ok,why=DSP.arb_agent.start_market()end
            if not ok then DSP.notify('\192\227\229\237\242 \224\240\225\232\242\240\224\230\224: '..tostring(why))end
        end
        local st_agent=DSP.arb_agent.stats()
        if st_agent.routes>0 then V.muted('\209\229\241\241\232\255: '..st_agent.done..'/'..st_agent.routes..' \236\224\240\248\240\243\242\238\226')end
    end
    V.inline();if b(st.status=='loading' and '\199\224\227\240\243\231\234\224...' or '\206\225\237\238\226\232\242\252','refresh',120)then DSP.market.pull(st.sid)end
    V.arb_source=V.arb_source or 'api'
    if b('API','source_api',116,V.arb_source=='api')then
        V.arb_source='api';V.reset_list('arb_main')
    end
    V.inline()
    if b('\204\206\200 \209\202\192\205\219','source_local',175,V.arb_source=='local')then
        V.arb_source='local';V.reset_list('local_arb_items')
    end
    if V.arb_source=='local' then
        if V.local_arbitrage_view then V.local_arbitrage_view() end
        return
    end
    if st.error then
        local delay=(tonumber(st.next_auto_retry) or 0)-os.time()
        V.red(V.fit('API: '..tostring(st.error)..(delay>0 and (' \183 \224\226\242\238-\239\238\226\242\238\240 \247\229\240\229\231 '..delay..'\241')or ''),
            imgui.GetContentRegionAvail().x))
    end
    local af=DSP.settings.arb_filters or {}
    V.muted(V.fit('\212\232\235\252\242\240\251: '..(tonumber(af.max_age)==0 and '\225\229\231 \238\227\240\224\237\232\247\229\237\232\255 \226\240\229\236\229\237\232' or
        (tostring(math.floor((tonumber(af.max_age)or 600)/60))..' \236\232\237'))..
        ' \183 ROI \238\242 '..tostring(af.min_roi or 0)..'% \183 \240\229\231\229\240\226 '..tostring(af.safety_pct or 0)..
        '% \183 \234\238\236\232\241\241\232\255 '..tostring((tonumber(af.tax_bp) or DSP.settings.tax_bp or 200)/100)..'%',
        imgui.GetContentRegionAvail().x))
    local query,edited=V.search('arb','\207\238\232\241\234 \239\240\229\228\236\229\242\224',-1)
    if edited then V.reset_list('arb_main')end
    if b(V.arb_sort=='az' and '\192\151\223' or '\207\240\232\225\251\235\252: \225\238\235\252\248\229','sort',143,V.arb_sort=='az')then
        V.arb_sort=V.arb_sort=='az' and 'profit' or 'az'
        V.reset_list('arb_main')
    end
    V.inline()
    if b('\212\232\235\252\242\240\251','filters',120,V.arb_filters)then
        V.arb_filters=true;V.open_popup('\212\232\235\252\242\240\251 \224\240\225\232\242\240\224\230\224','arb_filters')
    end
    -- Direct game observation does not require the external API to refresh.
    local live=DSP.market.live_shop_spreads and DSP.market.live_shop_spreads() or {}
    if #live>0 then
        V.green('\205\192\201\196\197\205\206 \194 \206\210\202\208\219\210\206\201 \203\192\194\202\197: '..tostring(#live))
        V.list_rows('arb_live_shop',live,86,function(deal,i)
            V.row('arb_live_row_'..i,86,function(w,x,y)
                V.at(x,y+2);V.text(V.fit(deal.name..' \183 \235\224\226\234\224 #'..tostring(deal.shop),w))
                V.at(x,y+27);V.muted(V.fit('\202\243\239\232\242\252 '..DSP.money(deal.buy_price)..' / \241\228\224\242\252 '..DSP.money(deal.sell_price),w))
                V.at(x,y+52);V.green(V.fit('~ +'..DSP.money(deal.profit_unit)..'/\248\242. \239\238\241\235\229 \234\238\236\232\241\241\232\232 \183 '..
                    (deal.verified_quantity and ('\228\238 '..tostring(deal.quantity)..' \248\242.') or '\234\238\235\232\247\229\241\242\226\238 \237\229\232\231\226\229\241\242\237\238'),w))
            end)
        end,{height=math.min(180,math.max(90,imgui.GetContentRegionAvail().y*.30)),footer=false})
    end
    local groups,status
    if DSP.market.arbitrage_grouped_ui then groups,status=DSP.market.arbitrage_grouped_ui()else groups=DSP.market.arbitrage_grouped()end
    if status=='loading'then V.muted('\208\224\241\247\184\242 \240\251\237\234\224...')elseif status=='error'then V.red('\206\248\232\225\234\224 \240\224\241\247\184\242\224. \209\236. \230\243\240\237\224\235')end
    local sig=tostring(groups)..'|'..DSP.lower(query)..'|'..tostring(V.arb_sort)
    local filtered=V.memo('arb_rows',sig,function()
        local out={};local q=DSP.lower(query)
        for _,g in ipairs(groups)do if q==''or DSP.lower(g.name):find(q,1,true)then out[#out+1]=g end end
        -- Cached per market snapshot, filter and sort mode; never sort every render frame.
        table.sort(out,function(a,b)
            if V.arb_sort=='profit' and a.profit~=b.profit then return a.profit>b.profit end
            local an,bn=DSP.lower(a.name),DSP.lower(b.name)
            if an~=bn then return an<bn end
            return tostring(a.key)<tostring(b.key)
        end)
        return out
    end)
    if st.status=='cache' then V.red(V.fit('\209\229\242\252 \237\229\228\238\241\242\243\239\237\224: \240\224\241\247\184\242 \239\238 \241\238\245\240\224\237\184\237\237\238\236\243 \241\237\232\236\234\243, \237\224\235\232\247\232\229 \237\229 \239\238\228\242\226\229\240\230\228\229\237\238',imgui.GetContentRegionAvail().x))end
    if status~='loading' and #groups==0 and DSP.market.arbitrage_visibility then
        local d=DSP.market.arbitrage_visibility()
        if d.pairs>0 then
            V.muted(V.fit('\194 API \229\241\242\252 '..d.pairs..' \246\229\237\238\226\251\245 \240\224\231\240\251\226\238\226 (\226 \238\228\237\238\233 \235\224\226\234\229: '..d.same_shop..
                '), \237\238 \244\232\235\252\242\240 \241\226\229\230\229\241\242\232/\238\225\250\184\236\224/\234\238\236\232\241\241\232\232 \232\241\234\235\254\247\232\235 \236\224\240\248\240\243\242\251.',imgui.GetContentRegionAvail().x))
        end
    end
    if #filtered==0 and status~='loading' then
        local age=tonumber((DSP.settings.arb_filters or{}).max_age)or 300
        local reason=#groups>0 and '\207\238 \231\224\239\240\238\241\243 \237\232\247\229\227\238 \237\229 \237\224\233\228\229\237\238' or
            (#(st.rows or{})==0 and '\205\229\242 \240\251\237\234\224: \237\224\230\236\232\242\229 \171\206\225\237\238\226\232\242\252\187' or
            ('\205\229\242 \226\251\227\238\228\237\251\245 \241\226\255\231\238\234 \239\238 \244\232\235\252\242\240\224\236'..(age>0 and (' \183 \241\242\224\240\248\229 '..math.floor(age/60)..'\236 \232\241\234\235\254\247\229\237\251')or '')))
        V.muted(V.fit(reason,imgui.GetContentRegionAvail().x))
    end
    V.list_rows('arb_main',filtered,92,function(g,i)
        V.row('arb_group_'..i,92,function(w,x,y)
            M.thumbnail({name=g.name,id=g.row and g.row.id},34)
            V.at(x+44,y+2);V.text(V.fit(g.name,w-220))
            V.at(x+44,y+29);V.muted(V.fit('\202\243\239\232\242\252: '..DSP.market.format_units(g.supply)..
                ' \183 \209\228\224\242\252: '..DSP.market.format_units(g.demand)..' \248\242. (API)',w-220))
            V.at(x+44,y+54);V.muted(V.fit('\207\235\224\237 '..DSP.market.format_units(g.planned)..
                ' \248\242. \183 \206\246\229\237\234\224 \239\240\232\225\251\235\232 '..DSP.money(g.profit),w-220))
            V.at(x+w-164,y+15)
            if b('\207\240\229\228\235\238\230\229\237\232\255 >','group_'..i,160,false)then
                V.arb_item=g.key;V.arb_snapshot=tostring(st.sid)..'/'..tostring(st.version)
                V.arb_server=st.sid;V.arb_detail_group=g;V.arb_snapshot_time=os.time()
                V.arb_route=false;V.arb_tab='sell';V.arb_best_error=nil;V.arb_verify=nil;choose_all(g);V.open_popup('\192\240\225\232\242\240\224\230','arb_details')
            end
        end)
    end,{footer=function()V.muted('\206\246\229\237\234\224 \239\238 API, \237\229 \227\224\240\224\237\242\232\240\238\226\224\237\237\224\255 \239\240\232\225\251\235\252. \202\238\235\232\247\229\241\242\226\238 \243 \241\234\243\239\249\232\234\224 \236\238\230\229\242 \243\236\229\237\252\248\232\242\252\241\255.')end})
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    if V.arb_filters then V.popup('\212\232\235\252\242\240\251 \224\240\225\232\242\240\224\230\224','arb_filters',function()
        local f=DSP.settings.arb_filters or {};DSP.settings.arb_filters=f
        -- Fields are saved as numeric settings and never trigger requests per frame.
        -- 0 seconds means any age; percentage fields use explicit units.
        local changed=false
        local function number(label,key,min,limit)
            V.muted(label)
            if M.compact_number(f,key,'arb_filter_'..key,math.min(260,imgui.GetContentRegionAvail().x),min)then
                if limit and f[key]>limit then f[key]=limit;M.refresh_buffer(f,key) end
                changed=true
            end
        end
        V.list('arb_filter_controls',function(w)
            number('\209\226\229\230\229\241\242\252 \228\224\237\237\251\245: \236\224\234\241\232\236\243\236 \241\229\234\243\237\228 (0 = \225\229\231 \238\227\240\224\237\232\247\229\237\232\255, 3600 = \247\224\241)', 'max_age',0,2592000)
            if b('10 \236\232\237','age10',110) then f.max_age=600;M.refresh_buffer(f,'max_age');changed=true end
            V.inline();if b('1 \247\224\241','age60',110)then f.max_age=3600;M.refresh_buffer(f,'max_age');changed=true end
            V.inline();if b('\203\254\225\238\233 \226\238\231\240\224\241\242','age_any',170)then f.max_age=0;M.refresh_buffer(f,'max_age');changed=true end
            number('\202\238\236\232\241\241\232\255 \226 \225\224\231\232\241\237\251\245 \239\243\237\234\242\224\245: 100 = 1%, 250 = 2.5%', 'tax_bp',0,10000)
            number('\208\229\231\229\240\226 \241\239\240\238\241\224 (%) \238\242 0 \228\238 90: \238\241\242\224\226\235\255\242\252 \237\229\239\240\238\226\229\240\229\237\237\251\233 \238\225\250\184\236', 'safety_pct',0,90)
            number('\204\232\237\232\236\224\235\252\237\224\255 \240\229\237\242\224\225\229\235\252\237\238\241\242\252 ROI (%)', 'min_roi',0,100000)
            number('\204\232\237\232\236\224\235\252\237\224\255 \247\232\241\242\224\255 \239\240\232\225\251\235\252 \237\224 \236\224\240\248\240\243\242 ($)', 'min_profit',0)
            number('\204\232\237\232\236\224\235\252\237\224\255 \239\240\232\225\251\235\252 \241 \238\228\237\238\233 \248\242\243\234\232 ($)', 'min_unit_profit',0)
            number('\204\224\234\241\232\236\224\235\252\237\224\255 \246\229\237\224 \231\224\234\243\239\234\232 \231\224 \248\242\243\234\243 ($; 0 = \225\229\231 \235\232\236\232\242\224)', 'max_buy_price',0)
            number('\204\232\237\232\236\224\235\252\237\251\233 \231\224\239\224\241 \200 \241\239\240\238\241 API (\248\242.; 0 = \225\229\231 \235\232\236\232\242\224)', 'min_stock',0)
            number('\193\254\228\230\229\242 \237\224 \226\241\229 \236\224\240\248\240\243\242\251 ($; 0 = \225\229\231 \235\232\236\232\242\224)', 'budget',0)
            number('\204\224\234\241\232\236\243\236 \248\242\243\234 \237\224 \236\224\240\248\240\243\242 (0 = \225\229\231 \235\232\236\232\242\224)', 'max_qty',0)
            V.muted('\203\224\226\234\232: \235\254\225\238\229 \241\238\247\229\242\224\237\232\229 / \242\238\235\252\234\238 \238\228\237\224 \232 \242\224 \230\229 / \242\238\235\252\234\238 \240\224\231\237\251\229')
            for i,opt in ipairs({{0,'\203\254\225\251\229'},{1,'\206\228\237\224'},{2,'\208\224\231\237\251\229'}})do
                if i>1 then V.inline()end
                if b(opt[2],'shop_mode_'..opt[1],110,f.shop_mode==opt[1])then f.shop_mode=opt[1];changed=true end
            end
            V.muted('\207\238\240\255\228\238\234 \240\224\241\247\184\242\224 (\239\240\232 \225\254\228\230\229\242\229 \239\240\232\238\240\232\242\229\242 ROI)')
            for i,opt in ipairs({{1,'\207\240\232\225\251\235\252'},{2,'\199\224 \248\242\243\234\243'},{3,'ROI'}})do
                if i>1 then V.inline()end
                if b(opt[2],'sort_mode_'..opt[1],110,f.sort==opt[1])then f.sort=opt[1];changed=true end
            end
            if b(f.allow_partial==false and '[ ] \215\224\241\242\232\247\237\251\229 \236\224\240\248\240\243\242\251' or '[x] \215\224\241\242\232\247\237\251\229 \236\224\240\248\240\243\242\251',
                'allow_partial',290)then f.allow_partial=not(f.allow_partial~=false);changed=true end
            if b(f.include_unknown==true and '[x] \193\229\231 \238\242\236\229\242\234\232 \226\240\229\236\229\237\232' or '[ ] \193\229\231 \238\242\236\229\242\234\232 \226\240\229\236\229\237\232',
                'include_unknown',290)then f.include_unknown=not(f.include_unknown==true);changed=true end
            if b('\209\225\240\238\241\232\242\252 \244\232\235\252\242\240\251','reset_filters',210)then
                local defaults={budget=0,min_profit=0,min_roi=0,sort=1,max_age=300,max_qty=0,
                    safety_pct=10,allow_partial=true,include_unknown=false,
                    tax_bp=DSP.settings.tax_bp or 200,min_unit_profit=0,max_buy_price=0,
                    min_stock=0,shop_mode=0}
                for k,v in pairs(defaults)do f[k]=v;M.refresh_buffer(f,k)end
                changed=true
            end
            V.muted('\194\238\231\240\224\241\242 0 \238\231\237\224\247\224\229\242 \239\238\234\224\231 \228\224\230\229 \241\242\224\240\251\245 \238\244\244\229\240\238\226; \253\242\238 \237\229 \227\224\240\224\237\242\232\255 \237\224\235\232\247\232\255.')
        end,{footer=true})
        if changed then
            DSP.market.invalidate_arbitrage();V.arb_revision=V.arb_revision+1
            V.reset_list('arb_main');M.defer_save()
        end
        if b('\207\240\232\236\229\237\232\242\252 \232 \231\224\234\240\251\242\252','filters_done',220,true)then
            V.arb_filters=false;imgui.CloseCurrentPopup()
        end
    end,{w=690,h=570})end
    V.popup('\192\240\225\232\242\240\224\230','arb_details',function()
        local st=DSP.market.state
        if V.arb_server~=st.sid then
            V.text('\194\251\225\240\224\237 \228\240\243\227\238\233 \241\229\240\226\229\240');V.muted('\206\242\234\240\238\233\242\229 \239\240\229\228\236\229\242 \239\238\226\242\238\240\237\238 \228\235\255 \237\238\226\238\227\238 \240\224\241\247\184\242\224')
            if b('\199\224\234\240\251\242\252','stale_close',150)then imgui.CloseCurrentPopup()end
            return
        end
        -- Never keep showing the old route after a market refresh: source
        -- offer tables are replaced, not updated in place.
        if V.arb_snapshot~=tostring(st.sid)..'/'..tostring(st.version)
            or st.status=='loading' then
            V.red('\196\224\237\237\251\229 \232\231\236\229\237\232\235\232\241\252 \232\235\232 \238\225\237\238\226\235\255\254\242\241\255. \209\242\224\240\251\233 \236\224\240\248\240\243\242 \231\224\225\235\238\234\232\240\238\226\224\237.')
            if b('\207\229\240\229\241\247\232\242\224\242\252','refresh_selected',164)then
                local groups,status
                if DSP.market.arbitrage_grouped_ui then
                    groups,status=DSP.market.arbitrage_grouped_ui()
                else groups=DSP.market.arbitrage_grouped()end
                if status~='loading' then
                    local g=V.arb_group(groups)
                    if g then
                        V.arb_detail_group=g;choose_all(g);V.arb_route=false
                        V.arb_verify=nil;V.arb_snapshot=tostring(st.sid)..'/'..tostring(st.version)
                        V.arb_snapshot_time=os.time()
                    else V.arb_best_error='\207\238\241\235\229 \238\225\237\238\226\235\229\237\232\255 \239\238\228\245\238\228\255\249\232\233 \236\224\240\248\240\243\242 \238\242\241\243\242\241\242\226\243\229\242'end
                end
            end
            V.inline();if b('\199\224\234\240\251\242\252','stale_close_version',140)then imgui.CloseCurrentPopup()end
            -- Keep the inspected snapshot browsable, but expose no old route,
            -- quantity confirmation or marker actions after a refresh.
            local snapshot=V.arb_detail_group
            if snapshot then
                if b('\207\240\238\228\224\254\242 \183 \241\237\232\236\238\234','sell',190,V.arb_tab=='sell')then V.arb_tab='sell'end
                V.inline();if b('\209\234\243\239\224\254\242 \183 \241\237\232\236\238\234','buy',190,V.arb_tab=='buy')then V.arb_tab='buy'end
                local offers=V.arb_tab=='sell'and snapshot.sellers or snapshot.buyers
                V.list_rows('arb_stale_'..snapshot.key..'_'..V.arb_tab,offers,76,function(o,i)
                    V.row('stale_offer_'..i,76,function(w,x,y)
                        V.text(V.fit('#'..tostring(o.shop)..' \183 '..tostring(o.owner or '?'),w))
                        V.at(x,y+26);V.muted(V.fit(DSP.money(o.price)..'/\248\242. \183 '..DSP.market.format_units(o.qty)..' \248\242. \183 \241\242\224\240\251\233 API-\241\237\232\236\238\234',w))
                    end)
                end)
            end
            return
        end
        local g=V.arb_detail_group
        if g then details(g)else
            V.muted('\209\226\255\231\234\224 \225\238\235\252\248\229 \237\229 \239\240\238\245\238\228\232\242 \244\232\235\252\242\240\251')
            if b('\199\224\234\240\251\242\252','empty_close',140)then imgui.CloseCurrentPopup()end
        end
    end,{w=850,h=560})
end

      end
      _v286_arbitrage_ui()
      local function _v286_local_arbitrage_ui()
-- Local scanned routes are kept separate from unverified API opportunities.
local V = DSP.ui21
local A = DSP.local_arb
local M = DSP.market
local function b(label,id,w,active) return V.button(label,'local_arb_'..id,w,active) end
local function elapsed(at,now)
    local n=math.max(0,now-(tonumber(at)or 0))
    return tostring(math.floor(n/60))..' \236\232\237 \237\224\231\224\228'
end
local function txt(s,w) return V.fit(s,math.max(1,w)) end
function V.local_arbitrage_view()
    local now=os.time()
    local stats=A.stats(now)
    local auto=DSP.settings.auto_shop_scan~=false
    if b(auto and '\192\194\210\206\209\202\192\205: \194\202\203' or '\192\194\210\206\209\202\192\205: \194\219\202\203','auto_toggle',180) then
        DSP.settings.auto_shop_scan=not auto
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
        else DSP.save_settings() end
        auto=not auto
    end
    V.inline()
    V.muted('\209\234\224\237\232\240\243\229\242 \239\240\232 \238\242\234\240\251\242\232\232 \235\224\226\234\232, \225\229\231 \234\237\238\239\234\232 \232 \225\229\231 API')
    local saver=DSP.settings.fps_saver==true
    if b(saver and '\221\202\206\205\206\204\200\223 FPS: \194\202\203' or '\221\202\206\205\206\204\200\223 FPS: \194\219\202\203','fps_toggle',200) then
        DSP.settings.fps_saver=not saver
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
        else DSP.save_settings() end
    end
    V.inline()
    V.muted('\206\242\234\235\254\247\224\229\242 \228\238\239\238\235\237\232\242\229\235\252\237\251\229 \238\234\237\224 \232 \232\234\238\237\234\232, \224\226\242\238\241\234\224\237 \238\241\242\224\184\242\241\255')
    local last=DSP.live and DSP.live.auto_scan
    if last and (last.at or 0)>0 then
        V.muted('\207\238\241\235\229\228\237\232\233 \241\234\224\237: \235\224\226\234\224 #'..tostring(last.shop)..' | '..tostring(last.items)..' \239\238\231\232\246\232\233 | '..elapsed(last.at,now))
    end
    V.green('\200\199 \209\202\192\205\206\194 \194 \200\195\208\197 \183 \193\197\199 API')
    V.muted('\203\224\226\238\234: '..stats.shops..' \183 \239\240\229\228\235\238\230\229\237\232\233: '..stats.offers..' \183 \239\224\236\255\242\252: 60 \236\232\237')
    V.muted('\209\238\245\240\224\237\255\254\242\241\255 \246\229\237\251 \242\238\235\252\234\238 \206\210\202\208\219\210\219\213 \235\224\226\238\234 \241 \232\231\226\229\241\242\237\251\236 \237\238\236\229\240\238\236. \207\240\238\226\229\240\255\233 \237\224\235\232\247\232\229 \239\229\240\229\228 \241\228\229\235\234\238\233.')
    local query,changed=V.search('local_arb','\205\224\231\226\224\237\232\229 \239\240\229\228\236\229\242\224 \232\235\232 \237\238\236\229\240 \235\224\226\234\232',-1)
    if changed then V.reset_list('local_arb_items');V.reset_list('local_offer_search') end
    if query~='' and DSP.shop_store and DSP.shop_store.search then
        local matches=DSP.shop_store.search(query,nil,stats.server)
        V.green('\xc2\xf1\xe5 \xef\xf0\xe5\xe4\xeb\xee\xe6\xe5\xed\xe8\xff \xe8\xe7 \xf1\xea\xe0\xed\xee\xe2: '..tostring(#matches))
        V.list_rows('local_offer_search',matches,78,function(ref,i)
            local o,sh=ref.offer or{},ref.shop or{}
            V.row('local_offer_'..i,78,function(w,x,y)
                local side=ref.side=='buy' and '\xf1\xea\xf3\xef\xea\xe0' or '\xef\xf0\xee\xe4\xe0\xe6\xe0'
                V.at(x,y+1);V.text(txt(tostring(o.name or '?')..'  ['..side..']',w))
                V.at(x,y+27);V.muted(txt('\xeb\xe0\xe2\xea\xe0 #'..tostring(sh.num or '?')..' \xb7 '..DSP.money(tonumber(o.price) or 0)..'/\xf8\xf2. \xb7 x'..tostring(o.qty or '?'),w))
                V.at(x,y+51);V.muted(txt(tostring(sh.owner or '?')..' \xb7 '..elapsed(sh.at,now),w))
            end)
        end,{height=math.min(260,math.max(92,#matches*78)),footer=false})
        V.muted('\xcf\xee\xe8\xf1\xea \xe2\xfb\xf8\xe5 \xe8\xe4\xb8\xf2 \xef\xee \xef\xee\xeb\xed\xee\xec\xf3 \xe8\xed\xe4\xe5\xea\xf1\xf3 \xf1\xea\xe0\xed\xee\xe2; \xed\xe8\xe6\xe5 -- \xf2\xee\xeb\xfc\xea\xee \xe2\xfb\xe3\xee\xe4\xed\xfb\xe5 \xe0\xf0\xe1\xe8\xf2\xf0\xe0\xe6\xed\xfb\xe5 \xef\xe0\xf0\xfb.')
    end
    local revision=table.concat({A.revision,math.floor(now/10),DSP.settings.tax_bp or 200,
        M.missing_revision or 0,DSP.arb_agent and DSP.arb_agent.revision or 0,DSP.lower(query)},'|')
    local routes=V.memo('local_arb_routes',revision,function()
        local all=A.routes(now)
        local q=DSP.lower(query)
        if q==''then return all end
        local out={}
        for _,r in ipairs(all) do
            local hay=DSP.lower(tostring(r.name or '')..' '..tostring(r.seller_shop)..' '..tostring(r.buyer_shop))
            if hay:find(q,1,true) then out[#out+1]=r end
        end
        return out
    end)
    V.muted('\205\224\233\228\229\237\238 \241\226\255\231\238\234: '..tostring(#routes)..' \183 \239\238\240\255\228\238\234: \239\240\232\225\251\235\252 \231\224 1 \248\242.')
    if #routes==0 then V.muted('\205\229\242 \226\251\227\238\228\237\251\245 \239\224\240 \232\231 \242\226\238\232\245 \241\234\224\237\238\226 \231\224 \239\238\241\235\229\228\237\232\233 \247\224\241.') end
    V.list_rows('local_arb_items',routes,142,function(r,i)
        V.row('local_route_'..i,142,function(w,x,y)
            local text_width=math.max(130,w-134)
            V.at(x,y+1);V.text(txt((r.name or 'ID:'..r.id)..' +'..tostring(r.ench or 0),text_width))
            V.at(x,y+28);V.muted(txt('\202\211\207\200\210\220: #'..r.seller_shop..' \183 '..DSP.money(r.buy_price)..'/\248\242.',text_width))
            V.at(x,y+51);V.muted(txt('\209\196\192\210\220: #'..r.buyer_shop..' \183 '..DSP.money(r.sell_price)..'/\248\242.',text_width))
            V.at(x,y+75);V.green(txt('~ +'..DSP.money(r.profit_unit)..'/\248\242. \239\238\241\235\229 \234\238\236\232\241\241\232\232',text_width))
            V.at(x,y+100)
            V.muted(txt('\209\234\224\237: '..elapsed(r.seller_at,now)..' / '..elapsed(r.buyer_at,now),w))
            V.at(x+math.max(0,w-124),y+33)
            if b('\204\224\240\248\240\243\242 >','open_'..i,118) then
                V.local_route={server=stats.server,route=r}
                V.open_popup('\204\224\240\248\240\243\242 \232\231 \241\234\224\237\224','local_route')
            end
        end)
    end,{footer=function()
        V.muted('\207\238\242\229\237\246\232\224\235\252\237\251\229 \246\229\237\251, \205\197 \240\229\224\235\252\237\251\229 \239\240\238\228\224\230\232. \205\229\232\231\226\229\241\242\237\251\229 \238\225\250\184\236\251 \237\229 \241\243\236\236\232\240\243\254\242\241\255.')
    end})
end
local previous=V.popups
function V.popups()
    if previous then previous() end
    V.popup('\204\224\240\248\240\243\242 \232\231 \241\234\224\237\224','local_route',function()
        local selected=V.local_route
        if not selected or selected.server~=A.stats().server then
            V.red('\209\236\229\237\232\235\241\255 \241\229\240\226\229\240. \194\251\225\229\240\232 \236\224\240\248\240\243\242 \231\224\237\238\226\238.')
            if b('\199\224\234\240\251\242\252','changed_close',150) then imgui.CloseCurrentPopup()end
            return
        end
        local r=selected.route
        local age=os.time()
        if age-r.seller_at>=A.ttl or age-r.buyer_at>=A.ttl then
            V.red('\196\224\237\237\251\229 \243\241\242\224\240\229\235\232. \206\242\234\240\238\233 \235\224\226\234\232 \231\224\237\238\226\238.')
            if b('\199\224\234\240\251\242\252','stale_close',150)then imgui.CloseCurrentPopup()end
            return
        end
        V.text(txt(r.name or '?',imgui.GetContentRegionAvail().x))
        V.green('\200\209\210\206\215\205\200\202: \235\238\234\224\235\252\237\251\233 \241\234\224\237 \226 \232\227\240\229, \237\229 API')
        V.text('1. \202\211\207\200\210\220 \226 \235\224\226\234\229 #'..r.seller_shop..' ('..tostring(r.seller_owner or '?')..')')
        V.muted(DSP.money(r.buy_price)..' \231\224 \248\242\243\234\243 \183 '..elapsed(r.seller_at,age))
        V.text('2. \209\196\192\210\220 \226 \235\224\226\234\243 #'..r.buyer_shop..' ('..tostring(r.buyer_owner or '?')..')')
        V.muted(DSP.money(r.sell_price)..' \231\224 \248\242\243\234\243 \183 '..elapsed(r.buyer_at,age))
        V.text('\207\238\241\242\243\239\235\229\237\232\255 \239\238\241\235\229 \234\238\236\232\241\241\232\232: '..DSP.money(r.net_unit)..' \231\224 \248\242\243\234\243')
        V.green('\207\238\242\229\237\246\232\224\235\252\237\224\255 \239\240\232\225\251\235\252: +'..DSP.money(r.profit_unit)..' \231\224 \248\242\243\234\243')
        if r.qty and r.profit_total then
            V.muted('\200\231\226\229\241\242\237\251\233 \235\232\236\232\242: \228\238 '..r.qty..' \248\242. \183 \239\238\242\238\235\238\234 \239\240\232\225\251\235\232 ~ '..DSP.money(r.profit_total))
        else
            V.muted('\202\238\235\232\247\229\241\242\226\238 \237\229\232\231\226\229\241\242\237\238: \232\242\238\227\238\226\243\254 \239\240\232\225\251\235\252 \237\229 \240\224\241\241\247\232\242\251\226\224\229\236.')
        end
        V.red('\209\234\224\237 \205\197 \227\224\240\224\237\242\232\240\243\229\242, \247\242\238 \239\240\229\228\235\238\230\229\237\232\229 \229\249\184 \241\243\249\229\241\242\226\243\229\242!')
        if DSP.arb_agent and r.qty and b('\194 \204\200\205\200-\192\195\197\205\210','local_to_agent',186)then
            local ok,why=DSP.arb_agent.add_local_route(r)
            if ok then DSP.arb_agent.show(true);imgui.CloseCurrentPopup()
            else DSP.notify('\192\227\229\237\242: '..tostring(why))end
        end
        if b('\204\229\242\234\224 \239\240\238\228\224\226\246\224','seller_marker',155) then M.mark_shop(r.seller_shop)end
        V.inline();if b('\204\229\242\234\224 \241\234\243\239\249\232\234\224','buyer_marker',155) then M.mark_shop(r.buyer_shop)end
        if b('\205\229\242 \235\224\226\234\232 #'..r.seller_shop,'seller_missing',195) then
            M.mark_shop_missing(r.seller_shop,30);if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
            imgui.CloseCurrentPopup()
        end
        V.inline();if b('\205\229\242 \235\224\226\234\232 #'..r.buyer_shop,'buyer_missing',195) then
            M.mark_shop_missing(r.buyer_shop,30);if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
            imgui.CloseCurrentPopup()
        end
        V.cancel('local_route')
    end,{w=710,h=440})
end
return true
      end
      _v286_local_arbitrage_ui()
      local function _v286_arb_agent_model()
-- Palatka Arbitrage Session: many routes, local execution ledger and a floating guide.
-- Read-only game integration: confirmation is manual, receipt matching only suggests.
-- This module never submits purchase/sale packets and never edits the remote API.
DSP.arb_agent=DSP.arb_agent or {}
local A=DSP.arb_agent
local M=DSP.market
local MAX=9007199254740991
local function num(v,lo,hi)
    local n=tonumber(v)
    if n and n==n and n%1==0 and n>=(lo or 0)and n<=(hi or MAX)then return math.floor(n)end
end
local function server()
    local detected
    if type(DSP.detect_server)=='function'then
        local ok,id=pcall(DSP.detect_server)
        if ok then detected=num(id,1)end
    end
    return detected or num(M.state and M.state.sid,1)
        or num(DSP.settings and DSP.settings.server,1)or 0
end
local function cycle_start(ts)
    local date=os.date('*t',ts or os.time())
    date.hour,date.min,date.sec=5,0,0
    local start=os.time(date)
    return(ts or os.time())<start and(start-86400)or start
end
local function part(v)
    local s=tostring(v or '')
    return tostring(#s)..':'..s
end
local function eq(a,b)
    if DSP.lower then return DSP.lower(tostring(a or''))==DSP.lower(tostring(b or''))end
    return tostring(a or''):lower()==tostring(b or''):lower()
end
local function key(sid,row,side,o)
    if not row or not o then return nil end
    local fields={sid,side,row.key or row.item_key or row.name or'',o.shop,o.owner,o.price,o.ts or 0}
    local out={}
    for i,v in ipairs(fields)do out[i]=part(v)end
    return table.concat(out,'|')
end
A.quote_key=key
A.path=(DSP.dir or '.')..'/arb_agent_v1.json'
A.data=A.data or {schema=1,session=nil,consumed={},history={}}
A.revision=A.revision or 0
A.hint=nil
local function safe_data(d)
    return type(d)=='table'and d.schema==1 and type(d.consumed)=='table'
        and type(d.history)=='table'and (d.session==nil or type(d.session)=='table')
end
function A.load()
    local f=io.open(A.path,'rb')
    if not f then return false end
    local raw=f:read('*a')or'';f:close()
    local ok,d=pcall(decodeJson,raw)
    if not ok or not safe_data(d)then return false end
    A.data=d
    if A.data.session and type(A.data.session.routes)~='table'then A.data.session=nil end
    return true
end
function A.save()
    local ok,raw=pcall(encodeJson,A.data)
    if not ok or type(raw)~='string'then return false,'encode'end
    local tmp=A.path..'.tmp'
    local f,err=io.open(tmp,'wb')
    if not f then return false,err end
    local wrote,why=f:write(raw);local closed,close_err=f:close()
    if not wrote or not closed then os.remove(tmp);return false,why or close_err or'write'end
    local renamed,rename_err=os.rename(tmp,A.path)
    if not renamed then os.remove(tmp);return false,rename_err or'rename'end
    return true
end
local function changed()
    A.revision=A.revision+1
    local ok,err=A.save()
    A.save_error=not ok and tostring(err)or nil
    if not ok and DSP.flog then DSP.flog('ARB AGENT save failed: '..tostring(err))end
    if M.invalidate_arbitrage then M.invalidate_arbitrage()end
    return ok,err
end
local function active()
    local s=A.data.session
    if not s or s.ended or s.sid~=server()
        or(num(s.started,0)or 0)<cycle_start(os.time())then return nil end
    return s
end
function A.active()return active()end
function A.is_open()
    return DSP.settings.arb_agent_open==true and active()~=nil
end
function A.show(value)
    DSP.settings.arb_agent_open=value~=false
    if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
    elseif DSP.save_settings then DSP.save_settings()end
end
function A.stop()
    local s=active()
    if not s then return false,'ГЌГҐГІ Г ГЄГІГЁГўГ­Г®Г© Г±ГҐГ±Г±ГЁГЁ'end
    s.ended=os.time()
    A.show(false)
    return changed()
end
local function record_snapshot(route,sid)
    if type(route)~='table'or not route.sell_offer or not route.buy_offer
        or not route.row then return nil end
    local q=num(route.tradable_qty,1,1000000000)
    local cost=num(route.p_buy,1,MAX)
    local price=num(route.p_sell,1,MAX)
    if not q or not cost or not price or price<=cost or q*math.max(cost,price)>MAX then return nil end
    local row=route.row
    local sell=route.sell_offer
    local buy=route.buy_offer
    local cut=cycle_start(os.time())
    -- Do not requeue a previous server-day quote after the expected 05:00 restart.
    local sell_at,buy_at=num(sell.ts,1),num(buy.ts,1)
    if (sell_at and sell_at<cut)or(buy_at and buy_at<cut)then return nil end
    local sk=key(sid,row,'sell',sell)
    local bk=key(sid,row,'buy',buy)
    local ts=os.time()
    local entry={
        id='',sid=sid,name=tostring(route.name or row.display or row.name or'?'),
        item_key=tostring(row.key or''),ench=num(row.ench,0,1000)or 0,
        qty=q,bought=0,sold=0,buy_price=cost,sell_price=price,
        seller_shop=tostring(sell.shop or'?'),buyer_shop=tostring(buy.shop or'?'),
        seller_owner=tostring(sell.owner or'?'),buyer_owner=tostring(buy.owner or'?'),
        seller_quote=sk,buyer_quote=bk,
        seller_ts=num(sell.ts,0)or 0,buyer_ts=num(buy.ts,0)or 0,
        proposed_profit=num(route.net_profit,0)or 0,created=ts
    }
    entry.id=sk..'>'..bk
    return entry
end
local function route_pending(e)
    return not e.skipped and e.sold<e.qty
end
local function count_open(s)
    local n=0
    for _,e in ipairs(s.routes)do if route_pending(e)then n=n+1 end end
    return n
end
local function append_routes(routes,cap)
    local s=active()
    if not s then return 0 end
    local seen={}
    for _,e in ipairs(s.routes)do seen[e.id]=true end
    local fresh=0;local open=count_open(s)
    for _,r in ipairs(routes or{})do
        if open>=(cap or 24)or #s.routes>=250 then break end
        local entry=record_snapshot(r,s.sid)
        if entry and not seen[entry.id]then
            seen[entry.id]=true
            s.routes[#s.routes+1]=entry
            open=open+1;fresh=fresh+1
        end
    end
    if fresh>0 then changed()end
    return fresh
end
function A.start(routes)
    if server()==0 then return false,'Г‘ГҐГ°ГўГҐГ° ГҐГ№Вё Г­ГҐ Г®ГЇГ°ГҐГ¤ГҐГ«ВёГ­'end
    local s=active()
    if not s then
        A.data.session={sid=server(),started=os.time(),routes={},focus=1,last_review=0,
            tax_bp=num(DSP.settings.tax_bp,0,10000)or 200}
    end
    local n=append_routes(routes,24)
    if n==0 and #A.data.session.routes==0 then
        A.data.session=nil
        return false,'ГЌГ®ГўГ»Гµ ГЇГ°ГЁГЈГ®Г¤Г­Г»Гµ Г¬Г Г°ГёГ°ГіГІГ®Гў ГЇГ®ГЄГ  Г­ГҐГІ'
    end
    A.show(true)
    return true,n
end
function A.add_plan(plan)
    local routes=plan and plan.routes
    if type(routes)~='table'or#routes==0 then return false,'Г‚ ГЇГ«Г Г­ГҐ Г­ГҐГІ Г¬Г Г°ГёГ°ГіГІГ®Гў'end
    return A.start(routes)
end
function A.start_market()
    if M.state.status=='cache'or M.state.status=='error'then
        return false,'ГЌГҐГІ Г±ГўГҐГ¦ГҐГЈГ® Г°Г»Г­ГЄГ ; ГЇГ°Г®ГўГҐГ°ГјГІГҐ API ГЁГ«ГЁ Г«Г®ГЄГ Г«ГјГ­Г»Г© Г±ГЄГ Г­'
    end
    local groups,status
    if M.arbitrage_grouped_ui then groups,status=M.arbitrage_grouped_ui()
    else groups=M.arbitrage_grouped();status='ready'end
    if status~='ready'or not groups then return false,'ГђГ»Г­Г®ГЄ ГҐГ№Вё Г°Г Г±Г±Г·ГЁГІГ»ГўГ ГҐГІГ±Гї'end
    local routes={}
    for _,g in ipairs(groups)do for _,r in ipairs(g.routes or{})do routes[#routes+1]=r end end
    table.sort(routes,function(a,b)return(tonumber(a.net_profit)or 0)>(tonumber(b.net_profit)or 0)end)
    return A.start(routes)
end
-- A locally scanned route can join the same session if both quantities are known.
-- The local quote identity is separate from remote API identities.
function A.add_local_route(r)
    if type(r)~='table' or not num(r.qty,1,1000000000)then
        return false,'Г‘ГЄГ Г­ Г­ГҐ ГЇГ®Г¤ГІГўГҐГ°Г¤ГЁГ« ГЄГ®Г«ГЁГ·ГҐГ±ГІГўГ® Г± Г®ГЎГҐГЁГµ Г±ГІГ®Г°Г®Г­'
    end
    local item_key=tostring(r.id or'?')..':'..tostring(r.ench or 0)
    local row={key=item_key,display=r.name,ench=r.ench or 0}
    local sell={shop=r.seller_shop,owner=r.seller_owner,price=r.buy_price,ts=r.seller_at}
    local buy={shop=r.buyer_shop,owner=r.buyer_owner,price=r.sell_price,ts=r.buyer_at}
    local p={row=row,name=r.name,sell_offer=sell,buy_offer=buy,
        tradable_qty=r.qty,p_buy=r.buy_price,p_sell=r.sell_price,net_profit=r.profit_total or 0}
    return A.add_plan({routes={p}})
end
function A.get(index)
    local s=active()
    return s and s.routes[index],s
end
function A.focus(index)
    local s=active()
    if not s then return false end
    index=num(index,1,#s.routes)
    if not index then return false end
    s.focus=index
    A.save()
    return true
end
function A.next(step)
    local s=active()
    if not s or #s.routes==0 then return false end
    local count=#s.routes;local i=num(s.focus,1,count)or 1
    for _=1,count do
        i=((i-1+(step or 1))%count)+1
        if route_pending(s.routes[i])then return A.focus(i)end
    end
    return A.focus(i)
end
function A.stats()
    local s=active();local out={routes=0,done=0,skipped=0,bought=0,sold=0,
        pending=0,profit_estimate=0,spent_estimate=0}
    if not s then return out end
    out.routes=#s.routes
    local bp=num(s.tax_bp,0,10000)or num(DSP.settings.tax_bp,0,10000)or 200
    local factor=10000-bp
    for _,e in ipairs(s.routes)do
        local b=num(e.bought,0)or 0;local sold=num(e.sold,0)or 0
        out.bought=out.bought+b;out.sold=out.sold+sold
        if e.skipped then out.skipped=out.skipped+1
        elseif sold==e.qty then out.done=out.done+1
        else out.pending=out.pending+1 end
        -- Confirming a trade does not prove the actual receipt amount.
        -- These figures remain estimates at originally quoted prices/tax.
        local gross=sold*e.sell_price
        local revenue=math.floor(gross/10000)*factor+math.floor((gross%10000)*factor/10000)
        out.profit_estimate=out.profit_estimate+revenue-sold*e.buy_price
        out.spent_estimate=out.spent_estimate+b*e.buy_price
    end
    return out
end
local function consumed_entry(quote)
    return A.data.consumed[quote]
end
local function consume(quote,n,at)
    local c=consumed_entry(quote)or{qty=0,at=0}
    c.qty=(num(c.qty,0)or 0)+n;c.at=at
    A.data.consumed[quote]=c
end
function A.confirm(index,side,amount)
    local e,s=A.get(index)
    if not e or not s then return false,'ГЌГҐГІ ГІГ ГЄГ®Г© Г±Г¤ГҐГ«ГЄГЁ'end
    if e.skipped then return false,'Г‘Г¤ГҐГ«ГЄГ  ГЇГ°Г®ГЇГіГ№ГҐГ­Г 'end
    if side~='buy'and side~='sell'then return false,'ГЌГҐГЁГ§ГўГҐГ±ГІГ­Г»Г© ГІГЁГЇ'end
    local limit=side=='buy'and(e.qty-e.bought)or(e.bought-e.sold)
    local q=num(amount,1,limit)
    if not q then return false,'ГЉГ®Г«ГЁГ·ГҐГ±ГІГўГ® ГЇГ°ГҐГўГ»ГёГ ГҐГІ Г®Г±ГІГ ГўГёГЁГ©Г±Гї Г«ГЁГ¬ГЁГІ'end
    local at=os.time()
    if side=='buy'then
        e.bought=e.bought+q;e.bought_at=at
        consume(e.seller_quote,q,at)
    else
        e.sold=e.sold+q;e.sold_at=at
        consume(e.buyer_quote,q,at)
    end
    s.last_action=at
    A.data.history[#A.data.history+1]={
        session_started=s.started,route_id=e.id,side=side,qty=q,
        item=e.name,at=at,method='manual',price=side=='buy'and e.buy_price or e.sell_price
    }
    if #A.data.history>1000 then table.remove(A.data.history,1)end
    if A.hint and A.hint.route_id==e.id and A.hint.side==side then A.hint=nil end
    changed()
    if e.sold==e.qty then A.next(1)end
    return true,q
end
function A.skip(index,value)
    local e=A.get(index);if not e then return false end
    e.skipped=value~=false
    changed()
    return true
end
function A.remaining(row,side,offer,base,meta)
    local q=num(base,0)or 0
    local quote=key(server(),row,side,offer)
    local c=quote and consumed_entry(quote)
    if not c then return q,meta end
    local last=num(c.at,0)or 0
    if last<cycle_start(os.time())then return q,meta end
    -- A newer complete game observation supersedes our local bookkeeping.
    if meta and(meta.source=='recent_scan'or meta.source=='game_observed')
        and (num(meta.at,0)or 0)>last then return q,meta end
    return math.max(0,q-(num(c.qty,0)or 0)),{source='local_execution',at=last}
end
local base_offer_qty=M.offer_quantity
if type(base_offer_qty)=='function'and not A._quantity_hook then
    M.offer_quantity=function(row,side,offer,now)
        local q,meta=base_offer_qty(row,side,offer,now)
        return A.remaining(row,side,offer,q,meta)
    end
    A._quantity_hook=true
end
local function matches_receipt(entry,side,name,amount)
    if not eq(entry.name,name)or entry.skipped then return false end
    local limit=side=='buy'and(entry.qty-entry.bought)or(entry.bought-entry.sold)
    local unit=side=='buy'and entry.buy_price or entry.sell_price
    return limit>0 and amount>0 and amount%unit==0 and amount/unit<=limit
end
function A.observe_receipt(side,name,amount)
    if side~='buy'and side~='sell'then return false end
    amount=num(amount,1);if not amount then return false end
    local s=active()
    if not s then return false end
    local matched,qty=nil,nil
    for i,e in ipairs(s.routes)do
        if matches_receipt(e,side,name,amount)then
            if matched then A.hint=nil;return false end -- ambiguous
            matched=i;qty=amount/(side=='buy'and e.buy_price or e.sell_price)
        end
    end
    if matched then
        A.hint={index=matched,route_id=s.routes[matched].id,side=side,
            qty=qty,amount=amount,at=os.time()}
        return true
    end
    return false
end
local log_market=DSP.craglog and DSP.craglog.log_market
if type(log_market)=='function'and not A._receipt_hook then
    DSP.craglog.log_market=function(direction,item,amount,raw)
        local ok,err=log_market(direction,item,amount,raw)
        if ok then pcall(A.observe_receipt,direction,item,amount)end
        return ok,err
    end
    A._receipt_hook=true
end
function A.review_market()
    local s=active();if not s then return false end
    local now=os.time()
    if now-(num(s.last_review,0)or 0)<60 then return false end
    s.last_review=now
    -- 60-second review is LOCAL; it never bypasses market API backoff.
    if M.state.status~='live'then return false end
    local groups,status
    if M.arbitrage_grouped_ui then groups,status=M.arbitrage_grouped_ui()
    else groups=M.arbitrage_grouped();status='ready'end
    if status~='ready'or not groups then return false end
    local routes={}
    for _,g in ipairs(groups)do for _,r in ipairs(g.routes or{})do routes[#routes+1]=r end end
    table.sort(routes,function(a,b)return(tonumber(a.net_profit)or 0)>(tonumber(b.net_profit)or 0)end)
    return append_routes(routes,24)>0
end
function A.install()
    if A.installed then return end
    A.installed=true
    A.load()
    -- Keep a finished session available in history but never reactivate it.
    if imgui and imgui.OnFrame then
        imgui.OnFrame(A.is_open,function()
            local ok,err=xpcall(A.draw,debug.traceback)
            if not ok then
                if DSP.flog then DSP.flog('ARB AGENT UI: '..tostring(err))end
                A.show(false)
            end
        end)
    end
end
return true

      end
      _v286_arb_agent_model()
      local function _v286_arb_agent_overlay()
-- Compact floating assistant for an entire arbitrage session (not one route).
-- Controls never send trades; all execution acknowledgement is explicit.
local A=DSP.arb_agent
local M=DSP.market
local U=DSP.ui
local V=DSP.ui22
local function cp(v)return DSP.utf8(tostring(v or''))end
local function btn(label,id,w,h)
    return imgui.Button(cp(label)..'##arb_agent_'..id,imgui.ImVec2(w or -1,h or 34))
end
local function text(s)imgui.Text(cp(s))end
local function muted(s)imgui.TextDisabled(cp(s))end
local function good(s)imgui.TextColored(DSP.theme.col('good',1),cp(s))end
local function bad(s)imgui.TextColored(DSP.theme.col('bad',1),cp(s))end
local function fmt(n)return DSP.money(tonumber(n)or 0)end
local function notify(msg)
    A.ui_message=tostring(msg or'')
    if DSP.flog then DSP.flog('ARB AGENT: '..A.ui_message)end
end
local function selected(s)
    local i=math.min(math.max(1,tonumber(s.focus)or 1),math.max(1,#s.routes))
    return s.routes[i],i
end
local function flag(e)
    if e.skipped then return 'ГЏГђГЋГЏГ“Г™Г…ГЌГЋ' end
    if e.sold==e.qty then return 'Г‡ГЂГ‚Г…ГђГГ…ГЌГЋ' end
    if e.bought==0 then return 'ГЉГ“ГЏГ€Г’Гњ' end
    if e.bought<e.qty then return 'Г„ГЋГЉГ“ГЏГ€Г’Гњ' end
    return 'Г‘Г„ГЂГ’Гњ'
end
local function geometry(sw,sh)
    local p=DSP.settings.arb_agent_window or{}
    local maxw=math.max(220,sw-16)
    local maxh=math.max(180,sh-16)
    local w=DSP.clamp(tonumber(p.w)or math.min(360,maxw),math.min(280,maxw),maxw)
    local h=DSP.clamp(tonumber(p.h)or math.min(440,maxh),math.min(280,maxh),maxh)
    return {w=w,h=h,x=DSP.clamp(tonumber(p.x)or(sw-w-10),0,math.max(0,sw-w)),
        y=DSP.clamp(tonumber(p.y)or math.max(8,sh*.16),0,math.max(0,sh-h))}
end
local function save_geometry(g,dx,dy,dw,dh,io)
    local sw,sh=io.DisplaySize.x,io.DisplaySize.y
    local x=DSP.clamp(g.x+(dx or 0),0,math.max(0,sw-g.w))
    local y=DSP.clamp(g.y+(dy or 0),0,math.max(0,sh-g.h))
    local w=DSP.clamp(g.w+(dw or 0),math.min(280,sw-16),sw-x)
    local h=DSP.clamp(g.h+(dh or 0),math.min(280,sh-16),sh-y)
    DSP.settings.arb_agent_window={x=x,y=y,w=w,h=h}
    if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
end
local function header(s,g,io)
    local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
    if btn('ГЂГђГЃГ€Г’ГђГЂГ† / MOVE','drag',math.max(65,g.w-119),32)then end
    if imgui.IsItemActive()and io.MouseDelta then
        local d=io.MouseDelta
        if d.x~=0 or d.y~=0 then save_geometry(g,d.x,d.y,0,0,io)end
    end
    imgui.SameLine(0,4)
    if btn(A.queue_expanded and '-' or '+','queue_toggle',33,32)then
        A.queue_expanded=not A.queue_expanded
    end
    imgui.SameLine(0,4)
    if btn('X','close',34,32)then A.show(false)end
end
local function summary(s)
    local st=A.stats()
    good('Г‘Г¤ГҐГ«Г®ГЄ: '..st.done..' / '..st.routes..'  |  Г‚ Г°Г ГЎГ®ГІГҐ: '..st.pending)
    text('ГЉГіГЇГ«ГҐГ­Г®: '..st.bought..'  |  Г‘Г¤Г Г­Г®: '..st.sold)
    good('ГЏГ°ГЁГЎГ»Г«Гј ~ '..fmt(st.profit_estimate))
    muted('ГђГ Г±Г·ВёГІ ГЇГ® Г¶ГҐГ­Г Г¬ ГЇГ«Г Г­Г , Г­ГҐ ГЇГ®Г¤ГІГўГҐГ°Г¦Г¤ВёГ­Г­Г Гї ГЄГ Г±Г±Г ')
    local updated=M.state and M.state.updated or 0
    muted('API: '..(M.freshness and M.freshness()or'Г­ГҐГІ Г¤Г Г­Г­Г»Гµ')..' | Г®ГЎГ§Г®Г° ГЄГ Г¦Г¤Г»ГҐ 60 Г±')
end
local function queue(s)
    local total=#s.routes
    if total==0 then muted('ГЊГ Г°ГёГ°ГіГІГ®Гў ГЇГ®ГЄГ  Г­ГҐГІ');return end
    A.queue_page=math.max(1,math.min(tonumber(A.queue_page)or 1,math.ceil(total/5)))
    local pages=math.ceil(total/5)
    muted('Г‚Г±ГҐ Г¬Г Г°ГёГ°ГіГІГ», ГўГЄГ«ГѕГ·Г Гї Г§Г ГўГҐГ°ГёВёГ­Г­Г»ГҐ: '..total)
    local first=(A.queue_page-1)*5+1
    for i=first,math.min(total,first+4)do
        local e=s.routes[i]
        local label=(i==s.focus and '* 'or'')..tostring(i)..'. '..e.name..
            ' | '..flag(e)..' '..e.sold..'/'..e.qty
        if btn(label,'route_'..i,-1,30)then A.focus(i);A.qty_key=nil end
    end
    if pages>1 then
        if btn('<','queue_prev',52,28)then A.queue_page=math.max(1,A.queue_page-1)end
        imgui.SameLine(0,5)
        muted('Г‘ГІГ°Г Г­ГЁГ¶Г  '..A.queue_page..'/'..pages)
        imgui.SameLine(0,5)
        if btn('>','queue_next',52,28)then A.queue_page=math.min(pages,A.queue_page+1)end
    end
end
-- Normal ImGui input is used intentionally: unavailable native exotic widgets
-- must not make the floating assistant impossible to close.
function A.draw()
    local s=A.active()
    if not s then A.show(false);return end
    if A.review_market then A.review_market()end
    local io=imgui.GetIO()
    local g=geometry(io.DisplaySize.x,io.DisplaySize.y)
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    local colors=DSP.theme.push_window()
    imgui.SetNextWindowBgAlpha(.90)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(7,6))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,5))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,6)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoResize+imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoScrollbar
    if imgui.Begin('##palatka_arbitrage_agent',nil,flags)then
        if imgui.SetWindowFontScale then
            imgui.SetWindowFontScale(1)
            local fs=imgui.GetFontSize()
            imgui.SetWindowFontScale(math.min(1.15,15/math.max(1,fs)))
        end
        header(s,g,io)
        imgui.Separator()
        if imgui.BeginChild('##arb_agent_scroll',imgui.ImVec2(0,-40),false)then
            summary(s)
            imgui.Separator()
            if A.queue_expanded then
                queue(s)
                if not A.end_confirm then
                    if btn('Г‡Г ГўГҐГ°ГёГЁГІГј Г±ГҐГ±Г±ГЁГѕ','end_session',-1,28)then A.end_confirm=true end
                else
                    bad('Г‡Г ГўГҐГ°ГёГЁГІГј ГІГҐГЄГіГ№ГіГѕ Г±ГҐГ±Г±ГЁГѕ? Г€Г±ГІГ®Г°ГЁГї Г®Г±ГІГ Г­ГҐГІГ±Гї.')
                    if btn('Г„Г , Г§Г ГўГҐГ°ГёГЁГІГј','end_yes',-1,30)then
                        A.stop();A.end_confirm=false
                    end
                    if btn('ГЋГІГ¬ГҐГ­Г ','end_cancel',-1,28)then A.end_confirm=false end
                end
                imgui.Separator()
            end
            local e,index=selected(s)
            if e then
                text('ГЊГЂГђГГђГ“Г’ '..index..' / '..#s.routes..' | '..flag(e))
                text(V.fit(e.name,math.max(100,imgui.GetContentRegionAvail().x-8)))
                muted('ГЏГ«Г Г­: '..e.qty..' ГёГІ. | Г®Г¦ГЁГ¤Г Г­ГЁГҐ ~ '..fmt(e.proposed_profit))
                muted('ГЉГіГЇГ«ГҐГ­Г® '..e.bought..' / '..e.qty..' | ГЏГ°Г®Г¤Г Г­Г® '..e.sold..' / '..e.qty)
                -- Confirming each step updates the local offer ledger, never cash history.
                if e.skipped then
                    if btn('Г‚ГҐГ°Г­ГіГІГј','restore',-1)then A.skip(index,false)end
                else
                    local side=e.bought<e.qty and'buy'or'sell'
                    local remaining=side=='buy'and(e.qty-e.bought)or(e.bought-e.sold)
                    if remaining>0 then
                        local shop=side=='buy'and e.seller_shop or e.buyer_shop
                        local owner=side=='buy'and e.seller_owner or e.buyer_owner
                        local unit=side=='buy'and e.buy_price or e.sell_price
                        text(side=='buy'and'ГЉГ“ГЏГ€Г’Гњ' or'Г‘Г„ГЂГ’Гњ')
                        text('Г‹Г ГўГЄГ  #'..shop..' | '..owner)
                        text('x'..remaining..' | '..fmt(unit)..'/ГёГІ.')
                        if btn('ГЌГ Г©ГІГЁ Г«Г ГўГЄГі #'..shop,'target',-1)then
                            if not M.mark_shop(shop)then notify('ГЊГҐГІГЄГ  Г­ГҐГ¤Г®Г±ГІГіГЇГ­Г ')end
                        end
                        local input_key=e.id..':'..side
                        if A.qty_key~=input_key then A.qty_key=input_key;A.qty_field=imgui.new.int(remaining)end
                        muted('ГЏГ®Г¤ГІГўГҐГ°Г¤ГЁГІГј ГЄГ®Г«ГЁГ·ГҐГ±ГІГўГ®:')
                        imgui.SetNextItemWidth(math.min(160,imgui.GetContentRegionAvail().x))
                        imgui.InputInt('##arb_agent_qty',A.qty_field,1,10)
                        if btn(side=='buy'and'ГЉГ“ГЏГ‹Г…ГЌГЋ' or'ГЏГђГЋГ„ГЂГЌГЋ','confirm',-1,39)then
                            local ok,why=A.confirm(index,side,A.qty_field[0])
                            if ok then A.qty_key=nil;notify('ГЏГ®Г¤ГІГўГҐГ°Г¦Г¤ГҐГ­Г®: '..e.name)
                            else notify(tostring(why))end
                        end
                        local hint=A.hint
                        if hint and hint.route_id==e.id and hint.side==side then
                            muted('ГЏГ®ГµГ®Г¦ГЁГ© Г·ГҐГЄ: '..hint.qty..' ГёГІ. (Г­ГҐ Г ГўГІГ®Г§Г Г·ВёГІ)')
                            if btn('ГЏГ®Г¤ГІГўГҐГ°Г¤ГЁГІГј Г·ГҐГЄ','accept_receipt',-1)then
                                local ok,why=A.confirm(index,side,hint.qty)
                                if ok then A.qty_key=nil;notify('Г—ГҐГЄ ГЇГ®Г¤ГІГўГҐГ°Г¦Г¤ВёГ­')
                                else notify(tostring(why))end
                            end
                        end
                    else good('ГЊГ Г°ГёГ°ГіГІ ГўГ»ГЇГ®Г«Г­ГҐГ­')end
                end
            else
                muted('ГЊГ Г°ГёГ°ГіГІГ» ГЇГ®ГїГўГїГІГ±Гї ГЇГ®Г±Г«ГҐ Г±ГЄГ Г­ГЁГ°Г®ГўГ Г­ГЁГї Г°Г»Г­ГЄГ ')
            end
        end
        imgui.EndChild()
        if A.save_error then bad('Г‡Г ГЇГЁГ±Гј Г­ГҐ Г±Г®ГµГ°Г Г­ГҐГ­Г : '..tostring(A.save_error))end
        if A.ui_message then muted(V.fit(A.ui_message,math.max(80,g.w-32)))end
        if btn('<','previous',47,30)then A.next(-1);A.qty_key=nil end
        imgui.SameLine(0,5)
        if btn('>','next',47,30)then A.next(1);A.qty_key=nil end
        imgui.SameLine(0,5)
        local e,i=selected(s)
        if e and btn('ГЏГ°Г®ГЇГіГ±ГІГЁГІГј','skip',100,30)then A.skip(i,true);A.next(1);A.qty_key=nil end
        imgui.SameLine(0,5)
        if btn('ГЊГҐГ­Гѕ','main',65,30)then
            if U and U.set_open then U.set_open(true)end
            if V and V.set_screen then V.set_screen('arbitrage')end
        end
        -- Bottom-right corner belongs to resize, not to gameplay.
        imgui.SetCursorPos(imgui.ImVec2(g.w-44,g.h-34))
        btn('//','size',30,27)
        if imgui.IsItemActive()and io.MouseDelta then
            local d=io.MouseDelta
            if d.x~=0 or d.y~=0 then save_geometry(g,0,0,d.x,d.y,io)end
        end
    end
    imgui.End()
    imgui.PopStyleVar(3)
    if colors and colors>0 then imgui.PopStyleColor(colors)end
end
return true

      end
      _v286_arb_agent_overlay()
      if DSP.arb_agent and DSP.arb_agent.install then DSP.arb_agent.install() end

    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka 2.8.6 UI / agent install: '..tostring(err)) end
      return false
    end
    DSP._v286_installed=true
    DSP.version='2.8.6'
    if DSP.flog then DSP.flog('Palatka v2.8.6 Arbitrage Agent installed') end
    return true
  end
  -- v2.8.7: restore original Palatka UI and keep the arbitrage session.
  local function install_v287()
    local applied=install_v286()
    if not applied then return false end
    if DSP._v287_installed then DSP.version='2.8.7';return true end
    local ok,err=pcall(function()
      DSP.settings.ui_style='carbon'
      DSP.settings.mcr_window=nil
      DSP.settings.mcr_classic_alpha=nil
      local function _v287_original_mini()
-- Phone journal: one stable anchor, fixed controls, and readable event cards.
local C=DSP.craglog
local function cp(s) return DSP.utf8(tostring(s or '')) end
local function text(s) imgui.TextWrapped(cp(s)) end
local function button(label,id,w,active)
    if active then imgui.PushStyleColor(imgui.Col.Button,DSP.theme.col('accent',.7)) end
    local hit=imgui.Button(cp(label)..'##mini_'..id,imgui.ImVec2(w,54))
    if active then imgui.PopStyleColor(1) end
    return hit
end
local function inline() imgui.SameLine(0,8) end
local function state() return DSP.settings.craglog end
local function header(g)
    local s=state()
    local handle=s.pinned and '\198\211\208\205\192\203 / \199\192\202\208\197\207\203\168\205' or '\198\211\208\205\192\203 / \207\197\208\197\210\192\217\200\210\220'
    button(handle,'handle',g.w-300,false)
    if not s.pinned and imgui.IsItemActive() and imgui.IsMouseDragging(0) then
        local delta=imgui.GetIO().MouseDelta
        C.drag(delta.x,delta.y)
    end
    if not imgui.IsMouseDown(0) then C.end_drag() end
    inline()
    if button(s.pinned and 'PIN: \196\192' or 'PIN: \205\197\210','pin',120,s.pinned) then C.set_pinned(not s.pinned) end
    inline()
    if button(s.minimized and '+' or '-','collapse',60) then C.set_minimized(not s.minimized) end
    inline()
    if button('X','close',60) then s.open=false; DSP.save_settings() end
end
local function filters(g)
    local s=state()
    for i,pair in ipairs({{'all','\194\241\229'},{'loot','\210\224\233\237\232\234\232'},{'payday','PayDay'},
                           {'sales','\207\240\238\228\224\230\232'},{'buys','\209\234\243\239\234\224'},{'income','\196\238\245\238\228\251'}}) do
        if button(pair[2],'filter_'..pair[1],(g.w-42)/3,s.filter==pair[1]) then
            s.filter=pair[1]; C.scroll=0; DSP.save_settings()
        end
        if i%3~=0 then inline() end
    end
end
local function row_card(entry)
    local kind=entry.kind or entry.type
    local tag=kind=='item' and '\205\192\195\208\192\196\192' or kind=='cash' and '\196\197\205\220\195\200' or kind=='opening' and '\210\192\201\205\200\202'
        or entry.type=='payday' and 'PAYDAY' or entry.type=='income' and '\196\206\213\206\196' or '\209\196\197\203\202\192'
    imgui.TextColored(DSP.theme.col('accent',1),cp(os.date('%H:%M:%S',entry.ts or 0)..'  '..tag))
    text(C.describe(entry))
    if entry.source then
        text('\200\241\242\238\247\237\232\234: '..entry.source..(entry.association=='inferred' and ' (\239\238 \247\224\242\243)' or ''))
    end
    imgui.Separator()
end
function C.draw()
    local io=imgui.GetIO()
    local g=C.geometry(io.DisplaySize.x,io.DisplaySize.y)
    local s=state()
    C.active_geometry=g
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    local force_size=(not C._window_size_initialized) or C._last_minimized~=s.minimized
    if force_size then imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always) end
    if not s.minimized and imgui.SetNextWindowSizeConstraints then
        imgui.SetNextWindowSizeConstraints(imgui.ImVec2(360,280),imgui.ImVec2(math.max(360,io.DisplaySize.x-16),math.max(280,io.DisplaySize.y-16)))
    end
    C._window_size_initialized=true;C._last_minimized=s.minimized
    imgui.SetNextWindowBgAlpha(.96)
    local colors=DSP.theme.push_overlay(.98)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,16)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,9)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(12,12))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(8,8))
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove
        +imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoFocusOnAppearing
    if imgui.Begin('##palatka_mini_journal',nil,flags) then
        if imgui.SetWindowFontScale then imgui.SetWindowFontScale(1.15) end
        header(g)
        if not s.minimized then
            filters(g)
            local events=C.filtered(s.filter or 'all')
            local per=3
            C.scroll=math.max(0,math.min(C.scroll,math.max(0,#events-per)))
            local start=#events-C.scroll
            text('\207\238\241\235\229\228\237\232\229 \241\238\225\251\242\232\255: '..#events..' / '..C.ring_cap..'   |   PIN \244\232\234\241\232\240\243\229\242 \239\238\235\238\230\229\237\232\229')
            if button('\194\194\197\208\213 / \205\206\194\197\197','up',(g.w-40)/2,C.scroll>0) then C.scroll=math.max(0,C.scroll-per) end
            inline()
            if button('\194\205\200\199 / \209\210\192\208\216\197','down',(g.w-40)/2,start>per) then C.scroll=math.min(math.max(0,#events-per),C.scroll+per) end
            start=#events-C.scroll
            local shown=imgui.BeginChild('##mini_cards',imgui.ImVec2(0,0),false)
            if shown then
                if #events==0 then
                    text('\199\228\229\241\252 \239\238\255\226\255\242\241\255 \241\228\229\235\234\232, \228\229\237\252\227\232 \232 \237\224\227\240\224\228\251 \232\231 \232\227\240\238\226\238\227\238 \247\224\242\224.')
                    text('\207\238\235\237\224\255 \232\241\242\238\240\232\255 \228\238\241\242\243\239\237\224 \226 \227\235\224\226\237\238\236 \236\229\237\254.')
                end
                for i=start,math.max(1,start-per+1),-1 do if events[i] then row_card(events[i]) end end
                if C.last_error then text('\206\248\232\225\234\224 \231\224\239\232\241\232: '..C.last_error) end
            end
            imgui.EndChild()
        end
    end
    if not s.minimized and imgui.GetWindowSize then
        local ws=imgui.GetWindowSize();C.remember_size(ws.x,ws.y)
    end
    C.end_resize()
    imgui.End()
    imgui.PopStyleVar(4)
    if colors and colors>0 then imgui.PopStyleColor(colors) end
end
return true

      end
      _v287_original_mini()
      local function _v287_original_geometry()
function C.geometry(sw,sh)
    local s=config()
    local w=math.min(math.max(390,math.min(550,sw*.24)),sw-16)
    local h=math.min(math.max(330,math.min(480,sh*.43)),sh-16)
    local x=math.max(8,math.min(tonumber(s.x)or 24,sw-w-8))
    local y=math.max(8,math.min(tonumber(s.y)or 120,sh-h-8))
    return{x=x,y=y,w=w,h=s.minimized and 56 or h,touch=42,max_x=sw-w-8,max_y=sh-h-8}
end

      end
      _v287_original_geometry()
      local function _v287_original_journal()
-- Journal overview: quantities and estimated loot value, with inspectable receipts.
local V,M,C=DSP.ui22,DSP.mobile,DSP.craglog
local periods={{'session','\209\229\241\241\232\255'},{'day','\209\229\227\238\228\237\255'},{'all','\194\241\184 \226\240\229\236\255'}}
local categories={{'all','\194\241\229'},{'loot','\205\224\227\240\224\228\251'},{'payday','PayDay'},{'sales','\207\240\238\228\224\230\232'},
 {'buys','\207\238\234\243\239\234\232'},{'income','\196\238\245\238\228\251'},{'other','\196\240\243\227\238\229'}}
V.journal_mode='loot';V.journal_period='day';V.journal_category=1
local function b(s,id,w,on)return V.button(s,'journal_'..id,w,on)end
local function cycle_period()
    local pos=1;for i,p in ipairs(periods)do if p[1]==V.journal_period then pos=i end end
    if b(periods[pos][2]..' >','period',140,true)then V.journal_period=periods[pos%3+1][1]end
end
function C.event_title(e)
    if e.kind=='item'or e.type=='crate'then return tostring(e.item_name or e.item or '\205\229\232\231\226\229\241\242\237\251\233 \239\240\229\228\236\229\242')..' x'..tostring(e.qty or e.count or 1)end
    if e.kind=='opening'then return '\206\242\234\240\251\242\232\229: '..tostring(e.source or '\200\241\242\238\247\237\232\234 \237\229\232\231\226\229\241\242\229\237')end
    if e.kind=='unknown'then return '\205\229\240\224\241\239\238\231\237\224\237\237\224\255 \237\224\227\240\224\228\224'end
    if e.kind=='cash'then return '\196\229\237\252\227\232 \232\231 \237\224\227\240\224\228\251'end
    if e.type=='payday'or e.kind=='payday'then return 'PayDay'end
    if e.type=='market'then return(e.direction=='sell'and'\207\240\238\228\224\230\224: 'or'\207\238\234\243\239\234\224: ')..tostring(e.item_name or '?')end
    if e.type=='income'or e.kind=='income'then return tostring(e.label or '\196\238\245\238\228')end
    return '\206\225\236\229\237: '..tostring(e.partner or '\200\227\240\238\234 \237\229\232\231\226\229\241\242\229\237')
end
function C.event_cash(e)
    if e.kind=='cash'then return tonumber(e.cash)or 0 end
    if e.type=='payday'then return tonumber(e.amount)end
    if e.type=='income'or e.kind=='income'then return tonumber(e.amount)end
    if e.type=='market'then return(tonumber(e.amount)or 0)*(e.direction=='sell'and 1 or -1)end
    if e.type=='trade'then return(tonumber(e.money_get)or 0)-(tonumber(e.money_give)or 0)end
end
local function cash_text(amount)
    if not amount then return end
    if amount>=0 then V.green('+'..DSP.money(amount))else V.red('-'..DSP.money(-amount))end
end
local function footer(key)
    local summary=C.summary(V.journal_period)
    local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY();local w=imgui.GetContentRegionAvail().x
    if w>800 then V.muted('\196\238\245\238\228 '..DSP.money(summary.income)..' \183 \208\224\241\245\238\228 '..DSP.money(summary.expense))
    else V.muted('\196\229\237\229\230\237\251\233 \232\242\238\227 '..DSP.money(summary.net))end
    V.at(x+w-126,y);V.scroll_buttons(key)
end
local function loot_row(row,i)
    V.row('loot_'..i,60,function(w,x,y)
        M.thumbnail({name=row.name},32)
        V.at(x+42,y-3)
        if V.text_button(V.fit(row.name,w-280),'journal_loot_'..i,w-270,false,30)then V.loot_detail=row;V.open_popup('\207\238\235\243\247\229\237\237\224\255 \228\238\225\251\247\224','loot_detail')end
        V.at(x+42,y+27);V.muted(row.receipts..' \239\238\235\243\247\229\237\232\233'..(row.ench>0 and(' \183 +'..row.ench)or''))
        V.at(x+w-220,y+5);V.text('x'..row.qty)
        V.at(x+w-150,y+4)
        if row.estimated>0 then V.green('~ '..DSP.money(row.estimated))else V.muted('\214\229\237\224 \237\229\232\231\226\229\241\242\237\224')end
        V.at(x+w-150,y+27)
        if row.unpriced_qty>0 then V.muted('\193\229\231 \246\229\237\251: '..row.unpriced_qty)
        elseif row.unit_estimate then V.muted('~ '..DSP.money(row.unit_estimate)..'/\248\242.')end
    end)
end
local function event_row(e,i)
    V.row('event_'..i,58,function(w,x,y)
        V.at(x,y-3)
        if V.text_button(V.fit(C.event_title(e),w-180),'tools_entry_'..i,w-168,false,30)then
            V.journal_detail=e;V.open_popup('\209\238\225\251\242\232\229','event')
        end
        V.at(x,y+27);V.muted(V.fit(os.date('%d.%m %H:%M',e.ts or 0)..' \183 '..tostring(e.source or e.label or '\207\238\228\240\238\225\237\238\241\242\232 \239\238 \237\224\230\224\242\232\254'),w-180))
        V.at(x+w-160,y+6);cash_text(C.event_cash(e))
    end)
end
function V.journal()
    V.heading('\198\243\240\237\224\235',function()
        cycle_period();V.inline()
        if b('\204\232\237\232-\230\243\240\237\224\235','mini',150)then DSP.settings.craglog.open=true;M.defer_save()end
    end,296)
    local w=imgui.GetContentRegionAvail().x
    if b('\196\238\225\251\247\224','loot_mode',120,V.journal_mode=='loot')then V.journal_mode='loot'end
    V.inline();if b('\209\238\225\251\242\232\255','events_mode',120,V.journal_mode=='events')then V.journal_mode='events'end
    V.inline()
    if V.journal_mode=='events'then
        local pos=V.journal_category
        if b(categories[pos][2]..' >','category',112,true)then V.journal_category=pos%#categories+1 end
        V.inline()
    end
    local query,edited=V.search('journal','\207\238\232\241\234 \239\240\229\228\236\229\242\224 \232\235\232 \232\241\242\238\247\237\232\234\224',-1)
    if edited then
        V.reset_list('journal_loot_'..V.journal_period)
        V.reset_list('journal_events_'..V.journal_period..V.journal_category)
    end
    if V.journal_mode=='loot'then
        local summary=C.loot_summary(V.journal_period,query)
        V.muted(V.fit(summary.qty..' \248\242. \183 \207\240\238\228\224\230\224 ~ '..DSP.money(summary.estimated)..' \183 \193\229\231 \246\229\237\251 '..summary.unpriced_qty..' \248\242.',w))
        V.list_rows('journal_loot_'..V.journal_period,summary.items,60,loot_row,{toolbar=footer})
    else
        local from=C.period_start(V.journal_period);local all=C.history and C.history(categories[V.journal_category][1],query)or C.filtered(categories[V.journal_category][1])
        local rows=V.memo('journal_period_rows',tostring(all)..'/'..from,function()
            local out={};for _,e in ipairs(all)do if(e.ts or 0)>=from then out[#out+1]=e end end;return out
        end)
        V.muted(#rows..' \241\238\225\251\242\232\233 \183 \237\224\230\236\232\242\229 \241\242\240\238\234\243 \228\235\255 \239\238\228\240\238\225\237\238\241\242\229\233')
        V.list_rows('journal_events_'..V.journal_period..V.journal_category,rows,58,event_row,{toolbar=footer})
    end
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    V.popup('\207\238\235\243\247\229\237\237\224\255 \228\238\225\251\247\224','loot_detail',function()
        local row=V.loot_detail;if not row then return end
        V.text(row.name..(row.ench>0 and(' (+'..row.ench..')')or''))
        V.muted('\207\238\235\243\247\229\237\238 '..row.qty..' \248\242. \183 '..row.receipts..' \238\242\228\229\235\252\237\251\245 \239\238\235\243\247\229\237\232\233')
        if row.estimated>0 then V.green('\207\240\232\236\229\240\237\224\255 \239\240\238\228\224\230\224 ~ '..DSP.money(row.estimated))end
        if row.unpriced_qty>0 then V.muted('\214\229\237\224 \237\229\232\231\226\229\241\242\237\224 \228\235\255 '..row.unpriced_qty..' \248\242.')end
        V.muted(tostring(row.price_source or '\205\229\242 \240\251\237\238\247\237\238\233 \238\246\229\237\234\232')..(row.price_ts and(' \183 '..os.date('%d.%m %H:%M',row.price_ts))or''))
        V.muted('\206\246\229\237\234\224 \237\229 \227\224\240\224\237\242\232\240\243\229\242 \239\240\238\228\224\230\243 \226\241\229\227\238 \234\238\235\232\247\229\241\242\226\224 \239\238 \253\242\238\233 \246\229\237\229')
        V.loot_tab=V.loot_tab or 'receipts'
        if b('\207\238\235\243\247\229\237\232\255','receipts',145,V.loot_tab=='receipts')then V.loot_tab='receipts'end
        V.inline();if b('\200\241\242\238\247\237\232\234\232','sources',145,V.loot_tab=='sources')then V.loot_tab='sources'end
        local h=math.max(48,imgui.GetContentRegionAvail().y-50)
        if V.loot_tab=='sources'then
            V.list('loot_sources',function()
                for source,qty in pairs(row.sources)do V.text(source..' \183 x'..qty)end
            end,{height=h,footer=function()if b('\199\224\234\240\251\242\252','loot_close',140)then imgui.CloseCurrentPopup()end end})
        else
            V.list_rows('loot_receipts',row.events,52,function(e,i)
                if V.text_button(V.fit(os.date('%d.%m %H:%M',e.ts or 0)..' \183 x'..tostring(e.qty or e.count or 1)..' \183 '..tostring(e.source or '\205\229\232\231\226\229\241\242\237\251\233 \232\241\242\238\247\237\232\234'),imgui.GetContentRegionAvail().x-12),'journal_receipt_'..i,-1)then
                    V.journal_detail=e;imgui.CloseCurrentPopup();V.open_popup('\209\238\225\251\242\232\229','event')
                end
            end,{height=h,footer=function()if b('\199\224\234\240\251\242\252','loot_close',140)then imgui.CloseCurrentPopup()end end})
        end
    end,{w=720,h=520})
end

      end
      _v287_original_journal()

      local function _v287_availability()
-- Arbitrage agent availability: user-confirmed absence and trusted game evidence.
-- Quote absence is NOT inferred from a partial shop snapshot.
local A,M=DSP.arb_agent,DSP.market
local function now()return os.time()end
local function sid()return tonumber(M.state and M.state.sid)or tonumber(DSP.settings.server)or 0 end
local function cycle(t)
    local d=os.date('*t',t);d.hour=5;d.min=0;d.sec=0
    local boundary=os.time(d);return t<boundary and boundary-86400 or boundary
end
local function text_eq(x,y)
    local f=DSP.lower or string.lower
    return f(tostring(x or''))==f(tostring(y or''))
end
local function valid_shop(shop)
    local n=tonumber(shop)
    return n and n>0 and n<=99999 and n==math.floor(n)
end
local function ensure()
    A.data=A.data or{schema=1,consumed={},history={}}
    A.data.unavailable=A.data.unavailable or{}
    return A.data.unavailable
end
local old_load=A.load
function A.load(...)
    local result=old_load(...)
    ensure()
    return result
end
ensure()
local old_remaining=A.remaining
function A.remaining(row,side,offer,base,meta)
    local qty,origin=old_remaining(row,side,offer,base,meta)
    local quote=A.quote_key(sid(),row,side,offer)
    local denied=quote and ensure()[quote]
    if denied and tonumber(denied.at)and denied.at>=cycle(now())then
        -- Trusted positive game observation AFTER the manual absence supersedes it.
        local evidence=origin and (origin.source=='game_observed' or origin.source=='recent_scan')
        if evidence and (tonumber(origin.at)or 0)>denied.at and qty>0 then
            ensure()[quote]=nil;A.save()
            return qty,origin
        end
        return 0,{source='confirmed_unavailable',at=denied.at,reason=denied.reason}
    end
    return qty,origin
end
local function changed()
    A.revision=(A.revision or 0)+1
    local ok,err=A.save()
    A.save_error=ok and nil or tostring(err)
    if M.invalidate_arbitrage then M.invalidate_arbitrage()end
    return ok,err
end
local function required_leg(e)
    if e.bought<e.qty then return 'sell',e.seller_shop,e.seller_quote end
    if e.sold<e.qty then return 'buy',e.buyer_shop,e.buyer_quote end
end
local function block_related(shop,quote,reason,source)
    local s=A.active();if not s then return 0 end
    local marked=0
    for _,e in ipairs(s.routes or{})do
        local side,target,current=required_leg(e)
        local match=side and ((quote and current==quote)or
            (not quote and tostring(target)==tostring(shop)))
        if match and e.sold<e.qty and not e.unavailable_reason then
            e.unavailable_reason=reason
            e.unavailable_source=source or'manual'
            e.unavailable_at=now()
            e.unavailable_side=side
            e.skipped=true
            marked=marked+1
        end
    end
    return marked
end
function A.mark_unavailable(index,reason)
    if reason~='shop'and reason~='item'then return false,'\205\229\226\229\240\237\224\255 \239\240\232\247\232\237\224'end
    local e,s=A.get(index)
    if not e or not s then return false,'\204\224\240\248\240\243\242 \237\229 \226\251\225\240\224\237'end
    local side,shop,quote=required_leg(e)
    if not side then return false,'\204\224\240\248\240\243\242 \243\230\229 \231\224\226\229\240\248\184\237'end
    if reason=='shop' then
        if not valid_shop(shop)then return false,'\205\238\236\229\240 \235\224\226\234\232 \237\229\232\231\226\229\241\242\229\237'end
        if not M.mark_shop_missing(shop,30)then return false,'\205\229 \243\228\224\235\238\241\252 \238\242\236\229\242\232\242\252 \235\224\226\234\243'end
        block_related(shop,nil,'shop_missing','manual')
    else
        ensure()[quote]={at=now(),reason='item_missing',sid=s.sid}
        block_related(shop,quote,'item_missing','manual')
    end
    changed()
    A.next(1)
    return true
end
function A.restore_unavailable(index)
    local e=A.get(index)
    if not e then return false,'\205\229\242 \236\224\240\248\240\243\242\224'end
    if not e.unavailable_reason then return A.skip(index,false)end
    local reason=e.unavailable_reason
    local shop=e.unavailable_side=='sell'and e.seller_shop or e.buyer_shop
    local quote=e.unavailable_side=='sell'and e.seller_quote or e.buyer_quote
    if reason=='shop_missing' or reason=='owner_changed' then
        if M.restore_shop and valid_shop(shop) then M.restore_shop(shop) end
    end
    if quote then ensure()[quote]=nil end
    e.unavailable_reason=nil;e.unavailable_at=nil;e.unavailable_side=nil
    e.unavailable_source=nil;e.skipped=false
    changed();return true
end
-- Server's response to our own /findilavka, not arbitrary chat, is authoritative.
local former_game=M.mark_shop_missing_from_game
if type(former_game)=='function' then
    M.mark_shop_missing_from_game=function(shop,timestamp)
        local ok=former_game(shop,timestamp)
        if ok and block_related(shop,nil,'shop_missing','game')>0 then changed()end
        return ok
    end
end
-- A stable, numbered, owner-identified shop observed in game may prove that
-- the old owner no longer runs this shop; missing ITEM still needs manual review.
function A.observe_live_shop()
    local live=DSP.live and DSP.live.shop
    if not live or not live.scan_complete or tonumber(live.server)~=sid()
        or not valid_shop(live.num) or tostring(live.owner or'')==''then return false end
    local s=A.active()
    if not s or s.sid~=sid()then return false end
    local ts=tonumber(live.items_updated)or 0
    if ts<=0 or now()-ts>90 then return false end
    local blocked=0
    for _,e in ipairs(s.routes)do
        local side,shop=required_leg(e)
        local owner=side=='sell'and e.seller_owner or e.buyer_owner
        if side and tostring(shop)==tostring(live.num)
            and owner~='?' and not text_eq(owner,live.owner)
            and not e.unavailable_reason then
            e.unavailable_reason='owner_changed';e.unavailable_source='game'
            e.unavailable_at=now();e.unavailable_side=side;e.skipped=true;blocked=blocked+1
        end
    end
    if blocked>0 then changed()end
    return blocked>0
end
local previous_review=A.review_market
function A.review_market(...)
    local t=now()
    if t-(A._last_availability_check or 0)>=2 then
        A._last_availability_check=t
        A.observe_live_shop()
    end
    return previous_review(...)
end
return true

      end
      _v287_availability()

      local function _v287_agent_window()
-- Compact floating assistant for an entire arbitrage session (not one route).
-- Controls never send trades; all execution acknowledgement is explicit.
local A=DSP.arb_agent
local M=DSP.market
local U=DSP.ui
local V=DSP.ui22
local function cp(v)return DSP.utf8(tostring(v or''))end
local function btn(label,id,w,h)
    return imgui.Button(cp(label)..'##arb_agent_'..id,imgui.ImVec2(w or -1,h or 34))
end
local function text(s)imgui.Text(cp(s))end
local function muted(s)imgui.TextDisabled(cp(s))end
local function good(s)imgui.TextColored(DSP.theme.col('good',1),cp(s))end
local function bad(s)imgui.TextColored(DSP.theme.col('bad',1),cp(s))end
local function fmt(n)return DSP.money(tonumber(n)or 0)end
local function notify(msg)
    A.ui_message=tostring(msg or'')
    if DSP.flog then DSP.flog('ARB AGENT: '..A.ui_message)end
end
local function selected(s)
    local i=math.min(math.max(1,tonumber(s.focus)or 1),math.max(1,#s.routes))
    return s.routes[i],i
end
local function flag(e)
    if e.unavailable_reason=='shop_missing' then return '\205\197\210 \203\192\194\202\200' end
    if e.unavailable_reason=='item_missing' then return '\205\197\210 \207\208\197\196\204\197\210\192' end
    if e.unavailable_reason=='owner_changed' then return '\209\204\197\205\192 \194\203\192\196\197\203\220\214\192' end
    if e.skipped then return '\207\208\206\207\211\217\197\205\206' end
    if e.sold==e.qty then return '\199\192\194\197\208\216\197\205\206' end
    if e.bought==0 then return '\202\211\207\200\210\220' end
    if e.bought<e.qty then return '\196\206\202\211\207\200\210\220' end
    return '\209\196\192\210\220'
end
local function geometry(sw,sh)
    local p=DSP.settings.arb_agent_window or{}
    local maxw=math.max(220,sw-16)
    local maxh=math.max(180,sh-16)
    local w=DSP.clamp(tonumber(p.w)or math.min(360,maxw),math.min(280,maxw),maxw)
    local h=DSP.clamp(tonumber(p.h)or math.min(440,maxh),math.min(280,maxh),maxh)
    return {w=w,h=h,x=DSP.clamp(tonumber(p.x)or(sw-w-10),0,math.max(0,sw-w)),
        y=DSP.clamp(tonumber(p.y)or math.max(8,sh*.16),0,math.max(0,sh-h))}
end
local function save_geometry(g,dx,dy,dw,dh,io)
    local sw,sh=io.DisplaySize.x,io.DisplaySize.y
    local x=DSP.clamp(g.x+(dx or 0),0,math.max(0,sw-g.w))
    local y=DSP.clamp(g.y+(dy or 0),0,math.max(0,sh-g.h))
    local w=DSP.clamp(g.w+(dw or 0),math.min(280,sw-16),sw-x)
    local h=DSP.clamp(g.h+(dh or 0),math.min(280,sh-16),sh-y)
    DSP.settings.arb_agent_window={x=x,y=y,w=w,h=h}
    if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
end
local function header(s,g,io)
    local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
    if btn('\192\208\193\200\210\208\192\198 / MOVE','drag',math.max(65,g.w-119),32)then end
    if imgui.IsItemActive()and io.MouseDelta then
        local d=io.MouseDelta
        if d.x~=0 or d.y~=0 then save_geometry(g,d.x,d.y,0,0,io)end
    end
    imgui.SameLine(0,4)
    if btn(A.queue_expanded and '-' or '+','queue_toggle',33,32)then
        A.queue_expanded=not A.queue_expanded
    end
    imgui.SameLine(0,4)
    if btn('X','close',34,32)then A.show(false)end
end
local function summary(s)
    local st=A.stats()
    good('\209\228\229\235\238\234: '..st.done..' / '..st.routes..'  |  \194 \240\224\225\238\242\229: '..st.pending)
    text('\202\243\239\235\229\237\238: '..st.bought..'  |  \209\228\224\237\238: '..st.sold)
    good('\207\240\232\225\251\235\252 ~ '..fmt(st.profit_estimate))
    muted('\208\224\241\247\184\242 \239\238 \246\229\237\224\236 \239\235\224\237\224, \237\229 \239\238\228\242\226\229\240\230\228\184\237\237\224\255 \234\224\241\241\224')
    local updated=M.state and M.state.updated or 0
    muted('API: '..(M.freshness and M.freshness()or'\237\229\242 \228\224\237\237\251\245')..' | \238\225\231\238\240 \234\224\230\228\251\229 60 \241')
end
local function queue(s)
    local total=#s.routes
    if total==0 then muted('\204\224\240\248\240\243\242\238\226 \239\238\234\224 \237\229\242');return end
    A.queue_page=math.max(1,math.min(tonumber(A.queue_page)or 1,math.ceil(total/5)))
    local pages=math.ceil(total/5)
    muted('\194\241\229 \236\224\240\248\240\243\242\251, \226\234\235\254\247\224\255 \231\224\226\229\240\248\184\237\237\251\229: '..total)
    local first=(A.queue_page-1)*5+1
    for i=first,math.min(total,first+4)do
        local e=s.routes[i]
        local label=(i==s.focus and '* 'or'')..tostring(i)..'. '..e.name..
            ' | '..flag(e)..' '..e.sold..'/'..e.qty
        if btn(label,'route_'..i,-1,30)then A.focus(i);A.qty_key=nil end
    end
    if pages>1 then
        if btn('<','queue_prev',52,28)then A.queue_page=math.max(1,A.queue_page-1)end
        imgui.SameLine(0,5)
        muted('\209\242\240\224\237\232\246\224 '..A.queue_page..'/'..pages)
        imgui.SameLine(0,5)
        if btn('>','queue_next',52,28)then A.queue_page=math.min(pages,A.queue_page+1)end
    end
end
-- Normal ImGui input is used intentionally: unavailable native exotic widgets
-- must not make the floating assistant impossible to close.
function A.draw()
    local s=A.active()
    if not s then A.show(false);return end
    if A.review_market then A.review_market()end
    local io=imgui.GetIO()
    local g=geometry(io.DisplaySize.x,io.DisplaySize.y)
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    local colors=DSP.theme.push_window()
    imgui.SetNextWindowBgAlpha(.90)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(7,6))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,5))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,6)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoResize+imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoScrollbar
    if imgui.Begin('##palatka_arbitrage_agent',nil,flags)then
        if imgui.SetWindowFontScale then
            imgui.SetWindowFontScale(1)
            local fs=imgui.GetFontSize()
            imgui.SetWindowFontScale(math.min(1.15,15/math.max(1,fs)))
        end
        header(s,g,io)
        imgui.Separator()
        if imgui.BeginChild('##arb_agent_scroll',imgui.ImVec2(0,-40),false)then
            summary(s)
            imgui.Separator()
            if A.queue_expanded then
                queue(s)
                if not A.end_confirm then
                    if btn('\199\224\226\229\240\248\232\242\252 \241\229\241\241\232\254','end_session',-1,28)then A.end_confirm=true end
                else
                    bad('\199\224\226\229\240\248\232\242\252 \242\229\234\243\249\243\254 \241\229\241\241\232\254? \200\241\242\238\240\232\255 \238\241\242\224\237\229\242\241\255.')
                    if btn('\196\224, \231\224\226\229\240\248\232\242\252','end_yes',-1,30)then
                        A.stop();A.end_confirm=false
                    end
                    if btn('\206\242\236\229\237\224','end_cancel',-1,28)then A.end_confirm=false end
                end
                imgui.Separator()
            end
            local e,index=selected(s)
            if e then
                text('\204\192\208\216\208\211\210 '..index..' / '..#s.routes..' | '..flag(e))
                text(V.fit(e.name,math.max(100,imgui.GetContentRegionAvail().x-8)))
                muted('\207\235\224\237: '..e.qty..' \248\242. | \238\230\232\228\224\237\232\229 ~ '..fmt(e.proposed_profit))
                muted('\202\243\239\235\229\237\238 '..e.bought..' / '..e.qty..' | \207\240\238\228\224\237\238 '..e.sold..' / '..e.qty)
                -- Confirming each step updates the local offer ledger, never cash history.
                if e.skipped then
                    if e.unavailable_reason then
                        bad('\200\241\234\235\254\247\229\237\238: '..flag(e)..' ('..tostring(e.unavailable_source or '\240\243\247\237\224\255')..')')
                        if e.bought>e.sold then bad('\206\241\242\224\235\232\241\252 \234\243\239\235\229\237\237\251\229 \242\238\226\224\240\251: '..(e.bought-e.sold)..' \248\242.') end
                    end
                    if btn('\194\229\240\237\243\242\252 \236\224\240\248\240\243\242','restore',-1)then
                        if e.unavailable_reason then A.restore_unavailable(index)
                        else A.skip(index,false)end
                    end
                else
                    local side=e.bought<e.qty and'buy'or'sell'
                    local remaining=side=='buy'and(e.qty-e.bought)or(e.bought-e.sold)
                    if remaining>0 then
                        local shop=side=='buy'and e.seller_shop or e.buyer_shop
                        local owner=side=='buy'and e.seller_owner or e.buyer_owner
                        local unit=side=='buy'and e.buy_price or e.sell_price
                        text(side=='buy'and'\202\211\207\200\210\220' or'\209\196\192\210\220')
                        text('\203\224\226\234\224 #'..shop..' | '..owner)
                        text('x'..remaining..' | '..fmt(unit)..'/\248\242.')
                        if btn('\205\224\233\242\232 \235\224\226\234\243 #'..shop,'target',-1)then
                            if not M.mark_shop(shop)then notify('\204\229\242\234\224 \237\229\228\238\241\242\243\239\237\224')end
                        end
                        if btn('\205\229\242 \235\224\226\234\232','missing_shop',-1,32)then
                            local ok,why=A.mark_unavailable(index,'shop')
                            if ok then A.qty_key=nil;notify('\203\224\226\234\224 #'..shop..' \232\241\234\235\254\247\229\237\224 \232\231 \239\235\224\237\238\226')
                            else notify(tostring(why))end
                        end
                        if btn('\205\229\242 \239\240\229\228\236\229\242\224 / \237\229\242 \241\234\243\239\234\232','missing_item',-1,32)then
                            local ok,why=A.mark_unavailable(index,'item')
                            if ok then A.qty_key=nil;notify('\207\240\229\228\235\238\230\229\237\232\229 \232\241\234\235\254\247\229\237\238 \228\238 \237\238\226\238\233 \239\240\238\226\229\240\234\232')
                            else notify(tostring(why))end
                        end
                        local input_key=e.id..':'..side
                        if A.qty_key~=input_key then A.qty_key=input_key;A.qty_field=imgui.new.int(remaining)end
                        muted('\207\238\228\242\226\229\240\228\232\242\252 \234\238\235\232\247\229\241\242\226\238:')
                        imgui.SetNextItemWidth(math.min(160,imgui.GetContentRegionAvail().x))
                        imgui.InputInt('##arb_agent_qty',A.qty_field,1,10)
                        if btn(side=='buy'and'\202\211\207\203\197\205\206' or'\207\208\206\196\192\205\206','confirm',-1,39)then
                            local ok,why=A.confirm(index,side,A.qty_field[0])
                            if ok then A.qty_key=nil;notify('\207\238\228\242\226\229\240\230\228\229\237\238: '..e.name)
                            else notify(tostring(why))end
                        end
                        local hint=A.hint
                        if hint and hint.route_id==e.id and hint.side==side then
                            muted('\207\238\245\238\230\232\233 \247\229\234: '..hint.qty..' \248\242. (\237\229 \224\226\242\238\231\224\247\184\242)')
                            if btn('\207\238\228\242\226\229\240\228\232\242\252 \247\229\234','accept_receipt',-1)then
                                local ok,why=A.confirm(index,side,hint.qty)
                                if ok then A.qty_key=nil;notify('\215\229\234 \239\238\228\242\226\229\240\230\228\184\237')
                                else notify(tostring(why))end
                            end
                        end
                    else good('\204\224\240\248\240\243\242 \226\251\239\238\235\237\229\237')end
                end
            else
                muted('\204\224\240\248\240\243\242\251 \239\238\255\226\255\242\241\255 \239\238\241\235\229 \241\234\224\237\232\240\238\226\224\237\232\255 \240\251\237\234\224')
            end
        end
        imgui.EndChild()
        if A.save_error then bad('\199\224\239\232\241\252 \237\229 \241\238\245\240\224\237\229\237\224: '..tostring(A.save_error))end
        if A.ui_message then muted(V.fit(A.ui_message,math.max(80,g.w-32)))end
        if btn('<','previous',47,30)then A.next(-1);A.qty_key=nil end
        imgui.SameLine(0,5)
        if btn('>','next',47,30)then A.next(1);A.qty_key=nil end
        imgui.SameLine(0,5)
        local e,i=selected(s)
        if e and btn('\207\240\238\239\243\241\242\232\242\252','skip',100,30)then A.skip(i,true);A.next(1);A.qty_key=nil end
        imgui.SameLine(0,5)
        if btn('\204\229\237\254','main',65,30)then
            if U and U.set_open then U.set_open(true)end
            if V and V.set_screen then V.set_screen('arbitrage')end
        end
        -- Bottom-right corner belongs to resize, not to gameplay.
        imgui.SetCursorPos(imgui.ImVec2(g.w-44,g.h-34))
        btn('//','size',30,27)
        if imgui.IsItemActive()and io.MouseDelta then
            local d=io.MouseDelta
            if d.x~=0 or d.y~=0 then save_geometry(g,0,0,d.x,d.y,io)end
        end
    end
    imgui.End()
    imgui.PopStyleVar(3)
    if colors and colors>0 then imgui.PopStyleColor(colors)end
end
return true

      end
      _v287_agent_window()

      if DSP.mobile and DSP.mobile.defer_save then
        DSP.mobile.defer_save()
      elseif DSP.save_settings then
        pcall(DSP.save_settings)
      end
    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka 2.8.7 restore UI / agent: '..tostring(err))end
      return false
    end
    DSP._v287_installed=true
    DSP.version='2.8.7'
    if DSP.flog then DSP.flog('Palatka v2.8.7 original UI restored; arbitration checks ready')end
    return true
  end
  -- v2.8.8: universal opt-in command queue in original Palatka.
  local function install_v288()
    if not install_v287()then return false end
    if DSP._v288_installed then DSP.version='2.8.8';return true end
    local ok,err=pcall(function()
      local function _v288_promo_model()
-- Universal promotion scheduler. Built on Palatka's existing settings and
-- game connection; never bypasses server chat cooldowns or auto-posts by default.
local P=DSP.promo
P.MIN_INTERVAL=60
P.MAX_SESSION=12
P.MAX_TEMPLATES=32
P.MAX_STEP_BYTES=200
P.running=P.running==true
P.cursor=P.cursor or 1
P.next_at=P.next_at or 0
P.cycle_count=P.cycle_count or 0
P.pause_reason=nil
local function num(n,lo,hi)
    n=tonumber(n)
    if n and n==n and n%1==0 then return math.max(lo,math.min(hi,math.floor(n)))end
end
local function persist()
    if DSP.save_settings then return DSP.save_settings()~=false end
    if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
    return true
end
local function settings()
    local s=P.settings()
    if s.continuous==nil then s.continuous=false end
    if s.resume_on_login==nil then s.resume_on_login=false end
    if s.enabled==nil then s.enabled=false end
    s.start_delay=num(s.start_delay,10,120)or 20
    return s
end
local function online()
    if not sampSendChat then return false end
    if sampIsSampAvailable and not sampIsSampAvailable()then return false end
    if sampIsLocalPlayerSpawned and not sampIsLocalPlayerSpawned()then return false end
    return true
end
local function trim(s)return tostring(s or ''):match('^%s*(.-)%s*$')end
function P.validate(text)
    if type(text)~='string' or #text==0 or #text>1500 then
        return false,'\194\226\229\228\232\242\229 \234\238\236\224\237\228\243 \232\235\232 \242\229\234\241\242 (\228\238 1500 \225\224\233\242)'end
    if text:find('[%z\1-\8\11\12\14-\31]')then
        return false,'\211\239\240\224\226\235\255\254\249\232\229 \241\232\236\226\238\235\251 \231\224\239\240\229\249\229\237\251'end
    local n=0
    for _,line in ipairs(P.lines(text))do
        n=n+1
        if n>12 then return false,'\205\229 \225\238\235\229\229 12 \234\238\236\224\237\228 \226 \238\228\237\238\236 \241\242\224\240\238\236 \248\224\225\235\238\237\229'end
        if #line>P.MAX_STEP_BYTES then return false,'\196\235\232\237\224 \241\242\240\238\234\232 \225\238\235\229\229 200 \225\224\233\242'end
        -- This scheduler sends chat commands only; no arbitrary raw packets.
        if not line:match('^/[%w_]+[%s%S]*$') then
            return false,'\209\242\240\238\234\224 \228\238\235\230\237\224 \237\224\247\232\237\224\242\252\241\255 \241 /\234\238\236\224\237\228\251'end
    end
    return n>0,n==0 and '\207\243\241\242\238\233 \248\224\225\235\238\237' or nil
end
local function normalize_item(name,text,interval,auto)
    local ok,err=P.validate(text);if not ok then return nil,err end
    local item={name=trim(name):sub(1,48),text=trim(text),
        interval=num(interval,P.MIN_INTERVAL,3600)or 180,auto=auto~=false,
        last_sent=0,line_index=0}
    if item.name==''then item.name='\209\242\240\238\234\224'end
    return item
end
function P.add(name,text,interval)
    local s=settings()
    if #s.templates>=P.MAX_TEMPLATES then return false,'\203\232\236\232\242 32 \241\242\240\238\234'end
    local item,err=normalize_item(name,text,interval,true);if not item then return false,err end
    s.templates[#s.templates+1]=item
    if not persist()then table.remove(s.templates);return false,'\205\224\241\242\240\238\233\234\232 \237\229 \241\238\245\240\224\237\229\237\251'end
    return true
end
function P.update(index,name,text,interval)
    local s=settings();local old=s.templates[index]
    if not old then return false,'\209\242\240\238\234\224 \237\229 \237\224\233\228\229\237\224'end
    local new,err=normalize_item(name,text,interval,old.auto);if not new then return false,err end
    new.last_sent=old.last_sent or 0;new.line_index=old.line_index or 0
    s.templates[index]=new
    if not persist()then s.templates[index]=old;return false,'\205\224\241\242\240\238\233\234\232 \237\229 \241\238\245\240\224\237\229\237\251'end
    return true
end
function P.remove(index)
    local s=settings()
    if not s.templates[index]then return false end
    local old=table.remove(s.templates,index)
    if not persist()then table.insert(s.templates,index,old);return false end
    P.cursor=math.max(1,math.min(P.cursor,#s.templates))
    return true
end
function P.move(index,delta)
    local rows=settings().templates;local next_index=index+delta
    if not rows[index]or not rows[next_index]then return false end
    rows[index],rows[next_index]=rows[next_index],rows[index]
    if not persist()then rows[index],rows[next_index]=rows[next_index],rows[index];return false end
    P.cursor=next_index
    return true
end
function P.set_option(option,value)
    if option~='continuous'and option~='resume_on_login'and option~='start_delay' then
        return false,'\205\229\232\231\226\229\241\242\237\251\233 \239\224\240\224\236\229\242\240'end
    local s=settings();local before=s[option]
    s[option]=option=='start_delay' and (num(value,10,120)or 20)or(value==true)
    if not persist()then s[option]=before;return false,'\205\224\241\242\240\238\233\234\232 \237\229 \241\238\245\240\224\237\229\237\251'end
    return true
end
function P.steps()
    local rows={}
    for idx,t in ipairs(settings().templates)do
        if t.auto then
            for line_no,cmd in ipairs(P.lines(t.text or''))do
                local ok=P.validate(cmd)
                if ok then rows[#rows+1]={index=idx,line=line_no,command=cmd,
                    interval=num(t.interval,P.MIN_INTERVAL,3600)or 180,
                    name=t.name}end
            end
        end
    end
    return rows
end
function P.start(now)
    if #P.steps()==0 then return false,'\196\238\225\224\226\252 \232 \226\234\235\254\247\232 \245\238\242\255 \225\251 \238\228\237\243 \241\242\240\238\234\243'end
    local s=settings()
    if not s.continuous and P.session_count>=P.MAX_SESSION then
        return false,'\196\238\241\242\232\227\237\243\242 \235\232\236\232\242 12 \241\242\240\238\234 \231\224 \241\229\241\241\232\254'
    end
    P.running=true;P.pause_reason=nil;P.last_error=nil
    P.cursor=1
    P.next_at=(now or os.time())+s.start_delay
    P.started=now or os.time();P.was_online=false
    s.enabled=true
    if not persist()then
        P.running=false;s.enabled=false
        return false,'\205\229 \243\228\224\235\238\241\252 \241\238\245\240\224\237\232\242\252 \240\229\230\232\236'
    end
    return true
end
function P.stop()
    P.running=false;P.pause_reason=nil
    settings().enabled=false
    persist()
end
function P.bootstrap(now)
    local s=settings()
    -- Persisted template flags do not implicitly authorize unattended posting.
    P.running=false;P.pause_reason=nil;P.was_online=false
    P.session_count=0;P.cursor=1;P.next_at=0;P.last_sent=0
    if s.resume_on_login and s.enabled and #P.steps()>0 then
        P.running=true
        P.next_at=(now or os.time())+s.start_delay
        P.pause_reason='\206\230\232\228\224\237\232\229 \239\238\228\234\235\254\247\229\237\232\255'
    end
end
function P.send_once(index,at,send,connected)
    at=at or os.time()
    local t=settings().templates[index]
    if not t then return false,'\209\242\240\238\234\224 \237\229 \237\224\233\228\229\237\224'end
    local ok,err=P.validate(t.text);if not ok then return false,err end
    local lines=P.lines(t.text)
    if #lines==0 then return false,'\207\243\241\242\224\255 \241\242\240\238\234\224'end
    if P.last_sent>0 and at-P.last_sent<P.MIN_INTERVAL then
        return false,'\207\224\243\231\224 \228\238 \241\235\229\228\243\254\249\229\233 \238\242\239\240\224\226\234\232'end
    if connected==nil then connected=online()end
    if not connected then return false,'\205\229\242 \239\238\228\234\235\254\247\229\237\232\255 \234 \232\227\240\229'end
    local i=((num(t.line_index,0,1000)or 0)%#lines)+1
    local resolved,why=P.expand(lines[i])
    if not resolved then return false,why end
    if #resolved>P.MAX_STEP_BYTES then return false,'\207\238\241\235\229 \239\238\228\241\242\224\237\238\226\234\232 \242\229\234\241\242 \228\235\232\237\237\229\229 200 \225\224\233\242'end
    local sender=send or sampSendChat
    if type(sender)~='function'then return false,'\206\242\239\240\224\226\234\224 \247\224\242\224 \237\229\228\238\241\242\243\239\237\224'end
    local success,outcome=pcall(sender,resolved)
    if not success or outcome==false then return false,'\206\242\239\240\224\226\234\224 \237\229 \243\228\224\235\224\241\252'end
    P.last_sent=at;P.session_count=P.session_count+1
    t.last_sent=at;t.line_index=i
    P.last_command=resolved;P.last_error=nil
    return true
end
function P.tick(at,send,connected)
    if not P.running then return false end
    local s=settings();at=at or os.time()
    if connected==nil then connected=online()end
    if not connected then
        P.pause_reason='\205\229\242 \241\238\229\228\232\237\229\237\232\255: \238\242\239\240\224\226\234\224 \239\240\232\238\241\242\224\237\238\226\235\229\237\224'
        P.was_online=false
        return false
    end
    if not P.was_online then
        P.was_online=true
        P.next_at=math.max(P.next_at,at+s.start_delay)
        P.pause_reason='\206\230\232\228\224\237\232\229 \239\238\241\235\229 \226\245\238\228\224'
        return false
    end
    local steps=P.steps()
    if #steps==0 then P.running=false;P.pause_reason='\205\229\242 \226\234\235\254\247\184\237\237\251\245 \241\242\240\238\234';return false end
    if not s.continuous and P.session_count>=P.MAX_SESSION then
        P.running=false;P.pause_reason='\203\232\236\232\242 12 \241\238\238\225\249\229\237\232\233 \231\224 \241\229\241\241\232\254'
        s.enabled=false;persist();return false
    end
    if at<(P.next_at or 0)then return false end
    if P.last_sent>0 and at-P.last_sent<P.MIN_INTERVAL then
        P.next_at=P.last_sent+P.MIN_INTERVAL
        return false
    end
    local index=((P.cursor-1)%#steps)+1
    local step=steps[index]
    local ok,why=P.send_once(step.index,at,send,connected)
    if not ok then
        P.last_error=why;P.pause_reason=why
        P.next_at=at+math.max(P.MIN_INTERVAL,step.interval)
        return false
    end
    P.pause_reason=nil
    P.cursor=index%#steps+1
    if P.cursor==1 then P.cycle_count=(P.cycle_count or 0)+1 end
    P.next_at=at+math.max(P.MIN_INTERVAL,step.interval)
    if not s.continuous and P.session_count>=P.MAX_SESSION then
        P.running=false;P.pause_reason='\203\232\236\232\242 \238\242\239\240\224\226\238\234 \232\241\247\229\240\239\224\237'
        s.enabled=false;persist()
    end
    return true
end
-- Preserve Palatka's original background thread; replace only the scheduler.
local previous_install=P.install
function P.install()
    if P.installed then return end
    previous_install()
    P.bootstrap(os.time())
end

-- v2.8.9: a named template owns a list of independently scheduled commands.
-- Previous single-line templates migrate without losing their saved text/order.
local previous_settings=P.settings
local previous_update=P.update
local function ensure_rows(t)
    if type(t.rows)=='table' then return t.rows end
    local rows={}
    for _,line in ipairs(P.lines(t.text or''))do
        rows[#rows+1]={text=line,interval=num(t.interval,60,3600)or 180,auto=true}
    end
    t.rows=rows
    return rows
end
function P.settings()
    local s=previous_settings()
    for _,t in ipairs(s.templates)do ensure_rows(t)end
    return s
end
function P.update(index,name,text,interval)
    local ok,err=previous_update(index,name,text,interval)
    if ok then
        local t=P.settings().templates[index]
        local rows={}
        for _,line in ipairs(P.lines(text or''))do
            rows[#rows+1]={text=line,interval=num(interval,60,3600)or 180,auto=true}
        end
        t.rows=rows
        persist()
    end
    return ok,err
end
function P.save_template(index,name,rows,enabled)
    local s=P.settings()
    if type(name)~='string' or #name<1 or #name>64 then
        return false,'\205\224\231\226\224\237\232\229 \248\224\225\235\238\237\224: 1\15064 \225\224\233\242\224'
    end
    if type(rows)~='table' or #rows==0 or #rows>24 then
        return false,'\196\238\225\224\226\252 \238\242 1 \228\238 24 \241\242\240\238\234'
    end
    if not index and #s.templates>=P.MAX_TEMPLATES then
        return false,'\196\238\241\242\232\227\237\243\242 \235\232\236\232\242 \248\224\225\235\238\237\238\226'
    end
    if index and not s.templates[index]then return false,'\216\224\225\235\238\237 \237\229 \237\224\233\228\229\237'end
    local normalized={}
    local total=0
    for i,row in ipairs(rows)do
        if type(row)~='table' then return false,'\206\248\232\225\234\224 \241\242\240\238\234\232 '..i end
        local cmd=tostring(row.text or''):match('^%s*(.-)%s*$')
        local ok,err=P.validate(cmd)
        if not ok then return false,'\209\242\240\238\234\224 '..i..': '..tostring(err)end
        if #P.lines(cmd)~=1 then return false,'\206\228\237\224 \234\238\236\224\237\228\224 \237\224 \241\242\240\238\234\243'end
        total=total+#cmd
        if total>4800 then return false,'\209\235\232\248\234\238\236 \228\235\232\237\237\251\233 \248\224\225\235\238\237'end
        normalized[i]={text=cmd,interval=num(row.interval,P.MIN_INTERVAL,3600)or 180,
            auto=row.auto~=false}
    end
    local old=index and s.templates[index]or nil
    local t={name=name,text=table.concat((function()
        local lines={}
        for _,r in ipairs(normalized)do lines[#lines+1]=r.text end
        return lines
    end)(),'\n'),rows=normalized,
        interval=normalized[1].interval,auto=enabled~=false,
        last_sent=old and old.last_sent or 0,line_index=old and old.line_index or 0}
    if index then s.templates[index]=t else
        s.templates[#s.templates+1]=t;index=#s.templates
    end
    if not persist()then
        if old then s.templates[index]=old else table.remove(s.templates,index)end
        return false,'\205\229 \243\228\224\235\238\241\252 \241\238\245\240\224\237\232\242\252 \248\224\225\235\238\237'
    end
    return true,index
end
function P.steps()
    local steps={}
    for i,t in ipairs(P.settings().templates)do
        if t.auto~=false then
            for line,row in ipairs(ensure_rows(t))do
                if row.auto~=false and type(row.text)=='string' and P.validate(row.text)then
                    steps[#steps+1]={index=i,line=line,command=row.text,
                        interval=num(row.interval,P.MIN_INTERVAL,3600)or 180,name=t.name}
                end
            end
        end
    end
    return steps
end
function P.send_once(index,at,send,connected)
    at=at or os.time()
    local t=P.settings().templates[index]
    if not t then return false,'\216\224\225\235\238\237 \237\229 \237\224\233\228\229\237'end
    local all=P.steps()
    local target=all[P.cursor or 1]
    if not target or target.index~=index then
        for _,step in ipairs(all)do
            if step.index==index then target=step;break end
        end
    end
    if not target or target.index~=index then return false,'\194 \248\224\225\235\238\237\229 \237\229\242 \226\234\235\254\247\184\237\237\251\245 \241\242\240\238\234'end
    if P.last_sent>0 and at-P.last_sent<P.MIN_INTERVAL then
        return false,'\207\224\243\231\224 \228\238 \241\235\229\228\243\254\249\229\233 \238\242\239\240\224\226\234\232'
    end
    if connected==nil then connected=online()end
    if not connected then return false,'\205\229\242 \239\238\228\234\235\254\247\229\237\232\255 \234 \232\227\240\229'end
    local resolved,err=P.expand(target.command)
    if not resolved then return false,err end
    if #resolved>P.MAX_STEP_BYTES then return false,'\202\238\236\224\237\228\224 \239\240\229\226\251\248\224\229\242 200 \225\224\233\242'end
    local sender=send or sampSendChat
    if type(sender)~='function'then return false,'\205\229\242 \238\242\239\240\224\226\234\232 \247\224\242\224'end
    local ok,response=pcall(sender,resolved)
    if not ok or response==false then return false,'\205\229 \243\228\224\235\238\241\252 \238\242\239\240\224\226\232\242\252 \234\238\236\224\237\228\243'end
    P.last_sent=at;P.session_count=P.session_count+1
    P.last_command=resolved;P.last_error=nil
    t.last_sent=at;t.line_index=target.line
    t.rows[target.line].last_sent=at
    return true
end

return true

      end
      _v288_promo_model()

      local function _v288_promo_ui()
-- Market Helper pattern: template title and editable chat commands in one panel.
local ffi=require('ffi')
local V,M,P=DSP.ui22,DSP.mobile,DSP.promo
local function button(label,id,w,on)return V.button(label,'mhpromo_'..id,w,on)end
local function txt(s)return DSP.utf8(tostring(s or''))end
local function buff(str,n)
    local b=imgui.new.char[n]()
    local raw=DSP.to_u8(tostring(str or''))
    ffi.fill(b,n);ffi.copy(b,raw:sub(1,n-1))
    return b
end
local function open_editor(index)
    local t=P.settings().templates[index]
    local rows={}
    local buffers={}
    for i,r in ipairs(t and t.rows or{})do
        rows[i]={text=r.text,interval=r.interval,auto=r.auto~=false}
        buffers[i]=buff(r.text,512)
    end
    V.mhpromo_edit={index=index,name=buff(t and t.name or'\205\238\226\251\233 \248\224\225\235\238\237',96),
        rows=rows,buffers=buffers,enabled=t==nil or t.auto~=false}
end
local function editor(e)
    V.heading('\207\232\224\240 / \208\229\228\224\234\242\238\240',function()
        if button('\205\224\231\224\228','back',120)then V.mhpromo_edit=nil end
    end,142)
    V.text('\205\224\231\226\224\237\232\229 \248\224\225\235\238\237\224')
    imgui.SetNextItemWidth(-1)
    imgui.InputText('##mhpromo_name',e.name,96)
    V.muted('\202\224\230\228\224\255 \241\242\240\238\234\224 \151 \238\242\228\229\235\252\237\224\255 \232\227\240\238\226\224\255 \234\238\236\224\237\228\224; \238\242\239\240\224\226\235\255\254\242\241\255 \239\238 \238\247\229\240\229\228\232.')
    local rm=nil
    if imgui.BeginChild('##mhpromo_rows',imgui.ImVec2(0,300),true)then
        for i,row in ipairs(e.rows)do
            imgui.PushID(i)
            V.muted('\209\242\240\238\234\224 '..i)
            imgui.SetNextItemWidth(-1)
            if imgui.InputTextWithHint('##line',txt('/vr \210\229\234\241\242 \240\229\234\235\224\236\251'),
                e.buffers[i],512)then
                row.text=DSP.to_cp(ffi.string(e.buffers[i]))
            end
            V.muted('\207\224\243\231\224 \239\238\241\235\229, \241\229\234\243\237\228')
            M.compact_number(row,'interval','mhpromo_delay_'..i,145,60)
            V.inline(4)
            if button(row.auto~=false and '\194\202\203' or '\194\219\202\203','on_'..i,68,row.auto~=false)then
                row.auto=not(row.auto~=false)
            end
            V.inline(4)
            if button('\211\228\224\235\232\242\252','rm_'..i,94)then rm=i end
            imgui.Separator()
            imgui.PopID()
        end
    end
    imgui.EndChild()
    if rm then table.remove(e.rows,rm);table.remove(e.buffers,rm)end
    if button('+ \196\238\225\224\226\232\242\252 \241\242\240\238\234\243','add',225,true)then
        if #e.rows<24 then
            e.rows[#e.rows+1]={text='/vr ',interval=180,auto=true}
            e.buffers[#e.buffers+1]=buff('/vr ',512)
        else e.error='\205\229 \225\238\235\229\229 24 \241\242\240\238\234'end
    end
    V.inline(6)
    if button('\194\241\242\224\226\232\242\252 \235\224\226\234\243','shop',160)then
        local i=#e.rows
        if i>0 then
            local value=ffi.string(e.buffers[i])
            if #value<495 then
                e.buffers[i]=buff(DSP.to_cp(value..' {shop}'),512)
                e.rows[i].text=DSP.to_cp(ffi.string(e.buffers[i]))
            end
        end
    end
    V.muted('\204\224\234\240\238\241 {shop} \226\241\242\224\226\235\255\229\242 \234\235\232\234\224\225\229\235\252\237\243\254 \241\241\251\235\234\243 \237\224 \241\226\238\254 \235\224\226\234\243.')
    if e.error then V.red(e.error)end
    if button('\209\206\213\208\192\205\200\210\220 \216\192\193\203\206\205','save',250,true)then
        local name=DSP.to_cp(ffi.string(e.name)):match('^%s*(.-)%s*$')
        local ok,reason=P.save_template(e.index,name,e.rows,e.enabled)
        if ok then V.mhpromo_edit=nil else e.error=tostring(reason)end
    end
    V.inline(4)
    if button('\206\242\236\229\237\224','cancel',120)then V.mhpromo_edit=nil end
end
function V.promo_screen()
    if V.mhpromo_edit then
        return V.list('mhpromo_editor_scroll',function()editor(V.mhpromo_edit)end)
    end
    local settings=P.settings()
    V.heading('\192\226\242\238\239\232\224\240 \183 Palatka',function()
        if button('+ \216\224\225\235\238\237','new',155,true)then open_editor(nil)end
    end,172)
    if P.running then
        if button('\209\210\206\207','stop',127,true)then P.stop()end
    else
        if button('\207\211\209\202','start',127,true)then
            local ok,why=P.start()
            V.mhpromo_error=ok and nil or tostring(why)
        end
    end
    V.inline(5)
    if button(settings.continuous and '\214\232\234\235: \194\202\203' or '\214\232\234\235: \194\219\202\203',
        'loop',152,settings.continuous)then
        P.set_option('continuous',not settings.continuous)
    end
    V.inline(5)
    if button(settings.resume_on_login and'\207\240\232 \226\245\238\228\229: \194\202\203' or'\207\240\232 \226\245\238\228\229: \194\219\202\203',
        'resume',191,settings.resume_on_login)then
        P.set_option('resume_on_login',not settings.resume_on_login)
    end
    V.muted('\206\242\239\240\224\226\235\229\237\238: '..tostring(P.session_count)..
        (settings.continuous and' | \225\229\231 \235\232\236\232\242\224' or' / 12')..
        ' | '..(P.running and(P.pause_reason or'\240\224\225\238\242\224\229\242')or'\226\251\234\235\254\247\229\237'))
    if V.mhpromo_error then V.red(V.mhpromo_error)end
    V.muted('\216\224\225\235\238\237\251 \241\238 \241\242\240\238\234\224\236\232 /vr, /fam, /gd, /s, /ad \232 \228\240\243\227\232\245 \247\224\242\238\226.')
    V.list_rows('mhpromo_templates',settings.templates,96,function(t,i)
        V.row('mhpromo_t_'..i,96,function(w,x,y)
            V.at(x,y);V.text(V.fit(t.name or'\216\224\225\235\238\237',math.max(80,w-155)))
            V.at(x,y+27);V.muted(#(t.rows or{})..' \241\242\240\238\234')
            V.at(x,y+53)
            if button(t.auto~=false and'\192\226\242\238: \194\202\203' or'\192\226\242\238: \194\219\202\203',
                'enable_'..i,132,t.auto~=false)then
                local was=t.auto;t.auto=not(t.auto~=false)
                if DSP.save_settings and DSP.save_settings()==false then t.auto=was end
            end
            V.at(x+w-143,y+4)
            if button('\200\231\236\229\237\232\242\252','edit_'..i,140)then open_editor(i)end
            V.at(x+w-143,y+52)
            if button('\211\228\224\235\232\242\252','del_'..i,140)then
                V.mhpromo_del=i;V.open_popup('\211\228\224\235\232\242\252 \248\224\225\235\238\237','mhpromo_delete')
            end
        end)
    end)
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    V.popup('\211\228\224\235\232\242\252 \248\224\225\235\238\237','mhpromo_delete',function()
        V.text('\211\228\224\235\232\242\252 \248\224\225\235\238\237 \241\238 \226\241\229\236\232 \241\242\240\238\234\224\236\232?')
        if button('\196\224','yes',105)then
            if P.remove(V.mhpromo_del)then imgui.CloseCurrentPopup()end
        end
        V.inline(5);V.cancel('mhpromo_delete')
    end,{w=415,h=225})
end
return true

      end
      _v288_promo_ui()

      if DSP.promo and DSP.promo.bootstrap then DSP.promo.bootstrap(os.time())end
    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka 2.8.8 universal promo error: '..tostring(err))end
      return false
    end
    DSP._v288_installed=true;DSP.version='2.8.8'
    return true
  end
  -- 2.8.9: properly encoded arbitration labels and named promo template editor.
  local function install_v289()
    if not install_v288() then return false end
    if DSP._v289_installed then DSP.version='2.8.9';return true end
    DSP._v289_installed=true
    DSP.version='2.8.9'
    return true
  end
  -- 2.9.0: Market Helper-inspired inline promo and minimalist trade journal.
  local function install_v290()
    if not install_v289() then return false end
    if DSP._v290_installed then DSP.version='2.9.0';return true end
    local ok,err=pcall(function()
      local function _v290_mh_journal()
-- Market Helper inspired trading log: simple movable translucent feed.
-- Uses original Palatka journal events; never fabricates trade receipts.
local C=DSP.craglog
local function t(s)return DSP.utf8(tostring(s or''))end
local function prefs()
    DSP.settings.craglog=DSP.settings.craglog or{}
    local s=DSP.settings.craglog
    if not s.mh_log_style_v1 then
        s.w,s.h=445,210
        s.mh_log_style_v1=true
    end
    s.mh_log_lines=math.max(3,math.min(16,math.floor(tonumber(s.mh_log_lines)or 8)))
    s.mh_log_alpha=math.max(.12,math.min(.95,tonumber(s.mh_log_alpha)or .58))
    return s
end
local function is_trade(e)
    return e.type=='market'and(e.direction=='sell'or e.direction=='buy')
end
function C.trade_feed(limit)
    limit=math.max(1,math.min(40,math.floor(tonumber(limit)or 8)))
    local rows={}
    -- Oldest to newest ring order; render newest first without touching ledger.
    for _,e in ipairs(C.ring_recent(C.ring_count))do
        if is_trade(e)and(not C.event_visible or C.event_visible(e))then
            rows[#rows+1]=e
        end
    end
    local result={}
    for i=#rows,math.max(1,#rows-limit+1),-1 do result[#result+1]=rows[i]end
    return result
end
function C.trade_feed_line(e)
    local selling=e.direction=='sell'
    local label=selling and'\207\240\238\228\224\230\224' or'\209\234\243\239\234\224'
    local sign=selling and'+' or'-'
    local qty=tonumber(e.qty)or tonumber(e.count)
    local name=tostring(e.item_name or e.item or'?')
    return os.date('%H:%M',tonumber(e.ts)or os.time())..'  '..label..
        ': '..name..(qty and (' x'..math.floor(qty))or'')..
        '  '..sign..DSP.money(e.amount or 0)
end
local function trade_geometry(sw,sh,s)
    local maxw=math.max(180,sw-12)
    local maxh=math.max(90,sh-12)
    local w=math.min(maxw,math.max(math.min(maxw,250),tonumber(s.w)or math.min(445,maxw)))
    local h=math.min(maxh,math.max(math.min(maxh,120),tonumber(s.h)or math.min(210,maxh)))
    local x=math.max(4,math.min(tonumber(s.x)or 18,sw-w-4))
    local y=math.max(4,math.min(tonumber(s.y)or math.max(14,sh*.24),sh-h-4))
    return{x=x,y=y,w=w,h=s.minimized and 33 or h,
        max_x=math.max(4,sw-w-4),max_y=math.max(4,sh-h-4)}
end
function C.draw()
    local s=prefs()
    local io=imgui.GetIO()
    local g=trade_geometry(io.DisplaySize.x,io.DisplaySize.y,s)
    C.active_geometry=g
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.FirstUseEver)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoSavedSettings
    if s.minimized then
        imgui.SetNextWindowSize(imgui.ImVec2(g.w,37),imgui.Cond.Always)
        flags=flags+imgui.WindowFlags.NoResize
    end
    imgui.SetNextWindowBgAlpha(s.mh_log_alpha)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(7,5))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(4,4))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,4)
    if imgui.Begin('##palatka_trade_feed',nil,flags)then
        local avail=imgui.GetContentRegionAvail().x
        if imgui.Button(t('\210\206\208\195\206\194\219\201 \198\211\208\205\192\203')..'##trade_feed_drag',
            imgui.ImVec2(math.max(70,avail-56),26))then end
        if imgui.IsItemActive()and imgui.IsMouseDragging(0)and not s.pinned then
            local d=io.MouseDelta;C.drag(d.x,d.y)
        end
        if not imgui.IsMouseDown(0)then C.end_drag()end
        imgui.SameLine(0,4)
        if imgui.Button((s.minimized and'+'or'-')..'##trade_feed_fold',imgui.ImVec2(24,26))then
            C.set_minimized(not s.minimized)
        end
        imgui.SameLine(0,3)
        if imgui.Button('x##trade_feed_close',imgui.ImVec2(24,26))then
            s.open=false;DSP.save_settings()
        end
        if not s.minimized then
            imgui.Separator()
            if imgui.BeginChild('##trade_feed_lines',imgui.ImVec2(0,-2),false)then
                local entries=C.trade_feed(s.mh_log_lines)
                if #entries==0 then
                    imgui.TextDisabled(t('\207\240\238\228\224\230\232 \232 \241\234\243\239\234\224 \239\238\255\226\255\242\241\255 \231\228\229\241\252 \239\238\241\235\229 \239\238\228\242\226\229\240\230\228\229\237\232\255 \232\227\240\238\233'))
                end
                for _,e in ipairs(entries)do
                    local color=e.direction=='sell'
                        and imgui.ImVec4(.40,.94,.48,1)
                        or imgui.ImVec4(.40,.73,1,1)
                    imgui.TextColored(color,t(C.trade_feed_line(e)))
                end
            end
            imgui.EndChild()
            if imgui.GetWindowSize then
                local p=imgui.GetWindowSize()
                if not s.pinned and
                    (math.abs((s.w or 0)-p.x)>1 or math.abs((s.h or 0)-p.y)>1)then
                    s.w=math.floor(p.x+.5);s.h=math.floor(p.y+.5)
                    C.size_dirty=true
                end
            end
        end
    end
    imgui.End()
    imgui.PopStyleVar(3)
    C.end_resize()
end
return true

      end
      _v290_mh_journal()

      local function _v290_mh_journal_tab()
-- Trade-first journal tab, adapted from Market Helper log list.
-- Original reward/payday detail UI remains reachable if needed.
local V,M,C=DSP.ui22,DSP.mobile,DSP.craglog
local original=V.journal
local function b(label,id,width,on)
    return V.button(label,'tradelog_'..id,width,on)
end
local function line(e)
    if C.trade_feed_line then return C.trade_feed_line(e)end
    return tostring(e.item_name or'')..' '..DSP.money(e.amount or 0)
end
function V.journal()
    if V.trade_full_history and original then
        if b('\210\238\240\227\238\226\251\233 \230\243\240\237\224\235','trade_tab',200,true)then V.trade_full_history=false end
        return original()
    end
    local s=DSP.settings.craglog or{}
    DSP.settings.craglog=s
    V.heading('\210\238\240\227\238\226\251\233 \230\243\240\237\224\235',function()
        if b(s.open and'\209\234\240\251\242\252 \238\234\237\238' or'\207\238\234\224\231\224\242\252 \238\234\237\238','toggle',161,s.open)then
            if C.toggle then C.toggle()end
        end
    end,175)
    V.muted('\210\238\235\252\234\238 \239\238\228\242\226\229\240\230\228\184\237\237\251\229 \239\240\238\228\224\230\232 \232 \239\238\234\243\239\234\232, \225\229\231 \240\224\241\247\184\242\237\251\245 \241\228\229\235\238\234 \224\240\225\232\242\240\224\230\224.')
    if b('\194\241\229','all',88,V.trade_filter=='all' or not V.trade_filter)then V.trade_filter='all'end
    V.inline(5)
    if b('\207\240\238\228\224\230\232','sell',112,V.trade_filter=='sell')then V.trade_filter='sell'end
    V.inline(5)
    if b('\209\234\243\239\234\224','buy',112,V.trade_filter=='buy')then V.trade_filter='buy'end
    V.inline(5)
    if b('\207\238\228\240\238\225\237\224\255 \232\241\242\238\240\232\255','full',183)then V.trade_full_history=true end
    V.muted('\207\235\224\226\224\254\249\232\233 \235\238\227: \239\240\238\231\240\224\247\237\238\241\242\252 '..math.floor((tonumber(s.mh_log_alpha)or .58)*100)..'%')
    for _,pct in ipairs({25,45,60,80})do
        if b(pct..'%','opacity_'..pct,72,math.floor((s.mh_log_alpha or .58)*100)==pct)then
            s.mh_log_alpha=pct/100;DSP.save_settings()
        end
        V.inline(4)
    end
    V.muted('\209\242\240\238\234 \226 \239\235\224\226\224\254\249\229\236 \238\234\237\229: '..tostring(s.mh_log_lines or 8))
    for _,n in ipairs({5,8,12})do
        if b(tostring(n),'lines_'..n,68,(s.mh_log_lines or 8)==n)then
            s.mh_log_lines=n;DSP.save_settings()
        end
        V.inline(4)
    end
    local all=C.trade_feed and C.trade_feed(40)or{}
    local rows={}
    for _,e in ipairs(all)do
        if not V.trade_filter or V.trade_filter=='all' or e.direction==V.trade_filter then
            rows[#rows+1]=e
        end
    end
    if #rows==0 then V.muted('\199\224\239\232\241\229\233 \239\240\238\228\224\230\232 \232 \241\234\243\239\234\232 \239\238\234\224 \237\229\242.')end
    V.list_rows('tradelog_entries',rows,53,function(e,i)
        V.row('trade_'..i,53,function(w,x,y)
            V.at(x,y+2)
            if e.direction=='sell' then V.green(V.fit(line(e),w-8))
            else V.muted(V.fit(line(e),w-8))end
        end)
    end,{footer=function()V.muted('\209\238\225\251\242\232\255 \241\238\245\240\224\237\255\254\242\241\255 \248\242\224\242\237\251\236 \230\243\240\237\224\235\238\236 Palatka.')end})
end
return true

      end
      _v290_mh_journal_tab()

    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka 2.9.0 MH trade journal: '..tostring(err)) end
      return false
    end
    DSP._v290_installed=true
    DSP.version='2.9.0'
    return true
  end
  -- v2.9.1: compact native Palatka agent, MH trade journal and promo templates.
  local function install_v291()
    if not install_v290() then return false end
    if DSP._v291_installed then DSP.version='2.9.1';return true end
    local ok,err=pcall(function()
      local function _v291_promo_options()
-- Market Helper style template controls over Palatka's safe per-command queue.
-- Existing templates remain untouched until the user saves new options.
local P=DSP.promo
if P._mh_options_installed then return true end
P._mh_options_installed=true
local function int(v,min,max)
    v=tonumber(v)
    if not v or v~=v then return nil end
    return math.max(min,math.min(max,math.floor(v)))
end
function P.save_template_options(index,opts)
    local list=P.settings().templates
    local t=list[index]
    if not t then return false,'\216\224\225\235\238\237 \237\229 \237\224\233\228\229\237'end
    opts=opts or{}
    local previous={min=t.interval_min,max=t.interval_max,
        limit=t.auto_limit,random=t.random_line}
    local low=int(opts.interval_min,0,3600)or 0
    local high=int(opts.interval_max,0,3600)or 0
    if low>0 and low<60 then low=60 end
    if high>0 and high<60 then high=60 end
    if high>0 and high<low then high=low end
    t.interval_min=low;t.interval_max=high
    t.auto_limit=int(opts.auto_limit,0,1000)or 0
    t.random_line=opts.random_line==true
    local ok=not DSP.save_settings or DSP.save_settings()~=false
    if not ok then
        t.interval_min=previous.min;t.interval_max=previous.max
        t.auto_limit=previous.limit;t.random_line=previous.random
        return false,'\205\229 \243\228\224\235\238\241\252 \241\238\245\240\224\237\232\242\252 \237\224\241\242\240\238\233\234\232'
    end
    return true
end
local old_steps=P.steps
function P.steps()
    local all=old_steps()
    local result={}
    local random_by_template={}
    for _,step in ipairs(all)do
        local t=P.settings().templates[step.index]
        if not (t and t.random_line)then
            result[#result+1]=step
        elseif not random_by_template[step.index]then
            local options={}
            for _,candidate in ipairs(all)do
                if candidate.index==step.index then options[#options+1]=candidate end
            end
            if #options>0 then
                -- Pick once per cycle, not independently at each rendering/tick call.
                local choose=t._random_index
                if not choose or choose>#options then
                    choose=math.random(1,#options);t._random_index=choose
                end
                result[#result+1]=options[choose]
            end
            random_by_template[step.index]=true
        end
    end
    return result
end
local old_tick=P.tick
function P.tick(at,send,connected)
    local steps=P.steps()
    local i=P.cursor or 1
    local step=#steps>0 and steps[((i-1)%#steps)+1]or nil
    local before=P.session_count or 0
    local ok=old_tick(at,send,connected)
    if not ok or (P.session_count or 0)<=before or not step then return ok end
    local t=P.settings().templates[step.index]
    if not t then return ok end
    if t.random_line then t._random_index=nil end
    t.auto_count=(t.auto_count or 0)+1
    local lo=int(t.interval_min,0,3600)or 0
    local hi=int(t.interval_max,0,3600)or 0
    if lo>0 then
        hi=math.max(lo,hi)
        P.next_at=(at or os.time())+math.random(math.max(60,lo),math.max(60,hi))
    end
    local limit=int(t.auto_limit,0,1000)or 0
    if limit>0 and t.auto_count>=limit then
        t.auto=false;t.auto_count=0
        if DSP.save_settings then DSP.save_settings()end
        P.last_error='\216\224\225\235\238\237 \171'..tostring(t.name or'?')..'\187: \235\232\236\232\242 \226\251\239\238\235\237\229\237'
    end
    return ok
end
return true

      end
      _v291_promo_options()

      local function _v291_promo_ui()
-- Market Helper pattern: template title and editable chat commands in one panel.
local ffi=require('ffi')
local V,M,P=DSP.ui22,DSP.mobile,DSP.promo
if V._promo291_installed then return true end
V._promo291_installed=true
local function button(label,id,w,on)return V.button(label,'mhpromo_'..id,w,on)end
local function txt(s)return DSP.utf8(tostring(s or''))end
local function buff(str,n)
    local b=imgui.new.char[n]()
    local raw=DSP.to_u8(tostring(str or''))
    ffi.fill(b,n);ffi.copy(b,raw:sub(1,n-1))
    return b
end
local function open_editor(index)
    local t=P.settings().templates[index]
    local rows={}
    local buffers={}
    for i,r in ipairs(t and t.rows or{})do
        rows[i]={text=r.text,interval=r.interval,auto=r.auto~=false}
        buffers[i]=buff(r.text,512)
    end
    V.mhpromo_edit={index=index,name=buff(t and t.name or'\205\238\226\251\233 \248\224\225\235\238\237',96),
        rows=rows,buffers=buffers,enabled=t==nil or t.auto~=false,
        interval_min={value=t and t.interval_min or 0},interval_max={value=t and t.interval_max or 0},
        auto_limit={value=t and t.auto_limit or 0},random_line=t and t.random_line==true or false}
end
local function editor(e)
    V.heading('\207\232\224\240 / \208\229\228\224\234\242\238\240',function()
        if button('\205\224\231\224\228','back',120)then V.mhpromo_edit=nil end
    end,142)
    V.text('\205\224\231\226\224\237\232\229 \248\224\225\235\238\237\224')
    imgui.SetNextItemWidth(-1)
    imgui.InputText('##mhpromo_name',e.name,96)
    V.muted('\202\224\230\228\224\255 \241\242\240\238\234\224 \151 \238\242\228\229\235\252\237\224\255 \232\227\240\238\226\224\255 \234\238\236\224\237\228\224; \238\242\239\240\224\226\235\255\254\242\241\255 \239\238 \238\247\229\240\229\228\232.')
    V.muted('\202\224\234 \226 Market Helper: \237\224\231\226\224\237\232\229, \241\242\240\238\234\232 \232 \237\224\241\242\240\238\233\234\232 \238\228\237\238\227\238 \248\224\225\235\238\237\224.')
    local rm=nil
    if imgui.BeginChild('##mhpromo_rows',imgui.ImVec2(0,math.max(135,math.min(290,imgui.GetContentRegionAvail().y-225))),true)then
        for i,row in ipairs(e.rows)do
            imgui.PushID(i)
            V.muted('\209\242\240\238\234\224 '..i)
            imgui.SetNextItemWidth(-1)
            if imgui.InputTextWithHint('##line',txt('/vr \210\229\234\241\242 \240\229\234\235\224\236\251'),
                e.buffers[i],512)then
                row.text=DSP.to_cp(ffi.string(e.buffers[i]))
            end
            V.muted('\207\224\243\231\224 \239\238\241\235\229, \241\229\234\243\237\228')
            M.compact_number(row,'interval','mhpromo_delay_'..i,145,60)
            V.inline(4)
            if button(row.auto~=false and '\194\202\203' or '\194\219\202\203','on_'..i,68,row.auto~=false)then
                row.auto=not(row.auto~=false)
            end
            V.inline(4)
            if button('\211\228\224\235\232\242\252','rm_'..i,94)then rm=i end
            V.inline(4)
            if button('^','up_'..i,42) and i>1 then
                e.rows[i],e.rows[i-1]=e.rows[i-1],e.rows[i]
                e.buffers[i],e.buffers[i-1]=e.buffers[i-1],e.buffers[i]
            end
            V.inline(4)
            if button('v','down_'..i,42) and i<#e.rows then
                e.rows[i],e.rows[i+1]=e.rows[i+1],e.rows[i]
                e.buffers[i],e.buffers[i+1]=e.buffers[i+1],e.buffers[i]
            end
            imgui.Separator()
            imgui.PopID()
        end
    end
    imgui.EndChild()
    if rm then table.remove(e.rows,rm);table.remove(e.buffers,rm)end
    if button('+ \196\238\225\224\226\232\242\252 \241\242\240\238\234\243','add',225,true)then
        if #e.rows<24 then
            e.rows[#e.rows+1]={text='/vr ',interval=180,auto=true}
            e.buffers[#e.buffers+1]=buff('/vr ',512)
        else e.error='\205\229 \225\238\235\229\229 24 \241\242\240\238\234'end
    end
    V.inline(6)
    if button('\194\241\242\224\226\232\242\252 \235\224\226\234\243','shop',160)then
        local i=#e.rows
        if i>0 then
            local value=ffi.string(e.buffers[i])
            if #value<495 then
                e.buffers[i]=buff(DSP.to_cp(value..' {shop}'),512)
                e.rows[i].text=DSP.to_cp(ffi.string(e.buffers[i]))
            end
        end
    end
    V.muted('\204\224\234\240\238\241 {shop} \226\241\242\224\226\235\255\229\242 \234\235\232\234\224\225\229\235\252\237\243\254 \241\241\251\235\234\243 \237\224 \241\226\238\254 \235\224\226\234\243.')
    if button(e.random_line and'\209\235\243\247\224\233\237\224\255 \241\242\240\238\234\224: \194\202\203' or'\209\235\243\247\224\233\237\224\255 \241\242\240\238\234\224: \194\219\202\203',
        'random',235,e.random_line)then e.random_line=not e.random_line end
    V.muted('\200\237\242\229\240\226\224\235 \239\238\226\242\238\240\224: 0 = \232\237\228\232\226\232\228\243\224\235\252\237\251\233 \232\237\242\229\240\226\224\235 \234\224\230\228\238\233 \241\242\240\238\234\232.')
    V.muted('\204\232\237\232\236\243\236 \239\238\226\242\238\240\224, \241\229\234:')
    M.compact_number(e.interval_min,'value','mhpromo_imin',160,0)
    V.inline(6)
    V.muted('\204\224\234\241\232\236\243\236, \241\229\234:')
    M.compact_number(e.interval_max,'value','mhpromo_imax',160,0)
    V.muted('\203\232\236\232\242 \238\242\239\240\224\226\238\234 \248\224\225\235\238\237\224: 0 = \225\229\231 \235\232\236\232\242\224')
    M.compact_number(e.auto_limit,'value','mhpromo_limit',170,0)
    if e.error then V.red(e.error)end
    if button('\209\206\213\208\192\205\200\210\220 \216\192\193\203\206\205','save',250,true)then
        local name=DSP.to_cp(ffi.string(e.name)):match('^%s*(.-)%s*$')
        local ok,reason=P.save_template(e.index,name,e.rows,e.enabled)
        if ok then
            local list=P.settings().templates
            local idx=e.index or #list
            local saved,err=P.save_template_options(idx,{
                interval_min=e.interval_min.value,interval_max=e.interval_max.value,
                auto_limit=e.auto_limit.value,random_line=e.random_line})
            if saved then V.mhpromo_edit=nil else e.error=tostring(err)end
        else e.error=tostring(reason)end
    end
    V.inline(4)
    if button('\206\242\236\229\237\224','cancel',120)then V.mhpromo_edit=nil end
end
function V.promo_screen()
    if V.mhpromo_edit then
        return V.list('mhpromo_editor_scroll',function()editor(V.mhpromo_edit)end,{footer=true})
    end
    local settings=P.settings()
    V.heading('\192\226\242\238\239\232\224\240 \183 Palatka',function()
        if button('+ \216\224\225\235\238\237','new',155,true)then open_editor(nil)end
    end,172)
    if P.running then
        if button('\209\210\206\207','stop',127,true)then P.stop()end
    else
        if button('\207\211\209\202','start',127,true)then
            local ok,why=P.start()
            V.mhpromo_error=ok and nil or tostring(why)
        end
    end
    V.inline(5)
    if button(settings.continuous and '\214\232\234\235: \194\202\203' or '\214\232\234\235: \194\219\202\203',
        'loop',152,settings.continuous)then
        P.set_option('continuous',not settings.continuous)
    end
    V.inline(5)
    if button(settings.resume_on_login and'\207\240\232 \226\245\238\228\229: \194\202\203' or'\207\240\232 \226\245\238\228\229: \194\219\202\203',
        'resume',191,settings.resume_on_login)then
        P.set_option('resume_on_login',not settings.resume_on_login)
    end
    V.muted('\206\242\239\240\224\226\235\229\237\238: '..tostring(P.session_count)..
        (settings.continuous and' | \225\229\231 \235\232\236\232\242\224' or' / 12')..
        ' | '..(P.running and(P.pause_reason or'\240\224\225\238\242\224\229\242')or'\226\251\234\235\254\247\229\237'))
    if V.mhpromo_error then V.red(V.mhpromo_error)end
    V.muted('\216\224\225\235\238\237\251 \241\238 \241\242\240\238\234\224\236\232 /vr, /fam, /gd, /s, /ad \232 \228\240\243\227\232\245 \247\224\242\238\226.')
    V.list_rows('mhpromo_templates',settings.templates,96,function(t,i)
        V.row('mhpromo_t_'..i,96,function(w,x,y)
            V.at(x,y);V.text(V.fit(t.name or'\216\224\225\235\238\237',math.max(80,w-155)))
            V.at(x,y+27);V.muted(#(t.rows or{})..' \241\242\240\238\234')
            V.at(x,y+53)
            if button(t.auto~=false and'\192\226\242\238: \194\202\203' or'\192\226\242\238: \194\219\202\203',
                'enable_'..i,132,t.auto~=false)then
                local was=t.auto;t.auto=not(t.auto~=false)
                if DSP.save_settings and DSP.save_settings()==false then t.auto=was end
            end
            V.at(x+w-143,y+4)
            if button('\200\231\236\229\237\232\242\252','edit_'..i,140)then open_editor(i)end
            V.at(x+w-143,y+52)
            if button('\211\228\224\235\232\242\252','del_'..i,140)then
                V.mhpromo_del=i;V.open_popup('\211\228\224\235\232\242\252 \248\224\225\235\238\237','mhpromo_delete')
            end
        end)
    end)
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    V.popup('\211\228\224\235\232\242\252 \248\224\225\235\238\237','mhpromo_delete',function()
        V.text('\211\228\224\235\232\242\252 \248\224\225\235\238\237 \241\238 \226\241\229\236\232 \241\242\240\238\234\224\236\232?')
        if button('\196\224','yes',105)then
            if P.remove(V.mhpromo_del)then imgui.CloseCurrentPopup()end
        end
        V.inline(5);V.cancel('mhpromo_delete')
    end,{w=415,h=225})
end
return true

      end
      _v291_promo_ui()

      local function _v291_compact_journal()
-- Market Helper-inspired trade log: concise receipts and totals, no loot/stat dashboard.
-- All events originate from Palatka's verified journal; no invented transactions.
local C,V=DSP.craglog,DSP.ui22
if C._trade291_installed then return true end
C._trade291_installed=true
local function u(s)return DSP.utf8(tostring(s or''))end
local function b(s,id,w,active)return V.button(s,'trade291_'..id,w,active,false,38)end
local function money(n)return DSP.money(math.floor(tonumber(n)or 0))end
local function kind(e)
    if e.type=='market' then return e.direction=='sell' and 'sell' or e.direction=='buy' and 'buy'end
    if e.type=='trade' then
        local get,give=tonumber(e.money_get)or 0,tonumber(e.money_give)or 0
        if get>0 and give==0 then return 'sell' end
        if give>0 and get==0 then return 'buy' end
    end
end
local function value(e,k)
    if e.type=='market' then return tonumber(e.amount)or 0 end
    return tonumber(k=='sell' and e.money_get or e.money_give)or 0
end
local function description(e,k)
    if e.type=='market' then return tostring(e.item_name or e.item or'?') end
    local items=k=='sell'and e.items_give or e.items_get
    if type(items)=='table'and #items>0 then
        local parts={}
        for i=1,math.min(2,#items)do
            local it=items[i];parts[#parts+1]=tostring(it.name or'?')..' x'..tostring(it.qty or 1)
        end
        return table.concat(parts,', ')
    end
    return tostring(e.partner or '\210\238\240\227\238\226\224\255 \238\239\229\240\224\246\232\255')
end
function C.trade_rows(period)
    local list={}
    local today=os.date('%d.%m.%Y')
    for _,e in ipairs(C.ring_recent(C.ring_count))do
        local k=kind(e)
        if k and (not C.event_visible or C.event_visible(e)) then
            local when=tonumber(e.ts)or 0
            if period~='today' or os.date('%d.%m.%Y',when)==today then
                list[#list+1]={kind=k,ts=when,name=description(e,k),amount=value(e,k),
                    qty=tonumber(e.qty)or 1,source=e.source or'game'}
            end
        end
    end
    return list
end
function C.trade_totals(rows)
    local summary={sells=0,buys=0,sell_count=0,buy_count=0}
    for _,e in ipairs(rows)do
        if e.kind=='sell'then
            summary.sells=summary.sells+e.amount;summary.sell_count=summary.sell_count+1
        else
            summary.buys=summary.buys+e.amount;summary.buy_count=summary.buy_count+1
        end
    end
    return summary
end
local function stats(t)
    V.green('\207\240\238\228\224\237\238: '..money(t.sells)..' ('..t.sell_count..')')
    V.muted('\202\243\239\235\229\237\238: '..money(t.buys)..' ('..t.buy_count..')')
end
local function show_row(row,compact)
    local tag=row.kind=='sell'and '[+] 'or '[-] '
    local val=(row.kind=='sell'and '+' or '-')..money(row.amount)
    local stamp=os.date(compact and'%H:%M' or'%d.%m %H:%M',row.ts)
    local line=tag..stamp..'  '..row.name..'  '..val
    if compact then line=V.fit(line,math.max(100,imgui.GetContentRegionAvail().x-9))end
    imgui.TextColored(DSP.theme.col(row.kind=='sell'and'good'or'accent',1),u(line))
end
function V.journal()
    V.heading('\198\243\240\237\224\235 \241\228\229\235\238\234',function()
        if b('\204\232\237\232-\238\234\237\238','mini',160)then C.set_minimized(false);DSP.settings.craglog.open=true;DSP.save_settings()end
    end,178)
    V.muted('\207\238\228\242\226\229\240\230\228\184\237\237\251\229 \239\240\238\228\224\230\232 \232 \239\238\234\243\239\234\232. \193\229\231 \237\224\227\240\224\228 \232 \235\232\248\237\229\233 \241\242\224\242\232\241\242\232\234\232.')
    V.journal_trade_period=V.journal_trade_period or'today'
    if b('\209\229\227\238\228\237\255','today',136,V.journal_trade_period=='today')then V.journal_trade_period='today'end
    V.inline(6)
    if b('\194\241\184 \226\240\229\236\255','all',145,V.journal_trade_period=='all')then V.journal_trade_period='all'end
    local rows=C.trade_rows(V.journal_trade_period)
    local totals=C.trade_totals(rows)
    stats(totals)
    local reverse={}
    for i=#rows,1,-1 do reverse[#reverse+1]=rows[i]end
    V.list_rows('simple_trade_'..V.journal_trade_period,reverse,62,function(e,i)
        V.row('trade_'..i,62,function(w,x,y)
            V.at(x,y)
            if e.kind=='sell'then V.green('\207\208\206\196\192\198\192  +'..money(e.amount))
            else V.red('\207\206\202\211\207\202\192  -'..money(e.amount))end
            V.at(x,y+27)
            V.muted(V.fit(os.date('%H:%M',e.ts)..'  '..e.name,w-14))
        end)
    end,{count=#reverse})
end
local function config()
    DSP.settings.craglog=DSP.settings.craglog or{}
    return DSP.settings.craglog
end
-- Existing timestamps and ring persist. Only the mobile presentation changes.
local previous_geometry=C.geometry
function C.geometry(sw,sh)
    local s=config()
    if not s.trade_compact_initialized then
        s.trade_compact_initialized=true
        s.w=math.min(math.max(360,sw*.37),math.max(360,sw-16))
        s.h=math.min(305,math.max(280,sh-16))
    end
    return previous_geometry(sw,sh)
end
function C.draw()
    local io=imgui.GetIO();local s=config();local g=C.geometry(io.DisplaySize.x,io.DisplaySize.y)
    C.active_geometry=g
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    if not C._trade_size_set then imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always);C._trade_size_set=true end
    imgui.SetNextWindowBgAlpha(.78)
    local colors=DSP.theme.push_window()
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,10)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(8,7))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,5))
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse
    if imgui.Begin('##palatka_trade_journal',nil,flags)then
        if V.apply_font then V.apply_font()end
        if b('\209\228\229\235\234\232 \183 \239\229\240\229\236\229\241\242\232\242\252','move',math.max(95,g.w-143))then end
        if not s.pinned and imgui.IsItemActive()and io.MouseDelta then
            C.drag(io.MouseDelta.x,io.MouseDelta.y)
        end
        if not imgui.IsMouseDown(0)then C.end_drag()end
        imgui.SameLine(0,5)
        if b(s.pinned and'P' or'pin','pin',46,s.pinned)then C.set_pinned(not s.pinned)end
        imgui.SameLine(0,5)
        if b('X','close',45)then s.open=false;DSP.save_settings()end
        local filter=s.trade_period or'today'
        local rows=C.trade_rows(filter)
        local total=C.trade_totals(rows)
        if b('\209\229\227\238\228\237\255','today',116,filter=='today')then s.trade_period='today';DSP.save_settings()end
        imgui.SameLine(0,5)
        if b('\194\241\229','all',86,filter=='all')then s.trade_period='all';DSP.save_settings()end
        imgui.Separator()
        if imgui.BeginChild('##trade291_scroll',imgui.ImVec2(0,-60),false)then
            if #rows==0 then V.muted('\207\238\228\242\226\229\240\230\228\184\237\237\251\245 \241\228\229\235\238\234 \239\238\234\224 \237\229\242.')end
            local max=math.min(#rows,60)
            for i=#rows,#rows-max+1,-1 do
                local e=rows[i]
                if e then show_row(e,true)end
            end
        end
        imgui.EndChild()
        imgui.Separator()
        V.green('\207\240\238\228\224\237\238 '..money(total.sells)..' \183 '..total.sell_count)
        V.muted('\202\243\239\235\229\237\238 '..money(total.buys)..' \183 '..total.buy_count)
        C.remember_size(imgui.GetWindowSize().x,imgui.GetWindowSize().y)
    end
    imgui.End()
    if C.end_resize then C.end_resize()end
    imgui.PopStyleVar(3)
    if colors and colors>0 then imgui.PopStyleColor(colors)end
end
return true

      end
      _v291_compact_journal()

      local function _v291_arb_agent_native()
-- Palatka AI arbitration companion: native Carbon controls, compact game-safe panel.
-- All trades remain manually acknowledged; no packet, teleport or server automation.
local A,M,V=DSP.arb_agent,DSP.market,DSP.ui22
local function u(s)return DSP.utf8(tostring(s or ''))end
local function label(s)imgui.Text(u(s))end
local function quiet(s)imgui.TextDisabled(u(s))end
local function green(s)imgui.TextColored(DSP.theme.col('good',1),u(s))end
local function red(s)imgui.TextColored(DSP.theme.col('bad',1),u(s))end
local function b(name,id,w,active) return V.button(name,'agent291_'..id,w,active,false,38)end
local function money(v)return DSP.money(tonumber(v)or 0)end
local function selected(s)
    local index=math.max(1,math.min(tonumber(s.focus)or 1,#s.routes))
    return s.routes[index],index
end
local function status(e)
    if e.unavailable_reason=='shop_missing' then return '\205\229\242 \235\224\226\234\232' end
    if e.unavailable_reason=='item_missing' then return '\205\229\242 \239\240\229\228\236\229\242\224' end
    if e.unavailable_reason=='owner_changed' then return '\209\236\229\237\224 \226\235\224\228\229\235\252\246\224' end
    if e.skipped then return '\207\240\238\239\243\249\229\237\238' end
    if e.sold>=e.qty then return '\199\224\226\229\240\248\229\237\238' end
    if e.bought<e.qty then return '\207\238\234\243\239\234\224' end
    return '\207\240\238\228\224\230\224'
end
local function rect(io)
    DSP.settings.arb_agent_window=DSP.settings.arb_agent_window or{}
    local p=DSP.settings.arb_agent_window
    local sw,sh=io.DisplaySize.x,io.DisplaySize.y
    local w=DSP.clamp(tonumber(p.w)or 440,math.min(305,sw-16),math.max(305,sw-16))
    local h=DSP.clamp(tonumber(p.h)or 390,math.min(250,sh-16),math.max(250,sh-16))
    return {w=w,h=h,x=DSP.clamp(tonumber(p.x)or(sw-w-12),0,math.max(0,sw-w)),
        y=DSP.clamp(tonumber(p.y)or 110,0,math.max(0,sh-h))}
end
local function drag(g,io,resize)
    local d=io.MouseDelta
    if not d or (d.x==0 and d.y==0) then return end
    local w=resize and DSP.clamp(g.w+d.x,math.min(305,io.DisplaySize.x-16),io.DisplaySize.x-g.x)or g.w
    local h=resize and DSP.clamp(g.h+d.y,math.min(250,io.DisplaySize.y-16),io.DisplaySize.y-g.y)or g.h
    local x=resize and g.x or DSP.clamp(g.x+d.x,0,io.DisplaySize.x-w)
    local y=resize and g.y or DSP.clamp(g.y+d.y,0,io.DisplaySize.y-h)
    DSP.settings.arb_agent_window={x=x,y=y,w=w,h=h}
    A._geometry_dirty=true
end
local function notice(msg)A.ui_message=msg end
local function route_queue(s)
    local total=#s.routes
    if total==0 then return end
    local pages=math.max(1,math.ceil(total/4))
    A.queue_page=DSP.clamp(tonumber(A.queue_page)or 1,1,pages)
    quiet('\204\224\240\248\240\243\242\251: '..total..'  |  \209\242\240\224\237\232\246\224 '..A.queue_page..'/'..pages)
    local from=(A.queue_page-1)*4+1
    for i=from,math.min(total,from+3)do
        local e=s.routes[i]
        if b(V.fit(i..'. '..e.name..' \183 '..status(e),math.max(100,imgui.GetContentRegionAvail().x-20)),
            'route_'..i,-1,s.focus==i)then
            A.focus(i);A.qty_key=nil
        end
    end
    if pages>1 then
        if b('\208\224\237\229\229','pageprev',110)then A.queue_page=math.max(1,A.queue_page-1)end
        imgui.SameLine(0,8)
        if b('\196\224\235\229\229','pagenext',110)then A.queue_page=math.min(pages,A.queue_page+1)end
    end
end
local function route_info(e,index,total)
    if not e then quiet('\205\238\226\251\245 \236\224\240\248\240\243\242\238\226 \239\238\234\224 \237\229\242');return end
    quiet('\209\228\229\235\234\224 '..index..' \232\231 '..total..' \183 '..status(e))
    label(V.fit(e.name,math.max(120,imgui.GetContentRegionAvail().x-12)))
    quiet('\207\235\224\237 '..e.qty..' \248\242.  |  \206\230\232\228\224\229\236\224\255 \239\240\232\225\251\235\252 ~ '..money(e.proposed_profit))
    quiet('\202\243\239\235\229\237\238 '..e.bought..' \183 \207\240\238\228\224\237\238 '..e.sold)
    if e.skipped then
        if e.bought>e.sold then red('\210\238\226\224\240\238\226 \237\224 \240\243\234\224\245: '..(e.bought-e.sold)..' \248\242.')end
        if b('\194\229\240\237\243\242\252 \236\224\240\248\240\243\242','restore',-1)then
            if e.unavailable_reason then A.restore_unavailable(index)else A.skip(index,false)end
        end
        return
    end
    if e.sold>=e.qty then green('\209\228\229\235\234\224 \231\224\226\229\240\248\229\237\224');return end
    local buying=e.bought<e.qty
    local side=buying and 'buy' or 'sell'
    local shop=buying and e.seller_shop or e.buyer_shop
    local owner=buying and e.seller_owner or e.buyer_owner
    local price=buying and e.buy_price or e.sell_price
    local remaining=buying and(e.qty-e.bought)or(e.bought-e.sold)
    if remaining<=0 then return end
    green(buying and '\202\243\239\232\242\252' or '\207\240\238\228\224\242\252')
    label('\203\224\226\234\224 #'..shop..' \183 '..tostring(owner or'?'))
    quiet('\206\241\242\224\235\238\241\252 '..remaining..' \248\242.  |  '..money(price)..' / \248\242.')
    if b('\204\229\242\234\224 \237\224 \235\224\226\234\243 #'..shop,'mark',-1)then
        if not M.mark_shop(shop)then notice('\204\229\242\234\224 \237\229\228\238\241\242\243\239\237\224')end
    end
    if b('\205\229\242 \235\224\226\234\232','missing_shop',145)then
        local ok,err=A.mark_unavailable(index,'shop')
        notice(ok and '\203\224\226\234\224 \232\241\234\235\254\247\229\237\224 \232\231 \239\235\224\237\238\226' or tostring(err))
    end
    imgui.SameLine(0,6)
    if b('\205\229\242 \239\240\229\228\236\229\242\224','missing_item',160)then
        local ok,err=A.mark_unavailable(index,'item')
        notice(ok and '\207\240\229\228\235\238\230\229\237\232\229 \232\241\234\235\254\247\229\237\238' or tostring(err))
    end
    local key=e.id..':'..side
    if A.qty_key~=key then A.qty_key=key;A.qty_field=imgui.new.int(remaining)end
    quiet('\207\238\228\242\226\229\240\230\228\229\237\232\229 \234\238\235\232\247\229\241\242\226\224:')
    imgui.SetNextItemWidth(math.min(160,imgui.GetContentRegionAvail().x))
    imgui.InputInt('##agent291_qty',A.qty_field,1,10)
    if b(buying and '\207\238\228\242\226\229\240\228\232\242\252 \239\238\234\243\239\234\243' or '\207\238\228\242\226\229\240\228\232\242\252 \239\240\238\228\224\230\243','confirm',-1,true)then
        local ok,err=A.confirm(index,side,A.qty_field[0])
        if ok then A.qty_key=nil;notice('\202\238\235\232\247\229\241\242\226\238 \231\224\239\232\241\224\237\238')else notice(tostring(err))end
    end
    local hint=A.hint
    if hint and hint.route_id==e.id and hint.side==side then
        quiet('\206\225\237\224\240\243\230\229\237 \239\238\245\238\230\232\233 \247\229\234: '..hint.qty..' \248\242.')
        if b('\207\240\232\237\255\242\252 \228\224\237\237\251\229 \247\229\234\224','receipt',-1)then
            local ok,err=A.confirm(index,side,hint.qty)
            if ok then A.qty_key=nil;notice('\215\229\234 \239\238\228\242\226\229\240\230\228\184\237')else notice(tostring(err))end
        end
    end
end
function A.draw()
    local s=A.active()
    if not s then A.show(false);return end
    if A.review_market then A.review_market()end
    local io=imgui.GetIO()
    local g=rect(io)
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(.94)
    local color_count=DSP.theme.push_window()
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(9,8))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(6,6))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,9)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse
    if imgui.Begin('##palatka_arbitrage_agent',nil,flags)then
        if V.apply_font then V.apply_font()end
        if b('\192\240\225\232\242\240\224\230 \183 \239\229\240\229\236\229\241\242\232\242\252','handle',math.max(100,g.w-112))then end
        if imgui.IsItemActive() and io.MouseDelta then drag(g,io,false)end
        imgui.SameLine(0,5)
        if b(A.queue_expanded and '-' or '+','queue',40)then A.queue_expanded=not A.queue_expanded end
        imgui.SameLine(0,5)
        if b('X','close',43)then A.show(false)end
        local st=A.stats()
        quiet('\199\224\226\229\240\248\229\237\238 '..st.done..'/'..st.routes..' \183 \194 \240\224\225\238\242\229 '..st.pending)
        green('\206\230\232\228\224\229\236\251\233 \240\229\231\243\235\252\242\224\242 ~ '..money(st.profit_estimate))
        imgui.Separator()
        if A.queue_expanded then
            route_queue(s)
            if not A.end_confirm then
                if b('\199\224\234\238\237\247\232\242\252 \241\229\241\241\232\254','end',-1)then A.end_confirm=true end
            else
                red('\199\224\226\229\240\248\232\242\252 \241\229\241\241\232\254?')
                if b('\199\224\226\229\240\248\232\242\252','endyes',140)then A.stop();A.end_confirm=false end
                imgui.SameLine(0,5)
                if b('\206\242\236\229\237\224','endno',130)then A.end_confirm=false end
            end
            imgui.Separator()
        end
        if imgui.BeginChild('##agent291_content',imgui.ImVec2(0,-80),false)then
            local e,i=selected(s)
            route_info(e,i,#s.routes)
        end
        imgui.EndChild()
        if A.ui_message then quiet(V.fit(A.ui_message,math.max(120,g.w-35)))end
        if A.save_error then red('\205\229 \241\238\245\240\224\237\229\237\238: '..tostring(A.save_error))end
        if b('< \207\240\229\228\251\228\243\249\224\255','prev',math.max(105,math.floor((g.w-36)/2)))then A.next(-1);A.qty_key=nil end
        imgui.SameLine(0,6)
        if b('\209\235\229\228\243\254\249\224\255 >','next',math.max(105,math.floor((g.w-36)/2)))then A.next(1);A.qty_key=nil end
        -- Native ImGui drag-resize grip, visually aligned to Palatka corners.
        imgui.SetCursorPos(imgui.ImVec2(g.w-39,g.h-36))
        if b('//','resize',29)then end
        if imgui.IsItemActive()and io.MouseDelta then drag(g,io,true)end
    end
    imgui.End()
    imgui.PopStyleVar(3)
    if color_count and color_count>0 then imgui.PopStyleColor(color_count)end
    if A._geometry_dirty and not imgui.IsMouseDown(0)then
        A._geometry_dirty=false
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
    end
end
return true

      end
      _v291_arb_agent_native()

    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka 2.9.1 modules: '..tostring(err))end
      return false
    end
    DSP._v291_installed=true
    DSP.version='2.9.1'
    if DSP.flog then DSP.flog('Palatka 2.9.1 MH-style trade UI installed')end
    return true
  end
  -- v2.9.2: verify actual loaded UI, independently restore vital screens.
  local function install_v292()
    local parent_ok=install_v291()
    if not parent_ok and DSP.flog then
      DSP.flog('v2.9.2 predecessor failed: repairing core UI directly')
    end
    if DSP._v292_installed then DSP.version='2.9.2';return true end
    local ok,err=pcall(function()
      local function _v292_agent_active()
-- Palatka AI arbitration companion: native Carbon controls, compact game-safe panel.
-- All trades remain manually acknowledged; no packet, teleport or server automation.
local A,M,V=DSP.arb_agent,DSP.market,DSP.ui22
local function u(s)return DSP.utf8(tostring(s or ''))end
local function label(s)imgui.Text(u(s))end
local function quiet(s)imgui.TextDisabled(u(s))end
local function green(s)imgui.TextColored(DSP.theme.col('good',1),u(s))end
local function red(s)imgui.TextColored(DSP.theme.col('bad',1),u(s))end
local function b(name,id,w,active) return V.button(name,'agent291_'..id,w,active,false,38)end
local function money(v)return DSP.money(tonumber(v)or 0)end
local function selected(s)
    local index=math.max(1,math.min(tonumber(s.focus)or 1,#s.routes))
    return s.routes[index],index
end
local function status(e)
    if e.unavailable_reason=='shop_missing' then return '\205\229\242 \235\224\226\234\232' end
    if e.unavailable_reason=='item_missing' then return '\205\229\242 \239\240\229\228\236\229\242\224' end
    if e.unavailable_reason=='owner_changed' then return '\209\236\229\237\224 \226\235\224\228\229\235\252\246\224' end
    if e.skipped then return '\207\240\238\239\243\249\229\237\238' end
    if e.sold>=e.qty then return '\199\224\226\229\240\248\229\237\238' end
    if e.bought<e.qty then return '\207\238\234\243\239\234\224' end
    return '\207\240\238\228\224\230\224'
end
local function rect(io)
    DSP.settings.arb_agent_window=DSP.settings.arb_agent_window or{}
    local p=DSP.settings.arb_agent_window
    local sw,sh=io.DisplaySize.x,io.DisplaySize.y
    local w=DSP.clamp(tonumber(p.w)or 440,math.min(305,sw-16),math.max(305,sw-16))
    local h=DSP.clamp(tonumber(p.h)or 390,math.min(250,sh-16),math.max(250,sh-16))
    return {w=w,h=h,x=DSP.clamp(tonumber(p.x)or(sw-w-12),0,math.max(0,sw-w)),
        y=DSP.clamp(tonumber(p.y)or 110,0,math.max(0,sh-h))}
end
local function drag(g,io,resize)
    local d=io.MouseDelta
    if not d or (d.x==0 and d.y==0) then return end
    local w=resize and DSP.clamp(g.w+d.x,math.min(305,io.DisplaySize.x-16),io.DisplaySize.x-g.x)or g.w
    local h=resize and DSP.clamp(g.h+d.y,math.min(250,io.DisplaySize.y-16),io.DisplaySize.y-g.y)or g.h
    local x=resize and g.x or DSP.clamp(g.x+d.x,0,io.DisplaySize.x-w)
    local y=resize and g.y or DSP.clamp(g.y+d.y,0,io.DisplaySize.y-h)
    DSP.settings.arb_agent_window={x=x,y=y,w=w,h=h}
    A._geometry_dirty=true
end
local function notice(msg)A.ui_message=msg end
local function route_queue(s)
    local total=#s.routes
    if total==0 then return end
    local pages=math.max(1,math.ceil(total/4))
    A.queue_page=DSP.clamp(tonumber(A.queue_page)or 1,1,pages)
    quiet('\204\224\240\248\240\243\242\251: '..total..'  |  \209\242\240\224\237\232\246\224 '..A.queue_page..'/'..pages)
    local from=(A.queue_page-1)*4+1
    for i=from,math.min(total,from+3)do
        local e=s.routes[i]
        if b(V.fit(i..'. '..e.name..' \183 '..status(e),math.max(100,imgui.GetContentRegionAvail().x-20)),
            'route_'..i,-1,s.focus==i)then
            A.focus(i);A.qty_key=nil
        end
    end
    if pages>1 then
        if b('\208\224\237\229\229','pageprev',110)then A.queue_page=math.max(1,A.queue_page-1)end
        imgui.SameLine(0,8)
        if b('\196\224\235\229\229','pagenext',110)then A.queue_page=math.min(pages,A.queue_page+1)end
    end
end
local function route_info(e,index,total)
    if not e then quiet('\205\238\226\251\245 \236\224\240\248\240\243\242\238\226 \239\238\234\224 \237\229\242');return end
    quiet('\209\228\229\235\234\224 '..index..' \232\231 '..total..' \183 '..status(e))
    label(V.fit(e.name,math.max(120,imgui.GetContentRegionAvail().x-12)))
    quiet('\207\235\224\237 '..e.qty..' \248\242.  |  \206\230\232\228\224\229\236\224\255 \239\240\232\225\251\235\252 ~ '..money(e.proposed_profit))
    quiet('\202\243\239\235\229\237\238 '..e.bought..' \183 \207\240\238\228\224\237\238 '..e.sold)
    if e.skipped then
        if e.bought>e.sold then red('\210\238\226\224\240\238\226 \237\224 \240\243\234\224\245: '..(e.bought-e.sold)..' \248\242.')end
        if b('\194\229\240\237\243\242\252 \236\224\240\248\240\243\242','restore',-1)then
            if e.unavailable_reason then A.restore_unavailable(index)else A.skip(index,false)end
        end
        return
    end
    if e.sold>=e.qty then green('\209\228\229\235\234\224 \231\224\226\229\240\248\229\237\224');return end
    local buying=e.bought<e.qty
    local side=buying and 'buy' or 'sell'
    local shop=buying and e.seller_shop or e.buyer_shop
    local owner=buying and e.seller_owner or e.buyer_owner
    local price=buying and e.buy_price or e.sell_price
    local remaining=buying and(e.qty-e.bought)or(e.bought-e.sold)
    if remaining<=0 then return end
    green(buying and '\202\243\239\232\242\252' or '\207\240\238\228\224\242\252')
    label('\203\224\226\234\224 #'..shop..' \183 '..tostring(owner or'?'))
    quiet('\206\241\242\224\235\238\241\252 '..remaining..' \248\242.  |  '..money(price)..' / \248\242.')
    if b('\204\229\242\234\224 \237\224 \235\224\226\234\243 #'..shop,'mark',-1)then
        if not M.mark_shop(shop)then notice('\204\229\242\234\224 \237\229\228\238\241\242\243\239\237\224')end
    end
    if b('\205\229\242 \235\224\226\234\232','missing_shop',145)then
        local ok,err=A.mark_unavailable(index,'shop')
        notice(ok and '\203\224\226\234\224 \232\241\234\235\254\247\229\237\224 \232\231 \239\235\224\237\238\226' or tostring(err))
    end
    imgui.SameLine(0,6)
    if b('\205\229\242 \239\240\229\228\236\229\242\224','missing_item',160)then
        local ok,err=A.mark_unavailable(index,'item')
        notice(ok and '\207\240\229\228\235\238\230\229\237\232\229 \232\241\234\235\254\247\229\237\238' or tostring(err))
    end
    local key=e.id..':'..side
    if A.qty_key~=key then A.qty_key=key;A.qty_field=imgui.new.int(remaining)end
    quiet('\207\238\228\242\226\229\240\230\228\229\237\232\229 \234\238\235\232\247\229\241\242\226\224:')
    imgui.SetNextItemWidth(math.min(160,imgui.GetContentRegionAvail().x))
    imgui.InputInt('##agent291_qty',A.qty_field,1,10)
    if b(buying and '\207\238\228\242\226\229\240\228\232\242\252 \239\238\234\243\239\234\243' or '\207\238\228\242\226\229\240\228\232\242\252 \239\240\238\228\224\230\243','confirm',-1,true)then
        local ok,err=A.confirm(index,side,A.qty_field[0])
        if ok then A.qty_key=nil;notice('\202\238\235\232\247\229\241\242\226\238 \231\224\239\232\241\224\237\238')else notice(tostring(err))end
    end
    local hint=A.hint
    if hint and hint.route_id==e.id and hint.side==side then
        quiet('\206\225\237\224\240\243\230\229\237 \239\238\245\238\230\232\233 \247\229\234: '..hint.qty..' \248\242.')
        if b('\207\240\232\237\255\242\252 \228\224\237\237\251\229 \247\229\234\224','receipt',-1)then
            local ok,err=A.confirm(index,side,hint.qty)
            if ok then A.qty_key=nil;notice('\215\229\234 \239\238\228\242\226\229\240\230\228\184\237')else notice(tostring(err))end
        end
    end
end
function A.draw()
    local s=A.active()
    if not s then A.show(false);return end
    if A.review_market then A.review_market()end
    local io=imgui.GetIO()
    local g=rect(io)
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(.94)
    local color_count=DSP.theme.push_window()
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(9,8))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(6,6))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,9)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse
    if imgui.Begin('##palatka_arbitrage_agent',nil,flags)then
        if V.apply_font then V.apply_font()end
        if b('\192\240\225\232\242\240\224\230 \183 \239\229\240\229\236\229\241\242\232\242\252','handle',math.max(100,g.w-112))then end
        if imgui.IsItemActive() and io.MouseDelta then drag(g,io,false)end
        imgui.SameLine(0,5)
        if b(A.queue_expanded and '-' or '+','queue',40)then A.queue_expanded=not A.queue_expanded end
        imgui.SameLine(0,5)
        if b('X','close',43)then A.show(false)end
        local st=A.stats()
        quiet('\199\224\226\229\240\248\229\237\238 '..st.done..'/'..st.routes..' \183 \194 \240\224\225\238\242\229 '..st.pending)
        green('\206\230\232\228\224\229\236\251\233 \240\229\231\243\235\252\242\224\242 ~ '..money(st.profit_estimate))
        quiet('\204\232\237\232-\224\227\229\237\242 Palatka / \241\225\238\240\234\224 2.9.2')
        imgui.Separator()
        if A.queue_expanded then
            route_queue(s)
            if not A.end_confirm then
                if b('\199\224\234\238\237\247\232\242\252 \241\229\241\241\232\254','end',-1)then A.end_confirm=true end
            else
                red('\199\224\226\229\240\248\232\242\252 \241\229\241\241\232\254?')
                if b('\199\224\226\229\240\248\232\242\252','endyes',140)then A.stop();A.end_confirm=false end
                imgui.SameLine(0,5)
                if b('\206\242\236\229\237\224','endno',130)then A.end_confirm=false end
            end
            imgui.Separator()
        end
        if imgui.BeginChild('##agent291_content',imgui.ImVec2(0,-80),false)then
            local e,i=selected(s)
            route_info(e,i,#s.routes)
        end
        imgui.EndChild()
        if A.ui_message then quiet(V.fit(A.ui_message,math.max(120,g.w-35)))end
        if A.save_error then red('\205\229 \241\238\245\240\224\237\229\237\238: '..tostring(A.save_error))end
        if b('< \207\240\229\228\251\228\243\249\224\255','prev',math.max(105,math.floor((g.w-36)/2)))then A.next(-1);A.qty_key=nil end
        imgui.SameLine(0,6)
        if b('\209\235\229\228\243\254\249\224\255 >','next',math.max(105,math.floor((g.w-36)/2)))then A.next(1);A.qty_key=nil end
        -- Native ImGui drag-resize grip, visually aligned to Palatka corners.
        imgui.SetCursorPos(imgui.ImVec2(g.w-39,g.h-36))
        if b('//','resize',29)then end
        if imgui.IsItemActive()and io.MouseDelta then drag(g,io,true)end
    end
    imgui.End()
    imgui.PopStyleVar(3)
    if color_count and color_count>0 then imgui.PopStyleColor(color_count)end
    if A._geometry_dirty and not imgui.IsMouseDown(0)then
        A._geometry_dirty=false
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
    end
end
return true

      end
      local ok_module,why_module=pcall(_v292_agent_active)
      if not ok_module then error('_v292_agent_active: '..tostring(why_module))end

      local function _v292_journal_active()
-- Market Helper-inspired trade log: concise receipts and totals, no loot/stat dashboard.
-- All events originate from Palatka's verified journal; no invented transactions.
local C,V=DSP.craglog,DSP.ui22
if C._trade292_installed then return true end
C._trade292_installed=true
local function u(s)return DSP.utf8(tostring(s or''))end
local function b(s,id,w,active)return V.button(s,'trade291_'..id,w,active,false,38)end
local function money(n)return DSP.money(math.floor(tonumber(n)or 0))end
local function kind(e)
    if e.type=='market' then return e.direction=='sell' and 'sell' or e.direction=='buy' and 'buy'end
    if e.type=='trade' then
        local get,give=tonumber(e.money_get)or 0,tonumber(e.money_give)or 0
        if get>0 and give==0 then return 'sell' end
        if give>0 and get==0 then return 'buy' end
    end
end
local function value(e,k)
    if e.type=='market' then return tonumber(e.amount)or 0 end
    return tonumber(k=='sell' and e.money_get or e.money_give)or 0
end
local function description(e,k)
    if e.type=='market' then return tostring(e.item_name or e.item or'?') end
    local items=k=='sell'and e.items_give or e.items_get
    if type(items)=='table'and #items>0 then
        local parts={}
        for i=1,math.min(2,#items)do
            local it=items[i];parts[#parts+1]=tostring(it.name or'?')..' x'..tostring(it.qty or 1)
        end
        return table.concat(parts,', ')
    end
    return tostring(e.partner or '\210\238\240\227\238\226\224\255 \238\239\229\240\224\246\232\255')
end
function C.trade_rows(period)
    local list={}
    local today=os.date('%d.%m.%Y')
    for _,e in ipairs(C.ring_recent(C.ring_count))do
        local k=kind(e)
        if k and (not C.event_visible or C.event_visible(e)) then
            local when=tonumber(e.ts)or 0
            if period~='today' or os.date('%d.%m.%Y',when)==today then
                list[#list+1]={kind=k,ts=when,name=description(e,k),amount=value(e,k),
                    qty=tonumber(e.qty)or 1,source=e.source or'game'}
            end
        end
    end
    return list
end
function C.trade_totals(rows)
    local summary={sells=0,buys=0,sell_count=0,buy_count=0}
    for _,e in ipairs(rows)do
        if e.kind=='sell'then
            summary.sells=summary.sells+e.amount;summary.sell_count=summary.sell_count+1
        else
            summary.buys=summary.buys+e.amount;summary.buy_count=summary.buy_count+1
        end
    end
    return summary
end
local function stats(t)
    V.green('\207\240\238\228\224\237\238: '..money(t.sells)..' ('..t.sell_count..')')
    V.muted('\202\243\239\235\229\237\238: '..money(t.buys)..' ('..t.buy_count..')')
end
local function show_row(row,compact)
    local tag=row.kind=='sell'and '[+] 'or '[-] '
    local val=(row.kind=='sell'and '+' or '-')..money(row.amount)
    local stamp=os.date(compact and'%H:%M' or'%d.%m %H:%M',row.ts)
    local line=tag..stamp..'  '..row.name..'  '..val
    if compact then line=V.fit(line,math.max(100,imgui.GetContentRegionAvail().x-9))end
    imgui.TextColored(DSP.theme.col(row.kind=='sell'and'good'or'accent',1),u(line))
end
function V.journal()
    V.heading('\198\243\240\237\224\235 \241\228\229\235\238\234',function()
        if b('\204\232\237\232-\238\234\237\238','mini',160)then C.set_minimized(false);DSP.settings.craglog.open=true;DSP.save_settings()end
    end,178)
    V.muted('\207\238\228\242\226\229\240\230\228\184\237\237\251\229 \239\240\238\228\224\230\232 \232 \239\238\234\243\239\234\232. \193\229\231 \237\224\227\240\224\228 \232 \235\232\248\237\229\233 \241\242\224\242\232\241\242\232\234\232.')
    V.muted('\210\238\240\227\238\226\251\233 \230\243\240\237\224\235 / \241\225\238\240\234\224 2.9.2')
    V.journal_trade_period=V.journal_trade_period or'today'
    if b('\209\229\227\238\228\237\255','today',136,V.journal_trade_period=='today')then V.journal_trade_period='today'end
    V.inline(6)
    if b('\194\241\184 \226\240\229\236\255','all',145,V.journal_trade_period=='all')then V.journal_trade_period='all'end
    local rows=C.trade_rows(V.journal_trade_period)
    local totals=C.trade_totals(rows)
    stats(totals)
    local reverse={}
    for i=#rows,1,-1 do reverse[#reverse+1]=rows[i]end
    V.list_rows('simple_trade_'..V.journal_trade_period,reverse,62,function(e,i)
        V.row('trade_'..i,62,function(w,x,y)
            V.at(x,y)
            if e.kind=='sell'then V.green('\207\208\206\196\192\198\192  +'..money(e.amount))
            else V.red('\207\206\202\211\207\202\192  -'..money(e.amount))end
            V.at(x,y+27)
            V.muted(V.fit(os.date('%H:%M',e.ts)..'  '..e.name,w-14))
        end)
    end,{count=#reverse})
end
local function config()
    DSP.settings.craglog=DSP.settings.craglog or{}
    return DSP.settings.craglog
end
-- Existing timestamps and ring persist. Only the mobile presentation changes.
local previous_geometry=C.geometry
function C.geometry(sw,sh)
    local s=config()
    if not s.trade_compact_initialized then
        s.trade_compact_initialized=true
        s.w=math.min(math.max(360,sw*.37),math.max(360,sw-16))
        s.h=math.min(305,math.max(280,sh-16))
    end
    return previous_geometry(sw,sh)
end
function C.draw()
    local io=imgui.GetIO();local s=config();local g=C.geometry(io.DisplaySize.x,io.DisplaySize.y)
    C.active_geometry=g
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    if not C._trade_size_set then imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always);C._trade_size_set=true end
    imgui.SetNextWindowBgAlpha(.78)
    local colors=DSP.theme.push_window()
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,10)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(8,7))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,5))
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse
    if imgui.Begin('##palatka_trade_journal',nil,flags)then
        if V.apply_font then V.apply_font()end
        if b('\209\228\229\235\234\232 \183 \239\229\240\229\236\229\241\242\232\242\252','move',math.max(95,g.w-143))then end
        if not s.pinned and imgui.IsItemActive()and io.MouseDelta then
            C.drag(io.MouseDelta.x,io.MouseDelta.y)
        end
        if not imgui.IsMouseDown(0)then C.end_drag()end
        imgui.SameLine(0,5)
        if b(s.pinned and'P' or'pin','pin',46,s.pinned)then C.set_pinned(not s.pinned)end
        imgui.SameLine(0,5)
        if b('X','close',45)then s.open=false;DSP.save_settings()end
        local filter=s.trade_period or'today'
        local rows=C.trade_rows(filter)
        local total=C.trade_totals(rows)
        if b('\209\229\227\238\228\237\255','today',116,filter=='today')then s.trade_period='today';DSP.save_settings()end
        imgui.SameLine(0,5)
        if b('\194\241\229','all',86,filter=='all')then s.trade_period='all';DSP.save_settings()end
        imgui.Separator()
        if imgui.BeginChild('##trade291_scroll',imgui.ImVec2(0,-60),false)then
            if #rows==0 then V.muted('\207\238\228\242\226\229\240\230\228\184\237\237\251\245 \241\228\229\235\238\234 \239\238\234\224 \237\229\242.')end
            local max=math.min(#rows,60)
            for i=#rows,#rows-max+1,-1 do
                local e=rows[i]
                if e then show_row(e,true)end
            end
        end
        imgui.EndChild()
        imgui.Separator()
        V.green('\207\240\238\228\224\237\238 '..money(total.sells)..' \183 '..total.sell_count)
        V.muted('\202\243\239\235\229\237\238 '..money(total.buys)..' \183 '..total.buy_count)
        C.remember_size(imgui.GetWindowSize().x,imgui.GetWindowSize().y)
    end
    imgui.End()
    if C.end_resize then C.end_resize()end
    imgui.PopStyleVar(3)
    if colors and colors>0 then imgui.PopStyleColor(colors)end
end
return true

      end
      local ok_module,why_module=pcall(_v292_journal_active)
      if not ok_module then error('_v292_journal_active: '..tostring(why_module))end

      local function _v292_promo_active()
-- Market Helper pattern: template title and editable chat commands in one panel.
local ffi=require('ffi')
local V,M,P=DSP.ui22,DSP.mobile,DSP.promo
if V._promo292_installed then return true end
V._promo292_installed=true
local function button(label,id,w,on)return V.button(label,'mhpromo_'..id,w,on)end
local function txt(s)return DSP.utf8(tostring(s or''))end
local function buff(str,n)
    local b=imgui.new.char[n]()
    local raw=DSP.to_u8(tostring(str or''))
    ffi.fill(b,n);ffi.copy(b,raw:sub(1,n-1))
    return b
end
local function open_editor(index)
    local t=P.settings().templates[index]
    local rows={}
    local buffers={}
    for i,r in ipairs(t and t.rows or{})do
        rows[i]={text=r.text,interval=r.interval,auto=r.auto~=false}
        buffers[i]=buff(r.text,512)
    end
    V.mhpromo_edit={index=index,name=buff(t and t.name or'\205\238\226\251\233 \248\224\225\235\238\237',96),
        rows=rows,buffers=buffers,enabled=t==nil or t.auto~=false,
        interval_min={value=t and t.interval_min or 0},interval_max={value=t and t.interval_max or 0},
        auto_limit={value=t and t.auto_limit or 0},random_line=t and t.random_line==true or false}
end
local function editor(e)
    V.heading('\207\232\224\240 / \208\229\228\224\234\242\238\240',function()
        if button('\205\224\231\224\228','back',120)then V.mhpromo_edit=nil end
    end,142)
    V.text('\205\224\231\226\224\237\232\229 \248\224\225\235\238\237\224')
    imgui.SetNextItemWidth(-1)
    imgui.InputText('##mhpromo_name',e.name,96)
    V.muted('\202\224\230\228\224\255 \241\242\240\238\234\224 \151 \238\242\228\229\235\252\237\224\255 \232\227\240\238\226\224\255 \234\238\236\224\237\228\224; \238\242\239\240\224\226\235\255\254\242\241\255 \239\238 \238\247\229\240\229\228\232.')
    V.muted('\202\224\234 \226 Market Helper: \237\224\231\226\224\237\232\229, \241\242\240\238\234\232 \232 \237\224\241\242\240\238\233\234\232 \238\228\237\238\227\238 \248\224\225\235\238\237\224.')
    local rm=nil
    if imgui.BeginChild('##mhpromo_rows',imgui.ImVec2(0,math.max(135,math.min(290,imgui.GetContentRegionAvail().y-225))),true)then
        for i,row in ipairs(e.rows)do
            imgui.PushID(i)
            V.muted('\209\242\240\238\234\224 '..i)
            imgui.SetNextItemWidth(-1)
            if imgui.InputTextWithHint('##line',txt('/vr \210\229\234\241\242 \240\229\234\235\224\236\251'),
                e.buffers[i],512)then
                row.text=DSP.to_cp(ffi.string(e.buffers[i]))
            end
            V.muted('\207\224\243\231\224 \239\238\241\235\229, \241\229\234\243\237\228')
            M.compact_number(row,'interval','mhpromo_delay_'..i,145,60)
            V.inline(4)
            if button(row.auto~=false and '\194\202\203' or '\194\219\202\203','on_'..i,68,row.auto~=false)then
                row.auto=not(row.auto~=false)
            end
            V.inline(4)
            if button('\211\228\224\235\232\242\252','rm_'..i,94)then rm=i end
            V.inline(4)
            if button('^','up_'..i,42) and i>1 then
                e.rows[i],e.rows[i-1]=e.rows[i-1],e.rows[i]
                e.buffers[i],e.buffers[i-1]=e.buffers[i-1],e.buffers[i]
            end
            V.inline(4)
            if button('v','down_'..i,42) and i<#e.rows then
                e.rows[i],e.rows[i+1]=e.rows[i+1],e.rows[i]
                e.buffers[i],e.buffers[i+1]=e.buffers[i+1],e.buffers[i]
            end
            imgui.Separator()
            imgui.PopID()
        end
    end
    imgui.EndChild()
    if rm then table.remove(e.rows,rm);table.remove(e.buffers,rm)end
    if button('+ \196\238\225\224\226\232\242\252 \241\242\240\238\234\243','add',225,true)then
        if #e.rows<24 then
            e.rows[#e.rows+1]={text='/vr ',interval=180,auto=true}
            e.buffers[#e.buffers+1]=buff('/vr ',512)
        else e.error='\205\229 \225\238\235\229\229 24 \241\242\240\238\234'end
    end
    V.inline(6)
    if button('\194\241\242\224\226\232\242\252 \235\224\226\234\243','shop',160)then
        local i=#e.rows
        if i>0 then
            local value=ffi.string(e.buffers[i])
            if #value<495 then
                e.buffers[i]=buff(DSP.to_cp(value..' {shop}'),512)
                e.rows[i].text=DSP.to_cp(ffi.string(e.buffers[i]))
            end
        end
    end
    V.muted('\204\224\234\240\238\241 {shop} \226\241\242\224\226\235\255\229\242 \234\235\232\234\224\225\229\235\252\237\243\254 \241\241\251\235\234\243 \237\224 \241\226\238\254 \235\224\226\234\243.')
    if button(e.random_line and'\209\235\243\247\224\233\237\224\255 \241\242\240\238\234\224: \194\202\203' or'\209\235\243\247\224\233\237\224\255 \241\242\240\238\234\224: \194\219\202\203',
        'random',235,e.random_line)then e.random_line=not e.random_line end
    V.muted('\200\237\242\229\240\226\224\235 \239\238\226\242\238\240\224: 0 = \232\237\228\232\226\232\228\243\224\235\252\237\251\233 \232\237\242\229\240\226\224\235 \234\224\230\228\238\233 \241\242\240\238\234\232.')
    V.muted('\204\232\237\232\236\243\236 \239\238\226\242\238\240\224, \241\229\234:')
    M.compact_number(e.interval_min,'value','mhpromo_imin',160,0)
    V.inline(6)
    V.muted('\204\224\234\241\232\236\243\236, \241\229\234:')
    M.compact_number(e.interval_max,'value','mhpromo_imax',160,0)
    V.muted('\203\232\236\232\242 \238\242\239\240\224\226\238\234 \248\224\225\235\238\237\224: 0 = \225\229\231 \235\232\236\232\242\224')
    M.compact_number(e.auto_limit,'value','mhpromo_limit',170,0)
    if e.error then V.red(e.error)end
    if button('\209\206\213\208\192\205\200\210\220 \216\192\193\203\206\205','save',250,true)then
        local name=DSP.to_cp(ffi.string(e.name)):match('^%s*(.-)%s*$')
        local ok,reason=P.save_template(e.index,name,e.rows,e.enabled)
        if ok then
            local list=P.settings().templates
            local idx=e.index or #list
            local saved,err=P.save_template_options(idx,{
                interval_min=e.interval_min.value,interval_max=e.interval_max.value,
                auto_limit=e.auto_limit.value,random_line=e.random_line})
            if saved then V.mhpromo_edit=nil else e.error=tostring(err)end
        else e.error=tostring(reason)end
    end
    V.inline(4)
    if button('\206\242\236\229\237\224','cancel',120)then V.mhpromo_edit=nil end
end
function V.promo_screen()
    if V.mhpromo_edit then
        return V.list('mhpromo_editor_scroll',function()editor(V.mhpromo_edit)end,{footer=true})
    end
    local settings=P.settings()
    V.heading('\192\226\242\238\239\232\224\240 \183 Palatka',function()
        if button('+ \216\224\225\235\238\237','new',155,true)then open_editor(nil)end
    end,172)
    if P.running then
        if button('\209\210\206\207','stop',127,true)then P.stop()end
    else
        if button('\207\211\209\202','start',127,true)then
            local ok,why=P.start()
            V.mhpromo_error=ok and nil or tostring(why)
        end
    end
    V.inline(5)
    if button(settings.continuous and '\214\232\234\235: \194\202\203' or '\214\232\234\235: \194\219\202\203',
        'loop',152,settings.continuous)then
        P.set_option('continuous',not settings.continuous)
    end
    V.inline(5)
    if button(settings.resume_on_login and'\207\240\232 \226\245\238\228\229: \194\202\203' or'\207\240\232 \226\245\238\228\229: \194\219\202\203',
        'resume',191,settings.resume_on_login)then
        P.set_option('resume_on_login',not settings.resume_on_login)
    end
    V.muted('\206\242\239\240\224\226\235\229\237\238: '..tostring(P.session_count)..
        (settings.continuous and' | \225\229\231 \235\232\236\232\242\224' or' / 12')..
        ' | '..(P.running and(P.pause_reason or'\240\224\225\238\242\224\229\242')or'\226\251\234\235\254\247\229\237'))
    if V.mhpromo_error then V.red(V.mhpromo_error)end
    V.muted('\216\224\225\235\238\237\251 \241\238 \241\242\240\238\234\224\236\232 /vr, /fam, /gd, /s, /ad \232 \228\240\243\227\232\245 \247\224\242\238\226.')
    V.muted('\200\237\242\229\240\244\229\233\241 Palatka MH / \241\225\238\240\234\224 2.9.2')
    V.list_rows('mhpromo_templates',settings.templates,96,function(t,i)
        V.row('mhpromo_t_'..i,96,function(w,x,y)
            V.at(x,y);V.text(V.fit(t.name or'\216\224\225\235\238\237',math.max(80,w-155)))
            V.at(x,y+27);V.muted(#(t.rows or{})..' \241\242\240\238\234')
            V.at(x,y+53)
            if button(t.auto~=false and'\192\226\242\238: \194\202\203' or'\192\226\242\238: \194\219\202\203',
                'enable_'..i,132,t.auto~=false)then
                local was=t.auto;t.auto=not(t.auto~=false)
                if DSP.save_settings and DSP.save_settings()==false then t.auto=was end
            end
            V.at(x+w-143,y+4)
            if button('\200\231\236\229\237\232\242\252','edit_'..i,140)then open_editor(i)end
            V.at(x+w-143,y+52)
            if button('\211\228\224\235\232\242\252','del_'..i,140)then
                V.mhpromo_del=i;V.open_popup('\211\228\224\235\232\242\252 \248\224\225\235\238\237','mhpromo_delete')
            end
        end)
    end)
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    V.popup('\211\228\224\235\232\242\252 \248\224\225\235\238\237','mhpromo_delete',function()
        V.text('\211\228\224\235\232\242\252 \248\224\225\235\238\237 \241\238 \226\241\229\236\232 \241\242\240\238\234\224\236\232?')
        if button('\196\224','yes',105)then
            if P.remove(V.mhpromo_del)then imgui.CloseCurrentPopup()end
        end
        V.inline(5);V.cancel('mhpromo_delete')
    end,{w=415,h=225})
end
return true

      end
      local ok_module,why_module=pcall(_v292_promo_active)
      if not ok_module then error('_v292_promo_active: '..tostring(why_module))end

      local function _v292_runtime_diagnostic()
-- In-game verification for actively loaded UI modules, not just the version manifest.
local V,C,A,P=DSP.ui22,DSP.craglog,DSP.arb_agent,DSP.promo
DSP.active_ui_build='2.9.2'
DSP.active_ui_refs={
    agent=A and A.draw, journal=C and C.draw,
    journal_tab=V and V.journal, promo=V and V.promo_screen
}
local function report()
    local ref=DSP.active_ui_refs or{}
    local same=V and C and A and P and
        A.draw==ref.agent and C.draw==ref.journal and
        V.journal==ref.journal_tab and V.promo_screen==ref.promo and
        type(P.save_template_options)=='function' and type(C.trade_rows)=='function'
    local line='Palatka runtime '..tostring(DSP.version or '?')..
        ' / UI '..tostring(DSP.active_ui_build or 'none')..
        ' / screens '..(same and'ACTIVE' or'MISMATCH')
    if DSP.flog then DSP.flog('CRDIAG '..line)end
    if sampAddChatMessage then
        sampAddChatMessage('[Palatka] '..line,0x99FFAA)
    end
    return same,line
end
DSP.ui_runtime_check=report
if sampRegisterChatCommand and not DSP._crdiag_registered then
    sampRegisterChatCommand('crdiag',report)
    DSP._crdiag_registered=true
end
if DSP.flog then
    local ok,msg=report()
    DSP.flog('UI modules installed: '..tostring(ok)..' / '..tostring(msg))
end
return true

      end
      local ok_module,why_module=pcall(_v292_runtime_diagnostic)
      if not ok_module then error('_v292_runtime_diagnostic: '..tostring(why_module))end
    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka v2.9.2 screen load error: '..tostring(err))end
      return false
    end
    DSP._v292_installed=true
    DSP.version='2.9.2'
    if DSP.flog then DSP.flog('Palatka v2.9.2 active screens: '..tostring(DSP.active_ui_build))end
    return true
  end
  -- v2.9.3: Market Helper UX, touch scrolling, completed arbitrage flow, journal and statistics.
  local function install_v293()
    local parent_ok=install_v292()
    if not parent_ok then return false end
    if DSP._v293_installed then DSP.version='2.9.3';return true end
    local ok,err=pcall(function()
      local function _v293_promo_mh_options()
-- Market Helper style template controls over Palatka's safe chat-command queue.
-- Manual "send now" can run every enabled row with a configurable inter-line pause.
local P=DSP.promo
if P._mh_options_v293_installed then return true end
P._mh_options_v293_installed=true
P._mh_options_installed=true
P.MIN_INTERVAL=30
local function int(v,min,max)
    v=tonumber(v)
    if not v or v~=v then return nil end
    return math.max(min,math.min(max,math.floor(v)))
end
local function decimal(v,min,max,default)
    v=tonumber(v)
    if not v or v~=v then return default end
    return math.max(min,math.min(max,v))
end
function P.save_template_options(index,opts)
    local list=P.settings().templates
    local t=list[index]
    if not t then return false,'Шаблон не найден'end
    opts=opts or{}
    local previous={min=t.interval_min,max=t.interval_max,
        limit=t.auto_limit,random=t.random_line,waiting=t.waiting}
    local low=int(opts.interval_min,0,3600)or 0
    local high=int(opts.interval_max,0,3600)or 0
    if low>0 and low<P.MIN_INTERVAL then low=P.MIN_INTERVAL end
    if high>0 and high<P.MIN_INTERVAL then high=P.MIN_INTERVAL end
    if high>0 and high<low then high=low end
    t.interval_min=low;t.interval_max=high
    t.auto_limit=int(opts.auto_limit,0,1000)or 0
    t.random_line=opts.random_line==true
    t.waiting=decimal(opts.waiting,.5,10,1.5)
    local ok=not DSP.save_settings or DSP.save_settings()~=false
    if not ok then
        t.interval_min=previous.min;t.interval_max=previous.max
        t.auto_limit=previous.limit;t.random_line=previous.random;t.waiting=previous.waiting
        return false,'Не удалось сохранить настройки'
    end
    return true
end
local old_steps=P.steps
function P.steps()
    local all=old_steps()
    local result={}
    local random_by_template={}
    for _,step in ipairs(all)do
        local t=P.settings().templates[step.index]
        if not(t and t.random_line)then result[#result+1]=step
        elseif not random_by_template[step.index]then
            local options={}
            for _,candidate in ipairs(all)do if candidate.index==step.index then options[#options+1]=candidate end end
            if #options>0 then
                local choose=t._random_index
                if not choose or choose>#options then choose=math.random(1,#options);t._random_index=choose end
                result[#result+1]=options[choose]
            end
            random_by_template[step.index]=true
        end
    end
    return result
end
local old_tick=P.tick
function P.tick(at,send,connected)
    local steps=P.steps()
    local i=P.cursor or 1
    local step=#steps>0 and steps[((i-1)%#steps)+1]or nil
    local before=P.session_count or 0
    local ok=old_tick(at,send,connected)
    if not ok or(P.session_count or 0)<=before or not step then return ok end
    local t=P.settings().templates[step.index]
    if not t then return ok end
    if t.random_line then t._random_index=nil end
    t.auto_count=(t.auto_count or 0)+1
    local lo=int(t.interval_min,0,3600)or 0
    local hi=int(t.interval_max,0,3600)or 0
    if lo>0 then
        hi=math.max(lo,hi)
        P.next_at=(at or os.time())+math.random(math.max(P.MIN_INTERVAL,lo),math.max(P.MIN_INTERVAL,hi))
    end
    local limit=int(t.auto_limit,0,1000)or 0
    if limit>0 and t.auto_count>=limit then
        t.auto=false;t.auto_count=0
        if DSP.save_settings then DSP.save_settings()end
        P.last_error='Шаблон «'..tostring(t.name or'?')..'»: лимит выполнен'
    end
    return ok
end
local function connected_now()
    if not sampSendChat then return false end
    if sampIsSampAvailable and not sampIsSampAvailable()then return false end
    if sampIsLocalPlayerSpawned and not sampIsLocalPlayerSpawned()then return false end
    return true
end
function P.send_template_once(index)
    if P.manual_busy then return false,'Уже отправляется другой шаблон'end
    local t=P.settings().templates[index]
    if not t then return false,'Шаблон не найден'end
    local rows={}
    for _,row in ipairs(t.rows or{})do
        if row.auto~=false and type(row.text)=='string'and P.validate(row.text)then rows[#rows+1]=row end
    end
    if #rows==0 then return false,'Нет включённых строк'end
    if not connected_now()then return false,'Нет подключения к игре'end
    if not(lua_thread and lua_thread.create and wait)then return false,'Игровой поток недоступен'end
    local pause=decimal(t.waiting,.5,10,1.5)
    P.manual_busy=true;P.manual_template=index;P.last_error=nil
    lua_thread.create(function()
        for i,row in ipairs(rows)do
            if not connected_now()then P.last_error='Нет подключения к игре';break end
            local resolved,why=P.expand(row.text)
            if not resolved then P.last_error=tostring(why);break end
            local ok,result=pcall(sampSendChat,resolved)
            if not ok or result==false then P.last_error='Отправка не удалась';break end
            local at=os.time()
            P.last_sent=at;P.session_count=(P.session_count or 0)+1
            t.last_sent=at;row.last_sent=at;P.last_command=resolved
            if i<#rows then wait(math.floor(pause*1000))end
        end
        P.manual_busy=false;P.manual_template=nil
        if DSP.save_settings then DSP.save_settings()end
    end)
    return true
end
function P.queue_left()
    if not P.running then return nil end
    return math.max(0,(tonumber(P.next_at)or 0)-os.time())
end
return true
      end
      local ok_module,why_module=pcall(_v293_promo_mh_options)
      if not ok_module then error('_v293_promo_mh_options: '..tostring(why_module))end
      local function _v293_drop_sales_stats()
-- v2.9.3: reward/drop statistics joined with verified sales and current inventory scan.
local C=DSP.craglog
if C._drop_sales_v293 then return true end
C._drop_sales_v293=true

local old_period_start=C.period_start
function C.period_start(period,now)
    now=now or os.time()
    if period=='hour' then return now-3600 end
    if period=='week' then return now-7*86400 end
    if period=='month' then return now-30*86400 end
    if period=='day' or period=='today' then
        local d=os.date('*t',now);d.hour,d.min,d.sec=0,0,0;return os.time(d)
    end
    if period=='all' then return 0 end
    return old_period_start and old_period_start(period,now) or 0
end

local function positive(v)
    local n=tonumber(v)
    if not n or n~=n or n<=0 then return 0 end
    return math.floor(n)
end
local function split_ench(name,ench)
    name=tostring(name or'?')
    if ench~=nil then return name,tonumber(ench)or 0 end
    local base,n=name:match('^(.-)%s*%(%+(%d+)%)%s*$')
    return base or name,tonumber(n)or 0
end
local function add(map,name,ench,qty,exact)
    qty=positive(qty);if qty<=0 then return end
    name,ench=split_ench(name,ench)
    local key=DSP.item_key(name,ench)
    local row=map[key]
    if not row then
        row={key=key,name=name,ench=ench,qty=0,exact=true}
        map[key]=row
    end
    row.qty=row.qty+qty
    if exact==false then row.exact=false end
end
local function raw_qty(raw)
    local s=tostring(raw or'')
    local q=s:match('[xX]%s*(%d+)') or s:match('(%d+)%s*[xX]')
        or s:match('(%d+)%s*шт')
    q=positive(q)
    return q>0 and q or nil
end
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
      end
      local ok_module,why_module=pcall(_v293_drop_sales_stats)
      if not ok_module then error('_v293_drop_sales_stats: '..tostring(why_module))end
      local function _v293_touch_scroll()
-- v2.9.3 touch scrolling override. Keeps legacy CP1251 UI modules byte-identical.
local M,V=DSP.mobile,DSP.ui22
if not M or not V then return true end
M._touch_scroll_states=M._touch_scroll_states or {}
function M.touch_scroll(io,screen)
    if not imgui.IsWindowHovered or not imgui.GetScrollY or not imgui.SetScrollY then return end
    screen=tostring(screen or 'default')
    local st=M._touch_scroll_states[screen]
    if not st then st={velocity=0,travel=0,was_down=false};M._touch_scroll_states[screen]=st end
    local held=false
    if io and io.MouseDown then
        local ok,value=pcall(function()return io.MouseDown[0]end)
        held=ok and value and true or false
    end
    local flags=0
    pcall(function() flags=(imgui.HoveredFlags and imgui.HoveredFlags.ChildWindows) or 0 end)
    local hovered=false
    local ok_hover=pcall(function() hovered=imgui.IsWindowHovered(flags) end)
    if not ok_hover then pcall(function() hovered=imgui.IsWindowHovered() end) end
    local max=imgui.GetScrollMaxY and imgui.GetScrollMaxY()or 1000000
    local current=imgui.GetScrollY()or 0
    local dy=io and io.MouseDelta and(io.MouseDelta.y or 0)or 0
    local dx=io and io.MouseDelta and(io.MouseDelta.x or 0)or 0
    if held then
        if not st.was_down then st.travel=0;st.velocity=0 end
        st.was_down=true
        if not hovered or(io and io.WantTextInput)then st.velocity=0;return end
        st.travel=st.travel+math.abs(dy)+math.abs(dx)
        local active=false
        pcall(function() active=imgui.IsAnyItemActive() and true or false end)
        if active and(st.travel<8 or math.abs(dy)<math.abs(dx)*1.20)then return end
        if math.abs(dy)>.01 then
            local step=-dy
            imgui.SetScrollY(DSP.clamp(current+step,0,max))
            st.velocity=st.velocity*.35+step*.65
        end
        return
    end
    if st.was_down then st.was_down=false;st.travel=0 end
    if math.abs(st.velocity)>.08 then
        local y=DSP.clamp(current+st.velocity,0,max)
        imgui.SetScrollY(y)
        if y<=0 or y>=max then st.velocity=0
        else
            local dt=io and tonumber(io.DeltaTime)or(1/60)
            st.velocity=st.velocity*math.pow(.86,math.max(.25,dt*60))
        end
    else st.velocity=0 end
end
function V.list(key,draw,options)
    V.track_touch(imgui.GetIO())
    local o=options or{};local footer=o.footer~=false
    local avail=imgui.GetContentRegionAvail()
    local reserved=footer and(o.footer_height or 42)or 0
    local max_height=math.max(30,avail.y-reserved)
    local h=o.height and o.height>0 and math.min(o.height,max_height)or max_height
    local s=V.scrolls[key]or{pending=0,y=0};V.scrolls[key]=s;s.height=h
    if imgui.BeginChild('##v22_list_'..key,imgui.ImVec2(0,h),false,imgui.WindowFlags.NoScrollbar)then
        V.apply_font()
        if s.reset then imgui.SetScrollY(0);s.reset=false end
        if(s.pending or 0)~=0 then
            imgui.SetScrollY(DSP.clamp((imgui.GetScrollY()or 0)+s.pending,0,imgui.GetScrollMaxY()or 0));s.pending=0
        end
        s.y=imgui.GetScrollY()or 0
        local ok,err=xpcall(function()draw(imgui.GetContentRegionAvail().x,h,s.y)end,debug.traceback)
        if not ok then imgui.EndChild();error(err,0)end
        M.touch_scroll(imgui.GetIO(),'v293_'..key)
    end
    imgui.EndChild()
    if footer then
        if o.toolbar then imgui.Separator();o.toolbar(key)
        elseif o.scroll_buttons==true then
            imgui.Separator();V.scroll_buttons(key)
            if type(o.footer)=='function'then V.inline();o.footer()
            elseif o.count then V.inline();V.muted(tostring(o.count)..' записей')end
        elseif type(o.footer)=='function'then imgui.Separator();o.footer()
        elseif o.count then imgui.Separator();V.muted(tostring(o.count)..' записей')end
    end
end
return true
      end
      local ok_module,why_module=pcall(_v293_touch_scroll)
      if not ok_module then error('_v293_touch_scroll: '..tostring(why_module))end
      local function _v293_arbitrage_ui()
-- One item per row. Details are a real modal, allocations use raw offer IDs.
local V,M=DSP.ui21,DSP.mobile
V.arb_tab='sell';V.arb_revision=0;V.arb_sort='az'
local function b(s,id,w,on)return V.button(s,'arb_'..id,w,on)end
local function offerkey(o)return DSP.market.offer_key(o)end
function V.arb_group(groups)
    for _,g in ipairs(groups or{})do if g.key==V.arb_item then return g end end
end
local function choose_all(g)
    V.arb_sellers={};V.arb_buyers={}
    for _,o in ipairs(g.sellers)do V.arb_sellers[offerkey(o)]=true end
    for _,o in ipairs(g.buyers)do V.arb_buyers[offerkey(o)]=true end
    V.arb_revision=V.arb_revision+1
end
-- Unlike "select all", the auto-plan is an action: it selects offers actually
-- used by the allocator and immediately opens its route and financial result.
local function best_plan(g)
    local p=DSP.market.plan_offers(g,nil,nil,{
        extra=V.arb_extra_enabled and V.arb_extra and V.arb_extra.value or 0})
    if p.qty<=0 then
        V.arb_best_error='Нет выгодного маршрута при текущих фильтрах'
        return
    end
    V.arb_sellers={};V.arb_buyers={}
    for _,r in ipairs(p.routes)do
        V.arb_sellers[offerkey(r.sell_offer)]=true
        V.arb_buyers[offerkey(r.buy_offer)]=true
    end
    V.arb_best_error=nil
    V.arb_revision=V.arb_revision+1
    V.arb_route=true
end
function V.arb_plan(g)
    local f=DSP.settings.arb_filters or{}
    local sig=table.concat({tostring(g),V.arb_revision,DSP.settings.tax_bp or 200,
        f.budget or 0,f.min_profit or 0,f.min_roi or 0,f.max_age or 300,
        f.max_qty or 0,f.safety_pct or 0,f.tax_bp or 'global',
        f.min_unit_profit or 0,f.max_buy_price or 0,f.min_stock or 0,f.shop_mode or 0,
        tostring(f.allow_partial~=false),tostring(f.include_unknown~=false),
        V.arb_extra_enabled and(V.arb_extra and V.arb_extra.value or 0)or 0,
        DSP.market.missing_revision or 0,DSP.arb_agent and DSP.arb_agent.revision or 0},'|')
    if os.time()>=(V.arb_plan_expiry or 0)then V.cache.arb_plan=nil end
    return V.memo('arb_plan',sig,function()
        local now,until_ts=os.time(),math.huge
        local age=tonumber(f.max_age)or 300
        for _,offers in ipairs({g.sellers,g.buyers})do for _,o in ipairs(offers)do
            local ts=tonumber(o.ts)or 0
            if age>0 and ts>0 and ts+age+1>now then until_ts=math.min(until_ts,ts+age+1)end
        end end
        V.arb_plan_expiry=until_ts
        local p=DSP.market.plan_offers(g,V.arb_sellers or{},V.arb_buyers or{},
            {extra=V.arb_extra_enabled and V.arb_extra.value or 0})
        return p
    end)
end
local function offer_row(o,i)
    local selected=V.arb_tab=='sell'and V.arb_sellers or V.arb_buyers
    local key=offerkey(o);local checked=selected and selected[key]
    local missing=DSP.market.is_shop_missing and DSP.market.is_shop_missing(o.shop,os.time(),o.ts)
    V.row('arb_offer_'..V.arb_tab..i,100,function(w,x,y)
        local right=math.max(155,w-170)
        V.at(x,y+1);V.text(V.fit('#'..tostring(o.shop)..' · '..tostring(o.owner or'?'),right-8))
        local count=DSP.market.format_units(o.qty)
        local row=V.arb_detail_group and V.arb_detail_group.row
        local live_qty=DSP.market.live_offer_quantity(row,V.arb_tab,o)
        local status=o.qty_source=='game' and 'проверено: игра' or
            o.qty_source=='manual' and 'проверено вручную' or 'API, не подтверждено'
        V.at(x,y+26);V.muted(V.fit(count..' шт. · '..status..
            (live_qty and (' · Игра: '..DSP.market.format_units(live_qty)) or ''),right-8))
        V.at(x,y+52);V.text(V.fit(DSP.money(o.price)..'/шт. · '..DSP.market.offer_freshness(o.ts),right-8))
        if missing then
            V.at(x,y+76);V.red('Лавка недоступна: исключена из плана')
        elseif o.qty==1 and not o.verified_at then
            V.at(x,y+76);V.muted(V.fit('Внимание: 1 может быть количеством слотов',right-8))
        end
        V.at(x+right,y+1)
        if not missing and b(checked and 'Снять выбор' or 'Выбрать','select_'..i,160,checked)then
            selected[key]=not checked or nil;V.arb_revision=V.arb_revision+1
        end
        V.at(x+right,y+49)
        if b('Уточнить','verify_'..V.arb_tab..i,80,false)then
            V.arb_verify={offer=o,side=V.arb_tab,source=live_qty and 'game' or 'manual'}
            V.arb_verify_value={qty=live_qty or tonumber(o.qty) or 0}
        end
        V.inline(4)
        if b(missing and 'Вернуть' or 'Нет лавки','gone_'..V.arb_tab..i,82,missing)then
            if missing then DSP.market.restore_shop(o.shop) else DSP.market.mark_shop_missing(o.shop,30)end
            V.arb_revision=V.arb_revision+1;V.arb_route=false;V.cache.arb_plan=nil;M.defer_save()
        end
    end)
end
local function route_rows(p)
    return function(r,i)
        V.row('route_'..i,100,function(w,x,y)
            V.text(V.fit('КУПИТЬ '..r.tradable_qty..' шт. у лавки #'..tostring(r.sell_offer.shop)..' · '..DSP.money(r.p_buy)..'/шт.',w))
            V.at(x,y+26);V.text(V.fit('ПРОДАТЬ скупщику #'..tostring(r.buy_offer.shop)..' · '..DSP.money(r.p_sell)..'/шт.',w))
            V.at(x,y+52)
            if b('К продавцу','route_sell_'..i,140)then DSP.market.mark_shop(r.sell_offer.shop)end
            V.inline();if b('К скупщику','route_buy_'..i,144)then DSP.market.mark_shop(r.buy_offer.shop)end
            V.inline();V.green('~ +'..DSP.money(r.net_profit))
            if r.same_shop then
                V.at(x,y+78);V.red('Одна лавка: возможность обратной сделки проверьте в игре')
            end
        end)
    end
end
local function finance(p,compact)
    -- Planned, not executed. Display each money component explicitly.
    V.muted('Расчёт по заявкам API, не совершённая сделка')
    V.text('Закупка: -'..DSP.money(p.cost or 0))
    V.text('Продажа, до комиссии: +'..DSP.money(p.gross or 0))
    V.muted('Комиссия (принятая): -'..DSP.money(p.fee or 0))
    V.muted('Поступления после комиссии: '..DSP.money(p.revenue or 0))
    if (p.extra or 0)>0 then V.muted('Доп. расходы: -'..DSP.money(p.extra))end
    local result='ОЖИДАЕМАЯ ПРИБЫЛЬ: '..DSP.money(p.profit or 0)
    if (p.profit or 0)>=0 then V.green(result)else V.red(result)end
end

local function details(g)
    local p=V.arb_plan(g)
    local compact=imgui.GetContentRegionAvail().y<400
    V.arb_extra=V.arb_extra or{value=0}
    local function extra_control()
        if b(V.arb_extra_enabled and 'x Расходы' or '+ Расходы','extra',136,V.arb_extra_enabled)then V.arb_extra_enabled=not V.arb_extra_enabled end
        if V.arb_extra_enabled then V.inline();M.compact_number(V.arb_extra,'value','arb_extra',130,0)end
    end
    V.text(V.fit(g.name,imgui.GetContentRegionAvail().x-(compact and 290 or 0)))
    if compact then V.inline();extra_control()end
    V.muted('Продают '..(g.row.sell.qty or g.supply)..' · Скупают '..(g.row.buy.qty or g.demand)..' · План '..p.qty..' шт.')
    local changed=V.arb_snapshot~=tostring(DSP.market.state.sid)..'/'..tostring(DSP.market.state.version)
    if not compact then V.muted(V.fit('Снимок '..os.date('%H:%M:%S',V.arb_snapshot_time or os.time())..
        (changed and ' · есть новые данные, откройте заново'or ' · API, наличие проверьте в игре'),imgui.GetContentRegionAvail().x))end
    finance(p,compact)
    local f=DSP.settings.arb_filters or {}
    if not compact then V.muted('План условный: доступность не забронирована. Запас спроса: '
        ..tostring(f.safety_pct or 0)..'%; обновите и проверьте скупку перед закупкой.')end
    if V.arb_verify and V.arb_verify_value then
        local vr=V.arb_verify
        V.muted(V.fit('Фактически проверено в игре: #'..tostring(vr.offer.shop)..' · '..tostring(vr.side=='buy' and 'скупает' or 'продаёт'),imgui.GetContentRegionAvail().x))
        M.compact_number(V.arb_verify_value,'qty','arb_verify_qty',130,0)
        V.inline();if b('Применить','verify_save',112)then
            local game_now=DSP.market.live_offer_quantity(g.row,vr.side,vr.offer)
            local source=vr.source=='game' and game_now==V.arb_verify_value.qty and 'game' or 'manual'
            local ok,err=DSP.market.confirm_offer_quantity(g.row,vr.side,vr.offer,V.arb_verify_value.qty,source)
            if ok then
                V.arb_verify=nil;V.arb_verify_value=nil
                V.arb_revision=V.arb_revision+1;V.arb_route=false
                V.arb_snapshot=tostring(DSP.market.state.sid)..'/'..tostring(DSP.market.state.version)
            else V.arb_best_error=tostring(err)end
        end
        V.inline();if b('Отмена','verify_cancel',98)then V.arb_verify=nil;V.arb_verify_value=nil end
        if V.arb_best_error then V.red(V.fit(V.arb_best_error,imgui.GetContentRegionAvail().x))end
        return
    end
    if V.arb_route then
        if b('< Предложения','back_offers',170)then V.arb_route=false end
        V.inline()
        if DSP.arb_agent and b('В МИНИ-АГЕНТ','route_to_agent',176,true)then
            local ok,why=DSP.arb_agent.add_plan(p)
            if ok then
                DSP.arb_agent.show(true)
                imgui.CloseCurrentPopup()
            else DSP.notify('Агент: '..tostring(why))end
        end
        V.list_rows('arb_routes_'..g.key,p.routes,100,route_rows(p),{footer=function()
            if p.profit>=0 then V.green(DSP.money(p.profit)..' чистой прибыли')
            else V.red(DSP.money(p.profit)..' итогового убытка')end
        end})
        return
    end
    local tw=imgui.GetContentRegionAvail().x
    if b('Продают · купить '..#g.sellers,'sell',tw*.23,V.arb_tab=='sell')then V.arb_tab='sell'end
    V.inline();if b('Скупают · продать '..#g.buyers,'buy',tw*.23,V.arb_tab=='buy')then V.arb_tab='buy'end
    V.inline();if b('Лучший план >','best',tw*.27)then best_plan(g)end
    V.inline();if b('Сброс','none',-1)then V.arb_sellers={};V.arb_buyers={};V.arb_revision=V.arb_revision+1 end
    if not compact then extra_control()end
    if V.arb_best_error then V.red(V.arb_best_error)end
    local offers=V.arb_tab=='sell'and g.sellers or g.buyers
    V.list_rows('arb_'..g.key..'_'..V.arb_tab,offers,100,offer_row,{footer=function()
        if b('Маршрут >','route',142,true)then V.arb_route=true end
        V.inline();if b('Закрыть','close_details',116)then imgui.CloseCurrentPopup()end
    end})
end
function V.arbitrage()
    local st=DSP.market.state
    local compact_h=imgui.GetContentRegionAvail().y<340
    V.text('Арбитраж');V.inline();V.muted('Снимок: '..DSP.market.freshness())
    if DSP.arb_agent then
        V.inline()
        if b(DSP.arb_agent.active()and'МИНИ-АГЕНТ >'or'НАЧАТЬ СЕССИЮ','session_start',190,true)then
            local ok,why
            if DSP.arb_agent.active()then DSP.arb_agent.show(true);ok=true
            else ok,why=DSP.arb_agent.start_market()end
            if not ok then DSP.notify('Агент арбитража: '..tostring(why))end
        end
        local st_agent=DSP.arb_agent.stats()
        if st_agent.routes>0 then V.muted('Сессия: '..st_agent.done..'/'..st_agent.routes..' маршрутов')end
    end
    V.inline();if b(st.status=='loading' and 'Загрузка...' or 'Обновить','refresh',120)then DSP.market.pull(st.sid)end
    V.arb_source=V.arb_source or 'api'
    local source_api_w=compact_h and 88 or 116
    local source_local_w=compact_h and 132 or 175
    if b('API','source_api',source_api_w,V.arb_source=='api')then
        V.arb_source='api';V.reset_list('arb_main')
    end
    V.inline(5,source_local_w)
    if b('МОИ СКАНЫ','source_local',source_local_w,V.arb_source=='local')then
        V.arb_source='local';V.reset_list('local_arb_items')
    end
    if compact_h and V.arb_source=='api' then
        V.inline(5,132)
        if b(V.arb_sort=='az' and 'А-Я' or 'Прибыль','sort_compact',132,V.arb_sort~='az')then
            V.arb_sort=V.arb_sort=='az' and 'profit' or 'az'
            V.reset_list('arb_main')
        end
        V.inline(5,108)
        if b('Фильтры','filters_compact',108,V.arb_filters)then
            V.arb_filters=true;V.open_popup('Фильтры арбитража','arb_filters')
        end
    end
    if V.arb_source=='local' then
        if V.local_arbitrage_view then V.local_arbitrage_view() end
        return
    end
    if st.error then
        local delay=(tonumber(st.next_auto_retry) or 0)-os.time()
        V.red(V.fit('API: '..tostring(st.error)..(delay>0 and (' · авто-повтор через '..delay..'с')or ''),
            imgui.GetContentRegionAvail().x))
    end
    local af=DSP.settings.arb_filters or {}
    if not compact_h then
        V.muted(V.fit('Фильтры: '..(tonumber(af.max_age)==0 and 'без ограничения времени' or
            (tostring(math.floor((tonumber(af.max_age)or 600)/60))..' мин'))..
            ' · ROI от '..tostring(af.min_roi or 0)..'% · резерв '..tostring(af.safety_pct or 0)..
            '% · комиссия '..tostring((tonumber(af.tax_bp) or DSP.settings.tax_bp or 200)/100)..'%',
            imgui.GetContentRegionAvail().x))
    end
    local query,edited=V.search('arb','Поиск предмета',-1)
    if edited then V.reset_list('arb_main')end
    if not compact_h then
        if b(V.arb_sort=='az' and 'А-Я' or 'Прибыль: больше','sort',143,V.arb_sort=='az')then
            V.arb_sort=V.arb_sort=='az' and 'profit' or 'az'
            V.reset_list('arb_main')
        end
        V.inline()
        if b('Фильтры','filters',120,V.arb_filters)then
            V.arb_filters=true;V.open_popup('Фильтры арбитража','arb_filters')
        end
    end
    -- Direct game observation does not require the external API to refresh.
    local live=DSP.market.live_shop_spreads and DSP.market.live_shop_spreads() or {}
    if #live>0 then
        V.green('НАЙДЕНО В ОТКРЫТОЙ ЛАВКЕ: '..tostring(#live))
        V.list_rows('arb_live_shop',live,86,function(deal,i)
            V.row('arb_live_row_'..i,86,function(w,x,y)
                V.at(x,y+2);V.text(V.fit(deal.name..' · лавка #'..tostring(deal.shop),w))
                V.at(x,y+27);V.muted(V.fit('Купить '..DSP.money(deal.buy_price)..' / сдать '..DSP.money(deal.sell_price),w))
                V.at(x,y+52);V.green(V.fit('~ +'..DSP.money(deal.profit_unit)..'/шт. после комиссии · '..
                    (deal.verified_quantity and ('до '..tostring(deal.quantity)..' шт.') or 'количество неизвестно'),w))
            end)
        end,{height=math.min(180,math.max(90,imgui.GetContentRegionAvail().y*.30)),footer=false})
    end
    local groups,status
    if DSP.market.arbitrage_grouped_ui then groups,status=DSP.market.arbitrage_grouped_ui()else groups=DSP.market.arbitrage_grouped()end
    if status=='loading'then V.muted('Расчёт рынка...')elseif status=='error'then V.red('Ошибка расчёта. См. журнал')end
    local sig=tostring(groups)..'|'..DSP.lower(query)..'|'..tostring(V.arb_sort)
    local filtered=V.memo('arb_rows',sig,function()
        local out={};local q=DSP.lower(query)
        for _,g in ipairs(groups)do if q==''or DSP.lower(g.name):find(q,1,true)then out[#out+1]=g end end
        -- Cached per market snapshot, filter and sort mode; never sort every render frame.
        table.sort(out,function(a,b)
            if V.arb_sort=='profit' and a.profit~=b.profit then return a.profit>b.profit end
            local an,bn=DSP.lower(a.name),DSP.lower(b.name)
            if an~=bn then return an<bn end
            return tostring(a.key)<tostring(b.key)
        end)
        return out
    end)
    if st.status=='cache' then V.red(V.fit('Сеть недоступна: расчёт по сохранённому снимку, наличие не подтверждено',imgui.GetContentRegionAvail().x))end
    if status~='loading' and #groups==0 and DSP.market.arbitrage_visibility then
        local d=DSP.market.arbitrage_visibility()
        if d.pairs>0 then
            V.muted(V.fit('В API есть '..d.pairs..' ценовых разрывов (в одной лавке: '..d.same_shop..
                '), но фильтр свежести/объёма/комиссии исключил маршруты.',imgui.GetContentRegionAvail().x))
        end
    end
    if #filtered==0 and status~='loading' then
        local age=tonumber((DSP.settings.arb_filters or{}).max_age)or 300
        local reason=#groups>0 and 'По запросу ничего не найдено' or
            (#(st.rows or{})==0 and 'Нет рынка: нажмите «Обновить»' or
            ('Нет выгодных связок по фильтрам'..(age>0 and (' · старше '..math.floor(age/60)..'м исключены')or '')))
        V.muted(V.fit(reason,imgui.GetContentRegionAvail().x))
    end
    local list_options
    if compact_h then
        list_options={footer=false}
    else
        list_options={footer=function()
            V.muted('Оценка по API, не гарантированная прибыль. Количество у скупщика может уменьшиться.')
        end}
    end
    V.list_rows('arb_main',filtered,92,function(g,i)
        V.row('arb_group_'..i,92,function(w,x,y)
            M.thumbnail({name=g.name,id=g.row and g.row.id},34)
            V.at(x+44,y+2);V.text(V.fit(g.name,w-220))
            V.at(x+44,y+29);V.muted(V.fit('Купить: '..DSP.market.format_units(g.supply)..
                ' · Сдать: '..DSP.market.format_units(g.demand)..' шт. (API)',w-220))
            V.at(x+44,y+54);V.muted(V.fit('План '..DSP.market.format_units(g.planned)..
                ' шт. · Оценка прибыли '..DSP.money(g.profit),w-220))
            V.at(x+w-164,y+15)
            if b('Предложения >','group_'..i,160,false)then
                V.arb_item=g.key;V.arb_snapshot=tostring(st.sid)..'/'..tostring(st.version)
                V.arb_server=st.sid;V.arb_detail_group=g;V.arb_snapshot_time=os.time()
                V.arb_route=false;V.arb_tab='sell';V.arb_best_error=nil;V.arb_verify=nil;choose_all(g);V.open_popup('Арбитраж','arb_details')
            end
        end)
    end,list_options)
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    if V.arb_filters then V.popup('Фильтры арбитража','arb_filters',function()
        local f=DSP.settings.arb_filters or {};DSP.settings.arb_filters=f
        -- Fields are saved as numeric settings and never trigger requests per frame.
        -- 0 seconds means any age; percentage fields use explicit units.
        local changed=false
        local function number(label,key,min,limit)
            V.muted(label)
            if M.compact_number(f,key,'arb_filter_'..key,math.min(260,imgui.GetContentRegionAvail().x),min)then
                if limit and f[key]>limit then f[key]=limit;M.refresh_buffer(f,key) end
                changed=true
            end
        end
        V.list('arb_filter_controls',function(w)
            number('Свежесть данных: максимум секунд (0 = без ограничения, 3600 = час)', 'max_age',0,2592000)
            if b('10 мин','age10',110) then f.max_age=600;M.refresh_buffer(f,'max_age');changed=true end
            V.inline();if b('1 час','age60',110)then f.max_age=3600;M.refresh_buffer(f,'max_age');changed=true end
            V.inline();if b('Любой возраст','age_any',170)then f.max_age=0;M.refresh_buffer(f,'max_age');changed=true end
            number('Комиссия в базисных пунктах: 100 = 1%, 250 = 2.5%', 'tax_bp',0,10000)
            number('Резерв спроса (%) от 0 до 90: оставлять непроверенный объём', 'safety_pct',0,90)
            number('Минимальная рентабельность ROI (%)', 'min_roi',0,100000)
            number('Минимальная чистая прибыль на маршрут ($)', 'min_profit',0)
            number('Минимальная прибыль с одной штуки ($)', 'min_unit_profit',0)
            number('Максимальная цена закупки за штуку ($; 0 = без лимита)', 'max_buy_price',0)
            number('Минимальный запас И спрос API (шт.; 0 = без лимита)', 'min_stock',0)
            number('Бюджет на все маршруты ($; 0 = без лимита)', 'budget',0)
            number('Максимум штук на маршрут (0 = без лимита)', 'max_qty',0)
            V.muted('Лавки: любое сочетание / только одна и та же / только разные')
            for i,opt in ipairs({{0,'Любые'},{1,'Одна'},{2,'Разные'}})do
                if i>1 then V.inline()end
                if b(opt[2],'shop_mode_'..opt[1],110,f.shop_mode==opt[1])then f.shop_mode=opt[1];changed=true end
            end
            V.muted('Порядок расчёта (при бюджете приоритет ROI)')
            for i,opt in ipairs({{1,'Прибыль'},{2,'За штуку'},{3,'ROI'}})do
                if i>1 then V.inline()end
                if b(opt[2],'sort_mode_'..opt[1],110,f.sort==opt[1])then f.sort=opt[1];changed=true end
            end
            if b(f.allow_partial==false and '[ ] Частичные маршруты' or '[x] Частичные маршруты',
                'allow_partial',290)then f.allow_partial=not(f.allow_partial~=false);changed=true end
            if b(f.include_unknown==true and '[x] Без отметки времени' or '[ ] Без отметки времени',
                'include_unknown',290)then f.include_unknown=not(f.include_unknown==true);changed=true end
            if b('Сбросить фильтры','reset_filters',210)then
                local defaults={budget=0,min_profit=0,min_roi=0,sort=1,max_age=300,max_qty=0,
                    safety_pct=10,allow_partial=true,include_unknown=false,
                    tax_bp=DSP.settings.tax_bp or 200,min_unit_profit=0,max_buy_price=0,
                    min_stock=0,shop_mode=0}
                for k,v in pairs(defaults)do f[k]=v;M.refresh_buffer(f,k)end
                changed=true
            end
            V.muted('Возраст 0 означает показ даже старых офферов; это не гарантия наличия.')
        end,{footer=true})
        if changed then
            DSP.market.invalidate_arbitrage();V.arb_revision=V.arb_revision+1
            V.reset_list('arb_main');M.defer_save()
        end
        if b('Применить и закрыть','filters_done',220,true)then
            V.arb_filters=false;imgui.CloseCurrentPopup()
        end
    end,{w=690,h=570})end
    V.popup('Арбитраж','arb_details',function()
        local st=DSP.market.state
        if V.arb_server~=st.sid then
            V.text('Выбран другой сервер');V.muted('Откройте предмет повторно для нового расчёта')
            if b('Закрыть','stale_close',150)then imgui.CloseCurrentPopup()end
            return
        end
        -- Never keep showing the old route after a market refresh: source
        -- offer tables are replaced, not updated in place.
        if V.arb_snapshot~=tostring(st.sid)..'/'..tostring(st.version)
            or st.status=='loading' then
            V.red('Данные изменились или обновляются. Старый маршрут заблокирован.')
            if b('Пересчитать','refresh_selected',164)then
                local groups,status
                if DSP.market.arbitrage_grouped_ui then
                    groups,status=DSP.market.arbitrage_grouped_ui()
                else groups=DSP.market.arbitrage_grouped()end
                if status~='loading' then
                    local g=V.arb_group(groups)
                    if g then
                        V.arb_detail_group=g;choose_all(g);V.arb_route=false
                        V.arb_verify=nil;V.arb_snapshot=tostring(st.sid)..'/'..tostring(st.version)
                        V.arb_snapshot_time=os.time()
                    else V.arb_best_error='После обновления подходящий маршрут отсутствует'end
                end
            end
            V.inline();if b('Закрыть','stale_close_version',140)then imgui.CloseCurrentPopup()end
            -- Keep the inspected snapshot browsable, but expose no old route,
            -- quantity confirmation or marker actions after a refresh.
            local snapshot=V.arb_detail_group
            if snapshot then
                if b('Продают · снимок','sell',190,V.arb_tab=='sell')then V.arb_tab='sell'end
                V.inline();if b('Скупают · снимок','buy',190,V.arb_tab=='buy')then V.arb_tab='buy'end
                local offers=V.arb_tab=='sell'and snapshot.sellers or snapshot.buyers
                V.list_rows('arb_stale_'..snapshot.key..'_'..V.arb_tab,offers,76,function(o,i)
                    V.row('stale_offer_'..i,76,function(w,x,y)
                        V.text(V.fit('#'..tostring(o.shop)..' · '..tostring(o.owner or '?'),w))
                        V.at(x,y+26);V.muted(V.fit(DSP.money(o.price)..'/шт. · '..DSP.market.format_units(o.qty)..' шт. · старый API-снимок',w))
                    end)
                end)
            end
            return
        end
        local g=V.arb_detail_group
        if g then details(g)else
            V.muted('Связка больше не проходит фильтры')
            if b('Закрыть','empty_close',140)then imgui.CloseCurrentPopup()end
        end
    end,{w=850,h=560})
end
      end
      local ok_module,why_module=pcall(_v293_arbitrage_ui)
      if not ok_module then error('_v293_arbitrage_ui: '..tostring(why_module))end
      local function _v293_stats_ui()
-- v2.9.3 statistics screen override. Keeps the legacy settings module untouched.
local V,M,C=DSP.ui22,DSP.mobile,DSP.craglog
if V._stats_v293 then return true end
V._stats_v293=true
local old_tools=V.tools
local function b(s,id,w,on)return V.button(s,'stats293_'..id,w,on,false,38)end
local function statistics()
    V.heading('Статистика ларцов / наград')
    V.stats293_period=V.stats293_period or DSP.settings.stats_mode or'day'
    local periods={{'hour','Час'},{'day','День'},{'week','Неделя'},{'month','Месяц'},{'all','Всё'}}
    local pw=math.max(58,(imgui.GetContentRegionAvail().x-24)/5)
    for i,p in ipairs(periods)do
        if b(p[2],'period_'..p[1],pw,V.stats293_period==p[1])then
            V.stats293_period=p[1];DSP.settings.stats_mode=p[1]
            if M.defer_save then M.defer_save()end
        end
        if i<#periods then V.inline(6,pw)end
    end
    local query=V.search('stats293','Поиск ларца / награды',-1)
    local s=C.drop_sales_stats(V.stats293_period,query)
    V.green('Выпало: '..tostring(s.dropped)..' шт. · Продано: '..tostring(s.sold)..' шт.')
    if s.inventory_ready then
        V.text('Фактически в последнем скане инвентаря: '..tostring(s.inventory_total)..' шт.')
    else
        V.muted('Инвентарь ещё не сканирован: фактическое количество не подменяем расчётом.')
    end
    V.muted('Остаток по журналу: '..tostring(s.journal_balance)..' шт. (дроп за всё время - подтверждённые продажи)')
    if s.approx then V.muted('~ Для части старых рыночных чеков количество не было сохранено точно.')end
    if DSP.auto and not DSP.auto.scanning and b('Обновить фактический инвентарь','scan_inventory',260,true)then
        local ok=DSP.auto.scan_inventory()
        if ok==false then V.stats293_error='Сканирование сейчас недоступно'else V.stats293_error=nil end
    elseif DSP.auto and DSP.auto.scanning then
        V.muted('Сканирование инвентаря...')
    end
    if V.stats293_error then V.red(V.stats293_error)end
    V.list_rows('stats293_'..V.stats293_period,s.items,86,function(r,i)
        V.row('row_'..i,86,function(w,x,y)
            local name=r.name..((tonumber(r.ench)or 0)>0 and(' (+'..r.ench..')')or'')
            V.at(x,y+1);V.text(V.fit(name,w-12))
            V.at(x,y+29);V.muted(V.fit('Выпало '..r.dropped..' · Продано '..r.sold..
                (r.sold_exact and''or'~')..' · Остаток журнала '..r.journal_balance,w-12))
            V.at(x,y+56)
            if s.inventory_ready then
                V.green(V.fit('Фактически сейчас: '..r.inventory..' шт. · оценка дропа ~ '..DSP.money(r.estimated or 0),w-12))
            else
                V.muted(V.fit('Факт: нужен скан инвентаря · оценка дропа ~ '..DSP.money(r.estimated or 0),w-12))
            end
        end)
    end,{count=#s.items,footer=function()
        V.muted('Факт берётся только из собственного скана инвентаря; журнал не выдаётся за инвентарь.')
    end})
end
function V.tools(screen)
    if screen=='stats' then return statistics() end
    return old_tools(screen)
end
return true
      end
      local ok_module,why_module=pcall(_v293_stats_ui)
      if not ok_module then error('_v293_stats_ui: '..tostring(why_module))end
      local function _v293_trade_journal()
-- v2.9.3 Market Helper-style trade journal: verified sales/buys only.
local C,V=DSP.craglog,DSP.ui22
if C._trade293_installed then return true end
C._trade293_installed=true
local function u(s)return DSP.utf8(tostring(s or''))end
local function b(s,id,w,on)return V.button(s,'trade293_'..id,w,on,false,38)end
local function money(n)return DSP.money(math.floor(tonumber(n)or 0))end
local function low(s)return(DSP.lower or string.lower)(tostring(s or''))end
local function kind(e)
    if e.type=='market'then return e.direction=='sell'and'sell'or e.direction=='buy'and'buy'end
    if e.type=='trade'then
        local get,give=tonumber(e.money_get)or 0,tonumber(e.money_give)or 0
        if get>0 and give==0 then return'sell'end
        if give>0 and get==0 then return'buy'end
    end
end
local function items(e,k)return k=='sell'and(e.items_give or{})or(e.items_get or{})end
local function raw_qty(raw)
    local s=tostring(raw or'')
    return tonumber(s:match('[xX]%s*(%d+)')or s:match('(%d+)%s*[xX]')
        or s:match('(%d+)%s*шт'))
end
local function quantity(e,k)
    local q=tonumber(e.qty or e.count)
    if q and q>0 then return math.floor(q),e.qty_exact~=false end
    if e.type=='trade'then
        local n=0;for _,it in ipairs(items(e,k))do n=n+(tonumber(it.qty)or 1)end
        if n>0 then return n,true end
    end
    q=raw_qty(e.raw)
    if q and q>0 then return math.floor(q),false end
    return 1,false
end
local function amount(e,k)
    if e.type=='market'then return tonumber(e.amount)or 0 end
    return tonumber(k=='sell'and e.money_get or e.money_give)or 0
end
local function description(e,k)
    if e.type=='market'then return tostring(e.item_name or e.item or'?')end
    local parts={}
    for i,it in ipairs(items(e,k))do
        if i>3 then parts[#parts+1]='...';break end
        parts[#parts+1]=tostring(it.name or'?')..' x'..tostring(it.qty or 1)
    end
    return #parts>0 and table.concat(parts,', ')or tostring(e.partner or'Торговая операция')
end
local function period_from(period,now)
    now=now or os.time()
    if period=='hour'then return now-3600 end
    if period=='day'or period=='today'then local d=os.date('*t',now);d.hour,d.min,d.sec=0,0,0;return os.time(d)end
    if period=='week'then return now-7*86400 end
    if period=='month'then return now-30*86400 end
    return 0
end
local function events()
    if C.history then
        local h=C.history('all','');local out={}
        for i=#h,1,-1 do out[#out+1]=h[i]end
        return out
    end
    return C.ring_recent(C.ring_count)
end
function C.trade_rows(period,query,side)
    local list={};local from=period_from(period or'day');local q=low(query)
    for _,e in ipairs(events())do
        local k=kind(e);local ts=tonumber(e.ts)or 0
        if k and ts>=from and(not side or side=='all'or side==k)
            and(not C.event_visible or C.event_visible(e))then
            local name=description(e,k)
            if q==''or low(name):find(q,1,true)or low(e.partner):find(q,1,true)then
                local count,exact=quantity(e,k)
                list[#list+1]={kind=k,ts=ts,name=name,amount=amount(e,k),qty=count,
                    qty_exact=exact,partner=e.partner,source=e.source or'game'}
            end
        end
    end
    return list
end
function C.trade_totals(rows)
    local s={sells=0,buys=0,sell_count=0,buy_count=0,sell_qty=0,buy_qty=0,approx=false}
    for _,e in ipairs(rows or{})do
        if e.kind=='sell'then s.sells=s.sells+(e.amount or 0);s.sell_count=s.sell_count+1;s.sell_qty=s.sell_qty+(e.qty or 1)
        else s.buys=s.buys+(e.amount or 0);s.buy_count=s.buy_count+1;s.buy_qty=s.buy_qty+(e.qty or 1)end
        if e.qty_exact==false then s.approx=true end
    end
    return s
end
local function period_buttons(key,current)
    local opts={{'hour','Час'},{'day','День'},{'week','Неделя'},{'month','Месяц'},{'all','Всё'}}
    local w=math.max(56,(imgui.GetContentRegionAvail().x-24)/5)
    for i,p in ipairs(opts)do
        if b(p[2],key..p[1],w,current==p[1])then current=p[1]end
        if i<#opts then V.inline(6,w)end
    end
    return current
end
local function show_row(row,compact)
    local sign=row.kind=='sell'and'+'or'-'
    local action=row.kind=='sell'and'ПРОДАЖА'or'ПОКУПКА'
    local stamp=os.date(compact and'%H:%M'or'%d.%m %H:%M',row.ts)
    local text=action..' '..sign..money(row.amount)..' | '..stamp..' '..row.name..
        ' x'..tostring(row.qty or 1)..(row.qty_exact==false and'~'or'')
    if compact then text=V.fit(text,math.max(100,imgui.GetContentRegionAvail().x-9))end
    imgui.TextColored(DSP.theme.col(row.kind=='sell'and'good'or'accent',1),u(text))
end
function V.journal()
    V.heading('Журнал продаж / скупки',function()
        if b('Мини-окно','mini',150)then C.set_minimized(false);DSP.settings.craglog.open=true;DSP.save_settings()end
    end,166)
    V.muted('Только подтверждённые игрой сделки. Награды и PayDay вынесены в статистику.')
    V.journal_trade_period=period_buttons('main_',V.journal_trade_period or'day')
    V.journal_trade_side=V.journal_trade_side or'all'
    local sw=math.max(82,(imgui.GetContentRegionAvail().x-12)/3)
    for i,p in ipairs({{'all','Все'},{'sell','Продажи'},{'buy','Скупка'}})do
        if b(p[2],'side_'..p[1],sw,V.journal_trade_side==p[1])then V.journal_trade_side=p[1]end
        if i<3 then V.inline(6,sw)end
    end
    local query=V.search('trade293','Поиск товара или ника',-1)
    local rows=C.trade_rows(V.journal_trade_period,query,V.journal_trade_side)
    local total=C.trade_totals(rows)
    V.green('Продажи: '..money(total.sells)..' · '..total.sell_qty..' шт. · '..total.sell_count..' сделок')
    V.muted('Скупка: '..money(total.buys)..' · '..total.buy_qty..' шт. · '..total.buy_count..' сделок')
    if total.approx then V.muted('~ В старых рыночных чеках количество иногда не сохранялось отдельно.')end
    local reverse={};for i=#rows,1,-1 do reverse[#reverse+1]=rows[i]end
    V.list_rows('trade293_'..V.journal_trade_period..'_'..V.journal_trade_side,reverse,72,function(e,i)
        V.row('trade_'..i,72,function(w,x,y)
            V.at(x,y+1)
            if e.kind=='sell'then V.green('ПРОДАЖА +'..money(e.amount))else V.text('ПОКУПКА -'..money(e.amount))end
            V.at(x,y+29);V.muted(V.fit(os.date('%d.%m %H:%M',e.ts)..' · '..e.name..' · '..e.qty..' шт.',w-12))
        end)
    end,{count=#reverse,footer=function()V.muted('Свайпните список вверх/вниз — стрелки прокрутки не нужны.')end})
end
local function cfg()DSP.settings.craglog=DSP.settings.craglog or{};return DSP.settings.craglog end
local previous_geometry=C.geometry
function C.geometry(sw,sh)
    local s=cfg()
    if not s.trade_compact_initialized then
        s.trade_compact_initialized=true;s.w=math.min(math.max(390,sw*.39),math.max(390,sw-16));s.h=math.min(330,math.max(285,sh-16))
    end
    return previous_geometry(sw,sh)
end
function C.draw()
    local io=imgui.GetIO();local s=cfg();local g=C.geometry(io.DisplaySize.x,io.DisplaySize.y);C.active_geometry=g
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always);imgui.SetNextWindowBgAlpha(.82)
    local colors=DSP.theme.push_window()
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,8);imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(8,7));imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(5,5))
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove+imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse+(s.pinned and imgui.WindowFlags.NoResize or 0)
    if imgui.Begin('##palatka_trade_journal',nil,flags)then
        if V.apply_font then V.apply_font()end
        if b(s.pinned and'ЖУРНАЛ · ЗАКРЕПЛЁН'or'ЖУРНАЛ · ПЕРЕМЕСТИТЬ','move',math.max(120,g.w-170),s.pinned)then end
        if not s.pinned and imgui.IsItemActive()and io.MouseDelta then C.drag(io.MouseDelta.x,io.MouseDelta.y)end
        if not imgui.IsMouseDown(0)then C.end_drag()end
        imgui.SameLine(0,5);if b(s.pinned and'PIN'or'pin','pin',47,s.pinned)then C.set_pinned(not s.pinned)end
        imgui.SameLine(0,5);if b(s.minimized and'+'or'-','fold',38,s.minimized)then C.set_minimized(not s.minimized)end
        imgui.SameLine(0,5);if b('X','close',40)then s.open=false;DSP.save_settings()end
        if not s.minimized then
            s.trade_period=s.trade_period or'day'
            local ww=math.max(55,(imgui.GetContentRegionAvail().x-12)/3)
            for i,p in ipairs({{'day','День'},{'week','Неделя'},{'all','Всё'}})do
                if b(p[2],'float_'..p[1],ww,s.trade_period==p[1])then s.trade_period=p[1];DSP.save_settings()end
                if i<3 then imgui.SameLine(0,6)end
            end
            local rows=C.trade_rows(s.trade_period,'','all');local total=C.trade_totals(rows)
            imgui.Separator()
            if imgui.BeginChild('##trade293_scroll',imgui.ImVec2(0,-55),false,imgui.WindowFlags.NoScrollbar)then
                if #rows==0 then V.muted('Подтверждённых сделок пока нет.')end
                for i=#rows,math.max(1,#rows-119),-1 do show_row(rows[i],true)end
                if DSP.mobile and DSP.mobile.touch_scroll then DSP.mobile.touch_scroll(io,'trade_float')end
            end
            imgui.EndChild();imgui.Separator()
            V.green('Продано '..money(total.sells)..' · '..total.sell_qty..' шт.')
            V.muted('Куплено '..money(total.buys)..' · '..total.buy_qty..' шт.')
            C.remember_size(imgui.GetWindowSize().x,imgui.GetWindowSize().y)
        end
    end
    imgui.End();if C.end_resize then C.end_resize()end
    imgui.PopStyleVar(3);if colors and colors>0 then imgui.PopStyleColor(colors)end
end
return true
      end
      local ok_module,why_module=pcall(_v293_trade_journal)
      if not ok_module then error('_v293_trade_journal: '..tostring(why_module))end
      local function _v293_promo_ui()
-- Market Helper pattern: template title and editable chat commands in one panel.
local ffi=require('ffi')
local V,M,P=DSP.ui22,DSP.mobile,DSP.promo
if V._promo293_installed then return true end
V._promo293_installed=true
V._promo292_installed=true
local function button(label,id,w,on)return V.button(label,'mhpromo_'..id,w,on)end
local function txt(s)return DSP.utf8(tostring(s or''))end
local function buff(str,n)
    local b=imgui.new.char[n]()
    local raw=DSP.to_u8(tostring(str or''))
    ffi.fill(b,n);ffi.copy(b,raw:sub(1,n-1))
    return b
end
local function open_editor(index)
    local t=P.settings().templates[index]
    local rows={}
    local buffers={}
    for i,r in ipairs(t and t.rows or{})do
        rows[i]={text=r.text,interval=r.interval,auto=r.auto~=false}
        buffers[i]=buff(r.text,512)
    end
    V.mhpromo_edit={index=index,name=buff(t and t.name or'Новый шаблон',96),
        rows=rows,buffers=buffers,enabled=t==nil or t.auto~=false,
        waiting=imgui.new.float(t and tonumber(t.waiting) or 1.5),
        interval_min={value=t and t.interval_min or 0},interval_max={value=t and t.interval_max or 0},
        auto_limit={value=t and t.auto_limit or 0},random_line=t and t.random_line==true or false}
end
local function editor(e)
    V.heading('Пиар / Редактор',function()
        if button('Назад','back',120)then V.mhpromo_edit=nil end
    end,142)
    V.text('Название шаблона')
    imgui.SetNextItemWidth(-1)
    imgui.InputText('##mhpromo_name',e.name,96)
    V.muted('Каждая строка — отдельная игровая команда; отправляются по очереди.')
    V.muted('Как в Market Helper: название, строки и настройки одного шаблона.')
    local rm=nil
    if imgui.BeginChild('##mhpromo_rows',imgui.ImVec2(0,math.max(135,math.min(290,imgui.GetContentRegionAvail().y-225))),true)then
        for i,row in ipairs(e.rows)do
            imgui.PushID(i)
            V.muted('Строка '..i)
            imgui.SetNextItemWidth(-1)
            if imgui.InputTextWithHint('##line',txt('/vr Текст рекламы'),
                e.buffers[i],512)then
                row.text=DSP.to_cp(ffi.string(e.buffers[i]))
            end
            V.muted('Пауза после, секунд')
            M.compact_number(row,'interval','mhpromo_delay_'..i,145,60)
            V.inline(4)
            if button(row.auto~=false and 'ВКЛ' or 'ВЫКЛ','on_'..i,68,row.auto~=false)then
                row.auto=not(row.auto~=false)
            end
            V.inline(4)
            if button('Удалить','rm_'..i,94)then rm=i end
            V.inline(4)
            if button('^','up_'..i,42) and i>1 then
                e.rows[i],e.rows[i-1]=e.rows[i-1],e.rows[i]
                e.buffers[i],e.buffers[i-1]=e.buffers[i-1],e.buffers[i]
            end
            V.inline(4)
            if button('v','down_'..i,42) and i<#e.rows then
                e.rows[i],e.rows[i+1]=e.rows[i+1],e.rows[i]
                e.buffers[i],e.buffers[i+1]=e.buffers[i+1],e.buffers[i]
            end
            imgui.Separator()
            imgui.PopID()
        end
    end
    imgui.EndChild()
    if rm then table.remove(e.rows,rm);table.remove(e.buffers,rm)end
    if button('+ Добавить строку','add',225,true)then
        if #e.rows<24 then
            e.rows[#e.rows+1]={text='/vr ',interval=180,auto=true}
            e.buffers[#e.buffers+1]=buff('/vr ',512)
        else e.error='Не более 24 строк'end
    end
    V.inline(6)
    if button('Вставить лавку','shop',160)then
        local i=#e.rows
        if i>0 then
            local value=ffi.string(e.buffers[i])
            if #value<495 then
                e.buffers[i]=buff(DSP.to_cp(value..' {shop}'),512)
                e.rows[i].text=DSP.to_cp(ffi.string(e.buffers[i]))
            end
        end
    end
    V.muted('Макрос {shop} вставляет ссылку/номер своей лавки.')
    V.muted('Пауза между строками одного ручного запуска, сек:')
    imgui.SetNextItemWidth(150)
    imgui.InputFloat('##mhpromo_waiting',e.waiting,.1,.5,'%.1f')
    if e.waiting[0]<.5 then e.waiting[0]=.5 elseif e.waiting[0]>10 then e.waiting[0]=10 end
    if button(e.random_line and'Случайная строка: ВКЛ' or'Случайная строка: ВЫКЛ',
        'random',235,e.random_line)then e.random_line=not e.random_line end
    V.muted('Интервал повтора: 0 = индивидуальный интервал каждой строки.')
    V.muted('Минимум повтора, сек:')
    M.compact_number(e.interval_min,'value','mhpromo_imin',160,0)
    V.inline(6)
    V.muted('Максимум, сек:')
    M.compact_number(e.interval_max,'value','mhpromo_imax',160,0)
    V.muted('Лимит отправок шаблона: 0 = без лимита')
    M.compact_number(e.auto_limit,'value','mhpromo_limit',170,0)
    if e.error then V.red(e.error)end
    if button('СОХРАНИТЬ ШАБЛОН','save',250,true)then
        local name=DSP.to_cp(ffi.string(e.name)):match('^%s*(.-)%s*$')
        local ok,reason=P.save_template(e.index,name,e.rows,e.enabled)
        if ok then
            local list=P.settings().templates
            local idx=e.index or #list
            local saved,err=P.save_template_options(idx,{
                interval_min=e.interval_min.value,interval_max=e.interval_max.value,
                auto_limit=e.auto_limit.value,random_line=e.random_line,waiting=e.waiting[0]})
            if saved then V.mhpromo_edit=nil else e.error=tostring(err)end
        else e.error=tostring(reason)end
    end
    V.inline(4)
    if button('Отмена','cancel',120)then V.mhpromo_edit=nil end
end
function V.promo_screen()
    if V.mhpromo_edit then
        return V.list('mhpromo_editor_scroll',function()editor(V.mhpromo_edit)end,{footer=true})
    end
    local settings=P.settings()
    V.heading('Автопиар · Palatka',function()
        if button('+ Шаблон','new',155,true)then open_editor(nil)end
    end,172)
    if P.running then
        if button('СТОП','stop',127,true)then P.stop()end
    else
        if button('ПУСК','start',127,true)then
            local ok,why=P.start()
            V.mhpromo_error=ok and nil or tostring(why)
        end
    end
    V.inline(5)
    if button(settings.continuous and 'Цикл: ВКЛ' or 'Цикл: ВЫКЛ',
        'loop',152,settings.continuous)then
        P.set_option('continuous',not settings.continuous)
    end
    V.inline(5)
    if button(settings.resume_on_login and'При входе: ВКЛ' or'При входе: ВЫКЛ',
        'resume',191,settings.resume_on_login)then
        P.set_option('resume_on_login',not settings.resume_on_login)
    end
    local left=P.queue_left and P.queue_left()or nil
    V.muted('Отправлено: '..tostring(P.session_count)..
        (settings.continuous and' | без лимита'or' / 12')..
        ' | '..(P.running and(P.pause_reason or'работает')or'выключен')..
        (left and(' | следующая через '..left..'с')or''))
    if V.mhpromo_error or P.last_error then V.red(tostring(V.mhpromo_error or P.last_error))end
    V.muted('Шаблоны со строками /vr, /fam, /gd, /s, /ad и других чатов.')
    V.muted('Интерфейс Palatka MH / сборка 2.9.3')
    V.list_rows('mhpromo_templates',settings.templates,124,function(t,i)
        V.row('mhpromo_t_'..i,124,function(w,x,y)
            local lo=tonumber(t.interval_min)or 0
            local hi=tonumber(t.interval_max)or 0
            local interval=lo>0 and(hi>lo and(lo..'-'..hi..'с')or(lo..'с'))
                or tostring((t.rows and t.rows[1]and t.rows[1].interval)or 180)..'с'
            V.at(x,y);V.text(V.fit(t.name or'Шаблон',math.max(80,w-155)))
            V.at(x,y+27);V.muted(V.fit(#(t.rows or{})..' строк · интервал '..interval..
                ' · пауза '..tostring(t.waiting or 1.5)..'с',math.max(80,w-155)))
            V.at(x,y+56)
            if button(t.auto~=false and'Авто: ВКЛ'or'Авто: ВЫКЛ','enable_'..i,132,t.auto~=false)then
                local was=t.auto;t.auto=not(t.auto~=false)
                if DSP.save_settings and DSP.save_settings()==false then t.auto=was end
            end
            V.inline(4)
            if button(P.manual_busy and P.manual_template==i and'Отправка...'or'Отправить',
                'send_'..i,116,P.manual_busy and P.manual_template==i)then
                local ok,why=P.send_template_once(i);V.mhpromo_error=ok and nil or tostring(why)
            end
            V.at(x+w-143,y+4)
            if button('Изменить','edit_'..i,140)then open_editor(i)end
            V.at(x+w-143,y+78)
            if button('Удалить','del_'..i,140)then
                V.mhpromo_del=i;V.open_popup('Удалить шаблон','mhpromo_delete')
            end
        end)
    end)
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    V.popup('Удалить шаблон','mhpromo_delete',function()
        V.text('Удалить шаблон со всеми строками?')
        if button('Да','yes',105)then
            if P.remove(V.mhpromo_del)then imgui.CloseCurrentPopup()end
        end
        V.inline(5);V.cancel('mhpromo_delete')
    end,{w=415,h=225})
end
return true
      end
      local ok_module,why_module=pcall(_v293_promo_ui)
      if not ok_module then error('_v293_promo_ui: '..tostring(why_module))end
      local function _v293_agent_ui()
-- Palatka AI arbitration companion: native Carbon controls, compact game-safe panel.
-- All trades remain manually acknowledged; no packet, teleport or server automation.
local A,M,V=DSP.arb_agent,DSP.market,DSP.ui22
local function u(s)return DSP.utf8(tostring(s or ''))end
local function label(s)imgui.Text(u(s))end
local function quiet(s)imgui.TextDisabled(u(s))end
local function green(s)imgui.TextColored(DSP.theme.col('good',1),u(s))end
local function red(s)imgui.TextColored(DSP.theme.col('bad',1),u(s))end
local function b(name,id,w,active) return V.button(name,'agent291_'..id,w,active,false,38)end
local function money(v)return DSP.money(tonumber(v)or 0)end
local function selected(s)
    local index=math.max(1,math.min(tonumber(s.focus)or 1,#s.routes))
    return s.routes[index],index
end
local function status(e)
    if e.unavailable_reason=='shop_missing' then return 'Нет лавки' end
    if e.unavailable_reason=='item_missing' then return 'Нет предмета' end
    if e.unavailable_reason=='owner_changed' then return 'Смена владельца' end
    if e.skipped then return 'Пропущено' end
    if e.sold>=e.qty then return 'Завершено' end
    if e.bought<e.qty then return 'Покупка' end
    return 'Продажа'
end
local function rect(io)
    DSP.settings.arb_agent_window=DSP.settings.arb_agent_window or{}
    local p=DSP.settings.arb_agent_window
    local sw,sh=io.DisplaySize.x,io.DisplaySize.y
    local w=DSP.clamp(tonumber(p.w)or 440,math.min(305,sw-16),math.max(305,sw-16))
    local h=DSP.clamp(tonumber(p.h)or 390,math.min(250,sh-16),math.max(250,sh-16))
    return {w=w,h=h,x=DSP.clamp(tonumber(p.x)or(sw-w-12),0,math.max(0,sw-w)),
        y=DSP.clamp(tonumber(p.y)or 110,0,math.max(0,sh-h))}
end
local function drag(g,io,resize)
    local d=io.MouseDelta
    if not d or (d.x==0 and d.y==0) then return end
    local w=resize and DSP.clamp(g.w+d.x,math.min(305,io.DisplaySize.x-16),io.DisplaySize.x-g.x)or g.w
    local h=resize and DSP.clamp(g.h+d.y,math.min(250,io.DisplaySize.y-16),io.DisplaySize.y-g.y)or g.h
    local x=resize and g.x or DSP.clamp(g.x+d.x,0,io.DisplaySize.x-w)
    local y=resize and g.y or DSP.clamp(g.y+d.y,0,io.DisplaySize.y-h)
    DSP.settings.arb_agent_window={x=x,y=y,w=w,h=h}
    A._geometry_dirty=true
end
local function notice(msg)A.ui_message=msg end
local function route_queue(s)
    local total=#s.routes
    if total==0 then return end
    local pages=math.max(1,math.ceil(total/4))
    A.queue_page=DSP.clamp(tonumber(A.queue_page)or 1,1,pages)
    quiet('Маршруты: '..total..'  |  Страница '..A.queue_page..'/'..pages)
    local from=(A.queue_page-1)*4+1
    for i=from,math.min(total,from+3)do
        local e=s.routes[i]
        if b(V.fit(i..'. '..e.name..' · '..status(e),math.max(100,imgui.GetContentRegionAvail().x-20)),
            'route_'..i,-1,s.focus==i)then
            A.focus(i);A.qty_key=nil
        end
    end
    if pages>1 then
        if b('Ранее','pageprev',110)then A.queue_page=math.max(1,A.queue_page-1)end
        imgui.SameLine(0,8)
        if b('Далее','pagenext',110)then A.queue_page=math.min(pages,A.queue_page+1)end
    end
end
local function route_info(e,index,total)
    if not e then quiet('Новых маршрутов пока нет');return end
    quiet('Сделка '..index..' из '..total..' · '..status(e))
    label(V.fit(e.name,math.max(120,imgui.GetContentRegionAvail().x-12)))
    quiet('План '..e.qty..' шт.  |  Ожидаемая прибыль ~ '..money(e.proposed_profit))
    quiet('Куплено '..e.bought..' · Продано '..e.sold)
    if e.skipped then
        if e.bought>e.sold then red('Товаров на руках: '..(e.bought-e.sold)..' шт.')end
        quiet('Маршрут остаётся в сессии. Можно вернуть его или перейти дальше.')
        local half=math.max(105,math.floor((imgui.GetContentRegionAvail().x-6)/2))
        if b('Вернуть маршрут','restore',half)then
            local ok,err
            if e.unavailable_reason then ok,err=A.restore_unavailable(index)else ok=A.skip(index,false)end
            notice(ok and 'Маршрут снова активен' or tostring(err or 'Не удалось вернуть маршрут'))
        end
        imgui.SameLine(0,6)
        if b('Следующий','skipped_next',half)then A.next(1);A.qty_key=nil end
        return
    end
    if e.sold>=e.qty then green('Сделка завершена');return end
    local buying=e.bought<e.qty
    local side=buying and 'buy' or 'sell'
    local shop=buying and e.seller_shop or e.buyer_shop
    local owner=buying and e.seller_owner or e.buyer_owner
    local price=buying and e.buy_price or e.sell_price
    local remaining=buying and(e.qty-e.bought)or(e.bought-e.sold)
    if remaining<=0 then return end
    green(buying and 'Купить' or 'Продать')
    label('Лавка #'..shop..' · '..tostring(owner or'?'))
    quiet('Осталось '..remaining..' шт.  |  '..money(price)..' / шт.')
    if b('Метка на лавку #'..shop,'mark',-1)then
        if not M.mark_shop(shop)then notice('Метка недоступна')end
    end
    if b('Нет лавки','missing_shop',145)then
        local ok,err=A.mark_unavailable(index,'shop')
        notice(ok and 'Лавка исключена из планов' or tostring(err))
    end
    imgui.SameLine(0,6)
    if b('Нет предмета','missing_item',160)then
        local ok,err=A.mark_unavailable(index,'item')
        notice(ok and 'Предложение исключено' or tostring(err))
    end
    local key=e.id..':'..side
    if A.qty_key~=key then A.qty_key=key;A.qty_field=imgui.new.int(remaining)end
    quiet('Подтверждение количества:')
    imgui.SetNextItemWidth(math.min(160,imgui.GetContentRegionAvail().x))
    imgui.InputInt('##agent291_qty',A.qty_field,1,10)
    if b(buying and 'Подтвердить покупку' or 'Подтвердить продажу','confirm',-1,true)then
        local ok,err=A.confirm(index,side,A.qty_field[0])
        if ok then A.qty_key=nil;notice('Количество записано')else notice(tostring(err))end
    end
    local hint=A.hint
    if hint and hint.route_id==e.id and hint.side==side then
        quiet('Обнаружен похожий чек: '..hint.qty..' шт.')
        if b('Принять данные чека','receipt',-1)then
            local ok,err=A.confirm(index,side,hint.qty)
            if ok then A.qty_key=nil;notice('Чек подтверждён')else notice(tostring(err))end
        end
    end
end
function A.draw()
    local s=A.active()
    if not s then A.show(false);return end
    if A.review_market then A.review_market()end
    local io=imgui.GetIO()
    local g=rect(io)
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(.94)
    local color_count=DSP.theme.push_window()
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(9,8))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(6,6))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,9)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse
    if imgui.Begin('##palatka_arbitrage_agent',nil,flags)then
        if V.apply_font then V.apply_font()end
        if b('Арбитраж · переместить','handle',math.max(100,g.w-112))then end
        if imgui.IsItemActive() and io.MouseDelta then drag(g,io,false)end
        imgui.SameLine(0,5)
        if b(A.queue_expanded and '-' or '+','queue',40)then A.queue_expanded=not A.queue_expanded end
        imgui.SameLine(0,5)
        if b('X','close',43)then A.show(false)end
        local st=A.stats()
        quiet('Завершено '..st.done..'/'..st.routes..' · В работе '..st.pending)
        green('Ожидаемый результат ~ '..money(st.profit_estimate))
        quiet('Мини-агент Palatka / сборка 2.9.3')
        imgui.Separator()
        if A.queue_expanded then
            route_queue(s)
            if not A.end_confirm then
                if b('Закончить сессию','end',-1)then A.end_confirm=true end
            else
                red('Завершить сессию?')
                if b('Завершить','endyes',140)then A.stop();A.end_confirm=false end
                imgui.SameLine(0,5)
                if b('Отмена','endno',130)then A.end_confirm=false end
            end
            imgui.Separator()
        end
        if imgui.BeginChild('##agent291_content',imgui.ImVec2(0,-80),false,imgui.WindowFlags.NoScrollbar)then
            local e,i=selected(s)
            route_info(e,i,#s.routes)
            if DSP.mobile and DSP.mobile.touch_scroll then DSP.mobile.touch_scroll(io,'arb_agent_content')end
        end
        imgui.EndChild()
        if A.ui_message then quiet(V.fit(A.ui_message,math.max(120,g.w-35)))end
        if A.save_error then red('Не сохранено: '..tostring(A.save_error))end
        if b('< Предыдущая','prev',math.max(105,math.floor((g.w-36)/2)))then A.next(-1);A.qty_key=nil end
        imgui.SameLine(0,6)
        if b('Следующая >','next',math.max(105,math.floor((g.w-36)/2)))then A.next(1);A.qty_key=nil end
        -- Native ImGui drag-resize grip, visually aligned to Palatka corners.
        imgui.SetCursorPos(imgui.ImVec2(g.w-39,g.h-36))
        if b('//','resize',29)then end
        if imgui.IsItemActive()and io.MouseDelta then drag(g,io,true)end
    end
    imgui.End()
    imgui.PopStyleVar(3)
    if color_count and color_count>0 then imgui.PopStyleColor(color_count)end
    if A._geometry_dirty and not imgui.IsMouseDown(0)then
        A._geometry_dirty=false
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
    end
end
return true
      end
      local ok_module,why_module=pcall(_v293_agent_ui)
      if not ok_module then error('_v293_agent_ui: '..tostring(why_module))end
      local function _v293_arbitrage_status()
-- Arbitrage agent availability: user-confirmed absence and trusted game evidence.
-- Quote absence is NOT inferred from a partial shop snapshot.
local A,M=DSP.arb_agent,DSP.market
local function now()return os.time()end
local function sid()return tonumber(M.state and M.state.sid)or tonumber(DSP.settings.server)or 0 end
local function cycle(t)
    local d=os.date('*t',t);d.hour=5;d.min=0;d.sec=0
    local boundary=os.time(d);return t<boundary and boundary-86400 or boundary
end
local function text_eq(x,y)
    local f=DSP.lower or string.lower
    return f(tostring(x or''))==f(tostring(y or''))
end
local function valid_shop(shop)
    local n=tonumber(shop)
    return n and n>0 and n<=99999 and n==math.floor(n)
end
local function ensure()
    A.data=A.data or{schema=1,consumed={},history={}}
    A.data.unavailable=A.data.unavailable or{}
    return A.data.unavailable
end
local old_load=A.load
function A.load(...)
    local result=old_load(...)
    ensure()
    return result
end
ensure()
local old_remaining=A.remaining
function A.remaining(row,side,offer,base,meta)
    local qty,origin=old_remaining(row,side,offer,base,meta)
    local quote=A.quote_key(sid(),row,side,offer)
    local denied=quote and ensure()[quote]
    if denied and tonumber(denied.at)and denied.at>=cycle(now())then
        -- Trusted positive game observation AFTER the manual absence supersedes it.
        local evidence=origin and (origin.source=='game_observed' or origin.source=='recent_scan')
        if evidence and (tonumber(origin.at)or 0)>denied.at and qty>0 then
            ensure()[quote]=nil;A.save()
            return qty,origin
        end
        return 0,{source='confirmed_unavailable',at=denied.at,reason=denied.reason}
    end
    return qty,origin
end
local function changed()
    A.revision=(A.revision or 0)+1
    local ok,err=A.save()
    A.save_error=ok and nil or tostring(err)
    if M.invalidate_arbitrage then M.invalidate_arbitrage()end
    return ok,err
end
local function required_leg(e)
    if e.bought<e.qty then return 'sell',e.seller_shop,e.seller_quote end
    if e.sold<e.qty then return 'buy',e.buyer_shop,e.buyer_quote end
end
local function block_related(shop,quote,reason,source)
    local s=A.active();if not s then return 0 end
    local marked=0
    for _,e in ipairs(s.routes or{})do
        local side,target,current=required_leg(e)
        local match=side and ((quote and current==quote)or
            (not quote and tostring(target)==tostring(shop)))
        if match and e.sold<e.qty and not e.unavailable_reason then
            e.unavailable_reason=reason
            e.unavailable_source=source or'manual'
            e.unavailable_at=now()
            e.unavailable_side=side
            e.skipped=true
            marked=marked+1
        end
    end
    return marked
end
function A.mark_unavailable(index,reason)
    if reason~='shop'and reason~='item'then return false,'Неверная причина'end
    local e,s=A.get(index)
    if not e or not s then return false,'Маршрут не выбран'end
    local side,shop,quote=required_leg(e)
    if not side then return false,'Маршрут уже завершён'end
    if reason=='shop' then
        if not valid_shop(shop)then return false,'Номер лавки неизвестен'end
        if not M.mark_shop_missing(shop,30)then return false,'Не удалось отметить лавку'end
        block_related(shop,nil,'shop_missing','manual')
    else
        ensure()[quote]={at=now(),reason='item_missing',sid=s.sid}
        block_related(shop,quote,'item_missing','manual')
    end
    s.focus=index
    A.show(true)
    changed()
    return true
end
function A.restore_unavailable(index)
    local e=A.get(index)
    if not e then return false,'Нет маршрута'end
    if not e.unavailable_reason then return A.skip(index,false)end
    local reason=e.unavailable_reason
    local shop=e.unavailable_side=='sell'and e.seller_shop or e.buyer_shop
    local quote=e.unavailable_side=='sell'and e.seller_quote or e.buyer_quote
    if reason=='shop_missing' or reason=='owner_changed' then
        if M.restore_shop and valid_shop(shop) then M.restore_shop(shop) end
    end
    if quote then ensure()[quote]=nil end
    e.unavailable_reason=nil;e.unavailable_at=nil;e.unavailable_side=nil
    e.unavailable_source=nil;e.skipped=false
    changed();return true
end
-- Server's response to our own /findilavka, not arbitrary chat, is authoritative.
local former_game=M.mark_shop_missing_from_game
if type(former_game)=='function' then
    M.mark_shop_missing_from_game=function(shop,timestamp)
        local ok=former_game(shop,timestamp)
        if ok and block_related(shop,nil,'shop_missing','game')>0 then changed()end
        return ok
    end
end
-- A stable, numbered, owner-identified shop observed in game may prove that
-- the old owner no longer runs this shop; missing ITEM still needs manual review.
function A.observe_live_shop()
    local live=DSP.live and DSP.live.shop
    if not live or not live.scan_complete or tonumber(live.server)~=sid()
        or not valid_shop(live.num) or tostring(live.owner or'')==''then return false end
    local s=A.active()
    if not s or s.sid~=sid()then return false end
    local ts=tonumber(live.items_updated)or 0
    if ts<=0 or now()-ts>90 then return false end
    local blocked=0
    for _,e in ipairs(s.routes)do
        local side,shop=required_leg(e)
        local owner=side=='sell'and e.seller_owner or e.buyer_owner
        if side and tostring(shop)==tostring(live.num)
            and owner~='?' and not text_eq(owner,live.owner)
            and not e.unavailable_reason then
            e.unavailable_reason='owner_changed';e.unavailable_source='game'
            e.unavailable_at=now();e.unavailable_side=side;e.skipped=true;blocked=blocked+1
        end
    end
    if blocked>0 then changed()end
    return blocked>0
end
local previous_review=A.review_market
function A.review_market(...)
    local t=now()
    if t-(A._last_availability_check or 0)>=2 then
        A._last_availability_check=t
        A.observe_live_shop()
    end
    return previous_review(...)
end
return true
      end
      local ok_module,why_module=pcall(_v293_arbitrage_status)
      if not ok_module then error('_v293_arbitrage_status: '..tostring(why_module))end
      local function _v293_runtime_diagnostic()
-- In-game verification for actively loaded UI modules, not just the version manifest.
local V,C,A,P=DSP.ui22,DSP.craglog,DSP.arb_agent,DSP.promo
DSP.active_ui_build='2.9.3'
DSP.active_ui_refs={
    agent=A and A.draw, journal=C and C.draw,
    journal_tab=V and V.journal, promo=V and V.promo_screen
}
local function report()
    local ref=DSP.active_ui_refs or{}
    local same=V and C and A and P and
        A.draw==ref.agent and C.draw==ref.journal and
        V.journal==ref.journal_tab and V.promo_screen==ref.promo and
        type(P.save_template_options)=='function' and type(C.trade_rows)=='function'
    local line='Palatka runtime '..tostring(DSP.version or '?')..
        ' / UI '..tostring(DSP.active_ui_build or 'none')..
        ' / screens '..(same and'ACTIVE' or'MISMATCH')
    if DSP.flog then DSP.flog('CRDIAG '..line)end
    if sampAddChatMessage then
        sampAddChatMessage('[Palatka] '..line,0x99FFAA)
    end
    return same,line
end
DSP.ui_runtime_check=report
if sampRegisterChatCommand and not DSP._crdiag_registered then
    sampRegisterChatCommand('crdiag',report)
    DSP._crdiag_registered=true
end
if DSP.flog then
    local ok,msg=report()
    DSP.flog('UI modules installed: '..tostring(ok)..' / '..tostring(msg))
end
return true
      end
      local ok_module,why_module=pcall(_v293_runtime_diagnostic)
      if not ok_module then error('_v293_runtime_diagnostic: '..tostring(why_module))end
    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka v2.9.3 install error: '..tostring(err))end
      return false
    end
    DSP._v293_installed=true
    DSP.version='2.9.3'
    DSP.active_ui_build='2.9.3'
    if DSP.flog then DSP.flog('Palatka v2.9.3 Market Helper UX installed')end
    return true
  end
  -- v2.9.4: Market Helper UX, touch scrolling, completed arbitrage flow, journal and statistics.
  local function install_v294()
    local parent_ok=install_v293()
    if not parent_ok then return false end
    if DSP._v294_installed then DSP.version='2.9.4';return true end
    local ok,err=pcall(function()
      local function _v294_settings_persistence()
-- v2.9.4: persist theme and opacity across OTA, game restart and UI snapshots.
-- This overlay is also applied to existing 2.9.3 installations whose core is loaded.
local G=DSP.settings_persistence_v294 or {}
DSP.settings_persistence_v294=G
if G.installed then return true end

-- Recover the selected appearance from the authoritative settings file even if
-- an older core has already overlaid it with stale ui_state.json at startup.
local function read_selected()
    local path=DSP.settings_path
    if type(path)~='string' then return end
    local f=io.open(path,'rb')
    if not f then return end
    local body=f:read('*a')
    f:close()
    local ok,saved=pcall(decodeJson,body or'')
    if not ok or type(saved)~='table' then return end
    if type(saved.theme)=='string' and DSP.theme.list[saved.theme] then
        DSP.theme.current=saved.theme
        DSP.settings.theme=saved.theme
    end
    if type(saved.opacity)=='number' then
        DSP.theme.opacity=DSP.clamp(saved.opacity,0.65,1)
        DSP.settings.opacity=DSP.theme.opacity
    end
end
read_selected()

local function persist_appearance()
    if not DSP.save_ui_state then return true end
    local ok,why=DSP.save_ui_state()
    if not ok and DSP.flog then DSP.flog('APPEARANCE UI STATE SAVE FAILED: '..tostring(why))end
    return ok,why
end

function DSP.theme.set(name)
    if not DSP.theme.list[name] then return false,'Неизвестная тема'end
    local old=DSP.theme.current
    DSP.theme.current=name
    DSP.settings.theme=name
    local ok,why=DSP.save_settings()
    if not ok then
        DSP.theme.current=old
        DSP.settings.theme=old
        if DSP.flog then DSP.flog('APPEARANCE SAVE FAILED: '..tostring(why))end
        return false,why
    end
    persist_appearance()
    return true
end
function DSP.theme.set_opacity(value)
    local old=DSP.theme.opacity
    local next=DSP.clamp(tonumber(value)or 0.97,0.65,1)
    DSP.theme.opacity=next
    DSP.settings.opacity=next
    local ok,why=DSP.save_settings()
    if not ok then
        DSP.theme.opacity=old
        DSP.settings.opacity=old
        if DSP.flog then DSP.flog('OPACITY SAVE FAILED: '..tostring(why))end
        return false,why
    end
    persist_appearance()
    return true
end

-- Explicit save action and deferred changes use the same durable primary file.
if DSP.mobile and not G.flush_wrapped then
    local M=DSP.mobile
    local old_flush=M.flush_save
    if type(old_flush)=='function' then
        M.flush_save=function(force)
            local result=old_flush(force)
            if M._save_pending and DSP.flog then
                local now=os.time()
                if force or not G.last_warning or now-G.last_warning>15 then
                    G.last_warning=now
                    DSP.flog('PERSISTENCE: pending save retry, primary write failed')
                end
            end
            return result
        end
    end
    G.flush_wrapped=true
end
G.installed=true
return true
      end
      local ok_module,why_module=pcall(_v294_settings_persistence)
      if not ok_module then error('_v294_settings_persistence: '..tostring(why_module))end
      local function _v294_promo_scheduler()
-- v2.9.4: Market Helper scheduler: one template = one batch of chat commands.
-- No packet injection or server cooldown bypass. Fully opt-in and cancellable.
local P=DSP.promo
if P._mh_scheduler_v294 then return true end
P._mh_scheduler_v294=true

local function now()return os.time()end
local function connected()
    if type(sampSendChat)~='function' then return false end
    if sampIsSampAvailable and not sampIsSampAvailable()then return false end
    if sampIsLocalPlayerSpawned and not sampIsLocalPlayerSpawned()then return false end
    return true
end
local function clamp(v,lo,hi,default)
    v=tonumber(v)
    if not v or v~=v then return default end
    return math.max(lo,math.min(hi,v))
end
local function persist()
    if DSP.save_settings then
        local ok,why=DSP.save_settings()
        if not ok and DSP.flog then DSP.flog('PROMO SAVE ERROR: '..tostring(why))end
        return ok~=false,why
    end
    return true
end
local function rows(t)
    local result={}
    for _,r in ipairs(t.rows or{})do
        if r.auto~=false and type(r.text)=='string' and r.text~='' and P.validate(r.text)then
            result[#result+1]=r.text
        end
    end
    return result
end
local function active()
    for i,t in ipairs(P.settings().templates)do
        if t.auto~=false and #rows(t)>0 then return true end
    end
    return false
end
local function interval(t)
    local low=clamp(t.interval_min,0,3600,0)
    if low<=0 then
        low=clamp((t.rows or{})[1] and t.rows[1].interval or t.interval,30,3600,180)
    end
    local high=clamp(t.interval_max,0,3600,0)
    if high<=0 or high<low then high=low end
    low=math.max(30,math.floor(low))
    high=math.max(low,math.floor(high))
    return low==high and low or math.random(low,high)
end
local function make_batch(index,t,manual,at)
    local commands=rows(t)
    if #commands==0 then return nil,'Нет разрешённых строк в шаблоне'end
    if t.random_line and #commands>1 then commands={commands[math.random(1,#commands)]}end
    return {index=index,commands=commands,pos=1,manual=manual==true,
        due=at,waiting=clamp(t.waiting,.5,10,1.5)}
end
local function set_stopped(reason)
    local s=P.settings()
    P.running=false;P._batch=nil;P.manual_busy=false;P.manual_template=nil
    P.pause_reason=reason or 'Выключен'
    s.enabled=false
    persist()
end
local function report_error(err)
    P.last_error=tostring(err or'Ошибка отправки')
    P.pause_reason=P.last_error
    if DSP.flog then DSP.flog('PROMO: '..P.last_error)end
end
function P.start(at)
    at=at or now()
    if not active()then return false,'Включи хотя бы один шаблон с командами'end
    local s=P.settings()
    if not s.continuous and (P.session_count or 0)>=P.MAX_SESSION then
        return false,'Лимит отправок сессии исчерпан'
    end
    local prior=s.enabled
    s.enabled=true
    local ok,why=persist()
    if not ok then s.enabled=prior;return false,tostring(why or'Не удалось сохранить запуск')end
    P.running=true;P.last_error=nil;P.pause_reason=nil;P._batch=nil
    P.manual_busy=false;P.manual_template=nil
    P.was_online=false
    P.next_at=at+clamp(s.start_delay,10,120,20)
    for _,t in ipairs(s.templates)do t._promo_due=nil end
    return true
end
function P.stop()
    set_stopped('Остановлен пользователем')
end
function P.bootstrap(at)
    at=at or now()
    local s=P.settings()
    P.running=false;P._batch=nil;P.manual_busy=false;P.manual_template=nil
    P.session_count=0;P.last_sent=0;P.was_online=false;P.last_error=nil
    P.next_at=0
    for _,t in ipairs(s.templates)do t._promo_due=nil end
    if s.resume_on_login and s.enabled and active() then
        P.running=true
        P.next_at=at+clamp(s.start_delay,10,120,20)
        P.pause_reason='Ожидание подключения'
    end
end
function P.send_template_once(index)
    if P._batch then return false,'Дождись завершения текущего шаблона'end
    if not connected()then return false,'Нет подключения к игре'end
    local t=P.settings().templates[index]
    if not t then return false,'Шаблон не найден'end
    local batch,why=make_batch(index,t,true,now())
    if not batch then return false,why end
    P._batch=batch
    P.manual_busy=true;P.manual_template=index
    P.last_error=nil;P.pause_reason=nil
    return true
end
local function finish_batch(batch,at)
    local s=P.settings()
    local t=s.templates[batch.index]
    if t then
        t.last_sent=at
        if not batch.manual then
            t.auto_count=(tonumber(t.auto_count)or 0)+1
            local limit=clamp(t.auto_limit,0,1000,0)
            if limit>0 and t.auto_count>=limit then
                t.auto=false
                t.auto_count=0
                P.last_error='Шаблон «'..tostring(t.name or'?')..'»: достигнут лимит'
            end
            t._promo_due=at+interval(t)
        end
    end
    P._batch=nil;P.manual_busy=false;P.manual_template=nil
    P.next_at=at+math.max(30,tonumber(P.MIN_INTERVAL)or 30)
    persist()
end
local function step_batch(at,send,online)
    local batch=P._batch
    if not batch or at<batch.due then return false end
    if not online then
        report_error('Нет соединения: отправка приостановлена')
        P._batch=nil;P.manual_busy=false;P.manual_template=nil
        return false
    end
    if not P.settings().continuous and (P.session_count or 0)>=P.MAX_SESSION then
        set_stopped('Лимит сообщений за сессию')
        return false
    end
    local raw=batch.commands[batch.pos]
    local cmd,why=P.expand(raw)
    if not cmd or #cmd>P.MAX_STEP_BYTES then
        report_error(why or'Команда превышает 200 байт')
        P._batch=nil;P.manual_busy=false;P.manual_template=nil
        P.next_at=at+30
        return false
    end
    local sender=send or sampSendChat
    if type(sender)~='function'then report_error('Отправка чата недоступна');return false end
    local ok,result=pcall(sender,cmd)
    if not ok or result==false then
        report_error(ok and'Отправка отклонена' or result)
        P._batch=nil;P.manual_busy=false;P.manual_template=nil
        P.next_at=at+30
        return false
    end
    P.last_sent=at
    P.last_command=cmd
    P.session_count=(P.session_count or 0)+1
    batch.pos=batch.pos+1
    P.last_error=nil
    if batch.pos>#batch.commands then
        finish_batch(batch,at)
    else
        batch.due=at+math.max(1,math.ceil(batch.waiting))
        P.next_at=batch.due
    end
    if not P.settings().continuous and P.session_count>=P.MAX_SESSION then
        set_stopped('Лимит сообщений за сессию')
    end
    return true
end

function P.tick(at,send,online)
    at=at or now()
    if online==nil then online=connected()end
    if P._batch then return step_batch(at,send,online)end
    if not P.running then return false end
    if not online then
        P.was_online=false
        P.pause_reason='Нет подключения: ожидание'
        return false
    end
    local s=P.settings()
    if not P.was_online then
        P.was_online=true
        P.next_at=math.max(P.next_at or 0,at+clamp(s.start_delay,10,120,20))
        P.pause_reason='Ожидание после входа'
        return false
    end
    if at<(P.next_at or 0)then return false end
    if not s.continuous and P.session_count>=P.MAX_SESSION then
        set_stopped('Лимит сообщений за сессию')
        return false
    end
    local earliest
    for index,t in ipairs(s.templates)do
        if t.auto~=false and #rows(t)>0 then
            local due=t._promo_due
            if not due then
                local last=tonumber(t.last_sent)or 0
                due=last>0 and last+interval(t)or at
                t._promo_due=due
            end
            if at>=due and at>=((P.last_sent or 0)+math.max(30,P.MIN_INTERVAL or 30)) or
               (at>=due and (P.last_sent or 0)==0) then
                local batch,why=make_batch(index,t,false,at)
                if not batch then report_error(why);return false end
                P._batch=batch
                P.pause_reason=nil
                return step_batch(at,send,online)
            end
            earliest=not earliest and due or math.min(earliest,due)
        end
    end
    if not earliest then
        set_stopped('Нет включённых шаблонов')
    else
        P.next_at=math.max(at+1,earliest)
    end
    return false
end
function P.queue_left()
    if P._batch then return math.max(0,math.ceil(P._batch.due-now()))end
    if not P.running then return nil end
    return math.max(0,math.ceil((P.next_at or 0)-now()))
end
return true
      end
      local ok_module,why_module=pcall(_v294_promo_scheduler)
      if not ok_module then error('_v294_promo_scheduler: '..tostring(why_module))end
      local function _v294_mh_journal_screen()
-- v2.9.4: Market Helper-style journal as ONE normal screen, not a second floating UI.
-- Layout and filtering follow the user-provided Market_Helper(1).lua trade log.
local C,V=DSP.craglog,DSP.ui22
if C._mh_journal_screen_v294 then return true end
C._mh_journal_screen_v294=true
local function u(s)return DSP.utf8(tostring(s or''))end
local function text(s)imgui.Text(u(s))end
local function faded(s)imgui.TextDisabled(u(s))end
local function money(n)return DSP.money(math.floor(tonumber(n)or 0))end
local function button(s,id,w,active)
    return V.button(s,'mhjournal294_'..id,w,active,false,34)
end
local function state()
    DSP.settings.journal_mh=DSP.settings.journal_mh or {period='day',side='all',page=1,date=''}
    local s=DSP.settings.journal_mh
    if not ({day=true,week=true,month=true,all=true,date=true})[s.period] then s.period='day' end
    if not ({all=true,sell=true,buy=true})[s.side] then s.side='all' end
    s.page=math.max(1,math.floor(tonumber(s.page)or 1))
    return s
end
local function persist()
    if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
    elseif DSP.save_settings then DSP.save_settings()end
end
local function select_period(s,period)
    if s.period~=period then s.period=period;s.page=1;persist()end
end
local function matching_date(ts,period,spec,now)
    if period=='all' then return true end
    if period=='date' then return os.date('%Y-%m-%d',ts)==spec end
    if period=='day' then return os.date('%Y-%m-%d',ts)==os.date('%Y-%m-%d',now)end
    local delta=period=='week' and 7*86400 or 30*86400
    return ts>=now-delta and ts<=now
end
local function available_dates(rows)
    local seen,dates={},{}
    for _,r in ipairs(rows)do
        if (r.ts or 0)>0 then
            local day=os.date('%Y-%m-%d',r.ts)
            if not seen[day] then dates[#dates+1]=day;seen[day]=true end
        end
    end
    table.sort(dates,function(a,b)return a>b end)
    return dates
end
local function cell(s,width,tip)
    local str=tostring(s or'')
    local shown=V.fit and V.fit(str,math.max(25,width-7)) or str
    text(shown)
    if tip and shown~=str and imgui.IsItemHovered and imgui.IsItemHovered() then
        imgui.SetTooltip(u(str))
    end
    imgui.NextColumn()
end
local function columns(w)
    -- The same six columns as the Market Helper "Сделки" table.
    local ratios={.155,.265,.075,.155,.14,.21}
    local sizes={}
    for i,r in ipairs(ratios)do sizes[i]=math.max(43,math.floor(w*r))end
    imgui.Columns(6,'##mhjournal294_columns',false)
    for i=1,6 do imgui.SetColumnWidth(i-1,sizes[i])end
    faded('Дата');imgui.NextColumn()
    faded('Товар');imgui.NextColumn()
    faded('Кол.');imgui.NextColumn()
    faded('Цена $');imgui.NextColumn()
    faded('Тип');imgui.NextColumn()
    faded('Ник');imgui.NextColumn()
    imgui.Separator()
    return sizes
end
local function row(e,sizes)
    local stamp=(e.ts and e.ts>0)and os.date('%d.%m %H:%M',e.ts)or'—'
    cell(stamp,sizes[1],true)
    cell(e.name or'?',sizes[2],true)
    cell(tostring(e.qty or 1)..(e.qty_exact==false and'~'or''),sizes[3])
    local price=tonumber(e.amount)or 0
    -- Palatka receipts already store the actual FULL transaction amount.
    -- Do not accidentally multiply by quantity a second time.
    cell('$'..money(price):gsub('^%$', ''),sizes[4],true)
    if e.kind=='sell' then
        imgui.TextColored(DSP.theme.col('good',1),u('Продажа'))
    else
        imgui.TextColored(DSP.theme.col('accent',1),u('Покупка'))
    end
    imgui.NextColumn()
    cell(e.partner and e.partner~='' and e.partner or'—',sizes[6],true)
end
local function page_nav(s,count)
    local count_pages=math.max(1,math.ceil(count/60))
    s.page=math.max(1,math.min(count_pages,s.page))
    local width=math.max(39,math.min(55,imgui.GetContentRegionAvail().x/7))
    if button('<<','first',width)then s.page=1;persist()end
    imgui.SameLine(0,4)
    if button('<','back',width)then s.page=math.max(1,s.page-1);persist()end
    imgui.SameLine(0,8)
    faded('Стр. '..s.page..'/'..count_pages..' ('..count..')')
    imgui.SameLine(0,8)
    if button('>','next',width)then s.page=math.min(count_pages,s.page+1);persist()end
    imgui.SameLine(0,4)
    if button('>>','last',width)then s.page=count_pages;persist()end
end

-- The original floating button/pin/minimize window is deliberately removed.
-- Data collection by C.log_trade/C.log_market continues unchanged.
function C.draw() end
if DSP.settings.craglog then DSP.settings.craglog.open=false end

function V.journal()
    local s=state()
    V.heading('Журнал сделок')
    local avail=imgui.GetContentRegionAvail().x
    local labels={{'all','Все'},{'day','Сегодня'},{'week','Неделя'},
                  {'month','Месяц'},{'date','Дата'}}
    local width=math.max(54,(avail-24)/5)
    for i,p in ipairs(labels)do
        if button(p[2],'period_'..p[1],width,s.period==p[1])then
            select_period(s,p[1])
            if p[1]=='date' then imgui.OpenPopup('##mhjournal294_dates')end
        end
        if i<#labels then imgui.SameLine(0,6)end
    end
    local query,edited=V.search('mhjournal294_search','Поиск товара / ника',-1)
    if edited then s.page=1 end
    local side_width=math.max(73,(imgui.GetContentRegionAvail().x-12)/3)
    for i,p in ipairs({{'all','Все сделки'},{'sell','Продажи'},{'buy','Покупки'}})do
        if button(p[2],'side_'..p[1],side_width,s.side==p[1])then
            s.side=p[1];s.page=1;persist()
        end
        if i<3 then imgui.SameLine(0,6)end
    end
    -- Read all once so date selection contains every recorded trade.
    local all=C.trade_rows('all',query or'',s.side)
    if imgui.BeginPopup('##mhjournal294_dates')then
        faded('Выбери дату')
        for _,date in ipairs(available_dates(all))do
            local display=date:sub(9,10)..'.'..date:sub(6,7)..'.'..date:sub(1,4)
            if imgui.Selectable(display..'##'..date,s.date==date)then
                s.date=date;s.period='date';s.page=1;persist();imgui.CloseCurrentPopup()
            end
        end
        imgui.EndPopup()
    end
    if s.period=='date' then
        if s.date=='' then faded('Дата не выбрана')
        else faded('Дата: '..s.date:sub(9,10)..'.'..s.date:sub(6,7)..'.'..s.date:sub(1,4))end
    end

    local filtered,now={},os.time()
    for _,r in ipairs(all)do
        if matching_date(tonumber(r.ts)or 0,s.period,s.date,now)then
            filtered[#filtered+1]=r
        end
    end
    table.sort(filtered,function(a,b)return (a.ts or 0)>(b.ts or 0)end)
    local total=C.trade_totals(filtered)
    imgui.Separator()
    imgui.TextColored(DSP.theme.col('good',1),u('Продажи: '..total.sell_qty..' шт. · '..money(total.sells)))
    imgui.SameLine(0,18)
    imgui.TextColored(DSP.theme.col('accent',1),u('Покупки: '..total.buy_qty..' шт. · '..money(total.buys)))
    if total.approx then faded('~ В некоторых старых записях количество приблизительное')end
    local start=(s.page-1)*60+1
    local finish=math.min(start+59,#filtered)
    local height=math.max(95,imgui.GetContentRegionAvail().y-54)
    if imgui.BeginChild('##mhjournal294_table',imgui.ImVec2(-1,height),true)then
        local sizes=columns(math.max(610,imgui.GetWindowContentRegionWidth()))
        if #filtered==0 then faded('История сделок пуста.')end
        for i=start,finish do
            local e=filtered[i]
            if e then row(e,sizes)end
        end
        imgui.Columns(1)
        if DSP.mobile and DSP.mobile.touch_scroll then
            DSP.mobile.touch_scroll(imgui.GetIO(),'mhjournal294')
        end
    end
    imgui.EndChild()
    page_nav(s,#filtered)
end
return true
      end
      local ok_module,why_module=pcall(_v294_mh_journal_screen)
      if not ok_module then error('_v294_mh_journal_screen: '..tostring(why_module))end
    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka v2.9.4 install error: '..tostring(err))end
      return false
    end
    DSP._v294_installed=true
    DSP.version='2.9.4'
    DSP.active_ui_build='2.9.4'
    if DSP.flog then DSP.flog('Palatka v2.9.4 Market Helper UX installed')end
    return true
  end
  -- v2.9.5: Market Helper UX, touch scrolling, completed arbitrage flow, journal and statistics.
  local function install_v295()
    local parent_ok=install_v294()
    if not parent_ok then return false end
    if DSP._v295_installed then DSP.version='2.9.5';return true end
    local ok,err=pcall(function()
      local function _v295_storage_render_cache()
-- v2.9.5: avoid re-evaluating every stored trunk on every ImGui frame.
-- No data is discarded; a short expiry and market/snapshot changes invalidate.
local S=DSP.storage
if not S or S._render_cache_v295 then return true end
S._render_cache_v295=true
local base_evaluate=S.evaluate
local base_search=S.search_library
local values=setmetatable({},{__mode='k'})
local searches={}
local last_bucket=-1
local function generation()
    local state=DSP.market and DSP.market.state or{}
    local clock=os.time()
    local bucket=math.floor(clock/2)
    if last_bucket~=bucket then
        values=setmetatable({},{__mode='k'})
        searches={}
        last_bucket=bucket
    end
    return tostring(bucket)..':'..tostring(state.sid or 0)..':'..
        tostring(state.version or 0)..':'..tostring(S.snapshots)
end
function S.evaluate(snapshot,lookup)
    if lookup~=nil or type(snapshot)~='table' then return base_evaluate(snapshot,lookup)end
    local key=generation()..':'..tostring(snapshot.rows)..':'..
        tostring(snapshot.manual_prices)..':'..tostring(#(snapshot.rows or{}))
    local c=values[snapshot]
    if c and c.key==key then return c.result end
    local result=base_evaluate(snapshot)
    values[snapshot]={key=key,result=result}
    return result
end
if type(base_search)=='function' then
    function S.search_library(query,lookup)
        if lookup~=nil then return base_search(query,lookup)end
        local key=generation()..':'..tostring(query or'')
        local item=searches[key]
        if item then return item end
        local result=base_search(query)
        searches[key]=result
        return result
    end
end
return true
      end
      local ok_module,why_module=pcall(_v295_storage_render_cache)
      if not ok_module then error('_v295_storage_render_cache: '..tostring(why_module))end
      local function _v295_stats_render_cache()
-- v2.9.5: skip full inventory signature/loot reconciliation on every stats frame.
local C=DSP.craglog
if not C or C._stats_render_cache_v295 then return true end
C._stats_render_cache_v295=true
local original=C.drop_sales_stats
if type(original)~='function' then return true end
local cache={}
function C.drop_sales_stats(period,query)
    local a=DSP.auto or{}
    local inv=a.inv or{}
    local key=table.concat({
        tostring(period or'day'),tostring(query or''),
        tostring(C.history_revision or 0),tostring(C.visibility_revision or 0),
        tostring(DSP.logs and DSP.logs.revision or 0),
        tostring(DSP.rewards and DSP.rewards.sequence or 0),
        tostring(inv),tostring(#inv),tostring(a.inv_status or''),
        tostring(a.scanning),tostring(math.floor(os.time()/2))
    },'|')
    if cache.key==key then return cache.result end
    local result=original(period,query)
    cache={key=key,result=result}
    return result
end
return true
      end
      local ok_module,why_module=pcall(_v295_stats_render_cache)
      if not ok_module then error('_v295_stats_render_cache: '..tostring(why_module))end
      local function _v295_journal_render_cache()
-- v2.9.5: cached Market Helper journal; never rebuild/filter/sort full history every render frame.
-- Layout and filtering follow the user-provided Market_Helper(1).lua trade log.
local C,V=DSP.craglog,DSP.ui22
if C._mh_journal_screen_v295 then return true end
C._mh_journal_screen_v295=true
C._mh_journal_screen_v294=true
local function u(s)return DSP.utf8(tostring(s or''))end
local function text(s)imgui.Text(u(s))end
local function faded(s)imgui.TextDisabled(u(s))end
local function money(n)return DSP.money(math.floor(tonumber(n)or 0))end
local function button(s,id,w,active)
    return V.button(s,'mhjournal294_'..id,w,active,false,34)
end
local function state()
    DSP.settings.journal_mh=DSP.settings.journal_mh or {period='day',side='all',page=1,date=''}
    local s=DSP.settings.journal_mh
    if not ({day=true,week=true,month=true,all=true,date=true})[s.period] then s.period='day' end
    if not ({all=true,sell=true,buy=true})[s.side] then s.side='all' end
    s.page=math.max(1,math.floor(tonumber(s.page)or 1))
    return s
end
local function persist()
    if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
    elseif DSP.save_settings then DSP.save_settings()end
end
local function select_period(s,period)
    if s.period~=period then s.period=period;s.page=1;persist()end
end
local function matching_date(ts,period,spec,now)
    if period=='all' then return true end
    if period=='date' then return os.date('%Y-%m-%d',ts)==spec end
    if period=='day' then return os.date('%Y-%m-%d',ts)==os.date('%Y-%m-%d',now)end
    local delta=period=='week' and 7*86400 or 30*86400
    return ts>=now-delta and ts<=now
end
local function available_dates(rows)
    local seen,dates={},{}
    for _,r in ipairs(rows)do
        if (r.ts or 0)>0 then
            local day=os.date('%Y-%m-%d',r.ts)
            if not seen[day] then dates[#dates+1]=day;seen[day]=true end
        end
    end
    table.sort(dates,function(a,b)return a>b end)
    return dates
end
-- Events are append-only; trade/history revisions invalidate immediately.
-- The ten-second bucket also detects external file imports without blocking every frame.
local view_cache={}
local function view_for(query,s)
    local clock=os.time()
    local signature=table.concat({
        tostring(query or ''),s.period,s.date or '',s.side,
        tostring(C.history_revision or 0),tostring(C.visibility_revision or 0),
        tostring(DSP.logs and DSP.logs.revision or 0),
        tostring(DSP.rewards and DSP.rewards.sequence or 0),
        tostring(math.floor(clock/10)),
    },'|')
    if view_cache.signature==signature then
        return view_cache.all,view_cache.filtered,view_cache.total,view_cache.dates
    end
    local all=C.trade_rows('all',query or'',s.side)
    local filtered={}
    for _,r in ipairs(all)do
        if matching_date(tonumber(r.ts)or 0,s.period,s.date,clock)then
            filtered[#filtered+1]=r
        end
    end
    table.sort(filtered,function(a,b)return (a.ts or 0)>(b.ts or 0)end)
    local total=C.trade_totals(filtered)
    local dates=available_dates(all)
    view_cache={signature=signature,all=all,filtered=filtered,total=total,dates=dates}
    return all,filtered,total,dates
end
local function cell(s,width,tip)
    local str=tostring(s or'')
    local shown=V.fit and V.fit(str,math.max(25,width-7)) or str
    text(shown)
    if tip and shown~=str and imgui.IsItemHovered and imgui.IsItemHovered() then
        imgui.SetTooltip(u(str))
    end
    imgui.NextColumn()
end
local function columns(w)
    -- The same six columns as the Market Helper "Сделки" table.
    local ratios={.155,.265,.075,.155,.14,.21}
    local sizes={}
    for i,r in ipairs(ratios)do sizes[i]=math.max(43,math.floor(w*r))end
    imgui.Columns(6,'##mhjournal294_columns',false)
    for i=1,6 do imgui.SetColumnWidth(i-1,sizes[i])end
    faded('Дата');imgui.NextColumn()
    faded('Товар');imgui.NextColumn()
    faded('Кол.');imgui.NextColumn()
    faded('Цена $');imgui.NextColumn()
    faded('Тип');imgui.NextColumn()
    faded('Ник');imgui.NextColumn()
    imgui.Separator()
    return sizes
end
local function row(e,sizes)
    local stamp=(e.ts and e.ts>0)and os.date('%d.%m %H:%M',e.ts)or'—'
    cell(stamp,sizes[1],true)
    cell(e.name or'?',sizes[2],true)
    cell(tostring(e.qty or 1)..(e.qty_exact==false and'~'or''),sizes[3])
    local price=tonumber(e.amount)or 0
    -- Palatka receipts already store the actual FULL transaction amount.
    -- Do not accidentally multiply by quantity a second time.
    cell('$'..money(price):gsub('^%$', ''),sizes[4],true)
    if e.kind=='sell' then
        imgui.TextColored(DSP.theme.col('good',1),u('Продажа'))
    else
        imgui.TextColored(DSP.theme.col('accent',1),u('Покупка'))
    end
    imgui.NextColumn()
    cell(e.partner and e.partner~='' and e.partner or'—',sizes[6],true)
end
local function page_nav(s,count)
    local count_pages=math.max(1,math.ceil(count/60))
    s.page=math.max(1,math.min(count_pages,s.page))
    local width=math.max(39,math.min(55,imgui.GetContentRegionAvail().x/7))
    if button('<<','first',width)then s.page=1;persist()end
    imgui.SameLine(0,4)
    if button('<','back',width)then s.page=math.max(1,s.page-1);persist()end
    imgui.SameLine(0,8)
    faded('Стр. '..s.page..'/'..count_pages..' ('..count..')')
    imgui.SameLine(0,8)
    if button('>','next',width)then s.page=math.min(count_pages,s.page+1);persist()end
    imgui.SameLine(0,4)
    if button('>>','last',width)then s.page=count_pages;persist()end
end

-- The original floating button/pin/minimize window is deliberately removed.
-- Data collection by C.log_trade/C.log_market continues unchanged.
function C.draw() end
if DSP.settings.craglog then DSP.settings.craglog.open=false end

function V.journal()
    local s=state()
    V.heading('Журнал сделок')
    local avail=imgui.GetContentRegionAvail().x
    local labels={{'all','Все'},{'day','Сегодня'},{'week','Неделя'},
                  {'month','Месяц'},{'date','Дата'}}
    local width=math.max(54,(avail-24)/5)
    for i,p in ipairs(labels)do
        if button(p[2],'period_'..p[1],width,s.period==p[1])then
            select_period(s,p[1])
            if p[1]=='date' then imgui.OpenPopup('##mhjournal294_dates')end
        end
        if i<#labels then imgui.SameLine(0,6)end
    end
    local query,edited=V.search('mhjournal294_search','Поиск товара / ника',-1)
    if edited then s.page=1 end
    local side_width=math.max(73,(imgui.GetContentRegionAvail().x-12)/3)
    for i,p in ipairs({{'all','Все сделки'},{'sell','Продажи'},{'buy','Покупки'}})do
        if button(p[2],'side_'..p[1],side_width,s.side==p[1])then
            s.side=p[1];s.page=1;persist()
        end
        if i<3 then imgui.SameLine(0,6)end
    end
    -- A single cached view is shared by the filter bar, date picker, totals and table.
    local all,filtered,total,dates=view_for(query,s)
    if imgui.BeginPopup('##mhjournal294_dates')then
        faded('Выбери дату')
        for _,date in ipairs(dates)do
            local display=date:sub(9,10)..'.'..date:sub(6,7)..'.'..date:sub(1,4)
            if imgui.Selectable(display..'##'..date,s.date==date)then
                s.date=date;s.period='date';s.page=1;persist();imgui.CloseCurrentPopup()
            end
        end
        imgui.EndPopup()
    end
    if s.period=='date' then
        if s.date=='' then faded('Дата не выбрана')
        else faded('Дата: '..s.date:sub(9,10)..'.'..s.date:sub(6,7)..'.'..s.date:sub(1,4))end
    end

    imgui.Separator()
    imgui.TextColored(DSP.theme.col('good',1),u('Продажи: '..total.sell_qty..' шт. · '..money(total.sells)))
    imgui.SameLine(0,18)
    imgui.TextColored(DSP.theme.col('accent',1),u('Покупки: '..total.buy_qty..' шт. · '..money(total.buys)))
    if total.approx then faded('~ В некоторых старых записях количество приблизительное')end
    local start=(s.page-1)*60+1
    local finish=math.min(start+59,#filtered)
    local height=math.max(95,imgui.GetContentRegionAvail().y-54)
    if imgui.BeginChild('##mhjournal294_table',imgui.ImVec2(-1,height),true)then
        local sizes=columns(math.max(610,imgui.GetWindowContentRegionWidth()))
        if #filtered==0 then faded('История сделок пуста.')end
        for i=start,finish do
            local e=filtered[i]
            if e then row(e,sizes)end
        end
        imgui.Columns(1)
        if DSP.mobile and DSP.mobile.touch_scroll then
            DSP.mobile.touch_scroll(imgui.GetIO(),'mhjournal294')
        end
    end
    imgui.EndChild()
    page_nav(s,#filtered)
end
return true
      end
      local ok_module,why_module=pcall(_v295_journal_render_cache)
      if not ok_module then error('_v295_journal_render_cache: '..tostring(why_module))end
    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka v2.9.5 install error: '..tostring(err))end
      return false
    end
    DSP._v295_installed=true
    DSP.version='2.9.5'
    DSP.active_ui_build='2.9.5'
    if DSP.flog then DSP.flog('Palatka v2.9.5 Market Helper UX installed')end
    return true
  end
  -- v2.9.6: Market Helper UX, touch scrolling, completed arbitrage flow, journal and statistics.
  local function install_v296()
    local parent_ok=install_v295()
    if not parent_ok then return false end
    if DSP._v296_installed then DSP.version='2.9.6';return true end
    local ok,err=pcall(function()
      local function _v296_reconnect()
-- Palatka AI 2.9.6: bounded, opt-in reconnect + exact observed dialog spawn.
-- No credential storage, CEF spoofing, bypass of kicks/bans, or endless retry storms.
DSP.reconnect=DSP.reconnect or {}
local R=DSP.reconnect
if R._v296 then return true end
R._v296=true
local function now()return os.time()end
local function num(v,lo,hi,default)
    v=tonumber(v)
    if not v or v~=v then v=default end
    return math.floor(math.max(lo,math.min(hi,v)))
end
local defaults={
    enabled=false, on_lost=true, on_closed=false, on_rejected=false,
    initial_delay=8, min_delay=12, max_delay=150, jitter=4,
    max_attempts=8, connect_timeout=55, stable_seconds=5,
    spawn_enabled=false, spawn_delay=2, profiles={}
}
local keys={
    enabled=true,on_lost=true,on_closed=true,on_rejected=true,spawn_enabled=true
}
local limits={
    initial_delay={3,180}, min_delay={8,300}, max_delay={15,900},
    jitter={0,30},max_attempts={1,30},connect_timeout={30,180},
    stable_seconds={2,30},spawn_delay={1,15}
}
function R.config()
    if type(DSP.settings.reconnect)~='table' then DSP.settings.reconnect={}end
    local c=DSP.settings.reconnect
    for k,v in pairs(defaults)do
        if c[k]==nil then
            if type(v)=='table' then c[k]={}else c[k]=v end
        end
    end
    if type(c.profiles)~='table' then c.profiles={}end
    for k,l in pairs(limits)do c[k]=num(c[k],l[1],l[2],defaults[k])end
    if c.max_delay<c.min_delay then c.max_delay=c.min_delay end
    for k in pairs(keys)do c[k]=c[k]==true end
    return c
end
local function persist()
    if type(DSP.save_settings)=='function' then
        local ok,why=DSP.save_settings()
        if not ok then return false,tostring(why or'Cannot save settings')end
    end
    return true
end
function R.set(key,value)
    local c=R.config()
    if not keys[key] and not limits[key]then return false,'Unknown setting'end
    local prev=c[key]
    if keys[key]then value=value==true else
        local l=limits[key];value=num(value,l[1],l[2],defaults[key])
    end
    c[key]=value
    if c.max_delay<c.min_delay then c.max_delay=c.min_delay end
    local ok,why=persist()
    if not ok then c[key]=prev;return false,why end
    if key=='enabled' and not value then R.stop('Auto reconnect switched off')end
    return true
end
local function clean(s)
    s=tostring(s or''):gsub('{[%x]+}',''):gsub('%c',' '):gsub('%s+',' ')
    s=s:gsub('^%s+',''):gsub('%s+$','')
    return s
end
local function normalize(s)
    s=clean(s)
    return type(DSP.lower)=='function' and DSP.lower(s)or string.lower(s)
end
local function address(host,port)
    host=type(host)=='string' and host or ''
    port=tonumber(port)
    if host=='' or host:find('[%s/@]') or not port or port<1 or port>65535 then return nil end
    return host,math.floor(port)
end
function R.remember_address()
    if type(sampGetCurrentServerAddress)~='function' then return false end
    local ok,host,port=pcall(sampGetCurrentServerAddress)
    if not ok then return false end
    host,port=address(host,port)
    if not host then return false end
    local old=R.server_key()
    R.host,R.port=host,port
    if old and old~=R.server_key()then
        R.options={}
        R.dialog_id=nil
        R.spawn_pending=nil
    end
    return true
end
function R.server_key()
    return R.host and R.port and(R.host..':'..R.port)or nil
end
function R.profile()
    local key=R.server_key()
    if not key then return nil end
    local c=R.config()
    if type(c.profiles[key])~='table'then c.profiles[key]={}end
    return c.profiles[key]
end
function R.select_spawn(label)
    local p=R.profile()
    if not p then return false,'Unknown server: connect first'end
    if label~=nil and type(label)~='string' then return false,'Invalid spawn label'end
    local found=label==nil
    for _,o in ipairs(R.options or{})do
        if label and o.label==label then found=true;break end
    end
    if not found then return false,'Spawn was not observed in the game dialog'end
    local old=p.spawn_label
    p.spawn_label=label
    local ok,why=persist()
    if not ok then p.spawn_label=old;return false,why end
    return true
end
R.state=R.state or'idle'
R.attempts=R.attempts or 0
R.status=R.status or'Idle'
R.next_at=R.next_at or 0
R.last_reason=R.last_reason or''
R.options=R.options or{}
local function report(s)
    R.status=tostring(s)
    if DSP.flog then DSP.flog('RECONNECT: '..R.status)end
end
function R.stop(reason)
    R.state='idle';R.next_at=0;R.started_at=nil
    R.attempts=0;R.spawn_pending=nil;R.awaiting_input=false
    R.last_reason=tostring(reason or'Cancelled')
    R.status=R.last_reason
    return true
end
local function blocked(s)
    s=normalize(s)
    for _,part in ipairs({
        'banned','you are banned','account blocked','captcha','wrong password','invalid password',
        'kicked','you are kicked','вы забан','аккаунт заблокирован','капч','неверный пароль',
        'неправильный пароль','вы были кикнуты','отказ в авторизации',
    })do
        if s:find(part,1,true)then return true end
    end
    return false
end
function R.on_message(s)
    if blocked(s)then
        R.stop('Authorization, ban or kick: manual action required')
        R.blocked=true
    end
end
local function interval(attempts)
    local c=R.config()
    local delay=c.min_delay*math.pow(2,math.max(0,attempts-1))
    delay=math.min(c.max_delay,delay)
    return math.floor(delay+math.random(0,c.jitter))
end
local function queue(reason,at)
    local c=R.config()
    if R.blocked then return false,'Blocked by authentication or kick'end
    if not R.host then R.remember_address()end
    if not R.host and type(sampProcessChatInput)~='function' and
        type(sampSendChat)~='function' then
        return false,'No supported reconnect command or server address'
    end
    if R.attempts>=c.max_attempts then
        R.stop('Attempt limit reached');return false,'Attempt limit reached'
    end
    R.state='scheduled'
    R.started_at=nil
    R.next_at=(at or now())+(R.attempts==0 and c.initial_delay or interval(R.attempts))
    R.status='Waiting for next attempt'
    R.last_reason=tostring(reason or'Disconnected')
    return true
end
function R.disconnected(kind,reason,at)
    kind=tostring(kind or'')
    if R.state=='scheduled' then return true,'Already scheduled'end
    local c=R.config()
    local allowed=(kind=='lost' and c.on_lost)or(kind=='closed'and c.on_closed)
        or(kind=='rejected'and c.on_rejected)
    R.last_reason=tostring(reason or kind)
    if blocked(R.last_reason)then
        R.on_message(R.last_reason)
        return false,'Authentication or kick'
    end
    if not c.enabled or not allowed then
        R.status='Disconnected; automatic retry disabled for '..kind
        return false,'Disabled'
    end
    return queue(kind,at)
end
function R.manual(at)
    if R.state=='connecting' or R.state=='scheduled'then
        return false,'Reconnect is already running'
    end
    R.blocked=false
    R.attempts=0
    R.awaiting_input=false
    if not R.host then R.remember_address()end
    if not R.host and type(sampProcessChatInput)~='function' and
        type(sampSendChat)~='function' then
        return false,'No supported reconnect command or server address'
    end
    R.state='scheduled'
    R.next_at=at or now()
    R.status='Manual reconnect requested'
    return true
end
function R.connected(at)
    R.state='idle'
    R.attempts=0
    R.next_at=0
    R.started_at=nil
    R.awaiting_input=false
    R.blocked=false
    R.status='Connected'
    R.last_success=at or now()
    R.remember_address()
end
-- Connect uses an advertised MoonLoader/MonetLoader-compatible API if available.
-- Never call arbitrary RakNet disconnect RPCs or modify game memory.
local function connect()
    -- Arizona Mobile officially exposes /reconnect in the game client.
    -- Prefer the chat-input processor so client-side commands execute locally.
    if type(sampProcessChatInput)=='function' then
        local ok,result=pcall(sampProcessChatInput,'/reconnect')
        if ok and result~=false then return true end
    end
    -- Some MonetLoader builds expose only SAMP's normal chat dispatch.
    if type(sampSendChat)=='function' then
        local ok,result=pcall(sampSendChat,'/reconnect')
        if ok and result~=false then return true end
    end
    if type(sampConnectToServer)=='function' and R.host and R.port then
        local ok,result=pcall(sampConnectToServer,R.host,R.port)
        if ok and result~=false then return true end
    end
    return false,'No supported reconnect API in this MonetLoader build'
end
function R.tick(at)
    at=at or now()
    if type(sampIsLocalPlayerSpawned)=='function' then
        local ok,spawned=pcall(sampIsLocalPlayerSpawned)
        if ok and spawned then
            if R.state=='connecting'then R.connected(at)end
            if not R.last_seen_at or at-R.last_seen_at>=15 then R.last_seen_at=at;R.remember_address()end
        end
    end
    local pending=R.spawn_pending
    if pending and at>=pending.at then
        R.spawn_pending=nil
        local still=true
        if type(sampIsDialogActive)=='function' then
            local ok,val=pcall(sampIsDialogActive)
            still=ok and not not val
        end
        if still and type(sampGetCurrentDialogId)=='function' then
            local ok,id=pcall(sampGetCurrentDialogId)
            still=ok and tonumber(id)==pending.dialog_id
        end
        if still and type(sampSendDialogResponse)=='function' then
            local ok,result=pcall(sampSendDialogResponse,pending.dialog_id,1,pending.index,'')
            if ok and result~=false then R.status='Spawn choice sent: '..pending.label
            else R.status='Could not submit spawn dialog automatically'end
        end
    end
    if R.state=='idle' or R.awaiting_input then return false end
    local c=R.config()
    if R.state=='connecting' then
        if at-(R.started_at or at)>=c.connect_timeout then
            return queue('Connection timeout',at)
        end
        return false
    end
    if R.state~='scheduled' or at<R.next_at then return false end
    if R.attempts>=c.max_attempts then
        R.stop('Attempt limit reached');return false
    end
    R.attempts=R.attempts+1
    local ok,why=connect()
    if not ok then
        R.status='Reconnect API unavailable'
        R.state='idle'
        R.last_error=tostring(why or'Unknown connection error')
        return false
    end
    R.state='connecting'
    R.started_at=at
    R.status='Connecting: attempt '..R.attempts..' of '..c.max_attempts
    return true
end
-- Exact spawn option matching only. No guessed row index or teleport coordinates.
local function spawn_title(title)
    local s=normalize(title)
    if blocked(s) or s:find('password',1,true) or s:find('парол',1,true)
        or s:find('авторизац',1,true) then return false end
    return s:find('спавн',1,true)~=nil or s:find('spawn',1,true)~=nil
        or s:find('место появлен',1,true)~=nil or s:find('точк появлен',1,true)~=nil
end
function R.observe_dialog(id,style,title,content,at)
    if not R.host then R.remember_address()end
    id=tonumber(id);style=tonumber(style)or-1
    if not id or (style~=2 and style~=4 and style~=5) then
        if R.state=='connecting'then R.awaiting_input=true;R.status='Waiting for player input'end
        return false
    end
    if not spawn_title(title)then
        if R.state=='connecting'then R.awaiting_input=true;R.status='Waiting for player input'end
        return false
    end
    R.awaiting_input=false
    local options,lines={},{}
    for line in tostring(content or''):gmatch('[^\r\n]+')do
        lines[#lines+1]=line
    end
    local offset=style==5 and 1 or 0 -- tablist_headers has a separate header row
    for i=1+offset,#lines do
        local label=clean(lines[i]:match('^([^\t]+)') or lines[i])
        if label~=''then options[#options+1]={index=i-1-offset,label=label}end
    end
    R.options=options;R.dialog_id=id
    R.dialog_seen_at=at or now()
    local c,p=R.config(),R.profile()
    local want=p and p.spawn_label
    if not c.spawn_enabled or not want or want=='' then
        R.status='Spawn list detected: select preferred place in settings'
        return true
    end
    for _,row in ipairs(options)do
        if normalize(row.label)==normalize(want)then
            R.spawn_pending={at=(at or now())+c.spawn_delay,
                dialog_id=id,index=row.index,label=row.label}
            R.status='Exact spawn option found: '..row.label
            return true
        end
    end
    R.status='Saved spawn not found; select manually in game'
    return true
end
function R.install()
    if R.installed then return true end
    R.installed=true
    R.config()
    R.remember_address()
    if type(sampRegisterChatCommand)=='function' then
        pcall(sampRegisterChatCommand,'prc',function(argument)
            argument=tostring(argument or'')
            local ok,why
            if argument=='stop' or argument=='off'then ok=R.stop('Stopped by user')
            elseif argument=='status'then ok=true
            else ok,why=R.manual()end
            if type(sampAddChatMessage)=='function'then
                sampAddChatMessage('[Palatka Reconnect] '..tostring(why or R.status),0x66CC99)
            end
        end)
    end
    local ok,events=pcall(require,'samp.events')
    if ok and type(events)=='table' then
        local function wrap(name,fn)
            local previous=events[name]
            events[name]=function(...)
                local worked,why=pcall(fn,...)
                if not worked and DSP.flog then
                    DSP.flog('RECONNECT event '..name..': '..tostring(why))
                end
                if previous then return previous(...)end
            end
        end
        wrap('onShowDialog',function(id,style,title,button1,button2,content)
            R.observe_dialog(id,style,title,content)
        end)
        wrap('onServerMessage',function(color,text)R.on_message(text)end)
        wrap('onConnectionLost',function(...)R.disconnected('lost','Connection lost')end)
        wrap('onConnectionClosed',function(...)R.disconnected('closed','Connection closed')end)
        wrap('onConnectionRejected',function(...)R.disconnected('rejected','Connection rejected')end)
        wrap('onConnectionAttemptFailed',function(...)R.disconnected('lost','Connection attempt failed')end)
        wrap('onConnectionAccepted',function(...)
            if R.state=='connecting'then
                R.awaiting_input=true
                R.status='Connected to server; waiting for authorization'
            end
        end)
        wrap('onSpawn',function(...)R.connected()end)
        wrap('onSendDialogResponse',function(id,...)
            if tonumber(id)==R.dialog_id then R.spawn_pending=nil end
        end)
    end
    if lua_thread and type(lua_thread.create)=='function' and type(wait)=='function'then
        lua_thread.create(function()
            while true do
                wait(500)
                local worked,why=pcall(R.tick)
                if not worked and DSP.flog and why~=R._last_tick_error then
                    R._last_tick_error=why
                    DSP.flog('RECONNECT worker: '..tostring(why))
                end
            end
        end)
    end
    return true
end
R.install()
return true
      end
      local ok_module,why_module=pcall(_v296_reconnect)
      if not ok_module then error('_v296_reconnect: '..tostring(why_module))end
      local function _v296_reconnect_ui()
-- Palatka AI 2.9.6: touch-friendly reconnect management.
-- Settings button -> dedicated workspace screen; no always-on overlay.
local R,V,M=DSP.reconnect,DSP.ui22,DSP.mobile
if not R or not V or V._reconnect_ui_v296 then return true end
V._reconnect_ui_v296=true
local old_tools=V.tools
local function b(label,id,width,active)
    return V.button(label,'rec296_'..id,width,active,false,39)
end
local function update(key,value)
    local ok,why=R.set(key,value)
    if ok then V.reconnect_error=nil else V.reconnect_error=tostring(why)end
end
local function toggle(key,label)
    local c=R.config()
    if b((c[key]and '[x] 'or'[ ] ')..label,'toggle_'..key,-1,c[key])then
        update(key,not c[key])
    end
end
local function number(key,label,step,unit)
    local c=R.config()
    V.muted(label)
    local x=math.min(80,math.max(44,imgui.GetContentRegionAvail().x/4))
    if b('-','dec_'..key,x)then update(key,c[key]-step)end
    V.inline(4,x)
    V.text(tostring(c[key])..' '..(unit or'с'))
    V.inline(5,x)
    if b('+','inc_'..key,x)then update(key,c[key]+step)end
end
local function header()
    V.heading('Реконнект / Спавн',function()
        if b('Назад','go_back',105)then V.set_screen('settings')end
    end,127)
    local c=R.config()
    V.muted('Сервер: '..tostring(R.server_key()or'не определён'))
    V.muted('Состояние: '..tostring(R.status or'выключен'))
    if V.reconnect_error then V.red(V.reconnect_error)end
    if b('Реконнект сейчас','manual',math.min(220,imgui.GetContentRegionAvail().x))then
        local ok,why=R.manual()
        if not ok then V.reconnect_error=tostring(why)else V.reconnect_error=nil end
    end
    V.inline(5,160)
    if b('Остановить','stop',150)then R.stop('Отменено пользователем')end
end
local function general()
    local c=R.config()
    toggle('enabled','Авто-реконнект (по умолчанию выключен)')
    toggle('on_lost','После потери соединения / тайм-аута')
    toggle('on_closed','После закрытия соединения сервером')
    toggle('on_rejected','После отказа в подключении')
    V.muted('При бане, кике, пароле и капче автоматизация останавливается.')
    V.muted('Если игра полностью закрылась, Lua не сможет запустить её заново.')
    V.muted('Периоды ожидания:')
    number('initial_delay','Первое подключение после обрыва',1)
    number('min_delay','Начальная задержка повторов',2)
    number('max_delay','Максимальная пауза (экспоненциально)',10)
    number('jitter','Случайная добавка к паузе',1)
    number('max_attempts','Ограничение числа попыток',1,'раз')
    number('connect_timeout','Тайм-аут подключения',5)
end
local function spawns()
    local c=R.config()
    toggle('spawn_enabled','Автоматически выбрать сохранённый спавн')
    number('spawn_delay','Пауза до ответа на диалог',1)
    V.muted('Режим точного выбора: только реально обнаруженные пункты SA-MP.')
    V.muted('CEF-окна нельзя безопасно выбирать без подтверждённого API.')
    V.muted('Сначала войди в игру и открой меню выбора спавна.')
    local p=R.profile()
    local selected=p and p.spawn_label or nil
    V.muted('Сохранено для этого сервера: '..tostring(selected or'вручную'))
    if b('Сбросить выбор','clear_spawn',205)then
        local ok,why=R.select_spawn(nil)
        if not ok then V.reconnect_error=tostring(why)else V.reconnect_error=nil end
    end
    local opts=R.options or{}
    if not R.server_key()then
        V.muted('Адрес сервера не определён: сначала подключись в лаунчере.')
        return
    end
    if #opts==0 then
        V.muted('Пункты пока не получены из SA-MP-диалога.')
        return
    end
    V.muted('Пункты из последнего меню спавна:')
    for i,row in ipairs(opts)do
        if b((selected==row.label and'[x] 'or'[ ] ')..
            tostring(row.label),'spawn_'..i,-1,selected==row.label)then
            local ok,why=R.select_spawn(row.label)
            if not ok then V.reconnect_error=tostring(why)else V.reconnect_error=nil end
        end
    end
end
local function diag()
    local c=R.config()
    V.muted('Статус: '..tostring(R.status or'Ожидание'))
    V.muted('Последняя причина: '..tostring(R.last_reason or'—'))
    V.muted('Попытки: '..tostring(R.attempts or 0)..'/'..tostring(c.max_attempts))
    if R.state=='scheduled'then
        V.muted('Следующая попытка через '..math.max(0,(R.next_at or 0)-os.time())..' с')
    end
    V.muted('Клиентский /reconnect: '..((type(sampProcessChatInput)=='function'
        or type(sampSendChat)=='function')and'доступен' or'не определён'))
    V.muted('SA-MP-диалоги: '..tostring(#(R.options or{}))..' пунктов')
    if R.dialog_id then V.muted('ID последнего меню спавна: '..tostring(R.dialog_id))end
    V.muted('Команды: /prc (вручную), /prc status, /prc stop')
    V.muted('Ник и пароль не хранятся. Авторизацию проходишь в игре.')
    V.muted('При ошибке игры проверь standalone.log и client.log.')
    if b('Обновить адрес текущего сервера','refresh_server',-1)then
        if not R.remember_address()then
            V.reconnect_error='Не удалось получить адрес от клиента'
        else V.reconnect_error=nil end
    end
end
V.reconnect_tab=V.reconnect_tab or 1
function R.draw_ui()
    header()
    local pages={{'Основное',general},{'Спавн',spawns},{'Статус',diag}}
    local w=math.max(62,(imgui.GetContentRegionAvail().x-12)/3)
    for i,page in ipairs(pages)do
        if b(page[1],'page_'..i,w,V.reconnect_tab==i)then
            V.reconnect_tab=i
        end
        if i<3 then V.inline(6,w)end
    end
    V.list('reconnect296',function()
        pages[V.reconnect_tab][2]()
    end,{footer=false})
end
function V.tools(screen)
    if screen=='reconnect'then return R.draw_ui()end
    if screen=='settings'then
        local w=imgui.GetContentRegionAvail().x
        if b('Реконнект / выбор спавна','settings_entry',math.min(300,w))then
            V.set_screen('reconnect')
            return
        end
    end
    if old_tools then return old_tools(screen)end
end
return true
      end
      local ok_module,why_module=pcall(_v296_reconnect_ui)
      if not ok_module then error('_v296_reconnect_ui: '..tostring(why_module))end
    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka v2.9.6 install error: '..tostring(err))end
      return false
    end
    DSP._v296_installed=true
    DSP.version='2.9.6'
    DSP.active_ui_build='2.9.6'
    if DSP.flog then DSP.flog('Palatka v2.9.6 Market Helper UX installed')end
    return true
  end
  -- Install settings guard before any other overlay can save preferences.
  local function module_settings_safety()
-- Palatka Settings Safety: protect user preferences on every OTA update.
-- Install after core; do not replace, reset or filter unknown setting keys.
local G = DSP.settings_safety or {}
DSP.settings_safety = G
if not G.installed then
    local path = DSP.settings_path
    local release=tostring(PALATKA_UPDATE_VERSION or DSP.version or 'before_update')
        :gsub('[^%w_%-]','_')
    local original_save = DSP.save_settings

    local function read_all(filename)
        local f=io.open(filename,'rb')
        if not f then return nil end
        local data=f:read('*a')
        f:close()
        return data
    end
    local function valid_json(raw)
        if type(raw)~='string' or #raw==0 then return false end
        local ok,result=pcall(decodeJson,raw)
        return ok and type(result)=='table'
    end
    local function write_bytes(filename,data)
        local f,err=io.open(filename,'wb')
        if not f then return false,tostring(err or 'cannot open') end
        local wrote,e=f:write(data)
        local closed,close_err=f:close()
        if not wrote or not closed then return false,tostring(e or close_err) end
        local copy=read_all(filename)
        if copy~=data then return false,'verification mismatch' end
        return true
    end
    local function backup_valid(source,target)
        local raw=read_all(source)
        if not raw or not valid_json(raw) then return false,'invalid source' end
        local tmp=target..'.tmp'
        local ok,err=write_bytes(tmp,raw)
        if not ok then return false,err end
        -- Moving the last valid backup aside must never delete it.
        local existing=read_all(target)
        if existing and valid_json(existing) then
            local keep=target..'.previous'
            pcall(os.remove,keep)
            local moved= os.rename(target,keep)
            if not moved then pcall(os.remove,tmp);return false,'cannot rotate backup' end
        end
        local renamed,e=os.rename(tmp,target)
        if not renamed then
            pcall(os.remove,tmp)
            if existing and valid_json(existing) then pcall(os.rename,target..'.previous',target) end
            return false,tostring(e or 'cannot store backup')
        end
        return true
    end

    -- Back up the last known-good settings, including fields from future
    -- versions, BEFORE installing new default keys in any subsequent update.
    function G.checkpoint(tag)
        if type(path)~='string' then return false,'settings path missing' end
        local raw=read_all(path)
        if not raw then return true,'no settings yet' end
        if not valid_json(raw) then return false,'settings invalid: no overwrite' end
        local safe=tostring(tag or 'before_update'):gsub('[^%w_%-]','_')
        local snapshot=path..'.checkpoint_'..safe
        if read_all(snapshot) then return true,snapshot end
        local ok,e=write_bytes(snapshot..'.tmp',raw)
        if not ok then return false,e end
        local renamed,err=os.rename(snapshot..'.tmp',snapshot)
        if not renamed then return false,tostring(err or 'checkpoint rename failed') end
        return true,snapshot
    end

    -- File may be corrupt after a crash: NEVER save defaults over it.
    function DSP.save_settings()
        if type(path)~='string' or type(DSP.settings)~='table' then
            return false,'invalid settings state'
        end
        local existing=read_all(path)
        if existing and not valid_json(existing) then
            if DSP.flog then pcall(DSP.flog,'SETTINGS SAFETY: existing JSON corrupt; refusing overwrite') end
            return false,'Existing settings invalid; preserved for recovery'
        end
        local ok,json=pcall(encodeJson,DSP.settings)
        if not ok or not valid_json(json) then return false,'settings encoding invalid' end
        local temp=path..'.safe_new'
        local wrote,err=write_bytes(temp,json)
        if not wrote then return false,err end
        if existing then
            local saved,why=backup_valid(path,path..'.bak')
            if not saved then pcall(os.remove,temp);return false,'backup failed: '..tostring(why) end
            -- Android does not guarantee rename-over-existing.
            local old=path..'.old'
            pcall(os.remove,old)
            local moved,why2=os.rename(path,old)
            if not moved then pcall(os.remove,temp);return false,'cannot move old settings: '..tostring(why2) end
            local placed,why3=os.rename(temp,path)
            if not placed then
                pcall(os.rename,old,path)
                pcall(os.remove,temp)
                return false,'cannot replace settings: '..tostring(why3)
            end
            pcall(os.remove,old)
        else
            local placed,why=os.rename(temp,path)
            if not placed then pcall(os.remove,temp);return false,'cannot install settings: '..tostring(why) end
        end
        return true
    end

    -- Protect the second settings file too: window position, CR button
    -- placement, theme and opacity must survive application updates.
    if type(DSP.ui_state_path)=='string' then
        local ui_path=DSP.ui_state_path
        local ui_raw=read_all(ui_path)
        if ui_raw and valid_json(ui_raw) then
            local checkpoint=ui_path..'.checkpoint_'..release
            if not read_all(checkpoint) then
                local copied=write_bytes(checkpoint..'.tmp',ui_raw)
                if copied then pcall(os.rename,checkpoint..'.tmp',checkpoint) end
            end
        end
        DSP.save_ui_state=function()
            local previous=read_all(ui_path)
            if previous and not valid_json(previous) then
                return false,'Existing UI state corrupt; preserving file'
            end
            local pack={
                cr_pos=DSP.settings.cr_pos or {x=28,y=215},
                screen=DSP.settings.screen or 'palatka',
                theme=(DSP.theme and DSP.theme.current) or DSP.settings.theme,
                opacity=(DSP.theme and DSP.theme.opacity) or DSP.settings.opacity,
                saved_at=os.time()
            }
            local encoded,body=pcall(encodeJson,pack)
            if not encoded or not valid_json(body) then return false,'Invalid UI state JSON' end
            local temp=ui_path..'.safe_new'
            local wrote,err=write_bytes(temp,body)
            if not wrote then return false,err end
            if previous then
                local backed,why=backup_valid(ui_path,ui_path..'.bak')
                if not backed then pcall(os.remove,temp);return false,'UI backup failed: '..tostring(why) end
                local old=ui_path..'.old'
                pcall(os.remove,old)
                local moved,why2=os.rename(ui_path,old)
                if not moved then pcall(os.remove,temp);return false,'UI move failed: '..tostring(why2) end
                local renamed,why3=os.rename(temp,ui_path)
                if not renamed then
                    pcall(os.rename,old,ui_path)
                    pcall(os.remove,temp)
                    return false,'UI write failed: '..tostring(why3)
                end
                pcall(os.remove,old)
            else
                local renamed,why=os.rename(temp,ui_path)
                if not renamed then pcall(os.remove,temp);return false,tostring(why) end
            end
            return true
        end
    end

    -- Old files can contain a richer schema than the current build.
    -- Do not enumerate or discard unknown settings during an update.
    G.installed=true
    G.original_save=original_save
    local ok,detail=G.checkpoint(release)
    if DSP.flog then
        pcall(DSP.flog,'SETTINGS SAFETY checkpoint: '..tostring(ok)..' '..tostring(detail))
    end
end

  end
  module_settings_safety()

  local function module_storage()
-- Read-only inventory analysis for classic SA-MP cabinet/trunk dialogs.
-- Does not issue game commands, move items, infer missing counts or inspect memory.
DSP.storage = DSP.storage or {}
local S = DSP.storage
S.snapshots = S.snapshots or (DSP.settings and DSP.settings.storage_snapshots) or {}
S.last_error = nil
S.max_rows = 180
S.max_saved = 20

local function normal(s)
    s = DSP.clean_text(tostring(s or ''))
    return s:gsub('\t',' '):gsub(' +',' ')
end
local function int(s)
    if not s then return nil end
    s=tostring(s):gsub('[%s%.%,]','')
    if not s:match('^%d+$') then return nil end
    local n=tonumber(s)
    if not n or n<1 or n>2000000000 or n%1~=0 then return nil end
    return n
end
local function kind_of(title)
    local s=DSP.lower(normal(title))
    if s:find('\232\237\226\229\237\242\224\240\252',1,true) or s:find('\200\237\226\229\237\242\224\240\252',1,true) then return 'inventory' end
    if s:find('\225\224\227\224\230\237\232\234',1,true) or s:find('\193\224\227\224\230\237\232\234',1,true) then return 'trunk' end
    if s:find('\248\234\224\244',1,true) or s:find('\216\234\224\244',1,true) then return 'cabinet' end
    if s:find('\241\234\235\224\228',1,true) or s:find('\209\234\235\224\228',1,true) or s:find('\245\240\224\237\232\235\232\249\229',1,true) or s:find('\213\240\224\237\232\235\232\249\229',1,true) then return 'warehouse' end
    return nil
end
S.kind_of = kind_of
function S.parse_line(raw)
    local s=normal(raw)
    -- Strip only UI list position, not arbitrary numeric prefixes or item IDs.
    s=s:gsub('^%s*%d+[%.%)]%s+','')
    if s=='' or #s>320 then return nil end
    local name,qty
    -- An explicit unit is mandatory: 'slot #1' is NOT one item.
    name,qty=s:match('^(.-)%s*%(%s*([%d%., ]+)%s*\248\242%.?%s*%)%s*$')
    if not name then name,qty=s:match('^(.-)%s*%[%s*([%d%., ]+)%s*\248\242%.?%s*%]%s*$') end
    if not name then name,qty=s:match('^(.-)%s*[%-%\151:]%s*([%d%., ]+)%s*\248\242%.?%s*$')end
    if not name then name,qty=s:match('^(.-)%s+[x\245X\213]%s*([%d%., ]+)%s*$')end
    if not name then name,qty=s:match('^(.-)%s*%([x\245X\213]%s*([%d%., ]+)%)%s*$')end
    if not name then
        -- Legitimate unlabeled line: show unknown count, never silently x1.
        if s:find('%$',1,true) or s:find('\194\251\225\229\240\232\242\229',1,true) or s:find('\205\224\231\224\228',1,true)
            or DSP.lower(s):find('\226\236\229\241\242\232\236\238\241\242\252',1,true) or s:match('^[-=]+$')
            or s:find('\206\242\234\240\251\242\252',1,true) or s:find('\199\224\234\240\251\242\252',1,true)
            or s:find('\199\224\225\240\224\242\252',1,true) or s:find('\207\238\235\238\230\232\242\252',1,true) then return nil end
        name=s
    end
    name=DSP.trim(name or '')
    if name=='' or #name>125 then return nil end
    if name:match('^%d+$') then return nil end
    local count=int(qty)
    -- Explicitly malformed quantities are not accepted as reliable numeric values.
    return {name=name,qty=count,quantity_confirmed=count~=nil,raw=raw}
end
function S.parse_text(kind,title,text,ts)
    if not S.kind_of(title) or S.kind_of(title)~=kind then return nil,'not a container dialog' end
    if type(text)~='string' then return nil,'not text' end
    local rows,by_name={},{}
    for line in (text..'\n'):gmatch('(.-)\r?\n')do
        if #rows>=S.max_rows then break end
        local r=S.parse_line(line)
        if r then
            local key=DSP.item_key(r.name,0)
            if not by_name[key] then
                rows[#rows+1]=r;by_name[key]=r
            else
                -- Repeated view of the same item in one dialog is ambiguous;
                -- keep separate slots, never fabricate an aggregate count.
                rows[#rows+1]=r
            end
        end
    end
    if #rows==0 then return nil,'no item lines' end
    return {kind=kind,title=normal(title),rows=rows,observed_at=ts or os.time(),
        source='dialog',count_known=0}
end
function S.accept(kind,title,text,ts,source)
    local snap,err=S.parse_text(kind,title,text,ts)
    if not snap then S.last_error=err;return false,err end
    snap.source=source=='manual' and 'manual' or source=='textdraw' and 'textdraw' or 'dialog'
    for _,r in ipairs(snap.rows)do
        if r.qty then snap.count_known=snap.count_known+r.qty end
    end
    local signature=kind..'|'..snap.source..'|'..snap.title..'|'..text
    if S.last_signature==signature and S.last_snapshot and math.abs((ts or os.time())-(S.last_ts or 0))<=3 then
        -- Repeated same dialog callback does not add slots or duplicate snapshots.
        return true,S.last_snapshot
    end
    snap.id=tostring(ts or os.time())..'_'..tostring(#S.snapshots+1)
    snap.server=DSP.market and DSP.market.state and DSP.market.state.sid or nil
    table.insert(S.snapshots,1,snap)
    while #S.snapshots>S.max_saved+1 do table.remove(S.snapshots)end
    S.last_signature=signature;S.last_snapshot=snap;S.last_ts=ts or os.time();S.last_error=nil
    if DSP.settings and DSP.save_settings then
        DSP.settings.storage_snapshots=S.snapshots
        local ok,err=DSP.save_settings()
        if not ok then S.last_error='\205\229 \243\228\224\235\238\241\252 \241\238\245\240\224\237\232\242\252 \241\237\232\236\238\234: '..tostring(err) end
    end
    return true,snap
end
function S.on_dialog(id,style,title,text)
    local kind=kind_of(title)
    if not kind then return false end
    local ok,err=S.accept(kind,title,text)
    if ok then DSP.flog('STORAGE read-only '..kind..' rows='..#S.snapshots[1].rows..' dialog='..tostring(id))
    else DSP.flog('STORAGE unavailable '..tostring(err))end
    return ok
end
local function market_lookup(name,ench)
    local row=DSP.market and DSP.market.row_for and DSP.market.row_for(name,ench or 0)
    if not row then return nil,nil end
    local buy=row.buy and tonumber(row.buy.max)
    local sell=row.sell and tonumber(row.sell.min)
    if buy and buy<=0 then buy=nil end
    if sell and sell<=0 then sell=nil end
    return buy,sell
end
S.market_lookup=market_lookup
function S.item_group_key(row)
    if tonumber(row.id) and tonumber(row.id)>0 then
        return 'id:'..tostring(math.floor(tonumber(row.id)))..':'..tostring(tonumber(row.ench) or 0)
    end
    return 'name:'..DSP.item_key(row.name or '',tonumber(row.ench) or 0)
end
function S.set_manual_price(snapshot, row, amount)
    local n=tonumber(amount)
    if not n or n~=n or n<0 or n>9007199254740991 or n%1~=0 then return false,'invalid price' end
    local found=false
    for _,s in ipairs(S.snapshots or{}) do if s==snapshot then found=true;break end end
    if not found then return false,'stale snapshot' end
    local key=S.item_group_key(row)
    snapshot.manual_prices=snapshot.manual_prices or {}
    local previous=snapshot.manual_prices[key]
    local sid=tostring(snapshot.server or (DSP.market and DSP.market.state and DSP.market.state.sid) or 0)
    DSP.settings.storage_prices=DSP.settings.storage_prices or {}
    DSP.settings.storage_prices[sid]=DSP.settings.storage_prices[sid] or {}
    local global=DSP.settings.storage_prices[sid]
    local old_global=global[key]
    global[key]=n>0 and n or nil
    snapshot.manual_prices[key]=n>0 and n or nil
    if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
    if DSP.save_settings then
        local called,ok,err=pcall(DSP.save_settings)
        if not called or not ok then
            snapshot.manual_prices[key]=previous
            global[key]=old_global
            return false,tostring(err or ok or 'save error')
        end
    end
    S.sort_cache=setmetatable({},{__mode='k'})
    return true
end
function S.set_snapshot_label(snapshot,label)
    if type(label)~='string' then return false,'invalid label' end
    label=DSP.trim(DSP.clean_text(label))
    if #label>66 or label=='' then return false,'name must be 1-66 bytes' end
    -- Live scans are deliberately NOT in S.snapshots. Allow naming only the
    -- current live result; stale objects from previous scans are rejected.
    if snapshot.source=='packet220_trunk' and S.trunk and S.trunk.snapshot==snapshot then
        return S.save_named_trunk(snapshot,label)
    end
    local found=false
    for _,saved in ipairs(S.snapshots or{})do if saved==snapshot then found=true;break end end
    if not found then return false,'stale snapshot' end
    -- The live trunk is disposable by design. Renaming it must create a
    -- persistent library entry, otherwise the next scan would erase the name.
    if snapshot.source=='packet220_trunk' then
        if not S.save_named_trunk then return false,'archive function unavailable' end
        return S.save_named_trunk(snapshot,label)
    end
    local previous=snapshot.title
    snapshot.title=label
    if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
    if DSP.save_settings then
        local called,ok,err=pcall(DSP.save_settings)
        if not called or not ok then snapshot.title=previous;return false,tostring(err or ok or 'save error')end
    end
    return true,snapshot
end
function S.evaluate(snapshot,lookup)
    lookup=lookup or market_lookup
    local res={total_qty=0,known_qty_rows=0,unknown_qty=0,missing_prices=0,
        sell_to_buyers=0,ask_value=0,estimated_rows=0,rows={},cross_server=false}
    local current=DSP.market and DSP.market.state and DSP.market.state.sid
    local wrong_server=snapshot and snapshot.server and current and tonumber(snapshot.server)~=tonumber(current)
    res.cross_server=not not wrong_server
    local by_key={}
    for i,src in ipairs(snapshot and snapshot.rows or{})do
        local key=S.item_group_key(src)
        local row=by_key[key]
        if not row then
            row={key=key,name=src.name,ench=src.ench or 0,id=src.id,qty=0,
                bid=nil,ask=nil,index=i,slots=0,unknown_slots=0}
            by_key[key]=row;res.rows[#res.rows+1]=row
            if not wrong_server then row.bid,row.ask=lookup(src.name,src.ench or 0) end
            local prices=DSP.settings and DSP.settings.storage_prices
            local server=tostring(snapshot.server or (DSP.market and DSP.market.state and DSP.market.state.sid) or 0)
            local shared=prices and prices[server]
            local manual=(snapshot.manual_prices and snapshot.manual_prices[key]) or (shared and shared[key])
            if manual and tonumber(manual) and tonumber(manual)>0 then
                row.bid=tonumber(manual);row.manual_price=true
            end
        end
        row.slots=row.slots+1
        if src.qty then
            row.qty=row.qty+src.qty
            res.total_qty=res.total_qty+src.qty
            res.known_qty_rows=res.known_qty_rows+1
            if row.bid then res.sell_to_buyers=res.sell_to_buyers+row.bid*src.qty;res.estimated_rows=res.estimated_rows+1
            else res.missing_prices=res.missing_prices+1 end
            if row.ask then res.ask_value=res.ask_value+row.ask*src.qty end
        else
            row.unknown_slots=row.unknown_slots+1
            res.unknown_qty=res.unknown_qty+1
        end
    end
    for _,row in ipairs(res.rows) do if row.unknown_slots>0 and row.qty==0 then row.qty=nil end end
    return res
end

S.sort_cache=setmetatable({},{__mode='k'})
function S.sorted(snapshot,mode,lookup)
    if not lookup and snapshot then
        local st=DSP.market and DSP.market.state or {}
        local key=tostring(mode)..'/'..tostring(st.sid)..'/'..tostring(st.version)
        local entry=S.sort_cache[snapshot]
        if entry and entry.key==key then return entry.rows,entry.info end
    end
    local info=S.evaluate(snapshot,lookup)
    local sorted=info.rows
    table.sort(sorted,function(a,b)
        if mode=='category' then
            local function cat(n)
                n=DSP.lower(tostring(n or ''))
                if n:find('\228\240\238\226',1,true) or n:find('\236\229\242\224\235\235',1,true) or n:find('\234\224\236\229\237\252',1,true)
                    or n:find('\235\229\237',1,true) or n:find('\245\235\238\239',1,true) then return 1 end
                if n:find('\235\224\240\229\246',1,true) or n:find('\234\229\233\241',1,true) then return 2 end
                if n:find('\228\229\242\224\235\252 \242\254\237\232\237\227\224',1,true) then return 3 end
                return 4
            end
            if cat(a.name)~=cat(b.name)then return cat(a.name)<cat(b.name)end
        elseif mode=='qty' then
            if (a.qty or -1)~=(b.qty or -1)then return(a.qty or -1)>(b.qty or -1)end
        elseif mode=='value' then
            local av=a.bid and a.qty and a.bid*a.qty or -1
            local bv=b.bid and b.qty and b.bid*b.qty or -1
            if av~=bv then return av>bv end
        elseif mode=='price' then
            if (a.bid or -1)~=(b.bid or -1)then return(a.bid or -1)>(b.bid or -1)end
        end
        return tostring(a.name)<tostring(b.name)
    end)
    if not lookup and snapshot then
        local st=DSP.market and DSP.market.state or {}
        S.sort_cache[snapshot]={key=tostring(mode)..'/'..tostring(st.sid)..'/'..tostring(st.version),rows=sorted,info=info}
    end
    return sorted,info
end

-- Palatka AI v2.2.13 / Packet220 inventory trunk only (type=8).
-- Runs within __mod_47_storage, after the original storage/sorting functions.
-- No packet injection, commands, memory hooks or automatic inventory actions.
S.trunk = S.trunk or {status='idle', received=0, last_error=nil}
local T = S.trunk
local TRUNK_TYPE, TRUNK_SLOTS = 8, 180
local VALID_CAPACITY = {[30]=true,[60]=true,[90]=true,[120]=true,[150]=true,[180]=true}
local PENDING_TIMEOUT = 15       -- seconds to receive the 180-slot full snapshot
-- Partial slot changes are intentionally not applied without vehicle identity.

local function valid_slot(v)
    local n = tonumber(v)
    if n and n % 1 == 0 and n >= 0 and n < TRUNK_SLOTS then return n end
    return nil
end

local function valid_count(v)
    local n = tonumber(v)
    if n and n == n and n >= 0 and n <= 2000000000 and n % 1 == 0 then return n end
    return nil
end

local function sanitized_slot(it)
    if type(it) ~= 'table' then return nil end
    local slot = valid_slot(it.slot)
    if slot == nil then return nil end
    local id = it.item == nil and 0 or tonumber(it.item)
    if not id or id ~= id or id < 0 or id > 2000000000 or id % 1 ~= 0 then return nil end
    local amount = id > 0 and valid_count(it.amount) or 0
    return {slot=slot,item_id=id,qty=amount,
        ench=tonumber(it.enchant) or 0,empty=(id == 0)}
end

local function parse_payload(raw)
    if type(raw) ~= 'string' or #raw == 0 or #raw > 100000 then return nil end
    -- StringCompressor occasionally returns an extra trailing NUL byte.
    raw = raw:gsub('%z+$','')
    local ok, obj = pcall(decodeJson, raw)
    if not ok or type(obj) ~= 'table' or tonumber(obj.type) ~= TRUNK_TYPE
        or type(obj.items) ~= 'table' or #obj.items > TRUNK_SLOTS then return nil end
    local normalized, used = {}, {}
    for _, item in ipairs(obj.items) do
        local sl = sanitized_slot(item)
        if not sl or used[sl.slot] then return nil end
        used[sl.slot] = true
        normalized[#normalized+1] = sl
    end
    local capacity=tonumber(obj.capacity or obj.slotCount or obj.totalSlots)
    if not VALID_CAPACITY[capacity] then capacity=nil end
    return normalized,capacity
end

local function active_snapshot()
    for _, s in ipairs(S.snapshots or {}) do
        if s.source == 'packet220_trunk' and s.kind == 'trunk' then return s end
    end
    return nil
end

local function build_rows(slots, capacity)
    local rows, count, occupied = {}, 0, 0
    for i=0,(capacity or TRUNK_SLOTS)-1 do
        local v = slots[i+1]
        if v and v.item_id and v.item_id > 0 then
            local name = DSP.items and DSP.items.name and DSP.items.name(v.item_id)
                or ('ID:'..tostring(v.item_id))
            if type(name) ~= 'string' or name == '' then name='ID:'..tostring(v.item_id) end
            rows[#rows+1] = {
                slot=i,id=v.item_id,name=name,ench=v.ench or 0,
                qty=v.qty,quantity_confirmed=v.qty ~= nil,
            }
            occupied=occupied+1
            if v.qty then count=count+v.qty end
        end
    end
    return rows,count,occupied
end

local function save_snapshot(slots, source_reason, capacity)
    local ts=os.time()
    capacity=capacity or TRUNK_SLOTS
    local rows, total, occupied = build_rows(slots,capacity)
    local requested_at=T.requested_at
    local update_target_id=T.update_target_id
    local snap={
        id='trunk_live_'..tostring(ts)..'_'..tostring((T.scan_generation or 0)+1),
        kind='trunk',
        -- No persistent vehicle identity in observed packet. This is ALWAYS the last opened trunk.
        title='\207\238\241\235\229\228\237\232\233 \238\242\234\240\251\242\251\233 \225\224\227\224\230\237\232\234',
        source='packet220_trunk', identity_verified=false,
        observed_at=ts, updated_at=ts, server=DSP.market and DSP.market.state and DSP.market.state.sid or nil,
        slots_count=capacity, occupied_slots=occupied,count_known=total,
        rows=rows, slots=slots, update_kind=source_reason,
    }
    -- A scan is IN MEMORY ONLY. A user-named copy is the sole path to the
    -- persistent library. Never write an unnamed scan to storage_snapshots.
    T.snapshot=snap
    T.last_update=ts
    T.status='saved'
    T.received=capacity
    T.occupied=occupied
    T.total=total
    T.last_saved_at=ts
    if requested_at then
        T.last_completed_request_at=ts
        T.requested_at=nil
        T.completed_update_target_id=update_target_id
        T.update_target_id=nil
    end
    T.last_error=nil
    T.last_warning=nil
    T.scan_generation=(T.scan_generation or 0)+1
    T.review_generation=T.scan_generation
    T.review_needed=true
    if DSP.flog then DSP.flog('TRUNK '..source_reason..' slots='..capacity..' occupied='..occupied..' count='..total) end
    return true
end

-- No vehicle/container ID is exposed by the observed packets. A partial
-- update could belong to an entirely different trunk. Never merge it into
-- a previously saved snapshot without a verified identity.

-- Only handles JSON with type=8; never processes other inventory blocks (market/player/etc).
function S.on_inventory_packet(sub, raw)
    -- Real trunk full snapshots use subid=0. subid=2 carries a separate slot
    -- namespace for other inventory blocks; never merge it with trunk slots.
    if tonumber(sub)~=0 then return false end
    T.raw_packet_events=(T.raw_packet_events or 0)+1
    T.last_raw_packet_at=os.time()
    if not (T.autoscan_enabled or T.requested_at) then return false end
    local items,declared_capacity=parse_payload(raw)
    if not items or #items == 0 then
        T.invalid_packet_events=(T.invalid_packet_events or 0)+1
        T.last_error='type 8 received; payload could not be decoded'
        return false
    end
    local ts=os.time()
    -- Observed incoming payload; do not claim the trunk window is open.
    T.packet_events=(T.packet_events or 0)+1
    T.last_packet_at=ts
    if T.pending and (ts-T.pending.started)>PENDING_TIMEOUT then
        T.pending=nil;T.status='incomplete';T.last_error='Incomplete 180-slot batch timed out'
    end
    -- A trunk may arrive in chunks whose first chunk is not slot 0.
    -- type=8 is already the confirmed trunk namespace; large batches start a
    -- fresh capture, while tiny <=5 slot deltas remain ignored.
    local starts_capture=(not T.pending and #items>5)
    local explicit_restart=(T.pending and #items>5 and items[1] and items[1].slot==0 and T.pending.seen[0])
    local stale_restart=(T.pending and #items>5 and T.pending.last_at and (ts-T.pending.last_at)>3)
    if starts_capture or explicit_restart or stale_restart then
        T.pending={slots={},seen={},count=0,started=ts,last_at=ts,
            capacity=declared_capacity or T.selected_capacity or TRUNK_SLOTS}
        T.status='receiving';T.received=0;T.last_error=nil
    end
    if T.pending then
        local p=T.pending
        p.last_at=ts
        if declared_capacity then p.capacity=declared_capacity end
        -- Never finalize a user-selected 30-slot scan if the packet explicitly
        -- includes slots outside its capacity: the observed layout is larger.
        for _,v in ipairs(items) do
            if v.slot>=p.capacity then
                p.capacity=TRUNK_SLOTS
            end
        end
        for _,v in ipairs(items) do
            if not p.seen[v.slot] then p.seen[v.slot]=true;p.count=p.count+1 end
            p.slots[v.slot+1]=v
        end
        T.received=p.count
        if p.count>=p.capacity then
            -- Full means all expected slots in THIS layout were seen. If the
            -- server does not declare capacity, the player explicitly chooses
            -- their car's capacity (30/180), not automatic guessing.
            local complete=true
            for i=1,p.capacity do if not p.slots[i] then complete=false;break end end
            if complete then
                T.pending=nil
                save_snapshot(p.slots,'full',p.capacity)
            end
        end
        return true
    end
    -- If the user started a new scan while the trunk was already open,
    -- the game usually sends only tiny slot deltas when an item moves. Those
    -- deltas are not a full second trunk and must never replace the old scan.
    if #items<=5 then
        if T.requested_at then
            T.saw_delta_after_request=true
            T.status='need_reopen'
            T.last_error='\207\238\235\237\251\233 \241\237\232\236\238\234 \237\229 \239\240\232\248\184\235. \199\224\234\240\238\233 \225\224\227\224\230\237\232\234 \232 \238\242\234\240\238\233 \229\227\238 \231\224\237\238\226\238.'
        elseif T.snapshot then
            -- Do not hide a previously valid full scan just because a single
            -- slot changed while the player was inside the trunk.
            T.last_warning='\200\231\236\229\237\229\237\232\229 \238\242\228\229\235\252\237\251\245 \241\235\238\242\238\226 \237\229 \239\240\232\236\229\237\229\237\238. \196\235\255 \237\238\226\251\245 \228\224\237\237\251\245 \238\242\234\240\238\233 \225\224\227\224\230\237\232\234 \231\224\237\238\226\238.'
        end
        return false
    end
    T.status=T.requested_at and 'need_reopen' or 'unknown_partial'
    if T.requested_at then
        T.last_error='\207\238\235\243\247\229\237\224 \242\238\235\252\234\238 \247\224\241\242\252. \199\224\234\240\238\233 \225\224\227\224\230\237\232\234 \232 \238\242\234\240\238\233 \231\224\237\238\226\238.'
    end
    return false
end

-- Load the most recently persisted trunk as read-only history after restart.
-- Old versions may have stored a nameless live scan. Do not resurrect it
-- in the new unsaved session; named library entries remain untouched.
T.snapshot=nil
T.autoscan_enabled=not (DSP.settings and DSP.settings.storage_trunk_autoscan==false)
T.selected_capacity=VALID_CAPACITY[tonumber(DSP.settings and DSP.settings.storage_trunk_capacity)]
    and tonumber(DSP.settings.storage_trunk_capacity) or 180

function S.set_trunk_capacity(cap)
    cap=tonumber(cap)
    if not VALID_CAPACITY[cap] then return false,'\205\229\228\238\239\243\241\242\232\236\224\255 \226\236\229\241\242\232\236\238\241\242\252' end
    if T.requested_at then return false,'\209\237\224\247\224\235\224 \238\241\242\224\237\238\226\232 \242\229\234\243\249\232\233 \241\234\224\237' end
    local previous=T.selected_capacity
    T.selected_capacity=cap
    if DSP.settings then DSP.settings.storage_trunk_capacity=cap end
    if DSP.save_settings then
        local ok,saved,err=pcall(DSP.save_settings)
        if not ok or not saved then
            T.selected_capacity=previous
            if DSP.settings then DSP.settings.storage_trunk_capacity=previous end
            return false,tostring(err or saved or '\206\248\232\225\234\224 \241\238\245\240\224\237\229\237\232\255')
        end
    end
    return true
end

-- The normal UI uses these methods; no additional game commands are needed.
function S.set_trunk_autoscan(enabled)
    local value=not not enabled
    local prior=T.autoscan_enabled
    T.autoscan_enabled=value
    if DSP.settings then DSP.settings.storage_trunk_autoscan=value end
    if DSP.save_settings then
        local ok,saved,err=pcall(DSP.save_settings)
        if not ok or not saved then
            T.autoscan_enabled=prior
            if DSP.settings then DSP.settings.storage_trunk_autoscan=prior end
            return false,tostring(err or saved or 'save failed')
        end
    end
    if not value and not T.requested_at then
        T.pending=nil
        T.status='disabled'
    elseif value and T.status=='disabled' then
        T.status='idle'
    end
    return true
end

function S.begin_trunk_scan(update_target_id)
    T.pending=nil
    T.received=0
    T.last_error=nil
    T.last_completed_request_at=nil
    T.completed_update_target_id=nil
    T.review_needed=false
    T.update_target_id=update_target_id
    T.requested_at=os.time()
    T.scan_started_at=T.requested_at
    T.scan_raw_start=T.raw_packet_events or 0
    T.scan_packet_start=T.packet_events or 0
    T.saw_delta_after_request=false
    T.status='waiting_open'
    return true
end

function S.cancel_trunk_scan()
    T.pending=nil
    T.received=0
    T.requested_at=nil
    T.update_target_id=nil
    T.completed_update_target_id=nil
    T.saw_delta_after_request=false
    T.status=T.autoscan_enabled and 'idle' or 'disabled'
    T.last_error=nil
    return true
end

function S.find_snapshot(id)
    if not id then return nil end
    for i,saved in ipairs(S.snapshots or {}) do
        if tostring(saved.id)==tostring(id) then return saved,i end
    end
    return nil
end

function S.delete_snapshot(snapshot)
    if type(snapshot)~='table' then return false,'\213\240\224\237\232\235\232\249\229 \237\229 \226\251\225\240\224\237\238' end
    if snapshot.source=='packet220_trunk' then
        return S.clear_live_snapshot()
    end
    local index=nil
    for i,saved in ipairs(S.snapshots or {})do
        if saved==snapshot then index=i;break end
    end
    if not index then return false,'\213\240\224\237\232\235\232\249\229 \243\230\229 \243\228\224\235\229\237\238' end
    local prior=S.snapshots
    local prior_saved=DSP.settings and DSP.settings.storage_snapshots
    local fresh={}
    for i,saved in ipairs(prior)do if i~=index then fresh[#fresh+1]=saved end end
    S.snapshots=fresh
    if DSP.settings then DSP.settings.storage_snapshots=fresh end
    if DSP.save_settings then
        local called,ok,err=pcall(DSP.save_settings)
        if not called or not ok then
            S.snapshots=prior
            if DSP.settings then DSP.settings.storage_snapshots=prior_saved end
            return false,tostring(err or ok or 'save error')
        end
    end
    S.sort_cache=setmetatable({},{__mode='k'})
    return true
end

function S.clear_live_snapshot()
    local prior=S.snapshots
    local prior_saved=DSP.settings and DSP.settings.storage_snapshots
    local fresh={}
    for _,saved in ipairs(prior or {})do
        if saved.source~='packet220_trunk' then fresh[#fresh+1]=saved end
    end
    S.snapshots=fresh
    if DSP.settings then DSP.settings.storage_snapshots=fresh end
    local old_state={snapshot=T.snapshot,occupied=T.occupied,total=T.total,received=T.received,
        last_saved_at=T.last_saved_at,last_completed_request_at=T.last_completed_request_at,
        status=T.status}
    T.snapshot=nil;T.occupied=nil;T.total=nil;T.received=0
    T.last_saved_at=nil;T.last_completed_request_at=nil
    if not T.requested_at then T.status=T.autoscan_enabled and 'idle' or 'disabled' end
    if DSP.save_settings then
        local called,ok,err=pcall(DSP.save_settings)
        if not called or not ok then
            S.snapshots=prior
            if DSP.settings then DSP.settings.storage_snapshots=prior_saved end
            for k,v in pairs(old_state)do T[k]=v end
            return false,tostring(err or ok or 'save error')
        end
    end
    S.sort_cache=setmetatable({},{__mode='k'})
    return true
end

function S.library()
    local rows={}
    for i,saved in ipairs(S.snapshots or {}) do
        if saved.source~='packet220_trunk' then
            rows[#rows+1]={snapshot=saved,index=i}
        end
    end
    return rows
end

-- Candidate detection is only a suggestion, never a vehicle identifier.
-- Compare item IDs and enchantments across slots, not slot positions or amounts.
-- Only fully saved, named type-8 trunk snapshots are eligible.
local function trunk_types(snapshot)
    local keys, count={},0
    for _,row in ipairs(snapshot and snapshot.rows or {}) do
        local id=tonumber(row.id)
        if id and id>0 and id%1==0 then
            local enchant=tonumber(row.ench) or 0
            local key=tostring(id)..':'..tostring(enchant)
            if not keys[key] then keys[key]=true;count=count+1 end
        end
    end
    return keys,count
end

function S.match_saved_trunks(snapshot)
    if type(snapshot)~='table' or snapshot.kind~='trunk'
        or snapshot.source~='packet220_trunk' or not VALID_CAPACITY[snapshot.slots_count]
        or type(snapshot.rows)~='table' then return {} end
    local current,total=trunk_types(snapshot)
    if total==0 then return {} end
    local matches={}
    for _,saved in ipairs(S.snapshots or {}) do
        if saved.source=='packet220_trunk_named' and saved.kind=='trunk'
            and type(saved.rows)=='table'
            and (snapshot.server==nil or saved.server==nil
                 or tostring(snapshot.server)==tostring(saved.server)) then
            local previous,count=trunk_types(saved)
            if count>0 then
                local common=0
                for key in pairs(current)do if previous[key] then common=common+1 end end
                if common>0 then
                    local union=total+count-common
                    matches[#matches+1]={
                        id=saved.id,title=saved.title,shared=common,
                        current_types=total,saved_types=count,
                        similarity=math.floor(100*common/math.max(1,union)+.5),
                        observed_at=tonumber(saved.observed_at) or 0
                    }
                end
            end
        end
    end
    table.sort(matches,function(a,b)
        if a.similarity~=b.similarity then return a.similarity>b.similarity end
        if a.shared~=b.shared then return a.shared>b.shared end
        if a.observed_at~=b.observed_at then return a.observed_at>b.observed_at end
        return tostring(a.id)<tostring(b.id)
    end)
    return matches
end

-- Keep manually named copies independent from the latest automatically opened
-- vehicle. The packet has no trusted vehicle ID: do NOT auto-assign old labels
-- when a different trunk is opened.
function S.save_named_trunk(snapshot,label)
    if type(snapshot)~='table' or snapshot.source~='packet220_trunk' then
        return false,'select a confirmed full trunk snapshot'
    end
    if not snapshot.rows or not VALID_CAPACITY[snapshot.slots_count] then
        return false,'incomplete trunk snapshot'
    end
    local name=DSP.trim(DSP.clean_text(tostring(label or '')))
    if name=='' or #name>66 or name:find('[%c]') then
        return false,'name must contain 1-66 characters without controls'
    end
    S._named_seq=(S._named_seq or 0)+1
    local ts=os.time()
    local rows={}
    for i,r in ipairs(snapshot.rows) do
        rows[i]={slot=r.slot,id=r.id,name=r.name,ench=r.ench,
            qty=r.qty,quantity_confirmed=r.quantity_confirmed}
    end
    local named={id='trunk_saved_'..tostring(ts)..'_'..tostring(S._named_seq),
        title=name,kind='trunk',source='packet220_trunk_named',
        identity_verified=false,complete_verified=true,
        observed_at=snapshot.observed_at,server=snapshot.server,
        slots_count=snapshot.slots_count,occupied_slots=snapshot.occupied_slots,
        count_known=snapshot.count_known,rows=rows}
    for _,existing in ipairs(S.snapshots or {}) do
        if existing.source~='packet220_trunk' and DSP.lower(tostring(existing.title or ''))==DSP.lower(name) then
            return false,'\210\224\234\238\229 \237\224\231\226\224\237\232\229 \243\230\229 \229\241\242\252. \206\242\234\240\238\233 \229\227\238 \232 \226\251\225\229\240\232 \171\206\225\237\238\226\232\242\252\187.'
        end
    end
    local prior=S.snapshots
    local prior_saved=DSP.settings and DSP.settings.storage_snapshots
    local fresh={named}
    for _,existing in ipairs(prior) do
        -- Old releases wrote a nameless live scan into settings. Keep ONLY
        -- deliberately saved user records in the persistent library.
        if existing.source~='packet220_trunk' then
            fresh[#fresh+1]=existing
            if #fresh>=S.max_saved then break end
        end
    end
    S.snapshots=fresh
    if DSP.settings then DSP.settings.storage_snapshots=fresh end
    if DSP.save_settings then
        local ok,saved,err=pcall(DSP.save_settings)
        if not ok or not saved then
            S.snapshots=prior
            if DSP.settings then DSP.settings.storage_snapshots=prior_saved end
            return false,tostring(err or saved or 'save failed')
        end
    end
    T.completed_update_target_id=nil
    T.review_needed=false
    S.sort_cache=setmetatable({},{__mode='k'})
    return true,named
end

function S.apply_latest_to_saved(target_id)
    local live=T.snapshot
    local target=S.find_snapshot(target_id)
    if not live or live.source~='packet220_trunk' or not VALID_CAPACITY[live.slots_count] then
        return false,'\205\229\242 \239\238\235\237\238\227\238 \237\238\226\238\227\238 \241\234\224\237\224'
    end
    if not target or target.source~='packet220_trunk_named' then
        return false,'\209\238\245\240\224\237\184\237\237\251\233 \225\224\227\224\230\237\232\234 \237\229 \237\224\233\228\229\237'
    end
    local backup={
        rows=target.rows,observed_at=target.observed_at,server=target.server,
        occupied_slots=target.occupied_slots,count_known=target.count_known,
        slots_count=target.slots_count,updated_at=target.updated_at
    }
    local rows={}
    for i,row in ipairs(live.rows or {}) do
        rows[i]={slot=row.slot,id=row.id,name=row.name,ench=row.ench,
            qty=row.qty,quantity_confirmed=row.quantity_confirmed}
    end
    target.rows=rows
    target.observed_at=live.observed_at
    target.updated_at=os.time()
    target.server=live.server
    target.occupied_slots=live.occupied_slots
    target.count_known=live.count_known
    target.slots_count=live.slots_count
    if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
    if DSP.save_settings then
        local called,ok,err=pcall(DSP.save_settings)
        if not called or not ok then
            for k,v in pairs(backup) do target[k]=v end
            if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
            return false,tostring(err or ok or 'save error')
        end
    end
    T.completed_update_target_id=nil
    T.review_needed=false
    S.sort_cache=setmetatable({},{__mode='k'})
    return true,target
end

-- Refresh timeout status when the scanner panel is drawn, even if no more packets arrive.
function S.trunk_state()
    local now=os.time()
    if T.pending and now-T.pending.started>PENDING_TIMEOUT then
        T.pending=nil;T.status='incomplete';T.last_error='Incomplete 180-slot batch timed out'
    end
    if T.requested_at and now-T.requested_at>45 then
        T.requested_at=nil
        T.update_target_id=nil
        if T.status=='waiting_open' or T.status=='receiving' or T.status=='need_reopen' then
            T.status='no_packets'
            T.last_error='\207\238\235\237\251\233 \241\237\232\236\238\234 180/180 \237\229 \239\238\235\243\247\229\237. \199\224\239\243\241\242\232 \241\234\224\237 \232 \231\224\237\238\226\238 \238\242\234\240\238\233 \225\224\227\224\230\237\232\234.'
        end
    end
    return T
end

  end
  module_storage()

  local function module_probe()
-- Opt-in, read-only observer for unknown InventoryScreen containers.
-- Does not send packets, click slots or assume undocumented type => kind mappings.
local S = DSP.storage
local P = {armed=false, status='idle', entries={}, order={}, observed=0, ignored_trunk=0, ignored_stall=0}
DSP.storage_probe = P
local MAX_SECONDS, MAX_SLOTS, MAX_SAMPLES, MAX_BYTES = 60, 180, 8, 100000
local allowed = {cabinet=true, warehouse=true}

local function integer(value, maximum, minimum)
    local n=tonumber(value)
    minimum=minimum or 0
    if n and n==n and n%1==0 and n>=minimum and n<=maximum then return n end
    return nil
end
local function observed_slot(item)
    if type(item)~='table' then return nil end
    local slot=integer(item.slot,MAX_SLOTS-1)
    local id=integer(item.item or item.id,2000000000)
    if not slot or not id then return nil end
    local qty=id==0 and 0 or integer(item.amount or item.count,2000000000)
    local ench=integer(item.enchant or item.ench or 0,100) or 0
    return {slot=slot,id=id,qty=qty,ench=ench}
end
local function decode_candidate(raw)
    if type(raw)~='string' or #raw<2 or #raw>MAX_BYTES then return nil end
    local ok,obj=pcall(decodeJson,raw:gsub('%z+$',''))
    if not ok or type(obj)~='table' or type(obj.items)~='table' then return nil end
    local packet_type=integer(obj.type,255)
    if not packet_type or #obj.items<1 or #obj.items>MAX_SLOTS then return nil end
    local slots,seen={},{}
    for _,item in ipairs(obj.items)do
        local v=observed_slot(item)
        if not v or seen[v.slot] then return nil end
        seen[v.slot]=true
        slots[#slots+1]=v
    end
    -- A declared capacity is diagnostic metadata, not proof of identity.
    local cap=integer(obj.capacity or obj.slotCount or obj.totalSlots,MAX_SLOTS,1)
    return packet_type,slots,cap
end

function P.arm(kind, seconds)
    if not allowed[kind] then return false,'unknown kind' end
    local dur=integer(seconds or 40,MAX_SECONDS,5) or 40
    P.armed=true;P.status='armed';P.kind=kind;P.started=os.time()
    P.until_ts=P.started+dur;P.entries={};P.order={}
    P.observed=0;P.ignored_trunk=0;P.ignored_stall=0;P.last_error=nil
    return true
end
function P.stop()
    if P.armed then P.armed=false;P.status='review';return true end
    return false
end
function P.state()
    if P.armed and os.time()>P.until_ts then P.armed=false;P.status='review' end
    return P
end
function P.on_packet(sub,raw)
    if not P.state().armed then return false end
    local namespace=integer(sub,255)
    if namespace~=0 and namespace~=2 then return false end
    local typ,slots,capacity=decode_candidate(raw)
    if not typ then return false end
    -- type 8 is the independently observed vehicle trunk, never a cupboard.
    if typ==8 then P.ignored_trunk=P.ignored_trunk+1;return false end
    -- The existing trade handler identifies type 1/sub 2 as stall inventory.
    if typ==1 and namespace==2 then P.ignored_stall=P.ignored_stall+1;return false end
    local key=tostring(typ)..'/'..tostring(namespace)
    local row=P.entries[key]
    if not row then
        if #P.order>=MAX_SAMPLES then return false end
        row={type=typ,sub=namespace,slots={},seen={},count=0,packet_count=0,
             capacity=capacity,started=os.time(),last_at=os.time()}
        P.entries[key]=row;P.order[#P.order+1]=row
    end
    -- A fresh batch starting with slot 0 cannot silently merge with an old view.
    if row.seen[0] and slots[1].slot==0 and #slots>=8 then
        row.slots={};row.seen={};row.count=0;row.started=os.time()
    end
    if capacity and row.capacity and row.capacity~=capacity then
        row.slots={};row.seen={};row.count=0;row.started=os.time()
    end
    row.capacity=capacity or row.capacity
    row.packet_count=row.packet_count+1
    row.last_at=os.time()
    for _,v in ipairs(slots) do
        if not row.seen[v.slot] then row.seen[v.slot]=true;row.count=row.count+1 end
        row.slots[v.slot]=v
    end
    P.observed=P.observed+1
    return true
end
function P.preview(index)
    local entry=P.order[tonumber(index) or 0]
    if not entry then return nil,'candidate not found' end
    local rows,occupied,known,missing={},0,0,0
    for i=0,MAX_SLOTS-1 do
        local v=entry.slots[i]
        if v and v.id>0 then
            occupied=occupied+1
            local name=DSP.items and DSP.items.name and DSP.items.name(v.id)
                or ('ID:'..tostring(v.id))
            if type(name)~='string' or name=='' then name='ID:'..tostring(v.id) end
            rows[#rows+1]={slot=i,id=v.id,ench=v.ench,name=name,
                qty=v.qty,quantity_confirmed=v.qty~=nil}
            if v.qty==nil then missing=missing+1 else known=known+v.qty end
        end
    end
    return {entry=entry,rows=rows,occupied=occupied,known=known,unknown_qty=missing,
        complete_unverified=entry.capacity~=nil and entry.count==entry.capacity}
end
function P.save(index)
    if P.state().armed then return false,'stop capture before saving' end
    local view,err=P.preview(index)
    if not view then return false,err end
    if #view.rows==0 then return false,'no occupied items observed' end
    if not allowed[P.kind] then return false,'unknown kind' end
    local titles={cabinet='\216\234\224\244',warehouse='\209\234\235\224\228'}
    local now=os.time()
    local snap={id='probe_'..tostring(now)..'_'..tostring(index),
        kind=P.kind,title=titles[P.kind]..' (\237\224\225\235\254\228\229\237\232\229; \237\229 \239\240\238\226\229\240\229\237\238)',
        source='packet220_probe',identity_verified=false,complete_verified=false,
        observed_at=now,server=DSP.market and DSP.market.state and DSP.market.state.sid,
        packet_type=view.entry.type,packet_sub=view.entry.sub,
        slots_observed=view.entry.count,slots_reported=view.entry.capacity,
        rows=view.rows,count_known=view.known,occupied_slots=view.occupied}
    local previous=S.snapshots
    local previous_saved=DSP.settings and DSP.settings.storage_snapshots
    -- Keep explicitly saved observations (including their chosen names).
    -- They are history, never proof that the same cabinet was opened again.
    local replacement={snap}
    for _,old in ipairs(previous or {})do
        replacement[#replacement+1]=old
        if #replacement>=(S.max_saved or 20)+1 then break end
    end
    S.snapshots=replacement
    if DSP.settings then DSP.settings.storage_snapshots=replacement end
    if DSP.save_settings then
        local ok,saved,save_error=pcall(DSP.save_settings)
        if not ok or not saved then
            S.snapshots=previous
            if DSP.settings then DSP.settings.storage_snapshots=previous_saved end
            return false,tostring(save_error or saved or 'save failed')
        end
    end
    S.sort_cache=setmetatable({},{__mode='k'})
    return true,snap
end

-- Explicit local diagnostics export. Metadata only: no raw JSON, item names,
-- item IDs, account identifiers, chat, tokens or individual item quantities.
function P.export_report()
    if P.state().armed then return false,'stop capture before export' end
    if type(encodeJson)~='function' or type(DSP.dir)~='string' then
        return false,'JSON export unavailable'
    end
    local candidates={}
    for _,e in ipairs(P.order)do
        candidates[#candidates+1]={type=e.type,sub=e.sub,slots_observed=e.count,
            declared_slots=e.capacity,packets=e.packet_count}
    end
    local report={schema=1,source='Palatka AI read-only probe',kind_label=P.kind,
        duration_seconds=math.max(0,(P.until_ts or 0)-(P.started or 0)),
        packets=P.observed,ignored_trunk=P.ignored_trunk,
        ignored_stall=P.ignored_stall,candidates=candidates}
    local ok,body=pcall(encodeJson,report)
    if not ok or type(body)~='string' then return false,'JSON encoding failed' end
    local path=DSP.dir..'/storage_probe_report.json'
    local file,err=io.open(path,'wb')
    if not file then return false,tostring(err or 'cannot open report') end
    local wrote,write_err=file:write(body)
    file:close()
    if not wrote then return false,tostring(write_err or 'write failed') end
    return true,path
end

  end
  module_probe()

  local function module_probe_ui()
-- Simplified read-only cabinet / warehouse observer.
-- Personal inventory scan intentionally removed from the UI.
local V = DSP.ui21
local P = DSP.storage_probe
local labels={cabinet='\216\202\192\212',warehouse='\209\202\203\192\196'}
local descriptions={cabinet='\248\234\224\244',warehouse='\241\234\235\224\228'}
local function button(label,id,width,active,primary)
    return V.button(label,'probe_'..id,width,active,primary)
end

function V.storage_probe_panel(width,kind)
    width=math.max(190,tonumber(width) or 300)
    local w=math.min(width,315)
    if not P then V.red('\209\234\224\237\229\240 \253\242\238\227\238 \234\238\237\242\229\233\237\229\240\224 \237\229\228\238\241\242\243\239\229\237.');return end
    if not labels[kind] then V.red('\205\229\232\231\226\229\241\242\237\251\233 \242\232\239 \245\240\224\237\232\235\232\249\224.');return end
    local state=P.state()

    V.apply_font((V.font_pixels or 18)*1.15)
    V.text(labels[kind])
    V.apply_font()

    if state.armed and state.kind~=kind then
        V.red('\209\229\233\247\224\241 \232\228\184\242 \241\234\224\237 \228\240\243\227\238\227\238 \245\240\224\237\232\235\232\249\224.')
        if button('\206\241\242\224\237\238\226\232\242\252 \242\229\234\243\249\232\233 \241\234\224\237','stop_other',w,false,true)then P.stop()end
        return
    end

    if state.kind~=kind and not state.armed then
        V.muted('\205\224\230\236\232 \171\205\224\247\224\242\252 \241\234\224\237\187, \231\224\242\229\236 \231\224\234\240\238\233 Palatka AI \232 \238\242\234\240\238\233 '..descriptions[kind]..' \226 \232\227\240\229.')
        if button('\205\192\215\192\210\220 \209\202\192\205','arm_'..kind,w,false,true)then
            P.arm(kind,40)
            V.probe_selected=1
            V.probe_error=nil
        end
        return
    end

    if state.armed then
        V.green('\209\202\192\205 \199\192\207\211\217\197\205')
        V.muted('\206\242\234\240\238\233 '..descriptions[kind]..' \226 \232\227\240\229. \207\238\241\235\229 \253\242\238\227\238 \226\229\240\237\232\241\252 \241\254\228\224.')
        V.muted('\206\241\242\224\235\238\241\252: '..math.max(0,state.until_ts-os.time())..' \241\229\234.')
        if button('\199\192\194\197\208\216\200\210\220 \200 \207\206\202\192\199\192\210\220','stop',w,false,true)then P.stop()end
        return
    end

    if #state.order==0 then
        V.red('\209\238\228\229\240\230\232\236\238\229 \237\229 \240\224\241\239\238\231\237\224\237\238.')
        V.muted('\207\238\239\240\238\225\243\233 \231\224\239\243\241\242\232\242\252 \241\234\224\237 \229\249\184 \240\224\231 \232 \231\224\237\238\226\238 \238\242\234\240\251\242\252 '..descriptions[kind]..'.')
        if button('\207\206\194\210\206\208\200\210\220 \209\202\192\205','arm_'..kind,w,false,true)then
            P.arm(kind,40);V.probe_selected=1;V.probe_error=nil
        end
        return
    end

    V.probe_selected=math.max(1,math.min(#state.order,V.probe_selected or 1))
    local selected=V.probe_selected
    if #state.order>1 then
        V.muted('\205\224\233\228\229\237\238 \237\229\241\234\238\235\252\234\238 \226\224\240\232\224\237\242\238\226: '..selected..' / '..#state.order)
        if button('\209\235\229\228\243\254\249\232\233 \226\224\240\232\224\237\242','next',w)then
            selected=selected%#state.order+1
            V.probe_selected=selected
        end
    end

    local info,err=P.preview(selected)
    if not info then V.red(tostring(err));return end

    V.green('\205\192\201\196\197\205\206: '..tostring(info.occupied)..' \231\224\237\255\242\251\245 \241\235\238\242\238\226')
    V.text('\207\238\228\242\226\229\240\230\228\229\237\238 \239\240\229\228\236\229\242\238\226: '..tostring(info.known))
    if info.unknown_qty>0 then
        V.muted('\193\229\231 \242\238\247\237\238\227\238 \234\238\235\232\247\229\241\242\226\224: '..tostring(info.unknown_qty)..' \241\242\240\238\234')
    end

    if DSP.storage and DSP.storage.evaluate then
        local estimate=DSP.storage.evaluate({kind=kind,rows=info.rows,
            server=DSP.market and DSP.market.state and DSP.market.state.sid})
        if not estimate.cross_server then
            V.green('\206\246\229\237\234\224 \241\234\243\239\234\232: '..DSP.money(estimate.sell_to_buyers))
            if estimate.missing_prices>0 then
                V.muted('\205\229\242 \246\229\237 \228\235\255 '..estimate.missing_prices..' \241\242\240\238\234')
            end
        end
    end

    V.red('\207\238\234\224 \253\242\238 \239\240\229\228\226\224\240\232\242\229\235\252\237\251\233 \241\234\224\237: \239\238\235\237\251\233 \244\238\240\236\224\242 '..descriptions[kind]..' \229\249\184 \239\240\238\226\229\240\255\229\242\241\255.')
    if button('\209\206\213\208\192\205\200\210\220 \208\197\199\211\203\220\210\192\210','save',w,false,true)then
        local ok,saved=P.save(selected)
        if ok then
            V.probe_error=nil
            V.storage_tab='library'
            V.storage_library_page='list'
        else
            V.probe_error=tostring(saved)
        end
    end
    if button('\207\206\194\210\206\208\200\210\220 \209\202\192\205','arm_'..kind,w)then
        P.arm(kind,40);V.probe_selected=1;V.probe_error=nil
    end
    if V.probe_error then V.red(V.fit(V.probe_error,width))end
end

  end
  module_probe_ui()

  local function install_beta_rollback()
    local U=DSP.updater
    local stable=[==[
-- Palatka AI v2.7.0: restore the native v2.5.2 mimgui interface.
-- This rollback release intentionally contains no WebUI hooks or browser UI.
-- The update manager reloads the base Lua after installing this overlay.
PALATKA_UPDATE_VERSION = '2.7.0'

return function(DSP)
    -- Best effort: clean up a WebView retained by the previous overlay.
    local W = DSP.webui
    if W and type(W.hide) == 'function' then pcall(W.hide) end
    local ok, web = pcall(require, 'webviews')
    if ok and web then
        local id = 95253
        if type(web.setClickable) == 'function' then pcall(web.setClickable, id, false) end
        if type(web.setVisible) == 'function' then pcall(web.setVisible, id, false) end
        if type(web.setPos) == 'function' then pcall(web.setPos, id, -99999, -99999) end
        if type(web.setSize) == 'function' then pcall(web.setSize, id, 1, 1) end
    end
    -- Leave presets, settings, market cache, saved storages and trading runtime untouched.
    DSP.version = '2.7.0'
    if DSP.flog then pcall(DSP.flog, 'Rollback to native mimgui UI (v2.5.2 base)') end
    return true
end

]==]
    local function restore()
      if not U or type(U.update_path)~='string' then return false,'Updater path unavailable' end
      local dest=U.update_path
      local temp=dest..'.crr_tmp'
      local backup=dest..'.crr_beta_backup'
      local f,err=io.open(temp,'wb')
      if not f then return false,tostring(err or 'cannot create rollback file') end
      local wrote,write_err=f:write(stable)
      local closed,close_err=f:close()
      if not wrote or not closed then
        pcall(os.remove,temp)
        return false,tostring(write_err or close_err or 'rollback write failed')
      end
      pcall(os.remove,backup)
      local kept,keep_err=os.rename(dest,backup)
      if not kept then pcall(os.remove,temp);return false,'backup failed: '..tostring(keep_err) end
      local placed,move_err=os.rename(temp,dest)
      if not placed then
        pcall(os.rename,backup,dest)
        pcall(os.remove,temp)
        return false,'restore failed: '..tostring(move_err)
      end
      if U.state then U.state.status='rolled_back';U.state.error=nil end
      if DSP.notify then pcall(DSP.notify,'CRR: stable 2.7.0 restored') end
      if lua_thread and lua_thread.create and wait and thisScript then
        lua_thread.create(function()
          wait(650)
          local sc=thisScript()
          if sc and sc.reload then sc:reload() end
        end)
      end
      return true
    end
    DSP.storage_beta_rollback=restore
    if U then U.rollback=restore end
  end
  install_beta_rollback()

  local function module_storage_search()
-- Search saved containers by item name; all totals are scoped to the
-- user's query, never the entire trunk. Works only with user-saved snapshots.
local S=DSP.storage

function S.search_library(query,lookup)
    local needle=DSP.lower(DSP.trim(query or ''))
    local report={
        query=needle, results={},storage_count=0,match_groups=0,
        known_qty=0,unknown_slots=0,priced_value=0,unpriced_groups=0,
        different_server=0
    }
    if needle=='' then return report end
    for _,entry in ipairs(S.library())do
        local snap=entry.snapshot
        local info=S.evaluate(snap,lookup)
        local hits={}
        local qty,unknown,value,unpriced=0,0,0,0
        for _,item in ipairs(info.rows or {})do
            if DSP.lower(tostring(item.name or '')):find(needle,1,true) then
                local known=tonumber(item.qty) or 0
                local missing=tonumber(item.unknown_slots) or 0
                local bid=not info.cross_server and tonumber(item.bid) or nil
                local estimated=bid and known*bid or nil
                hits[#hits+1]={
                    name=item.name, key=item.key,id=item.id,ench=item.ench,
                    qty=known,unknown_slots=missing,
                    unit_buy=bid,total_buy=estimated,
                    market_unavailable=info.cross_server
                }
                qty=qty+known
                unknown=unknown+missing
                if estimated then value=value+estimated
                elseif known>0 then unpriced=unpriced+1 end
            end
        end
        table.sort(hits,function(a,b)
            if a.qty~=b.qty then return a.qty>b.qty end
            return tostring(a.name)<tostring(b.name)
        end)
        local title_hit=DSP.lower(tostring(snap.title or '')):find(needle,1,true)~=nil
        if #hits>0 or title_hit then
            local line={
                index=entry.index,snapshot=snap,matched_items=hits,title_only=title_hit and #hits==0,
                known_qty=qty,unknown_slots=unknown,
                priced_value=value,unpriced_groups=unpriced,
                cross_server=info.cross_server
            }
            report.results[#report.results+1]=line
            report.storage_count=report.storage_count+1
            report.match_groups=report.match_groups+#hits
            report.known_qty=report.known_qty+qty
            report.unknown_slots=report.unknown_slots+unknown
            report.priced_value=report.priced_value+value
            report.unpriced_groups=report.unpriced_groups+unpriced
            if info.cross_server and #hits>0 then
                report.different_server=report.different_server+1
            end
        end
    end
    table.sort(report.results,function(a,b)
        if a.title_only~=b.title_only then return not a.title_only end
        if a.known_qty~=b.known_qty then return a.known_qty>b.known_qty end
        return tostring(a.snapshot.title)<tostring(b.snapshot.title)
    end)
    return report
end

  end
  module_storage_search()

  local function module_storage_ui()
-- Safe container analyzer; cannot read bespoke game UIs without a packet parser.
local ffi=require('ffi')
local V,S,M=DSP.ui21,DSP.storage,DSP.mobile
V.storage_sort='value'
V.storage_selected=1
local function b(s,id,w,on,primary)return V.button(s,'storage_'..id,w,on,primary)end
-- One task per panel: scanner, snapshots, manual fallback. This avoids the
-- previous giant fixed header which pushed the item list off small screens.
function V.storage_screen()
    V.heading('\213\240\224\237\232\235\232\249\224',function()
        if DSP.storage_beta_rollback and b('CRR \206\210\202\192\210','beta_rollback',145,false,true) then
            V.open_popup('CRR \238\242\234\224\242','storage_beta_rollback')
        end
    end,DSP.storage_beta_rollback and 149 or 0)

    -- Old versions used "snapshots/manual". Collapse them into the two-task UI.
    if V.storage_tab=='snapshots' then V.storage_tab='library' end
    if V.storage_tab=='manual' then V.storage_tab='scan' end
    V.storage_tab=V.storage_tab or 'scan'
    V.storage_scan_mode=(V.storage_scan_mode=='inventory') and 'trunk' or (V.storage_scan_mode or 'trunk')
    V.storage_library_page=V.storage_library_page or 'list'

    local width=imgui.GetContentRegionAvail().x
    local tabw=math.max(120,(width-6)/2)
    for i,tab in ipairs({{'scan','\209\202\192\205'},{'library','\204\206\200 \213\208\192\205\200\203\200\217\192'}})do
        if b(tab[2],'tab_'..tab[1],tabw,V.storage_tab==tab[1],V.storage_tab==tab[1])then
            V.storage_tab=tab[1]
            if tab[1]=='library' then V.storage_library_page='list' end
            V.reset_list('storage_scan_panel')
        end
        if i==1 then V.inline(6)end
    end
    imgui.Separator()

    if V.storage_tab=='scan' then
        V.list('storage_scan_panel',function(w)
            local options={{'trunk','\193\224\227\224\230\237\232\234'},{'cabinet','\216\234\224\244'},{'warehouse','\209\234\235\224\228'}}
            local bw=math.max(92,(w-12)/3)
            for i,item in ipairs(options)do
                if b(item[2],'choose_'..item[1],bw,V.storage_scan_mode==item[1],V.storage_scan_mode==item[1])then
                    if S.cancel_trunk_scan and V.storage_scan_mode=='trunk' and item[1]~='trunk' then
                        S.cancel_trunk_scan()
                    end
                    V.storage_scan_mode=item[1]
                    V.probe_error=nil
                    V.reset_list('storage_scan_panel')
                end
                if i<3 then V.inline(6)end
            end
            imgui.Separator()

            if V.storage_scan_mode~='trunk' then
                if V.storage_probe_panel then V.storage_probe_panel(w,V.storage_scan_mode)
                else V.red('\209\234\224\237\229\240 \253\242\238\227\238 \245\240\224\237\232\235\232\249\224 \237\229\228\238\241\242\243\239\229\237.') end
                return
            end

            local t=(S.trunk_state and S.trunk_state()) or S.trunk or {}
            -- A review appears once per NEW completed 180-slot scan, and only
            -- when existing saved trunks share at least one item ID/enchant.
            if t.review_needed and t.review_generation
                and V.storage_match_generation~=t.review_generation
                and t.snapshot and t.status=='saved' and S.match_saved_trunks then
                V.storage_match_generation=t.review_generation
                local matches=S.match_saved_trunks(t.snapshot)
                if #matches>0 then
                    V.storage_match_review={
                        generation=t.review_generation, matches=matches, selected=1
                    }
                    V.open_popup('\207\238\245\238\230\232\233 \225\224\227\224\230\237\232\234','storage_match_confirm')
                else
                    t.review_needed=false
                end
            end
            local active=t.requested_at~=nil or t.status=='waiting_open' or
                t.status=='receiving' or t.status=='need_reopen'

            V.apply_font((V.font_pixels or 18)*1.18)
            V.text('\205\206\194\219\201 \209\202\192\205 \193\192\195\192\198\205\200\202\192')
            V.apply_font()

            if active then
                if t.status=='receiving' then
                    V.green('\207\206\203\211\215\192\222 \196\192\205\205\219\197: '..tostring(t.received or 0)..' / 180')
                    V.muted('\205\229 \231\224\234\240\251\226\224\233 \225\224\227\224\230\237\232\234, \239\238\234\224 \237\229 \225\243\228\229\242 180 / 180.')
                elseif t.status=='need_reopen' then
                    V.red('\205\211\198\205\206 \199\192\205\206\194\206 \206\210\202\208\219\210\220 \193\192\195\192\198\205\200\202')
                    V.text('\199\224\234\240\238\233 \225\224\227\224\230\237\232\234 \239\238\235\237\238\241\242\252\254 \232 \238\242\234\240\238\233 \229\227\238 \229\249\184 \240\224\231.')
                    V.muted('\207\229\240\229\236\229\249\229\237\232\229 \239\240\229\228\236\229\242\238\226 \226\237\243\242\240\232 \243\230\229 \238\242\234\240\251\242\238\227\238 \225\224\227\224\230\237\232\234\224 \228\224\184\242 \242\238\235\252\234\238 \247\224\241\242\232\247\237\251\229 \232\231\236\229\237\229\237\232\255.')
                else
                    V.green('\209\202\192\205 \199\192\207\211\217\197\205')
                    V.text('\197\241\235\232 \225\224\227\224\230\237\232\234 \243\230\229 \238\242\234\240\251\242 \151 \231\224\234\240\238\233 \229\227\238.')
                    V.text('\199\224\242\229\236 \238\242\234\240\238\233 \225\224\227\224\230\237\232\234 \231\224\237\238\226\238 \238\225\251\247\237\251\236 \241\239\238\241\238\225\238\236.')
                    V.muted('\198\228\243 \239\238\235\237\251\233 \241\237\232\236\238\234 180 / 180 \241\235\238\242\238\226.')
                end
                V.muted('\207\238\235\243\247\229\237\238: '..tostring(t.received or 0)..' / 180')
                if b('\206\210\204\197\205\200\210\220 \209\202\192\205','cancel_trunk',math.min(w,240))then
                    S.cancel_trunk_scan()
                end
                V.muted('\207\240\229\228\251\228\243\249\232\233 \240\229\231\243\235\252\242\224\242 \226\238 \226\240\229\236\255 \237\238\226\238\227\238 \241\234\224\237\224 \237\229 \239\238\234\224\231\251\226\224\229\242\241\255.')
                return
            end

            if t.status=='no_packets' or t.status=='incomplete' then
                V.red('\205\206\194\219\201 \209\202\192\205 \205\197 \207\206\203\211\215\197\205')
                V.text('\199\224\234\240\238\233 \225\224\227\224\230\237\232\234, \237\224\230\236\232 \171\205\224\247\224\242\252 \237\238\226\251\233 \241\234\224\237\187 \232 \238\242\234\240\238\233 \229\227\238 \231\224\237\238\226\238.')
            elseif t.last_error and t.status~='saved' then
                V.red(V.fit(tostring(t.last_error),w))
            end

            if b('\205\192\215\192\210\220 \205\206\194\219\201 \209\202\192\205','start_trunk',math.min(w,320),false,true)then
                S.begin_trunk_scan()
                V.storage_error=nil
                return
            end
            V.muted('\194\224\230\237\238: \241\234\224\237 \231\224\239\243\241\234\224\229\242\241\255 \196\206 \239\238\226\242\238\240\237\238\227\238 \238\242\234\240\251\242\232\255 \225\224\227\224\230\237\232\234\224.')

            if t.snapshot and t.status=='saved' then
                imgui.Separator()
                V.green('\195\206\210\206\194\206 \183 180 / 180')
                if t.last_warning then V.muted(V.fit(t.last_warning,w)) end
                V.text('\199\224\237\255\242\238 \241\235\238\242\238\226: '..tostring(t.snapshot.occupied_slots or 0))
                V.text('\194\241\229\227\238 \239\240\229\228\236\229\242\238\226: '..tostring(t.snapshot.count_known or 0))
                local sig=tostring(t.last_saved_at or t.snapshot.observed_at)..'/'..
                    tostring(DSP.market and DSP.market.state and DSP.market.state.version or '')
                local info=V.memo('storage_trunk_summary',sig,function()return S.evaluate(t.snapshot)end)
                if not info.cross_server then
                    V.green('\206\246\229\237\234\224 \241\234\243\239\234\232: '..DSP.money(info.sell_to_buyers))
                end

                if t.review_needed and V.storage_match_review
                    and V.storage_match_review.generation==t.review_generation then
                    if b('\207\206\213\206\198\200\197 \193\192\195\192\198\205\200\202\200','show_matches',math.min(w,290),false,true)then
                        V.open_popup('\207\238\245\238\230\232\233 \225\224\227\224\230\237\232\234','storage_match_confirm')
                    end
                end
                local update_target=t.completed_update_target_id and S.find_snapshot(t.completed_update_target_id)
                if update_target then
                    V.text('\206\225\237\238\226\232\242\252: '..tostring(update_target.title))
                    if b('\207\208\200\204\197\205\200\210\220 \202 '..tostring(update_target.title),'apply_update',math.min(w,320),false,true)then
                        local ok,updated=S.apply_latest_to_saved(update_target.id)
                        if ok then
                            local _,idx=S.find_snapshot(updated.id)
                            V.storage_selected=idx or 1
                            V.storage_library_page='detail'
                            V.storage_tab='library'
                            return
                        else V.storage_error=tostring(updated) end
                    end
                    if b('\209\206\213\208\192\205\200\210\220 \202\192\202 \205\206\194\206\197','save_update_new',math.min(w,290))then
                        V.storage_name_target=t.snapshot
                        V.storage_name_buf=imgui.new.char[128]()
                        V.storage_name_error=nil
                        V.open_popup('\209\238\245\240\224\237\232\242\252 \225\224\227\224\230\237\232\234','storage_trunk_name')
                    end
                else
                    if b('\209\206\213\208\192\205\200\210\220 \202\192\202 \205\206\194\206\197','save_new',math.min(w,290),false,true)then
                        V.storage_name_target=t.snapshot
                        V.storage_name_buf=imgui.new.char[128]()
                        V.storage_name_error=nil
                        V.open_popup('\209\238\245\240\224\237\232\242\252 \225\224\227\224\230\237\232\234','storage_trunk_name')
                    end
                end
                if b('\206\215\200\209\210\200\210\220 \207\206\209\203\197\196\205\200\201 \209\202\192\205','clear_live',math.min(w,290))then
                    local ok,err=S.clear_live_snapshot()
                    if not ok then V.storage_error=tostring(err) end
                end
            end

            if V.storage_error then V.red(V.fit(V.storage_error,w)) end
            imgui.Separator()
            if b((t.autoscan_enabled and '\192\226\242\238\241\234\224\237: \194\202\203' or '\192\226\242\238\241\234\224\237: \194\219\202\203'),
                 'toggle_auto',math.min(w,210),t.autoscan_enabled)then
                local ok,err=S.set_trunk_autoscan(not t.autoscan_enabled)
                if not ok then V.storage_error=tostring(err) end
            end
            V.muted('\192\226\242\238\241\234\224\237 \235\238\226\232\242 \239\238\235\237\251\233 \241\237\232\236\238\234 \239\240\232 \238\242\234\240\251\242\232\232 \225\224\227\224\230\237\232\234\224. \206\237 \237\229 \243\227\224\228\251\226\224\229\242 \236\224\248\232\237\243 \239\238 \239\238\241\224\228\234\229 \226 \224\226\242\238.')
        end,{footer=false})
        return
    end

    local snapshots=S.snapshots or {}
    local library=S.library and S.library() or {}

    if V.storage_library_page=='list' then
        V.apply_font((V.font_pixels or 18)*1.24)
        V.text('\204\206\200 \213\208\192\205\200\203\200\217\192')
        V.apply_font()
        V.muted('\210\238\235\252\234\238 \241\238\245\240\224\237\184\237\237\251\229 \231\224\239\232\241\232. \207\238\241\235\229\228\237\232\233 \241\234\224\237 \241\254\228\224 \237\229 \239\238\228\236\229\248\232\226\224\229\242\241\255.')
        if b('+ \205\206\194\219\201 \209\202\192\205','library_new_scan',math.min(230,width),false,true)then
            V.storage_tab='scan'
            V.storage_scan_mode='trunk'
            S.begin_trunk_scan()
            V.reset_list('storage_scan_panel')
            return
        end
        V.muted('\207\206\200\209\202: \239\238 \237\224\231\226\224\237\232\254 \245\240\224\237\232\235\232\249\224 \232\235\232 \239\240\229\228\236\229\242\224')
        local query=V.search and V.search('storage_all','\205\224\231\226\224\237\232\229 \232\235\232 \239\240\229\228\236\229\242...',math.min(380,width)) or ''
        query=DSP.lower(DSP.trim(query or ''))
        -- Search results are item-centric: show quantities of matched
        -- items per named container. Do NOT show the entire trunk count/value.
        if query~='' and S.search_library then
            local report=S.search_library(query)
            V.apply_font((V.font_pixels or 18)*1.12)
            V.text('\205\192\201\196\197\205\206 \194 '..tostring(report.storage_count)..' \213\208\192\205\200\203\200\217\192\213')
            V.apply_font()
            V.text('\207\238\228\242\226\229\240\230\228\229\237\238 \239\238 \231\224\239\240\238\241\243: '..tostring(report.known_qty)..' \248\242.')
            if report.unknown_slots>0 then
                V.red('\193\229\231 \242\238\247\237\238\227\238 \234\238\235\232\247\229\241\242\226\224: '..tostring(report.unknown_slots)..' \241\235\238\242\238\226')
            end
            V.green('\206\246\229\237\234\224 \237\224\233\228\229\237\237\251\245 \239\240\229\228\236\229\242\238\226: '..DSP.money(report.priced_value))
            if report.unpriced_groups>0 then
                V.muted('\193\229\231 \246\229\237\251: '..report.unpriced_groups..' \226\232\228\238\226 \239\240\229\228\236\229\242\238\226')
            end
            if report.different_server>0 then
                V.muted('\209 \228\240\243\227\238\227\238 \241\229\240\226\229\240\224: '..report.different_server..' \245\240\224\237\232\235\232\249 (\225\229\231 \246\229\237\251)')
            end
            V.muted('\209\243\236\236\224 \239\238 \241\238\245\240\224\237\184\237\237\251\236 \241\237\232\236\234\224\236. \194\238\231\236\238\230\237\251 \239\238\226\242\238\240\237\251\229 \243\247\184\242\251.')
            local matches={}
            for _,entry in ipairs(report.results)do
                if entry.title_only then
                    matches[#matches+1]={entry=entry}
                else
                    for _,it in ipairs(entry.matched_items)do
                        matches[#matches+1]={entry=entry,item=it}
                    end
                end
            end
            if #matches==0 then
                V.muted('\210\224\234\232\245 \239\240\229\228\236\229\242\238\226 \232\235\232 \245\240\224\237\232\235\232\249 \237\229\242.')
                return
            end
            V.list_rows('storage_search_results',matches,136,function(match,i)
                local entry=match.entry
                local snap=entry.snapshot
                local it=match.item
                V.row('storage_result_'..i,136,function(rw,x,y)
                    V.at(x,y)
                    V.apply_font((V.font_pixels or 18)*1.09)
                    V.text(V.fit(tostring(snap.title or '\193\229\231 \237\224\231\226\224\237\232\255'),rw))
                    V.apply_font()
                    if it then
                        V.at(x,y+31)
                        V.text(V.fit(tostring(it.name or '\207\240\229\228\236\229\242'),rw))
                        V.at(x,y+60)
                        local qty=tostring(it.qty)..' \248\242.'
                        if it.unknown_slots>0 then
                            qty=qty..' + ? ('..it.unknown_slots..' \241\235.)'
                        end
                        V.muted('\202\238\235\232\247\229\241\242\226\238: '..qty)
                        V.at(x,y+88)
                        if it.total_buy then
                            V.green(V.fit('\209\234\243\239\234\224: '..DSP.money(it.total_buy)..
                                ' \183 '..DSP.money(it.unit_buy)..'/\248\242.',rw))
                        else
                            V.muted('\209\234\243\239\234\224: \237\229\242 \224\234\242\243\224\235\252\237\238\233 \246\229\237\251')
                        end
                    else
                        V.at(x,y+40)
                        V.muted('\209\238\226\239\224\235\238 \237\224\231\226\224\237\232\229 \245\240\224\237\232\235\232\249\224, \237\229 \237\224\231\226\224\237\232\229 \239\240\229\228\236\229\242\224')
                        V.at(x,y+75)
                        V.muted('\205\224\230\236\232, \247\242\238\225\251 \239\238\241\236\238\242\240\229\242\252 \241\238\228\229\240\230\232\236\238\229')
                    end
                    V.at(x,y)
                    local pressed
                    if imgui.InvisibleButton then
                        pressed=imgui.InvisibleButton('##storage_search_open',
                            imgui.ImVec2(rw,124))
                    else
                        pressed=V.text_button('\206\242\234\240\251\242\252','storage_search_fallback',rw,false,124)
                    end
                    if pressed and not V.dragged then
                        V.storage_selected=entry.index
                        V.storage_detail_key=it and it.key or nil
                        V.storage_library_page='detail'
                        V.reset_list('storage_items')
                    end
                end)
            end,{footer=function()
                V.muted('\208\229\231\243\235\252\242\224\242\238\226: '..#matches..' \183 \237\224\230\236\232 \234\224\240\242\238\247\234\243 \228\235\255 \239\240\238\241\236\238\242\240\224')
            end})
            return
        end
        local filtered={}
        local grand,missing=0,0
        for _,entry in ipairs(library)do
            local snap=entry.snapshot
            local found=query=='' or DSP.lower(tostring(snap.title or '')):find(query,1,true)~=nil
            if not found then
                for _,it in ipairs(snap.rows or {})do
                    if DSP.lower(tostring(it.name or '')):find(query,1,true)then found=true;break end
                end
            end
            if found then filtered[#filtered+1]=entry end
            local value=S.evaluate(snap)
            if value.cross_server then missing=missing+1
            else grand=grand+(value.sell_to_buyers or 0) end
        end
        V.text('\213\240\224\237\232\235\232\249: '..#library..' | \237\224\233\228\229\237\238: '..#filtered)
        V.green('\209\243\236\236\224 \238\246\229\237\238\234: '..DSP.money(grand))
        if missing>0 then V.muted('\193\229\231 \238\246\229\237\234\232: '..missing..' (\228\240\243\227\238\233 \241\229\240\226\229\240)') end
        V.muted('\221\242\238 \241\243\236\236\224 \238\246\229\237\238\234 \241\237\232\236\234\238\226, \237\229 \240\229\224\235\252\237\224\255 \239\240\232\225\251\235\252.')
        if #filtered==0 then
            V.muted(query=='' and '\207\238\234\224 \237\229\242 \241\238\245\240\224\237\184\237\237\251\245 \245\240\224\237\232\235\232\249.' or '\205\232\247\229\227\238 \237\229 \237\224\233\228\229\237\238.')
            return
        end
        V.list_rows('storage_library',filtered,95,function(entry,i)
            local snap=entry.snapshot
            local kind=snap.kind=='trunk'and'\193\224\227\224\230\237\232\234' or snap.kind=='cabinet'and'\216\234\224\244'
                or snap.kind=='warehouse'and'\209\234\235\224\228' or'\213\240\224\237\232\235\232\249\229'
            V.row('storage_library_'..i,95,function(rw,x,y)
                V.at(x,y)
                V.apply_font((V.font_pixels or 18)*1.12)
                V.text(V.fit(tostring(snap.title or kind),rw))
                V.apply_font()
                V.at(x,y+43)
                local value=S.evaluate(snap)
                V.muted(V.fit(kind..' \183 '..tostring(snap.count_known or 0)..' \248\242. \183 '..
                    DSP.money(value.sell_to_buyers),rw))
                V.at(x,y)
                local hit
                if imgui.InvisibleButton then
                    hit=imgui.InvisibleButton('##open_storage_card',imgui.ImVec2(rw,84))
                else
                    hit=V.text_button(tostring(snap.title or kind),'storage_open_fallback',rw,false,84)
                end
                if hit and not V.dragged then
                    V.storage_selected=entry.index
                    V.storage_detail_key=nil
                    V.storage_library_page='detail'
                    V.reset_list('storage_items')
                end
            end)
        end,{footer=function()V.muted('\209\238\245\240\224\237\229\237\238: '..#library..' / '..tostring(S.max_saved or 20))end})
        return
    end

    local current=snapshots[V.storage_selected or 1]
    if not current or current.source=='packet220_trunk' then
        V.storage_library_page='list'
        return
    end
    if b('< \204\206\200 \213\208\192\205\200\203\200\217\192','library_back',math.min(230,width))then
        V.storage_library_page='list'
        return
    end

    V.apply_font((V.font_pixels or 18)*1.34)
    V.text(V.fit(tostring(current.title or '\193\229\231 \237\224\231\226\224\237\232\255'),width))
    V.apply_font()
    local kind=current.kind=='trunk'and'\193\224\227\224\230\237\232\234' or current.kind=='cabinet'and'\216\234\224\244'
        or current.kind=='warehouse'and'\209\234\235\224\228' or'\213\240\224\237\232\235\232\249\229'
    V.muted(kind..' \183 '..os.date('%d.%m.%Y %H:%M',current.observed_at or os.time()))

    if current.source=='packet220_trunk_named' then
        if b('\206\193\205\206\194\200\210\220 \209\202\192\205','library_update',math.min(240,width),false,true)then
            S.begin_trunk_scan(current.id)
            V.storage_tab='scan'
            V.storage_scan_mode='trunk'
            return
        end
    end
    if b('\207\229\240\229\232\236\229\237\238\226\224\242\252','rename',math.min(180,width))then
        V.storage_label_target=current
        V.storage_label_buf=imgui.new.char[128]()
        ffi.copy(V.storage_label_buf,DSP.utf8(tostring(current.title or '')):sub(1,120))
        V.storage_label_error=nil
        V.open_popup('\205\224\231\226\224\237\232\229 \241\237\232\236\234\224','storage_rename_v283')
    end
    if b('\211\196\192\203\200\210\220','delete_one',math.min(150,width))then
        V.storage_delete_target=current
        V.storage_delete_error=nil
        V.open_popup('\211\228\224\235\232\242\252 \245\240\224\237\232\235\232\249\229','storage_delete_one')
    end

    local rows,info=S.sorted(current,V.storage_sort)
    if V.storage_detail_key then
        local only={}
        for _,it in ipairs(rows)do
            if it.key==V.storage_detail_key then only[#only+1]=it end
        end
        if #only>0 then
            rows=only
            V.muted('\207\238\234\224\231\224\237 \237\224\233\228\229\237\237\251\233 \239\240\229\228\236\229\242 \183 '..tostring(only[1].name))
            if b('\207\206\202\192\199\192\210\220 \194\209\168','show_all_contents',math.min(200,width))then
                V.storage_detail_key=nil
                V.reset_list('storage_items')
            end
        else
            V.storage_detail_key=nil
        end
    end
    if V.storage_detail_key then
        V.text('\205\224\233\228\229\237\238: '..tostring(rows[1].qty or 0)..' \248\242.')
        if (rows[1].unknown_slots or 0)>0 then
            V.muted('\197\241\242\252 \241\235\238\242\251 \225\229\231 \239\238\228\242\226\229\240\230\228\184\237\237\238\227\238 \234\238\235\232\247\229\241\242\226\224: '..rows[1].unknown_slots)
        end
    else
        V.text('\207\240\229\228\236\229\242\238\226: '..info.total_qty..' \248\242.')
    end
    if current.kind=='trunk' then
        V.muted('\199\224\237\255\242\238 \241\235\238\242\238\226: '..tostring(current.occupied_slots or #current.rows)..
            ' / '..tostring(current.slots_count or 180))
    elseif current.source=='packet220_probe' then
        V.red('\207\240\229\228\226\224\240\232\242\229\235\252\237\251\233 \241\237\232\236\238\234: \239\238\235\237\251\233 \244\238\240\236\224\242 \253\242\238\227\238 \245\240\224\237\232\235\232\249\224 \229\249\184 \239\240\238\226\229\240\255\229\242\241\255.')
    end
    if V.storage_detail_key and #rows==1 then
        local item=rows[1]
        if not info.cross_server and item.bid then
            V.green('\206\246\229\237\234\224 \253\242\238\227\238 \239\240\229\228\236\229\242\224: '..DSP.money((item.qty or 0)*item.bid))
            V.muted('\214\229\237\224 \241\234\243\239\234\232: '..DSP.money(item.bid)..' / \248\242.')
        else
            V.muted('\205\229\242 \224\234\242\243\224\235\252\237\238\233 \246\229\237\251 \241\234\243\239\234\232 \228\235\255 \237\224\233\228\229\237\237\238\227\238 \239\240\229\228\236\229\242\224.')
        end
    else
        V.green('\206\246\229\237\234\224 \241\234\243\239\234\232 \226\241\229\227\238 \245\240\224\237\232\235\232\249\224: '..DSP.money(info.sell_to_buyers))
        V.muted('\207\238 \238\225\250\255\226\235\229\237\232\255\236: '..DSP.money(info.ask_value)..' \183 \237\229 \247\232\241\242\224\255 \239\240\232\225\251\235\252')
    end

    V.list_rows('storage_items',rows,82,function(it,i)
        V.row('storage_item_'..i,82,function(rw,x,y)
            V.at(x,y);V.text(V.fit(it.name,rw))
            V.at(x,y+30)
            V.muted(V.fit('\202\238\235\232\247\229\241\242\226\238: '..(it.qty and tostring(it.qty)..' \248\242.'or'\237\229\232\231\226\229\241\242\237\238'),rw))
            V.at(x,y+56)
            local total=(it.bid and it.qty)and DSP.money(it.bid*it.qty)or'\237\229\242 \238\246\229\237\234\232'
            V.muted(V.fit('\209\234\243\239\224\254\242: '..(it.bid and DSP.money(it.bid)or'?')..' / \248\242. \183 '..total,rw))
        end)
    end,{footer=false})
end

-- Deletion is a real modal confirmation; cancellation never changes snapshots.
local old_popups=V.popups
function V.popups()
    if old_popups then old_popups()end
    V.popup('CRR \238\242\234\224\242','storage_beta_rollback',function()
        V.text('\194\229\240\237\243\242\252 \241\242\224\225\232\235\252\237\243\254 Palatka AI \241 \238\225\251\247\237\251\236 \232\237\242\229\240\244\229\233\241\238\236?')
        V.muted('\210\229\241\242\238\226\251\233 \241\234\224\237\229\240 \225\243\228\229\242 \238\242\234\235\254\247\184\237. \205\224\241\242\240\238\233\234\232, \239\240\229\241\229\242\251 \232 \241\237\232\236\234\232 \237\229 \243\228\224\235\255\254\242\241\255.')
        if b('\207\206\196\210\194\197\208\196\200\210\220 \206\210\202\192\210','beta_rollback_confirm',230,false,true)then
            local ok,err=DSP.storage_beta_rollback()
            if ok then
                imgui.CloseCurrentPopup()
            else
                V.storage_rollback_error=tostring(err)
            end
        end
        V.inline()
        if b('\206\242\236\229\237\224','beta_rollback_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_rollback_error then V.red(V.fit(V.storage_rollback_error,imgui.GetContentRegionAvail().x))end
    end,{w=480,h=260})
    V.popup('\207\238\245\238\230\232\233 \225\224\227\224\230\237\232\234','storage_match_confirm',function()
        local review=V.storage_match_review
        local t=S.trunk_state()
        if not review or not t.snapshot or not t.review_needed
            or review.generation~=t.review_generation then
            V.muted('\221\242\238\242 \241\234\224\237 \243\230\229 \238\225\240\224\225\238\242\224\237 \232\235\232 \231\224\236\229\237\184\237 \237\238\226\251\236.')
            if b('\199\224\234\240\251\242\252','match_stale',120)then imgui.CloseCurrentPopup()end
            return
        end
        local matches=review.matches or {}
        if #matches==0 then
            V.muted('\209\238\245\240\224\237\184\237\237\251\245 \239\238\245\238\230\232\245 \225\224\227\224\230\237\232\234\238\226 \237\229\242.')
            if b('\199\224\234\240\251\242\252','match_empty',120)then imgui.CloseCurrentPopup()end
            return
        end
        review.selected=math.max(1,math.min(#matches,review.selected or 1))
        local match=matches[review.selected]
        local saved=S.find_snapshot(match.id)
        if not saved then
            V.red('\221\242\224 \241\238\245\240\224\237\184\237\237\224\255 \231\224\239\232\241\252 \243\228\224\235\229\237\224.')
            if b('\199\224\234\240\251\242\252','match_deleted',120)then imgui.CloseCurrentPopup()end
            return
        end
        V.apply_font((V.font_pixels or 18)*1.22)
        V.text(V.fit(tostring(saved.title or '\193\224\227\224\230\237\232\234'),imgui.GetContentRegionAvail().x))
        V.apply_font()
        V.text('\221\242\238 \242\238\242 \230\229 \225\224\227\224\230\237\232\234?')
        V.green('\209\238\226\239\224\228\224\229\242 \242\232\239\238\226 \239\240\229\228\236\229\242\238\226: '..match.shared)
        V.muted('\207\238\245\238\230\229\241\242\252 \241\238\241\242\224\226\224: '..match.similarity..'% \183 \253\242\238 \205\197 \226\229\240\238\255\242\237\238\241\242\252 \232 \237\229 ID \236\224\248\232\237\251.')
        V.muted('\207\238\228\242\226\229\240\228\232\242\252, \234\224\234\224\255 \236\224\248\232\237\224 \238\242\234\240\251\242\224, \236\238\230\229\248\252 \242\238\235\252\234\238 \242\251.')
        if #matches>1 then
            V.muted('\194\224\240\232\224\237\242 '..review.selected..' \232\231 '..#matches)
            if b('\196\208\211\195\206\201 \207\206\213\206\198\200\201','match_next',math.min(230,imgui.GetContentRegionAvail().x))then
                review.selected=review.selected%#matches+1
            end
        end
        imgui.Separator()
        if b('\196\192, \221\210\206 '..tostring(saved.title),'match_yes',math.min(310,imgui.GetContentRegionAvail().x),false,true)then
            local ok,updated=S.apply_latest_to_saved(saved.id)
            if ok then
                local _,idx=S.find_snapshot(updated.id)
                V.storage_selected=idx or 1
                V.storage_library_page='detail'
                V.storage_tab='library'
                V.storage_match_error=nil
                imgui.CloseCurrentPopup()
            else
                V.storage_match_error=tostring(updated)
            end
        end
        if b('\205\197\210, \221\210\206 \205\206\194\219\201','match_no_new',math.min(280,imgui.GetContentRegionAvail().x))then
            local snap=t.snapshot
            V.storage_name_target=snap
            V.storage_name_buf=imgui.new.char[128]()
            V.storage_name_error=nil
            t.review_needed=false
            imgui.CloseCurrentPopup()
            V.open_popup('\209\238\245\240\224\237\232\242\252 \225\224\227\224\230\237\232\234','storage_trunk_name')
        end
        if b('\205\197 \211\194\197\208\197\205 \183 \207\206\199\198\197','match_later',math.min(240,imgui.GetContentRegionAvail().x))then
            imgui.CloseCurrentPopup()
        end
        if V.storage_match_error then
            V.red(V.fit(V.storage_match_error,imgui.GetContentRegionAvail().x))
        end
    end,{w=495,h=410})
    V.popup('\209\238\245\240\224\237\232\242\252 \225\224\227\224\230\237\232\234','storage_trunk_name',function()
        local target=V.storage_name_target
        if not target then V.red('\205\229\242 \239\238\235\237\238\227\238 \241\237\232\236\234\224 \225\224\227\224\230\237\232\234\224.');return end
        V.text('\194\226\229\228\232 \241\226\238\184 \237\224\231\226\224\237\232\229 \241\238\245\240\224\237\184\237\237\238\227\238 \241\237\232\236\234\224')
        V.muted('\205\224\239\240\232\236\229\240: \204\238\255 \236\224\248\232\237\224 \241 \235\224\240\246\224\236\232 / \204\224\248\232\237\224 \241 \240\229\241\243\240\241\224\236\232.')
        V.muted('\209\235\229\228\243\254\249\229\229 \238\242\234\240\251\242\232\229 \228\240\243\227\238\227\238 \225\224\227\224\230\237\232\234\224 \205\197 \225\243\228\229\242 \232\236\229\242\252 \253\242\238 \237\224\231\226\224\237\232\229 \224\226\242\238\236\224\242\232\247\229\241\234\232.')
        imgui.SetNextItemWidth(-1)
        imgui.InputText('##storage_trunk_named_input',V.storage_name_buf,128)
        if b('\209\238\245\240\224\237\232\242\252 \239\238\228 \237\224\231\226\224\237\232\229\236','save_named_trunk',math.min(240,imgui.GetContentRegionAvail().x),false,true)then
            local name=DSP.to_cp(ffi.string(V.storage_name_buf))
            local ok,snapshot=S.save_named_trunk(target,name)
            if ok then
                V.storage_name_target=nil
                V.storage_name_error=nil
                V.storage_tab='library'
                V.storage_library_page='detail'
                for i,saved in ipairs(S.snapshots or {})do
                    if saved==snapshot then V.storage_selected=i;break end
                end
                imgui.CloseCurrentPopup()
            else
                V.storage_name_error=tostring(snapshot)
            end
        end
        if b('\206\242\236\229\237\224','cancel_named_trunk',120)then imgui.CloseCurrentPopup()end
        if V.storage_name_error then V.red(V.fit(V.storage_name_error,imgui.GetContentRegionAvail().x))end
    end,{w=460,h=330})
    V.popup('\209\226\238\255 \246\229\237\224','storage_price',function()
        local target,row=V.storage_price_target,V.storage_price_row
        if not target or not row then V.muted('\205\229\242 \226\251\225\240\224\237\237\238\227\238 \239\240\229\228\236\229\242\224');return end
        V.text(V.fit(row.name,imgui.GetContentRegionAvail().x))
        V.muted('\214\229\237\224 \231\224 \238\228\237\243 \248\242\243\234\243 \228\235\255 \240\224\241\247\184\242\224 \253\242\238\227\238 \241\237\232\236\234\224. 0 = \246\229\237\224 API.')
        M.compact_number(V.storage_price_buf,'value','storage_price_value',math.min(250,imgui.GetContentRegionAvail().x),0)
        if b('\209\238\245\240\224\237\232\242\252','price_apply',135,false,true)then
            local ok,err=S.set_manual_price(target,row,V.storage_price_buf.value)
            if ok then V.reset_list('storage_items');V.storage_price_target=nil;imgui.CloseCurrentPopup()
            else V.storage_price_error=err end
        end
        V.inline();if b('\206\242\236\229\237\224','price_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_price_error then V.red(V.storage_price_error)end
    end,{w=460,h=260})
    V.popup('\205\224\231\226\224\237\232\229 \241\237\232\236\234\224','storage_rename_v283',function()
        local target=V.storage_label_target
        if not target then return end
        V.muted('\221\242\238 \232\236\255 \242\238\235\252\234\238 \228\235\255 \241\237\232\236\234\224. ID \236\224\248\232\237\251 \224\226\242\238\236\224\242\232\247\229\241\234\232 \237\229 \238\239\240\229\228\229\235\255\229\242\241\255.')
        imgui.SetNextItemWidth(-1)
        imgui.InputText('##storage_name_input',V.storage_label_buf,128)
        if b('\209\238\245\240\224\237\232\242\252','rename_apply',135,false,true)then
            local label=DSP.to_cp(ffi.string(V.storage_label_buf))
            local ok,result=S.set_snapshot_label(target,label)
            if ok then
                V.storage_label_target=nil
                if type(result)=='table' then
                    for i,saved in ipairs(S.snapshots or {})do
                        if saved==result then V.storage_selected=i;break end
                    end
                    V.storage_library_page='detail'
                end
                imgui.CloseCurrentPopup()
            else V.storage_label_error=result end
        end
        V.inline();if b('\206\242\236\229\237\224','rename_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_label_error then V.red(V.storage_label_error)end
    end,{w=640,h=300})
    V.popup('\211\228\224\235\232\242\252 \245\240\224\237\232\235\232\249\229','storage_delete_one',function()
        local target=V.storage_delete_target
        if not target then V.muted('\213\240\224\237\232\235\232\249\229 \243\230\229 \237\229 \226\251\225\240\224\237\238.');return end
        V.text('\211\228\224\235\232\242\252 \171'..tostring(target.title or '\193\229\231 \237\224\231\226\224\237\232\255')..'\187?')
        V.muted('\211\228\224\235\255\229\242\241\255 \242\238\235\252\234\238 \231\224\239\232\241\252 Palatka AI. \207\240\229\228\236\229\242\251 \226 \232\227\240\229 \237\229 \236\229\237\255\254\242\241\255.')
        if b('\211\196\192\203\200\210\220','delete_one_confirm',150,false,true)then
            local ok,err=S.delete_snapshot(target)
            if ok then
                V.storage_delete_target=nil
                V.storage_delete_error=nil
                V.storage_selected=1
                V.storage_library_page='list'
                imgui.CloseCurrentPopup()
            else V.storage_delete_error=tostring(err) end
        end
        V.inline()
        if b('\206\242\236\229\237\224','delete_one_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_delete_error then V.red(V.storage_delete_error)end
    end,{w=470,h=250})
    V.popup('\206\247\232\241\242\232\242\252 \241\237\232\236\234\232?','storage_clear',function()
        V.text('\211\228\224\235\232\242\252 \241\238\245\240\224\237\184\237\237\251\229 \241\237\232\236\234\232 \248\234\224\244\238\226 \232 \225\224\227\224\230\237\232\234\238\226?')
        V.muted('\207\240\229\228\236\229\242\251 \226 \232\227\240\229 \238\241\242\224\237\243\242\241\255 \225\229\231 \232\231\236\229\237\229\237\232\233.')
        if b('\211\228\224\235\232\242\252 \241\237\232\236\234\232','confirm_clear',170,false,true)then
            local old=S.snapshots
            S.snapshots={};S.last_signature=nil;S.last_snapshot=nil;V.storage_selected=1;V.storage_library_page='list'
            local old_trunk=S.trunk and S.trunk.snapshot
            if S.trunk then S.trunk.snapshot=nil;S.trunk.pending=nil;S.trunk.status='idle';S.trunk.received=0 end
            if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
            if DSP.save_settings and not DSP.save_settings() then
                S.snapshots=old
                if S.trunk then S.trunk.snapshot=old_trunk;S.trunk.status='saved' end
                if DSP.settings then DSP.settings.storage_snapshots=old end
                V.storage_error='\205\229 \243\228\224\235\238\241\252 \241\238\245\240\224\237\232\242\252 \243\228\224\235\229\237\232\229';return
            end
            imgui.CloseCurrentPopup()
        end
        V.inline()
        if b('\206\242\236\229\237\224','cancel_clear',120)then imgui.CloseCurrentPopup()end
    end,{w=480,h=230})
end

  end
  module_storage_ui()

  -- Read-only cabinet/warehouse observation alongside unchanged trade hooks.
  do
    local live=DSP.live
    if live and type(live.handle)=='function' and not live._storage_probe_wrapped then
      local previous=live.handle
      live.handle=function(iface,sub,raw)
        if iface==52 and DSP.storage_probe and DSP.storage_probe.on_packet then
          local ok,err=pcall(DSP.storage_probe.on_packet,sub,raw)
          if not ok and DSP.flog then DSP.flog('STORAGE observer: '..tostring(err)) end
        end
        return previous(iface,sub,raw)
      end
      live._storage_probe_wrapped=true
    end
  end

  do
    local V=DSP.ui21
    if V and type(V.set_screen)=='function' and not V._storage_screen_wrapped then
      local previous=V.set_screen
      V.set_screen=function(id)
        if id=='storage' then
          V.storage_tab='scan'
          if V.storage_scan_mode=='inventory' then V.storage_scan_mode='trunk' end
          V.storage_scan_mode=V.storage_scan_mode or 'trunk'
          V.storage_library_page='list'
          if V.reset_list then V.reset_list('storage_scan_panel') end
        end
        return previous(id)
      end
      V._storage_screen_wrapped=true
    end
  end

  -- Palatka AI 2.8.5: accurate trade and passive pawnshop read-only scanner.
  if DSP._v285_installed then
    return install_v296()
  end
  local applied,err=pcall(function()
    do
      local function _v285_arb()
-- Compare real offers; budget limits apply before profitability filters.
local M = DSP.market
local cache, signature, expires
-- Missing shops reported by the player are hidden temporarily per server.
-- No API timestamp is proof that a physical stall still exists.
M.missing_shops = M.missing_shops or DSP.settings.arb_missing_shops or {}
DSP.settings.arb_missing_shops=M.missing_shops
M.missing_revision = M.missing_revision or 0
local function missing_key(shop)
    local id=tonumber(shop)
    if not id or id<=0 or id>99999 or id%1~=0 then return nil end
    return tostring(M.state.sid or DSP.settings.server or 0)..':'..tostring(math.floor(id))
end
local function record_deadline(record)
    if type(record)=='table' then return tonumber(record.until_ts) or 0 end
    return tonumber(record) or 0
end
function M.missing_deadline(record)
    return record_deadline(record)
end
local function changed_missing()
    M.missing_revision=(M.missing_revision or 0)+1
    if M.invalidate_arbitrage then M.invalidate_arbitrage() end
    if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
    elseif DSP.save_settings then pcall(DSP.save_settings) end
end
-- Numeric entries remain compatible with the v2.2.15 settings file.
-- A confirmed game rejection persists longer and does not reappear merely
-- because the same stale API payload was downloaded again.
function M.is_shop_missing(shop, now, offer_ts)
    local key=missing_key(shop)
    if not key then return true end
    now=now or os.time()
    local record=M.missing_shops[key]
    if record==nil then return false end
    local deadline=record_deadline(record)
    if deadline<=now then
        M.missing_shops[key]=nil
        return false
    end
    if type(record)=='table' and record.reason=='game_not_found' then
        local observed=tonumber(offer_ts) or 0
        local blocked=tonumber(record.snapshot_ts) or 0
        local since=tonumber(record.since) or now
        -- A truly newer stall *observation*, fetched after the rejection,
        -- may be legitimate. Old API refreshes cannot erase a server verdict.
        if observed>blocked and observed>since and observed<=now+60
            and now>=since+300 and (tonumber(M.state.received_at) or 0)>since then
            return false
        end
    end
    return true
end
function M.mark_shop_missing(shop, minutes)
    local key=missing_key(shop)
    if not key then return false end
    local duration=math.max(60,math.min(3600,math.floor((tonumber(minutes) or 30)*60)))
    M.missing_shops[key]=os.time()+duration
    changed_missing()
    return true
end
function M.mark_shop_missing_from_game(shop, timestamp)
    local key=missing_key(shop)
    if not key then return false end
    local now=tonumber(timestamp) or os.time()
    local latest=0
    for _,row in ipairs(M.state.rows or {}) do
        for _,side in ipairs({row.sell or {},row.buy or {}}) do
            for _,offer in ipairs(side.offers or {}) do
                if tostring(offer.shop)==tostring(shop) then
                    latest=math.max(latest,tonumber(offer.ts) or 0)
                end
            end
        end
    end
    M.missing_shops[key]={reason='game_not_found',since=now,
        until_ts=now+21600,snapshot_ts=latest}
    changed_missing()
    -- /findilavka feedback can arrive after the UI was closed. Persist now,
    -- rather than relying on an ImGui frame to flush deferred settings.
    if DSP.save_settings then pcall(DSP.save_settings) end
    return true
end
function M.restore_shop(shop)
    local key=missing_key(shop)
    if not key then return false end
    M.missing_shops[key]=nil
    changed_missing()
    return true
end

-- Match server notifications only while a /findilavka request is outstanding.
-- They must never be attributed to an unrelated chat or arbitrary API record.
function M.on_shop_lookup_feedback(text, timestamp)
    local pending=M.pending_find
    if not pending then return false end
    local now=tonumber(timestamp) or os.time()
    if now-(tonumber(pending.at) or 0)>8 or now<(tonumber(pending.at) or 0) then
        M.pending_find=nil
        return false
    end
    local actual=DSP.detect_server and DSP.detect_server()
    if tonumber(pending.sid)~=tonumber(M.state.sid) or (actual and tonumber(actual)~=tonumber(pending.sid)) then
        M.pending_find=nil
        return false
    end
    local cleaned=DSP.lower(DSP.clean_text(text or '')):gsub('%s+',' ')
    local has_stall=cleaned:find('\235\224\226\234' ,1,true) ~= nil
    local no_stall=cleaned:find('\237\229 \241\243\249\229\241\242\226\243\229\242' ,1,true)
        or cleaned:find('\237\229 \237\224\233\228\229\237\224' ,1,true)
        or cleaned:find('\237\229 \237\224\233\228\229\237\238' ,1,true)
        or cleaned:find('\238\242\241\243\242\241\242\226\243\229\242' ,1,true)
    if not has_stall or not no_stall then return false end
    -- Prefer an explicit number, if the server includes one. A different
    -- number means this response is not for our request.
    local numbered=cleaned:match('#%s*(%d+)')
    if numbered and tonumber(numbered)~=tonumber(pending.shop) then return false end
    M.pending_find=nil
    if not M.mark_shop_missing_from_game(pending.shop,now) then return false end
    if DSP.shop_marker and DSP.shop_marker.clear then DSP.shop_marker.clear() end
    if DSP.add_log then DSP.add_log('\200\227\240\224: \235\224\226\234\224 #'..tostring(pending.shop)..' \237\229 \241\243\249\229\241\242\226\243\229\242. \211\228\224\235\229\237\224 \232\231 API-\236\224\240\248\240\243\242\238\226.','error') end
    if DSP.flog then DSP.flog('FINDILAVKA missing shop='..tostring(pending.shop)..' sid='..tostring(pending.sid)) end
    return true
end

local function checkpoint()
    local hook=M.arb_yield
    if hook and hook.owner==coroutine.running() then hook.checkpoint() end
end
local function sort_rows(rows,less)
    local hook=M.arb_yield
    if hook and hook.owner==coroutine.running() then return hook.sort(rows,less) end
    return table.sort(rows,less)
end

function M.should_refresh(now)
    if M.state.status == 'loading' then return false end
    if (tonumber(M.state.next_auto_retry) or 0) > (now or os.time()) then return false end
    local interval = math.max(180, tonumber(DSP.settings.refresh_seconds) or 300)
    return (now or os.time()) - (M.state.last_request or 0) >= interval
end

local function integer(value, default)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return default or 0 end
    return math.max(0, math.floor(n))
end

local function tax_factor(tax_bp)
    return 10000 - math.min(10000, integer(tax_bp, 200))
end

local function after_tax(gross, tax_bp)
    local factor = tax_factor(tax_bp)
    -- Avoid multiplying a large gross amount by 10000 before dividing.
    return math.floor(gross / 10000) * factor + math.floor((gross % 10000) * factor / 10000)
end

local function offer_qty(row,side,offer,now)
    if M.offer_quantity then return M.offer_quantity(row,side,offer,now) end
    return integer(offer.qty),{source='api'}
end
local function fresh(offer, now, filters)
    if M.state.status=='cache' or M.state.status=='error' then return false end
    if M.is_shop_missing(offer.shop,now,offer.ts) then return false end
    local ts = integer(offer.ts)
    if ts == 0 then return filters.include_unknown ~= false end
    if ts > now + 60 then return false end
    local max_age = integer(filters.max_age, 300)
    return max_age == 0 or now - ts <= max_age
end

-- Build a non-overlapping purchase/resale plan. A shop's stock or demand
-- cannot be committed twice just because it matches several other stalls.
-- Greedy allocation prioritizes unit profit (or ROI under a cash budget).
local function opportunities(filters, now, rows, selections)
    local candidates, out = {}, {}
    local tax_bp = math.min(10000, integer(filters.tax_bp, DSP.settings.tax_bp or 200))
    local budget = integer(filters.budget)
    local remaining_budget = budget > 0 and budget or math.huge
    local max_qty = integer(filters.max_qty)
    local sellers_left, buyers_left = {}, {}
    local min_profit = integer(filters.min_profit)
    local min_roi = tonumber(filters.min_roi) or 0
    local reserve_pct = math.floor(math.max(0, math.min(90, tonumber(filters.safety_pct) or 0)))
    local min_unit_profit = integer(filters.min_unit_profit)
    local max_buy_price = integer(filters.max_buy_price)
    local min_stock = integer(filters.min_stock)
    local shop_mode = integer(filters.shop_mode)
    for _, row in ipairs(rows or M.state.rows or {}) do
        for _, seller in ipairs(row.sell.offers or {}) do
            if (not selections or selections.sell[seller]) and fresh(seller, now, filters) then
                local seller_qty,seller_meta=offer_qty(row,'sell',seller,now)
                sellers_left[seller] = seller_qty
                for _, buyer in ipairs(row.buy.offers or {}) do
                    checkpoint()
                    local p_buy, p_sell = integer(seller.price), integer(buyer.price)
                    local buyer_qty,buyer_meta=offer_qty(row,'buy',buyer,now)
                    if (not selections or selections.buy[buyer])
                        and (seller.ench or 0) == (buyer.ench or 0)
                        and fresh(buyer, now, filters)
                        and p_buy > 0 and p_sell > p_buy
                        and (max_buy_price == 0 or p_buy <= max_buy_price)
                        and (shop_mode == 0
                            or (shop_mode == 1 and tostring(seller.shop)==tostring(buyer.shop))
                            or (shop_mode == 2 and tostring(seller.shop)~=tostring(buyer.shop)))
                        and seller_qty >= math.max(1, min_stock)
                        and buyer_qty >= math.max(1, min_stock) then
                        local demand_qty = buyer_qty
                        if not buyer.verified_at then
                            local factor=100-reserve_pct
                            -- Exact up to 2^53: do not overflow precision by multiplying
                            -- the full inventory count before dividing by 100.
                            demand_qty=math.floor(demand_qty/100)*factor
                                + math.floor((demand_qty%100)*factor/100)
                        end
                        -- On a one-unit quote, a 10% reserve cannot be a
                        -- fractional item. Retain 1 as a *potential* trade,
                        -- not as a guarantee that the order still exists.
                        if buyer_qty>0 and reserve_pct<100 then
                            demand_qty=math.max(1,demand_qty)
                        end
                        -- Several sellers can share one buyer. Do not replenish
                        -- the same demand pool for every candidate!
                        if buyers_left[buyer]==nil then buyers_left[buyer] = demand_qty end
                        -- Tax is rounded on the batch, not on each individual item.
                        local fraction = ((p_sell % 10000) * tax_factor(tax_bp) % 10000) / 10000
                        local unit_profit = after_tax(p_sell, tax_bp) - p_buy + fraction
                        if unit_profit > 0 and unit_profit >= min_unit_profit then
                            candidates[#candidates+1] = {
                                row=row, seller=seller, buyer=buyer,
                                qty_seller=seller_qty,qty_buyer=buyer_qty,
                                seller_source=seller_meta and seller_meta.source or 'api',
                                buyer_source=buyer_meta and buyer_meta.source or 'api',
                                p_buy=p_buy, p_sell=p_sell, unit_profit=unit_profit,
                                unit_roi=unit_profit / p_buy,
                            }
                        end
                    end
                end
            end
        end
    end
    sort_rows(candidates, function(a, b)
        local av = budget > 0 and a.unit_roi or a.unit_profit
        local bv = budget > 0 and b.unit_roi or b.unit_profit
        if av ~= bv then return av > bv end
        if a.unit_profit ~= b.unit_profit then return a.unit_profit > b.unit_profit end
        if a.row.key ~= b.row.key then return a.row.key < b.row.key end
        if a.p_buy ~= b.p_buy then return a.p_buy < b.p_buy end
        if tostring(a.seller.shop) ~= tostring(b.seller.shop) then
            return tostring(a.seller.shop) < tostring(b.seller.shop)
        end
        return tostring(a.buyer.shop) < tostring(b.buyer.shop)
    end)
    for _, c in ipairs(candidates) do
        checkpoint()
        local seller, buyer = c.seller, c.buyer
        -- Unverified buy demand is a dated quote, not a reservation. Leave a
        -- percentage uncommitted across all routes using this exact offer.
        -- A player-confirmed quantity can be used without this reserve.
        local available = math.min(sellers_left[seller] or 0, buyers_left[buyer] or 0)
        if available > 0 and remaining_budget >= c.p_buy then
            local qty = available
            if max_qty > 0 then qty = math.min(qty, max_qty) end
            -- Keep integer arithmetic inside IEEE-754's exact integer range.
            qty = math.min(qty, math.floor(9007199254740991 / math.max(c.p_buy,c.p_sell)))
            if remaining_budget ~= math.huge then
                if filters.allow_partial == false and qty * c.p_buy > remaining_budget then
                    qty = 0
                else
                    qty = math.min(qty, math.floor(remaining_budget / c.p_buy))
                end
            end
            if qty > 0 then
                local cost = qty * c.p_buy
                local revenue = after_tax(qty * c.p_sell, tax_bp)
                local profit = revenue - cost
                local roi = profit / cost * 100
                if profit > 0 and profit >= min_profit and roi >= min_roi then
                    out[#out+1] = {
                        row=c.row, name=c.row.display, ench=c.row.ench,
                        sell_offer=seller, buy_offer=buyer,
                        p_buy=c.p_buy, p_sell=c.p_sell,
                        qty_seller=c.qty_seller, qty_buyer=c.qty_buyer,
                        seller_source=c.seller_source, buyer_source=c.buyer_source,
                        available_qty=available, tradable_qty=qty, partial=qty<available,
                        total_cost=cost, net_revenue=revenue, net_profit=profit,
                        roi=roi, unit_profit=c.unit_profit,
                        sell_age=seller.ts or 0, buy_age=buyer.ts or 0,
                        shared_stock=available<math.min(c.qty_seller,c.qty_buyer),
                        same_shop=tostring(seller.shop)==tostring(buyer.shop),
                        demand_verified=(tonumber(buyer.verified_at) or 0)>0,
                        reserve_pct=(tonumber(buyer.verified_at) or 0)>0 and 0 or reserve_pct,
                    }
                    sellers_left[seller] = sellers_left[seller] - qty
                    buyers_left[buyer] = buyers_left[buyer] - qty
                    remaining_budget = remaining_budget - cost
                end
            end
        end
    end
    local sort = tonumber(filters.sort) or 1
    sort_rows(out, function(a,b)
        local av, bv = a.net_profit, b.net_profit
        if sort == 2 then av,bv = a.unit_profit,b.unit_profit end
        if sort == 3 then av,bv = a.roi,b.roi end
        if av ~= bv then return av > bv end
        if a.name ~= b.name then return a.name < b.name end
        if tostring(a.sell_offer.shop) ~= tostring(b.sell_offer.shop) then
            return tostring(a.sell_offer.shop) < tostring(b.sell_offer.shop)
        end
        return tostring(a.buy_offer.shop) < tostring(b.buy_offer.shop)
    end)
    return out
end

-- Selection keys are scoped to an item group; distinct price bands stay separate.
function M.offer_key(offer)
    return table.concat({tostring(offer.shop), tostring(offer.price), tostring(offer.owner)}, '\0')
end

local function selected_offers(offers, selection)
    local chosen, total = {}, 0
    local listed = {}
    for _, offer in ipairs(selection or {}) do listed[offer] = true end
    for _, offer in ipairs(offers or {}) do
        if selection == nil or selection[offer] or selection[M.offer_key(offer)] or listed[offer] then
            chosen[offer] = true
            total = total + integer(offer.qty)
        end
    end
    return chosen, total
end

-- Recalculate an alternative plan from selected source offers, never from already
-- allocated routes. nil selects all; {} selects none. Source quantities stay intact.
-- Options override the saved filters; extra is charged once for a nonempty plan.
function M.plan_offers(group, sellers, buyers, options)
    local plan = {qty=0, planned=0, cost=0, gross=0, revenue=0, fee=0, extra=0, profit=0, routes={}, supply=0, demand=0}
    if not group or not group.row then return plan end
    local row = group.row
    local selections = {}
    selections.sell, plan.supply = selected_offers(row.sell.offers, sellers)
    selections.buy, plan.demand = selected_offers(row.buy.offers, buyers)
    local filters = {}
    for key, value in pairs(DSP.settings.arb_filters or {}) do filters[key] = value end
    for key, value in pairs(options or {}) do filters[key] = value end
    plan.routes = opportunities(filters, os.time(), {row}, selections)
    for _, route in ipairs(plan.routes) do
        plan.qty = plan.qty + route.tradable_qty
        plan.cost = plan.cost + route.total_cost
        plan.gross = plan.gross + route.p_sell * route.tradable_qty
        plan.revenue = plan.revenue + route.net_revenue
        plan.profit = plan.profit + route.net_profit
    end
    plan.planned = plan.qty
    plan.fee = plan.gross - plan.revenue
    if plan.qty > 0 then
        plan.extra = integer(filters.extra)
        plan.profit = plan.profit - plan.extra
    end
    return plan
end

DSP.arbitrage = DSP.arbitrage or {}
DSP.arbitrage.plan_offers = M.plan_offers
DSP.arbitrage.offer_key = M.offer_key

function M.arbitrage()
    return opportunities({max_age=600, include_unknown=false, safety_pct=10}, os.time())
end

function M.arbitrage_filtered()
    local f = DSP.settings.arb_filters or {}
    local now = os.time()
    local sig = table.concat({M.state.sid or 0, M.state.version or 0, M.state.status or '', DSP.settings.tax_bp or 200,
        f.budget or 0, f.min_profit or 0, f.min_roi or 0, f.sort or 1,
        f.max_age or 300, tostring(f.include_unknown == true),
        tostring(f.allow_partial ~= false), f.max_qty or 0, f.safety_pct or 0,
        f.tax_bp or 'global',f.min_unit_profit or 0,f.max_buy_price or 0,
        f.min_stock or 0,f.shop_mode or 0,M.missing_revision or 0}, '|')
    if cache and sig == signature and not M.arb_dirty and now < expires then return cache end
    M.accuracy_next_expiry=nil
    cache, signature = opportunities(f, now), sig
    expires = math.huge
    local max_age = integer(f.max_age,300)
    for _,record in pairs(M.missing_shops or {})do
        local deadline=record_deadline(record)
        if deadline>now then expires=math.min(expires,deadline)end
    end
    for _, row in ipairs(M.state.rows or {}) do
            for _, side in ipairs({row.sell,row.buy}) do
                for _, offer in ipairs(side.offers or {}) do
                    local ts = integer(offer.ts)
                    local deadline = ts + max_age + 1
                    if max_age > 0 and ts > 0 and deadline > now then expires = math.min(expires,deadline) end
                    if ts > now+60 then expires = math.min(expires,ts-60) end
                end
            end
    end
    if M.accuracy_next_expiry then expires=math.min(expires,M.accuracy_next_expiry) end
    M.arb_dirty = false
    return cache
end

function M.offer_freshness(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return '\226\240\229\236\255 \237\229\232\231\226\229\241\242\237\238', 'muted' end
    local age = os.time() - ts
    if age < -60 then return '\238\248\232\225\234\224 \226\240\229\236\229\237\232', 'warn' end
    if age < 180 then return '\241\226\229\230\229\229', 'good' end
    if age < 600 then return math.floor(age / 60) .. ' \236\232\237 \237\224\231\224\228', 'warn' end
    return math.floor(age / 60) .. ' \236\232\237 \237\224\231\224\228', 'muted'
end

-- Direct observations from a currently open mobile stall are independent of
-- the web API. Even if the API is stale/empty, detect its own bid/ask spread.
-- Lack of server-provided quantity is explicitly unknown, never x1.
function M.live_shop_spreads()
    local shop=DSP.live and DSP.live.shop
    if not shop or (shop.menu_closed or 0)>0 or not shop.num or shop.num==''
       or not shop.owner or shop.owner=='' then return {} end
    if shop.server and tonumber(shop.server)~=tonumber(DSP.settings.server) then return {} end
    if os.time()-(shop.items_updated or 0)>120 then return {} end
    local sells={}
    for _,it in ipairs(shop.sell or{}) do
        local key=DSP.item_key(it.name,it.ench)
        if tonumber(it.price) and it.price>0 and
           (not sells[key] or it.price<sells[key].price) then sells[key]=it end
    end
    local results={}
    local factor=tax_factor(DSP.settings.tax_bp)
    for _,buyer in ipairs(shop.buy or{}) do
        local seller=sells[DSP.item_key(buyer.name,buyer.ench)]
        if seller and tonumber(buyer.price) and buyer.price>0 then
            local margin=after_tax(buyer.price,DSP.settings.tax_bp)-seller.price
            if margin>0 then
                local sq=tonumber(seller.qty);local bq=tonumber(buyer.qty)
                local confirmed=sq and bq and sq>0 and bq>0
                local count=confirmed and math.min(sq,bq) or nil
                results[#results+1]={name=buyer.name,ench=buyer.ench,
                    shop=shop.num,owner=shop.owner,buy_price=seller.price,
                    sell_price=buyer.price,profit_unit=margin,
                    quantity=count,verified_quantity=confirmed and true or false,
                    source='opened_shop',updated=shop.items_updated}
            end
        end
    end
    table.sort(results,function(a,b)return a.profit_unit>b.profit_unit end)
    return results
end

-- Cheap diagnostic summary from the current market, memoized per revision.
function M.arbitrage_visibility()
    local st=M.state;local c=M._arb_visibility
    local key=tostring(st.sid)..':'..tostring(st.version)..':'..tostring(DSP.settings.tax_bp)
    if c and c.key==key then return c.value end
    local result={pairs=0,same_shop=0,only_one=0,rows=#(st.rows or{})}
    for _,row in ipairs(st.rows or{})do
        if row.sell and row.buy and (row.sell.min or 0)>0
           and (row.buy.max or 0)>(row.sell.min or math.huge) then
            result.pairs=result.pairs+1
            local one=(row.sell.qty or 0)<=1 or (row.buy.qty or 0)<=1
            if one then result.only_one=result.only_one+1 end
            for _,s in ipairs(row.sell.offers or{})do
                for _,b in ipairs(row.buy.offers or{})do
                    if s.shop==b.shop and after_tax(b.price,DSP.settings.tax_bp)>s.price then
                        result.same_shop=result.same_shop+1
                        break
                    end
                end
            end
        end
    end
    M._arb_visibility={key=key,value=result}
    return result
end

      end
      _v285_arb()
    end

    do
      local function _v285_accuracy()
-- Market quantity reconciliation. No network calls, no packet writes.
-- API figures remain immutable; an observed game quantity is temporary evidence,
-- never a guarantee that a different player has not traded in the meantime.
local M=DSP.market
M.accuracy=M.accuracy or {}
local A=M.accuracy
A.ttl_seconds=90
local function unsigned(value)
    local n=tonumber(value)
    if n and n==n and n>=0 and n<=1000000000 and n%1==0 then return n end
end
local function equal(a,b)
    return DSP.lower(DSP.trim(tostring(a or '')))==DSP.lower(DSP.trim(tostring(b or '')))
end
local function rows_quantity(rows,row,side,offer)
    local wanted=row.key or DSP.item_key(row.name or '',row.ench or 0)
    local count,found=0,0
    for _,item in ipairs(rows or {})do
        if DSP.item_key(item.name or '',item.ench or 0)==wanted
            and tonumber(item.price)==tonumber(offer.price) then
            found=found+1
            if item.qty_known~=true then return nil end
            local q=unsigned(item.qty)
            if not q then return nil end
            count=count+q
            if count>1000000000 then return nil end
        end
    end
    if found>0 then return count,found end
end
-- Only confirmed packet quantities for the *same shop, server, owner, item, price, side*.
-- Completeness is not claimed: only observed matching rows are counted.
function A.quantity(row,side,offer,now)
    if not row or (side~='sell' and side~='buy') or not offer then return nil end
    now=tonumber(now) or os.time()
    local sid=tonumber(M.state and M.state.sid)
    local shop=tonumber(offer.shop)
    local owner=tostring(offer.owner or '')
    -- Never join anonymous API stalls to live scans by numeric id alone.
    if not sid or not shop or owner=='' or owner=='?' then return nil end
    local live=DSP.live and DSP.live.shop
    -- Recompute the market once a currently-loading native fragment has
    -- settled, even on clients without the optional shop-store worker.
    if live and tonumber(live.server)==sid and tonumber(live.num)==shop
        and (live.menu_closed or 0)==0 and equal(live.owner,offer.owner) then
        local stamp=tonumber(live.items_updated) or 0
        if stamp>0 and now-stamp>=0 and now-stamp<2
            and live.scan_complete~=true then
            M.accuracy_next_expiry=math.min(M.accuracy_next_expiry or math.huge,stamp+2)
        end
    end
    if live and tonumber(live.server)==sid
        -- Native pages can arrive as fragments: wait for the 2-second quiet
        -- window unless the existing scan worker already marked it stable.
        and (live.scan_complete==true or now-(tonumber(live.items_updated) or now)>=2)
        and tonumber(live.num)==shop and (live.menu_closed or 0)==0
        and equal(live.owner,offer.owner)
        and now-(tonumber(live.items_updated) or 0)>=0
        and now-(tonumber(live.items_updated) or 0)<=A.ttl_seconds then
        local n,slots=rows_quantity(live[side],row,side,offer)
        if n then
            local seen=tonumber(live.items_updated) or now
            M.accuracy_next_expiry=math.min(M.accuracy_next_expiry or math.huge,seen+A.ttl_seconds+1)
            return n,{source='game_observed',at=seen,slots=slots,complete=false}
        end
    end
    local store=DSP.shop_store
    local saved=store and store.get_by_num and store.get_by_num(shop,sid)
    if saved and equal(saved.owner,offer.owner) then
        local at=tonumber(saved.at) or 0
        if at>0 and now-at>=0 and now-at<=A.ttl_seconds then
            local n,slots=rows_quantity(saved[side],row,side,offer)
            if n then
                M.accuracy_next_expiry=math.min(M.accuracy_next_expiry or math.huge,at+A.ttl_seconds+1)
                return n,{source='recent_scan',at=at,slots=slots,complete=false}
            end
        end
    end
end
function M.offer_quantity(row,side,offer,now)
    local game,meta=A.quantity(row,side,offer,now)
    if game~=nil then return game,meta end
    local api=unsigned(offer and offer.qty)
    return api or 0,{source='api',at=offer and offer.ts or 0,complete=false}
end
return true

      end
      _v285_accuracy()
    end

    do
      local function _v285_pawn()
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
local CP_GIVE='\xf1\xe4\xe0\xf2\xfc' -- sdat (hand over / pawn)
local CP_ITEM='\xef\xf0\xe5\xe4\xec\xe5\xf2' -- predmet
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
    if is_lombard_text(title) or is_lombard_text(text) then return true end
    -- Nested pawnshop screens may be titled "Choose item" without "Lombard".
    -- Only trust them for an already recognized, recent pawnshop session.
    local sess=L.session
    if not sess or not sess.pawn_context or os.time()-(sess.last or 0)>20 then return false end
    local header=lower(clean(title))
    return header:find(CP_ITEM,1,true)~=nil or header:find(CP_GIVE,1,true)~=nil
end
local function side_from(title,text)
    local q=lower(clean(title)..' '..clean(text))
    if q:find(CP_GIVE,1,true) or q:find(CP_BUY,1,true) or q:find(CP_PURCHASE,1,true) then return 'buy' end
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
    n=n:gsub('^%[%d+%]%s*',''):gsub('^%d+[%.%)]%s*','')
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
    L.session={id=tonumber(id) or -1,title=clean(title),started=os.time(),last=os.time(),pages={},items={},order={},history_seen={},pawn_context=true}
    return L.session
end
local function get_session(id,title)
    local now=os.time();local s=L.session
    if not s or now-(s.last or 0)>20 or
        (s.id~=tonumber(id) and tonumber(id)~=nil and not s.pawn_context) then
        s=new_session(id,title)
    end
    s.id=tonumber(id) or s.id
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
        if #rows>0 then commit_session(s,L.auto_scan and 'auto_pages' or 'passive') end
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
-- Store only an explicitly reviewed native observation, not an automatic trade.
function L.save_observation(rows,source)
    if type(rows)~='table' or #rows==0 or #rows>180 then return false,'no rows' end
    local session=new_session(-1,'Lombard native observation')
    session.page_count=1
    for _,item in ipairs(rows) do
        if type(item)=='table' and type(item.name)=='string'
            and tonumber(item.price) and tonumber(item.price)>0 then
            local key=tostring(item.key or item.name..':'..item.price)
            if not session.items[key] then
                session.items[key]=item
                session.order[#session.order+1]=key
            end
        end
    end
    if #session.order==0 then return false,'no recognized items' end
    return commit_session(session,source or 'packet_unverified')
end
function L.start_auto()
    if not sampIsDialogActive or not sampIsDialogActive() then
        if L.packet_probe and L.packet_probe.arm then
            L.packet_probe.arm(35)
            if DSP.notify then DSP.notify('Lombard: listening for native pawnshop menu (35 sec)')end
            return true
        end
        return false
    end
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
        pcall(sampRegisterChatCommand,'crrlombardui',function()
            if DSP.ui21 and DSP.ui21.set_screen then DSP.ui21.set_screen('lombard') end
        end)
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
      end
      _v285_pawn()
    end

    do
      local function _v285_pawn_packets()
-- Passive native pawnshop menu inspection. The packet layout is NOT
-- verified against a real pawnshop dump; all entries are observational only.
local L=DSP.lombard
if not L then return false end
local P={active=false,status='idle',until_ts=0,packets=0,tagged=0,
    ignored=0,candidates={},items={},order={},verified_label=false}
L.packet_probe=P
local MAX_BYTES,MAX_ROWS,MAX_CANDIDATES=100000,180,12
local function int(v,cap)
    local n=tonumber(v)
    if n and n==n and n>=0 and n<=cap and n%1==0 then return n end
end
local function lower(s)
    s=tostring(s or '')
    return DSP.lower and DSP.lower(s) or s:lower()
end
local function pawn_text(s)
    s=lower(s)
    return s:find('\xeb\xee\xec\xe1\xe0\xf0\xe4',1,true)~=nil
        or s:find('\208\187\208\190\208\188\208\177\208\176\209\128\208\180',1,true)~=nil
        or s:find('pawnshop',1,true)~=nil or s:find('pawn',1,true)~=nil
end
function P.arm(seconds)
    local duration=int(seconds or 35,60) or 35
    if duration<5 then duration=35 end
    P.active=true;P.status='listening';P.until_ts=os.time()+duration
    P.packets=0;P.tagged=0;P.ignored=0;P.candidates={};P.items={};P.order={}
    P.verified_label=false
    return true
end
function P.stop()
    P.active=false;P.status='review';return true
end
function P.state()
    if P.active and os.time()>P.until_ts then P.stop() end
    return P
end
local function has_known_game_name(item)
    return type(item)=='table' and type(item.name)=='string' and item.name~=''
end
local function recognize(item,index,tag)
    if type(item)~='table' then return nil end
    local explicit_price=int(item.price or item.cost or item.unit_price or item.unitPrice,9007199254740991)
    if not explicit_price or explicit_price<1 then return nil end
    local row
    if DSP.item_registry and DSP.item_registry.from_node then
        local ok,value=pcall(DSP.item_registry.from_node,item,'buy',index)
        if ok and value then row=value end
    end
    if not row and has_known_game_name(item) and L.parse_dialog then
        local lines=L.parse_dialog(tag or '',item.name..'\t'..tostring(explicit_price))
        row=lines[1]
    end
    if not row then return nil end
    row.side='buy'
    row.price=explicit_price
    return row
end
local function nodes(obj)
    if type(obj)~='table' then return nil end
    if type(obj.items)=='table' then return obj.items end
    if type(obj.rows)=='table' then return obj.rows end
    if type(obj.data)=='table' then
        if type(obj.data.items)=='table' then return obj.data.items end
        if type(obj.data.rows)=='table' then return obj.data.rows end
    end
end
function L.on_packet(iface,sub,raw)
    local active=P.state().active
    if type(raw)~='string' or #raw<2 or #raw>MAX_BYTES then return false end
    -- A labeled pawnshop packet may be observed passively. Unknown packet
    -- layouts are explored only during the explicit 35-second scan window.
    if not active and not pawn_text(raw) then return false end
    local ok,obj=pcall(decodeJson,raw:gsub('%z+$',''))
    if not ok or type(obj)~='table' then return false end
    local packet_type=int(obj.type,255)
    if packet_type==8 or packet_type==13 or packet_type==28 or
        (packet_type==1 and tonumber(sub)==2) or tonumber(iface)==57 then
        P.ignored=P.ignored+1;return false
    end
    local label=tostring(obj.title or obj.header or obj.caption or obj.name or
        (type(obj.data)=='table' and obj.data.title) or '')
    local labeled=pawn_text(label)
    if not active and not labeled then return false end
    local slot_list=nodes(obj)
    if not slot_list then
        if active then
            P.packets=P.packets+1
            if #P.candidates<MAX_CANDIDATES then
                P.candidates[#P.candidates+1]={iface=tonumber(iface),sub=tonumber(sub),
                    type=packet_type,rows=0,label=labeled}
            end
        end
        return false
    end
    if #slot_list>MAX_ROWS then return false end
    P.packets=P.packets+1
    if labeled then P.tagged=P.tagged+1;P.verified_label=true end
    local accepted=0
    for i,item in ipairs(slot_list)do
        local row=recognize(item,i,label)
        if row then
            local key=tostring(row.key or row.name)..':'..tostring(row.price)
            if not P.items[key] then P.order[#P.order+1]=key end
            P.items[key]=row;accepted=accepted+1
        end
    end
    if #P.candidates<MAX_CANDIDATES then
        P.candidates[#P.candidates+1]={iface=tonumber(iface),sub=tonumber(sub),
            type=packet_type,rows=accepted,label=labeled}
    end
    -- Never write any native observation automatically: the server has not
    -- supplied a proven end-of-list marker or stable pawnshop session ID.
    if accepted>0 then P.status='preview_ready' end
    return accepted>0
end
function P.preview()
    local rows={}
    for _,key in ipairs(P.order)do
        local row=P.items[key]
        if row then rows[#rows+1]=row end
    end
    return rows
end
function P.save()
    if P.state().active then return false,'stop the scan first' end
    local rows=P.preview()
    if #rows==0 then return false,'no recognized priced items' end
    if not L.save_observation then return false,'pawnshop store unavailable' end
    local ok,result=L.save_observation(rows,'packet_unverified')
    if ok then P.status='saved_unverified' end
    return ok,result
end
function P.report()
    -- Metadata only; never include names, IDs, raw JSON or account data.
    local candidates={}
    for _,c in ipairs(P.candidates)do
        candidates[#candidates+1]={iface=c.iface,sub=c.sub,
            type=c.type,rows=c.rows,labeled=c.label}
    end
    return {schema=1,packets=P.packets,tagged=P.tagged,ignored=P.ignored,
        candidates=candidates}
end
return true

      end
      _v285_pawn_packets()
    end

    do
      local function _v285_pawn_ui()
-- Native mimgui pawnshop panel. No WebView and no item transfer actions.
local V=DSP.ui21
local L=DSP.lombard
if not (V and L) then return false end
local function button(label,id,w,active)
    return V.button(label,'lombard_'..id,w,active)
end
function V.lombard_screen()
    V.heading('LOMBARD')
    local P=L.packet_probe
    local stats=L.stats and L.stats() or {items=0,pages=0}
    V.text('Saved pawnshop quotes: '..tostring(stats.items or 0))
    V.muted('Read-only: approach the pawnshop and choose the item hand-in menu.')
    V.muted('Classic dialogs are captured automatically; native packets need validation.')
    V.muted('No item hand-in, clicks or purchases are sent by Palatka.')
    if not P then V.red('Native scanner unavailable');return end
    local st=P.state()
    if not st.active then
        if button('Listen for native menu (35 sec)','start',280,false)then P.arm(35) end
    else
        V.green('Observing native menu, seconds left: '..math.max(0,st.until_ts-os.time()))
        if button('Stop and review','stop',280,true)then P.stop()end
    end
    V.muted('Packets: '..st.packets..' \183 candidate packets: '..#st.candidates..
        ' \183 labelled: '..st.tagged)
    local rows=P.preview()
    V.text('Observed priced items: '..#rows)
    if not st.verified_label and #rows>0 then
        V.red('UNVERIFIED: menu identity and complete item list not confirmed.')
    end
    if #rows>0 then
        V.list_rows('lombard_preview',rows,60,function(item,i)
            V.row('lombard_item_'..i,60,function(w,x,y)
                V.at(x,y);V.text(V.fit(tostring(item.name or '?'),w-8))
                V.at(x,y+27);V.muted('Pawnshop quote: '..DSP.money(item.price or 0))
            end)
        end,{height=math.min(330,math.max(120,imgui.GetContentRegionAvail().y*.55)),footer=false})
        if not st.active and button('Save observed quotes (unverified)','save',280)then
            local ok,err=P.save()
            if ok then V.lombard_error=nil else V.lombard_error=tostring(err) end
        end
    end
    if V.lombard_error then V.red(V.lombard_error) end
    if stats.items>0 then
        V.text('Previously captured quotes')
        local old=L.search and L.search('') or {}
        for i=1,math.min(5,#old)do
            local item=old[i]
            V.muted(V.fit(item.name..' / '..DSP.money(item.price),280))
        end
    end
end
-- Compatibility route for older OTA shells which do not have a Lombard nav entry.
local previous_tools=V.tools
V.tools=function(screen)
    if screen=='lombard' then return V.lombard_screen() end
    if previous_tools then return previous_tools(screen) end
end
return true

      end
      _v285_pawn_ui()
    end

    if DSP.lombard and DSP.lombard.install then DSP.lombard.install() end
    local live=DSP.live
    if live and type(live.handle)=='function'
        and not live._lombard_packet_hooked and not live._v285_lombard_wrapped then
      local prior=live.handle
      live.handle=function(iface,sub,raw)
        if DSP.lombard and DSP.lombard.on_packet then
          local ok,why=pcall(DSP.lombard.on_packet,iface,sub,raw)
          if not ok and DSP.flog then DSP.flog('LOMBARD native observer: '..tostring(why)) end
        end
        local result={prior(iface,sub,raw)}
        local typ=tonumber(tostring(raw or ''):match('"type"%s*:%s*(%d+)'))
        if tonumber(iface)==255 or
           ((tonumber(iface)==52 or tonumber(iface)==60) and (typ==13 or typ==28)) then
          local ts=os.time()
          if ts-(live._v285_last_invalidate or 0)>=1 then
            if DSP.market and DSP.market.invalidate_arbitrage then
              pcall(DSP.market.invalidate_arbitrage)
            end
            live._v285_last_invalidate=ts
          end
        end
        return unpack(result)
      end
      live._v285_lombard_wrapped=true
    end
  end)
  if not applied then
    if DSP.flog then DSP.flog('Palatka 2.8.5 install failed: '..tostring(err)) end
    return false
  end
  DSP._v285_installed=true
  DSP.version='2.8.5'
  if DSP.flog then DSP.flog('Palatka 2.8.5 Accurate Trade / Lombard beta installed') end
  local function install_v297()
    if not install_v296() then return false end
    if DSP._v297_installed then DSP.version='2.9.7';return true end
    local ok,err=pcall(function()
    do
      local function _v297_listing()
-- Auto listing orchestration, separate from inventory and dialog observation.
local runtime = DSP.trade_runtime
local trade_wait = runtime.pause
local log = DSP.add_log
local h = DSP.auto.helpers
local close_dialog, wait_dialog, wait_text = h.close_dialog, h.wait_dialog, h.wait_text
local clean, base_name, has_qty = h.clean, h.base_name, h.has_qty
local wait_item = h.wait_trade_item_dialog
local trade_dialog_matches, current_dialog_title = h.trade_dialog_matches, h.current_dialog_title
local trade_dialog_matches, current_dialog_title = h.trade_dialog_matches, h.current_dialog_title
local function queue_sell()
    local queue, available = {}, {}
    local preset=DSP.settings.sell_preset
    if type(preset)~='table' or type(preset.items)~='table' then return nil,'preset unavailable' end
    if type(DSP.auto.inv)~='table' then return nil,'inventory unavailable' end
    for _, p in ipairs(preset.items) do
        if type(p)~='table' then return nil,'invalid preset row' end
        if p.enabled ~= false and runtime.positive(p.price) and runtime.positive(p.qty or 1) then
            if type(p.name)~='string' or p.name=='' then return nil,'invalid item name' end
            local target = base_name(p.name)
            local left = tonumber(p.qty) or 1
            for _, inv in ipairs(DSP.auto.inv) do
                if type(inv)~='table' or type(inv.stacks)~='table' then
                    return nil,'inventory slot list is missing; scan inventory again'
                end
                if inv.name == p.name or ((tonumber(p.ench) or 0) == 0 and inv.name == target) then
                    for _, st in ipairs(inv.stacks) do
                        if type(st)~='table' or type(st.slot)~='number' or st.slot%1~=0
                            or st.slot<0 or st.slot>1000 then
                            return nil,'inventory slot invalid; scan inventory again'
                        end
                        if left <= 0 then break end
                        if available[st.slot] == nil then
                            available[st.slot] = runtime.positive(st.count) and tonumber(st.count) or 0
                        end
                        local take = math.min(available[st.slot], left)
                        if take > 0 then
                            table.insert(queue, {
                                name = p.name, base = target, price = p.price,
                                qty = take, slot = st.slot,
                            })
                            left = left - take
                            available[st.slot] = available[st.slot] - take
                        end
                    end
                end
            end
            if left > 0 then return nil, p.name .. ': недостаточно в инвентаре' end
        end
    end
    return queue
end

function DSP.auto.start_sell()
    if DSP.auto.sell_running or DSP.auto.scanning then return false end
    if DSP.auto.buy_running or DSP.auto.scanning then return false end
    local preset=DSP.settings.sell_preset
    local items=type(preset)=='table' and preset.items or nil
    if type(items)~='table' then DSP.notify('Sale preset unavailable');return false end
    local n = 0
    for _, it in ipairs(items) do
        if type(it)~='table' then DSP.notify('Invalid preset row');return false end
        if it.enabled ~= false then n = n + 1 end
    end
    if n == 0 then DSP.notify('Продажа: пресет пуст'); return end
    if #DSP.auto.inv == 0 then
        DSP.notify('Продажа: сначала просканируйте инвентарь')
        return
    end
    local q_ok,queue,err=pcall(queue_sell)
    if not q_ok then
        DSP.flog('PRESET queue_sell error: '..tostring(queue))
        DSP.notify('Preset error; check standalone.log')
        return false
    end
    if not queue then DSP.notify('Sale: '..tostring(err)); return false end
    if #queue == 0 then DSP.notify('Продажа: в инвентаре нет позиций из пресета'); return end
    local dry_run = DSP.settings.dry_run
    DSP.auto.sell_running = true
    DSP.auto.sell_confirmed = false
    DSP.auto.sell_forbidden = false
    DSP.auto.sell_no_slots = false
    DSP.auto.status = 'продажа...'
    DSP.flog('PRESET sale accepted: '..#queue..' stacks, dry_run='..tostring(dry_run))
    log('Продажа: ' .. #queue .. ' стек(ов)')
    if dry_run then
        DSP.notify('ТЕСТ: игровые окна не открываются. Для действий нужен режим РЕАЛЬНО.')
        -- A preview must NEVER send RakNet clicks or dialog responses.
        DSP.auto.sell_running=true
        DSP.auto.status='sale preview...'
        runtime.spawn('sell',function()
            DSP.auto.progress.total=#queue
            for i,it in ipairs(queue) do
                DSP.auto.progress.dry=i
                DSP.auto.progress.done=i
                log('preview: '..it.name..' x'..it.qty..' @ '..DSP.money(it.price))
            end
            DSP.auto.sell_running=false
            DSP.auto.status='sale preview: '..#queue..' stacks, no packets sent'
        end)
        return true
    end
    runtime.spawn('sell', function()
        DSP.auto.progress.total = #queue
        local done = 0
        -- Establish the same native stall context as manual listing before
        -- clicking inventory slots. Without it Arizona may ignore iface60 clicks.
        if DSP.auto.prepare_stall_inventory then
            local ok,why=DSP.auto.prepare_stall_inventory()
            if not ok then
                DSP.auto.sell_running=false
                DSP.auto.status='продажа: лавка не готова'
                log('Продажа: '..tostring(why or 'не удалось открыть инвентарь лавки'),'error')
                DSP.notify('Продажа: '..tostring(why or 'лавка не готова'))
                return
            end
            trade_wait(120)
        end
        for _, it in ipairs(queue) do
            if not DSP.auto.sell_running then break end
            DSP.auto.status = 'продажа: ' .. it.name .. ' (' .. done .. '/' .. #queue .. ')'
            local json = '{"amount":' .. it.qty .. ',"id":0,"slot":' .. it.slot .. ',"type":1}'
            local got, id, dialog_text = false, nil, nil
            for attempt = 1, 3 do
                close_dialog()
                DSP.auto.sell_confirmed = false
                DSP.auto.sell_forbidden, DSP.auto.sell_no_slots = false, false
                -- Native RakNet must not receive stale/invalid slot data.
                if type(it.slot)~='number' or it.slot<0 or it.slot>1000 or it.slot%1~=0 then
                    error('Invalid inventory slot at send: '..tostring(it.slot))
                end
                runtime.transition('sell','select_item',tostring(it.name)..' slot='..tostring(it.slot))
                DSP.flog('PRESET sale packet: item='..tostring(it.name)..' slot='..it.slot..' qty='..tostring(it.qty))
                _G.dsp_click_slot(60, -1, 2, json)
                runtime.transition('sell','wait_item_dialog',tostring(it.name))
                -- v1.2 hotfix: also accept 15068-15071 (newer Arizona Mobile выставление dialogs).
                id,dialog_text,dialog_title = wait_item({ 26547, 15068, 15069, 15070, 15071 }, it.name, 2600, 'sell')
                if id then
                    got = true
                    break
                end
                log('Продажа: диалог предмета не готов ('..attempt..'): '..tostring(dialog_text or ''):sub(1,90),'error')
                close_dialog()
                trade_wait(180)
            end
            if got then
                -- mimgui/MonetLoader may publish the dialog text before the
                -- native input control is ready. Follow the observed game
                -- sequence: one short settle, then verify the *same* item/ID.
                trade_wait(180)
                local current=sampIsDialogActive() and sampGetCurrentDialogId() or nil
                local valid,actual,actual_title=false,'',''
                if current then valid,actual,actual_title=trade_dialog_matches(current,it.name,'sell') end
                if current~=id or not valid then
                    got=false
                    log('\xcf\xf0\xee\xe4\xe0\xe6\xe0: \xe4\xe8\xe0\xeb\xee\xe3 \xf1\xec\xe5\xed\xe8\xeb\xf1\xff \xe4\xee \xee\xf2\xef\xf0\xe0\xe2\xea\xe8, id='..tostring(current)..
                        ', \xee\xe6\xe8\xe4\xe0\xeb\xf1\xff='..tostring(id)..' \xb7 '..it.name,'error')
                else
                    dialog_text,dialog_title=actual,actual_title
                end
            end
            if got then
                local txt = (dialog_title or '') .. '\n' .. (dialog_text or '')
                local combined = has_qty(txt)
                -- Market Helper behavior: amount is already present in the iface60
                -- slot packet. If this client only asks for price, send only price.
                local resp = combined and (tostring(it.qty) .. ',' .. tostring(it.price))
                    or tostring(it.price)
                DSP.flog('PRESET sale input: item='..tostring(it.name)..' dialog='..tostring(id)..
                    ' mode='..(combined and 'qty_price' or 'price_only')..' resp_len='..tostring(#resp))
                if dry_run then
                    DSP.auto.progress.dry = DSP.auto.progress.dry + 1
                    log('dry-run: продал бы ' .. it.name .. ' x' .. it.qty .. ' @ ' .. DSP.money(it.price))
                    close_dialog()
                else
                    DSP.auto.sell_confirmed = false
                    -- v1.2 hotfix: use the active dialog id (may be 26547 or
                    -- 15068-15071 in newer Arizona Mobile). Fallback chain.
                    local resp_id = id or sampGetCurrentDialogId and sampGetCurrentDialogId() or 26547
                    runtime.transition('sell','submit',tostring(it.name)..' qty='..tostring(it.qty)..' price='..tostring(it.price))
                    sampSendDialogResponse(resp_id, 1, 0, resp)
                    for _ = 1, 100 do
                        if DSP.auto.sell_confirmed then break end
                        trade_wait(40)
                    end
                    if sampIsDialogActive() and sampGetCurrentDialogId()==resp_id then
                        sampSendDialogResponse(resp_id, 0, 0, '')
                    end
                    if DSP.auto.sell_no_slots then
                        DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                        log('Продажа: нет свободных мест', 'error')
                        DSP.auto.sell_running = false
                        break
                    end
                    if DSP.auto.sell_forbidden then
                        DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                        log('Продажа: запрещено для ' .. it.name, 'error')
                    elseif DSP.auto.sell_confirmed then
                        done = done + 1
                        DSP.auto.progress.done = done
                        log('Выставлено: ' .. it.name .. ' x' .. it.qty .. ' @ ' .. DSP.money(it.price), 'ok')
                    else
                        DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                        log('Продажа: нет подтверждения для ' .. it.name, 'error')
                    end
                end
                trade_wait(DSP.controls and DSP.controls.get and DSP.controls.get('sell_step_pause_ms') or 260)
            else
                DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                log('Продажа: не открылся диалог для ' .. it.name .. ' (slot ' .. it.slot .. ')', 'error')
                close_dialog()
            end
        end
        DSP.auto.sell_running = false
        DSP.auto.status = 'продажа: ' .. done .. '/' .. #queue
        log('Продажа завершена: ' .. done .. '/' .. #queue, 'ok')
        -- Inventory is now stale; refresh explicitly before another sale.
        DSP.auto.inv = {}
        DSP.auto.inv_status = 'нужно обновить'
    end)
    return true
end

function DSP.auto.stop_sell()
    if not DSP.auto.sell_running then return false end
    runtime.cancel()
    DSP.auto.sell_running = false
    DSP.auto.status = 'продажа остановлена'
    close_dialog()
    log('Продажа остановлена')
end

      end
      _v297_listing()
    end
    do
      local function _v297_buy()
-- Auto listing orchestration, separate from inventory and dialog observation.
local runtime = DSP.trade_runtime
local trade_wait = runtime.pause
local log = DSP.add_log
local h = DSP.auto.helpers
local close_dialog, wait_dialog, wait_text = h.close_dialog, h.wait_dialog, h.wait_text
local clean, base_name, has_qty = h.clean, h.base_name, h.has_qty
local wait_item = h.wait_trade_item_dialog
-- Search results may carry a line number, price/count columns and colour tags.
-- Match the complete normalized item name; do not pick an unrelated first-word hit.
local function find_list_index(text, name)
    local idx=0
    local fold=DSP.lower or string.lower
    local wanted=fold(base_name(name)):match('^%s*(.-)%s*$')
    local found=nil
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        local nm=clean(line):gsub('^%s*%d+[%.%)]%s*',''):match('^%s*(.-)%s*$')
        nm=(nm:match('^(.-)\t') or nm):match('^%s*(.-)%s*$')
        -- Some builds put quantity in square brackets after the item name.
        local base=nm:match('^(.-)%s+%[%d+[^%]]*%]') or nm
        base=fold(base_name(base)):match('^%s*(.-)%s*$')
        if base==wanted then
            if found~=nil then return nil,'несколько одинаковых строк' end
            found=idx
        end
        idx=idx+1
    end
    return found
end

local function open_shop_menu()
    runtime.transition('buy','open_shop','request native stall menu')
    close_dialog()
    _G.dsp_click_slot(8, 7, -1, '')
    runtime.transition('buy','wait_shop','dialogs 3040/15072')
    -- v1.2 hotfix: accept 15072/15073 fallback for shop menu open in newer Arizona Mobile.
    return wait_dialog({ 3040, 15072 }, 2500)
end

local function buy_one(it, pi, total, dry_run)
    DSP.auto.status = 'скупка: ' .. it.name .. ' (' .. pi .. '/' .. total .. ')'
    if not sampIsDialogActive() or (sampGetCurrentDialogId() ~= 3040 and sampGetCurrentDialogId()~=15072) then
        if not open_shop_menu() then
            log('Скупка: меню не открылось для ' .. it.name, 'error')
            return false
        end
    end
    local menu_id = sampGetCurrentDialogId()
    wait_text(menu_id, 350)
    runtime.transition('buy','open_search','menu='..tostring(menu_id))
    sampSendDialogResponse(menu_id, 1, 2, '')
    -- v1.2 hotfix: also accept 15065-15067 (newer search/dialog IDs).
    local id = wait_dialog({ 25663, 15065, 15066, 15067 }, 3000)
    if not id then
        log('Скупка: строка поиска не открылась', 'error')
        return false
    end
    wait_text(id, 700)
    local search = base_name(it.name):sub(1, 24)
    runtime.transition('buy','search',tostring(it.name))
    sampSendDialogResponse(id, 1, 0, search)
    -- v1.2 hotfix: search results dialog may also be 15068 in newer versions.
    id = wait_dialog({ 25664, 15068 }, 3500)
    if not id then
        log('Скупка: результаты не открылись: ' .. it.name, 'error')
        return false
    end
    local list_text = DSP.dialog_clean(wait_text(id, 500))
    local idx,index_err = find_list_index(list_text, it.name)
    if idx==nil then
        log('Скупка: '..tostring(index_err or 'не найдено')..': ' .. it.name, 'error')
        close_dialog()
        return false
    end
    runtime.transition('buy','select_result',tostring(it.name)..' row='..tostring(idx))
    sampSendDialogResponse(id, 1, idx, '')
    -- v1.2 hotfix: выставление price dialog may also use 15070/15071 in newer Arizona Mobile.
    id = wait_dialog({ 26560, 26563, 15070, 15071 }, 3000)
    if not id then
        log('Скупка: диалог цены не открылся: ' .. it.name, 'error')
        return false
    end
    if id == 26560 then
        sampSendDialogResponse(id, 1, 0, '')
        -- v1.2 hotfix: also accept 15071 fallback.
        id = wait_dialog({ 26563, 15071 }, 2000)
    end
    -- v1.2 hotfix: accept 15071 as alternative to 26563 for the final выставление dialog.
    if id ~= 26563 and id ~= 15071 then return false end
    local validated_id,txt,dialog_title=wait_item({id},it.name,1700,'buy')
    local base = base_name(it.name)
    if not validated_id then
        log('Скупка: в диалоге другой товар: ' .. it.name, 'error')
        close_dialog()
        return false
    end
    -- Stabilize the native price input after the dialog text appears. Never
    -- submit to another item/ID that replaced it during the delay.
    trade_wait(180)
    local current=sampIsDialogActive() and sampGetCurrentDialogId() or nil
    local valid,actual,actual_title=false,'',''
    if current then valid,actual,actual_title=trade_dialog_matches(current,it.name,'buy') end
    if current~=id or not valid then
        log('\xd1\xea\xf3\xef\xea\xe0: \xe4\xe8\xe0\xeb\xee\xe3 \xe8\xe7\xec\xe5\xed\xe8\xeb\xf1\xff \xe4\xee \xee\xf2\xef\xf0\xe0\xe2\xea\xe8 \xb7 '..it.name,'error')
        close_dialog()
        return false
    end
    txt,dialog_title=actual,actual_title
    local qty = tonumber(it.qty) or 1
    if qty < 1 then qty = 1 end
    local combined = has_qty((dialog_title or '') .. '\n' .. (txt or ''))
    if not combined and qty>1 then
        -- Same fallback as Market Helper: a price-only buy dialog represents one
        -- unit, so the outer loop repeats the listing until requested qty is done.
        log('Buy: price-only dialog, one unit per submit', 'info')
        qty=1
    end
    local resp = combined and (tostring(qty) .. ',' .. tostring(it.price))
        or tostring(it.price)
    DSP.flog('PRESET buy input: item='..tostring(it.name)..' dialog='..tostring(id)..
        ' mode='..(combined and 'qty_price' or 'price_only')..' resp_len='..tostring(#resp))
    if dry_run then
        log('dry-run: купил бы ' .. it.name .. ' x' .. qty .. ' @ ' .. DSP.money(it.price))
        close_dialog()
        return 'dry', tonumber(it.qty) or 1
    end
    -- v1.2 hotfix: use the active dialog id (may be 26563 or 15071 in newer
    -- Arizona Mobile выставление dialogs). Fallback chain via sampGetCurrentDialogId.
    local resp_id = id or (sampGetCurrentDialogId and sampGetCurrentDialogId()) or 26563
    sampSendDialogResponse(resp_id, 1, 0, resp)
    log('Скупка: ' .. it.name .. ' x' .. qty .. ' @ ' .. DSP.money(it.price), 'ok')
    for _ = 1, 24 do
        if not sampIsDialogActive() then return 'bought', qty end
        trade_wait(30)
    end
    log('Скупка: нет подтверждения закрытия диалога', 'error')
    return false
end

function DSP.auto.start_buy()
    if DSP.auto.buy_running or DSP.auto.scanning then return false end
    if DSP.auto.sell_running or DSP.auto.scanning then return false end
    local list = {}
    local preset=DSP.settings.buy_preset
    if type(preset)~='table' or type(preset.items)~='table' then
        DSP.notify('Buy preset unavailable');return false
    end
    for _, it in ipairs(preset.items) do
        if type(it)~='table' then DSP.notify('Invalid buy preset row');return false end
        if it.enabled ~= false and runtime.positive(it.price) and runtime.positive(it.qty or 1) then
            if type(it.name)~='string' or it.name=='' then
                DSP.notify('Invalid buy preset item name');return false
            end
            list[#list+1] = {name=it.name,price=tonumber(it.price),qty=tonumber(it.qty) or 1}
        end
    end
    if #list == 0 then DSP.notify('Скупка: пресет пуст или цены 0'); return end
    local dry_run = DSP.settings.dry_run
    DSP.auto.buy_running = true
    DSP.auto.status = 'скупка...'
    DSP.flog('PRESET buy accepted: '..#list..' positions, dry_run='..tostring(dry_run))
    log('Скупка: ' .. #list .. ' позиций' .. (dry_run and ' (dry-run)' or ''))
    if dry_run then
        DSP.notify('ТЕСТ: игровые окна не открываются. Для действий нужен режим РЕАЛЬНО.')
        -- No shop menu, network packets or dialog interactions in preview.
        runtime.spawn('buy',function()
            DSP.auto.progress.total=#list
            for i,it in ipairs(list) do
                DSP.auto.progress.dry=i
                DSP.auto.progress.done=i
                DSP.auto.progress.units=(DSP.auto.progress.units or 0)+(it.qty or 1)
                log('preview: '..it.name..' x'..it.qty..' @ '..DSP.money(it.price))
            end
            DSP.auto.buy_running=false
            DSP.auto.status='buy preview: '..#list..' positions, no packets sent'
        end)
        return true
    end
    runtime.spawn('buy', function()
        DSP.auto.progress.total = #list
        if not open_shop_menu() then
            log('Скупка: лавка не открылась. Подойдите к лавке.', 'error')
            DSP.auto.buy_running = false
            DSP.auto.status = 'скупка: ошибка'
            return
        end
        local bought, dry = 0, 0
        for pi, it in ipairs(list) do
            if not DSP.auto.buy_running then break end
            local remaining = tonumber(it.qty) or 1
            local result
            while remaining > 0 do
                local entry = {}
                for key, value in pairs(it) do entry[key] = value end
                entry.qty = remaining
                local units
                result, units = buy_one(entry, pi, #list, dry_run)
                if not result then break end
                remaining = remaining - (units or 1)
                DSP.auto.progress.units = (DSP.auto.progress.units or 0) + (units or 1)
                close_dialog()
            end
            if remaining == 0 and result == 'bought' then bought = bought + 1
            elseif remaining == 0 and result == 'dry' then dry = dry + 1
            else DSP.auto.progress.failed = DSP.auto.progress.failed + 1 end
            DSP.auto.progress.done, DSP.auto.progress.dry = bought, dry
            close_dialog()
            if pi < #list and DSP.auto.buy_running then
                local pause_ms=DSP.controls and DSP.controls.get and DSP.controls.get('buy_step_pause_ms') or 0
                if pause_ms>0 then trade_wait(pause_ms)end
                if not open_shop_menu() then break end
            end
        end
        DSP.auto.buy_running = false
        DSP.auto.status = 'скупка: ' .. bought .. '/' .. #list .. (dry > 0 and (' (dry ' .. dry .. ')') or '')
        log('Скупка завершена: ' .. bought .. '/' .. #list, 'ok')
    end)
    return true
end

function DSP.auto.stop_buy()
    if not DSP.auto.buy_running then return false end
    runtime.cancel()
    DSP.auto.buy_running = false
    DSP.auto.status = 'скупка остановлена'
    close_dialog()
    log('Скупка остановлена')
end


-- Queue user-initiated listing outside the ImGui drawing callback. Synchronous
-- Lua exceptions during an ImGui frame can corrupt its Begin/End stack.
-- This catches Lua-side errors only; native Android faults still need a log.
function DSP.auto.safe_start(kind)
    if kind~='sell' and kind~='buy' then return false end
    if DSP.auto._launch_queued or DSP.auto.buy_running or DSP.auto.sell_running or DSP.auto.scanning then
        DSP.notify('Trade already running or inventory scan active')
        return false
    end
    if type(lua_thread)~='table' or type(lua_thread.create)~='function' then
        DSP.notify('Thread scheduler unavailable')
        return false
    end
    DSP.auto._launch_queued=true
    DSP.flog('PRESET queued: kind='..kind..' dry_run='..tostring(DSP.settings.dry_run))
    local ok,err=pcall(lua_thread.create,function()
        DSP.auto._launch_queued=false
        local started,result=xpcall(function()
            if kind=='sell' then return DSP.auto.start_sell() end
            return DSP.auto.start_buy()
        end,function(e)
            if debug and debug.traceback then return debug.traceback(tostring(e),2) end
            return tostring(e)
        end)
        if not started then
            DSP.auto[kind..'_running']=false
            DSP.auto.status='Preset error; see standalone.log'
            if DSP.flog then DSP.flog('PRESET launch exception: '..tostring(result)) end
            DSP.notify('Preset error; see standalone.log')
        elseif result~=true then
            if DSP.flog then DSP.flog('PRESET launch rejected: '..kind) end
        end
    end)
    if not ok then
        DSP.auto._launch_queued=false
        DSP.flog('PRESET scheduler failure: '..tostring(err))
        DSP.notify('Failed to queue preset; see standalone.log')
        return false
    end
    return true
end
      end
      _v297_buy()
    end
    do
      local function _v297_arb()
-- Palatka Arbitrage Session: many routes, local execution ledger and a floating guide.
-- Read-only game integration: confirmation is manual, receipt matching only suggests.
-- This module never submits purchase/sale packets and never edits the remote API.
DSP.arb_agent=DSP.arb_agent or {}
local A=DSP.arb_agent
local M=DSP.market
local MAX=9007199254740991
local function num(v,lo,hi)
    local n=tonumber(v)
    if n and n==n and n%1==0 and n>=(lo or 0)and n<=(hi or MAX)then return math.floor(n)end
end
local function server()
    local detected
    if type(DSP.detect_server)=='function'then
        local ok,id=pcall(DSP.detect_server)
        if ok then detected=num(id,1)end
    end
    return detected or num(M.state and M.state.sid,1)
        or num(DSP.settings and DSP.settings.server,1)or 0
end
local function cycle_start(ts)
    local date=os.date('*t',ts or os.time())
    date.hour,date.min,date.sec=5,0,0
    local start=os.time(date)
    return(ts or os.time())<start and(start-86400)or start
end
local function part(v)
    local s=tostring(v or '')
    return tostring(#s)..':'..s
end
local function eq(a,b)
    if DSP.lower then return DSP.lower(tostring(a or''))==DSP.lower(tostring(b or''))end
    return tostring(a or''):lower()==tostring(b or''):lower()
end
local function key(sid,row,side,o)
    if not row or not o then return nil end
    local fields={sid,side,row.key or row.item_key or row.name or'',o.shop,o.owner,o.price,o.ts or 0}
    local out={}
    for i,v in ipairs(fields)do out[i]=part(v)end
    return table.concat(out,'|')
end
A.quote_key=key
A.path=(DSP.dir or '.')..'/arb_agent_v1.json'
A.data=A.data or {schema=1,session=nil,consumed={},history={}}
A.revision=A.revision or 0
A.hint=nil
local function safe_data(d)
    return type(d)=='table'and d.schema==1 and type(d.consumed)=='table'
        and type(d.history)=='table'and (d.session==nil or type(d.session)=='table')
end
function A.load()
    local f=io.open(A.path,'rb')
    if not f then return false end
    local raw=f:read('*a')or'';f:close()
    local ok,d=pcall(decodeJson,raw)
    if not ok or not safe_data(d)then return false end
    A.data=d
    if A.data.session and type(A.data.session.routes)~='table'then A.data.session=nil end
    return true
end
function A.save()
    local ok,raw=pcall(encodeJson,A.data)
    if not ok or type(raw)~='string'then return false,'encode'end
    local tmp=A.path..'.tmp'
    local f,err=io.open(tmp,'wb')
    if not f then return false,err end
    local wrote,why=f:write(raw);local closed,close_err=f:close()
    if not wrote or not closed then os.remove(tmp);return false,why or close_err or'write'end
    local renamed,rename_err=os.rename(tmp,A.path)
    if not renamed then os.remove(tmp);return false,rename_err or'rename'end
    return true
end
local function changed()
    A.revision=A.revision+1
    local ok,err=A.save()
    A.save_error=not ok and tostring(err)or nil
    if not ok and DSP.flog then DSP.flog('ARB AGENT save failed: '..tostring(err))end
    if M.invalidate_arbitrage then M.invalidate_arbitrage()end
    return ok,err
end
local function active()
    local s=A.data.session
    if not s or s.ended or s.sid~=server()
        or(num(s.started,0)or 0)<cycle_start(os.time())then return nil end
    return s
end
function A.active()return active()end
function A.is_open()
    return DSP.settings.arb_agent_open==true and active()~=nil
end
function A.show(value)
    DSP.settings.arb_agent_open=value~=false
    if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
    elseif DSP.save_settings then DSP.save_settings()end
end
function A.stop()
    local s=active()
    if not s then return false,'Нет активной сессии'end
    s.ended=os.time()
    A.show(false)
    return changed()
end
local function record_snapshot(route,sid)
    if type(route)~='table'or not route.sell_offer or not route.buy_offer
        or not route.row then return nil end
    local q=num(route.tradable_qty,1,1000000000)
    local cost=num(route.p_buy,1,MAX)
    local price=num(route.p_sell,1,MAX)
    if not q or not cost or not price or price<=cost or q*math.max(cost,price)>MAX then return nil end
    local row=route.row
    local sell=route.sell_offer
    local buy=route.buy_offer
    local cut=cycle_start(os.time())
    -- Do not requeue a previous server-day quote after the expected 05:00 restart.
    local sell_at,buy_at=num(sell.ts,1),num(buy.ts,1)
    if (sell_at and sell_at<cut)or(buy_at and buy_at<cut)then return nil end
    local sk=key(sid,row,'sell',sell)
    local bk=key(sid,row,'buy',buy)
    local ts=os.time()
    local entry={
        id='',sid=sid,name=tostring(route.name or row.display or row.name or'?'),
        item_key=tostring(row.key or''),ench=num(row.ench,0,1000)or 0,
        qty=q,bought=0,sold=0,buy_price=cost,sell_price=price,
        seller_shop=tostring(sell.shop or'?'),buyer_shop=tostring(buy.shop or'?'),
        seller_owner=tostring(sell.owner or'?'),buyer_owner=tostring(buy.owner or'?'),
        seller_quote=sk,buyer_quote=bk,
        seller_ts=num(sell.ts,0)or 0,buyer_ts=num(buy.ts,0)or 0,
        proposed_profit=num(route.net_profit,0)or 0,created=ts
    }
    entry.id=sk..'>'..bk
    return entry
end
local function route_pending(e)
    return not e.skipped and e.sold<e.qty
end
local function count_open(s)
    local n=0
    for _,e in ipairs(s.routes)do if route_pending(e)then n=n+1 end end
    return n
end
local function append_routes(routes,cap)
    local s=active()
    if not s then return 0 end
    local seen={}
    for _,e in ipairs(s.routes)do seen[e.id]=true end
    local fresh=0;local open=count_open(s)
    for _,r in ipairs(routes or{})do
        if open>=(cap or 24)or #s.routes>=250 then break end
        local entry=record_snapshot(r,s.sid)
        if entry and not seen[entry.id]then
            seen[entry.id]=true
            s.routes[#s.routes+1]=entry
            open=open+1;fresh=fresh+1
        end
    end
    if fresh>0 then changed()end
    return fresh
end
function A.start(routes)
    if server()==0 then return false,'Сервер ещё не определён'end
    local s=active()
    if not s then
        A.data.session={sid=server(),started=os.time(),routes={},focus=1,last_review=0,
            tax_bp=num(DSP.settings.tax_bp,0,10000)or 200}
    end
    local n=append_routes(routes,24)
    if n==0 and #A.data.session.routes==0 then
        A.data.session=nil
        return false,'Новых пригодных маршрутов пока нет'
    end
    A.show(true)
    return true,n
end
function A.add_plan(plan)
    local routes=plan and plan.routes
    if type(routes)~='table'or#routes==0 then return false,'В плане нет маршрутов'end
    return A.start(routes)
end
function A.start_market()
    if M.state.status=='cache'or M.state.status=='error'then
        return false,'Нет свежего рынка; проверьте API или локальный скан'
    end
    local groups,status
    if M.arbitrage_grouped_ui then groups,status=M.arbitrage_grouped_ui()
    else groups=M.arbitrage_grouped();status='ready'end
    if status~='ready'or not groups then return false,'Рынок ещё рассчитывается'end
    local routes={}
    for _,g in ipairs(groups)do for _,r in ipairs(g.routes or{})do routes[#routes+1]=r end end
    table.sort(routes,function(a,b)return(tonumber(a.net_profit)or 0)>(tonumber(b.net_profit)or 0)end)
    return A.start(routes)
end
-- A locally scanned route can join the same session if both quantities are known.
-- The local quote identity is separate from remote API identities.
function A.add_local_route(r)
    if type(r)~='table' or not num(r.qty,1,1000000000)then
        return false,'Скан не подтвердил количество с обеих сторон'
    end
    local item_key=tostring(r.id or'?')..':'..tostring(r.ench or 0)
    local row={key=item_key,display=r.name,ench=r.ench or 0}
    local sell={shop=r.seller_shop,owner=r.seller_owner,price=r.buy_price,ts=r.seller_at}
    local buy={shop=r.buyer_shop,owner=r.buyer_owner,price=r.sell_price,ts=r.buyer_at}
    local p={row=row,name=r.name,sell_offer=sell,buy_offer=buy,
        tradable_qty=r.qty,p_buy=r.buy_price,p_sell=r.sell_price,net_profit=r.profit_total or 0}
    return A.add_plan({routes={p}})
end
function A.get(index)
    local s=active()
    return s and s.routes[index],s
end
function A.focus(index)
    local s=active()
    if not s then return false end
    index=num(index,1,#s.routes)
    if not index then return false end
    s.focus=index
    A.save()
    return true
end
function A.next(step)
    local s=active()
    if not s or #s.routes==0 then return false end
    local count=#s.routes;local i=num(s.focus,1,count)or 1
    for _=1,count do
        i=((i-1+(step or 1))%count)+1
        if route_pending(s.routes[i])then return A.focus(i)end
    end
    return A.focus(i)
end
function A.stats()
    local s=active();local out={routes=0,done=0,skipped=0,bought=0,sold=0,
        pending=0,profit_estimate=0,spent_estimate=0}
    if not s then return out end
    out.routes=#s.routes
    local bp=num(s.tax_bp,0,10000)or num(DSP.settings.tax_bp,0,10000)or 200
    local factor=10000-bp
    for _,e in ipairs(s.routes)do
        local b=num(e.bought,0)or 0;local sold=num(e.sold,0)or 0
        out.bought=out.bought+b;out.sold=out.sold+sold
        if e.skipped then out.skipped=out.skipped+1
        elseif sold==e.qty then out.done=out.done+1
        else out.pending=out.pending+1 end
        -- Confirming a trade does not prove the actual receipt amount.
        -- These figures remain estimates at originally quoted prices/tax.
        local gross=sold*e.sell_price
        local revenue=math.floor(gross/10000)*factor+math.floor((gross%10000)*factor/10000)
        out.profit_estimate=out.profit_estimate+revenue-sold*e.buy_price
        out.spent_estimate=out.spent_estimate+b*e.buy_price
    end
    return out
end
local function consumed_entry(quote)
    return A.data.consumed[quote]
end
local function consume(quote,n,at)
    local c=consumed_entry(quote)or{qty=0,at=0}
    c.qty=(num(c.qty,0)or 0)+n;c.at=at
    A.data.consumed[quote]=c
end
function A.confirm(index,side,amount)
    local e,s=A.get(index)
    if not e or not s then return false,'Нет такой сделки'end
    if e.skipped then return false,'Сделка пропущена'end
    if side~='buy'and side~='sell'then return false,'Неизвестный тип'end
    local limit=side=='buy'and(e.qty-e.bought)or(e.bought-e.sold)
    local q=num(amount,1,limit)
    if not q then return false,'Количество превышает оставшийся лимит'end
    local at=os.time()
    -- Stage the ledger change, then roll back *all* in-memory fields if JSON
    -- cannot be persisted. Never acknowledge a trade that would vanish on relog.
    local quote=side=='buy'and e.seller_quote or e.buyer_quote
    local prior_consumed=A.data.consumed[quote]
    local prior_consumed_copy=prior_consumed and {qty=prior_consumed.qty,at=prior_consumed.at} or nil
    local old_bought,old_sold=e.bought,e.sold
    local old_bought_at,old_sold_at=e.bought_at,e.sold_at
    local old_last_action,old_hint=s.last_action,A.hint
    local old_history={}
    for i,v in ipairs(A.data.history)do old_history[i]=v end
    if side=='buy'then
        e.bought=e.bought+q;e.bought_at=at
    else
        e.sold=e.sold+q;e.sold_at=at
    end
    consume(quote,q,at)
    s.last_action=at
    A.data.history[#A.data.history+1]={
        session_started=s.started,route_id=e.id,side=side,qty=q,
        item=e.name,at=at,method='manual',price=side=='buy'and e.buy_price or e.sell_price
    }
    if #A.data.history>1000 then table.remove(A.data.history,1)end
    if A.hint and A.hint.route_id==e.id and A.hint.side==side then A.hint=nil end
    local saved,why=changed()
    if not saved then
        e.bought,e.sold=old_bought,old_sold
        e.bought_at,e.sold_at=old_bought_at,old_sold_at
        s.last_action,A.hint=old_last_action,old_hint
        A.data.consumed[quote]=prior_consumed_copy
        A.data.history=old_history
        A.revision=A.revision+1
        if M.invalidate_arbitrage then M.invalidate_arbitrage()end
        return false,'Не удалось сохранить сделку: '..tostring(why or 'disk error')
    end
    if e.sold==e.qty then A.next(1)end
    return true,q
end
function A.skip(index,value)
    local e=A.get(index);if not e then return false end
    e.skipped=value~=false
    changed()
    return true
end
function A.remaining(row,side,offer,base,meta)
    local q=num(base,0)or 0
    local quote=key(server(),row,side,offer)
    local c=quote and consumed_entry(quote)
    if not c then return q,meta end
    local last=num(c.at,0)or 0
    if last<cycle_start(os.time())then return q,meta end
    -- A newer complete game observation supersedes our local bookkeeping.
    if meta and(meta.source=='recent_scan'or meta.source=='game_observed')
        and (num(meta.at,0)or 0)>last then return q,meta end
    return math.max(0,q-(num(c.qty,0)or 0)),{source='local_execution',at=last}
end
local base_offer_qty=M.offer_quantity
if type(base_offer_qty)=='function'and not A._quantity_hook then
    M.offer_quantity=function(row,side,offer,now)
        local q,meta=base_offer_qty(row,side,offer,now)
        return A.remaining(row,side,offer,q,meta)
    end
    A._quantity_hook=true
end
local function matches_receipt(entry,side,name,amount)
    if not eq(entry.name,name)or entry.skipped then return false end
    local limit=side=='buy'and(entry.qty-entry.bought)or(entry.bought-entry.sold)
    local unit=side=='buy'and entry.buy_price or entry.sell_price
    return limit>0 and amount>0 and amount%unit==0 and amount/unit<=limit
end
function A.observe_receipt(side,name,amount)
    if side~='buy'and side~='sell'then return false end
    amount=num(amount,1);if not amount then return false end
    local s=active()
    if not s then return false end
    local matched,qty=nil,nil
    for i,e in ipairs(s.routes)do
        if matches_receipt(e,side,name,amount)then
            if matched then A.hint=nil;return false end -- ambiguous
            matched=i;qty=amount/(side=='buy'and e.buy_price or e.sell_price)
        end
    end
    if matched then
        A.hint={index=matched,route_id=s.routes[matched].id,side=side,
            qty=qty,amount=amount,at=os.time()}
        return true
    end
    return false
end
local log_market=DSP.craglog and DSP.craglog.log_market
if type(log_market)=='function'and not A._receipt_hook then
    DSP.craglog.log_market=function(direction,item,amount,raw)
        local ok,err=log_market(direction,item,amount,raw)
        if ok then pcall(A.observe_receipt,direction,item,amount)end
        return ok,err
    end
    A._receipt_hook=true
end
function A.review_market()
    local s=active();if not s then return false end
    local now=os.time()
    if now-(num(s.last_review,0)or 0)<60 then return false end
    s.last_review=now
    -- 60-second review is LOCAL; it never bypasses market API backoff.
    if M.state.status~='live'then return false end
    local groups,status
    if M.arbitrage_grouped_ui then groups,status=M.arbitrage_grouped_ui()
    else groups=M.arbitrage_grouped();status='ready'end
    if status~='ready'or not groups then return false end
    local routes={}
    for _,g in ipairs(groups)do for _,r in ipairs(g.routes or{})do routes[#routes+1]=r end end
    table.sort(routes,function(a,b)return(tonumber(a.net_profit)or 0)>(tonumber(b.net_profit)or 0)end)
    return append_routes(routes,24)>0
end
function A.install()
    if A.installed then return end
    A.installed=true
    A.load()
    -- Keep a finished session available in history but never reactivate it.
    if imgui and imgui.OnFrame then
        imgui.OnFrame(A.is_open,function()
            local ok,err=xpcall(A.draw,debug.traceback)
            if not ok then
                A.ui_error=tostring(err)
                if A._last_ui_error~=A.ui_error then
                    A._last_ui_error=A.ui_error
                    if DSP.flog then DSP.flog('ARB AGENT UI: '..A.ui_error)end
                end
                -- Keep the session and its window enabled; do not turn a
                -- temporary render exception into the loss of the route UI.
            end
        end)
    end
end
return true

      end
      _v297_arb()
    end
    do
      local function _v297_availability()
-- Arbitrage agent availability: user-confirmed absence and trusted game evidence.
-- Quote absence is NOT inferred from a partial shop snapshot.
local A,M=DSP.arb_agent,DSP.market
local function now()return os.time()end
local function sid()return tonumber(M.state and M.state.sid)or tonumber(DSP.settings.server)or 0 end
local function cycle(t)
    local d=os.date('*t',t);d.hour=5;d.min=0;d.sec=0
    local boundary=os.time(d);return t<boundary and boundary-86400 or boundary
end
local function text_eq(x,y)
    local f=DSP.lower or string.lower
    return f(tostring(x or''))==f(tostring(y or''))
end
local function valid_shop(shop)
    local n=tonumber(shop)
    return n and n>0 and n<=99999 and n==math.floor(n)
end
local function ensure()
    A.data=A.data or{schema=1,consumed={},history={}}
    A.data.unavailable=A.data.unavailable or{}
    return A.data.unavailable
end
local old_load=A.load
function A.load(...)
    local result=old_load(...)
    ensure()
    return result
end
ensure()
local old_remaining=A.remaining
function A.remaining(row,side,offer,base,meta)
    local qty,origin=old_remaining(row,side,offer,base,meta)
    local quote=A.quote_key(sid(),row,side,offer)
    local denied=quote and ensure()[quote]
    if denied and tonumber(denied.at)and denied.at>=cycle(now())then
        -- Trusted positive game observation AFTER the manual absence supersedes it.
        local evidence=origin and (origin.source=='game_observed' or origin.source=='recent_scan')
        if evidence and (tonumber(origin.at)or 0)>denied.at and qty>0 then
            ensure()[quote]=nil;A.save()
            return qty,origin
        end
        return 0,{source='confirmed_unavailable',at=denied.at,reason=denied.reason}
    end
    return qty,origin
end
local function changed()
    A.revision=(A.revision or 0)+1
    local ok,err=A.save()
    A.save_error=ok and nil or tostring(err)
    if M.invalidate_arbitrage then M.invalidate_arbitrage()end
    return ok,err
end
local function required_leg(e)
    if e.bought<e.qty then return 'sell',e.seller_shop,e.seller_quote end
    if e.sold<e.qty then return 'buy',e.buyer_shop,e.buyer_quote end
end
local function block_related(shop,quote,reason,source)
    local s=A.active();if not s then return 0 end
    local marked=0
    for _,e in ipairs(s.routes or{})do
        local side,target,current=required_leg(e)
        local match=side and ((quote and current==quote)or
            (not quote and tostring(target)==tostring(shop)))
        if match and e.sold<e.qty and not e.unavailable_reason then
            e.unavailable_reason=reason
            e.unavailable_source=source or'manual'
            e.unavailable_at=now()
            e.unavailable_side=side
            e.skipped=true
            marked=marked+1
        end
    end
    return marked
end
function A.mark_unavailable(index,reason)
    if reason~='shop'and reason~='item'then return false,'Неверная причина'end
    local e,s=A.get(index)
    if not e or not s then return false,'Маршрут не выбран'end
    local side,shop,quote=required_leg(e)
    if not side then return false,'Маршрут уже завершён'end
    if reason=='shop' and not valid_shop(shop)then return false,'Номер лавки неизвестен'end
    -- Record the old session status so a disk error cannot silently discard routes.
    local before={}
    for i,entry in ipairs(s.routes)do
        before[i]={entry=entry,skipped=entry.skipped,reason=entry.unavailable_reason,
            source=entry.unavailable_source,at=entry.unavailable_at,side=entry.unavailable_side}
    end
    local old_focus=s.focus
    local missing_store=M.missing_shops
    local missing_key=tostring(s.sid)..':'..tostring(shop)
    local old_missing=missing_store and missing_store[missing_key]
    local unavailable=ensure()
    local old_unavailable=quote and unavailable[quote] or nil
    if reason=='shop' then
        if not M.mark_shop_missing(shop,30)then return false,'Не удалось отметить лавку'end
        block_related(shop,nil,'shop_missing','manual')
    else
        unavailable[quote]={at=now(),reason='item_missing',sid=s.sid}
        block_related(shop,quote,'item_missing','manual')
    end
    local saved,err=changed()
    if not saved then
        for _,p in ipairs(before)do
            p.entry.skipped=p.skipped;p.entry.unavailable_reason=p.reason
            p.entry.unavailable_source=p.source;p.entry.unavailable_at=p.at
            p.entry.unavailable_side=p.side
        end
        s.focus=old_focus
        if reason=='shop' and missing_store then missing_store[missing_key]=old_missing end
        if reason=='item' then unavailable[quote]=old_unavailable end
        A.revision=(A.revision or 0)+1
        if M.invalidate_arbitrage then M.invalidate_arbitrage()end
        return false,'Не удалось сохранить статус: '..tostring(err)
    end
    -- Keep the unavailable route on screen, with "Restore" and "Next"
    -- controls. Moving focus without user input would hide the explanation.
    A.show(true)
    return true
end
function A.restore_unavailable(index)
    local e=A.get(index)
    if not e then return false,'Нет маршрута'end
    if not e.unavailable_reason then return A.skip(index,false)end
    local reason=e.unavailable_reason
    local shop=e.unavailable_side=='sell'and e.seller_shop or e.buyer_shop
    local quote=e.unavailable_side=='sell'and e.seller_quote or e.buyer_quote
    if reason=='shop_missing' or reason=='owner_changed' then
        if M.restore_shop and valid_shop(shop) then M.restore_shop(shop) end
    end
    if quote then ensure()[quote]=nil end
    e.unavailable_reason=nil;e.unavailable_at=nil;e.unavailable_side=nil
    e.unavailable_source=nil;e.skipped=false
    changed();return true
end
-- Server's response to our own /findilavka, not arbitrary chat, is authoritative.
local former_game=M.mark_shop_missing_from_game
if type(former_game)=='function' then
    M.mark_shop_missing_from_game=function(shop,timestamp)
        local ok=former_game(shop,timestamp)
        if ok and block_related(shop,nil,'shop_missing','game')>0 then changed()end
        return ok
    end
end
-- A stable, numbered, owner-identified shop observed in game may prove that
-- the old owner no longer runs this shop; missing ITEM still needs manual review.
function A.observe_live_shop()
    local live=DSP.live and DSP.live.shop
    if not live or not live.scan_complete or tonumber(live.server)~=sid()
        or not valid_shop(live.num) or tostring(live.owner or'')==''then return false end
    local s=A.active()
    if not s or s.sid~=sid()then return false end
    local ts=tonumber(live.items_updated)or 0
    if ts<=0 or now()-ts>90 then return false end
    local blocked=0
    for _,e in ipairs(s.routes)do
        local side,shop=required_leg(e)
        local owner=side=='sell'and e.seller_owner or e.buyer_owner
        if side and tostring(shop)==tostring(live.num)
            and owner~='?' and not text_eq(owner,live.owner)
            and not e.unavailable_reason then
            e.unavailable_reason='owner_changed';e.unavailable_source='game'
            e.unavailable_at=now();e.unavailable_side=side;e.skipped=true;blocked=blocked+1
        end
    end
    if blocked>0 then changed()end
    return blocked>0
end
local previous_review=A.review_market
function A.review_market(...)
    local t=now()
    if t-(A._last_availability_check or 0)>=2 then
        A._last_availability_check=t
        A.observe_live_shop()
    end
    return previous_review(...)
end
return true

      end
      _v297_availability()
    end
    do
      local function _v297_arb_ui()
-- Palatka AI arbitration companion: native Carbon controls, compact game-safe panel.
-- All trades remain manually acknowledged; no packet, teleport or server automation.
local A,M,V=DSP.arb_agent,DSP.market,DSP.ui22
local function u(s)return DSP.utf8(tostring(s or ''))end
local function label(s)imgui.Text(u(s))end
local function quiet(s)imgui.TextDisabled(u(s))end
local function green(s)imgui.TextColored(DSP.theme.col('good',1),u(s))end
local function red(s)imgui.TextColored(DSP.theme.col('bad',1),u(s))end
local function b(name,id,w,active) return V.button(name,'agent291_'..id,w,active,false,38)end
local function money(v)return DSP.money(tonumber(v)or 0)end
local function selected(s)
    local index=math.max(1,math.min(tonumber(s.focus)or 1,#s.routes))
    return s.routes[index],index
end
local function status(e)
    if e.unavailable_reason=='shop_missing' then return 'Нет лавки' end
    if e.unavailable_reason=='item_missing' then return 'Нет предмета' end
    if e.unavailable_reason=='owner_changed' then return 'Смена владельца' end
    if e.skipped then return 'Пропущено' end
    if e.sold>=e.qty then return 'Завершено' end
    if e.bought<e.qty then return 'Покупка' end
    return 'Продажа'
end
local function rect(io)
    DSP.settings.arb_agent_window=DSP.settings.arb_agent_window or{}
    local p=DSP.settings.arb_agent_window
    local sw,sh=io.DisplaySize.x,io.DisplaySize.y
    local w=DSP.clamp(tonumber(p.w)or 440,math.min(305,sw-16),math.max(305,sw-16))
    local h=DSP.clamp(tonumber(p.h)or 390,math.min(250,sh-16),math.max(250,sh-16))
    return {w=w,h=h,x=DSP.clamp(tonumber(p.x)or(sw-w-12),0,math.max(0,sw-w)),
        y=DSP.clamp(tonumber(p.y)or 110,0,math.max(0,sh-h))}
end
local function drag(g,io,resize)
    local d=io.MouseDelta
    if not d or (d.x==0 and d.y==0) then return end
    local w=resize and DSP.clamp(g.w+d.x,math.min(305,io.DisplaySize.x-16),io.DisplaySize.x-g.x)or g.w
    local h=resize and DSP.clamp(g.h+d.y,math.min(250,io.DisplaySize.y-16),io.DisplaySize.y-g.y)or g.h
    local x=resize and g.x or DSP.clamp(g.x+d.x,0,io.DisplaySize.x-w)
    local y=resize and g.y or DSP.clamp(g.y+d.y,0,io.DisplaySize.y-h)
    DSP.settings.arb_agent_window={x=x,y=y,w=w,h=h}
    A._geometry_dirty=true
end
local function notice(msg)A.ui_message=msg end
local function route_queue(s)
    local total=#s.routes
    if total==0 then return end
    local pages=math.max(1,math.ceil(total/4))
    A.queue_page=DSP.clamp(tonumber(A.queue_page)or 1,1,pages)
    quiet('Маршруты: '..total..'  |  Страница '..A.queue_page..'/'..pages)
    local from=(A.queue_page-1)*4+1
    for i=from,math.min(total,from+3)do
        local e=s.routes[i]
        if b(V.fit(i..'. '..e.name..' · '..status(e),math.max(100,imgui.GetContentRegionAvail().x-20)),
            'route_'..i,-1,s.focus==i)then
            A.focus(i);A.qty_key=nil
        end
    end
    if pages>1 then
        if b('Ранее','pageprev',110)then A.queue_page=math.max(1,A.queue_page-1)end
        imgui.SameLine(0,8)
        if b('Далее','pagenext',110)then A.queue_page=math.min(pages,A.queue_page+1)end
    end
end
local function route_info(e,index,total)
    if not e then quiet('Новых маршрутов пока нет');return end
    quiet('Сделка '..index..' из '..total..' · '..status(e))
    label(V.fit(e.name,math.max(120,imgui.GetContentRegionAvail().x-12)))
    quiet('План '..e.qty..' шт.  |  Ожидаемая прибыль ~ '..money(e.proposed_profit))
    quiet('Куплено '..e.bought..' · Продано '..e.sold)
    if e.skipped then
        if e.bought>e.sold then red('Товаров на руках: '..(e.bought-e.sold)..' шт.')end
        quiet('Маршрут остаётся в сессии. Можно вернуть его или перейти дальше.')
        local half=math.max(105,math.floor((imgui.GetContentRegionAvail().x-6)/2))
        if b('Вернуть маршрут','restore',half)then
            local ok,err
            if e.unavailable_reason then ok,err=A.restore_unavailable(index)else ok=A.skip(index,false)end
            notice(ok and 'Маршрут снова активен' or tostring(err or 'Не удалось вернуть маршрут'))
        end
        imgui.SameLine(0,6)
        if b('Следующий','skipped_next',half)then A.next(1);A.qty_key=nil end
        return
    end
    if e.sold>=e.qty then green('Сделка завершена');return end
    local buying=e.bought<e.qty
    local side=buying and 'buy' or 'sell'
    local shop=buying and e.seller_shop or e.buyer_shop
    local owner=buying and e.seller_owner or e.buyer_owner
    local price=buying and e.buy_price or e.sell_price
    local remaining=buying and(e.qty-e.bought)or(e.bought-e.sold)
    if remaining<=0 then return end
    green(buying and 'Купить' or 'Продать')
    label('Лавка #'..shop..' · '..tostring(owner or'?'))
    quiet('Осталось '..remaining..' шт.  |  '..money(price)..' / шт.')
    if b('Метка на лавку #'..shop,'mark',-1)then
        if not M.mark_shop(shop)then notice('Метка недоступна')end
    end
    if b('Нет лавки','missing_shop',145)then
        local ok,err=A.mark_unavailable(index,'shop')
        notice(ok and 'Лавка исключена из планов' or tostring(err))
    end
    imgui.SameLine(0,6)
    if b('Нет предмета','missing_item',160)then
        local ok,err=A.mark_unavailable(index,'item')
        notice(ok and 'Предложение исключено' or tostring(err))
    end
    local key=e.id..':'..side
    if A.qty_key~=key then A.qty_key=key;A.qty_field=imgui.new.int(remaining)end
    quiet('Подтверждение количества:')
    imgui.SetNextItemWidth(math.min(160,imgui.GetContentRegionAvail().x))
    imgui.InputInt('##agent291_qty',A.qty_field,1,10)
    if b(buying and 'Подтвердить покупку' or 'Подтвердить продажу','confirm',-1,true)then
        local ok,err=A.confirm(index,side,A.qty_field[0])
        if ok then A.qty_key=nil;notice('Количество записано')else notice(tostring(err))end
    end
    local hint=A.hint
    if hint and hint.route_id==e.id and hint.side==side then
        quiet('Обнаружен похожий чек: '..hint.qty..' шт.')
        if b('Принять данные чека','receipt',-1)then
            local ok,err=A.confirm(index,side,hint.qty)
            if ok then A.qty_key=nil;notice('Чек подтверждён')else notice(tostring(err))end
        end
    end
end
function A.draw()
    local s=A.active()
    if not s then A.show(false);return end
    if A.review_market then A.review_market()end
    local io=imgui.GetIO()
    local g=rect(io)
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(.94)
    local color_count=DSP.theme.push_window()
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(9,8))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(6,6))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,9)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse
    if imgui.Begin('##palatka_arbitrage_agent',nil,flags)then
        if V.apply_font then V.apply_font()end
        if b('Арбитраж · переместить','handle',math.max(100,g.w-112))then end
        if imgui.IsItemActive() and io.MouseDelta then drag(g,io,false)end
        imgui.SameLine(0,5)
        if b(A.queue_expanded and '-' or '+','queue',40)then A.queue_expanded=not A.queue_expanded end
        imgui.SameLine(0,5)
        if b('X','close',43)then A.show(false)end
        local st=A.stats()
        quiet('Завершено '..st.done..'/'..st.routes..' · В работе '..st.pending)
        green('Ожидаемый результат ~ '..money(st.profit_estimate))
        quiet('Мини-агент Palatka / сборка '..tostring(DSP.version or '?'))
        imgui.Separator()
        if A.queue_expanded then
            route_queue(s)
            if not A.end_confirm then
                if b('Закончить сессию','end',-1)then A.end_confirm=true end
            else
                red('Завершить сессию?')
                if b('Завершить','endyes',140)then A.stop();A.end_confirm=false end
                imgui.SameLine(0,5)
                if b('Отмена','endno',130)then A.end_confirm=false end
            end
            imgui.Separator()
        end
        if imgui.BeginChild('##agent291_content',imgui.ImVec2(0,-80),false,imgui.WindowFlags.NoScrollbar)then
            local e,i=selected(s)
            route_info(e,i,#s.routes)
            if DSP.mobile and DSP.mobile.touch_scroll then DSP.mobile.touch_scroll(io,'arb_agent_content')end
        end
        imgui.EndChild()
        if A.ui_message then quiet(V.fit(A.ui_message,math.max(120,g.w-35)))end
        if A.save_error then red('Не сохранено: '..tostring(A.save_error))end
        if A.ui_error then red('Ошибка интерфейса: см. standalone.log')end
        if b('< Предыдущая','prev',math.max(105,math.floor((g.w-36)/2)))then A.next(-1);A.qty_key=nil end
        imgui.SameLine(0,6)
        if b('Следующая >','next',math.max(105,math.floor((g.w-36)/2)))then A.next(1);A.qty_key=nil end
        -- Native ImGui drag-resize grip, visually aligned to Palatka corners.
        imgui.SetCursorPos(imgui.ImVec2(g.w-39,g.h-36))
        if b('//','resize',29)then end
        if imgui.IsItemActive()and io.MouseDelta then drag(g,io,true)end
    end
    imgui.End()
    imgui.PopStyleVar(3)
    if color_count and color_count>0 then imgui.PopStyleColor(color_count)end
    if A._geometry_dirty and not imgui.IsMouseDown(0)then
        A._geometry_dirty=false
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
    end
end
return true

      end
      _v297_arb_ui()
    end
    if DSP.promo then DSP.promo._mh_scheduler_v294=nil end
    do
      local function _v297_promo()
-- v2.9.4: Market Helper scheduler: one template = one batch of chat commands.
-- No packet injection or server cooldown bypass. Fully opt-in and cancellable.
local P=DSP.promo
if P._mh_scheduler_v294 then return true end
P._mh_scheduler_v294=true

local function now()return os.time()end
local function session_limit()
    return DSP.controls and DSP.controls.get and DSP.controls.get('promo_session_limit')
        or P.MAX_SESSION or 12
end
local function global_cooldown()
    return DSP.controls and DSP.controls.get and DSP.controls.get('promo_global_cooldown_s')
        or math.max(30,tonumber(P.MIN_INTERVAL)or 30)
end
local function connected()
    if type(sampSendChat)~='function' then return false end
    if sampIsSampAvailable and not sampIsSampAvailable()then return false end
    if sampIsLocalPlayerSpawned and not sampIsLocalPlayerSpawned()then return false end
    return true
end
local function clamp(v,lo,hi,default)
    v=tonumber(v)
    if not v or v~=v then return default end
    return math.max(lo,math.min(hi,v))
end
local function persist()
    if DSP.save_settings then
        local ok,why=DSP.save_settings()
        if not ok and DSP.flog then DSP.flog('PROMO SAVE ERROR: '..tostring(why))end
        return ok~=false,why
    end
    return true
end
local function rows(t)
    local result={}
    for _,r in ipairs(t.rows or{})do
        if r.auto~=false and type(r.text)=='string' and r.text~='' and P.validate(r.text)then
            result[#result+1]=r.text
        end
    end
    return result
end
local function active()
    for i,t in ipairs(P.settings().templates)do
        if t.auto~=false and #rows(t)>0 then return true end
    end
    return false
end
local function interval(t)
    local low=clamp(t.interval_min,0,3600,0)
    if low<=0 then
        low=clamp((t.rows or{})[1] and t.rows[1].interval or t.interval,30,3600,180)
    end
    local high=clamp(t.interval_max,0,3600,0)
    if high<=0 or high<low then high=low end
    low=math.max(30,math.floor(low))
    high=math.max(low,math.floor(high))
    return low==high and low or math.random(low,high)
end
local function make_batch(index,t,manual,at)
    local commands=rows(t)
    if #commands==0 then return nil,'Нет разрешённых строк в шаблоне'end
    if t.random_line and #commands>1 then commands={commands[math.random(1,#commands)]}end
    return {index=index,commands=commands,pos=1,manual=manual==true,
        due=at,waiting=clamp(t.waiting,.5,10,1.5)}
end
local function set_stopped(reason)
    local s=P.settings()
    P.running=false;P._batch=nil;P.manual_busy=false;P.manual_template=nil
    P.pause_reason=reason or 'Выключен'
    s.enabled=false
    persist()
end
local function report_error(err)
    P.last_error=tostring(err or'Ошибка отправки')
    P.pause_reason=P.last_error
    if DSP.flog then DSP.flog('PROMO: '..P.last_error)end
end
function P.start(at)
    at=at or now()
    if not active()then return false,'Включи хотя бы один шаблон с командами'end
    local s=P.settings()
    if not s.continuous and (P.session_count or 0)>=session_limit() then
        return false,'Лимит отправок сессии исчерпан'
    end
    local prior=s.enabled
    s.enabled=true
    local ok,why=persist()
    if not ok then s.enabled=prior;return false,tostring(why or'Не удалось сохранить запуск')end
    P.running=true;P.last_error=nil;P.pause_reason=nil;P._batch=nil
    P.manual_busy=false;P.manual_template=nil
    P.was_online=false
    P.next_at=at+clamp(s.start_delay,10,120,20)
    for _,t in ipairs(s.templates)do t._promo_due=nil end
    return true
end
function P.stop()
    set_stopped('Остановлен пользователем')
end
function P.bootstrap(at)
    at=at or now()
    local s=P.settings()
    P.running=false;P._batch=nil;P.manual_busy=false;P.manual_template=nil
    P.session_count=0;P.last_sent=0;P.was_online=false;P.last_error=nil
    P.next_at=0
    for _,t in ipairs(s.templates)do t._promo_due=nil end
    if s.resume_on_login and s.enabled and active() then
        P.running=true
        P.next_at=at+clamp(s.start_delay,10,120,20)
        P.pause_reason='Ожидание подключения'
    end
end
function P.send_template_once(index)
    if P._batch then return false,'Дождись завершения текущего шаблона'end
    if not connected()then return false,'Нет подключения к игре'end
    local t=P.settings().templates[index]
    if not t then return false,'Шаблон не найден'end
    local batch,why=make_batch(index,t,true,now())
    if not batch then return false,why end
    P._batch=batch
    P.manual_busy=true;P.manual_template=index
    P.last_error=nil;P.pause_reason=nil
    return true
end
local function finish_batch(batch,at)
    local s=P.settings()
    local t=s.templates[batch.index]
    if t then
        t.last_sent=at
        if not batch.manual then
            t.auto_count=(tonumber(t.auto_count)or 0)+1
            local limit=clamp(t.auto_limit,0,1000,0)
            if limit>0 and t.auto_count>=limit then
                t.auto=false
                t.auto_count=0
                P.last_error='Шаблон «'..tostring(t.name or'?')..'»: достигнут лимит'
            end
            t._promo_due=at+interval(t)
        end
    end
    P._batch=nil;P.manual_busy=false;P.manual_template=nil
    P.next_at=at+global_cooldown()
    persist()
end
local function step_batch(at,send,online)
    local batch=P._batch
    if not batch or at<batch.due then return false end
    if not online then
        report_error('Нет соединения: отправка приостановлена')
        P._batch=nil;P.manual_busy=false;P.manual_template=nil
        return false
    end
    if not P.settings().continuous and (P.session_count or 0)>=session_limit() then
        set_stopped('Лимит сообщений за сессию')
        return false
    end
    local raw=batch.commands[batch.pos]
    local cmd,why=P.expand(raw)
    if not cmd or #cmd>P.MAX_STEP_BYTES then
        report_error(why or'Команда превышает 200 байт')
        P._batch=nil;P.manual_busy=false;P.manual_template=nil
        P.next_at=at+30
        return false
    end
    local sender=send or sampSendChat
    if type(sender)~='function'then report_error('Отправка чата недоступна');return false end
    local ok,result=pcall(sender,cmd)
    if not ok or result==false then
        report_error(ok and'Отправка отклонена' or result)
        P._batch=nil;P.manual_busy=false;P.manual_template=nil
        P.next_at=at+30
        return false
    end
    P.last_sent=at
    P.last_command=cmd
    P.session_count=(P.session_count or 0)+1
    batch.pos=batch.pos+1
    P.last_error=nil
    if batch.pos>#batch.commands then
        finish_batch(batch,at)
    else
        batch.due=at+math.max(1,math.ceil(batch.waiting))
        P.next_at=batch.due
    end
    if not P.settings().continuous and P.session_count>=session_limit() then
        set_stopped('Лимит сообщений за сессию')
    end
    return true
end

function P.tick(at,send,online)
    at=at or now()
    if online==nil then online=connected()end
    if P._batch then return step_batch(at,send,online)end
    if not P.running then return false end
    if not online then
        P.was_online=false
        P.pause_reason='Нет подключения: ожидание'
        return false
    end
    local s=P.settings()
    if not P.was_online then
        P.was_online=true
        P.next_at=math.max(P.next_at or 0,at+clamp(s.start_delay,10,120,20))
        P.pause_reason='Ожидание после входа'
        return false
    end
    if at<(P.next_at or 0)then return false end
    if not s.continuous and P.session_count>=session_limit() then
        set_stopped('Лимит сообщений за сессию')
        return false
    end
    local earliest
    for index,t in ipairs(s.templates)do
        if t.auto~=false and #rows(t)>0 then
            local due=t._promo_due
            if not due then
                local last=tonumber(t.last_sent)or 0
                due=last>0 and last+interval(t)or at
                t._promo_due=due
            end
            if at>=due and at>=((P.last_sent or 0)+global_cooldown()) or
               (at>=due and (P.last_sent or 0)==0) then
                local batch,why=make_batch(index,t,false,at)
                if not batch then report_error(why);return false end
                P._batch=batch
                P.pause_reason=nil
                return step_batch(at,send,online)
            end
            earliest=not earliest and due or math.min(earliest,due)
        end
    end
    if not earliest then
        set_stopped('Нет включённых шаблонов')
    else
        P.next_at=math.max(at+1,earliest)
    end
    return false
end
function P.queue_left()
    if P._batch then return math.max(0,math.ceil(P._batch.due-now()))end
    if not P.running then return nil end
    return math.max(0,math.ceil((P.next_at or 0)-now()))
end
return true

      end
      _v297_promo()
    end
    do
      local function _v297_controls()
-- Palatka AI 2.9.7: user control center for safe, persistent timing and status.
-- Only explicitly wired controls are editable. No automatic trade starts.
DSP.controls=DSP.controls or {}
local C,V,M=DSP.controls,DSP.ui22,DSP.mobile
local limits={
    sell_step_pause_ms={100,5000,260,'Пауза между выставлениями, мс'},
    buy_step_pause_ms={0,5000,0,'Пауза между позициями скупки, мс'},
    promo_global_cooldown_s={30,3600,30,'Пауза между циклами рекламы, сек'},
    promo_session_limit={1,200,12,'Лимит команд за сессию'},
    refresh_seconds={180,3600,300,'Обновление рынка API, сек'},
    local_offer_ttl_minutes={5,1440,60,'Актуальность локальной лавки, мин'},
    max_local_shops={20,300,80,'Лавок в локальном кэше'},
    promo_start_delay={10,120,20,'Пауза после входа, сек'}
}
C.limits=limits
local function target(key)
    if key=='promo_start_delay'then
        DSP.settings.promo=DSP.settings.promo or{}
        return DSP.settings.promo,'start_delay'
    end
    if key=='refresh_seconds'or key=='local_offer_ttl_minutes'or key=='max_local_shops'then
        return DSP.settings,key
    end
    DSP.settings.control_center=DSP.settings.control_center or{}
    return DSP.settings.control_center,key
end
function C.get(key)
    local spec=limits[key];if not spec then return nil end
    local t,k=target(key)
    local v=tonumber(t[k])
    if not v or v~=v or v%1~=0 or v<spec[1]or v>spec[2]then return spec[3]end
    return v
end
function C.set(key,value)
    local spec=limits[key];if not spec then return false,'Неизвестная настройка'end
    local n=tonumber(value)
    if not n or n~=n or n%1~=0 or n<spec[1]or n>spec[2]then
        return false,'Допустимо: '..spec[1]..' - '..spec[2]
    end
    local t,k=target(key);local previous=t[k]
    t[k]=n
    local ok,err=DSP.save_settings()
    if not ok then t[k]=previous;return false,'Не удалось сохранить: '..tostring(err)end
    if key=='refresh_seconds' and DSP.market and DSP.market.state then
        DSP.market.state.filter_version=-1
    end
    return true
end
local ordered={'sell_step_pause_ms','buy_step_pause_ms','promo_global_cooldown_s',
    'promo_session_limit','promo_start_delay','refresh_seconds',
    'local_offer_ttl_minutes','max_local_shops'}
function C.profile(name)
    local profiles={
        default={260,0,30,12,20,300,60,80},
        cautious={800,800,300,12,30,600,30,80},
        relaxed={1200,1500,600,6,45,900,20,60}
    }
    local values=profiles[name];if not values then return false,'Профиль не найден'end
    local previous={}
    for i,key in ipairs(ordered)do
        local t,k=target(key)
        previous[i]={t,k,t[k]};t[k]=values[i]
    end
    local ok,err=DSP.save_settings()
    if not ok then
        for _,p in ipairs(previous)do p[1][p[2]]=p[3]end
        return false,'Не удалось сохранить профиль: '..tostring(err)
    end
    C._editors={}
    return true
end
function C.stop_all()
    local errors={}
    if DSP.auto then
        if DSP.auto.sell_running and DSP.auto.stop_sell then
            local ok,err=pcall(DSP.auto.stop_sell)
            if not ok then errors[#errors+1]=tostring(err)end
        end
        if DSP.auto.buy_running and DSP.auto.stop_buy then
            local ok,err=pcall(DSP.auto.stop_buy)
            if not ok then errors[#errors+1]=tostring(err)end
        end
    end
    if DSP.promo and DSP.promo.stop and (DSP.promo.running or DSP.promo._batch) then
        local ok,err=pcall(DSP.promo.stop)
        if not ok then errors[#errors+1]=tostring(err)end
    end
    if #errors>0 then return false,table.concat(errors,'; ')end
    return true
end
local function status()
    local a,p=DSP.auto or{},DSP.promo or{}
    local left=p.queue_left and p.queue_left()or nil
    local lines={
        'Продажа: '..(a.sell_running and 'работает' or 'выключена')..
            ' | Скупка: '..(a.buy_running and 'работает' or 'выключена'),
        'Операция: '..tostring(a.status or 'готово'),
        'Авто-пиар: '..(p.running and 'работает' or 'выключен')..
            ' | Команд: '..tostring(p.session_count or 0)..
            (left and (' | следующая через '..left..' с')or''),
        'Рынок: '..tostring(DSP.market and DSP.market.state and DSP.market.state.status or 'нет данных')
    }
    return lines
end
local function b(title,id,w,on,primary)
    return V.button(title,'control297_'..id,w,on,primary,39)
end
local function edit_field(key)
    local spec=limits[key]
    C._editors=C._editors or{}
    local item=C._editors[key]
    if not item then item={value=C.get(key)};C._editors[key]=item end
    V.muted(spec[4]..'  ['..spec[1]..'..'..spec[2]..']')
    local edited=M.compact_number(item,'value','ctl297_'..key,165,spec[1])
    if edited then
        local ok,err=C.set(key,item.value)
        if not ok then
            C.error=err
            item.value=C.get(key)
            M.refresh_buffer(item,'value')
        else C.error=nil end
    end
end
local function toggle(label,obj,key,default)
    local on=obj[key]
    if on==nil then on=default end
    if b(label..': '..(on and 'ВКЛ' or 'ВЫКЛ'),'toggle_'..key,230,on)then
        local old=obj[key]
        obj[key]=not on
        local ok,err=DSP.save_settings()
        if not ok then obj[key]=old;C.error='Не удалось сохранить: '..tostring(err)
        else C.error=nil end
    end
end
function C.draw()
    V.heading('Управление Palatka AI')
    V.muted('Изменение параметров не запускает команды. Стандартные значения можно вернуть.')
    if b('Остановить торговлю и пиар','stop_all',300,false,true)then
        local ok,err=C.stop_all();C.error=not ok and err or nil
    end
    V.inline(5)
    if b('Стандарт','preset_default',130)then
        local ok,err=C.profile('default');C.error=not ok and err or nil
    end
    if b('Бережный','preset_cautious',140)then
        local ok,err=C.profile('cautious');C.error=not ok and err or nil
    end
    V.inline(5)
    if b('Медленный','preset_relaxed',140)then
        local ok,err=C.profile('relaxed');C.error=not ok and err or nil
    end
    if C.error then V.red(C.error)end
    V.list('control_center_fields',function()
        V.text('Текущий статус')
        for _,line in ipairs(status())do V.muted(line)end
        if DSP.auto and DSP.auto.progress then
            local pr=DSP.auto.progress
            V.muted('Прогресс: '..tostring(pr.done or 0)..' / '..tostring(pr.total or 0)..
                ' | ошибок: '..tostring(pr.failed or 0))
        end
        imgui.Separator()
        V.text('Выставление лавки и скупка')
        toggle('ТЕСТ без игровых команд',DSP.settings,'dry_run',true)
        edit_field('sell_step_pause_ms')
        edit_field('buy_step_pause_ms')
        V.muted('Реальное выставление запускается вручную во вкладке Торговля.')
        if b('Перейти к торговле','trade',225)then V.set_screen('palatka')end
        imgui.Separator()
        V.text('Авто-пиар')
        DSP.settings.promo=DSP.settings.promo or{}
        toggle('Возобновлять после входа',DSP.settings.promo,'resume_on_login',false)
        toggle('Повторять без лимита',DSP.settings.promo,'continuous',false)
        edit_field('promo_global_cooldown_s')
        edit_field('promo_session_limit')
        edit_field('promo_start_delay')
        V.muted('Интервалы, паузы строк и лимиты шаблонов задаются в редакторе авто-пиара.')
        V.muted('Соблюдай ограничения сервера: отправка из Lua не подтверждает приём.')
        if b('Открыть авто-пиар','promo',225)then V.set_screen('promo')end
        imgui.Separator()
        V.text('Лавки и данные')
        edit_field('refresh_seconds')
        edit_field('local_offer_ttl_minutes')
        edit_field('max_local_shops')
        V.muted('TTL означает свежесть скана, а не удаление истории.')
        if b('Открыть список лавок','shops',225)then V.set_screen('lavki')end
        imgui.Separator()
        V.text('Ломбард')
        local ls=DSP.lombard and DSP.lombard.stats and DSP.lombard.stats()
        if ls then V.muted('В базе: '..tostring(ls.items)..' | страниц: '..tostring(ls.pages))end
        if b('Открыть ломбард','lombard',225)then V.set_screen('lombard')end
        V.muted('Нативный скан запускается вручную у меню ломбарда.')
    end,{footer=false})
end
V.control_screen=C.draw
return true

      end
      _v297_controls()
    end
    do
      local function _v297_diag()
-- In-game verification for actively loaded UI modules, not just the version manifest.
local V,C,A,P=DSP.ui22,DSP.craglog,DSP.arb_agent,DSP.promo
DSP.active_ui_build=tostring(DSP.version or 'unknown')
DSP.active_ui_refs={
    agent=A and A.draw, journal=C and C.draw,
    journal_tab=V and V.journal, promo=V and V.promo_screen
}
local function report()
    local ref=DSP.active_ui_refs or{}
    local same=V and C and A and P and
        A.draw==ref.agent and C.draw==ref.journal and
        V.journal==ref.journal_tab and V.promo_screen==ref.promo and
        type(P.save_template_options)=='function' and type(C.trade_rows)=='function'
    local line='Palatka runtime '..tostring(DSP.version or '?')..
        ' / UI '..tostring(DSP.active_ui_build or 'none')..
        ' / screens '..(same and'ACTIVE' or'MISMATCH')
    if DSP.flog then DSP.flog('CRDIAG '..line)end
    if sampAddChatMessage then
        sampAddChatMessage('[Palatka] '..line,0x99FFAA)
    end
    return same,line
end
DSP.ui_runtime_check=report
if sampRegisterChatCommand and not DSP._crdiag_registered then
    sampRegisterChatCommand('crdiag',report)
    DSP._crdiag_registered=true
end
if DSP.flog then
    local ok,msg=report()
    DSP.flog('UI modules installed: '..tostring(ok)..' / '..tostring(msg))
end
return true

      end
      _v297_diag()
    end
    do
      local agent = DSP.arb_agent
      if agent and type(agent.draw)=='function' then
        local old_draw=agent.draw
        agent.draw=function(...)
          local ok,err=xpcall(function() return old_draw() end,debug.traceback)
          if not ok then
            agent.ui_error=tostring(err)
            if DSP.flog and agent._v297_last_draw_error~=agent.ui_error then
              agent._v297_last_draw_error=agent.ui_error
              DSP.flog('ARB AGENT UI 2.9.7: '..agent.ui_error)
            end
          end
        end
      end
    end
    do
      local V=DSP.ui22 or DSP.ui21
      if V and V.set_screen then
        local old_tools=V.tools
        V.tools=function(page,...)
          if page=='control' and DSP.controls then
            return DSP.controls.draw()
          end
          if old_tools then return old_tools(page,...) end
        end
        -- The existing primary nav is a local captured table in the 2.9.6
        -- shell. Add clear on-screen shortcuts instead of rebuilding ImGui.
        local function shortcut(id)
          if V.button('Управление и интервалы','v297_control_'..id,246,false,true,39) then
            V.set_screen('control')
            return true
          end
          return false
        end
        if type(V.home)=='function' then
          local old_home=V.home
          V.home=function(...)
            if shortcut('home') then return end
            return old_home(...)
          end
        end
        if type(V.trade)=='function' then
          local old_trade=V.trade
          V.trade=function(...)
            if shortcut('trade') then return end
            return old_trade(...)
          end
        end
        if type(V.promo_screen)=='function' then
          local old_promo=V.promo_screen
          V.promo_screen=function(...)
            if shortcut('promo') then return end
            return old_promo(...)
          end
        end
      end
    end
    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka 2.9.7 OTA failed: '..tostring(err)) end
      return false
    end
    DSP._v297_installed=true
    DSP.version='2.9.7'
    if DSP.flog then DSP.flog('Palatka 2.9.7 control center installed') end
    return true
  end
  local function install_v298()
    if not install_v297() then return false end
    if DSP._v298_installed then DSP.version='2.9.8';return true end
    local ok,err=pcall(function()
      do
        local function v298_promo_mobile()
-- Palatka AI v2.9.8: compact Market Helper-style promotion screen.
-- Fresh implementation using Palatka models and native mobile mimgui.
-- Existing templates and per-template options are preserved.
local V,M,P=DSP.ui22,DSP.mobile,DSP.promo
if not (V and M and P) then return true end
if V._promo_mobile_298 then return true end
V._promo_mobile_298=true
local ffi=require('ffi')
local function b(label,id,width,active)
    return V.button(label,'pm298_'..id,width,active,false,39)
end
local function str(v)return DSP.to_u8(tostring(v or''))end
local function buffer(value,size)
    local buf=imgui.new.char[size]()
    local text=DSP.to_u8(tostring(value or''))
    ffi.fill(buf,size)
    ffi.copy(buf,text:sub(1,size-1))
    return buf
end
local function save()
    if DSP.save_settings then return DSP.save_settings()~=false end
    return true
end
local function toggle_auto(i)
    local t=P.settings().templates[i]
    if not t then return end
    local old=t.auto
    t.auto=(t.auto==false)
    t.auto_count=0;t._promo_due=nil
    if not save()then t.auto=old;V.promo298_error='Ошибка сохранения';return end
    if t.auto then
        -- In MH an auto_limit=0 means unrestricted template cycles. Preserve
        -- per-template limits and server pacing, not an unrelated 12-chat cap.
        local opts=P.settings()
        if not opts.continuous then
            local ok,why=P.set_option('continuous',true)
            if not ok then V.promo298_error=tostring(why);return end
        end
        if not P.running then
            local ok,why=P.start()
            if not ok then V.promo298_error=tostring(why)end
        end
    else
        local any=false
        for _,v in ipairs(P.settings().templates)do
            if v.auto~=false then any=true;break end
        end
        if not any and P.running then P.stop()end
    end
end
local function new_editor(index)
    local t=index and P.settings().templates[index] or nil
    local edit={index=index,name=buffer(t and t.name or'Новый шаблон',96),
        rows={},linebuf={},waiting=imgui.new.float(tonumber(t and t.waiting)or 1.5),
        min=imgui.new.int(tonumber(t and t.interval_min)or 300),
        max=imgui.new.int(tonumber(t and t.interval_max)or 0),
        limit=imgui.new.int(tonumber(t and t.auto_limit)or 0),
        random=t and t.random_line==true or false,
        auto=t and t.auto~=false or false}
    if t then
        for _,r in ipairs(t.rows or{})do
            edit.rows[#edit.rows+1]={text=r.text or'',auto=r.auto~=false,interval=r.interval or 300}
        end
    else
        edit.rows[1]={text='/s ',auto=true,interval=300}
    end
    for i,r in ipairs(edit.rows)do edit.linebuf[i]=buffer(r.text,512)end
    V.promo298_edit=edit
end
local function modify_number(label,ptr,id,lo,hi,step)
    V.muted(label..': '..tostring(ptr[0])..(id=='wait' and' с' or''))
    if b('-','minus_'..id,66)then ptr[0]=math.max(lo,ptr[0]-step)end
    V.inline(4,66)
    if b('+','plus_'..id,66)then ptr[0]=math.min(hi,ptr[0]+step)end
    ptr[0]=math.max(lo,math.min(hi,ptr[0]))
end
local function editor(e)
    V.heading('Автопиар / Редактор',function()
        if b('Назад','back',100)then V.promo298_edit=nil end
    end,110)
    if e.error then V.red(e.error)end
    if b('Сохранить шаблон','save_editor',224,true)then
        local name=DSP.to_cp(ffi.string(e.name)):match('^%s*(.-)%s*$')
        for i,r in ipairs(e.rows)do r.text=DSP.to_cp(ffi.string(e.linebuf[i]))end
        local ok,index=P.save_template(e.index,name,e.rows,e.auto)
        if ok then
            local more,why=P.save_template_options(index,{
                interval_min=e.min[0],interval_max=e.max[0],
                waiting=e.waiting[0],auto_limit=e.limit[0],random_line=e.random})
            if more then
                V.promo298_edit=nil;V.promo298_error=nil
                if e.auto and not P.running then
                    local yes,why=P.set_option('continuous',true)
                    if yes then
                        local begun,err=P.start()
                        if not begun then V.promo298_error=tostring(err)end
                    else V.promo298_error=tostring(why)end
                end
            else e.error=tostring(why)end
        else e.error=tostring(index)end
    end
    if e.index and b('Удалить шаблон','editor_delete',210)then
        V.promo298_delete=e.index
        V.open_popup('Удалить шаблон','pm298_delete')
    end
    V.list('pm298_editor',function()
        V.text('Название')
        imgui.SetNextItemWidth(-1)
        imgui.InputText('##pm298_title',e.name,96)
        V.muted('Каждая строка — отдельная команда. Не более 24 строк.')
        local remove
        for i,r in ipairs(e.rows)do
            V.text('Строка '..i)
            imgui.SetNextItemWidth(-1)
            imgui.InputText('##pm298_line_'..i,e.linebuf[i],512)
            if b(r.auto and'Строка ВКЛ' or'Строка ВЫКЛ','line_toggle_'..i,145,r.auto)then
                r.auto=not r.auto
            end
            V.inline(5,92)
            if b('Удалить','line_remove_'..i,92)then remove=i end
            imgui.Separator()
        end
        if remove and #e.rows>1 then
            table.remove(e.rows,remove);table.remove(e.linebuf,remove)
        end
        if b('+ Строка','line_add',165,true)then
            if #e.rows<24 then
                e.rows[#e.rows+1]={text='/s ',auto=true,interval=300}
                e.linebuf[#e.linebuf+1]=buffer('/s ',512)
            else e.error='Достигнут лимит строк'end
        end
        V.inline(5,162)
        if b('<lavka>','insert_lavka',155)then
            local i=#e.rows
            if i>0 then
                local prev=DSP.to_cp(ffi.string(e.linebuf[i]))
                if #prev<460 then
                    e.rows[i].text=prev..' <lavka>'
                    e.linebuf[i]=buffer(e.rows[i].text,512)
                end
            end
        end
        V.muted('<lavka> — номер твоей лавки, если он обнаружен.')
        V.text('Интервалы')
        modify_number('Пауза между строками (0.5-10 c)',e.waiting,'wait',.5,10,.5)
        modify_number('Минимальный интервал (сек)',e.min,'min',30,3600,30)
        modify_number('Максимум (0 = без случайности)',e.max,'max',0,3600,30)
        modify_number('Лимит циклов (0 = без лимита)',e.limit,'limit',0,1000,1)
        if b(e.random and'Случайная строка: ДА' or'Случайная строка: НЕТ',
                'random',235,e.random)then e.random=not e.random end
        if b(e.auto and'Авто: включено' or'Авто: выключено',
                'edited_auto',235,e.auto)then e.auto=not e.auto end
        V.muted('Интервал выбирается отдельно для каждого шаблона.')
    end,{footer=true})
end
local function countdown(t)
    if t.auto==false then return 'Авто выключено'end
    local low=tonumber(t.interval_min)or 0
    if low<=0 then low=tonumber((t.rows or{})[1] and t.rows[1].interval)or 300 end
    local high=tonumber(t.interval_max)or 0
    local period=high>low and(low..'-'..high)or tostring(low)
    local due=tonumber(t._promo_due)
    if not due then
        local last=tonumber(t.last_sent)or 0
        due=last>0 and last+low or os.time()
    end
    return 'Интервал '..period..'с | осталось '..math.max(0,due-os.time())..'с'
end
function V.promo_screen()
    if V.promo298_edit then return editor(V.promo298_edit)end
    local s=P.settings()
    V.heading('Автопиар',function()
        if b('+ Шаблон','new',155,true)then new_editor(nil)end
    end,160)
    V.muted('Как в Market Helper: Пуск / Авто / Редактировать')
    if P.running then
        if b('Остановить всё','stop_all',173,true)then P.stop()end
    else
        if b('Запустить авто','start_all',173,true)then
            if not s.continuous then P.set_option('continuous',true)end
            local ok,why=P.start()
            V.promo298_error=not ok and tostring(why)or nil
        end
    end
    V.inline(5,130)
    if b('Настройки','promo_settings',130)then V.set_screen('settings')end
    V.muted('Состояние: '..(P.running and(P.pause_reason or'работает')or'выключен')..
        ' | отправлено: '..tostring(P.session_count or 0))
    if V.promo298_error or P.last_error then V.red(tostring(V.promo298_error or P.last_error))end
    if #s.templates==0 then
        V.muted('Нет шаблонов. Нажми + Шаблон.')
        return
    end
    V.list_rows('pm298_templates',s.templates,128,function(t,i)
        V.row('pm298_t_'..i,128,function(w,x,y)
            V.at(x,y)
            V.text(V.fit(t.name or'Шаблон',math.max(105,w-18)))
            V.at(x,y+28)
            V.muted(V.fit(#(t.rows or{})..' строк | '..countdown(t),math.max(100,w-18)))
            local bw=math.max(78,math.floor((w-24)/3))
            V.at(x,y+64)
            if b('Пуск','send_'..i,bw)then
                local ok,why=P.send_template_once(i)
                V.promo298_error=not ok and tostring(why)or nil
            end
            V.inline(5,bw)
            if b(t.auto~=false and'Авто: ВКЛ' or'Авто: ВЫКЛ','auto_'..i,bw,t.auto~=false)then
                toggle_auto(i)
            end
            V.inline(5,bw)
            if b('Изменить','edit_'..i,bw)then new_editor(i)end
        end)
    end,{footer=true})
end
local old_popups=V.popups
function V.popups()
    if old_popups then old_popups()end
    V.popup('Удалить шаблон','pm298_delete',function()
        V.text('Удалить этот шаблон и все его строки?')
        if b('Удалить','confirm_delete',160)then
            local ok=P.remove(V.promo298_delete)
            if ok then V.promo298_edit=nil;imgui.CloseCurrentPopup()
            else V.promo298_error='Ошибка сохранения удаления'end
        end
        V.inline(5,120)
        V.cancel('pm298_delete')
    end,{w=415,h=225})
end
local expand=P.expand
function P.expand(text)
    if type(text)=='string' and text:find('<lavka>',1,true)then
        local number,why=P.own_shop_number()
        if not number then return nil,tostring(why or'Номер лавки неизвестен')end
        text=text:gsub('<lavka>',tostring(number))
    end
    return expand(text)
end
-- The earlier 2.9.7 OTA put control shortcuts in home/trade. Hide those,
-- without replacing the working home/trade renderers.
if not V._pm298_button_wrap then
    V._pm298_button_wrap=true
    local original=V.button
    V.button=function(label,id,...)
        if type(id)=='string' and id:find('^v297_control_') then return false end
        return original(label,id,...)
    end
end
if not V._pm298_nav_wrap then
    V._pm298_nav_wrap=true
    local original=V.list_rows
    V.list_rows=function(key,rows,...)
        if key=='navigation' and type(rows)=='table' then
            local filtered={}
            for _,item in ipairs(rows)do
                if type(item)~='table' or item[1]~='control' then
                    filtered[#filtered+1]=item
                end
            end
            return original(key,filtered,...)
        end
        return original(key,rows,...)
    end
end
return true

        end
        v298_promo_mobile()
      end
      do
        local function v298_fast_rec()
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

        end
        v298_fast_rec()
      end
    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka 2.9.8 install failed: '..tostring(err))end
      return false
    end
    DSP._v298_installed=true
    DSP.version='2.9.8'
    return true
  end
  local function install_v299()
    if not install_v298() then return false end
    if DSP._v299_installed then DSP.version='2.9.9'; return true end
    DSP._v299_installed=true
    DSP.version='2.9.9'
    if DSP.flog then DSP.flog('Palatka AI 2.9.9 Fast REC syntax hotfix ready') end
    return true
  end
  local function install_v2910()
    if not install_v299() then return false end
    if DSP._v2910_installed then DSP.version='2.9.10';return true end
    local ok,err=pcall(function()
      local C=DSP.craglog
      if C then C._drop_sales_v293=nil;C._stats_render_cache_v295=nil end
      if DSP.ui22 then DSP.ui22._stats_v293=nil;DSP.ui22._promo_mobile_298=nil end
      do
        local function v2910_74_promo_save_v2910()
-- Palatka AI 2.9.10: transactional promotion template save.
-- Keep all user-defined timing fields in the SAME durable write as the lines.
local P=DSP.promo
if not P or P._atomic_promo_2910 then return true end
P._atomic_promo_2910=true
local function num(v,low,high,default)
    v=tonumber(v)
    if not v or v~=v then return default end
    v=math.floor(v)
    if v<low or v>high then return nil end
    return v
end
local function trim(s)
    return tostring(s or''):match('^%s*(.-)%s*$')
end
local function flush()
    if type(DSP.save_settings)~='function'then return false,'Нет механизма сохранения'end
    local ok,saved,err=pcall(DSP.save_settings)
    if not ok then return false,tostring(saved)end
    if saved==false or saved==nil then return false,tostring(err or'Ошибка записи настроек')end
    -- In MonetLoader a successful return must correspond to actual saved bytes.
    if type(DSP.settings_path)=='string' and type(decodeJson)=='function' then
        local f=io.open(DSP.settings_path,'rb')
        if not f then return false,'Файл настроек не найден после сохранения'end
        local data=f:read('*a')or'';f:close()
        local pass,saved_data=pcall(decodeJson,data)
        if not pass or type(saved_data)~='table'
            or type(saved_data.promo)~='table'
            or type(saved_data.promo.templates)~='table' then
            return false,'Не удалось проверить записанные шаблоны'
        end
        local source=DSP.settings.promo.templates
        if #saved_data.promo.templates~=#source then
            return false,'Количество сохранённых шаблонов не совпадает'
        end
        for i,t in ipairs(source)do
            local disk=saved_data.promo.templates[i]
            if type(disk)~='table' or disk.name~=t.name
                or #(disk.rows or{})~=#(t.rows or{})
                or tonumber(disk.interval_min)~=tonumber(t.interval_min)
                or tonumber(disk.interval_max)~=tonumber(t.interval_max)
                or tonumber(disk.waiting)~=tonumber(t.waiting) then
                return false,'Проверка шаблона #'..i..' не пройдена'
            end
        end
    end
    return true
end
function P.save_template_complete(index,name,rows,enabled,options)
    local s=P.settings()
    if type(name)~='string' or #trim(name)<1 or #trim(name)>64 then
        return false,'Название должно быть от 1 до 64 байт'
    end
    name=trim(name)
    if type(rows)~='table' or #rows==0 or #rows>24 then
        return false,'Допустимо 1–24 рекламные строки'
    end
    local max_templates=tonumber(P.MAX_TEMPLATES)or 32
    if index~=nil then
        index=tonumber(index)
        if not index or index%1~=0 or not s.templates[index] then
            return false,'Шаблон не найден'
        end
    elseif #s.templates>=max_templates then
        return false,'Достигнут лимит шаблонов'
    end
    local previous=index and s.templates[index]or nil
    options=options or{}
    local low=num(options.interval_min,0,3600,previous and previous.interval_min or 0)
    local high=num(options.interval_max,0,3600,previous and previous.interval_max or 0)
    local limit=num(options.auto_limit,0,1000,previous and previous.auto_limit or 0)
    local waiting=tonumber(options.waiting)
    if low==nil or high==nil or limit==nil or not waiting
        or waiting~=waiting or waiting<.5 or waiting>10 then
        return false,'Неверные интервалы или лимит отправок'
    end
    if low>0 and low<(tonumber(P.MIN_INTERVAL)or 30)then
        return false,'Интервал меньше разрешённого'
    end
    if high>0 and high<low then return false,'Максимум меньше минимума'end
    local normalized,commands={},{}
    for i,row in ipairs(rows)do
        if type(row)~='table' then return false,'Ошибка строки '..i end
        local command=trim(row.text)
        local valid,why=P.validate(command)
        if not valid then return false,'Строка '..i..': '..tostring(why)end
        if #P.lines(command)~=1 then return false,'Только одна команда на строку'end
        local interval=num(row.interval,30,3600,300)
        if not interval then return false,'Неверный интервал строки '..i end
        commands[#commands+1]=command
        normalized[#normalized+1]={text=command,interval=interval,auto=row.auto~=false}
    end
    local record={}
    if previous then for k,v in pairs(previous)do record[k]=v end end
    record.name=name
    record.text=table.concat(commands,'\n')
    record.rows=normalized
    record.interval=normalized[1].interval
    record.auto=enabled==true
    record.interval_min=low
    record.interval_max=high
    record.auto_limit=limit
    record.random_line=options.random_line==true
    record.waiting=waiting
    record._promo_due=nil
    local target=index or (#s.templates+1)
    s.templates[target]=record
    local ok,why=flush()
    if not ok then
        if previous then s.templates[target]=previous
        else table.remove(s.templates,target)end
        P.last_save_error=tostring(why)
        if DSP.flog then DSP.flog('PROMO SAVE: '..P.last_save_error)end
        return false,P.last_save_error
    end
    P.last_save_error=nil
    P.last_saved_at=os.time()
    return true,target
end
return true

        end
        v2910_74_promo_save_v2910()
      end
      do
        local function v2910_59b_drop_sales_stats()
-- v2.9.3: reward/drop statistics joined with verified sales and current inventory scan.
local C=DSP.craglog
if C._drop_sales_v293 then return true end
C._drop_sales_v293=true

local old_period_start=C.period_start
function C.period_start(period,now)
    now=now or os.time()
    if period=='hour' then return now-3600 end
    if period=='week' then return now-7*86400 end
    if period=='month' then return now-30*86400 end
    if period=='day' or period=='today' then
        local d=os.date('*t',now);d.hour,d.min,d.sec=0,0,0;return os.time(d)
    end
    if period=='all' then return 0 end
    return old_period_start and old_period_start(period,now) or 0
end

local function positive(v)
    local n=tonumber(v)
    if not n or n~=n or n<=0 then return 0 end
    return math.floor(n)
end
local function split_ench(name,ench)
    name=tostring(name or'?')
    if ench~=nil then return name,tonumber(ench)or 0 end
    local base,n=name:match('^(.-)%s*%(%+(%d+)%)%s*$')
    return base or name,tonumber(n)or 0
end
local function add(map,name,ench,qty,exact)
    qty=positive(qty);if qty<=0 then return end
    name,ench=split_ench(name,ench)
    local key=DSP.item_key(name,ench)
    local row=map[key]
    if not row then
        row={key=key,name=name,ench=ench,qty=0,exact=true}
        map[key]=row
    end
    row.qty=row.qty+qty
    if exact==false then row.exact=false end
end
local function raw_qty(raw)
    local s=tostring(raw or'')
    -- Only an EXPLICIT item quantity can be treated as sold. The price and
    -- the inventory delta are never a substitute for an acknowledged sale.
    local q=s:match('[xXхХЧ]%s*(%d+)%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local item,q_from_item=normalize_receipt_item(e.item_name or e.item)
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then
                    q=q_from_item or 0
                    exact=q>0
                    if q<=0 then
                        -- Old receipts without a number tell us a sale happened,
                        -- but not how many resources were sold. Treat one unit
                        -- as a non-exact lower bound; never claim a loss.
                        q=1;exact=false
                    end
                end
                add(map,item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
)
        or s:match('%(%s*(%d+)%s*шт%.?%s*%)%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
)
        or s:match('%s(%d+)%s*шт%.?%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
)
        or s:match('%s(%d+)%s*[xXхХЧ]%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
)
    q=positive(q)
    return q>0 and q or nil
end
local function normalize_receipt_item(value)
    local item=tostring(value or'')
    local count=raw_qty(item)
    if count then
        item=item:gsub('%s*[xXхХЧ]%s*%d+%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
,'')
        item=item:gsub('%s*%(%s*%d+%s*шт%.?%s*%)%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
,'')
        item=item:gsub('%s+%d+%s*шт%.?%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
,'')
        item=item:gsub('%s+%d+%s*[xXхХЧ]%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
,'')
    end
    item=item:match('^%s*(.-)%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
)
    return item,count
end
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true

        end
        v2910_59b_drop_sales_stats()
      end
      do
        local function v2910_65b_stats_render_cache_v295()
-- v2.9.5: skip full inventory signature/loot reconciliation on every stats frame.
local C=DSP.craglog
if not C or C._stats_render_cache_v295 then return true end
C._stats_render_cache_v295=true
local original=C.drop_sales_stats
if type(original)~='function' then return true end
local cache={}
function C.drop_sales_stats(period,query)
    local a=DSP.auto or{}
    local inv=a.inv or{}
    local key=table.concat({
        tostring(period or'day'),tostring(query or''),
        tostring(C.history_revision or 0),tostring(C.visibility_revision or 0),
        tostring(DSP.logs and DSP.logs.revision or 0),
        tostring(DSP.rewards and DSP.rewards.sequence or 0),
        tostring(inv),tostring(#inv),tostring(a.inv_status or''),
        tostring(a.scanning),tostring(math.floor(os.time()/2))
    },'|')
    if cache.key==key then return cache.result end
    local result=original(period,query)
    cache={key=key,result=result}
    return result
end
return true

        end
        v2910_65b_stats_render_cache_v295()
      end
      do
        local function v2910_65a_stats_v293()
-- v2.9.3 statistics screen override. Keeps the legacy settings module untouched.
local V,M,C=DSP.ui22,DSP.mobile,DSP.craglog
if V._stats_v293 then return true end
V._stats_v293=true
local old_tools=V.tools
local function b(s,id,w,on)return V.button(s,'stats293_'..id,w,on,false,38)end
local function statistics()
    V.heading('Статистика ларцов / наград')
    V.stats293_period=V.stats293_period or DSP.settings.stats_mode or'day'
    local periods={{'hour','Час'},{'day','День'},{'week','Неделя'},{'month','Месяц'},{'all','Всё'}}
    local pw=math.max(58,(imgui.GetContentRegionAvail().x-24)/5)
    for i,p in ipairs(periods)do
        if b(p[2],'period_'..p[1],pw,V.stats293_period==p[1])then
            V.stats293_period=p[1];DSP.settings.stats_mode=p[1]
            if M.defer_save then M.defer_save()end
        end
        if i<#periods then V.inline(6,pw)end
    end
    local query=V.search('stats293','Поиск ларца / награды',-1)
    local s=C.drop_sales_stats(V.stats293_period,query)
    V.green('Выпало: '..tostring(s.dropped)..' шт. · Продано: '..tostring(s.sold)..' шт.')
    if s.inventory_ready then
        V.text('Фактически в последнем скане инвентаря: '..tostring(s.inventory_total)..' шт.')
    else
        V.muted('Инвентарь ещё не сканирован: фактическое количество не подменяем расчётом.')
    end
    V.muted('Расчётный остаток: '..tostring(s.journal_balance)..' шт. (известные награды минус учтённые продажи)')
    if s.approx then V.muted('~ В части чеков неизвестно количество проданного: остаток может быть завышен.')end
    V.muted('Разница со сканом не означает пропажу: возможны продажи без точного чека и другие операции.')
    if DSP.auto and not DSP.auto.scanning and b('Обновить фактический инвентарь','scan_inventory',260,true)then
        local ok=DSP.auto.scan_inventory()
        if ok==false then V.stats293_error='Сканирование сейчас недоступно'else V.stats293_error=nil end
    elseif DSP.auto and DSP.auto.scanning then
        V.muted('Сканирование инвентаря...')
    end
    if V.stats293_error then V.red(V.stats293_error)end
    V.list_rows('stats293_'..V.stats293_period,s.items,86,function(r,i)
        V.row('row_'..i,86,function(w,x,y)
            local name=r.name..((tonumber(r.ench)or 0)>0 and(' (+'..r.ench..')')or'')
            V.at(x,y+1);V.text(V.fit(name,w-12))
            V.at(x,y+29);V.muted(V.fit('Выпало '..r.dropped..' · Продано '..r.sold..
                (r.sold_exact and''or'~')..' · Остаток журнала '..r.journal_balance,w-12))
            V.at(x,y+56)
            if s.inventory_ready then
                V.green(V.fit('Фактически сейчас: '..r.inventory..' шт. · оценка дропа ~ '..DSP.money(r.estimated or 0),w-12))
            else
                V.muted(V.fit('Факт: нужен скан инвентаря · оценка дропа ~ '..DSP.money(r.estimated or 0),w-12))
            end
        end)
    end,{count=#s.items,footer=function()
        V.muted('Факт берётся только из собственного скана инвентаря; журнал не выдаётся за инвентарь.')
    end})
end
function V.tools(screen)
    if screen=='stats' then return statistics() end
    return old_tools(screen)
end
return true

        end
        v2910_65a_stats_v293()
      end
      do
        local function v2910_72_promo_market_style_v298()
-- Palatka AI v2.9.8: compact Market Helper-style promotion screen.
-- Fresh implementation using Palatka models and native mobile mimgui.
-- Existing templates and per-template options are preserved.
local V,M,P=DSP.ui22,DSP.mobile,DSP.promo
if not (V and M and P) then return true end
if V._promo_mobile_298 then return true end
V._promo_mobile_298=true
local ffi=require('ffi')
local function b(label,id,width,active)
    return V.button(label,'pm298_'..id,width,active,false,39)
end
local function str(v)return DSP.to_u8(tostring(v or''))end
local function buffer(value,size)
    local buf=imgui.new.char[size]()
    local text=DSP.to_u8(tostring(value or''))
    ffi.fill(buf,size)
    ffi.copy(buf,text:sub(1,size-1))
    return buf
end
local function save()
    if DSP.save_settings then return DSP.save_settings()~=false end
    return true
end
local function toggle_auto(i)
    local t=P.settings().templates[i]
    if not t then return end
    local old=t.auto
    t.auto=(t.auto==false)
    t.auto_count=0;t._promo_due=nil
    if not save()then t.auto=old;V.promo298_error='Ошибка сохранения';return end
    if t.auto then
        -- In MH an auto_limit=0 means unrestricted template cycles. Preserve
        -- per-template limits and server pacing, not an unrelated 12-chat cap.
        local opts=P.settings()
        if not opts.continuous then
            local ok,why=P.set_option('continuous',true)
            if not ok then V.promo298_error=tostring(why);return end
        end
        if not P.running then
            local ok,why=P.start()
            if not ok then V.promo298_error=tostring(why)end
        end
    else
        local any=false
        for _,v in ipairs(P.settings().templates)do
            if v.auto~=false then any=true;break end
        end
        if not any and P.running then P.stop()end
    end
end
local function new_editor(index)
    local t=index and P.settings().templates[index] or nil
    local edit={index=index,name=buffer(t and t.name or'Новый шаблон',96),
        rows={},linebuf={},waiting=imgui.new.float(tonumber(t and t.waiting)or 1.5),
        min=imgui.new.int(tonumber(t and t.interval_min)or 300),
        max=imgui.new.int(tonumber(t and t.interval_max)or 0),
        limit=imgui.new.int(tonumber(t and t.auto_limit)or 0),
        random=t and t.random_line==true or false,
        auto=t and t.auto~=false or false}
    if t then
        for _,r in ipairs(t.rows or{})do
            edit.rows[#edit.rows+1]={text=r.text or'',auto=r.auto~=false,interval=r.interval or 300}
        end
    else
        edit.rows[1]={text='/s ',auto=true,interval=300}
    end
    for i,r in ipairs(edit.rows)do edit.linebuf[i]=buffer(r.text,512)end
    V.promo298_edit=edit
end
local function modify_number(label,ptr,id,lo,hi,step)
    V.muted(label..': '..tostring(ptr[0])..(id=='wait' and' с' or''))
    if b('-','minus_'..id,66)then ptr[0]=math.max(lo,ptr[0]-step)end
    V.inline(4,66)
    if b('+','plus_'..id,66)then ptr[0]=math.min(hi,ptr[0]+step)end
    ptr[0]=math.max(lo,math.min(hi,ptr[0]))
end
local function editor(e)
    V.heading('Автопиар / Редактор',function()
        if b('Назад','back',100)then V.promo298_edit=nil end
    end,110)
    if e.error then V.red(e.error)end
    if b('Сохранить шаблон','save_editor',224,true)then
        local name=DSP.to_cp(ffi.string(e.name)):match('^%s*(.-)%s*$')
        for i,r in ipairs(e.rows)do r.text=DSP.to_cp(ffi.string(e.linebuf[i]))end
        local full=P.save_template_complete
        if type(full)~='function'then
            e.error='Модуль сохранения автопиара не загружен'
        else
            local ok,result=full(e.index,name,e.rows,e.auto,{
                interval_min=e.min[0],interval_max=e.max[0],
                waiting=e.waiting[0],auto_limit=e.limit[0],random_line=e.random})
            if ok then
                V.promo298_edit=nil;V.promo298_error=nil;V.promo298_notice='Шаблон сохранён в настройках'
                if e.auto and not P.running then
                    local yes,why=P.set_option('continuous',true)
                    if yes then
                        local begun,err=P.start()
                        if not begun then V.promo298_error=tostring(err)end
                    else V.promo298_error=tostring(why)end
                end
            else e.error=tostring(result)end
        end
    end
    if e.index and b('Удалить шаблон','editor_delete',210)then
        V.promo298_delete=e.index
        V.open_popup('Удалить шаблон','pm2910_delete')
    end
    V.list('pm298_editor',function()
        V.text('Название')
        imgui.SetNextItemWidth(-1)
        imgui.InputText('##pm298_title',e.name,96)
        V.muted('Каждая строка — отдельная команда. Не более 24 строк.')
        local remove
        for i,r in ipairs(e.rows)do
            V.text('Строка '..i)
            imgui.SetNextItemWidth(-1)
            imgui.InputText('##pm298_line_'..i,e.linebuf[i],512)
            if b(r.auto and'Строка ВКЛ' or'Строка ВЫКЛ','line_toggle_'..i,145,r.auto)then
                r.auto=not r.auto
            end
            V.inline(5,92)
            if b('Удалить','line_remove_'..i,92)then remove=i end
            imgui.Separator()
        end
        if remove and #e.rows>1 then
            table.remove(e.rows,remove);table.remove(e.linebuf,remove)
        end
        if b('+ Строка','line_add',165,true)then
            if #e.rows<24 then
                e.rows[#e.rows+1]={text='/s ',auto=true,interval=300}
                e.linebuf[#e.linebuf+1]=buffer('/s ',512)
            else e.error='Достигнут лимит строк'end
        end
        V.inline(5,162)
        if b('<lavka>','insert_lavka',155)then
            local i=#e.rows
            if i>0 then
                local prev=DSP.to_cp(ffi.string(e.linebuf[i]))
                if #prev<460 then
                    e.rows[i].text=prev..' <lavka>'
                    e.linebuf[i]=buffer(e.rows[i].text,512)
                end
            end
        end
        V.muted('<lavka> — номер твоей лавки, если он обнаружен.')
        V.text('Интервалы')
        modify_number('Пауза между строками (0.5-10 c)',e.waiting,'wait',.5,10,.5)
        modify_number('Минимальный интервал (сек)',e.min,'min',30,3600,30)
        modify_number('Максимум (0 = без случайности)',e.max,'max',0,3600,30)
        modify_number('Лимит циклов (0 = без лимита)',e.limit,'limit',0,1000,1)
        if b(e.random and'Случайная строка: ДА' or'Случайная строка: НЕТ',
                'random',235,e.random)then e.random=not e.random end
        if b(e.auto and'Авто: включено' or'Авто: выключено',
                'edited_auto',235,e.auto)then e.auto=not e.auto end
        V.muted('Интервал выбирается отдельно для каждого шаблона.')
    end,{footer=true})
end
local function countdown(t)
    if t.auto==false then return 'Авто выключено'end
    local low=tonumber(t.interval_min)or 0
    if low<=0 then low=tonumber((t.rows or{})[1] and t.rows[1].interval)or 300 end
    local high=tonumber(t.interval_max)or 0
    local period=high>low and(low..'-'..high)or tostring(low)
    local due=tonumber(t._promo_due)
    if not due then
        local last=tonumber(t.last_sent)or 0
        due=last>0 and last+low or os.time()
    end
    return 'Интервал '..period..'с | осталось '..math.max(0,due-os.time())..'с'
end
function V.promo_screen()
    if V.promo298_edit then return editor(V.promo298_edit)end
    local s=P.settings()
    V.heading('Автопиар',function()
        if b('+ Шаблон','new',155,true)then new_editor(nil)end
    end,160)
    V.muted('Как в Market Helper: Пуск / Авто / Редактировать')
    if P.running then
        if b('Остановить всё','stop_all',173,true)then P.stop()end
    else
        if b('Запустить авто','start_all',173,true)then
            if not s.continuous then P.set_option('continuous',true)end
            local ok,why=P.start()
            V.promo298_error=not ok and tostring(why)or nil
        end
    end
    V.inline(5,130)
    if b('Настройки','promo_settings',130)then V.set_screen('settings')end
    V.muted('Состояние: '..(P.running and(P.pause_reason or'работает')or'выключен')..
        ' | отправлено: '..tostring(P.session_count or 0))
    if V.promo298_notice then V.green(V.promo298_notice)end
    if V.promo298_error or P.last_error then V.red(tostring(V.promo298_error or P.last_error))end
    if #s.templates==0 then
        V.muted('Нет шаблонов. Нажми + Шаблон.')
        return
    end
    V.list_rows('pm298_templates',s.templates,128,function(t,i)
        V.row('pm298_t_'..i,128,function(w,x,y)
            V.at(x,y)
            V.text(V.fit(t.name or'Шаблон',math.max(105,w-18)))
            V.at(x,y+28)
            V.muted(V.fit(#(t.rows or{})..' строк | '..countdown(t),math.max(100,w-18)))
            local bw=math.max(78,math.floor((w-24)/3))
            V.at(x,y+64)
            if b('Пуск','send_'..i,bw)then
                local ok,why=P.send_template_once(i)
                V.promo298_error=not ok and tostring(why)or nil
            end
            V.inline(5,bw)
            if b(t.auto~=false and'Авто: ВКЛ' or'Авто: ВЫКЛ','auto_'..i,bw,t.auto~=false)then
                toggle_auto(i)
            end
            V.inline(5,bw)
            if b('Изменить','edit_'..i,bw)then new_editor(i)end
        end)
    end,{footer=true})
end
local old_popups=V.popups
function V.popups()
    if old_popups then old_popups()end
    V.popup('Удалить шаблон','pm2910_delete',function()
        V.text('Удалить этот шаблон и все его строки?')
        if b('Удалить','confirm_delete',160)then
            local ok=P.remove(V.promo298_delete)
            if ok then V.promo298_edit=nil;imgui.CloseCurrentPopup()
            else V.promo298_error='Ошибка сохранения удаления'end
        end
        V.inline(5,120)
        V.cancel('pm2910_delete')
    end,{w=415,h=225})
end
local expand=P.expand
function P.expand(text)
    if type(text)=='string' and text:find('<lavka>',1,true)then
        local number,why=P.own_shop_number()
        if not number then return nil,tostring(why or'Номер лавки неизвестен')end
        text=text:gsub('<lavka>',tostring(number))
    end
    return expand(text)
end
-- The earlier 2.9.7 OTA put control shortcuts in home/trade. Hide those,
-- without replacing the working home/trade renderers.
if not V._pm298_button_wrap then
    V._pm298_button_wrap=true
    local original=V.button
    V.button=function(label,id,...)
        if type(id)=='string' and id:find('^v297_control_') then return false end
        return original(label,id,...)
    end
end
if not V._pm298_nav_wrap then
    V._pm298_nav_wrap=true
    local original=V.list_rows
    V.list_rows=function(key,rows,...)
        if key=='navigation' and type(rows)=='table' then
            local filtered={}
            for _,item in ipairs(rows)do
                if type(item)~='table' or item[1]~='control' then
                    filtered[#filtered+1]=item
                end
            end
            return original(key,filtered,...)
        end
        return original(key,rows,...)
    end
end
return true

        end
        v2910_72_promo_market_style_v298()
      end
    end)
    if not ok then
      if DSP.flog then DSP.flog('Palatka 2.9.10 OTA failed: '..tostring(err)) end
      return false
    end
    DSP._v2910_installed=true
    DSP.version='2.9.10'
    if DSP.flog then DSP.flog('Palatka 2.9.10 promo persistence and sale accounting installed') end
    return true
  end
  return install_v2910()
end
