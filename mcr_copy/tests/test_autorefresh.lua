-- Execute the actual MonetLoader polling host with a virtual clock/coroutine.
do
 local captured,thread,ticks
 ticks=0
 local env=setmetatable({getWorkingDirectory=function()return'.'end,F3={},T={},NeomText={},
  PalatkaMCR={install=function(host)captured=host end},
  lua_thread={create=function(fn)thread=coroutine.create(fn)end},
  wait=function(ms)coroutine.yield(ms)end},{__index=_G})
 local host=assert(loadfile('mcr_copy/src/host.lua'));setfenv(host,env);host()
 captured.poll_market(function()ticks=ticks+1 end)
 local ok,delay=coroutine.resume(thread);assert(ok and delay==2000 and ticks==0)
 ok,delay=coroutine.resume(thread)
 assert(ok and delay==60000 and ticks==1,'native polling timer is not one minute')
 ok,delay=coroutine.resume(thread)
 assert(ok and delay==60000 and ticks==2,'native polling stopped after the first refresh')
end
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
now=1001;reply('data');drain();assert(#A.results==1 and A.results[1].profit==94)
assert(type(poll)=='function','background refresh was not scheduled')
now=1059;A.refresh_market(function(ok)assert(ok)end);drain()
assert(requests==1,'fresh quotes were fetched again before one minute')
now=1060;data.shops[2].buy_slots[1].price=90;data.shops[2].updated_at=1060
poll();drain();assert(requests==2,'one-minute refresh was blocked by the old cache')
poll();drain();assert(requests==2,'pending minute refresh duplicated the public request')
reply('data');drain()
assert(#A.results==0,'background refresh left the old opportunity visible')
local before=requests
A.calculate(true);drain()
assert(requests==before+1,'explicit refresh reused cache instead of requesting quotes')
data.shops[2].buy_slots[1].price=150;reply('data');drain()
assert(#A.results==1,'manual refresh did not recalculate active arbitrage')
print('Calculate refreshes quotes; background changes recompute opportunities: OK')
