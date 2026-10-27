-- Regression coverage for validated edits and immutable listing requests.
local failures=0
local function check(name,fn)
 local ok,err=pcall(fn)
 if ok then print('PASS '..name) else failures=failures+1;print('FAIL '..name..': '..tostring(err)) end
end
local function workflow()
 DSP={ui={},mobile={refresh_buffer=function()end,defer_save=function()end},
  auto={inv={}},settings={sell_preset={name='Sell',items={}},buy_preset={name='Buy',items={}}},
  save_settings=function()return true end,add_log=function()end,text_cp=function(s)return s end,
  item_name=function(s,e)return e>0 and s..' (+'..e..')' or s end,
  item_key=function(s,e)return s..'|'..tostring(e) end}
 assert(loadfile('src/20_presets.lua'))();assert(loadfile('src/21_preset_library.lua'))()
 assert(loadfile('src/37_trade_v16.lua'))()
 return DSP.trade_v16
end
check('zero and invalid inventory counts never become one',function()
 local t=workflow()
 for _,n in ipairs({0,-1,1.5,0/0,math.huge,9007199254740992}) do
  assert(not t.add_from_inventory('sell',{name='Item',count=n}),'accepted count '..tostring(n))
 end
 assert(#DSP.settings.sell_preset.items==0)
end)
check('all owned stacks aggregate when adding the item',function()
 local t=workflow()
 DSP.auto.inv={{name='Item',count=2,stacks={{slot=1,count=2}}},
  {name='Item',count=3,stacks={{slot=2,count=3}}}}
 assert(t.add_from_inventory('sell',DSP.auto.inv[1]))
 assert(DSP.settings.sell_preset.items[1].qty==5)
 DSP.auto.inv[#DSP.auto.inv+1]={name='Item',count=2,stacks={{slot=1,count=2}}}
 local it=DSP.settings.sell_preset.items[1];it.price=50;it.enabled=true
 assert(t.validate('sell'))
 it.qty=6;assert(not t.validate('sell'),'duplicate snapshot slot inflated availability')
end)
check('invalid edit buffers block listing until corrected',function()
 local t=workflow();local it={name='Item',ench=0,qty=1,price=50,enabled=true}
 DSP.settings.buy_preset.items={it}
 DSP.mobile.invalid_edits=setmetatable({[it]={price=true}},{__mode='k'})
 assert(not t.validate('buy'),'invalid visible price was listed using old model')
 DSP.mobile.invalid_edits[it]=nil;assert(t.validate('buy'))
end)
check('nonfinite oversized and unsafe totals are rejected',function()
 local t=workflow();local it={name='Item',ench=0,qty=1,price=50,enabled=true}
 DSP.settings.buy_preset.items={it}
 for _,n in ipairs({0/0,math.huge,-math.huge,9007199254740992}) do
  it.price=n;assert(not t.validate('buy'),'accepted price '..tostring(n))
  it.price=50;it.qty=n;assert(not t.validate('buy'),'accepted qty '..tostring(n))
 end
 it.price=9007199254740991;it.qty=2;assert(not t.validate('buy'),'unsafe total accepted')
end)
local function engine()
 local dialog,threads,requests=nil,{},{}
 DSP={settings={buy_preset={items={}},sell_preset={items={}},dry_run=false},market={},
  add_log=function()end,notify=function()end,money=tostring}
 sampIsDialogActive=function()return dialog~=nil end
 sampGetCurrentDialogId=function()return dialog and dialog.id or -1 end
 sampGetDialogText=function()return dialog and dialog.text or '' end
 wait=function()end;lua_thread={create=function(fn)threads[#threads+1]=fn end}
 sampSendChat=function()end
 sampSendDialogResponse=function(id,btn,idx,text)
  if btn==0 then dialog=nil;return end
  if id==3040 then dialog={id=25663,text='Search'}
  elseif id==25663 then dialog={id=25664,text='Item'}
  elseif id==25664 then dialog={id=26563,text='Item quantity'}
  elseif id==26563 or id==26547 then
   requests[#requests+1]=text;dialog=nil
   if id==26547 then DSP.auto.on_dialog(9000,0,'','','','Успешно выставлено на продажу') end
  end
 end
 for _,m in ipairs({'39_trade_runtime','40_auto','41_trade_listing','42_trade_buy'}) do assert(loadfile('src/'..m..'.lua'))() end
 _G.dsp_click_slot=function(interface)
  if interface==60 then dialog={id=26547,text='Item quantity'} else dialog={id=3040,text='Shop'} end
 end
 return threads,requests
end
check('buy queue preserves launch price quantity and test mode',function()
 local threads,requests=engine();local it={name='Item',price=50,qty=2,enabled=true}
 DSP.settings.buy_preset.items={it};DSP.auto.start_buy()
 it.price=99;it.qty=8;it.name='Wrong';it.enabled=false
 threads[1]();assert(requests[1]=='2,50','buy request changed after launch: '..tostring(requests[1]))
 threads,requests=engine();DSP.settings.dry_run=true
 DSP.settings.buy_preset.items={{name='Item',price=50,qty=2,enabled=true}}
 DSP.auto.start_buy();DSP.settings.dry_run=false;threads[1]()
 assert(#requests==0,'test run became real after launch')
end)
check('sell queue preserves launch values and aggregates disjoint stacks',function()
 local threads,requests=engine();local it={name='Item',ench=0,price=50,qty=5,enabled=true}
 DSP.settings.sell_preset.items={it}
 DSP.auto.inv={{name='Item',count=2,stacks={{slot=1,count=2}}},{name='Item',count=3,stacks={{slot=2,count=3}}}}
 DSP.auto.start_sell();it.price=99;it.qty=8;it.name='Wrong';threads[1]()
 assert(#requests==2 and requests[1]=='2,50' and requests[2]=='3,50','sell queue did not use both stacks')
 threads,requests=engine();DSP.settings.dry_run=true
 DSP.settings.sell_preset.items={{name='Item',price=50,qty=2,enabled=true}}
 DSP.auto.inv={{name='Item',count=2,stacks={{slot=1,count=2}}}}
 DSP.auto.start_sell();DSP.settings.dry_run=false;threads[1]()
 assert(#requests==0,'sell test run became real after launch')
end)
check('sell queue cannot spend one inventory slot twice',function()
 local threads=engine()
 DSP.settings.sell_preset.items={{name='Item',price=50,qty=2,enabled=true},{name='Item',price=60,qty=2,enabled=true}}
 DSP.auto.inv={{name='Item',count=3,stacks={{slot=1,count=3}}}}
 DSP.auto.start_sell();assert(#threads==0,'oversubscribed queue was launched')
end)
assert(failures==0,tostring(failures)..' v2.2 trade regressions failed')
print('v2.2 trade validation and snapshots: OK')
