-- Cooperative scheduler regression; never treats a cached call as a cold benchmark.
package.preload.encoding=function()return{UTF8={decode=function(_,s)return s end,encode=function(_,s)return s end}}end
getWorkingDirectory=function()return '/tmp/palatka_async'end
doesDirectoryExist=function()return true end
createDirectory=function()end
encodeJson=function()return '{}'end
decodeJson=function()return {}end
local real_clock,real_time=os.clock,os.time
local now,cpu=100000,0
os.time=function()return now end
os.clock=function()cpu=cpu+.002;return cpu end
local function fixture(async)
    DSP=nil;lua_thread=nil;wait=nil
    dofile('src/00_core.lua');dofile('src/05_items.lua');dofile('src/10_market.lua')
    dofile('src/11_arbitrage.lua');dofile('src/12_arbitrage_groups.lua')
    local queue,scheduled={},0
    if async then
        lua_thread={create=function(fn)local co=coroutine.create(fn);queue[#queue+1]=co;scheduled=scheduled+1;return co end}
        wait=function(ms)assert(ms==0);return coroutine.yield('frame')end
    end
    local calls=0;local grouped=DSP.market.arbitrage_grouped
    DSP.market.arbitrage_grouped=function()calls=calls+1;return grouped()end
    assert(loadfile('src/13_arbitrage_async.lua'))()
    local function step()
        local co=queue[1];if not co then return false end
        local ok,err=coroutine.resume(co);assert(ok,err)
        if coroutine.status(co)=='dead'then table.remove(queue,1)end
        return true
    end
    local function finish()
        local steps=0;while step()do steps=steps+1;assert(steps<10000,'worker never completes')end
        return steps
    end
    return DSP.market,step,finish,function()return calls,scheduled end
end
local function rebuild(M,n,items,ts)
    local shops={}
    for shop=1,n or 4 do
        local row={server_id=102,shop_num=shop,owner='Player'..shop,updated_at=ts or now,sell_slots={},buy_slots={}}
        for i=1,items or 1 do
            row.sell_slots[i]={name='Item '..i,price=100+shop,qty=3}
            row.buy_slots[i]={name='Item '..i,price=220+shop,qty=7}
        end
        shops[#shops+1]=row
    end
    M.rebuild({shops=shops},102)
end
local M,step,finish,counts=fixture(true)
DSP.settings.arb_filters={max_age=30}
rebuild(M,4,2)
local empty,status=M.arbitrage_grouped_ui()
assert(#empty==0 and status=='loading','cold render schedules preparation and returns immediately')
for _=1,20 do local rows,s=M.arbitrage_grouped_ui();assert(rows==empty and s=='loading')end
local calls,scheduled=counts();assert(calls==0 and scheduled==1,'one job per signature, no work in draw')
step();calls=counts();assert(calls==0,'worker yields before any cold work')
finish()
local groups,ready=M.arbitrage_grouped_ui();assert(#groups==2 and ready=='ready')
for _=1,20 do assert(M.arbitrage_grouped_ui()==groups,'warm UI retains group identity')end
calls,scheduled=counts();assert(calls==1 and scheduled==1)
DSP.settings.arb_filters.budget=150
local fresh,s=M.arbitrage_grouped_ui();assert(#fresh==0 and s=='loading','changed budget hides previous scenario')
finish();groups=M.arbitrage_grouped_ui();assert(groups[1].planned==1)
DSP.settings.tax_bp=10000
assert(#M.arbitrage_grouped_ui()==0,'changed tax hides old profit immediately')
finish();assert(#M.arbitrage_grouped_ui()==0)
DSP.settings.tax_bp=200;DSP.settings.arb_filters.budget=0
M.arbitrage_grouped_ui();finish();assert(#M.arbitrage_grouped_ui()==2)
now=now+31
local expired,es=M.arbitrage_grouped_ui();assert(#expired==0 and es=='loading','expired quotes hidden before refresh work')
finish();assert(#M.arbitrage_grouped_ui()==0)
-- Large candidate generation and sorting really suspend, without changing allocation.
M,step,finish,counts=fixture(true);DSP.settings.arb_filters={max_age=0}
rebuild(M,30,10)
local baseline=M.arbitrage_grouped();local expected={}
for _,g in ipairs(baseline)do expected[g.key]={planned=g.planned,cost=g.cost,profit=g.profit}end
M.invalidate_arbitrage();M.arbitrage_grouped_ui()
local steps=finish();assert(steps>10,'large candidate sorting must cooperatively yield')
groups=M.arbitrage_grouped_ui();assert(#groups==10)
for _,g in ipairs(groups)do local e=expected[g.key];assert(g.planned==e.planned and g.cost==e.cost and g.profit==e.profit,'cooperative sort preserves allocation')end
assert(M.arb_yield==nil,'worker hook removed after completion')
-- A job already running cannot publish a different server after invalidation.
M.invalidate_arbitrage();M.arbitrage_grouped_ui();step();step()
M.clear_for_server(103)
local switched,ss=M.arbitrage_grouped_ui();assert(#switched==0 and ss=='loading')
finish();assert(M.arb_yield==nil,'cancelled worker cleans yield hook')
local next_rows,next_status=M.arbitrage_grouped_ui();assert(#next_rows==0)
if next_status=='loading'then finish()end
local done,ds=M.arbitrage_grouped_ui();assert(#done==0 and ds=='ready','old server never appears')
-- Invalidation during processing also cancels same-server stale settings.
M.clear_for_server(102);rebuild(M,15,4);M.arbitrage_grouped_ui();step();step()
DSP.settings.arb_filters.min_profit=99999999
assert(#M.arbitrage_grouped_ui()==0);finish();M.arbitrage_grouped_ui();finish()
assert(#M.arbitrage_grouped_ui()==0)
-- Exceptions become an explicit error status, not recurring jobs every frame.
M.invalidate_arbitrage();local old=M.arbitrage_grouped
M.arbitrage_grouped=function()error('fixture allocator failure')end
M.arbitrage_grouped_ui();finish()
local failed,fs=M.arbitrage_grouped_ui();assert(#failed==0 and fs=='error'and M.arb_ui_error:find('fixture allocator failure',1,true))
local _,before=counts();for _=1,10 do M.arbitrage_grouped_ui()end
local _,after=counts();assert(before==after and M.arb_yield==nil)
M.arbitrage_grouped=old
-- No MonetLoader scheduler: existing pure desktop users get synchronous cache semantics.
M,step,finish,counts=fixture(false);DSP.settings.arb_filters={max_age=0};rebuild(M,4,2)
local sync,sy=M.arbitrage_grouped_ui();assert(#sync==2 and sy=='ready')
assert(M.arbitrage_grouped_ui()==sync);assert(counts()==1)
os.clock,os.time=real_clock,real_time
print('v2.2 async arbitrage: deferred cold work, stable cache, yields, stale cancellation, expiry, errors: ok')
