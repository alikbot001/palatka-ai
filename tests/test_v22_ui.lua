-- Real UI modules + real market allocator/presets/calculator; deterministic ImGui model.
-- Geometry checks validate model invariants, not Android rendering or touch drivers.
local Harness=dofile('tests/support/imgui22.lua')
local ffi=require('ffi')
package.preload.encoding=function()return{UTF8={decode=function(_,s)return s end,encode=function(_,s)return s end}}end
getWorkingDirectory=function()return '/tmp/palatka_ui22_harness'end
doesDirectoryExist=function()return true end
createDirectory=function()end
encodeJson=function()return '{}'end
decodeJson=function()return {}end
local function noop()end
-- GetStyle exposes the live color array; pushes restore exact previous values.
do
    local model=Harness.new(800,360);local im=model.imgui;local index=im.Col.WindowBg
    local original=im.GetStyle().Colors[index]
    im.PushStyleColor(index,im.ImVec4(.1,.2,.3,.4))
    assert(im.GetStyle().Colors[index].x==.1 and im.GetStyle().Colors[index].w==.4)
    im.PushStyleColor(index,0xff0000ff)
    assert(im.GetStyle().Colors[index].x==1 and im.GetStyle().Colors[index].z==0)
    im.PopStyleColor();assert(im.GetStyle().Colors[index].x==.1)
    im.PopStyleColor();assert(im.GetStyle().Colors[index].x==original.x)
    assert(im.GetColorU32(index)~=0,'drawlist colors use the current style array')
    model:finish_frame()
