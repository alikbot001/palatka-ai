local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local P=assert(loadfile('mcr_copy/src/purchases.lua'))()(E)
local D=assert(loadfile('mcr_copy/src/popularity.lua'))()(E)
local A=assert(loadfile('mcr_copy/src/app.lua'))()(E)
local captured
local R={rank=function(_,_,_,options)captured=options;return{}end}
assert(loadfile('mcr_copy/src/workspace.lua'))()(A,E,R,P,D)
local server,now,queue,callbacks,requests='102',10000,{},{},0
local function drain()while #queue>0 do table.remove(queue,1)()end end
A.install({server=function()return server end,currency=function()return'SA$'end,now=function()return now end,
 market_server_id=function()return tonumber(server)end,run=function(fn)queue[#queue+1]=fn end,
 unique_item=function(name)if name=='Coupon'then return'5'end end,
 fetch_popularity=function(sid,done)requests=requests+1;callbacks[#callbacks+1]={sid,done}end,
 yield=function()end,write=function()return true end,encode=function()return'json'end})
local key='5\31'..'0:0\31SA$'
local data={ok=true,items={{name='Coupon',qty_sold_30d=8892,avg=11000,updated_at=9000}}}
local done=0
A.refresh_popularity(function(ok)assert(ok);done=done+1 end)
A.refresh_popularity(function(ok)assert(ok);done=done+1 end)
drain();assert(requests==1,'concurrent demand requests not deduplicated')
callbacks[1][2](data);drain();assert(done==2)
A.compute();drain();assert(captured.market_sales[key].qty_30d==8892)
A.refresh_popularity(function(ok)assert(ok)end);drain();assert(requests==1,'demand cache ignored')
now=10901;A.refresh_popularity(function(ok)assert(not ok)end);drain();callbacks[2][2](nil,'offline')
A.compute();drain();assert(captured.market_sales[key]==nil,'expired history still influences ranking')
A.refresh_popularity(function(ok)assert(not ok)end,true);drain();server='103'
callbacks[3][2](data);drain();A.compute();drain()
assert(captured.market_sales[key]==nil,'late server history leaked into another server')
server='102';local cancelled=0
A.refresh_popularity(function(ok)assert(not ok);cancelled=cancelled+1 end,true)
server='103';drain()
assert(requests==3 and cancelled==1 and not A.demand_pending,'queued demand request switched its source server')
print('Monthly demand async cache, expiry, dedupe and server isolation: OK')
