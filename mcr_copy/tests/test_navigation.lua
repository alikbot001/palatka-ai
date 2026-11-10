local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local make=assert(loadfile('mcr_copy/src/app.lua'))()
local navigation=assert(loadfile('mcr_copy/src/navigation.lua'))()
local A=make(E)
navigation(A)
local server,clock='mobile2',1000
local sends,callbacks,forced,notifications={},{},{},{}
local host={server=function()return server end,now=function()return clock end,
 notify=function(message)notifications[#notifications+1]=message end,
 find=function(number,sid)sends[#sends+1]={number=number,server=sid}end}
A.install(host)
local function navigate(number,sid,owner)return A.navigate(number,owner or'Owner_A',sid)end
A.refresh_market=function(done,force)
 callbacks[#callbacks+1]=done;forced[#forced+1]=force
end
local function observed(owner,at)
 assert(E.observe(A.state,{server='mobile2',shop=74,owner=owner,at=at or clock,
  source='market-helper',sell={},buy={}}))
end
local function complete(index,ok,err,receipt)
 if receipt==nil then
  receipt={schema=1,shops={}}
  for _,shop in pairs(A.state.shops)do receipt.shops[#receipt.shops+1]=shop end
 end
 callbacks[index](ok,err,receipt)
end
local function reset()
 server='mobile2';clock=1000;sends={};callbacks={};forced={};notifications={};A.state=E.new();observed('Owner_A')
end
reset()
navigate(74,'mobile2','Owner_A')
assert(#sends==0,'native find sent command before refreshing owner')
assert(#callbacks==1 and forced[1]==true,'navigation did not force a fresh public request')
observed('Owner_B',1001);clock=1001;complete(1,true)
assert(#sends==0 and A.error:find('владелец',1,true),'owner replacement did not abort navigation')
assert(#notifications>0 and notifications[#notifications]:find('владелец',1,true),'native owner mismatch failure was silent')

reset();navigate(74,'mobile2','Owner_A');complete(1,true)
assert(#sends==1 and sends[1].number==74 and sends[1].server=='mobile2','same shop did not navigate')
complete(1,true);assert(#sends==1,'duplicate completion sent command twice')

reset();navigate(74,'mobile2','Old_Label')
assert(#sends==0 and #callbacks==0,'stale visible owner was silently replaced with cached owner')
reset();navigate(74,'mobile2','Owner_A');complete(1,false,'offline')
assert(#sends==0 and A.error:find('offline',1,true),'network failure navigated from cache')
assert(notifications[#notifications]:find('offline',1,true),'native network failure was silent')
reset();navigate(74,'mobile2');A.state=E.new();complete(1,true)
assert(#sends==0,'disappeared shop still navigated')
reset();navigate(74,'mobile2');server='mobile3';complete(1,true)
assert(#sends==0,'reconnect navigated using old-server quote')
reset();navigate(74,'mobile3');assert(#sends==0 and #callbacks==0,'foreign server accepted')
reset();navigate(74,'mobile2');clock=4601;complete(1,true)
assert(#sends==0,'expired snapshot navigated after refresh')
reset();clock=4601;navigate(74,'mobile2');assert(#callbacks==0,'expired click was accepted')
reset();observed('',1001);clock=1001;navigate(74,'mobile2')
assert(#callbacks==0 and #sends==0,'unknown owner was accepted')
reset();clock=999;navigate(74,'mobile2');assert(#callbacks==0,'future snapshot was accepted')
reset();navigate(74,'mobile2');navigate(74,'mobile2')
assert(#callbacks==1,'repeated touch started duplicate navigation')
complete(1,true);assert(#sends==1,'repeated touch sent duplicate commands')
navigate(74,'mobile2');assert(#callbacks==2,'completed navigation left the guard locked')
complete(2,true);assert(#sends==2,'second deliberate navigation failed')
reset();navigate(74,'mobile2','owner_a');complete(1,true)
assert(#sends==1,'nickname comparison unexpectedly became case sensitive')
reset();navigate('bad','mobile2');assert(#sends==0 and #callbacks==0,'invalid shop number accepted')
reset();A.navigate(74,nil,'mobile2');assert(#callbacks==0,'missing visible owner was accepted')
reset();assert(A.navigate({shop=74,owner='Owner_A',server='mobile2'}))
complete(1,true);assert(#sends==1,'route object did not navigate')
reset();navigate(74,'mobile2');callbacks[1](true)
assert(#sends==0,'successful refresh without a response receipt trusted retained cache')
local function rejected_receipt(receipt,label)
 reset();navigate(74,'mobile2');complete(1,true,nil,receipt)
 assert(#sends==0,label..' response receipt trusted retained cache')
end
rejected_receipt({schema=1,shops={}},'omitted shop')
rejected_receipt({schema=2,shops={{server='mobile2',shop=74,owner='Owner_A',at=1000}}},'invalid schema')
rejected_receipt({schema=1,shops={{server='mobile3',shop=74,owner='Owner_A',at=1000}}},'foreign server')
rejected_receipt({schema=1,shops={{server='mobile2',shop=75,owner='Owner_A',at=1000}}},'wrong shop')
rejected_receipt({schema=1,shops={{server='mobile2',shop=74,owner='Owner_B',at=1000}}},'changed owner')
rejected_receipt({schema=1,shops={{server='mobile2',shop=74,owner='Owner_A',at=1000,owner_conflict=true}}},'owner conflict')
rejected_receipt({schema=1,shops={{server='mobile2',shop=74,owner='Owner_A',at=1001}}},'future scan')
rejected_receipt({schema=1,shops={{server='mobile2',shop=74,owner='Owner_A',at=-3000}}},'stale scan')
-- A rejected row can leave its older snapshot in persistent state. Only the
-- normalized response, rather than this retained cache, proves refresh identity.
local real=make(E)
real.external=assert(loadfile('mcr_copy/src/external.lua'))()
navigation(real)
local queue,commands={},0
local payload={ok=true,has_more=false,shops={
 {server_id=102,shop_num=74,owner='Owner_B',scanned_at=1001,
  sell_slots={{item_id=5,name='Invalid',qty=1,price=0}}},
 {server_id=102,shop_num=75,owner='Other',scanned_at=1001,
  sell_slots={{item_id=5,name='Valid',qty=1,price=100}}}}}
real.install({server=function()return'mobile2'end,market_server_id=function()return 102 end,
 currency=function()return'SA$'end,now=function()return 1001 end,
 run=function(fn)queue[#queue+1]=fn end,decode=function()return payload end,
 encode=function()return'{}'end,write=function()return true end,
 fetch_market=function(_,done)done('{}')end,find=function()commands=commands+1 end})
assert(E.observe(real.state,{server='mobile2',shop=74,owner='Owner_A',at=1000,
 source='market-helper',sell={},buy={}}))
assert(real.navigate(74,'Owner_A','mobile2'))
while #queue>0 do table.remove(queue,1)()end
assert(real.state.shops['mobile2/74'].owner=='Owner_A','retained-cache regression setup changed')
assert(commands==0,'rejected new owner row reused retained old owner for navigation')
assert(real.error and real.error:find('не подтвердил',1,true),'omitted normalized identity was not reported')
payload.shops[1].owner='Owner_A';payload.shops[1].sell_slots[1].price=100
assert(real.navigate(74,'Owner_A','mobile2'))
while #queue>0 do table.remove(queue,1)()end
assert(commands==1,'actual refresh did not forward its normalized identity receipt')
print('Navigation: forced refresh, owner changes, stale UI, reconnect, expiry and response identity receipts: OK')
