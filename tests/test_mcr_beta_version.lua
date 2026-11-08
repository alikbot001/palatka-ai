-- Beta preview script versions must be checked against a selected manifest.
local file='tests/_mcr_beta_updater.tmp'
local body="-- Palatka AI v2.9.17-beta.1 preview\nscript_name('palatka ai')\n"..
    "script_version('2.9.17-beta.1')\n"..string.rep('-',600)..'\n]=]\n'
local f=assert(io.open(file,'wb'));assert(f:write(body));assert(f:close())
local V={tools=function()end,popups=function()end,popup=function()end}
DSP={ui21=V,ui={set_open=function()end},mobile={defer_save=function()end},
    settings={},version='2.9.17-beta.1',utf8=function(v)return v end,
    flog=function()end}
assert(loadfile('src/69f_channel_updater.lua'))()
local C=DSP.channels
local manifest={version='2.9.17-beta.1',size=#body}
local ok,why=C.verify_file(file,manifest)
assert(ok,why)
assert(not C.verify_file(file,{version='2.9.16',size=#body}),
    'stale stable manifest must not accept a newer beta script')
assert(not C.allowed_url('beta','https://raw.githubusercontent.com/alikbot001/palatka-ai/main/palatka_ai.lua'))
os.remove(file)
print('PASS MCR beta semantic version and strict channel origin')
