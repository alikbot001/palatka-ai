-- Independent Lua test: UI behavior without Android dependencies.
local fake_ffi={string=function(b) return type(b)=='table' and b.val or '' end,copy=function()end}
package.loaded['ffi']=fake_ffi; package.preload['ffi']=function() return fake_ffi end
local open=false
local click
local last_scroll=100
local hover=true
local texts={}
local changed=0
imgui={}
imgui.ImVec2=function(x,y)return{x=x,y=y}end
imgui.ImVec4=function(a,b,c,d)return{a,b,c,d}end
imgui.Col=setmetatable({},{__index=function()return 0 end})
imgui.StyleVar=setmetatable({},{__index=function()return 0 end})
imgui.WindowFlags={AlwaysAutoResize=1}
imgui.Cond={Appearing=1}
imgui.GetIO=function()return{DisplaySize={x=1600,y=900},MouseDelta={x=0,y=-20},MouseDown={[0]=true}}end
imgui.IsWindowHovered=function()return hover end
imgui.IsAnyItemActive=function()return false end
imgui.GetScrollY=function()return last_scroll end
imgui.GetScrollMaxY=function()return 700 end
imgui.SetScrollY=function(v)last_scroll=v end
imgui.GetContentRegionAvail=function()return{x=1050,y=500}end
imgui.GetWindowWidth=function()return 1100 end
imgui.CalcTextSize=function(s)return{x=#s*8,y=18}end
imgui.BeginChild=function()return true end
imgui.EndChild=function()end
imgui.Separator=function()end
imgui.TextDisabled=function()end
imgui.TextColored=function()end
imgui.SameLine=function()end
imgui.SetNextItemWidth=function()end
imgui.SetNextWindowPos=function()end
imgui.InputText=function()return false end
imgui.InputTextMultiline=function()return false end
imgui.InputTextWithHint=function()return false end
imgui.Checkbox=function()return false end
imgui.BeginPopupModal=function()return open end
imgui.OpenPopup=function()open=true end
imgui.CloseCurrentPopup=function()open=false end
imgui.EndPopup=function()end
imgui.new={char=setmetatable({},{__index=function(_,size)return function()return {val=''} end end}),bool=function(v)return {[0]=v}end}
DSP={version='1.5.1',settings={notes={{id='1',title='Test',text='Hello'}}},ui={}, screens={list={{id='palatka'},{id='lavki'},{id='arbitrage'},{id='search'},{id='logs'},{id='stats'},{id='notes'},{id='settings'}}},
 theme={get=function()return{accent={.1,.2,.6},panel={.1,.1,.1},text={1,1,1}}end,col=function()return{}end},
 utf8=function(s)return s end,to_cp=function(s)return s end,to_u8=function(s)return s end,
 lower=function(s)return s:lower()end,trim=function(s)return s end,save_settings=function()return true end,
 notify=function()end,clamp=function(n,a,b)return math.max(a,math.min(b,n))end}
DSP.screens.set=function()end
assert(loadfile('src/36_mobile.lua'))()
assert(loadfile('src/40_mobile_notes.lua'))()
local M=DSP.mobile
M.button=function(_,id)return id==click end
M.title=function(s)texts[#texts+1]=s end
M.text=function(s)texts[#texts+1]=s end
M.inline=function()end
M.toggle=function()end
DSP.ui.note_current=DSP.settings.notes[1]
DSP.ui.note_title={val='Test'};DSP.ui.notes_buf={val='Hello'};DSP.ui.note_item={val=''};DSP.ui.note_shop={val=''}
click='note_delete';DSP.ui.notes_tab()
assert(open,'delete must open modal')
assert(#DSP.settings.notes==1,'modal must not delete before confirmation')
click='note_cancel_modal';DSP.ui.notes_tab()
assert(not open and #DSP.settings.notes==1,'cancel must preserve the note')
click='note_delete';DSP.ui.notes_tab()
click='note_delete_confirm';DSP.ui.notes_tab()
assert(#DSP.settings.notes==0 and DSP.ui.note_current==nil,'confirm must delete')
-- Swipe behavior is independent of tiny scrollbar hit areas.
M.touch_scroll(imgui.GetIO(),'notes')
assert(last_scroll==123,'vertical swipe should follow the finger')
print('1.5.1 popup and swipe: OK')

-- The trading window must keep inventory and the active preset in parallel panes
-- on a landscape phone, with its publish action outside both scroll regions.
local pbuy={name='Скупка',items={{name='Бинт',price=300,qty=12,enabled=true}}}
local psell={name='Продажа',items={{name='Металл',price=2000,qty=6,enabled=true}}}
DSP.settings.buy_preset=pbuy;DSP.settings.sell_preset=psell;DSP.settings.dry_run=true
DSP.presets={list=function(k)return{k=='buy' and pbuy or psell}end,selected=function()return 1 end,
 active_count=function(k)return #(k=='buy' and pbuy.items or psell.items)end,
 find_row=function()return nil end,items=function(k)return(k=='buy' and pbuy or psell).items end}
DSP.money=function(n)return '$'..tostring(n)end
DSP.auto={inv_status='Готов',inv={},buy_running=false,sell_running=false}
DSP.market={state={sid=102,offers=0},find_item=function()return{}end}
M.thumbnail=function()end
M.compact_number=function()return false end
local panes={}
M.child=function(id,w,h,fn)panes[#panes+1]=id;fn()end
click=nil
assert(loadfile('src/37_mobile_trade.lua'))()
DSP.ui.preset_kind='buy';DSP.ui.trade_section='items'
DSP.ui.trade_tab()
assert(panes[1]=='mh_inventory' and panes[2]=='mh_preset','landscape must show inventory next to preset')
assert(pbuy.items[1].price==300 and psell.items[1].qty==6,'data unchanged by rendering')
print('1.5.1 Market Helper layout: OK')
