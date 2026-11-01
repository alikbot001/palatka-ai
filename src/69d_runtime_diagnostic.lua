-- In-game verification for actively loaded UI modules, not just the version manifest.
local V,C,A,P=DSP.ui22,DSP.craglog,DSP.arb_agent,DSP.promo
DSP.active_ui_build='2.9.3'
DSP.active_ui_refs={
    agent=A and A.draw, journal=C and C.draw,
    journal_tab=V and V.journal, promo=V and V.promo_screen
}
local function report()
    local ref=DSP.active_ui_refs or{}
    local same=V and C and A and P and
        A.draw==ref.agent and C.draw==ref.journal and
        V.journal==ref.journal_tab and V.promo_screen==ref.promo and
        type(P.save_template_options)=='function' and type(C.trade_rows)=='function'
    local line='Palatka runtime '..tostring(DSP.version or '?')..
        ' / UI '..tostring(DSP.active_ui_build or 'none')..
        ' / screens '..(same and'ACTIVE' or'MISMATCH')
    if DSP.flog then DSP.flog('CRDIAG '..line)end
    if sampAddChatMessage then
        sampAddChatMessage('[Palatka] '..line,0x99FFAA)
    end
    return same,line
end
DSP.ui_runtime_check=report
if sampRegisterChatCommand and not DSP._crdiag_registered then
    sampRegisterChatCommand('crdiag',report)
    DSP._crdiag_registered=true
end
if DSP.flog then
    local ok,msg=report()
    DSP.flog('UI modules installed: '..tostring(ok)..' / '..tostring(msg))
end
return true
