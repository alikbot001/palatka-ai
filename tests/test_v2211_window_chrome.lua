-- Pure regression for the common popup close and corner resize; not native touch proof.
package.preload['ffi']=function()return {} end
DSP={ui={},screens={set=function()end}, mobile={defer_save=function()end}, settings={mobile_window={x=30,y=25,w=680,h=450}},
    utf8=function(s)return s end,clamp=function(v,a,b)return math.max(a,math.min(v,b))end,
    theme={col=function()return{}end}}
local positions,events,click={}, {},false
imgui={Cond={Appearing=1},WindowFlags={NoTitleBar=1,NoScrollbar=2,NoResize=4},
    ImVec2=function(x,y)return{x=x,y=y}end,GetIO=function()return{DisplaySize={x=1100,y=750}}end,
    SetNextWindowPos=function()end,SetNextWindowSize=function()end,
    BeginPopupModal=function(_,_,flags)assert(flags%8<4 or flags==1,'bad flags');assert(flags%8<4,'popup unexpectedly fixed');return true end,
    EndPopup=function()events.ended=true end,GetCursorPosX=function()return 8 end,GetCursorPosY=function()return 8 end,
    GetContentRegionAvail=function()return{x=600,y=290}end,
    Text=function()end,TextDisabled=function()end,Separator=function()end,
    SetCursorPos=function(pos)positions[#positions+1]=pos end,
    Button=function(label) if label:find('##v22_modal_x_detail',1,true)then return click end;return false end,
    CloseCurrentPopup=function()events.closed=(events.closed or 0)+1 end,
    GetCursorScreenPos=function()return{x=1020,y=660}end,GetWindowDrawList=function()return{AddLine=function()end}end,
    GetColorU32=function()return 0xffffff end,Col={Text=1},IsItemActive=function()return events.dragging end}
dofile('src/60_ui21_shell.lua')
local V=DSP.ui21
local drawn=0
V.popup('Подробности','detail',function()drawn=drawn+1 end)
assert(drawn==1 and not events.closed,'detail opens normally')
click=true
V.popup('Подробности','detail',function()drawn=drawn+1 end)
assert(drawn==1 and events.closed==1,'modal X closes without walking back')
assert(positions[1] and positions[1].x>500,'modal X anchored at right')
local before=DSP.settings.mobile_window
local save=0;DSP.mobile.defer_save=function()save=save+1 end
events.dragging=true
V.resize_grip({x=30,y=25,w=680,h=450},{DisplaySize={x=1100,y=750},MouseDelta={x=45,y=25}})
local after=DSP.settings.mobile_window
assert(after.w==before.w+45 and after.h==before.h+25,'corner drag expands both dimensions')
assert(after.x==30 and after.y==25 and save==1,'position retained and save deferred')
print('PASS common modal close and bottom-right resize')
