-- Compact utility screens share the workspace list and fixed scroll controls.
local ffi=require('ffi')
local V,M,U=DSP.ui21,DSP.mobile,DSP.ui
local function b(label,id,width,on,primary)return V.button(label,'tools22_'..id,width,on,primary)end
local function width()return math.max(1,imgui.GetContentRegionAvail().x)end
local function changed()U._notes_dirty=true;U._notes_last_edit=os.time()end
local function input(id,hint,buffer,size,w,flags)
    imgui.SetNextItemWidth(w or -1)
    return imgui.InputTextWithHint('##tools22_'..id,DSP.utf8(hint),buffer,size,flags or 0)
end
local function field(label,key,min,w,parent)
    parent=parent or DSP.settings
    V.muted(label)
    if M.compact_number(parent,key,'tools22_'..key,math.min(230,w),min or 0)then
        if key=='tax_bp'then parent[key]=math.min(10000,parent[key]);DSP.market.invalidate_arbitrage()end
        M.defer_save()
    end
end
local function toggle(label,parent,key,default)
    local value=parent[key];if value==nil then value=default end
    if V.text_button((value and '[x] 'or '[ ] ')..label,'tools22_toggle_'..key,-1,false)then
        parent[key]=not value;M.defer_save();return true
    end
end
local function choices(rows,key,current,select,w)
    local cell=(w-(#rows-1)*6)/#rows
    for i,e in ipairs(rows)do
        if b(e[2],key..i,cell,current==e[1])then select(e[1])end
        if i<#rows then V.inline()end
    end
end
local function statistics()
    V.text('Ñòàòèñòèêà')
    V.tools_period=V.tools_period or 'day'
    for i,p in ipairs({{'session','Ñåññèÿ'},{'day','Ñåãîäíÿ'},{'all','Âñ¸ âðåìÿ'}})do
        if b(p[2],'period_'..p[1],(width()-12)/(4-i),V.tools_period==p[1])then V.tools_period=p[1]end
        if i<3 then V.inline()end
    end
    local s=DSP.craglog.summary(V.tools_period)
    local rows={{'Äîõîäû',s.income},{'Ðàñõîäû',s.expense},{'Äåíåæíûé èòîã',s.net},
        {'Ïðèáûëü òðåéäîâ',s.trade_profit},{'Íàãðàäû: äåíüãè',s.reward_cash},
        {'Íàãðàäû: ðûíî÷íàÿ îöåíêà',s.reward_estimated},{'PayDay: íà÷èñëåíî',s.payday_income},
        {'PayDay: ñïèñàíî',s.payday_expense},{'Äðóãèå äîõîäû',s.other_income}}
    V.list('stats',function(w)
        V.muted('Ñîáûòèé: '..tostring(s.count or 0)..' · Íàãðàä áåç öåíû: '..tostring(s.unknown_items or 0))
        for i,e in ipairs(rows)do
            local x,y=imgui.GetCursorPosX(),imgui.GetCursorPosY()
            V.muted(V.fit(e[1],w*.56));V.at(x+w*.60,y)
            local amount=tonumber(e[2])or 0
            if amount<0 then V.red(DSP.money(amount))else V.text(DSP.money(amount))end
            V.at(x,y+34)
        end
        if DSP.craglog.loot_summary then
            local loot=DSP.craglog.loot_summary(V.tools_period)
            V.muted('Ïîëó÷åíî ïðåäìåòîâ: '..loot.qty..' øò. · '..#loot.items..' âèäîâ')
        end
        V.muted('Ðûíî÷íàÿ îöåíêà íàãðàä íå ïðèáàâëÿåòñÿ ê ïîëó÷åííûì äåíüãàì.')
    end,{count=s.count or 0})
end
local function note_editor()
    local note=U.note_current
    local w=width();local cell=(w-18)/4
    if b('< Âñå','note_back',cell)and M.save_notes()then U.note_current=nil;return end
    V.inline();if b('Ñîõðàíèòü','note_save',cell,false,true)then M.save_notes()end
    V.inline();if b(note.pinned and '* Ñâåðõó'or 'Çàêðåïèòü','note_pin',cell,note.pinned)then note.pinned=not note.pinned;changed()end
    V.inline();if b('Óäàëèòü','note_delete',cell)then V.note_delete=note;V.note_error=nil;V.open_popup('Óäàëèòü çàìåòêó?','note_delete')end
    V.list('note_editor',function(rw,h)
        if input('note_title','Íàçâàíèå çàìåòêè',U.note_title,256,rw)then changed()end
        local half=(rw-6)/2
        if input('note_item','Ïðåäìåò',U.note_item,256,half)then changed()end
        V.inline();if input('note_shop','Íîìåð ëàâêè',U.note_shop,64,half)then changed()end
        local shop=DSP.to_cp(ffi.string(U.note_shop))
        if shop:match('^%d+$')and b('Ìåòêà ëàâêè #'..shop,'note_mark',rw)then DSP.market.mark_shop(shop)end
        V.muted('Òåêñò çàìåòêè')
        local remaining=math.max(64,h-(shop:match('^%d+$')and 180 or 132))
        if imgui.InputTextMultiline('##tools22_note_text',U.notes_buf,8192,imgui.ImVec2(rw,remaining),0)then changed()end
    end,{footer=function()V.muted(U._notes_dirty and 'Íå ñîõðàíåíî'or 'Ñîõðàíåíî')end})
end
local function notes()
    V.text('Çàìåòêè')
    DSP.notes.all()
    if U.note_current then return note_editor()end
    if b('+ Íîâàÿ','note_new',120,false,true)then local note=DSP.notes.create();if note then DSP.notes.open(note)end;return end
    V.inline();local query=V.search('notes','Ïîèñê çàìåòêè',-1)
    local rows=V.memo('notes_rows',query..'|'..tostring(DSP.notes.revision or 0)..'|'..tostring(DSP.settings.notes),function()return DSP.notes.filtered(query)end)
    V.list_rows('notes',rows,70,function(note,i,w)
        V.row('note_'..i,70,function(rw,x,y)
            local label=(note.pinned and '* 'or '')..tostring(note.title or 'Áåç íàçâàíèÿ')
            if V.text_button(V.fit(label,rw),'tools22_note_open_'..i,rw,false)then DSP.notes.open(note)end
            V.at(x,y+44)
            local hint=(note.item or '')..(note.shop and note.shop~=''and ' · Ëàâêà #'..note.shop or '')
            V.muted(V.fit(hint~=''and hint or tostring(note.text or ''):gsub('\n',' '),rw))
        end)
    end,{count=#rows})
end
local sections={'Âèä','Òîðãîâëÿ','Äàííûå','Telegram','Èíñòðóìåíòû'}
local function appearance(w)
    V.muted('Òåìà îôîðìëåíèÿ')
    local themes={'mcr_sand','carbon_trade','ocean_blue','dark_amber','amoled','cyberpunk','purple','emerald'}
    local columns=w>700 and 3 or 2
    for i,id in ipairs(themes)do
        local theme=DSP.theme.list[id]
        if theme and b(theme.name,'theme_'..id,(w-(columns-1)*6)/columns,DSP.theme.current==id)then DSP.theme.set(id)end
        if i%columns~=0 then V.inline()end
    end
    V.muted('Ïðîçðà÷íîñòü')
    choices({{.8,'80%'},{.9,'90%'},{.97,'97%'},{1,'100%'}},'opacity',DSP.theme.opacity,DSP.theme.set_opacity,w)
    V.muted('Ðàçìåð òåêñòà')
    choices({{1,'1.0'},{1.25,'1.25'},{1.5,'1.5'}},'dpi',U.d or DSP.settings.dpi,function(value)
        U.d=value;DSP.settings.dpi=value;M.defer_save()
    end,w)
    toggle('Îöåíêà òðåéäà',DSP.settings,'overlay_trade',true)
    toggle('Îöåíêà ëàâêè',DSP.settings,'overlay_shop',true)
    toggle('Îâåðëåé ïîâåðõ îêîí',DSP.settings,'overlay_top',true)
    toggle('Carbon: ðèñîâàíèå êàðòî÷åê DrawList',DSP.settings,'carbon_draw_enabled',true)
    local c=DSP.settings.craglog
    toggle('Ïîêàçûâàòü ìèíè-æóðíàë',c,'open',false)
    if toggle('Çàêðåïèòü ìèíè-æóðíàë',c,'pinned',false)then DSP.craglog.set_pinned(c.pinned)end
    toggle('Ñâåðíóòü ìèíè-æóðíàë',c,'minimized',false)
end
local function trading(w)
    field('Êîìèññèÿ (100 áàçèñíûõ ïóíêòîâ = 1%)','tax_bp',0,w)
    field('Ìàðæà ñêóïêè (%)','margin',0,w)
    field('Ñíèæåíèå öåíû ïðîäàæè (%)','undercut',0,w)
    field('Ñêóïàòü ïî óìîë÷àíèþ (øò.)','auto_buy_qty',1,w)
    toggle('Ïðîâåðêà áåç îòïðàâêè êîìàíä',DSP.settings,'dry_run',true)
    toggle('Òîëüêî ïðèáûëüíûå ïðåäëîæåíèÿ',DSP.settings,'only_profit',false)
    toggle('Òîëüêî ëèêâèäíûå ïðåäëîæåíèÿ',DSP.settings,'liquid',false)
    V.muted('Ñîðòèðîâêà ðûíêà')
    for i,label in ipairs({'Âûãîäà','Äåøåâëå êóïèòü','Äîðîæå ïðîäàòü','Ïðîöåíò','Ïðåäëîæåíèÿ'})do
        if b(label,'sort_'..i,w,DSP.settings.sort==i)then
            DSP.settings.sort=i;DSP.market.state.filter_version=-1;U.page=1;M.defer_save()
        end
    end
    V.muted('Ñòàòèñòèêà ïî óìîë÷àíèþ')
    for _,e in ipairs({{'hour','×àñ'},{'day','Äåíü'},{'week','Íåäåëÿ'},{'month','Ìåñÿö'},{'all','Âñ¸ âðåìÿ'}})do
        if b(e[2],'stats_mode_'..e[1],w,DSP.settings.stats_mode==e[1])then DSP.settings.stats_mode=e[1];U.stat_mode=e[1];M.defer_save()end
    end
end
local function data(w)
    V.muted('Ñåðâåð ðûíêà')
    for _,server in ipairs(DSP.market.servers)do
        if b(server.name,'server_'..server.id,w,DSP.market.state.sid==server.id)then
            DSP.settings.server=server.id;U.selected=nil
            DSP.market.clear_for_server(server.id);M.defer_save();DSP.market.pull(server.id)
        end
    end
    field('Îáíîâëåíèå ðûíêà (ñåê.; àâòî ìèíèìóì 180)','refresh_seconds',180,w)
    field('Ðàçìåð ñòðàíèöû ñòàðûõ ñïèñêîâ','per_page',1,w)
    toggle('Çàïèñûâàòü íàãðàäû è òàéíèêè',DSP.settings,'log_chat_drops',true)
    local scan=DSP.market.cr_scan_state
    V.muted(V.fit('Ñêàí ìåòêè ÖÐ: '..tostring(scan.status or 'íå ñêàíèðîâàí'),w))
    if b(scan.active and 'Îñòàíîâèòü ñêàí'or 'Ñêàíèðîâàòü ìåòêó ÖÐ','scan_cr',w)then
        if scan.active then scan.active=false;scan.status='îñòàíîâëåíî'else DSP.market.scan_cr_marker()end
    end
    V.muted('Äëÿ ñêàíà îòêðîéòå äèàëîã öåí ó ìåòêè ÖÐ.')
end
local function credential(key,label,size,password,w)
    V.tools_buffers=V.tools_buffers or {}
    local buffer=V.tools_buffers[key]
    if not buffer then
        buffer=imgui.new.char[size]();local value=tostring(DSP.settings[key]or '')
        ffi.copy(buffer,value,math.min(#value,size-1));V.tools_buffers[key]=buffer
    end
    V.muted(label)
    local flags=password and imgui.InputTextFlags and imgui.InputTextFlags.Password or 0
    local id=key=='tg_bot_token'and 'tg_token'or 'tg_chat'
    if input(id,label,buffer,size,w,flags)then DSP.settings[key]=ffi.string(buffer);M.defer_save()end
end
local function telegram(w)
    toggle('Telegram-óâåäîìëåíèÿ',DSP.settings,'tg_notify',false)
    toggle('Ñâîäêà PayDay',DSP.settings,'tg_payday_enabled',false)
    credential('tg_bot_token','Bot Token',256,true,w)
    credential('tg_chat_id','Chat ID',64,false,w)
    if b('Ýêñïîðòèðîâàòü â Telegram','tg_export',w)then DSP.logs.export_logs()end
end
local function diagnostics(w)
    if b('Êàëüêóëÿòîð ñäåëêè','calculator',w)then V.set_screen('calculator')end
    if b('Ýêñïîðòèðîâàòü æóðíàë â Telegram','export',w)then DSP.logs.export_logs()end
    V.muted(V.fit('Âåðñèÿ '..tostring(DSP.version)..' · '..tostring(DSP.dir),w))
    V.muted(V.fit('API: '..tostring(DSP.market.api),w))
    for _,e in ipairs(DSP.log or {})do V.text(V.fit(tostring(e.t or '')..' '..tostring(e.text or ''),w))end
end
local function settings()
    V.tools_section=V.tools_section or 1
    local pos=math.max(1,math.min(#sections,V.tools_section))
    V.heading('Íàñòðîéêè',function()
        if b('<','section_prev',42)then pos=(pos-2)%#sections+1 end
        V.inline();if b(sections[pos]..' >','section_next',164,true)then pos=pos%#sections+1 end
    end,212)
    if pos~=V.tools_section then V.reset_list('settings')end
    V.tools_section=pos
    local views={appearance,trading,data,telegram,diagnostics}
    V.list('settings',function(w)
        if V.tools_error then V.red(V.tools_error)end
        views[pos](w)
    end,{footer=function()
        if b('Ñîõðàíèòü','save_settings',0,false,true)then
            if DSP.save_settings()then DSP.save_ui_state();V.tools_error=nil;DSP.notify('Íàñòðîéêè ñîõðàíåíû')
            else V.tools_error='Íå óäàëîñü ñîõðàíèòü íàñòðîéêè'end
        end
    end})
end
function V.tools(screen)
    if screen=='stats'then statistics()
    elseif screen=='notes'then notes()
    elseif screen=='settings'then settings()
    elseif screen=='search'then V.shops()end
end
local previous_popups=V.popups
local last_note_attempt=-math.huge
function V.popups()
    if previous_popups then previous_popups()end
    local now=os.time()
    if U._notes_dirty and now-(U._notes_last_edit or 0)>1.5 and now-last_note_attempt>1.5 then
        last_note_attempt=now;M.save_notes()
    end
    V.popup('Óäàëèòü çàìåòêó?','note_delete',function()
        local note=V.note_delete
        if not note then imgui.CloseCurrentPopup();return end
        V.text(V.fit(tostring(note.title or 'Áåç íàçâàíèÿ'),imgui.GetContentRegionAvail().x))
        V.muted('Âîññòàíîâèòü óäàë¸ííóþ çàìåòêó íåëüçÿ.')
        if V.note_error then V.red(V.note_error)end
        if b('Îòìåíà','note_delete_cancel',120)then V.note_delete=nil;imgui.CloseCurrentPopup()end
        V.inline()
        if b('Äà, óäàëèòü','note_delete_confirm',160,false,true)then
            local notes=DSP.notes.all();local index
            for i,n in ipairs(notes)do if n==note then index=i;table.remove(notes,i);break end end
            if index and DSP.save_settings()then
                if U.note_current==note then U.note_current=nil;U._notes_dirty=false end
                V.note_delete=nil;V.note_error=nil;DSP.notes.revision=(DSP.notes.revision or 0)+1;if V.cache then V.cache.notes_rows=nil end;imgui.CloseCurrentPopup()
            elseif index then
                table.insert(notes,index,note);V.note_error='Íå óäàëîñü ñîõðàíèòü. Çàìåòêà âîññòàíîâëåíà.'
            else V.note_error='Çàìåòêà óæå óäàëåíà'end
        end
    end,{w=560,h=220})
end

-- Edits live in FFI buffers until saved; a close must flush them before hiding.
local old_set_open=U.set_open
function U.set_open(value)
    if not value and U._notes_dirty and not M.save_notes() then return false end
    return old_set_open(value)
end
