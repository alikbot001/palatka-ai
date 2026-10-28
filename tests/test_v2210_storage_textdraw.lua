DSP={}
DSP.clean_text=function(s)return tostring(s or ''):gsub('{[%x]+}','')end
DSP.lower=string.lower
DSP.trim=function(s)return(s:gsub('^%s+',''):gsub('%s+$',''))end
DSP.item_key=function(s,e)return s..':'..e end
DSP.market={state={sid=102,version=1},row_for=function()return nil end}
DSP.flog=function()end
DSP.money=tostring
dofile('src/47_storage.lua')
local previous_hits=0
local handlers={onShowTextDraw=function() previous_hits=previous_hits+1;return 'show-ok' end,
 onTextDrawSetString=function() previous_hits=previous_hits+1;return 'set-ok' end}
package.loaded['samp.events']=handlers
dofile('src/47a_storage_textdraw.lua')
local S=DSP.storage
assert(S.install_textdraw())
assert(S.install_textdraw()==nil,'hook installs only once')
assert(type(handlers.onShowTextDraw)=='function' and type(handlers.onTextDrawSetString)=='function')
assert(not S.observe_textdraw(1,{text='Шкаф'}),'opt-in: disabled until explicitly armed')
S.arm_textdraw(25)
assert(handlers.onShowTextDraw(20,{text='Багажник автомобиля'})=='show-ok')
handlers.onShowTextDraw(21,{text='Дрова x45000'})
assert(handlers.onTextDrawSetString(21,'Дрова x45120')=='set-ok')
assert(previous_hits>=3,'must chain original packet observers')
handlers.onShowTextDraw(22,{text='Камень (90 шт.)'})
assert(S.textdraw_state()=='armed')
local ok,snap=S.finish_textdraw()
assert(ok and snap.kind=='trunk' and #snap.rows==2 and snap.source=='textdraw')
assert(snap.count_known==45210 and #S.snapshots==1,'incremental textdraw update replaces old qty')
assert(not S.observe_textdraw(23,'Золото x1'),'closed capture must ignore subsequent packets')
S.arm_textdraw(25)
handlers.onShowTextDraw(24,{text='Дрова x250'})
local got,err=S.finish_textdraw()
assert(not got and err:find('заголовок',1,true),'do not infer container kind from item labels')
S.arm_textdraw(25)
handlers.onShowTextDraw(1,{text='Шкаф дома'})
handlers.onShowTextDraw(2,{text='Неведомая вещь'})
local got2,err2=S.finish_textdraw()
assert(not got2 and err2:find('количеств',1,true),'no false quantities')
S.arm_textdraw(25)
assert(S.td_session.unique==0,'capture reset must clear quota')
for i=1,200 do S.observe_textdraw(i,'Дрова x2') end
assert(S.td_session.unique==110,'TextDraw diagnostic has strict memory ceiling')
assert(S.td_session.seen==200,'can count events without retaining all text')
print('PASS v2.2.10 bounded opt-in textdraw capture and trusted qty only')
