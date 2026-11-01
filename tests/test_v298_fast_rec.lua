-- Pure LuaJIT model test: only real observed spawns can be selected.
local snapshot={}
local p={known_spawns=nil}
local choices={}
local manual_calls=0
_G.DSP={
 settings={fast_rec={},reconnect={spawn_enabled=false}},
 lower=function(s)return string.lower(s)end,
 utf8=function(s)return s end,
 save_settings=function()return true end,
 reconnect={
    options={}, state='idle',
    server_key=function()return 'game.example:7777'end,
    profile=function()return p end,
    config=function()return DSP.settings.reconnect end,
    observe_dialog=function(id,style,title,content)
        DSP.reconnect.options={{index=0,label='Home'},{index=1,label='Station'}}
        return true
    end,
    manual=function(at)manual_calls=manual_calls+1;return true end,
    tick=function(at)return false end,
 },
 ui22={},
}
assert(loadfile('src/73_fast_reconnect_v298.lua'))()
local R=DSP.reconnect
assert(#R.fast_spawns()==0,'no invented destinations')
assert(not R.fast('Any Place'),'unseen option not allowed')
assert(R.observe_dialog(3,2,'Spawn','Home\nStation'))
assert(#R.fast_spawns()==2,'capture actual menu entries')
assert(R.fast('Home'),'observed spawn should be allowed')
assert(p.spawn_label=='Home' and DSP.settings.reconnect.spawn_enabled)
assert(manual_calls==1)
assert(not R.fast('Unknown destination'))
assert(manual_calls==1,'unverified destination must not reconnect')
print('PASS test_v298_fast_rec')
