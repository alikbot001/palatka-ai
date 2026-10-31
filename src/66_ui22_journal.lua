-- Journal overview: quantities and estimated loot value, with inspectable receipts.
local V,M,C=DSP.ui22,DSP.mobile,DSP.craglog
local periods={{'session','Ñåññèÿ'},{'day','Ñåãîäíÿ'},{'all','Âñ¸ âðåìÿ'}}
local categories={{'all','Âñå'},{'loot','Íàãðàäû'},{'payday','PayDay'},{'sales','Ïðîäàæè'},
 {'buys','Ïîêóïêè'},{'income','Äîõîäû'},{'other','Äðóãîå'}}
V.journal_mode='loot';V.journal_period='day';V.journal_category=1
local function b(s,id,w,on)return V.button(s,'journal_'..id,w,on)end
local function cycle_period()
    local pos=1;for i,p in ipairs(periods)do if p[1]==V.journal_period then pos=i end end
    if b(periods[pos][2]..' >','period',140,true)then V.journal_period=periods[pos%3+1][1]end
end
function C.event_title(e)
    if e.kind=='item'or e.type=='crate'then return tostring(e.item_name or e.item or 'Íåèçâåñòíûé ïðåäìåò')..' x'..tostring(e.qty or e.count or 1)end
    if e.kind=='opening'then return 'Îòêðûòèå: '..tostring(e.source or 'Èñòî÷íèê íåèçâåñòåí')end
    if e.kind=='unknown'then return 'Íåðàñïîçíàííàÿ íàãðàäà'end
    if e.kind=='cash'then return 'Äåíüãè èç íàãðàäû'end
    if e.type=='payday'or e.kind=='payday'then return 'PayDay'end
    if e.type=='market'then return(e.direction=='sell'and'Ïðîäàæà: 'or'Ïîêóïêà: ')..tostring(e.item_name or '?')end
    if e.type=='income'or e.kind=='income'then return tostring(e.label or 'Äîõîä')end
    return 'Îáìåí: '..tostring(e.partner or 'Èãðîê íåèçâåñòåí')
end
function C.event_cash(e)
    if e.kind=='cash'then return tonumber(e.cash)or 0 end
    if e.type=='payday'then return tonumber(e.amount)end
    if e.type=='income'or e.kind=='income'then return tonumber(e.amount)end
    if e.type=='market'then return(tonumber(e.amount)or 0)*(e.direction=='sell'and 1 or -1)end
    if e.type=='trade'then return(tonumber(e.money_get)or 0)-(tonumber(e.money_give)or 0)end
end
local function cash_text(amount)
    if not amount then return end
    if amount>=0 then V.green('+'..DSP.money(amount))else V.red('-'..DSP.money(-amount))end
end
local function footer(key)
    local summary=C.summary(V.journal_period)
    local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY();local w=imgui.GetContentRegionAvail().x
    if w>800 then V.muted('Äîõîä '..DSP.money(summary.income)..' · Ðàñõîä '..DSP.money(summary.expense))
    else V.muted('Äåíåæíûé èòîã '..DSP.money(summary.net))end
    V.at(x+w-126,y);V.scroll_buttons(key)
end
local function loot_row(row,i)
    V.row('loot_'..i,60,function(w,x,y)
        M.thumbnail({name=row.name},32)
        V.at(x+42,y-3)
        if V.text_button(V.fit(row.name,w-280),'journal_loot_'..i,w-270,false,30)then V.loot_detail=row;V.open_popup('Ïîëó÷åííàÿ äîáû÷à','loot_detail')end
        V.at(x+42,y+27);V.muted(row.receipts..' ïîëó÷åíèé'..(row.ench>0 and(' · +'..row.ench)or''))
        V.at(x+w-220,y+5);V.text('x'..row.qty)
        V.at(x+w-150,y+4)
        if row.estimated>0 then V.green('~ '..DSP.money(row.estimated))else V.muted('Öåíà íåèçâåñòíà')end
        V.at(x+w-150,y+27)
        if row.unpriced_qty>0 then V.muted('Áåç öåíû: '..row.unpriced_qty)
        elseif row.unit_estimate then V.muted('~ '..DSP.money(row.unit_estimate)..'/øò.')end
    end)
end
local function event_row(e,i)
    V.row('event_'..i,58,function(w,x,y)
        V.at(x,y-3)
        if V.text_button(V.fit(C.event_title(e),w-180),'tools_entry_'..i,w-168,false,30)then
            V.journal_detail=e;V.open_popup('Ñîáûòèå','event')
        end
        V.at(x,y+27);V.muted(V.fit(os.date('%d.%m %H:%M',e.ts or 0)..' · '..tostring(e.source or e.label or 'Ïîäðîáíîñòè ïî íàæàòèþ'),w-180))
        V.at(x+w-160,y+6);cash_text(C.event_cash(e))
    end)
