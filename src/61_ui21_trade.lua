-- Trade view: two tabs, inline editing, fixed actions; execution stays in auto.
local ffi=require('ffi')
local V,M,T=DSP.ui21,DSP.mobile,DSP.trade_v16
local function stock_preview()
    if V.kind~='sell' then return nil,nil end
    local stock=DSP.sell_stock_guard
    if not stock or type(stock.preview)~='function' then return nil,nil end
    local p=DSP.settings and DSP.settings.sell_preset
    return stock.preview((type(p)=='table' and p.items) or {},DSP.auto.inv)
end
local function busy()return DSP.auto.buy_running or DSP.auto.sell_running end
local function preset()return V.kind=='sell'and DSP.settings.sell_preset or DSP.settings.buy_preset end
local function b(s,id,w,on)return V.button(s,'trade_'..id,w,on)end
local function money(n)
    local text=string.format('%.0f',math.abs(n)):reverse():gsub('(%d%d%d)','%1.'):reverse():gsub('^%.','')
    return (n<0 and '-$'or'$')..text
end
local function report(ok,msg)DSP.notify(ok and tostring(msg or 'Ãîòîâî')or('Íå óäàëîñü: '..tostring(msg or '?')))end
function V.trade_add(source,it)
    if source=='inventory'then return T.add_from_inventory(V.kind,it)end
    return T.add_from_catalog(V.kind,it)
end
local function launch()
    local checked,ok,issues=pcall(T.validate,V.kind)
    if not checked then
        DSP.flog('PRESET validate error: '..tostring(ok))
        DSP.notify('Preset check failed; see standalone.log')
        return false
    end
    if not ok then V.tab='preset';report(false,table.concat(issues,'; '));return false end
    local started=DSP.auto.safe_start(V.kind)
    if started~=true then
        DSP.notify('Âûñòàâëåíèå íå çàïóùåíî: ñìîòðèòå ïðè÷èíó â ñòàòóñå òîðãîâëè')
        return false
    end
    return true
end
local function footer_height()return math.ceil((imgui.GetFontSize and imgui.GetFontSize()or 16)*2+62)end
local function footer(key)
    local r=T.totals(V.kind)
    local w=imgui.GetContentRegionAvail().x
    local first,second
    if not r.complete then
        first=(V.kind=='buy'and'Áþäæåò'or'Âûðó÷êà')..' — èòîã íå ðàññ÷èòàí'
        second=r.overflow and 'Ñóììà âíå òî÷íîãî äèàïàçîíà' or r.invalid_tax and 'Ïðîâåðüòå êîìèññèþ' or ('Ïðîâåðüòå öåíó / êîëè÷åñòâî: '..r.invalid..' ïîç.')
    elseif V.kind=='buy'then
        first='Áþäæåò ñêóïêè '..money(r.required_funds)
        second=r.positions..' ïîç. · '..r.qty..' øò. · Áåç êîìèññèè ïðîäàæè'
    else
        first='Âûðó÷êà '..money(r.gross)..' · Êîìèññèÿ ~ '..money(r.commission)
        second='×èñòûìè ~ '..money(r.net)..' · Ïðèáûëü '..(r.profit and '~ '..money(r.profit)or'— íåò ñåáåñòîèìîñòè')
    end
    V.text(V.fit(first,w));V.muted(V.fit(second,w))
    local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
    local info=(DSP.settings.dry_run and 'ÒÅÑÒ'or'ÐÅÀËÜÍÎ')
    if V.kind=='sell'and r.complete then info=r.positions..' ïîç. · '..r.qty..' øò. · '..info end
    V.muted(V.fit(info,math.max(1,w-406)))
    V.at(x+math.max(0,w-398),y);V.scroll_buttons(key);V.inline()
    if V.tab=='items'then
        if b(V.source=='inventory'and'Èíâåíòàðü'or'Êàòàëîã','source_menu',112)then V.open_popup('Ïðåäìåòû','source_menu')end
    else
        if b('Íàáîðû','manage',112)then V.open_popup('Íàáîðû','presets')end
    end
    V.inline()
    if busy()then
        if b('Îñòàíîâèòü','stop',146,true)then
            if DSP.auto.sell_running then DSP.auto.stop_sell()else DSP.auto.stop_buy()end
        end
    elseif V.button('Âûñòàâèòü >','trade_launch',146,false,true)then V.open_popup('Âûñòàâëåíèå','launch')end
