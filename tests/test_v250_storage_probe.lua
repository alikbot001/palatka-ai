-- Read-only packet observer tests: no in-game actions and no MonetLoader needed.
local fixtures={
 first={type=4,capacity=12,items={}},
 second={type=4,capacity=12,items={}},
 trunk={type=8,items={{slot=0,item=100,amount=5}}},
 stall={type=1,items={{slot=0,item=100,amount=5}}},
 invalid={type=9,items={{slot=2,item=3,amount=1},{slot=2,item=4,amount=2}}},
 unknown={type=4,items={{slot=4,item=3}}},
 other={type=2,items={{slot=0,item=7,amount=2}}},
}
for n=0,5 do fixtures.first.items[#fixtures.first.items+1]={slot=n,item=n==1 and 101 or 0,amount=4} end
for n=6,11 do fixtures.second.items[#fixtures.second.items+1]={slot=n,item=n==9 and 104 or 0,amount=8} end
local saves=0
DSP={storage={snapshots={}},settings={},market={state={sid=102}},
 items={name=function(id)return 'Item_'..tostring(id) end},
 save_settings=function()saves=saves+1;return true end}
function decodeJson(raw)return fixtures[raw] end
dofile('src/47b_storage_probe.lua')
local P=DSP.storage_probe
assert(P.arm('cabinet',30))
assert(not P.on_packet(0,'trunk'))
assert(P.ignored_trunk==1)
assert(not P.on_packet(2,'stall') and P.ignored_stall==1)
assert(not P.on_packet(1,'first'))
assert(not P.on_packet(0,'invalid'))
assert(P.on_packet(0,'first'))
assert(P.on_packet(0,'second'))
assert(#P.order==1 and P.order[1].count==12)
local view=P.preview(1)
assert(view.complete_unverified and view.occupied==2 and view.known==12)
assert(#DSP.storage.snapshots==0 and saves==0,'must never auto-persist')
assert(not P.save(1),'must stop before save')
assert(P.stop())
local ok,snap=P.save(1)
assert(ok and snap.kind=='cabinet' and snap.complete_verified==false and snap.identity_verified==false)
assert(snap.rows[1].name=='Item_101' and snap.rows[2].qty==8)
assert(saves==1)
assert(not P.arm('inventory',30),'personal inventory probe is intentionally removed')
local current=DSP.storage.snapshots
DSP.save_settings=function()return false,'disk fail' end
assert(P.arm('warehouse',30));assert(P.on_packet(2,'other'));assert(P.stop())
assert(not P.save(1),'save failure must propagate')
assert(DSP.storage.snapshots==current and DSP.settings.storage_snapshots==current,'rollback state')
assert(not P.arm('trunk',30),'trunks must use known parser')
print('PASS storage probe: opt-in, trunk exclusion, counts, save rollback')
