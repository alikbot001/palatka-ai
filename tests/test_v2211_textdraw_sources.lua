DSP={settings={}}
DSP.clean_text=function(s)return tostring(s or ''):gsub('{[%x]+}','')end
DSP.lower=string.lower
DSP.trim=function(s)return(s:gsub('^%s+',''):gsub('%s+$',''))end
DSP.item_key=function(s,e)return s..':'..e end
DSP.market={state={sid=102,version=1},row_for=function()return nil end}
DSP.flog=function()end
DSP.money=tostring
dofile('src/47_storage.lua')
local chained=0
local handlers={onShowPlayerTextDraw=function()chained=chained+1;return 'player-ok'end,
 onPlayerTextDrawSetString=function()chained=chained+1;return 'player-set-ok'end}
package.loaded['samp.events']=handlers
dofile('src/47a_storage_textdraw.lua')
local S=DSP.storage
assert(S.install_textdraw())
assert(not S.observe_textdraw(1,{text='Багажник'}),'not armed')
S.arm_textdraw(35)
assert(handlers.onShowPlayerTextDraw(5,{string='Шкаф'})=='player-ok')
handlers.onShowPlayerTextDraw(5,{text='Склад'}) -- same ID, title changes
handlers.onShowPlayerTextDraw(5,{text='Домашний шкаф'})
assert(handlers.onPlayerTextDrawSetString(8,'Дрова x45000')=='player-set-ok')
assert(chained==4)
local ok,snap=S.finish_textdraw()
assert(ok and snap.kind=='cabinet' and snap.rows[1].qty==45000,'header survives replacement')
S.arm_textdraw(35)
handlers.onShowPlayerTextDraw(1,{value='Дрова x1'})
local valid,err=S.finish_textdraw()
assert(not valid and err:find('заголовок',1,true),'unrecognized native UI never invents snapshot')
assert(S.td_session.events==1 and S.td_session.seen==1,'diagnostic event accounting')
print('PASS player TextDraw sources, preserved title and scan diagnostics')
