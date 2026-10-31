-- Detect a real UI override regression, not merely a file/version change.
_G.DSP={
 version='2.9.2',settings={promo={templates={}},craglog={}},
 ui22={journal=function()end,promo_screen=function()end},
 mobile={},craglog={ring_recent=function()return {}end,ring_count=0},
 market={},arb_agent={},promo={save_template_options=function()return true end},
 utf8=function(s)return s end,money=function(v)return tostring(v)end,
 theme={col=function()return{}end},flog=function()end
}
imgui={}
sampRegisterChatCommand=function(cmd,func)
    assert(cmd=='crdiag');_G.diagnostic=func
end
sampAddChatMessage=function(msg) _G.diag_message=msg end
local V=DSP.ui22
-- These files must load in exactly the same order as in build.py.
dofile('src/66a_trade_log_tab_mh.lua')
local legacy=V.journal
dofile('src/66c_mh_trade_journal.lua')
assert(V.journal~=legacy,'legacy journal overwrote the compact journal')
assert(type(DSP.craglog.trade_rows)=='function')
dofile('src/68b_promo_universal_ui.lua')
assert(type(V.promo_screen)=='function')
dofile('src/69b_arbitrage_agent_ui.lua')
assert(type(DSP.arb_agent.draw)=='function')
dofile('src/69d_runtime_diagnostic.lua')
assert(diagnostic)
local ok,msg=diagnostic()
assert(ok and msg:find('ACTIVE',1,true))
assert(diag_message and diag_message:find('2.9.2',1,true))
-- The verifier must detect overwrites that happen after installation.
V.journal=function()end
assert(DSP.ui_runtime_check()==false,'must detect a stale screen')
print('PASS active UI bindings and override detection')
