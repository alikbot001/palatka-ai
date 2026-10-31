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
        if DSP.arb_agent and b('В МИНИ-АГЕНТ','route_to_agent',176,true)then
            local ok,why=DSP.arb_agent.add_plan(p)
            if ok then
                DSP.arb_agent.show(true)
                imgui.CloseCurrentPopup()
            else DSP.notify('Агент: '..tostring(why))end
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
        if b(DSP.arb_agent.active()and'МИНИ-АГЕНТ >'or'НАЧАТЬ СЕССИЮ','session_start',190,true)then
            local ok,why
            if DSP.arb_agent.active()then DSP.arb_agent.show(true);ok=true
            else ok,why=DSP.arb_agent.start_market()end
            if not ok then DSP.notify('Агент арбитража: '..tostring(why))end
        end
        local st_agent=DSP.arb_agent.stats()
        if st_agent.routes>0 then V.muted('Сессия: '..st_agent.done..'/'..st_agent.routes..' маршрутов')end
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
