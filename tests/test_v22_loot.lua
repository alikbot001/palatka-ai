DSP={craglog={session_started=100,history=function()return{}end},settings={},market={state={version=1}},
 lower=string.lower,item_key=function(n,e)return n..'@'..e end}
assert(loadfile('src/59a_loot_summary.lua'))()
local C=DSP.craglog
local entries={
 {kind='opening',source='Case',ts=110},
 {kind='item',item_name='Casket A',qty=2,ts=111,source='Case',price_known=true,unit_price=100,estimated_value=200},
 {kind='item',item_name='Casket A',qty=3,ts=112,source='Cache',price_known=true,unit_price=110,estimated_value=330},
 {kind='item',item_name='Casket B',qty=4,ts=113,source='unknown',price_known=false},
 {kind='cash',cash=500,ts=114},
 {kind='item',item_name='Casket A',ench=1,qty=1,ts=115,price_known=true,unit_price=200},
}
local s=C.summarize_loot(entries,function(name,e)if name=='Casket A'and e==0 then return 120,'current market' end end)
assert(s.qty==10 and #s.items==3,'count quantities, keep enchantments, exclude opening/cash')
assert(s.estimated==800 and s.unpriced_qty==4,'unknown prices must not be guessed')
local a
for _,row in ipairs(s.items)do if row.name=='Casket A'and row.ench==0 then a=row end end
assert(a.qty==5 and a.estimated==600 and a.sources.Case==2 and a.sources.Cache==3)
assert(#a.events==2,'inspect every contributing reward')
local old=C.summarize_loot(entries)
assert(old.estimated==730 and old.unpriced_qty==4,'snapshot fallback sums individual prices')
local opens=0
C.history=function()opens=opens+1;return entries end
C.history_revision=1
local all=C.loot_summary('all');for _=1,60 do assert(C.loot_summary('all')==all)end
assert(opens==1,'do not regroup rewards on every frame')
C.history_revision=2;assert(C.loot_summary('all')~=all)
local session=C.loot_summary('session');assert(session.qty==10)
print('v22 loot: individual quantities, estimates, unknown prices, sources, inspection, cache: OK')
