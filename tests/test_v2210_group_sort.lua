DSP={lower=function(s)return tostring(s):lower()end,market={}}
local M=DSP.market
M.state={sid=102,version=1}
local rowZ={key='z',display='Zebra',sell={qty=8,offers={{}}},buy={qty=4,offers={{}}}}
local rowA={key='a',display='Alpha',sell={qty=2,offers={{}}},buy={qty=2,offers={{}}}}
local deals={{row=rowZ,tradable_qty=2,total_cost=1,net_revenue=900,net_profit=900},
    {row=rowA,tradable_qty=1,total_cost=1,net_revenue=50,net_profit=50}}
M.arbitrage_filtered=function()return deals end
M.invalidate_arbitrage=function()end
dofile('src/12_arbitrage_groups.lua')
local groups=M.arbitrage_grouped()
assert(#groups==2 and groups[1].name=='Alpha' and groups[2].name=='Zebra', 'default A-Z order')
assert(M.arbitrage_grouped()==groups,'stable cached identity, no per-frame sorting')
assert(groups[2].profit==900,'display sort must not alter calculations')
print('PASS v2.2.10 arbitration alphabetical default and unchanged finance')
