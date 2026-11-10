local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local D=assert(loadfile('mcr_copy/src/popularity.lua'))()(E)
local now=1000000
local pack={ok=true,items={
 {name='Coupon',qty_sold_30d=8892,updated_at=now-7200},
 {name='Ambiguous',qty_sold_30d=999999,updated_at=now},
 {name='Future',qty_sold_30d=500,updated_at=now+1},
 {name='Negative',qty_sold_30d=-5,updated_at=now},
 {name='Ancient',qty_sold_30d=9999,avg=99999,updated_at=1},
 {name='Zero',qty_sold_30d=0,updated_at=now}}}
local ids={Coupon='5',Future='6',Negative='7',Zero='8',Ancient='9'}
local rows=assert(D.parse(pack,now,'SA$',function(name)return ids[name]end))
local key='5\31'..'0:0\31SA$'
assert(rows[key].qty_30d==8892 and rows[key].valid_until==now+900)
assert(rows['8\31'..'0:0\31SA$'].qty_30d==0,'known zero converted to unknown')
assert(rows['6\31'..'0:0\31SA$']==nil and rows['7\31'..'0:0\31SA$']==nil)
assert(rows['9\31'..'0:0\31SA$']==nil,'ancient history made fresh just by fetching it')
assert(rows['5\31'..'4:0\31SA$']==nil,'base-name history assigned to enhanced item')
assert(next(assert(D.parse(pack,now,'VC$',function(name)return ids[name]end)))==nil,'dollar market history relabelled as VC$')
pack.items[#pack.items+1]={name='Coupon',qty_sold_30d=100,updated_at=now}
assert(D.parse(pack,now,'SA$',function(name)return ids[name]end)[key]==nil,'ambiguous duplicate name stats were merged')
assert(not D.parse({ok=false,items={}},now,'SA$',function()end))
assert(not D.parse({ok=true,items={bad=true}},now,'SA$',function()end),'object accepted as array')
print('Public monthly-volume adapter: unique catalogue identity, dates and variant isolation OK')
