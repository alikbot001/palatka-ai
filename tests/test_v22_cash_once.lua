dofile('tests/test_v22_events.lua')
local C=DSP.craglog
assert(C.log_payday({},'PayDay cash-once fixture'))
local before=C.summary('day').net
DSP.logs.log_chat('Вам начислено $12.000 зарплата')
local after=C.summary('day').net
assert(after-before==12000,'same salary must not be counted both as PayDay and cash reward')
print('v22 cash receipt appears once across PayDay/reward channels: OK')
