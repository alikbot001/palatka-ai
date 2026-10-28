-- Resale model regression; offers and confirmed trades are distinct evidence.
local now=os.time()
DSP={settings={server=102,tax_bp=200,arb_filters={max_age=1800},
    flip={capital=10000,reserve_pct=20,max_position_pct=50,min_roi=1,max_risk=1,sort='profit'}},
    market={state={sid=102,version=2,by_key={}}},money=function(n)return tostring(n)end,
    save_settings=function()return true end}
dofile('src/48_flip_intel.lua')
local F=DSP.flip
local function route(name,sell_shop,buy_shop,price,sell,qty)
    local row={key=name,display=name}
    local seller={shop=sell_shop,qty=qty,price=price,ts=now,qty_source='game',verified_at=now}
    local buyer={shop=buy_shop,qty=qty,price=sell,ts=now,qty_source='game',verified_at=now}
    local r={row=row,name=name,p_buy=price,p_sell=sell,tradable_qty=qty,
       sell_offer=seller,buy_offer=buyer,demand_verified=true}
    return {key=name,name=name,row=row,routes={r},sellers={seller},buyers={buyer}}
end
local groups={route('Wood',101,202,1000,1300,10),route('Ore',103,205,1000,1300,10)}
local pack=F.rank(groups,now)
assert(pack.summary.limited and pack.summary.budget==8000 and pack.summary.reserve==2000)
assert(pack.summary.cost==8000 and pack.summary.count==2)
assert(pack.rows[1].qty==4 and pack.rows[2].qty==4)
assert(pack.summary.gross==10400 and pack.summary.fee==208)
assert(pack.summary.revenue==10192 and pack.summary.profit==2192)
assert(F.rank(groups,now)==pack,'same snapshot must use cached result')
local r=F.score_route(groups[1].routes[1],{budget=2000,tax_bp=200,min_roi=0,max_age=1800},now)
assert(r.qty==2 and r.profit==548 and r.roi>0)
-- A single-slot qty=1 with no game proof is a severe risk.
groups[1].routes[1].sell_offer.qty=1;groups[1].routes[1].sell_offer.verified_at=nil
F.invalidate();local risked=F.rank(groups,now)
assert(#risked.rows==1 and risked.rows[1].key=='Ore','high-risk entry should be suppressed')
local row={sell={count=5,p25=120,med=140,p75=160,min=100}}
local cheap=F.suggest_price(row,'fast')
local market=F.suggest_price(row,'market')
local premium=F.suggest_price(row,'premium',160,200)
assert(cheap==118 and market==140 and premium>=164,'cost protection must prevent loss')
assert(F.suggest_price(row,'market',nil)==140,'unknown cost must not be treated as zero')
assert(F.suggest_price(row,'market',1,10000)==nil,'100% commission has no breakeven')
local key='Wood@0'
DSP.market.state.by_key[key]={sell={min=500,med=550},buy={best=600}}
assert(F.watch_set(key,'Дрова',550))
F.settings().alerts=true
local messages={}
assert(F.check_alerts(now,function(s)messages[#messages+1]=s end)==1)
assert(#messages==1 and messages[1]:find('API',1,true))
assert(F.check_alerts(now+400,function(s)messages[#messages+1]=s end)==0,'same offer should not spam')
DSP.market.state.version=3
assert(F.check_alerts(now+401,function(s)messages[#messages+1]=s end)==1)
assert(F.watch_remove(key))
local trades={
 {type='trade',ts=now,money_give=100,money_get=200,items_give={{name='Ore'}},profit=900000},
 {type='trade',ts=now,money_give=20,money_get=50},
 {type='estimate',ts=now,money_get=1000000},
}
local cash=F.cash_summary(trades,true)
assert(cash.trades==2 and cash.cash_in==250 and cash.cash_out==120 and cash.cash_net==130)
assert(cash.valued_trades==1,'estimated item value should remain separate from real cash')
print('v2.2.4 resale: capital, reserve, risk, pricing, alerts, cash provenance PASS')
