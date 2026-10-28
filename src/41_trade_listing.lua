-- Auto listing orchestration, separate from inventory and dialog observation.
local runtime = DSP.trade_runtime
local trade_wait = runtime.pause
local log = DSP.add_log
local h = DSP.auto.helpers
local close_dialog, wait_dialog, wait_text = h.close_dialog, h.wait_dialog, h.wait_text
local clean, base_name, has_qty = h.clean, h.base_name, h.has_qty
local wait_item = h.wait_trade_item_dialog
local function queue_sell()
    local queue, available = {}, {}
    for _, p in ipairs(DSP.settings.sell_preset.items) do
        if p.enabled ~= false and runtime.positive(p.price) and runtime.positive(p.qty or 1) then
            local target = base_name(p.name)
            local left = tonumber(p.qty) or 1
            for _, inv in ipairs(DSP.auto.inv) do
                if inv.name == p.name or ((tonumber(p.ench) or 0) == 0 and inv.name == target) then
                    for _, st in ipairs(inv.stacks) do
                        if left <= 0 then break end
                        if available[st.slot] == nil then
                            available[st.slot] = runtime.positive(st.count) and tonumber(st.count) or 0
                        end
                        local take = math.min(available[st.slot], left)
                        if take > 0 then
                            table.insert(queue, {
                                name = p.name, base = target, price = p.price,
                                qty = take, slot = st.slot,
                            })
                            left = left - take
                            available[st.slot] = available[st.slot] - take
                        end
                    end
                end
            end
            if left > 0 then return nil, p.name .. ': недостаточно в инвентаре' end
        end
    end
    return queue
end

function DSP.auto.start_sell()
    if DSP.auto.sell_running or DSP.auto.scanning then return false end
    if DSP.auto.buy_running or DSP.auto.scanning then return false end
    local items = DSP.settings.sell_preset.items
    local n = 0
    for _, it in ipairs(items) do if it.enabled ~= false then n = n + 1 end end
    if n == 0 then DSP.notify('Продажа: пресет пуст'); return end
    if #DSP.auto.inv == 0 then
        DSP.notify('Продажа: сначала просканируйте инвентарь')
        return
    end
    local queue, err = queue_sell()
    if not queue then DSP.notify('Продажа: ' .. err); return false end
    if #queue == 0 then DSP.notify('Продажа: в инвентаре нет позиций из пресета'); return end
    local dry_run = DSP.settings.dry_run
    DSP.auto.sell_running = true
    DSP.auto.sell_confirmed = false
    DSP.auto.sell_forbidden = false
    DSP.auto.sell_no_slots = false
    DSP.auto.status = 'продажа...'
    log('Продажа: ' .. #queue .. ' стек(ов)')
    runtime.spawn('sell', function()
        DSP.auto.progress.total = #queue
        local done = 0
        for _, it in ipairs(queue) do
            if not DSP.auto.sell_running then break end
            DSP.auto.status = 'продажа: ' .. it.name .. ' (' .. done .. '/' .. #queue .. ')'
            local json = '{"amount":' .. it.qty .. ',"id":0,"slot":' .. it.slot .. ',"type":1}'
            local got, id, dialog_text = false, nil, nil
            for attempt = 1, 3 do
                close_dialog()
                DSP.auto.sell_confirmed = false
                DSP.auto.sell_forbidden, DSP.auto.sell_no_slots = false, false
                _G.dsp_click_slot(60, -1, 2, json)
                -- v1.2 hotfix: also accept 15068-15071 (newer Arizona Mobile выставление dialogs).
                id,dialog_text = wait_item({ 26547, 15068, 15069, 15070, 15071 }, it.name, 2200)
                if id then
                    got = true
                    break
                end
                log('Продажа: диалог предмета не готов ('..attempt..'): '..tostring(dialog_text or ''):sub(1,90),'error')
                close_dialog()
                trade_wait(180)
            end
            if got then
                -- mimgui/MonetLoader may publish the dialog text before the
                -- native input control is ready. Follow the observed game
                -- sequence: one short settle, then verify the *same* item/ID.
                trade_wait(180)
                local current=sampIsDialogActive() and sampGetCurrentDialogId() or nil
                local actual=current and DSP.dialog_clean(sampGetDialogText() or '') or ''
                if current~=id or not runtime.matches(actual,it.base) then
                    got=false
                    log('Продажа: диалог сменился до отправки, id='..tostring(current)..
                        ', ожидался='..tostring(id)..' · '..it.name,'error')
                else
                    dialog_text=actual
                end
            end
            if got then
                local txt = dialog_text or ''
                local resp = has_qty(txt) and (tostring(it.qty) .. ',' .. tostring(it.price))
                    or tostring(it.price)
                if not has_qty(txt) and it.qty > 1 then
                    error('Диалог не поддерживает количество: ' .. it.name)
                end
                if dry_run then
                    DSP.auto.progress.dry = DSP.auto.progress.dry + 1
                    log('dry-run: продал бы ' .. it.name .. ' x' .. it.qty .. ' @ ' .. DSP.money(it.price))
                    close_dialog()
                else
                    DSP.auto.sell_confirmed = false
                    -- v1.2 hotfix: use the active dialog id (may be 26547 or
                    -- 15068-15071 in newer Arizona Mobile). Fallback chain.
                    local resp_id = id or sampGetCurrentDialogId and sampGetCurrentDialogId() or 26547
                    sampSendDialogResponse(resp_id, 1, 0, resp)
                    for _ = 1, 100 do
                        if DSP.auto.sell_confirmed then break end
                        trade_wait(40)
                    end
                    if sampIsDialogActive() and sampGetCurrentDialogId()==resp_id then
                        sampSendDialogResponse(resp_id, 0, 0, '')
                    end
                    if DSP.auto.sell_no_slots then
                        DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                        log('Продажа: нет свободных мест', 'error')
                        DSP.auto.sell_running = false
                        break
                    end
                    if DSP.auto.sell_forbidden then
                        DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                        log('Продажа: запрещено для ' .. it.name, 'error')
                    elseif DSP.auto.sell_confirmed then
                        done = done + 1
                        DSP.auto.progress.done = done
                        log('Выставлено: ' .. it.name .. ' x' .. it.qty .. ' @ ' .. DSP.money(it.price), 'ok')
                    else
                        DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                        log('Продажа: нет подтверждения для ' .. it.name, 'error')
                    end
                end
                trade_wait(260)
            else
                DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                log('Продажа: не открылся диалог для ' .. it.name .. ' (slot ' .. it.slot .. ')', 'error')
                close_dialog()
            end
        end
        DSP.auto.sell_running = false
        DSP.auto.status = 'продажа: ' .. done .. '/' .. #queue
        log('Продажа завершена: ' .. done .. '/' .. #queue, 'ok')
        -- Inventory is now stale; refresh explicitly before another sale.
        DSP.auto.inv = {}
        DSP.auto.inv_status = 'нужно обновить'
    end)
    return true
end

function DSP.auto.stop_sell()
    if not DSP.auto.sell_running then return false end
    runtime.cancel()
    DSP.auto.sell_running = false
    DSP.auto.status = 'продажа остановлена'
    close_dialog()
    log('Продажа остановлена')
end
