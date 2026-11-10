local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local path='mcr_copy/src/resale.lua'
local file=io.open(path,'rb')
assert(file,'missing resale ranking module');file:close()
local R=assert(loadfile(path))()(E)
local now=1000000
local function offer(price,qty,id,variant,currency)
    return {id=id or '5',variant=variant or '0',name='Popular item',
        price=price,qty=qty,currency=currency or 'SA$'}
end
local function add(s,id,sell,buy,owner,at,server)
    assert(E.observe(s,{shop=id,owner=owner or ('P'..id),at=at or now,
        server=server or '102',sell=sell or {},buy=buy or {}}))
end
local function market(cost,stock)
    local s=E.new()
    add(s,1,{offer(cost or 10000,stock or 30)})
    add(s,2,{offer(15000,40)});add(s,3,{offer(16000,30)})
    add(s,4,{offer(17000,20)})
    add(s,5,{}, {offer(13000,10)});add(s,6,{}, {offer(14000,10)})
    return s
end
local function rank(s,opts,at,server,yield_fn)
    opts=opts or {};if opts.currency==nil then opts.currency='SA$' end
    local rows,err=R.rank(s,server or '102',at or now,opts,yield_fn)
    assert(not err,err);return rows
end
-- Removing commission, the peer median, or the small-lot cap breaks this fixture.
local rows=rank(market())
assert(#rows==1,'10k vs 15-17k should qualify')
local r=rows[1]
assert(r.qty==10 and r.seller_qty==30 and r.buy_price==10000)
assert(r.reference_price==16000 and r.sell_price==15840 and r.peer_count==3)
assert(r.cost==100000 and r.gross==158400 and r.fee==3168)
assert(r.net==155232 and r.profit==55232 and r.roi_bp==5523)
assert(r.id=='5' and r.variant=='0' and r.currency=='SA$' and r.seller.shop==1)
assert(r.buyer==nil and r.buyer_qty==nil,'estimated resale fabricated a counterparty')
assert(r.popularity.kind=='buy_orders' and r.popularity.buyer_shops==2
    and r.popularity.buyer_qty==20)
assert(#rank(market(13000))==1,'13k lot was missed')

-- Repeated asks from one owner must not manufacture independent peers.
local s=market();add(s,7,{offer(1000000,100)},{},'P2')
rows=rank(s);assert(rows[1].reference_price==16000 and rows[1].peer_count==3)
add(s,8,{offer(16000,1)},{},'P1')
assert(rank(s)[1].peer_count==3,'candidate owner contributed to reference')
local sparse=E.new();add(sparse,1,{offer(100,3)})
add(sparse,2,{offer(200,1)},{},'same');add(sparse,3,{offer(210,1)},{},'SAME')
add(sparse,4,{offer(220,1)})
assert(#rank(sparse,{popular_only=false})==0,'same owner counted twice')

-- A distant outlier must not set the target when ordinary peers exist.
s=market();add(s,7,{offer(100000000,1)})
assert(rank(s)[1].reference_price==16500,'median ignored middle peers')

-- Demand is a declared order, with independent merchants and a price floor.
s=market();add(s,6,{}, {offer(9999,100)})
assert(#rank(s)==0,'below-cost buy order passed demand gate')
rows=rank(s,{popular_only=false})
assert(#rows==1 and rows[1].popularity.kind=='unknown')
assert(rows[1].popularity.buyer_shops==1 and rows[1].popularity.buyer_qty==10)
s=market();add(s,6,{}, {offer(14000,100)},'P5')
assert(#rank(s)==0,'same buyer owner counted twice')
s=market();add(s,6,{}, {offer(13000,10)},'P5')
add(s,7,{}, {offer(13000,1)})
assert(#rank(s)==0,'repeated merchant order multiplied declared quantity')
s=market();add(s,6,{}, {offer(14000,9)})
assert(#rank(s)==0,'fewer than 20 declared units qualified')
s=market();add(s,6,{}, {offer(14000,nil)})
assert(#rank(s)==0,'unknown demand quantity guessed')
s=market();add(s,6,{}, {offer(14000,100)},'P1')
assert(#rank(s)==0,'candidate owner manufactured demand')

local key='5\0310\031SA$'
local own={[key]={events=3,qty=20,last_at=now-604800}}
rows=rank(s,{own_sales=own})
assert(#rows==1 and rows[1].popularity.kind=='own_sales')
assert(rows[1].popularity.own_events==3 and rows[1].popularity.own_qty==20)
own[key].last_at=now-604801;assert(#rank(s,{own_sales=own})==0,'old sale evidence reused')
own[key].last_at=now+1;assert(#rank(s,{own_sales=own})==0,'future sales accepted')
own[key]={events=2,qty=200,last_at=now};assert(#rank(s,{own_sales=own})==0)
own[key]={events=30,qty=19,last_at=now};assert(#rank(s,{own_sales=own})==0)

-- Current server, exact item variant and currency are mandatory reference boundaries.
for _,bad in ipairs({'stale','future','server','variant','currency','id'})do
    s=market()
    local o=offer(17000,20)
    local at=bad=='stale' and now-3601 or bad=='future' and now+1 or now
    if bad=='variant' then o.variant='1' elseif bad=='currency' then o.currency='BTC'
    elseif bad=='id' then o.id='6' end
    s.shops['102/4']=nil
    add(s,4,{o},{},nil,at,bad=='server' and '103' or '102')
    -- Overwrite the old server's copy for the cross-server fixture.
    if bad=='server' then s.shops['102/4']=nil end
    assert(#rank(s)==0,'reference leaked across '..bad)
end
assert(#rank(market(),{},now+3600)==1,'TTL boundary excluded')
assert(#rank(market(),{},now+3601)==0,'expired candidates accepted')
s=market();add(s,1,{offer(10000,nil)})
assert(#rank(s)==0,'unknown seller stock guessed')

-- Shared budget and one max-quantity cap apply across quotes of the same item.
s=market();add(s,1,{offer(10000,3),offer(11000,20)})
rows=rank(s,{budget=85000,max_qty=7})
local total,qty=0,0
for _,v in ipairs(rows)do total=total+v.cost;qty=qty+v.qty end
assert(total==74000 and qty==7 and #rows==2,'stock, budget or item cap reused')
s=market();add(s,1,{offer(10000,3),offer(10000,3)})
assert(rank(s)[1].qty==3,'duplicate quote multiplied stock')
s=market();add(s,7,{offer(1000,30,'6'),offer(1500,30,'6')})
add(s,8,{offer(1600,30,'6')});add(s,9,{offer(1700,30,'6')})
add(s,10,{}, {offer(1100,20,'6')});add(s,11,{}, {offer(1100,20,'6')})
add(s,12,{offer(1800,30,'6')})
rows=rank(s,{budget=25000})
total=0;for _,v in ipairs(rows)do total=total+v.cost end
assert(total==20000 and #rows==2 and rows[1].id=='6','shared budget or popularity ranking failed')

-- Per-lot commission flooring decides the exact 10% ROI boundary.
s=E.new();add(s,1,{offer(100,3)})
for i=2,4 do add(s,i,{offer(113,1)})end
rows=rank(s,{popular_only=false,tax_bp=200,undercut_bp=0,min_roi_bp=1000})
assert(#rows==1 and rows[1].net==332 and rows[1].roi_bp==1066)
assert(#rank(s,{popular_only=false,tax_bp=200,undercut_bp=0,min_roi_bp=1067})==0)
assert(rank(s,{popular_only=false,tax_bp=200,undercut_bp=0,min_roi_bp=1066})[1].qty==3)
rows=rank(s,{popular_only=false,tax_bp=0,undercut_bp=0,max_qty=1,min_roi_bp=1300})
assert(#rows==1 and rows[1].roi_bp==1300)
assert(#rank(s,{popular_only=false,tax_bp=0,undercut_bp=0,max_qty=1,min_roi_bp=1301})==0)

-- Near MAX integers must not wrap cost, gross, medians or ROI products.
s=E.new();add(s,1,{offer(1000000000000000,10)})
for i=2,4 do add(s,i,{offer(1200000000000000,1)})end
rows=rank(s,{popular_only=false,undercut_bp=0,tax_bp=0,min_roi_bp=2000})
assert(#rows==1 and rows[1].qty==7 and rows[1].roi_bp==2000)
assert(rows[1].cost==7000000000000000 and rows[1].gross==8400000000000000)
assert(#rank(s,{popular_only=false,undercut_bp=0,tax_bp=0,min_roi_bp=2001})==0)
s=E.new();add(s,1,{offer(1,1)})
for i=2,4 do add(s,i,{offer(E.MAX,1)})end
rows=rank(s,{popular_only=false,tax_bp=0,undercut_bp=0})
assert(#rows==1 and rows[1].reference_price==E.MAX and rows[1].roi_bp==E.MAX)

-- Cached rows expire with supporting peer/demand evidence, not only the candidate.
s=market();s.shops['102/3'].at=now-2000
assert(rank(s)[1].valid_until==now+1600,'peer expiration not carried with row')
s=market();s.shops['102/6'].at=now-3000
assert(rank(s)[1].valid_until==now+600,'demand expiration not carried with row')
s=market();s.shops['102/6']=nil
own[key]={events=3,qty=20,last_at=now-604700}
assert(rank(s,{own_sales=own})[1].valid_until==now+100,'own sales window expiration lost')
own[key]={events=3,qty=20,last_at=now-100,valid_until=now+50}
assert(rank(s,{own_sales=own})[1].valid_until==now+50,'oldest supporting sale expiration lost')
own[key].valid_until=now-1
assert(#rank(s,{own_sales=own})==0,'expired aggregate evidence accepted')
own[key]={events=3,qty=20,last_at=now-604700,valid_until=now+10000}
assert(rank(s,{own_sales=own})[1].valid_until==now+100,'aggregate expiry extended beyond last sale')

-- Verified public aggregate sale quantities are distinct from current buy orders.
local sales={[key]={qty_30d=300,updated_at=now-100,valid_until=now+40}}
rows=rank(s,{market_sales=sales})
assert(#rows==1 and rows[1].popularity.kind=='market_sales','actual sale aggregate ignored')
assert(rows[1].popularity.market_qty_30d==300
    and rows[1].popularity.market_updated_at==now-100
    and rows[1].popularity.market_source=='va-ta.com/market')
assert(rows[1].valid_until==now+40 and rows[1].reference_price==16000,
    'market sale totals replaced asking-price reference or lost expiry')
assert(#rank(s,{market_sales={['5\0311\031SA$']=sales[key]}})==0,'other variant sale totals leaked')
assert(#rank(s,{market_sales={['5\0310\031BTC']=sales[key]}})==0,'other currency sale totals leaked')
for _,bad in ipairs({
    {qty_30d=299,updated_at=now,valid_until=now+20},
    {qty_30d=300.5,updated_at=now,valid_until=now+20},
    {qty_30d=0/0,updated_at=now,valid_until=now+20},
    {qty_30d=1e16,updated_at=now,valid_until=now+20},
    {qty_30d=300,updated_at=now+1,valid_until=now+20},
    {qty_30d=300,updated_at=now,valid_until=now-1},
    {qty_30d=300,updated_at=now},
})do assert(#rank(s,{market_sales={[key]=bad}})==0,'invalid public sale evidence passed gate')end
sales[key].valid_until=now
assert(#rank(s,{market_sales=sales})==1,'sale evidence expiry boundary excluded')
assert(#rank(s,{market_sales=sales},now+1)==0,'expired public sale aggregate accepted')
assert(rank(market(),{market_sales={[key]={qty_30d=1e16}}})[1].popularity.kind=='buy_orders',
    'bad optional sale source blocked valid current orders')
rows=rank(s,{market_sales={[key]={qty_30d='300',updated_at=tostring(now),valid_until=now+10}}})
assert(rows[1].popularity.market_qty_30d==300 and rows[1].popularity.market_updated_at==now,
    'numeric source fields were not normalized')

-- A valid public market benchmark caps an inflated current asking-price median.
sales[key]={qty_30d=300,updated_at=now,valid_until=now+40,reference_price=10956}
assert(#rank(market(13000),{market_sales=sales})==0,'inflated asks defeated public market benchmark')
rows=rank(market(9000),{market_sales=sales})
assert(#rows==1 and rows[1].peer_price==16000 and rows[1].history_price==10956
    and rows[1].reference_price==10956 and rows[1].sell_price==10846)
assert(rows[1].cost==90000 and rows[1].gross==108460 and rows[1].net==106290
    and rows[1].roi_bp==1810,'benchmark cap did not flow through net ROI')
sales[key].qty_30d=1
assert(#rank(market(13000),{market_sales=sales})==0,'thin history failed to cap buy-order backed row')
sales[key].reference_price=20000
rows=rank(market(13000),{market_sales=sales})
assert(rows[1].reference_price==16000 and rows[1].history_price==20000,'market benchmark increased target')
for _,bad in ipairs({-1,0,0/0,1e16})do
    sales[key].reference_price=bad
    rows=rank(market(13000),{market_sales=sales})
    assert(#rows==1 and rows[1].reference_price==16000 and rows[1].history_price==nil,
        'invalid benchmark blocked legacy order evidence')
end
sales[key].reference_price=nil
assert(rank(market(13000),{market_sales=sales})[1].reference_price==16000,'missing benchmark failed fallback')

-- A later cancellation must discard work already collected.
s=market();local many={}
for i=1,100 do many[i]=offer(10000+i,1)end
add(s,1,many)
local ticks=0
local cancelled,cancel_error=R.rank(s,'102',now,{currency='SA$'},function()
    ticks=ticks+1;return ticks<2
end)
assert(ticks==2 and #cancelled==0 and cancel_error=='cancelled','long computation did not cancel')

local invalid={
    {},{currency=''},{currency='SA$',min_roi_bp=-1},{currency='SA$',max_qty=0},
    {currency='SA$',tax_bp=10001},{currency='SA$',budget=0/0},
    {currency='SA$',undercut_bp=10001},{currency='SA$',min_peers=2},
}
for _,opts in ipairs(invalid)do
    local result,err=R.rank(market(),'102',now,opts)
    assert(#result==0 and err,'invalid options were accepted')
end
local called=0
local result,err=R.rank(market(),'102',now,{currency='SA$'},function()
    called=called+1;return false
end)
assert(called>0 and #result==0 and err=='cancelled','cancellation published rows')
local ok,why=pcall(R.rank,market(),'102',now,{currency='SA$'},function()error('stop-test')end)
assert(not ok and tostring(why):find('stop%-test'),'yield exception was swallowed')
print('MCR resale ranking: OK')
