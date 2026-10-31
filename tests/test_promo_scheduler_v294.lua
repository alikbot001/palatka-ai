-- A multi-line template must send ALL commands with configured pauses.
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
    {text='/s Второй',interval=60,auto=true},
    {text='/fam Третий',interval=60,auto=true}},true))
assert(P.save_template_options(1,{waiting=1.5,interval_min=45,interval_max=45,auto_limit=2,random_line=false}))
assert(P.set_option('continuous',true))
local sent={}
local function send(text) sent[#sent+1]=text;return true end
assert(P.start(1000))
assert(not P.tick(1000,send,true))
assert(P.tick(1020,send,true))
assert(not P.tick(1021,send,true))
assert(P.tick(1022,send,true))
assert(not P.tick(1023,send,true))
assert(P.tick(1024,send,true))
assert(#sent==3 and sent[1]:match('Первый') and sent[2]:match('Второй') and sent[3]:match('Третий'))
assert(P.settings().templates[1].auto_count==1)
assert(not P.tick(1054,send,true))
assert(not P.tick(1068,send,true))
assert(P.tick(1069,send,true))
assert(P.tick(1071,send,true))
assert(P.tick(1073,send,true))
assert(#sent==6 and P.settings().templates[1].auto==false)
assert(not P.tick(2000,send,true))
P.stop()
local current=os.time()
assert(P.send_template_once(1))
assert(P.manual_busy and not P.send_template_once(1))
assert(P.tick(current,send,true))
assert(not P.tick(current+1,send,true))
assert(P.tick(current+2,send,true))
assert(P.tick(current+4,send,true))
assert(#sent==9 and not P.manual_busy)
print('PASS v2.9.4 promo multi-line scheduling, cooldown, manual, limit and persistence')
