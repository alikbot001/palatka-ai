package.preload['ffi']=function() return {string=function() return '' end} end
local labels={}; local clicked=nil; local started=nil
local pbuy={name='Тестовая скупка',items={{name='Бинт',price=200,qty=50,enabled=true},{name='Металл',price=100,qty=25,enabled=true}}}
local psell={name='Тестовая продажа',items={{name='Аптечка',price=1000,qty=5,enabled=true}}}
imgui={Columns=function() end,NextColumn=function() end,Separator=function() end,
   TextDisabled=function() end,SetNextItemWidth=function() end,InputText=function() return false end,
   new={char=setmetatable({}, {__index=function() return function() return {} end end})}}
DSP={utf8=function(s) return s end,ui={preset_kind='buy',trade_section='items'},settings={buy_preset=pbuy,sell_preset=psell,dry_run=true},
 mobile={button=function(label,id) return id==clicked end,
   title=function() end,text=function(s) labels[#labels+1]=s end,inline=function() end,
   thumbnail=function() end,toggle=function() end,compact_number=function() end,
   refresh_buffer=function() end},
 presets={list=function(kind) return {{name=kind=='buy' and pbuy.name or psell.name}} end,
    selected=function() return 1 end,active_count=function(kind) return #(kind=='buy' and pbuy.items or psell.items) end,
    select=function() end,remove=function() end},
 auto={buy_running=false,sell_running=false,start_buy=function() started='buy' end,start_sell=function() started='sell' end},
 save_settings=function() end, money=function(n) return '$'..n end, notify=function() end}
assert(loadfile('src/37_mobile_trade.lua'))()
DSP.ui.trade_tab()
assert(started==nil)
assert(table.concat(labels,' '):find('12500',1,true),'subtotal uses per-item quantities')
clicked='kind_sell';DSP.ui.trade_tab();assert(DSP.ui.preset_kind=='sell','buy/sell toggle works')
clicked='run_sell';DSP.ui.trade_tab();assert(started=='sell','action dispatch sell')
print('v1.4 trade UI tests: OK')
