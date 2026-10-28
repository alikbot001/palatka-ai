-- Pure Lua modal regression: no FFI, no game/financial transactions.
local output,actions={},{}
local seller={shop='17',owner='Seller',qty=5,price=59000,ts=os.time()}
local buyer={shop='71',owner='Buyer',qty=504,price=72000,ts=os.time()}
local group={key='crate|0',name='Crate',row={sell={offers={seller}},buy={offers={buyer}}},
 sellers={seller},buyers={buyer},supply=5,demand=504,planned=5,profit=57800}
local planned=0
DSP={ui21={cache={},arb_tab='sell',arb_revision=0,arb_sellers={},arb_buyers={},arb_route=false},
 mobile={},settings={tax_bp=200,arb_filters={}},money=tostring,
 market={state={sid=102,version=1},offer_key=function(o)return o.shop..'|'..o.price end,
   offer_freshness=function()return 'свежее' end,
   format_units=tostring,live_offer_quantity=function()return nil end,
   plan_offers=function(_,_,_,opts)
     planned=planned+1
     return{qty=5,supply=5,demand=504,cost=295000,gross=360000,fee=7200,
       revenue=352800,profit=57800-(opts.extra or 0),extra=opts.extra or 0,
       routes={{sell_offer=seller,buy_offer=buyer,p_buy=59000,p_sell=72000,tradable_qty=5,net_profit=57800}}}
   end,
   mark_shop=function(num)actions.marked=num;return true end}}
imgui={GetContentRegionAvail=function()return{x=740,y=420}end,CloseCurrentPopup=function()end}
local V=DSP.ui21
V.fit=function(s)return s end
V.text=function(s)output[#output+1]=s end
V.muted=V.text;V.green=V.text;V.red=V.text;V.inline=function()end;V.at=function()end
V.row=function(_,_,cb)cb(740,0,0)end
V.button=function(label,id)
  output[#output+1]=label
  actions[id]=true
  if actions.press==id then actions.press=nil;return true end
  return false
end
V.memo=function(key,sig,fn)
 local m=V.cache[key]
 if not m or m.sig~=sig then m={sig=sig,value=fn()};V.cache[key]=m end
 return m.value
end
V.list_rows=function(_,rows,_,draw,options)
 for i,r in ipairs(rows)do draw(r,i)end
 if options and options.footer then options.footer()end
end
V.popup=function(_,_,draw)draw()end
assert(loadfile('src/63_ui21_arbitrage.lua'))()
V.arb_server=102;V.arb_detail_group=group;V.arb_snapshot='102/1'
V.popups()
local t=table.concat(output,'\n')
assert(t:find('Закупка (затраты): 295000',1,true),'purchase cost absent')
assert(t:find('Валовая выручка: 360000',1,true),'gross proceeds absent')
assert(t:find('Комиссия: 7200',1,true) and t:find('Чистая выручка: 352800',1,true),
 'commission or proceeds after tax absent')
assert(t:find('ПРИБЫЛЬ после закупки, комиссии и расходов: 57800',1,true),
 'net profit not distinguished from gross revenue')
assert(t:find('Продают · купить',1,true) and t:find('Скупают · продать',1,true),
 'direction explanation absent from clickable tabs')
actions.press='arb_best';V.popups()
assert(V.arb_route,'best plan button must open route rather than silently reselect everything')
assert(V.arb_sellers[DSP.market.offer_key(seller)] and V.arb_buyers[DSP.market.offer_key(buyer)],
 'best plan did not select actual source offers')
output={};V.popups();t=table.concat(output,'\n')
assert(t:find('КУПИТЬ 5 шт. у лавки #17',1,true),'purchase route direction unclear')
assert(t:find('ПРОДАТЬ скупщику #71',1,true),'resale route direction unclear')
assert(t:find('ПРИБЫЛЬ после закупки, комиссии и расходов: 57800',1,true),
 'route view lost financial breakdown')
assert(planned>=2,'automatic planner was never invoked')
local loss_red=false
V.red=function(s)if s:find('ПРИБЫЛЬ после закупки',1,true) then loss_red=true end end
V.arb_extra_enabled=true;V.arb_extra={value=60000};V.arb_revision=V.arb_revision+1
V.popups()
assert(loss_red,'a route made unprofitable by expenses must not display green profit')
-- An updated snapshot may not continue to show an old route as actionable.
DSP.market.state.version=2
V.red=function(s)output[#output+1]=s end
output={};V.popups();t=table.concat(output,'\n')
assert(t:find('Старый маршрут заблокирован',1,true),'stale plan shown after market revision')
print('v22 arbitrage popup labels, commission, net profit, loss color and best-plan route: OK')
