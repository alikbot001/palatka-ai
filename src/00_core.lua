-- DsPic Helper standalone core: state, settings, encoding, formatting.
-- v1.2: theme registry, opacity, ui_state, screen pager state.
DSP = DSP or {}
DSP.version = '1.6.0'
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
DSP.ui_state_path = DSP.dir .. '/ui_state.json'
DSP.notes_path = DSP.dir .. '/notes.txt'
DSP.trades_log_path = DSP.dir .. '/logs/all_trades.log'
DSP.crates_log_path = DSP.dir .. '/logs/crates.log'
DSP.events_log_path = DSP.dir .. '/logs/events.jsonl'
DSP.legacy_items_path = DSP.dir .. '/arz_items.json'
DSP.market_path = function(sid)
    return DSP.dir .. '/market_' .. tostring(sid) .. '.json'
end

-- Recursive directory creation (nested dirs under DSP.dir).
-- Required for logs/ subdir where craglog appends.
function DSP.mkdir_p(path)
    if type(path) ~= 'string' or path == '' then return end
    if doesDirectoryExist and doesDirectoryExist(path) then return end
    -- Build parent first
    local parent = path:match('^(.*)/[^/]+$')
    if parent and parent ~= '' and parent ~= path
        and not (doesDirectoryExist and doesDirectoryExist(parent)) then
        DSP.mkdir_p(parent)
    end
    if createDirectory then pcall(createDirectory, path) end
end

DSP.settings = {
    server = 102,
    sort = 1,
    margin = 10,
    undercut = 2,
    only_profit = false,
    liquid = false,
    dry_run = true,
    refresh_seconds = 60,
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
    -- v1.2 additions
    theme = 'ocean_blue',
    opacity = 0.97,
    screen = 'palatka',
    crag_pinned = false,
    crag_pos = nil,
    -- v1.2 Stage 2 additions: CR tax + arbitrage filters
    -- tax_bp is in basis points: 100=1%, 200=2%, 300=3%, 400=4%
    -- Default 200 (Titan/Premium). Set in Settings -> Комиссия ЦР.
    tax_bp = 200,
    arb_filters = {
        budget = 0,         -- 0 = no budget filter
        min_profit = 0,     -- 0 = show all
        min_roi = 0,        -- 0 = show all (percent)
        sort = 1,           -- 1=profit party, 2=profit per unit, 3=ROI
        max_age = 1800,
        max_qty = 0,
        allow_partial = true,
        include_unknown = true,
    },
    -- v1.2 Stage 3 additions: craglog + telegram payday
    craglog = {
        open = false,        -- /crlog mini-window visibility
        minimized = false,   -- collapsed into a thin bar
        pinned = false,      -- prevent collapse while pinned
        filter = 'all',      -- 'all' | 'sales' | 'buys'
    },
    tg_payday_last = 0,      -- epoch ts of last PayDay telegram (avoid dupes within same hour)
    tg_payday_enabled = false,
}

function DSP.save_settings()
    local ok, json = pcall(encodeJson, DSP.settings)
    if not ok or type(json) ~= 'string' then return false, 'settings encode failed' end
    local temporary = DSP.settings_path .. '.tmp'
    local f, err = io.open(temporary, 'w')
    if not f then return false, err end
    local written, write_error = f:write(json)
    local closed, close_error = f:close()
    if not written or not closed then return false, write_error or close_error end
    local renamed, rename_error = os.rename(temporary, DSP.settings_path)
    if not renamed then return false, rename_error end
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
    if type(DSP.settings.theme) ~= 'string' then DSP.settings.theme = 'ocean_blue' end
    if type(DSP.settings.opacity) ~= 'number' then DSP.settings.opacity = 0.97 end
    if type(DSP.settings.screen) ~= 'string' then DSP.settings.screen = 'palatka' end
    if type(DSP.settings.tax_bp) ~= 'number' then DSP.settings.tax_bp = 200 end
    if type(DSP.settings.arb_filters) ~= 'table' then
        DSP.settings.arb_filters = { budget = 0, min_profit = 0, min_roi = 0, sort = 1 }
    else
        -- ensure all subfields exist
        DSP.settings.arb_filters.budget = tonumber(DSP.settings.arb_filters.budget) or 0
        DSP.settings.arb_filters.min_profit = tonumber(DSP.settings.arb_filters.min_profit) or 0
        DSP.settings.arb_filters.min_roi = tonumber(DSP.settings.arb_filters.min_roi) or 0
        DSP.settings.arb_filters.sort = tonumber(DSP.settings.arb_filters.sort) or 1
    end
    -- v1.2 Stage 3: craglog state
    if type(DSP.settings.craglog) ~= 'table' then
        DSP.settings.craglog = { open = false, minimized = false, pinned = false, filter = 'all' }
    else
        DSP.settings.craglog.open = DSP.settings.craglog.open and true or false
        DSP.settings.craglog.minimized = DSP.settings.craglog.minimized and true or false
        DSP.settings.craglog.pinned = DSP.settings.craglog.pinned and true or false
        local f = DSP.settings.craglog.filter
        if f ~= 'all' and f ~= 'sales' and f ~= 'buys' and f ~= 'loot' and f ~= 'income' and f ~= 'payday' then f = 'all' end
        DSP.settings.craglog.filter = f
    end
    if type(DSP.settings.tg_payday_last) ~= 'number' then DSP.settings.tg_payday_last = 0 end
    if type(DSP.settings.tg_payday_enabled) ~= 'boolean' then DSP.settings.tg_payday_enabled = false end
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
    -- v1.2: strict key includes enchant level so +0 stock is never matched against +12 buyback.
    name = DSP.trim(tostring(name or ''):gsub('{%x+}', ''))
    return DSP.lower(name) .. '@' .. tostring(tonumber(ench) or 0)