end
local function fixture(sw,sh)
    local h=Harness.new(sw,sh);imgui=h.imgui;DSP=nil
    for _,name in ipairs({'00_core','05_items','10_market','11_arbitrage','12_arbitrage_groups','20_presets','21_preset_library'})do dofile('src/'..name..'.lua')end
    DSP.save_settings=function()return true end;DSP.save_ui_state=noop
    DSP.notify=function(msg)h.notification=msg end;DSP.flog=function(msg)h.logged=msg end
    if sw==2340 then DSP.settings.mobile_window={x=426,y=136,w=1450,h=790}end
    DSP.ui={open_ref=ffi.new('bool[1]',true),d=1.25,set_open=noop}
    DSP.screens={list={},set=function(id)DSP.ui.screen=id end,draw=function(id)error('unhandled screen '..id)end}
    for _,id in ipairs({'palatka','lavki','arbitrage','search','logs','stats','notes','settings'})do DSP.screens.list[#DSP.screens.list+1]={id=id}end
    DSP.auto={inv={},scan_inventory=function()h.scanned=true end,
        start_sell=function()DSP.auto.sell_running=true end,start_buy=function()DSP.auto.buy_running=true end,
        stop_sell=function()DSP.auto.sell_running=false end,stop_buy=function()DSP.auto.buy_running=false end}
    DSP.items.by_id={}
    for i=1,80 do
        local name=string.format('Inventory item %02d',i)
        DSP.auto.inv[i]={name=name,count=20,stacks={{slot=i,count=20}}}
        DSP.items.by_id[i]=name
    end
    local M={defer_save=noop,flush_save=noop,touch_scroll=noop,buffers=setmetatable({},{__mode='k'})}
    DSP.mobile=M
    M.thumbnail=function(_,size)imgui.Dummy(imgui.ImVec2(size,size))end
    M.edit_buffer=function(item,key)
        local cache=M.buffers[item];if not cache then cache={};M.buffers[item]=cache end
        if not cache[key]then cache[key]=ffi.new('char[64]');local s=tostring(item[key]or 0);ffi.copy(cache[key],s,#s)end
        return cache[key]
    end
    M.refresh_buffer=function(item,key)if M.buffers[item]then M.buffers[item][key]=nil end end
    M.compact_number=function(item,key,id,w,min)
        local buffer=M.edit_buffer(item,key);imgui.SetNextItemWidth(w or 140)
        if imgui.InputText('##compact_'..id,buffer,64)then
            local value=tonumber(ffi.string(buffer))
            if value and value%1==0 and value>=(min or 0)then item[key]=value;return true end
        end
        return false
    end
    DSP.log={};DSP.logs={export_logs=function()h.exported=true end}
    local events={}
    for i=1,40 do events[i]={ts=os.time(),kind='income',amount=i,raw='Chat event '..i,item_name='Wood',source='Fixture'}end
    DSP.craglog={history=function()return events end,filtered=function()return events end,describe=function(e)return e.raw end,
        summary=function()return{income=200,expense=100,net=100,count=#events}end,set_pinned=noop,
        delete_event=function(entry)for i,e in ipairs(events)do if e==entry then table.remove(events,i);return true end end;return false end}
    for _,name in ipairs({'37_trade_v16','40_mobile_notes','43_calculator_nav','57_journal_v16','59a_loot_summary'})do dofile('src/'..name..'.lua')end
    local shops={}
    for shop=1,5 do
        local row={server_id=102,shop_num=shop,owner='Player_'..shop,updated_at=os.time(),sell_slots={},buy_slots={}}
        for i=1,24 do
            local slot={name=string.format('Market item %02d',i),ench=0,price=shop<=3 and(100+shop*10)or(200+shop*10),qty=shop<=3 and 3 or 700}
            table.insert(shop<=3 and row.sell_slots or row.buy_slots,slot)
        end
        shops[#shops+1]=row
    end
    DSP.settings.arb_filters={max_age=0};DSP.market.rebuild({shops=shops},102)
    DSP.market.pull=function()h.pulled=true end
    DSP.market.mark_shop=function(id)h.marked=id end
    for i=1,35 do DSP.settings.notes=DSP.settings.notes or{};DSP.settings.notes[i]={id=tostring(i),title='Note '..i,text='Body '..i,updated_at=i}end
    for _,name in ipairs({'60_ui21_shell','61_ui21_trade','62_ui21_shops','63_ui21_arbitrage','64_ui21_journal_calc','65_ui22_tools','66_ui22_journal'})do dofile('src/'..name..'.lua')end
    h.V=DSP.ui21
    local baseline={}
    for index,c in pairs(imgui.GetStyle().Colors)do baseline[index]={x=c.x,y=c.y,z=c.z,w=c.w}end
    local row=h.V.row
    h.V.row=function(id,height,draw)
        local start=imgui.GetCursorScreenPos();local before=#h.rects
        row(id,height,draw)
        for i=before+1,#h.rects do local r=h.rects[i]
            if r.control and r.y+r.h>start.y+height+.1 then
                h.violations[#h.violations+1]='row overflow '..id..' '..r.id..' bottom='..(r.y+r.h)..' row_end='..(start.y+height)
            end
        end
    end
    function h:draw(screen,bounds)
        if screen then self.V.set_screen(screen)end
        self:begin_frame()
        local ok,err=pcall(DSP.ui.draw)
        local problems={};for id,message in pairs(self.V.errors)do problems[#problems+1]=id..': '..message end
        assert(#problems==0,table.concat(problems,'\n'))
        assert(ok,err);self:finish_frame()
        assert(not DSP.theme._push_error,DSP.theme._push_error)
        for index,c in pairs(baseline)do
            local restored=imgui.GetStyle().Colors[index]
            assert(restored.x==c.x and restored.y==c.y and restored.z==c.z and restored.w==c.w,'theme color did not restore after frame')
        end
        local palette=DSP.theme.get()
        for _,window in ipairs(self.windows)do
            local expected=window.kind=='window'and palette.bg or palette.panel
            local applied=window.background
            assert(applied.x==expected[1]and applied.y==expected[2]and applied.z==expected[3],
                'window uses a color other than the active theme: '..window.key)
            if window.kind=='window'then assert(applied.w==DSP.theme.opacity,'explicit window alpha is applied')end
        end
        if bounds then self:assert_bounds()end
    end
    function h:act(id,screen)self:click(id);self:draw(screen)end
    return h
end
local sizes={{800,360},{925,512},{1120,650},{2340,1080}}
local bounds_failures={}
local function capture(h,name)
    for _,problem in ipairs(h.violations)do bounds_failures[#bounds_failures+1]=h.width..'x'..h.height..' '..name..' '..problem end
end
for _,size in ipairs(sizes)do
    local h=fixture(size[1],size[2])
    for _,screen in ipairs({'palatka','lavki','arbitrage','search','logs','stats','notes','settings','calculator'})do
        h:draw(screen)
        capture(h,screen)
    end
    h:draw('settings');for i=1,5 do h.V.tools_section=i;h:draw();capture(h,'settings'..i)end
    h:act('v22_menu','palatka');assert(h.V.nav,'drawer opens');capture(h,'drawer_trade');h:draw();capture(h,'drawer_trade_idle')
    h:act('v22_nav_2');assert(h.V.screen=='lavki'and not h.V.nav,'legacy screen IDs preserved by navigation')
    h:draw('arbitrage');h:act('v22_arb_group_1');capture(h,'arb_details')
    h:act('v22_arb_close_details')
    h:draw('notes');h:act('v22_tools22_note_open_1');capture(h,'notes_editor')
    h:act('v22_tools22_note_delete');capture(h,'notes_delete_modal');h:act('v22_tools22_note_delete_cancel')
    for _,kind in ipairs({'sell','buy'})do
        local p=DSP.settings[kind..'_preset'];p.items={}
        for i,it in ipairs(DSP.auto.inv)do p.items[i]={name=it.name,key=DSP.item_key(it.name,0),ench=0,qty=1,price=100,enabled=true}end
        h.V.kind=kind;h.V.tab='preset';h.V.nav=true;h:draw('palatka');capture(h,'drawer_preset_'..kind)
    end
    h.V.nav=false;h:draw();h:act('v22_trade_manage');capture(h,'preset_library_modal')
    h.opened={};h:draw()
    h:act('v22_trade_launch');capture(h,'launch_modal')
    h:act('v22_trade_review');h:draw();capture(h,'review_modal')
    h:act('v22_cancel_review')
    h:act('v22_trade_quantity_1');capture(h,'quantity_modal')
    h:act('v22_trade_max_qty');capture(h,'quantity_limit_modal')
    h:act('v22_trade_qty_done')
    h.V.journal_mode='events';h:draw('logs');h:act('v22_tools_entry_1');capture(h,'event_modal');h.opened={};h:draw()
end
local h=fixture(1120,650);local V=h.V
h:draw('palatka');h:act('v22_trade_add_1')
assert(V.tab=='items'and #DSP.settings.sell_preset.items==1,'adding inventory keeps items tab open')
local up=h:find('v22_scroll_up_items_sell_inventory');local down=h:find('v22_scroll_down_items_sell_inventory')
assert(not up and not down,'fixed scroll arrows are removed from touch lists')
V.queue_scroll('items_sell_inventory',1,300);h:draw()
assert(V.scrolls.items_sell_inventory.y>0,'list still supports programmatic/touch scrolling without arrows')
h:edit('v22_query_items','Inventory item 80');h:draw()
assert(h:find('v22_trade_add_1')and h:find('v22_trade_add_1').visible,'search reduces long list')
h:act('v22_trade_add_1');assert(#DSP.settings.sell_preset.items==2)
h:act('v22_trade_preset_tab')
h:edit('compact_v22_price_sell1','125');h:edit('compact_v22_qty_sell1','4');h:draw()
assert(DSP.settings.sell_preset.items[1].price==125 and DSP.settings.sell_preset.items[1].qty==4,'inline edits reach actual preset')
local pr=h:find('compact_v22_price_sell1');local qr=h:find('compact_v22_qty_sell1')
assert(pr and qr and math.abs(pr.y-qr.y)<1 and pr.x+pr.w<=qr.x,'price and quantity stay in distinct inline columns')
h:act('v22_trade_remove_1');assert(#DSP.settings.sell_preset.items==2)
h:act('v22_cancel_remove');assert(#DSP.settings.sell_preset.items==2,'cancel keeps preset item')
h:act('v22_trade_remove_1');h:act('v22_trade_confirm_remove');assert(#DSP.settings.sell_preset.items==1,'confirmed modal removes selected item')
h:draw('lavki');h:act('v22_shops_item_1');h:act('v22_shops_detail_1')
assert(V.offer_detail and next(h.opened),'offer opens modal from scoped child row')
h:act('v22_shops_open_stall');assert(V.shop_detail,'offer opens whole stall')
h:draw();assert(h:find('v22_shops_stall_buy'),'whole stall contains both sides')
h:draw('arbitrage');h:act('v22_arb_group_1')
local group=V.arb_group(DSP.market.arbitrage_grouped());assert(group)
local p=V.arb_plan(group);assert(p.qty==9 and p.demand==1400,'manual plan never replaces raw demand with allocation')
h:act('v22_arb_select_1');p=V.arb_plan(group);assert(p.qty==6,'multiple selected seller stock is recalculated')
h:act('v22_arb_buy');h:act('v22_arb_select_1');p=V.arb_plan(group)
assert(p.qty==6 and p.demand==700,'buyer deselection preserves single remaining demand')
h:act('v22_arb_route');assert(V.arb_route,'route view opens')
h:act('v22_arb_route_sell_1');assert(h.marked,'route pin action reaches engine')
imgui=h.imgui
-- Close modal through its actual visible control, or the route back and close path.
h:act('v22_arb_back_offers');h:act('v22_arb_close_details')
h:draw('notes');h:act('v22_tools22_note_open_1');assert(DSP.ui.note_current)
h:act('v22_tools22_note_delete');local note_count=#DSP.settings.notes;local deleted_title=DSP.ui.note_current.title
h:act('v22_tools22_note_delete_cancel');assert(#DSP.settings.notes==note_count)
h:act('v22_tools22_note_delete');h:act('v22_tools22_note_delete_confirm')
assert(#DSP.settings.notes==note_count-1 and DSP.ui.note_current==nil,'notes modal cancel then delete works')
h:draw('notes')
assert(not h:find('v22_tools22_note_open_1').label:find(deleted_title,1,true),'deleted note vanishes from cached list immediately')
h:draw('calculator')
for _,id in ipairs({'v22_tools_calc_42','v22_tools_calc_44','v22_tools_calc_43','v22_tools_calc_54','v22_tools_calc_54'})do h:act(id)end
assert(DSP.calc_v16.display=='8','calculator computes 2 + 3 = = through actual keypad')
h:edit('v22_finance_buy','100');h:edit('v22_finance_sell','150')
h:edit('v22_finance_qty','3');h:edit('v22_finance_commission','0.5');h:edit('v22_finance_extra','2.5');h:draw()
assert(V.finance.commission==.5 and V.finance.extra==2.5,'fractional fees and expenses survive finance inputs')
local finance=DSP.calc_v16.finance(V.finance.buy,V.finance.sell,V.finance.qty,V.finance.commission,V.finance.extra)
assert(math.abs(finance.profit-145.25)<.001,'finance output applies decimal fee and expense')
h:act('v22_tools_history');assert(next(h.opened),'history opens as actual scoped modal')
h:act('v22_tools_calc_history_close')

-- The shell catches render errors: this regression proves the test still fails.
local good_dsp,good_imgui=DSP,imgui
local bad=fixture(925,512)
bad.V.trade=function()imgui.UnsupportedMustFail()end
local caught,message=pcall(function()bad:draw('palatka')end)
assert(not caught and message:find('unsupported imgui.UnsupportedMustFail',1,true),
    'caught UI exceptions must fail the test instead of becoming a false PASS')
DSP,imgui=good_dsp,good_imgui
-- Fail explicitly after collecting all compact-size geometry evidence.
if #bounds_failures>0 then
    for i=1,math.min(48,#bounds_failures)do io.stderr:write(bounds_failures[i]..'\n')end
    error('UI22 geometry violations: '..#bounds_failures)
end
print('UI22 strict runtime: nine screens, navigation, scroll, inline edits, allocator, modal cancel/delete, calculator: ok')

-- Floating journal: cash figures remain outside its scrolling child.
do
    local h=fixture(1120,650);DSP.settings.craglog={open=true,mini_mode='events',summary_period='all'}
    DSP.craglog.set_pinned=function()end;DSP.craglog.end_drag=function()end
    h:begin_frame();DSP.craglog.draw();h:finish_frame()
    local seen={}
    for _,r in ipairs(h.rects)do
        if r.label=='Доход'or r.label=='Расход'or r.label=='Итог'then
            seen[r.label]=true;assert(not r.container:find('v22_list',1,true),'totals must remain fixed')
        end
    end
    assert(seen['Доход']and seen['Расход']and seen['Итог'],'mini income/expense/net are visible')
    assert(#h.violations==0,table.concat(h.violations,'\n'))
end

return {fixture=fixture}
