local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local f=io.open('mcr_copy/src/app.lua','rb');assert(f,'missing MCR source adapter');f:close()
local factory=assert(loadfile('mcr_copy/src/app.lua'))()
local disk,queue={},{}
local h={now=function()return 1000 end,server=function()return '102'end,
    fields={name='name',price='price',qty='count'},currency=function()return 'SA$'end,
    name=function(id)return 'Item '..id end,
    encode=function(v)disk.saved=v;return 'json'end,decode=function()return disk.saved end,
    read=function()return nil end,write=function(_,data)disk.data=data;return true end,
    run=function(fn)queue[#queue+1]=fn end,yield=function()end}
local registered,main_opened,arb_opened={},0,0
h.register=function(name,fn)assert(not registered[name],'duplicate command');registered[name]=fn end
h.open_main=function()main_opened=main_opened+1 end
h.open=function()arb_opened=arb_opened+1 end
local A=factory(E);A.install(h)
A.start();A.start()
assert(type(registered.crr)=='function','/crr was not registered')
registered.crr();assert(main_opened==1 and arb_opened==0,'/crr opened arbitrage instead of the main interface')
registered.parb();assert(arb_opened==1)

assert(A.capture({shop_num=1,owner='a',scanned_at=1000,
    sell_items={{item_id=5,name='Item',price=100,count=3}},buy_items={}}))
assert(A.capture({shop_num=2,owner='b',scanned_at=1000,
    sell_items={},buy_items={{item_id=5,name='Item',price=150,count=7}}}))
assert(A.selected==nil,'a route was selected without user action')
assert(not disk.data,'disk write happened during capture/render path')
A.calculate();assert(A.busy and #queue>0)
while #queue>0 do table.remove(queue,1)()end
assert(#A.results==1 and A.results[1].qty==3)
assert(A.select_route(1) and A.selected_route().id=='5')
local tracked
h.find=function(shop,server)tracked={shop,server}end
assert(A.track_selected('buy') and tracked[1]==1 and tracked[2]=='102')
assert(A.track_selected('sell') and tracked[1]==2)
assert(not A.track_selected('invalid'))
h.server_name=function()return 'gta-cache/v' end
assert(A.server_label()=='Текущий сервер','technical path leaked')
h.market_server_id=function()return 102 end
assert(A.server_label()=='Arizona Mobile 2')
assert(disk.data=='json','snapshots not saved by worker')
assert(not A.capture_external({shop={shop_id=3},items={}}),'unknown time accepted')
local ok=A.import({schema=1,shops={{server='102',shop=4,owner='ext',at=1000,
    sell={{id='5',variant='0:0',currency='SA$',price=90,qty=2,name='Item'}},buy={}}}})
assert(ok,'normalized external snapshot rejected')
A.calculate();h.server=function()return '103'end
while #queue>0 do table.remove(queue,1)()end
assert(#A.results==0,'old server calculation published')
assert(not A.track_selected('buy'),'stale selection can send a command')
h.server=function()return '102'end
h.write=function()return false,'disk full'end
A.dirty=true;assert(not A.flush());assert(A.dirty and A.error:find('disk full',1,true))
print('MCR adapters/persistence/cancellation: OK')
