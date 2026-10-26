dofile('tests/test_ui.lua')
assert(loadfile('src/11_arbitrage.lua'))()
assert(loadfile('src/12_arbitrage_groups.lua'))()
assert(loadfile('src/36_mobile.lua'))()
assert(loadfile('src/38_mobile_market.lua'))()
local captured={}
imgui.TextWrapped=function(s) captured[#captured+1]=s end
imgui.TextColored=function(_,s) captured[#captured+1]=s end
local clock=os.time()
DSP.market.rebuild({shops={
    {shop_num=1,owner='Seller 1',server_id=102,updated_at=clock,sell_slots={{name='Case Frame',qty=1,price=100}}},
    {shop_num=2,owner='Seller 2',server_id=102,updated_at=clock,sell_slots={{name='Case Frame',qty=2,price=110}}},
    {shop_num=3,owner='Buyer',server_id=102,updated_at=clock,buy_slots={{name='Case Frame',qty=700,price=200}}}
}},102)
DSP.settings.arb_filters={budget=0,max_age=0}
DSP.ui.arb_expanded={[DSP.item_key('Case Frame',0)]=true}
DSP.ui.arbitrage_tab()
local words=table.concat(captured,'\n')
assert(words:find('ПРОДАЮТ  3 шт.',1,true),'all sellers in group')
assert(words:find('СКУПАЮТ  700 шт.',1,true),'all buyers in group')
assert(words:find('План: 3 шт.',1,true),'planned quantity distinct from snapshot demand')
assert(words:find('Скупщик: 700 шт.',1,true),'buyer raw volume visible per route')
print('v1.5 arbitrage grouped UI: ok')
