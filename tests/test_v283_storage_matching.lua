-- Candidate comparison is advisory only. Never infer or persist vehicle IDs.
DSP={settings={},storage={},market={state={sid=42,version=1}},
 items={name=function(id)return 'Item'..id end},
 clean_text=function(s)return tostring(s or '')end,
 trim=function(s)return tostring(s or ''):match('^%s*(.-)%s*$')end,
 lower=function(s)return string.lower(s)end,
 item_key=function(s,e)return tostring(s)..':'..tostring(e)end,
 flog=function()end}
DSP.save_settings=function()return true end
local payload
function decodeJson(raw)return payload end
dofile('src/47_storage.lua')
local S=DSP.storage
local function slots(entries)
 local all={}
 for i=0,179 do
  local e=entries[i]
  all[#all+1]={slot=i,item=e and e.id or 0,amount=e and e.qty or 0,
                enchant=e and e.ench or 0}
 end
 return all
end
local function scan(entries)
 assert(S.begin_trunk_scan())
 payload={type=8,items=slots(entries)}
 assert(S.on_inventory_packet(0,'full'))
 return S.trunk_state().snapshot
end
local one=scan({[1]={id=111,qty=10},[8]={id=222,qty=5}})
local ok,boxA=S.save_named_trunk(one,'LRC')
assert(ok and not S.trunk_state().review_needed)
local two=scan({[2]={id=111,qty=500},[9]={id=333,qty=6}})
assert(S.trunk_state().review_needed)
local suggestions=S.match_saved_trunks(two)
assert(#suggestions==1 and suggestions[1].id==boxA.id)
assert(suggestions[1].shared==1 and suggestions[1].similarity==33)
assert(boxA.count_known==15,'never auto update a saved trunk')
local ok2,boxB=S.save_named_trunk(two,'Такси')
assert(ok2 and boxB.count_known==506)
local three=scan({[4]={id=111,qty=1},[5]={id=333,qty=7}})
local matches=S.match_saved_trunks(three)
assert(#matches==2 and matches[1].id==boxB.id,'most overlap wins')
assert(matches[1].shared==2 and matches[1].similarity==100)
assert(matches[2].id==boxA.id and matches[2].similarity==33)
assert(S.trunk_state().review_needed,'must request user decision')
-- User confirmation is the only operation that may refresh a saved entry.
assert(S.apply_latest_to_saved(boxB.id))
assert(not S.trunk_state().review_needed)
assert(boxB.count_known==8 and boxA.count_known==15)
-- Different server must never be suggested.
DSP.market.state.sid=99
local elsewhere=scan({[4]={id=111,qty=2}})
assert(#S.match_saved_trunks(elsewhere)==0)
-- Empty trunks are not useful identifiers.
DSP.market.state.sid=42
local empty=scan({})
assert(#S.match_saved_trunks(empty)==0)
-- Changing the enchantment must not imply a match for a unique item.
local enchanted=scan({[4]={id=500,qty=1,ench=1}})
local yes,boxC=S.save_named_trunk(enchanted,'Чары')
assert(yes)
local different=scan({[4]={id=500,qty=1,ench=2}})
assert(#S.match_saved_trunks(different)==0)
assert(boxC.count_known==1)
print('PASS storage candidate matcher: shared items, ranking, different servers, empty, enchant and explicit confirmation')
