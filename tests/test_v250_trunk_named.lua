-- Test full trunk scan, opt-in session, valuations, named snapshots.
DSP={settings={},storage={},market={state={sid=102,version=1}},
 items={name=function(id)return id==551 and 'Ларцы' or 'Предмет' end},
 clean_text=function(s)return tostring(s or '') end,
 trim=function(s)return tostring(s or ''):match('^%s*(.-)%s*$') end,
 lower=function(s)return string.lower(s)end,
 item_key=function(s,e)return tostring(s)..':'..tostring(e)end,
 money=tostring,
 flog=function()end}
local saves=0
DSP.save_settings=function()saves=saves+1;return true end
DSP.market.row_for=function(name)
 if name=='Ларцы' then return {buy={max=100},sell={min=120}} end
 return nil
end
local payload=nil
function decodeJson(raw) return payload end
dofile('src/47_storage.lua')
local S=DSP.storage
assert(S.kind_of('Инвентарь')=='inventory')
local slots={}
for i=0,179 do slots[#slots+1]={slot=i,item=i==5 and 551 or 0,amount=i==5 and 30 or 0}end
payload={type=8,items=slots}
assert(S.trunk_state().autoscan_enabled==true)
assert(S.set_trunk_autoscan(false))
assert(not S.on_inventory_packet(0,'full'),'disabled scan must ignore unsolicited packet')
assert(S.trunk_state().snapshot==nil)
assert(S.begin_trunk_scan())
assert(S.trunk_state().status=='waiting')
assert(S.on_inventory_packet(0,'full'))
local t=S.trunk_state()
assert(t.status=='saved' and t.received==180)
assert(t.snapshot.rows[1].qty==30 and t.snapshot.rows[1].name=='Ларцы')
assert(t.last_completed_request_at and t.requested_at==nil)
local v=S.evaluate(t.snapshot)
assert(v.sell_to_buyers==3000 and v.ask_value==3600)
local ok,archive=S.save_named_trunk(t.snapshot,'Моя машина с ларцами')
assert(ok and archive.title=='Моя машина с ларцами')
assert(archive.identity_verified==false and archive.source=='packet220_trunk_named')
assert(S.snapshots[2]==archive)
payload={type=8,items=slots}
assert(S.set_trunk_autoscan(true))
assert(S.on_inventory_packet(0,'full'))
assert(S.snapshots[1].source=='packet220_trunk')
assert(S.snapshots[2].title=='Моя машина с ларцами')
assert(S.snapshots[1].title~='Моя машина с ларцами',
    'next vehicle must not inherit previous manual name')
local previous=S.snapshots
DSP.save_settings=function()return false,'disk full'end
assert(not S.save_named_trunk(S.snapshots[1],'Моя машина с ресурсами'))
assert(S.snapshots==previous and DSP.settings.storage_snapshots==previous)
print('PASS trunk: start/auto, 180 slots, value, named history and failure rollback')
