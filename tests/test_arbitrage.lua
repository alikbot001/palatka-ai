package.preload.encoding = function()
    return { UTF8 = { decode = function(_, s) return s end, encode = function(_, s) return s end } }
end
getWorkingDirectory = function() return '/tmp/palatka_arbitrage_test' end
doesDirectoryExist = function() return true end
createDirectory = function() end
encodeJson = function() return '{}' end
decodeJson = function() return {} end
DSP = nil
dofile('src/00_core.lua')
dofile('src/05_items.lua')
dofile('src/10_market.lua')
if io.open('src/11_arbitrage.lua', 'r') then dofile('src/11_arbitrage.lua') end
local clock = 10000
os.time = function() return clock end
local function rebuild(sell, buy, qty, ts)
    DSP.market.rebuild({shops = {
        {server_id=102, shop_num='1', owner='Seller', updated_at=ts or clock,
            sell_slots={{name='Wood', price=sell, qty=qty, ench=0}}},
        {server_id=102, shop_num='2', owner='Buyer', updated_at=ts or clock,
            buy_slots={{name='Wood', price=buy, qty=qty, ench=0}}},
    }}, 102)
end
DSP.settings.tax_bp = 200
DSP.settings.arb_filters = {budget=350, min_profit=0, min_roi=0, sort=1}
rebuild(100,200,10)
local a = DSP.market.arbitrage_filtered()
assert(#a == 1, 'affordable partial party must remain visible')
assert(a[1].tradable_qty == 3 and a[1].total_cost == 300)
assert(a[1].net_revenue == 588 and a[1].net_profit == 288)
assert(a[1].available_qty == 10 and a[1].partial)
assert(DSP.market.arbitrage_filtered() == a, 'same snapshot uses cache')
DSP.settings.tax_bp = 1000
assert(DSP.market.arbitrage_filtered()[1].net_profit == 240, 'tax change invalidates cache')
DSP.settings.arb_filters.allow_partial = false
assert(#DSP.market.arbitrage_filtered() == 0, 'optional whole party only')
DSP.settings.arb_filters = {budget=0, max_qty=2}
assert(DSP.market.arbitrage_filtered()[1].tradable_qty == 2, 'quantity cap')
DSP.settings.arb_filters = {max_age=30}
clock = clock + 31
assert(#DSP.market.arbitrage_filtered() == 0, 'cached offer expires without market refresh')
DSP.settings.arb_filters = {include_unknown=false}
rebuild(100,200,10,0)
assert(#DSP.market.arbitrage_filtered() == 0, 'unknown timestamps can be excluded')
DSP.settings.arb_filters.include_unknown=true
assert(#DSP.market.arbitrage_filtered() == 1)
assert(DSP.market.offer_freshness(0) == 'время неизвестно')
local row = DSP.market.row_for('Wood',0)
assert(DSP.market.sell_target(row,2) == 98, 'sell undercut compares competing sale prices')
assert(DSP.market.buy_target(row,10) == 162, 'buy target includes tax and margin')
assert(DSP.item_key('{FF0000}Wood',0) == DSP.item_key('Wood',0), 'color does not change identity')
assert(DSP.item_key('Wood',0) ~= DSP.item_key('Wood',12))
dofile('src/15_prices.lua')
DSP.db.by_key = {[DSP.item_key('Hat',12)]={name='Hat',ench=12,sell={min=100000}}}
DSP.db.rebuild_base()
assert(DSP.db.get('Hat',0) == nil, 'price fallback must not use different enchantment')
DSP.market.state.status='live'; DSP.market.state.last_request=clock
DSP.settings.refresh_seconds=60
assert(not DSP.market.should_refresh(clock+59))
assert(DSP.market.should_refresh(clock+60), 'market refreshes even without server/nick changes')
DSP.market.state.status='loading'
assert(not DSP.market.should_refresh(clock+90), 'requests never overlap')
DSP.settings.arb_filters={max_age=0}
rebuild(100,200,10,clock+100)
assert(#DSP.market.arbitrage_filtered()==0)
clock=clock+41
assert(#DSP.market.arbitrage_filtered()==1, 'future timestamp becomes eligible even with no age limit')
print('arbitrage tests: ok')
-- Regression: same-price slots in one stall form one stock pool.
DSP.settings.arb_filters = {budget=0, max_age=0, sort=1}
DSP.market.rebuild({shops={
    {server_id=102,shop_num='10',owner='Stock',updated_at=clock,
        sell_slots={{name='Wood',price=100,qty=2},{name='Wood',price=100,qty=3}}},
    {server_id=102,shop_num='20',owner='Demand',updated_at=clock,
        buy_slots={{name='Wood',price=210,qty=4}}},
    {server_id=102,shop_num='30',owner='Demand2',updated_at=clock,
        buy_slots={{name='Wood',price=170,qty=4}}},
}},102)
local row2 = DSP.market.row_for('Wood', 0)
assert(#row2.sell.offers==1 and row2.sell.offers[1].qty==5, 'same stall/price slots are summed')
local plan = DSP.market.arbitrage_filtered()
local allocated, to_20, to_30 = 0,0,0
for _,deal in ipairs(plan) do
    allocated=allocated+deal.tradable_qty
    if deal.buy_offer.shop=='20' then to_20=to_20+deal.tradable_qty end
    if deal.buy_offer.shop=='30' then to_30=to_30+deal.tradable_qty end
end
assert(allocated==5 and to_20==4 and to_30==1,'seller stock not promised twice')
DSP.settings.arb_filters={budget=350,max_age=0}
plan=DSP.market.arbitrage_filtered()
allocated=0
local total=0
for _,deal in ipairs(plan) do allocated=allocated+deal.tradable_qty; total=total+deal.total_cost end
assert(allocated==3 and total==300,'budget not reused across multiple deal rows')
-- Reverse: one buyer's demand must not be promised to two sellers.
DSP.settings.arb_filters={budget=0,max_age=0}
DSP.market.rebuild({shops={
    {server_id=102,shop_num='11',owner='Seller A',updated_at=clock,
        sell_slots={{name='Wood',price=100,qty=7}}},
    {server_id=102,shop_num='12',owner='Seller B',updated_at=clock,
        sell_slots={{name='Wood',price=110,qty=7}}},
    {server_id=102,shop_num='13',owner='Buyer',updated_at=clock,
        buy_slots={{name='Wood',price=200,qty=8}}},
}},102)
plan=DSP.market.arbitrage_filtered()
allocated=0
for _,deal in ipairs(plan) do allocated=allocated+deal.tradable_qty end
assert(allocated==8,'buyer demand not promised twice')
-- One store can sell the same item at distinct prices without blending prices.
DSP.market.rebuild({shops={
    {server_id=102,shop_num='1',updated_at=clock,sell_slots={
        {name='Wood',price=100,qty=2},{name='Wood',price=140,qty=4}}},
    {server_id=102,shop_num='2',updated_at=clock,buy_slots={{name='Wood',price=200,qty=6}}},
}},102)
local row3=DSP.market.row_for('Wood',0)
assert(#row3.sell.offers==2,'different-price slots remain distinct')
plan=DSP.market.arbitrage_filtered()
allocated=0
for _,deal in ipairs(plan) do allocated=allocated+deal.tradable_qty end
assert(allocated==6,'different price bands both supported')
-- Server mismatch must clear the visible snapshot, even if a request fails.
DSP.market.clear_for_server(103)
assert(DSP.market.state.sid==103 and #DSP.market.state.rows==0,'no mixed-server offers')
assert(#DSP.market.arbitrage_filtered()==0,'no arbitrage from old server')
print('arbitrage allocation, slot merging, server isolation: ok')
