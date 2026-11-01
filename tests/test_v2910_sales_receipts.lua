-- Only confirmed receipt quantities subtract from known loot; no false claims.
local events={{ts=os.time(),type='market',direction='sell',
 item_name='Resources x2',amount=4000,raw='Вы продали Resources x2 за $4000'}}
local source={{key='resources@0',name='Resources',ench=0,qty=3,estimated=3000}}
local C={history=function()return events end,
 loot_summary=function()return {items=source} end,
 period_start=function()return 0 end}
DSP={craglog=C,settings={},item_key=function(s,n)
 return string.lower(s)..'@'..tostring(n or 0) end,
 rewards={sequence=0},logs={revision=0},
 auto={inv={},scanning=false,inv_status='скан завершён'}}
assert(loadfile('src/59b_drop_sales_stats.lua'))()
local s=C.drop_sales_stats('all','')
assert(s.sold==2,'two explicit resources were sold')
assert(s.journal_balance==1,'three received minus two sold')
assert(s.inventory_ready,'completed zero-inventory scan is valid')
assert(s.items[1].sold_exact,'explicit receipt quantity exact')
print('PASS: explicit receipt quantity, inventory zero, known balance')
