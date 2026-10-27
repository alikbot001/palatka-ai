local h=dofile('tests/test_v22_ui.lua').fixture(1120,650)
h:draw('arbitrage');h:act('v22_arb_group_1')
assert(h:find('v22_arb_sell'),'details opened')
DSP.market.state.version=(DSP.market.state.version or 0)+1
h:draw()
assert(h:find('v22_arb_sell'),'background refresh must not replace the offers being studied')
assert(h.V.arb_detail_group,'detail holds its explicit snapshot')
DSP.market.state.sid=999
h:draw()
assert(not h:find('v22_arb_sell')and h:find('v22_arb_stale_close'),'server change must block old market scenario')
print('v22 stable inspected arbitrage snapshot: OK')
