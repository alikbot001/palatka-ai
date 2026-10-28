local dir=os.tmpname();os.remove(dir);assert(os.execute('mkdir -p '..dir..'/logs')==0)
local function encode(v)
 if type(v)=='string' then return string.format('%q',v) end
 if type(v)~='table' then return tostring(v) end
 local t={};for k,x in pairs(v)do t[#t+1]='['..encode(k)..']='..encode(x)end
 return '{'..table.concat(t,',')..'}'
end
encodeJson=encode
DSP={dir=dir,settings={trades={},stalls={},crates={},chat_logs={},server=102,tg_notify=false},db={},logs={},
    money=tostring,add_log=function()end,notify=function()end,flog=function()end,
    clean_text=function(s)return s end}
dofile('src/05_trades.lua')
DSP.db.get=function(name) return {buy={max=100}} end
DSP.logs.record_trade('User',{{name='Дрова',qty=2}}, {},0,500,'ok')
DSP.logs.record_trade('User',{}, {},100,200,'ok')
local trades=DSP.settings.trades
local estimated,confirmed=0,0
for _,e in pairs(trades)do
 if e.profit_estimated then estimated=estimated+1;assert(e.profit==300)
 else confirmed=confirmed+1;assert(e.profit==100)end
end
assert(estimated==1 and confirmed==1,'only barter estimated')
local sm=DSP.logs.profit_summary('day')
assert(sm.estimated_result==300 and sm.confirmed_result==100)
assert(sm.cash_get==700 and sm.cash_give==100,'cash is not identical to valued-item profit')
print('v225 journal: market-valued trades marked estimated, cash flows separated PASS')
