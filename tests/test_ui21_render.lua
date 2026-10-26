-- Headless render smoke test. Simulates ImGui, does not validate phone layout.
package.preload.ffi=function() return {string=function(x) return x.text or '' end} end
local noop=function() end
local im={}
im.new={bool=function(v) return {[0]=v} end,
 char=setmetatable({},{__index=function() return function() return {text=''} end end})}
im.ImVec2=function(x,y) return {x=x,y=y} end
im.WindowFlags=setmetatable({},{__index=function()return 0 end})
im.StyleVar=im.WindowFlags; im.Col=im.WindowFlags; im.Cond=im.WindowFlags
im.GetContentRegionAvail=function() return {x=900,y=540} end
im.GetIO=function() return {DisplaySize={x=2340,y=1080},MouseDelta={x=0,y=0}} end
im.Begin=function() return true end
im.BeginChild=function() return true end
im.Button=function()return false end
im.BeginPopupModal=function()return false end
im.InputTextWithHint=function()return false end
im.Checkbox=function()return false end
for _,method in ipairs({'PushStyleColor','PopStyleColor','SetNextItemWidth','Text',
 'TextDisabled','TextColored','Separator','Columns','SetColumnWidth','NextColumn',
 'EndChild','End','SameLine','SetNextWindowSize','SetNextWindowPos',
 'SetNextWindowBgAlpha','PushStyleVarVec2','PushStyleVarFloat','PopStyleVar',
 'SetWindowFontScale','OpenPopup'}) do im[method]=noop end
imgui=im
local id=function(s) return s end
DSP={version='2.1.0',settings={sell_preset={name='Primary',items={}},
 buy_preset={name='Primary',items={}},mobile_window={},craglog={}},
 ui={open_ref={[0]=true},tab=1,set_open=noop},mobile={thumbnail=noop,
 number=noop,compact_number=noop,touch_scroll=noop,flush_save=noop,
 queue_scroll=noop,defer_save=noop},screens={index_by_id=function()return 1 end,
 set=noop,draw=noop},market={state={sid=102,version=1,status='live',rows={}}},
 theme={push_window=function()return 0 end,col=function()return {1,1,1,1} end},
 auto={inv={},scan_inventory=noop},trade_v16={},arb_v16={},
 presets={list=function()return {} end,selected=function()return 1 end,
 active_count=function()return 0 end,find=function()return nil end},
 craglog={filtered=function()return {} end},
 calc_v16={display='0',history={},finance=function()return
 {spent=0,received=0,profit=0,roi=0,markup=0} end},
 flog=noop,save_settings=noop}
DSP.utf8=id;DSP.to_cp=id;DSP.lower=string.lower
DSP.trim=function(s)return s end
DSP.clamp=function(x,a,b) return math.max(a,math.min(b,x)) end
DSP.money=function(x)return '$'..tostring(x) end
DSP.market.freshness=function()return 'test snapshot' end
DSP.market.arbitrage_grouped=function()return {} end
DSP.market.pull=noop
DSP.market.shops_list=function()return {} end
DSP.trade_v16.validate=function()return true,{},0 end
for _,name in ipairs({'60_ui21_shell','61_ui21_trade','62_ui21_shops',
 '63_ui21_arbitrage','64_ui21_journal_calc'}) do
 assert(loadfile('src/'..name..'.lua'))()
end
for _,screen in ipairs({'palatka','lavki','arbitrage','logs','calculator'}) do
 DSP.ui21.screen=screen
 DSP.ui.draw()
end
DSP.ui21.screen='palatka';DSP.ui21.tab='preset';DSP.ui.draw()
DSP.ui21.screen='palatka';DSP.ui21.kind='buy';DSP.ui.draw()
print('UI21 headless screen smoke: OK')
