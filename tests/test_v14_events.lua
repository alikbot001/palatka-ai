-- Standalone event regression tests with pure Lua mocks (runs in texlua).
package.path='./src/?.lua;'..package.path
local dir='/tmp/palatka_v14_event_tests'
os.execute('mkdir -p '..dir..'/logs')
DSP={
    settings={server=102,craglog={open=false,pinned=false,minimized=false,filter='all'},tg_payday_last=0,tg_payday_enabled=false,tg_notify=false},
    dir=dir,trades_log_path=dir..'/logs/trades.log',events_log_path=dir..'/logs/events.jsonl',crates_log_path=dir..'/logs/crates.log',
    lower=function(s) return string.lower(s) end,clean_text=function(s) return tostring(s or '') end,
    money_val=function(s) return tonumber((tostring(s):gsub('[^%d]',''))) or 0 end,
    money=function(n) return '$'..tostring(n or 0) end,
    add_log=function() end,flog=function() end,save_settings=function() return true end,
    mkdir_p=function() end, notify=function() end,
    logs={profit_summary=function() return {count=3,profit=250,total_get=500,total_give=250,roi=100,avg_profit=83} end},
}
encodeJson=function(e) return '{"type":"'..tostring(e.type)..'","ts":'..tostring(e.ts or 0)..'}' end
decodeJson=function() return nil end
local ev={}
package.preload['samp.events']=function() return ev end
assert(loadfile('src/55_craglog.lua'))()
assert(loadfile('src/45_live.lua'))()
DSP.logs.log_chat=function(msg)
    DSP.live.check_payday_message(msg)
    DSP.live.check_income_message(msg)
    DSP.live.check_market_message(msg)
end
DSP.live.install()
assert(type(ev.onServerMessage)=='function','server hook missing')
ev.onServerMessage(0xFFFFFF,'PayDay')
local pay= DSP.craglog.filtered('payday')
assert(#pay==1,'payday must log with Telegram switch OFF')
ev.onServerMessage(0xFFFFFF,'PayDay')
assert(#DSP.craglog.filtered('payday')==1,'duplicate PayDay within same second')
ev.onServerMessage(0xFFFFFF,'вы заработали $12.500')
local incomes=DSP.craglog.filtered('income')
assert(#incomes==1 and incomes[1].amount==12500,'exact cash amount')
ev.onServerMessage(0xFFFFFF,'Вы продали Бинт x50 за $10.000')
assert(#DSP.craglog.filtered('sales')==1,'market sale captured')
assert(DSP.craglog.filtered('sales')[1].amount==10000,'market cash exact')
ev.onServerMessage(0xFFFFFF,'Вы купили Аптечка x2 за $3.000')
assert(#DSP.craglog.filtered('buys')==1,'market purchase captured')
ev.onServerMessage(0xFFFFFF,'Вы можете продать Бинт за $1000')
assert(#DSP.craglog.filtered('sales')==1,'price offer not treated as sale')
assert(#DSP.craglog.filtered('all')==4,'ring includes four actual events')
local f=assert(io.open(DSP.events_log_path,'r')); local t=f:read('*a');f:close()
assert(t:find('payday',1,true) and t:find('income',1,true),'events persisted')
print('v1.4 server + payday + income tests: OK')
