-- An absence applies only to the right server/shop/quote; game verdicts are trusted.
local temp=os.tmpname();os.remove(temp)
_G.encodeJson=function()return '{"schema":1}'end
_G.decodeJson=function()return {}end
_G.DSP={dir='.',settings={server=102,tax_bp=200},lower=string.lower,
    market={state={sid=102,status='live',version=1}},craglog={log_market=function()return true end},
    save_settings=function()return true end,flog=function()end}
local M=DSP.market
local removed={}
M.mark_shop_missing=function(shop)removed[tostring(shop)]=true;return true end
M.mark_shop_missing_from_game=function(shop)removed[tostring(shop)]=true;return true end
M.restore_shop=function(shop)removed[tostring(shop)]=nil;return true end
M.offer_quantity=function(_,_,quote)return quote.qty,{source='api',at=quote.ts}end
M.invalidate_arbitrage=function()end
local row={key='crate:0',name='Crate',display='Crate',ench=0}
local timestamp=os.time()-20
local function make(sellshop,buyshop)
    return {row=row,name='Crate',tradable_qty=10,p_buy=100,p_sell=300,
        net_profit=1880,sell_offer={shop=sellshop,owner='Seller',price=100,qty=10,ts=timestamp},
        buy_offer={shop=buyshop,owner='Buyer',price=300,qty=10,ts=timestamp}}
end
local route1=make('10','20')
local route2=make('11','21')
assert(dofile('src/69a_arbitrage_agent.lua'))
assert(dofile('src/69c_arbitrage_status.lua'))
local A=DSP.arb_agent;A.path=temp
assert(A.start({route1,route2}))
assert(A.mark_unavailable(1,'item'))
assert(A.active().routes[1].unavailable_reason=='item_missing')
assert(A.active().routes[1].skipped)
assert(A.active().focus==1,'missing item keeps the same route visible until user moves on')
assert(DSP.settings.arb_agent_open==true,'missing item keeps mini-agent open')
assert(M.offer_quantity(row,'sell',route1.sell_offer)==0)
assert(M.offer_quantity(row,'sell',route2.sell_offer)==10)
assert(A.restore_unavailable(1))
assert(M.offer_quantity(row,'sell',route1.sell_offer)==10)
assert(A.mark_unavailable(2,'shop'))
assert(removed['11'])
assert(A.active().routes[2].unavailable_reason=='shop_missing')
assert(A.restore_unavailable(2))
assert(not removed['11'])
-- Trusted server response blocks every pending route using that shop.
assert(A.mark_unavailable(1,'item'))
assert(A.restore_unavailable(1))
assert(M.mark_shop_missing_from_game('10'))
assert(A.active().routes[1].unavailable_source=='game')
assert(A.active().routes[1].skipped)
assert(A.restore_unavailable(1))
-- A new confirmed shop owner blocks stale matching plan, but not other stalls.
DSP.live={shop={server=102,num='20',owner='Different',scan_complete=true,items_updated=os.time()}}
assert(A.confirm(1,'buy',10))
assert(A.observe_live_shop())
assert(A.active().routes[1].unavailable_reason=='owner_changed')
assert(A.active().routes[2].unavailable_reason==nil)
-- Item without positive complete evidence is never guessed absent automatically.
A.restore_unavailable(1)
DSP.live.shop.owner='Buyer'
DSP.live.shop.buy={}
assert(not A.observe_live_shop())
assert(A.active().routes[1].unavailable_reason==nil)
os.remove(temp)
print('PASS agent missing shop/item model')
