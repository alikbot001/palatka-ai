-- Palatka AI 2.8.3: compatible trunk sizes, suggestion dialog and settings protection.
PALATKA_UPDATE_VERSION = '2.8.8'
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
        V.arb_best_error='Íåò âûãîäíîãî ìàðøðóòà ïðè òåêóùèõ ôèëüòðàõ'
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
        local status=o.qty_source=='game' and 'ïðîâåðåíî: èãðà' or
            o.qty_source=='manual' and 'ïðîâåðåíî âðó÷íóþ' or 'API, íå ïîäòâåðæäåíî'
        V.at(x,y+26);V.muted(V.fit(count..' øò. · '..status..
            (live_qty and (' · Èãðà: '..DSP.market.format_units(live_qty)) or ''),right-8))
        V.at(x,y+52);V.text(V.fit(DSP.money(o.price)..'/øò. · '..DSP.market.offer_freshness(o.ts),right-8))
        if missing then
            V.at(x,y+76);V.red('Ëàâêà íåäîñòóïíà: èñêëþ÷åíà èç ïëàíà')
        elseif o.qty==1 and not o.verified_at then
            V.at(x,y+76);V.muted(V.fit('Âíèìàíèå: 1 ìîæåò áûòü êîëè÷åñòâîì ñëîòîâ',right-8))
        end
        V.at(x+right,y+1)
        if not missing and b(checked and 'Ñíÿòü âûáîð' or 'Âûáðàòü','select_'..i,160,checked)then
            selected[key]=not checked or nil;V.arb_revision=V.arb_revision+1
        end
        V.at(x+right,y+49)
        if b('Óòî÷íèòü','verify_'..V.arb_tab..i,80,false)then
            V.arb_verify={offer=o,side=V.arb_tab,source=live_qty and 'game' or 'manual'}
            V.arb_verify_value={qty=live_qty or tonumber(o.qty) or 0}
        end
        V.inline(4)
        if b(missing and 'Âåðíóòü' or 'Íåò ëàâêè','gone_'..V.arb_tab..i,82,missing)then
            if missing then DSP.market.restore_shop(o.shop) else DSP.market.mark_shop_missing(o.shop,30)end
            V.arb_revision=V.arb_revision+1;V.arb_route=false;V.cache.arb_plan=nil;M.defer_save()
        end
    end)
end
local function route_rows(p)
    return function(r,i)
        V.row('route_'..i,100,function(w,x,y)
            V.text(V.fit('ÊÓÏÈÒÜ '..r.tradable_qty..' øò. ó ëàâêè #'..tostring(r.sell_offer.shop)..' · '..DSP.money(r.p_buy)..'/øò.',w))
            V.at(x,y+26);V.text(V.fit('ÏÐÎÄÀÒÜ ñêóïùèêó #'..tostring(r.buy_offer.shop)..' · '..DSP.money(r.p_sell)..'/øò.',w))
            V.at(x,y+52)
            if b('Ê ïðîäàâöó','route_sell_'..i,140)then DSP.market.mark_shop(r.sell_offer.shop)end
            V.inline();if b('Ê ñêóïùèêó','route_buy_'..i,144)then DSP.market.mark_shop(r.buy_offer.shop)end
            V.inline();V.green('~ +'..DSP.money(r.net_profit))
            if r.same_shop then
                V.at(x,y+78);V.red('Îäíà ëàâêà: âîçìîæíîñòü îáðàòíîé ñäåëêè ïðîâåðüòå â èãðå')
            end
        end)
    end
end
local function finance(p,compact)
    -- Planned, not executed. Display each money component explicitly.
    V.muted('Ðàñ÷¸ò ïî çàÿâêàì API, íå ñîâåðø¸ííàÿ ñäåëêà')
    V.text('Çàêóïêà: -'..DSP.money(p.cost or 0))
    V.text('Ïðîäàæà, äî êîìèññèè: +'..DSP.money(p.gross or 0))
    V.muted('Êîìèññèÿ (ïðèíÿòàÿ): -'..DSP.money(p.fee or 0))
    V.muted('Ïîñòóïëåíèÿ ïîñëå êîìèññèè: '..DSP.money(p.revenue or 0))
    if (p.extra or 0)>0 then V.muted('Äîï. ðàñõîäû: -'..DSP.money(p.extra))end
    local result='ÎÆÈÄÀÅÌÀß ÏÐÈÁÛËÜ: '..DSP.money(p.profit or 0)
    if (p.profit or 0)>=0 then V.green(result)else V.red(result)end
end

