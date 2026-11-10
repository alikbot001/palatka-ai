local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local make=assert(loadfile('mcr_copy/src/app.lua'))()
local extend=assert(loadfile('mcr_copy/src/workspace.lua'))()
-- Strict stand-ins isolate the orchestration, not resale/ledger mathematics.
local resale_calls=0
local R={rank=function(_,server,now,options,yield)
 resale_calls=resale_calls+1;assert(server=='102'and options.currency=='SA$')
 if yield and yield()==false then return{},'cancelled'end
 return{{id='5',variant='0:0',currency='SA$',name='Item',qty=1,seller={server=server,shop=1,at=now},
  buy_price=100,sell_price=150,cost=100,gross=150,net=147,fee=3,profit=47,roi_bp=4700,
  reference_price=151,peer_count=3,popularity={kind='buy_orders',buyer_shops=2,buyer_qty=30}}}
end}
local P={new=function()return{schema=1,next_id=1,lots={},sales={}}end,
 validate=function(pack)if pack.schema~=1 then return nil,'bad ledger'end;return pack end,
 buy=function(state,p)
  local next={schema=1,next_id=2,lots={{id=1,server=p.server,currency=p.currency,name=p.name,
   unit_cost=p.unit_cost,qty=p.qty,remaining=p.qty,at=p.at,note=p.note}},sales={}}
  return next,next.lots[1]
 end,
 sell=function(state,id,p)return nil,'sale rejected'end,
 view=function(state)return{lots=state.lots,invested=0,realized_profit=0,sold_qty=0}end,
 evidence=function()return{}end}
local queue,server,now={},'102',1000
local disk,write_ok,write_throws,read_error,encoded={},true,false,nil,nil
local A=make(E);extend(A,E,R,P)
local function drain()while #queue>0 do table.remove(queue,1)()end end
A.install({server=function()return server end,currency=function()return'SA$'end,now=function()return now end,
 run=function(fn)queue[#queue+1]=fn end,yield=function()end,
 read=function(name)return disk[name],read_error end,
 decode=function(raw)if raw=='corrupt'then error('bad json')end;return raw end,
 encode=function(pack)encoded=pack;return pack end,
 write=function(name,raw)if write_throws then error('write exception')end;if not write_ok then return false,'disk full'end;disk[name]=raw;return true end,
 find=function()end})
A.load();assert(A.book_loaded and not A.book_error)
local finished=0
local p={name='Item',unit_cost=100,qty=3,note='manual'}
write_ok=false
assert(A.record_purchase(p,function(ok)finished=finished+1;assert(not ok)end))
assert(A.book_busy and #A.purchase_state.lots==0)
assert(not A.record_purchase(p,function()error('duplicate callback')end),'busy accepted duplicate write')
drain();assert(finished==1 and #A.purchase_state.lots==0 and not A.book_busy)
write_throws=true
assert(A.record_purchase(p,function(ok)assert(not ok)end));drain()
assert(not A.book_busy and #A.purchase_state.lots==0,'write exception stuck or published ledger')
write_throws=false
write_ok=true
assert(A.record_purchase(p,function(ok)assert(ok);finished=finished+1 end));drain()
assert(finished==2 and #A.purchase_state.lots==1 and disk['purchases.json'])
local old=A.purchase_state
assert(A.record_sale(1,{qty=4,net_total=10},function(ok)assert(not ok)end));drain()
assert(A.purchase_state==old,'rejected sale changed ledger')
assert(A.record_purchase(p,function(ok)assert(not ok)end));server='103';drain()
assert(A.purchase_state==old,'server change wrote a purchase to the wrong server')
server='102'
local restart=make(E);extend(restart,E,R,P);restart.install(A.host);restart.load()
assert(#restart.purchase_state.lots==1,'purchase was lost on restart')
disk['purchases.json']='corrupt';restart.load_book()
assert(restart.book_error and not restart.book_loaded)
assert(not restart.record_purchase(p,function()end),'corrupt ledger was overwritten')
disk['purchases.json']=nil;read_error='permission denied';restart.load_book()
assert(restart.book_error and not restart.book_loaded,'read error treated as empty ledger')
read_error=nil
-- Both analyzers run outside rendering and reject obsolete output.
A.compute();assert(resale_calls==0);drain()
assert(resale_calls==1 and #A.current_resale()==1)
now=5001;assert(#A.current_resale()==0,'expired resale stayed current');now=1000
A.compute();A.invalidate();drain();assert(#A.current_resale()==0,'cancelled resale published late')
A.compute();server='103';drain();assert(#A.current_resale()==0,'other server resale published')
assert(not A.resale_busy,'server change left resale permanently busy')
print('Workspace async resale, safe purchase persistence, restart and failure isolation: OK')
