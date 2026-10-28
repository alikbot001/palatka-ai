-- Current version must be consistent across standalone metadata, core and mobile UI.
local function read(path)
    local f=assert(io.open(path, 'rb'))
    local s=f:read('*a');f:close();return s
end
local core=read('src/00_core.lua')
local builder=read('build.py')
local standalone=read('palatka_ai.lua')
assert(core:find("DSP.version = '2.2.11'",1,true))
assert(builder:find("script_version('2.2.11')",1,true))
assert(standalone:find("script_version('2.2.11')",1,true))
assert(standalone:find("DSP.version = '2.2.11'",1,true))
for _,file in ipairs({'src/60_ui21_shell.lua', 'src/65_ui22_tools.lua', 'src/36_mobile.lua','src/30_ui.lua'}) do
    assert(read(file):find('DSP.version',1,true), file..' needs shared version')
end
print('PASS v2.2.11 shared UI and Lua metadata')
