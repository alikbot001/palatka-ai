-- Item-centric market view. This module NEVER substitutes a planned trade
-- quantity for the observed stock/demand in the source market snapshot.
local M = DSP.market
local function qty(v)
    local n=tonumber(v)
    if not n or n~=n or n<0 or n==math.huge then return 0 end
    return math.floor(n)
end

-- Group all matched routes for the same exact item + enchantment.
-- Source offers are listed once regardless of how many routes use them.
function M.arbitrage_grouped()
    local deals=M.arbitrage_filtered()
    local groups,by_key={},{}
    for _,deal in ipairs(deals) do
        local row=deal.row
        local key=row.key
        local g=by_key[key]
        if not g then
            g={key=key,name=row.display,row=row,routes={},
                supply=qty(row.sell.qty),demand=qty(row.buy.qty),
                sellers=row.sell.offers or {},buyers=row.buy.offers or {},
                seller_count=#(row.sell.offers or {}),buyer_count=#(row.buy.offers or {}),
                planned=0,cost=0,revenue=0,profit=0,
                min_sell=row.sell.min or 0,max_buy=row.buy.max or 0}
            groups[#groups+1]=g
            by_key[key]=g
        end
        g.routes[#g.routes+1]=deal
        g.planned=g.planned+qty(deal.tradable_qty)
        g.cost=g.cost+(tonumber(deal.total_cost) or 0)
        g.revenue=g.revenue+(tonumber(deal.net_revenue) or 0)
        g.profit=g.profit+(tonumber(deal.net_profit) or 0)
    end
    table.sort(groups,function(a,b)
        if a.profit~=b.profit then return a.profit>b.profit end
        return a.name<b.name
    end)
    return groups
end

-- Raw snapshot demand is independent of a route's allocated quantity.
-- Individual routes can each mention the same buyer: NEVER sum qty_buyer
-- across routes. Use the raw buy-offer list instead.
function M.arbitrage_group_totals(groups)
    local result={items=0,routes=0,planned=0,cost=0,profit=0}
    for _,g in ipairs(groups or {}) do
        result.items=result.items+1
        result.routes=result.routes+#g.routes
        result.planned=result.planned+g.planned
        result.cost=result.cost+g.cost
        result.profit=result.profit+g.profit
    end
    return result
end

-- Optional manual correction after the player visits a stall. Keep the
-- original API number visible, and discard this correction on the next pull.
function M.confirm_offer_quantity(row,kind,offer,value)
    if not row or (kind~='buy' and kind~='sell') or not offer then
        return false,'неверное предложение'
    end
    local n=tonumber(value)
    if not n or n~=n or n<0 or n>1000000000 or n~=math.floor(n) then
        return false,'введите количество от 0 до 1 000 000 000'
    end
    local side=row[kind]
    local found=false
    for _,o in ipairs(side.offers or {}) do
        if o==offer then found=true; break end
    end
    if not found then return false,'предложение устарело' end
    if offer.snapshot_qty==nil then offer.snapshot_qty=qty(offer.qty) end
    side.qty=math.max(0,qty(side.qty)-qty(offer.qty)+n)
    offer.qty=n
    offer.verified_at=os.time()
    M.state.version=(M.state.version or 0)+1
    M.invalidate_arbitrage()
    return true
end
