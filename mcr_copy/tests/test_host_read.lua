local host
local env={F3={},T={},NeomText={},PalatkaMCR={install=function(h)host=h end},
 getWorkingDirectory=function()return'/tmp/palatka-test'end}
setmetatable(env,{__index=_G})
local code=assert(loadfile('mcr_copy/src/host.lua'));setfenv(code,env);code()
env.Y={attributes=function()return nil,'permission denied',13 end}
local raw,why=host.read('purchases.json')
assert(raw==nil and why and why:find('permission',1,true),'inaccessible ledger treated as missing file')
env.Y.attributes=function()return nil,'no such file',2 end
raw,why=host.read('purchases.json');assert(raw==nil and why==nil,'new ledger cannot start empty')
print('Native storage distinguishes an absent ledger from stat/read failures: OK')
