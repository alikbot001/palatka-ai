-- Auto listing orchestration, separate from inventory and dialog observation.
local runtime = DSP.trade_runtime
local trade_wait = runtime.pause
local log = DSP.add_log
local h = DSP.auto.helpers
local close_dialog, wait_dialog, wait_text = h.close_dialog, h.wait_dialog, h.wait_text
local clean, base_name, has_qty = h.clean, h.base_name, h.has_qty
local wait_item = h.wait_trade_item_dialog
local trade_dialog_matches, current_dialog_title = h.trade_dialog_matches, h.current_dialog_title
local function queue_sell()
    local queue, available = {}, {}
    local preset=DSP.settings.sell_preset
    if type(preset)~='table' or type(preset.items)~='table' then return nil,'preset unavailable' end
    if type(DSP.auto.inv)~='table' then return nil,'inventory unavailable' end
    for _, p in ipairs(preset.items) do
        if type(p)~='table' then return nil,'invalid preset row' end
        if p.enabled ~= false and runtime.positive(p.price) and runtime.positive(p.qty or 1) then
            if type(p.name)~='string' or p.name=='' then return nil,'invalid item name' end
            local target = base_name(p.name)
            local left = tonumber(p.qty) or 1
            for _, inv in ipairs(DSP.auto.inv) do
                if type(inv)~='table' or type(inv.stacks)~='table' then
                    return nil,'inventory slot list is missing; scan inventory again'
                end
                if inv.name == p.name or ((tonumber(p.ench) or 0) == 0 and inv.name == target) then
                    for _, st in ipairs(inv.stacks) do
                        if type(st)~='table' or type(st.slot)~='number' or st.slot%1~=0
                            or st.slot<0 or st.slot>1000 then
                            return nil,'inventory slot invalid; scan inventory again'
                        end
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
            if left > 0 then return nil, p.name .. ': íåäîñòàòî÷íî â èíâåíòàðå' end
        end
    end
    return queue
end

