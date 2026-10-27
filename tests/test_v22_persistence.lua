-- A failed disk save must leave preset objects, libraries and active aliases intact.
local failures=0
local function test(name,fn)
 local ok,err=pcall(fn)
 if ok then print('PASS '..name)else failures=failures+1;print('FAIL '..name..': '..tostring(err))end
end
local function fixture()
 local saved,logs=0,{}
 DSP={settings={buy_preset={name='Buy',items={{name='Apple',key='Apple|0',ench=0,price=5,qty=1,enabled=true}}},
  sell_preset={name='Sell',items={{name='Pear',key='Pear|0',ench=0,price=7,qty=2,enabled=true}}}},
  save_settings=function()saved=saved+1;return true end,
  add_log=function(s)logs[#logs+1]=s end,money=tostring,
  item_key=function(n,e)return n..'|'..tostring(e or 0)end,item_name=function(n)return n end,
  text_cp=function(s)return s end,market={buy_target=function()return 99 end,sell_target=function()return 88 end,
   row_for=function()return {key='Updated|0'}end}}
 assert(loadfile('src/20_presets.lua'))();assert(loadfile('src/21_preset_library.lua'))()
 return function()return saved,logs end
end
local function snapshot(root)
 local seen={}
 local function visit(t)
  if type(t)~='table' or seen[t]then return end
  local copy={};seen[t]=copy
  for k,v in pairs(t)do copy[k]=v;visit(v)end
 end
 visit(root)
 return function()
  for t,old in pairs(seen)do
   for k,v in pairs(old)do assert(t[k]==v,'changed prior value '..tostring(k))end
   for k in pairs(t)do assert(old[k]~=nil,'added unexpected key '..tostring(k))end
  end
 end
end
local cases={
 {'select',function(p)return p.select('buy',2)end},
 {'create',function(p)return p.create('buy','New')end},
 {'rename',function(p)return p.rename('buy',1,'Changed')end},
 {'delete',function(p)return p.delete('buy',1)end},
 {'update',function(p)return p.update('buy',1,{price=20,qty=3,enabled=false})end},
 {'add manual',function(p)return p.add_manual('buy',{name='New item',price=9,qty=2})end},
 {'import both kinds',function(p)return p.import_data({buy_presets={{name='Imported Buy',items={{name='B',price=8,qty=2}}}},
  sell_presets={{name='Imported Sell',items={{name='S',price=9,qty=3}}}}})end},
 {'add market new',function(p)return p.add({key='New|0',display='New',ench=0},'buy')end},
 {'add market existing',function(p)return p.add({key='Apple|0',display='Apple',ench=0},'buy')end},
 {'remove item',function(p)return p.remove('buy',1)end},
 {'clear',function(p)return p.clear('buy')end},
 {'recalculate',function(p)return p.recalc('buy')end},
}
for _,case in ipairs(cases)do
 test(case[1]..' rolls back failed save',function()
  fixture();local p=DSP.presets
  assert(p.create('buy','Second'));assert(p.select('buy',1))
  local unchanged=snapshot(DSP.settings)
  DSP.save_settings=function()return false,'disk full' end
  local ok,err=case[2](p)
  assert(ok==false and tostring(err):find('disk full',1,true),'save failure reported as success')
  unchanged()
  assert(DSP.settings.buy_preset==p.list('buy')[p.selected('buy')],'active alias broken')
 end)
end
test('save exception rolls back and reports its cause',function()
 fixture();local unchanged=snapshot(DSP.settings)
 DSP.save_settings=function()error('permission denied')end
 local ok,err=DSP.presets.rename('sell',1,'Changed')
 assert(ok==false and tostring(err):find('permission denied',1,true));unchanged()
end)
test('missing library migration is rolled back with the failed transaction',function()
 fixture();DSP.settings.buy_presets=nil;DSP.settings.active_buy_preset=nil
 local original=DSP.settings.buy_preset;local unchanged=snapshot(DSP.settings)
 DSP.save_settings=function()return nil,'write failed' end
 local ok,err=DSP.presets.create('buy','New')
 assert(ok==false and err=='write failed');unchanged()
 assert(DSP.settings.buy_preset==original)
end)
test('success commits once and keeps legacy alias identity',function()
 local state=fixture();local p=DSP.presets
 local before=state();local ok,index=p.create('buy','Second');assert(ok and index==2)
 assert(state()==before+1,'create saved multiple times')
 assert(DSP.settings.buy_preset==DSP.settings.buy_presets[2])
 assert(p.add_manual('buy',{name='B',price=20,qty=2}));local it=p.items('buy')[1]
 assert(p.update('buy',1,{price=30}));assert(p.items('buy')[1]==it and it.price==30)
 assert(p.select('buy',1));assert(p.delete('buy',2))
 assert(DSP.settings.buy_preset==DSP.settings.buy_presets[1])
end)
test('failed export preserves the previous file',function()
 fixture();local path=os.tmpname();local real_open=io.open
 local f=assert(real_open(path,'wb'));assert(f:write('previous'));f:close()
 encodeJson=function()return '{"new":true}'end
 io.open=function(p,mode)
  local file,err=real_open(p,mode)
  if file and mode=='wb' and (p==path or p==path..'.tmp')then
   return {write=function()return nil,'disk full'end,close=function()return file:close()end}
  end
  return file,err
 end
 local called,ok,err=pcall(DSP.presets.export_file,'buy',path);io.open=real_open
 local old=assert(real_open(path,'rb'));local raw=old:read('*a');old:close();os.remove(path);os.remove(path..'.tmp')
 assert(called and ok==false and err=='disk full');assert(raw=='previous','failed export truncated old preset')
end)
assert(failures==0,tostring(failures)..' persistence regressions failed')
print('v2.2 transactional preset persistence: OK')
