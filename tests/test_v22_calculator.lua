DSP={mobile={},ui={},screens={list={},set=function()end,draw=function()end},settings={}}
assert(loadfile('src/43_calculator_nav.lua'))()
local C=DSP.calc_v16
local function press(keys)C.press('AC');for _,k in ipairs(keys)do C.press(k)end;return tonumber(C.display)end
assert(press({'2','+','3','*','4','='})==20,'chained operation must evaluate before next operator')
assert(press({'2','0','0','+','1','0','%','='})==220,'context percent')
assert(press({'2','+','3','=','='})==8,'repeated equals')
C.press('AC');C.press('8');C.press('/');C.press('0');assert(C.press('=')=='Ошибка')
assert(press({'1','.','5','*','2','='})==3)
assert(math.abs(C.finance(100,150,2,1.5,10).profit-85.5)<1e-6)
print('v22 calculator chaining, percent, decimals, history, division zero: OK')
