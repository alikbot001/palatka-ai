local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local A=assert(loadfile('mcr_copy/src/app.lua'))()(E)
local f=io.open('mcr_copy/src/ui.lua','rb');assert(f,'missing MCR arbitrage section');f:close()
assert(loadfile('mcr_copy/src/ui.lua'))()(A)
local calls,depth={},0
local B={new={char=setmetatable({},{__index=function()return function(s)return s end end}),
    float=function(v)return{[0]=v}end}}
local function record(name)return function(...)calls[#calls+1]={name,...};return false end end
for _,n in ipairs({'Text','TextWrapped','Separator','Spacing','SameLine','Button','InputText','InputFloat','CenterText','ScrollMouse'})do B[n]=record(n)end
B.GetContentRegionAvail=function()return{x=480,y=300}end
B.ImVec2=function(x,y)return{x=x,y=y}end
B.BeginChild=function()depth=depth+1;return true end
B.EndChild=function()depth=depth-1;assert(depth>=0)end
local h={imgui=B,utf8=function(s)return s end,now=function()return 1000 end,
    server=function()return '102'end,run=function()error('unexpected work while drawing')end,
    input_string=function(v)return v end,find=function()error('unexpected game command')end}
A.install(h)
A.draw_center();A.draw_right()
assert(depth==0 and #calls>4,'unbalanced or empty UI')
local found=false
for _,c in ipairs(calls)do if c[1]=='TextWrapped'and c[2]:find('Откройте',1,true)then found=true end end
assert(found,'empty-state instructions missing')
assert(#A.current_results()==0)
print('MCR arbitrage UI strict API/balance/empty state: OK')
