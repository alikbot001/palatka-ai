-- Strict desktop layout model: clipping/scroll boundaries, not Android rendering.
local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local function length(s)return select(2,tostring(s):gsub('[^\128-\191]',''))end
local function exercise(width,height,mode,long)
 local A=assert(loadfile('mcr_copy/src/app.lua'))()(E)
 local P=assert(loadfile('mcr_copy/src/purchases.lua'))()(E)
 assert(loadfile('mcr_copy/src/workspace.lua'))()(A,E,assert(loadfile('mcr_copy/src/resale.lua'))()(E),P)
 assert(loadfile('mcr_copy/src/ui.lua'))()(A)
 A.vertical_list=assert(loadfile('mcr_copy/src/vertical_list.lua'))()
 assert(loadfile('mcr_copy/src/workspace_ui.lua'))()(A)
 assert(loadfile('mcr_copy/src/purchases_ui.lua'))()(A)
 local frames={{name='screen',width=width,height=height,x=0,y=0,max_y=0}}
 local positions,scrolls={},{}
 local function frame()return frames[#frames]end
 local gap,line,char=4,18,8
 local function place(w,h,label)
  local f=frame();local y=f.y
  if f.same then y=f.previous.y;f.x=f.previous.x+f.previous.w+gap;f.same=false end
  assert(f.x+w<=f.width+1,'horizontal overflow '..f.name..' '..tostring(label))
  f.previous={x=f.x,y=y,w=w,h=h};f.max_y=math.max(f.max_y,y+h)
  positions[#positions+1]={view=f.name,label=label,y=y,height=h}
  f.x=0;f.y=f.max_y+gap
 end
 local function wrapped(s)
  local f=frame();local lines=1;local used=0
  for word in tostring(s):gmatch('%S+')do
   local w=length(word)*char
   if used>0 and used+char+w>f.width then lines=lines+1;used=0 end
   while w>f.width do lines=lines+1;w=w-f.width end
   used=used>0 and used+char+w or w
  end
  place(f.width,lines*line,s)
 end
 local B={}
 B.ImVec2=function(x,y)return{x=x,y=y}end
 B.GetContentRegionAvail=function()local f=frame();return{x=f.width-f.x,y=f.height-f.y}end
 B.GetStyle=function()return{ItemSpacing={x=gap,y=gap}}end
 B.GetTextLineHeight=function()return line end
 B.GetFrameHeight=function()return line+6 end
 B.GetCursorPosY=function()return frame().y end
 B.GetScrollY=function()return 0 end
 B.Dummy=function(v)place(v.x,v.y,'spacer')end
 B.CalcTextSize=function(s)return{x=length(s)*char,y=line}end
 B.Text=function(s)place(length(s)*char,line,s)end
 B.TextWrapped=wrapped;B.CenterText=B.Text
 B.Separator=function()place(frame().width,1,'separator')end
 B.Spacing=function()place(0,gap,'spacing')end
 B.SameLine=function()frame().same=true end
 B.Button=function(label,size)
  local w=size and size.x or length(label:match('^(.-)##')or label)*char+16
  local h=size and size.y or 0
  if w<=0 then w=frame().width+(w<0 and w or 0)end
  if h<=0 then h=B.GetFrameHeight()end
  place(w,h,label);return false
 end
 B.ButtonClickable=function(_,...)return B.Button(...)end
 B.SetScrollY=function(n)assert(n==0);scrolls[#scrolls+1]=frame().name end
 B.ScrollMouse=function(name)
  assert(name==frame().name,'scroll attached to wrong child');frame().scroll=true
 end
 B.BeginChild=function(name,size)
  local p=frame();local w=size.x;local h=size.y
  if w<=0 then w=p.width+w end
  if h<=0 then h=math.max(1,p.height-p.y+h)end
  assert(w>0 and h>0 and w<=p.width,'invalid child dimensions')
  assert(p.name=='pa_arb_body'or p.y+h<=p.height+1,'child consumes reserved footer '..name)
  frames[#frames+1]={name=name,width=w,height=h,x=0,y=0,max_y=0}
  return true
 end
 B.EndChild=function()
  local f=table.remove(frames)
  assert(f.scroll or f.max_y<=f.height+1,'fixed content clipped in '..f.name..': '..f.max_y..' > '..f.height)
  place(f.width,f.height,f.name)
 end
 local seller={shop=123,owner=long and string.rep('LongOwnerName',4)or'Seller',server='102',source='local',at=990}
 local buyer={shop=456,owner='Buyer',server='102',source='market-helper',at=900}
 local name=long and string.rep('Очень длинное название предмета ',8)or'Предмет'
 local route={id='5',variant='4:888',name=name,seller=seller,buyer=buyer,seller_qty=3,buyer_qty=700,
  qty=2,buy_price=1000000,sell_price=10000000,cost=2000000,gross=20000000,
  fee=400000,net=19600000,profit=17600000,currency='SA$'}
 A.install({imgui=B,utf8=function(s)return s end,now=function()return 1000 end,
  server=function()return'102'end,currency=function()return'SA$'end,center_width=function()return width-80 end,
  sidebar_width=function()return 64 end,market_server_id=function()return 102 end,
  run=function()error('work started while drawing')end,find=function()error('trade action while drawing')end})
 if mode~='empty'and mode~='loading'then
  A.result_server='102';A.result_at=1000;A.results={route,route,route}
  if mode=='many'then for n=4,5000 do A.results[n]=route end end
 end
 if mode=='details'then assert(A.select_route(1))end
 if mode=='resale'or mode=='resale_details'then
  route.reference_price=12000000;route.peer_price=12000000;route.peer_count=4;route.roi_bp=5523
  route.popularity={kind='market_sales',market_qty_30d=8892,market_updated_at=900,buyer_shops=2,buyer_qty=50,own_qty=0,own_events=0}
  A.workspace_tab='resale';A.resale_results={route,route,route};A.resale_server='102';A.resale_currency='SA$';A.resale_at=1000;A.resale_revision=0
  if mode=='resale_details'then assert(A.select_resale(1))end
 end
 if mode=='purchases'then
  A.workspace_tab='purchases';A.book_loaded=true
  A.purchases_view=function()return{lots={{id=1,name=name,unit_cost=long and E.MAX or 1000000,
   qty=1,remaining=1,currency='SA$',note=name}},invested=long and E.MAX or 1000000,realized_profit=long and E.MAX or 100000,sold_qty=0}end
 end
 A.busy=mode=='loading'
 A.draw_center()
 assert(#frames==1,'unbalanced children')
 local body_end,footer_start
 for _,p in ipairs(positions)do
  if p.label=='pa_arb_body'then body_end=p.y+p.height end
  if p.view=='Central'and(p.label:find('Вариантов:',1,true)or p.label:find('План:',1,true)or p.label:find('Вложено:',1,true))then footer_start=p.y end
 end
 assert(body_end and footer_start and footer_start>=body_end,'footer overlays the body')
 assert(#scrolls==1,'body must reset to its start on first open')
 return A,B,scrolls
end
for _,size in ipairs({{310,280},{460,360},{620,512},{760,650},{1200,880},
 {800,360},{925,512},{1120,650},{2340,1080}})do
 for _,mode in ipairs({'empty','loading','list','details','resale','resale_details','purchases'})do
  for _,long in ipairs({false,true})do exercise(size[1],size[2],mode,long)end
 end
end
exercise(310,280,'many',false)
print('Arbitrage/resale/purchases fixed header/footer: 126 layouts + 5000 routes OK')
