-- Durable rewards, real multi-message chat sequences, and historical valuation.
local dir = os.tmpname(); os.remove(dir); assert(os.execute('mkdir -p ' .. dir) == 0)
local function encode(v)
    if type(v) == 'string' then return string.format('%q', v) end
    if type(v) ~= 'table' then return tostring(v) end
    local out = {}; for k, x in pairs(v) do out[#out+1] = '[' .. encode(k) .. ']=' .. encode(x) end
    return '{' .. table.concat(out, ',') .. '}'
end
encodeJson = encode
decodeJson = function(s) return assert(loadstring('return ' .. s))() end
DSP = {dir=dir, settings={server=102, log_chat_drops=true, chat_logs={}}, db={}, logs={}}
DSP.clean_text = function(s) return s:gsub('{%x%x%x%x%x%x}', ''):gsub('^%s+', ''):gsub('%s+$', '') end
DSP.add_log=function() end; DSP.flog=function() end; DSP.money=tostring; DSP.notify=function() end
DSP.db.get=function(name) if name=='Ларец Fortnite' then return {buy={max=120,offers={{price=120,ts=900}}}} end end
assert(loadfile('src/05_trades.lua'))()
assert(loadfile('src/06_rewards.lua'))()
DSP.rewards.load()
local inline=DSP.rewards.parse('Вы открыли Тайник и получили Item (2 шт.)!')
assert(inline and inline.kind=='item' and inline.item_name=='Item' and inline.qty==2 and inline.source=='Тайник', 'inline opening does not swallow item reward')
local generic=DSP.rewards.parse('Вы получили Item (+2) (3 шт.)')
assert(generic and generic.item_name=='Item' and generic.qty==3 and generic.ench==2, 'generic item quantity reward')
local parsed=DSP.logs.parse_chat_drop('Вам выпало: Item (+3) (5 шт.)')
assert(parsed.name=='Item' and parsed.ench==3 and parsed.qty==5 and parsed.source=='тайник', 'quantity pattern preserves item/source')
local a="{FF00FF}Вам был добавлен предмет 'Ларец Fortnite'. Откройте инвентарь, используйте МЕНЮ"
local b="Вам был добавлен предмет 'Ностальгический ящик' (2шт). Откройте инвентарь, используйте МЕНЮ"
for i=1,2 do
 DSP.rewards.ingest(a,1000); DSP.rewards.ingest(b,1000); DSP.rewards.ingest('Вы открыли Тайник Vice City!',1000)
end
local items=DSP.rewards.query({kind='item',page_size=50})
assert(items.total==4, 'identical same-second rewards preserved')
assert(items.entries[1].qty==2 and items.entries[1].source=='Тайник Vice City', 'preceding items associated')
assert(items.entries[1].association=='inferred' and items.entries[1].price_known==false and items.entries[1].unit_price==nil, 'uncertainty and unknown valuation')
local priced=items.entries[2]
assert(priced.unit_price==120 and priced.estimated_value==120 and priced.price_ts==900 and priced.raw==a, 'historical snapshot and raw evidence')
DSP.rewards.ingest('Вы получили +$50.000 от хар-ки надетого аксессуара Космическое сердце (выдается каждые 30 минут)',1001)
local sum=DSP.rewards.summary()
assert(sum.cash==50000 and sum.estimated_value==240 and sum.unknown_items==2 and sum.openings==2, 'cash separate from item value')
assert(DSP.rewards.query({search='Fortnite',page_size=1,page=2}).total==2, 'search and pagination')
assert(DSP.rewards.query({kind='opening',from_ts=1001}).total==0, 'time filter')
DSP.rewards.ingest(a,1002); DSP.rewards.ingest('unrelated chat',1002); DSP.rewards.ingest('Вы открыли Тайник Лича!',1010)
assert(DSP.rewards.query({kind='item'}).entries[1].source=='неизвестно', 'expired window breaks uncertain association')
DSP.db.get=function() return {buy={max=999}} end
DSP.rewards.load()
assert(DSP.rewards.query({search='Fortnite',page_size=50}).entries[2].unit_price==120, 'reload retains original valuation')
local before=DSP.rewards.query().total
DSP.rewards.load(); assert(DSP.rewards.query().total==before, 'repeated load is idempotent')
DSP.db.get=function() return {buy={max=25},updated=990} end
DSP.rewards.ingest(a,1002)
assert(DSP.rewards.query({kind='item'}).entries[1].price_ts==990, 'cached market timestamp retained')
before=before+1
DSP.logs.clear_trades(); assert(DSP.rewards.query().total==before, 'legacy clear preserves durable reward history')
-- A damaged final write remains recoverable without poisoning the next append.
local f=assert(io.open(dir..'/rewards.jsonl','a')); f:write('BROKEN'); f:close()
DSP.rewards.load(); assert(DSP.rewards.corrupt_lines==1, 'corruption surfaced')
DSP.rewards.ingest(a,1004); DSP.rewards.load()
assert(DSP.rewards.query().total==before+1, 'append after damaged tail remains readable')
local legacy_count=DSP.rewards.query().total
DSP.settings.crates={old={ts=5,item_name='Legacy',count=2,price=10,source='Old crate'}}
DSP.rewards.load(); DSP.rewards.load()
assert(DSP.rewards.query().total==legacy_count+1, 'legacy migration runs once')
assert(DSP.rewards.query({search='Legacy'}).entries[1].estimated_value==20, 'legacy value retained')
assert(os.rename(dir,dir..'.moved'))
local failed, failure=DSP.rewards.ingest(a,2000)
assert(not failed and failure and DSP.rewards.last_error, 'disk failure is reported')
assert(os.rename(dir..'.moved',dir))
local real_open,reads=io.open,0
io.open=function(file,mode)
 if file==dir..'/rewards.jsonl' and mode=='r' then reads=reads+1 end
 return real_open(file,mode)
end
DSP.rewards.query({search='cache-probe'}); DSP.rewards.query({search='cache-probe'})
assert(reads==1, 'unchanged page does not rescan history each frame')
io.open=real_open
-- Byte fixtures exercise the game's CP1251 case folding even in UTF8 source tests.
local upper,lower='\210\192\201\205\200\202:fixture','\242\224\233\237\232\234:fixture'
DSP.lower=function(s)
 return (s:gsub('[\192-\223]',function(c) return string.char(c:byte()+32) end):gsub('\168','\184'):lower())
end
DSP.rewards.record({kind='cash',cash=7,source=upper,item_name=upper,raw='source filter fixture'})
assert(DSP.rewards.query({source_contains=lower}).total==1, 'CP1251 source substring folds case')
assert(DSP.rewards.summary({source_contains=lower}).cash==7, 'source substring applies to summary')
assert(DSP.rewards.query({source_contains='no-such-source'}).total==0, 'source substring has a separate cache signature')
assert(DSP.rewards.query({source=lower}).total==0, 'exact source filter retains exact semantics')
assert(DSP.rewards.query({search=lower}).total==1, 'general CP1251 search folds case')
assert(DSP.rewards.query({source_contains='source filter fixture'}).total==0, 'source filter ignores raw evidence')
local fixture=os.getenv('PALATKA_CHAT_FIXTURE')
if fixture then
 local previous=DSP.rewards.summary()
 local n=0
 for line in io.lines(fixture) do
  local h,m,s=line:match('^%[(%d%d):(%d%d):(%d%d)%]')
  if h then DSP.rewards.ingest(line,200000+tonumber(h)*3600+tonumber(m)*60+tonumber(s)); n=n+1 end
 end
 local summary=DSP.rewards.summary()
 print('real chat replay: lines='..n..' items='..(summary.items-previous.items)..' openings='..(summary.openings-previous.openings)..' cash='..(summary.cash-previous.cash))
end
print('rewards tests: ok')
