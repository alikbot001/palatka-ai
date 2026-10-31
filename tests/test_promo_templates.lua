-- Named multi-line promo templates and per-command intervals.
_G.DSP={settings={promo={templates={{name='Старый',text='/vr Hi\n/fam Hi',
    interval=180,auto=false}}}},save_settings=function()return true end}
dofile('src/49_promo.lua')
dofile('src/49a_promo_universal.lua')
local P=DSP.promo
local s=P.settings()
assert(#s.templates==1)
assert(#s.templates[1].rows==2)
assert(s.templates[1].rows[2].text=='/fam Hi')
assert(P.save_template(nil,'Мой шаблон',{
    {text='/vr Реклама на ЦР',interval=60,auto=true},
    {text='/fam Привет семье',interval=120,auto=true},
    {text='/gd Банда онлайн',interval=180,auto=false}},true))
assert(#s.templates==2 and #s.templates[2].rows==3)
local steps=P.steps()
assert(#steps==2 and steps[1].command:sub(1,3)=='/vr')
assert(steps[1].interval==60 and steps[2].interval==120)
assert(P.set_option('continuous',true))
local sent={}
local function sender(line)sent[#sent+1]=line;return true end
assert(P.start(1000))
assert(not P.tick(1000,sender,true))
assert(P.tick(1020,sender,true))
assert(sent[1]:sub(1,3)=='/vr')
assert(not P.tick(1079,sender,true))
assert(P.tick(1080,sender,true))
assert(sent[2]:sub(1,4)=='/fam')
assert(not P.tick(1199,sender,true))
assert(P.tick(1200,sender,true))
assert(sent[3]:sub(1,3)=='/vr')
assert(P.save_template(2,'Мой шаблон',{
    {text='/vr Новая реклама',interval=100,auto=true},
    {text='/fam Новый чат',interval=180,auto=false}},false))
assert(s.templates[2].auto==false)
assert(#P.steps()==0)
assert(not P.start(1300))
assert(P.save_template(2,'Мой шаблон',{
    {text='/vr Новая реклама',interval=100,auto=true},
    {text='/fam Новый чат',interval=180,auto=true}},true))
assert(#P.steps()==2)
assert(not P.save_template(nil,'Пустой',{},true))
assert(not P.save_template(nil,'Недопустимый',{{text='обычный текст',interval=60}},true))
print('PASS named promo templates and per-line timing')
