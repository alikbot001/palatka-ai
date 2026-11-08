-- Regression for the embedded Stable/Beta downloader and safe replacement.
local base='tests/_channel_smoke_script.lua'
local function write(path,s)
    local f=assert(io.open(path,'wb'));assert(f:write(s));assert(f:close())
end
local initial="-- old installed Palatka AI test file\n"
write(base,initial)
local fake="-- Palatka AI v2.9.16 mobile release\nscript_name('palatka ai')\nscript_version('2.9.16')\n"
fake=fake..string.rep('-',500000-#fake-5)..'\n]=]\n'
assert(#fake==500000)
local download_log={}
local valid_sha=string.rep('a',64)
local V={set_screen=function(_,id)end,button=function()end,open_popup=function()end,
    popups=function()end,popup=function()end,tools=function()end}
local U={set_open=function()end}
DSP={
    ui21=V,ui=U,mobile={defer_save=function()end},
    settings={},version='2.9.16',utf8=function(v)return v end,
    save_settings=function()return true end,
    notify=function()end,
    auto={sell_running=false,buy_running=false},
}
thisScript=function()return {path=base}end
decodeJson=function(s)
    assert(s=='manifest test')
    return {schema=1,channel=_G.channel_under_test,version='2.9.16',size=#fake,
        sha256=valid_sha,url='https://raw.githubusercontent.com/alikbot001/palatka-ai/'..
            (_G.channel_under_test=='stable'and'main'or'beta')..'/palatka_ai.lua'}
end
downloadUrlToFile=function(url,path,callback)
    download_log[#download_log+1]=url
    if url:find('channels/',1,true)then
        write(path,'manifest test')
    else
        write(path,fake)
    end
    callback(1,6)
end
assert(loadfile('src/69f_channel_updater.lua'))()
local C=DSP.channels
assert(C.allowed_url('stable','https://raw.githubusercontent.com/alikbot001/palatka-ai/main/palatka_ai.lua'))
assert(not C.allowed_url('stable','https://example.com/hijack.lua'))
assert(not C.allowed_url('beta','https://raw.githubusercontent.com/alikbot001/palatka-ai/main/palatka_ai.lua'))
_G.channel_under_test='beta'
assert(C.select('beta'));assert(C.check());assert(C.state=='ready')
assert(C.install());assert(C.state=='installed')
assert(assert(io.open(base,'rb')):read('*a')==fake)
assert(assert(io.open(base..'.bak','rb')):read('*a')==initial)
assert(download_log[1]:find('/beta/updates/channels/beta.json',1,true))
assert(download_log[2]:find('/beta/palatka_ai.lua',1,true))
os.remove(base);os.remove(base..'.bak')
print('PASS two channels, strict URL, manifest, stage, backup, replacement')