end

local function item_row(it,i,w)
    local _,found=DSP.presets.find(V.kind,DSP.item_key(it.name or it.display or '',it.ench or 0))
    V.row('inventory_'..i,58,function(rw,x,y)
        M.thumbnail(it,32)
        V.at(x+42,y-3)
        if V.text_button(V.fit(it.display or it.name or '?',rw-190),'trade_name_add_'..i,rw-180,false,28)then report(V.trade_add(V.source,it))end
        V.at(x+42,y+26);V.muted(V.source=='inventory'and('Â èíâåíòàðå · '..tostring(it.count or it.qty or 0)..' øò.')or('ID '..tostring(it.id or '?')))
        V.at(x+rw-134,y+2)
        if b(found and 'Äîáàâëåí' or '+ Äîáàâèòü','add_'..i,134,found~=nil)then
            report(V.trade_add(V.source,it))
        end
    end)
end
local function item_rows(query)
    local q=DSP.lower(query)
    local source=V.source=='inventory'and DSP.auto.inv or DSP.items.by_id
    local sig=table.concat({V.source,tostring(source),tostring(#(DSP.auto.inv or {})),q,tostring(DSP.market.state.version)},'|')
    return V.memo('items_rows',sig,function()
        local out={}
        if V.source=='inventory'then
            -- Inventory tables are replaced by the scanner, not edited by rendering.
            for _,it in ipairs(DSP.auto.inv or {})do
                if q==''or DSP.lower(it.name or ''):find(q,1,true)then out[#out+1]=it end
            end
        else
            for id,name in pairs(DSP.items.by_id or {})do
                if name~='-'and DSP.trim(name)~=''and not name:find('DELETED',1,true)and(q==''or DSP.lower(name):find(q,1,true)or tostring(id)==q)then out[#out+1]={id=id,name=name}end
            end
            if #out==0 and q~=''then out=DSP.market.find_item(query)or {}end
            table.sort(out,function(a,b)return tostring(a.name or a.display)<tostring(b.name or b.display)end)
        end
        return out
    end)
end
local function items(query,edited)
    local listkey='items_'..V.kind..'_'..V.source
    if edited then V.reset_list(listkey)end
    V.list_rows(listkey,item_rows(query),58,item_row,{toolbar=footer,footer_height=footer_height()})
end

local function price_button_label(label,price)
    if not price then return label..' —' end
    if price>=1000000 then return label..' '..string.format('%.1fì',price/1000000) end
    if price>=10000 then return label..' '..string.format('%.1fê',price/1000) end
    return label..' '..tostring(price)
end
local function price_choice(it,i,which,label,w)
    local q=DSP.db and DSP.db.reference_prices and DSP.db.reference_prices(it.name,it.ench) or {}
    local amount=q[which]
    if b(price_button_label(label,amount),'reference_'..which..'_'..i,w,false) and not busy() then
        local ok,msg
        if DSP.db and DSP.db.apply_reference then ok,msg=DSP.db.apply_reference(it,which)
        else ok,msg=false,'Íåò ìîäåëè ðûíî÷íûõ öåí' end
        if ok then M.refresh_buffer(it,'price');M.defer_save() end
        report(ok,msg)
    end
end
local function preset_row(it,i)
    V.row('preset_'..V.kind..i,118,function(w,x,y)
        local namew=math.max(80,w-318)
        V.at(x,y)
        if busy()then V.muted(it.enabled~=false and '[x]'or'[ ]')
        elseif b(it.enabled~=false and 'x'or' ','enabled_'..i,42,it.enabled~=false)then
            it.enabled=it.enabled==false and(tonumber(it.price)or 0)>0 or false;M.defer_save()
        end
        V.at(x+48,y+2);M.thumbnail(it,30)
        V.at(x+86,y+8)
        if V.text_button(V.fit(it.name or '?',namew-92),'trade_name_'..i,namew-86,false,36)then V.item_info=it;V.open_popup('Ïðåäìåò','item_info')end
        local px=x+namew+6
        V.at(px,y)
        if busy()then V.text(DSP.money(it.price))else
            if M.compact_number(it,'price','v22_price_'..V.kind..i,122,0)then
                it.needs_price=(tonumber(it.price)or 0)<=0 or nil;it.enabled=(tonumber(it.price)or 0)>0
            end
        end
        V.at(px+128,y)
        if busy()then V.text(tostring(it.qty))else M.compact_number(it,'qty','v22_qty_'..V.kind..i,76,1)end
        V.at(px+210,y)
        if V.kind=='buy'then
            if b('...','quantity_'..i,44)and not busy()then V.qty_item=it;V.open_popup('Êîëè÷åñòâî','quantity')end
            V.at(px+260,y)
        end
        if b('x','remove_'..i,42)and not busy()then V.remove_pending={kind=V.kind,item=it};V.open_popup('Óäàëèòü ïîçèöèþ','remove')end
        -- Full-size actions stay on a second line: price input remains editable.
        -- Today is unavailable until genuine completed-sale history exists.
        local gap=6
        local btnw=math.max(54,math.floor((w-gap*2)/3))
        V.at(x,y+49);price_choice(it,i,'market','Ðûíîê',btnw)
        V.at(x+btnw+gap,y+49);price_choice(it,i,'buy','Ñêóïêà',btnw)
        V.at(x+(btnw+gap)*2,y+49);price_choice(it,i,'today','Ñåãîäíÿ',btnw)
        if V.kind=='sell' then
            local live=V._mcr_stocks and V._mcr_stocks[it]
            V.at(x,y+95)
            if live then
                local text='Пресет '..live.desired_qty..
                    ' / доступно '..live.available_qty..
                    ' / выставить '..live.planned_qty..
                    ' / не хватает '..live.shortfall
                V.muted(V.fit(text,w))
            else
                V.red(V.fit('Нет проверенного инвентаря; обнови скан',w))
            end
        end
    end)
end
local function my_preset()
    local p=preset()
    local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
    local w=imgui.GetContentRegionAvail().x
    local px=x+8+math.max(80,w-16-318)+6
    V.at(px,y);V.muted('Öåíà');V.at(px+128,y);V.muted('Øò.')
    V.at(x,y+24)
    V.list_rows('preset_'..V.kind..'_'..tostring(p),p.items or{},118,preset_row,{toolbar=footer,footer_height=footer_height()})
end
function V.trade()
    V.heading('Моя лавка',function()
        if b('Ïðîäàæà','sell',112,V.kind=='sell')then V.kind='sell'end
        V.inline();if b('Ñêóïêà','buy',112,V.kind=='buy')then V.kind='buy'end
    end,230)
    local w=imgui.GetContentRegionAvail().x
    V.muted(V.fit('Очередь: '..tostring(DSP.auto.status or 'готова')..
        ' · инвентарь: '..tostring(DSP.auto.inv_status or 'не сканирован'),w))
    V._mcr_stocks,V._mcr_stock_summary=stock_preview()
    if V.kind=='sell' then
        local stats=V._mcr_stock_summary
        if stats then
            V.muted(V.fit('Желаемое: '..stats.requested..' шт. · можно выставить: '..
                stats.planned..' · сокращено: '..stats.adjusted..' · отсутствует: '..
                stats.skipped,w))
        else
            V.red(V.fit('Нужен актуальный скан инвентаря перед продажей',w))
        end
    else
        V.muted('Скупка: заявки на покупку у других игроков; суммы — бюджет, не расход.')
    end
    if not busy() and b('Обновить инвентарь','refresh_inventory',166,false)then
        DSP.auto.scan_inventory()
    end
    local tabs=w*.56;local each=(tabs-6)/2
    if b('Ïðåäìåòû','items_tab',each,V.tab=='items')then V.tab='items'end
    V.inline();if b('Ìîé ïðåñåò · '..#(preset().items or{}),'preset_tab',each,V.tab=='preset')then V.tab='preset'end
    V.inline()
    if V.tab=='items'then
        local query,edited=V.search('items','Ïîèñê ïðåäìåòà èëè ID',-1)
        items(query,edited)
    else
        if b(V.fit(preset().name or'Îñíîâíîé',w-tabs-28)..' >','manage',-1)then V.open_popup('Íàáîðû','presets')end
        my_preset()
    end
end

local function remove_position()
    local p=V.remove_pending;if not p then return end
    V.text('Óäàëèòü '..tostring(p.item.name)..'?')
    V.cancel('remove');V.inline()
    if b('Óäàëèòü','confirm_remove',132)then
        for i,it in ipairs(DSP.presets.items(p.kind))do if it==p.item then DSP.presets.remove(p.kind,i);break end end
        V.remove_pending=nil;imgui.CloseCurrentPopup()
    end
end
local function presets_popup()
    local kind=V.kind
    local w=math.max(145,imgui.GetContentRegionAvail().x)
    local tab=math.max(60,(w-6)/2)
    if b('Продажа','preset_mode_sell',tab,kind=='sell')then V.kind='sell';kind='sell'end
    V.inline(6)
    if b('Скупка','preset_mode_buy',tab,kind=='buy')then V.kind='buy';kind='buy'end
    V.muted('Наборы · выбери текущий пресет или создай новый')
    local list=DSP.presets.list(kind)or{}
    V.list_rows('preset_library_'..kind,list,52,function(p,i)
        V.row('mcr_preset_library_'..i,52,function(rw,x,y)
            local name=V.fit(tostring(p.name or 'Без названия'),math.max(48,rw-104))
            V.at(x,y)
            if b(name,'select_'..i,math.max(48,rw-104),DSP.presets.selected(kind)==i)then
                report(DSP.presets.select(kind,i))
            end
            V.at(x+rw-92,y+12)
            V.muted(V.fit(tostring(#(p.items or {}))..' поз.',86))
        end)
    end,{height=math.max(64,math.min(134,imgui.GetContentRegionAvail().y-245)),footer=false})
    V.preset_name=V.preset_name or imgui.new.char[128]()
    imgui.SetNextItemWidth(-1);imgui.InputTextWithHint('##v22_preset_name',DSP.utf8('Íàçâàíèå íàáîðà'),V.preset_name,128)
    local name=DSP.to_cp(ffi.string(V.preset_name))
    if b('+ Ñîçäàòü','preset_create',130)then report(DSP.presets.create(kind,name))end
    V.inline();if b('Ïåðåèìåíîâàòü','preset_rename',166)then report(DSP.presets.rename(kind,DSP.presets.selected(kind),name))end
    if b('Ýêñïîðò','preset_export',110)then report(DSP.presets.export_file(kind))end
    V.inline();if b('Market Helper','preset_mh',151)then report(DSP.presets.import_mh())end
    V.inline();if b('Óäàëèòü','preset_delete',116)then
        V.delete_preset={kind=kind,index=DSP.presets.selected(kind)};imgui.OpenPopup(DSP.utf8('Óäàëèòü íàáîð')..'##v22_del_preset')
    end
    V.popup('Óäàëèòü íàáîð','del_preset',function()
        V.text('Áåçâîçâðàòíî óäàëèòü âûáðàííûé íàáîð?');V.cancel('del_preset');V.inline()
        if b('Óäàëèòü','del_preset_yes',142)then local p=V.delete_preset;report(DSP.presets.delete(p.kind,p.index));imgui.CloseCurrentPopup()end
    end,{w=560,h=170})
    if b('Èìïîðò JSON...','json_popup',160)then imgui.OpenPopup(DSP.utf8('Èìïîðò JSON')..'##v22_import')end
    V.inline();if b('Çàêðûòü','presets_close',116)then imgui.CloseCurrentPopup()end
    V.popup('Èìïîðò JSON','import',function()
        V.import_path=V.import_path or imgui.new.char[384]()
        imgui.SetNextItemWidth(-1);imgui.InputTextWithHint('##v22_import_path',DSP.utf8('Ïóòü ê ôàéëó JSON'),V.import_path,384)
        V.cancel('import');V.inline()
        if b('Èìïîðòèðîâàòü','import_file',180)then report(DSP.presets.import_file(DSP.to_cp(ffi.string(V.import_path)),kind))end
    end,{w=620,h=180})
end
local old=V.popups
function V.popups()
    if old then old()end
    V.popup('Ïðåäìåòû','source_menu',function()
        if b('Èíâåíòàðü','inventory',-1,V.source=='inventory')then V.source='inventory';imgui.CloseCurrentPopup()end
        if b('Êàòàëîã','catalog',-1,V.source=='catalog')then V.source='catalog';imgui.CloseCurrentPopup()end
        if b('Ïðîñêàíèðîâàòü èíâåíòàðü','scan',-1)then DSP.auto.scan_inventory();imgui.CloseCurrentPopup()end
        if b('+ Ââåñòè íàçâàíèå âðó÷íóþ','manual',-1)then imgui.CloseCurrentPopup();V.open_popup('Íîâûé ïðåäìåò','manual')end
        if b('Çàêðûòü','source_close',140)then imgui.CloseCurrentPopup()end
    end,{w=620,h=300})
    V.popup('Âûñòàâëåíèå','launch',function()
        local ok,issues,total=T.validate(V.kind)
        V.text((V.kind=='sell'and'Ïðîäàæà' or'Ñêóïêà')..' · '..(DSP.settings.dry_run and 'ÒÅÑÒ' or 'ÐÅÀËÜÍÎ'))
        if DSP.settings.dry_run then
            V.red('ÒÅÑÒ: òîðãîâûå çàÿâêè ÍÅ îòïðàâëÿþòñÿ ñåðâåðó.')
            if b('Ïåðåêëþ÷èòü íà ÐÅÀËÜÍÎ','mode_to_real',252) then
                DSP.settings.dry_run=false;M.defer_save()
            end
        else
            V.red('ÐÅÀËÜÍÎ: îòïðàâÿòñÿ çàÿâêè íà âûñòàâëåíèå â èãðîâîé ëàâêå.')
            if b('Ïåðåêëþ÷èòü íà ÒÅÑÒ','mode_to_test',252) then
                DSP.settings.dry_run=true;M.defer_save()
            end
        end
        if not ok and #issues>0 then V.red(V.fit('Ïðè÷èíà: '..tostring(issues[1]),math.max(1,imgui.GetContentRegionAvail().x))) end
        V.text('Позиций: '..DSP.presets.active_count(V.kind)..' · '..DSP.money(total))
        if V.kind=='sell' then
            local proposals,summary=stock_preview()
            if not proposals then
                V.red('Нет подтверждённых данных инвентаря — выставление заблокировано.')
            else
                V.muted('Пресет: '..summary.requested..' · запланировано: '..summary.planned..
                    ' · сокращено: '..summary.adjusted..' · пропущено: '..summary.skipped)
                V.muted('Выставление не равно продаже: доход только после покупки игроком.')
            end
        else
            V.muted('Это бюджет заявок. Расход возникнет после подтверждённой скупки.')
        end
        V.list('launch_issues',function()for _,s in ipairs(issues)do V.red(s)end end,{height=100})
        V.cancel('launch');V.inline()
        if b('Ïðîâåðèòü','review',128)then imgui.CloseCurrentPopup();V.open_popup('Ïðîâåðêà ñïèñêà','review')end
        V.inline();if b('Âûñòàâèòü','fast',142,ok)and ok then if launch() then imgui.CloseCurrentPopup() end end
    end)
    V.popup('Ïðîâåðêà ñïèñêà','review',function()
        local ok,issues,total=T.validate(V.kind)
        V.list_rows('review_items',preset().items or{},48,function(it)
            local proposal=V.kind=='sell' and V._mcr_stocks and V._mcr_stocks[it]
            V.text(V.fit(it.name,300))
            V.muted((proposal and ('План '..proposal.planned_qty..' / пресет '..proposal.desired_qty)
                or ('Пресет '..tostring(it.qty)))..' шт. · '..
                DSP.money(it.price)..(it.enabled==false and ' · выключено'or''))
        end,{height=185})
        V.text('Âñåãî: '..DSP.money(total));if not ok then V.red(V.fit(table.concat(issues,'; '),550))end
        V.cancel('review');V.inline();if b('Ïîäòâåðäèòü','review_start',176,ok)and ok then if launch() then imgui.CloseCurrentPopup() end end
    end)
    V.popup('Óäàëèòü ïîçèöèþ','remove',remove_position,{w=620,h=200})
    V.popup('Наборы','presets',presets_popup,{w=720,h=480})
    V.popup('Íîâûé ïðåäìåò','manual',function()
        V.manual_name=V.manual_name or imgui.new.char[192]()
        imgui.SetNextItemWidth(-1);imgui.InputTextWithHint('##v22_manual',DSP.utf8('Íàçâàíèå êàê â èãðå'),V.manual_name,192)
        V.cancel('manual');V.inline()
        if b('+ Äîáàâèòü','manual_add',150)then
            local ok,msg=T.add_from_catalog(V.kind,{name=DSP.trim(DSP.to_cp(ffi.string(V.manual_name)))})
            report(ok,msg);if ok then imgui.CloseCurrentPopup()end
        end
    end,{w=620,h=180})
    V.popup('Ïðåäìåò','item_info',function()
        local it=V.item_info
        if it then
            imgui.TextWrapped(DSP.utf8(it.name or '?'))
            local refs=DSP.db and DSP.db.reference_prices and DSP.db.reference_prices(it.name,it.ench) or {}
            V.muted('Îáúÿâëåíèÿ: ðûíîê '..(refs.market and DSP.money(refs.market) or '—')..' / ñêóïêà '..(refs.buy and DSP.money(refs.buy) or '—'))
            V.muted(refs.today and ('Ñåãîäíÿ, ñðåäíÿÿ öåíà ïðîäàæè: '..DSP.money(refs.today))
                or 'Ñåãîäíÿ: íåò ïîäòâåðæä¸ííûõ ñðåäíèõ öåí ñîâåðø¸ííûõ ïðîäàæ')
            if refs.source then V.muted(V.fit(refs.source,530)) end
            if V.kind=='sell'then
                V.muted('Ñåáåñòîèìîñòü çà øò. · 0 = áåñïëàòíî')
                if busy()then V.text(it.cost_price~=nil and DSP.money(it.cost_price)or'Íå çàäàíà')
                else M.compact_number(it,'cost_price','v22_cost',190,0)end
                V.muted(it.cost_price==nil and 'Íå çàäàíà: ïðèáûëü íåèçâåñòíà' or 'Ïðèáûëü ó÷èòûâàåò êîìèññèþ ïðîäàæè')
                if b('Íåèçâåñòíà','cost_unknown',146)and not busy()then
                    it.cost_price=nil;M.refresh_buffer(it,'cost_price');M.defer_save()
                end
                V.inline()
            end
        end
        if b('Çàêðûòü','info_close',140)then imgui.CloseCurrentPopup()end
    end,{w=620,h=280})
    V.popup('Êîëè÷åñòâî','quantity',function()
        local it=V.qty_item;if not it then return end
        V.text(V.fit(it.name,530));M.compact_number(it,'qty','popup_qty',180,1)
        for _,n in ipairs({1,10,100})do
            if b(tostring(n),'quick_qty_'..n,72)and not busy()then it.qty=n;M.refresh_buffer(it,'qty');M.defer_save()end
            V.inline()
        end
        if b('Ìàêñ','max_qty',100)then
            it._v22_limit=it._v22_limit or{qty=it.max_qty or it.qty};V.limit_open=true
        end
        if V.limit_open then
            V.muted('Óêàæèòå ëèìèò ñêóïêè');local lim=it._v22_limit
            M.compact_number(lim,'qty','limit_qty',180,1)
            if b('Ïðèìåíèòü ëèìèò','apply_limit',220)and not busy()then it.max_qty=lim.qty;it.qty=lim.qty;M.refresh_buffer(it,'qty');M.defer_save()end
        end
        if b('Ãîòîâî','qty_done',140)then V.limit_open=false;imgui.CloseCurrentPopup()end
    end)
end
