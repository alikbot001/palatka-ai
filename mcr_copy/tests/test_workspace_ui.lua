local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local A=assert(loadfile('mcr_copy/src/app.lua'))()(E)
local R=assert(loadfile('mcr_copy/src/resale.lua'))()(E)
local P=assert(loadfile('mcr_copy/src/purchases.lua'))()(E)
assert(loadfile('mcr_copy/src/workspace.lua'))()(A,E,R,P)
A.vertical_list=assert(loadfile('mcr_copy/src/vertical_list.lua'))()
assert(loadfile('mcr_copy/src/ui.lua'))()(A)
assert(loadfile('mcr_copy/src/workspace_ui.lua'))()(A)
local calls,click,finds,server={},nil,0,'102'
local B={new={char=setmetatable({},{__index=function()return function(v)return{value=v}end end}),
 float=function(v)return{[0]=v}end,bool=function(v)return{[0]=v}end}}
local function log(label)calls[#calls+1]=label end
B.Text=log;B.TextWrapped=log;B.CenterText=log
B.Separator=function()end;B.Spacing=function()end;B.SameLine=function()end
B.GetStyle=function()return{ItemSpacing={x=8,y=4}}end
B.GetContentRegionAvail=function()return{x=520,y=600}end
B.GetTextLineHeight=function()return 20 end;B.GetFrameHeight=function()return 26 end
B.GetCursorPosY=function()return 0 end;B.GetScrollY=function()return 0 end
B.SetScrollY=function()end;B.ScrollMouse=function()end;B.Dummy=function()end
B.ImVec2=function(x,y)return{x=x,y=y}end;B.BeginChild=function()return true end;B.EndChild=function()end
B.CalcTextSize=function(s)return{x=#s*7,y=20}end
B.Button=function(label)log(label);if click and label:find(click,1,true)then click=nil;return true end;return false end
B.ButtonClickable=function(enabled,...)if enabled then return B.Button(...)end end
B.InputFloat=function()return false end;B.InputText=function()return false end;B.Checkbox=function()return false end
local h={imgui=B,utf8=function(s)return s end,server=function()return server end,
 currency=function()return'SA$'end,now=function()return 1000 end,
 find=function()finds=finds+1 end,run=function()error('work unexpectedly started by drawing resale')end,
 input_string=function(v)return v.value end,market_server_id=function()return 102 end}
A.install(h)
A.workspace_tab='resale';A.resale_server='102';A.resale_currency='SA$';A.resale_revision=0;A.resale_at=1000
A.resale_results={{id='5',variant='0:0',name='Coupon',currency='SA$',qty=10,
 seller={shop=1,owner='Seller',server='102',source='market-helper',at=1000},seller_qty=20,
 buy_price=10000,sell_price=15840,reference_price=16000,peer_price=17000,history_price=16000,peer_count=4,
 cost=100000,gross=158400,fee=3168,net=155232,profit=55232,roi_bp=5523,
 popularity={kind='market_sales',market_qty_30d=8892,market_updated_at=900,buyer_shops=2,buyer_qty=50,own_qty=0,own_events=0}}}
A.draw_center();local list=table.concat(calls,'\n')
assert(list:find('Перепродажа',1,true)and list:find('8.892',1,true),'monthly popularity is invisible')
assert(not list:find('##pa_page',1,true),'horizontal pagination returned')
calls={};A.resale_results[1].name='Coupon\nExtra';A.draw_center()
for _,value in ipairs(calls)do assert(not value:find('\n',1,true),'one-line list caption contains a newline')end
A.resale_results[1].name='Coupon'
click='##pa_resale_1';A.draw_center();assert(A.resale_details and A.resale_selected==1)
calls={};A.draw_center();local details=table.concat(calls,'\n')
for _,s in ipairs({'Coupon','По данным Market Helper','30 дней','Цена рынка','Цель продажи','55.232'})do
 assert(details:find(s,1,true),'missing price/popularity provenance '..s)
end
click='##pa_resale_find';A.draw_center();assert(finds==1)
server='103';click='##pa_resale_find';A.draw_center();assert(finds==1,'stale resale sent command')
server='102'
A.resale_settings();assert(A.apply_resale_settings())
local bounded=false
B.GetIO=function()return{DisplaySize={x=800,y=360}}end
B.Cond={Appearing=1};B.SetNextWindowPos=function()end
B.BeginChild=function(id,size)
 if id=='pa_arb_settings'then assert(size.y<=162 and size.y>0);bounded=true end
 return true
end
h.draw_popup=function(title,draw)if title=='Параметры арбитража'then draw()end end
A.draw_right();assert(bounded,'additional settings grew the native popup off screen')
print('Resale UI: monthly popularity, separate reference/target/fees, selection and stale guards OK')
