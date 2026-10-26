-- 2.1 compact history + calculator. Full persistent event capture stays in 55_craglog.
local V,M=DSP.ui21,DSP.mobile
local C=DSP.craglog
local filters={{'all','Все'},{'loot','Награды'},{'payday','PayDay'},
    {'sales','Продажи'},{'buys','Скупка'},{'income','Доходы'},{'other','Другое'}}
V.jfilter='all'
local function b(label,id,w,active) return V.button(label,'tools_'..id,w,active) end
local function label(e)
    if e.kind=='opening' then return 'Открытие: '..tostring(e.source or 'неизвестный источник') end
    if e.kind=='item' then return tostring(e.item_name or 'неизвестный предмет')..' x'..tostring(e.qty or 1) end
    return C.describe(e)
end
function V.journal()
    V.text('Журнал событий')
    V.inline()
    if b('Открыть мини-журнал','miniopen',214) then
        DSP.settings.craglog.open=true;M.defer_save()
    end
    -- At most four filters per row. No permanently visible bulky event cards.
    for i,f in ipairs(filters) do
        if b(f[2],'filter_'..i,math.min(122,math.max(86,imgui.GetContentRegionAvail().x/4)),V.jfilter==f[1]) then
            V.jfilter=f[1];V.pages.journal=1;V.journal_detail=nil
        end
        if i%4~=0 and i<#filters then V.inline() end
    end
    if V.journal_detail then
        local e=V.journal_detail
        if b('‹ Назад','history_back',125) then V.journal_detail=nil;return end
        V.text(os.date('%d.%m.%Y  %H:%M:%S',e.ts or os.time()))
        V.text(label(e))
        if e.source then V.text('Источник: '..tostring(e.source)) end
        if e.kind=='payday' or e.type=='payday' then
            V.text('PayDay: '..DSP.money(e.amount or 0))
            V.text('Прибыль: '..DSP.money(e.profit or 0))
        end
        if e.raw then V.muted('Чат: '..tostring(e.raw)) end
        return
    end
    local entries=C.filtered(V.jfilter)
    V.muted('Записей: '..#entries)
    local from,to=V.selected_page('journal',#entries,18)
    local index=0
    for i=#entries-from+1,#entries-to+1,-1 do
        local e=entries[i]
        if e then
            index=index+1
            local text=os.date('%H:%M:%S',e.ts or os.time())..'  '..label(e)
            if b(text,'entry_'..i,-1) then V.journal_detail=e end
        end
    end
    if #entries==0 then V.muted('Событий этой категории пока нет.') end
    V.pager('journal',#entries,18)
    if C.last_error then V.red('Ошибка записи: '..C.last_error) end
end
local calc=DSP.calc_v16
local finance={buy=0,sell=0,qty=1,commission=2,extra=0}
V.calc_mode='standard'
function V.calculator()
    V.text('Калькулятор')
    V.inline()
    if b('Обычный','calc_normal',124,V.calc_mode=='standard') then V.calc_mode='standard' end
    V.inline()
    if b('Прибыль / %','calc_finance',149,V.calc_mode=='finance') then V.calc_mode='finance' end
    V.inline()
    if b('История','calc_history',105,calc.history_open) then calc.history_open=not calc.history_open end
    imgui.Separator()
    if V.calc_mode=='finance' then
        M.number('Купил за ($/шт.)','calc_buy',finance,'buy',0,175)
        M.number('Продам за ($/шт.)','calc_sell',finance,'sell',0,175)
        M.number('Количество','calc_qty',finance,'qty',1,160)
        M.number('Комиссия (%)','calc_commission',finance,'commission',0,160)
        M.number('Доп. расходы ($)','calc_extra',finance,'extra',0,175)
        local r=calc.finance(finance.buy,finance.sell,finance.qty,finance.commission,finance.extra)
        V.muted('Затраты: '..DSP.money(r.spent)..'   ·   Выручка: '..DSP.money(r.received))
        if r.profit>=0 then V.green('Прибыль: '..DSP.money(r.profit)) else V.red('Убыток: '..DSP.money(r.profit)) end
        V.text(string.format('ROI %.1f%%   ·   Наценка %.1f%%',r.roi,r.markup))
    else
        V.text('                           '..calc.display)
        imgui.Separator()
        local rows={{'AC','+/-','%','/'},{'7','8','9','*'},{'4','5','6','-'},
            {'1','2','3','+'},{'C','0','.','='}}
        local w=math.max(54,math.min(135,(imgui.GetContentRegionAvail().x-26)/4))
        for r,row in ipairs(rows) do
            for i,k in ipairs(row) do
                if b(k,'calc_key_'..r..'_'..i,w,k=='=') then calc.press(k) end
                if i<4 then V.inline() end
            end
        end
    end
    if calc.history_open then
        V.text('История')
        for i=#calc.history,math.max(1,#calc.history-8),-1 do
            local e=calc.history[i]
            if b(e.text,'calc_rec_'..i,-1) and e.result then
                calc.display=tostring(e.result);calc.fresh=true
            end
        end
    end
end
