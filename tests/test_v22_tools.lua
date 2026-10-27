-- Strict functional smoke: no game runtime; exercise persistent operations.
local ffi=require('ffi')
local hits,edits,texts,lists={},{},{},{}
local save_ok,saves=true,0
local function click(id) hits['tools22_'..id]=true end
local function noop() end
local V={pages={},searches={}}
V.button=function(label,id,w)
    assert(not w or w==-1 or w<=480,'widget exceeds narrow workspace')
    local hit=hits[id];hits[id]=nil;return hit
end
V.text=function(s)texts[#texts+1]=s end
V.muted=V.text;V.green=V.text;V.red=V.text
V.inline=noop;V.at=noop
V.fit=function(s,w)assert(w>=0);return s end
V.search=function()return '' end
V.reset_list=noop
local memo_cache={}
V.memo=function(key,signature,build)
    local cached=memo_cache[key]
    if not cached or cached.signature~=signature then cached={signature=signature,value=build()};memo_cache[key]=cached end
    return cached.value
end
V.list=function(id,fn,opts)lists[#lists+1]=id;fn(480,300,0);if opts and type(opts.footer)=='function' then opts.footer()end end
V.list_rows=function(id,rows,h,fn,opts)V.list(id,function()for i,r in ipairs(rows)do fn(r,i,480)end end,opts)end
V.row=function(id,h,fn)fn(464,8,5)end
V.open_popup=function(t,id)V.modal=id end
V.popup=function(t,id,fn,size)if V.modal==id then
 if id=='note_delete' then assert(size and size.h<=230,'confirmation must fit its content, without a tall empty panel')end
 fn()end end
V.shops=function()V.shop_calls=(V.shop_calls or 0)+1 end
V.set_screen=function(s)V.screen=s end
local function input(id,buf,size)
    if not edits[id]then return false end
    ffi.fill(buf,size,0);ffi.copy(buf,edits[id]);edits[id]=nil;return true
end
imgui={new={char=setmetatable({},{__index=function(_,n)return function()return ffi.new('char[?]',n)end end})},
 GetContentRegionAvail=function()return{x=480,y=300}end,SetNextItemWidth=function(w)assert(w<=480)end,
 InputTextWithHint=function(id,h,b,n,flags)
  if id=='##tools22_tg_token'then assert(flags==1,'bot token must be masked')end
  return input(id,b,n)
 end,InputText=input,
 InputTextMultiline=function(id,b,n,sz)assert(sz.y>=48);return input(id,b,n)end,
 ImVec2=function(x,y)return{x=x,y=y}end,InputTextFlags={Password=1},
 CloseCurrentPopup=function()V.modal=nil end,TextWrapped=noop,Separator=noop}
local id=function(x)return x end
DSP={settings={notes={},craglog={},arb_filters={},tax_bp=200},ui={},mobile={defer_save=noop},
 ui21=V,ui22=V,utf8=id,to_u8=id,to_cp=id,trim=id,lower=string.lower,
 money=function(x)return '$'..tostring(x or 0)end,notify=noop,save_ui_state=noop,
 save_settings=function()saves=saves+1;return save_ok end,
 theme={list={ocean_blue={name='Ocean'}},current='ocean_blue',opacity=.97,set=noop,set_opacity=noop},
 market={state={sid=102},servers={{id=102,name='Mobile II'}},cr_scan_state={status='idle'},api='test',
 invalidate_arbitrage=noop,scan_cr_marker=noop,pull=noop,clear_for_server=noop,mark_shop=noop},
 craglog={summary=function(period)
  V.period_seen=period;return{count=1,income=100,expense=40,net=60,trade_profit=20,
   reward_cash=2,reward_estimated=3,unknown_items=1,payday_income=30,payday_expense=10,other_income=50}
 end,set_pinned=noop},logs={export_logs=function()V.exported=true end},log={},dir='test',version='2.2'}
DSP.mobile.compact_number=function()return false end
imgui.GetCursorPosX=function()return 0 end
imgui.GetCursorPosY=function()return 0 end
V.text_button=V.button
V.heading=function(title,fn)if fn then fn()end end
assert(loadfile('src/40_mobile_notes.lua'))()
assert(loadfile('src/65_ui22_tools.lua'))()
V.tools('stats');assert(V.period_seen=='day')
click('period_session');V.tools('stats');assert(V.period_seen=='session')
V.tools('search');assert(V.shop_calls==1)
-- All sections render, including previously hidden Telegram credentials.
for i=1,5 do V.tools_section=i;V.tools('settings')end
V.tools_section=4
edits['##tools22_tg_token']='123:secret';edits['##tools22_tg_chat']='-999'
V.tools('settings')
assert(DSP.settings.tg_bot_token=='123:secret' and DSP.settings.tg_chat_id=='-999')
click('tg_export');V.tools('settings');assert(V.exported)
local note=DSP.notes.create('Original');assert(DSP.notes.open(note))
edits['##tools22_note_title']='Edited'
edits['##tools22_note_text']='Unsaved body'
V.tools('notes');assert(DSP.ui._notes_dirty)
save_ok=false;click('note_back');V.tools('notes')
assert(DSP.ui.note_current==note and DSP.ui._notes_dirty,'failed save prevents editor exit')
save_ok=true
DSP.ui._notes_last_edit=os.time()-3
V.popups();assert(not DSP.ui._notes_dirty and note.title=='Edited' and note.text=='Unsaved body')
click('note_delete');V.tools('notes');assert(#DSP.settings.notes==1,'opening modal does not delete')
save_ok=false;click('note_delete_confirm');V.popups()
assert(#DSP.settings.notes==1 and DSP.settings.notes[1]==note and DSP.ui.note_current==note,
 'failed delete save restores exact note at original position')
save_ok=true;click('note_delete_confirm');V.popups()
assert(#DSP.settings.notes==0 and DSP.ui.note_current==nil)
V.tools('notes');assert(#lists>0 and saves>0)
print('v2.2 tools: stats, settings/Telegram, note debounce, modal delete rollback: ok')