end

-- =========================================================================
-- v1.2 THEME REGISTRY
-- 5 themes: dark_amber, amoled, cyberpunk, purple, emerald
-- Each palette has: bg, panel, accent, text, muted, good, bad, warn
-- (all values are RGB 0..1; alpha is applied separately via opacity)
-- =========================================================================
DSP.theme = DSP.theme or {}

DSP.theme.list = {
    ocean_blue = {
        name = 'Palatka Blue',
        bg={0.032,0.059,0.095},panel={0.060,0.103,0.160},accent={0.055,0.53,1.0},
        text={0.94,0.965,1.0},muted={0.62,0.74,0.86},good={0.13,0.88,0.54},
        bad={0.98,0.31,0.44},warn={1.0,0.72,0.22},
    },
    dark_amber = {
        name = 'Dark Amber',
        bg     = { 0.047, 0.055, 0.071 },
        panel  = { 0.078, 0.090, 0.110 },
        accent = { 0.95, 0.73, 0.34 },
        text   = { 0.94, 0.95, 0.97 },
        muted  = { 0.60, 0.65, 0.73 },
        good   = { 0.45, 0.95, 0.45 },
        bad    = { 1.00, 0.42, 0.38 },
        warn   = { 1.00, 0.82, 0.30 },
    },
    amoled = {
        name = 'AMOLED Black',
        bg     = { 0.000, 0.000, 0.000 },
        panel  = { 0.040, 0.040, 0.040 },
        accent = { 0.55, 0.72, 1.00 },
        text   = { 1.00, 1.00, 1.00 },
        muted  = { 0.55, 0.55, 0.55 },
        good   = { 0.45, 0.95, 0.45 },
        bad    = { 1.00, 0.42, 0.38 },
        warn   = { 1.00, 0.82, 0.30 },
    },
    cyberpunk = {
        name = 'Cyberpunk Neon',
        bg     = { 0.045, 0.025, 0.090 },
        panel  = { 0.090, 0.045, 0.140 },
        accent = { 1.00, 0.20, 0.80 },
        text   = { 0.90, 0.90, 0.95 },
        muted  = { 0.60, 0.55, 0.70 },
        good   = { 0.20, 1.00, 0.50 },
        bad    = { 1.00, 0.30, 0.30 },
        warn   = { 1.00, 0.85, 0.10 },
    },
    purple = {
        name = 'Purple Luxury',
        bg     = { 0.075, 0.050, 0.115 },
        panel  = { 0.130, 0.085, 0.180 },
        accent = { 0.65, 0.45, 0.95 },
        text   = { 0.95, 0.92, 0.95 },
        muted  = { 0.55, 0.50, 0.65 },
        good   = { 0.45, 0.95, 0.50 },
        bad    = { 1.00, 0.42, 0.42 },
        warn   = { 1.00, 0.80, 0.40 },
    },
    emerald = {
        name = 'Emerald Market',
        bg     = { 0.045, 0.075, 0.065 },
        panel  = { 0.070, 0.115, 0.100 },
        accent = { 0.30, 0.85, 0.55 },
        text   = { 0.92, 0.95, 0.93 },
        muted  = { 0.55, 0.65, 0.60 },
        good   = { 0.45, 0.95, 0.45 },
        bad    = { 1.00, 0.42, 0.38 },
        warn   = { 1.00, 0.82, 0.30 },
    },
}

