-- Verify Market Helper-inspired controls without a game client.
_G.DSP={settings={promo={templates={}}},save_settings=function()return true end,lower=string.lower}
dofile('src/49_promo.lua')
dofile('src/49a_promo_universal.lua')
dofile('src/49b_promo_mh_options.lua')
local P=DSP.promo
assert(P.save_template(nil,'ЦР и семья',{
    {text='/vr Товар на ЦР',interval=90,auto=true},
    {text='/fam Товар для семьи',interval=180,auto=true},
    {text='/gd Товар для банды',interval=240,auto=true}},true))
local template=P.settings().templates[1]
assert(#template.rows==3)
assert(P.save_template_options(1,{interval_min=70,interval_max=90,auto_limit=2,random_line=false}))
assert(template.interval_min==70 and template.interval_max==90)
assert(template.auto_limit==2)
assert(#P.steps()==3)
local sent={}
local function send(line)sent[#sent+1]=line;return true end
assert(P.set_option('continuous',true))
assert(P.start(1000))
assert(not P.tick(1000,send,true))
assert(P.tick(1020,send,true))
assert(P.next_at>=1090 and P.next_at<=1110)
assert(not P.tick(1060,send,true))
assert(P.tick(1120,send,true))
assert(#sent==2)
assert(template.auto==false)
assert(P.tick(1300,send,true)==false)
assert(#sent==2)
assert(P.save_template_options(1,{interval_min=0,interval_max=0,auto_limit=0,random_line=true}))
template.auto=true;template.auto_count=0
P.stop()
assert(P.start(2000))
assert(#P.steps()==1)
assert(not P.tick(2000,send,true))
assert(P.tick(2020,send,true))
assert(#sent==3)
assert(P.next_at-2020>=60)
assert(P.save_template_options(1,{interval_min=60,interval_max=180,auto_limit=0,random_line=false}))
assert(#P.steps()==3)
print('PASS promo MH template repeat options')
