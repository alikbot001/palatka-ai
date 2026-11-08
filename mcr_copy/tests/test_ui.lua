local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local A=assert(loadfile('mcr_copy/src/app.lua'))()(E)
local f=io.open('mcr_copy/src/ui.lua','rb');assert(f,'missing MCR arbitrage section');f:close()
assert(loadfile('mcr_copy/src/ui.lua'))()(A)
local calls,depth={},0
local available={x=480,y=600}
local B={new={char=setmetatable({},{__index=function()return function(s)return s end end}),
    float=function(v)return{[0]=v}end}}
local function record(name)return function(...)calls[#calls+1]={name,...};return false end end
for _,n in ipairs({'Text','TextWrapped','Separator','Spacing','SameLine','Button','InputText','InputFloat','CenterText','ScrollMouse'})do B[n]=record(n)end
B.GetContentRegionAvail=function()return available end
B.GetStyle=function()return{ItemSpacing={x=8,y=4}}end
B.GetTextLineHeight=function()return 20 end
B.CalcTextSize=function(s)return{x=#s*10,y=20}end
B.ImVec2=function(x,y)return{x=x,y=y}end
B.BeginChild=function()depth=depth+1;return true end
B.EndChild=function()depth=depth-1;assert(depth>=0)end
local h={imgui=B,utf8=function(s)return s end,now=function()return 1000 end,
    server=function()return '102'end,run=function()error('unexpected work while drawing')end,
    input_string=function(v)return v end,find=function()error('unexpected game command')end,
    sidebar_button_height=function()return 70 end,
    draw_settings_popup=function()end,open_settings=function()end}
A.install(h)
A.draw_center();A.draw_right()
assert(depth==0 and #calls>4,'unbalanced or empty UI')
local found=false
for _,c in ipairs(calls)do if c[1]=='TextWrapped'and c[2]:find('Откройте',1,true)then found=true end end
assert(found,'empty-state instructions missing')
assert(#A.current_results()==0)
local tiles=0
for _,c in ipairs(calls)do
    if c[1]=='Button'and c[2]:find('##pa_rail_',1,true)and not c[2]:find('pa_rail_prev',1,true)and not c[2]:find('pa_rail_next',1,true)then
        assert(type(c[3])=='table'and c[3].x==-1 and c[3].y==70,'sidebar tile differs from MCR geometry')
        tiles=tiles+1
    end
    assert(c[1]~='InputText'and c[1]~='InputFloat','settings leaked into icon sidebar')
end
assert(tiles==4,'expected four MCR action tiles')
local seller={shop=1,source='local',at=1000,server='102'}
local buyer={shop=2,source='local',at=1000,server='102'}
A.result_server='102';A.result_at=1000
A.results={{name='Item',qty=2,seller=seller,buyer=buyer,buy_price=1000000,
    sell_price=10000000,cost=2000000,gross=20000000,fee=400000,profit=17600000,currency='SA$'}}
calls={};A.draw_center();A.draw_right()
local rendered={};for _,c in ipairs(calls)do if type(c[2])=='string'then rendered[#rendered+1]=c[2]end end
local output=table.concat(rendered,'\n')
for _,v in ipairs({'1.000.000','10.000.000','2.000.000','20.000.000','400.000','17.600.000'})do
    assert(output:find(v,1,true),'money is not grouped: '..v)
end
assert(not output:find('1000000',1,true),'ungrouped price remains')
for _,size in ipairs({{100,580},{72,360},{90,220}})do
    available={x=size[1],y=size[2]};calls={}
    h.sidebar_width=function()return 120 end
    A.draw_right()
    local total=0
    for _,c in ipairs(calls)do
        if c[1]=='Button'and c[2]:find('##pa_rail_',1,true)and not c[2]:find('pa_rail_prev',1,true)and not c[2]:find('pa_rail_next',1,true)then
            total=total+c[3].y+32
        elseif c[1]=='CenterText'then
            assert(B.CalcTextSize(c[2]).x<=available.x,'sidebar label leaves narrow panel')
        end
    end
    assert(total<=available.y,'action tiles leave panel vertically')
end
print('MCR arbitrage UI strict API/balance/empty state: OK')
