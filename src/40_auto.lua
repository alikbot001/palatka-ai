-- Auto-buy / auto-sell engines: inventory scan + server dialogs.
DSP.auto = DSP.auto or {}
DSP.auto.buy_running = false
DSP.auto.sell_running = false
DSP.auto.scanning = false
DSP.auto.inv = {}
DSP.auto.inv_status = 'не сканирован'
DSP.auto.sell_confirmed = false
DSP.auto.sell_forbidden = false
DSP.auto.sell_no_slots = false
DSP.auto.status = 'готов'
DSP.auto._prev_dialog = nil

local runtime = DSP.trade_runtime
local function trade_wait(ms) runtime.pause(ms) end
local function log(s, kind) DSP.add_log(s, kind) end

function DSP.auto.status_text()
    return DSP.auto.status .. '  |  инвентарь: ' .. DSP.auto.inv_status
end

local function clean(s)
    return (tostring(s or ''):gsub('{%x+}', ''))
end

function DSP.dialog_clean(s)
    s = tostring(s or '')
    local ok, cp = pcall(function() return require('encoding').CP1251:encode(s) end)
    if ok and cp and cp ~= '' and not s:find('[\192-\255]') then s = cp end
    return clean(s)
end

local function base_name(name)
    return (tostring(name or ''):gsub('%s*%(%+%d+%)%s*$', ''))
end

local function has_qty(text)
    local t = DSP.lower and DSP.lower(text) or tostring(text):lower()
    return t:find('Количество', 1, true) ~= nil or t:find('количество', 1, true) ~= nil
        or t:find('кол-во', 1, true) ~= nil or t:find('кол во', 1, true) ~= nil
        or t:find('quantity', 1, true) ~= nil or t:find('запятую', 1, true) ~= nil
        or t:find('Пример:', 1, true) ~= nil or t:find('пример:', 1, true) ~= nil
        or t:find('%d+%s*,%s*%d+') ~= nil
end

local function close_dialog()
    if sampIsDialogActive() then
        sampSendDialogResponse(sampGetCurrentDialogId(), 0, 0, '')
        for _ = 1, 14 do
            if not sampIsDialogActive() then break end
            trade_wait(25)
        end
    end
end

local function wait_dialog(ids, ms)
    for _ = 1, math.ceil((ms or 2000) / 30) do
        trade_wait(30)
        if sampIsDialogActive() then
            local id = sampGetCurrentDialogId()
            if not ids then return id end
            for _, want in ipairs(ids) do
                if id == want then return id end
            end
        end
    end
    return nil
end

local function wait_text(id, ms)
    local prev, stable = '', 0
    for _ = 1, math.ceil((ms or 800) / 30) do
        trade_wait(30)
        if not sampIsDialogActive() or sampGetCurrentDialogId() ~= id then
            return prev
        end
        local cur = sampGetDialogText() or ''
        if cur ~= '' then
            if cur == prev then
                stable = stable + 1
                if stable >= 2 then return cur end
            else
                stable = 0
            end
            prev = cur
        end
    end
    return prev
end

