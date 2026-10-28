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
assert(DSP.version=='2.2.11')
assert(DSP.items.loaded and DSP.items.name(5723)~='ID:5723','clean install has embedded catalog')
assert(DSP.ui22 and DSP.ui22.tools and DSP.craglog.delete_event)
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
local image_id=next(DSP.item_icon_index or {})
assert(image_id,'autonomous artifact must include real item images')
local png=assert(DSP.item_icons.get(image_id),'read an indexed PNG from the actual CP1251 artifact')
assert(png:sub(1,8)=='\137PNG\r\n\26\n','indexed offset must address real PNG bytes')
assert(DSP.item_icon_data==nil,'do not keep the full base64 image bank in the Lua heap')
print('standalone indexed real PNG bank: ok')
