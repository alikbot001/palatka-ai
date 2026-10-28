-- Regression for same-stall arbitrage, split API snapshots, and native shop observation.
package.preload['encoding']=function() return {
  default='CP1251',CP1251={encode=function(_,s)return s end},
  UTF8={encode=function(_,s)return s end,decode=function(_,s)return s end}}
end
getWorkingDirectory=function()return '/tmp' end
doesDirectoryExist=function()return true end
createDirectory=function()end
encodeJson=function()return '{}' end
decodeJson=function()return {} end
DSP=nil
dofile('src/00_core.lua');dofile('src/05_items.lua');dofile('src/10_market.lua')
dofile('src/11_arbitrage.lua')
local clock=1700000000
os.time=function()return clock end
DSP.settings.server=102
DSP.settings.tax_bp=200
DSP.settings.arb_filters={max_age=600,safety_pct=10,include_unknown=false}
-- Both sides on one stall, each advertises only one item.
DSP.market.rebuild({shops={{server_id=102,shop_num=7,owner='Trader',updated_at=clock,
 sell_slots={{name='Ларец крафтера',qty=1,price=120000}} ,
 buy_slots={{name='Ларец крафтера',qty=1,price=160000}}}}},102)
local plan=DSP.market.arbitrage_filtered()
assert(#plan==1,'10% reserve cannot discard a 1-unit profitable same-stall route')
assert(plan[1].same_shop and plan[1].tradable_qty==1)
assert(plan[1].net_profit==36800,'after commission unit profit')
-- On some API payloads, one shop arrives in separate records for sell/buy.
DSP.market.rebuild({shops={
 {server_id=102,shop_num=7,owner='Trader',updated_at=clock,
  sell_slots={{name='Ларец крафтера',qty=1,price=120000}}},
 {server_id=102,shop_num=7,owner='Trader',updated_at=clock,
  buy_slots={{name='Ларец крафтера',qty=1,price=160000}}},
 {server_id=102,shop_num=7,owner='Trader',updated_at=clock,
  sell_slots={{name='Ларец крафтера',qty=1,price=120000}}},
}},102)
local row=DSP.market.row_for('Ларец крафтера',0)
assert(row and row.sell.qty==1 and row.buy.qty==1,'split pages merge, replay not double counted')
assert(#DSP.market.arbitrage_filtered()==1,'same-stall spread must survive split records')
-- Newer snapshot replaces historical entries, never sum stale offers.
DSP.market.rebuild({shops={
 {server_id=102,shop_num=7,updated_at=clock-10,
  sell_slots={{name='Ларец крафтера',qty=20,price=120000}}},
 {server_id=102,shop_num=7,updated_at=clock,
  sell_slots={{name='Ларец крафтера',qty=2,price=125000}}},
}},102)
row=DSP.market.row_for('Ларец крафтера',0)
assert(row.sell.qty==2 and row.buy.qty==0,'newest replaces old, no phantom demand')
-- Independent game packet source, no API response required.
DSP.live={shop={owner='Trader',num='7',server=102,updated=clock,items_updated=clock,
 menu_closed=0,sell={{name='Ларец крафтера',ench=0,price=120000,qty=1}},
 buy={{name='Ларец крафтера',ench=0,price=160000,qty=1}}}}
local game=DSP.market.live_shop_spreads()
assert(#game==1 and game[1].profit_unit==36800 and game[1].quantity==1)
DSP.live.shop.sell[1].qty=nil
assert(DSP.market.live_shop_spreads()[1].quantity==nil,'unknown count is not x1')
DSP.live.shop.server=103
assert(#DSP.market.live_shop_spreads()==0,'no cross-server game scan')
DSP.live.shop.server=102
DSP.live.shop.menu_closed=clock
assert(#DSP.market.live_shop_spreads()==0,'closed stall not live')
-- Entire Lua-build theme must identify Carbon Trade.
assert(DSP.theme.list.carbon_trade and DSP.theme.list.carbon_trade.name=='Carbon Trade')
print('v2.2.8 split API, 1-unit route, live same-stall, carbon: OK')
