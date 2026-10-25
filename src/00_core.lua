-- DsPic Helper standalone core: state, settings, encoding, formatting.
DSP = DSP or {}
DSP.version = '1.0.0'
DSP.name = 'palatka ai'
DSP.acc = { 0.516, 0.505, 0.977 }

local encoding = require('encoding')
encoding.default = 'CP1251'
DSP.u8 = encoding.UTF8

function DSP.to_cp(s)
    if type(s) ~= 'string' or s == '' then return s or '' end
    local ok, r = pcall(function() return DSP.u8:decode(s) end)
    return ok and r or s
end

function DSP.to_u8(s)
    if type(s) ~= 'string' or s == '' then return s or '' end
    local ok, r = pcall(function() return DSP.u8:encode(s) end)
    return ok and r or s
end

function DSP.utf8(s)
    return DSP.to_u8(tostring(s or ''))
end

function DSP.lower(s)
    s = tostring(s or '')
    s = s:gsub('[\192-\223]', function(c)
        return string.char(string.byte(c) + 32)
    end)
    s = s:gsub('\168', '\184')
    return s:lower()
end

function DSP.trim(s)
    return (tostring(s or ''):match('^%s*(.-)%s*$')) or ''
end

function DSP.money(n)
    n = math.floor(tonumber(n) or 0)
    local neg = n < 0
    if neg then n = -n end
    local s = tostring(n)
    s = s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return (neg and '-$' or '$') .. s
end

function DSP.quantile(sorted, p)
    local n = #sorted
    if n == 0 then return 0 end
    local idx = math.ceil(p * n)
    if idx < 1 then idx = 1 elseif idx > n then idx = n end
    return sorted[idx]
end

function DSP.clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function DSP.now()
    return os.time()
end

function DSP.mkdir(path)
    if type(path) ~= 'string' or path == '' then return end
    if doesDirectoryExist and doesDirectoryExist(path) then return end
    if createDirectory then pcall(createDirectory, path) end
end

DSP.dir = (getWorkingDirectory():gsub('\\', '/')):gsub('/$', '') .. '/PalatkaAI'
DSP.mkdir(DSP.dir)

DSP.log_path = DSP.dir .. '/standalone.log'
DSP.settings_path = DSP.dir .. '/standalone_settings.json'
DSP.legacy_items_path = DSP.dir .. '/arz_items.json'
DSP.market_path = function(sid)
    return DSP.dir .. '/market_' .. tostring(sid) .. '.json'
end

DSP.settings = {
    server = 102,
    sort = 1,
    margin = 10,
    undercut = 2,
    only_profit = false,
    liquid = false,
    dry_run = true,
    per_page = 20,
    auto_buy_qty = 1,
    dpi = 1.25,
    overlay_trade = true,
    overlay_shop = true,
    overlay_top = true,
    stats_mode = 'day',
    tg_bot_token = '',
    tg_chat_id = '',
    tg_notify = false,
    log_chat_drops = true,
    chat_logs = {},
    trades = {},
    stalls = {},
    crates = {},
    buy_preset = { name = 'Скупка', items = {} },
    sell_preset = { name = 'Продажа', items = {} },
}

function DSP.save_settings()
    local ok, json = pcall(encodeJson, DSP.settings)
    if not ok or not json then return false end
    local f = io.open(DSP.settings_path, 'w')
    if not f then return false end
    f:write(json)
    f:close()
    return true
end

function DSP.load_settings()
    local f = io.open(DSP.settings_path, 'rb')
    if not f then return false end
    local raw = f:read('*a')
    f:close()
    local ok, d = pcall(decodeJson, raw)
    if not ok or type(d) ~= 'table' then return false end
    for k, v in pairs(d) do DSP.settings[k] = v end
    if type(DSP.settings.buy_preset) ~= 'table' then
        DSP.settings.buy_preset = { name = 'Скупка', items = {} }
    end
    if type(DSP.settings.sell_preset) ~= 'table' then
        DSP.settings.sell_preset = { name = 'Продажа', items = {} }
    end
    DSP.settings.buy_preset.items = DSP.settings.buy_preset.items or {}
    DSP.settings.sell_preset.items = DSP.settings.sell_preset.items or {}
    return true
end

DSP.log = {}
DSP.log_seq = 0

function DSP.flog(msg)
    local f = io.open(DSP.log_path, 'a')
    if not f then return end
    f:write(os.date('%H:%M:%S ') .. tostring(msg) .. '\n')
    f:close()
end

local function hex(s)
    return (tostring(s or ''):gsub('.', function(c) return string.format('%02X', string.byte(c)) end))
end

function DSP.enc_selftest()
    local cp = DSP.to_u8('Тест')
    local utf = DSP.to_cp(string.char(0xD0,0xA2,0xD0,0xB5,0xD1,0x81,0xD1,0x82))
    DSP.flog('enc cp=' .. hex(cp) .. ' utf=' .. hex(utf))
end

function DSP.add_log(text, kind)
    DSP.log_seq = DSP.log_seq + 1
    table.insert(DSP.log, 1, {
        id = DSP.log_seq,
        t = os.date('%H:%M:%S'),
        text = text,
        kind = kind or 'info',
    })
    while #DSP.log > 250 do table.remove(DSP.log) end
end

function DSP.notify(text)
    DSP.add_log(text)
    DSP.flog('NOTIFY ' .. tostring(text))
    if mh_notify then
        pcall(mh_notify, text, 0xFFFFFF)
    elseif sampAddChatMessage then
        pcall(sampAddChatMessage, '[DsPic] ' .. text, 0xFFAAFF)
    end
end

function DSP.item_name(name, ench)
    name = tostring(name or '')
    ench = tonumber(ench) or 0
    if ench > 0 then return name .. ' (+' .. tostring(ench) .. ')' end
    return name
end

function DSP.item_key(name, ench)
    return DSP.lower(name) .. '|' .. tostring(tonumber(ench) or 0)
end

DSP.load_settings()
DSP.flog('--- load v' .. DSP.version .. ' ---')
DSP.enc_selftest()
