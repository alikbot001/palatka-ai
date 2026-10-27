-- Compare real offers; budget limits apply before profitability filters.
local M = DSP.market
local cache, signature, expires

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
    local interval = math.max(30, tonumber(DSP.settings.refresh_seconds) or 60)
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

local function fresh(offer, now, filters)
    local ts = integer(offer.ts)
    if ts == 0 then return filters.include_unknown ~= false end
    if ts > now + 60 then return false end
    local max_age = integer(filters.max_age, 1800)
    return max_age == 0 or now - ts <= max_age
end

-- Build a non-overlapping purchase/resale plan. A shop's stock or demand
-- cannot be committed twice just because it matches several other stalls.
-- Greedy allocation prioritizes unit profit (or ROI under a cash budget).
local function opportunities(filters, now, rows, selections)
    local candidates, out = {}, {}
    local tax_bp = filters.tax_bp or DSP.settings.tax_bp
    local budget = integer(filters.budget)
    local remaining_budget = budget > 0 and budget or math.huge
    local max_qty = integer(filters.max_qty)
    local sellers_left, buyers_left = {}, {}
    local min_profit = integer(filters.min_profit)
    local min_roi = tonumber(filters.min_roi) or 0
    local reserve_pct = math.floor(math.max(0, math.min(90, tonumber(filters.safety_pct) or 0)))
    for _, row in ipairs(rows or M.state.rows or {}) do
        for _, seller in ipairs(row.sell.offers or {}) do
            if (not selections or selections.sell[seller]) and fresh(seller, now, filters) then
                sellers_left[seller] = integer(seller.qty)
                for _, buyer in ipairs(row.buy.offers or {}) do
                    checkpoint()
                    local p_buy, p_sell = integer(seller.price), integer(buyer.price)
                    if (not selections or selections.buy[buyer])
                        and (seller.ench or 0) == (buyer.ench or 0)
                        and fresh(buyer, now, filters)
                        and p_buy > 0 and p_sell > p_buy
                        and integer(seller.qty) > 0 and integer(buyer.qty) > 0 then
                        local demand_qty = integer(buyer.qty)
                        if not buyer.verified_at then
                            local factor=100-reserve_pct
                            -- Exact up to 2^53: do not overflow precision by multiplying
                            -- the full inventory count before dividing by 100.
                            demand_qty=math.floor(demand_qty/100)*factor
                                + math.floor((demand_qty%100)*factor/100)
                        end
                        buyers_left[buyer] = demand_qty
                        -- Tax is rounded on the batch, not on each individual item.
                        local fraction = ((p_sell % 10000) * tax_factor(tax_bp) % 10000) / 10000
                        local unit_profit = after_tax(p_sell, tax_bp) - p_buy + fraction
                        if unit_profit > 0 then
                            candidates[#candidates+1] = {
                                row=row, seller=seller, buyer=buyer,
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
                        qty_seller=integer(seller.qty), qty_buyer=integer(buyer.qty),
                        available_qty=available, tradable_qty=qty, partial=qty<available,
                        total_cost=cost, net_revenue=revenue, net_profit=profit,
                        roi=roi, unit_profit=c.unit_profit,
                        sell_age=seller.ts or 0, buy_age=buyer.ts or 0,
                        shared_stock=available<math.min(integer(seller.qty),integer(buyer.qty)),
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
    local sig = table.concat({M.state.sid or 0, M.state.version or 0, DSP.settings.tax_bp or 200,
        f.budget or 0, f.min_profit or 0, f.min_roi or 0, f.sort or 1,
        f.max_age or 1800, tostring(f.include_unknown ~= false),
        tostring(f.allow_partial ~= false), f.max_qty or 0, f.safety_pct or 0}, '|')
    if cache and sig == signature and not M.arb_dirty and now < expires then return cache end
    cache, signature = opportunities(f, now), sig
    expires = math.huge
    local max_age = integer(f.max_age,1800)
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
    M.arb_dirty = false
    return cache
end

function M.offer_freshness(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return 'время неизвестно', 'muted' end
    local age = os.time() - ts
    if age < -60 then return 'ошибка времени', 'warn' end
    if age < 180 then return 'свежее', 'good' end
    if age < 600 then return math.floor(age / 60) .. ' мин назад', 'warn' end
    return math.floor(age / 60) .. ' мин назад', 'muted'
end
