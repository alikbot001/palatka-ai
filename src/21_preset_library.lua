-- Named libraries retain the legacy active preset fields as aliases.
local P = DSP.presets
local function keys(kind)
    if kind == 'sell' then return 'sell_presets', 'active_sell_preset', 'sell_preset' end
    return 'buy_presets', 'active_buy_preset', 'buy_preset'
end
local function library(kind)
    local list_key, active_key, legacy = keys(kind)
    local s = DSP.settings
    if type(s[list_key]) ~= 'table' or #s[list_key] == 0 then
        s[list_key] = {s[legacy] or {name = 'Пресет 1', items = {}}}
    end
    local idx = math.max(1, math.min(#s[list_key], tonumber(s[active_key]) or 1))
    s[active_key], s[legacy] = idx, s[list_key][idx]
    s[legacy].items = s[legacy].items or {}
    return s[list_key], idx
end
local function busy()
    return DSP.auto and (DSP.auto.buy_running or DSP.auto.sell_running)
end
local function positive(v)
    local n = tonumber(v)
    if n and n == n and n > 0 and n <= 9007199254740991 and n % 1 == 0 then return n end
end
function P.list(kind) return (library(kind)) end
function P.selected(kind) local _, idx = library(kind); return idx end
function P.select(kind, idx)
    if busy() then return false, 'остановите автоматизацию' end
    return P._transaction(function()
        local list = library(kind)
        if not list[idx] then return false, 'нет пресета' end
        local _, active, legacy = keys(kind)
        DSP.settings[active], DSP.settings[legacy] = idx, list[idx]
        return true
    end)
end
function P.create(kind, name)
    if busy() then return false, 'остановите автоматизацию' end
    name = tostring(name or ''):match('^%s*(.-)%s*$')
    if name == '' then return false, 'введите название' end
    return P._transaction(function()
        local list = library(kind)
        list[#list + 1] = {name = name, items = {}}
        local _,active,legacy=keys(kind)
        DSP.settings[active],DSP.settings[legacy]=#list,list[#list]
        return true, #list
    end)
end
function P.rename(kind, idx, name)
    if busy() then return false, 'остановите автоматизацию' end
    name = tostring(name or ''):match('^%s*(.-)%s*$')
    return P._transaction(function()
        local list = library(kind)
        if not list[idx] or name == '' then return false, 'некорректное название' end
        list[idx].name = name; return true
    end)
end
function P.delete(kind, idx)
    if busy() then return false, 'остановите автоматизацию' end
    return P._transaction(function()
        local list, active = library(kind)
        if #list <= 1 or not list[idx] then return false, 'нужен хотя бы один пресет' end
        table.remove(list, idx)
        if idx < active then active = active - 1 end
        local _,active_key,legacy=keys(kind)
        active=math.min(active,#list)
        DSP.settings[active_key],DSP.settings[legacy]=active,list[active]
        return true
    end)
end
function P.update(kind, idx, changes)
    if busy() then return false, 'остановите автоматизацию' end
    local it = P.items(kind)[idx]
    if not it or type(changes) ~= 'table' then return false, 'нет позиции' end
    local price = changes.price ~= nil and positive(changes.price) or it.price
    local qty = changes.qty ~= nil and positive(changes.qty) or it.qty
    if (changes.price ~= nil and not positive(changes.price)) or
        (changes.qty ~= nil and not positive(changes.qty)) then return false, 'нужно положительное целое число' end
    return P._transaction(function()
        it.price, it.qty = price, qty
        if positive(price) then it.needs_price = nil end
        if changes.enabled ~= nil then it.enabled = changes.enabled == true end
        return true
    end)
end
local function normalize(items, kind)
    local result = {}
    for _, it in ipairs(items or {}) do
        if type(it) ~= 'table' then return nil end
        local name = it.name or it.nm or it.item
        local raw_price = kind == 'buy' and (it.max_price or it.price) or it.price
        local price = tonumber(raw_price) == 0 and 0 or positive(raw_price)
        local qty = positive(it.target_qty) or positive(it.qty or it.count or 1)
        if type(name) ~= 'string' or name == '' or not price or not qty then return nil end
        name = DSP.text_cp(name)
        local suffix = name:match('%(%+(%d+)%)%s*$')
        local ench = math.max(0, math.floor(tonumber(it.ench or it.enchant or suffix) or 0))
        local base = name:gsub('%s*%(%+%d+%)%s*$', '')
        local cost = tonumber(it.cost_price)
        if cost and (cost~=cost or cost<0 or cost>9007199254740991 or cost%1~=0) then cost=nil end
        result[#result + 1] = {name = DSP.item_name(base, ench), key = DSP.item_key(base, ench), ench = ench,
            price = price, qty = qty, enabled = it.enabled ~= false and price > 0,
            needs_price = price == 0 or nil,
            item_id = it.item_id, qty_limit_1 = it.qty_limit_1, cost_price = cost}
    end
    return result
end
function P.add_manual(kind, item)
    if busy() then return false, 'остановите автоматизацию' end
    if type(item) ~= 'table' then return false, 'нет позиции' end
    local name = tostring(item.name or ''):match('^%s*(.-)%s*$')
    local unpriced = tonumber(item.price) == 0 and item.enabled == false and item.needs_price == true
    if name == '' or (not positive(item.price) and not unpriced) or not positive(item.qty or 1) then
        return false, 'укажите название, положительную цену и количество'
    end
    local ench = tonumber(item.ench or name:match('%(%+(%d+)%)%s*$')) or 0
    if ench < 0 or ench % 1 ~= 0 then return false, 'некорректное улучшение' end
    local rows = normalize({{name = name, ench = ench, price = tonumber(item.price),
        max_price = tonumber(item.price), qty = item.qty or 1, enabled = item.enabled, cost_price = item.cost_price}}, kind)
    if not rows then return false, 'некорректная позиция' end
    if P.find(kind, rows[1].key) then return false, 'позиция уже есть в пресете' end
    local items = P.items(kind)
    return P._transaction(function()
        items[#items + 1] = rows[1]
        return true, #items
    end)
end
function P.import_data(data, kind)
    if busy() then return false, 'остановите автоматизацию' end
    if type(data) ~= 'table' then return false, 'неверный формат' end
    local pending = {}
    local function add(k, p)
        if type(p) ~= 'table' or type(p.items) ~= 'table' then return false end
        local items = normalize(p.items, k)
        if not items then return false end
        pending[#pending + 1] = {kind = k, preset = {name = DSP.text_cp(p.name or 'Импорт'), items = items}}
        return true
    end
    if data.items then
        local k = kind or data.kind
        if k ~= 'buy' and k ~= 'sell' then return false, 'укажите тип пресета' end
        if not add(k, data) then return false, 'неверные позиции' end
    else
        for _, k in ipairs({'buy', 'sell'}) do
            local list = k == 'buy' and data.buy_presets or (data.presets or data.sell_presets)
            if type(list) == 'table' and #list > 0 then
                for _, p in ipairs(list) do if not add(k, p) then return false, 'неверные позиции' end end
            else
                local p = data[k .. '_preset']
                local old = data[k == 'buy' and 'autobuy_preset' or 'autosell_preset']
                    or data[k == 'buy' and 'autobuy_items' or 'autosell_items']
                if p and not add(k, p) then return false, 'неверные позиции' end
                if not p and old and not add(k, {items = old}) then return false, 'неверные позиции' end
            end
        end
    end
    if #pending == 0 then return false, 'нет пресетов' end
    return P._transaction(function()
        local count, imported = 0, {}
        for _, entry in ipairs(pending) do
            local list = library(entry.kind)
            list[#list + 1] = entry.preset
            imported[entry.kind] = imported[entry.kind] or {}
            imported[entry.kind][#imported[entry.kind]+1] = #list
            count = count + #entry.preset.items
        end
        for k, indices in pairs(imported) do
            local wanted = tonumber(k == 'buy' and data.active_buy_preset or data.active_preset) or 1
            wanted = math.max(1, math.min(#indices, math.floor(wanted)))
            local list_key, active_key, legacy = keys(k)
            DSP.settings[active_key] = indices[wanted]
            DSP.settings[legacy] = DSP.settings[list_key][indices[wanted]]
        end
        return true, count
    end)
end
function P.export_data(kind)
    local list, idx = library(kind)
    local items = {}
    for _, it in ipairs(list[idx].items) do
        local out = {}
        for k, v in pairs(it) do out[k] = v end
        if kind == 'buy' then out.max_price, out.target_qty = it.price, it.qty end
        items[#items + 1] = out
    end
    return {kind = kind, name = list[idx].name, created = os.date('%d.%m.%Y %H:%M'), items = items}
end
function P.import_file(path, kind)
    local f, err = io.open(path, 'rb')
    if not f then return false, err end
    local raw,read_err = f:read('*a')
    local closed,close_err=f:close()
    if not raw or not closed then return false,read_err or close_err end
    local ok, data = pcall(decodeJson, raw)
    if not ok then return false, 'ошибка JSON' end
    return P.import_data(data, kind)
end
function P.export_file(kind, path)
    if not path then
        DSP.mkdir(DSP.dir .. '/Preset')
        path = DSP.dir .. '/Preset/' .. kind .. '_' .. os.date('%Y%m%d_%H%M%S') .. '.json'
    end
    local ok, raw = pcall(encodeJson, P.export_data(kind))
    if not ok or type(raw) ~= 'string' then return false, 'ошибка JSON' end
    local temporary=path..'.tmp'
    local f, err = io.open(temporary, 'wb')
    if not f then return false, err end
    local written, write_err = f:write(raw)
    local closed, close_err = f:close()
    if not written or not closed then
        os.remove(temporary)
        return false, write_err or close_err
    end
    local renamed,rename_err=os.rename(temporary,path)
    if not renamed then os.remove(temporary);return false,rename_err end
    return true, path
end
function P.import_mh()
    local root = getWorkingDirectory():gsub('\\', '/') .. '/MarketHelper/'
    for _, name in ipairs({'MarketHelper_settings.json', 'settings.json'}) do
        local f = io.open(root .. name, 'rb')
        if f then f:close(); return P.import_file(root .. name) end
    end
    return false, 'настройки Market Helper не найдены'
end
library('buy'); library('sell')
