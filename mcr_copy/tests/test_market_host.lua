local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local P=assert(loadfile('mcr_copy/src/market.lua'))()
local state=E.new()
assert(E.observe(state,{server='mobile2',shop=7,owner='Owner',at=1000,source='market-helper',
 sell={{id='5',variant='0:0',name='Item',price=100,qty=2,currency='SA$'}},buy={}}))
PalatkaMCR={state=state,market=P,options={ttl=3600},
 host={server=function()return'mobile2'end,now=function()return 1000 end,
 currency=function()return'SA$'end,run=function(fn)fn()end},
 server_label=function()return'Arizona Mobile 2'end,
 refresh_market=function(done)done(true)end}
listStatusResponses={WAIT=1,SUCCESS=2,FAILURE=3}
function lIl_l__l(s,status,result)s.status=status;s.result=result end
u8=function(text)return text end
string.rlower=string.lower
function lI______ (value)return tostring(value)end
function lI_IIllI(name,level)return level>0 and name..'(+'..level..')'or name end
function lI_IIlII(id)return id>0 and'Embedded '..id or''end
i={};V={};X={};r6={};h6={};Y6={};x6={pageLimit=100};stateAvgPriceLavok={}
local fm={}
function lII_llll()return fm end
function lI__ll__()return false end
function lI__l_Il()return'mobile2'end
function llIIIlll(rows)assert(rows[1].row_number==3)end
function llIIIl_l(rows)assert(#rows>=1)end
U={main={userKey=''}}
assert(loadfile('mcr_copy/src/local_market_host.lua'))()
lI_II_I_();assert(i.status==2 and i.result.shops[1].shop_id==7)
lI_II_ll('Item');assert(X.status==2 and X.result.count==1)
lI_II_lI(7,'mobile2');assert(V.status==2 and V.result.items[1].price==100)
lI_II_lI(7,'wrong');assert(V.status==3,'foreign shop accepted')
lI_II___(false);assert(fm.status==2 and fm.result[1].items_sell[1]=='Item')
llIIll__();assert(r6.status==2 and x6.rows[2].values[3]=='100')
llIIlll_('absent');assert(h6.status==2 and x6.totalFound==0)
lIl___Il('Item');assert(Y6.status=='true'and Y6.result.sell_data[1].avg_price==100)
lIl_IIlI('Item',false);assert(stateAvgPriceLavok.status==2 and stateAvgPriceLavok.avg_sell_price==100)
lIl___Il('Item',nil,'other');assert(Y6.status=='false','foreign currency/server accepted')
assert(U.main.userKey=='')
assert(E.observe(state,{server='mobile2',shop=8,owner='B',at=1000,source='local',sell={
 {id='6',variant='4:888',bonus_level=4,embedded_item_id=888,name='Embedded item',price=900,qty=1,currency='SA$'},
 {id='7',variant='4:999',name='Opaque variant',price=900,qty=1,currency='SA$'},
 {id='6',variant='4:889',bonus_level=4,embedded_item_id=889,name='Embedded item',price=1100,qty=1,currency='SA$'}},buy={}}))
lI_II_lI(8,'mobile2')
local embedded=V.result.items[1]
assert(embedded.embedded_item_id==888 and embedded.embedded_item_text=='Embedded 888','embedded item fields lost')
assert(embedded.item_name=='Embedded item(+4)','native item naming changed')
assert(V.result.items[2].embedded_item_id==nil,'opaque discriminator guessed to be embedded item ID')
print('Native shops/search/details/price views with empty MCR key: OK')
assert(E.observe(state,{server='mobile2',shop=9,at=1000,sell={
 {id='8',variant='4:0',bonus_level=4,embedded_item_id=0,name='Enhanced',price=321,qty=1,currency='SA$'},
 {id='532',variant='0:0',name='Skull',price=100,qty=1,currency='SA$'},
 {id='10478',variant='0:0',name='Skull',price=900,qty=1,currency='SA$'},
 {id='532',variant='1:0',name='Skull',price=700,qty=1,currency='SA$'},
 {id='532',variant='0:0',name='Skull',price=5000,qty=1,currency='VC$'}},buy={}}))
lIl_IIlI('Enhanced(+4)',false)
assert(stateAvgPriceLavok.status==2 and stateAvgPriceLavok.avg_sell_price==321,'native enhanced name cannot resolve its quote')
llIIllll(1)
assert(x6.rows[1].values[7]=='ID' and x6.rows[1].values[8]=='Модификация','price table hides item identity')
local chosen
PalatkaMCR.host.imgui={TextWrapped=function()end,Button=function(label)
 if label:find('#10478',1,true)then chosen=true;return true end
 return false
end}
lIl_IIlI('Skull',false)
assert(stateAvgPriceLavok.status==3,'ambiguous legacy name combined different IDs')
PalatkaMCR.draw_price_identity_selector()
assert(chosen and stateAvgPriceLavok.status==2 and stateAvgPriceLavok.avg_sell_price==900,'visible identity button did not select the requested item')
assert(Y6.status=='true'and Y6.result.sell_data[1].avg_price==900,'identity selection did not update native price history view')
lIl_IIlI('Skull',false,{id='532',variant='0:0',currency='SA$'})
assert(stateAvgPriceLavok.avg_sell_price==100,'explicit identity mixed IDs or currencies')
lIl_IIlI('Skull(+1)',false,{id='532',variant='1:0',currency='SA$'})
assert(stateAvgPriceLavok.avg_sell_price==700,'explicit enhancement did not resolve separately')
print('Native enhanced names and selectable ID/variant/currency identity: OK')
assert(E.observe(state,{server='mobile2',shop=12,at=1000,sell={
 {id='90',variant='0:0',name='Rounded',price=100,qty=2,currency='SA$'},
 {id='90',variant='0:0',name='Rounded',price=101,qty=1,currency='SA$'},
 {id='91',variant='0:0',name='Overflow',price=9007199254740991,qty=2,currency='SA$'}},buy={
 {id='90',variant='0:0',name='Rounded',price=50,qty=1,currency='SA$'},
 {id='90',variant='0:0',name='Rounded',price=52,qty=2,currency='SA$'}}}))
lIl___Il('Rounded')
assert(Y6.status=='true'and Y6.result.sell_data[1].total_value==301,'native sell total_value missing or reconstructed from rounded average')
assert(Y6.result.buy_data[1].total_value==154,'native buy total_value lost rounding remainder')
lIl___Il('Overflow')
assert(Y6.status=='false','overflowed asking-price value was reported as successful zero turnover')
lIl_IIlI('Overflow',false)
assert(stateAvgPriceLavok.status==3,'overflowed shop average was reported as successful')
lIl_IIlI('Embedded item(+4)',false,{id='6',variant='4:888',currency='SA$'})
assert(stateAvgPriceLavok.status==2 and stateAvgPriceLavok.avg_sell_price==900,'embedded native item name cannot resolve its explicit identity')
lIl_IIlI('Embedded item(+4)',false)
assert(stateAvgPriceLavok.status==3,'embedded variants combined under their shared native name')
PalatkaMCR.host.imgui.Button=function(label)return label:find('4:889',1,true)~=nil end
PalatkaMCR.draw_price_identity_selector()
assert(stateAvgPriceLavok.status==2 and stateAvgPriceLavok.avg_sell_price==1100,'visible variant selector combined embedded improvements')
PalatkaMCR.host.currency=function()return'VC$'end
lIl_IIlI('Skull',true,{id='532',variant='0:0',currency='VC$'})
assert(stateAvgPriceLavok.status==2 and stateAvgPriceLavok.avg_sell_price==5000,'VC quote combined SA prices')
PalatkaMCR.host.currency=function()return'SA$'end
PalatkaMCR.host.imgui.Button=function(label)return label:find('#10478',1,true)~=nil end
lIl_IIlI('Skull',false);PalatkaMCR.draw_price_identity_selector()
assert(PalatkaMCR.price_identity.selector.id=='10478')
PalatkaMCR.host.currency=function()return'VC$'end
lIl_IIlI('Skull',true)
assert(stateAvgPriceLavok.status==2 and stateAvgPriceLavok.avg_sell_price==5000,'saved SA identity poisoned VC lookup')
PalatkaMCR.host.currency=function()return'SA$'end
-- A disappeared explicit selection requires choosing the remaining identity.
assert(E.observe(state,{server='mobile2',shop=9,at=1000,sell={
 {id='532',variant='0:0',name='Skull',price=100,qty=1,currency='SA$'},
 {id='8',variant='4:0',bonus_level=4,embedded_item_id=0,name='Enhanced',price=321,qty=1,currency='SA$'}},buy={}}))
lIl_IIlI('Skull',false)
assert(stateAvgPriceLavok.status==3,'missing explicit ID silently changed to another item')
local recovered=false
PalatkaMCR.host.imgui.Button=function(label)
 if label:find('#532',1,true)then recovered=true;return true end
 return false
end
PalatkaMCR.draw_price_identity_selector()
assert(recovered and stateAvgPriceLavok.status==2 and stateAvgPriceLavok.avg_sell_price==100,'single remaining identity had no recovery button')
local price_calls,original_prices=0,P.prices
P.prices=function(data)price_calls=price_calls+1;return original_prices(data)end
assert(E.observe(state,{server='mobile2',shop=10,at=1000,sell={},buy={}}))
PalatkaMCR.host.imgui.Button=function()return false end
PalatkaMCR.draw_price_identity_selector();PalatkaMCR.draw_price_identity_selector()
assert(price_calls==1,'identity selector recalculates the whole market every frame')
PalatkaMCR.host.now=function()return 5001 end
PalatkaMCR.draw_price_identity_selector()
assert(price_calls==2,'identity choice cache ignored quote expiry')
P.prices=original_prices;PalatkaMCR.host.now=function()return 1000 end
local failures={}
local function scenario(name,fn)
 local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err)end
