-- Auto listing orchestration, separate from inventory and dialog observation.
local runtime = DSP.trade_runtime
local trade_wait = runtime.pause
local log = DSP.add_log
local h = DSP.auto.helpers
local close_dialog, wait_dialog, wait_text = h.close_dialog, h.wait_dialog, h.wait_text
local clean, base_name, has_qty = h.clean, h.base_name, h.has_qty
local wait_item = h.wait_trade_item_dialog
-- Search results may carry a line number, price/count columns and colour tags.
-- Match the complete normalized item name; do not pick an unrelated first-word hit.
local function find_list_index(text, name)
    local idx=0
    local fold=DSP.lower or string.lower
    local wanted=fold(base_name(name)):match('^%s*(.-)%s*$')
    local found=nil
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        local nm=clean(line):gsub('^%s*%d+[%.%)]%s*',''):match('^%s*(.-)%s*$')
        nm=(nm:match('^(.-)\t') or nm):match('^%s*(.-)%s*$')
        -- Some builds put quantity in square brackets after the item name.
        local base=nm:match('^(.-)%s+%[%d+[^%]]*%]') or nm
        base=fold(base_name(base)):match('^%s*(.-)%s*$')
        if base==wanted then
            if found~=nil then return nil,'несколько одинаковых строк' end
            found=idx
        end
        idx=idx+1
    end
    return found
end

local function open_shop_menu()
    close_dialog()
    _G.dsp_click_slot(8, 7, -1, '')
    -- v1.2 hotfix: accept 15072/15073 fallback for shop menu open in newer Arizona Mobile.
    return wait_dialog({ 3040, 15072 }, 2500)
end

local function buy_one(it, pi, total, dry_run)
    DSP.auto.status = 'скупка: ' .. it.name .. ' (' .. pi .. '/' .. total .. ')'
    if not sampIsDialogActive() or (sampGetCurrentDialogId() ~= 3040 and sampGetCurrentDialogId()~=15072) then
        if not open_shop_menu() then
            log('Скупка: меню не открылось для ' .. it.name, 'error')
            return false
        end
    end
    local menu_id = sampGetCurrentDialogId()
    wait_text(menu_id, 350)
    sampSendDialogResponse(menu_id, 1, 2, '')
    -- v1.2 hotfix: also accept 15065-15067 (newer search/dialog IDs).
    local id = wait_dialog({ 25663, 15065, 15066, 15067 }, 3000)
    if not id then
        log('Скупка: строка поиска не открылась', 'error')
        return false
    end
    wait_text(id, 700)
    local search = base_name(it.name):sub(1, 24)
    sampSendDialogResponse(id, 1, 0, search)
    -- v1.2 hotfix: search results dialog may also be 15068 in newer versions.
    id = wait_dialog({ 25664, 15068 }, 3500)
    if not id then
        log('Скупка: результаты не открылись: ' .. it.name, 'error')
        return false
    end
    local list_text = DSP.dialog_clean(wait_text(id, 500))
    local idx,index_err = find_list_index(list_text, it.name)
    if idx==nil then
        log('Скупка: '..tostring(index_err or 'не найдено')..': ' .. it.name, 'error')
        close_dialog()
        return false
    end
    sampSendDialogResponse(id, 1, idx, '')
    -- v1.2 hotfix: выставление price dialog may also use 15070/15071 in newer Arizona Mobile.
    id = wait_dialog({ 26560, 26563, 15070, 15071 }, 3000)
    if not id then
        log('Скупка: диалог цены не открылся: ' .. it.name, 'error')
        return false
    end
    if id == 26560 then
        sampSendDialogResponse(id, 1, 0, '')
        -- v1.2 hotfix: also accept 15071 fallback.
        id = wait_dialog({ 26563, 15071 }, 2000)
    end
    -- v1.2 hotfix: accept 15071 as alternative to 26563 for the final выставление dialog.
    if id ~= 26563 and id ~= 15071 then return false end
    local validated_id,txt=wait_item({id},it.name,1300)
    local base = base_name(it.name)
    if not validated_id then
        log('Скупка: в диалоге другой товар: ' .. it.name, 'error')
        close_dialog()
        return false
    end
    local qty = tonumber(it.qty) or 1
    if qty < 1 then qty = 1 end
    if not has_qty(txt) and qty>1 then
        log('Скупка: сервер не предлагает поле количества; лимит будет добавлен по одной штуке','error')
        qty=1
    end
    local resp = has_qty(txt) and (tostring(qty) .. ',' .. tostring(it.price))
        or tostring(it.price)
    if dry_run then
        log('dry-run: купил бы ' .. it.name .. ' x' .. qty .. ' @ ' .. DSP.money(it.price))
        close_dialog()
        return 'dry', tonumber(it.qty) or 1
    end
    -- v1.2 hotfix: use the active dialog id (may be 26563 or 15071 in newer
    -- Arizona Mobile выставление dialogs). Fallback chain via sampGetCurrentDialogId.
    local resp_id = id or (sampGetCurrentDialogId and sampGetCurrentDialogId()) or 26563
    sampSendDialogResponse(resp_id, 1, 0, resp)
    log('Скупка: ' .. it.name .. ' x' .. qty .. ' @ ' .. DSP.money(it.price), 'ok')
    for _ = 1, 24 do
        if not sampIsDialogActive() then return 'bought', qty end
        trade_wait(30)
    end
    log('Скупка: нет подтверждения закрытия диалога', 'error')
    return false
