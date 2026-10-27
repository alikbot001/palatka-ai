package.preload.encoding=function() return {UTF8={decode=function(_,s)return s end,encode=function(_,s)return s end}} end
getWorkingDirectory=function() return '/tmp/palatka_v22_arb_test' end
doesDirectoryExist=function() return true end
createDirectory=function() end
encodeJson=function() return '{}' end
decodeJson=function() return {} end
DSP=nil
dofile('src/00_core.lua')
dofile('src/05_items.lua')
dofile('src/10_market.lua')
dofile('src/11_arbitrage.lua')
dofile('src/12_arbitrage_groups.lua')
local clock=100000
os.time=function() return clock end
local M=DSP.market
local function rebuild(shops)
    for _,shop in ipairs(shops) do shop.server_id=102;shop.updated_at=shop.updated_at or clock end
    M.rebuild({shops=shops},102)
end
DSP.settings.tax_bp=50
DSP.settings.arb_filters={max_age=0}
rebuild({
 {shop_num=1,sell_slots={{name='Wood',price=100,qty=3}}},
 {shop_num=2,buy_slots={{name='Wood',price=101,qty=3}}},
})
local deals=M.arbitrage_filtered()
assert(#deals==1 and deals[1].tradable_qty==3 and deals[1].net_profit==1,
    'profitable whole batch survives commission rounding on one unit')
assert(type(M.plan_offers)=='function','manual selection planner exists')
DSP.settings.tax_bp=200
rebuild({
 {shop_num=1,sell_slots={{name='Wood',price=100,qty=2},{name='Wood',price=100,qty=3}}},
 {shop_num=2,sell_slots={{name='Wood',price=110,qty=7}}},
 {shop_num=3,buy_slots={{name='Wood',price=200,qty=8}}},
 {shop_num=4,buy_slots={{name='Wood',price=180,qty=8}}},
})
local g=M.arbitrage_grouped()[1]
assert(g.supply==12 and g.demand==16 and g.planned==12)
local p=M.plan_offers(g,{g.sellers[1],g.sellers[2]},{g.buyers[1]})
assert(p.qty==8 and p.supply==12 and p.demand==8 and p.cost==830 and p.profit==738,
    'multiple selected sellers share buyer demand once')
assert(p.planned==p.qty and #p.routes==2)
local allocated={}
for _,r in ipairs(p.routes) do
    allocated[r.buy_offer]=(allocated[r.buy_offer] or 0)+r.tradable_qty
    assert(allocated[r.buy_offer]<=r.qty_buyer,'selected routes cannot duplicate buyer demand')
end
p=M.plan_offers(g,{[g.sellers[1]]=true},{[M.offer_key(g.buyers[1])]=true,[M.offer_key(g.buyers[2])]=true})
assert(p.qty==5 and p.supply==5 and p.demand==16,'one stock pool is not repeated for two buyers')
p=M.plan_offers(g,nil,nil,{budget=350,extra=25})
assert(p.qty==3 and p.cost==300 and p.revenue==588 and p.profit==263,
    'manual budget shared across all routes and extra expense deducted once')
assert(g.row.sell.qty==12 and g.row.buy.qty==16 and g.sellers[1].qty==5,
    'planning preserves raw supply and demand')
p=M.plan_offers(g,{},nil)
assert(p.qty==0 and p.cost==0 and p.supply==0,'empty selection means no sellers')
p=M.plan_offers(g,nil,{}, {extra=999})
assert(p.qty==0 and p.profit==0,'empty plan does not spend extra expenses')
p=M.plan_offers(g,{ {shop='1',price=100,qty=999999} },nil)
assert(p.qty==0,'foreign offer tables cannot inject stock into selection')
DSP.settings.arb_filters={max_age=30}
clock=clock+31
p=M.plan_offers(g,nil,nil)
assert(p.qty==0 and p.supply==12 and p.demand==16,'stale stock stays a snapshot, cannot enter plan')
-- Concrete player case: gross proceeds are NOT profit.
DSP.settings.arb_filters={max_age=0};DSP.settings.tax_bp=200
rebuild({
 {shop_num=17,sell_slots={{name='Crate',price=59000,qty=5}}},
 {shop_num=71,buy_slots={{name='Crate',price=72000,qty=504}}},
})
local gg=M.arbitrage_grouped()[1]
local pp=M.plan_offers(gg,nil,nil)
assert(pp.qty==5 and pp.supply==5 and pp.demand==504,'raw inventory and demand mixed')
assert(pp.cost==295000 and pp.gross==360000 and pp.fee==7200 and pp.revenue==352800
 and pp.profit==57800,'gross proceeds were confused with net profit')
local with_expenses=M.plan_offers(gg,nil,nil,{extra=5000})
assert(with_expenses.extra==5000 and with_expenses.profit==52800 and
 with_expenses.revenue==352800,'additional expenses did not affect only profit')
print('v2.2 arbitrage: 295k purchase, 360k gross, 7.2k commission, 57.8k profit: OK')
print('v2.2 arbitrage selection, no double counting, batch commission: ok')
DSP.mobile=DSP.mobile or {}
DSP.ui=DSP.ui or {}
dofile('src/38_arbitrage_v16.lua')
assert(DSP.arb_v16.manual_pair({shop='7',qty=3,price=100},{shop=7,qty=700,price=200},0,200)==nil,
    'manual pair cannot buy and resell at the same stall')
assert(DSP.arb_v16.manual_pair({shop='7',ench=1,qty=3,price=100},{shop='8',ench=2,qty=700,price=200},0,200)==nil,
    'manual pair preserves exact enchantment identity')
assert(DSP.arb_v16.manual_pair({qty=0/0,price=100},{qty=700,price=200},0,200)==nil,
    'invalid nonfinite source quantities are rejected')
local large=DSP.arb_v16.manual_pair({qty=3,price=1000000000000000},{qty=3,price=2000000000000001},0,200)
assert(large.revenue==5880000000000002 and large.cost==3000000000000000,
    'manual pair commission stays exact for large prices')
local untaxed=DSP.arb_v16.manual_pair({qty=1,price=100},{qty=1,price=200},0,-100)
assert(untaxed.revenue==200,'negative tax is clamped to zero consistently with the allocator')
print('v2.2 manual pair validation and large-price arithmetic: ok')
