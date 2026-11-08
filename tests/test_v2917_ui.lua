-- Pure UI/updater regression: no Android, real network or market mutation.
local function noop() end
local saved,rendered,screen = 0,{},'home'
local V={list_rows=function(key,rows) rendered[key]=rows end,
    tools=function(key) rendered.legacy=key end,
    button=function() return false end,
    text_button=function() return false end,
    list=function(key,draw,opts) draw(400);if opts and opts.footer then opts.footer() end end,
    heading=function(label,action) if action then action() end end,
    muted=noop,text=noop,green=noop,red=noop,fit=function(s)return s end,
    inline=noop,reset_list=noop,
    popup=noop,open_popup=noop,
    set_screen=function(s)screen=s end}
imgui={Separator=noop,CloseCurrentPopup=noop}
local payload = "PALATKA_UPDATE_VERSION = '2.9.18'\n-- Test payload padded to pass the minimum download-size validation.\nreturn function(d) d.version='2.9.18';return true end\n"
local manifest = {
    version='2.9.18',size=#payload,mode='overlay',
    url='https://raw.githubusercontent.com/alikbot001/palatka-ai/main/updates/palatka_update.lua',
    changelog={'Test only'}
}
local urls={}
DSP={ui21=V,settings={ui_advanced_menu=false},mobile={defer_save=function()saved=saved+1 end,
    compact_number=function()return false end},
    version='2.9.16',dir='.',
    market={state={status='idle',sid=102}},auto={},theme={},
    save_settings=function()saved=saved+1;return true end,
    http_get=function(url,cb)
        urls[#urls+1]=url
        if url:find('/version.json',1,true) then cb('mock manifest',nil,200)
        else cb(payload,nil,200) end
    end,
    notify=noop}
decodeJson=function()return manifest end
local ok,err=pcall(dofile,'src/69e_compact_ui_v2917.lua')
assert(ok,err)
assert(DSP.version=='2.9.17')
assert(V._compact_ui_2917_installed)
local nav={
 {'palatka','Торговля'},{'lavki','Лавки'},{'arbitrage','Арбитраж'},
 {'promo','Автопиар'},{'storage','Хранилища'},{'logs','Журнал'},
 {'settings','Настройки'},{'resale','Перепродажа'},
 {'market','Рынок'},{'notes','Заметки'},{'scan','Скан'}
}
V.list_rows('navigation',nav,44,noop,{})
assert(#rendered.navigation==7,'compact mode must expose seven primary sections')
DSP.settings.ui_advanced_menu=true
V.list_rows('navigation',nav,44,noop,{})
assert(#rendered.navigation==#nav,'advanced mode must preserve every original section')
DSP.settings.ui_advanced_menu=false
local updater=DSP.ui_updater
assert(updater and updater.newer('2.9.18','2.9.17'))
assert(not updater.newer('2.9.17','2.9.18'))
assert(not updater.newer('bad','2.9.17'))
assert(updater.check())
assert(updater.status=='available' and updater.info.version=='2.9.18')
DSP.auto.sell_running=true
assert(not updater.install(), 'running sale must block an update')
assert(updater.status=='error')
DSP.auto.sell_running=false
assert(updater.check() and updater.status=='available')
assert(updater.install())
assert(updater.status=='installed' and DSP.version=='2.9.18')
assert(io.open('./palatka_ota_2.9.18.lua','rb')~=nil)
os.remove('./palatka_ota_2.9.18.lua')
manifest.url='https://attacker.invalid/payload.lua'
assert(updater.check())
assert(updater.status=='error','untrusted manifest URL must be rejected')
assert(#urls==4,'network is only used for explicit check/install/check')
V.settings_group='view'
V.tools('settings')
V.settings_group='legacy'
V.tools('settings')
assert(rendered.legacy=='settings','old advanced settings remain reachable')
V.tools('notes')
assert(rendered.legacy=='notes','other screens must preserve legacy handlers')
print('PASS 2.9.17 compact navigation, safe update state and legacy settings')
