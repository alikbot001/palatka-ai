-- Native mimgui probe controls: minimal strict model of the UI entry points.
DSP={ui21={},storage={}}
local V=DSP.ui21
local count,pressed=0,''
function V.button(label,id,width,active) return id==pressed end
function V.text(x) count=count+1 end
function V.muted(x) count=count+1 end
function V.red(x) count=count+1 end
function V.green(x) count=count+1 end
function V.fit(x,width) return x end
imgui={Separator=function()end}
DSP.storage_probe={armed=false,kind=nil,order={},observed=0,ignored_trunk=0}
local P=DSP.storage_probe
function P.state() return P end
function P.arm(kind,sec) P.armed=true;P.kind=kind;P.until_ts=os.time()+sec;return true end
function P.stop()P.armed=false end
function P.preview(i)return {entry={type=4,sub=2,count=30},occupied=1,known=20,unknown_qty=0,
 rows={{name='Test',qty=20}}} end
function P.save(i) return true,{kind=P.kind} end
dofile('src/60e_storage_probe_ui.lua')
V.storage_probe_panel(320)
pressed='probe_arm_cabinet';V.storage_probe_panel(320);assert(P.armed and P.kind=='cabinet')
pressed='probe_stop';V.storage_probe_panel(320);assert(not P.armed)
P.order={{type=4,sub=2,count=30}}
pressed='probe_save';V.storage_probe_panel(320)
assert(V.storage_tab=='snapshots' and V.storage_selected==1)
assert(count>5)
print('PASS storage probe UI: idle, arm, stop, preview, save')
