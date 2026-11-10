local A={engine=dofile('mcr_copy/src/engine.lua'),book_loaded=true,server_label=function()return'Arizona Mobile 2'end}
local current,open,visible='Central',{},{}
local B={new={char=setmetatable({},{__index=function()return function(v)return{value=v}end end})},
 ImVec2=function(x,y)return{x=x,y=y}end,GetIO=function()return{DisplaySize={y=360}}end,
 GetTextLineHeight=function()return 16 end,BeginChild=function()return true end,EndChild=function()end,
 InputText=function()end,ScrollMouse=function()end}
local click
A.host={imgui=B,server=function()return'102'end,currency=function()return'SA$'end,
 utf8=function(s)return s end,input_string=function(v)return v.value end,
 open_popup=function(title)open[current..'/'..title]=true end}
A.ui={wrapped=function()end,text=function()end,money=tostring,caption=function()end,
 item_title=function()end,button=function(label)
  if click and label:find(click,1,true)then click=nil;return true end;return false
 end,
 popup=function(title,draw)
  if open[current..'/'..title]then visible[title]=true;draw()end
 end,
 list=function(rows,_,draw)
  for _,row in ipairs(rows)do current='pa_purchase_list_'..row.id;draw(row)end
 end}
dofile('mcr_copy/src/purchases_ui.lua')(A)
A.open_purchase({id='5',variant='0:0',name='Item',qty=1,buy_price=100,currency='SA$',seller={server='102'}})
current='RightSidebar';A.purchase_popups()
assert(visible['Записать покупку'],'purchase popup opened in another ImGui window scope')
click='##pa_sell_1'
A.draw_purchases({{id=1,name='Item',unit_cost=100,qty=1,remaining=1,currency='SA$',server='102'}},{})
current='RightSidebar';A.purchase_popups()
assert(visible['Записать продажу'],'sale popup opened in another ImGui window scope')
print('Native popup routing: purchase/detail/lot actions share modal window scope OK')
