-- The allocator owns deal-array invalidation; grouping must preserve cache identity.
local row={key='A|0',display='A',ench=0,
 sell={qty=3,min=10,offers={{shop=1,qty=3,price=10}}},
 buy={qty=700,max=20,offers={{shop=2,qty=700,price=20}}}}
local deal={row=row,tradable_qty=3,total_cost=30,net_revenue=60,net_profit=30}
local deals={deal}
DSP={market={arbitrage_filtered=function()return deals end}}
assert(loadfile('src/12_arbitrage_groups.lua'))()
local first=DSP.market.arbitrage_grouped()
local again=DSP.market.arbitrage_grouped()
assert(first==again,'unchanged allocator snapshot rebuilt grouped array every frame')
assert(first[1]==again[1],'unchanged group identity invalidates detail-plan cache')
assert(first[1].supply==3 and first[1].demand==700 and first[1].planned==3)
local real_sort,sorts=table.sort,0
table.sort=function(...)sorts=sorts+1;return real_sort(...)end
for _=1,120 do assert(DSP.market.arbitrage_grouped()==first)end
table.sort=real_sort
assert(sorts==0,'stable grouped redraw repeated sorting')
deals={{row=row,tradable_qty=2,total_cost=20,net_revenue=40,net_profit=20}}
local refreshed=DSP.market.arbitrage_grouped()
assert(refreshed~=first and refreshed[1]~=first[1])
assert(refreshed[1].planned==2 and refreshed[1].profit==20)
assert(first[1].planned==3,'refresh rewrote a previous grouped snapshot')
deals={}
local empty=DSP.market.arbitrage_grouped()
assert(#empty==0 and empty~=refreshed and DSP.market.arbitrage_grouped()==empty)
print('v22 stable grouped cache / refresh / empty snapshot / no repeated sorts: OK')
