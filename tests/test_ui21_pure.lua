-- Pure API model regression, runs under texlua without MonetLoader/FFI.
package.preload.ffi=function() return {} end
local id=function(x) return x end
DSP={settings={mobile_window={},arb_filters={}},ui={},mobile={},screens={set=function() end},
    market={state={sid=102,version=1}},theme={},presets={},trade_v16={},arb_v16={},
    auto={},calc_v16={},craglog={}}
DSP.utf8=id
DSP.to_cp=id
DSP.trim=function(s) return s end
DSP.lower=string.lower
DSP.clamp=function(v,a,b) return math.max(a,math.min(b,v)) end
DSP.money=function(v) return '$'..tostring(v) end
imgui={}
assert(loadfile('src/12_arbitrage_groups.lua'))()
assert(loadfile('src/60_ui21_shell.lua'))()
assert(loadfile('src/62_ui21_shops.lua'))()
local M,V=DSP.market,DSP.ui21
local offers={
 {shop='101',owner='seller1',qty=1,price=50,ts=999},
 {shop='102',owner='seller2',qty=1,price=60,ts=999},
 {shop='103',owner='seller3',qty=1,price=70,ts=999},
}
local bids={{shop='201',owner='bigbuyer',qty=700,price=100,ts=999}}
local row={key='frame@0',display='Кейс Frame',id=1,
 sell={qty=3,offers=offers,min=50},buy={qty=700,offers=bids,max=100}}
M.state.rows={row}
local sold=V.shops_result(M.state.rows,'sell','',M.state.version)
assert(#sold==1 and sold[1].qty==3 and sold[1].shops==3 and sold[1].count==3)
local buying=V.shops_result(M.state.rows,'buy','',M.state.version)
assert(#buying==1 and buying[1].qty==700 and buying[1].shops==1,
       'demand must show 700, not one allocated deal')
assert(#V.shops_result(M.state.rows,'buy','bigbuyer',M.state.version)==1)
assert(#V.shops_result(M.state.rows,'sell','101',M.state.version)==1)
assert(#V.shops_result(M.state.rows,'sell','nomatch',M.state.version)==0)
local routes={}
for i,s in ipairs(offers) do routes[#routes+1]={row=row,tradable_qty=1,
 sell_offer=s,buy_offer=bids[1],total_cost=s.price,net_revenue=98,net_profit=98-s.price} end
M.arbitrage_filtered=function() return routes end
local groups=M.arbitrage_grouped()
assert(#groups==1 and groups[1].supply==3 and groups[1].demand==700)
assert(groups[1].planned==3 and groups[1].seller_count==3 and groups[1].buyer_count==1)
print('UI 2.1: 3 sellers vs 700 demand, owner/shop search, grouped deals: OK')
