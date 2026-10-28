-- Three market observation sources, no fabricated daily sale averages.
local now=os.time()
local row={key='Wood@0',name='Wood',ench=0,sell={med=120,count=5},buy={med=80,shop_n=4}}
DSP={settings={server=102},market={state={sid=102,updated=now},
 load_cr_marker=function()return{sid=102,saved_at=now-240,
  items={{name='Wood',sell_med=135}},histories={wood={day=os.date('%Y-%m-%d'),qty=100,avg=145}}}end},
 live={shop={server=102,menu_closed=0,items_updated=now,sell={{name='Wood',ench=0,price=118}}}},
 lower=function(s)return string.lower(s)end,item_key=function(s,e)return s..'@'..e end}
dofile('src/48_flip_intel.lua')
local out=DSP.flip.price_evidence(row)
assert(out.api==120 and out.cr==135 and out.today==145 and out.opened==118 and out.buy==80)
assert(out.today_qty==100 and out.interest==4)
assert(DSP.flip.market_interest(row):find('несколько',1,true))
DSP.market.load_cr_marker=function()return{sid=102,saved_at=now-400,
 items={{name='Wood',sell_med=135}},histories={wood={day='2020-01-01',qty=100,avg=145}}}end
out=DSP.flip.price_evidence(row);assert(out.today==nil,'stale completed sales are not today')
DSP.live.shop.items_updated=now-200
out=DSP.flip.price_evidence(row);assert(out.opened==nil,'stale shop quote accepted')
DSP.settings.server=103
out=DSP.flip.price_evidence(row)
assert(not out.api and not out.cr and not out.today and not out.opened,'foreign server evidence leaked')
print('v2.2.4 separate API/CR/day/opened-shop prices, server/time guards PASS')
