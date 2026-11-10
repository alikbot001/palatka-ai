local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local A=assert(loadfile('mcr_copy/src/app.lua'))()(E)
A.external=assert(loadfile('mcr_copy/src/external.lua'))()
local queue,requests,reply,poll,now={},0,nil,nil,1000
local data={has_more=false,shops={
 {server_id=102,shop_num=1,updated_at=1000,sell_slots={{item_id=5,name='Item',price=100,qty=100}}},
 {server_id=102,shop_num=2,updated_at=1000,buy_slots={{item_id=5,name='Item',price=103,qty=100}}}}}
A.install({server=function()return'102'end,market_server_id=function()return 102 end,
 now=function()return now end,currency=function()return'SA$'end,
 run=function(fn)queue[#queue+1]=fn end,yield=function()end,
 fetch_market=function(_,done)requests=requests+1;reply=done end,
 decode=function()return data end,encode=function()return'json'end,write=function()return true end,
 read=function()return nil end,register=function()end,open=function()end,open_main=function()end,
 poll_market=function(fn)poll=fn end})
local function drain()while #queue>0 do table.remove(queue,1)()end end
A.start();drain()
A.calculate();drain()
assert(requests==1,'calculation did not refresh live quotes')
reply('data');drain();assert(#A.results==1 and A.results[1].profit==94)
assert(type(poll)=='function','background refresh was not scheduled')
now=1121;data.shops[2].buy_slots[1].price=90;data.shops[2].updated_at=1121
poll();drain();reply('data');drain()
assert(#A.results==0,'background refresh left the old opportunity visible')
local before=requests
A.calculate(true);drain()
assert(requests==before+1,'explicit refresh reused cache instead of requesting quotes')
data.shops[2].buy_slots[1].price=150;reply('data');drain()
assert(#A.results==1,'manual refresh did not recalculate active arbitrage')
print('Calculate refreshes quotes; background changes recompute opportunities: OK')
