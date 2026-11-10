local load=loadfile('mcr_copy/src/purchases.lua')
assert(load,'missing immutable purchase ledger')
local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local P=load()(E)
local MAX=9007199254740991
local function copy(t)
    if type(t)~='table' then return t end
    local out={};for k,v in pairs(t)do out[k]=copy(v)end;return out
end
local function same(a,b)
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not same(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function buy(s,changes)
    local v={server='102',currency='SA$',name='Item',item_id='5',variant='0',unit_cost=100,qty=5,at=1000,note='bought'}
    for k,x in pairs(changes or{})do
        if x==false and (k=='item_id' or k=='variant')then v[k]=nil else v[k]=x end
    end
    local n,l=P.buy(s,v);assert(n,l);return n,l
end
local function reject(operation,state,...)
    local old=copy(state);local n,e=operation(state,...)
    assert(n==nil and type(e)=='string','invalid operation accepted')
    assert(same(old,state),'failed operation mutated state')
end
local empty=P.new();local state,lot=buy(empty)
assert(#empty.lots==0 and empty.next_id==1,'buy mutated old state')
local before=copy(state)
local sold,sale=P.sell(state,lot.id,{qty=2,net_total=350,at=1100,note='actual net'})
assert(sold,sale)
assert(same(before,state) and sold.lots[1].remaining==3,'partial sale mutated purchase')
assert(sale.cost==200 and sale.profit==150 and sale.net_total==350,'actual net was taxed/estimated')
local view=P.view(sold,'102','SA$')
assert(view.invested==300 and view.realized_profit==150 and view.sold_qty==2)
local packed=copy(sold);local loaded,err=P.validate(packed);assert(loaded,err)
assert(same(loaded,sold),'validated roundtrip changed ledger')
loaded.lots[1].note='changed';assert(packed.lots[1].note=='bought','validate aliases input')
view.lots[1].note='changed';assert(sold.lots[1].note=='bought','view aliases state')
sale.note='changed';lot.note='changed'
assert(sold.sales[1].note=='actual net' and state.lots[1].note=='bought','operation aliases returned record')
local closed,full=P.sell(sold,1,{qty=3,net_total=250,at=1200})
assert(closed,full);view=P.view(closed,'102','SA$')
assert(view.invested==0 and view.realized_profit==100 and view.sold_qty==5)
reject(P.sell,closed,1,{qty=1,net_total=1,at=1300})
reject(P.sell,sold,1,{qty=4,net_total=1,at=1300})
reject(P.sell,sold,999,{qty=1,net_total=1,at=1300})
reject(P.sell,sold,1,{qty=1,net_total=0,at=999})
reject(P.sell,sold,1,{qty=1,net_total=MAX+1,at=1300})
reject(P.sell,sold,1,{qty=0,net_total=1,at=1300})
local free=buy(P.new(),{unit_cost=0,qty=1})
local free_sale,record=P.sell(free,1,{qty=1,net_total=0,at=1000})
assert(free_sale and record.cost==0 and record.profit==0,'explicit zero cost/net rejected')
local missing={server='102',currency='SA$',name='Item',qty=1,at=1000}
reject(P.buy,P.new(),missing)
for _,field in ipairs({'unit_cost','qty','at'})do
    for _,bad in ipairs({-1,0/0,math.huge,1.5,'1',false,MAX+1})do
        local input=copy(missing);input.unit_cost=1;input[field]=bad;reject(P.buy,P.new(),input)
    end
end
reject(P.buy,P.new(),{server='102',currency='SA$',name='Item',unit_cost=MAX,qty=2,at=1000})
local boundary=buy(P.new(),{unit_cost=MAX,qty=1})
local boundary_sale,boundary_record=P.sell(boundary,1,{qty=1,net_total=0,at=1100})
assert(boundary_sale and boundary_record.profit==-MAX,'safe signed loss rejected')
assert(P.validate(boundary_sale),'safe integer boundary cannot roundtrip')
local normalized=buy(P.new(),{item_id=5,variant=0})
assert(normalized.lots[1].item_id=='5' and normalized.lots[1].variant=='0','numeric identity is not canonical')
local multi=buy(closed,{server='103',qty=1,at=1300})
multi=buy(multi,{currency='BTC',qty=1,at=1400})
multi=buy(multi,{variant='1',qty=1,at=1500})
view=P.view(multi,'102','SA$')
assert(#view.lots==2 and view.lots[1].at==1500 and view.lots[2].remaining==0,'scope/sort incorrect')
assert(view.invested==100 and view.realized_profit==100 and view.sold_qty==5)
assert(P.view(multi,'103','SA$').invested==100 and P.view(multi,'102','BTC').invested==100)
assert(P.view(multi,'absent','SA$').invested==0)
local corruptions={
    function(p)p.schema=2 end,
    function(p)p.next_id=p.next_id+1 end,
    function(p)p.lots[3]=p.lots[1];p.lots[1]=nil end,
    function(p)p.sales[2]=p.sales[1] end,
    function(p)p.sales[1].cost=199 end,
    function(p)p.sales[1].profit=151 end,
    function(p)p.lots[1].remaining=4 end,
    function(p)p.sales[1].lot_id=999 end,
    function(p)p.sales[1].id=p.lots[1].id end,
    function(p)p.sales[1].at=999 end,
    function(p)p.lots[1].unit_cost='100' end,
    function(p)p.lots[1].qty=0/0 end,
    function(p)p.sales.extra={} end,
    function(p)p.secret='unrecognized schema field' end,
    function(p)p.lots[1].unexpected=true end,
    function(p)p.sales[1].qty=6 end,
}
for _,mutate in ipairs(corruptions)do
    local p=copy(sold);mutate(p);local original=copy(p)
    local validated,error=P.validate(p)
    assert(validated==nil and type(error)=='string','corrupt pack accepted')
    -- NaN is intentionally unequal to itself, so compare all other corruptions.
    if p.lots[1] and p.lots[1].qty==p.lots[1].qty then assert(same(original,p),'validate mutated corrupt pack')end
end
for _,p in ipairs({false,1,'bad',{schema=1,next_id=1,lots={},sales={bad=true}}})do
    assert(P.validate(p)==nil,'invalid pack reset silently')
end
local overflow=buy(boundary,{unit_cost=1,qty=1})
local bad_view,view_error=P.view(overflow,'102','SA$')
assert(bad_view.error and view_error and bad_view.invested==nil and bad_view.realized_profit==nil,'partial totals exposed after overflow')
local profits=buy(P.new(),{unit_cost=0,qty=1})
profits=assert(P.sell(profits,1,{qty=1,net_total=MAX,at=1100}))
local profits_lot;profits,profits_lot=buy(profits,{unit_cost=0,qty=1})
profits=assert(P.sell(profits,profits_lot.id,{qty=1,net_total=1,at=1100}))
assert(P.view(profits,'102','SA$').error,'profit aggregation overflow accepted')
local quantity=buy(P.new(),{unit_cost=0,qty=MAX})
quantity=assert(P.sell(quantity,1,{qty=MAX,net_total=1,at=1100}))
local extra;quantity,extra=buy(quantity,{unit_cost=0,qty=1})
quantity=assert(P.sell(quantity,extra.id,{qty=1,net_total=1,at=1100}))
assert(P.view(quantity,'102','SA$').error,'quantity aggregation overflow accepted')
local overflow_evidence,evidence_error=P.evidence(quantity,'102','SA$',1100)
assert(next(overflow_evidence)==nil and evidence_error,'partial own evidence exposed after quantity overflow')
local now=700000;local evidence_state=P.new()
local function sale_at(changes,at,qty)
    local l;evidence_state,l=buy(evidence_state,changes)
    evidence_state=assert(P.sell(evidence_state,l.id,{qty=qty or 1,net_total=150,at=at}))
end
sale_at({},now-604800,2);sale_at({},now,1)
sale_at({},now-604801,1);sale_at({},now+1,1)
sale_at({variant='1'},now,1);sale_at({server='103'},now,1);sale_at({currency='BTC'},now,1)
sale_at({item_id=false,variant=false},now,1)
sale_at({variant=false},now,1);sale_at({item_id=false},now,1)
local own=P.evidence(evidence_state,'102','SA$',now)
assert(own['5\0310\031SA$'].events==2 and own['5\0310\031SA$'].qty==3 and own['5\0310\031SA$'].last_at==now,'7-day evidence incorrect')
assert(own['5\0310\031SA$'].valid_until==now,'evidence expiry ignores oldest contributing sale')
assert(own['5\0311\031SA$'].qty==1 and own['5\0310\031BTC']==nil,'evidence identity leaked')
local count=0;for _ in pairs(own)do count=count+1 end;assert(count==2,'manual identity fabricated')
local capacity=P.new()
for i=1,500 do capacity=buy(capacity,{qty=1})end
reject(P.buy,capacity,{server='102',currency='SA$',name='extra',unit_cost=0,qty=1,at=1000})
assert(#capacity.lots==500,'capacity eviction')
local sales_capacity=buy(P.new(),{qty=2001,unit_cost=0})
for i=1,2000 do sales_capacity=assert(P.sell(sales_capacity,1,{qty=1,net_total=0,at=1000}))end
reject(P.sell,sales_capacity,1,{qty=1,net_total=0,at=1000})
assert(#sales_capacity.sales==2000 and sales_capacity.lots[1].remaining==1,'sale cap evicted evidence')
local gifts=P.new()
gifts=assert(P.buy(gifts,{server='102',currency='SA$',name='Gift',item_id='5',variant='0:0',unit_cost=0,qty=30,at=1000}))
for n=1,3 do gifts=assert(P.sell(gifts,1,{qty=10,net_total=0,at=1000+n}))end
assert(next(P.evidence(gifts,'102','SA$',1100))==nil,'free transfers counted as paid demand')
print('MCR immutable purchase ledger: OK')