DSP.theme.current = 'ocean_blue'
DSP.theme.opacity = 0.97

function DSP.theme.get()
    return DSP.theme.list[DSP.theme.current] or DSP.theme.list.dark_amber
end

-- Return ImVec4 for a palette key with optional alpha override.
-- Safe to call even before imgui is loaded (returns a plain table).
-- v1.2 hotfix: wrap in pcall so a malformed ImVec4 call (e.g. nil c[1])
-- doesn't propagate into a native SIGSEGV via FFI.
function DSP.theme.col(key, alpha)
    local t = DSP.theme.get()
    local c = t[key] or { 0.5, 0.5, 0.5 }
    local a = alpha ~= nil and alpha or 1
    if imgui and imgui.ImVec4 then
        local ok, vec = pcall(imgui.ImVec4, c[1] or 0.5, c[2] or 0.5, c[3] or 0.5, a)
        if ok then return vec end
    end
    return { r = c[1], g = c[2], b = c[3], a = a }
end

function DSP.theme.set(name)
    if DSP.theme.list[name] then
        DSP.theme.current = name
        DSP.settings.theme = name
        DSP.save_settings()
        DSP.add_log('Тема: ' .. DSP.theme.list[name].name)
    end
end

function DSP.theme.set_opacity(v)
    DSP.theme.opacity = DSP.clamp(v, 0.65, 1.00)
    DSP.settings.opacity = DSP.theme.opacity
    DSP.save_settings()
end

-- Push the full ImGui style palette for the active theme.
-- Returns the number of pushed colors to be popped via imgui.PopStyleColor(N).
-- Also pushes WindowRounding / FrameRounding / ItemSpacing style vars (pop with 3).
-- v1.2 hotfix: each PushStyleColor is wrapped in pcall so a single bad enum
-- doesn't abort the whole theme push (which would leave the color stack
-- unbalanced and crash the game on the next frame).
function DSP.theme.push_window()
    local t = DSP.theme.get()
    local a = DSP.theme.opacity
    local function c(k, alpha)
        local p = t[k] or { 0.5, 0.5, 0.5 }
        return imgui.ImVec4(p[1], p[2], p[3], alpha == nil and 1 or alpha)
    end
    local count = 0
    local function push(col_enum, vec)
        if col_enum and vec then
            local ok = pcall(imgui.PushStyleColor, col_enum, vec)
            if ok then count = count + 1 end
        end
    end
    push(imgui.Col.WindowBg,        c('bg',     a))
    push(imgui.Col.TitleBg,         c('panel',  1))
    push(imgui.Col.TitleBgActive,   imgui.ImVec4(t.accent[1]*0.35, t.accent[2]*0.35, t.accent[3]*0.35, 1))
    push(imgui.Col.Border,          imgui.ImVec4(t.text[1]*0.19, t.text[2]*0.19, t.text[3]*0.19, 1))
    push(imgui.Col.Button,          imgui.ImVec4(t.panel[1]+.055, t.panel[2]+.055, t.panel[3]+.055, 1))
    push(imgui.Col.ButtonHovered,   imgui.ImVec4(t.panel[1]+.10, t.panel[2]+.10, t.panel[3]+.10, 1))
    push(imgui.Col.ButtonActive,    imgui.ImVec4(t.panel[1]+.15, t.panel[2]+.15, t.panel[3]+.15, 1))
    push(imgui.Col.Header,          imgui.ImVec4(t.accent[1]*0.45, t.accent[2]*0.45, t.accent[3]*0.45, 1))
    push(imgui.Col.HeaderHovered,   imgui.ImVec4(t.accent[1]*0.65, t.accent[2]*0.65, t.accent[3]*0.65, 1))
    push(imgui.Col.ChildBg,         c('panel',  1))
    push(imgui.Col.FrameBg,         imgui.ImVec4(t.panel[1]+.04, t.panel[2]+.04, t.panel[3]+.04, 1))
    push(imgui.Col.FrameBgHovered,  imgui.ImVec4(t.accent[1]*0.50, t.accent[2]*0.50, t.accent[3]*0.50, 0.95))
    push(imgui.Col.Text,            c('text',   1))
    push(imgui.Col.TextDisabled,    c('muted',  1))
    push(imgui.Col.Separator,       imgui.ImVec4(t.text[1]*.18, t.text[2]*.18, t.text[3]*.18, 1))
    push(imgui.Col.ScrollbarBg,     c('bg',     0.50))
    push(imgui.Col.ScrollbarGrab,   imgui.ImVec4(t.accent[1]*0.60, t.accent[2]*0.60, t.accent[3]*0.60, 1))
    push(imgui.Col.ScrollbarGrabHovered, imgui.ImVec4(t.accent[1]*0.80, t.accent[2]*0.80, t.accent[3]*0.80, 1))
    push(imgui.Col.ScrollbarGrabActive,  imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], 1))
    push(imgui.Col.PopupBg,        c('panel',  0.98))
    -- v1.2 hotfix: FFI mimgui declares the enum as `ImGuiCol_CheckMark`
    -- (capital M). Lowercase `Checkmark` raised "missing declaration for
    -- symbol 'ImGuiCol_Checkmark'" and crashed the script on first frame.
    push(imgui.Col.CheckMark,      c('accent', 1))
    push(imgui.Col.SliderGrab,      c('accent', 1))
    push(imgui.Col.SliderGrabActive, c('accent', 1))
    return count
