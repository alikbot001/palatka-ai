-- v2.8.5 pawnshop: submenu detection, non-destructive menu, native metadata.
DSP={dir='/tmp',market={state={sid=102}},settings={}}
DSP.lower=string.lower
DSP.clean_text=function(v)return tostring(v or '')end
DSP.trim=function(v)return (tostring(v or ''):gsub('^%s+',''):gsub('%s+$',''))end
DSP.item_key=function(n,e)return n..':'..tostring(e or 0)end
DSP.items={id_for_name=function()return nil end}
DSP.money=function(n)return '$'..tostring(n)end
DSP.flog=function()end
local cp_pawn='\xeb\xee\xec\xe1\xe0\xf0\xe4'
local cp_item='\xef\xf0\xe5\xe4\xec\xe5\xf2'
local cp_give='\xf1\xe4\xe0\xf2\xfc'
local labeled_raw='tagged_'..cp_pawn
local fixture={
 [labeled_raw]={type=9,title=cp_pawn,items={{name='Lemon',price=150}}},
 unknown={type=9,items={{name='Pear',price=200}}},
 trunk={type=8,items={{name='Trunk',price=500}}},
 market={type=13,items={{name='Market',price=500}}},
}
decodeJson=function(raw)return fixture[raw] end
dofile('src/46c_lombard.lua')
local L=DSP.lombard
assert(L.observe_dialog(10,2,cp_pawn,'','','No item lines'))
assert(L.stats().items==0,'intro menu must not write empty snapshot')
assert(L.is_dialog(cp_item,'')==true,'nested page lost pawnshop context')
assert(L.observe_dialog(11,2,cp_item,'','','1. Firewood\t$150'))
local rows=L.search('')
assert(#rows==1 and rows[1].name=='Firewood' and rows[1].price==150)
assert(L.observe_dialog(12,2,cp_give..' '..cp_item,'','','2. Lemon\t$300'))
assert(L.stats().items==2,'nested pages did not accumulate')
dofile('src/46d_lombard_packets.lua')
local P=L.packet_probe
local previous=L.stats().items
assert(not L.on_packet(52,0,'trunk'))
assert(not L.on_packet(52,0,'market'))
assert(L.on_packet(52,0,labeled_raw),'pawnshop-labeled native packet not observed')
assert(P.verified_label and #P.preview()==1 and P.preview()[1].price==150)
assert(L.stats().items==previous,'native packet should never auto-persist')
assert(P.save(),'explicitly reviewed observation should save')
assert(L.stats().items==1)
assert(P.arm(35))
assert(L.on_packet(52,0,'unknown'))
assert(not P.verified_label,'untagged packet promoted to verified')
assert(not P.save(),'must stop capture before saving')
P.stop()
assert(P.save())
assert(L.stats().items==1 and L.search('')[1].name=='Pear')
local meta=P.report()
assert(meta.packets==1 and #meta.candidates==1)
for _,c in ipairs(meta.candidates)do
 assert(c.name==nil and c.price==nil and c.item==nil and c.raw==nil)
end
print('PASS v2.8.5 nested pawnshop menus, read-only native preview and consent')
