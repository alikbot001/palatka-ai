-- Pure Lua UI regression: source disagreement is visible and pressing Confirm
-- is required before replacing the API amount. No server trades.
local offered={shop='71',owner='Wood_Trader',price=10,qty=1,ts=os.time()}
local row={key='wood|0',sell={offers={offered}}}
local seen,press,confirm={},nil,{}
local V={shop_item='wood|0',offer_detail=offered,offer_detail_row='wood|0',offer_detail_side='sell'}
local M={compact_number=function()end,thumbnail=function()end}
DSP={ui21=V,mobile=M,money=function(n)return '$'..tostring(n)end,settings={marker_3d_enabled=false},market={state={sid=102,version=1,
 by_key={['wood|0']=row}},offer_freshness=function()return '10 сек' end,
 format_units=tostring,quantity_info=function()
 return {api=1,live=45000,disagreement=true}
 end,confirm_offer_quantity=function(_,side,o,qty,src)
 confirm[#confirm+1]={side=side,offer=o,qty=qty,source=src};return true
 end,mark_shop=function()end},notify=function()end}
imgui={GetContentRegionAvail=function()return{x=620,y=300}end,CloseCurrentPopup=function()end}
V.at=function()end;V.inline=function()end;V.red=function(s)seen[#seen+1]=s end
V.text=V.red;V.muted=V.red;V.fit=function(s)return s end
V.button=function(label,id,w)seen[#seen+1]=label;if press==id then press=nil;return true end;return false end
V.popup=function(_,_,draw)draw()end
V.list=function(key,draw,o)
 assert(key=='offer_detail_panel','detail must be scrollable on short mobile screens')
 assert(o.height>0,'detail panel has no height')
 draw();o.footer()
 end
assert(loadfile('src/62_ui21_shops.lua'))()
V.popups()
local text=table.concat(seen,' | ')
assert(text:find('Количество API: 1',1,true),'unverified API value hidden')
assert(text:find('Открытая лавка: 45000',1,true),'observed game amount hidden')
assert(text:find('Источники расходятся',1,true),'mismatch warning missing')
assert(#confirm==0,'viewing popup silently overwrote source amount')
press='shops_accept_game_qty';V.popups()
assert(#confirm==1 and confirm[1].qty==45000 and confirm[1].source=='game','confirmation not sourced to observed game packet')
V.shop_qty_input.value=45001
press='shops_confirm_qty';V.popups()
assert(#confirm==2 and confirm[2].qty==45001 and confirm[2].source=='manual','manual count action did not confirm exact input')
DSP.market.state.by_key={}
seen={};press='shops_accept_game_qty';V.popups()
assert(#confirm==2 and table.concat(seen,' '):find('устарело',1,true),'stale offer modified during popup')
print('shop quantity modal: source disagreement, scrolling, explicit game/manual actions, stale guard: OK')
