-- Pure planning totals plus fixed-footer geometry in the strict ImGui model.
local failures={}
local function check(name,fn)local ok,err=pcall(fn);if not ok then failures[#failures+1]=name..': '..tostring(err)end end
local function workflow()
    DSP={ui={},mobile={refresh_buffer=function()end,defer_save=function()end},auto={inv={}},
        settings={tax_bp=200,sell_preset={name='Sell',items={}},buy_preset={name='Buy',items={}}},
        save_settings=function()return true end,add_log=function()end,text_cp=function(s)return s end,
        item_name=function(s)return s end,item_key=function(s,e)return s..'|'..tostring(e or 0)end}
    dofile('src/20_presets.lua');dofile('src/21_preset_library.lua');dofile('src/37_trade_v16.lua')
    return DSP.trade_v16
end
local function rows()return{{name='A',price=100,qty=3,cost_price=40},
    {name='B',price=250,qty=2,cost_price=100},{name='Disabled',price=999,qty=100,enabled=false}}end
check('sell gross fee net known cost and disabled exclusions',function()
    local T=workflow();assert(T.calculate_totals,'totals API missing')
    local items=rows();local r=T.calculate_totals('sell',items,200)
    assert(r.complete and r.positions==2 and r.qty==5 and r.gross==800,'included rows')
    assert(r.commission==16 and r.net==784 and r.cost==320 and r.profit==464,'sale arithmetic')
    assert(items[1].cost_price==40 and items[1].enabled==nil,'pure total mutated inputs')
end)
check('buy budget has no sale commission or invented profit',function()
    local T=workflow();local r=T.calculate_totals('buy',rows(),200)
    assert(r.required_funds==800 and r.commission==0 and r.positions==2 and r.qty==5,'buy budget')
    assert(r.profit==nil,'buy profit was inferred')
end)
check('unknown cost differs from explicit free loot',function()
    local T=workflow();local items={{name='Old preset',price=100,qty=2}}
    local r=T.calculate_totals('sell',items,200)
    assert(r.net==196 and r.profit==nil and r.unknown_cost==1,'unknown cost invented')
    items[1].cost_price=0;r=T.calculate_totals('sell',items,200)
    assert(r.cost==0 and r.profit==196 and r.unknown_cost==0,'explicit free cost rejected')
    r=T.calculate_totals('sell',items,200,{[items[1]]={cost_price=true}})
    assert(r.net==196 and r.profit==nil,'invalid visible cost used old number')
end)
check('invalid visible values never expose a guaranteed full total',function()
    local T=workflow();local items=rows()
    local r=T.calculate_totals('buy',items,200,{[items[1]]={price=true}})
    assert(not r.complete and r.invalid==1 and r.required_funds==nil,'stale price used in budget')
    items[1].qty=0;r=T.calculate_totals('sell',items,200)
    assert(not r.complete and r.gross==nil and r.net==nil and r.profit==nil,'invalid quantity included')
end)
check('overflow nonfinite and per-lot rounding',function()
    local T=workflow();local max=9007199254740991
    for _,value in ipairs({0/0,math.huge,-1,max+1})do
        local r=T.calculate_totals('buy',{{price=value,qty=2}},200)
        assert(not r.complete and r.required_funds==nil,'unsafe number accepted')
    end
    local r=T.calculate_totals('buy',{{price=max,qty=2}},200)
    assert(r.overflow and r.required_funds==nil,'product overflow')
    r=T.calculate_totals('buy',{{price=max,qty=1},{price=1,qty=1}},200)
    assert(r.overflow and r.required_funds==nil,'sum overflow')
    r=T.calculate_totals('sell',{{price=max,qty=1,cost_price=0}},200)
    assert(r.complete and r.net+r.commission==max and r.net<=max,'commission overflow')
    r=T.calculate_totals('sell',{{price=1,qty=1,cost_price=0},{price=1,qty=1,cost_price=0}},200)
    assert(r.net==0 and r.commission==2,'commission must round per position')
    r=T.calculate_totals('sell',{{price=1,qty=2,cost_price=max}},200)
    assert(r.complete and r.gross==2 and r.cost_overflow and r.profit==nil,'cost overflow became guessed profit')
end)
check('cost survives preset export and import',function()
    workflow();DSP.presets.list('sell');DSP.settings.sell_preset.items=rows()
    local exported=DSP.presets.export_data('sell');assert(DSP.presets.import_data(exported,'sell'))
    assert(DSP.settings.sell_preset.items[1].cost_price==40,'import discarded optional cost')
    DSP.settings.sell_preset.items[1].cost_price=0
    assert(DSP.presets.import_data(DSP.presets.export_data('sell'),'sell'))
    assert(DSP.settings.sell_preset.items[1].cost_price==0,'import discarded explicit free cost')
    assert(DSP.settings.sell_preset.items[3].cost_price==nil,'legacy unknown cost became free')
end)
for _,err in ipairs(failures)do io.stderr:write(err..'\n')end
assert(#failures==0,tostring(#failures)..' trade totals regressions')
local UI=dofile('tests/test_v22_ui.lua')
for _,size in ipairs({{800,360},{925,512},{1120,650},{2340,1080}})do
    local h=UI.fixture(size[1],size[2]);local V=h.V
    for _,kind in ipairs({'sell','buy'})do
        DSP.settings[kind..'_preset'].items=rows();V.kind=kind
        for _,tab in ipairs({'items','preset'})do
            V.tab=tab;h:draw('palatka');h:assert_bounds()
            local launch=h:find('v22_trade_launch');assert(launch and launch.visible,'launch action clipped')
            local found={}
            for _,r in ipairs(h.rects)do
                if r.label:find(kind=='buy'and'Бюджет'or'Выручка',1,true)or(kind=='sell'and r.label:find('Чистыми',1,true))then
                    found[#found+1]=r;assert(not r.container:find('v22_list',1,true),'totals scrolled with rows')
                    assert(r.visible and r.y+r.h<=r.clip.y+r.clip.h+.1,'totals clipped vertically')
                    assert(r.x+r.w<=r.clip.x+r.clip.w+.1,'totals clipped horizontally')
                end
            end
            assert(#found==(kind=='sell'and 2 or 1),'fixed trade financial totals missing')
            for _,r in ipairs(found)do
                assert(r.y+r.h<=launch.y,'financial text overlaps launch actions')
            end
            local key=tab=='items'and('items_'..kind..'_'..V.source)or('preset_'..kind..'_'..tostring(DSP.settings[kind..'_preset']))
            local old_y=launch.y;V.queue_scroll(key,1,100);h:draw();h:assert_bounds()
            assert(h:find('v22_trade_launch').y==old_y,'launch moved while scrolling')
        end
    end
    V.kind='sell';V.tab='preset';V.reset_list('preset_sell_'..tostring(DSP.settings.sell_preset))
    h:draw('palatka');h:act('v22_trade_name_1')
    local input=h:find('compact_v22_cost');assert(input and input.visible,'cost editor missing from existing item popup')
    h:edit('compact_v22_cost','0');h:draw();assert(DSP.settings.sell_preset.items[1].cost_price==0,'explicit free cost not saved')
    h:act('v22_trade_cost_unknown');assert(DSP.settings.sell_preset.items[1].cost_price==nil,'cost cannot return to unknown')
    h:assert_bounds();h:act('v22_trade_info_close')
    local item=DSP.settings.sell_preset.items[1]
    DSP.mobile.invalid_edits={[item]={price=true}};h:draw()
    local incomplete=false
    for _,r in ipairs(h.rects)do if r.label:find('итог не рассчитан',1,true)then incomplete=true end end
    assert(incomplete,'invalid visible edit still showed guaranteed totals')
    DSP.mobile.invalid_edits={};DSP.settings.sell_preset.items={{name='Big',price=9007199254740991,qty=1,cost_price=0}}
    h:draw();local exact=false
    for _,r in ipairs(h.rects)do if r.label:find('Выручка',1,true)then
        exact=r.label:find('9.007.199.254.740.991',1,true)~=nil
    end end
    assert(exact,'safe large amount was formatted in scientific notation')
end
print('v22 trade totals: exact planning arithmetic, optional costs, fixed footer viewports: OK')
