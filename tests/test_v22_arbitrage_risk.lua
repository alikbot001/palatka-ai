-- Risk regression: one stall may publish BOTH sides, and dated buy demand
-- is not a guaranteed reservation. Tests do not execute real game trades.
package.preload.encoding=function()return{UTF8={decode=function(_,x)return x end,encode=function(_,x)return x end}}end
getWorkingDirectory=function()return '/tmp/palatka_arb_risk'end
doesDirectoryExist=function()return true end
createDirectory=function()end
encodeJson=function()return '{}'end
decodeJson=function()return {}end
DSP=nil
dofile('src/00_core.lua')
dofile('src/05_items.lua')
dofile('src/10_market.lua')
dofile('src/11_arbitrage.lua')
dofile('src/12_arbitrage_groups.lua')
local clock=1800000000
os.time=function()return clock end
local M=DSP.market
DSP.settings.tax_bp=200
DSP.settings.arb_filters={max_age=600,include_unknown=false,safety_pct=10}
local function shop(n,sell,buy)
 return {server_id=102,shop_num=n,updated_at=clock,sell_slots=sell or{},buy_slots=buy or{}}
end
M.rebuild({shops={shop(17,{{name='Amulet',qty=100,price=100000}},{{name='Amulet',qty=100,price=160000}})}},102)
local deals=M.arbitrage_filtered()
assert(#deals==1,'same-stall bid/ask opportunity was lost')
assert(deals[1].same_shop,'must label game-uncertain same-stall route')
assert(deals[1].tradable_qty==90,'unverified demand must keep a 10% reserve')
assert(deals[1].net_profit==90*(160000-100000)-math.floor(90*160000*.02),'tax/risk profit')
local group=M.arbitrage_grouped()[1]
local ok=M.confirm_offer_quantity(group.row,'buy',group.buyers[1],92)
assert(ok,'manual in-game correction failed')
local plan=M.plan_offers(group,nil,nil)
assert(plan.qty==92 and plan.demand==92,'player-verified demand must be used, not API 100')
M.rebuild({shops={shop(5,{{name='Rune',qty=60,price=100}}),shop(6,{{name='Rune',qty=60,price=110}}),
 shop(7,nil,{{name='Rune',qty=100,price=200}})}},102)
local g=M.arbitrage_grouped()[1]
local p=M.plan_offers(g,nil,nil)
assert(p.qty==90 and #p.routes==2,'the safety allowance cannot be reused for every seller')
local allocated=0
for _,route in ipairs(p.routes)do allocated=allocated+route.tradable_qty end
assert(allocated<=90,'double-spent buy demand')
clock=clock+601
assert(#M.arbitrage_filtered()==0,'expired offers still advertised as actionable')
print('market risk: same stall, reserve, real correction, shared buy limit, stale expiry: OK')
