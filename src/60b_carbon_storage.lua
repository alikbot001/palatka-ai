-- Safe container analyzer; cannot read bespoke game UIs without a packet parser.
local ffi=require('ffi')
local V,S,M=DSP.ui21,DSP.storage,DSP.mobile
V.storage_sort='value'
V.storage_selected=1
local function b(s,id,w,on,primary)return V.button(s,'storage_'..id,w,on,primary)end
-- One task per panel: scanner, snapshots, manual fallback. This avoids the
-- previous giant fixed header which pushed the item list off small screens.
function V.storage_screen()
    V.heading('Õðàíèëèùà',function()
        if b('Î÷èñòèòü','clear',105)then V.open_popup('Î÷èñòèòü ñíèìêè?','storage_clear')end
    end,109)
    local capstate,capcount,caperr=S.textdraw_state()
    V.storage_tab=V.storage_tab or (#S.snapshots>0 and 'snapshots' or 'scan')
    local w=imgui.GetContentRegionAvail().x
    local tabw=math.max(78,(w-12)/3)
    for i,tab in ipairs({{'scan','Ñêàí'}, {'snapshots','Ñíèìêè'}, {'manual','Ââîä'}})do
        if b(tab[2],'tab_'..tab[1],tabw,V.storage_tab==tab[1],V.storage_tab==tab[1])then
            V.storage_tab=tab[1];V.reset_list('storage_scan_panel')
        end
        if i<3 then V.inline(5)end
    end
    imgui.Separator()
    if V.storage_tab=='scan' then
        V.list('storage_scan_panel',function(width)
            V.text('Àâòîìàòè÷åñêèé ñêàíåð áàãàæíèêà')
            V.muted('Packet 220 / marker 84 / iface 52 / type 8.')
            V.muted('Îòêðîé áàãàæíèê îáû÷íûì ñïîñîáîì. Ñêàíåð ðàáîòàåò àâòîìàòè÷åñêè.')
            V.muted('Ñíèìîê ñîõðàíÿåòñÿ òîëüêî ïîñëå ïîëó÷åíèÿ âñåõ 180 ñëîòîâ.')
            V.muted('Áåç ID ìàøèíû ÷àñòè÷íûå èçìåíåíèÿ íå ïðèìåíÿþòñÿ. Äëÿ îáíîâëåíèÿ îòêðîé áàãàæíèê çàíîâî.')
            local t=(S.trunk_state and S.trunk_state()) or S.trunk or {}
            local statuses={idle='îæèäàåò',receiving='ïîëó÷åíèå ñíèìêà',
                saved='ñîõðàíåíî',saved_from_disk='çàãðóæåí ïîñëåäíèé ñíèìîê',
                incomplete='íåïîëíûé ñíèìîê',unknown_partial='íåîïîçíàííûé ôðàãìåíò',
                unverified_delta='×àñòè÷íîå èçìåíåíèå ïðîïóùåíî', save_error='îøèáêà ñîõðàíåíèÿ'}
            V.text('Ñòàòóñ: '..(statuses[t.status] or tostring(t.status or '?')))
            V.muted('Ïîëó÷åíî ñëîòîâ: '..tostring(t.received or 0)..' / 180')
            if t.occupied then
                V.text('Çàíÿòî: '..tostring(t.occupied)..' | Ïðåäìåòîâ: '..tostring(t.total or 0))
            end
            if t.last_error then V.red(V.fit(tostring(t.last_error),width)) end
            V.muted('Áåç ID ìàøèíû: õðàíèòñÿ èìåííî ïîñëåäíèé îòêðûòûé áàãàæíèê.')
            V.muted('Øêàôû è ñêëàäû ïîêà íå ñêàíèðóþòñÿ ýòèì îáðàáîò÷èêîì.')
            -- Experiment: read-only inventory/cabinet candidate discovery.
            if V.storage_probe_panel then V.storage_probe_panel(width) end
            if b('Ïîêàçàòü ñîõðàíåííûé ñíèìîê','open_snap',math.min(width,280),false,true)then
                V.storage_tab='snapshots';V.storage_selected=1
            end
        end,{footer=function()V.muted('×òåíèå òîëüêî âõîäÿùèõ äàííûõ. Ïðåäìåòû â èãðå íå ïåðåìåùàþòñÿ.')end})
        return
    end
    if V.storage_tab=='manual' then
        V.list('storage_manual_panel',function(width)
            V.muted('Åñëè èãðîâîé èíòåðôåéñ íå âûäà¸ò ñîäåðæèìîå ÷åðåç ñîáûòèÿ,')
            V.muted('ìîæíî âñòàâèòü ñïèñîê âðó÷íóþ — ýòî íå èãðîâîé ñêàí.')
            V.storage_manual_kind=V.storage_manual_kind or 'trunk'
            local bw=math.max(72,(width-12)/3)
            for i,t in ipairs({{'trunk','Áàãàæíèê'},{'cabinet','Øêàô'},{'warehouse','Ñêëàä'}})do
                if b(t[2],'manual_'..t[1],bw,V.storage_manual_kind==t[1])then V.storage_manual_kind=t[1]end
                if i<3 then V.inline(5)end
            end
            V.storage_input=V.storage_input or imgui.new.char[8192]()
            V.muted('Ôîðìàò: Äðîâà x45000  èëè  Äðîâà (45000 øò.)')
            imgui.InputTextMultiline('##storage_text',V.storage_input,8192,imgui.ImVec2(-1,100))
            if b('Ñîõðàíèòü ñíèìîê','manual_accept',math.min(width,220),false,true)then
                local kind=V.storage_manual_kind
                local title=kind=='trunk'and'Áàãàæíèê (ðó÷íîé ñïèñîê)' or kind=='cabinet'and'Øêàô (ðó÷íîé ñïèñîê)' or 'Ñêëàä (ðó÷íîé ñïèñîê)'
                local ok,err=S.accept(kind,title,DSP.to_cp(ffi.string(V.storage_input)),nil,'manual')
                if ok then V.storage_tab='snapshots';V.storage_selected=1;V.storage_error=nil
                else V.storage_error=err end
            end
            if V.storage_error then V.red(tostring(V.storage_error))end
        end,{footer=false})
        return
    end
    local snapshots=S.snapshots
    if #snapshots==0 then
        V.muted('Ñíèìêîâ íåò: îáû÷íûé èãðîâîé äèàëîã ïîêà íå ðàñïîçíàí.')
        if b('Îòêðûòü äèàãíîñòèêó','scan_open',220,false,true)then V.storage_tab='scan'end
        return
    end
    V.storage_selected=math.max(1,math.min(#snapshots,V.storage_selected or 1))
    local current=snapshots[V.storage_selected]
    local controlw=math.max(90,(imgui.GetContentRegionAvail().x-8)/2)
    if b('Ñíèìîê '..V.storage_selected..' / '..#snapshots,'next',controlw)then
        V.storage_selected=V.storage_selected%#snapshots+1;V.reset_list('storage_items')
    end
    V.inline(7)
    if b(V.storage_sort=='value'and'Îöåíêà'or V.storage_sort=='qty'and'Êîëè÷åñòâî'
        or V.storage_sort=='price'and'Öåíà'or V.storage_sort=='category'and'Êàòåãîðèè' or 'À–ß',
        'sort',controlw)then
        V.storage_sort=V.storage_sort=='value'and'qty'or V.storage_sort=='qty'and'price'
            or V.storage_sort=='price'and'category'or V.storage_sort=='category'and'name'or'value'
        V.reset_list('storage_items')
    end
    if b('Íàçâàíèå ñíèìêà','rename',math.min(190,imgui.GetContentRegionAvail().x))then
        V.storage_label_target=current
        V.storage_label_buf=imgui.new.char[128]()
        ffi.copy(V.storage_label_buf,DSP.utf8(tostring(current.title or '')):sub(1,120))
        V.storage_label_error=nil
        V.open_popup('Íàçâàíèå ñíèìêà','storage_rename')
    end
    local rows,info=S.sorted(current,V.storage_sort)
    V.muted(V.fit(current.title..' · '..os.date('%d.%m %H:%M',current.observed_at)..
        (current.source=='packet220_trunk'and' · Packet 220' or current.source=='packet220_probe'and' · Packet 220 (непроверено)' or current.source=='manual'and' · âðó÷íóþ' or current.source=='textdraw'and' · TextDraw' or' · Dialog'),imgui.GetContentRegionAvail().x))
    V.text('Ïîäòâåðæäåíî: '..info.total_qty..' øò. · íåèçâåñòíî: '..info.unknown_qty..' ñòðîê')
    if current.source=='packet220_trunk' then
        V.muted('180 ñëîòîâ | '..tostring(current.occupied_slots or #current.rows)..' çàíÿòî | ID àâòî íå ïîäòâåðæäåí')
    end
    if current.source=='packet220_probe' then
        V.red('НЕПОЛНЫЙ СНИМОК: тип выбран вручную, неизвестные слоты не учитываются.')
        V.muted('Оценки относятся только к предметам, полученным при наблюдении.')
    end
    V.green('Îöåíêà ñêóïêè: '..DSP.money(info.sell_to_buyers))
    V.muted('Íå ïðèáûëü · ïðîäàæà ïî îáúÿâëåíèÿì: '..DSP.money(info.ask_value))
    if info.cross_server then V.red('Äðóãîé ñåðâåð: öåíû ñêðûòû')end
    V.muted('Â îäíîé ñòðîêå — âñå ñòàêè îäíîãî ïðåäìåòà è óëó÷øåíèÿ.')
    V.list_rows('storage_items',rows,94,function(it,i)
        V.row('storage_item_'..i,94,function(ww,x,y)
            local textwidth=math.max(80,ww-118)
            V.at(x,y);V.text(V.fit(it.name,textwidth))
            V.at(x,y+27);V.muted(V.fit('Êîëè÷åñòâî: '..(it.qty and tostring(it.qty)..' øò.'or'íåèçâåñòíî')..' / '..tostring(it.slots or 1)..' ñëîòîâ',textwidth))
            V.at(x,y+56)
            local total=(it.bid and it.qty)and DSP.money(it.bid*it.qty)or'íåò îöåíêè'
            V.muted(V.fit((it.manual_price and 'Ñâîÿ öåíà: ' or 'Ñêóïàþò: ')..(it.bid and DSP.money(it.bid)or'?')..' / øò. · '..total,textwidth))
            V.at(x+math.max(0,ww-107),y+16)
            if b('Ñâîÿ öåíà','edit_price_'..i,106,it.manual_price)then
                V.storage_price_target=current
                V.storage_price_row=it
                V.storage_price_buf={value=it.manual_price and it.bid or 0}
                V.storage_price_error=nil
                V.open_popup('Ñâîÿ öåíà','storage_price')
            end
        end)
    end,{footer=function()V.muted('Òîëüêî ñîðòèðîâêà Palatka AI, íå ïðåäìåòîâ èãðû.')end})
end

-- Deletion is a real modal confirmation; cancellation never changes snapshots.
local old_popups=V.popups
function V.popups()
    if old_popups then old_popups()end
    V.popup('Ñâîÿ öåíà','storage_price',function()
        local target,row=V.storage_price_target,V.storage_price_row
        if not target or not row then V.muted('Íåò âûáðàííîãî ïðåäìåòà');return end
        V.text(V.fit(row.name,imgui.GetContentRegionAvail().x))
        V.muted('Öåíà çà îäíó øòóêó äëÿ ðàñ÷¸òà ýòîãî ñíèìêà. 0 = öåíà API.')
        M.compact_number(V.storage_price_buf,'value','storage_price_value',math.min(250,imgui.GetContentRegionAvail().x),0)
        if b('Ñîõðàíèòü','price_apply',135,false,true)then
            local ok,err=S.set_manual_price(target,row,V.storage_price_buf.value)
            if ok then V.reset_list('storage_items');V.storage_price_target=nil;imgui.CloseCurrentPopup()
            else V.storage_price_error=err end
        end
        V.inline();if b('Îòìåíà','price_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_price_error then V.red(V.storage_price_error)end
    end,{w=460,h=260})
    V.popup('Íàçâàíèå ñíèìêà','storage_rename',function()
        local target=V.storage_label_target
        if not target then return end
        V.muted('Ýòî èìÿ òîëüêî äëÿ ñíèìêà. ID ìàøèíû àâòîìàòè÷åñêè íå îïðåäåëÿåòñÿ.')
        imgui.SetNextItemWidth(-1)
        imgui.InputText('##storage_name_input',V.storage_label_buf,128)
        if b('Ñîõðàíèòü','rename_apply',135,false,true)then
            local label=DSP.to_cp(ffi.string(V.storage_label_buf))
            local ok,err=S.set_snapshot_label(target,label)
            if ok then V.storage_label_target=nil;imgui.CloseCurrentPopup()
            else V.storage_label_error=err end
        end
        V.inline();if b('Îòìåíà','rename_cancel',110)then imgui.CloseCurrentPopup()end
        if V.storage_label_error then V.red(V.storage_label_error)end
    end,{w=460,h=240})
    V.popup('Î÷èñòèòü ñíèìêè?','storage_clear',function()
        V.text('Óäàëèòü ñîõðàí¸ííûå ñíèìêè øêàôîâ è áàãàæíèêîâ?')
        V.muted('Ïðåäìåòû â èãðå îñòàíóòñÿ áåç èçìåíåíèé.')
        if b('Óäàëèòü ñíèìêè','confirm_clear',170,false,true)then
            local old=S.snapshots
            S.snapshots={};S.last_signature=nil;S.last_snapshot=nil;V.storage_selected=1
            local old_trunk=S.trunk and S.trunk.snapshot
            if S.trunk then S.trunk.snapshot=nil;S.trunk.pending=nil;S.trunk.status='idle';S.trunk.received=0 end
            if DSP.settings then DSP.settings.storage_snapshots=S.snapshots end
            if DSP.save_settings and not DSP.save_settings() then
                S.snapshots=old
                if S.trunk then S.trunk.snapshot=old_trunk;S.trunk.status='saved' end
                if DSP.settings then DSP.settings.storage_snapshots=old end
                V.storage_error='Íå óäàëîñü ñîõðàíèòü óäàëåíèå';return
            end
            imgui.CloseCurrentPopup()
        end
        V.inline()
        if b('Îòìåíà','cancel_clear',120)then imgui.CloseCurrentPopup()end
    end,{w=480,h=230})
end
