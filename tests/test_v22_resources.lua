local ffi=require('ffi')
local cleaned=0
DSP={ui={},screens={list={{},{},{},{},{},{}},set=function()end},settings={},dir='/tmp/no-palatka-icons',
 utf8=function(s)return s end,lower=string.lower,clean_text=function(s)cleaned=cleaned+1;return s end,
 items={id_for_name=function()return 1 end},theme={col=function()return{}end}}
imgui={new={char=setmetatable({},{__index=function()return function()return ffi.new('char[64]')end end})}}
assert(loadfile('src/36_mobile.lua'))()
local M=DSP.mobile
local item={name='simple'}
M.item_icon_kind(item);M.item_icon_kind(item)
assert(cleaned==1,'every category must be cached')
local buf=ffi.new('char[64]','abc');local p={price=500}
assert(not M.apply_number(p,'price',buf,1))
assert(M.invalid_edits[p].price,'invalid displayed edits must block listing')
ffi.copy(buf,'200\0');assert(M.apply_number(p,'price',buf,1));assert(not M.invalid_edits[p].price)
local released=0;imgui.ReleaseTexture=function()released=released+1 end
M.icon_textures={a={},b={}};M.release_icons();assert(released==2 and next(M.icon_textures)==nil)
DSP.item_icons={resolve=function()return 1 end,get=function()return 'embedded-png'end}
local decoded=0;imgui.CreateTextureFromFileInMemory=function(_,n)decoded=n;return {}end
imgui.ImVec2=function(x,y)return{x=x,y=y}end;imgui.Image=function()end;imgui.TextColored=function()end
assert(M.thumbnail({name='simple'},32)and decoded==12,'built-in images must work without filesystem access')
print('v22 icon cache / texture cleanup / invalid edit tracking: OK')
-- Finalizers close over renderer userdata; they must not run after renderer teardown.
MONET_VERSION=3008000
local native_gc=0;local manual_before=released
local texture=ffi.gc(ffi.new('int[1]',1),function()native_gc=native_gc+1 end)
M.icon_textures={android=M.own_texture(texture)};texture=nil
M.release_icons();collectgarbage();collectgarbage()
assert(released==manual_before+1 and native_gc==0,'release once while renderer is alive; no late renderer finalizer')
MONET_VERSION=nil
print('v22 MonetLoader texture ownership: OK')
-- Android tags occupy the high byte: Lua-number round trips corrupt the address.
MONET_VERSION=3008000
local tagged=0xb400000000000000ULL+0x13579b40ULL
assert(tagged~=ffi.cast('uint64_t',tonumber(tagged)))
local original_load=ffi.load
local exact_releases=0
ffi.load=function(name)
 assert(name=='GTASA')
 return {_Z15RwRasterDestroyP8RwRaster=function(pointer)
  assert(ffi.cast('uint64_t',pointer)==tagged,'native raster pointer must retain every bit')
  exact_releases=exact_releases+1;return 1
 end}
end
local rounded_release=imgui.ReleaseTexture
imgui.ReleaseTexture=function()error('tagged pointer must bypass lossy mimgui wrapper')end
M.icon_textures={tagged=ffi.cast('void*',tagged)}
M.release_icons()
assert(exact_releases==1,'tagged raster must be freed exactly once through native export')
ffi.load=original_load;imgui.ReleaseTexture=rounded_release;MONET_VERSION=nil
print('v22 tagged ARM64 raster release: OK')
