-- Native mimgui container scanner controls: only test model, no MonetLoader.
DSP={ui21={},storage={}}
local V=DSP.ui21
local count,pressed=0,''
function V.button(label,id,width,active) return id==pressed end
function V.text(s) count=count+1 end
function V.muted(s) count=count+1 end
function V.red(s) count=count+1 end
function V.green(s) count=count+1 end
function V.fit(s,w) return s end
imgui={Separator=function()end}
DSP.storage_probe={armed=false,kind=nil,order={},observed=0,ignored_trunk=0,ignored_stall=0}
local P=DSP.storage_probe
function P.state() return P end
function P.arm(kind,sec)
 P.armed=true;P.kind=kind;P.status='armed';P.until_ts=os.time()+sec;return true
end
function P.stop() P.armed=false;P.status='review' end
function P.preview(i)
 return {entry={type=4,sub=2,count=30},occupied=1,known=20,unknown_qty=0,
 rows={{name='Test',qty=20}}}
end
function P.save(i) return true,{kind=P.kind} end
function P.export_report() return true,'test.json' end
dofile('src/60e_storage_probe_ui.lua')
V.storage_probe_panel(320,'cabinet')
assert(not P.armed)
pressed='probe_arm_cabinet';V.storage_probe_panel(320,'cabinet')
assert(P.armed and P.kind=='cabinet')
pressed='probe_stop';V.storage_probe_panel(320,'cabinet')
assert(not P.armed)
P.order={{type=4,sub=2,count=30}}
pressed='probe_save';V.storage_probe_panel(320,'cabinet')
assert(V.storage_tab=='snapshots' and V.storage_selected==1)
-- Switching to inventory must not show previous cabinet data as inventory.
V.storage_tab='scan'
pressed='';V.storage_probe_panel(320,'inventory')
assert(not P.armed and V.storage_tab=='scan')
assert(count>5)
print('PASS storage probe UI: separate kind, start, stop, preview, save')