local function details(g)
    local p=V.arb_plan(g)
    local compact=imgui.GetContentRegionAvail().y<400
    V.arb_extra=V.arb_extra or{value=0}
    local function extra_control()
        if b(V.arb_extra_enabled and 'x Ðàñõîäû' or '+ Ðàñõîäû','extra',136,V.arb_extra_enabled)then V.arb_extra_enabled=not V.arb_extra_enabled end
        if V.arb_extra_enabled then V.inline();M.compact_number(V.arb_extra,'value','arb_extra',130,0)end
    end
    V.text(V.fit(g.name,imgui.GetContentRegionAvail().x-(compact and 290 or 0)))
    if compact then V.inline();extra_control()end
    V.muted('Ïðîäàþò '..(g.row.sell.qty or g.supply)..' · Ñêóïàþò '..(g.row.buy.qty or g.demand)..' · Ïëàí '..p.qty..' øò.')
    local changed=V.arb_snapshot~=tostring(DSP.market.state.sid)..'/'..tostring(DSP.market.state.version)
    if not compact then V.muted(V.fit('Ñíèìîê '..os.date('%H:%M:%S',V.arb_snapshot_time or os.time())..
        (changed and ' · åñòü íîâûå äàííûå, îòêðîéòå çàíîâî'or ' · API, íàëè÷èå ïðîâåðüòå â èãðå'),imgui.GetContentRegionAvail().x))end
    finance(p,compact)
    local f=DSP.settings.arb_filters or {}
    if not compact then V.muted('Ïëàí óñëîâíûé: äîñòóïíîñòü íå çàáðîíèðîâàíà. Çàïàñ ñïðîñà: '
        ..tostring(f.safety_pct or 0)..'%; îáíîâèòå è ïðîâåðüòå ñêóïêó ïåðåä çàêóïêîé.')end
    if V.arb_verify and V.arb_verify_value then
        local vr=V.arb_verify
        V.muted(V.fit('Ôàêòè÷åñêè ïðîâåðåíî â èãðå: #'..tostring(vr.offer.shop)..' · '..tostring(vr.side=='buy' and 'ñêóïàåò' or 'ïðîäà¸ò'),imgui.GetContentRegionAvail().x))
        M.compact_number(V.arb_verify_value,'qty','arb_verify_qty',130,0)
        V.inline();if b('Ïðèìåíèòü','verify_save',112)then
            local game_now=DSP.market.live_offer_quantity(g.row,vr.side,vr.offer)
            local source=vr.source=='game' and game_now==V.arb_verify_value.qty and 'game' or 'manual'
            local ok,err=DSP.market.confirm_offer_quantity(g.row,vr.side,vr.offer,V.arb_verify_value.qty,source)
            if ok then
                V.arb_verify=nil;V.arb_verify_value=nil
                V.arb_revision=V.arb_revision+1;V.arb_route=false
                V.arb_snapshot=tostring(DSP.market.state.sid)..'/'..tostring(DSP.market.state.version)
            else V.arb_best_error=tostring(err)end
        end
        V.inline();if b('Îòìåíà','verify_cancel',98)then V.arb_verify=nil;V.arb_verify_value=nil end
        if V.arb_best_error then V.red(V.fit(V.arb_best_error,imgui.GetContentRegionAvail().x))end
        return
    end
    if V.arb_route then
        if b('< Ïðåäëîæåíèÿ','back_offers',170)then V.arb_route=false end
        V.inline()
        if DSP.arb_agent and b('Â ÌÈÍÈ-ÀÃÅÍÒ','route_to_agent',176,true)then
            local ok,why=DSP.arb_agent.add_plan(p)
            if ok then
                DSP.arb_agent.show(true)
                imgui.CloseCurrentPopup()
            else DSP.notify('Àãåíò: '..tostring(why))end
        end
        V.list_rows('arb_routes_'..g.key,p.routes,100,route_rows(p),{footer=function()
            if p.profit>=0 then V.green(DSP.money(p.profit)..' ÷èñòîé ïðèáûëè')
            else V.red(DSP.money(p.profit)..' èòîãîâîãî óáûòêà')end
        end})
        return
    end
    local tw=imgui.GetContentRegionAvail().x
    if b('Ïðîäàþò · êóïèòü '..#g.sellers,'sell',tw*.23,V.arb_tab=='sell')then V.arb_tab='sell'end
    V.inline();if b('Ñêóïàþò · ïðîäàòü '..#g.buyers,'buy',tw*.23,V.arb_tab=='buy')then V.arb_tab='buy'end
    V.inline();if b('Ëó÷øèé ïëàí >','best',tw*.27)then best_plan(g)end
    V.inline();if b('Ñáðîñ','none',-1)then V.arb_sellers={};V.arb_buyers={};V.arb_revision=V.arb_revision+1 end
    if not compact then extra_control()end
    if V.arb_best_error then V.red(V.arb_best_error)end
    local offers=V.arb_tab=='sell'and g.sellers or g.buyers
    V.list_rows('arb_'..g.key..'_'..V.arb_tab,offers,100,offer_row,{footer=function()
        if b('Ìàðøðóò >','route',142,true)then V.arb_route=true end
        V.inline();if b('Çàêðûòü','close_details',116)then imgui.CloseCurrentPopup()end
    end})
end
function V.arbitrage()
    local st=DSP.market.state
    V.text('Àðáèòðàæ');V.inline();V.muted('Ñíèìîê: '..DSP.market.freshness())
    if DSP.arb_agent then
        V.inline()
        if b(DSP.arb_agent.active()and'ÌÈÍÈ-ÀÃÅÍÒ >'or'ÍÀ×ÀÒÜ ÑÅÑÑÈÞ','session_start',190,true)then
            local ok,why
            if DSP.arb_agent.active()then DSP.arb_agent.show(true);ok=true
            else ok,why=DSP.arb_agent.start_market()end
            if not ok then DSP.notify('Àãåíò àðáèòðàæà: '..tostring(why))end
        end
        local st_agent=DSP.arb_agent.stats()
        if st_agent.routes>0 then V.muted('Ñåññèÿ: '..st_agent.done..'/'..st_agent.routes..' ìàðøðóòîâ')end
    end
    V.inline();if b(st.status=='loading' and 'Çàãðóçêà...' or 'Îáíîâèòü','refresh',120)then DSP.market.pull(st.sid)end
    V.arb_source=V.arb_source or 'api'
    if b('API','source_api',116,V.arb_source=='api')then
        V.arb_source='api';V.reset_list('arb_main')
    end
    V.inline()
    if b('ÌÎÈ ÑÊÀÍÛ','source_local',175,V.arb_source=='local')then
        V.arb_source='local';V.reset_list('local_arb_items')
    end
    if V.arb_source=='local' then
        if V.local_arbitrage_view then V.local_arbitrage_view() end
        return
    end
    if st.error then
        local delay=(tonumber(st.next_auto_retry) or 0)-os.time()
        V.red(V.fit('API: '..tostring(st.error)..(delay>0 and (' · àâòî-ïîâòîð ÷åðåç '..delay..'ñ')or ''),
            imgui.GetContentRegionAvail().x))
    end
    local af=DSP.settings.arb_filters or {}
    V.muted(V.fit('Ôèëüòðû: '..(tonumber(af.max_age)==0 and 'áåç îãðàíè÷åíèÿ âðåìåíè' or
        (tostring(math.floor((tonumber(af.max_age)or 600)/60))..' ìèí'))..
        ' · ROI îò '..tostring(af.min_roi or 0)..'% · ðåçåðâ '..tostring(af.safety_pct or 0)..
        '% · êîìèññèÿ '..tostring((tonumber(af.tax_bp) or DSP.settings.tax_bp or 200)/100)..'%',
        imgui.GetContentRegionAvail().x))
    local query,edited=V.search('arb','Ïîèñê ïðåäìåòà',-1)
    if edited then V.reset_list('arb_main')end
    if b(V.arb_sort=='az' and 'Àß' or 'Ïðèáûëü: áîëüøå','sort',143,V.arb_sort=='az')then
        V.arb_sort=V.arb_sort=='az' and 'profit' or 'az'
        V.reset_list('arb_main')
    end
    V.inline()
    if b('Ôèëüòðû','filters',120,V.arb_filters)then
        V.arb_filters=true;V.open_popup('Ôèëüòðû àðáèòðàæà','arb_filters')
    end
    -- Direct game observation does not require the external API to refresh.
    local live=DSP.market.live_shop_spreads and DSP.market.live_shop_spreads() or {}
    if #live>0 then
        V.green('ÍÀÉÄÅÍÎ Â ÎÒÊÐÛÒÎÉ ËÀÂÊÅ: '..tostring(#live))
        V.list_rows('arb_live_shop',live,86,function(deal,i)
            V.row('arb_live_row_'..i,86,function(w,x,y)
                V.at(x,y+2);V.text(V.fit(deal.name..' · ëàâêà #'..tostring(deal.shop),w))
                V.at(x,y+27);V.muted(V.fit('Êóïèòü '..DSP.money(deal.buy_price)..' / ñäàòü '..DSP.money(deal.sell_price),w))
                V.at(x,y+52);V.green(V.fit('~ +'..DSP.money(deal.profit_unit)..'/øò. ïîñëå êîìèññèè · '..
                    (deal.verified_quantity and ('äî '..tostring(deal.quantity)..' øò.') or 'êîëè÷åñòâî íåèçâåñòíî'),w))
            end)
        end,{height=math.min(180,math.max(90,imgui.GetContentRegionAvail().y*.30)),footer=false})
    end
    local groups,status
    if DSP.market.arbitrage_grouped_ui then groups,status=DSP.market.arbitrage_grouped_ui()else groups=DSP.market.arbitrage_grouped()end
    if status=='loading'then V.muted('Ðàñ÷¸ò ðûíêà...')elseif status=='error'then V.red('Îøèáêà ðàñ÷¸òà. Ñì. æóðíàë')end
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
    if st.status=='cache' then V.red(V.fit('Ñåòü íåäîñòóïíà: ðàñ÷¸ò ïî ñîõðàí¸ííîìó ñíèìêó, íàëè÷èå íå ïîäòâåðæäåíî',imgui.GetContentRegionAvail().x))end
    if status~='loading' and #groups==0 and DSP.market.arbitrage_visibility then
        local d=DSP.market.arbitrage_visibility()
        if d.pairs>0 then
            V.muted(V.fit('Â API åñòü '..d.pairs..' öåíîâûõ ðàçðûâîâ (â îäíîé ëàâêå: '..d.same_shop..
                '), íî ôèëüòð ñâåæåñòè/îáú¸ìà/êîìèññèè èñêëþ÷èë ìàðøðóòû.',imgui.GetContentRegionAvail().x))
        end
    end
    if #filtered==0 and status~='loading' then
        local age=tonumber((DSP.settings.arb_filters or{}).max_age)or 300
        local reason=#groups>0 and 'Ïî çàïðîñó íè÷åãî íå íàéäåíî' or
            (#(st.rows or{})==0 and 'Íåò ðûíêà: íàæìèòå «Îáíîâèòü»' or
            ('Íåò âûãîäíûõ ñâÿçîê ïî ôèëüòðàì'..(age>0 and (' · ñòàðøå '..math.floor(age/60)..'ì èñêëþ÷åíû')or '')))
        V.muted(V.fit(reason,imgui.GetContentRegionAvail().x))
    end
    V.list_rows('arb_main',filtered,92,function(g,i)
        V.row('arb_group_'..i,92,function(w,x,y)
            M.thumbnail({name=g.name,id=g.row and g.row.id},34)
            V.at(x+44,y+2);V.text(V.fit(g.name,w-220))
            V.at(x+44,y+29);V.muted(V.fit('Êóïèòü: '..DSP.market.format_units(g.supply)..
                ' · Ñäàòü: '..DSP.market.format_units(g.demand)..' øò. (API)',w-220))
            V.at(x+44,y+54);V.muted(V.fit('Ïëàí '..DSP.market.format_units(g.planned)..
                ' øò. · Îöåíêà ïðèáûëè '..DSP.money(g.profit),w-220))
            V.at(x+w-164,y+15)
            if b('Ïðåäëîæåíèÿ >','group_'..i,160,false)then
                V.arb_item=g.key;V.arb_snapshot=tostring(st.sid)..'/'..tostring(st.version)
                V.arb_server=st.sid;V.arb_detail_group=g;V.arb_snapshot_time=os.time()
                V.arb_route=false;V.arb_tab='sell';V.arb_best_error=nil;V.arb_verify=nil;choose_all(g);V.open_popup('Àðáèòðàæ','arb_details')
            end
        end)
    end,{footer=function()V.muted('Îöåíêà ïî API, íå ãàðàíòèðîâàííàÿ ïðèáûëü. Êîëè÷åñòâî ó ñêóïùèêà ìîæåò óìåíüøèòüñÿ.')end})
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    if V.arb_filters then V.popup('Ôèëüòðû àðáèòðàæà','arb_filters',function()
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
            number('Ñâåæåñòü äàííûõ: ìàêñèìóì ñåêóíä (0 = áåç îãðàíè÷åíèÿ, 3600 = ÷àñ)', 'max_age',0,2592000)
            if b('10 ìèí','age10',110) then f.max_age=600;M.refresh_buffer(f,'max_age');changed=true end
            V.inline();if b('1 ÷àñ','age60',110)then f.max_age=3600;M.refresh_buffer(f,'max_age');changed=true end
            V.inline();if b('Ëþáîé âîçðàñò','age_any',170)then f.max_age=0;M.refresh_buffer(f,'max_age');changed=true end
            number('Êîìèññèÿ â áàçèñíûõ ïóíêòàõ: 100 = 1%, 250 = 2.5%', 'tax_bp',0,10000)
            number('Ðåçåðâ ñïðîñà (%) îò 0 äî 90: îñòàâëÿòü íåïðîâåðåííûé îáú¸ì', 'safety_pct',0,90)
            number('Ìèíèìàëüíàÿ ðåíòàáåëüíîñòü ROI (%)', 'min_roi',0,100000)
            number('Ìèíèìàëüíàÿ ÷èñòàÿ ïðèáûëü íà ìàðøðóò ($)', 'min_profit',0)
            number('Ìèíèìàëüíàÿ ïðèáûëü ñ îäíîé øòóêè ($)', 'min_unit_profit',0)
            number('Ìàêñèìàëüíàÿ öåíà çàêóïêè çà øòóêó ($; 0 = áåç ëèìèòà)', 'max_buy_price',0)
            number('Ìèíèìàëüíûé çàïàñ È ñïðîñ API (øò.; 0 = áåç ëèìèòà)', 'min_stock',0)
            number('Áþäæåò íà âñå ìàðøðóòû ($; 0 = áåç ëèìèòà)', 'budget',0)
            number('Ìàêñèìóì øòóê íà ìàðøðóò (0 = áåç ëèìèòà)', 'max_qty',0)
            V.muted('Ëàâêè: ëþáîå ñî÷åòàíèå / òîëüêî îäíà è òà æå / òîëüêî ðàçíûå')
            for i,opt in ipairs({{0,'Ëþáûå'},{1,'Îäíà'},{2,'Ðàçíûå'}})do
                if i>1 then V.inline()end
                if b(opt[2],'shop_mode_'..opt[1],110,f.shop_mode==opt[1])then f.shop_mode=opt[1];changed=true end
            end
            V.muted('Ïîðÿäîê ðàñ÷¸òà (ïðè áþäæåòå ïðèîðèòåò ROI)')
            for i,opt in ipairs({{1,'Ïðèáûëü'},{2,'Çà øòóêó'},{3,'ROI'}})do
                if i>1 then V.inline()end
                if b(opt[2],'sort_mode_'..opt[1],110,f.sort==opt[1])then f.sort=opt[1];changed=true end
            end
            if b(f.allow_partial==false and '[ ] ×àñòè÷íûå ìàðøðóòû' or '[x] ×àñòè÷íûå ìàðøðóòû',
                'allow_partial',290)then f.allow_partial=not(f.allow_partial~=false);changed=true end
            if b(f.include_unknown==true and '[x] Áåç îòìåòêè âðåìåíè' or '[ ] Áåç îòìåòêè âðåìåíè',
                'include_unknown',290)then f.include_unknown=not(f.include_unknown==true);changed=true end
            if b('Ñáðîñèòü ôèëüòðû','reset_filters',210)then
                local defaults={budget=0,min_profit=0,min_roi=0,sort=1,max_age=300,max_qty=0,
                    safety_pct=10,allow_partial=true,include_unknown=false,
                    tax_bp=DSP.settings.tax_bp or 200,min_unit_profit=0,max_buy_price=0,
                    min_stock=0,shop_mode=0}
                for k,v in pairs(defaults)do f[k]=v;M.refresh_buffer(f,k)end
                changed=true
            end
            V.muted('Âîçðàñò 0 îçíà÷àåò ïîêàç äàæå ñòàðûõ îôôåðîâ; ýòî íå ãàðàíòèÿ íàëè÷èÿ.')
        end,{footer=true})
        if changed then
            DSP.market.invalidate_arbitrage();V.arb_revision=V.arb_revision+1
            V.reset_list('arb_main');M.defer_save()
        end
        if b('Ïðèìåíèòü è çàêðûòü','filters_done',220,true)then
            V.arb_filters=false;imgui.CloseCurrentPopup()
        end
    end,{w=690,h=570})end
    V.popup('Àðáèòðàæ','arb_details',function()
        local st=DSP.market.state
        if V.arb_server~=st.sid then
            V.text('Âûáðàí äðóãîé ñåðâåð');V.muted('Îòêðîéòå ïðåäìåò ïîâòîðíî äëÿ íîâîãî ðàñ÷¸òà')
            if b('Çàêðûòü','stale_close',150)then imgui.CloseCurrentPopup()end
            return
        end
        -- Never keep showing the old route after a market refresh: source
        -- offer tables are replaced, not updated in place.
        if V.arb_snapshot~=tostring(st.sid)..'/'..tostring(st.version)
            or st.status=='loading' then
            V.red('Äàííûå èçìåíèëèñü èëè îáíîâëÿþòñÿ. Ñòàðûé ìàðøðóò çàáëîêèðîâàí.')
            if b('Ïåðåñ÷èòàòü','refresh_selected',164)then
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
                    else V.arb_best_error='Ïîñëå îáíîâëåíèÿ ïîäõîäÿùèé ìàðøðóò îòñóòñòâóåò'end
                end
            end
            V.inline();if b('Çàêðûòü','stale_close_version',140)then imgui.CloseCurrentPopup()end
            -- Keep the inspected snapshot browsable, but expose no old route,
            -- quantity confirmation or marker actions after a refresh.
            local snapshot=V.arb_detail_group
            if snapshot then
                if b('Ïðîäàþò · ñíèìîê','sell',190,V.arb_tab=='sell')then V.arb_tab='sell'end
                V.inline();if b('Ñêóïàþò · ñíèìîê','buy',190,V.arb_tab=='buy')then V.arb_tab='buy'end
                local offers=V.arb_tab=='sell'and snapshot.sellers or snapshot.buyers
                V.list_rows('arb_stale_'..snapshot.key..'_'..V.arb_tab,offers,76,function(o,i)
                    V.row('stale_offer_'..i,76,function(w,x,y)
                        V.text(V.fit('#'..tostring(o.shop)..' · '..tostring(o.owner or '?'),w))
                        V.at(x,y+26);V.muted(V.fit(DSP.money(o.price)..'/øò. · '..DSP.market.format_units(o.qty)..' øò. · ñòàðûé API-ñíèìîê',w))
                    end)
                end)
            end
            return
        end
        local g=V.arb_detail_group
        if g then details(g)else
            V.muted('Ñâÿçêà áîëüøå íå ïðîõîäèò ôèëüòðû')
            if b('Çàêðûòü','empty_close',140)then imgui.CloseCurrentPopup()end
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
    return tostring(math.floor(n/60))..' ìèí íàçàä'
end
local function txt(s,w) return V.fit(s,math.max(1,w)) end
function V.local_arbitrage_view()
    local now=os.time()
    local stats=A.stats(now)
    local auto=DSP.settings.auto_shop_scan~=false
    if b(auto and 'ÀÂÒÎÑÊÀÍ: ÂÊË' or 'ÀÂÒÎÑÊÀÍ: ÂÛÊË','auto_toggle',180) then
        DSP.settings.auto_shop_scan=not auto
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
        else DSP.save_settings() end
        auto=not auto
    end
    V.inline()
    V.muted('Ñêàíèðóåò ïðè îòêðûòèè ëàâêè, áåç êíîïêè è áåç API')
    local saver=DSP.settings.fps_saver==true
    if b(saver and 'ÝÊÎÍÎÌÈß FPS: ÂÊË' or 'ÝÊÎÍÎÌÈß FPS: ÂÛÊË','fps_toggle',200) then
        DSP.settings.fps_saver=not saver
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
        else DSP.save_settings() end
    end
    V.inline()
    V.muted('Îòêëþ÷àåò äîïîëíèòåëüíûå îêíà è èêîíêè, àâòîñêàí îñòà¸òñÿ')
    local last=DSP.live and DSP.live.auto_scan
    if last and (last.at or 0)>0 then
        V.muted('Ïîñëåäíèé ñêàí: ëàâêà #'..tostring(last.shop)..' | '..tostring(last.items)..' ïîçèöèé | '..elapsed(last.at,now))
    end
    V.green('ÈÇ ÑÊÀÍÎÂ Â ÈÃÐÅ · ÁÅÇ API')
    V.muted('Ëàâîê: '..stats.shops..' · ïðåäëîæåíèé: '..stats.offers..' · ïàìÿòü: 60 ìèí')
    V.muted('Ñîõðàíÿþòñÿ öåíû òîëüêî ÎÒÊÐÛÒÛÕ ëàâîê ñ èçâåñòíûì íîìåðîì. Ïðîâåðÿé íàëè÷èå ïåðåä ñäåëêîé.')
    local query,changed=V.search('local_arb','Íàçâàíèå ïðåäìåòà èëè íîìåð ëàâêè',-1)
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
    V.muted('Íàéäåíî ñâÿçîê: '..tostring(#routes)..' · ïîðÿäîê: ïðèáûëü çà 1 øò.')
    if #routes==0 then V.muted('Íåò âûãîäíûõ ïàð èç òâîèõ ñêàíîâ çà ïîñëåäíèé ÷àñ.') end
    V.list_rows('local_arb_items',routes,142,function(r,i)
        V.row('local_route_'..i,142,function(w,x,y)
            local text_width=math.max(130,w-134)
            V.at(x,y+1);V.text(txt((r.name or 'ID:'..r.id)..' +'..tostring(r.ench or 0),text_width))
            V.at(x,y+28);V.muted(txt('ÊÓÏÈÒÜ: #'..r.seller_shop..' · '..DSP.money(r.buy_price)..'/øò.',text_width))
            V.at(x,y+51);V.muted(txt('ÑÄÀÒÜ: #'..r.buyer_shop..' · '..DSP.money(r.sell_price)..'/øò.',text_width))
            V.at(x,y+75);V.green(txt('~ +'..DSP.money(r.profit_unit)..'/øò. ïîñëå êîìèññèè',text_width))
            V.at(x,y+100)
            V.muted(txt('Ñêàí: '..elapsed(r.seller_at,now)..' / '..elapsed(r.buyer_at,now),w))
            V.at(x+math.max(0,w-124),y+33)
            if b('Ìàðøðóò >','open_'..i,118) then
                V.local_route={server=stats.server,route=r}
                V.open_popup('Ìàðøðóò èç ñêàíà','local_route')
            end
        end)
    end,{footer=function()
        V.muted('Ïîòåíöèàëüíûå öåíû, ÍÅ ðåàëüíûå ïðîäàæè. Íåèçâåñòíûå îáú¸ìû íå ñóììèðóþòñÿ.')
    end})
end
local previous=V.popups
function V.popups()
    if previous then previous() end
    V.popup('Ìàðøðóò èç ñêàíà','local_route',function()
        local selected=V.local_route
        if not selected or selected.server~=A.stats().server then
            V.red('Ñìåíèëñÿ ñåðâåð. Âûáåðè ìàðøðóò çàíîâî.')
            if b('Çàêðûòü','changed_close',150) then imgui.CloseCurrentPopup()end
            return
        end
        local r=selected.route
        local age=os.time()
        if age-r.seller_at>=A.ttl or age-r.buyer_at>=A.ttl then
            V.red('Äàííûå óñòàðåëè. Îòêðîé ëàâêè çàíîâî.')
            if b('Çàêðûòü','stale_close',150)then imgui.CloseCurrentPopup()end
            return
        end
        V.text(txt(r.name or '?',imgui.GetContentRegionAvail().x))
        V.green('ÈÑÒÎ×ÍÈÊ: ëîêàëüíûé ñêàí â èãðå, íå API')
        V.text('1. ÊÓÏÈÒÜ â ëàâêå #'..r.seller_shop..' ('..tostring(r.seller_owner or '?')..')')
        V.muted(DSP.money(r.buy_price)..' çà øòóêó · '..elapsed(r.seller_at,age))
        V.text('2. ÑÄÀÒÜ â ëàâêó #'..r.buyer_shop..' ('..tostring(r.buyer_owner or '?')..')')
        V.muted(DSP.money(r.sell_price)..' çà øòóêó · '..elapsed(r.buyer_at,age))
        V.text('Ïîñòóïëåíèÿ ïîñëå êîìèññèè: '..DSP.money(r.net_unit)..' çà øòóêó')
        V.green('Ïîòåíöèàëüíàÿ ïðèáûëü: +'..DSP.money(r.profit_unit)..' çà øòóêó')
        if r.qty and r.profit_total then
            V.muted('Èçâåñòíûé ëèìèò: äî '..r.qty..' øò. · ïîòîëîê ïðèáûëè ~ '..DSP.money(r.profit_total))
        else
            V.muted('Êîëè÷åñòâî íåèçâåñòíî: èòîãîâóþ ïðèáûëü íå ðàññ÷èòûâàåì.')
        end
        V.red('Ñêàí ÍÅ ãàðàíòèðóåò, ÷òî ïðåäëîæåíèå åù¸ ñóùåñòâóåò!')
        if DSP.arb_agent and r.qty and b('Â ÌÈÍÈ-ÀÃÅÍÒ','local_to_agent',186)then
            local ok,why=DSP.arb_agent.add_local_route(r)
            if ok then DSP.arb_agent.show(true);imgui.CloseCurrentPopup()
            else DSP.notify('Àãåíò: '..tostring(why))end
        end
        if b('Ìåòêà ïðîäàâöà','seller_marker',155) then M.mark_shop(r.seller_shop)end
        V.inline();if b('Ìåòêà ñêóïùèêà','buyer_marker',155) then M.mark_shop(r.buyer_shop)end
        if b('Íåò ëàâêè #'..r.seller_shop,'seller_missing',195) then
            M.mark_shop_missing(r.seller_shop,30);if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
            imgui.CloseCurrentPopup()
        end
        V.inline();if b('Íåò ëàâêè #'..r.buyer_shop,'buyer_missing',195) then
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
    if not s then return false,'Íåò àêòèâíîé ñåññèè'end
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
    if server()==0 then return false,'Ñåðâåð åù¸ íå îïðåäåë¸í'end
    local s=active()
    if not s then
        A.data.session={sid=server(),started=os.time(),routes={},focus=1,last_review=0,
            tax_bp=num(DSP.settings.tax_bp,0,10000)or 200}
    end
    local n=append_routes(routes,24)
    if n==0 and #A.data.session.routes==0 then
        A.data.session=nil
        return false,'Íîâûõ ïðèãîäíûõ ìàðøðóòîâ ïîêà íåò'
    end
    A.show(true)
    return true,n
end
function A.add_plan(plan)
    local routes=plan and plan.routes
    if type(routes)~='table'or#routes==0 then return false,'Â ïëàíå íåò ìàðøðóòîâ'end
    return A.start(routes)
end
function A.start_market()
    if M.state.status=='cache'or M.state.status=='error'then
        return false,'Íåò ñâåæåãî ðûíêà; ïðîâåðüòå API èëè ëîêàëüíûé ñêàí'
    end
    local groups,status
    if M.arbitrage_grouped_ui then groups,status=M.arbitrage_grouped_ui()
    else groups=M.arbitrage_grouped();status='ready'end
    if status~='ready'or not groups then return false,'Ðûíîê åù¸ ðàññ÷èòûâàåòñÿ'end
    local routes={}
    for _,g in ipairs(groups)do for _,r in ipairs(g.routes or{})do routes[#routes+1]=r end end
    table.sort(routes,function(a,b)return(tonumber(a.net_profit)or 0)>(tonumber(b.net_profit)or 0)end)
    return A.start(routes)
end
-- A locally scanned route can join the same session if both quantities are known.
-- The local quote identity is separate from remote API identities.
function A.add_local_route(r)
    if type(r)~='table' or not num(r.qty,1,1000000000)then
        return false,'Ñêàí íå ïîäòâåðäèë êîëè÷åñòâî ñ îáåèõ ñòîðîí'
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
    if not e or not s then return false,'Íåò òàêîé ñäåëêè'end
    if e.skipped then return false,'Ñäåëêà ïðîïóùåíà'end
    if side~='buy'and side~='sell'then return false,'Íåèçâåñòíûé òèï'end
    local limit=side=='buy'and(e.qty-e.bought)or(e.bought-e.sold)
    local q=num(amount,1,limit)
    if not q then return false,'Êîëè÷åñòâî ïðåâûøàåò îñòàâøèéñÿ ëèìèò'end
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
    if e.skipped then return 'ÏÐÎÏÓÙÅÍÎ' end
    if e.sold==e.qty then return 'ÇÀÂÅÐØÅÍÎ' end
    if e.bought==0 then return 'ÊÓÏÈÒÜ' end
    if e.bought<e.qty then return 'ÄÎÊÓÏÈÒÜ' end
    return 'ÑÄÀÒÜ'
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
    if btn('ÀÐÁÈÒÐÀÆ / MOVE','drag',math.max(65,g.w-119),32)then end
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
    good('Ñäåëîê: '..st.done..' / '..st.routes..'  |  Â ðàáîòå: '..st.pending)
    text('Êóïëåíî: '..st.bought..'  |  Ñäàíî: '..st.sold)
    good('Ïðèáûëü ~ '..fmt(st.profit_estimate))
    muted('Ðàñ÷¸ò ïî öåíàì ïëàíà, íå ïîäòâåðæä¸ííàÿ êàññà')
    local updated=M.state and M.state.updated or 0
    muted('API: '..(M.freshness and M.freshness()or'íåò äàííûõ')..' | îáçîð êàæäûå 60 ñ')
end
local function queue(s)
    local total=#s.routes
    if total==0 then muted('Ìàðøðóòîâ ïîêà íåò');return end
    A.queue_page=math.max(1,math.min(tonumber(A.queue_page)or 1,math.ceil(total/5)))
    local pages=math.ceil(total/5)
    muted('Âñå ìàðøðóòû, âêëþ÷àÿ çàâåðø¸ííûå: '..total)
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
        muted('Ñòðàíèöà '..A.queue_page..'/'..pages)
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
                    if btn('Çàâåðøèòü ñåññèþ','end_session',-1,28)then A.end_confirm=true end
                else
                    bad('Çàâåðøèòü òåêóùóþ ñåññèþ? Èñòîðèÿ îñòàíåòñÿ.')
                    if btn('Äà, çàâåðøèòü','end_yes',-1,30)then
                        A.stop();A.end_confirm=false
                    end
                    if btn('Îòìåíà','end_cancel',-1,28)then A.end_confirm=false end
                end
                imgui.Separator()
            end
            local e,index=selected(s)
            if e then
                text('ÌÀÐØÐÓÒ '..index..' / '..#s.routes..' | '..flag(e))
                text(V.fit(e.name,math.max(100,imgui.GetContentRegionAvail().x-8)))
                muted('Ïëàí: '..e.qty..' øò. | îæèäàíèå ~ '..fmt(e.proposed_profit))
                muted('Êóïëåíî '..e.bought..' / '..e.qty..' | Ïðîäàíî '..e.sold..' / '..e.qty)
                -- Confirming each step updates the local offer ledger, never cash history.
                if e.skipped then
                    if btn('Âåðíóòü','restore',-1)then A.skip(index,false)end
                else
                    local side=e.bought<e.qty and'buy'or'sell'
                    local remaining=side=='buy'and(e.qty-e.bought)or(e.bought-e.sold)
                    if remaining>0 then
                        local shop=side=='buy'and e.seller_shop or e.buyer_shop
                        local owner=side=='buy'and e.seller_owner or e.buyer_owner
                        local unit=side=='buy'and e.buy_price or e.sell_price
                        text(side=='buy'and'ÊÓÏÈÒÜ' or'ÑÄÀÒÜ')
                        text('Ëàâêà #'..shop..' | '..owner)
                        text('x'..remaining..' | '..fmt(unit)..'/øò.')
                        if btn('Íàéòè ëàâêó #'..shop,'target',-1)then
                            if not M.mark_shop(shop)then notify('Ìåòêà íåäîñòóïíà')end
                        end
                        local input_key=e.id..':'..side
                        if A.qty_key~=input_key then A.qty_key=input_key;A.qty_field=imgui.new.int(remaining)end
                        muted('Ïîäòâåðäèòü êîëè÷åñòâî:')
                        imgui.SetNextItemWidth(math.min(160,imgui.GetContentRegionAvail().x))
                        imgui.InputInt('##arb_agent_qty',A.qty_field,1,10)
                        if btn(side=='buy'and'ÊÓÏËÅÍÎ' or'ÏÐÎÄÀÍÎ','confirm',-1,39)then
                            local ok,why=A.confirm(index,side,A.qty_field[0])
                            if ok then A.qty_key=nil;notify('Ïîäòâåðæäåíî: '..e.name)
                            else notify(tostring(why))end
                        end
                        local hint=A.hint
                        if hint and hint.route_id==e.id and hint.side==side then
                            muted('Ïîõîæèé ÷åê: '..hint.qty..' øò. (íå àâòîçà÷¸ò)')
                            if btn('Ïîäòâåðäèòü ÷åê','accept_receipt',-1)then
                                local ok,why=A.confirm(index,side,hint.qty)
                                if ok then A.qty_key=nil;notify('×åê ïîäòâåðæä¸í')
                                else notify(tostring(why))end
                            end
                        end
                    else good('Ìàðøðóò âûïîëíåí')end
                end
            else
                muted('Ìàðøðóòû ïîÿâÿòñÿ ïîñëå ñêàíèðîâàíèÿ ðûíêà')
            end
        end
        imgui.EndChild()
        if A.save_error then bad('Çàïèñü íå ñîõðàíåíà: '..tostring(A.save_error))end
        if A.ui_message then muted(V.fit(A.ui_message,math.max(80,g.w-32)))end
        if btn('<','previous',47,30)then A.next(-1);A.qty_key=nil end
        imgui.SameLine(0,5)
        if btn('>','next',47,30)then A.next(1);A.qty_key=nil end
        imgui.SameLine(0,5)
        local e,i=selected(s)
        if e and btn('Ïðîïóñòèòü','skip',100,30)then A.skip(i,true);A.next(1);A.qty_key=nil end
        imgui.SameLine(0,5)
        if btn('Ìåíþ','main',65,30)then
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
  -- v2.8.8: universal opt-in command queue in the original Palatka interface.
  local function install_v288()
    if not install_v287() then return false end
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
        return false,'\196\238\241\242\232\227\237\243\242 \235\232\236\232\242 12 \241\242\240\238\234 \231\224 \241\229\241\241\232\254'end
    end
    P.running=true;P.pause_reason=nil;P.last_error=nil
    P.cursor=1
    P.next_at=(now or os.time())+s.start_delay
    P.started=now or os.time();P.was_online=false
    s.enabled=true
    if not persist()then
        P.running=false;s.enabled=false
        return false,'\205\229 \243\228\224\235\238\241\252 \241\238\245\240\224\237\232\242\252 \240\229\230\232\236'end
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
return true

      end
      _v288_promo_model()

      local function _v288_promo_ui()
-- Native Palatka workspace for universal auto-promo. No MCR UI dependencies.
local ffi=require('ffi')
local V,M,P=DSP.ui22,DSP.mobile,DSP.promo
local function b(s,id,w,on)return V.button(s,'unipromo_'..id,w,on)end
local function save()return DSP.save_settings and DSP.save_settings()~=false end
local function input(id,hint,buffer,length)
    imgui.SetNextItemWidth(-1)
    return imgui.InputTextWithHint('##unipromo_'..id,DSP.utf8(hint),buffer,length)
end
local function fill(buf,value,max)
    local raw=DSP.to_u8(tostring(value or''))
    ffi.fill(buf,max);ffi.copy(buf,raw:sub(1,max-1))
end
local function open_editor(i)
    local row=P.settings().templates[i]
    V.unipromo_edit_index=i
    V.unipromo_name=V.unipromo_name or imgui.new.char[80]()
    V.unipromo_line=V.unipromo_line or imgui.new.char[512]()
    fill(V.unipromo_name,row and row.name or '\205\238\226\224\255 \241\242\240\238\234\224',80)
    fill(V.unipromo_line,row and row.text or '/fam ',512)
    V.unipromo_interval={value=row and tonumber(row.interval)or 180}
    V.unipromo_error=nil
    V.open_popup('\196\238\225\224\226\232\242\252 \234\238\236\224\237\228\243','unipromo_edit')
end
local function pretty(s,w)
    return V.fit(tostring(s or ''),math.max(40,w))
end
function V.promo_screen()
    local settings=P.settings()
    V.heading('\192\226\242\238\239\232\224\240 \183 Palatka AI',function()
        if P.running then
            if b('\207\192\211\199\192','stop',118,true)then P.stop()end
        else
            if b('\199\192\207\211\209\202','start',118,true)then
                local ok,why=P.start()
                V.unipromo_error=ok and nil or tostring(why)
            end
        end
    end,135)
    V.muted('\203\254\225\224\255 \232\227\240\238\226\224\255 /\234\238\236\224\237\228\224. \209\242\240\238\234\232 \232\228\243\242 \239\238 \238\247\229\240\229\228\232; \238\242\228\229\235\252\237\224\255 \239\224\243\231\224 \239\238\241\235\229 \234\224\230\228\238\233.')
    V.muted('\205\229 \243\241\234\238\240\255\229\242 \241\229\240\226\229\240\237\251\229 \238\227\240\224\237\232\247\229\237\232\255 \247\224\242\224. \192\226\242\238\226\238\231\238\225\237\238\226\235\229\237\232\229 \242\238\235\252\234\238 \239\240\232 \226\234\235\254\247\229\237\232\232.')
    V.text('\209\242\224\242\243\241: '..(P.running and (P.pause_reason or'\199\224\239\243\249\229\237')or'\206\241\242\224\237\238\226\235\229\237'))
    V.muted('\206\242\239\240\224\226\235\229\237\238: '..tostring(P.session_count)..(settings.continuous and ' | \246\232\234\235\232\247\229\241\234\232\233 \240\229\230\232\236' or ' / 12 \231\224 \231\224\239\243\241\234'))
    if P.running and P.next_at and P.next_at>0 then
        V.muted('\209\235\229\228\243\254\249\224\255 \238\242\239\240\224\226\234\224 \247\229\240\229\231 '..tostring(math.max(0,P.next_at-os.time()))..' \241')
    end
    if P.last_command then V.muted(pretty('\207\238\241\235\229\228\237\255\255: '..P.last_command,imgui.GetContentRegionAvail().x))end
    if V.unipromo_error or P.last_error then V.red(pretty(V.unipromo_error or P.last_error,imgui.GetContentRegionAvail().x))end
    if b(settings.continuous and '\214\232\234\235: \193\197\199 \203\200\204\200\210\192' or '\214\232\234\235: 12 \241\238\238\225\249\229\237\232\233',
        'continuous',234,settings.continuous)then
        local ok,err=P.set_option('continuous',not settings.continuous)
        if not ok then V.unipromo_error=err end
    end
    V.inline(5)
    if b(settings.resume_on_login and '\207\240\232 \226\245\238\228\229: \194\202\203' or '\207\240\232 \226\245\238\228\229: \194\219\202\203',
        'resume',230,settings.resume_on_login)then
        local ok,err=P.set_option('resume_on_login',not settings.resume_on_login)
        if not ok then V.unipromo_error=err end
    end
    V.muted('\207\238\241\235\229 \226\245\238\228\224: \231\224\228\229\240\230\234\224 '..tostring(settings.start_delay)..' \241 \183 \239\240\232 \238\242\234\235\254\247\229\237\232\232 \238\242\239\240\224\226\234\224 \237\224 \239\224\243\231\229.')
    for i,v in ipairs({10,20,30,60})do
        if b(v..' \241','start_delay_'..i,82,settings.start_delay==v)then
            local ok,err=P.set_option('start_delay',v)
            if not ok then V.unipromo_error=err end
        end
        if i<4 then V.inline(5)end
    end
    if b('+ \196\238\225\224\226\232\242\252 \241\242\240\238\234\243','add',200,true)then open_editor(nil)end
    V.inline(5)
    if b('\206\209\210\192\205\206\194\200\210\220','stop2',135,P.running)then P.stop()end
    local rows=settings.templates
    V.muted('\209\242\240\238\234: '..#rows..' / '..P.MAX_TEMPLATES..' \183 \232\237\242\229\240\226\224\235 60\1503600 \241 \239\238\241\235\229 \241\242\240\238\234\232.')
    V.list_rows('unipromo_lines',rows,124,function(it,i)
        V.row('unipromo_row_'..i,124,function(w,x,y)
            V.at(x,y)
            V.text(pretty(tostring(i)..'. '..tostring(it.name or '\209\242\240\238\234\224'),w-165))
            V.at(x,y+25)
            V.muted(pretty(it.text or'',w-165))
            V.at(x,y+49)
            V.muted('\207\224\243\231\224 \239\238\241\235\229: '..tostring(it.interval or 180)..' \241\229\234')
            V.at(x,y+73)
            if b(it.auto and '\194\202\203' or '\194\219\202\203','line_on_'..i,77,it.auto)then
                it.auto=not it.auto
                if not save()then it.auto=not it.auto;V.unipromo_error='\205\229 \243\228\224\235\238\241\252 \241\238\245\240\224\237\232\242\252'end
            end
            V.inline(4)
            if b('\194\226\229\240\245','line_up_'..i,71)then P.move(i,-1)end
            V.inline(4)
            if b('\194\237\232\231','line_down_'..i,71)then P.move(i,1)end
            V.at(x+w-155,y+10)
            if b('\200\231\236\229\237\232\242\252','line_edit_'..i,150)then open_editor(i)end
            V.at(x+w-155,y+65)
            if b('\211\228\224\235\232\242\252','line_del_'..i,150)then
                V.unipromo_delete=i;V.open_popup('\211\228\224\235\232\242\252 \234\238\236\224\237\228\243','unipromo_delete')
            end
        end)
    end,{footer=function()
        V.muted('\207\232\224\240 \226\251\239\238\235\237\255\229\242 \242\238\235\252\234\238 \243\234\224\231\224\237\237\251\229 \242\238\225\238\233 \234\238\236\224\237\228\251, \241 \241\238\225\235\254\228\229\237\232\229\236 \231\224\228\224\237\237\251\245 \239\224\243\231.')
    end})
end
local previous_popups=V.popups
function V.popups()
    if previous_popups then previous_popups()end
    V.popup('\196\238\225\224\226\232\242\252 \234\238\236\224\237\228\243','unipromo_edit',function()
        V.text('\205\224\231\226\224\237\232\229 \241\242\240\238\234\232')
        input('name','\205\224\239\240\232\236\229\240: \209\229\236\229\233\237\251\233 \247\224\242',V.unipromo_name,80)
        V.text('\202\238\236\224\237\228\224 \241 \224\240\227\243\236\229\237\242\224\236\232')
        input('line','\205\224\239\240\232\236\229\240: /fam \207\240\238\228\224\236 \235\224\240\246\251',V.unipromo_line,512)
        V.muted('\204\238\230\237\238 /f, /fam, /vr, /ad, /family \232 \235\254\225\243\254 \228\240\243\227\243\254 /\234\238\236\224\237\228\243 \232\227\240\251.')
        V.muted('\197\241\235\232 \234\238\236\224\237\228\224 \238\242\234\240\251\226\224\229\242 \236\229\237\254, \238\237\238 \236\238\230\229\242 \236\229\248\224\242\252 \232\227\240\229 \239\240\232 \234\224\230\228\238\236 \246\232\234\235\229.')
        if b('\194\241\242\224\226\232\242\252 {shop}','shopmacro',163)then
            local raw=ffi.string(V.unipromo_line)
            local suffix=' {shop}'
            if #raw+#suffix<511 then fill(V.unipromo_line,raw..suffix,512)end
        end
        V.muted('\204\224\234\240\238\241 {shop} \226\241\242\224\226\235\255\229\242 \234\235\232\234\224\225\229\235\252\237\251\233 \237\238\236\229\240 \241\226\238\229\233 \235\224\226\234\232 \239\240\232 \238\242\239\240\224\226\234\229.')
        V.text('\200\237\242\229\240\226\224\235 \239\238\241\235\229 \253\242\238\233 \241\242\240\238\234\232, \241\229\234\243\237\228')
        for _,seconds in ipairs({60,120,180,300,600})do
            if b(tostring(seconds),'interval_'..seconds,69,V.unipromo_interval.value==seconds)then
                V.unipromo_interval.value=seconds
            end
            V.inline(4)
        end
        M.compact_number(V.unipromo_interval,'value','unipromo_interval',180,60)
        if V.unipromo_error then V.red(tostring(V.unipromo_error))end
        if b('\209\238\245\240\224\237\232\242\252 \241\242\240\238\234\243','save',182,true)then
            local name=DSP.to_cp(ffi.string(V.unipromo_name))
            local line=DSP.to_cp(ffi.string(V.unipromo_line))
            local ok,err
            if V.unipromo_edit_index then
                ok,err=P.update(V.unipromo_edit_index,name,line,V.unipromo_interval.value)
            else
                ok,err=P.add(name,line,V.unipromo_interval.value)
            end
            if ok then V.unipromo_error=nil;imgui.CloseCurrentPopup()
            else V.unipromo_error=tostring(err)end
        end
        V.inline(6);V.cancel('unipromo_edit')
    end,{w=680,h=470,resizable=true})
    V.popup('\211\228\224\235\232\242\252 \234\238\236\224\237\228\243','unipromo_delete',function()
        V.text('\211\228\224\235\232\242\252 \253\242\243 \241\242\240\238\234\243 \232\231 \240\224\241\239\232\241\224\237\232\255?')
        if b('\196\224, \243\228\224\235\232\242\252','delete_confirm',174)then
            if P.remove(V.unipromo_delete)then imgui.CloseCurrentPopup()
            else V.unipromo_error='\206\248\232\225\234\224 \241\238\245\240\224\237\229\237\232\255'end
        end
        V.inline(6);V.cancel('unipromo_delete')
    end,{w=470,h=240})
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
    return install_v288()
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
  return install_v288()
end
