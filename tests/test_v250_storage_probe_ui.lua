-- Simplified cabinet / warehouse scan UI.
DSP={ui21={},storage={evaluate=function()return{cross_server=false,sell_to_buyers=200,missing_prices=0}end},
 money=tostring,market={state={sid=1}}}
local V=DSP.ui21
local count,pressed=0,''
V.font_pixels=18
function V.button(label,id,width,active,primary)return id==pressed end
function V.text(s)count=count+1 end
function V.muted(s)count=count+1 end
function V.red(s)count=count+1 end
function V.green(s)count=count+1 end
function V.fit(s,w)return s end
function V.apply_font()end
DSP.storage_probe={armed=false,kind=nil,order={},observed=0,ignored_trunk=0,ignored_stall=0}
local P=DSP.storage_probe
function P.state()return P end
function P.arm(kind,sec)P.armed=true;P.kind=kind;P.status='armed';P.until_ts=os.time()+sec;return true end
function P.stop()P.armed=false;P.status='review'end
function P.preview(i)return{entry={type=4,sub=2,count=30},occupied=1,known=20,unknown_qty=0,rows={{name='Test',qty=20}}}end
function P.save(i)return true,{kind=P.kind}end
dofile('src/60e_storage_probe_ui.lua')

V.storage_probe_panel(320,'cabinet')
pressed='probe_arm_cabinet';V.storage_probe_panel(320,'cabinet')
assert(P.armed and P.kind=='cabinet')
pressed='probe_stop';V.storage_probe_panel(320,'cabinet')
assert(not P.armed)
P.order={{type=4,sub=2,count=30}}
pressed='probe_save';V.storage_probe_panel(320,'cabinet')
assert(V.storage_tab=='library' and V.storage_library_page=='list')
pressed='';V.storage_probe_panel(320,'warehouse')
assert(count>4)
print('PASS storage probe UI: cabinet/warehouse only and simple return to library')
