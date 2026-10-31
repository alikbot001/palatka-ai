-- Local metadata-only diagnostics export. Never uploads inventory or account data.
DSP={storage={snapshots={}},dir='.',settings={}}
DSP.items={name=function(id)return 'Secret Item' end}
function decodeJson(raw)
  return {type=2,items={{slot=0,item=942,amount=15}}}
end
function encodeJson(obj)
  assert(obj.kind_label=='cabinet' and obj.packets==1 and #obj.candidates==1)
  assert(obj.candidates[1].type==2 and obj.candidates[1].slots_observed==1)
  assert(obj.candidates[1].item_id==nil and obj.candidates[1].name==nil)
  return '{"type":2,"slots_observed":1,"kind_label":"cabinet"}'
end
dofile('src/47b_storage_probe.lua')
local P=DSP.storage_probe
assert(P.arm('cabinet',40));assert(P.on_packet(0,'foo'));assert(P.stop())
local success,path=P.export_report();assert(success and path:find('storage_probe_report.json'))
local f=assert(io.open(path,'rb'));local contents=f:read('*a');f:close()
assert(not contents:find('Secret Item') and not contents:find('942') and not contents:find('15'))
os.remove(path)
print('PASS storage probe metadata-only report')
