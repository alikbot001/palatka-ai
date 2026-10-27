-- Separate notes remain searchable and retain optional market references.
local ffi=require('ffi')
local M=DSP.mobile
local U=DSP.ui
DSP.notes={}
local N=DSP.notes
local function save()
    if not DSP.save_settings() then
        U._notes_dirty=true
        DSP.notify('Не удалось сохранить заметки. Повторите сохранение.')
        return false
    end
    U._notes_dirty=false
    if DSP.notes then DSP.notes.revision=(DSP.notes.revision or 0)+1 end
    return true
end
function N.all()
    if type(DSP.settings.notes)~='table' then
        DSP.settings.notes={}
        local legacy=U.notes_buf and DSP.to_cp(ffi.string(U.notes_buf)) or ''
        if legacy~='' then
            DSP.settings.notes[1]={id='legacy',title='Мои заметки',text=legacy,pinned=false,updated_at=os.time()}
        end
        save()
    end
    return DSP.settings.notes
end
function N.filtered(query)
    local rows={}
    local q=DSP.lower(DSP.trim(query or ''))
    for _,note in ipairs(N.all()) do
        local text=table.concat({note.title or '',note.text or '',note.item or '',note.shop or ''},' ')
        if q=='' or DSP.lower(text):find(q,1,true) then rows[#rows+1]=note end
    end
    table.sort(rows,function(a,b)
        if (a.pinned and true or false)~=(b.pinned and true or false) then return a.pinned and true or false end
        if (a.updated_at or 0)~=(b.updated_at or 0) then return (a.updated_at or 0)>(b.updated_at or 0) end
        return tostring(a.id)<tostring(b.id)
    end)
    return rows
end
function N.create(title)
    local notes=N.all()
    local note={id=tostring(os.time())..'_'..tostring(#notes+1),title=title or 'Новая заметка',text='',updated_at=os.time()}
    notes[#notes+1]=note
    if not save() then table.remove(notes,#notes);return nil end
    return note
end
local function buffer(value,size)
    local b=imgui.new.char[size]()
    local text=DSP.to_u8(value or '')
    ffi.copy(b,text,math.min(#text,size-1))
    return b
end
function N.open(note)
    if U._notes_dirty and not M.save_notes() then return false end
    U.note_current=note
    U.note_title=buffer(note.title,256)
    U.note_item=buffer(note.item,256)
    U.note_shop=buffer(note.shop,64)
    U.notes_buf=buffer(note.text,8192)
    U.note_delete=false
    U.note_delete_pending=false
    return true
end
function M.save_notes()
    local note=U.note_current
    if note then
        note.title=DSP.to_cp(ffi.string(U.note_title))
        note.text=DSP.to_cp(ffi.string(U.notes_buf))
        note.item=DSP.to_cp(ffi.string(U.note_item))
        note.shop=DSP.to_cp(ffi.string(U.note_shop))
        note.updated_at=os.time()
    end
    return save()
end
local function changed()
    U._notes_dirty=true; U._notes_last_edit=os.time()
end
function U.notes_tab()
    M.title('ЗАМЕТКИ')
    N.all()
    U.note_search=U.note_search or buffer('',256)
    if U.note_current then
        local note=U.note_current
        if M.button('< Все заметки','notes_back',300) then
            if M.save_notes() then U.note_current=nil end
        end
        M.inline()
        if M.button('Сохранить','notes_save',300) then M.save_notes() end
        M.text(U._notes_dirty and 'Есть несохранённые изменения' or 'Сохранено')
        M.text('Название')
        imgui.SetNextItemWidth(math.min(900,imgui.GetContentRegionAvail().x))
        if imgui.InputText('##note_title',U.note_title,256) then changed() end
        if M.toggle('Закрепить в начале списка',note,'pinned',false) then changed() end
        M.text('Предмет (необязательно)')
        imgui.SetNextItemWidth(600)
        if imgui.InputText('##note_item',U.note_item,256) then changed() end
        M.text('Номер лавки (необязательно)')
        imgui.SetNextItemWidth(300)
        if imgui.InputText('##note_shop',U.note_shop,64) then changed() end
        if note.shop and note.shop:match('^%d+$') and M.button('Найти лавку #'..note.shop,'note_mark',380) then DSP.market.mark_shop(note.shop) end
        M.text('Текст заметки')
        if imgui.InputTextMultiline('##mobile_note_text',U.notes_buf,8192,imgui.ImVec2(-1,280),0) then changed() end
        local popup_id=DSP.utf8('Удалить заметку?')..'##note_delete_modal'
        if M.button('Удалить заметку','note_delete',350) then
            U.note_delete_pending=true
            if imgui.OpenPopup then imgui.OpenPopup(popup_id) end
        end
        -- Proper modal, not a red confirmation block hidden below the form.
        if imgui.GetIO and imgui.SetNextWindowPos and imgui.Cond and imgui.ImVec2 then
            local io=imgui.GetIO()
            if io and io.DisplaySize then
                imgui.SetNextWindowPos(imgui.ImVec2(io.DisplaySize.x*.5,io.DisplaySize.y*.5),
                    imgui.Cond.Appearing,imgui.ImVec2(.5,.5))
            end
        end
        if imgui.BeginPopupModal and imgui.BeginPopupModal(popup_id,nil,
            imgui.WindowFlags and imgui.WindowFlags.AlwaysAutoResize or 0) then
            M.title('Удалить заметку?')
            M.text('"'..tostring(note.title or '')..'" будет удалена безвозвратно.')
            if M.button('Отмена','note_cancel_modal',190) then
                U.note_delete_pending=false
                if imgui.CloseCurrentPopup then imgui.CloseCurrentPopup() end
            end
            M.inline()
            if M.button('Да, удалить','note_delete_confirm',220) then
                local old_index
                for i,v in ipairs(N.all()) do if v==note then old_index=i;table.remove(DSP.settings.notes,i);break end end
                if save() then
                    U.note_current=nil;U.note_delete_pending=false
                elseif old_index then
                    table.insert(DSP.settings.notes,old_index,note)
                end
                if imgui.CloseCurrentPopup then imgui.CloseCurrentPopup() end
            end
            imgui.EndPopup()
        end
        return
    end
    imgui.SetNextItemWidth(math.min(850,imgui.GetContentRegionAvail().x))
    imgui.InputTextWithHint('##notes_search',DSP.utf8('Поиск по названию, тексту, предмету и лавке'),U.note_search,256)
    if M.button('+ Новая заметка','notes_create',400) then N.open(N.create()) end
    local notes=N.filtered(DSP.to_cp(ffi.string(U.note_search)))
    M.text('Заметок: '..#notes)
    for i,note in ipairs(notes) do
        M.text((note.pinned and '[*] ' or '')..tostring(note.title))
        if note.item and note.item~='' then M.text('Предмет: '..note.item) end
        if note.shop and note.shop~='' then M.text('Лавка #'..note.shop) end
        if M.button('Открыть','note_open'..i,300) then N.open(note) end
        imgui.Separator()
    end
end
