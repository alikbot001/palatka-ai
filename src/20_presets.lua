-- Own buy/sell presets, independent from Market Helper.
DSP.presets = {}

-- Restore existing objects in place: edit buffers and legacy aliases retain identity.
function DSP.presets._transaction(change)
    local keys={'buy_preset','sell_preset','buy_presets','sell_presets',
        'active_buy_preset','active_sell_preset'}
    local roots,snapshots={},{}
    local function capture(t)
        if type(t)~='table' or snapshots[t] then return end
        local copy={};snapshots[t]=copy
        for k,v in pairs(t) do copy[k]=v;capture(v) end
    end
    for _,key in ipairs(keys) do roots[key]=DSP.settings[key];capture(roots[key]) end
    local function rollback()
        for t,copy in pairs(snapshots) do
            for k in pairs(t) do t[k]=nil end
            for k,v in pairs(copy) do t[k]=v end
        end
        for _,key in ipairs(keys) do DSP.settings[key]=roots[key] end
    end
    local changed,result,detail=pcall(change)
    if not changed or result==false then
        rollback();return false,changed and detail or tostring(result)
    end
    local called,saved,err=pcall(DSP.save_settings)
    if not called or saved==false or (saved==nil and err~=nil) then
        rollback();return false,called and (err or 'не удалось сохранить настройки') or tostring(saved)
    end
    -- Older embedders expose a void saver; the bundled saver returns true/false.
    return result,detail
end

local function preset(kind)
    if kind == 'sell' then return DSP.settings.sell_preset end
    return DSP.settings.buy_preset
end

function DSP.presets.items(kind)
    return preset(kind).items
end

function DSP.presets.find(kind, key)
    for i, it in ipairs(preset(kind).items) do
        if it.key == key or DSP.item_key(it.name:gsub('%s*%(%+%d+%)%s*$', ''), it.ench) == key then return i, it end
    end
    return nil
end

function DSP.presets.add(row, kind)
    if DSP.auto and (DSP.auto.buy_running or DSP.auto.sell_running) then return false, 'остановите автоматизацию' end
    if not row then return false, 'нет выбранного товара' end
    kind = kind == 'sell' and 'sell' or 'buy'
    local p = preset(kind)
    local price
    if kind == 'buy' then
        price = DSP.market.buy_target(row)
    else
        price = DSP.market.sell_target(row)
    end
    if price <= 0 then return false, 'нет цены для расчёта' end
    local idx, it = DSP.presets.find(kind, row.key)
    if it then
        local ok,err=DSP.presets._transaction(function()
            it.price = price
            it.name = row.display
            it.ench = row.ench
            it.enabled = true
            return true
        end)
        if not ok then return false,err end
        DSP.add_log('Обновлено в ' .. p.name .. ': ' .. row.display)
        return true
    end
    local ok,err=DSP.presets._transaction(function()
        table.insert(p.items, {
            key = row.key,
            name = row.display,
            ench = row.ench or 0,
            price = price,
            qty = 1,
            enabled = true,
        })
        return true
    end)
    if not ok then return false,err end
    DSP.add_log('Добавлено в ' .. p.name .. ': ' .. row.display .. ' по ' .. DSP.money(price))
    return true
end

function DSP.presets.remove(kind, idx)
    if DSP.auto and (DSP.auto.buy_running or DSP.auto.sell_running) then return false, 'остановите автоматизацию' end
    local p = preset(kind)
    local it=p.items[idx]
    if not it then return false,'нет позиции' end
    local ok,err=DSP.presets._transaction(function()
        table.remove(p.items,idx);return true
    end)
    if not ok then return false,err end
    DSP.add_log('Удалено из ' .. p.name .. ': ' .. it.name)
    return true
end

function DSP.presets.clear(kind)
    if DSP.auto and (DSP.auto.buy_running or DSP.auto.sell_running) then return false, 'остановите автоматизацию' end
    local p = preset(kind)
    local ok,err=DSP.presets._transaction(function() p.items={};return true end)
    if not ok then return false,err end
    DSP.add_log(p.name .. ': список очищен')
    return true
end

function DSP.presets.recalc(kind)
    if DSP.auto and (DSP.auto.buy_running or DSP.auto.sell_running) then return false, 'остановите автоматизацию' end
    local p = preset(kind)
    local changed, missing = 0, 0
    local ok,err=DSP.presets._transaction(function()
      for _, it in ipairs(p.items) do
        local row = DSP.market.row_for(it.name, it.ench)
        if not row then
            local base = it.name:gsub('%s+%(%+%d+%)$', '')
            row = DSP.market.row_for(base, it.ench)
        end
        if row then
            local price
            if kind == 'buy' then
                price = DSP.market.buy_target(row)
            else
                price = DSP.market.sell_target(row)
            end
            if price > 0 then
                it.price = price
                it.key = row.key
                changed = changed + 1
            else
                missing = missing + 1
            end
        else
            missing = missing + 1
        end
      end
      return true
    end)
    if not ok then return false,err end
    DSP.add_log(string.format('%s: пересчитано %d, без данных %d', p.name, changed, missing))
    return changed, missing
end

function DSP.presets.find_row(it)
    local row = DSP.market.row_for(it.name, it.ench)
    if not row then
        local base = it.name:gsub('%s+%(%+%d+%)$', '')
        row = DSP.market.row_for(base, it.ench)
    end
    return row
end

function DSP.presets.estimate(it, kind)
    local row = DSP.presets.find_row(it)
    if not row then return nil end
    local tax = math.max(0, math.min(10000, tonumber(DSP.settings.tax_bp) or 200))
    local qty = tonumber(it.qty) or 1
    if kind == 'buy' then
        if not row.sell or (tonumber(row.sell.min) or 0) <= 0 then return nil end
        -- Potential resale proceeds; this is an estimate, not realized profit.
        return math.floor(row.sell.min * qty * (10000 - tax) / 10000) - it.price * qty, row
    end
    if not row.buy or (tonumber(row.buy.max) or 0) <= 0 then return nil end
    return math.floor(it.price * qty * (10000 - tax) / 10000) - row.buy.max * qty, row
end

function DSP.presets.active_count(kind)
    local n = 0
    for _, it in ipairs(preset(kind).items) do
        if it.enabled ~= false then n = n + 1 end
    end
    return n
end
