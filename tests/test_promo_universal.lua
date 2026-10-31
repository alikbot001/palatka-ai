-- Universal Palatka promotion scheduler: testing model without connecting to SA-MP.
_G.DSP={settings={promo={templates={}}},
    lower=string.lower,
    save_settings=function()return true end,
    flog=function()end}
assert(dofile('src/49_promo.lua'))
assert(dofile('src/49a_promo_universal.lua'))
local P=DSP.promo
assert(P.MIN_INTERVAL==60)
local ok,why=P.validate('/family')
assert(ok,why)
assert(P.validate('/fam Продам 100 ларцов'))
assert(P.validate('/teleport'))
assert(not P.validate('ordinary non-command text'))
assert(not P.validate('/f\n/s hi\nplain text'))
assert(P.add('Семья','/f Встречаемся на ЦР',60))
assert(P.add('Объявление','/vr Продам 100 ларцов',120))
assert(P.add('Меню','/family',180))
local s=P.settings()
assert(#s.templates==3 and s.templates[1].auto)
assert(s.resume_on_login==false and s.continuous==false)
P.install()
assert(not P.running)
assert(P.set_option('continuous',true))
assert(P.set_option('resume_on_login',true))
local sent={}
local function sender(cmd)sent[#sent+1]=cmd;return true end
assert(P.start(1000))
assert(P.tick(1020,sender,true)==false) -- handshake delay, no immediate send
assert(P.tick(1039,sender,true)==false)
assert(P.tick(1040,sender,true)==true)
assert(sent[1]=='/f Встречаемся на ЦР')
assert(P.tick(1090,sender,true)==false)
assert(P.tick(1100,sender,true)==true)
assert(sent[2]=='/vr Продам 100 ларцов')
assert(P.tick(1220,sender,true)==true)
assert(sent[3]=='/family')
assert(P.cycle_count>=1)
-- Cycling continues beyond the earlier maximum, with safe >=60 s spacing.
local time=1400
for i=1,14 do
    assert(P.tick(time,sender,true))
    time=time+220
end
assert(P.running and P.session_count>12)
assert(P.tick(time,sender,false)==false and P.running)
assert(P.pause_reason~=nil)
assert(P.tick(time+1,sender,true)==false) -- reconnected; start delay
assert(P.tick(time+21,sender,true)==true)
local previous=#sent
P.stop()
assert(not P.running and not s.enabled)
P.bootstrap()
assert(not P.running) -- stop cancels persisted auto-resume
assert(P.set_option('continuous',false))
assert(P.set_option('resume_on_login',true))
assert(P.start(time+100))
P.bootstrap(time+150)
assert(P.running and s.enabled)
-- Pause if the player is not spawned, never attempt to send.
local n=#sent
assert(not P.tick(time+150,sender,false))
assert(#sent==n)
assert(P.move(3,-1))
assert(s.templates[2].text=='/family')
assert(P.update(1,'Обновлено','/f тест',90))
assert(s.templates[1].interval==90)
assert(P.remove(3))
assert(#s.templates==2)
print('PASS universal promo scheduler')
