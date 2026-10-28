local calls=0
DSP={settings={}}
imgui={}
imgui.Col={FrameBg=1,Border=2,CheckMark=3}
imgui.ImVec2=function(x,y)return{x=x,y=y}end
imgui.GetColorU32=function(n)return n end
imgui.GetWindowDrawList=function()return{
 AddRectFilled=function()calls=calls+1 end,
 AddRect=function()calls=calls+1 end,
 AddLine=function()calls=calls+1 end}
end
dofile('src/60c_carbon_draw.lua')
local D=DSP.carbon_draw
D.begin_frame()
assert(D.row(10,10,120,60) and calls==3)
D.max_shapes=3
assert(D.row(10,10,120,60) and calls==3,'draw calls per frame are bounded')
D.begin_frame();DSP.settings.carbon_draw_enabled=false
assert(not D.row(10,10,120,60) and calls==3,'fallback switch must be respected')
print('PASS v2.2.10 custom DrawList budget/disable')
