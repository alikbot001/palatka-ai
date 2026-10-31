-- Compact on-demand drawer + independent touch calculator.
local M,U=DSP.mobile,DSP.ui
DSP.screens.list[#DSP.screens.list+1]={id='calculator',label='КАЛЬКУЛЯТОР'}
-- Keep old numbered screens stable; new calculator is appended as #9.
local base_set=DSP.screens.set
function DSP.screens.set(id)
    base_set(id)
    M.nav_open=false
end
function DSP.screens.topbar()
    M.title('PALATKA AI')
    imgui.Separator()
    for _,p in ipairs({{'palatka','Торговля'},{'arbitrage','Арбитраж'},
        {'search','Поиск'},{'lavki','Лавки'},{'logs','Журнал'},
        {'calculator','Калькулятор'},{'stats','Статистика'},
        {'notes','Заметки'},{'settings','Настройки'}}) do
        if M.button(p[2],'drawer_'..p[1],-1,U.screen==p[1],'nav') then
            DSP.screens.set(p[1])
        end
    end
end
local old_draw=DSP.screens.draw
function DSP.screens.draw(id)
    if id=='calculator' then return U.calculator_v16() end
    return old_draw(id)
end
local C={display='0',stored=nil,op=nil,fresh=true,history={},mode='standard',memory=0}
DSP.calc_v16=C
local function fmt(n)
    if n==math.huge or n==-math.huge or n~=n then return 'Ошибка' end
    if math.abs(n)<0.000000001 then n=0 end
    -- Avoid scientific notation for ordinary integer money amounts.
    if n == math.floor(n) and math.abs(n) < 1e15 then
        return string.format('%.0f',n)
    end
    return string.format('%.12g',n)
end
-- Only display gets separators: input and stored operands stay numeric.
function C.pretty_display()
    local raw=tostring(C.display or '0')
    local sign, integer, frac=raw:match('^([%-]?)(%d+)(%.?%d*)$')
    if not integer then return raw end
    integer=integer:reverse():gsub('(%d%d%d)','%1.'):reverse():gsub('^%.','')
    return sign..integer..(frac~='' and frac:gsub('^%.',',') or '')
end
local function value() return tonumber(C.display) or 0 end
local function evaluate(a,op,b)
    if op=='+' then return a+b
    elseif op=='-' then return a-b
    elseif op=='*' then return a*b
    elseif op=='/' then if b==0 then return nil end; return a/b end
    return b
end
local function record(a,op,b,n)
    C.history[#C.history+1]={text=fmt(a)..' '..op..' '..fmt(b)..' = '..(n and fmt(n) or 'Ошибка'),result=n}
    if #C.history>50 then table.remove(C.history,1) end
end
function C.press(k)
    if k:match('^%d$') then
        if C.fresh or C.display=='0' or C.display=='Ошибка' then C.display=k
        elseif #C.display<18 then C.display=C.display..k end
        C.fresh=false
    elseif k=='.' then
        if C.fresh or C.display=='Ошибка' then C.display='0';C.fresh=false end
        if not C.display:find('.',1,true) then C.display=C.display..'.' end
    elseif k=='AC' then
        C.display='0';C.stored=nil;C.op=nil;C.fresh=true;C.last_op=nil;C.last_rhs=nil
    elseif k=='C' then C.display='0';C.fresh=true
    elseif k=='+/-' then C.display=fmt(-value())
    elseif k=='%' then
        local n=value()/100
        if C.stored and (C.op=='+' or C.op=='-') then n=C.stored*n end
        C.display=fmt(n)
    elseif k=='=' then
        local op=C.op or C.last_op
        local a=C.stored or value()
        local b=C.op and value() or C.last_rhs
        if op and b then
            local n=evaluate(a,op,b)
            record(a,op,b,n)
            C.display=n and fmt(n) or 'Ошибка'
            C.last_op=n and op or nil;C.last_rhs=n and b or nil
            C.stored=nil;C.op=nil;C.fresh=true
        end
    elseif k=='+' or k=='-' or k=='*' or k=='/' then
        if C.op and C.stored and not C.fresh then
            local n=evaluate(C.stored,C.op,value())
            C.display=n and fmt(n) or 'Ошибка'
            if not n then C.stored=nil;C.op=nil;C.fresh=true;return C.display end
        end
        C.stored=value();C.op=k;C.fresh=true;C.last_op=nil
    end
    return C.display
end

function C.finance(buy,sell,qty,commission,extra)
    buy,sell,qty=tonumber(buy) or 0,tonumber(sell) or 0,tonumber(qty) or 0
    commission=math.max(0,math.min(100,tonumber(commission) or 0))
    extra=math.max(0,tonumber(extra) or 0)
    local spent=buy*qty+extra
    local received=sell*qty*(1-commission/100)
    local profit=received-spent
    return {spent=spent,received=received,profit=profit,roi=spent>0 and profit/spent*100 or 0,
        markup=buy>0 and (sell-buy)/buy*100 or 0}
end
local F={buy=0,sell=0,qty=1,commission=2,extra=0}
function U.calculator_v16()
    local w=imgui.GetContentRegionAvail().x
    if M.button('Обычный','calc_standard',190,C.mode=='standard') then C.mode='standard' end
    M.inline()
    if M.button('Прибыль / %','calc_profit',205,C.mode=='profit') then C.mode='profit' end
    if C.mode=='profit' then
        M.number('Цена покупки','finance_buy',F,'buy',0,190)
        M.number('Цена продажи','finance_sell',F,'sell',0,190)
        M.number('Количество','finance_qty',F,'qty',1,190)
        M.number('Комиссия %','finance_tax',F,'commission',0,190)
        M.number('Дополнительные расходы','finance_extra',F,'extra',0,190)
        local r=C.finance(F.buy,F.sell,F.qty,F.commission,F.extra)
        M.text('Затраты: '..DSP.money(r.spent)..' | Выручка: '..DSP.money(r.received))
        M.title('Прибыль: '..DSP.money(r.profit))
        M.text('ROI: '..fmt(r.roi)..'% | Наценка: '..fmt(r.markup)..'%')
        return
    end
    imgui.TextColored(DSP.theme.col('accent',1),DSP.utf8(C.pretty_display()))
    local rows={{'AC','+/-','%','/'},{'7','8','9','*'},{'4','5','6','-'},{'1','2','3','+'},{'C','0','.','='}}
    local button_width=math.max(65,math.min(130,math.floor((w-42)/4)))
    for _,row in ipairs(rows) do
        for i,k in ipairs(row) do
            local label=k=='/' and '/' or k=='*' and '*' or k
            if M.button(label,'calc_'..k,button_width,k=='=','primary') then C.press(k) end
            if i<4 then M.inline() end
        end
    end
    if M.button('История  '..#C.history,'calc_history',270) then C.history_open=not C.history_open end
    if C.history_open then
        local first=math.max(1,#C.history-8)
        for i=#C.history,first,-1 do
            local entry=C.history[i]
            if M.button(entry.text,'calc_rec_'..i,-1) then
                if entry.result then C.display=fmt(entry.result);C.fresh=true end
            end
        end
    end
end
