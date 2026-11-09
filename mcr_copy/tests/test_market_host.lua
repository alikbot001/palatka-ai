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
function lI_IIllI(name,level)return level>0 and name..' (+'..level..')'or name end
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
 {id='7',variant='4:999',name='Opaque variant',price=900,qty=1,currency='SA$'}},buy={}}))
lI_II_lI(8,'mobile2')
local embedded=V.result.items[1]
assert(embedded.embedded_item_id==888 and embedded.embedded_item_text=='Embedded 888','embedded item fields lost')
assert(embedded.item_name=='Embedded item (+4)','native item naming changed')
assert(V.result.items[2].embedded_item_id==nil,'opaque discriminator guessed to be embedded item ID')
print('Native shops/search/details/price views with empty MCR key: OK')