end
local callbacks,workers,current={},{},'mobile2'
assert(E.observe(state,{server='other',shop=1,at=1000,sell={
 {id='5',variant='0:0',name='Other',price=222,qty=1,currency='SA$'}},buy={}}))
PalatkaMCR.host.server=function()return current end
PalatkaMCR.host.run=function(fn)workers[#workers+1]=fn end
PalatkaMCR.refresh_market=function(done)callbacks[#callbacks+1]=done end
local function reset()callbacks={};workers={};current='mobile2'end
local function finish_workers()for _,fn in ipairs(workers)do fn()end;workers={}end
scenario('identity cache runs outside rendering',function()
 assert(E.observe(state,{server='mobile2',shop=11,at=1000,sell={},buy={}}))
 local calls=0;P.prices=function(data)calls=calls+1;return original_prices(data)end
 PalatkaMCR.draw_price_identity_selector();PalatkaMCR.draw_price_identity_selector()
 assert(calls==0 and #workers==1,'cold full-market sorting happened inside rendering')
 finish_workers();assert(calls==1,'cached identity job was not executed once')
 PalatkaMCR.draw_price_identity_selector();assert(calls==1,'ready cache scheduled duplicate sorting')
 P.prices=original_prices
end)
scenario('same-server search ordering',function()
 reset();lI_II_ll('Item');lI_II_ll('Enhanced')
 callbacks[2](true);callbacks[1](true)
 assert(X.status==2 and X.result.shops[1].items[1].item_id==8,'older query replaced newer search')
end)
scenario('cross-server search ordering',function()
 reset();lI_II_ll('Item');current='other';lI_II_ll('absent')
 callbacks[2](true);callbacks[1](true)
 assert(X.status==2 and X.result.count==0,'obsolete server failure replaced current success')
end)
scenario('price table shared view ordering',function()
 reset();llIIllll(1);llIIlll_('Enhanced')
 callbacks[2](true);callbacks[1](true)
 assert(x6.isSearchMode and x6.returnedRows==1,'obsolete page replaced current search metadata')
 assert(r6.status~=1,'superseded table page remains waiting forever')
end)
scenario('same-server native price ordering',function()
 reset();lIl___Il('absent');lIl___Il('Item')
 callbacks[2](true);callbacks[1](true);finish_workers()
 assert(Y6.status=='true'and Y6.nameItem=='Item'and Y6.result.sell_data[1].avg_price==100,'obsolete native price completion replaced current result')
end)
scenario('cross-server native price worker',function()
 reset();lIl___Il('Item');current='other';lIl___Il('Other')
 callbacks[2](true);callbacks[1](false,'old network failure');finish_workers()
 assert(Y6.status=='true'and Y6.result.sell_data[1].avg_price==222,'obsolete failure worker replaced latest native price success')
end)
scenario('latest native price failure',function()
 reset();current='empty';lIl___Il('Item');callbacks[1](false,'latest network failure');finish_workers()
 assert(Y6.status=='false'and Y6.result:find('latest network failure',1,true),'latest native price failure was not delivered')
end)
assert(#failures==0,table.concat(failures,'\n'))
print('Market view generations reject obsolete query/server completions: OK')
