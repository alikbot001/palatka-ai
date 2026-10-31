-- MCR Classic integration contract: native shell remains reversible.
local original=function()return 'carbon-shell' end
DSP={
    ui={draw=original},
    ui22={popups=function()end},
    mobile={},
    trade_v16={},
    settings={},
    auto={sell_running=false,buy_running=false},
}
assert(dofile('src/69_mcr_classic.lua')==true)
assert(DSP.mcr_classic and type(DSP.mcr_classic.draw)=='function')
assert(DSP.settings.ui_style=='mcr')
assert(DSP.ui.draw~=original)
-- Selecting the original shell must not invoke the alternate renderer.
DSP.settings.ui_style='carbon'
assert(DSP.ui.draw()=='carbon-shell')
-- Existing users who choose Carbon must not be switched back during reload.
assert(dofile('src/69_mcr_classic.lua')==true)
assert(DSP.settings.ui_style=='carbon')
assert(DSP.ui.draw()=='carbon-shell')
print('PASS MCR classic shell model/rollback')
