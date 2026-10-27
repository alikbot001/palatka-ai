-- Scan UI contract: observed data, stable selection and explicit preset mutations.
local UI=dofile('tests/test_v22_ui.lua')
local failures={}
local function check(name,fn)local ok,err=pcall(fn);if not ok then failures[#failures+1]=name..': '..tostring(err)end end
local function fixture(w,h)
 local host=UI.fixture(w,h)
 local scan={owner='Observed_Owner',num=42,updated=os.time(),revision=1,generation=1,server=102,closed=false,
  sell={{key='sell:1',name='Observed item',item_id=1,price=123,qty=8,qty_known=true},
   {key='sell:2',name='Unknown count item',item_id=2,price=456,qty_known=false}},
  buy={{key='buy:3',name='Buy item',item_id=3,price=99,qty=4,qty_known=true}}}
 local calls={}
 DSP.shop_scan={snapshot=function()return scan end,
  copy_to_preset=function(side,options)
   calls[#calls+1]={method='copy',side=side,options=options}
   return{ok=true,count=1,index=options.index or 2,unknown_qty=1}
  end,
  apply_prices=function(side,index,options)
   calls[#calls+1]={method='prices',side=side,index=index,options=options}
   return{ok=true,count=1,index=index}
  end}
 DSP.shop_marker={set_enabled=function(value)DSP.settings.marker_3d_enabled=value;calls.marker=value end}
 assert(loadfile('src/67_ui22_shop_scan.lua'))()
 host:draw('lavki');host:act('v22_shops_source_scan')
 return host,scan,calls
end
for _,size in ipairs({{800,360},{925,512},{1120,650},{2340,1080}})do
 check('scan geometry '..size[1]..'x'..size[2],function()
  local h,scan,calls=fixture(size[1],size[2]);h:assert_bounds()
  local observed,unknown=false,false
  for _,r in ipairs(h.rects)do
   if r.label:find('Observed_Owner',1,true)then observed=true end
   if r.label:find('неизвестно',1,true)then unknown=true end
  end
  assert(observed and unknown,'observed owner or unknown quantity missing')
  h:act('v22_scan_select_sell:1');assert(h.V.scan_selection.sell['sell:1'])
  scan.revision=2;scan.sell[1].price=124;h:draw()
  assert(h.V.scan_selection.sell['sell:1'],'refresh discarded selection by stable slot key')
  h:act('v22_scan_copy');h:assert_bounds()
  assert(h:find('v22_scan_confirm')and h:find('v22_scan_confirm').visible,'copy confirmation hidden')
  h:act('v22_cancel_scan_preset');assert(#calls==0,'cancel performed mutation')
  h:act('v22_scan_copy');h:act('v22_scan_confirm')
  assert(#calls==1 and calls[1].method=='copy'and calls[1].side=='sell')
  assert(calls[1].options.selected['sell:1']and not calls[1].options.selected['sell:2'],'copy ignored selection')
  assert(calls[1].options.markup==0 and calls[1].options.target_side=='sell','copy defaults changed user price or side')
  assert(calls[1].options.expected_revision==2 and calls[1].options.expected_generation==1 and calls[1].options.expected_server==102,'copy lost snapshot concurrency guards')
  h:act('v22_scan_prices');h:assert_bounds();h:act('v22_scan_confirm')
  assert(calls[2].method=='prices'and calls[2].side=='sell'and calls[2].options.selected['sell:1'],'explicit selected price update missing')
  h:act('v22_scan_buy');h:act('v22_scan_select_buy:3');h:act('v22_scan_copy')
  h:act('v22_scan_new');h:edit('v22_scan_preset_name','Named capture');h:edit('v22_scan_markup','-1');h:draw();h:assert_bounds()
  h:act('v22_scan_confirm')
  assert(calls[3].side=='buy'and calls[3].options.name=='Named capture'and calls[3].options.markup==-1)
  assert(calls[3].options.target_side=='buy','buy scan defaulted to sale preset')
  scan.owner='Other_Owner';scan.num=43;scan.revision=3;h:draw()
  assert(not next(h.V.scan_selection.sell)and not next(h.V.scan_selection.buy),'new stall inherited selections')
  h:act('v22_shops_marker_toggle');assert(calls.marker==false,'3D toggle not delegated')
  h:act('v22_shops_source_api');assert(h.V.shops_source=='api','API browser removed')
  h:assert_bounds()
 end)
end
check('copy never edits existing prices before domain confirmation',function()
 local h,scan,calls=fixture(925,512)
 local item={name='Observed item',key=DSP.item_key('Observed item',0),ench=0,price=777,qty=20,enabled=true,cost_price=50}
 DSP.settings.sell_preset.items={item}
 h:act('v22_scan_select_sell:1');h:act('v22_scan_copy');h:act('v22_scan_confirm')
 assert(item.price==777 and item.qty==20 and item.cost_price==50,'scan UI overwrote existing preset values')
 assert(calls[1].method=='copy','copy secretly used update-prices API')
end)
check('replaced slot and reopened stall cannot inherit a different selection',function()
 local h,scan=fixture(925,512)
 h:act('v22_scan_select_sell:1')
 scan.sell[1].name='Replacement';scan.sell[1].item_id=77;scan.revision=2;h:draw()
 assert(not h.V.scan_selection.sell['sell:1'],'replacement item inherited old slot selection')
 h:act('v22_scan_select_sell:1');scan.generation=2;scan.revision=3;h:draw()
 assert(not h.V.scan_selection.sell['sell:1'],'reopening same owner/number retained selection')
 h:act('v22_scan_select_sell:1');h:act('v22_scan_copy')
 scan.revision=4;scan.sell[1].price=999;h:act('v22_scan_confirm');h:draw()
 assert(h:find('v22_scan_confirm').visible,'stale snapshot closed confirmation as success')
end)
check('preset shortcut follows the explicitly chosen destination side',function()
 local h,scan,calls=fixture(925,512)
 h:act('v22_scan_select_sell:1');h:act('v22_scan_copy');h:act('v22_scan_target_buy');h:act('v22_scan_confirm')
 assert(calls[1].options.target_side=='buy')
 h:act('v22_scan_presets');assert(h.V.kind=='buy','preset shortcut opened source side instead of selected destination')
 h:assert_bounds()
end)
check('empty scan and failed domain operation stay truthful',function()
 local h,scan,calls=fixture(925,512)
 scan.sell={};scan.buy={};scan.revision=3;scan.owner='';scan.num=nil;scan.updated=0
 h:draw();h:assert_bounds()
 local found=false;for _,r in ipairs(h.rects)do if r.label:find('Откройте лавку',1,true)then found=true end end
 assert(found,'empty scan lacks game-open instruction')
 h:act('v22_scan_copy');assert(#calls==0,'empty scan copied anything')
 scan.sell={{key='sell:9',name='Observed item',price=5,qty=1,qty_known=true}};scan.revision=4
 h:draw();h:act('v22_scan_select_sell:9');h:act('v22_scan_copy')
 DSP.shop_scan.copy_to_preset=function()return{ok=false,error='disk full'}end
 h:act('v22_scan_confirm');h:draw();assert(h:find('v22_scan_confirm').visible,'failed copy closed modal')
 local error_seen=false;for _,r in ipairs(h.rects)do if r.label:find('disk full',1,true)then error_seen=true end end
 assert(error_seen,'domain error hidden')
end)
check('real live packets reach copy and explicit price update without overwriting values',function()
 local h=fixture(925,512)
 DSP.db={learn=function()return true end}
 dofile('src/45_live.lua');dofile('src/46_shop_scan.lua')
 local L=DSP.live
 L.handle_shop_owner('{"name":"Live_Owner","shopNum":75}')
 L.handle(60,0,'{"type":13,"slot":0,"item":1,"amount":123,"qty":8}')
 L.handle(60,0,'{"type":13,"slot":1,"item":2,"amount":456}')
 L.handle(60,0,'{"type":28,"slot":3,"item":3,"amount":99,"qty":4}')
 local old={name=DSP.items.name(1),key=DSP.item_key(DSP.items.name(1),0),ench=0,price=777,qty=20,enabled=true,cost_price=50}
 DSP.settings.sell_preset.items={old};h:draw()
 assert(DSP.presets.create('sell','Other existing sell'));assert(DSP.presets.select('sell',1))
 h:act('v22_scan_select_sell:0');h:act('v22_scan_select_sell:1')
 h:act('v22_scan_copy');h:act('v22_scan_preset_2');h:act('v22_scan_confirm')
 assert(#DSP.presets.list('sell')[2].items==2 and #DSP.presets.list('sell')[1].items==1,'chosen existing preset ignored')
 assert(DSP.presets.select('sell',1))
 h:act('v22_scan_copy');h:act('v22_scan_confirm')
 assert(old.price==777 and old.qty==20 and old.cost_price==50,'copy overwrote existing values')
 assert(#DSP.settings.sell_preset.items==2,'selected new item missing')
 local added=DSP.settings.sell_preset.items[2]
 assert(added.price==456 and added.qty==1 and not added.enabled and added.source_qty_unknown,'unknown count became observed stock')
 h:act('v22_scan_prices');h:act('v22_scan_confirm')
 assert(old.price==123 and old.qty==20 and old.cost_price==50 and old.enabled,'explicit update changed non-price fields')
 h:act('v22_scan_buy');h:act('v22_scan_select_buy:3');h:act('v22_scan_copy');h:act('v22_scan_new')
 h:edit('v22_scan_preset_name','Live named buy');h:edit('v22_scan_markup','-1');h:draw();h:act('v22_scan_confirm')
 local target=DSP.settings.buy_preset
 assert(target.name=='Live named buy'and target.items[1].price==98 and target.items[1].qty==4 and target.items[1].enabled)
 h:assert_bounds()
end)
for _,err in ipairs(failures)do io.stderr:write(err..'\n')end
assert(#failures==0,tostring(#failures)..' scan UI regressions')
print('v22 shop scan UI: API switch, observed rows, modal copy/update, stable selection, geometry: OK')
