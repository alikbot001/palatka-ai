-- Smart trunk library: names survive later scans and updates require confirmation.
DSP={settings={},storage={},market={state={sid=102,version=1}},
 items={name=function(id)
   if id==551 then return 'Ларцы' end
   if id==552 then return 'Ресурсы' end
   return 'Предмет'
 end},
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
 if name=='Ресурсы' then return {buy={max=25},sell={min=40}} end
 return nil
end
local payload=nil
function decodeJson(raw)return payload end
dofile('src/47_storage.lua')
local S=DSP.storage
local function make_slots(id,qty,slot)
 local rows={}
 for i=0,179 do
   rows[#rows+1]={slot=i,item=i==slot and id or 0,amount=i==slot and qty or 0}
 end
 return rows
end
local function use_full(rows)
 payload={type=8,items=rows}
 assert(S.on_inventory_packet(0,'full'))
end
local function use_chunks(rows)
 local chunks={{},{},{}}
 -- Deliberately start at slot 60. Slot 0 arrives last.
 for i=61,120 do chunks[1][#chunks[1]+1]=rows[i] end
 for i=121,180 do chunks[2][#chunks[2]+1]=rows[i] end
 for i=1,60 do chunks[3][#chunks[3]+1]=rows[i] end
 for _,items in ipairs(chunks)do
   payload={type=8,items=items}
   assert(S.on_inventory_packet(0,'chunk'))
 end
end

assert(S.set_trunk_autoscan(false))
-- First vehicle -> LRC.
assert(S.begin_trunk_scan())
use_full(make_slots(551,30,5))
local live=S.trunk_state().snapshot
assert(live and live.count_known==30)
local ok,lrc=S.save_named_trunk(live,'LRC')
assert(ok and lrc.title=='LRC' and lrc.count_known==30)
assert(#S.library()==1)

-- Second vehicle arrives in chunks. It must not erase or rename LRC.
assert(S.begin_trunk_scan())
use_chunks(make_slots(552,50,9))
local second=S.trunk_state().snapshot
assert(second.count_known==50 and second.rows[1].name=='Ресурсы')
local kept=S.find_snapshot(lrc.id)
assert(kept==lrc and kept.title=='LRC' and kept.count_known==30)
local ok2,taxi=S.save_named_trunk(second,'Такси обратня')
assert(ok2 and taxi.title=='Такси обратня')
assert(#S.library()==2)
assert(S.find_snapshot(lrc.id).count_known==30)

-- Explicitly refresh LRC. The new scan does NOT touch it until apply.
assert(S.begin_trunk_scan(lrc.id))
use_chunks(make_slots(551,40,5))
local t=S.trunk_state()
assert(t.completed_update_target_id==lrc.id)
assert(S.find_snapshot(lrc.id).count_known==30,'must wait for confirmation')
local applied,updated=S.apply_latest_to_saved(lrc.id)
assert(applied and updated.title=='LRC' and updated.count_known==40)
assert(t.completed_update_target_id==nil)
assert(S.find_snapshot(taxi.id).count_known==50,'other vehicle must remain intact')

-- Renaming a live disposable scan archives it instead of mutating the live row.
assert(S.begin_trunk_scan())
use_full(make_slots(552,60,9))
local disposable=S.trunk_state().snapshot
local old_live_title=disposable.title
local renamed,new_saved=S.set_snapshot_label(disposable,'Третий багажник')
assert(renamed and new_saved.source=='packet220_trunk_named')
assert(disposable.title==old_live_title,'live title must stay generic')
assert(S.find_snapshot(new_saved.id)==new_saved)

-- Duplicate library names are rejected to keep update targets unambiguous.
local duplicate,err=S.save_named_trunk(disposable,'LRC')
assert(not duplicate and tostring(err):find('название'))

print('PASS smart trunk library: two vehicles, out-of-order chunks, explicit update, persistent names')
