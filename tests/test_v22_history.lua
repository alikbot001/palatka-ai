-- Full durable history remains available beyond the 300-row overlay ring.
local dir=os.tmpname();os.remove(dir);assert(os.execute('mkdir -p '..dir..'/logs')==0)
local function encode(v)
    if type(v)=='string' then return string.format('%q',v) end
    if type(v)~='table' then return tostring(v) end
    local out={};for k,x in pairs(v) do out[#out+1]='['..encode(k)..']='..encode(x) end
    return '{'..table.concat(out,',')..'}'
end
encodeJson=encode;decodeJson=function(s)return assert(loadstring('return '..s))()end
local noop=function()end
DSP={dir=dir,settings={server=102,chat_logs={},trades={}},db={get=noop},ui={},logs={},
    clean_text=function(s)return tostring(s or '')end,lower=string.lower,money=tostring,
    add_log=noop,flog=noop,notify=noop,mkdir_p=noop,save_settings=function()return true end,
    trades_log_path=dir..'/logs/trades.log',crates_log_path=dir..'/logs/crates.log',events_log_path=dir..'/logs/events.jsonl'}
for _,name in ipairs({'05_trades','06_rewards','54_payday_parse','55_craglog','58_journal_delete'}) do assert(loadfile('src/'..name..'.lua'))() end
DSP.rewards.load()
local C=DSP.craglog
local extension=loadfile('src/59_history.lua');if extension then extension() end
local f=assert(io.open(DSP.events_log_path,'a'))
for i=1,350 do f:write(encode({id='income-'..i,type='income',kind='income',ts=i,amount=i,label='Income '..i,raw='receipt '..i}),'\n') end
local trade={id='trade:mirror',type='trade',ts=370,partner='Partner',profit=5,money_get=5,total_get=5,total_give=0}
f:write(encode(trade),'\n');DSP.settings.trades.mirror=trade
DSP.settings.trades.old={type='trade',ts=1,partner='Ancient',profit=2,money_get=2,total_get=2,total_give=0}
f:write(encode({id='payday-old',type='payday',kind='payday',ts=400,profit=3,count=2,raw='PayDay',details={}}),'\n')
f:write(encode({type='payday_detail',payday_id='payday-old',ts=400,detail={direction='income',amount=15000,raw='Salary receipt'}}),'\n')
f:write(encode({type='payday_detail',payday_id='payday-old',ts=400,detail={direction='expense',amount=750,raw='Tax receipt'}}),'\n')
f:close()
for i=1,430 do assert(DSP.rewards.record({kind='item',ts=500+i,item_name='Reward '..i,qty=1,source='Source',raw='reward receipt '..i})) end
assert(C.ring_count==300,'fixture did not overflow overlay')
local failed={}
local function check(label,fn)local ok,err=pcall(fn);if not ok then failed[#failed+1]=label..': '..tostring(err)end end
check('all durable events and rewards included exactly once',function()
    assert(type(C.history)=='function','full history API missing')
    local rows=C.history('all','')
    assert(#rows==783,'full history count '..#rows)
    assert(rows[1].item_name=='Reward 430' and rows[#rows].ts==1,'newest-first ordering')
    assert(#C.history('income','')==350,'old income rows lost')
    assert(#C.history('sales','')==2,'source trades lost or mirror duplicated')
    assert(#C.history('loot','')==430,'rewards only first page loaded')
end)
check('PayDay patches merge into one searchable parent',function()
    local rows=C.history('payday','tax receipt')
    assert(#rows==1 and rows[1].amount==14250 and rows[1].income==15000 and rows[1].expense==750,'PayDay merge')
    assert(#rows[1].details==2,'detail rows lost or duplicated')
    assert(#C.history('all','receipt 1')>0,'raw evidence search')
end)
check('legacy deposit metadata contributes to historical income',function()
    local file=assert(io.open(DSP.events_log_path,'a'))
    file:write(encode({id='deposit-payday',type='payday',kind='payday',ts=950,raw='БАНКОВСКИЙ ЧЕК',details={}}),'\n')
    for _,part in ipairs({
        {direction='meta',metric='bank',amount=0,reported_gain=1019676,raw='bank evidence'},
        {direction='meta',metric='deposit',amount=0,reported_gain=742076,raw='deposit evidence'},
        {direction='income',metric='salary',amount=1019676,raw='salary evidence'}}) do
        file:write(encode({type='payday_detail',payday_id='deposit-payday',ts=950,detail=part}),'\n')
    end
    file:close();C.ring_push({type='payday',ts=950,id='deposit-payday'})
    local rows=C.history('payday','deposit evidence')
    assert(#rows==1 and rows[1].income==1761752 and rows[1].amount==1761752,'legacy deposit excluded or bank gain doubled')
    assert(#rows[1].details==3 and rows[1].details[2].direction=='meta' and rows[1].details[2].amount==0,'stored deposit evidence changed')
end)
check('redraw and search never reopen durable files',function()
    C.history('all','')
    local original=io.open;local reads=0
    io.open=function(path,mode)if mode=='r' and (path==DSP.events_log_path or path==dir..'/rewards.jsonl')then reads=reads+1 end return original(path,mode)end
    for i=1,20 do C.history('all','query '..i);C.history('income','receipt') end
    io.open=original
    assert(reads==0,'unchanged history reopened '..reads..' files')
end)
check('new events and PayDay details invalidate snapshot',function()
    local before=#C.history('all','')
    assert(C.log_income('New incoming',4,'new event'))
    assert(#C.history('all','')==before+1 and #C.history('income','new event')==1,'new event absent from cache')
    assert(C.log_payday({profit=0,count=0},'PayDay'))
    assert(C.history('payday','PayDay')[1].amount==nil,'unknown amount invented')
    assert(C.observe_payday('начислено $100'))
    local rows=C.history('payday','начислено')
    assert(#rows==1 and rows[1].amount==100,'detail append did not invalidate cached history')
end)
check('tombstones hide old rows and survive history reload',function()
    local old=C.history('income','receipt 1')[1];assert(old,'old fixture missing')
    local key=C.event_key(old);assert(C.delete_event(old))
    for _,e in ipairs(C.history('all','')) do assert(C.event_key(e)~=key,'deleted row remained visible')end
    assert(loadfile('src/59_history.lua'))()
    for _,e in ipairs(C.history('all','')) do assert(C.event_key(e)~=key,'history reload lost tombstone')end
end)
check('reward associations update historical source without duplicate rows',function()
    local reward=DSP.rewards.query({search='Reward 430',page_size=200}).entries[1]
    assert(DSP.rewards.record({kind='association',item_ids={reward.id},opening_id='opening',source='Linked source',ts=999}))
    local rows=C.history('loot','Linked source')
    assert(#rows==1 and rows[1].association=='inferred','reward association cache stale')
end)
for _,err in ipairs(failed)do io.stderr:write(err..'\n')end
assert(#failed==0,tostring(#failed)..' history regressions')
print('v2.2 full durable history regressions: OK')
