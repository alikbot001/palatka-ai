-- MCR-style UI adapter must preserve the established trade and settings entry points.
local previous_screen, previous_tools, previous_draw = nil,nil,nil
local changed={}
local V={
    screen='palatka',errors={},
    set_screen=function(id)previous_screen=id;return true end,
    tools=function(screen)previous_tools=screen;return screen end,
    geometry=function(sw,sh)return{w=sw*.9,h=sh*.9,x=0,y=0}end,
}
local U={draw=function()previous_draw=true end}
DSP={
    ui21=V,ui=U,mobile={defer_save=function()changed[#changed+1]=true end},
    settings={},utf8=function(x)return x end,
    clamp=function(v,a,b)return math.max(a,math.min(b,v))end,
}
imgui={}
dofile('src/69e_mcr_mobile_shell.lua')
assert(V._mcr_workspace and type(U.draw)=='function')
assert(V.set_screen('more') and V.screen=='more','More is a real client-side screen')
assert(V.set_screen('updates') and V.screen=='updates','Update information has a screen')
assert(V.set_screen('advanced') and V.screen=='advanced','Advanced options have a screen')
assert(V.set_screen('palatka') and previous_screen=='palatka',
    'Trading must continue through the stable navigation')
assert(V.tools('stats')=='stats' and previous_tools=='stats',
    'Existing statistics/settings renderer must be preserved')
local g=V.geometry(1280,720)
assert(g.w>=700 and g.w<=790 and g.h>350,'MCR starts as a compact centered window')
assert(math.abs(g.x-(1280-g.w)/2)<1,'Default window is centered')
DSP.settings.mobile_window={w=650,h=430,x=40,y=40}
g=V.geometry(1280,720)
assert(g.w==1152 and g.x==0,'Existing user window geometry is delegated unchanged')
local f=assert(io.open('build.py','rb'))
local build=f:read('*a');f:close()
assert(build:find('"69e_mcr_mobile_shell.lua"',1,true),'new UI must ship in standalone build')
print('PASS MCR navigation, advanced/settings routing and packaged source')
