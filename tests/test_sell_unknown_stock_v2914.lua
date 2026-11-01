-- A missing/corrupt inventory snapshot must not reach a live trade worker.
local launches=0
local item={name='Item',qty=10,price=100,ench=0,enabled=true}
DSP={settings={sell_preset={items={item}}},auto={inv=nil},
    trade_v16={},add_log=function()end}
DSP.auto.start_sell=function()
    launches=launches+1
    assert(item.qty<=3,'preset not capped to observed stock')
    return true
end
DSP.trade_v16.validate=function()
    return item.qty<=3,{},item.qty*item.price
end
dofile('src/42a_sell_stock_guard.lua')
local A,T=DSP.auto,DSP.trade_v16
assert(not A.start_sell() and launches==0,'nil inventory launched live worker')
assert(not T.validate('sell'))
A.inv={}
assert(not A.start_sell() and launches==0,'empty inventory launched live worker')
A.inv={{name='Item',stacks={{slot=1,count=-4}}}}
assert(not A.start_sell() and launches==0,'malformed count launched live worker')
A.inv={{name='Item',stacks={{slot=1,count=3},{slot=1,count=3}}}}
assert(A.start_sell() and launches==1,'verified partial inventory should cap, not reject')
assert(item.qty==10 and item.enabled,'preset was mutated after partial plan')
A.scanning=true
assert(not A.start_sell()and launches==1,'active scan must block trade launch')
print('PASS sale stock guard: unavailable, empty, malformed, duplicate slot, scan and partial stock')
