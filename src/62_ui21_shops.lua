-- 2.1 shops: API offers grouped by exact item key. Search by item/owner/shop.
-- Never display allocated arbitrage quantity as available market quantity.
local V,M=DSP.ui21,DSP.mobile
V.shops_mode='sell'
V.shops_sort='price'
local function b(s,id,w,active) return V.button(s,'shops_'..id,w,active) end
local function contains(s,q) return DSP.lower(tostring(s or '')):find(q,1,true)~=nil end
function V.shops_result(rows,mode,query,version)
    local stamp=tostring(DSP.market.state.sid)..'|'..tostring(version)..'|'..mode..'|'..DSP.lower(query or '')
    if V.shops_stamp==stamp then return V.shops_groups end
    local out={}
    local q=DSP.lower(query or '')
    for _,r in ipairs(rows or {}) do
        local entries=(r[mode] and r[mode].offers) or {}
        if #entries>0 then
            local item_match=q=='' or contains(r.display,q)
            local subset={}
            for _,o in ipairs(entries) do
                if item_match or contains(o.owner,q) or contains(o.shop,q) then subset[#subset+1]=o end
            end
            if #subset>0 then
                local total,shops,best=0,{},nil
                for _,o in ipairs(subset) do
                    total=total+math.max(0,math.floor(tonumber(o.qty) or 0))
                    shops[tostring(o.shop)]=true
                    local price=tonumber(o.price) or 0
                    if not best or (mode=='sell' and price<best) or (mode=='buy' and price>best) then best=price end
                end
                local nshops=0;for _ in pairs(shops) do nshops=nshops+1 end
                out[#out+1]={row=r,offers=subset,qty=total,count=#subset,shops=nshops,best=best or 0}
            end
        end
    end
    local asc=(mode=='sell')
    table.sort(out,function(a,b)
        if a.best~=b.best then
            if asc then return a.best < b.best else return a.best > b.best end
        end
        return tostring(a.row.display)<tostring(b.row.display)
    end)
    V.shops_stamp=stamp
    V.shops_groups=out
    return out
end
local function filtered_group()
    for _,g in ipairs(V.shops_groups or {}) do
        if g.row.key==V.shop_item then return g end
    end
    return nil
end
local function shop_detail()
    local stamp=tostring(DSP.market.state.sid)..'/'..tostring(DSP.market.state.version)
    if V.cached_shop_stamp~=stamp then
        V.cached_shops=DSP.market.shops_list();V.cached_shop_stamp=stamp
    end
    local shops=V.cached_shops or {}
    local item
    for _,s in ipairs(shops) do if tostring(s.num)==tostring(V.shop_detail) then item=s;break end end
    if b('‹ Назад','back_to_item',125) then V.shop_detail=nil;return end
    if not item then V.muted('Лавка отсутствует в текущем снимке.');return end
    V.text('Лавка #'..tostring(item.num)..'  ·  '..tostring(item.owner))
    V.muted(DSP.market.offer_freshness(item.ts))
    V.inline()
    if b('Отметить','mark_shop',135) then DSP.market.mark_shop(item.num) end
    if item.buy_count>0 and b('Скопировать скупку +1$','copy_shop',230) then
        local n,err=DSP.market.copy_shop_skupka(item.num,nil,1)
        DSP.notify(n and ('Скопировано: '..n) or tostring(err))
    end
    for _,side in ipairs({'sell','buy'}) do
        V.text(side=='sell' and 'Продаёт:' or 'Скупает:')
        for i,e in ipairs(item[side..'_offers'] or {}) do
            V.muted(tostring(e.row.display)..'   x'..tostring(e.offer.qty or 0)..'   '..DSP.money(e.offer.price))
        end
    end
end
local function item_detail()
    if V.shop_detail then return shop_detail() end
    local g=filtered_group()
    if b('‹ К товарам','item_back',152) then V.shop_item=nil;return end
    if not g then V.muted('Предложения обновились. Вернитесь к списку.');return end
    V.text(tostring(g.row.display))
    V.muted(g.shops..' лавок · '..g.qty..' шт. по снимку API · '..DSP.market.freshness())
    V.text(V.shops_mode=='sell' and 'Купить у игроков' or 'Продать игрокам')
    local offers=g.offers
    table.sort(offers,function(a,b)
        if a.price~=b.price then
            if V.shops_mode=='sell' then return a.price < b.price else return a.price > b.price end
        end
        return tostring(a.shop)<tostring(b.shop)
    end)
    local from,to=V.selected_page('shop_offers',#offers,14)
    for i=from,to do
        local o=offers[i]
        V.text('#'..tostring(o.shop)..'  '..tostring(o.owner or '?'))
        V.inline()
        V.muted('x'..tostring(o.qty)..' · '..DSP.money(o.price)..'/шт.')
        V.inline()
        if b('›','offer_'..i,47) then V.shop_detail=tostring(o.shop) end
        imgui.Separator()
    end
    V.pager('shop_offers',#offers,14)
end
function V.shops()
    local sig=tostring(DSP.market.state.sid)..'/'..tostring(DSP.market.state.version)
    if V.shop_version~=sig then
        V.shop_version=sig;V.shop_item=nil;V.shop_detail=nil
    end
    if V.shop_item then return item_detail() end
    V.text('Лавки')
    V.inline();V.muted('Рынок игроков · '..DSP.market.freshness())
    V.inline();if b('Обн.','refresh',51) then DSP.market.pull(DSP.market.state.sid) end
    if b('Продают','mode_sell',math.max(140,imgui.GetContentRegionAvail().x*.25),V.shops_mode=='sell') then
        V.shops_mode='sell';V.pages.shops=1
    end
    V.inline()
    if b('Скупают','mode_buy',math.max(140,imgui.GetContentRegionAvail().x*.25),V.shops_mode=='buy') then
        V.shops_mode='buy';V.pages.shops=1
    end
    local query=V.search('shops','Предмет, ник, № лавки',-1)
    local groups=V.shops_result(DSP.market.state.rows,V.shops_mode,query,DSP.market.state.version)
    V.muted(#groups..' предметов')
    local from,to=V.selected_page('shops',#groups,18)
    for i=from,to do
        local g=groups[i]
        local w=imgui.GetContentRegionAvail().x
        if w>500 then
            imgui.Columns(2,'##v21_shopgroup_'..i,false)
            imgui.SetColumnWidth(0,math.max(140,w-175))
        end
        M.thumbnail({name=g.row.display,id=g.row.id},23);V.inline()
        V.text(tostring(g.row.display))
        if w>500 then imgui.NextColumn() else V.inline() end
        if b(DSP.money(g.best)..' ›','group_'..i,math.min(155,w*.29)) then
            V.shop_item=g.row.key;V.pages.shop_offers=1
        end
        if w>500 then imgui.Columns(1) end
        V.muted(g.shops..' лавок · '..g.qty..' шт. (API)')
        imgui.Separator()
    end
    if #groups==0 then V.muted('Нет совпадений или не загружен рынок.') end
    V.pager('shops',#groups,18)
end
function V.shops_footer(w)
    if b('^','foot_up',55) then M.queue_scroll(-1) end
    V.inline()
    if b('v','foot_down',55) then M.queue_scroll(1) end
    V.inline()
    V.muted('Количество — снимок API')
end
