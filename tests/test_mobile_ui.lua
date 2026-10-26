-- UI test for the agreed v1.6 design. Old parallel-pane fixture preserved in tests/legacy.
dofile('tests/test_ui.lua')
assert(loadfile('src/21_preset_library.lua'))()
assert(loadfile('src/36_mobile.lua'))()
assert(loadfile('src/37_trade_v16.lua'))()
assert(loadfile('src/43_calculator_nav.lua'))()
local M=DSP.mobile
imgui.TextWrapped=function()end
local g=M.geometry(2340,1080)
assert(g.touch>=48 and g.nav>=170,'compact controls remain touch-sized')
assert(g.y+g.h<1080,'game interaction strip remains visible')
assert(DSP.screens.list[9].id=='calculator')
-- The side drawer is closed by default; opening it uses the same screen routing.
M.nav_open=true
DSP.screens.set('calculator')
assert(DSP.ui.screen=='calculator' and M.nav_open==false)
DSP.screens.set('palatka')
DSP.ui.v16_side='sell';DSP.ui.v16_tab='items'
DSP.auto.inv={{name='Бинт',count=3,stacks={{slot=1,count=3}}}}
DSP.ui.draw()
DSP.ui.v16_tab='preset'
DSP.ui.draw()
DSP.screens.set('calculator')
DSP.ui.draw()
print('v1.6 compact mobile UI: ok')
