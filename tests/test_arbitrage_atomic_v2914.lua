-- A confirmed trade is an in-memory *and* durable transaction.
-- Failed disk writes must not reserve phantom stock or report success.
local temp=os.tmpname();os.remove(temp)
local fail=false
encodeJson=function()
    if fail then error('simulated disk/encode failure')end
    return '{"schema":1}'
end
decodeJson=function()return{}end
DSP={dir='.',settings={tax_bp=200,server=102},lower=string.lower,
    market={state={sid=102}},flog=function()end,
    save_settings=function()return true end}
DSP.market.offer_quantity=function(_,_,offer)return offer.qty,{source='api',at=offer.ts}end
DSP.market.invalidate_arbitrage=function()end
assert(dofile('src/69a_arbitrage_agent.lua'))
local A=DSP.arb_agent
A.path=temp
local row={key='crate:0',name='Crate',ench=0}
local ts=os.time()-10
local seller={shop='10',owner='Seller',price=50,qty=10,ts=ts}
local buyer={shop='11',owner='Buyer',price=90,qty=10,ts=ts}
assert(A.start({{row=row,name='Crate',tradable_qty=10,p_buy=50,p_sell=90,
    net_profit=382,sell_offer=seller,buy_offer=buyer}}))
local e=A.active().routes[1]
local revision=A.revision
fail=true
local ok,err=A.confirm(1,'buy',4)
assert(not ok and type(err)=='string','failed write reported successful trade')
assert(e.bought==0 and e.sold==0 and #A.data.history==0)
assert(next(A.data.consumed)==nil,'failed write reserved phantom demand/stock')
assert(A.revision==revision,'failed transaction changed in-memory revision')
assert(not A.skip(1,true),'skipped route reported success despite write failure')
assert(e.skipped==nil and A.revision==revision,'failed route skip mutated live session')
fail=false
assert(A.confirm(1,'buy',4))
assert(e.bought==4 and #A.data.history==1 and A.revision>revision)
local left=A.remaining(row,'sell',seller,10,{source='api',at=ts})
assert(left==6,'successful purchase did not reserve precisely four items')
assert(A.confirm(1,'sell',2))
assert(e.sold==2 and #A.data.history==2)
assert(A.skip(1,true)and e.skipped)
assert(A.skip(1,false)and not e.skipped)
os.remove(temp)
print('PASS arbitrage transactional confirm and skip rollback on failed persistence')
