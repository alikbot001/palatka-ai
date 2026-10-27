-- Explicit deposit gains add to PayDay; account principal and bank salary mirrors do not.
local dir=os.tmpname();os.remove(dir);assert(os.execute('mkdir -p '..dir..'/logs')==0)
local function encode(v)
    if type(v)=='string' then return string.format('%q',v)end
    if type(v)~='table' then return tostring(v)end
    local out={};for key,value in pairs(v)do out[#out+1]='['..encode(key)..']='..encode(value)end
    return '{'..table.concat(out,',')..'}'
end
encodeJson=encode;decodeJson=function(s)return assert(loadstring('return '..s))()end
local noop=function()end
local real_time=os.time;local stamp=real_time()
os.time=function(t)if t then return real_time(t)end return stamp end
DSP={dir=dir,settings={server=102,chat_logs={},trades={},craglog={},tg_notify=false,tg_payday_enabled=false},
    clean_text=function(s)return tostring(s or '')end,lower=string.lower,money=tostring,
    add_log=noop,flog=noop,notify=noop,mkdir_p=noop,save_settings=function()return true end,
    logs={session_started=stamp,profit_summary=function()return{count=0,profit=0,total_get=0,total_give=0,cash_get=0,cash_give=0,roi=0,avg_profit=0}end},
    trades_log_path=dir..'/logs/trades.log',crates_log_path=dir..'/logs/crates.log',events_log_path=dir..'/logs/events.jsonl'}
imgui={OnFrame=noop}
for _,name in ipairs({'54_payday_parse','55_craglog','58_journal_delete','59_history','45_live'})do assert(loadfile('src/'..name..'.lua'))()end
local C,L=DSP.craglog,DSP.live
assert(not L.check_payday_message('[F] Player_Name[61]: жду PayDay'),'player chat must not start PayDay')
assert(not L.check_payday_message('Вы получили +$100.000 за договор (каждый PayDay)'),'bonus is not a PayDay header')
assert(L.check_payday_message('БАНКОВСКИЙ ЧЕК'))
assert(C.observe_payday('| Текущая сумма в банке: $212.880.268 (+$1.019.676)'))
assert(C.observe_payday('| Текущая сумма на депозите: $845.153.138 (+$742.076)'))
assert(C.observe_payday('| Общая заработная плата: $1.019.676'))
local row=C.filtered('payday')[1]
assert(row.income==1761752 and row.amount==1761752,'salary plus explicit deposit gain must count once without bank balance')
assert(#row.details==3 and row.details[1].metric=='bank','bank details retained')
assert(row.details[2].direction=='meta' and row.details[2].amount==0 and row.details[2].reported_gain==742076,'stored deposit schema changed')
assert(not C.observe_payday('[F] Player_Name[61]: зарплата $99.000'),'player chat cannot append salary')
local sum=C.summary('all')
assert(sum.payday_income==1761752 and sum.income==1761752 and sum.count==1,'summary differs from live PayDay')
assert(C.observe_payday('| Текущая сумма на депозите: $845.153.138 (+$742.076)'))
assert(C.summary('all').income==1761752 and #row.details==3,'repeated deposit evidence counted twice')
stamp=stamp+1801;assert(L.check_payday_message('БАНКОВСКИЙ ЧЕК'))
assert(C.observe_payday('| Текущая сумма на депозите: $844.411.062 (+$742.076)'))
assert(C.observe_payday('| Общая заработная плата: $0'))
assert(C.active_payday.income==742076 and C.active_payday.amount==742076,'zero salary suppressed independent deposit gain')
assert(C.summary('all').income==2503828 and C.summary('all').count==2,'zero-salary block changed count or lost deposit')
local function restore()
    for _,name in ipairs({'55_craglog','58_journal_delete','59_history'})do assert(loadfile('src/'..name..'.lua'))()end
    C=DSP.craglog;C.install()
end
restore()
assert(C.summary('all').income==2503828,'restart summary lost explicit deposit')
local restored=C.filtered('payday');assert(#restored==2 and restored[1].amount==1761752 and restored[2].amount==742076,'overlay restoration differs from live')
local history=C.history('payday','')
assert(#history==2 and history[1].amount==742076 and history[2].amount==1761752,'main history differs from live')
-- Old journal metadata remains readable without rewriting or migrating its bytes.
local fixture=assert(io.open(DSP.events_log_path,'a'))
fixture:write(encode({type='payday',kind='payday',id='legacy-payday',ts=stamp+1,raw='БАНКОВСКИЙ ЧЕК',details={}}),'\n')
for _,part in ipairs({
    {direction='meta',metric='bank',amount=0,reported_gain=1019676,raw='old bank'},
    {direction='meta',metric='deposit',amount=0,reported_gain=742076,raw='old deposit'},
    {direction='income',amount=1019676,raw='old salary'}})do
    fixture:write(encode({type='payday_detail',payday_id='legacy-payday',ts=stamp+1,detail=part}),'\n')
end
fixture:write(encode({type='payday',kind='payday',id='legacy-inline',ts=stamp+2,raw='Legacy inline',
    income=1019676,expense=0,amount=1019676,details={
        {direction='meta',metric='bank',amount=0,reported_gain=1019676,raw='inline bank'},
        {direction='meta',metric='deposit',amount=0,reported_gain=742076,raw='inline deposit'},
        {direction='income',amount=1019676,raw='inline salary'}}}),'\n')
fixture:close()
local function bytes()local f=assert(io.open(DSP.events_log_path,'r'));local raw=f:read('*a');f:close();return raw end
local original=bytes();restore()
assert(C.summary('all').income==6027332 and C.summary('all').count==4,'legacy metadata not included consistently')
local old=C.history('payday','old deposit')[1]
assert(old.income==1761752 and old.details[2].direction=='meta' and old.details[2].amount==0,'legacy history modified evidence')
assert(C.history('payday','inline deposit')[1].amount==1761752,'inline metadata excluded from restored history')
local inline
for _,e in ipairs(C.filtered('payday'))do if e.id=='legacy-inline' then inline=e end end
assert(inline and inline.amount==1761752,'inline metadata excluded from restored overlay')
assert(bytes()==original,'read-only reconstruction rewrote source journal')
for _,part in ipairs({{direction='meta',metric='bank',amount=0,reported_gain=1019676},
    {direction='income',metric='bank',amount=1019676},{direction='meta',metric='deposit',amount=0}})do
    local incoming,outgoing=DSP.payday_contribution(part)
    assert(incoming==0 and outgoing==0,'principal or bank mirror counted as income')
end
os.time=real_time
print('v22 PayDay deposit income: live, summary, history, restart, legacy evidence, counts: OK')
