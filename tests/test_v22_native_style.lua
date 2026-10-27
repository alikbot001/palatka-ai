-- Normalize font pixels independently of Monet atlas size and child ancestors.
local H=dofile('tests/support/imgui22.lua')
package.preload.encoding=function()return{UTF8={decode=function(_,s)return s end,encode=function(_,s)return s end}}end
getWorkingDirectory=function()return '/tmp/palatka_style'end
doesDirectoryExist=function()return true end
createDirectory=function()end
encodeJson=function()return '{}'end
decodeJson=function()return {}end
local h=H.new(2340,1080);imgui=h.imgui
dofile('src/00_core.lua')
local n=DSP.theme.push_window()
assert(imgui.GetStyle().Colors[imgui.Col.ChildBg].x==.075,'design colors must not be gamma-corrected twice')
imgui.PopStyleColor(n)
DSP.ui={d=1,open_ref=imgui.new.bool(true)};DSP.mobile={};DSP.screens={set=function()end}
dofile('src/60_ui21_shell.lua')
local V=DSP.ui22
assert(math.abs(V.font_scale_for(32,1450,1)*32-19.44)<.001)
local base,parent,local_scale=32,1,1
imgui.SetWindowFontScale=function(v)local_scale=v end
imgui.GetFontSize=function()return base*parent*local_scale end
V.font_pixels=19.44
for _,atlas in ipairs({16,28,32,42})do
 base=atlas
 for _,inherited in ipairs({1,.7,.49,1.35,1.8225})do
  parent=inherited;local_scale=.5;V.apply_font()
  assert(math.abs(imgui.GetFontSize()-19.44)<.001,'nested windows must keep same actual text pixels')
  V.apply_font(22);assert(math.abs(imgui.GetFontSize()-22)<.001,'heading reset must not accumulate')
 end
end
print('v22 native palette / inherited atlas normalization: OK')
