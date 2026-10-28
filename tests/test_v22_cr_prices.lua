-- Regression: 15073 from Market Helper is a single observed average per item,
-- not the old fictional simultaneous "sell/buy" columns.
encodeJson=function()return '{}' end
decodeJson=function()return {} end
local root='/tmp/palatka_cr_prices_'..tostring(os.time())
os.execute('mkdir -p '..root)
DSP={dir=root,settings={server=102},market={},db={},
 lower=function(s)return s:lower()end,trim=function(s)return s:match('^%s*(.-)%s*$')end,
 clean_text=function(s)return(s or ''):gsub('{%x+}',''):match('^%s*(.-)%s*$')end,
 item_key=function(s,e)return s..':'..tostring(e)end,add_log=function()end,notify=function()end,flog=function()end}
dofile('src/10_market.lua')
DSP.market.state.sid=102
DSP.market.state.updated=os.time()
DSP.market.row_for=function()return nil end
dofile('src/15_prices.lua')
local P=DSP.market
assert(P.parse_cr_price('$61.300')==61300,'grouped dollar price')
assert(P.parse_cr_price(':CASH:61300')==61300,'cash prefix')
assert(P.parse_cr_price('К61.3')==61300,'K abbreviated price')
assert(P.parse_cr_price('КК1.25')==1250000,'KK abbreviated price')
assert(P.parse_cr_price('М2.5')==2500000000,'M abbreviated price')
assert(P.parse_cr_price('unknown')==nil,'unrecognized price not rejected')
local nm,v=P.parse_cr_list_line('Ларец разводчика продуктов\tКК1.25')
assert(nm=='Ларец разводчика продуктов' and v==1250000,'tabbed CR row')
local answered={}
sampGetCurrentDialogId=function()return 15073 end
sampSendDialogResponse=function(id,btn,idx,text)answered[#answered+1]={id,btn,idx,text}end
P.cr_scan_state.active=true
P.cr_scan_state.sid=102
P.cr_scan_state.items={};P.cr_scan_state.page=0
local txt='Название\tСредняя цена\nПоиск по названию\nНазад\nЛарец разводчика продуктов\tКК1.25\nСледующая страница'
assert(P.on_cr_marker_dialog(txt))
assert(#P.cr_scan_state.items==1 and P.cr_scan_state.items[1].sell_med==1250000)
assert(#answered==1 and answered[1][3]==3,'next-page index must exclude 15073 header')
assert(P.on_cr_marker_dialog(txt))
assert(#P.cr_scan_state.items==1 and #answered==1,'repeat inflated counts/replayed response')
P.cr_scan_state.last_page_text=nil
local end_text='Название\tСредняя цена\nПоиск по названию\nНазад\nСундук\t$61.300'
assert(P.on_cr_marker_dialog(end_text));assert(#P.cr_scan_state.items==2)
local refs=DSP.db.reference_prices('Ларец разводчика продуктов',0)
assert(refs.market==1250000 and refs.buy==nil and refs.today==nil,'CR offered median was treated as trades or buy')
P.mark_cr_dialog()
local day=os.date('%Y-%m-%d')
local detail='Дата\tКоличество\tЦена\n'..day..'\t2\t$100\n'..day..'\t3\t$200\n2020-01-01\t100\t$999'
assert(P.observe_cr_detail("Продажа товара 'Ларец разводчика продуктов'",detail),'history was not captured')
refs=DSP.db.reference_prices('Ларец разводчика продуктов',0)
assert(refs.today==160,'today must be quantity-weighted completed-sale price')
assert(refs.buy==nil,'CR sale detail manufactured buyback price')
local r=P.load_cr_marker(102);assert(#r.items==2 and r.histories,'history destroyed previous catalog')
DSP.settings.server=103
refs=DSP.db.reference_prices('Ларец разводчика продуктов',0)
assert(refs.market==nil and refs.today==nil,'cross-server leak')
os.remove(P.cr_marker_path(102))
os.execute('rmdir '..root)
print('CR market prices: real list format, page index, dedup, cached day history and server guard: OK')
