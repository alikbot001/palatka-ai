local E=dofile('mcr_copy/src/engine.lua')
local P=dofile('mcr_copy/src/purchases.lua')(E)
local A=dofile('mcr_copy/src/app.lua')(E)
dofile('mcr_copy/src/workspace.lua')(A,E,{rank=function()return{}end},P)
local file=io.open('mcr_copy/src/purchases_ui.lua','rb')
assert(file,'missing purchase note UI');file:close()
local queue,calls,edits,click={}, {},{},nil
local server,currency,opened='102','SA$',nil
local depth,io_count,frame=0,0,false
local write_ok=true
local screen={x=800,y=360}
local function log(kind,value)calls[#calls+1]={kind,value,depth}end
local function drain()while #queue>0 do table.remove(queue,1)()end end
local B=setmetatable({
 new={char=setmetatable({}, {__index=function(_,capacity)return function(s)
    assert(#s<capacity);return {value=s}
 end end})},
 ImVec2=function(x,y)return{x=x,y=y}end,
 GetIO=function()return{DisplaySize=screen}end,
 GetTextLineHeight=function()return 16 end,GetFrameHeight=function()return 24 end,
 GetContentRegionAvail=function()return{x=400,y=180}end,
 BeginChild=function(id,size)
    assert(size.y>0 and size.y<=screen.y*.4 and size.y<=128,'unbounded form body')
    depth=depth+1;log('child',id);return true
 end,
 EndChild=function()depth=depth-1;assert(depth>=0)end,
 ScrollMouse=function(id)assert(depth>0);log('scroll',id)end,
 InputText=function(label,buffer,capacity)
    assert(depth>0,'form field outside bounded child')
    if edits[label]~=nil then buffer.value=edits[label];edits[label]=nil;return true end
    log('input',label..'='..buffer.value);return false
 end,
}, {__index=function(_,key)error('unconfirmed imgui API: '..key)end})
local function text(s)log('text',tostring(s))end
local function button(label)
 log('button',label)
 if click and (label==click or label:find(click,1,true))then click=nil;return true end
 return false
end
local function host_io()io_count=io_count+1;assert(not frame,'I/O during draw')end
local h={imgui=B,server=function()return server end,currency=function()return currency end,
 market_server_id=function()return 102 end,
 now=function()return 1000 end,utf8=function(s)return s end,to_cp=function(s)return s end,
 input_string=function(b)return b.value end,run=function(fn)queue[#queue+1]=fn end,
 read=function()host_io();return nil end,decode=function(v)host_io();return v end,
 encode=function(v)host_io();return v end,write=function()host_io();return write_ok,'disk full' end,
 yield=function()end,find=function()error('UI attempted live trade/navigation')end,
 open_popup=function(title)opened=title end}
A.install(h);A.load();drain()
A.ui={text=text,wrapped=function(s)log('wrapped',tostring(s))end,
 caption=function(s)log('caption',s)end,button=button,
 money=function(n)return string.format('%.0f',n)end,
 item_title=function(r)text(r.name);text('ID '..tostring(r.id)..' / '..tostring(r.variant))end,
 popup=function(title,draw)log('popup',title);if title==opened then draw()end end,
 list=function(rows,id,draw)
    assert(id=='pa_purchase_list');log('list',#rows)
    -- The shared virtual renderer owns clipping; the module must delegate to it.
    for i=1,math.min(2,#rows)do draw(rows[i],i)end
 end}
dofile('mcr_copy/src/purchases_ui.lua')(A)
local function render()
 frame=true;A.purchase_popups();frame=false;click=nil;assert(depth==0)
end
local function output()
 local t={};for _,c in ipairs(calls)do t[#t+1]=tostring(c[2])end
 return table.concat(t,'\n')
end
local function save_purchase()click='##pa_purchase_save';render()end
local function save_sale()click='##pa_sale_save';render()end
local function fill(qty,cost,name,note)
 edits['##pa_purchase_qty']=qty;edits['##pa_purchase_cost']=cost
 edits['##pa_purchase_name']=name;edits['##pa_purchase_note']=note
end
-- Blank/manual forms reject missing cost and malformed visible numbers without writes.
click='Записать покупку';A.purchases_header()
render()
assert(opened=='Записать покупку')
fill('3','','Manual item','batch note');save_purchase()
assert(not A.book_busy and #queue==0 and #A.purchase_state.lots==0)
for _,bad in ipairs({'10.5','1.00','1 00','1.000 000','1e3','-1','9007199254740992'})do
 fill('3',bad,'Manual item','note');save_purchase()
 assert(not A.book_busy and #queue==0,'invalid visible cost reused previous number: '..bad)
end
fill('3','0','Manual item','free lot');save_purchase()
assert(A.book_busy and #A.purchase_state.lots==0,'save was not queued')
calls={};render();assert(not output():find('##pa_purchase_cost=',1,true),
    'pending fields still accept edits to values already queued')
save_purchase();assert(#queue==1,'pending form queued duplicate save')
drain();assert(#A.purchase_state.lots==1 and A.purchase_state.lots[1].unit_cost==0)
assert(A.purchase_state.lots[1].item_id==nil,'manual name fabricated identity')
calls={};render();assert(output():find('Записано',1,true),'async success not shown next frame')
save_purchase();assert(#queue==0,'saved form submitted duplicate note')

-- An exact row pre-fills identity, price and quantity; its identity name is read-only.
local route={id='5',variant='0:0',name='Exact item',currency='SA$',qty=4,
 buy_price=10000,seller={server='102'}}
A.open_purchase(route);calls={};render()
assert(output():find('##pa_purchase_qty=4',1,true) and output():find('##pa_purchase_cost=10000',1,true))
assert(not output():find('##pa_purchase_name=',1,true),'exact identity name became editable')
edits['##pa_purchase_cost']='1.000';edits['##pa_purchase_qty']='1 000'
save_purchase();drain()
local lot=A.purchase_state.lots[2]
assert(lot.name=='Exact item'and lot.item_id=='5'and lot.variant=='0:0'
 and lot.qty==1000 and lot.unit_cost==1000)

-- Captured server/currency must still match when saving either form.
A.open_purchase(route);server='103';save_purchase()
assert(#queue==0 and #A.purchase_state.lots==2,'server-switched purchase saved')
server='102';A.open_purchase(route);currency='BTC';save_purchase()
assert(#queue==0,'currency-switched purchase saved');currency='SA$'
A.book_loaded=false;A.open_purchase();fill('1','1','Blocked');save_purchase()
assert(#queue==0,'unloaded ledger was overwritten');A.book_loaded=true

-- Row actions use actual net proceeds for partial sale records, with no unit estimate.
local view=P.view(A.purchase_state,'102','SA$')
calls={};click='Записать продажу##pa_sell_'..lot.id
A.draw_purchases(view.lots,view)
render()
assert(opened=='Записать продажу'and output():find('1000 / 1000',1,true),'remaining/initial stock missing')
calls={};render()
assert(output():find('Фактически получено',1,true),'sale total mistaken for estimated unit price')
save_sale();assert(#queue==0,'missing actual net total accepted')
edits['##pa_sale_qty']='2';edits['##pa_sale_net']='3.001';edits['##pa_sale_note']='partial'
save_sale();assert(A.book_busy);save_sale();assert(#queue==1)
drain();assert(A.purchase_state.lots[2].remaining==998)
assert(A.purchase_state.sales[1].net_total==3001 and A.purchase_state.sales[1].profit==1001)
calls={};render();assert(output():find('Записано',1,true))
view=P.view(A.purchase_state,'102','SA$');click='##pa_sell_'..lot.id;A.draw_purchases(view.lots,view)
server='103';edits['##pa_sale_qty']='1';edits['##pa_sale_net']='1500';save_sale()
assert(#queue==0,'server-switched sale saved');server='102'

-- List/footer draws use cached view only, keep money out of ellipsis captions.
calls={};frame=true
A.draw_purchases(view.lots,view);A.purchase_footer(view);A.purchases_header()
frame=false
assert(output():find('Вложено:',1,true)and output():find('ручным',1,true),'manual totals absent')
for _,call in ipairs(calls)do
 if call[1]=='caption'then assert(not call[2]:find('Цена:',1,true),'money was truncated')end
 if call[1]=='text'then assert(not call[2]:find('Цена:',1,true)
    and not call[2]:find('Остаток:',1,true),'financial row cannot wrap in narrow panels')end
end
local closed={id=99,name='Closed',unit_cost=1,qty=3,remaining=0,currency='SA$'}
calls={};A.draw_purchases({closed},view)
assert(not output():find('##pa_sell_99',1,true),'sold-out lot can open sale form')
for _,size in ipairs({{800,360},{925,512},{1120,650}})do
 screen={x=size[1],y=size[2]};A.open_purchase(route);render()
end
-- Read-only exact names must never be copied into a fixed-size editable buffer.
local long={id='6',variant='0:0',name=string.rep('Длинное имя ',200),qty=1,
 buy_price=1,currency='SA$',seller={server='102'}}
A.open_purchase(long);render()
local large={id='7',variant='0:0',name='Large price',qty=1,
 buy_price=1000000000000000,currency='SA$',seller={server='102'}}
A.open_purchase(large);calls={};render()
assert(output():find('##pa_purchase_cost=1000000000000000',1,true),
    'integer prefill became unsupported scientific notation')
assert(output():find('Arizona Mobile 2',1,true)and not output():find('Сервер 102',1,true),
    'technical canonical server identity leaked into manual form')
for _,c in ipairs(calls)do if c[1]=='text'then
 assert(not c[2]:find('Цена за',1,true)and not c[2]:find('Сервер',1,true),
    'form labels cannot wrap within popup')
end end

-- Disk failures stay unsaved, preserve the ledger and permit an explicit retry.
A.open_purchase(route);write_ok=false;save_purchase();drain()
assert(#A.purchase_state.lots==2 and not A.book_busy)
calls={};render();assert(output():find('disk full',1,true)and not output():find('Записано',1,true))
write_ok=true;save_purchase();drain();assert(#A.purchase_state.lots==3)
calls={};render();assert(output():find('Записано',1,true))

-- A shared virtual list may display two out of 5,000 cached rows without extra work.
local bulk={};for i=1,5000 do bulk[i]=closed end
calls={};frame=true;A.draw_purchases(bulk,view);frame=false
local captions=0;for _,c in ipairs(calls)do if c[1]=='caption'then captions=captions+1 end end
assert(captions==4,'purchase list bypassed shared row clipping')
assert(depth==0 and io_count>0)
print('Manual purchase/sale UI: bounded forms, strict numbers, scope, persistence and async safety: OK')
