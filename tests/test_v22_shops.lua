package.preload.ffi=function()return{}end
DSP={ui={},mobile={},screens={set=function()end},settings={},market={state={sid=102}},theme={}}
DSP.lower=string.lower;DSP.utf8=function(s)return s end;DSP.to_cp=DSP.utf8
imgui={}
assert(loadfile('src/60_ui21_shell.lua'))();assert(loadfile('src/62_ui21_shops.lua'))()
local rows={}
for i=100,1,-1 do rows[#rows+1]={key=tostring(i),display='item'..i,sell={offers={{shop=tostring(i),qty=i,price=i}}}}end
local groups=DSP.ui21.shops_result(rows,'sell','',1)
for i=1,100 do assert(groups[i].best==i,'sell ascending order')end
DSP.ui21.shops_sort='qty_desc'
groups=DSP.ui21.shops_result(rows,'sell','',1)
for i=1,100 do assert(groups[i].qty==101-i,'quantity sort invalidates cache')end
print('v22 shops strict sorting + cache invalidation: OK')
