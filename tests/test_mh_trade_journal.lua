_G.DSP={settings={craglog={}},money=function(n)return '$'..tostring(n)end,
    utf8=function(x)return x end,ui22={},theme={col=function()return{}end}}
local C={ring={},ring_count=0,ring_cap=300}
DSP.craglog=C
function C.ring_recent()return C.ring end
function C.event_visible()return true end
dofile('src/66c_mh_trade_journal.lua')
local now=os.time()
C.ring={{type='market',direction='sell',item_name='Камень',amount=900,ts=now},
        {type='market',direction='buy',item_name='Ларец',amount=300,ts=now},
        {type='payday',amount=2000,ts=now},
        {type='trade',money_get=500,money_give=0,items_give={{name='Удочка',qty=2}},ts=now},
        {type='trade',money_get=0,money_give=400,items_get={{name='Слиток',qty=1}},ts=now},
        {type='crate',kind='item',item_name='Монета',ts=now}}
local rows=C.trade_rows('today')
assert(#rows==4, #rows)
assert(rows[1].name=='Камень' and rows[1].kind=='sell')
assert(rows[2].kind=='buy')
assert(rows[3].name=='Удочка x2')
local t=C.trade_totals(rows)
assert(t.sells==1400 and t.buys==700)
assert(t.sell_count==2 and t.buy_count==2)
assert(#C.trade_rows('all')==4)
assert(C.trade_totals({}).sells==0)
print('PASS compact trading log source and totals')
