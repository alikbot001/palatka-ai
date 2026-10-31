_G.DSP={craglog={},settings={},lower=string.lower,auto={inv={},scanning=false,inv_status=''},
 item_key=function(n,e)return tostring(n)..'@'..tostring(e or 0)end}
local C=DSP.craglog
local now=os.time();C.history_revision=1
C.period_start=function(period)if period=='day'then return now-86400 end;return 0 end
local all={items={{key='Ларец A@0',name='Ларец A',ench=0,qty=10,estimated=1000}},qty=10}
local day={items={{key='Ларец A@0',name='Ларец A',ench=0,qty=4,estimated=400}},qty=4}
C.loot_summary=function(period)return period=='all'and all or day end
C.history=function()return{
 {type='market',direction='sell',item_name='Ларец A',raw='Продано x2',ts=now-100,amount=200},
 {type='trade',money_get=500,money_give=0,items_give={{name='Ларец A',qty=3}},ts=now-100000},
}end
assert(dofile('src/59b_drop_sales_stats.lua'))
local d=C.drop_sales_stats('day','')
assert(d.dropped==4 and d.sold==2 and d.journal_balance==5)
DSP.auto.inv={{name='Ларец A',count=7}};DSP.auto.inv_status='готов'
C.history_revision=2
local a=C.drop_sales_stats('all','')
assert(a.dropped==10 and a.sold==5 and a.inventory_ready and a.inventory_total==7)
print('PASS v2.9.3 drop/sale/inventory statistics')
