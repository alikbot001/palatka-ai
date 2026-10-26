local saves=0
DSP={settings={craglog={open=false,pinned=false,minimized=false}},ui={open=false},dir='/tmp',
 save_settings=function() saves=saves+1; return true end,money=tostring,utf8=function(s)return s end,
 add_log=function()end,flog=function()end,mkdir_p=function()end,
 rewards={record=function(row)return row end}}
DSP.trades_log_path=os.tmpname(); DSP.crates_log_path=os.tmpname()
assert(loadfile('src/55_craglog.lua'))()
local C=DSP.craglog
for i=1,5 do C.ring_push({ts=i,type='trade',money_get=1}) end
assert(C.ring_recent(2)[1].ts==4 and C.ring_recent(2)[2].ts==5,'recent returns newest n in chronological order')
C.set_anchor(140,180); C.set_pinned(true)
assert(DSP.settings.craglog.open and DSP.settings.craglog.pinned,'pin makes journal visible')
assert(not C.drag(30,40),'pinned handle cannot drag')
assert(DSP.settings.craglog.x==140 and DSP.settings.craglog.y==180,'pin keeps position')
C.set_minimized(true)
assert(DSP.settings.craglog.minimized,'pin permits compact mode')
local a=C.geometry(2340,1080)
C.set_minimized(false); local b=C.geometry(2340,1080)
assert(a.x==b.x and a.y==b.y,'both modes share anchor')
DSP.ui.open=false; assert(C.visible(),'main close does not hide pinned journal')
C.set_pinned(false); assert(C.drag(20,10)); C.end_drag()
assert(DSP.settings.craglog.x==160 and DSP.settings.craglog.y==190 and saves>0,'drag persists')
C.toggle(); assert(not C.visible(),'explicit toggle closes independent window')
C.toggle(); assert(C.visible())
C.clear_ring()
for i=1,305 do C.ring_push({ts=i,type='trade',money_get=1}) end
assert(C.ring_count==300 and C.ring_recent(2)[1].ts==304,'wrapped newest slice')
assert(#C.filtered('sales')==300 and #C.filtered('loot')==0,'filters classify events')
local row={id='r1',kind='item',ts=10,item_name='A',qty=2,source='неизвестно',price_known=false}
DSP.rewards.record(row)
assert(C.ring_recent(1)[1].id=='r1','reward journal feeds mini log')
DSP.rewards.record({kind='association',item_ids={'r1'},opening_id='o1',source='VC'})
assert(C.ring_recent(1)[1].source=='VC' and C.ring_recent(1)[1].association=='inferred','association updates ring evidence')
DSP.rewards.record({id='r2',kind='item',item_name='B'})
local count=C.ring_count
C.log_crate({id='r2',item_name='B'})
assert(C.ring_count==count,'legacy reward mirror does not duplicate')
C.clear_ring()
local old_count=C.ring_count
DSP.rewards.record({id='legacy-r',kind='item',legacy_id='crate:k',item_name='Legacy',ts=20})
C.log_crate({item_name='Legacy',ts=20})
assert(C.ring_count==old_count+1,'legacy crate mirror pushes exactly one event')
assert(C.describe(row):find('нет цены',1,true),'unknown value shown explicitly')
local f=io.open(DSP.trades_log_path,'r'); if f then f:close() end
DSP.trades_log_path='/nonexistent/palatka-test/log'
assert(not C.log_trade({type='trade',profit=1}), 'append errors returned')
assert(C.last_error,'append errors visible')
print('mini journal tests: ok')

-- Exercise both render modes and ensure clipped children still balance.
dofile('tests/test_ui.lua')
local callbacks={}
imgui.OnFrame=function(ready,draw) callbacks[#callbacks+1]={ready=ready,draw=draw} end
imgui.TextWrapped=function()end
imgui.IsMouseDown=function()return false end
imgui.IsMouseDragging=function()return false end
imgui.IsItemActive=function()return false end
local children=0
imgui.BeginChild=function()children=children+1;return false end
imgui.EndChild=function()children=children-1 end
assert(loadfile('src/55_craglog.lua'))()
assert(loadfile('src/56_mini_journal.lua'))()
C=DSP.craglog
C.set_anchor(50,60); C.set_pinned(true)
C.install(); assert(#callbacks==1)
DSP.ui.open=false; assert(callbacks[1].ready(),'render gate ignores main window state')
C.draw(); assert(children==0,'clipped cards still end child')
C.set_minimized(true); C.draw(); assert(children==0)
print('mini journal rendering fixture: ok')
