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
    if live and live.scan_complete==true and tonumber(live.server)==sid
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
