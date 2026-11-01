-- Stateful, non-networked regression: stop, reconnect, edit, failed save.
local fail_save=false
_G.DSP={settings={promo={templates={}}},lower=string.lower,
    save_settings=function()if fail_save then return false,'disk-full' end return true end}
sampSendChat=function()return true end
sampIsSampAvailable=function()return true end
sampIsLocalPlayerSpawned=function()return true end
dofile('src/49_promo.lua')
dofile('src/49a_promo_universal.lua')
dofile('src/49b_promo_mh_options.lua')
dofile('src/49c_promo_mh_scheduler_v294.lua')
local P=DSP.promo
local rows={{text='/vr A',interval=60,auto=true},{text='/s B',interval=60,auto=true}}
assert(P.save_template(nil,'Test',rows,true,
    {waiting=2.5,interval_min=75,interval_max=75,auto_limit=3,random_line=false}))
local old=P.settings().templates[1]
assert(old.interval_min==75 and old.interval_max==75 and old.auto_limit==3 and old.waiting==2.5)
fail_save=true
local ok,err=P.save_template(1,'Broken',rows,true,{interval_min=120})
assert(not ok and err and P.settings().templates[1]==old,'failed persistence mutated saved template')
fail_save=false
assert(P.save_template(1,'Saved',rows,true))
local t=P.settings().templates[1]
assert(t.interval_min==75 and t.auto_limit==3 and t.waiting==2.5,'ordinary edit lost schedule')
assert(P.copy_template(1))
local duplicate=P.settings().templates[2]
assert(duplicate.auto==false and duplicate.interval_min==75 and duplicate.auto_limit==3)
assert(duplicate.rows~=t.rows,'copy shares mutable row table')
local sent={}
local function send(cmd)sent[#sent+1]=cmd;return true end
assert(P.start(1000))
assert(not P.tick(1000,send,true))
assert(P.tick(1020,send,true))
assert(#sent==1)
P.stop()
assert(not P.tick(1080,send,true) and #sent==1 and not P._batch,'STOP sent stale work')
assert(P.start(2000))
assert(not P.tick(2000,send,true))
assert(P.tick(2020,send,true))
assert(not P.tick(2060,send,false))
assert(P.state=='PAUSED' and P._batch,'disconnect destroyed unsent auto queue')
assert(not P.tick(2061,send,true),'reconnect ignored startup safety delay')
assert(not P.tick(2080,send,true))
assert(P.tick(2081,send,true))
assert(#sent==3,'reconnect duplicated or skipped pending command')
P.stop()
assert(P.start(3000))
assert(not P.tick(3000,send,true))
assert(P.tick(3020,send,true))
assert(P.save_template(1,'Edited',rows,true))
local before=#sent
assert(not P.tick(3080,send,true))
assert(#sent==before and P._batch==nil,'template edit allowed stale send')
P.stop()
assert(P.send_template_once(1))
local n=#sent
P.stop()
assert(not P.tick(os.time()+999,send,true) and #sent==n,'manual work survived STOP')
local failed=0
local function reject()failed=failed+1;return false end
assert(P.start(5000))
assert(not P.tick(5000,reject,true))
assert(not P.tick(5020,reject,true))
assert(failed==1 and P.paused and P.state=='ERROR','client rejection not surfaced as ERROR')
assert(not P.tick(9999,reject,true)and failed==1,'uncertain send was retried silently')
assert(P.start(10000),'user should be able to explicitly resume')
assert(not P.tick(10000,send,true))
assert(P.tick(10020,send,true))
P.stop()
print('PASS promo atomic schedule, safe copy, reconnect, stop, edit and rejected-send recovery')
