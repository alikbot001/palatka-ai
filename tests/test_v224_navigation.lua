-- Static source contract check: both screens live in the same native mobile workspace.
local function read(path)
 local f=assert(io.open(path,'rb'));local d=f:read('*a');f:close();return d
end
local shell=read('src/60_ui21_shell.lua')
assert(shell:find("{'resale','Перепродажа'}",1,true))
assert(shell:find("{'promo','Авто-пиар'}",1,true))
assert(shell:find("elseif V.screen=='resale'then V.flip_screen()",1,true))
assert(shell:find("elseif V.screen=='promo'then V.promo_screen()",1,true))
local ui=read('src/68_ui22_flip_promo.lua')
assert(ui:find('V.list_rows',1,true) and ui:find('V.row(',1,true))
assert(ui:find("V.popup('Удалить шаблон?'",1,true),'real modal required for deletion')
assert(ui:find("V.popup('Разбор сделки'",1,true),'detail modal required')
assert(ui:find('V.scroll_buttons',1,true)==nil,'list must manage fixed scroll buttons')
local promo=read('src/49_promo.lua')
assert(not promo:find('MarketHelper',1,true) and not promo:find('dofile(',1,true))
local core=read('src/48_flip_intel.lua')
assert(not core:find('http_get',1,true),'core must not fetch network data while rendering')
print('v2.2.4 mobile navigation / modal / background boundaries PASS')
