-- v2.2.4: independent resale workstation. All values are estimates from market
-- offers, never evidence of completed transactions or reserved stock.
DSP.flip = DSP.flip or {}
local F = DSP.flip
local MAX_SAFE = 9007199254740991
local function num(x, fallback)
    local n=tonumber(x)
    if not n or n~=n or n==math.huge or n==-math.huge then return fallback or 0 end
    return n
end
local function integer(x, fallback)
    return math.max(0,math.floor(num(x,fallback)))
end
function F.settings()
    if type(DSP.settings.flip)~='table' then DSP.settings.flip={} end
    local s=DSP.settings.flip
    s.capital=math.min(MAX_SAFE,integer(s.capital))
    s.reserve_pct=math.min(90,integer(s.reserve_pct,20))
    s.max_position_pct=math.min(100,math.max(5,integer(s.max_position_pct,35)))
    s.min_roi=math.min(10000,integer(s.min_roi,5))
    s.max_risk=math.min(3,integer(s.max_risk,2))
    if s.sort~='roi' and s.sort~='unit' then s.sort='profit' end
    if type(s.watch)~='table' then s.watch={} end
    if type(s.alerts)~='boolean' then s.alerts=false end
    return s
end
local function risk_of(r,now,max_age)
    local a,b=r.sell_offer or {},r.buy_offer or {}
    local risk=0;local reasons={}
    local function flag(msg,level)
        if level>risk then risk=level end
        reasons[#reasons+1]=msg
    end
    for _,o in ipairs({a,b}) do
        if integer(o.qty)==1 and not o.verified_at then flag('объём API=1 может быть одним слотом',3) end
        local ts=integer(o.ts)
        if ts<=0 then flag('нет времени снимка',2)
        elseif ts>now+60 or now-ts>max_age then flag('старые данные',3) end
        if o.qty_source~='game' and o.qty_source~='manual' then flag('остаток не проверен в игре',1) end
    end
    if tostring(a.shop)==tostring(b.shop) then flag('одна лавка с обеих сторон',3) end
    if r.demand_verified==false then flag('скупка не гарантирована',2) end
    return risk,table.concat(reasons,'; ')
end
function F.score_route(route,opts,now)
    opts=opts or{};now=now or os.time()
    local q=integer(route and route.tradable_qty)
    local buy=integer(route and route.p_buy)
    local sell=integer(route and route.p_sell)
    if q==0 or buy==0 or sell<=buy then return nil end
    local tax=math.min(10000,integer(opts.tax_bp,integer(DSP.settings.tax_bp,200)))
    local max_age=integer(opts.max_age,1800)
    local risk,reason=risk_of(route,now,max_age)
    local cap=integer(opts.budget)
    if cap>0 then q=math.min(q,math.floor(cap/buy)) end
    if q<=0 then return nil end
    q=math.min(q,math.floor(MAX_SAFE/math.max(sell,buy)))
    if q<=0 then return nil end
    local cost=q*buy
    local gross=q*sell
    local fee=math.floor(gross*tax/10000)
    local revenue=gross-fee
    local profit=revenue-cost-integer(opts.extra)
    local roi=cost>0 and profit/cost*100 or 0
    if profit<=0 or roi<num(opts.min_roi) then return nil end
    return {route=route,key=route.row and route.row.key or '?',name=route.name or (route.row and route.row.display) or '?',
        qty=q,buy_price=buy,sell_price=sell,cost=cost,gross=gross,fee=fee,
        revenue=revenue,profit=profit,roi=roi,risk=risk,reason=reason,
        seller=route.sell_offer,buyer=route.buy_offer,
        seller_shop=route.sell_offer and route.sell_offer.shop,
        buyer_shop=route.buy_offer and route.buy_offer.shop}
end
local cache_key,cache
local function signature(groups,s,now)
    local st=DSP.market.state or{}
    return table.concat({tostring(groups),st.sid or 0,st.version or 0,
        s.capital,s.reserve_pct,s.max_position_pct,s.min_roi,s.max_risk,s.sort,
        DSP.settings.tax_bp or 200,math.floor(now/30)},'|')
end
-- Input routes are disjoint allocations produced by the existing allocator.
-- Do not sum each candidate's profit blindly; budget is reserved once globally.
function F.rank(groups, now)
    now=now or os.time()
    local s=F.settings()
    local sig=signature(groups,s,now)
    if sig==cache_key and cache then return cache end
    local options={tax_bp=DSP.settings.tax_bp,max_age=(DSP.settings.arb_filters or{}).max_age or 600,min_roi=s.min_roi}
    local candidates={}
    for _,group in ipairs(groups or{}) do
        for _,r in ipairs(group.routes or{}) do
            local c=F.score_route(r,options,now)
            if c and c.risk<=s.max_risk then
                c.group=group
                candidates[#candidates+1]=c
            end
        end
    end
    local mode=s.sort
    table.sort(candidates,function(a,b)
        local ax=mode=='roi' and a.roi or mode=='unit' and a.profit/a.qty or a.profit
        local bx=mode=='roi' and b.roi or mode=='unit' and b.profit/b.qty or b.profit
        if ax~=bx then return ax>bx end
        if a.risk~=b.risk then return a.risk<b.risk end
        return tostring(a.key)<tostring(b.key)
    end)
    local budget=s.capital>0 and math.floor(s.capital*(100-s.reserve_pct)/100) or 0
    local rest=budget
    local per_item={}
    local selected={}
    local total={cost=0,gross=0,fee=0,revenue=0,profit=0,qty=0,count=0,
        capital=s.capital,budget=budget,reserve=s.capital-budget,limited=s.capital>0}
    for _,c in ipairs(candidates) do
        local available=rest
        if s.capital>0 then
            local item_limit=math.floor(budget*s.max_position_pct/100)
            available=math.min(rest,math.max(0,item_limit-(per_item[c.key]or 0)))
        end
        local choice=F.score_route(c.route,{budget=available,tax_bp=DSP.settings.tax_bp,
            max_age=options.max_age,min_roi=s.min_roi},now)
        -- If a capital is set and no more budget remains, never interpret 0
        -- as "unlimited" (the score_route API uses 0 for no limit).
        if s.capital==0 or available>=c.buy_price then
            if choice and total.cost+choice.cost<=MAX_SAFE
                and total.gross+choice.gross<=MAX_SAFE and total.revenue+choice.revenue<=MAX_SAFE then
                choice.group=c.group;selected[#selected+1]=choice
                rest=rest-choice.cost
                per_item[c.key]=(per_item[c.key]or 0)+choice.cost
                total.cost=total.cost+choice.cost;total.gross=total.gross+choice.gross
                total.fee=total.fee+choice.fee;total.revenue=total.revenue+choice.revenue
                total.profit=total.profit+choice.profit;total.qty=total.qty+choice.qty
            end
        end
    end
    total.count=#selected;total.unallocated=rest
    cache={rows=selected,candidates=#candidates,summary=total,version=sig,source='market snapshot'}
    cache_key=sig
    return cache
end
function F.invalidate() cache_key=nil;cache=nil end

-- Independent observations never overwrite the API quote automatically.
-- CR "today" is only shown when the stored sale history explicitly has
-- a day and a positive sold quantity. Open-stall quotes are local sightings.
function F.price_evidence(row)
    local out={api=nil,cr=nil,today=nil,opened=nil,buy=nil,age=nil,interest=0}
    if type(row)~='table' then return out end
    local st=DSP.market.state or{}
    if tonumber(st.sid)~=tonumber(DSP.settings.server) then return out end
    out.api=integer(row.sell and row.sell.med)>0 and integer(row.sell.med) or nil
    out.buy=integer(row.buy and row.buy.med)>0 and integer(row.buy.med) or nil
    out.interest=integer(row.buy and row.buy.shop_n)
    out.age=integer(st.updated)>0 and math.max(0,os.time()-integer(st.updated)) or nil
    local marker=DSP.market.load_cr_marker and DSP.market.load_cr_marker(st.sid)
    if marker and tonumber(marker.sid)==tonumber(st.sid) and (tonumber(row.ench)or 0)==0 then
        local key=DSP.lower(row.name or '')
        for _,it in ipairs(marker.items or{})do
            if DSP.lower(tostring(it.name or ''))==key then
                local val=integer(it.sell_med)
                if val>0 then out.cr=val;out.cr_age=integer(marker.saved_at)>0 and math.max(0,os.time()-integer(marker.saved_at))or nil end
                break
            end
        end
        local history=marker.histories and marker.histories[key]
        if history and history.day==os.date('%Y-%m-%d') and integer(history.qty)>0 and integer(history.avg)>0 then
            out.today=integer(history.avg);out.today_qty=integer(history.qty)
        end
    end
    local shop=DSP.live and DSP.live.shop or nil
    local updated=shop and integer(shop.items_updated or shop.updated)
    if shop and tonumber(shop.server)==tonumber(st.sid) and integer(shop.menu_closed)==0
        and updated>0 and os.time()-updated<=120 then
        local key=row.key or DSP.item_key(row.name,row.ench or 0)
        for _,it in ipairs(shop.sell or{})do
            local k=DSP.item_key(it.name or '',it.ench or 0)
            if k==key and integer(it.price)>0 then
                out.opened=out.opened and math.min(out.opened,integer(it.price)) or integer(it.price)
            end
        end
    end
    return out
end
function F.market_interest(row)
    local n=integer(row and row.buy and row.buy.shop_n)
    if n>=5 then return 'много скупщиков ('..n..')'
    elseif n>=2 then return 'несколько скупщиков ('..n..')'
    elseif n==1 then return 'один скупщик'
    end
    return 'нет наблюдаемой скупки'
end

-- SELL recommendations from asking prices only. They are not completed sales.
function F.suggest_price(row,mode,cost,tax)
    if not row or not row.sell then return nil,'нет рынка' end
    local sell=row.sell
    if integer(sell.count)==0 then return nil,'нет цен предложений' end
    local reference=mode=='fast' and (sell.p25>0 and sell.p25 or sell.min)
        or mode=='premium' and (sell.p75>0 and sell.p75 or sell.med)
        or sell.med
    local rate=mode=='fast' and 0.99 or mode=='premium' and 1.02 or 1
    local price=math.max(1,math.floor(reference*rate))
    if cost~=nil then
        local paid=num(cost,-1)
        if paid<0 then return nil,'неверная себестоимость' end
        local fee=math.min(10000,integer(tax,integer(DSP.settings.tax_bp,200)))
        if fee>=10000 then return nil,'комиссия 100%' end
        local floor_price=math.ceil(paid*10000/(10000-fee))
        price=math.max(price,floor_price)
    end
    return price,'по объявлениям; не подтверждённая цена сделки'
end
function F.watch_set(key,name,limit)
    local s=F.settings();key=tostring(key or '')
    local p=integer(limit)
    if key=='' or p==0 or p>MAX_SAFE then return false,'нужен предмет и цена выше нуля' end
    if not s.watch[key] then
        local n=0;for _ in pairs(s.watch)do n=n+1 end
        if n>=30 then return false,'максимум 30 наблюдений' end
    end
    local previous=s.watch[key]
    s.watch[key]={name=tostring(name or key),max_price=p,server=tonumber((DSP.market.state or{}).sid)or DSP.settings.server}
    if not DSP.save_settings() then s.watch[key]=previous;return false,'не удалось записать настройки' end
    return true
end
function F.watch_remove(key)
    local s=F.settings();local previous=s.watch[key];s.watch[key]=nil
    if not DSP.save_settings() then s.watch[key]=previous;return false,'не удалось записать настройки' end
    return true
end
F.last_alert=0;F.alerted={}
function F.check_alerts(now,notify)
    now=now or os.time();local s=F.settings();local st=DSP.market.state or{}
    if not s.alerts or not st.version or now-F.last_alert<300 then return 0 end
    local count=0
    for key,rule in pairs(s.watch)do
        local r=(st.by_key or{})[key]
        if tonumber(rule.server)==tonumber(st.sid) and r and r.sell and r.sell.min and r.sell.min>0
            and r.sell.min<=integer(rule.max_price) then
            local signature=tostring(st.sid)..':'..tostring(st.version)..':'..key
            if not F.alerted[signature] then
                F.alerted[signature]=true;F.last_alert=now
                if type(notify)=='function' then notify('Наблюдение: '..tostring(rule.name)..' по '..DSP.money(r.sell.min)..' (API, проверьте лавку)')end
                count=count+1;break
            end
        end
    end
    if count>0 then
        local n=0;for _ in pairs(F.alerted)do n=n+1 end
        if n>100 then F.alerted={} end
    end
    return count
end
-- Actual cash movements from saved trades only. Item valuations are excluded.
function F.cash_summary(trades,day)
    local out={trades=0,cash_in=0,cash_out=0,cash_net=0,valued_trades=0}
    local now=os.time();local today=os.date('%Y-%m-%d',now)
    for _,e in pairs(trades or{})do
        if type(e)=='table' and e.type=='trade' and (not day or os.date('%Y-%m-%d',integer(e.ts))==today) then
            out.trades=out.trades+1
            out.cash_in=out.cash_in+integer(e.money_get)
            out.cash_out=out.cash_out+integer(e.money_give)
            if # (e.items_get or{})>0 or #(e.items_give or{})>0 then out.valued_trades=out.valued_trades+1 end
        end
    end
    out.cash_net=out.cash_in-out.cash_out
    return out
end
