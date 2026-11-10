local factory=assert(loadfile('mcr_copy/src/updater.lua'))()
local hash=assert(loadfile('mcr_copy/src/sha256.lua'))()
local body='-- Configuration: Palatka MCR Local; independent client build.\n'..string.rep('-- update test\n',100)
local manifest={schema=1,channel='mcr-local',build=6,version='3.0.0-local.6',size=#body,sha256=hash(body)}
local base='https://raw.githubusercontent.com/alikbot001/palatka-ai/feat/mcr-full-copy-arbitrage-20261108/outputs/'
manifest.url=base..'palatka_mcr_local.lua'
local notifications,installed,active,saved={},0,false,nil
local activate_during_download=false
local U=factory({current_build=5,base=base,sha256=hash,
 get=function(url,done)
  if url:find('.json',1,true)then done('manifest')else
   if activate_during_download then active=true end
   done(body)
  end
 end,
 decode=function(raw)assert(raw=='manifest');return manifest end,
 notify=function(s)notifications[#notifications+1]=s end,
 busy=function()return active end,compile=loadstring,
 install=function(bytes)assert(bytes==body);installed=installed+1;return true end,
 remember=function(build)saved=build;return true end,remembered=function()return saved end})
U.check(false,false);assert(#notifications==1 and installed==0 and saved==6)
U.check(false,false);assert(#notifications==1,'same update announced repeatedly')
U.check(true,true);assert(installed==1)
manifest.build=7;manifest.version='3.0.0-local.7'
manifest.sha256=string.rep('0',64);U.check(true,true)
assert(installed==1 and U.error:find('SHA256',1,true),'corrupt download not verified')
manifest.sha256=hash(body);manifest.url='https://example.org/injected.lua'
U.check(true,true);assert(installed==1,'foreign URL installed')
assert(U.error:find('описание',1,true))
manifest.url=base..'palatka_mcr_local.lua';active=true
U.check(true,true);assert(installed==1,'updated during an active operation')
assert(U.error:find('операцию',1,true))
active=false;activate_during_download=true
U.check(true,true);assert(installed==1 and U.error:find('Началась операция',1,true),'late operation did not block replacement')
activate_during_download=false
active=false;manifest.build=5;manifest.version='3.0.0-local.5'
U.check(true,true);assert(installed==1,'same version reinstalled')
manifest.build=8;manifest.version='3.0.0-local.8'
local attempts,announced=0,0
local retry=factory({current_build=6,base=base,decode=function()return manifest end,
 get=function(_,done)done('manifest')end,remembered=function()return 0 end,
 notify=function()announced=announced+1 end,remember=function(build)
  assert(build==8);attempts=attempts+1;return attempts>1,'disk full'
 end})
retry.check(false,false);retry.check(false,false)
assert(announced==1 and attempts==2,'notification persistence was not retried without spam')
print('Update notification/manual install/hash/origin/busy guards: OK')
