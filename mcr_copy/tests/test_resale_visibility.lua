local E=dofile('mcr_copy/src/engine.lua')
local R=dofile('mcr_copy/src/resale.lua')(E)
local P=dofile('mcr_copy/src/purchases.lua')(E)
local failures={}
local function scenario(name,fn)
 local ok,why=pcall(fn);if not ok then failures[#failures+1]=name..': '..tostring(why)end
end
local function fixture()
 local A=dofile('mcr_copy/src/app.lua')(E);dofile('mcr_copy/src/workspace.lua')(A,E,R,P)
 local queue,now,tracked={},1000,nil
 A.install({server=function()return'102'end,currency=function()return'SA$'end,now=function()return now end,
 run=function(fn)queue[#queue+1]=fn end,yield=function()end,
 find=function(number)tracked=number end})
 local function drain()while #queue>0 do table.remove(queue,1)()end end
 return A,drain,function(value)now=value end,function()return tracked end
end
scenario('popularity is a ranking signal by default',function()
 local A,drain=fixture()
 for n,price in ipairs({100,150,160,170})do
  assert(E.observe(A.state,{server='102',shop=n,owner='Seller'..n,at=1000,
   sell={{id='5',variant='0:0',name='Item',currency='SA$',price=price,qty=20}}}))
 end
 A.compute();drain()
 assert(#A.current_resale()>0,'profitable goods with unknown sales speed hidden by default')
 assert(A.current_resale()[1].popularity.kind=='unknown','unknown demand falsely confirmed')
 A.resale_options.popular_only=true;A.compute();drain()
 assert(#A.current_resale()==0,'explicit demand-only filter ignored')
end)
scenario('one expired quote does not hide fresh plans',function()
 local A,_,now,tracked=fixture()
 local a={id='5',seller={shop=1,server='102',at=1000},valid_until=1010}
 local b={id='6',seller={shop=2,server='102',at=1000},valid_until=2000}
 A.resale_results={a,b};A.resale_server='102';A.resale_currency='SA$';A.resale_at=1000;A.resale_revision=0
 assert(A.select_resale(2));now(1011)
 local rows=A.current_resale()
 assert(#rows==1 and rows[1]==b,'expired first row wiped the whole list')
 assert(A.resale_selected==1 and A.track_resale()and tracked()==2,'selection changed item after pruning')
 now(1000);assert(A.select_resale(1));now(1011);A.current_resale()
 assert(not A.resale_details and not A.track_resale(),'expired selection rebound to another shop')
end)
scenario('empty result reports the actual filter',function()
 local A=fixture()
 local function shop(n,price)
  assert(E.observe(A.state,{server='102',shop=n,owner='Seller'..n,at=1000,
   sell={{id='5',variant='0:0',name='Item',currency='SA$',price=price,qty=20}}}))
 end
 local rows,why,report=R.rank(A.state,'102',1000,{currency='SA$',popular_only=false})
 assert(not why and #rows==0 and report and report.offers==0,'missing empty-source diagnostics')
 shop(1,100)
 rows,why,report=R.rank(A.state,'102',1000,{currency='SA$',popular_only=false})
 assert(report.no_reference==1 and report.shops==1 and report.offers==1,'missing sparse-reference reason')
 shop(2,150);shop(3,160);shop(4,170)
 rows,why,report=R.rank(A.state,'102',1000,{currency='SA$',popular_only=true})
 assert(#rows==0 and report.no_demand>0,'missing demand-only reason')
 rows,why,report=R.rank(A.state,'102',1000,{currency='SA$',popular_only=false,min_roi_bp=10000})
 assert(#rows==0 and report.below_roi>0,'missing ROI reason')
 rows,why,report=R.rank(A.state,'102',1000,{currency='SA$',popular_only=false,budget=1})
 assert(#rows==0 and report.budget_or_qty>0,'missing budget reason')
 rows,why,report=R.rank(A.state,'102',1000,{currency='SA$',popular_only=false})
 assert(#rows==report.accepted and #rows>0,'accepted count differs from plans')
end)
assert(#failures==0,table.concat(failures,'\n'))
print('Resale visibility: ranked unknown demand and independent row expiry/selection OK')