end

function DSP.auto.start_buy()
    if DSP.auto.buy_running or DSP.auto.scanning then return false end
    if DSP.auto.sell_running or DSP.auto.scanning then return false end
    local list = {}
    for _, it in ipairs(DSP.settings.buy_preset.items) do
        if it.enabled ~= false and runtime.positive(it.price) and runtime.positive(it.qty or 1) then
            list[#list+1] = {name=it.name,price=tonumber(it.price),qty=tonumber(it.qty) or 1}
        end
    end
    if #list == 0 then DSP.notify('Скупка: пресет пуст или цены 0'); return end
    local dry_run = DSP.settings.dry_run
    DSP.auto.buy_running = true
    DSP.auto.status = 'скупка...'
    log('Скупка: ' .. #list .. ' позиций' .. (dry_run and ' (dry-run)' or ''))
    runtime.spawn('buy', function()
        DSP.auto.progress.total = #list
        if not open_shop_menu() then
            log('Скупка: лавка не открылась. Подойдите к лавке.', 'error')
            DSP.auto.buy_running = false
            DSP.auto.status = 'скупка: ошибка'
            return
        end
        local bought, dry = 0, 0
        for pi, it in ipairs(list) do
            if not DSP.auto.buy_running then break end
            local remaining = tonumber(it.qty) or 1
            local result
            while remaining > 0 do
                local entry = {}
                for key, value in pairs(it) do entry[key] = value end
                entry.qty = remaining
                local units
                result, units = buy_one(entry, pi, #list, dry_run)
                if not result then break end
                remaining = remaining - (units or 1)
                DSP.auto.progress.units = (DSP.auto.progress.units or 0) + (units or 1)
                close_dialog()
            end
            if remaining == 0 and result == 'bought' then bought = bought + 1
            elseif remaining == 0 and result == 'dry' then dry = dry + 1
            else DSP.auto.progress.failed = DSP.auto.progress.failed + 1 end
            DSP.auto.progress.done, DSP.auto.progress.dry = bought, dry
            close_dialog()
            if pi < #list and DSP.auto.buy_running then
                if not open_shop_menu() then break end
            end
        end
        DSP.auto.buy_running = false
        DSP.auto.status = 'скупка: ' .. bought .. '/' .. #list .. (dry > 0 and (' (dry ' .. dry .. ')') or '')
        log('Скупка завершена: ' .. bought .. '/' .. #list, 'ok')
    end)
    return true
end

function DSP.auto.stop_buy()
    if not DSP.auto.buy_running then return false end
    runtime.cancel()
    DSP.auto.buy_running = false
    DSP.auto.status = 'скупка остановлена'
    close_dialog()
    log('Скупка остановлена')
end
