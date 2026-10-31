-- v2.9.4: Market Helper-style journal as ONE normal screen, not a second floating UI.
-- Layout and filtering follow the user-provided Market_Helper(1).lua trade log.
local C,V=DSP.craglog,DSP.ui22
if C._mh_journal_screen_v294 then return true end
C._mh_journal_screen_v294=true
local function u(s)return DSP.utf8(tostring(s or''))end
local function text(s)imgui.Text(u(s))end
local function faded(s)imgui.TextDisabled(u(s))end
local function money(n)return DSP.money(math.floor(tonumber(n)or 0))end
local function button(s,id,w,active)
    return V.button(s,'mhjournal294_'..id,w,active,false,34)
end
local function state()
    DSP.settings.journal_mh=DSP.settings.journal_mh or {period='day',side='all',page=1,date=''}
    local s=DSP.settings.journal_mh
    if not ({day=true,week=true,month=true,all=true,date=true})[s.period] then s.period='day' end
    if not ({all=true,sell=true,buy=true})[s.side] then s.side='all' end
    s.page=math.max(1,math.floor(tonumber(s.page)or 1))
    return s
end
local function persist()
    if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()
    elseif DSP.save_settings then DSP.save_settings()end
end
local function select_period(s,period)
    if s.period~=period then s.period=period;s.page=1;persist()end
end
local function matching_date(ts,period,spec,now)
    if period=='all' then return true end
    if period=='date' then return os.date('%Y-%m-%d',ts)==spec end
    if period=='day' then return os.date('%Y-%m-%d',ts)==os.date('%Y-%m-%d',now)end
    local delta=period=='week' and 7*86400 or 30*86400
    return ts>=now-delta and ts<=now
