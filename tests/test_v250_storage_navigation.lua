-- Smoke test for the simplified two-page storage UI.
package.loaded['ffi']={string=function(x)return tostring(x)end,copy=function()end}
local pressed,last_probe='', ''
local labels={}
DSP={ui21={},mobile={},to_cp=function(x)return x end,utf8=function(x)return tostring(x or '') end,
 money=tostring,lower=function(x)return string.lower(tostring(x or ''))end,
 trim=function(x)return tostring(x or ''):match('^%s*(.-)%s*
    trunk_state=function()return {status='idle',received=0,autoscan_enabled=true}end,
    library=function()return{}end,
    begin_trunk_scan=function()return true end,
    cancel_trunk_scan=function()return true end,
    set_trunk_autoscan=function()return true end,
    clear_live_snapshot=function()return true end,
    evaluate=function()return{sell_to_buyers=0,ask_value=0,total_qty=0,rows={}}end}}
local V=DSP.ui21
V.font_pixels=18
function V.button(label,id,w,on,primary)
 labels[#labels+1]=label
 return id==pressed
end
function V.text_button(label,id,w,on,h)return id==pressed end
function V.heading(title,fn,w)if fn then fn()end end
function V.text()end
function V.muted()end
function V.red()end
function V.green()end
function V.fit(s)return s end
function V.inline()end
function V.reset_list()end
function V.apply_font()end
function V.at()end
function V.row(id,h,draw)draw(360,0,0)end
function V.list(key,draw,options)draw(380)end
function V.list_rows(key,rows,height,draw,options)
 for i,row in ipairs(rows)do draw(row,i,360)end
 if options and options.footer then options.footer()end
end
function V.storage_probe_panel(w,kind)last_probe=kind end
imgui={new={char=setmetatable({},{__index=function(_,n)return function()return '' end end})},
 Separator=function()end,GetContentRegionAvail=function()return{x=380,y=360}end}
dofile('src/60b_carbon_storage.lua')

V.storage_screen()
assert(V.storage_tab=='scan')
pressed='storage_choose_cabinet';V.storage_screen()
assert(V.storage_scan_mode=='cabinet' and last_probe=='cabinet')
pressed='storage_tab_library';V.storage_screen()
assert(V.storage_tab=='library' and V.storage_library_page=='list')
pressed='storage_library_new_scan';V.storage_screen()
assert(V.storage_tab=='scan' and V.storage_scan_mode=='trunk')
for _,label in ipairs(labels)do
 assert(label~='Инвентарь','inventory scan must not be visible')
 assert(label~='Ввод','manual tab must not be visible')
end
print('PASS storage navigation: two pages, trunk/cabinet/warehouse only, no inventory/manual clutter')
)end,storage={snapshots={},
    trunk_state=function()return {status='idle',received=0,autoscan_enabled=true}end,
    library=function()return{}end,
    begin_trunk_scan=function()return true end,
    cancel_trunk_scan=function()return true end,
    set_trunk_autoscan=function()return true end,
    clear_live_snapshot=function()return true end,
    evaluate=function()return{sell_to_buyers=0,ask_value=0,total_qty=0,rows={}}end}}
local V=DSP.ui21
V.font_pixels=18
function V.button(label,id,w,on,primary)
 labels[#labels+1]=label
 return id==pressed
end
function V.text_button(label,id,w,on,h)return id==pressed end
function V.heading(title,fn,w)if fn then fn()end end
function V.text()end
function V.muted()end
function V.red()end
function V.green()end
function V.fit(s)return s end
function V.inline()end
function V.reset_list()end
function V.apply_font()end
function V.at()end
function V.row(id,h,draw)draw(360,0,0)end
function V.list(key,draw,options)draw(380)end
function V.list_rows(key,rows,height,draw,options)
 for i,row in ipairs(rows)do draw(row,i,360)end
 if options and options.footer then options.footer()end
end
function V.storage_probe_panel(w,kind)last_probe=kind end
imgui={new={char=setmetatable({},{__index=function(_,n)return function()return '' end end})},
 Separator=function()end,GetContentRegionAvail=function()return{x=380,y=360}end}
dofile('src/60b_carbon_storage.lua')

V.storage_screen()
assert(V.storage_tab=='scan')
pressed='storage_choose_cabinet';V.storage_screen()
assert(V.storage_scan_mode=='cabinet' and last_probe=='cabinet')
pressed='storage_tab_library';V.storage_screen()
assert(V.storage_tab=='library' and V.storage_library_page=='list')
pressed='storage_library_new_scan';V.storage_screen()
assert(V.storage_tab=='scan' and V.storage_scan_mode=='trunk')
for _,label in ipairs(labels)do
 assert(label~='Инвентарь','inventory scan must not be visible')
 assert(label~='Ввод','manual tab must not be visible')
end
print('PASS storage navigation: two pages, trunk/cabinet/warehouse only, no inventory/manual clutter')
