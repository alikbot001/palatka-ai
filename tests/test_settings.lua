package.preload.encoding=function() return {UTF8={encode=function(_,s)return s end,decode=function(_,s)return s end}} end
getWorkingDirectory=function()return '/tmp/palatka_settings' end
doesDirectoryExist=function()return true end
encodeJson=function()return '{}' end
dofile('src/00_core.lua')
local open=io.open
io.open=function()return {write=function()return nil,'disk full' end,close=function()return true end} end
local saved,err=DSP.save_settings()
assert(saved==false and err, 'failed write must be reported')
io.open=open
assert(os.execute('mkdir -p /tmp/palatka_settings/PalatkaAI')==0)
assert(DSP.save_settings())
local f=assert(io.open(DSP.settings_path));assert(f:read('*a')=='{}');f:close()
print('settings tests: ok')
