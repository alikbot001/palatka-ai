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