-- The original queue uses a point-in-time inventory snapshot. Every confirmed
-- sale can remove/compact slots. Refresh the inventory before the next packet
-- and bind the item to its CURRENT confirmed slot, never a stale index.
local function refresh_sell_inventory()
    if type(DSP.auto.scan_inventory)~='function' then return false,'inventory scanner unavailable' end
    runtime.transition('sell','refresh_inventory','scan actual stock before next sale')
    local started=DSP.auto.scan_inventory(true)
    if started==false then return false,'inventory refresh blocked' end
    local elapsed=0
    while DSP.auto.scanning and elapsed<27000 do
        trade_wait(50)
        elapsed=elapsed+50
    end
    if DSP.auto.scanning or tostring(DSP.auto.inv_status or ''):find('òàéìàóò',1,true) then
        return false,'inventory refresh timed out'
    end
    if type(DSP.auto.inv)~='table' then return false,'inventory scan returned invalid stock' end
    if DSP.flog then DSP.flog('PRESET fresh inventory rows='..#DSP.auto.inv) end
    return true
end

local function current_sell_stack(item)
    if type(DSP.auto.inv)~='table' then return nil end
    local best
    for _, inv in ipairs(DSP.auto.inv) do
        if type(inv)=='table' and type(inv.stacks)=='table'
            and (inv.name==item.name or (inv.name==item.base and item.name==item.base)) then
            for _, st in ipairs(inv.stacks) do
                local slot,count=tonumber(st.slot),tonumber(st.count)
                if slot and slot%1==0 and slot>=0 and slot<=1000
                    and count and count%1==0 and count>0
                    and (not best or count>best.count) then
                    best={slot=slot,count=count}
                end
            end
        end
    end
    return best
end

function DSP.auto.start_sell()
    if DSP.auto.sell_running or DSP.auto.scanning then return false end
    if DSP.auto.buy_running or DSP.auto.scanning then return false end
    local preset=DSP.settings.sell_preset
    local items=type(preset)=='table' and preset.items or nil
    if type(items)~='table' then DSP.notify('Sale preset unavailable');return false end
    local n = 0
    for _, it in ipairs(items) do
        if type(it)~='table' then DSP.notify('Invalid preset row');return false end
        if it.enabled ~= false then n = n + 1 end
    end
    if n == 0 then DSP.notify('Ïðîäàæà: ïðåñåò ïóñò'); return end
    if #DSP.auto.inv == 0 then
        DSP.notify('Ïðîäàæà: ñíà÷àëà ïðîñêàíèðóéòå èíâåíòàðü')
        return
    end
    local q_ok,queue,err=pcall(queue_sell)
    if not q_ok then
        DSP.flog('PRESET queue_sell error: '..tostring(queue))
        DSP.notify('Preset error; check standalone.log')
        return false
    end
    if not queue then DSP.notify('Sale: '..tostring(err)); return false end
    if #queue == 0 then DSP.notify('Ïðîäàæà: â èíâåíòàðå íåò ïîçèöèé èç ïðåñåòà'); return end
    local dry_run = DSP.settings.dry_run
    DSP.auto.sell_running = true
    DSP.auto.sell_confirmed = false
    DSP.auto.sell_forbidden = false
    DSP.auto.sell_no_slots = false
    DSP.auto.status = 'ïðîäàæà...'
    DSP.flog('PRESET sale accepted: '..#queue..' stacks, dry_run='..tostring(dry_run))
    log('Ïðîäàæà: ' .. #queue .. ' ñòåê(îâ)')
    if dry_run then
        DSP.notify('ÒÅÑÒ: èãðîâûå îêíà íå îòêðûâàþòñÿ. Äëÿ äåéñòâèé íóæåí ðåæèì ÐÅÀËÜÍÎ.')
        -- A preview must NEVER send RakNet clicks or dialog responses.
        DSP.auto.sell_running=true
        DSP.auto.status='sale preview...'
        runtime.spawn('sell',function()
            DSP.auto.progress.total=#queue
            for i,it in ipairs(queue) do
                DSP.auto.progress.dry=i
                DSP.auto.progress.done=i
                log('preview: '..it.name..' x'..it.qty..' @ '..DSP.money(it.price))
            end
            DSP.auto.sell_running=false
            DSP.auto.status='sale preview: '..#queue..' stacks, no packets sent'
        end)
        return true
    end
    runtime.spawn('sell', function()
        DSP.auto.progress.total = #queue
        local done = 0
        local aborted=false
        local attempted=0
        for index,it in ipairs(queue) do
            if not DSP.auto.sell_running then break end
            if index>1 then
                local ok,why=refresh_sell_inventory()
                if not ok then
                    DSP.auto.progress.failed=DSP.auto.progress.failed+1
                    DSP.auto.status='Sale stopped: inventory refresh failed'
                    log('PRESET sale halted: '..tostring(why),'error')
                    aborted=true
                    break
                end
            end
            local fresh=current_sell_stack(it)
            if not fresh then
                DSP.auto.progress.failed=DSP.auto.progress.failed+1
                DSP.auto.status='Sale stopped: item slot no longer available'
                log('PRESET sale halted: item not in fresh inventory '..tostring(it.name),'error')
                aborted=true
                break
            end
            -- A previously planned stack may have split/merged. Never send
            -- more than the current stack contains; carry the remainder
            -- forward as a new pending task after this confirmed sale.
            if fresh.count<it.qty then
                table.insert(queue,index+1,{
                    name=it.name,base=it.base,price=it.price,
                    qty=it.qty-fresh.count,slot=it.slot,
                })
                it.qty=fresh.count
                DSP.auto.progress.total=#queue
            end
            it.slot=fresh.slot
            -- Do not reuse a previous server-side stall context after posting
            -- a sale; the native menu can close or change after each listing.
            if DSP.auto.prepare_stall_inventory then
                local ok,why=DSP.auto.prepare_stall_inventory()
                if not ok then
                    DSP.auto.progress.failed=DSP.auto.progress.failed+1
                    DSP.auto.status='Sale stopped: stall not ready'
                    log('PRESET sale halted: '..tostring(why or 'stall not ready'),'error')
                    aborted=true
                    break
                end
                trade_wait(120)
            end
            attempted=attempted+1
            DSP.auto.status = 'ïðîäàæà: ' .. it.name .. ' (' .. done .. '/' .. #queue .. ')'
            local json = '{"amount":' .. it.qty .. ',"id":0,"slot":' .. it.slot .. ',"type":1}'
            local got, id, dialog_text = false, nil, nil
            for attempt = 1, 3 do
                close_dialog()
                DSP.auto.sell_confirmed = false
                DSP.auto.sell_forbidden, DSP.auto.sell_no_slots = false, false
                -- Native RakNet must not receive stale/invalid slot data.
                if type(it.slot)~='number' or it.slot<0 or it.slot>1000 or it.slot%1~=0 then
                    error('Invalid inventory slot at send: '..tostring(it.slot))
                end
                runtime.transition('sell','select_item',tostring(it.name)..' slot='..tostring(it.slot))
                DSP.flog('PRESET sale packet: item='..tostring(it.name)..' slot='..it.slot..' qty='..tostring(it.qty))
                -- Associate a newly arrived input dialog with THIS slot click.
                -- Unknown IDs (including Halloween IDs) are accepted only by
                -- the fresh-input title/body guard in 40_auto.lua.
                if DSP.auto.arm_trade_dialog then DSP.auto.arm_trade_dialog('sell', it.name) end
                _G.dsp_click_slot(60, -1, 2, json)
                runtime.transition('sell','wait_item_dialog',tostring(it.name))
                id,dialog_text,dialog_title = wait_item({ 26547, 15068, 15069, 15070, 15071 }, it.name, 2600, 'sell')
                if id then
                    got = true
                    break
                end
                log('Ïðîäàæà: äèàëîã ïðåäìåòà íå ãîòîâ ('..attempt..'): '..tostring(dialog_text or ''):sub(1,90),'error')
                close_dialog()
                trade_wait(180)
            end
            if got then
                -- mimgui/MonetLoader may publish the dialog text before the
                -- native input control is ready. Follow the observed game
                -- sequence: one short settle, then verify the *same* item/ID.
                trade_wait(180)
                local current=sampIsDialogActive() and sampGetCurrentDialogId() or nil
                local valid,actual,actual_title=false,'',''
                if current then valid,actual,actual_title=trade_dialog_matches(current,it.name,'sell') end
                if current~=id or not valid then
                    got=false
                    log('\xcf\xf0\xee\xe4\xe0\xe6\xe0: \xe4\xe8\xe0\xeb\xee\xe3 \xf1\xec\xe5\xed\xe8\xeb\xf1\xff \xe4\xee \xee\xf2\xef\xf0\xe0\xe2\xea\xe8, id='..tostring(current)..
                        ', \xee\xe6\xe8\xe4\xe0\xeb\xf1\xff='..tostring(id)..' \xb7 '..it.name,'error')
                else
                    dialog_text,dialog_title=actual,actual_title
                end
            end
            if got then
                local txt = (dialog_title or '') .. '\n' .. (dialog_text or '')
                local combined = has_qty(txt)
                -- Market Helper behavior: amount is already present in the iface60
                -- slot packet. If this client only asks for price, send only price.
                local resp = combined and (tostring(it.qty) .. ',' .. tostring(it.price))
                    or tostring(it.price)
                DSP.flog('PRESET sale input: item='..tostring(it.name)..' dialog='..tostring(id)..
                    ' mode='..(combined and 'qty_price' or 'price_only')..' resp_len='..tostring(#resp))
                if dry_run then
                    DSP.auto.progress.dry = DSP.auto.progress.dry + 1
                    log('dry-run: ïðîäàë áû ' .. it.name .. ' x' .. it.qty .. ' @ ' .. DSP.money(it.price))
                    close_dialog()
                else
                    DSP.auto.sell_confirmed = false
                    -- v1.2 hotfix: use the active dialog id (may be 26547 or
                    -- 15068-15071 in newer Arizona Mobile). Fallback chain.
                    local resp_id = id or sampGetCurrentDialogId and sampGetCurrentDialogId() or 26547
                    runtime.transition('sell','submit',tostring(it.name)..' qty='..tostring(it.qty)..' price='..tostring(it.price))
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
                        log('Ïðîäàæà: íåò ñâîáîäíûõ ìåñò', 'error')
                        DSP.auto.sell_running = false
                        break
                    end
                    if DSP.auto.sell_forbidden then
                        DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                        log('Ïðîäàæà: çàïðåùåíî äëÿ ' .. it.name, 'error')
                    elseif DSP.auto.sell_confirmed then
                        done = done + 1
                        DSP.auto.progress.done = done
                        log('Âûñòàâëåíî: ' .. it.name .. ' x' .. it.qty .. ' @ ' .. DSP.money(it.price), 'ok')
                    else
                        DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                        DSP.auto.status='Sale stopped: no server confirmation'
                        log('PRESET sale halted: no confirmation for '..it.name..' slot='..tostring(it.slot),'error')
                        aborted=true
                    end
                end
                if aborted then break end
                trade_wait(260)
            else
                DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                DSP.auto.status='Sale stopped: item dialog not received'
                log('PRESET sale halted: no price dialog for '..it.name..' slot='..tostring(it.slot),'error')
                close_dialog()
                aborted=true
                break
            end
        end
        DSP.auto.sell_running = false
        if aborted or DSP.auto.sell_no_slots then
            DSP.auto.status = 'Sale PARTIAL: '..done..'/'..#queue..' (see log)'
            log('Sale PARTIAL: confirmed '..done..' of '..#queue..' actions; retry only after rescan', 'error')
        else
            DSP.auto.status = 'ïðîäàæà: ' .. done .. '/' .. #queue
            log('Ïðîäàæà çàâåðøåíà: ' .. done .. '/' .. #queue, 'ok')
        end
        -- Inventory is now stale; refresh explicitly before another sale.
        DSP.auto.inv = {}
        DSP.auto.inv_status = 'íóæíî îáíîâèòü'
    end)
    return true
end

function DSP.auto.stop_sell()
    if not DSP.auto.sell_running then return false end
    runtime.cancel()
    DSP.auto.sell_running = false
    DSP.auto.status = 'ïðîäàæà îñòàíîâëåíà'
    close_dialog()
    log('Ïðîäàæà îñòàíîâëåíà')
end
