local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local path='mcr_copy/src/market.lua'
local M=assert(loadfile(path))()
local state=E.new()
local function offer(price,qty,variant)
 return{id='5',name='Item',price=price,qty=qty,variant=variant or'0:0',currency='SA$'}
end
assert(E.observe(state,{server='mobile2',shop=1,owner='A',at=1000,source='market-helper',
 sell={offer(100,2)},buy={offer(80,3)}}))
assert(E.observe(state,{server='mobile2',shop=2,owner='B',at=1000,source='local',
 sell={offer(200,1),offer(900,1,'7:0')},buy={}}))
assert(E.observe(state,{server='other',shop=3,at=1000,sell={offer(1,100)},buy={}}))
local shops=M.shops(state,'mobile2',1001,3600)
assert(#shops==2 and shops[1].shop==1)
local stats=M.prices(shops)
assert(#stats==2,'different item modifications merged')
local base
for _,r in ipairs(stats)do if r.variant=='0:0'then base=r end end
assert(base and base.sell.qty==3 and base.sell.avg==133 and base.buy.avg==80)
assert(base.sell.min==100 and base.sell.max==200)
assert(#M.shops(state,'mobile2',5001,3600)==0,'stale prices remain current')
assert(#M.shops(state,'mobile2',999,3600)==0,'future snapshots accepted')
local large={};for n=1,300 do large[n]=offer(n,1)end
assert(E.observe(E.new(),{server='mobile2',shop=1,at=1000,sell=large,buy={}}),
 'real public snapshot size (300 offers) rejected')
print('Independent shop list and asking-price statistics: OK')
