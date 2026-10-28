-- Accessible mobile actions: a dedicated open button per commodity and a
-- full-size select button per raw offer. No game transactions invoked.
local clicked,seen={},{}
local offer_a={shop='1',owner='Seller',qty=1,price=100,ts=os.time()}
local offer_b={shop='2',owner='Buyer',qty=45000,price=170,ts=os.time()}
local row={key='wood|0',name='Wood',sell={offers={offer_a}},buy={offers={offer_b}}}
local group={key='wood|0',name='Wood',row=row,sellers={offer_a},buyers={offer_b},
 supply=1,demand=45000,planned=1,profit=66}
local plan={qty=1,cost=100,gross=170,fee=4,revenue=166,profit=66,extra=0,
 routes={{sell_offer=offer_a,buy_offer=offer_b,tradable_qty=1,p_buy=100,p_sell=170,net_profit=66}}}
DSP={ui21={cache={},arb_tab='sell',arb_revision=0,searches={},errors={}},mobile={},
 settings={tax_bp=200,arb_filters={}},money=tostring,lower=string.lower,
 market={state={sid=102,version=1,status='live'},freshness=function()return 'now' end,
 offer_key=function(o)return tostring(o.shop) end,
 offer_freshness=function()return 'now' end,
 format_units=function(n)return tostring(n or '?') end,
 live_offer_quantity=function()return nil end,
 arbitrage_grouped=function()return{group}end,
 plan_offers=function()return plan end,mark_shop=function()return true end}}
imgui={GetContentRegionAvail=function()return {x=760,y=470}end,CloseCurrentPopup=function()end}
local V=DSP.ui21
DSP.mobile.thumbnail=function()end
V.search=function()return '',false end
V.at=function()end;V.text=function()end;V.muted=function()end
V.green=function()end;V.red=function()end;V.fit=function(s)return s end
V.inline=function()end;V.reset_list=function()end
V.row=function(_,_,fn)fn(720,0,0)end
V.button=function(label,id,w)
 seen[id]={label=label,width=w}
 if clicked[id]then clicked[id]=false;return true end
 return false
end
V.memo=function(_,_,fn)return fn()end
V.list_rows=function(_,rows,_,fn,opts)
 for i,x in ipairs(rows)do fn(x,i)end
 if opts and opts.footer then opts.footer()end
end
V.popup=function(_,_,fn)fn()end
V.open_popup=function()seen.opened=true end
assert(loadfile('src/63_ui21_arbitrage.lua'))()
V.arbitrage()
assert(seen.arb_group_1 and seen.arb_group_1.label:find('Предложения',1,true)
 and seen.arb_group_1.width>=150,'commodity must have a large explicit Open button')
clicked.arb_group_1=true;V.arbitrage()
assert(seen.opened and V.arb_detail_group==group,'dedicated open button not wired')
V.arb_server=102;V.arb_snapshot='102/1'
V.popups()
assert(seen.arb_select_1 and seen.arb_select_1.width>=150,'offer select button too narrow')
assert(V.arb_sellers['1'],'seller not selected by default')
clicked.arb_select_1=true;V.popups()
assert(not V.arb_sellers['1'],'full width button failed to deselect offer')
assert(seen.arb_verify_sell1 and seen.arb_pin_1,'verify and marker actions missing')
print('arbitrage touch buttons: visible dedicated open/select/verify/marker: OK')
