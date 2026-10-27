-- Compact journal and iPhone-like keypad share the workspace touch primitives.
local V,M,C=DSP.ui21,DSP.mobile,DSP.craglog
local ffi=require('ffi')
local filters={{'all','Все'},{'loot','Награды'},{'payday','PayDay'},{'sales','Продажи'},
 {'buys','Скупка'},{'income','Доходы'},{'other','Другое'}}
V.jfilter='all'
local function b(s,id,w,on,primary,height)return V.button(s,'tools_'..id,w,on,primary,height)end
function V.journal()
    V.text('История');V.inline()
    if b('Мини-журнал','mini',170)then DSP.settings.craglog.open=true;M.defer_save()end
    V.jfilter_pos=V.jfilter_pos or 1
    V.inline();if b('<','filter_prev',44)then V.jfilter_pos=(V.jfilter_pos-2)%#filters+1 end
    V.inline();if b(filters[V.jfilter_pos][2],'filter',134,true)then V.jfilter_pos=V.jfilter_pos%#filters+1 end
    V.inline();if b('>','filter_next',44)then V.jfilter_pos=V.jfilter_pos%#filters+1 end
    V.jfilter=filters[V.jfilter_pos][1]
    local query,edited=V.search('journal','Поиск по событию и источнику',-1)
    -- Ring is bounded; cache invalidates on newest record and in-place detail updates.
    if edited then V.reset_list('journal_'..V.jfilter)end
    local newest
    if C.history then newest=C.history(V.jfilter,query)
    else
        newest={};local rows=C.filtered(V.jfilter)
        for i=#rows,1,-1 do newest[#newest+1]=rows[i]end
    end
    V.list_rows('journal_'..V.jfilter,newest,54,function(e,i)
        V.row('journal_'..i,54,function(w,x,y)
            V.muted(os.date('%H:%M',e.ts or 0))
            V.at(x+52,y)
            if b(V.fit(C.describe(e),w-68),'entry_'..i,w-54)then V.journal_detail=e;V.open_popup('Событие','event')end
        end)
    end,{footer=function()
        V.muted(#newest..' событий')
        if C.last_error then V.inline();V.red(V.fit(C.last_error,imgui.GetContentRegionAvail().x))end
    end})
end
local calc=DSP.calc_v16
local finance={buy=0,sell=0,qty=1,commission=1,extra=0}
V.finance=finance
local function decimal(label,key,width)
    local x=imgui.GetCursorPosX()
    V.muted(label)
    -- Text starts a new line at the window's left edge, not this field's column.
    V.at(x,imgui.GetCursorPosY())
    local buf=M.edit_buffer(finance,key)
    imgui.SetNextItemWidth(width or -1)
    if imgui.InputText('##v22_finance_'..key,buf,64)then
        local raw=ffi.string(buf):gsub(',','.')
        local n=tonumber(raw)
        local valid=raw:match('^%d*%.?%d+$')and n and n==n and n>=0 and n<=9007199254740991
        V.finance_invalid=V.finance_invalid or{};V.finance_invalid[key]=not valid or nil
        if valid then finance[key]=n end
    end
    if V.finance_invalid and V.finance_invalid[key]then V.at(x,imgui.GetCursorPosY());V.red('Проверьте число')end
end
local function finance_panel()
    V.text('Прибыль от сделки')
    local w=imgui.GetContentRegionAvail().x;local x=imgui.GetCursorPosX();local y=imgui.GetCursorPosY()
    decimal('Закупка, $','buy',(w-10)/2)
    V.at(x+(w+10)/2,y);decimal('Продажа, $','sell',(w-10)/2)
    y=imgui.GetCursorPosY();V.at(x,y);decimal('Количество','qty',(w-10)/2)
    V.at(x+(w+10)/2,y);decimal('Комиссия, %','commission',(w-10)/2)
    V.at(x,imgui.GetCursorPosY());decimal('Доп. расходы, $','extra',-1)
    imgui.Separator()
    if V.finance_invalid and next(V.finance_invalid)then V.red('Исправьте поля для расчёта');return end
    local r=calc.finance(finance.buy,finance.sell,finance.qty,finance.commission,finance.extra)
    V.muted('Затраты '..DSP.money(r.spent));V.muted('Выручка после комиссии '..DSP.money(r.received))
    if r.profit>=0 then V.green('Чистыми '..DSP.money(r.profit))else V.red('Убыток '..DSP.money(r.profit))end
    V.muted(string.format('Наценка %.2f%% · ROI %.2f%%',r.markup,r.roi))
end
local function keypad(width,height)
    local top=imgui.GetCursorPosY();local x=imgui.GetCursorPosX()
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,12)
    V.apply_font((V.font_pixels or 18)*1.4)
    V.text(V.fit(calc.display,width-12))
    V.apply_font()
    local rows={{'AC','+/-','%','/'},{'7','8','9','*'},{'4','5','6','-'},{'1','2','3','+'},{'C','0','.','='}}
    local h=math.max(42,(height-(imgui.GetCursorPosY()-top)-24)/5)
    local bw=(width-18)/4
    for r,row in ipairs(rows)do
        local y=imgui.GetCursorPosY()
        for i,k in ipairs(row)do
            V.at(x+(i-1)*(bw+6),y)
            local op=i==4
            if op then imgui.PushStyleColor(imgui.Col.Button,imgui.ImVec4(.73,.44,.12,1))
            elseif r==1 then imgui.PushStyleColor(imgui.Col.Button,imgui.ImVec4(.33,.39,.48,1))end
            if b(k,'calc_'..r..i,bw,false,false,h)then calc.press(k)end
            if op or r==1 then imgui.PopStyleColor(1)end
        end
        V.at(x,y+h+4)
    end
    imgui.PopStyleVar(1)
