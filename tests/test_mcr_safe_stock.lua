-- MCR preview: immutable desired quantity and fail-closed inventory checks.
local item={id=120,name='Ore',ench=0,qty=100,price=5,enabled=true}
local rival={id=121,name='Ore',ench=0,qty=10,price=10,enabled=true}
local advertised={}
DSP={
    settings={sell_preset={items={item,rival}},dry_run=true},
    auto={inv={{id=120,name='Ore',ench=0,
        stacks={{slot=1,count=30},{slot=2,count=40}}}}},
    trade_v16={},add_log=function()end,
    notify=function(s)advertised[#advertised+1]=s end,
    flog=function()end
}
local function valid()
    local total,n=0,0
    for _,r in ipairs(DSP.settings.sell_preset.items)do
        if r.enabled~=false then
            n=n+1
            assert(r.qty<=70,'oversell')
            total=total+r.qty*r.price
        end
    end
    return n>0,{},total
end
DSP.trade_v16.validate=valid
DSP.trade_v16.totals=function()
    local qty=0
    for _,r in ipairs(DSP.settings.sell_preset.items)do
        if r.enabled~=false then qty=qty+r.qty end
    end
    return {complete=true,qty=qty}
end
local observed={}
DSP.auto.start_sell=function()
    for _,r in ipairs(DSP.settings.sell_preset.items)do
        if r.enabled~=false then
            observed[#observed+1]={id=r.id,qty=r.qty,price=r.price,dry=DSP.settings.dry_run}
        end
    end
    return #observed>0
end
assert(loadfile('src/42a_sell_stock_guard.lua'))()
local S=DSP.sell_stock_guard
local proposals,summary=S.preview(DSP.settings.sell_preset.items,DSP.auto.inv)
assert(proposals and summary.planned==70 and summary.requested==110)
assert(proposals[item].desired_qty==100 and proposals[item].planned_qty==70)
assert(proposals[item].shortfall==30)
assert(proposals[rival].desired_qty==10 and proposals[rival].planned_qty==0)
assert(proposals[rival].shortfall==10,'a different ID must not consume the Ore stock')
local ok,issues,total=DSP.trade_v16.validate('sell')
assert(ok and total==350)
assert(DSP.trade_v16.totals('sell').qty==70)
assert(DSP.auto.start_sell()==true and #observed==1)
assert(observed[1].id==120 and observed[1].qty==70 and observed[1].dry==true)
assert(item.qty==100 and item.enabled and rival.qty==10 and rival.enabled,
    'preset must remain independent of confirmed stock')
-- A competing item using the same physical slot is not allowed.
DSP.auto.inv={{name='Ore',id=120,stacks={{slot=1,count=70}}},
              {name='Ore',id=121,stacks={{slot=1,count=70}}}}
assert(S.plan(DSP.settings.sell_preset.items,DSP.auto.inv)==nil)
local rejected,reason=S.preview(DSP.settings.sell_preset.items,DSP.auto.inv)
assert(rejected==nil and reason,'inconsistent snapshot must be rejected')
assert(DSP.auto.start_sell()==false,'unsafe live launch must fail closed')
assert(#observed==1,'unsafe launch must not call native sale executor')
local totals=DSP.trade_v16.totals('sell')
assert(totals.complete==false and totals.invalid_stock,'unsafe totals cannot look final')
-- Partial scan has no reliable slots and must never authorize a sale.
DSP.auto.inv={{name='Ore',id=120,count=100}}
assert(DSP.auto.start_sell()==false)
DSP.auto.scanning=true
assert(S.preview(DSP.settings.sell_preset.items,DSP.auto.inv)==nil)
print('PASS MCR partial-sale UI model, identity and fail-closed launch')
