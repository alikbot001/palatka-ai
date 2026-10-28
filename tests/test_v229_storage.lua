-- Snapshot parser and valuations; no MonetLoader packet fixtures are claimed.
DSP={}
DSP.clean_text=function(s)return(tostring(s or ''):gsub('{[%x]+}',''):gsub('^%s+',''):gsub('%s+$',''))end
DSP.lower=function(s)return string.lower(s)end
DSP.trim=function(s)return(s:gsub('^%s+',''):gsub('%s+$',''))end
DSP.item_key=function(s,e)return string.lower(s)..':'..tostring(e)end
DSP.flog=function()end
DSP.money=function(x)return tostring(x)end
DSP.market={row_for=function(name)
 if name=='Дрова' then return {buy={max=6},sell={min=9}}end
 return nil
end}
dofile('src/47_storage.lua')
local S=DSP.storage
assert(S.kind_of('Багажник автомобиля')=='trunk')
assert(S.kind_of('Шкаф дома')=='cabinet')
assert(S.kind_of('Меню бизнеса')==nil)
local row=S.parse_line('1. Дрова (45 000 шт.)')
assert(row and row.name=='Дрова' and row.qty==45000)
row=S.parse_line('2. Дрова x45000');assert(row.qty==45000)
row=S.parse_line('3. Дрова');assert(row.qty==nil)
local ok,snap=S.accept('trunk','Багажник автомобиля','1. Дрова (45 000 шт.)\n2. Семена x2',1200)
assert(ok and snap.count_known==45002 and #snap.rows==2)
local result=S.evaluate(snap)
assert(result.total_qty==45002 and result.sell_to_buyers==270000 and result.missing_prices==1)
assert(result.ask_value==405000)
local again=S.accept('trunk','Багажник автомобиля','1. Дрова (45 000 шт.)\n2. Семена x2',1201)
assert(again and #S.snapshots==1,'duplicate dialog should not add quantities')
ok,snap=S.accept('cabinet','Шкаф дома','1. Дрова\n2. Семена x2',1300)
assert(ok and S.evaluate(snap).unknown_qty==1,'unknown quantity must stay nil')
local sorted=S.sorted(snap,'value');assert(sorted[1].name=='Дрова' or sorted[1].name=='Семена')
assert(not S.on_dialog(9,1,'Калькулятор','Дрова x100'))
DSP.market.state={sid=102}
S.snapshots[1].server=103
local wrong=S.evaluate(S.snapshots[1]);assert(wrong.cross_server and wrong.sell_to_buyers==0)
S.snapshots[1].server=102
assert(not S.evaluate(S.snapshots[1]).cross_server)
local manual,source=S.accept('trunk','Багажник','Дрова x3',1400,'manual')
assert(manual and source.source=='manual' and source.rows[1].qty==3)
assert(S.parse_line('Открыть багажник')==nil,'UI action cannot become inventory item')
local order1=S.sorted(source,'qty')
local order2=S.sorted(source,'qty')
assert(order1==order2,'cached rows avoid redundant per-frame sorting')
DSP.market.state.version=2
assert(S.sorted(source,'qty')~=order1,'price version invalidates row cache')
print('PASS v2.2.9 storage snapshot read-only / safe amounts / valuation')
