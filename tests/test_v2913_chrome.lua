-- Pure window-chrome tests: header hit region, viewport recovery, reopen center.
local sw,sh=1100,750
local cursor=56
local visible={}
local logged={}
imgui={
    GetIO=function()return{DisplaySize={x=sw,y=sh}}end,
    GetCursorPosX=function()return cursor end,
    IsPopupOpen=function(key)return visible[key]==true end,
}
local function clamp(n,lo,hi)return math.max(lo,math.min(hi,n))end
local V={popup_positions={},popup_sizes={}}
V.geometry=function(w,h)return{w=680,h=450,x=100,y=-300}end
V.text_button=function(label,id,width)logged[#logged+1]={id=id,width=width};return true end
V.open_popup=function(title,id)return id end
V.popup=function(title,id)return V.popup_positions[id] end
local U={open=false}
U.set_open=function(on)U.open=not not on;return U.open end
local saved={}
DSP={ui=U,ui21=V,mobile={defer_save=function()saved[#saved+1]=true end},
    settings={mobile_window={},ui_windows={detail={x=1,y=2,w=600,h=300}}},
    utf8=function(s)return s end,clamp=clamp}
assert(loadfile('src/60g_window_chrome_v2913.lua'))()
local g=V.geometry(sw,sh)
assert(g.y==18 and g.x==100,'negative window position must recover onscreen')
V.text_button('PALATKA AI','carbon_title',155,false,36)
assert(logged[#logged].width==680-141-cursor-8,'header must fill free area to menu')
assert(V.text_button('Other','different',42)==true,'other controls retain clicks')
assert(logged[#logged].width==42,'other button sizing must stay intact')
assert(U.set_open(true))
local p=DSP.settings.mobile_window
assert(p.x==210 and p.y==150 and p.w==680 and p.h==450,'main window opens centered')
assert(#saved==1,'centered main geometry is queued for save')
DSP.settings.mobile_window.x=40
assert(U.set_open(true) and DSP.settings.mobile_window.x==40,'open window must retain manual drag')
U.set_open(false);U.set_open(true)
assert(DSP.settings.mobile_window.x==210,'main window must recenter on reopen')
local key='Details##v22_detail'
visible[key]=true
local first=V.popup('Details','detail',function()end,{w=600,h=300})
assert(first.x==250 and first.y==225,'saved edge position must be ignored on opening')
V.popup_positions.detail={x=40,y=70}
local held=V.popup('Details','detail',function()end,{w=600,h=300})
assert(held.x==40 and held.y==70,'dragged popup must remain where placed while open')
visible[key]=false;V.popup('Details','detail',function()end,{w=600,h=300})
visible[key]=true
local reopened=V.popup('Details','detail',function()end,{w=600,h=300})
assert(reopened.x==250 and reopened.y==225,'popup must recenter after closing')
V.popup_positions.detail={x=3,y=4}
V.open_popup('Details','detail')
assert(V.popup('Details','detail',function()end,{w=600,h=300}).x==250,
    'explicit open request must recenter')
visible[key]=false
sw,sh=390,280
V.popup('Details','detail',function()end,{w=600,h=300})
visible[key]=true
local small=V.popup('Details','detail',function()end,{w=600,h=300})
assert(small.x>=0 and small.y>=0 and small.x<50 and small.y<50,'small screen modal fits viewport')
print('PASS v2.9.13 centered windows and wide header drag')