end

-- Compact 4-color push for overlay subwindows that already manage their own layout.
-- v1.2 hotfix: dynamically counts pushed colors so pop never mismatches.
function DSP.theme.push_overlay(accent_alpha)
    local t = DSP.theme.get()
    local a = DSP.theme.opacity
    local count = 0
    local function push(col_enum, vec)
        if col_enum and vec then
            local ok = pcall(imgui.PushStyleColor, col_enum, vec)
            if ok then count = count + 1 end
        end
    end
    push(imgui.Col.WindowBg,      imgui.ImVec4(t.bg[1], t.bg[2], t.bg[3], a))
    push(imgui.Col.Border,        imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], accent_alpha or 0.95))
    push(imgui.Col.Button,        imgui.ImVec4(t.panel[1], t.panel[2], t.panel[3], 1))
    push(imgui.Col.ButtonHovered, imgui.ImVec4(t.accent[1]*0.7, t.accent[2]*0.7, t.accent[3]*0.7, 1))
    return count
end

-- UI state persistence (CR button position, screen, theme transient)
function DSP.load_ui_state()
    local f = io.open(DSP.ui_state_path, 'rb')
    if not f then return false end
    local raw = f:read('*a')
    f:close()
    local ok, d = pcall(decodeJson, raw)
    if not ok or type(d) ~= 'table' then return false end
    if type(d.cr_pos) == 'table' then
        DSP.settings.cr_pos = { x = tonumber(d.cr_pos.x) or 28, y = tonumber(d.cr_pos.y) or 215 }
    end
    if type(d.screen) == 'string' then DSP.settings.screen = d.screen end
    if type(d.theme) == 'string' then DSP.settings.theme = d.theme end
    if type(d.opacity) == 'number' then DSP.settings.opacity = d.opacity end
    return true
end

function DSP.save_ui_state()
    local pack = {
        cr_pos = DSP.settings.cr_pos or { x = 28, y = 215 },
        screen = DSP.settings.screen or 'palatka',
        theme = DSP.theme.current,
        opacity = DSP.theme.opacity,
        saved_at = os.time(),
    }
    local ok, json = pcall(encodeJson, pack)
    if not ok or not json then return false end
    local f = io.open(DSP.ui_state_path, 'w')
    if not f then return false end
    f:write(json)
    f:close()
    return true
end

DSP.load_settings()
DSP.load_ui_state()
-- Migrate the stock 1.3.x amber look on first v1.4 launch. Respect custom themes.
if not DSP.settings.ui_v14_migrated then
    if DSP.settings.theme=='dark_amber' then DSP.settings.theme='ocean_blue' end
    DSP.settings.ui_v14_migrated=true
    DSP.save_settings()
end
DSP.theme.current = DSP.settings.theme or 'ocean_blue'
DSP.save_ui_state()
DSP.theme.opacity = DSP.clamp(DSP.settings.opacity or 0.97, 0.65, 1.00)
DSP.flog('--- load v' .. DSP.version .. ' theme=' .. DSP.theme.current .. ' opacity=' .. tostring(DSP.theme.opacity) .. ' ---')
DSP.enc_selftest()
