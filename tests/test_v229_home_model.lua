-- Carbon Trade dashboard actions; deterministic model, not a pixel rendering test.
local taps,seen,pulled={}, {},0
local V={}
V.heading=function(_,right)right()end
V.button=function(_,id)
 seen[id]=true
 return taps[id]==true
end
V.set_screen=function(id)V.screen=id end
V.list=function(_,cb,opts)cb(850);if opts.footer then opts.footer() end end
V.row=function(id,height,cb)cb(850,0,0)end
V.muted=function(s)end
V.text=function(s)end
V.green=function(s)end
V.fit=function(s,w)return s end
V.at=function(x,y)end
V.apply_font=function()end
V.inline=function()end
imgui={Separator=function()end,GetContentRegionAvail=function()return{x=850}end,BeginChild=function()return true end,EndChild=function()end,ImVec2=function(x,y)return{x=x,y=y}end,WindowFlags={NoScrollbar=1}}
DSP={ui21=V,settings={server=102},market={state={rows={},sid=102,status='ok'},
 freshness=function()return'актуально'end,pull=function(sid)pulled=pulled+1;assert(sid==102)end},
 detect_server=function()return 102 end,money=function(v)return '$'..v end,
 craglog={summary=function()return{net=15,income=20,expense=5}end,
 ring_recent=function()return{{ts=os.time(),kind='market'}}end,
 describe=function()return'Продажа: тест'end}}
dofile('src/60a_carbon_home.lua')
V.home()
assert(seen.carbon_quick_arb and seen.carbon_quick_shop and seen.carbon_quick_storage)
assert(seen.carbon_link_1 and seen.carbon_link_6 and seen.carbon_refresh)
assert(pulled==0,'dashboard must not fetch every frame')
taps.carbon_refresh=true;V.home();assert(pulled==1,'refresh is only on a deliberate click')
taps.carbon_refresh=nil;taps.carbon_quick_storage=true;V.home();assert(V.screen=='scan')
print('PASS v2.2.9 Carbon landing page navigation / opt-in refresh / live counters')
