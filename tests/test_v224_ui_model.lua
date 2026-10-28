-- Headless UI smoke; not a native MonetLoader visual or touch verification.
package.preload.ffi=function()return {}end
local V={cache={},errors={}}
local labels={};local textlines={}
local function add(s)textlines[#textlines+1]=tostring(s)end
V.button=function(s)labels[#labels+1]=tostring(s);return false end
V.inline=function()end;V.fit=function(s)return tostring(s)end
V.at=function()end;V.text=add;V.muted=add;V.green=add;V.red=add
V.heading=function(_,callback)if callback then callback()end end
V.list=function(_,callback)callback(500,350,0)end
V.list_rows=function(_,rows,_,callback)for i,r in ipairs(rows)do callback(r,i,500)end end
V.row=function(_,_,callback)callback(500,0,0)end
V.search=function()return '',false end
V.memo=function(_,_,factory)return factory()end
V.reset_list=function()end
V.popup=function()end
V.open_popup=function()end
V.cancel=function()end
V.set_screen=function()end
local now=os.time()
local sell={shop=12,ts=now,qty=20,qty_source='game',verified_at=now}
local buy={shop=34,ts=now,qty=20,qty_source='game',verified_at=now}
local row={key='Ore@0',name='Ore',display='Ore',sell={count=1,min=100,med=100,p25=100,p75=100},buy={best=120}}
local route={row=row,name='Ore',sell_offer=sell,buy_offer=buy,p_buy=100,p_sell=120,tradable_qty=20,demand_verified=true}
local group={key=row.key,name='Ore',row=row,routes={route},sellers={sell},buyers={buy}}
DSP={ui22=V,mobile={thumbnail=function()end,compact_number=function()return false end},
 settings={tax_bp=200,flip={capital=0,reserve_pct=10,max_risk=3,watch={}}},
 market={state={sid=102,version=1,by_key={[row.key]=row},rows={row}},arbitrage_grouped_ui=function()return {group},'ready'end},
 money=function(n)return tostring(n or 0)end,lower=function(s)return string.lower(tostring(s))end,
 save_settings=function()return true end}
dofile('src/48_flip_intel.lua');dofile('src/49_promo.lua')
assert(DSP.promo.add('One','/vr Продаю ресурсы',300))
DSP.flip.settings().watch[row.key]={name='Ore',max_price=105,server=102}
imgui={GetContentRegionAvail=function()return {x=650,y=450}end}
dofile('src/68_ui22_flip_promo.lua')
for _,tab in ipairs({'opportunities','portfolio','watch','pricing','earnings'})do
 V.flip_tab=tab;V.flip_screen()
end
V.promo_screen();V.popups()
local both=table.concat(labels,'|')
assert(both:find('Разобрать',1,true) and both:find('Маршрут',1,true))
assert(both:find('Запустить авто-пиар',1,true))
assert(both:find('Цена',1,true) or both:find('Настроить',1,true))
assert(table.concat(textlines,'|'):find('НЕ равно прибыли',1,true))
print('v2.2.4 UI model: all resale panes, promo, modal registration OK (headless)')
