-- Execute the real native host adapter, not a hand-written updater host.
local decode_calls,notices=0,{}
local base='https://raw.githubusercontent.com/alikbot001/palatka-ai/feat/mcr-full-copy-arbitrage-20261108/outputs/'
local manifest={schema=1,channel='mcr-local',build=7,version='3.0.0-local.7',
 url=base..'palatka_mcr_local.lua',size=2000000,sha256=string.rep('a',64)}
T={decode=function(raw)
 assert(raw=='published manifest');decode_calls=decode_calls+1;return manifest
end,encode=function(data)assert(data.notified_build==7);return'notification state'end}
local factory=assert(loadfile('mcr_copy/src/updater.lua'))()
PalatkaMCR={build=6,version='3.0.0-local.6',update_base=base,
 sha256=function()error('no payload should be hashed during notification check')end,
 host={read=function()return nil end,write=function(name,raw)
  assert(name=='updater.json'and raw=='notification state');return true
 end,run=function(fn)fn()end},
 new_updater=factory,install_file=function()error('check must not install')end}
function sampAddChatMessage(message)notices[#notices+1]=message end
function lIl_l_lI(method,url,options,success)
 assert(method=='GET'and url==base..'palatka_mcr_update.json')
 success({status_code=200,text='published manifest'})
end
assert(loadfile('mcr_copy/src/local_update_host.lua'))()
PalatkaMCR.updater.check(true,false)
assert(decode_calls==1,'native updater host did not provide JSON decoder')
assert(not PalatkaMCR.updater.error,'valid manifest rejected by actual host adapter')
assert(notices[#notices]:find('3.0.0-local.7',1,true))
print('Real native updater host wiring/manifest decode/notification: OK')

-- Exercise the native flags through the real adapter and file installer.
local hash=assert(loadfile('mcr_copy/src/sha256.lua'))()
local replace=assert(loadfile('mcr_copy/src/update_file.lua'))()
local body='-- Configuration: Palatka MCR Local; independent client build.\n'..string.rep('-- update payload\n',100)
local next_manifest={schema=1,channel='mcr-local',build=8,version='3.0.0-local.8',
 url=base..'palatka_mcr_local.lua',size=#body,sha256=hash(body)}
local function read(path)
 local file=assert(io.open(path,'rb'));local bytes=file:read('*a');assert(file:close());return bytes
end
local function check_buy_guard(flag,during_download)
 local temporary=os.tmpname()
 local path=temporary..'.lua'
 local original='-- original script\n'
 local file=assert(io.open(path,'wb'));assert(file:write(original));assert(file:close())
 local ok,why=pcall(function()
  local pending,downloads
  downloads=0
  local env={m6=false,isParseInventoryDialogsForBuy=false}
  setmetatable(env,{__index=_G})
  env.T={decode=function(raw)assert(raw=='release manifest');return next_manifest end}
  env.PalatkaMCR={build=7,version='3.0.0-local.7',update_base=base,
   sha256=hash,new_updater=factory,install_file=replace,
   host={read=function()return nil end,run=function(fn)fn()end}}
  env.thisScript=function()return{path=path}end
  env.wait=function()end
  env.sampAddChatMessage=function()end
  env.lIl_l_lI=function(method,url,options,success,_,timeout)
   assert(method=='GET'and options.headers['Cache-Control']=='no-cache'and timeout==30)
   if url==base..'palatka_mcr_update.json'then
    success({status_code=200,text='release manifest'})
   else
    assert(url==next_manifest.url and pending==nil)
    downloads=downloads+1;pending=success
   end
  end
  local adapter=assert(loadfile('mcr_copy/src/local_update_host.lua'))
  setfenv(adapter,env);adapter()
  local updater=env.PalatkaMCR.updater
  local function finish_download()
   local done=assert(pending,'payload request missing');pending=nil
   done({status_code=200,text=body})
  end
  if during_download then
   assert(updater.check(true,true)and updater.busy)
   env[flag]=true;finish_download()
   assert(updater.error and updater.error:find('Началась операция',1,true),flag..' did not block late install')
  else
   env[flag]=true
   assert(updater.check(true,true))
   assert(downloads==0,flag..' did not block payload download')
   assert(updater.error and updater.error:find('Завершите текущую операцию',1,true),flag..' busy error missing')
  end
  assert(not updater.busy and not updater.installed_build)
  assert(read(path)==original,flag..' allowed script replacement during a buy')
  local backup=io.open(path..'.crr-backup','rb')
  if backup then backup:close();error(flag..' invoked installer during a buy')end
  env[flag]=false
  assert(updater.check(true,true)and updater.busy)
  finish_download()
  assert(not updater.busy and not updater.error and updater.installed_build==8)
  assert(read(path)==body and read(path..'.crr-backup')==original,'idle update/backup failed')
 end)
 for _,suffix in ipairs({'','.crr-backup','.crr-new','.crr-backup.tmp'})do os.remove(path..suffix)end
 os.remove(temporary)
 assert(ok,why)
end
local failures={}
for _,flag in ipairs({'m6','isParseInventoryDialogsForBuy'})do
 for _,during_download in ipairs({false,true})do
  local label=flag..(during_download and' during download'or' at invocation')
  local ok,why=pcall(check_buy_guard,flag,during_download)
  if ok then print('Native updater buy guard: '..label..': OK')
  else failures[#failures+1]=label..': '..tostring(why)end
 end
end
assert(#failures==0,table.concat(failures,'\n'))
