local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local P=assert(loadfile('mcr_copy/src/purchases.lua'))()(E)
local make=assert(loadfile('mcr_copy/src/app.lua'))()
local extend=assert(loadfile('mcr_copy/src/workspace.lua'))()
local A=make(E);extend(A,E,{rank=function()return{}end},P)
local disk,queue={},{}
local h={server=function()return'102'end,currency=function()return'SA$'end,now=function()return 1000 end,
 run=function(fn)queue[#queue+1]=fn end,read=function(name)return disk[name]end,
 encode=function(pack)return pack end,decode=function(raw)return raw end,
 write=function(name,raw)disk[name]=raw;return true end}
local function drain()while #queue>0 do table.remove(queue,1)()end end
A.install(h);A.load_book()
assert(A.record_purchase({name='Coupon',item_id='5',variant='0:0',unit_cost=10000,qty=10},function(ok)assert(ok)end));drain()
assert(A.record_sale(1,{qty=3,net_total=45000},function(ok,why)assert(ok,why)end));drain()
assert(A.purchase_state.lots[1].remaining==7)
local view=P.view(A.purchase_state,'102','SA$')
assert(view.invested==70000 and view.realized_profit==15000 and view.sold_qty==3)
local restarted=make(E);extend(restarted,E,{},P);restarted.install(h);assert(restarted.load_book())
assert(restarted.purchase_state.lots[1].remaining==7 and #restarted.purchase_state.sales==1)
assert(A.record_purchase({name='Other',unit_cost=100,qty=1},function(ok)assert(not ok)end))
disk['purchases.json']='corrupt';assert(not A.load_book());drain()
assert(disk['purchases.json']=='corrupt','queued save overwrote a ledger after failed reload')
print('Real ledger/runtime purchase -> partial sale -> restart roundtrip: OK')
