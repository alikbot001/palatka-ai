-- Failure to persist a "missing item/shop" verdict must not hide the route.
DSP={
  dir='.',settings={server=102,tax_bp=200},lower=string.lower,
  market={state={sid=102,status='live',rows={}},missing_shops={},
    invalidate_arbitrage=function()end,
    offer_quantity=function(_,_,offer)return offer.qty,{source='api'}end},
  mobile={defer_save=function()end},
  save_settings=function()return true end
}
local M=DSP.market
M.mark_shop_missing=function(shop)
  M.missing_shops['102:'..tostring(shop)]=1234567899
  return true
end
M.restore_shop=function(shop)
  M.missing_shops['102:'..tostring(shop)]=nil
  return true
end
assert(loadfile('src/69a_arbitrage_agent.lua'))()
assert(loadfile('src/69c_arbitrage_status.lua'))()
local A=DSP.arb_agent
local save_ok=true
A.save=function()if save_ok then return true end return false,'disk full'end
local t=os.time()
assert(A.start({{
 row={key='sword:0',display='Sword',ench=0},name='Sword',
 tradable_qty=3,p_buy=100,p_sell=200,net_profit=260,
 sell_offer={shop=17,owner='seller',price=100,qty=3,ts=t},
 buy_offer={shop=18,owner='buyer',price=200,qty=3,ts=t},
}}))
local e=A.get(1)
save_ok=false
local ok,err=A.mark_unavailable(1,'item')
assert(not ok and tostring(err):find('сохранить',1,true))
assert(not e.unavailable_reason and not e.skipped)
assert(next(A.data.unavailable)==nil)
ok,err=A.mark_unavailable(1,'shop')
assert(not ok and tostring(err):find('сохранить',1,true))
assert(not e.unavailable_reason and not e.skipped)
assert(M.missing_shops['102:17']==nil)
save_ok=true
assert(A.mark_unavailable(1,'item'))
assert(e.unavailable_reason=='item_missing' and e.skipped==true)
assert(A.active().focus==1)
assert(DSP.settings.arb_agent_open==true)
assert(A.restore_unavailable(1))
assert(e.unavailable_reason==nil and e.skipped==false)
print('2.9.7 missing route: atomic mark/restore, panel stays open ok')
