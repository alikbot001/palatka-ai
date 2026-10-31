-- Smoke test for the native storage home: menu is always accessible.
package.loaded['ffi']={string=function(x)return tostring(x)end,copy=function()end}
local pressed,last_kind,last_title,last_probe = '','','',''
DSP={ui21={},mobile={},storage={snapshots={},
    textdraw_state=function()return 'idle' end,
    trunk_state=function()return {status='idle',received=0}end,
    accept=function(kind,title,text)last_kind=kind;last_title=title;return trueend}}
local V=DSP.ui21
function V.button(label,id,w,on,primary)return id==pressed end
function V.heading(title,fn,w)if fn then fn()end end
function V.text()end
function V.muted()end
function V.red()end
function V.green()end
function V.fit(s)return s end
function V.inline()end
function V.reset_list()end
function V.list(key,draw,options)draw(380)end
function V.storage_probe_panel(w,kind)last_probe=kind end
imgui={new={char=setmetatable({},{__index=function(_,n)return function()return '' end end})},
    Separator=function()end,
    GetContentRegionAvail=function()return{x=380,y=360}end,
    ImVec2=function(x,y)return {x=x,y=y}end,
    InputTextMultiline=function()end}
dofile('src/60b_carbon_storage.lua')
V.storage_screen()
assert(V.storage_tab=='scan','must open scanner first')
pressed='storage_choose_cabinet';V.storage_screen()
assert(V.storage_scan_mode=='cabinet' and last_probe=='cabinet')
pressed='storage_manual_open';V.storage_screen()
assert(V.storage_tab=='manual' and V.storage_manual_kind=='cabinet')
pressed='storage_manual_inventory';V.storage_screen()
assert(V.storage_manual_kind=='inventory')
pressed='storage_manual_accept';V.storage_screen()
assert(last_kind=='inventory' and last_title:find('Инвентарь',1,true))
assert(V.storage_tab=='snapshots')
pressed='storage_scan_open';V.storage_screen()
assert(V.storage_tab=='scan')
pressed='storage_choose_trunk';V.storage_screen()
assert(V.storage_scan_mode=='trunk')
print('PASS storage navigation: scan default, four selectors, manual, return')
