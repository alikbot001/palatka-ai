-- Regression: quantity + price workflow and calculator arithmetic (no game dependencies).
dofile('tests/test_ui.lua')
local ffi=require('ffi')
assert(loadfile('src/21_preset_library.lua'))()
assert(loadfile('src/36_mobile.lua'))()
assert(loadfile('src/37_trade_v16.lua'))()
assert(loadfile('src/43_calculator_nav.lua'))()
local T=DSP.trade_v16
local C=DSP.calc_v16
DSP.settings.sell_preset.items={}
DSP.settings.buy_preset.items={}
DSP.auto.inv={{name='Фрейм кейс',count=15,stacks={{slot=10,count=15}}}}
local ok,err=T.add_from_inventory('sell',DSP.auto.inv[1]);assert(ok,err)
local items=DSP.settings.sell_preset.items
assert(#items==1 and items[1].qty==15 and items[1].price==0 and items[1].enabled==false,
    'whole inventory stack, no guessed price')
local valid,issues=T.validate('sell');assert(not valid,'unpriced item must not be listed')
items[1].price=500;items[1].enabled=true
assert(T.validate('sell'),'priced item within inventory must pass')
items[1].qty=16
assert(not T.validate('sell'),'must not list more than owned')
items[1].qty=15
local original=items[1]
assert(T.add_from_inventory('sell',{name='Фрейм кейс',count=9}))
assert(#items==1 and items[1]==original and items[1].price==500 and items[1].qty==9,
    'repeat tap updates count but never price or duplicates')
assert(T.add_from_inventory('buy',{name='Фрейм кейс',count=9}))
assert(#DSP.settings.buy_preset.items==1 and DSP.settings.buy_preset.items[1].qty==1,
    'buy quantity is user-editable, not forced by inventory count')
C.press('1');C.press('2');C.press('+');C.press('3');C.press('=')
assert(C.display=='15' and #C.history==1,'math and history')
C.press('AC');C.press('8');C.press('/');C.press('0');C.press('=')
assert(C.display=='Ошибка','division by zero must not crash')
local f=C.finance(100,150,3,2,20)
assert(math.abs(f.profit-121)<.001 and math.abs(f.spent-320)<.001,'commission and extras')
assert(DSP.screens.list[#DSP.screens.list].id=='calculator')
assert(loadfile('src/38_arbitrage_v16.lua'))()
local pair=DSP.arb_v16.manual_pair({qty=3,price=100},{qty=700,price=200},0,200)
assert(pair.qty==3 and pair.cost==300 and pair.revenue==588 and pair.profit==288, '1 vs 700 uses raw supply and demand, with fee')
local limited=DSP.arb_v16.manual_pair({qty=3,price=100},{qty=700,price=200},150,200)
assert(limited.qty==1,'budget reduces planned quantity, never raw supply or demand')
print('v1.6 trading and calculator tests: ok')
