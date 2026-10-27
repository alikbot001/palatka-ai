local handlers,frames={},{}
local old_calls=0
package.loaded['samp.events']={onSetCheckpoint=function()old_calls=old_calls+1;return false end}
DSP={settings={},mobile={defer_save=function()end},market={state={sid=102},mark_shop=function(n)handlers.command=n;return true end},
 clean_text=function(s)return s:gsub('{%x+}','')end,lower=function(s)return string.lower(s):gsub('Л','л')end,utf8=function(s)return s end,flog=function(s)handlers.error=s end}
imgui={OnFrame=function(test,draw)frames[#frames+1]={test,draw}end}
assert(loadfile('src/47_shop_marker.lua'))()
local M=DSP.shop_marker;assert(M and M.install)
M.install();assert(DSP.market.mark_shop('75') and handlers.command=='75')
assert(M.target.num=='75' and not M.target.position,'no invented player-coordinate marker')
local events=package.loaded['samp.events']
assert(events.onSetCheckpoint({x=10,y=20,z=3},2)==false and old_calls==1,'previous RPC handler lost')
assert(not M.target.position and M.target.unverified_checkpoint.x==10,
 'unrelated checkpoint cannot become exact stall position')
assert(not frames[1][1]() and M.status():find('GPS не подтверждён',1,true),
 'unknown target should show pending status, not a false marker')
M.set_enabled(false);assert(not frames[1][1](),'toggle must stop rendering')
M.set_enabled(true);assert(not frames[1][1](),'unverified checkpoint cannot render after toggle')
assert(not DSP.market.mark_shop('75 /bad') and M.target.num=='75','invalid shop command')
assert(DSP.market.mark_shop(76));assert(not M.target.position,'new target must not retain old coordinates')
events.onCreate3DText(9,0,{x=99,y=99,z=99},20,false,0,0,'Лавка #75')
assert(not M.target.position,'another stall label cannot bind to chosen stall')
events.onCreate3DText(1,0,{x=30,y=40,z=5},20,false,0,0,'Лавка #76')
assert(M.target.position and M.target.position.x==30 and M.target.position.source=='label','exact stall label position')
events.onSetCheckpoint({x=1,y=1,z=1},2)
assert(M.target.position.x==30,'GPS should not overwrite exact stall position')
assert(M.status():find('#76',1,true) and frames[1][1](),'verified label enables world marker')
local p=M.project(function()return false,500,200,5 end,{x=0,y=0,z=0},1000,500)
assert(not p,'behind-camera markers must be hidden')
assert(not M.project(function()return true,100,200,-1 end,{x=0,y=0,z=0},1000,500))
assert(M.project(function()return true,100,200,2 end,{x=0,y=0,z=0},1000,500).x==100)
DSP.market.state.sid=103;assert(not frames[1][1]() and not M.target,'server change must clear coordinates')
print('v22 shop 3D marker: exact target, RPC chaining, toggle, projection and server isolation: OK')
