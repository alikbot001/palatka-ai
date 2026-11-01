-- Pure LuaJIT model test: MH macro and old shortcut removal.
package.preload['ffi']=function()return {}end
local sent={}
_G.DSP={
  ui22={button=function(...)sent[#sent+1]='button';return true end,
        list_rows=function(key,rows)if key=='navigation'then assert(#rows==2)end;return rows end},
  mobile={},
  promo={
      expand=function(value)return value end,
      own_shop_number=function()return 57 end,
  },
  to_u8=function(s)return s end,to_cp=function(s)return s end,
  utf8=function(s)return s end,
}
assert(loadfile('src/72_promo_market_style_v298.lua'))()
assert(DSP.promo.expand('/vr Come to <lavka>')=='/vr Come to 57')
assert(DSP.ui22.button('Управление и интервалы','v297_control_home')==false)
local items=DSP.ui22.list_rows('navigation',{{'home','Главная'},{'control','Управление'},{'promo','Пиар'}},44)
assert(#items==2 and items[2][1]=='promo')
assert(DSP.ui22.button('Пиар','other_button')==true)
print('PASS test_v298_promo')
