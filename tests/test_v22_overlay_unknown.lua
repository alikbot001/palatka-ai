-- Regression: a lavka without an observed quantity must never invent x1.
local shown={}
DSP={settings={dpi=1.25},ui={},utf8=function(s)return s end,
 item_name=function(n)return n end,money=function(n)return '$'..n end,
 market={state={sid=102}},db={sid=102,freshness=function()return 'cached' end,get=function()return nil end},
 live={shop={num='75',owner='Owner',opened=100,updated=100,menu_closed=0,
   sell={{name='Unknown',price=1000,qty=nil,qty_known=false},
         {name='Known',price=500,qty=7,qty_known=true}},buy={}},
   trade={give={},get={}}},
 theme={opacity=.97,col=function()return{}end,push_overlay=function()return 0 end}}
local noop=function()end
imgui={new={bool=function(v)return{[0]=v}end},
 ImVec2=function(x,y)return{x=x,y=y}end,ImVec4=function()return{}end,
 Col={},WindowFlags=setmetatable({},{__index=function()return 0 end}),
 Cond={FirstUseEver=0},
 GetIO=function()return{DisplaySize={x=2340,y=1080}}end,
 SetNextWindowPos=noop,SetNextWindowSize=noop,SetNextWindowFocus=noop,
 SetNextWindowBgAlpha=noop,PopStyleColor=noop,SameLine=noop,Separator=noop,
 End=noop,EndChild=noop,
 Begin=function()return true end,BeginChild=function()return true end,
 Button=function()return false end,SmallButton=function()return false end,
 Text=function(s)shown[#shown+1]=s end,TextWrapped=function(s)shown[#shown+1]=s end,
 TextDisabled=function(s)shown[#shown+1]=s end,
 TextColored=function(_,s)shown[#shown+1]=s end}
assert(loadfile('src/50_overlay.lua'))()
DSP.overlay.draw_shop()
local output=table.concat(shown,'\n')
assert(output:find('Unknown  · кол-во неизвестно',1,true),'unknown stock rendered as a number')
assert(output:find('Known  x7',1,true),'known stock quantity was lost')
assert(not output:find('Unknown  x1',1,true),'unknown stock falsely became x1')
print('v22 legacy shop overlay unknown qty: OK')