end
function V.calculator()
    V.text('Калькулятор');V.inline()
    if b('История · '..#calc.history,'history',175,calc.history_open)then V.open_popup('История расчётов','calc_history')end
    local avail=imgui.GetContentRegionAvail();local narrow=avail.x<720
    if narrow then
        V.calc_mode=V.calc_mode or 'standard'
        if b('Обычный','standard',140,V.calc_mode=='standard')then V.calc_mode='standard'end
        V.inline();if b('Прибыль / %','finance',166,V.calc_mode=='finance')then V.calc_mode='finance'end
        V.list('calculator',function(w,h)
            if V.calc_mode=='finance'then finance_panel()else keypad(w,h)end
        end)
    else
        local left=(avail.x-18)*.51;local x=imgui.GetCursorPosX();local y=imgui.GetCursorPosY()
        if imgui.BeginChild('##v22_calc_keys',imgui.ImVec2(left,avail.y),false,imgui.WindowFlags.NoScrollbar)then
            V.list('calc_keys',function(w,h)keypad(w,h)end)
        end
        imgui.EndChild();V.at(x+left+12,y)
        if imgui.BeginChild('##v22_calc_finance',imgui.ImVec2(0,avail.y),false,imgui.WindowFlags.NoScrollbar)then
            V.list('calc_finance',finance_panel)
        end
        imgui.EndChild()
    end
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    V.popup('Событие','event',function()
        local e=V.journal_detail;if not e then return end
        V.list('event_details',function()
            for _,line in ipairs(C.detail_lines(e))do imgui.TextWrapped(DSP.utf8(line))end
        end,{height=215})
        if b('Закрыть','event_close',138)then imgui.CloseCurrentPopup()end
        V.inline();if C.delete_event and b('Удалить запись','event_delete',180)then
            imgui.OpenPopup(DSP.utf8('Удалить событие')..'##v22_delete_event')
        end
        V.popup('Удалить событие','delete_event',function()
            V.text('Скрыть эту запись в журнале?')
            V.muted('Исходный учёт сделок сохранится')
            V.cancel('delete_event');V.inline()
            if b('Удалить','event_yes',142)then
                local ok,err=C.delete_event(e)
                if ok then V.journal_detail=nil;imgui.CloseCurrentPopup()else DSP.notify(tostring(err))end
            end
        end,{w=560,h=200})
    end)
    V.popup('История расчётов','calc_history',function()
        local rows={};for i=#calc.history,1,-1 do rows[#rows+1]=calc.history[i]end
        V.list_rows('calc_history',rows,48,function(e,i)
            if b(V.fit(e.text,imgui.GetContentRegionAvail().x-10),'calc_record_'..i,-1)and e.result then calc.display=tostring(e.result);calc.fresh=true end
        end,{height=235})
        if b('Закрыть','calc_history_close',140)then imgui.CloseCurrentPopup()end
    end)
end
