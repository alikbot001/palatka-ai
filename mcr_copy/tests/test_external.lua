local f=io.open('mcr_copy/src/external.lua','rb');assert(f,'missing cached market provider');f:close()
local P=assert(loadfile('mcr_copy/src/external.lua'))()
local data={shops={
    {server_id=102,shop_num=1,owner='A',updated_at=1000,
        sell_slots={{item_id=5,name='Item',price=10,qty=2,ench=9}}},
    {server_id=102,shop_num=1,owner='A',updated_at=1000,
        buy_slots={{item_id=6,name='Other',price=20,qty=4}}},
    {server_id=103,shop_num=2,owner='B',updated_at=1000,sell_slots={}},
}}
local pack=P.vata(data,102,'server-ip','SA$')
assert(#pack.shops==1,'wrong server imported')
assert(pack.shops[1].server=='server-ip' and #pack.shops[1].sell==1 and #pack.shops[1].buy==1)
assert(pack.shops[1].sell[1].variant=='9:0' and pack.shops[1].at==1000)
assert(#P.vata({shops={{server_id=102,shop_num=1}}},102,'ip','SA$').shops==0,'guessed time')
assert(#P.vata({shops={{server_id=102,shop_num=1,updated_at=1000,
    sell_slots={{name='Unknown',qty=5,price=10}}}}},102,'ip','SA$').shops==0,'guessed identity')
print('MCR external cache normalization: OK')
local raw={shops={{server_id=102,shop_num=4,updated_at=1000,sell_slots={
 {item_id=0,name='Unknown ID',price=100,qty=3},
 {item_id=5,name='Item',price=100,qty=3,quality=7},
 {item_id=5,name='Item',price=100,qty=3,quality=8},
}}}}
local public=P.vata(raw,102,'ip','SA$',nil,{read_only_unknown=true,source='market-helper'})
assert(#public.shops==1 and #public.shops[1].sell==3,'public rows discarded with unknown ID')
assert(public.shops[1].sell[1].variant==nil,'unknown item made actionable')
assert(public.shops[1].sell[2].variant~=public.shops[1].sell[3].variant,'quality mixed')
assert(public.shops[1].source=='market-helper')
