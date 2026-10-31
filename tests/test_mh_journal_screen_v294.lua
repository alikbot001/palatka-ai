-- Journal renders as a screen; the legacy floating mini window is gone.
_G.DSP={
    settings={craglog={open=true}},
    craglog={draw=function() error('old popup must be replaced')end},
    ui22={journal=function()error('old list must be replaced')end},
    utf8=function(s)return s end,
}
dofile('src/66d_mh_journal_screen_v294.lua')
assert(DSP.settings.craglog.open==false)
assert(DSP.craglog.draw())
local src=assert(io.open('src/66d_mh_journal_screen_v294.lua','rb')):read('*a')
for _,label in ipairs({'Дата','Товар','Кол.','Цена $','Тип','Ник'})do
    assert(src:find(label,1,true),label)
end
assert(src:find('imgui.Columns(6',1,true))
assert(src:find("function V.journal()",1,true))
assert(not src:find("Мини-окно",1,true))
assert(not src:find('ЗАКРЕПЛЁН',1,true))
assert(src:find('available_dates',1,true))
assert(src:find('C.trade_totals',1,true))
print('PASS v2.9.4 MH journal screen only, six columns and date filters')
