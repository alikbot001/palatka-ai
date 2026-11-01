-- Promo schedule uses user configured cooldown and session limit.
local settings={templates={{name='Demo',auto=true,
    rows={{text='/vr Test message',auto=true,interval=30}},
    interval=30,interval_min=30,interval_max=30}},continuous=false,start_delay=20}
local dispatched={}
DSP={
  settings={promo=settings},
  controls={get=function(key)
    if key=='promo_global_cooldown_s'then return 120 end
    if key=='promo_session_limit'then return 2 end
  end},
  save_settings=function()return true end,
  promo={MIN_INTERVAL=30,MAX_SESSION=12,MAX_STEP_BYTES=200,session_count=0,
    settings=function()return settings end,
    validate=function(cmd)return type(cmd)=='string'and cmd:sub(1,1)=='/'end,
    expand=function(cmd)return cmd end},
}
assert(loadfile('src/49c_promo_mh_scheduler_v294.lua'))()
local P=DSP.promo
local sender=function(cmd)dispatched[#dispatched+1]=cmd;return true end
assert(P.start(1000))
assert(not P.tick(1020,sender,true)) -- connection settling
assert(P.tick(1040,sender,true))
assert(#dispatched==1)
assert(not P.tick(1100,sender,true)) -- global cooldown, not row interval
assert(P.tick(1160,sender,true))
assert(#dispatched==2 and P.session_count==2)
assert(P.running==false)
assert(not P.start(1170)) -- custom cap reached
print('2.9.7 promo: cooldown, cap and deliberate stop ok')
