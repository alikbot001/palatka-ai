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
        if DSP.arb_agent and r.qty and b('В МИНИ-АГЕНТ','local_to_agent',186)then
            local ok,why=DSP.arb_agent.add_local_route(r)
            if ok then DSP.arb_agent.show(true);imgui.CloseCurrentPopup()
            else DSP.notify('Агент: '..tostring(why))end
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