DSP={settings={},save_settings=function()return true end,
    player_nick=function()return 'RealPlayer' end,
    live={shop={owner='OtherPlayer',num='150'}}}
dofile('src/49_promo.lua')
local P=DSP.promo
assert(P.add('Trade','/vr Купите в лавке {лавка}\n/fam Скупка в лавке {лавка}\n/gd Ресурсы в лавке {лавка}',180))
local sent={}
local function send(s)sent[#sent+1]=s end
assert(not P.send_once(1,1000,send,true),' чужая лавка не должна подставляться')
assert(#sent==0)
assert(P.set_shop_number(374))
assert(P.send_once(1,1000,send,true))
assert(sent[1]=='/vr Купите в лавке :lavka374:')
assert(not P.send_once(1,1010,send,true),'rate limit')
assert(P.send_once(1,1180,send,true));assert(sent[2]=='/fam Скупка в лавке :lavka374:')
assert(P.send_once(1,1360,send,true));assert(sent[3]=='/gd Ресурсы в лавке :lavka374:')
assert(P.send_once(1,1540,send,true));assert(sent[4]==sent[1],'cycles lines')
assert(P.set_shop_number(0))
assert(not P.own_shop_number(),'other stall may never be selected')
DSP.live.shop.owner='RealPlayer'
local shop,source=P.own_shop_number();assert(shop==150 and source=='своя открытая лавка')
assert(not P.validate('/vr да\n/s ок\n/b запрещено'))
print('v225 promo batch, macro, foreign shop guard, opt-in cooldown PASS')
