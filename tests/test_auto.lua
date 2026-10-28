local clock, dialog, responses, threads, logs = 0, nil, {}, {}, {}
DSP={settings={buy_preset={items={}},sell_preset={items={}},dry_run=true},market={},add_log=function(s)logs[#logs+1]=s end,notify=function()end,money=tostring}
sampIsDialogActive=function()return dialog~=nil end
sampGetCurrentDialogId=function()return dialog and dialog.id or -1 end
sampGetDialogText=function()return dialog and dialog.text or '' end
sampSendDialogResponse=function(id,btn,idx,text)
 responses[#responses+1]={id=id,btn=btn,idx=idx,text=text}
 if btn==0 then dialog=nil end
 if _G.respond then _G.respond(id,btn,idx,text) end
end
sampSendChat=function(s)_G.last_chat=s end
wait=function(ms)clock=clock+ms;if _G.on_wait then _G.on_wait(ms) end end
lua_thread={create=function(fn)threads[#threads+1]=fn end}
assert(loadfile('src/39_trade_runtime.lua'))()
assert(loadfile('src/40_auto.lua'))()
assert(loadfile('src/41_trade_listing.lua'))()
assert(loadfile('src/42_trade_buy.lua'))()
DSP.auto.scanning=true
DSP.auto.on_dialog(25494,5,'Инвентарь','','','Слот\tНазвание\n[12] Item [2 шт]\n[13] Other [1 шт]\nСледующая страница')
assert(#DSP.auto.inv==2)
threads[#threads]();assert(responses[#responses].idx==2)
DSP.auto.on_dialog(25494,5,'Инвентарь','','','Слот\tНазвание\n[12] Item [2 шт]')
assert(DSP.auto.inv[1].count==2,'repeated page must not duplicate slots')
DSP.auto.scanning=false; threads={}
DSP.settings.buy_preset.items={{name='Apple',qty=2,price=5000000000,enabled=true}}
_G.dsp_click_slot=function()dialog={id=15072,text='Лавка'} end
_G.respond=function(id,btn,idx,text)
 if btn==0 then return end
 if id==15072 then dialog={id=15065,text='Поиск'}
 elseif id==15065 then dialog={id=15068,text='Apple\nApple juice'}
 elseif id==15068 then assert(idx==0);dialog={id=15071,text='Apple Количество'}
 elseif id==15071 then assert(text=='2,5000000000');dialog=nil end
end
DSP.auto.start_buy(); assert(DSP.auto.buy_running)
DSP.auto.start_sell(); assert(not DSP.auto.sell_running)
threads[1]();assert(not DSP.auto.buy_running)
for _,r in ipairs(responses)do assert(not(r.id==15071 and r.btn==1),'dry-run submitted listing')end
DSP.settings.dry_run=false;threads={};responses={}
DSP.auto.start_buy();threads[1]()
assert(DSP.auto.progress.done==1,'submitted listing not tracked')
-- Cancellation at a wait boundary must prevent the next dialog response.
threads={}; responses={}
DSP.auto.start_buy();_G.on_wait=function()DSP.auto.stop_buy();_G.on_wait=nil end
threads[1]();assert(not DSP.auto.buy_running)
for _,r in ipairs(responses)do assert(r.btn~=1,'sent affirmative response after cancellation')end
_G.respond=nil;_G.on_wait=nil;threads={};dialog=nil
_G.dsp_click_slot=function()end
DSP.auto.start_buy();threads[1]();assert(not DSP.auto.buy_running and clock<30000,'timeout must use elapsed waits')
-- A worker cancelled before its scheduled turn cannot open any interface.
threads={};responses={};dialog=nil
local clicks=0
_G.dsp_click_slot=function()clicks=clicks+1 end
DSP.auto.start_buy();DSP.auto.stop_buy();threads[1]()
assert(clicks==0 and not DSP.auto.buy_running,'cancelled queued worker opened interface')
-- Non-stackable items repeat their full route for each requested unit.
threads={};responses={};dialog=nil
DSP.settings.dry_run=false
DSP.settings.buy_preset.items={{name='Apple',qty=3,price=500,enabled=true}}
_G.dsp_click_slot=function()dialog={id=3040,text='Лавка'} end
local listings=0
_G.respond=function(id,btn,idx,text)
 if btn==0 then return end
 if id==3040 then dialog={id=25663,text='Поиск'}
 elseif id==25663 then dialog={id=25664,text='Apple'}
 elseif id==25664 then dialog={id=26563,text='Apple Цена'}
 elseif id==26563 then assert(text=='500');listings=listings+1;dialog=nil end
end
DSP.auto.start_buy();threads[1]()
assert(listings==3 and DSP.auto.progress.done==1 and DSP.auto.progress.units==3)
-- Selling requires a server listing acknowledgement, never a guessed success.
local function sell_run(reply)
 threads={};responses={};dialog=nil
 DSP.settings.dry_run=false
 DSP.settings.sell_preset.items={{name='Item',ench=0,price=500,qty=2,enabled=true}}
 DSP.auto.inv={{name='Item',count=2,stacks={{slot=12,count=2}}}}
 _G.dsp_click_slot=function(interface)
  if interface==60 then dialog={id=26547,text='Item Количество цена'} end
 end
 _G.respond=function(id,btn,idx,text)
  if id==26547 and btn==1 then
   assert(text=='2,500');dialog=nil
   if reply then DSP.auto.on_dialog(9000,0,'','','',reply) end
  end
 end
 DSP.auto.start_sell();threads[1]()
 assert(not DSP.auto.sell_running)
end
sell_run('Успешно выставлено на продажу')
assert(DSP.auto.progress.done==1)
sell_run('Запрещено')
assert(DSP.auto.progress.done==0 and DSP.auto.progress.failed==1)
sell_run(nil)
assert(DSP.auto.progress.done==0 and DSP.auto.progress.failed==1)
-- Actual listing feedback can arrive as chat, not onShowDialog.
DSP.auto.sell_running=true
DSP.auto.sell_confirmed=false
DSP.auto.on_trade_feedback('Товар успешно выставлен на продажу')
assert(DSP.auto.sell_confirmed,'native sale ack in server chat was ignored')
DSP.auto.sell_confirmed=false;DSP.auto.sell_no_slots=false
DSP.auto.on_trade_feedback('У вас нет доступных ячеек')
assert(DSP.auto.sell_confirmed and DSP.auto.sell_no_slots,'server no-slot feedback was ignored')
DSP.auto.sell_confirmed=false;DSP.auto.sell_no_slots=false
DSP.auto.on_trade_feedback('Другой игрок вошёл в игру')
assert(not DSP.auto.sell_confirmed,'unrelated server chat confirmed a trade')
DSP.auto.sell_running=false
-- The server event hook must preserve an existing handler and report sales.
local existing=0
package.preload['samp.events']=function()
 return {onServerMessage=function(color,text)existing=existing+1;return 'previous handler result'end}
end
DSP.auto.install()
local ev=require('samp.events')
DSP.auto.sell_running=true;DSP.auto.sell_confirmed=false
assert(ev.onServerMessage(123,'Товар успешно выставлен на продажу')=='previous handler result')
assert(DSP.auto.sell_confirmed and existing==1,'server message handler did not preserve chain')
DSP.auto.sell_running=false
assert(DSP.auto.helpers.has_qty('Введите количество и цену через запятую'), 'comma-form quantity was missed')
assert(DSP.auto.helpers.has_qty('Пример: 2,61000'), 'buy example quantity was missed')
assert(not DSP.trade_runtime.matches('Apple juice Количество','Apple'))
assert(not DSP.trade_runtime.matches('Item (+1) Количество','Item (+2)'))
local marker_calls=0
DSP.market.cr_scan_state={active=false}
DSP.market.on_cr_marker_dialog=function()marker_calls=marker_calls+1 end
assert(not DSP.auto.on_dialog(15073,0,'','','','marker'))
assert(marker_calls==0)
DSP.market.cr_scan_state.active=true
assert(DSP.auto.on_dialog(15073,0,'','','','marker'))
assert(marker_calls==1)
print('auto tests: ok')
