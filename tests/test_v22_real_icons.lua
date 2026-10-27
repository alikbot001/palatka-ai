local ffi=require('ffi')
local draws,loads=0,0
DSP={dir='/tmp/palatka-no-icon-files',settings={},ui={},screens={list={{},{},{},{},{},{}}},
 utf8=function(s)return s end,lower=string.lower,clean_text=function(s)return s end,
 item_key=function(s)return string.lower((s:gsub('%s*%(%+%d+%)$','')))end,
 items={id_for_name=function(n)return n=='Real case' and 1852 or nil end},theme={col=function()return{}end},
 item_icon_data={[1852]='UE5H',name_extra='UE5H'},item_icon_names={[1852]='Real case',name_extra='Manual exact item'}}
assert(loadfile('src/08_icons.lua'))()
assert(DSP.item_icons.resolve({name='Real case'})==1852)
assert(DSP.item_icons.resolve({name='Manual exact item'})=='name_extra','exact named artwork must work without a catalog ID')
assert(DSP.item_icons.get('name_extra')=='PNG')
assert(DSP.item_icons.resolve({item_id=1852,name='Real case (+5)'})==1852)
assert(not DSP.item_icons.resolve({item_id=1852,name='Different item'}),'mismatched name must not borrow artwork')
assert(DSP.item_icons.get(1852)=='PNG','bundled PNG decoded lazily')
assert(not DSP.item_icons.get(99999),'missing artwork stays unknown')
imgui={new={char=setmetatable({},{__index=function()return function()return ffi.new('char[64]')end end})},
 CreateTextureFromFileInMemory=function(data,n)loads=loads+1;assert(ffi.string(data,n)=='PNG');return{}end,
 Image=function()draws=draws+1 end,ImVec2=function()return{}end,TextColored=function()end,ReleaseTexture=function()end}
assert(loadfile('src/36_mobile.lua'))()
DSP.icon_bytes={other='old stock picture'}
assert(DSP.mobile.thumbnail({name='Real case'},32))
assert(DSP.mobile.thumbnail({name='Real case'},32) and loads==1 and draws==2,'textures must be reused')
assert(not DSP.mobile.thumbnail({name='Unknown item'},32) and loads==1,'generic category must never substitute an item image')
DSP.mobile.release_icons()
assert(DSP.mobile.thumbnail({name='Real case'},32) and loads==2,'reload must rebuild real texture')
print('v22 real item icons: identity, lazy decode, texture reuse, no stock fallback: OK')
-- Read only the requested indexed slice of an autonomous Lua image bank.
local tmp=os.tmpname();local f=assert(io.open(tmp,'wb'));f:write('prefixUE5Htrailer');f:close()
DSP.item_icon_data=nil;DSP.item_icon_index={[1852]={0,4}};DSP.item_icon_blob_offset=6
DSP.item_icons.source_path=tmp
assert(DSP.item_icons.get(1852)=='PNG','embedded source byte offset must be exact')
DSP.item_icon_index[1852][2]=999
assert(not DSP.item_icons.get(1852),'truncated asset must be rejected')
os.remove(tmp)
print('v22 indexed autonomous image bank: bounded reads, no eager image strings: OK')
