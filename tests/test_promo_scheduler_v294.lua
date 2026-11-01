-- Scheduler contract: every enabled row is sent once with its own pause.
_G.DSP={settings={promo={templates={}}},save_settings=function()return true end,lower=string.lower}
sampSendChat=function()return true end
sampIsSampAvailable=function()return true end
sampIsLocalPlayerSpawned=function()return true end
dofile('src/49_promo.lua')
dofile('src/49a_promo_universal.lua')
dofile('src/49b_promo_mh_options.lua')
dofile('src/49c_promo_mh_scheduler_v294.lua')
local P=DSP.promo
assert(P.save_template(nil,'ЦР и семья',{
    {text='/vr Первый',interval=60,auto=true},
    {text='/s Второй',interval=90,auto=true},
    {text='/fam Третий',interval=120,auto=true}},true))
assert(P.save_template_options(1,{waiting=1.5,interval_min=45,interval_max=45,auto_limit=2,random_line=false}))
assert(P.set_option('continuous',true))
local sent={}
local function send(text) sent[#sent+1]=text;return true end
assert(P.start(1000))
assert(not P.tick(1000,send,true))
assert(P.tick(1020,send,true))
local batch=P._batch
assert(P.start(1020),'double START is idempotent')
assert(P._batch==batch,'double START discarded in-flight queue')
assert(not P.tick(1079,send,true))
assert(P.tick(1080,send,true),'row one interval ignored')
assert(not P.tick(1169,send,true))
assert(P.tick(1170,send,true),'row two interval ignored')
assert(#sent==3 and sent[1]:match('Первый') and sent[2]:match('Второй') and sent[3]:match('Третий'))
assert(P.settings().templates[1].auto_count==1)
assert(P.delivery_status=='client_sent_unconfirmed')
assert(not P.tick(1200,send,true))
assert(not P.tick(1214,send,true))
assert(P.tick(1215,send,true))
assert(P.tick(1275,send,true))
assert(P.tick(1365,send,true))
assert(#sent==6 and P.settings().templates[1].auto==false)
assert(not P.tick(2000,send,true))
P.stop()
local current=os.time()
assert(P.send_template_once(1))
assert(P.manual_busy and not P.send_template_once(1))
assert(P.tick(current,send,true))
assert(not P.tick(current+59,send,true))
assert(P.tick(current+60,send,true))
assert(P.tick(current+150,send,true))
assert(#sent==9 and not P.manual_busy)
print('PASS promo line delays, repeat interval, idempotent start, manual queue, safe cooldown and limits')
