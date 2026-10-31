-- A 30-slot basic vehicle must not be forced to 180.
DSP={settings={},storage={},market={state={sid=102,version=1}},
 items={name=function(id)return 'Item'..id end},
 clean_text=function(s)return tostring(s or '')end,
 trim=function(s)return tostring(s or ''):match('^%s*(.-)%s*$')end,
 lower=function(s)return string.lower(s)end,
 item_key=function(s,e)return tostring(s)..':'..tostring(e)end,
 flog=function()end,
 save_settings=function()return true end}
local payload
function decodeJson(raw)return payload end
dofile('src/47_storage.lua')
local S=DSP.storage
local function make_items(count)
 local items={}
 for i=0,count-1 do items[#items+1]={slot=i,item=i==5 and 800 or 0,amount=i==5 and 20 or 0}end
 return items
end
assert(S.set_trunk_autoscan(false))
assert(S.set_trunk_capacity(30))
assert(DSP.settings.storage_trunk_capacity==30)
assert(S.begin_trunk_scan())
payload={type=8,items=make_items(30)}
assert(S.on_inventory_packet(0,'full'))
local t=S.trunk_state()
assert(t.status=='saved' and t.snapshot.slots_count==30)
assert(t.snapshot.count_known==20 and t.received==30)
assert(#S.library()==0 and #S.snapshots==0,'unnamed scan must remain temporary')
local ok,named=S.save_named_trunk(t.snapshot,'Базовая машина')
assert(ok and named.slots_count==30 and #S.library()==1)
assert(DSP.settings.storage_snapshots[1].title=='Базовая машина')
assert(S.set_trunk_capacity(180))
assert(S.begin_trunk_scan())
payload={type=8,items=make_items(30)}
assert(S.on_inventory_packet(0,'partial'))
assert(S.trunk_state().received==30 and S.trunk_state().requested_at)
assert(S.trunk_state().status=='receiving','30 slots not complete when user selected 180')
assert(#S.library()==1)
assert(S.cancel_trunk_scan())
print('PASS storage capacities: manual 30/180 choice, temporary scan, manual named save')
