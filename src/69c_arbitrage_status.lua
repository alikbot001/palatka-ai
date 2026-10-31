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
    changed()
    A.next(1)
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
