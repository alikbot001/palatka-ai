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
    return tostring(text or ''):find('Количество', 1, true) ~= nil
end

local function close_dialog()
    if sampIsDialogActive() then
        pcall(sampSendDialogResponse, sampGetCurrentDialogId(), 0, 0, '')
        local t = os.clock() + 0.35
        while os.clock() < t and sampIsDialogActive() do wait(25) end
    end
end

local function wait_dialog(ids, ms)
    local t = os.clock() + (ms or 2000) / 1000
    while os.clock() < t do
        wait(30)
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
    local t = os.clock() + (ms or 800) / 1000
    local prev, stable = '', 0
    while os.clock() < t do
        wait(30)
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
    if DSP.auto.scanning then return end
    DSP.auto.scanning = true
    DSP.auto.inv = {}
    DSP.auto.inv_status = 'сканирование...'
    log('Инвентарь: открываю /mm...')
    sampSendChat('/mm')
    lua_thread.create(function()
        local deadline = os.clock() + 25
        while DSP.auto.scanning and os.clock() < deadline do wait(50) end
        if DSP.auto.scanning then
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
    if DSP.auto.scanning then
        if id == 722 or id == 600 or id == 235 then
            lua_thread.create(function()
                wait(120)
                pcall(sampSendDialogResponse, id, 1, 0, '')
            end)
            return true
        end
        if inventory_dialog(id, text) then
            local items = parse_inventory(text)
            for _, it in ipairs(items) do
                local found = false
                for _, old in ipairs(DSP.auto.inv) do
                    if old.name == it.name then
                        old.count = old.count + it.count
                        for _, st in ipairs(it.stacks) do table.insert(old.stacks, st) end
                        found = true
                        break
                    end
                end
                if not found then table.insert(DSP.auto.inv, it) end
            end
            DSP.auto.inv_status = #DSP.auto.inv .. ' поз. (' ..
                (function() local n = 0; for _, x in ipairs(DSP.auto.inv) do n = n + x.count end; return n end)() .. ' шт)'
            local next_idx
            local line_no = 0
            for ln in tostring(text or ''):gmatch('[^\n]+') do
                line_no = line_no + 1
                if line_no > 1 and ln:find('Следующая страница', 1, true) then
                    next_idx = line_no - 2
                    break
                end
            end
            if next_idx then
                log('Инвентарь: ' .. DSP.auto.inv_status .. ', дальше...')
                lua_thread.create(function()
                    wait(140)
                    pcall(sampSendDialogResponse, id, 1, next_idx, '')
                end)
            else
                DSP.auto.scanning = false
                log('Инвентарь готов: ' .. DSP.auto.inv_status, 'ok')
                lua_thread.create(function()
                    wait(100)
                    pcall(sampSendDialogResponse, id, 0, 0, '')
                    wait(160)
                    pcall(_G.dsp_click_slot, 52, -1, 4, '""')
                end)
            end
            return true
        end
    end
    if DSP.auto.sell_running then
        local t = clean(text)
        if t:find('Успешно выставлено на продажу', 1, true) then
            DSP.auto.sell_confirmed = true
        end
        if t:find('нельзя выставлять', 1, true) or t:find('Запрещено', 1, true) then
            DSP.auto.sell_forbidden = true
            DSP.auto.sell_confirmed = true
        end
        if t:find('нет свободных мест', 1, true) or t:find('Нет свободных мест', 1, true) then
            DSP.auto.sell_no_slots = true
            DSP.auto.sell_confirmed = true
        end
    end
    return false
end

function DSP.auto.install()
    local ok, sampev = pcall(require, 'samp.events')
    if not ok or not sampev then
        log('Авто: samp.events недоступен', 'error')
        return
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

local function queue_sell()
    local queue = {}
    for _, p in ipairs(DSP.settings.sell_preset.items) do
        if p.enabled ~= false and (tonumber(p.price) or 0) > 0 then
            local target = base_name(p.name)
            local left = tonumber(p.qty) or 1
            for _, inv in ipairs(DSP.auto.inv) do
                if inv.name == target or inv.name == p.name then
                    for _, st in ipairs(inv.stacks) do
                        if left <= 0 then break end
                        local take = math.min(st.count, left)
                        if take > 0 then
                            table.insert(queue, {
                                name = p.name, base = target, price = p.price,
                                qty = take, slot = st.slot,
                            })
                            left = left - take
                        end
                    end
                    break
                end
            end
        end
    end
    return queue
end

function DSP.auto.start_sell()
    if DSP.auto.sell_running then return end
    if DSP.auto.buy_running then return end
    local items = DSP.settings.sell_preset.items
    local n = 0
    for _, it in ipairs(items) do if it.enabled ~= false then n = n + 1 end end
    if n == 0 then DSP.notify('Продажа: пресет пуст'); return end
    if #DSP.auto.inv == 0 then
        DSP.notify('Продажа: сначала просканируйте инвентарь')
        return
    end
    local queue = queue_sell()
    if #queue == 0 then DSP.notify('Продажа: в инвентаре нет позиций из пресета'); return end
    DSP.auto.sell_running = true
    DSP.auto.sell_confirmed = false
    DSP.auto.sell_forbidden = false
    DSP.auto.sell_no_slots = false
    DSP.auto.status = 'продажа...'
    log('Продажа: ' .. #queue .. ' стек(ов)')
    lua_thread.create(function()
        local done = 0
        for _, it in ipairs(queue) do
            if not DSP.auto.sell_running then break end
            DSP.auto.status = 'продажа: ' .. it.name .. ' (' .. done .. '/' .. #queue .. ')'
            local json = '{"amount":' .. it.qty .. ',"id":0,"slot":' .. it.slot .. ',"type":1}'
            local got = false
            for attempt = 1, 3 do
                close_dialog()
                DSP.auto.sell_confirmed = false
                pcall(_G.dsp_click_slot, 60, -1, 2, json)
                local id = wait_dialog({ 26547 }, 1800)
                if id then
                    local txt = DSP.dialog_clean(wait_text(id, 700))
                    local base = base_name(it.base)
                    if txt:find(base, 1, true) then
                        got = true
                        break
                    end
                    log('Продажа: диалог не тот (' .. tostring(attempt) .. '): ' .. txt:sub(1, 60), 'error')
                    close_dialog()
                end
                wait(180)
            end
            if got then
                local txt = DSP.dialog_clean(sampGetDialogText() or '')
                local resp = has_qty(txt) and (tostring(it.qty) .. ',' .. tostring(it.price))
                    or tostring(it.price)
                if DSP.settings.dry_run then
                    log('dry-run: продал бы ' .. it.name .. ' x' .. it.qty .. ' @ ' .. DSP.money(it.price))
                    close_dialog()
                else
                    DSP.auto.sell_confirmed = false
                    pcall(sampSendDialogResponse, 26547, 1, 0, resp)
                    local t = os.clock() + 4
                    while not DSP.auto.sell_confirmed and os.clock() < t do wait(40) end
                    pcall(sampSendDialogResponse, 26547, 0, 0, '')
                    if DSP.auto.sell_no_slots then
                        log('Продажа: нет свободных мест', 'error')
                        DSP.auto.sell_running = false
                        break
                    end
                    if DSP.auto.sell_forbidden then
                        log('Продажа: запрещено для ' .. it.name, 'error')
                    elseif DSP.auto.sell_confirmed then
                        done = done + 1
                        log('Продано: ' .. it.name .. ' x' .. it.qty .. ' @ ' .. DSP.money(it.price), 'ok')
                    else
                        log('Продажа: нет подтверждения для ' .. it.name, 'error')
                    end
                end
                wait(260)
            else
                log('Продажа: не открылся диалог для ' .. it.name .. ' (slot ' .. it.slot .. ')', 'error')
                close_dialog()
            end
        end
        DSP.auto.sell_running = false
        DSP.auto.status = 'продажа: ' .. done .. '/' .. #queue
        log('Продажа завершена: ' .. done .. '/' .. #queue, 'ok')
        DSP.auto.scan_inventory()
    end)
end

function DSP.auto.stop_sell()
    DSP.auto.sell_running = false
    DSP.auto.status = 'продажа остановлена'
    close_dialog()
    log('Продажа остановлена')
end

local function find_list_index(text, name)
    local want = base_name(name):lower()
    local idx = 0
    for line in tostring(text or ''):gmatch('[^\n]+') do
        local nm = clean(line):match('^%d+[%.%)%s]+(.-)%s*$')
            or clean(line):match('^%s*(.-)%s*$')
        if nm and nm:lower():find(want, 1, true) then return idx end
        idx = idx + 1
    end
    local first = want:match('^(%S+)')
    if first and #first >= 4 then
        idx = 0
        for line in tostring(text or ''):gmatch('[^\n]+') do
            if clean(line):lower():find(first, 1, true) then return idx end
            idx = idx + 1
        end
    end
    return nil
end

local function open_shop_menu()
    close_dialog()
    pcall(_G.dsp_click_slot, 8, 7, -1, '')
    return wait_dialog({ 3040 }, 2500) ~= nil
end

local function buy_one(it, pi, total)
    DSP.auto.status = 'скупка: ' .. it.name .. ' (' .. pi .. '/' .. total .. ')'
    if not sampIsDialogActive() or sampGetCurrentDialogId() ~= 3040 then
        if not open_shop_menu() then
            log('Скупка: меню не открылось для ' .. it.name, 'error')
            return false
        end
    end
    wait_text(3040, 350)
    pcall(sampSendDialogResponse, 3040, 1, 2, '')
    local id = wait_dialog({ 25663 }, 3000)
    if not id then
        log('Скупка: строка поиска не открылась', 'error')
        return false
    end
    wait_text(25663, 700)
    local search = base_name(it.name):sub(1, 24)
    pcall(sampSendDialogResponse, 25663, 1, 0, search)
    id = wait_dialog({ 25664 }, 3500)
    if not id then
        log('Скупка: результаты не открылись: ' .. it.name, 'error')
        return false
    end
    local list_text = DSP.dialog_clean(wait_text(25664, 500))
    local idx = find_list_index(list_text, it.name)
    if not idx then
        log('Скупка: не найдено: ' .. it.name, 'error')
        close_dialog()
        return false
    end
    pcall(sampSendDialogResponse, 25664, 1, idx, '')
    id = wait_dialog({ 26560, 26563 }, 3000)
    if not id then
        log('Скупка: диалог цены не открылся: ' .. it.name, 'error')
        return false
    end
    if id == 26560 then
        pcall(sampSendDialogResponse, id, 1, 0, '')
        id = wait_dialog({ 26563 }, 2000)
    end
    if id ~= 26563 then return false end
    wait_text(26563, 500)
    local txt = DSP.dialog_clean(sampGetDialogText() or '')
    local base = base_name(it.name)
    if not txt:find(base, 1, true) then
        local first = base:lower():match('^(%S+)')
        if not (first and #first >= 4 and txt:lower():find(first, 1, true)) then
            log('Скупка: в диалоге другой товар: ' .. it.name, 'error')
            close_dialog()
            return false
        end
    end
    local qty = tonumber(it.qty) or 1
    if qty < 1 then qty = 1 end
    local resp = has_qty(txt) and (tostring(qty) .. ',' .. tostring(it.price))
        or tostring(it.price)
    if DSP.settings.dry_run then
        log('dry-run: купил бы ' .. it.name .. ' x' .. qty .. ' @ ' .. DSP.money(it.price))
        close_dialog()
        return 'dry'
    end
    pcall(sampSendDialogResponse, 26563, 1, 0, resp)
    log('Скупка: ' .. it.name .. ' x' .. qty .. ' @ ' .. DSP.money(it.price), 'ok')
    local t = os.clock() + 0.7
    while os.clock() < t and sampIsDialogActive() do wait(30) end
    return 'bought'
end

function DSP.auto.start_buy()
    if DSP.auto.buy_running then return end
    if DSP.auto.sell_running then return end
    local list = {}
    for _, it in ipairs(DSP.settings.buy_preset.items) do
        if it.enabled ~= false and (tonumber(it.price) or 0) > 0 then table.insert(list, it) end
    end
    if #list == 0 then DSP.notify('Скупка: пресет пуст или цены 0'); return end
    DSP.auto.buy_running = true
    DSP.auto.status = 'скупка...'
    log('Скупка: ' .. #list .. ' позиций' .. (DSP.settings.dry_run and ' (dry-run)' or ''))
    lua_thread.create(function()
        if not open_shop_menu() then
            log('Скупка: лавка не открылась. Подойдите к лавке.', 'error')
            DSP.auto.buy_running = false
            DSP.auto.status = 'скупка: ошибка'
            return
        end
        local bought, dry = 0, 0
        for pi, it in ipairs(list) do
            if not DSP.auto.buy_running then break end
            local ok = buy_one(it, pi, #list)
            if ok == 'bought' then bought = bought + 1
            elseif ok == 'dry' then dry = dry + 1 end
            close_dialog()
            if pi < #list and DSP.auto.buy_running then
                if not open_shop_menu() then break end
            end
        end
        DSP.auto.buy_running = false
        DSP.auto.status = 'скупка: ' .. bought .. '/' .. #list .. (dry > 0 and (' (dry ' .. dry .. ')') or '')
        log('Скупка завершена: ' .. bought .. '/' .. #list, 'ok')
    end)
end

function DSP.auto.stop_buy()
    DSP.auto.buy_running = false
    DSP.auto.status = 'скупка остановлена'
    close_dialog()
    log('Скупка остановлена')
end
