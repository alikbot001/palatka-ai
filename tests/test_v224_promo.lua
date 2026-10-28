DSP={settings={},save_settings=function()return true end}
dofile('src/49_promo.lua')
local P=DSP.promo
assert(not P.validate('Hello'), 'plain chat must not be allowed')
assert(P.validate('/vr X\n/ad Y'), 'multiple explicit channels are allowed')
assert(not P.validate('/vr X\n/rm something'), 'unapproved command must fail')
assert(not P.validate('/zz Offer'), 'arbitrary slash commands forbidden')
assert(P.add('Offer','/vr Продам дрова в лавке №12',300))
assert(P.add('Second','/ad Куплю ресурсы',300))
assert(#P.settings().templates==2)
assert(P.update(1,'New offer','/s Ресурсы в лавке №12',5))
assert(P.settings().templates[1].interval==180,'server throttle must not be less than 180s')
assert(not P.start(),'no autorun before explicit selection')
P.settings().templates[1].auto=true
assert(P.start() and P.running)
local out={}
local function send(s)out[#out+1]=s end
local now=10000
assert(P.tick(now,send,true))
assert(#out==1 and out[1]:find('^/s'))
assert(not P.tick(now+2,send,true),'no fast repeat')
assert(not P.send_once(2,now+30,send,true),'manual action should also observe cooldown')
assert(P.tick(now+180,send,true))
P.stop();assert(not P.tick(now+500,send,true),'stop should be effective')
assert(P.start());assert(not P.tick(now+1000,send,false) and not P.running,'disconnect should stop auto promo')
assert(not P.send_once(2,now+1000,send,false),'offline send blocked')
P.session_count=P.MAX_SESSION
assert(not P.start(),'no restart after session limit')
assert(not P.send_once(1,now+5000,send,true))
assert(P.remove(2) and #P.settings().templates==1)
-- No global Market Helper dependency; local injection is only a test seam.
print('v2.2.4 promo: opt-in, template CRUD, sanitized commands, cooldown, stop, session cap PASS')
