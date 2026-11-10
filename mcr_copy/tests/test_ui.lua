local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local A=assert(loadfile('mcr_copy/src/app.lua'))()(E)
local f=io.open('mcr_copy/src/ui.lua','rb');assert(f,'missing MCR arbitrage section');f:close()
assert(loadfile('mcr_copy/src/ui.lua'))()(A)
local calls,depth={},0
local available={x=480,y=600}
local B={new={char=setmetatable({},{__index=function()return function(s)return s end end}),
    float=function(v)return{[0]=v}end}}
local function record(name)return function(...)calls[#calls+1]={name,...};return false end end
for _,n in ipairs({'Text','TextWrapped','TextDisabled','Separator','Spacing','SameLine','Button','InputText','InputFloat','CenterText','ScrollMouse','SetScrollY'})do B[n]=record(n)end
B.GetContentRegionAvail=function()return available end
B.GetStyle=function()return{ItemSpacing={x=8,y=4}}end
B.GetTextLineHeight=function()return 20 end
B.GetFrameHeight=function()return 26 end
B.CalcTextSize=function(s)return{x=#s*10,y=20}end
B.GetIO=function()return{DisplaySize={x=2340,y=1080}}end
B.Cond={Appearing='appearing'}
B.SetNextWindowPos=record('SetNextWindowPos')
B.ImVec2=function(x,y)return{x=x,y=y}end
B.BeginChild=function(name,size)calls[#calls+1]={'BeginChild',name,size};depth=depth+1;return true end
B.EndChild=function()depth=depth-1;assert(depth>=0)end
local h={imgui=B,utf8=function(s)return s end,now=function()return 1000 end,
    server=function()return '102'end,run=function()error('unexpected work while drawing')end,
    input_string=function(v)return v end,find=function()error('unexpected game command')end,
    sidebar_button_height=function()return 70 end,
    draw_popup=function()end,open_popup=function()end}
A.install(h)
A.draw_center();A.draw_right()
assert(depth==0 and #calls>4,'unbalanced or empty UI')
local found=false
for _,c in ipairs(calls)do if c[1]=='TextWrapped'and c[2]:find('Откройте',1,true)then found=true end end
assert(found,'empty-state instructions missing')
assert(#A.current_results()==0)
local positions=0
for _,c in ipairs(calls)do
 if c[1]=='SetNextWindowPos'then
  positions=positions+1
  assert(c[2].x==1170 and c[2].y==540 and c[3]=='appearing')
  assert(c[4].x==0.5 and c[4].y==0.5,'popup is not centered by its own size')
 end
end
assert(positions==2,'new popups do not open at screen center')
local body=false
for _,c in ipairs(calls)do
 if c[1]=='BeginChild'and c[2]=='pa_arb_body'then body=true;assert(c[3].y>0)end
 assert(not(c[1]=='ScrollMouse'and c[2]=='Central'),'header/footer scroll with the item list')
end
assert(body,'arbitrage has no independently scrolling body')
local tiles=0
for _,c in ipairs(calls)do
    if c[1]=='Button'and c[2]:find('##pa_rail_',1,true)and not c[2]:find('pa_rail_prev',1,true)and not c[2]:find('pa_rail_next',1,true)then
        assert(type(c[3])=='table'and c[3].x==-1 and c[3].y==70,'sidebar tile differs from MCR geometry')
        tiles=tiles+1
    end
    assert(c[1]~='InputText'and c[1]~='InputFloat','settings leaked into icon sidebar')
end
assert(tiles==3,'expected calculation, settings and sources tiles')
local seller={shop=1,source='va-ta-cache',at=1000,server='102'}
local buyer={shop=2,source='local',at=1000,server='102'}
A.result_server='102';A.result_at=1000
A.results={{id='5',variant='0:0',name='Item',seller_qty=3,buyer_qty=700,qty=2,seller=seller,buyer=buyer,buy_price=1000000,
    sell_price=10000000,cost=2000000,gross=20000000,fee=400000,profit=17600000,currency='SA$'}}
assert(A.select_route(1));calls={};A.draw_center();A.draw_right()
local rendered={};for _,c in ipairs(calls)do if type(c[2])=='string'then rendered[#rendered+1]=c[2]end end
local output=table.concat(rendered,'\n')
for _,v in ipairs({'1.000.000','10.000.000','2.000.000','20.000.000','400.000','17.600.000'})do
    assert(output:find(v,1,true),'money is not grouped: '..v)
end
for _,label in ipairs({'Item','1. Купить у продавца','2. Сдать в скупку','3. Расчёт','Лавка #1','Лавка #2','Источники','После комиссии'})do
 assert(output:find(label,1,true),'missing route context: '..label)
end
assert(not output:find('va-ta-cache',1,true),'technical source label leaked')
assert(not output:find('1000000',1,true),'ungrouped price remains')
local reset=false
for _,c in ipairs(calls)do if c[1]=='SetScrollY'and c[2]==0 then reset=true end end
assert(reset,'opening details inherits the previous list scroll position')
calls={};A.draw_center()
for _,c in ipairs(calls)do assert(c[1]~='SetScrollY','reading the card resets scrolling every frame')end
A.generation=A.generation+1;calls={};A.draw_center();reset=false
for _,c in ipairs(calls)do if c[1]=='SetScrollY'then reset=true end end
assert(reset,'replaced market results retain scroll from the previous data')
A.results[1].variant='4:0:quality=2:wear=10';calls={};A.draw_center()
local modified={};for _,c in ipairs(calls)do if type(c[2])=='string'then modified[#modified+1]=c[2]end end
local identity=table.concat(modified)
assert(identity:find('Улучшение +4',1,true)and identity:find('Качество: 2',1,true)
 and identity:find('Износ: 10',1,true),'special item variants became indistinguishable')
A.results[1].variant='0:0'
local tracked={}
h.find=function(shop,server)tracked[#tracked+1]={shop,server}end
local click
local original_button=B.Button
B.Button=function(label,...)
    original_button(label,...)
    if click and label:find(click,1,true)then click=nil;return true end
    return false
end
click='##pa_find_buy';A.draw_center()
click='##pa_find_sell';A.draw_center()
assert(#tracked==2 and tracked[1][1]==1 and tracked[2][1]==2)
h.can_click=function()return false end
click='##pa_find_buy';A.draw_center();assert(#tracked==2,'drag activated a route action')
h.can_click=nil
A.route_details=false;A.selected=nil
click='##pa_find_buy';A.draw_center()
assert(#tracked==2,'find button appeared without a chosen route')
click='##pa_route_1';A.draw_center()
assert(A.selected==1 and A.route_details,'list did not open exact route')
A.route_details=false;calls={};click=nil;A.draw_center()
local list={};for _,c in ipairs(calls)do if type(c[2])=='string'then list[#list+1]=c[2]end end
local listing=table.concat(list,'\n')
local title=assert(listing:find('Item',1,true))
local purchase=assert(listing:find('Купить в лавке #1',1,true),'list purchase side is ambiguous')
local buyback=assert(listing:find('Сдать в лавку #2',1,true),'list buyback side is ambiguous')
local open=assert(listing:find('Посмотреть расчёт',1,true),'list action is detached from the item')
assert(title<purchase and purchase<buyback and buyback<open,'item/card information order is confusing')
h.server=function()return '103'end
click='##pa_find_buy';A.draw_center()
assert(#tracked==2,'old server route sent command')
h.server=function()return '102'end
h.draw_popup=function(title,draw)
    if title=='Источники цен'then draw()end
end
calls={};click=nil;A.draw_right()
local sources_text={}
for _,c in ipairs(calls)do if type(c[2])=='string'then sources_text[#sources_text+1]=c[2]end end
assert(table.concat(sources_text):find('не обновляет цены в интернете',1,true),'cache mistaken for live prices')
h.draw_popup=function()end
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
