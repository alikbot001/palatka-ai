-- Exercise the actual CP1251 artifact and startup wiring, not only source modules.
dofile('tests/test_ui.lua')
local root=os.tmpname(); os.remove(root)
assert(os.execute('mkdir -p '..root..'/PalatkaAI/logs')==0)
getWorkingDirectory=function()return root end
local commands,frames={},{}
sampRegisterChatCommand=function(name,fn)commands[name]=fn end
imgui.OnFrame=function(condition,draw)frames[#frames+1]={condition,draw} end
lua_thread={create=function(fn)return {_fn=fn} end}
script_name=function()end;script_author=function()end;script_version=function()end
package.preload['samp.events']=function()return {} end
addEventHandler=function()end
DSP=nil
assert(loadfile('palatka_ai.lua'))()
assert(DSP.version=='1.3.3')
assert(DSP.mobile and DSP.notes and DSP.rewards and DSP.trade_runtime)
assert(DSP.craglog.installed and #frames>=3, 'mini journal and main window registered')
assert(commands.crr and commands.crlog,'both commands are wired')
commands.crr();assert(DSP.ui.open)
commands.crlog();assert(DSP.settings.craglog.open)
DSP.craglog.set_pinned(true)
commands.crr();assert(not DSP.ui.open and DSP.craglog.visible())
local f=assert(io.open(DSP.log_path));local log=f:read('*a');f:close()
assert(not log:find('INSTALL ERROR',1,true),log)
print('standalone startup tests: ok')
