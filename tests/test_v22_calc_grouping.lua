-- Numeric source remains unformatted; only display inserts separators.
DSP={mobile={},ui={},screens={list={},set=function()end,draw=function()end}}
dofile('src/43_calculator_nav.lua')
local c=DSP.calc_v16
for _,x in ipairs({'1','0','0','0','0','0','0'})do c.press(x)end
assert(c.display=='1000000'and c.pretty_display()=='1.000.000','million grouping')
c.press('*');c.press('1');c.press('0');c.press('=')
assert(c.display=='10000000'and c.pretty_display()=='10.000.000','ten million without exponential notation')
c.press('+/-')
assert(c.display=='-10000000'and c.pretty_display()=='-10.000.000','negative grouping')
c.press('AC');c.press('0');c.press('.');c.press('2');c.press('5')
assert(c.display=='0.25'and c.pretty_display()=='0,25','decimal entry stays numeric')
print('calculator: grouping, decimal separator, arithmetic and negative values: OK')
