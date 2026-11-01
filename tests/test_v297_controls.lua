-- Palatka 2.9.7: controllable defaults, bounds, profile persistence, global stop.
local failed=false
local writes=0
DSP={
  settings={server=1,refresh_seconds=300,promo={},dry_run=true},
  ui22={},mobile={},
  save_settings=function()
    writes=writes+1
    if failed then return false,'disk full' end
    return true
  end,
}
assert(loadfile('src/71_control_center.lua'))()
local C=DSP.controls
assert(C.get('sell_step_pause_ms')==260)
assert(C.get('promo_session_limit')==12)
assert(C.get('promo_global_cooldown_s')==30)
assert(C.get('local_offer_ttl_minutes')==60)
assert(C.get('not-a-key')==nil)
assert(not C.set('promo_global_cooldown_s',5))
assert(not C.set('promo_session_limit',0))
assert(not C.set('sell_step_pause_ms',999999))
assert(not C.set('sell_step_pause_ms','not number'))
assert(C.set('sell_step_pause_ms',600))
assert(C.get('sell_step_pause_ms')==600)
assert(C.set('promo_session_limit',24))
assert(C.get('promo_session_limit')==24)
assert(C.set('refresh_seconds',600))
assert(DSP.settings.refresh_seconds==600)
failed=true
assert(not C.set('refresh_seconds',700))
assert(DSP.settings.refresh_seconds==600)
assert(not C.profile('cautious'))
assert(C.get('sell_step_pause_ms')==600)
failed=false
assert(C.profile('cautious'))
assert(C.get('sell_step_pause_ms')==800)
assert(C.get('promo_global_cooldown_s')==300)
assert(C.get('promo_session_limit')==12)
assert(C.profile('default'))
assert(C.get('sell_step_pause_ms')==260)
assert(C.get('promo_session_limit')==12)
local stopped={sell=0,buy=0,promo=0}
DSP.auto={sell_running=true,buy_running=true,
  stop_sell=function()stopped.sell=stopped.sell+1 end,
  stop_buy=function()stopped.buy=stopped.buy+1 end}
DSP.promo={running=true,stop=function()stopped.promo=stopped.promo+1 end}
assert(C.stop_all())
assert(stopped.sell==1 and stopped.buy==1 and stopped.promo==1)
assert(writes>0)
print('2.9.7 controls: defaults, bounds, rollback, profiles and stop ok')
