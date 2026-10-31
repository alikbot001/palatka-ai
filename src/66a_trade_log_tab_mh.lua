-- Trade-first journal tab, adapted from Market Helper log list.
-- Original reward/payday detail UI remains reachable if needed.
local V,M,C=DSP.ui22,DSP.mobile,DSP.craglog
local original=V.journal
local function b(label,id,width,on)
    return V.button(label,'tradelog_'..id,width,on)
end
local function line(e)
    if C.trade_feed_line then return C.trade_feed_line(e)end
    return tostring(e.item_name or'')..' '..DSP.money(e.amount or 0)
end
function V.journal()
    if V.trade_full_history and original then
        if b('Торговый журнал','trade_tab',200,true)then V.trade_full_history=false end
        return original()
    end
    local s=DSP.settings.craglog or{}
    DSP.settings.craglog=s
    V.heading('Торговый журнал',function()
        if b(s.open and'Скрыть окно' or'Показать окно','toggle',161,s.open)then
            if C.toggle then C.toggle()end
        end
    end,175)
    V.muted('Только подтверждённые продажи и покупки, без расчётных сделок арбитража.')
    if b('Все','all',88,V.trade_filter=='all' or not V.trade_filter)then V.trade_filter='all'end
    V.inline(5)
    if b('Продажи','sell',112,V.trade_filter=='sell')then V.trade_filter='sell'end
    V.inline(5)
    if b('Скупка','buy',112,V.trade_filter=='buy')then V.trade_filter='buy'end
    V.inline(5)
    if b('Подробная история','full',183)then V.trade_full_history=true end
    V.muted('Плавающий лог: прозрачность '..math.floor((tonumber(s.mh_log_alpha)or .58)*100)..'%')
    for _,pct in ipairs({25,45,60,80})do
        if b(pct..'%','opacity_'..pct,72,math.floor((s.mh_log_alpha or .58)*100)==pct)then
            s.mh_log_alpha=pct/100;DSP.save_settings()
        end
        V.inline(4)
    end
    V.muted('Строк в плавающем окне: '..tostring(s.mh_log_lines or 8))
    for _,n in ipairs({5,8,12})do
        if b(tostring(n),'lines_'..n,68,(s.mh_log_lines or 8)==n)then
            s.mh_log_lines=n;DSP.save_settings()
        end
        V.inline(4)
    end
    local all=C.trade_feed and C.trade_feed(40)or{}
    local rows={}
    for _,e in ipairs(all)do
        if not V.trade_filter or V.trade_filter=='all' or e.direction==V.trade_filter then
            rows[#rows+1]=e
        end
    end
    if #rows==0 then V.muted('Записей продажи и скупки пока нет.')end
    V.list_rows('tradelog_entries',rows,53,function(e,i)
        V.row('trade_'..i,53,function(w,x,y)
            V.at(x,y+2)
            if e.direction=='sell' then V.green(V.fit(line(e),w-8))
            else V.muted(V.fit(line(e),w-8))end
        end)
    end,{footer=function()V.muted('События сохраняются штатным журналом Palatka.')end})
end
return true
