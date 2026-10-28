-- Game packet vs API vs manual confirmation; never mistake one slot for stock.
package.preload.encoding=function()return {UTF8={decode=function(_,x)return x end,encode=function(_,x)return x end}} end
getWorkingDirectory=function()return '/tmp/palatka_qty_sources' end
doesDirectoryExist=function()return true end
createDirectory=function()end
encodeJson=function()return '{}'end
decodeJson=function()return {}end
dofile('src/00_core.lua')
dofile('src/05_items.lua')
dofile('src/10_market.lua')
dofile('src/11_arbitrage.lua')
dofile('src/12_arbitrage_groups.lua')
DSP.settings.server=102
local now=os.time()
DSP.market.rebuild({shops={{server_id=102,shop_num=71,owner='Wood_Trader',updated_at=now,
 sell_slots={{name='Firewood',price=10,qty=1}},buy_slots={{name='Firewood',price=20,qty=1}}}}},102)
local row=DSP.market.state.by_key[DSP.item_key('Firewood',0)]
assert(row,'fixture API offer missing')
local sell,buy=row.sell.offers[1],row.buy.offers[1]
local function live(num,owner,sid,price,qty,known)
 DSP.live={shop={num=tostring(num),owner=owner,server=sid,menu_closed=0,items_updated=now,
 sell={{name='Firewood',ench=0,price=price,qty=qty,qty_known=known}},buy={}}}
end
live(71,'Wood_Trader',102,10,45000,true)
local observed,meta=DSP.market.live_offer_quantity(row,'sell',sell)
assert(observed==45000 and meta.source=='game','game count should be 45000 not 1')
assert(DSP.market.quantity_info(row,'sell',sell).disagreement,'must expose API/game disagreement')
assert(sell.qty==1 and row.sell.qty==1,'observation must not silently edit API')
local ok=DSP.market.confirm_offer_quantity(row,'sell',sell,observed,'game')
assert(ok and sell.qty==45000 and sell.snapshot_qty==1 and sell.qty_source=='game','explicit game count confirmation')
assert(row.sell.qty==45000,'row total did not reflect verified count')
assert(DSP.market.quantity_info(row,'sell',sell).api==1,'original API value lost')
assert(DSP.market.format_units(45000)=='45 000','quantity grouping')
live(71,'Wrong_Owner',102,10,50000,true)
assert(DSP.market.live_offer_quantity(row,'sell',sell)==nil,'mismatched owner trusted')
local trusted_before=sell.qty
local accepted,reason=DSP.market.confirm_offer_quantity(row,'sell',sell,50000,'game')
assert(not accepted and tostring(reason):find('игровое',1,true),'stale game confirmation was accepted')
assert(sell.qty==trusted_before and sell.qty_source=='game','rejected confirmation mutated quantity')
live(72,'Wood_Trader',102,10,50000,true)
assert(DSP.market.live_offer_quantity(row,'sell',sell)==nil,'mismatched stall trusted')
live(71,'Wood_Trader',103,10,50000,true)
assert(DSP.market.live_offer_quantity(row,'sell',sell)==nil,'cross-server leak')
live(71,'Wood_Trader',102,11,50000,true)
assert(DSP.market.live_offer_quantity(row,'sell',sell)==nil,'mismatched price trusted')
live(71,'Wood_Trader',102,10,nil,false)
assert(DSP.market.live_offer_quantity(row,'sell',sell)==nil,'unknown game quantity trusted')
live(71,'Wood_Trader',102,10,45000,true)
DSP.live.shop.menu_closed=os.time()
assert(DSP.market.live_offer_quantity(row,'sell',sell)==nil,'closed stall treated as live')
DSP.live.shop.menu_closed=0
DSP.live.shop.items_updated=now-121
assert(DSP.market.live_offer_quantity(row,'sell',sell)==nil,'stale game observation trusted')
DSP.market.rebuild({shops={{server_id=102,shop_num=71,owner='Wood_Trader',updated_at=now,
 sell_slots={{name='Firewood',price=10,qty=1}},buy_slots={{name='Firewood',price=20,qty=1}}}}},102)
row=DSP.market.state.by_key[DSP.item_key('Firewood',0)]
assert(row.sell.offers[1].qty==1 and not row.sell.offers[1].verified_at,'old verification leaked into new API snapshot')
-- Market Helper publishes qty=1 for one shop slot without its actual stack;
-- the parser must require explicit qty/count/label, never invent one.
DSP.items.by_id[135]='Firewood'
DSP.live={shop={}}
dofile('src/45_live.lua')
local L=DSP.live
DSP.db={learn=function()return true end}
L.reset_shop('Wood_Trader',71)
L.handle(60,0,'{"type":13,"slot":1,"item":135,"amount":10}')
assert(L.shop.sell[1].qty==nil and L.shop.sell[1].qty_known==false,'unknown game quantity became 1')
L.handle(60,0,'{"type":13,"slot":1,"item":135,"amount":10,"qty":45000}')
assert(L.shop.sell[1].qty==45000 and L.shop.sell[1].qty_known,'explicit game count missing')
L.handle(60,0,'{"type":13,"slot":1,"item":135,"amount":10,"text":"45000 шт."}')
assert(L.shop.sell[1].qty==45000,'explicit qty in text not detected')
L.handle(60,0,'{"type":13,"slot":1,"item":135,"amount":10,"text":"45 000 шт."}')
assert(L.shop.sell[1].qty==45000,'grouped qty in text not detected')
L.handle(60,0,'{"type":13,"slot":1,"item":135,"amount":10,"text":"45.000 шт."}')
assert(L.shop.sell[1].qty==45000,'dot separated qty in text not detected')
print('quantity provenance: API slot=1, game 45000, explicit consent, scope/freshness, parser: OK')
