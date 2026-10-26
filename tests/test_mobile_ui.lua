-- Behavioral touch UI checks using the same LuaJIT/FFI fixture as the runtime UI.
dofile('tests/test_ui.lua')
dofile('src/11_arbitrage.lua')
dofile('src/12_arbitrage_groups.lua')
local ffi = require('ffi')
-- The legacy fixture allocated char[128] regardless of requested capacity.
imgui.new.char=setmetatable({}, {__index=function(_,size)
    return function() return ffi.new('char[?]',size) end
end})
for _, name in ipairs({'36_mobile.lua', '37_mobile_trade.lua', '38_mobile_market.lua', '39_mobile_history.lua'}) do
    local chunk, err = loadfile('src/' .. name)
    assert(chunk, err)
    chunk()
end
local m = DSP.mobile
assert(m, 'mobile UI module must be installed')
local g = m.geometry(2340, 1080)
assert(g.w > 1800 and g.h > 700, 'landscape uses the available phone screen')
assert(g.y + g.h <= 1080 * 0.88, 'bottom interaction area stays reachable')
assert(g.nav >= 200 and g.touch >= 56, 'touch targets must be finger sized')
local small = m.geometry(1280, 720)
assert(small.w <= 1280 and small.y + small.h < 720)
DSP.screens.set('nonexistent')
assert(DSP.ui.screen == 'palatka', 'invalid saved screens recover to trade')
-- Editing a billion-dollar price must preserve it beyond signed 32-bit range.
local item = {name='Long item name', price=3500000000, qty=4}
local price = m.edit_buffer(item, 'price')
assert(ffi.string(price) == '3500000000')
ffi.copy(price, '4500000000\0')
assert(m.apply_number(item, 'price', price, 0))
assert(item.price == 4500000000)
ffi.copy(price, '-42\0')
assert(not m.apply_number(item, 'price', price, 0), 'negative prices rejected')
assert(item.price == 4500000000)
-- Drawing every route exercises balanced child windows, including clipped ones.
imgui.TextWrapped = function() end
local depth = 0
imgui.BeginChild = function() depth=depth+1; return true end
imgui.EndChild = function() depth=depth-1; assert(depth>=0) end
for _, e in ipairs(DSP.screens.list) do
    DSP.screens.set(e.id)
    DSP.ui.draw()
    assert(depth==0, 'unbalanced child window: '..e.id)
