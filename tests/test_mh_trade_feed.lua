-- Market Helper style trade feed reads confirmed market events only.
_G.DSP={settings={craglog={}},money=function(n)return tostring(n)end,
  utf8=function(s)return s end,save_settings=function()return true end}
DSP.craglog={
  ring_count=4,
  ring_recent=function()
    return {
      {type='market',direction='buy',item_name='Box',amount=500,ts=1700000000},
      {type='crate',item_name='Box',amount=500,ts=1700000001},
      {type='market',direction='sell',item_name='Box',amount=650,ts=1700000002},
      {type='market',direction='buy',item_name='Chest',amount=1100,ts=1700000003}
    }
  end
}
assert(dofile('src/57a_trade_feed_mh.lua'))
local C=DSP.craglog
local entries=C.trade_feed(8)
assert(#entries==3)
assert(entries[1].item_name=='Chest' and entries[1].direction=='buy')
assert(entries[2].direction=='sell')
assert(entries[3].item_name=='Box')
assert(#C.trade_feed(1)==1)
assert(C.trade_feed_line(entries[2]):find('Продажа',1,true))
assert(C.trade_feed_line(entries[1]):find('Скупка',1,true))
assert(C.trade_feed_line(entries[1]):find('-1100',1,true))
print('PASS MH trade feed')