end
local function available_dates(rows)
    local seen,dates={},{}
    for _,r in ipairs(rows)do
        if (r.ts or 0)>0 then
            local day=os.date('%Y-%m-%d',r.ts)
            if not seen[day] then dates[#dates+1]=day;seen[day]=true end
        end
    end
    table.sort(dates,function(a,b)return a>b end)
    return dates
end
local function cell(s,width,tip)
    local str=tostring(s or'')
    local shown=V.fit and V.fit(str,math.max(25,width-7)) or str
    text(shown)
    if tip and shown~=str and imgui.IsItemHovered and imgui.IsItemHovered() then
        imgui.SetTooltip(u(str))
    end
    imgui.NextColumn()
end
local function columns(w)
    -- The same six columns as the Market Helper "Сделки" table.
    local ratios={.155,.265,.075,.155,.14,.21}
    local sizes={}
    for i,r in ipairs(ratios)do sizes[i]=math.max(43,math.floor(w*r))end
    imgui.Columns(6,'##mhjournal294_columns',false)
    for i=1,6 do imgui.SetColumnWidth(i-1,sizes[i])end
    faded('Дата');imgui.NextColumn()
    faded('Товар');imgui.NextColumn()
    faded('Кол.');imgui.NextColumn()
    faded('Цена $');imgui.NextColumn()
    faded('Тип');imgui.NextColumn()
    faded('Ник');imgui.NextColumn()
    imgui.Separator()
    return sizes
end
local function row(e,sizes)
    local stamp=(e.ts and e.ts>0)and os.date('%d.%m %H:%M',e.ts)or'—'
    cell(stamp,sizes[1],true)
    cell(e.name or'?',sizes[2],true)
    cell(tostring(e.qty or 1)..(e.qty_exact==false and'~'or''),sizes[3])
    local price=tonumber(e.amount)or 0
    -- Palatka receipts already store the actual FULL transaction amount.
    -- Do not accidentally multiply by quantity a second time.
    cell('$'..money(price):gsub('^%$', ''),sizes[4],true)
    if e.kind=='sell' then
        imgui.TextColored(DSP.theme.col('good',1),u('Продажа'))
    else
        imgui.TextColored(DSP.theme.col('accent',1),u('Покупка'))
    end
    imgui.NextColumn()
    cell(e.partner and e.partner~='' and e.partner or'—',sizes[6],true)
end
local function page_nav(s,count)
    local count_pages=math.max(1,math.ceil(count/60))
    s.page=math.max(1,math.min(count_pages,s.page))
    local width=math.max(39,math.min(55,imgui.GetContentRegionAvail().x/7))
    if button('<<','first',width)then s.page=1;persist()end
    imgui.SameLine(0,4)
    if button('<','back',width)then s.page=math.max(1,s.page-1);persist()end
    imgui.SameLine(0,8)
    faded('Стр. '..s.page..'/'..count_pages..' ('..count..')')
    imgui.SameLine(0,8)
    if button('>','next',width)then s.page=math.min(count_pages,s.page+1);persist()end
    imgui.SameLine(0,4)
    if button('>>','last',width)then s.page=count_pages;persist()end
end

-- The original floating button/pin/minimize window is deliberately removed.
-- Data collection by C.log_trade/C.log_market continues unchanged.
function C.draw() end
if DSP.settings.craglog then DSP.settings.craglog.open=false end

function V.journal()
    local s=state()
    V.heading('Журнал сделок')
    local avail=imgui.GetContentRegionAvail().x
    local labels={{'all','Все'},{'day','Сегодня'},{'week','Неделя'},
                  {'month','Месяц'},{'date','Дата'}}
    local width=math.max(54,(avail-24)/5)
    for i,p in ipairs(labels)do
        if button(p[2],'period_'..p[1],width,s.period==p[1])then
            select_period(s,p[1])
            if p[1]=='date' then imgui.OpenPopup('##mhjournal294_dates')end
        end
        if i<#labels then imgui.SameLine(0,6)end
    end
    local query,edited=V.search('mhjournal294_search','Поиск товара / ника',-1)
    if edited then s.page=1 end
    local side_width=math.max(73,(imgui.GetContentRegionAvail().x-12)/3)
    for i,p in ipairs({{'all','Все сделки'},{'sell','Продажи'},{'buy','Покупки'}})do
        if button(p[2],'side_'..p[1],side_width,s.side==p[1])then
            s.side=p[1];s.page=1;persist()
        end
        if i<3 then imgui.SameLine(0,6)end
    end
    -- Read all once so date selection contains every recorded trade.
    local all=C.trade_rows('all',query or'',s.side)
    if imgui.BeginPopup('##mhjournal294_dates')then
        faded('Выбери дату')
        for _,date in ipairs(available_dates(all))do
            local display=date:sub(9,10)..'.'..date:sub(6,7)..'.'..date:sub(1,4)
            if imgui.Selectable(display..'##'..date,s.date==date)then
                s.date=date;s.period='date';s.page=1;persist();imgui.CloseCurrentPopup()
            end
        end
        imgui.EndPopup()
    end
    if s.period=='date' then
        if s.date=='' then faded('Дата не выбрана')
        else faded('Дата: '..s.date:sub(9,10)..'.'..s.date:sub(6,7)..'.'..s.date:sub(1,4))end
    end

    local filtered,now={},os.time()
    for _,r in ipairs(all)do
        if matching_date(tonumber(r.ts)or 0,s.period,s.date,now)then
            filtered[#filtered+1]=r
        end
    end
    table.sort(filtered,function(a,b)return (a.ts or 0)>(b.ts or 0)end)
    local total=C.trade_totals(filtered)
    imgui.Separator()
    imgui.TextColored(DSP.theme.col('good',1),u('Продажи: '..total.sell_qty..' шт. · '..money(total.sells)))
    imgui.SameLine(0,18)
    imgui.TextColored(DSP.theme.col('accent',1),u('Покупки: '..total.buy_qty..' шт. · '..money(total.buys)))
    if total.approx then faded('~ В некоторых старых записях количество приблизительное')end
    local start=(s.page-1)*60+1
    local finish=math.min(start+59,#filtered)
    local height=math.max(95,imgui.GetContentRegionAvail().y-54)
    if imgui.BeginChild('##mhjournal294_table',imgui.ImVec2(-1,height),true)then
        local sizes=columns(math.max(610,imgui.GetWindowContentRegionWidth()))
        if #filtered==0 then faded('История сделок пуста.')end
        for i=start,finish do
            local e=filtered[i]
            if e then row(e,sizes)end
        end
        imgui.Columns(1)
        if DSP.mobile and DSP.mobile.touch_scroll then
            DSP.mobile.touch_scroll(imgui.GetIO(),'mhjournal294')
        end
    end
    imgui.EndChild()
    page_nav(s,#filtered)
end
return true