function _G.dsp_click_slot(interfaceid, id, subid, json_str)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 63)
    raknetBitStreamWriteInt8(bs, interfaceid)
    raknetBitStreamWriteInt32(bs, id)
    raknetBitStreamWriteInt32(bs, subid)
    raknetBitStreamWriteInt16(bs, #json_str)
    raknetBitStreamWriteString(bs, json_str)
    raknetSendBitStreamEx(bs, 1, 7, 1)
    raknetDeleteBitStream(bs)
end

-- A matching ID alone is not enough: MonetLoader may expose a previous dialog's
-- text while the server is replacing it. Confirm both the active ID and the
-- stabilized title/body before submitting any values.
local function wait_trade_item_dialog(ids, item_name, timeout)
    local elapsed=0
    local wanted=base_name(item_name)
    local observed=''
    while elapsed<(timeout or 3200) do
        trade_wait(40); elapsed=elapsed+40
        if sampIsDialogActive() then
            local id=sampGetCurrentDialogId()
            local allowed=false
            for _,x in ipairs(ids) do if x==id then allowed=true;break end end
            if allowed then
                local txt=DSP.dialog_clean(sampGetDialogText() or '')
                if txt~='' then
                    observed=txt
                    if DSP.trade_runtime.matches(txt,wanted) then
                        local stable=DSP.dialog_clean(wait_text(id,360))
                        if sampIsDialogActive() and sampGetCurrentDialogId()==id
                            and DSP.trade_runtime.matches(stable,wanted) then
                            return id,stable
                        end
                    end
                end
            end
        end
    end
    return nil,observed
end

local function parse_inventory(text)
    local raw = {}
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        local clean_line = clean(line)
        local slot_s, name, cnt_s
        slot_s, name, cnt_s = clean_line:match('%[(%d+)%]%s+(.-)%s+%{[^}]*%}%[(%d+)%s+')
        if not slot_s then
            slot_s, name, cnt_s = clean_line:match('%[(%d+)%]%s+(.-)%s+%[(%d+)%s+')
        end
        if not slot_s then
            slot_s, name, cnt_s = clean_line:match('%[(%d+)%]%s+(.-)%s+%[(%d+)%]')
        end
        if slot_s and name and cnt_s then
            name = name:match('^%s*(.-)%s*$') or name
            if name ~= '' and name ~= 'Пусто' then
                table.insert(raw, { slot = tonumber(slot_s), name = name, count = tonumber(cnt_s) or 1 })
            end
        end
    end
    local grouped, by_name = {}, {}
    for _, it in ipairs(raw) do
        local g = by_name[it.name]
        if not g then
            g = { name = it.name, count = 0, stacks = {} }
            by_name[it.name] = g
            table.insert(grouped, g)
        end
        g.count = g.count + it.count
        table.insert(g.stacks, { slot = it.slot, count = it.count })
    end
    return grouped
end

function DSP.auto.scan_inventory()
    if DSP.auto.scanning or DSP.auto.buy_running or DSP.auto.sell_running then return false end
    DSP.auto.scanning = true
    DSP.auto.scan_generation = (DSP.auto.scan_generation or 0) + 1
    local generation = DSP.auto.scan_generation
    DSP.auto.inv = {}
    DSP.auto.inv_status = 'сканирование...'
    log('Инвентарь: открываю /mm...')
    sampSendChat('/mm')
    lua_thread.create(function()
        for _ = 1, 500 do
            if not DSP.auto.scanning or generation ~= DSP.auto.scan_generation then return end
            trade_wait(50)
        end
        if DSP.auto.scanning and generation == DSP.auto.scan_generation then
            DSP.auto.scanning = false
            DSP.auto.inv_status = 'таймаут'
            log('Инвентарь: таймаут. Откройте инвентарь через /mm вручную и повторите.', 'error')
        end
    end)
end

local function inventory_dialog(id, text)
    if id == 25494 or id == 25493 then return true end
    local t = clean(text)
    return (t:find('%[%d+%]') ~= nil and (t:find('%[%d+ шт%]') ~= nil or t:find('Инвентарь:') ~= nil))
        or t:find('Следующая страница', 1, true) ~= nil
        or t:find('Предыдущая страница', 1, true) ~= nil
end

function DSP.auto.on_dialog(id, style, title, b1, b2, text)
    if DSP.market then
        if id == 15073 and DSP.market.mark_cr_dialog then DSP.market.mark_cr_dialog() end
        if DSP.market.observe_cr_detail then
            local ok,err=pcall(DSP.market.observe_cr_detail,title,text)
            if not ok then log('ЦР: ошибка разбора истории: '..tostring(err),'error') end
        end
    end
    -- v1.2 Stage 3 hotfix: CR marker scan (dialog 15073).
    -- When scan_cr_marker() has armed the scan state, intercept dialog 15073
    -- and let the market module parse + flip pages.
    if id == 15073 and DSP.market and DSP.market.cr_scan_state and DSP.market.cr_scan_state.active and DSP.market.on_cr_marker_dialog then
        pcall(DSP.market.on_cr_marker_dialog, text)
        return true  -- intercept: don't let other handlers close it
    end
    if DSP.auto.scanning then
        local generation = DSP.auto.scan_generation
        if id == 722 or id == 600 or id == 235 then
            lua_thread.create(function()
                trade_wait(120)
                if not DSP.auto.scanning or generation ~= DSP.auto.scan_generation then return end
                sampSendDialogResponse(id, 1, 0, '')
            end)
            return true
        end
        if inventory_dialog(id, text) then
            local items = parse_inventory(text)
            local slots = {}
            for _, old in ipairs(DSP.auto.inv) do
                for _, st in ipairs(old.stacks) do slots[st.slot] = true end
            end
            for _, it in ipairs(items) do
                local group
                for _, old in ipairs(DSP.auto.inv) do if old.name == it.name then group = old end end
                for _, st in ipairs(it.stacks) do
                    if not slots[st.slot] then
                        if not group then
                            group = {name = it.name, count = 0, stacks = {}}
                            table.insert(DSP.auto.inv, group)
                        end
                        group.count = group.count + st.count
                        table.insert(group.stacks, st)
                        slots[st.slot] = true
                    end
                end
            end
            DSP.auto.inv_status = #DSP.auto.inv .. ' поз. (' ..
                (function() local n = 0; for _, x in ipairs(DSP.auto.inv) do n = n + x.count end; return n end)() .. ' шт)'
            local next_idx
            local line_no = 0
            local header = style == 5 and 1 or 0
            for ln in tostring(text or ''):gmatch('[^\n]+') do
                line_no = line_no + 1
                if line_no > 1 and ln:find('Следующая страница', 1, true) then
                    next_idx = line_no - 1 - header
                    break
                end
            end
            if next_idx then
                log('Инвентарь: ' .. DSP.auto.inv_status .. ', дальше...')
                lua_thread.create(function()
                    trade_wait(140)
                    if not DSP.auto.scanning or generation ~= DSP.auto.scan_generation then return end
                    sampSendDialogResponse(id, 1, next_idx, '')
                end)
            else
                DSP.auto.scanning = false
                log('Инвентарь готов: ' .. DSP.auto.inv_status, 'ok')
                lua_thread.create(function()
                    trade_wait(100)
                    if generation ~= DSP.auto.scan_generation or DSP.auto.buy_running or DSP.auto.sell_running then return end
                    sampSendDialogResponse(id, 0, 0, '')
                    trade_wait(160)
                    if generation ~= DSP.auto.scan_generation or DSP.auto.buy_running or DSP.auto.sell_running then return end
                    _G.dsp_click_slot(52, -1, 4, '""')
                end)
            end
            return true
        end
    end
    DSP.auto.on_trade_feedback(text)
    return false
end

-- Arizona confirms shop listings through a SERVER CHAT message, not always
-- another dialog. A dialog-only acknowledgement made every real sale time out.
-- Never treat a generic chat message as a sale confirmation.
function DSP.auto.on_trade_feedback(text)
    if not DSP.auto.sell_running then return end
    local t=clean(text)
    if t:find('успешно выставлен на продажу',1,true)
        or t:find('Успешно выставлено на продажу',1,true)
        or t:find('Успешно выставлен на продажу',1,true) then
        DSP.auto.sell_confirmed=true
    elseif t:find('Данные товары запрещено продавать',1,true)
        or t:find('нельзя выставлять',1,true)
        or t:find('Запрещено',1,true) then
        DSP.auto.sell_forbidden=true;DSP.auto.sell_confirmed=true
    elseif t:find('нет доступных ячеек',1,true)
        or t:find('Нет доступных ячеек',1,true)
        or t:find('нет свободных мест',1,true)
        or t:find('Нет свободных мест',1,true) then
        DSP.auto.sell_no_slots=true;DSP.auto.sell_confirmed=true
    end
end

function DSP.auto.install()
    local ok, sampev = pcall(require, 'samp.events')
    if not ok or not sampev then
        log('Авто: samp.events недоступен', 'error')
        return
    end
    local prev_server=sampev.onServerMessage
    sampev.onServerMessage=function(color,text)
        if DSP.auto.on_trade_feedback then
            local safe,err=pcall(DSP.auto.on_trade_feedback,text)
            if not safe then log('Торговля: ошибка обработки ответа: '..tostring(err),'error') end
        end
        if prev_server then return prev_server(color,text) end
    end
    DSP.auto._prev_dialog = sampev.onShowDialog
    sampev.onShowDialog = function(id, style, title, b1, b2, text)
        local prev = DSP.auto._prev_dialog
        local ret
        if prev then
            local r = { pcall(prev, id, style, title, b1, b2, text) }
            if r[1] then ret = r[2] end
        end
        local intercept = DSP.auto.on_dialog(id, style, title, b1, b2, text)
        if intercept then return false end
        return ret
    end
end

DSP.auto.helpers = {close_dialog = close_dialog, wait_dialog = wait_dialog, wait_text = wait_text,
    clean = clean, base_name = base_name, has_qty = has_qty,
    wait_trade_item_dialog = wait_trade_item_dialog}
