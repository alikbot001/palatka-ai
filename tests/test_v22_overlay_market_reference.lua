-- A stall cannot be its own market reference. No frame network calls.
local observed={}
local now=1800000000
os.time=function()return now end
local live={shop={num='1',owner='Owner',opened=50,sell={{name='Crate',ench=0,price=120000,qty_known=false}},buy={}}}
DSP={settings={server=102,dpi=1.25},ui={},live=live,utf8=function(s)return s end,
 item_key=function(n,e)return n..'|'..(e or 0) end,item_name=function(n)return n end,
 money=function(n)return '$'..n end,market={state={sid=102,version=1,by_key={}}},
 db={sid=102,freshness=function()return 'cached'end,get=function()return nil end},
 theme={opacity=.97,col=function()return{}end,push_overlay=function()return 0 end}}
local nop=function()end
imgui={new={bool=function(v)return{[0]=v}end},ImVec2=function(x,y)return{x=x,y=y}end,
 ImVec4=function()return{}end,Col={},WindowFlags=setmetatable({},{__index=function()return 0 end}),
 Cond={FirstUseEver=0},GetIO=function()return{DisplaySize={x=1200,y=700}}end,
 SetNextWindowPos=nop,SetNextWindowSize=nop,SetNextWindowBgAlpha=nop,PopStyleColor=nop,
 SameLine=nop,Separator=nop,End=nop,EndChild=nop,
 Begin=function()return true end,BeginChild=function()return true end,Button=function()return false end,
 SmallButton=function()return false end,Text=function(s)observed[#observed+1]=s end,
 TextWrapped=function(s)observed[#observed+1]=s end,TextDisabled=function(s)observed[#observed+1]=s end,
 TextColored=function(_,s)observed[#observed+1]=s end}
assert(loadfile('src/50_overlay.lua'))()
local side={offers={{shop='1',price=120000,ts=now,qty=5}}}
DSP.market.state.by_key['Crate|0']={sell=side,buy={offers={}}}
assert(DSP.overlay.shop_market_reference('Crate',0,1,'sell')==nil,'self quote became market')
DSP.overlay.draw_shop()
assert(table.concat(observed,'\n'):find('НЕТ СВЕЖИХ ЧУЖИХ ЦЕН',1,true),'self reference displayed as cheap')
side.offers[#side.offers+1]={shop='2',price=120000,ts=now}
side.offers[#side.offers+1]={shop='3',price=120000,ts=now}
DSP.market.state.version=2
local q=DSP.overlay.shop_market_reference('Crate',0,1,'sell')
assert(q and q.n==2 and q.shops==2 and q.med==120000,'wrong comparable market quotes')
observed={};DSP.overlay.draw_shop()
local output=table.concat(observed,'\n')
assert(output:find('НА УРОВНЕ РЫНКА',1,true),'market equality wrongly called cheap')
assert(not output:find('НИЖЕ ДРУГИХ',1,true),'market equality marked bargain')
DSP.market.state.sid=103
assert(DSP.overlay.shop_market_reference('Crate',0,1,'sell')==nil,'cross-server price leak')
print('overlay: self-reference excluded, market parity and server isolation: OK')
