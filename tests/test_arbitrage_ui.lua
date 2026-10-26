dofile('tests/test_ui.lua')
assert(loadfile('src/36_mobile.lua'))()
assert(loadfile('src/38_mobile_market.lua'))()
local captured={}
imgui.TextWrapped=function(s) captured[#captured+1]=s end
imgui.TextColored=function(_,s) captured[#captured+1]=s end
DSP.market.arbitrage_filtered=function() return {{name='Test stock',
    sell_offer={owner='Seller',shop=1,qty=100},buy_offer={owner='Buyer',shop=2,qty=200},
    p_buy=100,p_sell=200,tradable_qty=3,available_qty=100,partial=true,
    total_cost=300,net_profit=288,net_revenue=588,roi=96}} end
DSP.ui.arbitrage_tab()
local text=table.concat(captured,'\n')
assert(text:find('Продаёт: 100 шт.',1,true),'seller original stock quantity must appear')
assert(text:find('Скупает: 200 шт.',1,true),'buyer original demand quantity must appear')
assert(text:find('Купить 3 шт.',1,true),'budget limited deal quantity remains separate')
print('arbitrage UI stock and demand: ok')
