-- Failure to persist an arb confirmation must not silently consume stock.
DSP={
  dir='.',
  settings={server=1,tax_bp=200,arb_agent_open=false},
  mobile={defer_save=function()end},
  lower=string.lower,
  market={state={sid=1,status='live',rows={}},
    invalidate_arbitrage=function()end},
  save_settings=function()return true end
}
assert(loadfile('src/69a_arbitrage_agent.lua'))()
local A=DSP.arb_agent
local save_ok=true
A.save=function()if save_ok then return true end return false,'disk full'end
local at=os.time()
local row={key='123:0',display='Test item',ench=0}
local sell={shop=101,owner='Seller',price=100,ts=at}
local buy={shop=202,owner='Buyer',price=200,ts=at}
local route={row=row,name='Test item',sell_offer=sell,buy_offer=buy,
  tradable_qty=4,p_buy=100,p_sell=200,net_profit=380}
assert(A.start({route}))
local e=A.get(1)
assert(e and e.qty==4)
save_ok=false
local ok,why=A.confirm(1,'buy',2)
assert(not ok and tostring(why):find('сохранить',1,true))
assert(e.bought==0 and e.sold==0)
assert(A.data.consumed[e.seller_quote]==nil)
assert(#A.data.history==0)
save_ok=true
assert(A.confirm(1,'buy',3))
assert(e.bought==3)
assert(A.data.consumed[e.seller_quote].qty==3)
save_ok=false
assert(not A.confirm(1,'sell',2))
assert(e.sold==0)
assert(A.data.consumed[e.buyer_quote]==nil)
assert(#A.data.history==1)
save_ok=true
assert(A.confirm(1,'sell',2))
assert(e.sold==2 and A.stats().sold==2)
assert(#A.data.history==2)
assert(not A.confirm(1,'sell',5))
print('2.9.7 agent: persistent confirmations and in-memory rollback ok')
