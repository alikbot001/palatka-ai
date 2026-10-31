-- Arbitrage assistant model tests: manual execution, local depletion,
-- receipt suggestions, server separation and duplicate prevention.
local path=os.tmpname()
os.remove(path)
_G.encodeJson=function(_)return '{"schema":1}'end
_G.decodeJson=function(_)return{}end
_G.DSP={
    dir='.',settings={tax_bp=200,server=102},
    market={state={sid=102,status='live',version=1}},
    craglog={log_market=function()return true end},
    lower=string.lower,
    ui={},ui22={},
    save_settings=function()return true end,
    flog=function()end,
}
local M=DSP.market
local changed=0
M.offer_quantity=function(_,_,offer) return offer.qty,{source='api',at=offer.ts}end
M.invalidate_arbitrage=function()changed=changed+1 end
local row={key='Super Car Box:0',display='Super Car Box',ench=0}
local seller={shop='154',owner='Seller',price=200000,qty=100,ts=1234}
local buyer={shop='281',owner='Buyer',price=260000,qty=100,ts=1234}
local route={row=row,name=row.display,sell_offer=seller,buy_offer=buyer,
    tradable_qty=100,p_buy=200000,p_sell=260000,net_profit=5480000}
M.arbitrage_grouped_ui=function()return{{routes={route}}},'ready'end
assert(dofile('src/69a_arbitrage_agent.lua')==true)
local A=DSP.arb_agent
A.path=path
local ok,n=A.start_market()
assert(ok and n==1)
assert(A.active()and#A.active().routes==1)
local e=A.active().routes[1]
assert(e.bought==0 and e.sold==0)
assert(M.offer_quantity(row,'sell',seller)==100)
assert(M.offer_quantity(row,'buy',buyer)==100)
-- Buying 40 reduces the seller but not the buyer.
assert(A.confirm(1,'buy',40))
assert(e.bought==40 and e.sold==0)
assert(M.offer_quantity(row,'sell',seller)==60)
assert(M.offer_quantity(row,'buy',buyer)==100)
-- Same quote is not added a second time by a periodic scan.
assert(A.start_market())
assert(#A.active().routes==1)
-- Selling cannot exceed actually bought quantity.
assert(not A.confirm(1,'sell',41))
assert(A.confirm(1,'sell',30))
assert(M.offer_quantity(row,'buy',buyer)==70)
assert(e.sold==30)
-- Complete both halves of the 100-piece route.
assert(A.confirm(1,'buy',60))
assert(A.confirm(1,'sell',70))
assert(e.bought==100 and e.sold==100)
local stats=A.stats()
assert(stats.done==1 and stats.routes==1 and stats.bought==100 and stats.sold==100)
assert(stats.profit_estimate>0)
assert(M.offer_quantity(row,'sell',seller)==0)
assert(M.offer_quantity(row,'buy',buyer)==0)
assert(#A.data.history==4)
-- Local depletion must not leak into another game server.
M.state.sid=103
assert(M.offer_quantity(row,'sell',seller)==100)
assert(A.active()==nil)
M.state.sid=102
-- Fresh confirmed game evidence outranks earlier manual reductions.
local q=A.remaining(row,'sell',seller,25,{source='game_observed',at=os.time()+10})
assert(q==25)
-- Receipt cues only suggest; they do not silently apply executions.
local buyer2={shop='450',owner='Other',price=280000,qty=10,ts=2234}
local seller2={shop='451',owner='Other',price=210000,qty=10,ts=2234}
local extra={row=row,name='Super Car Box',sell_offer=seller2,buy_offer=buyer2,
    tradable_qty=10,p_buy=210000,p_sell=280000,net_profit=600000}
assert(A.add_plan({routes={extra}}))
local new=A.active().routes[2]
assert(new.bought==0)
assert(A.observe_receipt('buy','Super Car Box',2100000))
assert(A.hint and A.hint.qty==10 and A.hint.index==2)
assert(new.bought==0)
assert(changed>=5)
-- A known-quantity live/local-scan route joins the same session.
local scanned={name='Ларец',id=321,ench=0,seller_shop=12,seller_owner='A',
    seller_at=os.time()-20,buyer_shop=14,buyer_owner='B',
    buyer_at=os.time()-20,buy_price=1000,sell_price=1500,
    qty=8,profit_total=3600}
local ok_local,n_local=A.add_local_route(scanned)
assert(ok_local and n_local==1)
local third=A.active().routes[3]
assert(third and third.name=='Ларец')
assert(A.confirm(3,'buy',8))
local before=A.remaining({key='321:0'},'sell',
    {shop=12,owner='A',price=1000,ts=scanned.seller_at},
    8,{source='recent_scan',at=scanned.seller_at})
assert(before==0)
assert(not A.confirm(3,'sell',9))
assert(A.confirm(3,'sell',8))
assert(A.stats().done==2)
assert(A.stop())
assert(A.active()==nil)
os.remove(path)
print('PASS multi-deal arbitrage assistant model')
