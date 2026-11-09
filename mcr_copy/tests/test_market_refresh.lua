local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local A=assert(loadfile('mcr_copy/src/app.lua'))()(E)
A.external=assert(loadfile('mcr_copy/src/external.lua'))()
local queue,reply={},nil
local server,requests,callbacks='mobile2',0,0
local payload={shops={{server_id=102,shop_num=1,updated_at=1000,
 sell_slots={{item_id=5,name='Item',price=100,qty=2}}}}}
A.install({server=function()return server end,market_server_id=function()return 102 end,
 now=function()return 1000 end,currency=function()return'SA$'end,
 run=function(fn)queue[#queue+1]=fn end,
 decode=function(raw)assert(raw=='json');return payload end,
 encode=function()return'json'end,write=function()return true end,
 fetch_market=function(sid,done)assert(sid==102);requests=requests+1;reply=done end})
local function drain()while #queue>0 do table.remove(queue,1)()end end
local function ok(success)assert(success);callbacks=callbacks+1 end
A.refresh_market(ok);A.refresh_market(ok)
assert(requests==0,'network started inside render path');drain()
assert(requests==1,'concurrent native views duplicated request')
reply('json');drain();assert(callbacks==2 and A.state.revision==1)
A.refresh_market(ok);drain();assert(requests==1 and callbacks==3,'cache ignored')
local revision=A.state.revision
A.refresh_market(function(success)assert(not success)end,true);drain()
reply(nil,'network unavailable');drain();assert(A.state.revision==revision,'network failure erased cache')
A.refresh_market(function(success)assert(not success)end,true);drain()
server='mobile3';reply('json');drain()
assert(A.state.revision==revision,'late response contaminated new server')
print('Public market refresh/cache/failure/server isolation: OK')
