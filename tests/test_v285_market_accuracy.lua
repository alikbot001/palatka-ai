-- Accurate Trade v2.8.5: shared demand, live packet qty, stale/anonymous fallback.
package.preload.encoding=function()return {UTF8={decode=function(_,x)return x end,encode=function(_,x)return x end}} end
getWorkingDirectory=function()return '/tmp/palatka_accuracy_v285' end
doesDirectoryExist=function()return true end
createDirectory=function()end
decodeJson=function()return {}end
encodeJson=function()return '{}'end
dofile('src/00_core.lua')
dofile('src/05_items.lua')
dofile('src/10_market.lua')
dofile('src/11_arbitrage.lua')
dofile('src/11a_accuracy.lua')
dofile('src/12_arbitrage_groups.lua')
local M=DSP.market
DSP.settings.server=102
DSP.settings.arb_filters={budget=0,min_profit=0,min_roi=0,max_age=300,include_unknown=false,
    safety_pct=0,max_qty=0,shop_mode=2,tax_bp=0}
local now=os.time()
assert(M.rebuild({shops={
 {server_id=102,shop_num=71,owner='Seller_A',updated_at=now,
  sell_slots={{name='Firewood',price=10,qty=4}}},
 {server_id=102,shop_num=72,owner='Seller_B',updated_at=now,
  sell_slots={{name='Firewood',price=11,qty=4}}},
 {server_id=102,shop_num=80,owner='Buyer_A',updated_at=now,
  buy_slots={{name='Firewood',price=30,qty=5}}}
}},102))
local row=M.state.by_key[DSP.item_key('Firewood',0)]
assert(row and #row.sell.offers==2 and #row.buy.offers==1)
local routes=M.arbitrage_filtered()
local sold=0
for _,route in ipairs(routes)do
 sold=sold+route.tradable_qty
 assert(route.qty_buyer==5)
end
assert(sold==5,'one buyer demand allocated more than once: '..sold)
local offer
for _,o in ipairs(row.sell.offers)do if tostring(o.shop)=='71' then offer=o end end
assert(offer and offer.qty==4)
DSP.live={shop={num='71',owner='Seller_A',server=102,menu_closed=0,scan_complete=true,
 items_updated=now,sell={{name='Firewood',ench=0,price=10,qty=45000,qty_known=true}},buy={}}}
local q,meta=M.offer_quantity(row,'sell',offer,now)
assert(q==45000 and meta.source=='game_observed' and meta.complete==false)
assert(offer.qty==4,'game observation must not corrupt original API quantity')
DSP.live.shop.owner='Wrong_Owner'
assert(M.offer_quantity(row,'sell',offer,now)==4,'incorrect stall owner was trusted')
DSP.live.shop.owner='Seller_A';DSP.live.shop.items_updated=now-91
assert(M.offer_quantity(row,'sell',offer,now)==4,'outdated game observation trusted')
DSP.shop_store={get_by_num=function(id,sid)
 if id==71 and sid==102 then
  return {owner='Seller_A',at=now,sell={{name='Firewood',ench=0,price=10,qty=45000,qty_known=true}}}
 end
end}
local nq,nmeta=M.offer_quantity(row,'sell',offer,now)
assert(nq==45000 and nmeta.source=='recent_scan','fresh local scan ignored')
DSP.shop_store.get_by_num=function()return {owner='wrong',at=now,sell={{name='Firewood',price=10,qty=50000,qty_known=true}}}end
assert(M.offer_quantity(row,'sell',offer,now)==4,'mismatched stored owner trusted')
print('PASS v2.8.5 shared demand and transient game/API quantity reconciliation')