end
imgui.BeginChild = function() depth=depth+1; return false end
DSP.ui.draw()
assert(depth==0, 'clipped children still require EndChild')
print('mobile ui tests: ok')
assert(loadfile('src/40_mobile_notes.lua'))()
DSP.settings.notes=nil
ffi.copy(DSP.ui.notes_buf,'Legacy note\0')
local notes=DSP.notes.all()
assert(#notes==1 and notes[1].text=='Legacy note', 'migrate the old notebook')
local note=DSP.notes.create('Test title')
assert(note and note.title=='Test title')
note.text='shopping wood'; note.pinned=true; note.item='Wood'; note.shop='42'
assert(DSP.notes.filtered('wood')[1]==note, 'search note content and item reference')
assert(DSP.notes.filtered('42')[1]==note, 'search shop reference')
assert(DSP.notes.filtered('')[1]==note, 'pinned notes sort first')
local save=DSP.save_settings
DSP.save_settings=function() return false end
DSP.ui._notes_dirty=true
assert(not DSP.mobile.save_notes(), 'failed persistence must remain dirty')
assert(DSP.ui._notes_dirty)
DSP.save_settings=save
print('mobile notes tests: ok')
-- Full item names pass to wrapped text and the buy/sell actions stay distinct.
local wrapped={}
imgui.TextWrapped=function(value) wrapped[#wrapped+1]=value end
imgui.TextDisabled=function(value) wrapped[#wrapped+1]=value end
local row=DSP.market.state.rows[1]
local fullname='Item with a long full name that must never be truncated at the old 28 character boundary'
row.display=fullname
DSP.ui.finder_query='Item'; DSP.ui.selected=nil
local called
local real_add=DSP.presets.add
DSP.presets.add=function(_,kind) called=kind; return true end
imgui.Button=function(label) return label:find('##mobile_search_buy1',1,true)~=nil end
DSP.ui.finder_tab()
assert(called=='buy','buy button must populate the buy preset')
called=nil
imgui.Button=function(label) return label:find('##mobile_search_sell1',1,true)~=nil end
DSP.ui.finder_tab()
assert(called=='sell','sell button must populate the sell preset')
assert(table.concat(wrapped,'\n'):find(fullname,1,true),'long name must be rendered in full')
DSP.presets.add=real_add
imgui.Button=function() return false end
-- Timestamp-keyed trade history must remain visible.
DSP.settings.trades={['event:1']={ts=1,partner='Visible partner',item_summary='Visible trade'}}
DSP.ui.tab_detail='trades'; DSP.ui.legacy_trade_open=true; wrapped={}
DSP.ui.log_tab()
assert(table.concat(wrapped,'\n'):find('Visible trade',1,true),'keyed history must render')
-- Touch paging must apply immediately, without showing a stale page on the click frame.
DSP.screens.set_page('search',1)
imgui.Button=function(label) return label:find('##mobile_nextsearch',1,true)~=nil end
local first,last=DSP.screens.pager(30,6,'search')
assert(first==7 and last==12)
imgui.Button=function() return false end
print('mobile interaction tests: ok')
-- Keyboard input crosses UTF8 -> CP1251 before searching stored rows.
local old_cp=DSP.to_cp
local old_find=DSP.market.find_item
local old_input=imgui.InputTextWithHint
local captured
DSP.to_cp=function(value) return 'decoded:'..value end
DSP.market.find_item=function(query) captured=query; return {} end
imgui.InputTextWithHint=function(label) return label=='##mobile_search' end
ffi.copy(DSP.ui.finder_search_buf,'keyboard\0')
DSP.ui.finder_tab()
assert(captured=='decoded:keyboard')
DSP.to_cp=old_cp; DSP.market.find_item=old_find; imgui.InputTextWithHint=old_input
local old_row=DSP.market.row_for
local old_inv=DSP.auto.inv
DSP.auto.inv={{name='Item (+13)',count=2}}
DSP.market.row_for=function(name,ench) captured={name,ench}; return nil end
DSP.ui.trade_advanced=true; DSP.ui.trade_section='inventory'; DSP.ui.preset_kind='buy'
DSP.ui.trade_tab()
assert(captured[1]=='Item' and captured[2]==13,'enchanted inventory retains its market key')
DSP.market.row_for=old_row; DSP.auto.inv=old_inv
print('mobile encoding and inventory tests: ok')
local a=DSP.mobile.history_rows('trades')
assert(a[1].item_summary=='Visible trade')
assert(a==DSP.mobile.history_rows('trades'),'unchanged history must reuse sorted list')
DSP.mobile.history_revision.trades=DSP.mobile.history_revision.trades+1
DSP.settings.trades.extra={ts=2,item_summary='New revision trade'}
local b=DSP.mobile.history_rows('trades')
assert(a~=b and b[1].item_summary=='New revision trade','new revision rebuilds sort')
DSP.settings.chat_logs={}
for i=1,30 do DSP.settings.chat_logs[i]={ts=i,text='Chat row '..i} end
DSP.ui.tab_detail='chat'; DSP.ui.journal_chat_open=true; DSP.screens.set_page('chat_history',1); wrapped={}
DSP.ui.log_tab()
local rendered=table.concat(wrapped,'\n')
assert(rendered:find('Chat row 30',1,true) and not rendered:find('Chat row 1\n',1,true),'chat renders one page newest first')
print('mobile history cache tests: ok')
local rewards=DSP.rewards
local seen
DSP.rewards={summary=function(options)
    seen=options
    return {openings=0,items=0,cash=0,estimated_value=0,unknown_items=0}
end,query=function() return {entries={},total=0} end}
DSP.ui.reward_source=imgui.new.char[256]()
ffi.copy(DSP.ui.reward_source,'Vice City\0')
local input=imgui.InputTextWithHint
imgui.InputTextWithHint=function(label) return label=='##reward_source' end
imgui.Button=function(label) return label:find('##mobile_reward_period604800',1,true)~=nil end
DSP.ui.crate_log()
assert(seen.source_contains=='Vice City','source filter must stay separate from generic search')
assert(math.abs(seen.from_ts-(os.time()-604800))<2,'seven-day filter passes an epoch boundary')
imgui.InputTextWithHint=input; imgui.Button=function() return false end
DSP.rewards=rewards
print('mobile reward filter tests: ok')
local manual=DSP.presets.add_manual
DSP.presets.add_manual=function(kind,entry) captured={kind=kind,entry=entry}; return true,1 end
DSP.auto.inv={{name='Unpriced item (+9)',count=7}}
DSP.market.row_for=function() return nil end
DSP.ui.trade_advanced=true; DSP.ui.trade_section='inventory'; DSP.ui.preset_kind='sell'; captured=nil
imgui.Button=function(label) return label:find('##mobile_inv_unknown_sell1',1,true)~=nil end
DSP.ui.trade_tab()
assert(captured and captured.kind=='sell','inventory must add items without market data')
assert(captured.entry.price==0 and captured.entry.qty==7 and captured.entry.ench==9 and captured.entry.enabled==false)
DSP.presets.add_manual=manual; DSP.market.row_for=old_row; DSP.auto.inv=old_inv
imgui.Button=function() return false end
print('mobile unpriced inventory tests: ok')
DSP.presets.add_manual=function(kind,entry) captured={kind=kind,entry=entry}; return true,1 end
DSP.ui.trade_advanced=true; DSP.ui.trade_section='manual'; DSP.ui.preset_kind='buy'
DSP.ui.manual_name=imgui.new.char[256]()
ffi.copy(DSP.ui.manual_name,'Manual item\0')
DSP.ui.manual_item={ench=5,price=6500000000,qty=3}
imgui.Button=function(label) return label:find('##mobile_manual_add',1,true)~=nil end
DSP.ui.trade_tab()
assert(captured.kind=='buy' and captured.entry.price==6500000000 and captured.entry.ench==5)
assert(captured.entry.name=='Manual item' and captured.entry.qty==3)
DSP.ui.trade_section='manual'
ffi.copy(DSP.mobile.edit_buffer(DSP.ui.manual_item,'price'),'-5\0')
captured=nil
DSP.ui.trade_tab()
assert(captured==nil,'manual add must reject invalid visible price text')
DSP.presets.add_manual=manual; imgui.Button=function() return false end
print('mobile manual entry tests: ok')
local measured=imgui.CalcTextSize
local button=imgui.Button
imgui.CalcTextSize=function() return {x=420,y=28} end
local bw
imgui.Button=function(_,size) bw=size.x; return false end
DSP.mobile.button('Wide action with shop #123','measure_action',330)
assert(bw>=452,'action button must fit measured label plus padding')
assert(DSP.mobile.geometry(2340,1080).nav>=200,'compact navigation must still fit labels')
DSP.screens.set('arbitrage')
assert(DSP.mobile.reset_scroll,'screen navigation must reset content scroll')
imgui.CalcTextSize=measured;imgui.Button=button
print('mobile measured layout tests: ok')
local scroll
imgui.BeginChild=function() depth=depth+1; return true end
imgui.SetScrollY=function(value) scroll=value end
DSP.screens.set('arbitrage')
DSP.ui.draw()
assert(scroll==0 and not DSP.mobile.reset_scroll,'body scroll resets on the first frame of navigation')
assert(not DSP.mobile.sticky and #DSP.mobile.footers==1,'pager is registered for the fixed footer')
assert(depth==0)
print('mobile sticky workspace tests: ok')
DSP.settings.mobile_window=nil
local pos=DSP.mobile.window_position(2340,1080)
DSP.mobile.move_window(40,40,2340,1080)
local moved=DSP.mobile.window_position(2340,1080)
assert(moved.x==pos.x+40 and moved.y==pos.y+40,'drag handle moves the window')
DSP.mobile.move_window(99999,99999,2340,1080)
local clamped=DSP.mobile.window_position(2340,1080)
assert(clamped.x+DSP.mobile.layout.w<=2340 and clamped.y+DSP.mobile.layout.h<=1080)
DSP.settings.scroll_step=300
DSP.mobile.queue_scroll(1)
assert(DSP.mobile.scroll_delta==300,'down rail uses configured jump')
DSP.mobile.queue_scroll(-1)
assert(DSP.mobile.scroll_delta==0,'up rail reverses configured jump')
print('mobile drag and scroll tests: ok')
local labels={}
imgui.Button=function(label) labels[#labels+1]=label; return false end
DSP.ui.trade_advanced=false; DSP.ui.trade_section='items'; DSP.ui.preset_kind='buy'
DSP.ui.trade_tab()
local screen=table.concat(labels,'\n')
assert(not screen:find('trade_sectionlibrary',1,true) and not screen:find('trade_sectionauto',1,true),'advanced tools stay out of the main listing path')
assert(screen:find('+ ДОБАВИТЬ ПРЕДМЕТ',1,true),'add item flow is visible without advanced submenu')
imgui.Button=function() return false end
print('mobile simple listing tests: ok')
-- Item-centric arbitrage retains both owners, prices, quantities and commission.
local clock=os.time()
DSP.market.rebuild({shops={
    {shop_num='10',owner='Player_A',server_id=102,updated_at=clock,sell_slots={{name='Wood',qty=2,price=100}}},
    {shop_num='20',owner='Player_B',server_id=102,updated_at=clock,buy_slots={{name='Wood',qty=700,price=200}}},
}},102)
DSP.settings.arb_filters={budget=0,max_age=0}
DSP.ui.arb_expanded={[DSP.item_key('Wood',0)]=true}
wrapped={}; DSP.ui.arbitrage_tab()
local route=table.concat(wrapped,'\n')
assert(route:find('Player_A',1,true) and route:find('Player_B',1,true),'arbitrage explains both players')
assert(route:find('Комиссия',1,true),'route explains commission and net result')
assert(route:find('СКУПАЮТ  700',1,true),'demand remains independent of seller stock')
print('mobile clear arbitrage tests: ok')
DSP.mobile.scroll_delta=0
DSP.mobile.queue_scroll(1)
DSP.mobile.reset_scroll=false
imgui.GetScrollY=function() return 100 end
imgui.GetScrollMaxY=function() return 1000 end
DSP.ui.draw()
assert(scroll==400,'scroll rail applies one configured jump within the scrolling body')
local start=DSP.auto.start_buy
local submitted
DSP.auto.start_buy=function() submitted=true end
DSP.ui.preset_kind='buy'; DSP.ui.trade_section='items'; DSP.ui.trade_advanced=false; DSP.settings.dry_run=false
DSP.settings.buy_preset.items={{name='Wood',price=100,qty=1,enabled=true}}
imgui.Button=function(label) return label:find('##mobile_run_buy',1,true)~=nil end
DSP.ui.trade_tab()
assert(submitted and DSP.settings.dry_run==false,'normal listing action sends actual listing, not hidden dry-run')
DSP.auto.start_buy=start; imgui.Button=function() return false end
print('mobile scroll and listing execution tests: ok')
local check=imgui.Checkbox
local pinned_api=DSP.craglog.set_pinned
local opened
DSP.settings.craglog={open=false,pinned=false}
DSP.craglog.set_pinned=function(value) opened=value; DSP.settings.craglog.open=value end
DSP.ui.settings_section='appearance'
imgui.Checkbox=function(label,ref)
    if label:find('Закрепить мини-журнал',1,true) then ref[0]=true; return true end
    return false
end
DSP.ui.settings_tab()
assert(opened and DSP.settings.craglog.open,'pinning from settings opens the mini journal')
imgui.Checkbox=check; DSP.craglog.set_pinned=pinned_api
print('mobile settings journal pin tests: ok')
DSP.settings.mobile_window=nil
local initial=DSP.mobile.window_position(2340,1080)
local before=DSP.mobile.geometry(2340,1080)
DSP.mobile.resize_window(100,80,2340,1080)
local after=DSP.mobile.geometry(2340,1080)
local resized=DSP.mobile.window_position(2340,1080)
assert(after.w==before.w-100 and after.h==before.h+80,'bottom-left drag resizes both axes')
assert(resized.x+after.w==initial.x+before.w and resized.y==initial.y,'resize anchors right/top')
assert(DSP.settings.mobile_window.w==after.w and DSP.settings.mobile_window.h==after.h,'saved window retains dimensions')
DSP.mobile.resize_window(99999,-99999,2340,1080)
local minimum=DSP.mobile.geometry(2340,1080)
assert(minimum.w>=1100 and minimum.h>=550,'resize stops at usable minimum')
DSP.mobile.resize_window(-99999,99999,2340,1080)
local maximum=DSP.mobile.window_position(2340,1080)
assert(maximum.x+maximum.w<=2340 and maximum.y+maximum.h<=1080,'resize stays within viewport')
print('mobile resize tests: ok')
