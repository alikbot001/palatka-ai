package.preload.ffi=function() return {} end
DSP={ui={},mobile={},screens={set=function()end},settings={mobile_window={}},market={state={}},theme={}}
DSP.utf8=function(s)return s end; DSP.to_cp=DSP.utf8;DSP.trim=DSP.utf8
DSP.clamp=function(v,a,b)return math.max(a,math.min(b,v))end
imgui={}
assert(loadfile('src/60_ui21_shell.lua'))()
local V=DSP.ui21
assert(type(V.visible_range)=='function','virtualized range is required')
local a,b=V.visible_range(10000,52,5200,260)
assert(a<=101 and b>=105 and b-a<12,'render only viewport + overscan')
V.queue_scroll('inventory',1,260)
assert(V.scrolls.inventory.pending>0)
assert(not V.scrolls.preset,'scroll commands must target a list')
V.queue_scroll('inventory',-1,260)
assert(V.scrolls.inventory.pending==0)
assert(V.geometry(800,360).h<=360 and V.geometry(800,360).w<=800)
print('v22 isolated scrolling / virtualization / viewport: OK')
