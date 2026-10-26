package.preload.encoding=function() return {UTF8={decode=function(_,s)return s end,encode=function(_,s)return s end}} end
getWorkingDirectory=function() return '/tmp/palatka_v15_test' end
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
DSP.settings.tax_bp=200
DSP.settings.arb_filters={budget=0,max_age=0}
-- Three sellers, one buyer: the same item must be a SINGLE group.
DSP.market.rebuild({shops={
    {server_id=102,shop_num=1,owner='A',updated_at=clock,sell_slots={{name='Case Frame',qty=1,price=100}}},
    {server_id=102,shop_num=2,owner='B',updated_at=clock,sell_slots={{name='Case Frame',qty=1,price=110}}},
    {server_id=102,shop_num=3,owner='C',updated_at=clock,sell_slots={{name='Case Frame',qty=1,price=115}}},
    {server_id=102,shop_num=4,owner='D',updated_at=clock,buy_slots={{name='Case Frame',qty=700,price=200}}},
}},102)
local groups=DSP.market.arbitrage_grouped()
assert(#groups==1,'must group all sellers of the same item')
local g=groups[1]
assert(g.name=='Case Frame')
assert(g.supply==3 and g.demand==700,'source volumes differ from allocated plan')
assert(g.seller_count==3 and g.buyer_count==1)
assert(g.planned==3 and #g.routes==3,'seller stock must not be counted twice')
assert(g.profit>0)
for _,r in ipairs(g.routes) do
  assert(r.qty_buyer==700,'raw buyer qty must remain visible in every route')
  assert(r.tradable_qty==1,'planned qty stays separate from buyer demand')
end
local sums=DSP.market.arbitrage_group_totals(groups)
assert(sums.items==1 and sums.routes==3 and sums.planned==3)
-- Budget may reduce planned volume, but MUST NOT change the 700-unit demand figure.
DSP.settings.arb_filters={budget=105,max_age=0}
g=DSP.market.arbitrage_grouped()[1]
assert(g and g.demand==700 and g.supply==3 and g.planned==1)
-- Source demand of 1 is never silently inflated to an unverified number.
DSP.market.rebuild({shops={
    {server_id=102,shop_num=1,owner='A',updated_at=clock,sell_slots={{name='Case Frame',qty=4,price=100}}},
    {server_id=102,shop_num=4,owner='D',updated_at=clock,buy_slots={{name='Case Frame',qty=1,price=200}}},
}},102)
DSP.settings.arb_filters={budget=0,max_age=0}
g=DSP.market.arbitrage_grouped()[1]
assert(g and g.demand==1 and g.planned==1,'cannot infer live stock from snapshot')
local buyer=g.buyers[1]
local ok,err=DSP.market.confirm_offer_quantity(g.row,'buy',buyer,700)
assert(ok,err)
g=DSP.market.arbitrage_grouped()[1]
assert(g.demand==700 and g.planned==4 and buyer.snapshot_qty==1,
    'verified in-game demand changes the plan but preserves original API value')
assert(not DSP.market.confirm_offer_quantity(g.row,'buy',buyer,-1),
    'invalid manual amounts rejected')
print('v1.5 item grouping and 1-vs-700 source tests: ok')
