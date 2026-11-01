-- Persist entire promotion template and timing in one verified operation.
local writes=0
local fail=false
DSP={settings={promo={templates={}}},promo={MIN_INTERVAL=30,MAX_TEMPLATES=32,
 settings=function()return DSP.settings.promo end,
 lines=function(str)return {str}end,
 validate=function(s)return s:match('^/%a+%s+%S')~=nil,'not a command'end},
 save_settings=function()writes=writes+1;return not fail,'simulated failure'end}
assert(loadfile('src/74_promo_save_v2910.lua'))()
local P=DSP.promo
local opts={interval_min=180,interval_max=330,waiting=2.5,auto_limit=7,random_line=true}
local rows={{text='/s Resources 30k',interval=200,auto=true}}
local ok,i=P.save_template_complete(nil,'Resources',rows,true,opts)
assert(ok and i==1 and writes==1)
assert(P.settings().templates[1].interval_min==180)
assert(P.settings().templates[1].interval_max==330)
assert(P.settings().templates[1].waiting==2.5)
assert(P.settings().templates[1].auto_limit==7)
assert(P.settings().templates[1].random_line==true)
local old=P.settings().templates[1]
fail=true
local saved,err=P.save_template_complete(1,'Other',rows,true,opts)
assert(not saved and err)
assert(P.settings().templates[1]==old,'rollback changed working template')
print('PASS: promo template and options are atomic with rollback')
