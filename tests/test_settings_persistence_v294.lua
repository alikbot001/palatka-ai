-- A stale ui_state.json may never override the user's theme in settings.
local saves,ui_saves=0,0
local saved='{"theme":"emerald","opacity":0.8}'
local real_open=io.open
io.open=function(path,mode)
    if path=='/settings.json' then
        return {read=function()return saved end,close=function()return true end}
    end
    return real_open(path,mode)
end
_G.DSP={
    settings_path='/settings.json',
    settings={theme='ocean_blue',opacity=0.97},
    theme={list={emerald={name='Green'},ocean_blue={},purple={}},current='ocean_blue',opacity=0.97},
    clamp=function(v,lo,hi)return math.max(lo,math.min(v,hi))end,
    save_settings=function()saves=saves+1;return true end,
    save_ui_state=function()ui_saves=ui_saves+1;return true end,
    mobile={flush_save=function()return true end},
}
decodeJson=function(raw)
    if raw==saved then return {theme='emerald',opacity=0.8}end
    return {}
end
dofile('src/00b_settings_persistence_v294.lua')
assert(DSP.theme.current=='emerald' and DSP.settings.theme=='emerald')
assert(DSP.theme.opacity==0.8)
assert(DSP.theme.set('purple'))
assert(DSP.settings.theme=='purple' and saves==1 and ui_saves==1)
assert(DSP.theme.set_opacity(0.9))
assert(DSP.settings.opacity==0.9 and saves==2 and ui_saves==2)
local core=assert(real_open('src/00_core.lua','rb')):read('*a')
assert(core:find('DSP.load_ui_state(loaded_settings)',1,true))
assert(core:find('if not prefer_settings then',1,true))
io.open=real_open
print('PASS v2.9.4 settings priority and theme persistence')
