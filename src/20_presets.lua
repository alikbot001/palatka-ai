-- Own buy/sell presets, independent from Market Helper.
DSP.presets = {}

local function preset(kind)
    if kind == 'sell' then return DSP.settings.sell_preset end
    return DSP.settings.buy_preset
end

function DSP.presets.items(kind)
    return preset(kind).items
end

function DSP.presets.find(kind, key)
    for i, it in ipairs(preset(kind).items) do
        if it.key == key or DSP.item_key(it.name, it.ench) == key then return i, it end
    end
    return nil
end

function DSP.presets.add(row, kind)
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
        it.price = price
        it.name = row.display
        it.ench = row.ench
        it.enabled = true
        DSP.save_settings()
        DSP.add_log('Обновлено в ' .. p.name .. ': ' .. row.display)
        return true
    end
    table.insert(p.items, {
        key = row.key,
        name = row.display,
        ench = row.ench or 0,
        price = price,
        qty = 1,
        enabled = true,
    })
    DSP.save_settings()
    DSP.add_log('Добавлено в ' .. p.name .. ': ' .. row.display .. ' по ' .. DSP.money(price))
    return true
end

function DSP.presets.remove(kind, idx)
    local p = preset(kind)
    local it = table.remove(p.items, idx)
    if it then
        DSP.save_settings()
        DSP.add_log('Удалено из ' .. p.name .. ': ' .. it.name)
    end
end

function DSP.presets.clear(kind)
    local p = preset(kind)
    p.items = {}
    DSP.save_settings()
    DSP.add_log(p.name .. ': список очищен')
end

function DSP.presets.recalc(kind)
    local p = preset(kind)
    local changed, missing = 0, 0
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
    DSP.save_settings()
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
    if kind == 'buy' then
        -- Profit = resale value - purchase price
        return (row.buy.max - it.price) * (it.qty or 1), row
    end
    -- For sell: listing price vs acquisition cost
    return (it.price - row.sell.min) * (it.qty or 1), row
end

function DSP.presets.active_count(kind)
    local n = 0
    for _, it in ipairs(preset(kind).items) do
        if it.enabled then n = n + 1 end
    end
    return n
end

function DSP.presets.import_mh()
    local candidates = {
        (getWorkingDirectory():gsub('\\', '/')) .. '/MarketHelper/MarketHelper_settings.json',
        (getWorkingDirectory():gsub('\\', '/')) .. '/MarketHelper/settings.json',
    }
    local raw
    for _, path in ipairs(candidates) do
        local f = io.open(path, 'rb')
        if f then raw = f:read('*a'); f:close(); break end
    end
    if not raw then return false, 'настройки Market Helper не найдены' end
    local ok, d = pcall(decodeJson, raw)
    if not ok or type(d) ~= 'table' then return false, 'не удалось прочитать JSON' end
    local imported = 0
    local function pull(src, kind)
        if type(src) ~= 'table' then return end
        for _, it in ipairs(src) do
            local name = it.name or it.nm or it.item
            local ench = tonumber(it.ench or it.enchant or 0) or 0
            local price = tonumber(it.price or it.max_price or it.maxPrice or 0) or 0
            local qty = tonumber(it.qty or it.count or 1) or 1
            if name and price > 0 then
                local key = DSP.item_key(DSP.text_cp(name), ench)
                local idx = DSP.presets.find(kind, key)
                if not idx then
                    table.insert(preset(kind).items, {
                        key = key,
                        name = DSP.item_name(DSP.text_cp(name), ench),
                        ench = ench,
                        price = price,
                        qty = qty,
                        enabled = it.enabled ~= false,
                    })
                    imported = imported + 1
                end
            end
        end
    end
    pull(d.buy_preset and d.buy_preset.items, 'buy')
    pull(d.sell_preset and d.sell_preset.items, 'sell')
    pull(d.autobuy_items, 'buy')
    pull(d.autosell_items, 'sell')
    if imported == 0 then return false, 'в настройках MH нет подходящих списков' end
    DSP.save_settings()
    DSP.add_log('Импорт из Market Helper: ' .. imported .. ' поз.')
    return true, imported
end
