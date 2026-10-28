-- Tested price buttons must derive from observed offers and never fabricate
-- a same-day transaction average from listed asking prices.
DSP={dir='/tmp',settings={server=102},market={state={sid=102,updated=os.time()},
 row_for=function(name,ench)if name=='Crate' and ench==0 then
  return {name='Crate',ench=0,sid=102,updated=os.time(),
    sell={med=62000,count=5,p25=59000,min=54000},
    buy={med=51000,count=4,max=56000}}
 end end},lower=function(s)return s:lower()end,
 clean_text=function(s)return s end,item_key=function(s,e)return s..':'..e end,
 flog=function()end}
dofile('src/15_prices.lua')
local refs=DSP.db.reference_prices('Crate',0)
assert(refs.market==62000 and refs.buy==51000,'listing median not exposed')
assert(refs.today==nil,'asking prices were fabricated into completed sales')
assert(refs.source:find('объявления',1,true),'source not disclosed')
local item={name='Crate',ench=0,price=100,qty=2,enabled=false}
local ok,msg=DSP.db.apply_reference(item,'market')
assert(ok and item.price==62000 and item.qty==2,'market button altered non-price fields')
ok,msg=DSP.db.apply_reference(item,'buy')
assert(ok and item.price==51000,'buy button did not apply bid-side quote')
local before=item.price
ok,msg=DSP.db.apply_reference(item,'today')
assert(not ok and item.price==before,'today wrote unobserved value')
DSP.settings.server=103
refs=DSP.db.reference_prices('Crate',0)
assert(not refs.market and not refs.buy,'another server price leaked into editor')
item.price=12345;ok,msg=DSP.db.apply_reference(item,'market')
assert(not ok and item.price==12345,'missing price overwrote the user')
DSP.settings.server=102
item.name='Unknown';ok,msg=DSP.db.apply_reference(item,'market')
assert(not ok and item.price==12345,'unknown item price was guessed')
print('price quick actions: observed medians, source, no fake day trades, server isolation: OK')
