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
            if found~=nil then return nil,'íåñêîëüêî îäèíàêîâûõ ñòðîê' end
            found=idx
        end
        idx=idx+1
    end
    return found
end

local function open_shop_menu()
    runtime.transition('buy','open_shop','request native stall menu')
    close_dialog()
    _G.dsp_click_slot(8, 7, -1, '')
    runtime.transition('buy','wait_shop','dialogs 3040/15072')
    -- v1.2 hotfix: accept 15072/15073 fallback for shop menu open in newer Arizona Mobile.
    return wait_dialog({ 3040, 15072 }, 2500)
end

local function buy_one(it, pi, total, dry_run)
    DSP.auto.status = 'ñêóïêà: ' .. it.name .. ' (' .. pi .. '/' .. total .. ')'
    if not sampIsDialogActive() or (sampGetCurrentDialogId() ~= 3040 and sampGetCurrentDialogId()~=15072) then
        if not open_shop_menu() then
            log('Ñêóïêà: ìåíþ íå îòêðûëîñü äëÿ ' .. it.name, 'error')
            return false
        end
    end
    local menu_id = sampGetCurrentDialogId()
    wait_text(menu_id, 350)
    runtime.transition('buy','open_search','menu='..tostring(menu_id))
    sampSendDialogResponse(menu_id, 1, 2, '')
    -- v1.2 hotfix: also accept 15065-15067 (newer search/dialog IDs).
    local id = wait_dialog({ 25663, 15065, 15066, 15067 }, 3000)
    if not id then
        log('Ñêóïêà: ñòðîêà ïîèñêà íå îòêðûëàñü', 'error')
        return false
    end
    wait_text(id, 700)
    local search = base_name(it.name):sub(1, 24)
    runtime.transition('buy','search',tostring(it.name))
    sampSendDialogResponse(id, 1, 0, search)
    -- v1.2 hotfix: search results dialog may also be 15068 in newer versions.
    id = wait_dialog({ 25664, 15068 }, 3500)
    if not id then
        log('Ñêóïêà: ðåçóëüòàòû íå îòêðûëèñü: ' .. it.name, 'error')
        return false
    end
    local list_text = DSP.dialog_clean(wait_text(id, 500))
    local idx,index_err = find_list_index(list_text, it.name)
    if idx==nil then
        log('Ñêóïêà: '..tostring(index_err or 'íå íàéäåíî')..': ' .. it.name, 'error')
        close_dialog()
        return false
    end
    runtime.transition('buy','select_result',tostring(it.name)..' row='..tostring(idx))
    sampSendDialogResponse(id, 1, idx, '')
    -- v1.2 hotfix: âûñòàâëåíèå price dialog may also use 15070/15071 in newer Arizona Mobile.
    id = wait_dialog({ 26560, 26563, 15070, 15071 }, 3000)
    if not id then
        log('Ñêóïêà: äèàëîã öåíû íå îòêðûëñÿ: ' .. it.name, 'error')
        return false
    end
    if id == 26560 then
        sampSendDialogResponse(id, 1, 0, '')
        -- v1.2 hotfix: also accept 15071 fallback.
        id = wait_dialog({ 26563, 15071 }, 2000)
    end
    -- v1.2 hotfix: accept 15071 as alternative to 26563 for the final âûñòàâëåíèå dialog.
    if id ~= 26563 and id ~= 15071 then return false end
    local validated_id,txt,dialog_title=wait_item({id},it.name,1700,'buy')
    local base = base_name(it.name)
    if not validated_id then
        log('Ñêóïêà: â äèàëîãå äðóãîé òîâàð: ' .. it.name, 'error')
        close_dialog()
        return false
    end
    -- Stabilize the native price input after the dialog text appears. Never
    -- submit to another item/ID that replaced it during the delay.
    trade_wait(180)
    local current=sampIsDialogActive() and sampGetCurrentDialogId() or nil
    local valid,actual,actual_title=false,'',''
    if current then valid,actual,actual_title=trade_dialog_matches(current,it.name,'buy') end
    if current~=id or not valid then
        log('\xd1\xea\xf3\xef\xea\xe0: \xe4\xe8\xe0\xeb\xee\xe3 \xe8\xe7\xec\xe5\xed\xe8\xeb\xf1\xff \xe4\xee \xee\xf2\xef\xf0\xe0\xe2\xea\xe8 \xb7 '..it.name,'error')
        close_dialog()
        return false
    end
    txt,dialog_title=actual,actual_title
    local qty = tonumber(it.qty) or 1
    if qty < 1 then qty = 1 end
    local combined = has_qty((dialog_title or '') .. '\n' .. (txt or ''))
    if not combined and qty>1 then
        -- Same fallback as Market Helper: a price-only buy dialog represents one
        -- unit, so the outer loop repeats the listing until requested qty is done.
        log('Buy: price-only dialog, one unit per submit', 'info')
        qty=1
    end
    local resp = combined and (tostring(qty) .. ',' .. tostring(it.price))
        or tostring(it.price)
    DSP.flog('PRESET buy input: item='..tostring(it.name)..' dialog='..tostring(id)..
        ' mode='..(combined and 'qty_price' or 'price_only')..' resp_len='..tostring(#resp))
    if dry_run then
        log('dry-run: êóïèë áû ' .. it.name .. ' x' .. qty .. ' @ ' .. DSP.money(it.price))
        close_dialog()
        return 'dry', tonumber(it.qty) or 1
    end
    -- v1.2 hotfix: use the active dialog id (may be 26563 or 15071 in newer
    -- Arizona Mobile âûñòàâëåíèå dialogs). Fallback chain via sampGetCurrentDialogId.
    local resp_id = id or (sampGetCurrentDialogId and sampGetCurrentDialogId()) or 26563
    sampSendDialogResponse(resp_id, 1, 0, resp)
    log('Ñêóïêà: ' .. it.name .. ' x' .. qty .. ' @ ' .. DSP.money(it.price), 'ok')
    for _ = 1, 24 do
        if not sampIsDialogActive() then return 'bought', qty end
        trade_wait(30)
    end
    log('Ñêóïêà: íåò ïîäòâåðæäåíèÿ çàêðûòèÿ äèàëîãà', 'error')
    return false
end

function DSP.auto.start_buy()
    if DSP.auto.buy_running or DSP.auto.scanning then return false end
    if DSP.auto.sell_running or DSP.auto.scanning then return false end
    local list = {}
    local preset=DSP.settings.buy_preset
    if type(preset)~='table' or type(preset.items)~='table' then
        DSP.notify('Buy preset unavailable');return false
    end
    for _, it in ipairs(preset.items) do
        if type(it)~='table' then DSP.notify('Invalid buy preset row');return false end
        if it.enabled ~= false and runtime.positive(it.price) and runtime.positive(it.qty or 1) then
            if type(it.name)~='string' or it.name=='' then
                DSP.notify('Invalid buy preset item name');return false
            end
            list[#list+1] = {name=it.name,price=tonumber(it.price),qty=tonumber(it.qty) or 1}
        end
    end
    if #list == 0 then DSP.notify('Ñêóïêà: ïðåñåò ïóñò èëè öåíû 0'); return end
    local dry_run = DSP.settings.dry_run
    DSP.auto.buy_running = true
    DSP.auto.status = 'ñêóïêà...'
    DSP.flog('PRESET buy accepted: '..#list..' positions, dry_run='..tostring(dry_run))
    log('Ñêóïêà: ' .. #list .. ' ïîçèöèé' .. (dry_run and ' (dry-run)' or ''))
    if dry_run then
        DSP.notify('ÒÅÑÒ: èãðîâûå îêíà íå îòêðûâàþòñÿ. Äëÿ äåéñòâèé íóæåí ðåæèì ÐÅÀËÜÍÎ.')
        -- No shop menu, network packets or dialog interactions in preview.
        runtime.spawn('buy',function()
            DSP.auto.progress.total=#list
            for i,it in ipairs(list) do
                DSP.auto.progress.dry=i
                DSP.auto.progress.done=i
                DSP.auto.progress.units=(DSP.auto.progress.units or 0)+(it.qty or 1)
                log('preview: '..it.name..' x'..it.qty..' @ '..DSP.money(it.price))
            end
            DSP.auto.buy_running=false
            DSP.auto.status='buy preview: '..#list..' positions, no packets sent'
        end)
        return true
    end
    runtime.spawn('buy', function()
        DSP.auto.progress.total = #list
        if not open_shop_menu() then
            log('Ñêóïêà: ëàâêà íå îòêðûëàñü. Ïîäîéäèòå ê ëàâêå.', 'error')
            DSP.auto.buy_running = false
            DSP.auto.status = 'ñêóïêà: îøèáêà'
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
        DSP.auto.status = 'ñêóïêà: ' .. bought .. '/' .. #list .. (dry > 0 and (' (dry ' .. dry .. ')') or '')
        log('Ñêóïêà çàâåðøåíà: ' .. bought .. '/' .. #list, 'ok')
    end)
    return true
end

function DSP.auto.stop_buy()
    if not DSP.auto.buy_running then return false end
    runtime.cancel()
    DSP.auto.buy_running = false
    DSP.auto.status = 'ñêóïêà îñòàíîâëåíà'
    close_dialog()
    log('Ñêóïêà îñòàíîâëåíà')
end


-- Queue user-initiated listing outside the ImGui drawing callback. Synchronous
-- Lua exceptions during an ImGui frame can corrupt its Begin/End stack.
-- This catches Lua-side errors only; native Android faults still need a log.
function DSP.auto.safe_start(kind)
    if kind~='sell' and kind~='buy' then return false end
    if DSP.auto._launch_queued or DSP.auto.buy_running or DSP.auto.sell_running or DSP.auto.scanning then
        DSP.notify('Trade already running or inventory scan active')
        return false
    end
    if type(lua_thread)~='table' or type(lua_thread.create)~='function' then
        DSP.notify('Thread scheduler unavailable')
        return false
    end
    DSP.auto._launch_queued=true
    DSP.flog('PRESET queued: kind='..kind..' dry_run='..tostring(DSP.settings.dry_run))
    local ok,err=pcall(lua_thread.create,function()
        DSP.auto._launch_queued=false
        local started,result=xpcall(function()
            if kind=='sell' then return DSP.auto.start_sell() end
            return DSP.auto.start_buy()
        end,function(e)
            if debug and debug.traceback then return debug.traceback(tostring(e),2) end
            return tostring(e)
        end)
        if not started then
            DSP.auto[kind..'_running']=false
            DSP.auto.status='Preset error; see standalone.log'
            if DSP.flog then DSP.flog('PRESET launch exception: '..tostring(result)) end
            DSP.notify('Preset error; see standalone.log')
        elseif result~=true then
            if DSP.flog then DSP.flog('PRESET launch rejected: '..kind) end
        end
    end)
    if not ok then
        DSP.auto._launch_queued=false
        DSP.flog('PRESET scheduler failure: '..tostring(err))
        DSP.notify('Failed to queue preset; see standalone.log')
        return false
    end
    return true
end