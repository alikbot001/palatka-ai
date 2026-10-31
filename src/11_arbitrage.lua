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
    local has_stall=cleaned:find('лавк' ,1,true) ~= nil
    local no_stall=cleaned:find('не существует' ,1,true)
        or cleaned:find('не найдена' ,1,true)
        or cleaned:find('не найдено' ,1,true)
        or cleaned:find('отсутствует' ,1,true)
    if not has_stall or not no_stall then return false end
    -- Prefer an explicit number, if the server includes one. A different
    -- number means this response is not for our request.
    local numbered=cleaned:match('#%s*(%d+)')
    if numbered and tonumber(numbered)~=tonumber(pending.shop) then return false end
    M.pending_find=nil
    if not M.mark_shop_missing_from_game(pending.shop,now) then return false end
    if DSP.shop_marker and DSP.shop_marker.clear then DSP.shop_marker.clear() end
    if DSP.add_log then DSP.add_log('Игра: лавка #'..tostring(pending.shop)..' не существует. Удалена из API-маршрутов.','error') end
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
                sellers_left[seller] = integer(seller.qty)
                for _, buyer in ipairs(row.buy.offers or {}) do
                    checkpoint()
                    local p_buy, p_sell = integer(seller.price), integer(buyer.price)
                    if (not selections or selections.buy[buyer])
                        and (seller.ench or 0) == (buyer.ench or 0)
                        and fresh(buyer, now, filters)
                        and p_buy > 0 and p_sell > p_buy
                        and (max_buy_price == 0 or p_buy <= max_buy_price)
                        and (shop_mode == 0
                            or (shop_mode == 1 and tostring(seller.shop)==tostring(buyer.shop))
                            or (shop_mode == 2 and tostring(seller.shop)~=tostring(buyer.shop)))
                        and integer(seller.qty) >= math.max(1, min_stock)
                        and integer(buyer.qty) >= math.max(1, min_stock) then
                        local demand_qty = integer(buyer.qty)
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
                        if integer(buyer.qty)>0 and reserve_pct<100 then
                            demand_qty=math.max(1,demand_qty)
                        end
                        buyers_left[buyer] = demand_qty
                        -- Tax is rounded on the batch, not on each individual item.
                        local fraction = ((p_sell % 10000) * tax_factor(tax_bp) % 10000) / 10000
                        local unit_profit = after_tax(p_sell, tax_bp) - p_buy + fraction
                        if unit_profit > 0 and unit_profit >= min_unit_profit then
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
    local sig = table.concat({M.state.sid or 0, M.state.version or 0, M.state.status or '', DSP.settings.tax_bp or 200,
        f.budget or 0, f.min_profit or 0, f.min_roi or 0, f.sort or 1,
        f.max_age or 300, tostring(f.include_unknown == true),
        tostring(f.allow_partial ~= false), f.max_qty or 0, f.safety_pct or 0,
        f.tax_bp or 'global',f.min_unit_profit or 0,f.max_buy_price or 0,
        f.min_stock or 0,f.shop_mode or 0,M.missing_revision or 0}, '|')
    if cache and sig == signature and not M.arb_dirty and now < expires then return cache end
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
