-- Regression: the last 7 units can be listed against a 10-unit sell preset.
local item={name='Item',qty=10,price=50,ench=0,enabled=true}
local absent={name='Absent',qty=3,price=100,ench=0,enabled=true}
local calls={}
DSP={settings={sell_preset={items={item,absent}}},
    auto={inv={{name='Item',stacks={{slot=1,count=3},{slot=2,count=4}}}}},
    trade_v16={},add_log=function()end}
DSP.trade_v16.validate=function()
    local total,active=0,0
    for _,r in ipairs(DSP.settings.sell_preset.items)do
        if r.enabled~=false then active=active+1;total=total+r.qty*r.price
            if r.qty>7 then return false,{'oversell'},0 end
        end
    end
    return active>0,{},total
end
DSP.trade_v16.totals=function()
    local n=0
    for _,r in ipairs(DSP.settings.sell_preset.items)do
        if r.enabled~=false then n=n+r.qty end
    end
    return {qty=n}
end
DSP.auto.start_sell=function()
    calls={}
    for _,r in ipairs(DSP.settings.sell_preset.items)do
        if r.enabled~=false then calls[#calls+1]={r.name,r.qty,r.price}end
    end
    return #calls>0
end
assert(loadfile('src/42a_sell_stock_guard.lua'))()
local S=DSP.sell_stock_guard
local valid,_,total=DSP.trade_v16.validate('sell')
assert(valid and total==350 and DSP.trade_v16.totals('sell').qty==7)
assert(DSP.auto.start_sell() and #calls==1 and calls[1][2]==7 and calls[1][3]==50)
assert(item.qty==10 and item.enabled and absent.qty==3 and absent.enabled)
DSP.auto.inv={{name='Item',stacks={{slot=1,count=2},{slot=1,count=2},{slot=2,count=1}}}}
assert(DSP.trade_v16.totals('sell').qty==3,'one slot was counted twice')
DSP.auto.inv={{name='Item',stacks={{slot=1,count=2}}},{name='Wrong',stacks={{slot=1,count=2}}}}
assert(S.plan(DSP.settings.sell_preset.items,DSP.auto.inv)==nil,'conflicting slot ownership')
DSP.auto.inv={{name='Different',stacks={{slot=5,count=1}}}}
assert(not DSP.trade_v16.validate('sell') and not DSP.auto.start_sell())
assert(item.qty==10 and absent.qty==3,'preset changed after rejected launch')
print('v2.9.12 partial-sale reconciliation: OK')