end
function V.journal()
    V.heading('Æóðíàë',function()
        cycle_period();V.inline()
        if b('Ìèíè-æóðíàë','mini',150)then DSP.settings.craglog.open=true;M.defer_save()end
    end,296)
    -- MCR-inspired mini-log controls: fully reversible, no action affects accounting.
    local st=DSP.settings.craglog or {}
    DSP.settings.craglog=st
    if st.compact==nil then st.compact=true end
    if st.alpha==nil then st.alpha=.28 end
    if b(st.compact and 'Компактный лог' or 'Расширенный лог','mini_layout',174,st.compact)then
        st.compact=not st.compact;M.defer_save()
    end
    V.inline()
    if b(st.click_through and 'Касания: насквозь' or 'Касания: управление','mini_touch',208,st.click_through)then
        st.click_through=not st.click_through;M.defer_save()
    end
    V.inline()
    if b('Открыть лог','mini_open',124)then st.open=true;M.defer_save()end
    V.muted('Окно сохраняет позицию после перетаскивания. Закреплять вручную не нужно.')
    local alpha=imgui.new.float(tonumber(st.alpha)or .28)
    imgui.SetNextItemWidth(math.min(260,imgui.GetContentRegionAvail().x))
    if imgui.SliderFloat('##mini_alpha',alpha,.08,1)then
        st.alpha=math.max(.08,math.min(1,alpha[0]));M.defer_save()
    end
    V.inline();V.muted('Непрозрачность: '..math.floor((st.alpha or .28)*100)..'%')
    local w=imgui.GetContentRegionAvail().x
    if b('Äîáû÷à','loot_mode',120,V.journal_mode=='loot')then V.journal_mode='loot'end
    V.inline();if b('Ñîáûòèÿ','events_mode',120,V.journal_mode=='events')then V.journal_mode='events'end
    V.inline()
    if V.journal_mode=='events'then
        local pos=V.journal_category
        if b(categories[pos][2]..' >','category',112,true)then V.journal_category=pos%#categories+1 end
        V.inline()
    end
    local query,edited=V.search('journal','Ïîèñê ïðåäìåòà èëè èñòî÷íèêà',-1)
    if edited then
        V.reset_list('journal_loot_'..V.journal_period)
        V.reset_list('journal_events_'..V.journal_period..V.journal_category)
    end
    if V.journal_mode=='loot'then
        local summary=C.loot_summary(V.journal_period,query)
        V.muted(V.fit(summary.qty..' øò. · Ïðîäàæà ~ '..DSP.money(summary.estimated)..' · Áåç öåíû '..summary.unpriced_qty..' øò.',w))
        V.list_rows('journal_loot_'..V.journal_period,summary.items,60,loot_row,{toolbar=footer})
    else
        local from=C.period_start(V.journal_period);local all=C.history and C.history(categories[V.journal_category][1],query)or C.filtered(categories[V.journal_category][1])
        local rows=V.memo('journal_period_rows',tostring(all)..'/'..from,function()
            local out={};for _,e in ipairs(all)do if(e.ts or 0)>=from then out[#out+1]=e end end;return out
        end)
        V.muted(#rows..' ñîáûòèé · íàæìèòå ñòðîêó äëÿ ïîäðîáíîñòåé')
        V.list_rows('journal_events_'..V.journal_period..V.journal_category,rows,58,event_row,{toolbar=footer})
    end
end
local previous=V.popups
function V.popups()
    if previous then previous()end
    V.popup('Ïîëó÷åííàÿ äîáû÷à','loot_detail',function()
        local row=V.loot_detail;if not row then return end
        V.text(row.name..(row.ench>0 and(' (+'..row.ench..')')or''))
        V.muted('Ïîëó÷åíî '..row.qty..' øò. · '..row.receipts..' îòäåëüíûõ ïîëó÷åíèé')
        if row.estimated>0 then V.green('Ïðèìåðíàÿ ïðîäàæà ~ '..DSP.money(row.estimated))end
        if row.unpriced_qty>0 then V.muted('Öåíà íåèçâåñòíà äëÿ '..row.unpriced_qty..' øò.')end
        V.muted(tostring(row.price_source or 'Íåò ðûíî÷íîé îöåíêè')..(row.price_ts and(' · '..os.date('%d.%m %H:%M',row.price_ts))or''))
        V.muted('Îöåíêà íå ãàðàíòèðóåò ïðîäàæó âñåãî êîëè÷åñòâà ïî ýòîé öåíå')
        V.loot_tab=V.loot_tab or 'receipts'
        if b('Ïîëó÷åíèÿ','receipts',145,V.loot_tab=='receipts')then V.loot_tab='receipts'end
        V.inline();if b('Èñòî÷íèêè','sources',145,V.loot_tab=='sources')then V.loot_tab='sources'end
        local h=math.max(48,imgui.GetContentRegionAvail().y-50)
        if V.loot_tab=='sources'then
            V.list('loot_sources',function()
                for source,qty in pairs(row.sources)do V.text(source..' · x'..qty)end
            end,{height=h,footer=function()if b('Çàêðûòü','loot_close',140)then imgui.CloseCurrentPopup()end end})
        else
            V.list_rows('loot_receipts',row.events,52,function(e,i)
                if V.text_button(V.fit(os.date('%d.%m %H:%M',e.ts or 0)..' · x'..tostring(e.qty or e.count or 1)..' · '..tostring(e.source or 'Íåèçâåñòíûé èñòî÷íèê'),imgui.GetContentRegionAvail().x-12),'journal_receipt_'..i,-1)then
                    V.journal_detail=e;imgui.CloseCurrentPopup();V.open_popup('Ñîáûòèå','event')
                end
            end,{height=h,footer=function()if b('Çàêðûòü','loot_close',140)then imgui.CloseCurrentPopup()end end})
        end
    end,{w=720,h=520})
end
