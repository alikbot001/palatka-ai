-- Palatka AI v1.3.3, built from src/*.lua (independent of Market Helper)
script_name('palatka ai')
script_author('palatka ai')
script_version('1.3.3')

if not imgui then imgui = require('mimgui') end
DSP = DSP or {}

local function __mod_00_core()
-- DsPic Helper standalone core: state, settings, encoding, formatting.
-- v1.2: theme registry, opacity, ui_state, screen pager state.
DSP = DSP or {}
DSP.version = '1.3.3'
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
    theme = 'dark_amber',
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
    if type(DSP.settings.theme) ~= 'string' then DSP.settings.theme = 'dark_amber' end
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
        if f ~= 'all' and f ~= 'sales' and f ~= 'buys' and f ~= 'loot' then f = 'all' end
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

DSP.theme.current = 'dark_amber'
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
DSP.theme.current = DSP.settings.theme or 'dark_amber'
DSP.theme.opacity = DSP.clamp(DSP.settings.opacity or 0.97, 0.65, 1.00)
DSP.flog('--- load v' .. DSP.version .. ' theme=' .. DSP.theme.current .. ' opacity=' .. tostring(DSP.theme.opacity) .. ' ---')
DSP.enc_selftest()

end
__mod_00_core()

local function __mod_05_items()
-- Item catalog: numeric item id -> CP1251 name.
DSP.items = DSP.items or { by_id = {}, loaded = false }

local function valid_utf8(s)
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        if c < 0x80 then
            i = i + 1
        elseif c >= 0xC2 and c <= 0xDF then
            local c2 = s:byte(i + 1)
            if not c2 or c2 < 0x80 or c2 > 0xBF then return false end
            i = i + 2
        elseif c >= 0xE0 and c <= 0xEF then
            local c2, c3 = s:byte(i + 1), s:byte(i + 2)
            if not c2 or not c3 or c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF then return false end
            i = i + 3
        elseif c >= 0xF0 and c <= 0xF4 then
            local c2, c3, c4 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
            if not c2 or not c3 or not c4
                or c2 < 0x80 or c2 > 0xBF
                or c3 < 0x80 or c3 > 0xBF
                or c4 < 0x80 or c4 > 0xBF then return false end
            i = i + 4
        else
            return false
        end
    end
    return true
end

function DSP.text_cp(s)
    if type(s) ~= 'string' or s == '' then return s or '' end
    if s:find('[\194-\244]') and valid_utf8(s) then
        local ok, r = pcall(function() return DSP.u8:decode(s) end)
        if ok and r and r ~= '' then return r end
    end
    return s
end

function DSP.clean_text(s)
    s = DSP.text_cp(tostring(s or ''))
    return (s:gsub('{[%x]+}', ''):match('^%s*(.-)%s*$')) or ''
end

function DSP.parse_item_id(raw, ench)
    local base, e = 0, 0
    if type(raw) == 'number' then
        base = math.floor(raw)
    else
        local s = tostring(raw or '')
        base = tonumber(s:match('^(%d+)')) or 0
        e = tonumber(s:match('%((%d+)%)')) or 0
    end
    local e_field = tonumber(ench)
    if e_field and e_field > 0 then e = e_field end
    e = e or 0
    if e < 0 or e > 20 then e = 0 end
    return base, math.floor(e)
end

function DSP.items.name(id)
    id = tonumber(id) or 0
    local nm = DSP.items.by_id[id]
    if nm and nm ~= '' then return DSP.clean_text(nm) end
    return 'ID:' .. tostring(id)
end

function DSP.items.display(raw, ench)
    local id, e = DSP.parse_item_id(raw, ench)
    return DSP.item_name(DSP.items.name(id), e), id, e
end

local function parse_flat(raw)
    local data = {}
    for k, v in tostring(raw or ''):gmatch('"(%d+)"%s*:%s*"([^"]*)"') do
        data[k] = v
    end
    return data
end

function DSP.items.load()
    local root = (getWorkingDirectory() or '.'):gsub('\\', '/'):gsub('/$', '')
    local paths = {
        DSP.dir .. '/items_data.json',
        DSP.dir .. '/arz_items.json',
        root .. '/MarketHelper/items_data.json',
        root .. '/MarketHelper/arz_items.json',
    }
    for _, path in ipairs(paths) do
        local f = io.open(path, 'rb')
        if f then
            local raw = f:read('*a') or ''
            f:close()
            local ok, data = pcall(decodeJson, raw)
            if not ok or type(data) ~= 'table' then
                data = parse_flat(raw)
                ok = next(data) ~= nil
            end
            local n = 0
            if ok and type(data) == 'table' then
                for k, v in pairs(data) do
                    local id = tonumber(k)
                    if id and type(v) == 'string' and v ~= '' then
                        DSP.items.by_id[id] = v
                        n = n + 1
                    end
                end
            end
            if n == 0 then
                data = parse_flat(raw)
                for k, v in pairs(data) do
                    local id = tonumber(k)
                    if id and type(v) == 'string' and v ~= '' then
                        DSP.items.by_id[id] = v
                        n = n + 1
                    end
                end
            end
            if n > 0 then
                DSP.items.loaded = true
                DSP.flog('ITEMS loaded=' .. tostring(n) .. ' path=' .. path)
                return true
            end
            DSP.flog('ITEMS parse failed path=' .. path)
        end
    end
    DSP.flog('ITEMS missing catalog')
    return false
end

end
__mod_05_items()

local function __mod_10_market()
-- Live lavka market: pull, enchant-aware stats, cache.
DSP.market = DSP.market or {}

DSP.market.api = 'https://va-ta.com/api/shops/pull'
DSP.market.state = {
    sid = DSP.settings.server or 102,
    status = 'idle',
    error = nil,
    rows = {},
    by_key = {},
    shops = 0,
    offers = 0,
    updated = 0,
    saved_at = 0,
    version = 0,
    filter_cache = nil,
    filter_version = -1,
    page = 1,
}

DSP.market.servers = {
    { id = 101, name = 'Mobile I' },
    { id = 102, name = 'Mobile II' },
    { id = 103, name = 'Mobile III' },
}

function _G.dsp_http_get(url)
    local ok, requests = pcall(require, 'requests')
    if not ok or not requests then return { code = 0, body = '', err = 'requests missing' } end
    local ok2, resp = pcall(requests.request, 'GET', url)
    if not ok2 or not resp then return { code = 0, body = '', err = 'request failed: ' .. tostring(resp) } end
    return { code = tonumber(resp.status_code) or 0, body = tostring(resp.text or ''), err = nil }
end

local function effil_result(thread)
    local ok_get, result = pcall(function() return thread:get() end)
    if not ok_get then
        return nil, tostring(result)
    end
    if type(result) == 'table' or type(result) == 'userdata' then
        local code = tonumber(result.code or result[1] or 0)
        local body = tostring(result.body or result[2] or '')
        local werr = result.err or result[3]
        return { code = code, body = body, err = werr }, nil
    end
    if type(result) == 'number' then
        return { code = result, body = '', err = nil }, nil
    end
    return nil, 'unexpected result type: ' .. type(result)
end

function DSP.http_get(url, cb)
    local ok, effil = pcall(require, 'effil')
    if not ok or not effil then
        return cb(nil, 'effil missing')
    end
    local ok_th, thread = pcall(function() return effil.thread(_G.dsp_http_get)(url) end)
    if not ok_th or not thread then
        return cb(nil, 'thread create: ' .. tostring(thread))
    end
    lua_thread.create(function()
        local deadline = os.time() + 60
        while true do
            wait(25)
            if os.time() > deadline then
                pcall(function() thread:cancel() end)
                return cb(nil, 'timeout')
            end
            local ok_status, status, err = pcall(function() return thread:status() end)
            if not ok_status then
                return cb(nil, 'thread status error')
            end
            if status == 'completed' or status == 'canceled' then
                local res, rerr = effil_result(thread)
                if not res then
                    return cb(nil, 'get: ' .. tostring(rerr))
                end
                if res.code ~= 200 then
                    return cb(nil, 'HTTP ' .. tostring(res.code) .. (res.err and (' ' .. tostring(res.err)) or ''))
                end
                if type(res.body) ~= 'string' or res.body == '' then
                    return cb(nil, 'empty response')
                end
                return cb(res.body, nil)
            end
            if status == 'error' or status == 'failed' then
                local e = tostring(err or 'thread error')
                if type(err) == 'table' and err.message then e = err.message end
                return cb(nil, e)
            end
        end
    end)
end

function DSP.player_nick()
    local nick = ''
    pcall(function()
        local ok, pid = sampGetPlayerIdByCharHandle(PLAYER_PED)
        if ok then nick = sampGetPlayerNickname(pid) or '' end
    end)
    if nick == '' then pcall(function() nick = sampGetCurrentPlayerName() or '' end) end
    if nick == '' then nick = 'DsPic' end
    return nick
end

function DSP.detect_server()
    local name = ''
    pcall(function() name = sampGetCurrentServerName() or '' end)
    name = DSP.lower(name)
    if name ~= '' then
        if name:find('mobile%s*iii') or name:find('mobile%s*3') then return 103 end
        if name:find('mobile%s*ii') or name:find('mobile%s*2') then return 102 end
        if name:find('mobile%s*i') or name:find('mobile%s*1') then return 101 end
    end
    return nil
end

local function sanitize_ench(v)
    local e = tonumber(v) or 0
    if e < 0 or e > 20 then e = 0 end
    return math.floor(e)
end

local function item_units(value)
    local n = tonumber(value)
    if not n or n ~= n or n < 0 or n == math.huge or n > 9007199254740991 then
        return 0
    end
    return math.floor(n)
end

local function add_offer(map, name, ench, offer)
    if name == '' or offer.price <= 0 then return end
    local key = DSP.item_key(name, ench)
    local row = map[key]
    if not row then
        row = {
            key = key,
            name = name,
            ench = ench,
            display = DSP.item_name(name, ench),
            sell = { offers = {}, prices = {}, n = 0, qty = 0, shops = {} },
            buy = { offers = {}, prices = {}, n = 0, qty = 0, shops = {} },
        }
        map[key] = row
    end
    local side = offer.side == 'sell' and row.sell or row.buy
    side.n = side.n + 1
    side.qty = side.qty + offer.qty
    side.prices[#side.prices + 1] = offer.price
    side.shops[offer.shop] = true
    -- One stall may expose multiple slots of the same item at the same price.
    -- They are one actionable stock pool; different prices stay separate.
    side.offer_index = side.offer_index or {}
    local slot_key = tostring(offer.shop) .. '\0' .. tostring(offer.price)
    local existing = side.offer_index[slot_key]
    if existing then
        existing.qty = existing.qty + offer.qty
        existing.slots = (existing.slots or 1) + 1
    else
        offer.slots = 1
        side.offer_index[slot_key] = offer
        side.offers[#side.offers + 1] = offer
    end
end

local function finish_side(side, asc)
    table.sort(side.prices)
    local n = #side.prices
    side.count = n
    if n == 0 then
        side.min, side.max, side.p25, side.med, side.p75 = 0, 0, 0, 0, 0
        side.best = 0
        return
    end
    side.min = side.prices[1]
    side.max = side.prices[n]
    side.p25 = DSP.quantile(side.prices, 0.25)
    side.med = DSP.quantile(side.prices, 0.50)
    side.p75 = DSP.quantile(side.prices, 0.75)
    side.best = asc and side.min or side.max
    table.sort(side.offers, function(a, b)
        if a.price ~= b.price then
            if asc then
                return a.price < b.price
            else
                return a.price > b.price
            end
        end
        return (a.qty or 0) > (b.qty or 0)
    end)
    local shop_n = 0
    for _ in pairs(side.shops) do shop_n = shop_n + 1 end
    side.shop_n = shop_n
end

function DSP.market.rebuild(payload, sid)
    sid = tonumber(sid) or DSP.market.state.sid
    local shops = type(payload) == 'table' and payload.shops or {}
    local map = {}
    local offers_n, shops_n = 0, 0
    local newest, oldest = 0, 0
    -- v1.2 hotfix: yield to the scheduler every 50 shops when called from
    -- a coroutine (http_get callback path). When called sync (load_cache path
    -- at script init), coroutine.running() returns nil and we don't yield.
    -- This prevents the 2500-row rebuild from blocking the render thread
    -- for ~1 second on Samsung A15 -> game freeze -> system kill.
    local co = (coroutine and coroutine.running and coroutine.running()) or nil
    local can_yield = co ~= nil and wait ~= nil
    local yield_count = 0
    for shop_idx, shop in ipairs(shops) do
        local ssid = tonumber(shop.server_id)
        if not ssid or ssid == sid then
            local owner = DSP.to_cp(shop.owner or '?')
            local shop_num = tostring(shop.shop_num or '?')
            local ts = tonumber(shop.updated_at or 0) or 0
            if ts > 0 then
                if newest == 0 or ts > newest then newest = ts end
                if oldest == 0 or ts < oldest then oldest = ts end
            end
            local has_slot = false
            for _, slot in ipairs(shop.sell_slots or {}) do
                local name = DSP.to_cp(slot.name or '')
                local price = tonumber(slot.price) or 0
                local qty = item_units(slot.qty)
                if name ~= '' and price > 0 and qty > 0 then
                    has_slot = true
                    offers_n = offers_n + 1
                    -- v1.2 Stage 2 fix: shop.sell_slots = лавка ПРОДАЁТ игроку -> player BUYS.
                    -- Store in row.sell (лавка продаёт) so the UI label matches the data
                    -- AND finish_side's asc sort + best=min gives the cheapest price
                    -- for the player to buy at.
                    add_offer(map, name, sanitize_ench(slot.ench), {
                        side = 'sell', price = price, qty = qty,
                        owner = owner, shop = shop_num,
                        ench = sanitize_ench(slot.ench),
                        ts = ts,
                    })
                end
            end
            for _, slot in ipairs(shop.buy_slots or {}) do
                local name = DSP.to_cp(slot.name or '')
                local price = tonumber(slot.price) or 0
                local qty = item_units(slot.qty)
                if name ~= '' and price > 0 and qty > 0 then
                    has_slot = true
                    offers_n = offers_n + 1
                    -- v1.2 Stage 2 fix: shop.buy_slots = лавка СКУПАЕТ у игрока -> player SELLS.
                    -- Store in row.buy (лавка скупает); finish_side sorts desc, best=max
                    -- so row.buy.best = the highest buyback price (best for the player to sell to).
                    add_offer(map, name, sanitize_ench(slot.ench), {
                        side = 'buy', price = price, qty = qty,
                        owner = owner, shop = shop_num,
                        ench = sanitize_ench(slot.ench),
                        ts = ts,
                    })
                end
            end
            if has_slot then shops_n = shops_n + 1 end
        end
        -- Yield to scheduler every 50 shops if we're in a coroutine.
        -- pcall protects against wait() being called across C boundaries.
        if can_yield and shop_idx % 50 == 0 then
            pcall(wait, 0)
            yield_count = yield_count + 1
        end
    end
    local rows = {}
    for _, row in pairs(map) do
        finish_side(row.sell, true)
        finish_side(row.buy, false)
        if row.sell.count > 0 and row.buy.count > 0 then
            row.profit = row.buy.max - row.sell.min
            row.profit_med = row.buy.med - row.sell.med
            row.profit_pct = row.sell.min > 0 and (row.profit / row.sell.min * 100) or 0
        else
            row.profit, row.profit_med, row.profit_pct = 0, 0, 0
        end
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b)
        if (a.profit or 0) ~= (b.profit or 0) then return (a.profit or 0) > (b.profit or 0) end
        if (a.sell.best or 0) ~= (b.sell.best or 0) then return (a.sell.best or 0) < (b.sell.best or 0) end
        return a.display < b.display
    end)
    DSP.market.state.rows = rows
    DSP.market.state.by_key = map
    DSP.market.state.sid = sid
    DSP.market.state.shops = shops_n
    DSP.market.state.offers = offers_n
    DSP.market.state.updated = newest
    DSP.market.state.oldest = oldest
    DSP.market.state.version = DSP.market.state.version + 1
    DSP.market.state.filter_version = -1
    DSP.market.state.error = nil
    DSP.market.state.status = 'live'
    -- v1.2 hotfix: invalidate arbitrage cache. The market data changed,
    -- so the cached arbitrage list is now stale and must be recomputed
    -- on the next call to arbitrage_filtered().
    DSP.market.arb_dirty = true
    DSP.market.arb_cache = nil
    DSP.market.arb_cache_version = -1
    if yield_count > 0 then
        DSP.flog('REBUILD chunked: shops=' .. tostring(#shops) .. ' yields=' .. tostring(yield_count))
    end
    if DSP.db and DSP.db.set_rows then
        local ok_db, err_db = pcall(DSP.db.set_rows, rows, sid)
        if not ok_db then DSP.flog('DB set error: ' .. tostring(err_db)) end
    end
end

function DSP.market.freshness()
    local ts = DSP.market.state.updated
    if not ts or ts <= 0 then return 'нет данных' end
    local age = math.max(0, os.time() - ts)
    if age < 60 then return age .. ' сек' end
    if age < 3600 then return math.floor(age / 60) .. ' мин' end
    if age < 86400 then return math.floor(age / 3600) .. ' ч' end
    return math.floor(age / 86400) .. ' дн'
end

function DSP.market.url(sid)
    return DSP.market.api
        .. '?server=' .. tostring(sid)
        .. '&nick=' .. tostring(DSP.player_nick())
        .. '&ver=' .. tostring(DSP.version)
end

function DSP.market.clear_for_server(sid)
    local st = DSP.market.state
    if tonumber(st.sid) == tonumber(sid) then return end
    st.rows, st.by_key = {}, {}
    st.shops, st.offers, st.updated, st.oldest, st.saved_at = 0, 0, 0, 0, 0
    st.filter_cache, st.filter_version = nil, -1
    st.version = (st.version or 0) + 1
    st.sid = sid
    DSP.market.invalidate_arbitrage()
end

function DSP.market.pull(sid, done)
    sid = tonumber(sid) or DSP.market.state.sid
    if DSP.market.state.status == 'loading' then return end
    DSP.market.clear_for_server(sid)
    DSP.market.state.sid = sid
    DSP.market.state.status = 'loading'
    DSP.market.state.last_request = os.time()
    DSP.market.state.error = nil
    DSP.market.state.nick = DSP.player_nick()
    DSP.add_log('Запрос рынка Mobile ' .. tostring(sid) .. '...')
    DSP.flog('PULL start sid=' .. tostring(sid) .. ' nick=' .. DSP.player_nick())
    DSP.http_get(DSP.market.url(sid), function(body, err)
        if not body then
            DSP.flog('PULL error: ' .. tostring(err))
            DSP.market.state.status = 'error'
            DSP.market.state.error = tostring(err or 'ошибка')
            DSP.add_log('Рынок: ' .. DSP.market.state.error, 'error')
            if done then done(false, err) end
            return
        end
        DSP.flog('PULL body bytes=' .. tostring(#body) .. ' head=' .. body:sub(1, 80):gsub('[\r\n]', ' '))
        local ok, payload = pcall(decodeJson, body)
        if not ok or type(payload) ~= 'table' then
            DSP.flog('PULL decode error: ' .. tostring(payload))
            DSP.market.state.status = 'error'
            DSP.market.state.error = 'JSON: ' .. tostring(payload)
            DSP.add_log('Рынок: JSON ' .. tostring(payload), 'error')
            if done then done(false, payload) end
            return
        end
        if type(payload.shops) ~= 'table' then
            DSP.market.state.status = 'error'
            DSP.market.state.error = 'API: нет списка лавок'
            if done then done(false, DSP.market.state.error) end
            return
        end
        pcall(function() DSP.market.save_cache(sid, body) end)
        DSP.market.state.sid = sid
        DSP.settings.server = sid
        DSP.save_settings()
        DSP.market.rebuild(payload, sid)
        DSP.flog(string.format('PULL ok shops=%d offers=%d rows=%d newest=%d',
            DSP.market.state.shops, DSP.market.state.offers, #DSP.market.state.rows, DSP.market.state.updated))
        DSP.add_log(string.format('Рынок: %d лавок, %d офферов, свежесть %s',
            DSP.market.state.shops, DSP.market.state.offers, DSP.market.freshness()))
        if done then done(true) end
    end)
end

function DSP.market.save_cache(sid, body)
    local payload = encodeJson({ saved_at = os.time(), body = body })
    if not payload then return end
    local f = io.open(DSP.market_path(sid), 'w')
    if not f then return end
    f:write(payload)
    f:close()
end

function DSP.market.rebuild_legacy(pack, sid)
    local function side(src, asc)
        src = src or {}
        local min = tonumber(src.min) or 0
        local max = tonumber(src.max) or 0
        local n = tonumber(src.n) or #(src.offers or {})
        return {
            min = min, max = max,
            p25 = tonumber(src.p25) or min,
            med = tonumber(src.med) or min,
            p75 = tonumber(src.p75) or max,
            best = tonumber(src.best) or (asc and min or max),
            count = n, qty = tonumber(src.qty) or 0,
        }
    end
    local rows, map = {}, {}
    for _, it in ipairs(pack.items or {}) do
        local name = DSP.clean_text(it.name or it.key or '')
        if name ~= '' then
            local sell, buy = side(it.sell, true), side(it.buy, false)
            local key = DSP.item_key(name, 0)
            local row = {
                key = key, name = name, ench = 0,
                display = DSP.item_name(name, 0),
                sell = sell, buy = buy,
            }
            row.profit = (sell.count > 0 and buy.count > 0) and (buy.max - sell.min) or 0
            row.profit_med = (sell.count > 0 and buy.count > 0) and (buy.med - sell.med) or 0
            row.profit_pct = sell.min > 0 and (row.profit / sell.min * 100) or 0
            rows[#rows + 1] = row
            map[key] = row
        end
    end
    table.sort(rows, function(a, b)
        if (a.profit or 0) ~= (b.profit or 0) then return (a.profit or 0) > (b.profit or 0) end
        return a.display < b.display
    end)
    DSP.market.state.rows = rows
    DSP.market.state.by_key = map
    DSP.market.state.sid = tonumber(sid) or DSP.market.state.sid
    DSP.market.state.shops = tonumber(pack.shops) or 0
    DSP.market.state.offers = tonumber(pack.offers) or 0
    DSP.market.state.updated = tonumber(pack.newest) or tonumber(pack.ts) or 0
    DSP.market.state.oldest = tonumber(pack.oldest) or 0
    DSP.market.state.version = DSP.market.state.version + 1
    DSP.market.state.filter_version = -1
    DSP.market.state.error = nil
    DSP.market.state.status = 'cache'
    if DSP.db and DSP.db.set_rows then
        local ok_db, err_db = pcall(DSP.db.set_rows, rows, sid)
        if not ok_db then DSP.flog('DB legacy error: ' .. tostring(err_db)) end
    end
end

function DSP.market.load_cache(sid)
    sid = tonumber(sid) or DSP.market.state.sid
    local f = io.open(DSP.market_path(sid), 'rb')
    if not f then return false end
    local raw = f:read('*a')
    f:close()
    local ok, pack = pcall(decodeJson, raw)
    if not ok or type(pack) ~= 'table' then return false end
    if type(pack.body) == 'string' then
        local ok2, payload = pcall(decodeJson, pack.body)
        if not ok2 or type(payload) ~= 'table' then return false end
        DSP.market.state.sid = sid
        DSP.market.rebuild(payload, sid)
        DSP.market.state.saved_at = tonumber(pack.saved_at) or 0
        DSP.market.state.status = 'cache'
        return true
    end
    if type(pack.items) == 'table' then
        DSP.market.rebuild_legacy(pack, sid)
        DSP.market.state.saved_at = tonumber(pack.ts) or 0
        return true
    end
    if type(pack.shops) == 'table' then
        DSP.market.rebuild(pack, sid)
        DSP.market.state.saved_at = tonumber(pack.saved_at) or 0
        DSP.market.state.status = 'cache'
        return true
    end
    return false
end

function DSP.market.filtered()
    local st = DSP.market.state
    if st.filter_version == st.version and st.filter_cache then
        return st.filter_cache
    end
    local q = DSP.lower(DSP.trim(DSP.ui and DSP.ui.search or ''))
    local out = {}
    for _, row in ipairs(st.rows) do
        local ok = true
        if q ~= '' and not DSP.lower(row.display):find(q, 1, true) then ok = false end
        if ok and DSP.settings.only_profit and (row.profit or 0) <= 0 then ok = false end
        if ok and DSP.settings.liquid then
            if row.sell.count < 2 or row.buy.count < 2 then ok = false end
        end
        if ok then out[#out + 1] = row end
    end
    local sort = tonumber(DSP.settings.sort) or 1
    table.sort(out, function(a, b)
        if sort == 2 then
            if (a.sell.best or 0) ~= (b.sell.best or 0) then return (a.sell.best or 0) < (b.sell.best or 0) end
        elseif sort == 3 then
            if (a.buy.best or 0) ~= (b.buy.best or 0) then return (a.buy.best or 0) > (b.buy.best or 0) end
        elseif sort == 4 then
            if (a.profit_pct or 0) ~= (b.profit_pct or 0) then return (a.profit_pct or 0) > (b.profit_pct or 0) end
        elseif sort == 5 then
            local an, bn = a.sell.count + a.buy.count, b.sell.count + b.buy.count
            if an ~= bn then return an > bn end
        else
            if (a.profit or 0) ~= (b.profit or 0) then return (a.profit or 0) > (b.profit or 0) end
        end
        return a.display < b.display
    end)
    st.filter_cache = out
    st.filter_version = st.version
    return out
end

function DSP.market.buy_target(row, margin)
    margin = tonumber(margin) or tonumber(DSP.settings.margin) or 10
    local resale = row and row.buy and row.buy.max or 0
    if resale <= 0 then return 0 end
    local tax = DSP.clamp(tonumber(DSP.settings.tax_bp) or 200, 0, 10000)
    return math.max(0, math.floor(resale * (10000 - tax) / 10000 * (1 - margin / 100)))
end

function DSP.market.sell_target(row, undercut)
    undercut = tonumber(undercut) or tonumber(DSP.settings.undercut) or 2
    -- Compete with other sellers, not the shops buying from the player.
    local comp = row and row.sell and row.sell.min or 0
    if comp <= 0 then return 0 end
    return math.max(1, math.floor(comp * (1 - undercut / 100)))
end

function DSP.market.invalidate()
    DSP.market.state.filter_version = -1
    DSP.ui.page = 1
end

function DSP.market.row_for(name, ench)
    return DSP.market.state.by_key[DSP.item_key(name, ench)]
end

function DSP.market.load()
    local sid = DSP.detect_server() or DSP.settings.server or 102
    DSP.market.clear_for_server(sid)
    -- Never substitute Mobile II data for a missing cache on another server.
    if not DSP.market.load_cache(sid) then
        DSP.market.state.status = 'idle'
        DSP.market.state.rows, DSP.market.state.by_key = {}, {}
    end
    DSP.market.pull(sid)
end

-- =========================================================================
-- v1.2 Stage 2: 100% arbitrage + Item Finder + shops list.
-- =========================================================================

-- Freshness label for an offer. Returns (text, palette_key).
--   ts < 3 min: ('СВЕЖО (<3m)', 'good')  -- green
--   ts < 10 min: ('5m назад', 'warn')    -- yellow (text is approximate)
--   ts >= 10 min or 0: ('Устарело', 'muted')  -- gray
function DSP.market.offer_freshness(ts)
    if not ts or ts <= 0 then return 'Устарело', 'muted' end
    local age = math.max(0, os.time() - ts)
    if age < 180 then
        return string.format('СВЕЖО (<%dm)', math.floor(age / 60) + 1), 'good'
    end
    if age < 600 then
        return string.format('%dm назад', math.floor(age / 60)), 'warn'
    end
    return 'Устарело', 'muted'
end

-- Build cross-shop arbitrage opportunities.
-- Iterates row.sell.offers (лавка A продаёт cheap) + row.buy.offers
-- (лавка B скупает expensive), pairs them when A.shop ~= B.shop AND
-- B.price > A.price (otherwise negative profit).
-- Key includes @ench (set in DSP.item_key), so +0 stock is never matched
-- against +12 buyback.
--
-- v1.2 hotfix: лавки старше STALE_AFTER секунд (default 1800 = 30 мин)
-- отсекаются как неактуальные, чтобы не ловить фантомный арбитраж по
-- устаревшим данным из кэша va-ta.com.
local STALE_AFTER = 1800

-- v1.2 hotfix: ARBITRAGE CACHE.
-- In v1.2 we computed arbitrage() EVERY frame inside arbitrage_tab().
-- That ran 800 rows * 25 sell * 25 buy = ~500k iterations + table.sort,
-- 60 times per second -> game froze solid on Samsung A15.
--
-- Fix: compute arbitrage lazily. Cache the result + a version stamp.
-- Invalidate the cache only when:
--   * market.state.version changes (rebuild() bumped it)
--   * arb_filters change (budget / min_profit / min_roi / sort)
--   * arb_dirty flag is set (force re-compute)
--
-- arbitrage_filtered() reads from the cache, returning the cached array
-- in O(1) without re-sorting. The 60 FPS frame cost is now < 0.1 ms.
DSP.market.arb_cache = nil
DSP.market.arb_cache_version = -1
DSP.market.arb_cache_filter_sig = ''
DSP.market.arb_dirty = true

-- Compute the cache key signature from active filters. Used to detect
-- when the user changed filters and we need to re-filter (but not re-scan).
local function arb_filter_signature()
    local f = DSP.settings.arb_filters or {}
    return string.format('%d|%d|%d|%d',
        tonumber(f.budget) or 0,
        tonumber(f.min_profit) or 0,
        tonumber(f.min_roi) or 0,
        tonumber(f.sort) or 1)
end

-- Each result entry contains:
--   name, ench            -- display label and enchant level
--   sell_offer, buy_offer -- the matched offer objects (with .ts, .shop, .owner)
--   p_buy, p_sell         -- unit prices (player pays p_buy, receives p_sell)
--   qty_seller, qty_buyer -- qty offered by A and demanded by B
--   tradable_qty          -- min(qty_seller, qty_buyer) = realistic party size
--   total_cost            -- tradable_qty * p_buy (what player needs on hand)
--   net_revenue           -- math.floor(tradable_qty * p_sell * (10000 - tax_bp) / 10000)
--                          -- integer CR tax (basis points), no float drift
--   net_profit            -- net_revenue - total_cost (whole-cycle profit)
--   roi                   -- net_profit / total_cost * 100 (percent)
--   sell_age, buy_age     -- raw timestamps for freshness display
function DSP.market.arbitrage()
    local out = {}
    local tax_bp = tonumber(DSP.settings.tax_bp) or 200
    if tax_bp < 0 or tax_bp > 1000 then tax_bp = 200 end
    local now = os.time()
    for _, row in ipairs(DSP.market.state.rows or {}) do
        if row.sell.count > 0 and row.buy.count > 0 then
            for _, sell_offer in ipairs(row.sell.offers) do
                -- v1.2 hotfix: skip stale offers (>= 30 min old).
                -- Avoids phantom arbitrage from stale va-ta.com cache.
                if (tonumber(sell_offer.ts) or 0) == 0
                    or (now - sell_offer.ts) <= STALE_AFTER then
                    for _, buy_offer in ipairs(row.buy.offers) do
                        if (tonumber(buy_offer.ts) or 0) == 0
                            or (now - buy_offer.ts) <= STALE_AFTER then
                            -- Strict same-name + same-ench check via row key (already
                            -- enforced by map keying, but double-check in case of
                            -- legacy data).
                            if (sell_offer.ench or 0) == (buy_offer.ench or 0)
                                and sell_offer.shop ~= buy_offer.shop then
                                local p_buy = tonumber(sell_offer.price) or 0
                                local p_sell = tonumber(buy_offer.price) or 0
                                if p_sell > p_buy and p_buy > 0 then
                                    local qty_seller = tonumber(sell_offer.qty) or 0
                                    local qty_buyer = tonumber(buy_offer.qty) or 0
                                    local tradable_qty = math.min(qty_seller, qty_buyer)
                                    if tradable_qty > 0 then
                                        local total_cost = tradable_qty * p_buy
                                        local net_revenue = math.floor(
                                            tradable_qty * p_sell * (10000 - tax_bp) / 10000)
                                        local net_profit = net_revenue - total_cost
                                        if net_profit > 0 then
                                            local roi = total_cost > 0
                                                and (net_profit / total_cost * 100) or 0
                                            out[#out + 1] = {
                                                row = row,
                                                name = row.display,
                                                ench = row.ench,
                                                sell_offer = sell_offer,
                                                buy_offer = buy_offer,
                                                p_buy = p_buy,
                                                p_sell = p_sell,
                                                qty_seller = qty_seller,
                                                qty_buyer = qty_buyer,
                                                tradable_qty = tradable_qty,
                                                total_cost = total_cost,
                                                net_revenue = net_revenue,
                                                net_profit = net_profit,
                                                roi = roi,
                                                sell_age = sell_offer.ts or 0,
                                                buy_age = buy_offer.ts or 0,
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- Sort ONCE here, by net_profit desc (default sort id = 1).
    -- arbitrage_filtered() will re-sort only if sort != 1 OR filter changed.
    table.sort(out, function(a, b)
        if (a.net_profit or 0) ~= (b.net_profit or 0) then
            return (a.net_profit or 0) > (b.net_profit or 0)
        end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- Apply active arbitrage filters from DSP.settings.arb_filters.
-- Returns a CACHED array (filtered + sorted) so the UI can render a slice.
-- v1.2 hotfix: cache by (market.version, filter_signature). Re-computes only
-- when either changes -- NOT every frame. Per-frame cost dropped from
-- ~500ms (worst case) to <0.1ms (cache hit).
function DSP.market.arbitrage_filtered()
    local f = DSP.settings.arb_filters or { budget = 0, min_profit = 0, min_roi = 0, sort = 1 }
    local sig = arb_filter_signature()
    local mver = tonumber(DSP.market.state.version) or 0
    -- Cache hit: same market version + same filters + not dirty.
    if DSP.market.arb_cache
        and DSP.market.arb_cache_version == mver
        and DSP.market.arb_cache_filter_sig == sig
        and not DSP.market.arb_dirty then
        return DSP.market.arb_cache
    end
    -- Cache miss: rebuild. This is the heavy pass (~500k iterations on a
    -- full 800-row market). Runs ONCE per market update or filter change,
    -- NOT per frame.
    local all = DSP.market.arbitrage()
    local out = {}
    local budget = tonumber(f.budget) or 0
    local min_profit = tonumber(f.min_profit) or 0
    local min_roi = tonumber(f.min_roi) or 0
    for _, e in ipairs(all) do
        if budget > 0 and (e.total_cost or 0) > budget then
            -- skip: not enough on hands
        elseif min_profit > 0 and (e.net_profit or 0) < min_profit then
            -- skip: profit too low
        elseif min_roi > 0 and (e.roi or 0) < min_roi then
            -- skip: ROI too low
        else
            out[#out + 1] = e
        end
    end
    local sort = tonumber(f.sort) or 1
    -- Re-sort only if sort != default (default already sorted by arbitrage()).
    if sort ~= 1 then
        table.sort(out, function(a, b)
            if sort == 2 then
                -- per-unit profit
                local pa = a.p_sell - a.p_buy
                local pb = b.p_sell - b.p_buy
                if pa ~= pb then return pa > pb end
            elseif sort == 3 then
                -- ROI
                if (a.roi or 0) ~= (b.roi or 0) then return (a.roi or 0) > (b.roi or 0) end
            end
            return tostring(a.name) < tostring(b.name)
        end)
    end
    DSP.market.arb_cache = out
    DSP.market.arb_cache_version = mver
    DSP.market.arb_cache_filter_sig = sig
    DSP.market.arb_dirty = false
    return out
end

-- Force the arbitrage cache to be invalidated. Call after arbitrage filter
-- changes (UI buttons) or after manual market cache replacement.
function DSP.market.invalidate_arbitrage()
    DSP.market.arb_dirty = true
end

-- Item Finder: search rows by partial name (case-insensitive).
-- Returns matching rows (each with full .sell / .buy offer lists already
-- sorted by finish_side).
function DSP.market.find_item(query)
    local q = DSP.lower(DSP.trim(query))
    if q == '' then return {} end
    local out = {}
    for _, row in ipairs(DSP.market.state.rows or {}) do
        if DSP.lower(row.display):find(q, 1, true) then
            out[#out + 1] = row
        end
    end
    return out
end

-- Group all offers by shop. Returns array of
--   { num, owner, ts (max), sell_count, buy_count, sell_offers = [], buy_offers = [] }
-- where sell_offers = [{ row, offer }] (лавка ПРОДАЁТ to player)
-- and   buy_offers  = [{ row, offer }] (лавка СКУПАЕТ from player)
-- Sorted by ts desc (freshest first).
function DSP.market.shops_list()
    local shops = {}
    for _, row in ipairs(DSP.market.state.rows or {}) do
        for _, offer in ipairs(row.sell.offers) do
            local num = tostring(offer.shop or '?')
            local s = shops[num]
            if not s then
                s = { num = num, owner = offer.owner or '?', ts = offer.ts or 0,
                      sell_count = 0, buy_count = 0,
                      sell_offers = {}, buy_offers = {} }
                shops[num] = s
            end
            if (offer.ts or 0) > s.ts then s.ts = offer.ts end
            s.sell_count = s.sell_count + 1
            s.sell_offers[#s.sell_offers + 1] = { row = row, offer = offer }
        end
        for _, offer in ipairs(row.buy.offers) do
            local num = tostring(offer.shop or '?')
            local s = shops[num]
            if not s then
                s = { num = num, owner = offer.owner or '?', ts = offer.ts or 0,
                      sell_count = 0, buy_count = 0,
                      sell_offers = {}, buy_offers = {} }
                shops[num] = s
            end
            if (offer.ts or 0) > s.ts then s.ts = offer.ts end
            s.buy_count = s.buy_count + 1
            s.buy_offers[#s.buy_offers + 1] = { row = row, offer = offer }
        end
    end
    local arr = {}
    for _, s in pairs(shops) do arr[#arr + 1] = s end
    table.sort(arr, function(a, b)
        if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) > (b.ts or 0) end
        return tostring(a.num) < tostring(b.num)
    end)
    return arr
end

-- Send the /findilavka N command to mark a shop on the GPS map.
-- This is the standard Arizona Mobile command for highlighting a CR shop.
function DSP.market.mark_shop(shop_num)
    if shop_num == nil then return false end
    local cmd = '/findilavka ' .. tostring(shop_num)
    if sampSendChat then
        local ok = pcall(sampSendChat, cmd)
        if ok then
            DSP.add_log('Метка лавки: ' .. tostring(shop_num))
            return true
        end
    end
    return false
end

-- Copy a shop's buyback list (buy_slots = items лавка скупает у игрока)
-- into the player's BUY preset (so the player выставляет the same buyback
-- in their own лавка).
-- Args:
--   shop_num   -- the shop number whose buy offers to copy
--   preset_name -- override name for the new preset (optional)
--   markup     -- price markup in $ to apply (default 1, i.e. +1$ to outbid)
-- Returns: count of items copied, or nil + error
function DSP.market.copy_shop_skupka(shop_num, preset_name, markup)
    markup = tonumber(markup) or 1
    local shops = DSP.market.shops_list()
    local target
    for _, s in ipairs(shops) do
        if tostring(s.num) == tostring(shop_num) then
            target = s
            break
        end
    end
    if not target then return nil, 'лавка не найдена' end
    if target.buy_count == 0 then return nil, 'у лавки нет скупки' end
    local p = DSP.settings.buy_preset
    if not p.items then p.items = {} end
    if preset_name then p.name = preset_name
    elseif p.name == 'Скупка' then
        p.name = 'Скупка_' .. tostring(target.owner)
    end
    local added = 0
    for _, entry in ipairs(target.buy_offers) do
        local row = entry.row
        local offer = entry.offer
        -- Skip if already in preset (matched by row key including @ench)
        local exists = false
        for _, it in ipairs(p.items) do
            if it.key == row.key then exists = true break end
        end
        if not exists then
            local price = math.max(1, math.floor((tonumber(offer.price) or 0) + markup))
            p.items[#p.items + 1] = {
                key = row.key,
                name = row.display,
                ench = row.ench or 0,
                price = price,
                qty = 1,
                enabled = true,
            }
            added = added + 1
        end
    end
    DSP.save_settings()
    DSP.add_log(string.format('Скопировано скупки: лавка #%s, +%d поз. (markup +%d$)',
        tostring(shop_num), added, markup))
    return added
end

-- =========================================================================
-- v1.2 Stage 3 hotfix: CR marker scan (dialog 15073) + median market prices.
-- =========================================================================

-- Path to the CR-marker snapshot file for a given server id.
function DSP.market.cr_marker_path(sid)
    sid = tonumber(sid) or DSP.market.state.sid or 102
    return DSP.dir .. '/prices_server_' .. tostring(sid) .. '.json'
end

-- Live scan state. Set by scan_cr_marker(), read by on_cr_marker_dialog()
-- in 40_auto.lua when dialog 15073 fires.
DSP.market.cr_scan_state = {
    active = false,
    page = 0,
    total = 0,
    items = {},
    status = 'не сканирован',
    started_at = 0,
}

-- Kick off the CR marker scan. The user must be standing on the CR
-- checkpoint that opens dialog 15073. We arm the scan state; the actual
-- page-flipping happens in on_cr_marker_dialog() when 40_auto.lua fires
-- the sampev.onShowDialog hook.
function DSP.market.scan_cr_marker()
    if DSP.market.cr_scan_state.active then
        DSP.notify('Скан ЦР: уже идёт, дождитесь окончания')
        return false
    end
    DSP.market.cr_scan_state.active = true
    DSP.market.cr_scan_state.page = 0
    DSP.market.cr_scan_state.total = 0
    DSP.market.cr_scan_state.items = {}
    DSP.market.cr_scan_state.started_at = os.time()
    DSP.market.cr_scan_state.status = 'ожидание диалога 15073 (встаньте на метку ЦР)'
    DSP.add_log('Скан ЦР: запущен, встаньте на метку средних цен ЦР')
    -- Auto-expire after 60 seconds if no dialog fires.
    if lua_thread and wait then
        lua_thread.create(function()
            local deadline = os.time() + 60
            while DSP.market.cr_scan_state.active and os.time() < deadline do
                wait(500)
            end
            if DSP.market.cr_scan_state.active and DSP.market.cr_scan_state.page == 0 then
                DSP.market.cr_scan_state.active = false
                DSP.market.cr_scan_state.status = 'таймаут: диалог 15073 не открыт'
                DSP.add_log('Скан ЦР: таймаут', 'error')
            end
        end)
    end
    return true
end

-- Save the CR marker snapshot. Format mirrors the in-memory rows map so
-- that load_cr_marker can rehydrate rows without API calls.
function DSP.market.save_cr_marker(sid)
    sid = tonumber(sid) or DSP.market.state.sid or 102
    local pack = {
        saved_at = os.time(),
        sid = sid,
        items = DSP.market.cr_scan_state.items,
        page = DSP.market.cr_scan_state.page,
        total = DSP.market.cr_scan_state.total,
    }
    local ok, json = pcall(encodeJson, pack)
    if not ok or not json then
        DSP.flog('CR MARKER save failed: ' .. tostring(json))
        return false
    end
    local f = io.open(DSP.market.cr_marker_path(sid), 'w')
    if not f then return false end
    f:write(json)
    f:close()
    DSP.flog(string.format('CR MARKER saved sid=%d items=%d page=%d',
        sid, #pack.items, pack.page))
    return true
end

function DSP.market.load_cr_marker(sid)
    sid = tonumber(sid) or DSP.market.state.sid or 102
    local f = io.open(DSP.market.cr_marker_path(sid), 'rb')
    if not f then return nil end
    local raw = f:read('*a')
    f:close()
    local ok, pack = pcall(decodeJson, raw)
    if not ok or type(pack) ~= 'table' then return nil end
    return pack
end

-- Called from 40_auto.lua's on_dialog when sampev.onShowDialog fires with
-- id == 15073. Parses the dialog text for items + average prices, then
-- sends "Next page" response or finalizes the scan.
--
-- We try several formats because Arizona Mobile dialog text varies:
--   "Item name ........ $X (sell) / $Y (buy) | qty: N"
--   "1. Item name — sell: $X / buy: $Y"
--   "Item name | средняя: $X | скупка: $Y | остаток: N"
-- Anything we can't parse, we log + skip (no crash).
function DSP.market.on_cr_marker_dialog(text)
    if not DSP.market.cr_scan_state.active then return false end
    DSP.market.cr_scan_state.page = DSP.market.cr_scan_state.page + 1
    local s = DSP.market.cr_scan_state
    local parsed = 0
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        local clean = DSP.clean_text(line)
        if clean ~= '' and not clean:find('^%s*$') then
            -- Try: "Name ... sell: X$ / buy: Y$"
            local name, sell_s, buy_s = clean:match('^(.-)%s*[%s%.%-:]+продаж[а-я]*%s*:?%s*%$?([%d%.]+).-скупк[а-я]*%s*:?%s*%$?([%d%.]+)')
            if not name then
                -- Try: "Name ... $X / $Y"
                name, sell_s, buy_s = clean:match('^(.-)%s*[%s%.%-]+%$?([%d%.]+).-/?%s*%$?([%d%.]+)')
            end
            if not name then
                -- Try: "N. Name - sell: X / buy: Y"
                name, sell_s, buy_s = clean:match('^%d+[%.%)]%s*(.-)%s*-?%s*продаж[а-я]*%s*:?%s*%$?([%d%.]+).-скупк[а-я]*%s*:?%s*%$?([%d%.]+)')
            end
            if name and sell_s and buy_s then
                name = DSP.trim(name)
                if name ~= '' and name ~= 'Следующая' and name ~= 'Предыдущая'
                    and name ~= 'Назад' and name ~= 'Далее' then
                    local sell = tonumber(sell_s:gsub('%.', ''):gsub(',', ''))
                    local buy = tonumber(buy_s:gsub('%.', ''):gsub(',', ''))
                    if sell and buy and (sell > 0 or buy > 0) then
                        s.items[#s.items + 1] = {
                            name = name,
                            sell_med = sell,
                            buy_med = buy,
                            ts = os.time(),
                        }
                        parsed = parsed + 1
                    end
                end
            end
        end
    end
    s.status = string.format('Сканирование: стр. %d, считано %d товаров', s.page, #s.items)
    DSP.flog('CR MARKER page=' .. s.page .. ' parsed=' .. parsed .. ' total_items=' .. #s.items)
    -- Send "Next page" response. Arizona Mobile uses listrow index 1 = "Назад"
    -- and the last row = "Следующая страница" (or vice versa). We try both.
    -- Look for the "Следующая" line number in the dialog text.
    local next_idx = nil
    local line_no = 0
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        line_no = line_no + 1
        local c = DSP.clean_text(line)
        if c:find('Следующая', 1, true) or c:find('Далее', 1, true) then
            next_idx = line_no - 1  -- listrow index is 0-based, line includes header
            break
        end
    end
    if next_idx and sampSendDialogResponse and sampGetCurrentDialogId then
        local did = sampGetCurrentDialogId()
        if lua_thread and wait then
            lua_thread.create(function()
                wait(150)
                pcall(sampSendDialogResponse, did, 1, next_idx, '')
            end)
        else
            pcall(sampSendDialogResponse, did, 1, next_idx, '')
        end
        return true
    end
    -- No more pages -- finalize.
    DSP.market.cr_scan_state.active = false
    DSP.market.cr_scan_state.status = string.format('Готово: %d товаров на %d стр.', #s.items, s.page)
    DSP.market.save_cr_marker(DSP.market.state.sid)
    DSP.add_log(string.format('Скан ЦР: готово, %d товаров сохранено', #s.items), 'ok')
    -- Close dialog
    if sampSendDialogResponse and sampGetCurrentDialogId then
        local did = sampGetCurrentDialogId()
        pcall(sampSendDialogResponse, did, 0, 0, '')
    end
    return true
end

-- Compute median market prices from the live va-ta.com data (DSP.market.state).
-- Returns { sell_med, buy_med, sell_min, sell_max, buy_min, buy_max, shops_n }
-- for a given row. Used when no CR marker snapshot is available.
function DSP.market.median_prices(row)
    if not row then return nil end
    local function side_stats(side)
        if not side or side.count == 0 then
            return { med = 0, min = 0, max = 0, shops_n = 0 }
        end
        local n = #side.prices
        if n == 0 then
            return { med = side.med or 0, min = side.min or 0, max = side.max or 0, shops_n = side.shop_n or 0 }
        end
        -- prices is already sorted asc by finish_side, so median is the middle element.
        local mid = math.floor((n + 1) / 2)
        return {
            med = side.prices[mid],
            min = side.prices[1],
            max = side.prices[n],
            shops_n = side.shop_n or 0,
        }
    end
    return {
        sell = side_stats(row.sell),
        buy = side_stats(row.buy),
    }
end

-- Format the "Рынок сервера #N: Продажа ~X$ | Скупка ~Y$ (на основе N лавок)"
-- header line for a given row. Falls back to CR marker snapshot if available,
-- else uses live median from va-ta.com data.
function DSP.market.market_label_for(row)
    if not row then return '' end
    local sid = tonumber(DSP.market.state.sid) or 0
    -- Try CR marker snapshot first
    local marker = DSP.market.load_cr_marker(sid)
    if marker and marker.items then
        for _, it in ipairs(marker.items) do
            if DSP.lower(it.name or '') == DSP.lower(row.name or '') then
                return string.format('Рынок ЦР #%d: Продажа ~%s | Скупка ~%s (метка %s)',
                    sid, DSP.money(it.sell_med or 0), DSP.money(it.buy_med or 0),
                    os.date('%d.%m %H:%M', marker.saved_at or 0))
            end
        end
    end
    -- Fall back to live va-ta.com medians
    local med = DSP.market.median_prices(row)
    if not med then return '' end
    local sell = med.sell or { med = 0, shops_n = 0 }
    local buy = med.buy or { med = 0, shops_n = 0 }
    if sell.med == 0 and buy.med == 0 then return '' end
    local shops = math.max(sell.shops_n or 0, buy.shops_n or 0)
    return string.format('Рынок #%d: Продажа ~%s | Скупка ~%s (на основе %d лавок)',
        sid, DSP.money(sell.med), DSP.money(buy.med), shops)
end

end
__mod_10_market()

local function __mod_11_arbitrage()
-- Compare real offers; budget limits apply before profitability filters.
local M = DSP.market
local cache, signature, expires

function M.should_refresh(now)
    if M.state.status == 'loading' then return false end
    local interval = math.max(30, tonumber(DSP.settings.refresh_seconds) or 60)
    return (now or os.time()) - (M.state.last_request or 0) >= interval
end

local function integer(value, default)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return default or 0 end
    return math.max(0, math.floor(n))
end

local function after_tax(gross)
    local factor = 10000 - math.min(10000, integer(DSP.settings.tax_bp, 200))
    -- Avoid multiplying a large gross amount by 10000 before dividing.
    return math.floor(gross / 10000) * factor + math.floor((gross % 10000) * factor / 10000)
end

local function fresh(offer, now, filters)
    local ts = integer(offer.ts)
    if ts == 0 then return filters.include_unknown ~= false end
    if ts > now + 60 then return false end
    local max_age = integer(filters.max_age, 1800)
    return max_age == 0 or now - ts <= max_age
end

-- Build a non-overlapping purchase/resale plan. A shop's stock or demand
-- cannot be committed twice just because it matches several other stalls.
-- Greedy allocation prioritizes unit profit (or ROI under a cash budget).
local function opportunities(filters, now)
    local candidates, out = {}, {}
    local budget = integer(filters.budget)
    local remaining_budget = budget > 0 and budget or math.huge
    local max_qty = integer(filters.max_qty)
    local sellers_left, buyers_left = {}, {}
    local min_profit = integer(filters.min_profit)
    local min_roi = tonumber(filters.min_roi) or 0
    for _, row in ipairs(M.state.rows or {}) do
        for _, seller in ipairs(row.sell.offers or {}) do
            if fresh(seller, now, filters) then
                sellers_left[seller] = integer(seller.qty)
                for _, buyer in ipairs(row.buy.offers or {}) do
                    local p_buy, p_sell = integer(seller.price), integer(buyer.price)
                    if tostring(seller.shop) ~= tostring(buyer.shop)
                        and (seller.ench or 0) == (buyer.ench or 0)
                        and fresh(buyer, now, filters)
                        and p_buy > 0 and p_sell > p_buy
                        and integer(seller.qty) > 0 and integer(buyer.qty) > 0 then
                        buyers_left[buyer] = integer(buyer.qty)
                        local unit_profit = after_tax(p_sell) - p_buy
                        if unit_profit > 0 then
                            candidates[#candidates+1] = {
                                row=row, seller=seller, buyer=buyer,
                                p_buy=p_buy, p_sell=p_sell, unit_profit=unit_profit,
                                unit_roi=unit_profit / p_buy,
                            }
                        end
                    end
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        local av = budget > 0 and a.unit_roi or a.unit_profit
        local bv = budget > 0 and b.unit_roi or b.unit_profit
        if av ~= bv then return av > bv end
        if a.unit_profit ~= b.unit_profit then return a.unit_profit > b.unit_profit end
        if a.row.key ~= b.row.key then return a.row.key < b.row.key end
        if a.p_buy ~= b.p_buy then return a.p_buy < b.p_buy end
        if tostring(a.seller.shop) ~= tostring(b.seller.shop) then
            return tostring(a.seller.shop) < tostring(b.seller.shop)
        end
        return tostring(a.buyer.shop) < tostring(b.buyer.shop)
    end)
    for _, c in ipairs(candidates) do
        local seller, buyer = c.seller, c.buyer
        local available = math.min(sellers_left[seller] or 0, buyers_left[buyer] or 0)
        if available > 0 and remaining_budget >= c.p_buy then
            local qty = available
            if max_qty > 0 then qty = math.min(qty, max_qty) end
            -- Keep integer arithmetic inside IEEE-754's exact integer range.
            qty = math.min(qty, math.floor(9007199254740991 / math.max(c.p_buy,c.p_sell)))
            if remaining_budget ~= math.huge then
                if filters.allow_partial == false and qty * c.p_buy > remaining_budget then
                    qty = 0
                else
                    qty = math.min(qty, math.floor(remaining_budget / c.p_buy))
                end
            end
            if qty > 0 then
                local cost = qty * c.p_buy
                local revenue = after_tax(qty * c.p_sell)
                local profit = revenue - cost
                local roi = profit / cost * 100
                if profit > 0 and profit >= min_profit and roi >= min_roi then
                    out[#out+1] = {
                        row=c.row, name=c.row.display, ench=c.row.ench,
                        sell_offer=seller, buy_offer=buyer,
                        p_buy=c.p_buy, p_sell=c.p_sell,
                        qty_seller=integer(seller.qty), qty_buyer=integer(buyer.qty),
                        available_qty=available, tradable_qty=qty, partial=qty<available,
                        total_cost=cost, net_revenue=revenue, net_profit=profit,
                        roi=roi, unit_profit=c.unit_profit,
                        sell_age=seller.ts or 0, buy_age=buyer.ts or 0,
                        shared_stock=available<math.min(integer(seller.qty),integer(buyer.qty)),
                    }
                    sellers_left[seller] = sellers_left[seller] - qty
                    buyers_left[buyer] = buyers_left[buyer] - qty
                    remaining_budget = remaining_budget - cost
                end
            end
        end
    end
    local sort = tonumber(filters.sort) or 1
    table.sort(out, function(a,b)
        local av, bv = a.net_profit, b.net_profit
        if sort == 2 then av,bv = a.unit_profit,b.unit_profit end
        if sort == 3 then av,bv = a.roi,b.roi end
        if av ~= bv then return av > bv end
        if a.name ~= b.name then return a.name < b.name end
        if tostring(a.sell_offer.shop) ~= tostring(b.sell_offer.shop) then
            return tostring(a.sell_offer.shop) < tostring(b.sell_offer.shop)
        end
        return tostring(a.buy_offer.shop) < tostring(b.buy_offer.shop)
    end)
    return out
end

function M.arbitrage()
    return opportunities({max_age=1800, include_unknown=true}, os.time())
end

function M.arbitrage_filtered()
    local f = DSP.settings.arb_filters or {}
    local now = os.time()
    local sig = table.concat({M.state.sid or 0, M.state.version or 0, DSP.settings.tax_bp or 200,
        f.budget or 0, f.min_profit or 0, f.min_roi or 0, f.sort or 1,
        f.max_age or 1800, tostring(f.include_unknown ~= false),
        tostring(f.allow_partial ~= false), f.max_qty or 0}, '|')
    if cache and sig == signature and not M.arb_dirty and now < expires then return cache end
    cache, signature = opportunities(f, now), sig
    expires = math.huge
    local max_age = integer(f.max_age,1800)
    for _, row in ipairs(M.state.rows or {}) do
            for _, side in ipairs({row.sell,row.buy}) do
                for _, offer in ipairs(side.offers or {}) do
                    local ts = integer(offer.ts)
                    local deadline = ts + max_age + 1
                    if max_age > 0 and ts > 0 and deadline > now then expires = math.min(expires,deadline) end
                    if ts > now+60 then expires = math.min(expires,ts-60) end
                end
            end
    end
    M.arb_dirty = false
    return cache
end

function M.offer_freshness(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return 'время неизвестно', 'muted' end
    local age = os.time() - ts
    if age < -60 then return 'ошибка времени', 'warn' end
    if age < 180 then return 'свежее', 'good' end
    if age < 600 then return math.floor(age / 60) .. ' мин назад', 'warn' end
    return math.floor(age / 60) .. ' мин назад', 'muted'
end

end
__mod_11_arbitrage()

local function __mod_15_prices()
-- Persistent price base: API stats + learned shop observations.
DSP.db = DSP.db or {}
DSP.db.path = DSP.dir .. '/standalone_prices.json'
DSP.db.by_key = {}
DSP.db.by_base = {}
DSP.db.learned = {}
DSP.db.saved_at = 0
DSP.db.sid = 0
DSP.db.last_save = 0

local function zero_side()
    return { min = 0, max = 0, p25 = 0, med = 0, p75 = 0, best = 0, count = 0, qty = 0 }
end

local function copy_side(side)
    side = side or {}
    return {
        min = tonumber(side.min) or 0,
        max = tonumber(side.max) or 0,
        p25 = tonumber(side.p25) or 0,
        med = tonumber(side.med) or 0,
        p75 = tonumber(side.p75) or 0,
        best = tonumber(side.best) or 0,
        count = tonumber(side.count) or #(side.prices or {}),
        qty = tonumber(side.qty) or 0,
    }
end

function DSP.db.rebuild_base()
    local base = {}
    for key, e in pairs(DSP.db.by_key) do
        local b = DSP.lower(e.name or '')
        local old = base[b]
        local score = (e.sell and e.sell.count or 0) + (e.buy and e.buy.count or 0)
        local old_score = old and ((old.sell and old.sell.count or 0) + (old.buy and old.buy.count or 0)) or -1
        if not old or score > old_score or (score == old_score and (e.ench or 0) == 0) then
            base[b] = e
        end
    end
    DSP.db.by_base = base
end

function DSP.db.save(force)
    local now = os.clock()
    if not force and now - (DSP.db.last_save or 0) < 5 then return false end
    DSP.db.last_save = now
    DSP.db.saved_at = os.time()
    local pack = {
        saved_at = DSP.db.saved_at,
        sid = DSP.db.sid or 0,
        by_key = DSP.db.by_key,
        learned = DSP.db.learned,
    }
    local ok, json = pcall(encodeJson, pack)
    if not ok or not json then return false end
    local f = io.open(DSP.db.path, 'w')
    if not f then return false end
    f:write(json)
    f:close()
    return true
end

function DSP.db.set_rows(rows, sid)
    local map = {}
    local updated = DSP.market.state.updated or 0
    for _, r in ipairs(rows or {}) do
        map[r.key] = {
            key = r.key,
            name = r.name,
            ench = tonumber(r.ench) or 0,
            display = r.display,
            sell = copy_side(r.sell),
            buy = copy_side(r.buy),
            updated = updated,
            sid = tonumber(sid) or 0,
        }
    end
    DSP.db.by_key = map
    DSP.db.sid = tonumber(sid) or 0
    DSP.db.updated = updated
    DSP.db.rebuild_base()
    DSP.db.save(true)
    DSP.flog('DB rows=' .. tostring(#(rows or {})) .. ' sid=' .. tostring(sid))
end

function DSP.db.load()
    local f = io.open(DSP.db.path, 'rb')
    if not f then return false end
    local raw = f:read('*a') or ''
    f:close()
    local ok, pack = pcall(decodeJson, raw)
    if not ok or type(pack) ~= 'table' then return false end
    if type(pack.by_key) == 'table' then DSP.db.by_key = pack.by_key end
    if type(pack.learned) == 'table' then DSP.db.learned = pack.learned end
    DSP.db.saved_at = tonumber(pack.saved_at) or 0
    DSP.db.sid = tonumber(pack.sid) or 0
    DSP.db.rebuild_base()
    DSP.flog('DB loaded keys=' .. tostring((function() local n=0; for _ in pairs(DSP.db.by_key) do n=n+1 end; return n end)()))
    return true
end

function DSP.db.get(name, ench)
    name = DSP.clean_text(name or '')
    if name == '' or name:find('^ID:') then return nil, false, 'none' end
    ench = tonumber(ench) or 0
    if ench < 0 or ench > 20 then ench = 0 end
    local key = DSP.item_key(name, ench)
    local e = DSP.db.by_key[key]
    if e then return e, true, 'api' end
    local base = DSP.db.by_base[DSP.lower(name)]
    if base and (tonumber(base.ench) or 0) == ench then return base, false, 'api_base' end
    e = DSP.db.learned[key]
    if e then return e, true, 'shop' end
    return nil, false, 'none'
end

function DSP.db.learn(raw, ench, price, side)
    price = tonumber(price) or 0
    if price <= 0 then return end
    local disp, id, e = DSP.items.display(raw, ench)
    local name = DSP.items.name(id)
    if not name or name == '' or name:find('^ID:') then return end
    local key = DSP.item_key(name, e)
    local entry = DSP.db.learned[key]
    if not entry then
        entry = {
            key = key,
            name = name,
            display = disp,
            ench = e,
            sell = zero_side(),
            buy = zero_side(),
            updated = os.time(),
            sid = DSP.market.state.sid or 0,
        }
        DSP.db.learned[key] = entry
    end
    entry.updated = os.time()
    if side == 'sell' then
        if entry.sell.min <= 0 or price < entry.sell.min then entry.sell.min = price end
        entry.sell.best = entry.sell.min
        entry.sell.med = entry.sell.min
        entry.sell.count = (entry.sell.count or 0) + 1
    else
        if price > entry.buy.max then entry.buy.max = price end
        entry.buy.best = entry.buy.max
        entry.buy.med = entry.buy.max
        entry.buy.count = (entry.buy.count or 0) + 1
    end
    DSP.db.save(false)
end

function DSP.db.freshness()
    local ts = DSP.db.updated or DSP.db.saved_at or 0
    if ts <= 0 then return 'нет базы' end
    local age = math.max(0, os.time() - ts)
    if age < 60 then return age .. ' сек' end
    if age < 3600 then return math.floor(age / 60) .. ' мин' end
    if age < 86400 then return math.floor(age / 3600) .. ' ч' end
    return math.floor(age / 86400) .. ' дн'
end

end
__mod_15_prices()

local function __mod_05_trades()
-- Trade logging, profit tracking, stall drops, crate sources.
DSP.logs = DSP.logs or {}
DSP.logs.installed = false
DSP.logs.trade_logs = {}
DSP.logs.stall_logs = {}
DSP.logs.crate_logs = {}

local ok_lfs, lfs = pcall(require, 'lfs')

DSP.db = DSP.db or {}

DSP.settings.trades = DSP.settings.trades or {}
DSP.settings.stalls = DSP.settings.stalls or {}
DSP.settings.crates = DSP.settings.crates or {}
DSP.settings.stats_tab = DSP.settings.stats_tab or 'day'

local LOG_DIR = DSP.dir .. '/logs'
local send_telegram

-- v1.2 fix: moved `name_ench` declaration ABOVE `parse_chat_drop`.
-- In v1.1 this was a latent bug: parse_chat_drop referenced `name_ench` as a
-- local, but `local function name_ench` was declared later in the file, so
-- Lua's lexical scoping meant parse_chat_drop saw `name_ench` as a global
-- (which is nil since the local never escapes to _G). The first call would
-- crash with "attempt to call a nil value". Declaring it here first ensures
-- both functions see the same local upvalue.
local function name_ench(s)
    s = DSP.clean_text(s or '')
    local base, e = s:match('^(.-)%s*%(%+(%d+)%)%s*$')
    if base and base ~= '' then return base, tonumber(e) or 0 end
    return s, 0
end

local function mkdir_p(p)
    if not ok_lfs or not lfs then return end
    if type(lfs.attributes) == 'function' then
        local ok, attr = pcall(lfs.attributes, p)
        if not ok then
            pcall(lfs.mkdir, p)
        end
    end
end

local function file_write(path, data)
    local f = io.open(path, 'w')
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function file_read(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local raw = f:read('*a')
    f:close()
    return raw
end

function DSP.db.save_trades()
    local pack = {
        trades = DSP.settings.trades or {},
        stalls = DSP.settings.stalls or {},
        crates = DSP.settings.crates or {},
        chat_logs = DSP.settings.chat_logs or {},
        saved_at = os.time(),
    }
    local ok, json = pcall(encodeJson, pack)
    if not ok or not json then return false end
    local f = io.open(DSP.dir .. '/trades.json', 'w')
    if not f then return false end
    f:write(json)
    f:close()
    return true
end

function DSP.db.load_trades()
    local raw = file_read(DSP.dir .. '/trades.json')
    if not raw then return false end
    local ok, pack = pcall(decodeJson, raw)
    if not ok or type(pack) ~= 'table' then return false end
    DSP.settings.trades = pack.trades or {}
    DSP.settings.stalls = pack.stalls or {}
    DSP.settings.crates = pack.crates or {}
    DSP.settings.chat_logs = pack.chat_logs or {}
    DSP.logs.trade_logs, DSP.logs.stall_logs, DSP.logs.crate_logs = {}, {}, {}
    local n_trade, n_stall, n_crate = 0, 0, 0
    for _, e in pairs(DSP.settings.trades) do DSP.logs.trade_logs[#DSP.logs.trade_logs + 1] = e; n_trade = n_trade + 1 end
    for _, e in pairs(DSP.settings.stalls) do DSP.logs.stall_logs[#DSP.logs.stall_logs + 1] = e; n_stall = n_stall + 1 end
    for _, e in pairs(DSP.settings.crates) do DSP.logs.crate_logs[#DSP.logs.crate_logs + 1] = e; n_crate = n_crate + 1 end
    table.sort(DSP.logs.trade_logs, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    table.sort(DSP.logs.stall_logs, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    table.sort(DSP.logs.crate_logs, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    DSP.flog('TRADES loaded trades=' .. tostring(n_trade) .. ' stalls=' .. tostring(n_stall) .. ' crates=' .. tostring(n_crate))
    return true
end

function DSP.logs.save_daily_log()
    mkdir_p(LOG_DIR)
    local today = os.date('%Y-%m-%d', os.time())
    local lines = {}
    for _, e in ipairs(DSP.logs.trade_logs) do
        if os.date('%Y-%m-%d', e.ts or 0) == today then
            local t = type(e) == 'table' and e
            if t and t.type == 'trade' then
                table.insert(lines, string.format('[TRADE] %s | %s -> получено: %s, отдано: %s, прибыль: %s (%+.1f%%) | %s',
                    os.date('%H:%M:%S', t.ts or 0),
                    t.partner or '?',
                    DSP.money(t.total_get or 0),
                    DSP.money(t.total_give or 0),
                    DSP.money(t.profit or 0),
                    t.delta_pct or 0,
                    t.kind or ''))
            end
        end
    end
    file_write(LOG_DIR .. '/' .. today .. '.log', table.concat(lines, '\n') .. '\n')
end

function DSP.logs.record_trade(partner, items_give, items_get, money_give, money_get, result)
    local total_give = tonumber(money_give or 0)
    local total_get = tonumber(money_get or 0)
    for _, it in ipairs(items_give or {}) do
        local e = DSP.db.get(it.name, it.ench)
        if e and e.buy and e.buy.max and e.buy.max > 0 then
            total_give = total_give + e.buy.max * (it.qty or 1)
        end
    end
    for _, it in ipairs(items_get or {}) do
        local e = DSP.db.get(it.name, it.ench)
        if e and e.buy and e.buy.max and e.buy.max > 0 then
            total_get = total_get + e.buy.max * (it.qty or 1)
        end
    end
    local profit = total_get - total_give
    local delta_pct = total_give > 0 and (profit / total_give * 100) or 0
    local kind = profit > 0 and 'profit' or (profit < 0 and 'loss' or 'neutral')

    local entry = {
        type = 'trade',
        ts = os.time(),
        partner = tostring(partner or '?'),
        kind = kind,
        total_get = total_get,
        total_give = total_give,
        profit = profit,
        delta_pct = delta_pct,
        items_give = items_give or {},
        items_get = items_get or {},
        money_give = tonumber(money_give or 0) or 0,
        money_get = tonumber(money_get or 0) or 0,
        server = DSP.settings.server or 102,
    }
    local entry_id = tostring(entry.ts)
    while DSP.settings.trades[entry_id] do entry_id = entry_id .. '_' end
    DSP.settings.trades[entry_id] = entry
    DSP.logs.trade_logs[#DSP.logs.trade_logs + 1] = entry
    DSP.db.save_trades()
    DSP.logs.save_daily_log()
    -- v1.2 Stage 3: push to craglog ring buffer + append-only file.
    -- Independent of save_daily_log which rewrites today's file each trade.
    if DSP.craglog and DSP.craglog.log_trade then
        pcall(DSP.craglog.log_trade, entry)
    end
    if DSP.live and DSP.live.reset_trade then DSP.live.reset_trade(partner) end
    DSP.notify('СДЕЛКА: ' .. DSP.money(profit) .. ' (' .. string.format('%+.1f%%', delta_pct) .. ')', kind == 'profit' and 'ok' or 'error')
    DSP.add_log('СДЕЙКА с ' .. tostring(partner) .. ': ' .. DSP.money(profit) .. ' (' .. DSP.money(total_get) .. '/' .. DSP.money(total_give) .. ')',
        kind == 'profit' and 'ok' or 'error')
    -- Telegram notification for trade
    if DSP.settings.tg_notify and DSP.settings.tg_bot_token and DSP.settings.tg_chat_id then
        local emoji = profit > 0 and '[+]' or (profit < 0 and '[-]' or '[=]')
        local msg = '[palatka ai] Сделка ' .. emoji .. ' '
            .. DSP.money(profit) .. ' с ' .. tostring(partner or '?')
            .. ' (получено: ' .. DSP.money(total_get) .. ', отдано: ' .. DSP.money(total_give) .. ')'
        send_telegram(msg)
    end
end

function DSP.logs.stall_dropped(owner, shop_num, item_name, price)
    local entry = {
        type = 'stall',
        ts = os.time(),
        owner = tostring(owner or '?'),
        shop_num = tostring(shop_num or '?'),
        item_name = tostring(item_name or ''),
        price = tonumber(price) or 0,
        server = DSP.settings.server or 102,
    }
    local key = tostring(entry.ts)
    while DSP.settings.stalls[key] do key = key .. '_' end
    DSP.settings.stalls[key] = entry
    DSP.logs.stall_logs[#DSP.logs.stall_logs + 1] = entry
    DSP.db.save_trades()
    DSP.logs.save_daily_log()
    DSP.add_log('Лавка пала: ' .. tostring(owner) .. '#' .. tostring(shop_num)
        .. ' / ' .. tostring(item_name) .. ' @ ' .. DSP.money(entry.price), 'ok')
end

function DSP.logs.crate_opened(item_name, price, count, source, ench)
    local entry = {
        type = 'crate',
        ts = os.time(),
        item_name = tostring(item_name or ''),
        item = tostring(item_name or ''),
        price = tonumber(price) or 0,
        count = tonumber(count) or 1,
        qty = tonumber(count) or 1,
        crate_type = tostring(source or 'тайник'),
        source = tostring(source or 'тайник'),
        ench = tonumber(ench) or 0,
        server = DSP.settings.server or 102,
    }
    local key = tostring(entry.ts)
    while DSP.settings.crates[key] do key = key .. '_' end
    DSP.settings.crates[key] = entry
    if DSP.rewards then
        local known = tonumber(price) and tonumber(price) > 0
        DSP.rewards.record({kind='item', ts=entry.ts, item_name=entry.item_name, qty=entry.qty, ench=entry.ench,
            source=entry.source, association='explicit', price_known=not not known,
            unit_price=known and tonumber(price) or nil, estimated_value=known and tonumber(price)*entry.qty or nil,
            price_source=known and 'caller' or nil, legacy_id='crate:' .. key})
    end
    DSP.db.save_trades()
    DSP.logs.save_daily_log()
    DSP.add_log('Тайник (' .. entry.source .. '): +' .. tostring(entry.count) .. 'x ' .. tostring(item_name)
        .. ' @ ' .. DSP.money(entry.price), 'ok')
    -- v1.2 Stage 3: push to craglog ring buffer + crates.log file.
    if DSP.craglog and DSP.craglog.log_crate then
        pcall(DSP.craglog.log_crate, entry)
    end
    -- Telegram notification for crate drop
    if DSP.settings.tg_notify and DSP.settings.tg_bot_token and DSP.settings.tg_chat_id then
        send_telegram('[palatka ai] [+] ' .. entry.source .. ': +' .. tostring(entry.count)
            .. 'x ' .. tostring(item_name) .. (entry.ench and entry.ench > 0 and (' +' .. tostring(entry.ench)) or ''))
    end
end

local function day_key(ts, mode)
    if mode == 'hour' then return os.date('%Y-%m-%d %H:00', ts) end
    if mode == 'day' then return os.date('%Y-%m-%d', ts) end
    if mode == 'week' then
        local d = os.date('*t', ts)
        local w = math.floor((d.yday - 1) / 7) + 1
        return string.format('%04d-W%02d', d.year, w)
    end
    if mode == 'month' then return string.format('%04d-%02d', d.year, d.month) end
    return 'all'
end

function DSP.logs.stats(mode)
    mode = mode or 'day'
    local buckets = {}
    for _, e in pairs(DSP.settings.trades or {}) do
        if e and e.type == 'trade' then
            local key = day_key(e.ts or 0, mode)
            local b = buckets[key] or { count = 0, profit = 0, total_get = 0, total_give = 0 }
            b.count = b.count + 1
            b.profit = b.profit + (e.profit or 0)
            b.total_get = b.total_get + (e.total_get or 0)
            b.total_give = b.total_give + (e.total_give or 0)
            buckets[key] = b
        end
    end
    return buckets
end

function DSP.logs.profit_summary(mode)
    local buckets = DSP.logs.stats(mode)
    local total_count, total_profit, total_get, total_give = 0, 0, 0, 0
    local sorted_keys = {}
    for k, _ in pairs(buckets) do table.insert(sorted_keys, k) end
    table.sort(sorted_keys, function(a, b) return a > b end)
    for _, k in ipairs(sorted_keys) do
        local b = buckets[k]
        total_count = total_count + b.count
        total_profit = total_profit + b.profit
        total_get = total_get + b.total_get
        total_give = total_give + b.total_give
    end
    return {
        count = total_count,
        profit = total_profit,
        avg_profit = total_count > 0 and math.floor(total_profit / total_count) or 0,
        total_get = total_get,
        total_give = total_give,
        roi = total_give > 0 and (total_profit / total_give * 100) or 0,
        buckets = buckets,
        sorted_keys = sorted_keys,
    }
end

function DSP.logs.trade_detail(idx)
    local i = 0
    for _, e in pairs(DSP.settings.trades or {}) do
        i = i + 1
        if i == idx and e then return e end
    end
    return nil
end

function DSP.logs.clear_trades()
    DSP.settings.trades = {}
    DSP.settings.stalls = {}
    DSP.settings.crates = {}
    DSP.settings.chat_logs = {}
    DSP.logs.trade_logs = {}
    DSP.logs.stall_logs = {}
    DSP.logs.crate_logs = {}
    DSP.db.save_trades()
    DSP.add_log('Все логи сделок очищены')
end

local function url_encode(s)
    if not s then return '' end
    s = tostring(s):gsub('([^%w%.%-_])', function(c)
        local b = string.byte(c)
        return '%' .. string.format('%02X', b)
    end)
    return s
end

send_telegram = function(msg)
    if not DSP.settings.tg_notify or not DSP.settings.tg_bot_token or not DSP.settings.tg_chat_id then
        return
    end
    msg = tostring(msg or '')
    local url = 'https://api.telegram.org/bot' .. DSP.settings.tg_bot_token
        .. '/sendMessage?chat_id=' .. DSP.settings.tg_chat_id
        .. '&text=' .. url_encode(msg)
    if DSP.http_get then
        pcall(DSP.http_get, url, function(_, _) end)
    end
end

function DSP.logs.parse_chat_drop(text)
    local s = DSP.clean_text(text or '')
    local source, item, qty = s:match('^Вам выпало из (.+): (.+) %((%d+) шт%.%)$')
    if not item then item, qty = s:match('^Вам выпало: (.+) %((%d+) шт%.%)$') end
    if not item then source, item = s:match('^Вы открыли (.+) и получили (.+)$') end
    if not item then source, item = s:match('^Вы использовали (.+) и получили (.+)$') end
    if not item then source, item = s:match('^Вы успешно открыли (.+) и вам выпало (.+)$') end
    if not item then item = s:match('^Вам выпало: (.+)$') or s:match('^Вам выпало (.+)$')
        or s:match('^Вам выпала (.+)$') or s:match('^Вам выпал (.+)$') end
    if not item then return nil end
    if not qty then
        local base, count = item:match('^(.-) %((%d+)%s*шт%.?%)$')
        if base then item, qty = base, count end
    end
    local base, ench = name_ench(item)
    return {name=base, ench=ench, qty=tonumber(qty) or 1, source=DSP.clean_text(source or 'тайник')}
end

function DSP.logs.log_chat(text)
    if not DSP.settings.log_chat_drops then return end
    local s = DSP.clean_text(text or '')
    if s == '' then return end
    -- v1.2 Stage 3: PayDay detection. The hook in 45_live.lua checks the
    -- message for the payday marker and triggers Telegram. The detection
    -- function lives in 45_live.lua to keep this module focused on logging.
    if DSP.live and DSP.live.check_payday_message then
        pcall(DSP.live.check_payday_message, s)
    end
    -- Check for item drop messages (now with source + ench propagation)
    local drop
    if DSP.rewards then
        local row, err = DSP.rewards.ingest(text)
        if err then DSP.add_log('История наград: ' .. tostring(err), 'error') end
    else drop = DSP.logs.parse_chat_drop(s) end
    if drop and drop.name and drop.name ~= '' then
        DSP.logs.crate_opened(drop.name, 0, drop.qty, drop.source, drop.ench)
    end
    -- Store in chat log
    local entry = {
        ts = os.time(),
        text = s,
        kind = 'chat',
    }
    table.insert(DSP.settings.chat_logs, entry)
    while #DSP.settings.chat_logs > 500 do
        table.remove(DSP.settings.chat_logs, 1)
    end
end

function DSP.logs.send_telegram(msg)
    send_telegram(msg)
end

function DSP.logs.export_logs()
    local today = DSP.logs.profit_summary('all')
    local msg = '[palatka ai] Статистика:\n'
        .. 'Сделок: ' .. today.count .. '\n'
        .. 'Прибыль: ' .. DSP.money(today.profit) .. '\n'
        .. 'Получено: ' .. DSP.money(today.total_get) .. '\n'
        .. 'Отдано: ' .. DSP.money(today.total_give) .. '\n'
        .. 'ROI: ' .. string.format('%.1f%%', today.roi) .. '\n'
        .. 'Средняя сделка: ' .. DSP.money(today.avg_profit)
    DSP.logs.send_telegram(msg)
end

function DSP.logs.install()
    if DSP.logs.installed then return end
    DSP.logs.installed = true
end

function DSP.logs.load()
    DSP.db.load_trades()
    if DSP.rewards then DSP.rewards.load() end
end

return true

end
__mod_05_trades()

local function __mod_06_rewards()
-- Append-only reward journal. Associations are evidence-backed inferences, never edits.
DSP.rewards = {pending = {}, sequence = 0, corrupt_lines = 0}
local R = DSP.rewards
local path = DSP.dir .. '/rewards.jsonl'
local cache, cache_keys = {}, {}
local function invalidate()
    cache, cache_keys = {}, {}
end
local function cache_key(prefix, options)
    local out = {prefix}
    for _, key in ipairs({'page','page_size','search','kind','source','source_contains','from_ts','to_ts'}) do
        local value = tostring(options[key] or '')
        out[#out+1] = tostring(#value) .. ':' .. value
    end
    return table.concat(out,'|')
end
local function remember(key, value)
    cache[key] = value; cache_keys[#cache_keys+1] = key
    if #cache_keys > 8 then cache[table.remove(cache_keys,1)] = nil end
    return value
end
local function scan(fn)
    local f = io.open(path, 'r'); if not f then return end
    for line in f:lines() do
        if line ~= '' then
            local ok, row = pcall(decodeJson, line)
            if ok and type(row) == 'table' and row.id then fn(row)
            else R.corrupt_lines = R.corrupt_lines + 1 end
        end
    end
    f:close()
end
local function append(row)
    local ok, raw = pcall(encodeJson, row)
    if not ok or type(raw) ~= 'string' then R.last_error = 'reward encode failed'; return nil, R.last_error end
    local f, err = io.open(path, 'a')
    if not f then R.last_error = err; return nil, err end
    -- A newline isolates any incomplete tail left by an interrupted write.
    local wrote, why = f:write('\n', raw, '\n')
    local closed, close_error = f:close()
    if not wrote or not closed then R.last_error = why or close_error; return nil, R.last_error end
    R.last_error = nil
    invalidate()
    return row
end
function R.record(row)
    R.sequence = R.sequence + 1
    row.id = row.id or ('reward-' .. tostring(R.sequence))
    row.seq = R.sequence
    row.ts = row.ts or os.time()
    row.server = row.server or DSP.settings.server
    return append(row)
end
local function snapshot(row)
    row.price_known = false
    if row.kind ~= 'item' then return end
    local market = DSP.db.get and DSP.db.get(row.item_name, row.ench)
    local buy = market and market.buy
    local price = buy and tonumber(buy.max)
    if price and price > 0 then
        row.unit_price, row.price_known = price, true
        row.estimated_value = price * row.qty
        row.price_source = 'market_buy_max'
        row.price_ts = tonumber(market.updated) and market.updated > 0 and market.updated or nil
        row.price_timestamp_kind = row.price_ts and 'market_snapshot' or 'unknown'
        for _, offer in ipairs(buy.offers or {}) do
            if tonumber(offer.price) == price and tonumber(offer.ts) and offer.ts > 0 then
                row.price_ts = offer.ts; row.price_timestamp_kind = 'offer'; break
            end
        end
        row.price_age = row.price_ts and math.max(0, row.ts - row.price_ts) or nil
    end
    row.valued_at = row.ts
end
function R.load()
    invalidate()
    R.sequence, R.pending, R.corrupt_lines = 0, {}, 0
    local migrated = {}
    scan(function(row)
        R.sequence = math.max(R.sequence, tonumber(row.seq) or 0)
        if row.legacy_id then migrated[row.legacy_id] = true end
    end)
    for key, entry in pairs(DSP.settings.crates or {}) do
        local id = 'crate:' .. tostring(key)
        if not migrated[id] then
            local known = tonumber(entry.price) and entry.price > 0
            R.record({legacy_id=id, ts=entry.ts, kind='item', item_name=entry.item_name or entry.item,
                qty=entry.qty or entry.count or 1, ench=entry.ench or 0, source=entry.source or entry.crate_type or 'тайник',
                association='legacy', price_known=not not known, unit_price=known and entry.price or nil,
                estimated_value=known and entry.price * (entry.qty or entry.count or 1) or nil,
                price_source=known and 'legacy' or nil, raw=entry.raw, legacy=true})
        end
    end
end
local function item_parts(s)
    local qty = s:match('%((%d+)%s*шт%.?%)%s*$')
    if qty then s = s:gsub('%s*%(%d+%s*шт%.?%)%s*$', '') end
    local base, ench = s:match('^(.-)%s*%(%+(%d+)%)$')
    return DSP.clean_text(base or s), tonumber(ench) or 0, tonumber(qty) or 1
end
function R.parse(raw)
    local s = DSP.clean_text(raw or ''):gsub('^%[%d%d:%d%d:%d%d%]%s*', '')
    local name, tail = s:match("^Вам был добавлен предмет '([^']+)'(.*)$")
    if name then
        local base, ench = item_parts(name)
        return {kind='item',item_name=base,ench=ench,qty=tonumber(tail:match('^%s*%((%d+)%s*шт')) or 1,source='неизвестно',association='unknown',pending=true}
    end
    local source = s:match('^Вы открыли (.+)!$')
    if source and not s:find(' и получили ',1,true) then return {kind='opening',source=source,association='explicit'} end
    local amount, origin = s:match('^Вы получили %+?%$([%d%., ]+)%s*(.*)$')
    if not amount then amount, origin = s:match('^Вам начислено %+?%$([%d%., ]+)%s*(.*)$') end
    if amount then return {kind='cash',cash=tonumber((amount:gsub('[^%d]', ''))),source=origin,association='explicit'} end
    local item, accessory = s:match('^Вы получили (.+) от хар%-ки надетого аксессуара (.+)$')
    if item then
        local base, ench, qty = item_parts(item)
        return {kind='item',item_name=base,ench=ench,qty=qty,source=accessory,association='explicit'}
    end
    local generic = s:match('^Вы получили (.+%(%d+%s*шт%.?%))%.?$')
    if generic then
        local base, ench, qty = item_parts(generic)
        return {kind='item',item_name=base,ench=ench,qty=qty,source='неизвестно',association='unknown'}
    end
    local drop = DSP.logs.parse_chat_drop((s:gsub('!$', '')))
    if drop then return {kind='item',item_name=drop.name,ench=drop.ench,qty=drop.qty,source=drop.source,association='explicit'} end
end
function R.ingest(raw, ts)
    local row = R.parse(raw)
    if not row then R.pending = {}; return nil end
    row.raw, row.ts = raw, ts or os.time()
    local pending = row.pending; row.pending = nil
    snapshot(row)
    local saved, err = R.record(row)
    if not saved then return nil, err end
    if row.kind == 'opening' then
        local ids = {}
        for _, entry in ipairs(R.pending) do
            if row.ts >= entry.ts and row.ts - entry.ts <= 3 then ids[#ids+1] = entry.id end
        end
        R.pending = {}
        if #ids > 0 then
            local link, link_error = R.record({kind='association',ts=row.ts,source=row.source,opening_id=row.id,
                item_ids=ids,association='inferred',raw=raw})
            if not link then return row, link_error end
        end
    elseif pending then
        R.pending[#R.pending+1] = row
        if #R.pending > 32 then table.remove(R.pending,1) end
    else R.pending = {} end
    return row
end
local function matches(row, o)
    local lower = DSP.lower or string.lower
    if o.kind and o.kind ~= '' and row.kind ~= o.kind then return false end
    if o.source and o.source ~= '' and row.source ~= o.source then return false end
    if o.source_contains and o.source_contains ~= '' and
        not lower(row.source or ''):find(lower(o.source_contains),1,true) then return false end
    if o.from_ts and row.ts < o.from_ts then return false end
    if o.to_ts and row.ts > o.to_ts then return false end
    if o.search and o.search ~= '' then
        local hay = (row.item_name or '') .. ' ' .. (row.source or '') .. ' ' .. (row.raw or '')
        if not lower(hay):find(lower(o.search),1,true) then return false end
    end
    return true
end
local function read_rows(o)
    R.corrupt_lines = 0
    local rows, links = {}, {}
    scan(function(row)
        if row.kind == 'association' then
            for _, id in ipairs(row.item_ids or {}) do links[id] = row end
        else rows[#rows+1] = row end
    end)
    local filtered = {}
    for _, row in ipairs(rows) do
        local link = links[row.id]
        if link then row.source, row.opening_id, row.association = link.source, link.opening_id, 'inferred'; row.source_raw = link.raw end
        if matches(row,o) then filtered[#filtered+1] = row end
    end
    table.sort(filtered,function(a,b) if a.ts ~= b.ts then return a.ts > b.ts end return (a.seq or 0) > (b.seq or 0) end)
    return filtered
end
function R.query(options)
    local o = options or {}
    local key = cache_key('query',o)
    if cache[key] then cache[key].error = R.last_error; return cache[key] end
    local rows = read_rows(o)
    local size = math.max(1,math.min(200, math.floor(tonumber(o.page_size) or 25)))
    local pages = math.max(1,math.ceil(#rows / size))
    local page = math.max(1,math.min(pages,math.floor(tonumber(o.page) or 1)))
    local entries = {}
    for i=(page-1)*size+1,math.min(page*size,#rows) do entries[#entries+1] = rows[i] end
    return remember(key,{entries=entries,total=#rows,page=page,pages=pages,page_size=size,error=R.last_error,corrupt_lines=R.corrupt_lines})
end
function R.summary(options)
    local key = cache_key('summary',options or {})
    if cache[key] then return cache[key] end
    local out = {cash=0,estimated_value=0,unknown_items=0,items=0,openings=0}
    for _, row in ipairs(read_rows(options or {})) do
        if row.kind=='cash' then out.cash=out.cash+(row.cash or 0)
        elseif row.kind=='opening' then out.openings=out.openings+1
        elseif row.kind=='item' then
            out.items=out.items+(row.qty or 1)
            if row.price_known then out.estimated_value=out.estimated_value+(row.estimated_value or 0)
            else out.unknown_items=out.unknown_items+1 end
        end
    end
    return remember(key,out)
end
return true

end
__mod_06_rewards()

local function __mod_20_presets()
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
    if DSP.auto and (DSP.auto.buy_running or DSP.auto.sell_running) then return false, 'остановите автоматизацию' end
    local p = preset(kind)
    local it = table.remove(p.items, idx)
    if it then
        DSP.save_settings()
        DSP.add_log('Удалено из ' .. p.name .. ': ' .. it.name)
    end
end

function DSP.presets.clear(kind)
    if DSP.auto and (DSP.auto.buy_running or DSP.auto.sell_running) then return false, 'остановите автоматизацию' end
    local p = preset(kind)
    p.items = {}
    DSP.save_settings()
    DSP.add_log(p.name .. ': список очищен')
end

function DSP.presets.recalc(kind)
    if DSP.auto and (DSP.auto.buy_running or DSP.auto.sell_running) then return false, 'остановите автоматизацию' end
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

end
__mod_20_presets()

local function __mod_21_preset_library()
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
local function save() DSP.save_settings() end
local function positive(v)
    local n = tonumber(v)
    if n and n == n and n > 0 and n <= 9007199254740991 and n % 1 == 0 then return n end
end
function P.list(kind) return (library(kind)) end
function P.selected(kind) local _, idx = library(kind); return idx end
function P.select(kind, idx)
    if busy() then return false, 'остановите автоматизацию' end
    local list = library(kind)
    if not list[idx] then return false, 'нет пресета' end
    local _, active, legacy = keys(kind)
    DSP.settings[active], DSP.settings[legacy] = idx, list[idx]
    save(); return true
end
function P.create(kind, name)
    if busy() then return false, 'остановите автоматизацию' end
    name = tostring(name or ''):match('^%s*(.-)%s*$')
    if name == '' then return false, 'введите название' end
    local list = library(kind)
    list[#list + 1] = {name = name, items = {}}
    P.select(kind, #list)
    return true, #list
end
function P.rename(kind, idx, name)
    if busy() then return false, 'остановите автоматизацию' end
    local list = library(kind)
    name = tostring(name or ''):match('^%s*(.-)%s*$')
    if not list[idx] or name == '' then return false, 'некорректное название' end
    list[idx].name = name; save(); return true
end
function P.delete(kind, idx)
    if busy() then return false, 'остановите автоматизацию' end
    local list, active = library(kind)
    if #list <= 1 or not list[idx] then return false, 'нужен хотя бы один пресет' end
    table.remove(list, idx)
    if idx < active then active = active - 1 end
    return P.select(kind, math.min(active, #list))
end
function P.update(kind, idx, changes)
    if busy() then return false, 'остановите автоматизацию' end
    local it = P.items(kind)[idx]
    if not it or type(changes) ~= 'table' then return false, 'нет позиции' end
    local price = changes.price ~= nil and positive(changes.price) or it.price
    local qty = changes.qty ~= nil and positive(changes.qty) or it.qty
    if (changes.price ~= nil and not positive(changes.price)) or
        (changes.qty ~= nil and not positive(changes.qty)) then return false, 'нужно положительное целое число' end
    it.price, it.qty = price, qty
    if positive(price) then it.needs_price = nil end
    if changes.enabled ~= nil then it.enabled = changes.enabled == true end
    save(); return true
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
        result[#result + 1] = {name = DSP.item_name(base, ench), key = DSP.item_key(base, ench), ench = ench,
            price = price, qty = qty, enabled = it.enabled ~= false and price > 0,
            needs_price = price == 0 or nil,
            item_id = it.item_id, qty_limit_1 = it.qty_limit_1}
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
        max_price = tonumber(item.price), qty = item.qty or 1, enabled = item.enabled}}, kind)
    if not rows then return false, 'некорректная позиция' end
    if P.find(kind, rows[1].key) then return false, 'позиция уже есть в пресете' end
    local items = P.items(kind)
    items[#items + 1] = rows[1]
    save(); return true, #items
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
    save(); return true, count
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
    local raw = f:read('*a'); f:close()
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
    local f, err = io.open(path, 'wb')
    if not f then return false, err end
    local written, write_err = f:write(raw)
    local closed, close_err = f:close()
    if not written or not closed then return false, write_err or close_err end
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

end
__mod_21_preset_library()

local function __mod_30_ui()
-- 30_ui.lua
-- v1.2 main UI: horizontal Top Bar + landscape window + theme system + pager.
--
-- The legacy DSP.ui.tab (numeric 1..8) and the new DSP.ui.screen (string)
-- are kept in sync by DSP.screens.set_index() so that:
--   * Old code that does `DSP.ui.tab = N` still works.
--   * The Top Bar sets the active screen by string id.
--
-- All *_tab() functions from v1.1 are preserved (market, trade, auto, log,
-- calculator, statistics, settings). The v1.2 dispatcher (DSP.screens.draw)
-- maps the active screen id to the right *_tab() function.

local ffi = require('ffi')

local function count_keys(t)
    if not t then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function to_sorted_array(t)
    local arr = {}
    if type(t) == 'table' then
        for _, v in pairs(t) do
            if type(v) == 'table' then arr[#arr + 1] = v end
        end
    end
    table.sort(arr, function(a, b)
        return (a.ts or 0) < (b.ts or 0)
    end)
    return arr
end

DSP.ui = DSP.ui or {}
DSP.ui.open = false
DSP.ui.tab = 1
DSP.ui.search = ''
DSP.ui.selected = nil
DSP.ui.page = 1
DSP.ui.preset_kind = 'buy'
DSP.ui.margin_dirty = false
DSP.ui.d = tonumber(DSP.settings.dpi) or 1.25
DSP.ui.search_buf = nil
DSP.ui.open_ref = nil
DSP.ui.chk = {}
DSP.ui.calc_buy = 1000
DSP.ui.calc_sell = 1000
DSP.ui.calc_qty = 1
DSP.ui.stat_mode = 'day'
DSP.ui.tab_detail = 'trades'

-- v1.2 additions: per-screen page state, sync with DSP.ui.screen
DSP.ui.screen = DSP.settings.screen or 'palatka'
DSP.ui.pages = DSP.ui.pages or {}

local ACC = DSP.acc

local function col(r, g, b, a)
    return imgui.ImVec4(r, g, b, a or 1)
end

local function acc_col(a)
    return col(ACC[1], ACC[2], ACC[3], a)
end

local function d()
    return DSP.ui.d
end

local function trunc(s, n)
    s = tostring(s or '')
    if #s > n then return s:sub(1, n - 1) .. '.' end
    return s
end

local function checkbox(label, key)
    local b = imgui.new.bool(DSP.settings[key] and true or false)
    if imgui.Checkbox(label, b) then
        DSP.settings[key] = b[0]
        DSP.save_settings()
        DSP.market.state.filter_version = -1
        DSP.ui.page = 1
    end
end

-- Legacy numeric nav kept for backward compat with tests; never rendered in v1.2.
local function nav(label, id)
    local active = DSP.ui.tab == id
    if active then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.72)) end
    if imgui.Button(label, imgui.ImVec2(-1, 38 * d())) then
        DSP.screens.set_index(id)
    end
    if active then imgui.PopStyleColor(1) end
    imgui.Spacing()
end

function DSP.ui.set_open(v)
    DSP.ui.open = v and true or false
    if DSP.ui.open_ref then DSP.ui.open_ref[0] = DSP.ui.open end
end

function DSP.ui.toggle()
    DSP.ui.set_open(not DSP.ui.open)
end

function DSP.ui.init()
    DSP.ui.d = tonumber(DSP.settings.dpi) or 1.25
    DSP.ui.open_ref = imgui.new.bool(false)
    DSP.ui.search_buf = imgui.new.char[128]()
    DSP.ui.chk.only_profit = imgui.new.bool(DSP.settings.only_profit and true or false)
    DSP.ui.chk.liquid = imgui.new.bool(DSP.settings.liquid and true or false)
    DSP.ui.chk.dry_run = imgui.new.bool(DSP.settings.dry_run ~= false)
    DSP.ui.calc_buy_ref = imgui.new.int(1000)
    DSP.ui.calc_sell_ref = imgui.new.int(1000)
    DSP.ui.calc_qty_ref = imgui.new.int(1)
    DSP.ui.stat_mode = DSP.settings.stats_mode or 'day'
    DSP.ui.chk.tg_notify = imgui.new.bool(DSP.settings.tg_notify and true or false)
    DSP.ui.chk.log_drops = imgui.new.bool(DSP.settings.log_chat_drops ~= false)
    DSP.ui.tg_token_buf = imgui.new.char[256]()
    DSP.ui.tg_chat_buf = imgui.new.char[64]()
    if DSP.settings.tg_bot_token then ffi.copy(DSP.ui.tg_token_buf, DSP.settings.tg_bot_token, #DSP.settings.tg_bot_token) end
    if DSP.settings.tg_chat_id then ffi.copy(DSP.ui.tg_chat_buf, DSP.settings.tg_chat_id, #DSP.settings.tg_chat_id) end
    -- v1.2 Stage 2: arbitrage budget input + finder search buffer
    DSP.ui.arb_budget_ref = imgui.new.int(tonumber(DSP.settings.arb_filters and DSP.settings.arb_filters.budget) or 0)
    DSP.ui.finder_search_buf = imgui.new.char[128]()
    DSP.ui.finder_query = ''
    DSP.ui.lavki_expanded = {}
    -- v1.2 Stage 3: notes debounced auto-save state
    DSP.ui.notes_buf = imgui.new.char[8192]()
    DSP.ui._notes_dirty = false
    DSP.ui._notes_last_edit = 0
    DSP.ui._cr_pos_dirty = false
    DSP.ui._cr_last_save = 0
    local notes = ''
    local nf = io.open(DSP.notes_path, 'r')
    if nf then notes = nf:read('*a') or ''; nf:close() end
    if #notes > 0 then
        local encoded = DSP.to_u8(notes)
        ffi.copy(DSP.ui.notes_buf, encoded, math.min(#encoded, 8191))
    end
    -- v1.2: sync screen <-> tab
    DSP.ui.screen = DSP.settings.screen or 'palatka'
    DSP.ui.tab = DSP.screens.index_by_id(DSP.ui.screen)
    if sampRegisterChatCommand then
        sampRegisterChatCommand('crr', function() DSP.ui.toggle() end)
    end
    DSP.add_log('palatka ai v' .. DSP.version .. ' загружен')
end

function DSP.ui.header()
    local st = DSP.market.state
    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8('PALATKA AI'))
    imgui.SameLine(0, 14 * d())
    imgui.TextDisabled(DSP.utf8('Mobile ' .. tostring(st.sid)))
    imgui.SameLine(0, 14 * d())
    local status = st.status == 'loading' and 'обновление...'
        or st.status == 'error' and ('ошибка: ' .. tostring(st.error))
        or st.status == 'cache' and 'кэш'
        or 'live'
    local sc = st.status == 'error' and DSP.theme.col('bad', 1) or DSP.theme.col('good', 1)
    imgui.TextColored(sc, DSP.utf8(status))
    imgui.SameLine(0, 14 * d())
    imgui.TextDisabled(DSP.utf8(string.format('Лавок: %d  |  Офферов: %d  |  Свежесть: %s',
        st.shops or 0, st.offers or 0, DSP.market.freshness())))
    local bw = 130 * d()
    local avail = imgui.GetContentRegionAvail().x
    if avail > bw + 10 then
        imgui.SameLine(imgui.GetWindowWidth() - bw - 24 * d())
    else
        imgui.SameLine(0, 10 * d())
    end
    if st.status == 'loading' then
        imgui.TextDisabled(DSP.utf8('...'))
    elseif imgui.Button(DSP.utf8('ОБНОВИТЬ'), imgui.ImVec2(bw, 0)) then
        DSP.market.pull(st.sid)
    end
    imgui.Separator()
end

function DSP.ui.server_buttons()
    imgui.TextDisabled(DSP.utf8('Сервер:'))
    imgui.SameLine(0, 8 * d())
    for _, s in ipairs(DSP.market.servers) do
        local active = DSP.market.state.sid == s.id
        if active then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
        if imgui.Button(s.name, imgui.ImVec2(92 * d(), 0)) then
            if DSP.market.state.sid ~= s.id then
                DSP.market.state.sid = s.id
                DSP.settings.server = s.id
                DSP.save_settings()
                DSP.ui.selected = nil
                DSP.ui.page = 1
                DSP.market.pull(s.id)
            end
        end
        if active then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()
end

function DSP.ui.market_tab()
    DSP.ui.header()
    DSP.ui.server_buttons()

    imgui.SetNextItemWidth(320 * d())
    if imgui.InputTextWithHint('##dsp_search', DSP.utf8('Поиск по названию...'), DSP.ui.search_buf, 128) then
        DSP.ui.search = ffi.string(DSP.ui.search_buf)
        DSP.market.state.filter_version = -1
        DSP.ui.page = 1
    end
    imgui.SameLine(0, 12 * d())
    if imgui.Checkbox(DSP.utf8('Только с профитом'), DSP.ui.chk.only_profit) then
        DSP.settings.only_profit = DSP.ui.chk.only_profit[0]
        DSP.save_settings()
        DSP.market.state.filter_version = -1
        DSP.ui.page = 1
    end
    imgui.SameLine(0, 12 * d())
    if imgui.Checkbox(DSP.utf8('Ликвидные (2+ оффера)'), DSP.ui.chk.liquid) then
        DSP.settings.liquid = DSP.ui.chk.liquid[0]
        DSP.save_settings()
        DSP.market.state.filter_version = -1
        DSP.ui.page = 1
    end

    local rows = DSP.market.filtered()
    local per = math.max(5, tonumber(DSP.settings.per_page) or 20)
    local sel = DSP.ui.selected and DSP.market.state.by_key[DSP.ui.selected] or nil

    imgui.TextDisabled(DSP.utf8(string.format('Найдено: %d  |  сортировка: %s',
        #rows,
        (tonumber(DSP.settings.sort) == 2 and 'дешёвые'
            or tonumber(DSP.settings.sort) == 3 and 'дорогая скупка'
            or tonumber(DSP.settings.sort) == 4 and 'процент'
            or tonumber(DSP.settings.sort) == 5 and 'офферы'
            or 'выгода'))))

    local avail = imgui.GetContentRegionAvail()
    local detail_h = sel and (196 * d()) or 0
    local table_h = math.max(150 * d(), avail.y - detail_h - 100 * d())
    local cw = avail.x
    if cw < 600 * d() then cw = 600 * d() end
    local widths = {
        math.floor(cw * 0.38), math.floor(cw * 0.15), math.floor(cw * 0.15),
        math.floor(cw * 0.16), math.floor(cw * 0.08), math.floor(cw * 0.08),
    }

    if imgui.BeginChild('##dsp_mkt_table', imgui.ImVec2(-1, table_h), true) then
        imgui.Columns(6, '##dsp_hdr', false)
        for i = 0, 5 do imgui.SetColumnWidth(i, widths[i + 1]) end
        imgui.TextDisabled(DSP.utf8('ТОВАР'))
        imgui.NextColumn(); imgui.TextDisabled(DSP.utf8('СКУПКА'))
        imgui.NextColumn(); imgui.TextDisabled(DSP.utf8('ПРОДАЖА'))
        imgui.NextColumn(); imgui.TextDisabled(DSP.utf8('ВЫГОДА'))
        imgui.NextColumn(); imgui.TextDisabled(DSP.utf8('КОЛ-ВО'))
        imgui.NextColumn(); imgui.TextDisabled(DSP.utf8('ОФФ.'))
        imgui.NextColumn()
        imgui.Separator()
        imgui.Columns(1)

        -- v1.2 pager integration: fetch the slice for the current screen.
        local from, to = DSP.screens.pager(#rows, per, 'arbitrage')
        imgui.Columns(6, '##dsp_rows', false)
        for i = 0, 5 do imgui.SetColumnWidth(i, widths[i + 1]) end
        for i = from, to do
            local row = rows[i]
            if row then
                local selected = DSP.ui.selected == row.key
                local label = DSP.utf8(row.display) .. '##dsp_r' .. tostring(i)
                if imgui.Selectable(label, selected,
                    imgui.SelectableFlags.SpanAllColumns + imgui.SelectableFlags.AllowDoubleClick,
                    imgui.ImVec2(0, 28 * d())) then
                    DSP.ui.selected = row.key
                end
                imgui.NextColumn()
                if row.buy.count > 0 then
                    imgui.TextColored(DSP.theme.col('good', 1), DSP.money(row.buy.best))
                else
                    imgui.TextDisabled('-')
                end
                imgui.NextColumn()
                if row.sell.count > 0 then
                    imgui.TextColored(DSP.theme.col('warn', 1), DSP.money(row.sell.best))
                else
                    imgui.TextDisabled('-')
                end
                imgui.NextColumn()
                if row.sell.count > 0 and row.buy.count > 0 then
                    local pc = row.profit > 0 and DSP.theme.col('good', 1)
                        or row.profit < 0 and DSP.theme.col('bad', 1) or DSP.theme.col('muted', 1)
                    local ps = (row.profit > 0 and '+' or '') .. DSP.money(row.profit)
                    imgui.TextColored(pc, ps)
                    imgui.SameLine(0, 5 * d())
                    imgui.TextDisabled(string.format('%.0f%%', row.profit_pct or 0))
                else
                    imgui.TextDisabled('-')
                end
                imgui.NextColumn()
                imgui.TextDisabled(string.format('%d/%d', row.sell.qty, row.buy.qty))
                imgui.NextColumn()
                imgui.TextDisabled(string.format('%d/%d', row.sell.count, row.buy.count))
                imgui.NextColumn()
            end
        end
        imgui.Columns(1)
        if #rows == 0 then
            imgui.Spacing()
            imgui.TextDisabled(DSP.utf8('Нет строк под фильтр. Нажмите ОБНОВИТЬ.'))
        end
        imgui.EndChild()
    end

    -- per-page size selector on the right of the pager
    DSP.screens.per_page_selector()

    if sel then
        imgui.Separator()
        DSP.ui.detail(sel)
    end
end

function DSP.ui.detail(row)
    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8(trunc(row.display, 42)))
    imgui.SameLine(0, 14 * d())
    local pc = row.profit > 0 and DSP.theme.col('good', 1) or DSP.theme.col('bad', 1)
    imgui.TextColored(pc, DSP.utf8('выгода ') .. (row.profit > 0 and '+' or '') .. DSP.money(row.profit))
    imgui.SameLine(0, 10 * d())
    imgui.TextDisabled(string.format('(%+.1f%%)', row.profit_pct or 0))
    imgui.SameLine(0, 20 * d())
    if imgui.SmallButton(DSP.utf8('закрыть')) then DSP.ui.selected = nil end
    -- v1.2 hotfix: рыночная метка. Если есть скан ЦР (файл prices_server_{SID}.json)
    -- — показывает «Рынок ЦР #N: Продажа ~X$ | Скупка ~Y$ (метка DD.MM HH:MM)».
    -- Иначе: динамическая медиана из va-ta.com — «Рынок #N: Продажа ~X$ | Скупка ~Y$ (на основе N лавок)».
    imgui.Spacing()
    local label = DSP.market.market_label_for(row)
    if label and label ~= '' then
        imgui.TextColored(DSP.theme.col('muted', 1), DSP.utf8(label))
    end
    imgui.Spacing()
    local h = 100 * d()
    if imgui.BeginChild('##dsp_d_sell', imgui.ImVec2(-1, h), true) then
        imgui.TextDisabled(DSP.utf8('КУПИТЬ ДЕШЕВЛЕ (лавка продаёт)'))
        for i = 1, math.min(3, #row.sell.offers) do
            local o = row.sell.offers[i]
            imgui.TextColored(DSP.theme.col('warn', 1), DSP.money(o.price))
            imgui.SameLine(0, 8 * d())
            imgui.TextDisabled(DSP.utf8(string.format('x%d  #%s  %s', o.qty, o.shop, trunc(o.owner, 18))))
        end
        if #row.sell.offers == 0 then imgui.TextDisabled('-') end
        imgui.EndChild()
    end
    if imgui.BeginChild('##dsp_d_buy', imgui.ImVec2(-1, h), true) then
        imgui.TextDisabled(DSP.utf8('ПРОДАТЬ ДОРОЖЕ (лавка скупает)'))
        for i = 1, math.min(3, #row.buy.offers) do
            local o = row.buy.offers[i]
            imgui.TextColored(DSP.theme.col('good', 1), DSP.money(o.price))
            imgui.SameLine(0, 8 * d())
            imgui.TextDisabled(DSP.utf8(string.format('x%d  #%s  %s', o.qty, o.shop, trunc(o.owner, 18))))
        end
        if #row.buy.offers == 0 then imgui.TextDisabled('-') end
        imgui.EndChild()
    end
    local bw = 210 * d()
    local bt = DSP.market.buy_target(row)
    local st = DSP.market.sell_target(row)
    if imgui.Button(DSP.utf8('+ В скупку  ' .. DSP.money(bt)), imgui.ImVec2(bw, 0)) then
        local ok, err = DSP.presets.add(row, 'buy')
        if not ok then DSP.notify('Скупка: ' .. tostring(err)) end
    end
    imgui.SameLine(0, 10 * d())
    if imgui.Button(DSP.utf8('+ В продажу  ' .. DSP.money(st)), imgui.ImVec2(bw, 0)) then
        local ok, err = DSP.presets.add(row, 'sell')
        if not ok then DSP.notify('Продажа: ' .. tostring(err)) end
    end
end

function DSP.ui.trade_tab()
    local kind = DSP.ui.preset_kind
    local p = kind == 'buy' and DSP.settings.buy_preset or DSP.settings.sell_preset

    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8('ТОРГОВЛЯ'))
    imgui.SameLine(0, 18 * d())
    if kind == 'buy' then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
    if imgui.Button(DSP.utf8('СКУПКА'), imgui.ImVec2(130 * d(), 0)) then DSP.ui.preset_kind = 'buy' end
    if kind == 'buy' then imgui.PopStyleColor(1) end
    imgui.SameLine(0, 6 * d())
    if kind == 'sell' then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
    if imgui.Button(DSP.utf8('ПРОДАЖА'), imgui.ImVec2(130 * d(), 0)) then DSP.ui.preset_kind = 'sell' end
    if kind == 'sell' then imgui.PopStyleColor(1) end
    imgui.SameLine(0, 18 * d())
    imgui.TextDisabled(DSP.utf8(string.format('%s: %d поз.', p.name or kind, #p.items)))
    imgui.Separator()

    local avail = imgui.GetContentRegionAvail()
    local inv_h = math.min(220 * d(), avail.y * 0.55)
    local pre_h = avail.y - inv_h - 40 * d()

    if imgui.BeginChild('##dsp_trade_presets', imgui.ImVec2(-1, pre_h), true) then
        if #p.items == 0 then
            imgui.TextDisabled(DSP.utf8('Пусто. Сканируйте инвентарь и добавляйте товары.'))
        end
        -- v1.2 hotfix: full inline preset editor. Per-item row layout:
        --   [x] name  [Price: 50.000$] [-1$] [Рынок] [+10к] [-10к] [+100к]  [Кол-во: 100] [X]
        -- All inputs write straight to it.price / it.qty and save_settings.
        -- Auto-выставление (40_auto.lua) reads it.price + it.qty when
        -- queueing dialog responses (15068-15071), so editing here
        -- guarantees the price/qty that lands in the dialog.
        for i, it in ipairs(p.items) do
            -- Row 1: enable checkbox + item name + estimate
            local en = imgui.new.bool(it.enabled ~= false)
            if imgui.Checkbox('##dsp_en' .. i, en) then
                it.enabled = en[0]
                DSP.save_settings()
            end
            imgui.SameLine(0, 8 * d())
            imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8(trunc(it.name, 28)))
            imgui.SameLine(0, 12 * d())
            local est = DSP.presets.estimate(it, kind)
            if est then
                local ec = est >= 0 and DSP.theme.col('good', 1) or DSP.theme.col('bad', 1)
                imgui.TextColored(ec, DSP.utf8('профит ' .. (est >= 0 and '+' or '') .. DSP.money(est)))
            end

            -- Row 2: price input + quick adjust buttons
            imgui.TextDisabled(DSP.utf8('  Цена:'))
            imgui.SameLine(0, 6 * d())
            imgui.SetNextItemWidth(140 * d())
            local price_ref = imgui.new.int(tonumber(it.price) or 0)
            if imgui.InputInt('##dsp_price' .. i, price_ref, 1000, 100000) then
                it.price = math.max(0, price_ref[0])
                DSP.save_settings()
            end
            imgui.SameLine(0, 4 * d())
            -- Quick adjust: -1$ / Рынок / +10к / -10к / +100к
            if imgui.SmallButton(DSP.utf8('-1$##pm1_' .. i)) then
                it.price = math.max(0, (tonumber(it.price) or 0) - 1)
                DSP.save_settings()
            end
            imgui.SameLine(0, 2 * d())
            if imgui.SmallButton(DSP.utf8('Рынок##pmr_' .. i)) then
                local row = DSP.presets.find_row(it)
                if row then
                    local target = kind == 'buy'
                        and DSP.market.buy_target(row)
                        or  DSP.market.sell_target(row)
                    if target > 0 then
                        it.price = target
                        DSP.save_settings()
                    else
                        DSP.notify('Рынок: нет базы для ' .. tostring(it.name))
                    end
                else
                    DSP.notify('Рынок: товар не найден в базе')
                end
            end
            imgui.SameLine(0, 2 * d())
            if imgui.SmallButton(DSP.utf8('+10к##pp10k_' .. i)) then
                it.price = (tonumber(it.price) or 0) + 10000
                DSP.save_settings()
            end
            imgui.SameLine(0, 2 * d())
            if imgui.SmallButton(DSP.utf8('-10к##pm10k_' .. i)) then
                it.price = math.max(0, (tonumber(it.price) or 0) - 10000)
                DSP.save_settings()
            end
            imgui.SameLine(0, 2 * d())
            if imgui.SmallButton(DSP.utf8('+100к##pp100k_' .. i)) then
                it.price = (tonumber(it.price) or 0) + 100000
                DSP.save_settings()
            end

            -- Row 3: qty input + delete [X]
            imgui.TextDisabled(DSP.utf8('  Кол-во:'))
            imgui.SameLine(0, 6 * d())
            imgui.SetNextItemWidth(100 * d())
            local qty_ref = imgui.new.int(tonumber(it.qty) or 1)
            if imgui.InputInt('##dsp_qty' .. i, qty_ref, 1, 10) then
                it.qty = math.max(1, qty_ref[0])
                DSP.save_settings()
            end
            imgui.SameLine(0, 12 * d())
            if imgui.Button(DSP.utf8('[X]##del_' .. i), imgui.ImVec2(44 * d(), 32 * d())) then
                DSP.presets.remove(kind, i)
                break
            end
            imgui.Separator()
        end
        imgui.EndChild()
    end
    imgui.Separator()

    imgui.TextDisabled(DSP.utf8('СКАН ИНВЕНТАРЯ: ' .. (DSP.auto.inv_status or 'не сканирован')))
    if imgui.Button(DSP.utf8('СКАНИРОВАТЬ'), imgui.ImVec2(120 * d(), 0)) then
        DSP.auto.scan_inventory()
    end
    imgui.SameLine(0, 8 * d())
    imgui.TextDisabled(DSP.utf8('позиций: ' .. tostring(#(DSP.auto.inv or {}))))

    if DSP.auto and DSP.auto.inv and #DSP.auto.inv > 0 then
        if imgui.BeginChild('##dsp_trade_inv', imgui.ImVec2(-1, inv_h), true) then
            for _, inv_item in ipairs(DSP.auto.inv or {}) do
                imgui.Text(DSP.utf8(trunc(inv_item.name or '', 34)))
                imgui.SameLine(0, 8 * d())
                imgui.TextDisabled(DSP.utf8('x' .. tostring(inv_item.count or 0)))
                imgui.SameLine(0, 8 * d())
                local row = DSP.market.row_for(inv_item.name, 0)
                local price_text = '-'
                local price_color = DSP.theme.col('muted', 1)
                if row then
                    if kind == 'buy' then
                        local bp = DSP.market.buy_target(row)
                        if bp > 0 then price_text = DSP.money(bp); price_color = DSP.theme.col('good', 1) end
                    else
                        local sp = DSP.market.sell_target(row)
                        if sp > 0 then price_text = DSP.money(sp); price_color = DSP.theme.col('warn', 1) end
                    end
                end
                imgui.TextColored(price_color, price_text)
                imgui.SameLine(0, 8 * d())
                if row then
                    local rev = row.buy and row.buy.max or 0
                    local cost = row.sell and row.sell.min or 0
                    local pct = cost > 0 and ((rev / cost - 1) * 100) or 0
                    imgui.TextDisabled(string.format('%+.0f%%', pct))
                end
                imgui.SameLine(0, 6 * d())
                if imgui.SmallButton(DSP.utf8('+скуп##dsp_inv_buy_' .. inv_item.name)) then
                    if row then
                        local ok, err = DSP.presets.add(row, 'buy')
                        DSP.notify(ok and 'OK' or ('Ошибка: ' .. tostring(err)))
                    end
                end
                imgui.SameLine(0, 3 * d())
                if imgui.SmallButton(DSP.utf8('+прод##dsp_inv_sell_' .. inv_item.name)) then
                    if row then
                        local ok, err = DSP.presets.add(row, 'sell')
                        DSP.notify(ok and 'OK' or ('Ошибка: ' .. tostring(err)))
                    end
                end
                imgui.Spacing()
            end
            imgui.EndChild()
        end
    end

    if imgui.Button(DSP.utf8('ПЕРЕСЧИТАТЬ'), imgui.ImVec2(160 * d(), 0)) then
        DSP.presets.recalc(kind)
    end
    imgui.SameLine(0, 8 * d())
    if imgui.Button(DSP.utf8('ИМПОРТ ИЗ MH'), imgui.ImVec2(140 * d(), 0)) then
        local ok, err = DSP.presets.import_mh()
        DSP.notify(ok and ('Импорт: ' .. tostring(err)) or ('Импорт: ' .. tostring(err)))
    end
    imgui.SameLine(0, 8 * d())
    if imgui.Button(DSP.utf8('ОЧИСТИТЬ'), imgui.ImVec2(110 * d(), 0)) then DSP.presets.clear(kind) end
    imgui.SameLine(0, 12 * d())
    if kind == 'buy' then
        if DSP.auto.buy_running then
            if imgui.Button(DSP.utf8('СТОП СКУПКИ'), imgui.ImVec2(140 * d(), 0)) then DSP.auto.stop_buy() end
        else
            if imgui.Button(DSP.utf8('СТАРТ СКУПКИ'), imgui.ImVec2(140 * d(), 0)) then DSP.auto.start_buy() end
        end
    else
        if DSP.auto.sell_running then
            if imgui.Button(DSP.utf8('СТОП ПРОДАЖИ'), imgui.ImVec2(140 * d(), 0)) then DSP.auto.stop_sell() end
        else
            if imgui.Button(DSP.utf8('СТАРТ ПРОДАЖИ'), imgui.ImVec2(140 * d(), 0)) then DSP.auto.start_sell() end
        end
    end
    imgui.SameLine(0, 10 * d())
    imgui.TextDisabled(DSP.utf8('dry-run: ') .. (DSP.settings.dry_run and 'ON' or 'OFF'))
end

-- v1.2 alias: ПАЛАТКА screen -> trade_tab for Stage 1.
-- Stage 2 will replace this with a dedicated palatka_tab() that merges
-- preset выставление + auto-sell controls into a single mobile-friendly card.
DSP.ui.palatka_tab = DSP.ui.trade_tab

function DSP.ui.auto_tab()
    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8('АВТО'))
    imgui.Separator()
    local st = DSP.auto and DSP.auto.status_text and DSP.auto.status_text() or 'движок не загружен'
    imgui.TextDisabled(DSP.utf8(st))
    imgui.Spacing()

    if imgui.BeginChild('##dsp_auto_buy', imgui.ImVec2(-1, 150 * d()), true) then
        imgui.TextColored(DSP.theme.col('good', 1), DSP.utf8('АВТО-СКУПКА'))
        imgui.TextDisabled(DSP.utf8(string.format('Пресет: %d поз.  |  маржа: %d%%  |  кол-во: %d',
            DSP.presets.active_count('buy'), tonumber(DSP.settings.margin) or 10,
            tonumber(DSP.settings.auto_buy_qty) or 1)))
        if DSP.auto.buy_running then
            if imgui.Button(DSP.utf8('СТОП'), imgui.ImVec2(140 * d(), 0)) then DSP.auto.stop_buy() end
        else
            if imgui.Button(DSP.utf8('СТАРТ'), imgui.ImVec2(140 * d(), 0)) then DSP.auto.start_buy() end
        end
        imgui.SameLine(0, 12 * d())
        if imgui.Button(DSP.utf8('ПЕРЕСЧИТАТЬ'), imgui.ImVec2(160 * d(), 0)) then DSP.presets.recalc('buy') end
        imgui.SameLine(0, 16 * d())
        if imgui.Checkbox(DSP.utf8('dry-run (без покупок)'), DSP.ui.chk.dry_run) then
            DSP.settings.dry_run = DSP.ui.chk.dry_run[0]
            DSP.save_settings()
        end
        imgui.EndChild()
    end
    imgui.Spacing()
    if imgui.BeginChild('##dsp_auto_sell', imgui.ImVec2(-1, 150 * d()), true) then
        imgui.TextColored(DSP.theme.col('warn', 1), DSP.utf8('АВТО-ПРОДАЖА'))
        imgui.TextDisabled(DSP.utf8(string.format('Пресет: %d поз.  |  undercut: %d%%  |  инвентарь: %s',
            DSP.presets.active_count('sell'), tonumber(DSP.settings.undercut) or 2,
            DSP.auto.inv_status or 'не сканирован')))
        if DSP.auto.sell_running then
            if imgui.Button(DSP.utf8('СТОП'), imgui.ImVec2(140 * d(), 0)) then DSP.auto.stop_sell() end
        else
            if imgui.Button(DSP.utf8('СТАРТ'), imgui.ImVec2(140 * d(), 0)) then DSP.auto.start_sell() end
        end
        imgui.SameLine(0, 12 * d())
        if imgui.Button(DSP.utf8('СКАН ИНВЕНТАРЯ'), imgui.ImVec2(180 * d(), 0)) then DSP.auto.scan_inventory() end
        imgui.SameLine(0, 12 * d())
        if imgui.Button(DSP.utf8('ПЕРЕСЧИТАТЬ'), imgui.ImVec2(160 * d(), 0)) then DSP.presets.recalc('sell') end
        imgui.EndChild()
    end
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Последние события:'))
    if imgui.BeginChild('##dsp_auto_log', imgui.ImVec2(-1, 0), true) then
        for i = 1, math.min(8, #DSP.log) do
            local e = DSP.log[i]
            imgui.TextDisabled(e.t)
            imgui.SameLine(0, 8 * d())
            local c = e.kind == 'error' and DSP.theme.col('bad', 1)
                or e.kind == 'ok' and DSP.theme.col('good', 1) or DSP.theme.col('text', 1)
            imgui.TextColored(c, DSP.utf8(e.text))
        end
        imgui.EndChild()
    end
end

function DSP.ui.log_tab()
    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8('ЛОГИ'))
    imgui.SameLine(0, 30 * d())
    imgui.TextDisabled(DSP.utf8('Сделки: ' .. tostring(count_keys(DSP.settings.trades))))
    imgui.SameLine(0, 12 * d())
    imgui.TextDisabled(DSP.utf8('Лавки: ' .. tostring(count_keys(DSP.settings.stalls))))
    imgui.SameLine(0, 12 * d())
    imgui.TextDisabled(DSP.utf8('Ларцы: ' .. tostring(count_keys(DSP.settings.crates))))
    imgui.SameLine(0, 12 * d())
    imgui.TextDisabled(DSP.utf8('Чат: ' .. tostring(#(DSP.settings.chat_logs or {}))))
    imgui.SameLine(0, 20 * d())
    if imgui.SmallButton(DSP.utf8('очистить лог')) then DSP.log = {} end
    imgui.SameLine(0, 8 * d())
    if imgui.SmallButton(DSP.utf8('очистить сделки')) then DSP.logs.clear_trades() end
    imgui.SameLine(0, 8 * d())
    if imgui.SmallButton(DSP.utf8('очистить чат')) then DSP.settings.chat_logs = {}; DSP.db.save(true) end
    imgui.Separator()

    if DSP.ui.tab_detail == 'crates' then
        DSP.ui.crate_log()
    elseif DSP.ui.tab_detail == 'chat' then
        DSP.ui.chat_log()
    else
        DSP.ui.trade_log()
    end
    imgui.Spacing()
    local r1 = DSP.ui.tab_detail == 'trades'
    if r1 then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
    if imgui.Button(DSP.utf8('Сделки + лавки'), imgui.ImVec2(160 * d(), 0)) then DSP.ui.tab_detail = 'trades' end
    if r1 then imgui.PopStyleColor(1) end
    imgui.SameLine(0, 8 * d())
    local r2 = DSP.ui.tab_detail == 'crates'
    if r2 then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
    if imgui.Button(DSP.utf8('Ларцы'), imgui.ImVec2(120 * d(), 0)) then DSP.ui.tab_detail = 'crates' end
    if r2 then imgui.PopStyleColor(1) end
    imgui.SameLine(0, 8 * d())
    local r3 = DSP.ui.tab_detail == 'chat'
    if r3 then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
    if imgui.Button(DSP.utf8('Чат'), imgui.ImVec2(120 * d(), 0)) then DSP.ui.tab_detail = 'chat' end
    if r3 then imgui.PopStyleColor(1) end
end

function DSP.ui.trade_log()
    if not DSP.settings.trades or #DSP.settings.trades == 0 then
        imgui.TextDisabled(DSP.utf8('Сделки не записаны'))
    else
        if imgui.BeginChild('##dsp_trade_log', imgui.ImVec2(-1, 360 * d()), true) then
            local sorted = to_sorted_array(DSP.settings.trades)
            for i = #sorted, 1, -1 do
                local e = sorted[i]
                local t = os.date('%H:%M:%S', e.ts or 0)
                imgui.TextDisabled(t)
                imgui.SameLine(0, 8 * d())
                local sign = e.profit and e.profit >= 0 and DSP.theme.col('good', 1) or DSP.theme.col('bad', 1)
                local pstr = e.profit and ((e.profit > 0 and '+' or '') .. DSP.money(e.profit)) or '-'
                imgui.TextColored(sign, DSP.utf8(string.format('%s | %s -> %s | %s',
                    t, e.partner or '?', e.item_summary or 'N/A', pstr)))
                imgui.TextDisabled(DSP.utf8(string.format('  получено: %s | отдано: %s',
                    DSP.money(e.total_get or 0), DSP.money(e.total_give or 0))))
            end
            imgui.EndChild()
        end
    end

    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Стенды (сканирование лавок):'))
    if imgui.BeginChild('##dsp_stall_log', imgui.ImVec2(-1, 120 * d()), true) then
        local stalls = to_sorted_array(DSP.settings.stalls)
        if #stalls == 0 then
            imgui.TextDisabled(DSP.utf8('Стенды не сканированы'))
        else
            for i = #stalls, 1, -1 do
                local e = stalls[i]
                local t = os.date('%H:%M:%S', e.ts or 0)
                imgui.TextDisabled(string.format('%s  [#%s %s] %s',
                    t, tostring(e.shop_num or '?'), DSP.to_cp(e.owner or '?'), e.action or ''))
            end
        end
        imgui.EndChild()
    end
end

function DSP.ui.crate_log()
    if not DSP.settings.crates or #DSP.settings.crates == 0 then
        imgui.TextDisabled(DSP.utf8('Ларцы не открывались'))
    else
        if imgui.BeginChild('##dsp_crate_log', imgui.ImVec2(-1, 360 * d()), true) then
            local sorted = to_sorted_array(DSP.settings.crates)
            for i = #sorted, 1, -1 do
                local e = sorted[i]
                local t = os.date('%H:%M:%S', e.ts or 0)
                imgui.TextDisabled(t)
                imgui.SameLine(0, 8 * d())
                imgui.TextColored(DSP.theme.col('warn', 1), DSP.utf8(e.item or '?'))
                imgui.SameLine(0, 8 * d())
                imgui.TextDisabled(DSP.utf8('x' .. tostring(e.qty or 1)))
                imgui.SameLine(0, 8 * d())
                if e.ench and e.ench > 0 then
                    imgui.TextDisabled(DSP.utf8('+' .. tostring(e.ench)))
                end
            end
            imgui.EndChild()
        end
    end
end

function DSP.ui.chat_log()
    if not DSP.settings.chat_logs or #DSP.settings.chat_logs == 0 then
        imgui.TextDisabled(DSP.utf8('Чат-сообщения не записаны'))
        return
    end
    if imgui.BeginChild('##dsp_chat_log', imgui.ImVec2(-1, 0), true) then
        for i = #DSP.settings.chat_logs, 1, -1 do
            local e = DSP.settings.chat_logs[i]
            local t = os.date('%H:%M:%S', e.ts or 0)
            imgui.TextDisabled(t)
            imgui.SameLine(0, 8 * d())
            local drop = DSP.logs and DSP.logs.parse_chat_drop and DSP.logs.parse_chat_drop(e.text)
            local clr = drop and DSP.theme.col('warn', 1) or DSP.theme.col('text', 1)
            imgui.TextColored(clr, DSP.utf8(e.text or ''))
        end
        imgui.EndChild()
    end
end

function DSP.ui.settings_tab()
    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8('НАСТРОЙКИ'))
    imgui.Separator()

    -- v1.2 Section 1: theme + opacity slider
    imgui.TextDisabled(DSP.utf8('Тема оформления:'))
    local theme_order = { 'dark_amber', 'amoled', 'cyberpunk', 'purple', 'emerald' }
    for _, id in ipairs(theme_order) do
        local e = DSP.theme.list[id]
        if e then
            local act = DSP.theme.current == id
            if act then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
            if imgui.Button(DSP.utf8(e.name), imgui.ImVec2(150 * d(), 0)) then
                DSP.theme.set(id)
            end
            if act then imgui.PopStyleColor(1) end
            imgui.SameLine(0, 6 * d())
        end
    end
    imgui.NewLine()
    imgui.TextDisabled(DSP.utf8(string.format('Прозрачность окна: %.2f', DSP.theme.opacity)))
    imgui.SameLine(0, 12 * d())
    -- v1.2 hotfix: imgui.new.float may not exist in all mimgui builds.
    -- Fall back to imgui.new.int (scaled to 0-1000) if float is unavailable.
    local op_buf
    local ok_f, f = pcall(function() return imgui.new.float(DSP.theme.opacity) end)
    if ok_f and f then
        op_buf = f
    else
        op_buf = imgui.new.int(math.floor(DSP.theme.opacity * 1000))
    end
    pcall(imgui.PushStyleColor, imgui.Col.SliderGrab, DSP.theme.col('accent', 1))
    local slider_ok, slider_changed
    if op_buf then
        if ok_f then
            -- Float mode: standard SliderFloat.
            slider_ok, slider_changed = pcall(imgui.SliderFloat, '##dsp_opacity', op_buf, 0.65, 1.00, DSP.utf8('%.2f'))
            if slider_changed and slider_ok then
                DSP.theme.set_opacity(op_buf[0])
            end
        else
            -- Int mode (fallback): use SliderInt with 650-1000 range, divide by 1000.
            slider_ok, slider_changed = pcall(imgui.SliderInt, '##dsp_opacity', op_buf, 650, 1000, DSP.utf8('%.0f'))
            if slider_changed and slider_ok then
                DSP.theme.set_opacity((op_buf[0] or 650) / 1000)
            end
        end
    end
    pcall(imgui.PopStyleColor, 1)
    imgui.Separator()

    -- v1.2 Stage 2 Section 1.5: CR tax selector (basis points)
    imgui.TextDisabled(DSP.utf8('Комиссия ЦР:'))
    local tax_options = {
        { bp = 100, label = '1% (ADD VIP)' },
        { bp = 200, label = '2% (Titan/Premium)' },
        { bp = 300, label = '3% (без VIP)' },
        { bp = 400, label = '4% (без VIP)' },
    }
    for _, t in ipairs(tax_options) do
        local act = (tonumber(DSP.settings.tax_bp) or 200) == t.bp
        if act then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
        if imgui.Button(DSP.utf8(t.label), imgui.ImVec2(180 * d(), 0)) then
            DSP.settings.tax_bp = t.bp
            DSP.save_settings()
            DSP.notify('Комиссия ЦР: ' .. t.label)
        end
        if act then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()
    imgui.Separator()

    -- v1.2 Section 2: server selection
    DSP.ui.server_buttons()
    imgui.Spacing()

    -- v1.2 hotfix: CR marker scan (dialog 15073) button + progress bar.
    imgui.TextDisabled(DSP.utf8('Скан метки ЦР (диалог 15073):'))
    imgui.SameLine(0, 8 * d())
    if DSP.market.cr_scan_state.active then
        if imgui.Button(DSP.utf8('[ СТОП ]'), imgui.ImVec2(110 * d(), 0)) then
            DSP.market.cr_scan_state.active = false
            DSP.market.cr_scan_state.status = 'остановлено'
            DSP.add_log('Скан ЦР: остановлен вручную')
        end
    else
        if imgui.Button(DSP.utf8('[ SCAN CR ]'), imgui.ImVec2(160 * d(), 0)) then
            DSP.market.scan_cr_marker()
        end
    end
    imgui.SameLine(0, 12 * d())
    imgui.TextDisabled(DSP.utf8(DSP.market.cr_scan_state.status or 'не сканирован'))
    if DSP.market.cr_scan_state.active then
        -- ASCII-safe text-based progress bar (no imgui.ProgressBar needed).
        local s = DSP.market.cr_scan_state
        imgui.Spacing()
        local pct = math.min(100, math.floor(s.page * 100 / math.max(1, s.total)))
        if s.total == 0 then pct = math.min(50, s.page * 8) end
        local bar_len = 30
        local filled = math.floor(bar_len * pct / 100)
        local bar = string.rep('=', filled) .. '>' .. string.rep(' ', bar_len - filled - 1)
        imgui.TextColored(DSP.theme.col('accent', 1),
            DSP.utf8(string.format('[%s] %d%% стр.%d, тов. %d',
                bar, pct, s.page, #s.items)))
    end
    imgui.Separator()

    -- v1.2 Section 3: sort + margin + undercut
    imgui.TextDisabled(DSP.utf8('Сортировка рынка:'))
    local sorts = { 'выгода', 'дешёвые', 'дорогая скупка', 'процент', 'офферы' }
    for i, name in ipairs(sorts) do
        local act = (tonumber(DSP.settings.sort) or 1) == i
        if act then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
        if imgui.Button(DSP.utf8(name), imgui.ImVec2(150 * d(), 0)) then
            DSP.settings.sort = i
            DSP.save_settings()
            DSP.market.state.filter_version = -1
            DSP.ui.page = 1
        end
        if act then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8(string.format('Маржа скупки: %d%%', tonumber(DSP.settings.margin) or 10)))
    if imgui.SmallButton('-5##dsp_margm') then DSP.settings.margin = math.max(0, (tonumber(DSP.settings.margin) or 10) - 5); DSP.save_settings() end
    imgui.SameLine(0, 4 * d())
    if imgui.SmallButton('+5##dsp_margp') then DSP.settings.margin = math.min(80, (tonumber(DSP.settings.margin) or 10) + 5); DSP.save_settings() end
    imgui.SameLine(0, 12 * d())
    imgui.TextDisabled(DSP.utf8(string.format('Undercut продажи: %d%%', tonumber(DSP.settings.undercut) or 2)))
    if imgui.SmallButton('-1##dsp_ucm') then DSP.settings.undercut = math.max(0, (tonumber(DSP.settings.undercut) or 2) - 1); DSP.save_settings() end
    imgui.SameLine(0, 4 * d())
    if imgui.SmallButton('+1##dsp_ucp') then DSP.settings.undercut = math.min(50, (tonumber(DSP.settings.undercut) or 2) + 1); DSP.save_settings() end
    imgui.Spacing()
    imgui.Spacing()

    -- v1.2 Section 4: overlay toggles
    imgui.TextDisabled(DSP.utf8('Оверлей при трейде/лавке:'))
    checkbox(DSP.utf8('оценка трейда'), 'overlay_trade')
    imgui.SameLine(0, 12 * d())
    checkbox(DSP.utf8('скан лавки'), 'overlay_shop')
    imgui.SameLine(0, 12 * d())
    checkbox(DSP.utf8('поверх окон'), 'overlay_top')
    imgui.Spacing()

    -- v1.2 Section 5: DPI scale
    imgui.TextDisabled(DSP.utf8('Масштаб интерфейса:'))
    for _, v in ipairs({ 1.0, 1.25, 1.5 }) do
        local act = math.abs((DSP.ui.d or 1.25) - v) < 0.01
        if act then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
        if imgui.Button(tostring(v), imgui.ImVec2(80 * d(), 0)) then
            DSP.ui.d = v
            DSP.settings.dpi = v
            DSP.save_settings()
        end
        if act then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()
    imgui.Spacing()

    -- v1.2 Section 6: stats mode
    imgui.TextDisabled(DSP.utf8('Статистика по умолчанию:'))
    local modes = {
        { key = 'hour', label = 'Час' },
        { key = 'day', label = 'День' },
        { key = 'week', label = 'Неделя' },
        { key = 'month', label = 'Месяц' },
        { key = 'all', label = 'Все время' },
    }
    for _, m in ipairs(modes) do
        local act = DSP.settings.stats_mode == m.key
        if act then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
        if imgui.Button(DSP.utf8(m.label), imgui.ImVec2(100 * d(), 0)) then
            DSP.settings.stats_mode = m.key
            DSP.save_settings()
        end
        if act then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()
    imgui.Spacing()

    -- v1.2 Section 7: Telegram
    imgui.TextDisabled(DSP.utf8('Telegram-уведомления:'))
    if imgui.Checkbox(DSP.utf8('включить'), DSP.ui.chk.tg_notify) then
        DSP.settings.tg_notify = DSP.ui.chk.tg_notify[0]
        DSP.save_settings()
    end
    imgui.SameLine(0, 14 * d())
    local payday_chk = imgui.new.bool(DSP.settings.tg_payday_enabled and true or false)
    if imgui.Checkbox(DSP.utf8('PayDay сводка (XX:00)'), payday_chk) then
        DSP.settings.tg_payday_enabled = payday_chk[0]
        DSP.save_settings()
    end
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Bot Token:'))
    imgui.PushItemWidth(300 * d())
    local changed = imgui.InputText('##dsp_tg_token', DSP.ui.tg_token_buf, 256)
    imgui.PopItemWidth()
    if changed then
        DSP.settings.tg_bot_token = ffi.string(DSP.ui.tg_token_buf)
        DSP.save_settings()
    end
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Chat ID:'))
    imgui.PushItemWidth(160 * d())
    local changed2 = imgui.InputText('##dsp_tg_chat', DSP.ui.tg_chat_buf, 64)
    imgui.PopItemWidth()
    if changed2 then
        DSP.settings.tg_chat_id = ffi.string(DSP.ui.tg_chat_buf)
        DSP.save_settings()
    end
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Логи чата и выпадов:'))
    if imgui.Checkbox(DSP.utf8('записывать выпады'), DSP.ui.chk.log_drops) then
        DSP.settings.log_chat_drops = DSP.ui.chk.log_drops[0]
        DSP.save_settings()
    end
    if imgui.Button(DSP.utf8('ЭКСПОРТ В TELEGRAM'), imgui.ImVec2(200 * d(), 0)) then
        if DSP.logs and DSP.logs.export_logs then DSP.logs.export_logs() end
    end
    imgui.SameLine(0, 12 * d())
    if imgui.Button(DSP.utf8('СОХРАНИТЬ'), imgui.ImVec2(160 * d(), 0)) then
        DSP.save_settings()
        DSP.save_ui_state()
        DSP.notify('Настройки сохранены')
    end
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Данные: ' .. DSP.dir))
    imgui.TextDisabled(DSP.utf8('API: ' .. DSP.market.api))
end

function DSP.ui.calculator_tab()
    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8('КАЛЬКУЛЯТОР'))
    imgui.SameLine(0, 14 * d())
    imgui.TextDisabled(DSP.utf8('Арбитражный калькулятор'))
    imgui.Separator()

    local avail = imgui.GetContentRegionAvail()
    local w = math.min(avail.x, 520 * d())

    if imgui.BeginChild('##dsp_calc_card', imgui.ImVec2(-1, 260 * d()), true) then
        imgui.PushItemWidth(w * 0.55)
        imgui.TextDisabled(DSP.utf8('Цена покупки:'))
        imgui.SameLine(0, 8 * d())
        imgui.InputInt(DSP.utf8('buy##price'), DSP.ui.calc_buy_ref, 1000, 10000)

        imgui.Spacing()
        imgui.TextDisabled(DSP.utf8('Цена продажи:'))
        imgui.SameLine(0, 8 * d())
        imgui.InputInt(DSP.utf8('sell##price'), DSP.ui.calc_sell_ref, 1000, 10000)

        imgui.Spacing()
        imgui.TextDisabled(DSP.utf8('Кол-во:'))
        imgui.SameLine(0, 8 * d())
        imgui.InputInt(DSP.utf8('qty##calc'), DSP.ui.calc_qty_ref, 1, 10)

        imgui.PopItemWidth()
    end
    imgui.EndChild()

    imgui.Spacing()
    local buy_p = DSP.ui.calc_buy_ref[0]
    local sell_p = DSP.ui.calc_sell_ref[0]
    local qty = DSP.ui.calc_qty_ref[0]
    local profit = (sell_p - buy_p) * qty
    local pct = buy_p > 0 and ((sell_p - buy_p) / buy_p * 100) or 0

    if imgui.BeginChild('##dsp_calc_result', imgui.ImVec2(-1, 140 * d()), true) then
        imgui.TextDisabled(DSP.utf8('Сумма вложений:'))
        imgui.SameLine(0, 20 * d())
        imgui.Text(DSP.money(buy_p * qty))

        imgui.Spacing()
        imgui.TextDisabled(DSP.utf8('Ожидаемая выручка:'))
        imgui.SameLine(0, 20 * d())
        imgui.Text(DSP.money(sell_p * qty))

        imgui.Spacing()
        local pc = profit >= 0 and DSP.theme.col('good', 1) or DSP.theme.col('bad', 1)
        imgui.TextDisabled(DSP.utf8('Прибыль:'))
        imgui.SameLine(0, 30 * d())
        imgui.TextColored(pc, DSP.utf8((profit >= 0 and '+' or '') .. DSP.money(profit)))
        imgui.SameLine(0, 10 * d())
        imgui.TextColored(pc, string.format('%+.1f%%', pct))

        imgui.Spacing()
        imgui.TextDisabled(DSP.utf8('На штуку:'))
        imgui.SameLine(0, 24 * d())
        imgui.TextColored(pc, DSP.utf8((sell_p - buy_p >= 0 and '+' or '')
            .. DSP.money(sell_p - buy_p)))

        local bw = 160 * d()
        if imgui.Button(DSP.utf8('ОЧИСТИТЬ'), imgui.ImVec2(bw, 0)) then
            DSP.ui.calc_buy_ref[0] = 1000
            DSP.ui.calc_sell_ref[0] = 1000
            DSP.ui.calc_qty_ref[0] = 1
        end
    end
    imgui.EndChild()
end

function DSP.ui.statistics_tab()
    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8('СТАТИСТИКА'))
    imgui.SameLine(0, 14 * d())
    imgui.TextDisabled(DSP.utf8('Прибыль по периодам'))
    imgui.Separator()

    local modes = {
        { key = 'hour', label = 'Час' },
        { key = 'day', label = 'День' },
        { key = 'week', label = 'Неделя' },
        { key = 'month', label = 'Месяц' },
        { key = 'all', label = 'Все время' },
    }
    for _, m in ipairs(modes) do
        local active = DSP.ui.stat_mode == m.key
        if active then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
        if imgui.Button(DSP.utf8(m.label), imgui.ImVec2(90 * d(), 0)) then
            DSP.ui.stat_mode = m.key
        end
        if active then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()

    local summary = DSP.logs.profit_summary(DSP.ui.stat_mode)
    local avail = imgui.GetContentRegionAvail()
    local stat_h = avail.y - 30 * d()

    if imgui.BeginChild('##dsp_stat_summary', imgui.ImVec2(-1, 90 * d()), true) then
        imgui.TextDisabled(DSP.utf8(string.format('Сделок: %d', summary.count)))
        imgui.SameLine(0, 16 * d())
        imgui.Text(DSP.money(summary.total_get))
        imgui.SameLine(0, 4 * d())
        imgui.TextDisabled(DSP.utf8('получено'))
        imgui.SameLine(0, 16 * d())
        imgui.Text(DSP.money(summary.total_give))
        imgui.SameLine(0, 4 * d())
        imgui.TextDisabled(DSP.utf8('отдано'))
        imgui.Spacing()
        local pc = summary.profit >= 0 and DSP.theme.col('good', 1) or DSP.theme.col('bad', 1)
        imgui.TextColored(pc, DSP.utf8('Прибыль: ' .. (summary.profit >= 0 and '+' or '') .. DSP.money(summary.profit)))
        imgui.SameLine(0, 16 * d())
        imgui.TextDisabled(string.format('ROI: %+.1f%%', summary.roi))
        imgui.SameLine(0, 16 * d())
        imgui.TextDisabled(DSP.utf8('Средняя: ' .. DSP.money(summary.avg_profit)))
    end
    imgui.EndChild()

    imgui.Spacing()
    if imgui.BeginChild('##dsp_stat_buckets', imgui.ImVec2(-1, stat_h - 100 * d()), true) then
        if #summary.sorted_keys == 0 then
            imgui.TextDisabled(DSP.utf8('Нет данных. Совершите сделки чтобы увидеть статистику.'))
        end
        for _, k in ipairs(summary.sorted_keys) do
            local b = summary.buckets[k]
            if b then
                local pc = b.profit >= 0 and DSP.theme.col('good', 1) or DSP.theme.col('bad', 1)
                imgui.Text(DSP.utf8(k))
                imgui.SameLine(0, 20 * d())
                imgui.TextColored(pc, DSP.utf8((b.profit >= 0 and '+' or '') .. DSP.money(b.profit)))
                imgui.SameLine(0, 10 * d())
                imgui.TextDisabled(string.format('%d сдел.', b.count))
            end
            imgui.Spacing()
        end
    end
    imgui.EndChild()
end

-- =========================================================================
-- v1.2 Stage 2: ЛАВКИ ЦР screen.
-- Lists all shops as cards with [Отметить лавку] + [Скопировать скупку] buttons.
-- =========================================================================
function DSP.ui.lavki_tab()
    local dpi = d()
    local shops = DSP.market.shops_list()
    DSP.ui.header()

    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8('ЛАВКИ ЦР'))
    imgui.SameLine(0, 14 * dpi)
    imgui.TextDisabled(DSP.utf8(string.format('Всего лавок: %d', #shops)))
    imgui.SameLine(0, 14 * dpi)
    if imgui.Button(DSP.utf8('ОБНОВИТЬ БАЗУ'), imgui.ImVec2(160 * dpi, 0)) then
        DSP.market.pull(DSP.market.state.sid)
    end
    imgui.Separator()

    local avail = imgui.GetContentRegionAvail()
    local list_h = avail.y - 80 * dpi
    if list_h < 100 * dpi then list_h = 100 * dpi end

    local per = math.max(3, tonumber(DSP.settings.per_page) or 20)
    -- pager in this screen
    local from, to = DSP.screens.pager(#shops, per, 'lavki')

    if imgui.BeginChild('##dsp_lavki_list', imgui.ImVec2(-1, list_h), true) then
        if #shops == 0 then
            imgui.TextDisabled(DSP.utf8('Нет данных. Нажмите ОБНОВИТЬ БАЗУ.'))
        end
        for i = from, to do
            local s = shops[i]
            if s then
                local fresh_text, fresh_key = DSP.market.offer_freshness(s.ts)
                local expanded = DSP.ui.lavki_expanded[s.num] == true
                imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.18))
                if imgui.Button(DSP.utf8(string.format('[ %s ]', expanded and '-' or '+')),
                        imgui.ImVec2(34 * dpi, 32 * dpi)) then
                    DSP.ui.lavki_expanded[s.num] = not expanded
                end
                imgui.PopStyleColor(1)
                imgui.SameLine(0, 8 * dpi)
                imgui.TextColored(DSP.theme.col('accent', 1),
                    DSP.utf8(string.format('Лавка #%s  %s', tostring(s.num), tostring(s.owner))))
                imgui.SameLine(0, 14 * dpi)
                imgui.TextColored(DSP.theme.col(fresh_key, 1), DSP.utf8(fresh_text))
                imgui.SameLine(0, 14 * dpi)
                imgui.TextDisabled(DSP.utf8(string.format('продажа: %d  скупка: %d',
                    s.sell_count, s.buy_count)))
                imgui.SameLine(0, 12 * dpi)
                if imgui.Button(DSP.utf8('[ Отметить лавку ]##mk' .. tostring(s.num)),
                        imgui.ImVec2(170 * dpi, 32 * dpi)) then
                    DSP.market.mark_shop(s.num)
                end
                imgui.SameLine(0, 8 * dpi)
                if s.buy_count > 0 then
                    if imgui.Button(DSP.utf8('[ Скопировать скупку ]##cp' .. tostring(s.num)),
                            imgui.ImVec2(190 * dpi, 32 * dpi)) then
                        local n, err = DSP.market.copy_shop_skupka(s.num, nil, 1)
                        if n then
                            DSP.notify(string.format('Скупка: +%d поз. из лавки #%s', n, tostring(s.num)))
                        else
                            DSP.notify('Скупка: ' .. tostring(err))
                        end
                    end
                end
                if expanded then
                    imgui.Spacing()
                    if s.sell_count > 0 then
                        imgui.TextDisabled(DSP.utf8(string.format('ПРОДАЁТ (лавка -> игрок): %d поз.', s.sell_count)))
                        local max_show = math.min(8, #s.sell_offers)
                        for j = 1, max_show do
                            local e = s.sell_offers[j]
                            local o = e.offer
                            imgui.TextColored(DSP.theme.col('warn', 1),
                                DSP.utf8('  ' .. DSP.money(o.price)))
                            imgui.SameLine(0, 8 * dpi)
                            imgui.TextDisabled(DSP.utf8(string.format('x%d  %s',
                                o.qty or 0, trunc(e.row.display, 32))))
                        end
                    end
                    if s.buy_count > 0 then
                        imgui.Spacing()
                        imgui.TextDisabled(DSP.utf8(string.format('СКУПАЕТ (лавка <- игрок): %d поз.', s.buy_count)))
                        local max_show = math.min(8, #s.buy_offers)
                        for j = 1, max_show do
                            local e = s.buy_offers[j]
                            local o = e.offer
                            imgui.TextColored(DSP.theme.col('good', 1),
                                DSP.utf8('  ' .. DSP.money(o.price)))
                            imgui.SameLine(0, 8 * dpi)
                            imgui.TextDisabled(DSP.utf8(string.format('x%d  %s',
                                o.qty or 0, trunc(e.row.display, 32))))
                        end
                    end
                end
                imgui.Separator()
            end
        end
        imgui.EndChild()
    end
end

-- =========================================================================
-- v1.2 Stage 2: АРБИТРАЖ screen.
-- Table of cross-shop arbitrage opportunities with budget / profit / ROI
-- filters, freshness labels, integer CR tax.
-- =========================================================================
function DSP.ui.arbitrage_tab()
    local dpi = d()
    local f = DSP.settings.arb_filters or { budget = 0, min_profit = 0, min_roi = 0, sort = 1 }
    DSP.ui.header()

    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8('АРБИТРАЖ'))
    imgui.SameLine(0, 14 * dpi)
    local tax_bp = tonumber(DSP.settings.tax_bp) or 200
    imgui.TextDisabled(DSP.utf8(string.format('Комиссия ЦР: %d%%', math.floor(tax_bp / 100))))
    imgui.Separator()

    -- Filter row 1: budget input + [С рук] + sort selector
    imgui.TextDisabled(DSP.utf8('Бюджет на руках:'))
    imgui.SameLine(0, 8 * dpi)
    imgui.SetNextItemWidth(160 * dpi)
    if imgui.InputInt('##arb_budget', DSP.ui.arb_budget_ref, 100000, 1000000) then
        f.budget = math.max(0, DSP.ui.arb_budget_ref[0])
        DSP.settings.arb_filters.budget = f.budget
            if DSP.market and DSP.market.invalidate_arbitrage then DSP.market.invalidate_arbitrage() end
        DSP.save_settings()
        DSP.screens.set_page('arbitrage', 1)
    end
    imgui.SameLine(0, 8 * dpi)
    if imgui.Button(DSP.utf8('[ С рук ]'), imgui.ImVec2(110 * dpi, 32 * dpi)) then
        -- Apply budget filter; the user just confirmed the input.
        f.budget = math.max(0, DSP.ui.arb_budget_ref[0])
        DSP.settings.arb_filters.budget = f.budget
            if DSP.market and DSP.market.invalidate_arbitrage then DSP.market.invalidate_arbitrage() end
        DSP.save_settings()
        DSP.screens.set_page('arbitrage', 1)
    end
    imgui.SameLine(0, 8 * dpi)
    if f.budget > 0 then
        if imgui.Button(DSP.utf8('[ Сброс ]'), imgui.ImVec2(110 * dpi, 32 * dpi)) then
            f.budget = 0
            DSP.settings.arb_filters.budget = 0
            if DSP.market and DSP.market.invalidate_arbitrage then DSP.market.invalidate_arbitrage() end
            DSP.ui.arb_budget_ref[0] = 0
            DSP.save_settings()
            DSP.screens.set_page('arbitrage', 1)
        end
    end
    imgui.SameLine(0, 14 * dpi)
    imgui.TextDisabled(DSP.utf8('Сортировка:'))
    imgui.SameLine(0, 6 * dpi)
    local sorts = {
        { id = 1, label = 'По партии' },
        { id = 2, label = 'За 1 шт.' },
        { id = 3, label = 'По ROI' },
    }
    for _, s in ipairs(sorts) do
        local act = (tonumber(f.sort) or 1) == s.id
        if act then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
        if imgui.Button(DSP.utf8(s.label), imgui.ImVec2(110 * dpi, 0)) then
            f.sort = s.id
            DSP.settings.arb_filters.sort = s.id
            if DSP.market and DSP.market.invalidate_arbitrage then DSP.market.invalidate_arbitrage() end
            DSP.save_settings()
        end
        if act then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 4 * dpi)
    end
    imgui.NewLine()

    -- Filter row 2: profit + ROI quick presets
    imgui.TextDisabled(DSP.utf8('Мин. прибыль:'))
    imgui.SameLine(0, 6 * dpi)
    local profit_presets = {
        { label = 'Все',     val = 0 },
        { label = '500к+',   val = 500000 },
        { label = '1кк+',    val = 1000000 },
        { label = '5кк+',    val = 5000000 },
        { label = '10кк+',  val = 10000000 },
    }
    for _, p in ipairs(profit_presets) do
        local act = (tonumber(f.min_profit) or 0) == p.val
        if act then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
        if imgui.Button(DSP.utf8(p.label), imgui.ImVec2(70 * dpi, 0)) then
            f.min_profit = p.val
            DSP.settings.arb_filters.min_profit = p.val
            if DSP.market and DSP.market.invalidate_arbitrage then DSP.market.invalidate_arbitrage() end
            DSP.save_settings()
            DSP.screens.set_page('arbitrage', 1)
        end
        if act then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 4 * dpi)
    end
    imgui.NewLine()
    imgui.SameLine(0, 0)
    imgui.TextDisabled(DSP.utf8('Мин. ROI:'))
    imgui.SameLine(0, 6 * dpi)
    local roi_presets = {
        { label = 'Все',  val = 0 },
        { label = '5%+',   val = 5 },
        { label = '10%+',  val = 10 },
        { label = '25%+',  val = 25 },
    }
    for _, p in ipairs(roi_presets) do
        local act = (tonumber(f.min_roi) or 0) == p.val
        if act then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
        if imgui.Button(DSP.utf8(p.label), imgui.ImVec2(70 * dpi, 0)) then
            f.min_roi = p.val
            DSP.settings.arb_filters.min_roi = p.val
            if DSP.market and DSP.market.invalidate_arbitrage then DSP.market.invalidate_arbitrage() end
            DSP.save_settings()
            DSP.screens.set_page('arbitrage', 1)
        end
        if act then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 4 * dpi)
    end
    imgui.NewLine()
    imgui.Separator()

    local rows = DSP.market.arbitrage_filtered()
    local total_cost, total_profit, total_qty = 0, 0, 0
    for _, e in ipairs(rows) do
        total_cost = total_cost + (e.total_cost or 0)
        total_profit = total_profit + (e.net_profit or 0)
        total_qty = total_qty + (e.tradable_qty or 0)
    end
    imgui.TextDisabled(DSP.utf8(string.format(
        'План: %d связок | %d шт. | затраты %s | прибыль +%s',
        #rows, total_qty, DSP.money(total_cost), DSP.money(total_profit))))
    if (tonumber(f.budget) or 0) > 0 then
        imgui.TextDisabled(DSP.utf8('Общий остаток бюджета: '..
            DSP.money(math.max(0, f.budget - total_cost))))
    end
    imgui.TextColored(DSP.theme.col('warn', 1), DSP.utf8(
        'Остатки не дублируются между связками. Перед покупкой обновите рынок и проверьте лавки.'))
    if DSP.market.state.status == 'cache' or DSP.market.state.status == 'error' then
        imgui.TextColored(DSP.theme.col('warn', 1), DSP.utf8(
            'Внимание: расчёт выполнен по локальному снимку рынка.'))
    end
    imgui.Separator()

    local avail = imgui.GetContentRegionAvail()
    local table_h = math.max(200 * dpi, avail.y - 20 * dpi)
    if imgui.BeginChild('##dsp_arb_table', imgui.ImVec2(-1, table_h), true) then
        -- Six readable columns, with quantity and age under each price.
        imgui.Columns(6, '##dsp_arb_hdr', false)
        local cw = avail.x
        local widths = {cw*.24,cw*.17,cw*.17,cw*.12,cw*.17,cw*.13}
        for i = 0, 5 do imgui.SetColumnWidth(i, widths[i+1]) end
        for _, title in ipairs({'ТОВАР', 'КУПИТЬ У', 'ПРОДАТЬ В', 'СДЕЛКА', 'ЧИСТАЯ ПРИБЫЛЬ', 'МЕТКИ'}) do
            imgui.TextDisabled(DSP.utf8(title)); imgui.NextColumn()
        end
        imgui.Separator()
        imgui.Columns(1)
        local per = math.max(5, tonumber(DSP.settings.per_page) or 20)
        local first, last = DSP.screens.pager(#rows, per, 'arbitrage')
        imgui.Columns(6, '##dsp_arb_rows', false)
        for i = 0, 5 do imgui.SetColumnWidth(i, widths[i+1]) end
        for i = first, last do
            local e = rows[i]
            if e then
                imgui.Text(DSP.utf8(trunc(e.name, 30)))
                imgui.TextDisabled(DSP.utf8('Сервер '..tostring(DSP.market.state.sid)))
                imgui.NextColumn()
                imgui.TextColored(DSP.theme.col('warn', 1), DSP.money(e.p_buy))
                imgui.TextDisabled(DSP.utf8('Лавка #'..tostring(e.sell_offer.shop)..
                    ' | '..tostring(e.qty_seller or e.sell_offer.qty)..' шт.'))
                imgui.NextColumn()
                imgui.TextColored(DSP.theme.col('good', 1), DSP.money(e.p_sell))
                imgui.TextDisabled(DSP.utf8('Лавка #'..tostring(e.buy_offer.shop)..
                    ' | '..tostring(e.qty_buyer or e.buy_offer.qty)..' шт.'))
                imgui.NextColumn()
                imgui.Text(DSP.utf8(tostring(e.tradable_qty)..' шт.'))
                imgui.TextDisabled(DSP.money(e.total_cost))
                imgui.NextColumn()
                imgui.TextColored(DSP.theme.col('good', 1), DSP.utf8('+'..DSP.money(e.net_profit)))
                imgui.TextDisabled(DSP.utf8(string.format('ROI %.1f%%', e.roi)))
                imgui.NextColumn()
                if imgui.SmallButton(DSP.utf8('Купить##arb_a'..i)) then
                    DSP.market.mark_shop(e.sell_offer.shop)
                end
                if imgui.SmallButton(DSP.utf8('Сдать##arb_b'..i)) then
                    DSP.market.mark_shop(e.buy_offer.shop)
                end
                imgui.NextColumn()
                imgui.Separator()
            end
        end
        imgui.Columns(1)
        if #rows == 0 then
            imgui.Spacing()
            imgui.TextDisabled(DSP.utf8('Нет подходящих сделок. Измените фильтры или обновите рынок.'))
        end
        imgui.EndChild()
    end
end

-- =========================================================================
-- v1.2 Stage 2: ПОИСК screen (Item Finder).
-- Single search input -> for each matching row, show ПРОДАЖА + СКУПКА blocks
-- with [Отметить лавку] buttons per offer.
-- =========================================================================
function DSP.ui.finder_tab()
    local dpi = d()
    DSP.ui.header()

    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8('ПОИСК ТОВАРА'))
    imgui.SameLine(0, 14 * dpi)
    imgui.TextDisabled(DSP.utf8('Поиск по всем лавкам ЦР'))
    imgui.Separator()

    imgui.SetNextItemWidth(360 * dpi)
    if imgui.InputTextWithHint('##dsp_finder', DSP.utf8('Введите название (Дрова, Лён, Камень, Ларец)...'),
            DSP.ui.finder_search_buf, 128) then
        DSP.ui.finder_query = ffi.string(DSP.ui.finder_search_buf)
        DSP.screens.set_page('search', 1)
    end
    imgui.SameLine(0, 12 * dpi)
    if imgui.Button(DSP.utf8('Очистить'), imgui.ImVec2(110 * dpi, 0)) then
        DSP.ui.finder_query = ''
        -- Wipe the C buffer
        for i = 0, 127 do DSP.ui.finder_search_buf[i] = 0 end
    end

    local matches = DSP.market.find_item(DSP.ui.finder_query)
    imgui.SameLine(0, 12 * dpi)
    imgui.TextDisabled(DSP.utf8(string.format('Найдено: %d', #matches)))
    imgui.Separator()

    local avail = imgui.GetContentRegionAvail()
    local list_h = avail.y - 50 * dpi
    if list_h < 100 * dpi then list_h = 100 * dpi end

    local per = math.max(3, tonumber(DSP.settings.per_page) or 20)
    local from, to = DSP.screens.pager(#matches, per, 'search')

    if imgui.BeginChild('##dsp_finder_list', imgui.ImVec2(-1, list_h), true) then
        if #matches == 0 then
            imgui.TextDisabled(DSP.utf8('Введите название товара в строку поиска.'))
        end
        -- v1.2 hotfix: helper to format qty with thousand dots (CP1251 safe).
        local function fmt_qty(n)
            n = math.floor(tonumber(n) or 0)
            local s = tostring(n)
            s = s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
            return s
        end
        for i = from, to do
            local row = matches[i]
            if row then
                -- Header per row: shows counts of sellers + buyers.
                imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8(row.display))
                imgui.SameLine(0, 12 * dpi)
                imgui.TextDisabled(DSP.utf8(string.format('продаёт: %d лавок  |  скупает: %d лавок',
                    row.sell.count, row.buy.count)))
                if row.sell.count > 0 and row.buy.count > 0 then
                    local profit = (row.buy.best or 0) - (row.sell.best or 0)
                    local pc = profit > 0 and DSP.theme.col('good', 1) or DSP.theme.col('bad', 1)
                    imgui.SameLine(0, 12 * dpi)
                    imgui.TextColored(pc, DSP.utf8('спред: ' .. DSP.money(profit)))
                end
                imgui.Separator()

                -- ПРОДАЖА block (лавка продаёт игроку): sort asc cheapest first
                -- Format per ТЗ: [Лавка #14] Vanya_Pupkin - 2.500 шт. по $3.500 [freshness] [Отметить]
                if row.sell.count > 0 then
                    imgui.TextColored(DSP.theme.col('warn', 1), DSP.utf8('ПРОДАЖА (где купить себе)'))
                    local max_show = math.min(10, #row.sell.offers)
                    for j = 1, max_show do
                        local o = row.sell.offers[j]
                        local fresh_text, fresh_key = DSP.market.offer_freshness(o.ts)
                        imgui.TextColored(DSP.theme.col('accent', 1),
                            DSP.utf8(string.format('[Лавка #%s] %s', tostring(o.shop),
                                trunc(o.owner or '?', 18))))
                        imgui.SameLine(0, 6 * dpi)
                        imgui.Text(DSP.utf8(string.format('- %s шт. по ', fmt_qty(o.qty or 0))))
                        imgui.SameLine(0, 4 * dpi)
                        imgui.TextColored(DSP.theme.col('warn', 1), DSP.money(o.price))
                        imgui.SameLine(0, 8 * dpi)
                        imgui.TextColored(DSP.theme.col(fresh_key, 1), DSP.utf8('[' .. fresh_text .. ']'))
                        imgui.SameLine(0, 8 * dpi)
                        if imgui.SmallButton(DSP.utf8('[ Отметить ]##fs' .. tostring(i) .. '_' .. tostring(j))) then
                            DSP.market.mark_shop(o.shop)
                        end
                    end
                else
                    imgui.TextDisabled(DSP.utf8('  Нет продавцов'))
                end

                imgui.Spacing()
                -- СКУПКА block (лавка скупает у игрока): sort desc highest first
                -- Format per ТЗ: [Лавка #5] Sasha_Grey - нужно 10.000 шт. по $5.000 [freshness] [Отметить]
                if row.buy.count > 0 then
                    imgui.TextColored(DSP.theme.col('good', 1), DSP.utf8('СКУПКА (кому выгодно сдать)'))
                    local max_show = math.min(10, #row.buy.offers)
                    for j = 1, max_show do
                        local o = row.buy.offers[j]
                        local fresh_text, fresh_key = DSP.market.offer_freshness(o.ts)
                        imgui.TextColored(DSP.theme.col('accent', 1),
                            DSP.utf8(string.format('[Лавка #%s] %s', tostring(o.shop),
                                trunc(o.owner or '?', 18))))
                        imgui.SameLine(0, 6 * dpi)
                        imgui.Text(DSP.utf8(string.format('- нужно %s шт. по ', fmt_qty(o.qty or 0))))
                        imgui.SameLine(0, 4 * dpi)
                        imgui.TextColored(DSP.theme.col('good', 1), DSP.money(o.price))
                        imgui.SameLine(0, 8 * dpi)
                        imgui.TextColored(DSP.theme.col(fresh_key, 1), DSP.utf8('[' .. fresh_text .. ']'))
                        imgui.SameLine(0, 8 * dpi)
                        if imgui.SmallButton(DSP.utf8('[ Отметить ]##fb' .. tostring(i) .. '_' .. tostring(j))) then
                            DSP.market.mark_shop(o.shop)
                        end
                    end
                else
                    imgui.TextDisabled(DSP.utf8('  Нет скупщиков'))
                end
                imgui.Separator()
                imgui.Spacing()
            end
        end
        imgui.EndChild()
    end
end

-- =========================================================================
-- v1.2 Stage 3: ЗАМЕТКИ screen.
-- InputTextMultiline fills the available area; auto-save is debounced to
-- 1.5 seconds after the last edit so we never thrash the disk on every
-- keystroke. The actual save is performed in DSP.ui.install()'s OnFrame.
-- =========================================================================
function DSP.ui.notes_tab()
    local dpi = d()
    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8('ЗАМЕТКИ'))
    imgui.SameLine(0, 14 * dpi)
    imgui.TextDisabled(DSP.utf8('Автосохранение в config/PalatkaAI/notes.txt (debounce 1.5с)'))
    imgui.SameLine(0, 14 * dpi)
    if DSP.ui._notes_dirty then
        imgui.TextColored(DSP.theme.col('warn', 1), DSP.utf8('* не сохранено'))
    else
        imgui.TextColored(DSP.theme.col('good', 1), DSP.utf8('OK'))
    end
    imgui.SameLine(imgui.GetWindowWidth() - 130 * dpi, 6 * dpi)
    if imgui.Button(DSP.utf8('Сохранить'), imgui.ImVec2(110 * dpi, 0)) then
        local txt = ffi.string(DSP.ui.notes_buf)
        local f = io.open(DSP.notes_path, 'w')
        if f then f:write(txt); f:close() end
        DSP.ui._notes_dirty = false
        DSP.add_log('Заметки сохранены вручную')
    end
    imgui.Separator()

    local avail = imgui.GetContentRegionAvail()
    -- v1.2 hotfix: imgui.InputTextMultiline may be missing in older mimgui
    -- builds. Fall back to plain imgui.InputText (single-line) wrapped in pcall
    -- so the script doesn't crash on the ЗАМЕТКИ tab.
    local flags = 0
    if imgui.InputTextFlags and imgui.InputTextFlags.Multiline then
        flags = imgui.InputTextFlags.Multiline
    end
    local ok_ml, changed = pcall(imgui.InputTextMultiline, '##dsp_notes',
        DSP.ui.notes_buf, 8192, imgui.ImVec2(avail.x, avail.y), flags)
    if ok_ml and changed then
        DSP.ui._notes_dirty = true
        DSP.ui._notes_last_edit = os.clock()
    elseif not ok_ml then
        -- Fallback: single-line InputText (multiline unavailable).
        -- Still usable -- just no newlines in notes.
        local ok_it, changed2 = pcall(imgui.InputText, '##dsp_notes_fallback',
            DSP.ui.notes_buf, 8192)
        if ok_it and changed2 then
            DSP.ui._notes_dirty = true
            DSP.ui._notes_last_edit = os.clock()
        end
    end
end

-- =========================================================================
-- v1.2 main draw: landscape window, centered, theme via DSP.theme.push_window.
-- =========================================================================
function DSP.ui.draw()
    local dpi = d()
    local io = imgui.GetIO()
    -- Defensive: io may be {} in tests or missing DisplaySize on some imgui builds.
    local sw = (io and io.DisplaySize and io.DisplaySize.x) or 2340
    local sh = (io and io.DisplaySize and io.DisplaySize.y) or 1080
    -- v1.2: landscape proportions -- wide but NOT high, centered, never
    -- reaches the system [ВЗАИМОДЕЙСТВИЕ] button at the bottom.
    local win_w = math.min(sw * 0.85, 1600)
    local win_h = math.min(sh * 0.68, 540)
    local px = (sw - win_w) / 2
    local py = (sh - win_h) / 2

    imgui.SetNextWindowSize(imgui.ImVec2(win_w, win_h), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(px, py), imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(DSP.theme.opacity)

    local ncol = DSP.theme.push_window()
    local pushed_vars = 0
    if pcall(imgui.PushStyleVarFloat, imgui.StyleVar.WindowRounding, 12 * dpi) then pushed_vars = pushed_vars + 1 end
    if pcall(imgui.PushStyleVarFloat, imgui.StyleVar.FrameRounding, 8 * dpi) then pushed_vars = pushed_vars + 1 end
    if pcall(imgui.PushStyleVarFloat, imgui.StyleVar.ChildRounding, 9 * dpi) then pushed_vars = pushed_vars + 1 end
    if pcall(imgui.PushStyleVarVec2, imgui.StyleVar.ItemSpacing, imgui.ImVec2(8 * dpi, 6 * dpi)) then pushed_vars = pushed_vars + 1 end

    -- v1.2 sync: if numeric tab was changed externally (tests / old code),
    -- bring the screen id in line so the dispatcher renders the right panel.
    if DSP.ui.tab ~= DSP.screens.index_by_id(DSP.ui.screen) then
        DSP.screens.set_index(DSP.ui.tab)
    end

    local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar
    if imgui.Begin(DSP.utf8(' palatka ai | РЫНОК v' .. DSP.version .. ' '), DSP.ui.open_ref, flags) then
        DSP.screens.topbar()
        if imgui.BeginChild('##dsp_main', imgui.ImVec2(0, 0), false) then
            DSP.screens.draw(DSP.ui.screen)
        end
        imgui.EndChild()
    end
    imgui.End()
    if pushed_vars > 0 then
        pcall(imgui.PopStyleVar, pushed_vars)
    end
    if ncol and ncol > 0 then
        pcall(imgui.PopStyleColor, ncol)
    end
    if DSP.ui.open_ref and DSP.ui.open_ref[0] == false then
        DSP.ui.open = false
    end
end

function DSP.ui.install()
    DSP.ui.init()
    -- v1.2 Stage 3: install the craglog mini-window (independent of main UI).
    -- /crlog command is registered here so the toggle is always available.
    if DSP.craglog and DSP.craglog.install then
        pcall(DSP.craglog.install)
    end
    -- Floating [CR] button. v1.2 Stage 3: drag handle on the left, open
    -- button on the right; position persists to ui_state.json every 5s when
    -- moved. Touch-friendly: the drag strip is 18*dpi wide, the open button
    -- is 58*dpi wide. A small "::" glyph on the handle shows it's grabbable.
    -- v1.2 hotfix: whole callback wrapped in pcall so a single bad imgui call
    -- never crashes the game (the script just logs the error to standalone.log
    -- and silently retries next frame).
    imgui.OnFrame(function()
        return DSP.ui.btn_visible ~= false and not DSP.ui.open and not (isPauseMenuActive and isPauseMenuActive())
    end, function(player)
        local ok, err = pcall(function()
            local dpi = d()
            if player then player.HideCursor = false end
            local io = imgui.GetIO()
            local sw = (io and io.DisplaySize and io.DisplaySize.x) or 2340
            local sh = (io and io.DisplaySize and io.DisplaySize.y) or 1080
            local win_w = 76 * dpi
            local win_h = 60 * dpi
            local saved = DSP.settings.cr_pos or { x = 28, y = 215 }
            local px = DSP.clamp(saved.x, 4, sw - win_w - 4)
            local py = DSP.clamp(saved.y, 4, sh - win_h - 4)
            imgui.SetNextWindowPos(imgui.ImVec2(px, py), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(win_w, win_h), imgui.Cond.Always)
            imgui.SetNextWindowBgAlpha(DSP.theme.opacity)
            local ncol = DSP.theme.push_overlay(0.85)
            local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoBackground
                + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoMove
            if imgui.Begin('##dsp_cr_btn', nil, flags) then
                -- Drag handle (left 18*dpi)
                local p1 = 0
                if pcall(imgui.PushStyleColor, imgui.Col.Button,        DSP.theme.col('accent', 0.30)) then p1 = p1 + 1 end
                if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, DSP.theme.col('accent', 0.50)) then p1 = p1 + 1 end
                if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive,  DSP.theme.col('accent', 0.70)) then p1 = p1 + 1 end
                pcall(imgui.Button, DSP.utf8('::##cr_drag'), imgui.ImVec2(18 * dpi, -1))
                -- Drag detection: if the handle is being held AND the mouse moved,
                -- shift the saved position by the mouse delta (clamped to screen).
                -- Safe access: imgui.IsItemActive may not exist in older mimgui.
                if imgui.IsItemActive then
                    local ok_active, active = pcall(imgui.IsItemActive)
                    if ok_active and active then
                        local mdx = (io and io.MouseDelta and io.MouseDelta.x) or 0
                        local mdy = (io and io.MouseDelta and io.MouseDelta.y) or 0
                        if mdx ~= 0 or mdy ~= 0 then
                            DSP.settings.cr_pos = {
                                x = DSP.clamp(px + mdx, 4, sw - win_w - 4),
                                y = DSP.clamp(py + mdy, 4, sh - win_h - 4),
                            }
                            DSP.ui._cr_pos_dirty = true
                        end
                    end
                end
                if p1 > 0 then pcall(imgui.PopStyleColor, p1) end
                imgui.SameLine(0, 0)
                -- Open button (right 58*dpi)
                local p2 = 0
                if pcall(imgui.PushStyleColor, imgui.Col.Button,        DSP.theme.col('accent', 0.85)) then p2 = p2 + 1 end
                if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, DSP.theme.col('accent', 1.00)) then p2 = p2 + 1 end
                if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive,  DSP.theme.col('accent', 1.00)) then p2 = p2 + 1 end
                if imgui.Button(DSP.utf8('[CR]'), imgui.ImVec2(58 * dpi, -1)) then
                    DSP.ui.set_open(true)
                end
                if p2 > 0 then pcall(imgui.PopStyleColor, p2) end
            end
            imgui.End()
            if ncol and ncol > 0 then pcall(imgui.PopStyleColor, ncol) end
            -- Persist drag-moved position every 5s (avoids writing on every frame).
            if DSP.ui._cr_pos_dirty and (os.time() - (DSP.ui._cr_last_save or 0)) > 5 then
                pcall(DSP.save_ui_state)
                DSP.ui._cr_pos_dirty = false
                DSP.ui._cr_last_save = os.time()
            end
        end)
        if not ok then
            if DSP and DSP.flog then
                DSP.flog('CR button frame error: ' .. tostring(err))
            end
            -- Disable CR button visibility for this session to prevent
            -- persistent error spam; user can restart script to retry.
            DSP.ui.btn_visible = false
        end
    end)
    imgui.OnFrame(function() return DSP.ui.open end, function()
        local ok, err = pcall(function()
            DSP.ui.draw()
            -- v1.2 Stage 3: debounced notes auto-save (1.5s after last edit)
            if DSP.ui._notes_dirty and (os.clock() - (DSP.ui._notes_last_edit or 0)) > 1.5 then
                if DSP.mobile and DSP.mobile.save_notes then
                    DSP.mobile.save_notes()
                else
                    local txt = ffi.string(DSP.ui.notes_buf)
                    local f, err = io.open(DSP.notes_path, 'w')
                    if f then
                        local written, write_err = f:write(txt)
                        local closed, close_err = f:close()
                        if written and closed then DSP.ui._notes_dirty = false
                        else DSP.notify('Ошибка заметок: ' .. tostring(write_err or close_err)) end
                    else DSP.notify('Ошибка заметок: ' .. tostring(err)) end
                end
            end
        end)
        if not ok then
            if DSP and DSP.flog then
                DSP.flog('UI draw error: ' .. tostring(err))
            end
            -- Auto-close to prevent persistent error loop.
            DSP.ui.set_open(false)
        end
    end)
end

end
__mod_30_ui()

local function __mod_35_screens()
-- 35_screens.lua
-- v1.2 Screen dispatcher: horizontal Top Bar + per-screen touch pager.
--
-- Responsibilities:
--   * Define the 8-tab Top Bar layout (ПАЛАТКА / ЛАВКИ ЦР / АРБИТРАЖ / ПОИСК /
--     ЛОГИ / СТАТИСТИКА / ЗАМЕТКИ / НАСТРОЙКИ).
--   * Maintain per-screen page state (DSP.ui.pages[id]).
--   * Provide a touch-friendly pager (big buttons, ASCII arrows only).
--   * Route the active screen id to its draw function in DSP.ui.*
--
-- This module is loaded between 30_ui.lua and 50_overlay.lua in build.py,
-- but it never references DSP.ui.draw() directly -- the dispatcher is invoked
-- from inside the parent Begin/End scope by 30_ui.lua's draw().

DSP.screens = DSP.screens or {}

-- Ordered list of screens for the Top Bar.
-- id     -- stable string identifier, used by DSP.settings.screen and DSP.ui.pages
-- label  -- short label shown in the Top Bar (ASCII safe; Cyrillic is fine for CP1251)
DSP.screens.list = {
    { id = 'palatka',  label = 'ПАЛАТКА' },
    { id = 'lavki',    label = 'ЛАВКИ ЦР' },
    { id = 'arbitrage',label = 'АРБИТРАЖ' },
    { id = 'search',   label = 'ПОИСК' },
    { id = 'logs',     label = 'ЛОГИ' },
    { id = 'stats',    label = 'СТАТИСТИКА' },
    { id = 'notes',    label = 'ЗАМЕТКИ' },
    { id = 'settings', label = 'НАСТРОЙКИ' },
}

-- Backward compat: numeric tab id (1..8) maps to a screen id.
-- Old tests/UI code that uses DSP.ui.tab = N keeps working.
DSP.ui = DSP.ui or {}
DSP.ui.screen = DSP.settings.screen or 'palatka'
DSP.ui.pages = DSP.ui.pages or {}

local function d()
    return tonumber(DSP.ui.d) or tonumber(DSP.settings.dpi) or 1.25
end

function DSP.screens.id_by_index(i)
    local e = DSP.screens.list[i]
    return e and e.id or 'palatka'
end

function DSP.screens.index_by_id(id)
    for i, e in ipairs(DSP.screens.list) do
        if e.id == id then return i end
    end
    return 1
end

function DSP.screens.set(id)
    if not id then return end
    if DSP.screens.index_by_id(id) == 0 then id = 'palatka' end
    DSP.ui.screen = id
    DSP.settings.screen = id
    -- Keep numeric tab back-compat in sync.
    DSP.ui.tab = DSP.screens.index_by_id(id)
    -- Reset page state for the new screen so we don't land past the end of a list.
    DSP.ui.pages[id] = 1
    DSP.save_settings()
end

-- Back-compat: legacy numeric tab setter used by old code/tests.
function DSP.screens.set_index(i)
    DSP.screens.set(DSP.screens.id_by_index(i))
end

function DSP.screens.page_of(id)
    id = id or DSP.ui.screen or 'palatka'
    local p = tonumber(DSP.ui.pages[id]) or 1
    if p < 1 then p = 1 end
    DSP.ui.pages[id] = p
    return p
end

function DSP.screens.set_page(id, p)
    id = id or DSP.ui.screen or 'palatka'
    p = tonumber(p) or 1
    if p < 1 then p = 1 end
    DSP.ui.pages[id] = p
end

-- =========================================================================
-- Horizontal Top Bar (replaces the v1.1 left vertical nav column).
-- Renders a single row of compact tab buttons that fill 100% of parent width.
-- =========================================================================
function DSP.screens.topbar()
    local dpi = d()
    local cur = DSP.ui.screen or 'palatka'
    local cur_idx = DSP.screens.index_by_id(cur)
    local avail = imgui.GetContentRegionAvail().x
    local n = #DSP.screens.list
    local spacing = 4 * dpi
    local bw = (avail - spacing * (n - 1)) / n
    if bw < 60 * dpi then bw = 60 * dpi end
    local bh = 38 * dpi

    local pushed_vars = 0
    if pcall(imgui.PushStyleVarFloat, imgui.StyleVar.FrameRounding, 6 * dpi) then
        pushed_vars = pushed_vars + 1
    end
    if pcall(imgui.PushStyleVarVec2, imgui.StyleVar.ItemSpacing, imgui.ImVec2(4 * dpi, 4 * dpi)) then
        pushed_vars = pushed_vars + 1
    end
    for i, e in ipairs(DSP.screens.list) do
        local active = (i == cur_idx)
        if active then
            imgui.PushStyleColor(imgui.Col.Button,        DSP.theme.col('accent', 0.55))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, DSP.theme.col('accent', 0.75))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  DSP.theme.col('accent', 0.95))
        end
        local label = DSP.utf8(' ' .. e.label .. ' ') .. '##scr' .. tostring(i)
        if imgui.Button(label, imgui.ImVec2(bw, bh)) then
            DSP.screens.set(e.id)
        end
        if i < n then
            imgui.SameLine(0, spacing)
        end
        if active then imgui.PopStyleColor(3) end
    end
    if pushed_vars > 0 then
        pcall(imgui.PopStyleVar, pushed_vars)
    end
    imgui.Spacing()
end

-- =========================================================================
-- Touch pager: [< Предыдущая] [Стр. X из Y] [Следующая >] [^ ВВЕРХ] [v ВНИЗ]
-- All buttons are large (>= 36*dpi height) for finger tapping on Samsung A15.
--
-- Returns from, to (1-indexed inclusive) into the source rows array.
-- Use as: local from, to = DSP.screens.pager(#rows, per_page, 'palatka')
-- =========================================================================
function DSP.screens.pager(total_rows, per_page, id)
    local dpi = d()
    total_rows = math.max(0, tonumber(total_rows) or 0)
    per_page = math.max(5, tonumber(per_page) or 20)
    local pages = math.max(1, math.ceil(total_rows / per_page))
    local page = DSP.screens.page_of(id)
    if page > pages then page = pages end
    if page < 1 then page = 1 end
    DSP.screens.set_page(id, page)

    local from = (page - 1) * per_page + 1
    local to = math.min(total_rows, page * per_page)

    local bw_prev = 150 * dpi
    local bw_next = 150 * dpi
    local bw_qx   = 95 * dpi
    local bh      = 36 * dpi

    local pushed_vars = 0
    if pcall(imgui.PushStyleVarVec2, imgui.StyleVar.ItemSpacing, imgui.ImVec2(6 * dpi, 6 * dpi)) then
        pushed_vars = pushed_vars + 1
    end
    if imgui.Button(DSP.utf8('< Предыдущая'), imgui.ImVec2(bw_prev, bh)) then
        DSP.screens.set_page(id, page - 1)
    end
    imgui.SameLine(0, 6 * dpi)
    imgui.TextDisabled(DSP.utf8(string.format('Стр. %d из %d', page, pages)))
    imgui.SameLine(0, 6 * dpi)
    if imgui.Button(DSP.utf8('Следующая >'), imgui.ImVec2(bw_next, bh)) then
        DSP.screens.set_page(id, page + 1)
    end
    imgui.SameLine(0, 14 * dpi)
    if imgui.Button(DSP.utf8('^ ВВЕРХ'), imgui.ImVec2(bw_qx, bh)) then
        DSP.screens.set_page(id, 1)
    end
    imgui.SameLine(0, 6 * dpi)
    if imgui.Button(DSP.utf8('v ВНИЗ'), imgui.ImVec2(bw_qx, bh)) then
        DSP.screens.set_page(id, pages)
    end
    if pushed_vars > 0 then
        pcall(imgui.PopStyleVar, pushed_vars)
    end
    return from, to
end

-- =========================================================================
-- Per-page size selector. Renders "[Строк на странице:] [-] N [+]" inline.
-- =========================================================================
function DSP.screens.per_page_selector()
    local dpi = d()
    local per = math.max(5, tonumber(DSP.settings.per_page) or 20)
    local pushed_vars = 0
    if pcall(imgui.PushStyleVarVec2, imgui.StyleVar.ItemSpacing, imgui.ImVec2(4 * dpi, 4 * dpi)) then
        pushed_vars = pushed_vars + 1
    end
    imgui.TextDisabled(DSP.utf8('Строк/стр:'))
    imgui.SameLine(0, 6 * dpi)
    if imgui.Button(DSP.utf8('-##per_minus'), imgui.ImVec2(34 * dpi, 32 * dpi)) then
        DSP.settings.per_page = math.max(10, per - 5)
        DSP.save_settings()
    end
    imgui.SameLine(0, 4 * dpi)
    imgui.Text(tostring(per))
    imgui.SameLine(0, 4 * dpi)
    if imgui.Button(DSP.utf8('+##per_plus'), imgui.ImVec2(34 * dpi, 32 * dpi)) then
        DSP.settings.per_page = math.min(50, per + 5)
        DSP.save_settings()
    end
    if pushed_vars > 0 then
        pcall(imgui.PopStyleVar, pushed_vars)
    end
end

-- =========================================================================
-- Dispatcher: route the active screen id to its draw function in DSP.ui.*.
-- New screens (lavki, search, notes) have stubs that render a "Stage 2/3"
-- placeholder. Stage 2 will replace lavki_tab and finder_tab; Stage 3 will
-- replace notes_tab.
-- =========================================================================
function DSP.screens.draw(id)
    id = id or DSP.ui.screen or 'palatka'
    if id == 'palatka' then
        if DSP.ui.palatka_tab then DSP.ui.palatka_tab()
        elseif DSP.ui.trade_tab then DSP.ui.trade_tab() end
    elseif id == 'lavki' then
        if DSP.ui.lavki_tab then DSP.ui.lavki_tab() else DSP.screens.stub('Stage 2') end
    elseif id == 'arbitrage' then
        if DSP.ui.arbitrage_tab then DSP.ui.arbitrage_tab()
        elseif DSP.ui.market_tab then DSP.ui.market_tab() end
    elseif id == 'search' then
        if DSP.ui.finder_tab then DSP.ui.finder_tab() else DSP.screens.stub('Stage 2') end
    elseif id == 'logs' then
        if DSP.ui.log_tab then DSP.ui.log_tab() end
    elseif id == 'stats' then
        if DSP.ui.statistics_tab then DSP.ui.statistics_tab() end
    elseif id == 'notes' then
        if DSP.ui.notes_tab then DSP.ui.notes_tab() else DSP.screens.stub('Stage 3') end
    elseif id == 'settings' then
        if DSP.ui.settings_tab then DSP.ui.settings_tab() end
    end
end

function DSP.screens.stub(stage)
    local dpi = d()
    imgui.Spacing()
    imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8('[ ' .. stage .. ' ]'))
    imgui.Separator()
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Экран будет реализован в ' .. stage .. ' модернизации Palatka AI v1.2.'))
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Сейчас работает вёрстка Top Bar, темы оформления, пейджер,'))
    imgui.TextDisabled(DSP.utf8('прозрачность окна и перетаскиваемая кнопка [CR].'))
end

end
__mod_35_screens()

local function __mod_36_mobile()
-- Touch shell. Keep the lower game interaction strip outside this window.
local ffi = require('ffi')
DSP.mobile = {}
local M = DSP.mobile
function M.scale() return tonumber(DSP.ui.d) or 1.25 end
function M.geometry(sw, sh)
    local saved=DSP.settings.mobile_window or {}
    local s=math.min(sw/2340,sh/1080)
    return {x=sw*.03,y=sh*.03,w=DSP.clamp(tonumber(saved.w) or sw*.80,math.min(1100,sw),sw),
        h=DSP.clamp(tonumber(saved.h) or sh*.70,math.min(550,sh),sh),nav=math.max(210,250*s),touch=math.max(48,60*s)}
end
function M.window_position(sw,sh)
    local g=M.geometry(sw,sh)
    local saved=DSP.settings.mobile_window or {x=g.x,y=g.y}
    return {x=DSP.clamp(tonumber(saved.x) or g.x,0,math.max(0,sw-g.w)),
        y=DSP.clamp(tonumber(saved.y) or g.y,0,math.max(0,sh-g.h)),w=g.w,h=g.h}
end
function M.move_window(dx,dy,sw,sh)
    local pos=M.window_position(sw,sh)
    pos.x=pos.x+dx;pos.y=pos.y+dy;DSP.settings.mobile_window=pos
    DSP.settings.mobile_window=M.window_position(sw,sh)
    M.window_dirty=true;M.position_pending=true
end
function M.resize_window(dx,dy,sw,sh)
    local p=M.window_position(sw,sh)
    local right=p.x+p.w
    local w=DSP.clamp(p.w-dx,math.min(1100,sw),right)
    DSP.settings.mobile_window={x=right-w,y=p.y,w=w,h=DSP.clamp(p.h+dy,math.min(550,sh-p.y),sh-p.y)}
    M.window_dirty=true;M.position_pending=true
end
local function mix(a,b,t)
    return imgui.ImVec4(a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t,1)
end
function M.paint_button(role,active)
    local t=DSP.theme.get()
    local primary=role=='primary'
    local bg=primary and t.accent or {t.panel[1]+.05,t.panel[2]+.05,t.panel[3]+.05}
    if active and not primary then bg={t.panel[1]*.8+t.accent[1]*.2,t.panel[2]*.8+t.accent[2]*.2,t.panel[3]*.8+t.accent[3]*.2} end
    if role=='quiet' then bg=t.panel end
    imgui.PushStyleColor(imgui.Col.Button,mix(bg,bg,0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered,mix(bg,t.text,.10))
    imgui.PushStyleColor(imgui.Col.ButtonActive,mix(bg,t.accent,.30))
    imgui.PushStyleColor(imgui.Col.Text,primary and DSP.theme.col('bg',1) or DSP.theme.col(active and 'accent' or 'text',1))
end
function M.queue_scroll(direction)
    local step=DSP.clamp(tonumber(DSP.settings.scroll_step) or 300,100,1200)
    M.scroll_delta=(M.scroll_delta or 0)+direction*step
end
function M.scroll_rail(height)
    local h=math.max(48,(height-80)/2)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding,imgui.ImVec2(8,5))
    M.paint_button('rail',false)
    if imgui.Button(DSP.utf8('ВВЕРХ')..'##mobile_rail_up',imgui.ImVec2(-1,h)) then M.queue_scroll(-1) end
    if imgui.Button(DSP.utf8('ВНИЗ')..'##mobile_rail_down',imgui.ImVec2(-1,h)) then M.queue_scroll(1) end
    local step=tonumber(DSP.settings.scroll_step) or 300
    local name=step<=150 and 'короткий' or step<=300 and 'средний' or 'длинный'
    if imgui.Button(DSP.utf8('Шаг\n'..name)..'##scroll_step',imgui.ImVec2(-1,60)) then
        DSP.settings.scroll_step=step<=150 and 300 or step<=300 and 600 or 150
        DSP.save_settings()
    end
    imgui.PopStyleColor(4)
    imgui.PopStyleVar(1)
end
function M.text(s) imgui.TextWrapped(DSP.utf8(tostring(s or ''))) end
function M.title(s) imgui.TextColored(DSP.theme.col('accent', 1), DSP.utf8(s)) end
function M.button(label, id, width, active, role)
    M.paint_button(role or 'secondary',active)
    if role=='nav' then imgui.PushStyleVarVec2(imgui.StyleVar.ButtonTextAlign,imgui.ImVec2(.12,.5)) end
    local text=DSP.utf8(label)
    local measured=imgui.CalcTextSize(text).x+40
    local available=imgui.GetContentRegionAvail().x
    if width and width>0 then
        width=math.max(width,measured)
        if available<width then imgui.NewLine(); available=imgui.GetContentRegionAvail().x end
        width=math.min(width,available)
    end
    local hit = imgui.Button(text..'##mobile_'..id,
        imgui.ImVec2(width or -1, (M.layout and M.layout.touch) or 60))
    imgui.PopStyleColor(4)
    if role=='nav' then imgui.PopStyleVar(1) end
    return hit
end
function M.inline() imgui.SameLine(0, 12) end
function M.child(id, w, h, fn)
    local shown = imgui.BeginChild('##mobile_'..id, imgui.ImVec2(w or 0, h or 0), true)
    if shown then fn() end
    imgui.EndChild()
end
function M.toggle(label, parent, key, default)
    local value = parent[key]
    if value == nil then value=default end
    local b=imgui.new.bool(value and true or false)
    if imgui.Checkbox(DSP.utf8(label), b) then parent[key]=b[0]; DSP.save_settings(); return true end
    return false
end
M.buffers = setmetatable({}, {__mode='k'})
function M.edit_buffer(item, key)
    local cache=M.buffers[item]
    if not cache then cache={}; M.buffers[item]=cache end
    if not cache[key] then
        cache[key]=imgui.new.char[64]()
        local value=tostring(item[key] or 0)
        ffi.copy(cache[key], value, math.min(#value, 63))
    end
    return cache[key]
end
function M.apply_number(item,key,buf,minimum)
    local raw=ffi.string(buf)
    if not raw:match('^%d+$') then return false end
    local n=tonumber(raw)
    if not n or n < (minimum or 0) or n > 9007199254740991 then return false end
    item[key]=math.floor(n)
    return true
end
function M.number(label,id,item,key,minimum,width)
    imgui.TextDisabled(DSP.utf8(label))
    local buf=M.edit_buffer(item,key)
    imgui.SetNextItemWidth(width or 250)
    if imgui.InputText('##mobile_num_'..id,buf,64) then
        if M.apply_number(item,key,buf,minimum) then DSP.save_settings(); return true end
    end
    if not ffi.string(buf):match('^%d+$') then
        imgui.TextColored(DSP.theme.col('bad',1), DSP.utf8('Введите целое положительное число'))
    end
    return false
end
function M.refresh_buffer(item,key)
    if M.buffers[item] then M.buffers[item][key]=nil end
end
local set_screen = DSP.screens.set
function DSP.screens.set(id)
    local found=false
    for _,e in ipairs(DSP.screens.list) do if e.id==id then found=true end end
    set_screen(found and id or 'palatka')
    M.reset_scroll=true
end
DSP.screens.list[1].label='ПАЛАТКА'
DSP.screens.list[2].label='ЛАВКИ'
DSP.screens.list[6].label='СТАТИСТИКА'
DSP.screens.list[5].label='ИСТОРИЯ'
function DSP.screens.topbar()
    M.title('РАЗДЕЛЫ')
    imgui.Separator()
    for i,e in ipairs(DSP.screens.list) do
        if M.button(e.label,'nav'..i,-1,DSP.ui.screen==e.id,'nav') then DSP.screens.set(e.id) end
    end
end
function M.draw_pager(total,per,id)
    total=math.max(0,tonumber(total) or 0)
    per=math.max(1,tonumber(per) or 8)
    local pages=math.max(1, math.ceil(total/per))
    local page=math.min(pages,DSP.screens.page_of(id))
    local width=math.min(230,(imgui.GetContentRegionAvail().x-24)/3)
    if M.button('< Назад','prev'..id,width) then page=math.max(1,page-1) end
    M.inline()
    local prefix=id=='trade_history' and 'Сделки ' or id=='stall_history' and 'Лавки ' or ''
    if M.button(prefix..page..' / '..pages,'page'..id,width) then page=1 end
    M.inline()
    if M.button('Вперёд >','next'..id,width) then page=math.min(pages,page+1) end
    DSP.screens.set_page(id,page)
    return (page-1)*per+1, math.min(total,page*per)
end
function DSP.screens.pager(total,per,id)
    if M.sticky then
        M.footers=M.footers or {}
        local found=false
        for _,entry in ipairs(M.footers) do
            if entry.id==id then entry.total=total; entry.per=per; found=true end
        end
        if not found then M.footers[#M.footers+1]={total=total,per=per,id=id} end
        local page=math.min(DSP.screens.page_of(id),math.max(1,math.ceil(total/per)))
        DSP.screens.set_page(id,page)
        return (page-1)*per+1,math.min(total,page*per)
    end
    return M.draw_pager(total,per,id)
end
local function workspace()
    local screen=DSP.ui.screen
    local entry=DSP.screens.list[DSP.screens.index_by_id(screen)]
    imgui.TextColored(DSP.theme.col('text',1),DSP.utf8(entry.label..' / '..tostring(DSP.market.state.sid)))
    M.inline()
    if M.button('Наверх','header_top',220) then M.reset_scroll=true end
    M.inline()
    if M.button('Свернуть','header_close',240) then DSP.ui.set_open(false) end
    imgui.Separator()
    M.footers={}
    local height=math.max(120,imgui.GetContentRegionAvail().y-96)
    local body_width=math.max(300,imgui.GetContentRegionAvail().x-150)
    M.child('body_'..screen,body_width,height,function()
        if M.reset_scroll then
            if imgui.SetScrollY then imgui.SetScrollY(0) end
            M.reset_scroll=false
        end
        if (M.scroll_delta or 0)~=0 then
            local current=imgui.GetScrollY and imgui.GetScrollY() or 0
            local limit=imgui.GetScrollMaxY and imgui.GetScrollMaxY() or 1000000
            if imgui.SetScrollY then imgui.SetScrollY(DSP.clamp(current+M.scroll_delta,0,limit)) end
            M.scroll_delta=0
        end
        M.sticky=true
        DSP.screens.draw(screen)
        M.sticky=false
    end)
    M.inline()
    M.child('scroll_rail',138,height,function() M.scroll_rail(height) end)
    if #M.footers>0 then
        for i,entry in ipairs(M.footers) do
            if i>1 then M.inline() end
            M.draw_pager(entry.total,entry.per,entry.id)
        end
    else
        if M.button('Наверх','content_top',240) then M.reset_scroll=true end
    end
end
function DSP.ui.header()
    local st=DSP.market.state
    M.title('РЫНОК / '..tostring(st.sid))
    M.text(string.format('%s | %d лавок | %d предложений | %s',
        st.status=='loading' and 'Загрузка' or st.status=='error' and 'Ошибка обновления' or 'База рынка',
        st.shops or 0,st.offers or 0,DSP.market.freshness()))
    if st.status=='error' then M.text(st.error or '') end
    if M.button('Обновить рынок','refresh',260) then DSP.market.pull(st.sid) end
    imgui.Separator()
end
function DSP.ui.draw()
    local io=imgui.GetIO()
    local sz=io and io.DisplaySize or {x=2340,y=1080}
    local g=M.geometry(sz.x,sz.y)
    M.layout=g
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    local pos=M.window_position(sz.x,sz.y)
    local changed=M.last_viewport~=tostring(sz.x)..':'..tostring(sz.y)
    imgui.SetNextWindowPos(imgui.ImVec2(pos.x,pos.y),
        (M.position_pending or changed) and imgui.Cond.Always or imgui.Cond.FirstUseEver)
    M.position_pending=false; M.last_viewport=tostring(sz.x)..':'..tostring(sz.y)
    imgui.SetNextWindowBgAlpha(DSP.theme.opacity)
    local colors=DSP.theme.push_window()
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding,imgui.ImVec2(14,11))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(10,8))
    if DSP.ui.tab~=DSP.screens.index_by_id(DSP.ui.screen) then DSP.screens.set_index(DSP.ui.tab) end
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,14)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,10)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding,12)
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize
        +imgui.WindowFlags.NoSavedSettings
    if imgui.Begin('##palatka_mobile',DSP.ui.open_ref,flags) then
        if imgui.SetWindowFontScale then imgui.SetWindowFontScale(1.05 * M.scale() / 1.25) end
        M.paint_button('quiet',false)
        imgui.Button(DSP.utf8('PALATKA AI     ::'),imgui.ImVec2(-1,50))
        imgui.PopStyleColor(4)
        local handle_active=false
        if imgui.IsItemActive and imgui.IsItemActive() then
            handle_active=true
            local delta=io.MouseDelta or {x=0,y=0}
            if delta.x~=0 or delta.y~=0 then M.move_window(delta.x,delta.y,sz.x,sz.y) end
        end
        if imgui.GetWindowPos and not M.position_pending then
            local actual=imgui.GetWindowPos()
            if actual and (actual.x~=pos.x or actual.y~=pos.y) then
                DSP.settings.mobile_window={x=actual.x,y=actual.y,w=g.w,h=g.h}
                local clamped=M.window_position(sz.x,sz.y)
                if clamped.x~=actual.x or clamped.y~=actual.y then
                    DSP.settings.mobile_window=clamped; M.position_pending=true
                end
                M.window_dirty=true
            end
        end
        local content_height=math.max(200,imgui.GetContentRegionAvail().y-74)
        M.child('navigation',g.nav,content_height,DSP.screens.topbar)
        M.inline()
        M.child('content_'..DSP.ui.screen,0,content_height,workspace)
        M.paint_button('quiet',false)
        imgui.Button(DSP.utf8('/  Размер'),imgui.ImVec2(190,60))
        imgui.PopStyleColor(4)
        if imgui.IsItemActive and imgui.IsItemActive() then
            handle_active=true
            local delta=io.MouseDelta or {x=0,y=0}
            if delta.x~=0 or delta.y~=0 then M.resize_window(delta.x,delta.y,sz.x,sz.y) end
        end
        if M.window_dirty and not handle_active then M.window_dirty=not DSP.save_settings() end
    end
    imgui.End()
    imgui.PopStyleVar(5)
    if colors and colors>0 then imgui.PopStyleColor(colors) end
    if DSP.ui.open_ref and not DSP.ui.open_ref[0] then DSP.ui.open=false end
end
-- The old settings screen remains complete and scrolls vertically in the content child.
-- Wrap rows on wider settings selectors instead of forcing them beyond the edge.

end
__mod_36_mobile()

local function __mod_37_mobile_trade()
-- Active preset editor: never recreate a keyboard input on every frame.
local ffi=require('ffi')
local M=DSP.mobile
local U=DSP.ui
local function report(ok,detail)
    DSP.notify(ok and ('Готово: '..tostring(detail or '')) or ('Ошибка: '..tostring(detail or '')))
end
local function set_price(kind,it,value)
    it.price=math.max(1,math.floor(value))
    it.needs_price=nil
    M.refresh_buffer(it,'price')
    DSP.save_settings()
end
local function item_card(kind,it,index)
    M.text(tostring(index)..'. '..tostring(it.name or '?'))
    if (tonumber(it.price) or 0)>0 then
        M.toggle('Выставлять##item'..kind..index,it,'enabled',true)
    else M.text('Нужна ваша цена. Позиция отключена до заполнения.'); it.enabled=false end
    imgui.Columns(2,'##edit_item'..kind..index,false)
    if M.number('Цена ($)','price'..kind..index,it,'price',1,300) then
        it.needs_price=nil; DSP.save_settings()
    end
    imgui.NextColumn()
    M.number('Количество','qty'..kind..index,it,'qty',1,230)
    imgui.Columns(1)
    if not U.trade_advanced then imgui.Separator(); return false end
    if M.button('-1$','minus'..kind..index,135) then set_price(kind,it,(tonumber(it.price) or 0)-1) end
    M.inline()
    if M.button('Рынок','market'..kind..index,180) then
        local row=DSP.presets.find_row(it)
        if row then
            local price=kind=='buy' and DSP.market.buy_target(row) or DSP.market.sell_target(row)
            if price>0 then set_price(kind,it,price) else DSP.notify('Нет цены для этой стороны рынка') end
        else DSP.notify('Товар не найден в базе рынка') end
    end
    M.inline()
    if M.button('+10 000','plus'..kind..index,180) then set_price(kind,it,(tonumber(it.price) or 0)+10000) end
    M.inline()
    if M.button('Удалить','remove'..kind..index,180) then DSP.presets.remove(kind,index); return true end
    imgui.Separator()
end
local function preset_library(kind,p)
    if not DSP.presets.list then return end
    U.preset_name_buf=U.preset_name_buf or imgui.new.char[128]()
    M.title('Наборы товаров')
    local list=DSP.presets.list(kind)
    for i,entry in ipairs(list) do
        if M.button(entry.name or ('Набор '..i),'preset'..kind..i,300,DSP.presets.selected(kind)==i) then
            report(DSP.presets.select(kind,i))
        end
    end
    imgui.SetNextItemWidth(360)
    imgui.InputTextWithHint('##preset_name',DSP.utf8('Название набора'),U.preset_name_buf,128)
    if M.button('Создать набор','create_preset',250) then report(DSP.presets.create(kind,DSP.to_cp(ffi.string(U.preset_name_buf)))) end
    M.inline()
    if M.button('Переименовать','rename_preset',280) then report(DSP.presets.rename(kind,DSP.presets.selected(kind),DSP.to_cp(ffi.string(U.preset_name_buf)))) end
    if M.button('Удалить этот набор','delete_preset',350) then
        U.confirm_delete=not U.confirm_delete
    end
    if U.confirm_delete then
        M.text('Удалить выбранный набор товаров?')
        if M.button('Да, удалить набор','confirm_delete',350) then
            report(DSP.presets.delete(kind,DSP.presets.selected(kind))); U.confirm_delete=false
        end
    end
    imgui.Separator()
    if M.button('Импорт Market Helper','import_mh',350) then report(DSP.presets.import_mh()) end
    M.inline()
    if DSP.presets.export_file and M.button('Экспорт набора','export_preset',300) then report(DSP.presets.export_file(kind)) end
    if DSP.presets.import_file then
        U.import_path_buf=U.import_path_buf or imgui.new.char[512]()
        imgui.SetNextItemWidth(math.min(800,imgui.GetContentRegionAvail().x))
        imgui.InputTextWithHint('##import_path',DSP.utf8('Полный путь к JSON файлу набора'),U.import_path_buf,512)
        if M.button('Импорт файла','import_file',300) then report(DSP.presets.import_file(DSP.to_cp(ffi.string(U.import_path_buf)),kind)) end
    end
end
local function inventory(kind)
    M.text('Инвентарь: '..tostring(DSP.auto.inv_status or 'не сканирован'))
    if M.button('Сканировать инвентарь','scan_inventory',400) then DSP.auto.scan_inventory() end
    M.text('Откройте инвентарь в игре; добавляйте товары в нужную сторону торговли.')
    for i,it in ipairs(DSP.auto.inv or {}) do
        M.text(tostring(it.name or '?')..' x'..tostring(it.count or 0))
        local name=tostring(it.name or '')
        local ench=tonumber(it.ench) or tonumber(name:match('%(%+(%d+)%)%s*$')) or 0
        local base=name:gsub('%s+%(%+%d+%)%s*$','')
        local row=DSP.market.row_for(base,ench)
        if row then
            if M.button('В скупку','inv_buy'..i,240) then report(DSP.presets.add(row,'buy')) end
            M.inline()
            if M.button('В продажу','inv_sell'..i,240) then report(DSP.presets.add(row,'sell')) end
        else
            M.text('Рыночной цены нет. Добавьте товар и задайте свою цену в наборе.')
            for _,side in ipairs({'buy','sell'}) do
                local label=side=='buy' and 'В скупку / задать цену' or 'В продажу / задать цену'
                if M.button(label,'inv_unknown_'..side..i,430) then
                    local ok,err=DSP.presets.add_manual(side,{name=base,ench=ench,price=0,
                        qty=math.max(1,tonumber(it.count or it.qty) or 1),enabled=false,needs_price=true})
                    report(ok,err)
                    if ok then U.preset_kind=side; U.trade_section='items' end
                end
                if side=='buy' then M.inline() end
            end
        end
        imgui.Separator()
    end
end
local function manual_entry(kind)
    U.manual_item=U.manual_item or {ench=0,price=1,qty=1}
    U.manual_name=U.manual_name or imgui.new.char[256]()
    local item=U.manual_item
    M.title('ДОБАВИТЬ ТОВАР ВРУЧНУЮ')
    M.text('Точное название как в игре. Рыночная база не требуется.')
    imgui.SetNextItemWidth(math.min(850,imgui.GetContentRegionAvail().x))
    imgui.InputTextWithHint('##manual_name',DSP.utf8('Название товара'),U.manual_name,256)
    M.number('Заточка, 0 = без заточки','manual_ench',item,'ench',0,300)
    M.number('Ваша цена за 1 шт. ($)','manual_price',item,'price',1,350)
    M.number('Количество','manual_qty',item,'qty',1,300)
    if M.button('Добавить в '..(kind=='buy' and 'скупку' or 'продажу'),'manual_add',480) then
        local draft={name=DSP.to_cp(ffi.string(U.manual_name)),enabled=true}
        for _,field in ipairs({{'ench',0},{'price',1},{'qty',1}}) do
            if not M.apply_number(draft,field[1],M.edit_buffer(item,field[1]),field[2]) then
                DSP.notify('Проверьте заточку, цену и количество'); return
            end
        end
        local ok,err=DSP.presets.add_manual(kind,draft)
        report(ok,err)
        if ok then U.trade_section='items'; ffi.fill(U.manual_name,256) end
    end
end
function U.trade_tab()
    local kind=U.preset_kind or 'buy'
    local p=kind=='buy' and DSP.settings.buy_preset or DSP.settings.sell_preset
    if M.button('СКУПКА','kind_buy',220,kind=='buy','segment') then U.preset_kind='buy' end
    M.inline()
    if M.button('ПРОДАЖА','kind_sell',220,kind=='sell','segment') then U.preset_kind='sell' end
    imgui.Separator()
    local running=DSP.auto.buy_running or DSP.auto.sell_running
    if DSP.presets.list then
        local list=DSP.presets.list(kind)
        local selected=DSP.presets.selected(kind)
        if M.button('<','preset_prev',70) and not running then
            DSP.presets.select(kind,selected>1 and selected-1 or #list)
        end
        M.inline()
        M.button(p.name or 'Мой набор','current_preset',320,false)
        M.inline()
        if M.button('>','preset_next',70) and not running then DSP.presets.select(kind,selected<#list and selected+1 or 1) end
    else M.title(p.name or 'Мой набор') end
    if not running then
        M.inline()
        if M.button('+ Товары','trade_add',220) then U.trade_advanced=true; U.trade_section='inventory' end
    end
    local action=running and 'ОСТАНОВИТЬ' or (U.trade_advanced and DSP.settings.dry_run and 'ПРОВЕРИТЬ' or 'ВЫСТАВИТЬ')
    if M.button(action,'run_'..kind,360,true,'primary') then
        if not running and not U.trade_advanced then DSP.settings.dry_run=false; DSP.save_settings() end
        if DSP.auto.buy_running then DSP.auto.stop_buy()
        elseif DSP.auto.sell_running then DSP.auto.stop_sell()
        elseif kind=='buy' then DSP.auto.start_buy() else DSP.auto.start_sell() end
    end
    if running then
        M.text(DSP.auto.status_text())
        if DSP.auto.progress then M.text(tostring(DSP.auto.progress.done or 0)..' / '..tostring(DSP.auto.progress.total or 0)) end
        return
    end
    if M.button(U.trade_advanced and 'Скрыть дополнительные' or 'Дополнительно','trade_advanced',380) then
        U.trade_advanced=not U.trade_advanced
        if not U.trade_advanced then U.trade_section='items' end
    end
    local section=U.trade_advanced and (U.trade_section or 'items') or 'items'
    if U.trade_advanced then
        for _,v in ipairs({{'items','Товары'},{'inventory','Инвентарь'},{'manual','Вручную'},{'library','Наборы / импорт'}}) do
            if M.button(v[2],'trade_section'..v[1],220,section==v[1]) then U.trade_section=v[1] end
            if v[1]~='library' then M.inline() end
        end
        M.toggle('Проверить без отправки',DSP.settings,'dry_run',true)
        if M.button('Обновить цены по рынку','recalc',400) then DSP.presets.recalc(kind); M.buffers=setmetatable({}, {__mode='k'}) end
    end
    imgui.Separator()
    if section=='library' then preset_library(kind,p)
    elseif section=='inventory' then inventory(kind)
    elseif section=='manual' then manual_entry(kind)
    else
        if #p.items==0 then
            M.text('Выберите свой набор или добавьте товары.')
            if M.button('Взять мои наборы из Market Helper','empty_import',650) then
                report(DSP.presets.import_mh()); U.trade_section='items'
            end
            if M.button('Добавить товары','empty_add',420) then U.trade_advanced=true; U.trade_section='inventory' end
        end
        for i,it in ipairs(p.items) do if item_card(kind,it,i) then break end end
    end
end
U.palatka_tab=U.trade_tab
function U.auto_tab()
    M.title('АВТОМАТИЗАЦИЯ')
    M.text(DSP.auto.status_text())
    M.text('Автоматизация выставляет товары. Счётчик показывает подтверждённые позиции, а не завершённые сделки.')
    if DSP.auto.progress then
        local p=DSP.auto.progress
        M.text('Обработано '..tostring(p.done or 0)..' из '..tostring(p.total or 0)..' | Ошибок '..tostring(p.failed or 0))
    end
    for _,kind in ipairs({'buy','sell'}) do
        local running=kind=='buy' and DSP.auto.buy_running or kind=='sell' and DSP.auto.sell_running
        local label=kind=='buy' and 'СКУПКИ' or 'ПРОДАЖИ'
        M.title(label)
        M.text('Позиций: '..DSP.presets.active_count(kind))
        if M.button((running and 'СТОП ' or 'СТАРТ ')..label,'auto_'..kind,400,running) then
            if kind=='buy' then
                if running then DSP.auto.stop_buy() else DSP.auto.start_buy() end
            else
                if running then DSP.auto.stop_sell() else DSP.auto.start_sell() end
            end
        end
    end
    M.toggle('Тест без отправки',DSP.settings,'dry_run',true)
    M.text('Последние события')
    for i=1,math.min(15,#DSP.log) do M.text((DSP.log[i].t or '')..' '..tostring(DSP.log[i].text)) end
end

end
__mod_37_mobile_trade()

local function __mod_38_mobile_market()
-- Market cards preserve buy/sell meaning and never truncate the item name.
local ffi=require('ffi')
local M=DSP.mobile
local U=DSP.ui
local function add(row,kind)
    local ok,err=DSP.presets.add(row,kind)
    DSP.notify(ok and 'Добавлено в набор' or tostring(err))
end
local function mark(o,id,label)
    if M.button(label..' #'..tostring(o.shop),id,330) then DSP.market.mark_shop(o.shop) end
end
local function offers(row,kind)
    local side=kind=='buy' and row.sell or row.buy
    M.title(kind=='buy' and 'КУПИТЬ СЕБЕ (лавка продаёт)' or 'ПРОДАТЬ СВОЁ (лавка скупает)')
    for i,o in ipairs(side.offers or {}) do
        M.text(DSP.money(o.price)..' x'..tostring(o.qty)..' | '..tostring(o.owner or '?'))
        local fresh=DSP.market.offer_freshness(o.ts)
        M.text('Свежесть: '..tostring(fresh))
        mark(o,'offer'..row.key..kind..i,'Найти лавку')
        imgui.Separator()
    end
    if #(side.offers or {})==0 then M.text('Предложений нет') end
end
function U.detail(row)
    M.title('КАРТОЧКА ТОВАРА')
    M.text(row.display)
    M.text(DSP.market.market_label_for(row) or '')
    if M.button('Добавить в мою скупку','detail_add_buy',400) then add(row,'buy') end
    M.inline()
    if M.button('Добавить в мою продажу','detail_add_sell',420) then add(row,'sell') end
    offers(row,'buy')
    offers(row,'sell')
end
function U.finder_tab()
    U.header()
    imgui.SetNextItemWidth(math.min(800,imgui.GetContentRegionAvail().x))
    if imgui.InputTextWithHint('##mobile_search',DSP.utf8('Название товара...'),U.finder_search_buf,128) then
        U.finder_query=DSP.to_cp(ffi.string(U.finder_search_buf)); DSP.screens.set_page('search',1)
    end
    if M.button('Очистить поиск','clear_search',300) then
        ffi.fill(U.finder_search_buf,128); U.finder_query=''; DSP.screens.set_page('search',1)
    end
    local matches=DSP.market.find_item(U.finder_query)
    M.text('Найдено товаров: '..#matches)
    if U.selected then
        local row=DSP.market.state.by_key[U.selected]
        if M.button('< К результатам','back_search',340) then U.selected=nil end
        if row then U.detail(row) end
        return
    end
    local first,last=DSP.screens.pager(#matches,6,'search')
    if #matches==0 then M.text('Введите название или обновите рынок. Источники могут временно не отвечать.') end
    for i=first,last do
        local row=matches[i]
        M.text(row.display)
        M.text('Купить себе: '..(row.sell.count>0 and DSP.money(row.sell.best) or 'нет продавцов')
            ..' | Продать своё: '..(row.buy.count>0 and DSP.money(row.buy.best) or 'нет скупщиков'))
        if M.button('Все предложения','open_item'..i,350) then U.selected=row.key end
        M.inline()
        if M.button('+ В скупку','search_buy'..i,260) then add(row,'buy') end
        M.inline()
        if M.button('+ В продажу','search_sell'..i,280) then add(row,'sell') end
        imgui.Separator()
    end
end
-- A touch-first arbitrage plan: stock, demand and allocated quantity stay distinct.
function U.arbitrage_tab()
    U.header()
    local f=DSP.settings.arb_filters or {}
    DSP.settings.arb_filters=f
    M.title('АРБИТРАЖ / ПЛАН СДЕЛОК')
    local state=DSP.market.state
    local tax=(tonumber(DSP.settings.tax_bp) or 200)/100
    M.text(string.format('Комиссия %.2f%% | Mobile %s | данные: %s',
        tax,tostring(state.sid),DSP.market.freshness()))
    if state.status=='cache' or state.status=='error' then
        imgui.TextColored(DSP.theme.col('warn',1),
            DSP.utf8('ВНИМАНИЕ: офлайн-база. Перед сделкой обновите рынок.'))
    else
        M.text('Остатки берутся из последнего снимка рынка. Перед сделкой проверьте лавку.')
    end
    local changed=false
    if M.button(U.arb_controls and 'Скрыть настройки' or 'Настроить бюджет и фильтры',
            'arb_controls',470,false,'primary') then U.arb_controls=not U.arb_controls end
    if U.arb_controls then
        M.title('ЛИМИТЫ')
        changed=M.number('Общий бюджет ($), 0 = без лимита','arb_budget',f,'budget',0,380) or changed
        changed=M.number('Макс. шт. на одну связку, 0 = всё','arb_maxqty',f,'max_qty',0,380) or changed
        changed=M.number('Минимальная прибыль на связку ($)','arb_profit',f,'min_profit',0,380) or changed
        changed=M.number('Минимальная доходность (%)','arb_roi',f,'min_roi',0,380) or changed
        changed=M.number('Возраст предложения (сек), 0 = любой','arb_age',f,'max_age',0,380) or changed
        changed=M.toggle('Покупать доступную часть партии',f,'allow_partial',true) or changed
        changed=M.toggle('Показывать предложения без времени',f,'include_unknown',true) or changed
        M.title('СОРТИРОВКА')
        for i,label in ipairs({'Общая прибыль','Прибыль / шт.','Доходность (%)'}) do
            if M.button(label,'arb_sort'..i,300,(tonumber(f.sort) or 1)==i) then
                f.sort=i; changed=true
            end
            if i<3 then M.inline() end
        end
        if changed then DSP.market.invalidate_arbitrage(); DSP.save_settings(); DSP.screens.set_page('arbitrage',1) end
    end
    local rows=DSP.market.arbitrage_filtered()
    local total_cost,total_profit,total_qty=0,0,0
    for _,e in ipairs(rows) do
        total_cost=total_cost+(e.total_cost or 0)
        total_profit=total_profit+(e.net_profit or 0)
        total_qty=total_qty+(e.tradable_qty or 0)
    end
    imgui.Separator()
    M.title('НАЙДЕНО: '..#rows..'  |  ОБЪЁМ: '..total_qty..' ШТ.')
    M.text('Общие затраты: '..DSP.money(total_cost))
    imgui.TextColored(DSP.theme.col('good',1),
        DSP.utf8('Чистая прибыль плана: +'..DSP.money(total_profit)))
    M.text('Объём каждого продавца и скупщика учитывается только один раз.')
    if (tonumber(f.budget) or 0)>0 then
        M.text('Лимит: '..DSP.money(f.budget)..' | Остаток: '..DSP.money(math.max(0,f.budget-total_cost)))
    end
    local first,last=DSP.screens.pager(#rows,6,'arbitrage')
    if #rows==0 then M.text('Сделок нет. Обновите рынок или ослабьте фильтры.') end
    for i=first,last do
        local e=rows[i]
        imgui.Separator()
        M.title(tostring(i)..'. '..tostring(e.name))
        imgui.TextColored(DSP.theme.col('good',1),
            DSP.utf8('ПРИБЫЛЬ  +'..DSP.money(e.net_profit or 0)..
                '     ROI  '..string.format('%.1f%%',e.roi or 0)))
        M.text('Купить '..tostring(e.tradable_qty or 0)..' шт. за '..DSP.money(e.total_cost or 0))
        M.text('Продаёт: '..tostring(e.qty_seller or e.sell_offer.qty or 0)..
            ' шт. / '..DSP.money(e.p_buy)..' за шт. | лавка #'..tostring(e.sell_offer.shop))
        M.text('Скупает: '..tostring(e.qty_buyer or e.buy_offer.qty or 0)..
            ' шт. / '..DSP.money(e.p_sell)..' за шт. | лавка #'..tostring(e.buy_offer.shop))
        M.text('Продавец: '..tostring(e.sell_offer.owner or '?')..
            ' | Скупщик: '..tostring(e.buy_offer.owner or '?'))
        if e.partial or e.shared_stock then
            imgui.TextColored(DSP.theme.col('warn',1),DSP.utf8(
                'Выделено '..tostring(e.tradable_qty)..' из '..tostring(e.available_qty or 0)..
                ' возможных шт. (лимит / другие сделки)'))
        end
        local gross=(e.tradable_qty or 0)*(e.p_sell or 0)
        M.text('Выручка: '..DSP.money(gross)..' | Комиссия: '..DSP.money(gross-(e.net_revenue or 0)))
        local a=DSP.market.offer_freshness(e.sell_age or e.sell_offer.ts)
        local b=DSP.market.offer_freshness(e.buy_age or e.buy_offer.ts)
        M.text('Обновление: продавец — '..tostring(a)..', скупщик — '..tostring(b))
        if M.button('1. Отметить лавку продавца #'..tostring(e.sell_offer.shop),
                'arb_sell'..i,540,false,'secondary') then
            DSP.market.mark_shop(e.sell_offer.shop)
        end
        if M.button('2. Отметить лавку скупщика #'..tostring(e.buy_offer.shop),
                'arb_buy'..i,540,false,'secondary') then
            DSP.market.mark_shop(e.buy_offer.shop)
        end
    end
end
U.market_tab=U.arbitrage_tab
-- Shop list uses a vertical card for each stall, then opens the full item search.
function U.lavki_tab()
    U.header()
    local shops=DSP.market.shops_list()
    local first,last=DSP.screens.pager(#shops,6,'lavki')
    if #shops==0 then M.text('Лавки не загружены. Обновите рынок.') end
    for i=first,last do
        local shop=shops[i]
        local number=shop.num or '?'
        M.title('ЛАВКА #'..tostring(number))
        M.text(shop.owner or '?')
        local fresh=DSP.market.offer_freshness(shop.ts or shop.updated_at)
        M.text('Свежесть: '..tostring(fresh))
        if M.button('Найти лавку #'..tostring(number),'shop_mark'..i,400) then DSP.market.mark_shop(number) end
        if (shop.buy_count or 0)>0 and M.button('Скопировать скупку +1$','copy_shop'..i,460) then
            local n,err=DSP.market.copy_shop_skupka(number,nil,1)
            DSP.notify(n and ('Скопировано позиций: '..n) or tostring(err))
        end
        local expanded=U.lavki_expanded[number]
        if M.button(expanded and 'Скрыть товары' or 'Показать товары','expand_shop'..i,400) then
            U.lavki_expanded[number]=not expanded
        end
        if expanded then
            for _,side in ipairs({'sell','buy'}) do
                M.title(side=='sell' and 'Продаёт вам:' or 'Скупает у вас:')
                for _,entry in ipairs(shop[side..'_offers'] or {}) do
                    local it=entry.offer
                    M.text(entry.row.display..' | '..DSP.money(it.price or 0)..' x'..tostring(it.qty or 0))
                end
            end
        end
        imgui.Separator()
    end
end

end
__mod_38_mobile_market()

local function __mod_39_mobile_history()
local ffi=require('ffi')
local M=DSP.mobile
local U=DSP.ui
local function date(ts) return os.date('%d.%m.%Y %H:%M:%S',tonumber(ts) or 0) end
M.history_revision={trades=0,stalls=0}
local history_cache={}
function M.history_rows(kind)
    local source=DSP.settings[kind] or {}
    local revision=M.history_revision[kind]
    local cached=history_cache[kind]
    if cached and cached.source==source and cached.revision==revision then return cached.rows end
    local rows={}
    for _,entry in pairs(source) do rows[#rows+1]=entry end
    table.sort(rows,function(a,b) return (a.ts or 0)>(b.ts or 0) end)
    history_cache[kind]={source=source,revision=revision,rows=rows}
    return rows
end
-- Invalidate only when events mutate logs; unchanged frames reuse sorted rows.
for name,kinds in pairs({record_trade={'trades'},stall_dropped={'stalls'},clear_trades={'trades','stalls'},load={'trades','stalls'}}) do
    local original=DSP.logs[name]
    if original then
        DSP.logs[name]=function(...)
            for _,kind in ipairs(kinds) do M.history_revision[kind]=M.history_revision[kind]+1 end
            return original(...)
        end
    end
end
function U.crate_log()
    if not DSP.rewards then M.text('История наград недоступна'); return end
    U.reward_filter=U.reward_filter or {search=''}
    U.reward_search=U.reward_search or imgui.new.char[256]()
    local filter=U.reward_filter
    imgui.SetNextItemWidth(math.min(700,imgui.GetContentRegionAvail().x))
    if imgui.InputTextWithHint('##reward_search',DSP.utf8('Найти предмет или источник'),U.reward_search,256) then
        filter.search=DSP.to_cp(ffi.string(U.reward_search)); DSP.screens.set_page('rewards',1)
    end
    U.reward_source=U.reward_source or imgui.new.char[256]()
    imgui.SetNextItemWidth(math.min(700,imgui.GetContentRegionAvail().x))
    if imgui.InputTextWithHint('##reward_source',DSP.utf8('Источник содержит (например: Vice City)'),U.reward_source,256) then
        filter.source_contains=DSP.to_cp(ffi.string(U.reward_source)); DSP.screens.set_page('rewards',1)
    end
    for _,period in ipairs({{0,'Все даты'},{86400,'24 часа'},{604800,'7 дней'}}) do
        if M.button(period[2],'reward_period'..period[1],260,(U.reward_period or 0)==period[1]) then
            U.reward_period=period[1]
            filter.from_ts=period[1]>0 and os.time()-period[1] or nil
            DSP.screens.set_page('rewards',1)
        end
        if period[1]~=604800 then M.inline() end
    end
    for _,pair in ipairs({{'all','Все'},{'item','Предметы'},{'cash','Деньги'},{'opening','Открытия'}}) do
        if M.button(pair[2],'reward_kind'..pair[1],220,(filter.kind or 'all')==pair[1]) then
            filter.kind=pair[1]~='all' and pair[1] or nil; DSP.screens.set_page('rewards',1)
        end
        if pair[1]~='opening' then M.inline() end
    end
    local summary=DSP.rewards.summary(filter)
    M.text('Открытий: '..tostring(summary.openings)..' | Предметов: '..tostring(summary.items)
        ..' | Деньги: '..DSP.money(summary.cash or 0))
    M.text('Рыночная оценка: '..DSP.money(summary.estimated_value or 0)
        ..' | Без цены: '..tostring(summary.unknown_items)..' записей')
    filter.page=DSP.screens.page_of('rewards'); filter.page_size=10
    local result=DSP.rewards.query(filter)
    local first=DSP.screens.pager(result.total or 0,10,'rewards')
    local current=math.floor((first-1)/10)+1
    if current~=filter.page then filter.page=current; result=DSP.rewards.query(filter) end
    if result.error then M.text('Ошибка истории: '..tostring(result.error)) end
    if (result.corrupt_lines or 0)>0 then M.text('Повреждённых строк: '..result.corrupt_lines) end
    if (result.total or 0)==0 then M.text('Наград пока нет. История пополняется из сообщений игрового чата.') end
    for _,e in ipairs(result.entries or {}) do
        M.title(date(e.ts)..' / '..tostring(e.source or 'Источник неизвестен'))
        if e.kind=='opening' then M.text('Открыт тайник / ларец')
        elseif e.kind=='cash' then M.text('Получено денег: '..DSP.money(e.cash or 0))
        else
            M.text(tostring(e.item_name or '?')..' x'..tostring(e.qty or 1)..((e.ench or 0)>0 and (' (+'..e.ench..')') or ''))
            if e.price_known then
                M.text('Оценка: '..DSP.money(e.estimated_value or 0)..' | За шт.: '..DSP.money(e.unit_price or 0))
                M.text('База: '..tostring(e.price_source or '?')..' | Метка цены: '..(e.price_ts and date(e.price_ts) or 'время неизвестно'))
            else M.text('Цена неизвестна. Оценка не включена в сумму.') end
        end
        if e.association=='inferred' then M.text('Источник определён по соседнему сообщению чата') end
        if e.association=='unknown' then M.text('Источник награды не определён') end
        M.text(e.raw or '')
        imgui.Separator()
    end
end
function U.log_tab()
    M.title('ИСТОРИЯ')
    for _,v in ipairs({{'crates','Награды / тайники'},{'trades','Сделки'},{'chat','Чат'}}) do
        if M.button(v[2],'history_'..v[1],330,U.tab_detail==v[1]) then U.tab_detail=v[1] end
        if v[1]~='chat' then M.inline() end
    end
    imgui.Separator()
    if U.tab_detail=='crates' then U.crate_log()
    elseif U.tab_detail=='chat' then
        local chat=DSP.settings.chat_logs or {}
        local first,last=DSP.screens.pager(#chat,12,'chat_history')
        for i=first,last do
            local e=chat[#chat-i+1]
            M.text(date(e.ts)..' | '..tostring(e.text or '')); imgui.Separator()
        end
    else
        local trades=M.history_rows('trades')
        M.title('СДЕЛКИ / '..#trades)
        local first,last=DSP.screens.pager(#trades,8,'trade_history')
        for i=first,last do
            local e=trades[i]
            M.title(date(e.ts)..' | '..tostring(e.partner or '?'))
            M.text(e.item_summary or '')
            M.text('Получено '..DSP.money(e.total_get or 0)..' | Отдано '..DSP.money(e.total_give or 0)
                ..' | Прибыль '..DSP.money(e.profit or 0)); imgui.Separator()
        end
        local stalls=M.history_rows('stalls')
        M.title('ЛАВКИ / '..#stalls)
        first,last=DSP.screens.pager(#stalls,8,'stall_history')
        for i=first,last do
            local e=stalls[i]
            M.text(date(e.ts)..' | Лавка #'..tostring(e.shop_num or '?')..' '..tostring(e.owner or '')..' '..tostring(e.action or ''))
        end
    end
end
local function save_notes()
    local f,err=io.open(DSP.notes_path,'w')
    if not f then DSP.notify('Не удалось сохранить заметки: '..tostring(err)); return false end
    local ok,write_err=f:write(ffi.string(U.notes_buf))
    local closed,close_err=f:close()
    if not ok or not closed then DSP.notify('Ошибка сохранения заметок: '..tostring(write_err or close_err)); return false end
    U._notes_dirty=false
    return true
end
M.save_notes=save_notes
function U.notes_tab()
    M.title('ЗАМЕТКИ')
    M.text(U._notes_dirty and 'Есть несохранённые изменения' or 'Сохранено')
    if M.button('Сохранить заметку','save_notes',340) then save_notes() end
    M.text('Ваш список закупок, планы и цены. Автосохранение после паузы во вводе.')
    local avail=imgui.GetContentRegionAvail()
    if imgui.InputTextMultiline('##mobile_notes',U.notes_buf,8192,imgui.ImVec2(avail.x,math.max(160,avail.y-20)),0) then
        U._notes_dirty=true; U._notes_last_edit=os.clock()
    end
end
-- Save before closing, including when an Android keyboard temporarily changes the viewport.
local set_open=U.set_open
function U.set_open(value)
    if not value and U._notes_dirty and U.notes_buf then M.save_notes() end
    set_open(value)
end
function U.settings_tab()
    M.title('НАСТРОЙКИ')
    U.settings_section=U.settings_section or 'appearance'
    for _,v in ipairs({{'appearance','Вид'},{'trade','Торговля'},{'data','Данные'},{'tools','Инструменты'}}) do
        if M.button(v[2],'settings_'..v[1],270,U.settings_section==v[1]) then U.settings_section=v[1] end
        if v[1]~='tools' then M.inline() end
    end
    imgui.Separator()
    local section=U.settings_section
    if section=='appearance' then
        M.text('Цветовая тема')
        for _,id in ipairs({'dark_amber','amoled','cyberpunk','purple','emerald'}) do
            local theme=DSP.theme.list[id]
            if M.button(theme.name,'theme_'..id,400,DSP.theme.current==id) then DSP.theme.set(id) end
        end
        M.text('Прозрачность')
        for _,v in ipairs({.8,.9,.97,1}) do
            if M.button(tostring(math.floor(v*100))..'%','opacity'..v,170,math.abs(DSP.theme.opacity-v)<.01) then DSP.theme.set_opacity(v) end
            if v~=1 then M.inline() end
        end
        M.text('Размер текста')
        for _,v in ipairs({1,1.25,1.5}) do
            if M.button(tostring(v),'scale'..v,180,M.scale()==v) then U.d=v; DSP.settings.dpi=v; DSP.save_settings() end
            if v~=1.5 then M.inline() end
        end
        M.toggle('Оценка трейда',DSP.settings,'overlay_trade',true)
        M.toggle('Оценка лавки',DSP.settings,'overlay_shop',true)
        M.toggle('Оверлей поверх окон',DSP.settings,'overlay_top',true)
        if DSP.settings.craglog then
            M.toggle('Показывать мини-журнал',DSP.settings.craglog,'open',false)
            if M.toggle('Закрепить мини-журнал',DSP.settings.craglog,'pinned',false) then
                if DSP.craglog and DSP.craglog.set_pinned then DSP.craglog.set_pinned(DSP.settings.craglog.pinned) end
            end
        end
    elseif section=='trade' then
        M.number('Комиссия в базисных пунктах (100 = 1%)','tax',DSP.settings,'tax_bp',0,300)
        M.number('Маржа скупки (%)','margin',DSP.settings,'margin',0,300)
        M.number('Снижение цены продажи (%)','undercut',DSP.settings,'undercut',0,300)
        M.number('Количество скупки по умолчанию','default_qty',DSP.settings,'auto_buy_qty',1,300)
        M.toggle('Тест выставления без отправки',DSP.settings,'dry_run',true)
        M.text('Проверьте комиссию вашего аккаунта: расчёт арбитража использует это значение.')
    elseif section=='data' then
        M.text('Сервер рынка')
        for _,server in ipairs(DSP.market.servers) do
            if M.button(server.name,'server'..server.id,400,DSP.market.state.sid==server.id) then
                DSP.market.state.sid=server.id; DSP.settings.server=server.id
                U.selected=nil; DSP.save_settings(); DSP.market.pull(server.id)
            end
        end
        M.number('Обновление рынка (сек)','refresh_seconds',DSP.settings,'refresh_seconds',30,300)
        M.toggle('Записывать награды и тайники',DSP.settings,'log_chat_drops',true)
        M.text('Скан рыночной метки ЦР: '..tostring(DSP.market.cr_scan_state.status or 'не сканирован'))
        if DSP.market.cr_scan_state.active then
            if M.button('Остановить скан ЦР','stop_cr',400) then
                DSP.market.cr_scan_state.active=false; DSP.market.cr_scan_state.status='остановлено'
            end
        elseif M.button('Сканировать метку ЦР','scan_cr',450) then DSP.market.scan_cr_marker() end
        M.text('Для скана подойдите к рыночной метке и откройте диалог цен.')
    else
        if M.button('Калькулятор сделки','calculator',430) then U.settings_tool='calculator' end
        M.inline()
        if M.button('Диагностика','diagnostics',360) then U.settings_tool='diagnostics' end
        if U.settings_tool=='calculator' then U.calculator_tab()
        else
            M.text('Версия '..tostring(DSP.version)..' | Данные: '..DSP.dir)
            M.text('Источник рынка: '..tostring(DSP.market.api))
            for i=1,math.min(20,#DSP.log) do M.text((DSP.log[i].t or '')..' '..tostring(DSP.log[i].text)) end
        end
    end
    imgui.Separator()
    if M.button('Сохранить настройки','save_settings',420) then DSP.save_settings(); DSP.save_ui_state(); DSP.notify('Настройки сохранены') end
end

end
__mod_39_mobile_history()

local function __mod_40_mobile_notes()
-- Separate notes remain searchable and retain optional market references.
local ffi=require('ffi')
local M=DSP.mobile
local U=DSP.ui
DSP.notes={}
local N=DSP.notes
local function save()
    if not DSP.save_settings() then
        U._notes_dirty=true
        DSP.notify('Не удалось сохранить заметки. Повторите сохранение.')
        return false
    end
    U._notes_dirty=false
    return true
end
function N.all()
    if type(DSP.settings.notes)~='table' then
        DSP.settings.notes={}
        local legacy=U.notes_buf and DSP.to_cp(ffi.string(U.notes_buf)) or ''
        if legacy~='' then
            DSP.settings.notes[1]={id='legacy',title='Мои заметки',text=legacy,pinned=false,updated_at=os.time()}
        end
        save()
    end
    return DSP.settings.notes
end
function N.filtered(query)
    local rows={}
    local q=DSP.lower(DSP.trim(query or ''))
    for _,note in ipairs(N.all()) do
        local text=table.concat({note.title or '',note.text or '',note.item or '',note.shop or ''},' ')
        if q=='' or DSP.lower(text):find(q,1,true) then rows[#rows+1]=note end
    end
    table.sort(rows,function(a,b)
        if (a.pinned and true or false)~=(b.pinned and true or false) then return a.pinned and true or false end
        if (a.updated_at or 0)~=(b.updated_at or 0) then return (a.updated_at or 0)>(b.updated_at or 0) end
        return tostring(a.id)<tostring(b.id)
    end)
    return rows
end
function N.create(title)
    local notes=N.all()
    local note={id=tostring(os.time())..'_'..tostring(#notes+1),title=title or 'Новая заметка',text='',updated_at=os.time()}
    notes[#notes+1]=note
    save()
    return note
end
local function buffer(value,size)
    local b=imgui.new.char[size]()
    local text=DSP.to_u8(value or '')
    ffi.copy(b,text,math.min(#text,size-1))
    return b
end
function N.open(note)
    if U._notes_dirty and not M.save_notes() then return false end
    U.note_current=note
    U.note_title=buffer(note.title,256)
    U.note_item=buffer(note.item,256)
    U.note_shop=buffer(note.shop,64)
    U.notes_buf=buffer(note.text,8192)
    U.note_delete=false
    return true
end
function M.save_notes()
    local note=U.note_current
    if note then
        note.title=DSP.to_cp(ffi.string(U.note_title))
        note.text=DSP.to_cp(ffi.string(U.notes_buf))
        note.item=DSP.to_cp(ffi.string(U.note_item))
        note.shop=DSP.to_cp(ffi.string(U.note_shop))
        note.updated_at=os.time()
    end
    return save()
end
local function changed()
    U._notes_dirty=true; U._notes_last_edit=os.clock()
end
function U.notes_tab()
    M.title('ЗАМЕТКИ')
    N.all()
    U.note_search=U.note_search or buffer('',256)
    if U.note_current then
        local note=U.note_current
        if M.button('< Все заметки','notes_back',300) then
            if M.save_notes() then U.note_current=nil end
        end
        M.inline()
        if M.button('Сохранить','notes_save',300) then M.save_notes() end
        M.text(U._notes_dirty and 'Есть несохранённые изменения' or 'Сохранено')
        M.text('Название')
        imgui.SetNextItemWidth(math.min(900,imgui.GetContentRegionAvail().x))
        if imgui.InputText('##note_title',U.note_title,256) then changed() end
        if M.toggle('Закрепить в начале списка',note,'pinned',false) then changed() end
        M.text('Предмет (необязательно)')
        imgui.SetNextItemWidth(600)
        if imgui.InputText('##note_item',U.note_item,256) then changed() end
        M.text('Номер лавки (необязательно)')
        imgui.SetNextItemWidth(300)
        if imgui.InputText('##note_shop',U.note_shop,64) then changed() end
        if note.shop and note.shop:match('^%d+$') and M.button('Найти лавку #'..note.shop,'note_mark',380) then DSP.market.mark_shop(note.shop) end
        M.text('Текст заметки')
        if imgui.InputTextMultiline('##mobile_note_text',U.notes_buf,8192,imgui.ImVec2(-1,280),0) then changed() end
        if M.button('Удалить заметку','note_delete',350) then U.note_delete=not U.note_delete end
        if U.note_delete then
            M.text('Удалить заметку безвозвратно?')
            if M.button('Да, удалить','note_delete_confirm',350) then
                for i,v in ipairs(N.all()) do if v==note then table.remove(DSP.settings.notes,i); break end end
                if save() then U.note_current=nil else DSP.settings.notes[#DSP.settings.notes+1]=note end
            end
        end
        return
    end
    imgui.SetNextItemWidth(math.min(850,imgui.GetContentRegionAvail().x))
    imgui.InputTextWithHint('##notes_search',DSP.utf8('Поиск по названию, тексту, предмету и лавке'),U.note_search,256)
    if M.button('+ Новая заметка','notes_create',400) then N.open(N.create()) end
    local notes=N.filtered(DSP.to_cp(ffi.string(U.note_search)))
    M.text('Заметок: '..#notes)
    for i,note in ipairs(notes) do
        M.text((note.pinned and '[*] ' or '')..tostring(note.title))
        if note.item and note.item~='' then M.text('Предмет: '..note.item) end
        if note.shop and note.shop~='' then M.text('Лавка #'..note.shop) end
        if M.button('Открыть','note_open'..i,300) then N.open(note) end
        imgui.Separator()
    end
end

end
__mod_40_mobile_notes()

local function __mod_39_trade_runtime()
-- Cooperative waits use elapsed scheduler time, not CPU time (os.clock).
DSP.trade_runtime = {}
local R = DSP.trade_runtime
local owners = setmetatable({}, {__mode = 'k'})
R.generation = 0
local main = {}
local function owner() return coroutine.running() or main end
function R.pause(ms)
    local generation = owners[owner()]
    wait(ms)
    if generation and generation ~= R.generation then error('trade_cancelled', 0) end
end
function R.cancel() R.generation = R.generation + 1 end
function R.spawn(kind, fn)
    R.generation = R.generation + 1
    local generation = R.generation
    DSP.auto.progress = {kind = kind, done = 0, total = 0, failed = 0, dry = 0}
    lua_thread.create(function()
        if generation ~= R.generation then return end
        owners[owner()] = generation
        local ok, err = pcall(fn)
        owners[owner()] = nil
        if generation == R.generation then
            DSP.auto[kind .. '_running'] = false
            if not ok then
                DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                DSP.auto.status = 'ошибка: ' .. tostring(err)
                if sampIsDialogActive() then
                    local closed, close_err = pcall(sampSendDialogResponse, sampGetCurrentDialogId(), 0, 0, '')
                    if not closed then DSP.add_log(tostring(close_err), 'error') end
                end
                DSP.add_log(DSP.auto.status, 'error')
            end
        end
    end)
end
function R.positive(n)
    n = tonumber(n)
    return n and n == n and n > 0 and n % 1 == 0 and n <= 9007199254740991
end
function R.matches(text, name)
    -- Require the entire item name; matching just the first word can list another item.
    local want = tostring(name)
    local start = 1
    while true do
        local a, b = tostring(text):find(want, start, true)
        if not a then return false end
        local before, after = text:sub(a - 1, a - 1), text:sub(b + 1, b + 1)
        local tail = text:sub(b + 1):match('^%s*(.-)%s*$')
        local field = tail == '' or tail:find('^Количество') or tail:find('^количество')
            or tail:find('^Цена') or tail:find('^цена') or tail:find('^quantity') or tail:find('^price')
        local suffix = after == '' or after:match('[:»".,\t\r\n]') or (after:match('%s') and field)
        if (a == 1 or before:match('[%s:«"\t]')) and
            suffix then return true end
        start = b + 1
    end
end

end
__mod_39_trade_runtime()

local function __mod_40_auto()
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

local runtime = DSP.trade_runtime
local function trade_wait(ms) runtime.pause(ms) end
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
    local t = DSP.lower and DSP.lower(text) or tostring(text):lower()
    return t:find('Количество', 1, true) ~= nil or t:find('количество', 1, true) ~= nil
        or t:find('кол-во', 1, true) ~= nil or t:find('кол во', 1, true) ~= nil
        or t:find('quantity', 1, true) ~= nil or t:find('%d+%s*,%s*%d+') ~= nil
end

local function close_dialog()
    if sampIsDialogActive() then
        sampSendDialogResponse(sampGetCurrentDialogId(), 0, 0, '')
        for _ = 1, 14 do
            if not sampIsDialogActive() then break end
            trade_wait(25)
        end
    end
end

local function wait_dialog(ids, ms)
    for _ = 1, math.ceil((ms or 2000) / 30) do
        trade_wait(30)
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
    local prev, stable = '', 0
    for _ = 1, math.ceil((ms or 800) / 30) do
        trade_wait(30)
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
    if DSP.auto.scanning or DSP.auto.buy_running or DSP.auto.sell_running then return false end
    DSP.auto.scanning = true
    DSP.auto.scan_generation = (DSP.auto.scan_generation or 0) + 1
    local generation = DSP.auto.scan_generation
    DSP.auto.inv = {}
    DSP.auto.inv_status = 'сканирование...'
    log('Инвентарь: открываю /mm...')
    sampSendChat('/mm')
    lua_thread.create(function()
        for _ = 1, 500 do
            if not DSP.auto.scanning or generation ~= DSP.auto.scan_generation then return end
            trade_wait(50)
        end
        if DSP.auto.scanning and generation == DSP.auto.scan_generation then
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
    -- v1.2 Stage 3 hotfix: CR marker scan (dialog 15073).
    -- When scan_cr_marker() has armed the scan state, intercept dialog 15073
    -- and let the market module parse + flip pages.
    if id == 15073 and DSP.market and DSP.market.cr_scan_state and DSP.market.cr_scan_state.active and DSP.market.on_cr_marker_dialog then
        pcall(DSP.market.on_cr_marker_dialog, text)
        return true  -- intercept: don't let other handlers close it
    end
    if DSP.auto.scanning then
        local generation = DSP.auto.scan_generation
        if id == 722 or id == 600 or id == 235 then
            lua_thread.create(function()
                trade_wait(120)
                if not DSP.auto.scanning or generation ~= DSP.auto.scan_generation then return end
                sampSendDialogResponse(id, 1, 0, '')
            end)
            return true
        end
        if inventory_dialog(id, text) then
            local items = parse_inventory(text)
            local slots = {}
            for _, old in ipairs(DSP.auto.inv) do
                for _, st in ipairs(old.stacks) do slots[st.slot] = true end
            end
            for _, it in ipairs(items) do
                local group
                for _, old in ipairs(DSP.auto.inv) do if old.name == it.name then group = old end end
                for _, st in ipairs(it.stacks) do
                    if not slots[st.slot] then
                        if not group then
                            group = {name = it.name, count = 0, stacks = {}}
                            table.insert(DSP.auto.inv, group)
                        end
                        group.count = group.count + st.count
                        table.insert(group.stacks, st)
                        slots[st.slot] = true
                    end
                end
            end
            DSP.auto.inv_status = #DSP.auto.inv .. ' поз. (' ..
                (function() local n = 0; for _, x in ipairs(DSP.auto.inv) do n = n + x.count end; return n end)() .. ' шт)'
            local next_idx
            local line_no = 0
            local header = style == 5 and 1 or 0
            for ln in tostring(text or ''):gmatch('[^\n]+') do
                line_no = line_no + 1
                if line_no > 1 and ln:find('Следующая страница', 1, true) then
                    next_idx = line_no - 1 - header
                    break
                end
            end
            if next_idx then
                log('Инвентарь: ' .. DSP.auto.inv_status .. ', дальше...')
                lua_thread.create(function()
                    trade_wait(140)
                    if not DSP.auto.scanning or generation ~= DSP.auto.scan_generation then return end
                    sampSendDialogResponse(id, 1, next_idx, '')
                end)
            else
                DSP.auto.scanning = false
                log('Инвентарь готов: ' .. DSP.auto.inv_status, 'ok')
                lua_thread.create(function()
                    trade_wait(100)
                    if generation ~= DSP.auto.scan_generation or DSP.auto.buy_running or DSP.auto.sell_running then return end
                    sampSendDialogResponse(id, 0, 0, '')
                    trade_wait(160)
                    if generation ~= DSP.auto.scan_generation or DSP.auto.buy_running or DSP.auto.sell_running then return end
                    _G.dsp_click_slot(52, -1, 4, '""')
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

DSP.auto.helpers = {close_dialog = close_dialog, wait_dialog = wait_dialog, wait_text = wait_text,
    clean = clean, base_name = base_name, has_qty = has_qty}

end
__mod_40_auto()

local function __mod_41_trade_listing()
-- Auto listing orchestration, separate from inventory and dialog observation.
local runtime = DSP.trade_runtime
local trade_wait = runtime.pause
local log = DSP.add_log
local h = DSP.auto.helpers
local close_dialog, wait_dialog, wait_text = h.close_dialog, h.wait_dialog, h.wait_text
local clean, base_name, has_qty = h.clean, h.base_name, h.has_qty
local function queue_sell()
    local queue = {}
    for _, p in ipairs(DSP.settings.sell_preset.items) do
        if p.enabled ~= false and runtime.positive(p.price) and runtime.positive(p.qty or 1) then
            local target = base_name(p.name)
            local left = tonumber(p.qty) or 1
            for _, inv in ipairs(DSP.auto.inv) do
                if inv.name == p.name or ((tonumber(p.ench) or 0) == 0 and inv.name == target) then
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
    local queue = queue_sell()
    if #queue == 0 then DSP.notify('Продажа: в инвентаре нет позиций из пресета'); return end
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
            local got, id = false, nil
            for attempt = 1, 3 do
                close_dialog()
                DSP.auto.sell_confirmed = false
                DSP.auto.sell_forbidden, DSP.auto.sell_no_slots = false, false
                _G.dsp_click_slot(60, -1, 2, json)
                -- v1.2 hotfix: also accept 15068-15071 (newer Arizona Mobile выставление dialogs).
                id = wait_dialog({ 26547, 15068, 15069, 15070, 15071 }, 1800)
                if id then
                    local txt = DSP.dialog_clean(wait_text(id, 700))
                    local base = base_name(it.base)
                    if runtime.matches(txt, it.name) then
                        got = true
                        break
                    end
                    log('Продажа: диалог не тот (' .. tostring(attempt) .. '): ' .. txt:sub(1, 60), 'error')
                    close_dialog()
                end
                trade_wait(180)
            end
            if got then
                local txt = DSP.dialog_clean(sampGetDialogText() or '')
                local resp = has_qty(txt) and (tostring(it.qty) .. ',' .. tostring(it.price))
                    or tostring(it.price)
                if not has_qty(txt) and it.qty > 1 then
                    error('Диалог не поддерживает количество: ' .. it.name)
                end
                if DSP.settings.dry_run then
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
                    sampSendDialogResponse(resp_id, 0, 0, '')
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
end

function DSP.auto.stop_sell()
    if not DSP.auto.sell_running then return false end
    runtime.cancel()
    DSP.auto.sell_running = false
    DSP.auto.status = 'продажа остановлена'
    close_dialog()
    log('Продажа остановлена')
end


end
__mod_41_trade_listing()

local function __mod_42_trade_buy()
-- Auto listing orchestration, separate from inventory and dialog observation.
local runtime = DSP.trade_runtime
local trade_wait = runtime.pause
local log = DSP.add_log
local h = DSP.auto.helpers
local close_dialog, wait_dialog, wait_text = h.close_dialog, h.wait_dialog, h.wait_text
local clean, base_name, has_qty = h.clean, h.base_name, h.has_qty
local function find_list_index(text, name)
    local idx = 0
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        local nm = clean(line):gsub('^%s*%d+[%.%)]%s*', ''):match('^%s*(.-)%s*$')
        nm = nm:match('^(.-)\t') or nm
        if nm == name then return idx end
        idx = idx + 1
    end
    return nil
end

local function open_shop_menu()
    close_dialog()
    _G.dsp_click_slot(8, 7, -1, '')
    -- v1.2 hotfix: accept 15072/15073 fallback for shop menu open in newer Arizona Mobile.
    return wait_dialog({ 3040, 15072 }, 2500)
end

local function buy_one(it, pi, total)
    DSP.auto.status = 'скупка: ' .. it.name .. ' (' .. pi .. '/' .. total .. ')'
    if not sampIsDialogActive() or sampGetCurrentDialogId() ~= 3040 then
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
    local idx = find_list_index(list_text, it.name)
    if not idx then
        log('Скупка: не найдено: ' .. it.name, 'error')
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
    wait_text(id, 500)
    local txt = DSP.dialog_clean(sampGetDialogText() or '')
    local base = base_name(it.name)
    if not runtime.matches(txt, it.name) then
        log('Скупка: в диалоге другой товар: ' .. it.name, 'error')
        close_dialog()
        return false
    end
    local qty = tonumber(it.qty) or 1
    if qty < 1 then qty = 1 end
    if not has_qty(txt) then qty = 1 end
    local resp = has_qty(txt) and (tostring(qty) .. ',' .. tostring(it.price))
        or tostring(it.price)
    if DSP.settings.dry_run then
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
        if it.enabled ~= false and runtime.positive(it.price) and runtime.positive(it.qty or 1) then table.insert(list, it) end
    end
    if #list == 0 then DSP.notify('Скупка: пресет пуст или цены 0'); return end
    DSP.auto.buy_running = true
    DSP.auto.status = 'скупка...'
    log('Скупка: ' .. #list .. ' позиций' .. (DSP.settings.dry_run and ' (dry-run)' or ''))
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
                result, units = buy_one(entry, pi, #list)
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
end

function DSP.auto.stop_buy()
    if not DSP.auto.buy_running then return false end
    runtime.cancel()
    DSP.auto.buy_running = false
    DSP.auto.status = 'скупка остановлена'
    close_dialog()
    log('Скупка остановлена')
end

end
__mod_42_trade_buy()

local function __mod_45_live()
-- Live game hooks: trade (iface 57) and lavka (iface 60/52) parsing.
DSP.live = DSP.live or {}
local L = DSP.live

L.trade = { partner = '', give = {}, get = {}, money_give = 0, money_get = 0,
            opened = 0, updated = 0, complete = false }
L.shop  = { owner = '', num = '', sell = {}, buy = {}, seen = {},
            opened = 0, updated = 0, items_updated = 0, menu_closed = 0 }

local function now()
    return os.time()
end

local function decode(raw)
    raw = tostring(raw or ''):gsub('%z+$', '')
    if raw == '' then return nil end
    local ok, d = pcall(decodeJson, raw)
    if ok and type(d) == 'table' then return d end
    return nil
end

function DSP.money_val(s)
    s = tostring(s or ''):gsub('{[%x]+}', ''):gsub('%s+', '')
    if s == '' then return 0 end
    local mult = 1
    local low = s:lower()
    if low:find('кк', 1, true) or low:find('kk', 1, true) then
        mult = 1000000
        s = s:gsub('[Кк]к', ''):gsub('[Kk]k', '')
    elseif low:find('кк', 1, true) == nil and (low:find('к', 1, true) or low:find('k', 1, true)) then
        mult = 1000
        s = s:gsub('[Кк]', ''):gsub('[Kk]', '')
    elseif low:find('м', 1, true) or low:find('m', 1, true) then
        mult = 1000000
        s = s:gsub('[Мм]', ''):gsub('[Mm]', '')
    end
    s = s:gsub('%$', ''):gsub('%.', ''):gsub(',', '.')
    local n = tonumber(s:match('(%d+%.?%d*)'))
    if not n then return 0 end
    return math.floor(n * mult)
end

local function strip(s)
    return DSP.clean_text(s or '')
end

local function name_ench(s)
    s = strip(s)
    local base, e = s:match('^(.-)%s*%((%d+)%)%s*$')
    if base and base ~= '' then return strip(base), tonumber(e) or 0 end
    return s, 0
end

function L.item_from_id(raw, ench, qty)
    local id, e = DSP.parse_item_id(raw, ench)
    if id <= 0 then return nil end
    local nm = DSP.items.name(id)
    if nm:find('^ID:') then return nil end
    return { name = nm, ench = e, qty = math.max(1, tonumber(qty) or 1), id = id }
end

function L.reset_trade(partner)
    L.trade = {
        partner = partner or '',
        give = {}, get = {},
        money_give = 0, money_get = 0,
        opened = now(), updated = now(),
        complete = false,
    }
    DSP.flog('TRADE reset partner=' .. tostring(partner or ''))
end

function L.reset_shop(owner, num)
    L.shop = {
        owner = owner or '', num = tostring(num or ''),
        sell = {}, buy = {}, seen = {},
        opened = now(), updated = now(), items_updated = 0, menu_closed = 0,
    }
    DSP.flog('SHOP reset owner=' .. tostring(owner or '') .. ' num=' .. tostring(num or ''))
end

function L.ensure_shop()
    if not L.shop or L.shop.updated == 0 then L.reset_shop('', '') end
    return L.shop
end

function L.merge_side(list, items, replace)
    if replace then
        for i = #list, 1, -1 do list[i] = nil end
    end
    local idx = {}
    for _, it in ipairs(list) do idx[it.id .. '|' .. tostring(it.ench or 0)] = it end
    for _, it in ipairs(items) do
        local k = it.id .. '|' .. tostring(it.ench or 0)
        local ex = idx[k]
        if ex then
            ex.qty = it.qty
        else
            list[#list + 1] = it
            idx[k] = it
        end
    end
end

function L.parse_trade_items(raw, kind)
    local items = {}
    for obj in tostring(raw or ''):gmatch('{([^}]+)}') do
        local item_raw = obj:match('"item"%s*:%s*"([^"]+)"') or obj:match('"item"%s*:%s*(%d+)')
        if item_raw then
            local ench = tonumber(obj:match('"enchant"%s*:%s*(%d+)')) or 0
            local qty = tonumber(obj:match('"amount"%s*:%s*(%d+)'))
                or tonumber(obj:match('"count"%s*:%s*(%d+)')) or 1
            local it = L.item_from_id(item_raw, ench, qty)
            if it then items[#items + 1] = it end
        end
    end
    return items
end

function L.handle_trade(sub, raw)
    local t = L.trade
    if sub == 0 then
        local d = decode(raw)
        local partner = d and (d.name or d.owner or d.nick) or raw:match('"name"%s*:%s*"([^"]+)"')
        partner = partner and strip(partner):match('^(.-)%s*%(%d+%)%s*$') or strip(partner or '')
        if partner == '' then partner = '?' end
        if t.partner ~= partner or now() - (t.updated or 0) > 300 then
            L.reset_trade(partner)
        else
            t.partner = partner
            t.updated = now()
        end
        return
    end
    if not t or t.opened == 0 then L.reset_trade(t and t.partner or '?') end
    t = L.trade
    if sub == 2 then
        local tp = tonumber(raw:match('"type"%s*:%s*(%d+)')) or 0
        local items = L.parse_trade_items(raw, tp)
        if tp == 3 then
            L.merge_side(t.give, items, true)
        elseif tp == 4 then
            L.merge_side(t.get, items, false)
        else
            return
        end
        t.updated = now()
        DSP.flog('TRADE sub2 type=' .. tostring(tp) .. ' n=' .. tostring(#items))
    elseif sub == 6 then
        local sg = tonumber(raw:match('"self"%s*:%s*{[^}]-"value"%s*:%s*(%d+)'))
        local tg = tonumber(raw:match('"target"%s*:%s*{[^}]-"value"%s*:%s*(%d+)'))
        if sg then t.money_give = sg end
        if tg then t.money_get = tg end
        t.updated = now()
        DSP.flog('TRADE sub6 give=' .. tostring(t.money_give) .. ' get=' .. tostring(t.money_get))
    elseif sub == 4 then
        local sc = tonumber(raw:match('"self"%s*:%s*{[^}]-"confirm"%s*:%s*(%d+)')) or 0
        local tc = tonumber(raw:match('"target"%s*:%s*{[^}]-"confirm"%s*:%s*(%d+)')) or 0
        local sa = tonumber(raw:match('"self"%s*:%s*{[^}]-"accept"%s*:%s*(%d+)')) or 0
        local ta = tonumber(raw:match('"target"%s*:%s*{[^}]-"accept"%s*:%s*(%d+)')) or 0
        if sa == 1 and ta == 1 and sc == 1 and tc == 1 then
            t.complete = true
            DSP.flog('TRADE complete partner=' .. tostring(t.partner))
            if DSP.logs and DSP.logs.record_trade then
                DSP.logs.record_trade(t.partner, t.give, t.get, t.money_give, t.money_get, 'accepted')
            end
        end
        t.updated = now()
    end
end

function L.parse_shop_item(obj, side)
    local s = L.ensure_shop()
    local item_raw = obj:match('"item"%s*:%s*"([^"]+)"') or obj:match('"item"%s*:%s*(%d+)')
    if not item_raw then return end
    local ench = tonumber(obj:match('"enchant"%s*:%s*(%d+)')) or 0
    local amount = tonumber(obj:match('"amount"%s*:%s*(%d+)')) or 0
    local text = obj:match('"text"%s*:%s*"([^"]*)"')
    local text_price = text and DSP.money_val(text) or 0
    local price = text_price > amount and text_price or amount
    if price <= 0 then return end
    local it = L.item_from_id(item_raw, ench, 1)
    if not it then return end
    local key = tostring(it.id) .. '|' .. tostring(price) .. '|' .. tostring(it.ench or 0)
    local list = side == 'sell' and s.sell or s.buy
    local ex = s.seen[key]
    if ex then
        ex.qty = ex.qty + 1
    else
        local e = { name = it.name, ench = it.ench, id = it.id, price = price, qty = 1 }
        s.seen[key] = e
        list[#list + 1] = e
    end
    DSP.db.learn(it.id, it.ench, price, side)
end

function L.handle_shop_items(raw)
    local tp = tonumber(raw:match('"type"%s*:%s*(%d+)')) or 0
    if tp ~= 13 and tp ~= 28 then return end
    local s = L.ensure_shop()
    local first_slot = tonumber(raw:match('"slot"%s*:%s*(%d+)'))
    local stale = now() - (s.items_updated or 0) > 10
    if first_slot == 0 and ((s.menu_closed or 0) > 0 or stale) then
        local keep_owner = now() - (s.updated or 0) <= 2 and s.owner or ''
        local keep_num = keep_owner ~= '' and s.num or ''
        L.reset_shop(keep_owner, keep_num)
        s = L.shop
    end
    s.updated = now()
    s.items_updated = s.updated
    if s.opened == 0 then s.opened = s.updated end
    s.menu_closed = 0
    local side = tp == 13 and 'sell' or 'buy'
    local n = 0
    for obj in tostring(raw or ''):gmatch('{([^}]+)}') do
        if obj:find('"item"', 1, true) then
            L.parse_shop_item(obj, side)
            n = n + 1
        end
    end
    if n > 0 then DSP.flog('SHOP items type=' .. tostring(tp) .. ' n=' .. tostring(n)) end
end

function L.handle_shop_owner(raw)
    local d = decode(raw)
    local owner = d and (d.name or d.owner or d.nick) or raw:match('"name"%s*:%s*"([^"]+)"')
    owner = strip(owner or '')
    owner = owner:match('%-%s*([%w_]+)') or owner:match('^([%w_]+)') or owner
    if owner == '' then return end
    local num = nil
    if d then num = d.shopNum or d.shopId or d.lavkaId or d.shop_num end
    num = num or raw:match('"shopNum"%s*:%s*(%d+)')
        or raw:match('"shopId"%s*:%s*(%d+)')
        or raw:match('"lavkaId"%s*:%s*(%d+)')
        or raw:match('"shopNum"%s*:%s*"(%d+)"')
        or raw:match('"shopId"%s*:%s*"(%d+)"')
        or raw:match('"lavkaId"%s*:%s*"(%d+)"')
    local s = L.shop
    if not s or s.updated == 0 or (s.owner ~= '' and s.owner ~= owner) then
        L.reset_shop(owner, num)
    else
        s.owner = owner
        s.num = tostring(num or s.num or '')
        s.updated = now()
        s.menu_closed = 0
    end
    DSP.flog('SHOP owner=' .. tostring(owner) .. ' num=' .. tostring(num or '?'))
    if DSP.logs and DSP.logs.stall_dropped then
        DSP.logs.stall_dropped(owner, num or '', 'opened', (s.sell and #s.sell) or 0)
    end
end

function L.handle(iface, sub, raw)
    if iface == 60 and sub == 1 then
        L.handle_shop_owner(raw)
    elseif iface == 52 and sub == 2 then
        L.handle_shop_items(raw)
    elseif iface == 57 then
        L.handle_trade(sub, raw)
    elseif iface == 60 and sub == 0 then
        local tp = tonumber(raw:match('"type"%s*:%s*(%d+)')) or 0
        if tp == 13 or tp == 28 then
            L.handle_shop_items(raw)
        end
    elseif iface == 8 and sub == 15 then
        local tp = tonumber(raw:match('"type"%s*:%s*(%d+)')) or 0
        local title = strip(raw:match('"title"%s*:%s*"([^"]*)"') or '')
        if tp == 3 and title:find('Мен', 1, true) then
            local s = L.ensure_shop()
            s.updated = now()
            if s.opened == 0 then s.opened = s.updated end
            s.menu_closed = 0
        end
    elseif iface == 255 then
        if L.shop then L.shop.menu_closed = now() end
    end
end

function L.read_json(bs)
    local len = raknetBitStreamReadInt16(bs)
    if not len or len <= 0 then return nil end
    local enc = raknetBitStreamReadInt8(bs) or 0
    if enc ~= 0 then
        return raknetBitStreamDecodeString(bs, len + enc)
    end
    return raknetBitStreamReadString(bs, len)
end

function L.on_receive(packet_id, bs)
    if packet_id ~= 220 then return end
    pcall(raknetBitStreamResetReadPointer, bs)
    local ok, err = pcall(function()
        raknetBitStreamIgnoreBits(bs, 8)
        local marker = raknetBitStreamReadInt8(bs)
        if marker ~= 84 then return end
        local iface = raknetBitStreamReadInt8(bs)
        local sub = raknetBitStreamReadInt8(bs)
        local raw = L.read_json(bs)
        if raw and raw ~= '' then L.handle(iface, sub, raw) end
    end)
    if not ok then DSP.flog('LIVE packet error: ' .. tostring(err)) end
    pcall(raknetBitStreamResetReadPointer, bs)
end

function L.parse_dialog_trade(title, text)
    local partner = strip(title or ''):match('Результат сделки с (.-)%s*$') or ''
    if partner == '' then return end
    local t = L.trade
    if not t or t.opened == 0 or t.partner ~= partner then L.reset_trade(partner) end
    t = L.trade
    local sec = ''
    local give, get = {}, {}
    -- v1.2 hotfix: Lua 5.5 forbids reassigning for-loop variables.
    -- Use a separate local `ln` instead of reassigning `line`.
    -- (LuaJIT 5.1 permits it but lupa's Lua 5.5 sandbox test enforces the rule.)
    for raw_line in tostring(text or ''):gsub('{[%x]+}', ''):gmatch('[^\r\n]+') do
        local line = strip(raw_line)
        if line:find('Перед', 1, true) then
            sec = 'give'
        elseif line:find('Получ', 1, true) then
            sec = 'get'
        elseif line:find('Комис', 1, true) then
            sec = ''
        elseif (sec == 'give' or sec == 'get') and line ~= '' and line ~= '-' then
            local money = DSP.money_val(line)
            local is_money = (line:find('%$') or line:lower():find('кк') or line:lower():find('kk')) and money > 0
            if is_money then
                if sec == 'give' then t.money_give = money else t.money_get = money end
            else
                local nm, qty = line:match('^(.-)%s*[xXхХ]%s*(%d+)%s*$')
                if not nm then nm, qty = line:match('^(.-)%s*%((%d+)%s*[^%)]*%)%s*$') end
                if not nm then nm, qty = line, '1' end
                local base, e = name_ench(nm)
                if base ~= '' then
                    local it = { name = base, ench = e, qty = tonumber(qty) or 1, id = 0 }
                    if sec == 'give' then give[#give + 1] = it else get[#get + 1] = it end
                end
            end
        end
    end
    if #give > 0 or #get > 0 or t.money_give > 0 or t.money_get > 0 then
        if #give > 0 then t.give = give end
        if #get > 0 then t.get = get end
        t.updated = now()
        DSP.flog('TRADE dialog partner=' .. partner .. ' give=' .. #give .. ' get=' .. #get
            .. ' money=' .. tostring(t.money_give) .. '/' .. tostring(t.money_get))
    end
end

function L.on_dialog(dialog_id, style, title, b1, b2, text)
    if dialog_id == 28148 then
        L.parse_dialog_trade(title, text)
        -- Also check for trade result in dialog text
        local txt = DSP.clean_text(text or '')
        if txt:find('сделка', 1, true) or txt:find('Обмен', 1, true) then
            local t = L.trade
            if t and t.give and t.get then
                local items_given, items_received = {}, {}
                for _, it in ipairs(t.give or {}) do
                    table.insert(items_given, { name = it.name, ench = it.ench, qty = it.qty })
                end
                for _, it in ipairs(t.get or {}) do
                    table.insert(items_received, { name = it.name, ench = it.ench, qty = it.qty })
                end
                if (#items_given > 0 or #items_received > 0 or t.money_give > 0 or t.money_get > 0) then
                    if not t._recorded then
                        t._recorded = true
                        if DSP.logs and DSP.logs.record_trade then
                            DSP.logs.record_trade(t.partner or '?', items_given, items_received,
                                t.money_give, t.money_get, 'accepted')
                        end
                    end
                end
            end
        end
    elseif dialog_id == 8248 then
        if L.trade then L.trade.updated = now() end
    end
end

function L.install()
    if L.installed then return end
    L.installed = true
    if addEventHandler then
        addEventHandler('onReceivePacket', L.on_receive)
        DSP.flog('LIVE receive hook installed')
    end
    local ok, sampev = pcall(require, 'samp.events')
    if ok and sampev then
        -- Chat message capture for item drops
        local prev_chat = sampev.onChatMessage
        sampev.onChatMessage = function(message, author, answer)
            if DSP.logs and DSP.logs.log_chat then
                DSP.logs.log_chat(message)
            end
            if prev_chat then return prev_chat(message, author, answer) end
        end
        local prev = sampev.onShowDialog
        sampev.onShowDialog = function(dialog_id, style, title, b1, b2, text)
            pcall(L.on_dialog, dialog_id, style, title, b1, b2, text)
            if prev then return prev(dialog_id, style, title, b1, b2, text) end
        end
        DSP.flog('LIVE dialog hook installed')
    end
end

function L.trade_age()
    if not L.trade or L.trade.updated == 0 then return 9999 end
    return now() - L.trade.updated
end

function L.shop_age()
    if not L.shop or L.shop.updated == 0 then return 9999 end
    return now() - L.shop.updated
end

-- =========================================================================
-- v1.2 Stage 3: PayDay detector + Telegram trigger.
--
-- Arizona RP sends a chat message at the start of every in-game hour
-- containing "PayDay" (or localized variant). When we see it, we:
--   1. Compute today's profit summary via DSP.logs.profit_summary('day')
--   2. Push a PayDay marker into the craglog ring buffer
--   3. Send a UTF-8 Telegram message with the day's stats
--   4. Throttle by remembering the last payday epoch (avoid dupes within
--      the same in-game hour)
-- =========================================================================

local PAYDAY_PATTERNS = {
    'PayDay',
    'ПэйДэй',
    'ПейДей',
    'вы получили зарплату',
    'Вам начислена заработная плата',
}

function L.check_payday_message(text)
    if not text or text == '' then return false end
    if not DSP.settings.tg_payday_enabled then return false end
    local s = DSP.lower(text)
    local hit = false
    for _, pat in ipairs(PAYDAY_PATTERNS) do
        if s:find(DSP.lower(pat), 1, true) then
            hit = true
            break
        end
    end
    if not hit then return false end
    -- Throttle: don't fire twice within the same real-world hour.
    local ts = os.time()
    if ts - (tonumber(DSP.settings.tg_payday_last) or 0) < 1800 then
        return false
    end
    DSP.settings.tg_payday_last = ts
    DSP.save_settings()
    -- Build daily summary
    local summary = DSP.logs.profit_summary('day')
    -- Push marker to craglog ring buffer + file
    if DSP.craglog and DSP.craglog.log_payday then
        pcall(DSP.craglog.log_payday, summary)
    end
    DSP.add_log(string.format('PayDay: %d сделок, %s%s',
        summary.count,
        summary.profit >= 0 and '+' or '',
        DSP.money(summary.profit)))
    -- Telegram notification (UTF-8 over HTTP)
    if DSP.settings.tg_notify and DSP.settings.tg_bot_token and DSP.settings.tg_chat_id then
        local msg = '[palatka ai] PayDay ' .. os.date('%H:%M') .. '\n'
            .. 'Сделок за день: ' .. summary.count .. '\n'
            .. 'Прибыль: ' .. (summary.profit >= 0 and '+' or '') .. DSP.money(summary.profit) .. '\n'
            .. 'Получено: ' .. DSP.money(summary.total_get) .. '\n'
            .. 'Отдано: ' .. DSP.money(summary.total_give) .. '\n'
            .. 'ROI: ' .. string.format('%.1f%%', summary.roi) .. '\n'
            .. 'Средняя сделка: ' .. DSP.money(summary.avg_profit)
        if DSP.logs and DSP.logs.send_telegram then
            pcall(DSP.logs.send_telegram, msg)
        end
    end
    return true
end

end
__mod_45_live()

local function __mod_50_overlay()
-- 50_overlay.lua
-- v1.2 overlay windows: trade eval + shop scan + crlog mini-window.
-- All colors now flow from DSP.theme so the overlay respects the active
-- theme + opacity slider.

DSP.overlay = DSP.overlay or {}
DSP.overlay.shop_tab = 1
DSP.overlay.trade_closed = 0
DSP.overlay.shop_closed = 0
DSP.overlay.focus_trade = 0
DSP.overlay.focus_shop = 0

if DSP.settings.overlay_shop == nil then DSP.settings.overlay_shop = true end
if DSP.settings.overlay_trade == nil then DSP.settings.overlay_trade = true end
if DSP.settings.overlay_top == nil then DSP.settings.overlay_top = true end

local function d()
    return tonumber(DSP.ui and DSP.ui.d) or tonumber(DSP.settings.dpi) or 1.25
end

local function col(r, g, b, a)
    return imgui.ImVec4(r, g, b, a or 1)
end

local function u(s)
    return DSP.utf8(s)
end

-- Theme-backed semantic colors (still cache locals for hot path speed).
local GREEN, YELLOW, RED, GRAY, BLUE
local function refresh_palette()
    GREEN  = DSP.theme.col('good', 1)
    YELLOW = DSP.theme.col('warn', 1)
    RED    = DSP.theme.col('bad',  1)
    GRAY   = DSP.theme.col('muted',1)
    BLUE   = DSP.theme.col('accent', 1)
end

local function base_label()
    local sid = tonumber(DSP.db.sid) or 0
    local cur = tonumber(DSP.market.state and DSP.market.state.sid) or 0
    local fresh = DSP.db.freshness()
    if sid > 0 and cur > 0 and sid ~= cur then
        return 'M' .. sid .. ' (текущий M' .. cur .. ')'
    end
    return sid > 0 and ('M' .. sid .. ' ' .. fresh) or fresh
end

local function item_price(it)
    local e = DSP.db.get(it.name, it.ench)
    if not e or not e.sell or not e.sell.min or e.sell.min <= 0 then return nil end
    return e.sell.min
end

function DSP.overlay.trade_sum()
    local t = DSP.live.trade
    local get_v, give_v, miss_get, miss_give = 0, 0, 0, 0
    for _, it in ipairs(t.get or {}) do
        local p = item_price(it)
        if p then get_v = get_v + p * (it.qty or 1) else miss_get = miss_get + 1 end
    end
    for _, it in ipairs(t.give or {}) do
        local p = item_price(it)
        if p then give_v = give_v + p * (it.qty or 1) else miss_give = miss_give + 1 end
    end
    local total_get = get_v + (t.money_get or 0)
    local total_give = give_v + (t.money_give or 0)
    local delta = total_get - total_give
    local pct = total_give > 0 and (delta / total_give * 100) or 0
    return total_get, total_give, delta, pct, miss_get, miss_give, get_v, give_v
end

function DSP.overlay.trade_ratio()
    local t = DSP.live.trade
    local _, _, _, _, _, _, get_v, give_v = DSP.overlay.trade_sum()
    local mg, mr = t.money_give or 0, t.money_get or 0
    if mr > 0 and mg == 0 and give_v > 0 then return mr / give_v, 'sale' end
    if mg > 0 and mr == 0 and get_v > 0 then return mg / get_v, 'buy' end
    local total_get = get_v + mr
    local total_give = give_v + mg
    if total_give > 0 then return total_get / total_give, 'swap' end
    return nil, 'none'
end

function DSP.overlay.show_trade()
    if DSP.settings.overlay_trade == false then return false end
    local t = DSP.live.trade
    if not t or (t.opened or 0) == 0 then return false end
    local age = DSP.live.trade_age()
    if t.complete and age > 60 then return false end
    if age > 600 then return false end
    if DSP.overlay.trade_closed == t.opened then return false end
    return (#(t.give or {}) > 0 or #(t.get or {}) > 0
        or (t.money_give or 0) > 0 or (t.money_get or 0) > 0)
end

function DSP.overlay.show_shop()
    if DSP.settings.overlay_shop == false then return false end
    local s = DSP.live.shop
    if not s or (s.opened or 0) == 0 then return false end
    if DSP.overlay.shop_closed == s.opened then return false end
    if (s.menu_closed or 0) > 0 then return false end
    if DSP.live.shop_age() > 300 then return false end
    return #(s.sell or {}) > 0 or #(s.buy or {}) > 0
end

local function close_btn(id)
    imgui.SameLine(0, 8 * d())
    if imgui.Button('X##' .. id, imgui.ImVec2(64, 56)) then return true end
    return false
end

local function trade_item_row(it, kind)
    local e = DSP.db.get(it.name, it.ench)
    local qty = it.qty or 1
    local disp = DSP.item_name(it.name, it.ench)
    if imgui.TextWrapped then imgui.TextWrapped(u(disp .. '  x' .. tostring(qty)))
    else imgui.Text(u(disp .. '  x' .. tostring(qty))) end
    if not e or not e.sell or not e.sell.min or e.sell.min <= 0 then
        imgui.TextColored(GRAY, u('нет базы'))
        return
    end
    local unit = e.sell.min
    local sum = unit * qty
    imgui.TextColored(BLUE, u(DSP.money(unit)))
    imgui.SameLine(0, 6 * d())
    imgui.TextColored(GRAY, u('=' .. DSP.money(sum)))
    if kind == 'get' then
        imgui.SameLine(0, 6 * d())
        imgui.TextDisabled(u('рынок ' .. DSP.money(e.sell.med or unit)))
    end
end

function DSP.overlay.draw_trade()
    refresh_palette()
    local t = DSP.live.trade
    local sw, sh = imgui.GetIO().DisplaySize.x, imgui.GetIO().DisplaySize.y
    local w = math.min(sw * 0.34, 640 * d())
    imgui.SetNextWindowPos(imgui.ImVec2(sw - 8 * d(), 76 * d()), imgui.Cond.FirstUseEver, imgui.ImVec2(1, 0))
    imgui.SetNextWindowSize(imgui.ImVec2(w, 0), imgui.Cond.FirstUseEver)
    if DSP.settings.overlay_top ~= false then imgui.SetNextWindowFocus() end
    imgui.SetNextWindowBgAlpha(DSP.theme.opacity)
    local ncol = DSP.theme.push_overlay(0.95)
    local open = imgui.new.bool(true)
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoSavedSettings
        + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoNav
    if imgui.Begin('##dsp_trade_overlay', open, flags) then
        imgui.TextColored(BLUE, u('ТРЕЙД  ' .. (t.partner ~= '' and t.partner or '?')))
        if close_btn('dsp_trade_close') then DSP.overlay.trade_closed = t.opened end
        imgui.SameLine(0, 12 * d())
        imgui.TextDisabled(u('база: ' .. base_label()))
        imgui.Separator()

        local total_get, total_give, delta, pct, miss_get, miss_give, get_v, give_v = DSP.overlay.trade_sum()
        local ratio, mode = DSP.overlay.trade_ratio()
        local vc, vt = YELLOW, 'НОРМ'
        if miss_get + miss_give > 0 and total_get == 0 and total_give == 0 then
            vc, vt = GRAY, 'НЕТ БАЗЫ'
        elseif miss_get + miss_give > 0 and total_get == 0 then
            vc, vt = GRAY, 'НЕТ ЦЕНЫ ПОЛУЧАЕМОГО'
        elseif ratio then
            if ratio >= 1.10 then vc, vt = GREEN, 'ВЫГОДНО'
            elseif ratio < 0.90 then vc, vt = RED, 'НЕВЫГОДНО' end
        end
        imgui.TextColored(vc, u(vt .. (ratio and string.format('  %.0f%% рынка', ratio * 100) or '')))
        imgui.Text(u('Получаете: ' .. DSP.money(total_get) .. '   Отдаёте: ' .. DSP.money(total_give)))
        imgui.TextColored(delta >= 0 and GREEN or RED,
            u('Итог: ' .. (delta >= 0 and '+' or '') .. DSP.money(delta) .. string.format('  (%+.0f%%)', pct)))
        if (t.money_get or 0) > 0 and (t.money_give or 0) == 0 and give_v > 0 then
            local r = (t.money_get or 0) / give_v
            local c, s
            if r < 0.85 then c, s = RED, 'СКУП НИЖЕ РЫНКА'
            elseif r <= 1.10 then c, s = YELLOW, 'НОРМ ЦЕНА'
            else c, s = GREEN, 'ОВЕР - ВЫГОДНО ВАМ' end
            imgui.TextColored(c, u(string.format('Скуп: %.0f%% рынка - %s', r * 100, s)))
        elseif (t.money_give or 0) > 0 and (t.money_get or 0) == 0 and get_v > 0 then
            local r = (t.money_give or 0) / get_v
            local c, s
            if r < 0.85 then c, s = GREEN, 'ДЕШЕВО - БРАТЬ'
            elseif r <= 1.10 then c, s = YELLOW, 'НОРМ ЦЕНА'
            else c, s = RED, 'ОВЕР - ПЕРЕПЛАТА' end
            imgui.TextColored(c, u(string.format('Покупка: %.0f%% рынка - %s', r * 100, s)))
        end
        imgui.Separator()

        local half = math.floor((w - 28 * d()) / 2)
        local h = math.min(230 * d(), sh * 0.38)
        imgui.BeginChild('##dsp_trade_give', imgui.ImVec2(half, h), true)
        imgui.TextColored(RED, u('ВЫ ОТДАЁТЕ'))
        for _, it in ipairs(t.give or {}) do trade_item_row(it, 'give') end
        if (t.money_give or 0) > 0 then imgui.TextColored(RED, u('Деньги: -' .. DSP.money(t.money_give))) end
        if #(t.give or {}) == 0 and (t.money_give or 0) == 0 then imgui.TextDisabled(u('—')) end
        imgui.EndChild()
        imgui.SameLine(0, 8 * d())
        imgui.BeginChild('##dsp_trade_get', imgui.ImVec2(half, h), true)
        imgui.TextColored(GREEN, u('ВЫ ПОЛУЧАЕТЕ'))
        for _, it in ipairs(t.get or {}) do trade_item_row(it, 'get') end
        if (t.money_get or 0) > 0 then imgui.TextColored(GREEN, u('Деньги: +' .. DSP.money(t.money_get))) end
        if #(t.get or {}) == 0 and (t.money_get or 0) == 0 then imgui.TextDisabled(u('—')) end
        imgui.EndChild()
        if miss_get + miss_give > 0 then
            imgui.TextColored(YELLOW, u('Нет базы: ' .. tostring(miss_get + miss_give) .. ' поз. - обнови рынок'))
        end
        if imgui.SmallButton(u('ОБНОВИТЬ БАЗУ##dsp_trade_refresh')) then
            DSP.market.pull(DSP.market.state.sid)
        end
    end
    imgui.End()
    imgui.PopStyleColor(ncol)
    if not open[0] then DSP.overlay.trade_closed = t.opened end
end

local function shop_verdict_sell(price, e)
    if not e or not e.sell or not e.sell.min or e.sell.min <= 0 then return GRAY, 'НЕТ БАЗЫ', 0 end
    local low = e.sell.min
    local p25 = e.sell.p25 or low
    local med = e.sell.med or low
    local pct = med > 0 and (price / med * 100) or 0
    if price <= low * 1.02 or (p25 > 0 and price <= p25) then return GREEN, 'ДЕШЕВО - БРАТЬ', pct end
    if price <= med * 1.05 then return YELLOW, 'НОРМ', pct end
    return RED, 'ОВЕР', pct
end

local function shop_verdict_buy(price, e)
    if not e or not e.sell or not e.sell.min or e.sell.min <= 0 then return GRAY, 'НЕТ БАЗЫ', 0 end
    local low = e.sell.min
    local med = e.sell.med or low
    local pct = med > 0 and (price / med * 100) or 0
    if price >= med then return GREEN, 'ВЫГОДНО СДАТЬ', pct end
    if price >= low then return YELLOW, 'НОРМ', pct end
    return RED, 'НИЖЕ РЫНКА', pct
end

function DSP.overlay.draw_shop()
    refresh_palette()
    local s = DSP.live.shop
    local sw, sh = imgui.GetIO().DisplaySize.x, imgui.GetIO().DisplaySize.y
    local w = math.min(sw * 0.34, 640 * d())
    imgui.SetNextWindowPos(imgui.ImVec2(sw - 8 * d(), 76 * d()), imgui.Cond.FirstUseEver, imgui.ImVec2(1, 0))
    imgui.SetNextWindowSize(imgui.ImVec2(w, 0), imgui.Cond.FirstUseEver)
    if DSP.settings.overlay_top ~= false then imgui.SetNextWindowFocus() end
    imgui.SetNextWindowBgAlpha(DSP.theme.opacity)
    local ncol = DSP.theme.push_overlay(0.85)
    local open = imgui.new.bool(true)
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoSavedSettings
        + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoNav
    if imgui.Begin('##dsp_shop_overlay', open, flags) then
        imgui.TextColored(GREEN, u('ЛАВКА  #' .. tostring(s.num or '?') .. '  ' .. tostring(s.owner or '?')))
        if close_btn('dsp_shop_close') then DSP.overlay.shop_closed = s.opened end
        imgui.SameLine(0, 12 * d())
        imgui.TextDisabled(u('база: ' .. base_label()))
        imgui.Separator()

        local sell_n, buy_n = #(s.sell or {}), #(s.buy or {})
        if imgui.Button(u('КУПИТЬ СЕБЕ (' .. sell_n .. ')##dsp_shop_sell'), imgui.ImVec2(290, 64)) then DSP.overlay.shop_tab = 1 end
        imgui.SameLine(0, 6 * d())
        if imgui.Button(u('ПРОДАТЬ СВОЁ (' .. buy_n .. ')##dsp_shop_buy'), imgui.ImVec2(290, 64)) then DSP.overlay.shop_tab = 2 end
        imgui.Separator()

        local rows = {}
        if DSP.overlay.shop_tab == 1 then
            for _, it in ipairs(s.sell or {}) do
                local e = DSP.db.get(it.name, it.ench)
                local c, label, pct = shop_verdict_sell(it.price, e)
                local profit = e and e.buy and e.buy.max and e.buy.max > 0 and (e.buy.max - it.price) or 0
                rows[#rows + 1] = { it = it, e = e, c = c, label = label, pct = pct,
                    profit = profit, side = 'sell' }
            end
        else
            for _, it in ipairs(s.buy or {}) do
                local e = DSP.db.get(it.name, it.ench)
                local c, label, pct = shop_verdict_buy(it.price, e)
                local profit = e and e.sell and e.sell.min and e.sell.min > 0 and (it.price - e.sell.min) or 0
                rows[#rows + 1] = { it = it, e = e, c = c, label = label, pct = pct,
                    profit = profit, side = 'buy' }
            end
        end
        table.sort(rows, function(a, b)
            local pa, pb = a.profit or 0, b.profit or 0
            if pa ~= pb then return pa > pb end
            return (a.pct or 0) < (b.pct or 0)
        end)

        local h = math.min(340 * d(), sh * 0.55)
        if imgui.BeginChild('##dsp_shop_list', imgui.ImVec2(-1, h), true) then
            if #rows == 0 then
                imgui.TextDisabled(u('  Нет товаров. Открой меню товаров лавки.'))
            end
            for _, r in ipairs(rows) do
                local it = r.it
                imgui.TextColored(r.c, u(r.label))
                local label = u(DSP.item_name(it.name, it.ench) .. '  x' .. tostring(it.qty or 1))
                if imgui.TextWrapped then imgui.TextWrapped(label) else imgui.Text(label) end
                imgui.TextColored(BLUE, u(DSP.money(it.price)))
                if r.e and r.e.sell and r.e.sell.min and r.e.sell.min > 0 then
                    imgui.SameLine(0, 6 * d())
                    imgui.TextDisabled(u('рынок ' .. DSP.money(r.e.sell.min)
                        .. '/' .. DSP.money(r.e.sell.med or r.e.sell.min)))
                    if r.profit and r.profit ~= 0 then
                        imgui.SameLine(0, 6 * d())
                        imgui.TextColored(r.profit > 0 and GREEN or RED,
                            u((r.profit > 0 and 'профит ' or 'минус ') .. DSP.money(math.abs(r.profit))))
                    end
                end
                imgui.Separator()
            end
        end
        imgui.EndChild()
        if imgui.SmallButton(u('ОБНОВИТЬ БАЗУ##dsp_shop_refresh')) then
            DSP.market.pull(DSP.market.state.sid)
        end
    end
    imgui.End()
    imgui.PopStyleColor(ncol)
    if not open[0] then DSP.overlay.shop_closed = s.opened end
end

function DSP.overlay.install()
    if DSP.overlay.installed then return end
    DSP.overlay.installed = true
    imgui.OnFrame(function()
        return DSP.overlay.show_trade() or DSP.overlay.show_shop()
    end, function()
        -- v1.2 hotfix: pcall so a bad imgui call doesn't crash the game.
        local ok, err = pcall(function()
            if DSP.overlay.show_trade() then DSP.overlay.draw_trade() end
            if DSP.overlay.show_shop() then DSP.overlay.draw_shop() end
        end)
        if not ok then
            if DSP and DSP.flog then
                DSP.flog('overlay frame error: ' .. tostring(err))
            end
        end
    end)
end

end
__mod_50_overlay()

local function __mod_55_craglog()
-- Bounded live journal; full rewards remain in rewards.jsonl.
DSP.craglog = {ring={},ring_cap=300,ring_head=1,ring_count=0,scroll=0}
local C=DSP.craglog
local function settings()
    DSP.settings.craglog=DSP.settings.craglog or {open=false,pinned=false,minimized=false,filter='all'}
    return DSP.settings.craglog
end
local function persist() return DSP.save_settings() end
function C.clear_ring()
    C.ring,C.ring_head,C.ring_count,C.scroll={},1,0,0
    C.counters={trades=0,sales=0,buys=0,crates=0,profit=0}
end
C.clear_ring()
function C.ring_push(entry)
    if type(entry)~='table' then return end
    C.ring[C.ring_head]=entry
    C.ring_head=C.ring_head%C.ring_cap+1
    C.ring_count=math.min(C.ring_count+1,C.ring_cap)
end
function C.ring_recent(n)
    n=math.max(0,math.min(C.ring_count,math.floor(tonumber(n) or C.ring_count)))
    local out={}
    for i=0,n-1 do out[#out+1]=C.ring[(C.ring_head-n+i-1)%C.ring_cap+1] end
    return out
end
local function category(e)
    if e.kind=='item' or e.kind=='opening' or e.kind=='cash' or e.type=='crate' then return 'loot' end
    if (tonumber(e.money_get) or 0)>0 and (tonumber(e.money_give) or 0)==0 then return 'sales' end
    if (tonumber(e.money_give) or 0)>0 and (tonumber(e.money_get) or 0)==0 then return 'buys' end
    return 'other'
end
function C.filtered(filter)
    local out={}
    for _,e in ipairs(C.ring_recent(C.ring_count)) do
        if filter=='all' or category(e)==filter then out[#out+1]=e end
    end
    return out
end
local function append(path,line)
    DSP.mkdir_p(DSP.dir..'/logs')
    local f,err=io.open(path,'a')
    if not f then C.last_error=err; DSP.add_log('Журнал: '..tostring(err),'error'); return false,err end
    local wrote,write_err=f:write(line..'\n')
    local closed,close_err=f:close()
    if not wrote or not closed then
        C.last_error=write_err or close_err; DSP.add_log('Журнал: '..tostring(C.last_error),'error')
        return false,C.last_error
    end
    C.last_error=nil
    return true
end
function C.describe(e)
    if e.kind=='item' or e.type=='crate' then
        local value=e.price_known and DSP.money(e.estimated_value or 0) or 'нет цены'
        local name=tostring(e.item_name or e.item or '?')
        if (tonumber(e.ench) or 0)>0 and not name:find('%(%+%d+%)$') then name=name..' (+'..e.ench..')' end
        return name..' x'..tostring(e.qty or e.count or 1)..' | Оценка: '..value
    elseif e.kind=='cash' then return 'Деньги: +'..DSP.money(e.cash or 0)
    elseif e.kind=='opening' then return 'Открытие: '..tostring(e.source or '?')
    elseif e.type=='payday' then return 'PayDay | Сделок: '..tostring(e.count or 0)..' | Итог: '..DSP.money(e.profit or 0) end
    local parts={}
    for _,side in ipairs({{'items_give','Отдано'},{'items_get','Получено'}}) do
        for _,it in ipairs(e[side[1]] or {}) do parts[#parts+1]=side[2]..': '..tostring(it.name)..' x'..tostring(it.qty or 1) end
    end
    return tostring(e.partner or '?')..' | '..(#parts>0 and table.concat(parts,'; ')..' | ' or '')..'Итог сделки: '..DSP.money(e.profit or 0)
end
function C.log_trade(e)
    if type(e)~='table' then return false,'нет записи' end
    C.ring_push(e); C.counters.trades=C.counters.trades+1
    C.counters.profit=C.counters.profit+(tonumber(e.profit) or 0)
    local key=category(e); if C.counters[key] then C.counters[key]=C.counters[key]+1 end
    return append(DSP.trades_log_path,os.date('%Y-%m-%d %H:%M:%S',e.ts or os.time())..' '..C.describe(e))
end
function C.log_crate(e)
    if type(e)~='table' then return false,'нет записи' end
    if e.id then
        for _,row in ipairs(C.ring_recent(C.ring_count)) do if row.id==e.id then return true end end
    end
    local row={type='crate',kind='item',ts=e.ts or os.time(),id=e.id,
        item_name=e.item_name or e.item,ench=e.ench,qty=e.qty or e.count or 1,source=e.source or e.crate_type,
        price_known=e.price_known or (tonumber(e.price) or 0)>0,unit_price=e.unit_price or e.price,
        estimated_value=e.estimated_value or ((tonumber(e.price) or 0)*(tonumber(e.qty or e.count) or 1))}
    C.ring_push(row); C.counters.crates=C.counters.crates+1
    return append(DSP.crates_log_path,os.date('%Y-%m-%d %H:%M:%S',row.ts)..' '..C.describe(row))
end
function C.log_payday(summary)
    summary=summary or {}
    local row={type='payday',kind='payday',ts=os.time(),profit=summary.profit or 0,count=summary.count or 0}
    C.ring_push(row)
    return append(DSP.trades_log_path,os.date('%Y-%m-%d %H:%M:%S',row.ts)..' '..C.describe(row))
end
function C.visible() return settings().open==true end
function C.toggle() local s=settings(); s.open=not s.open; persist() end
function C.set_pinned(value)
    local s=settings(); s.pinned=value==true
    if s.pinned then s.open=true end
    persist()
end
function C.set_minimized(value) settings().minimized=value==true; persist() end
function C.set_anchor(x,y)
    local s=settings(); s.x,s.y=tonumber(x) or 20,tonumber(y) or 120
    persist()
end
function C.drag(dx,dy)
    local s=settings(); if s.pinned then return false end
    local g=C.active_geometry
    s.x,s.y=(g and g.x or s.x or 24)+dx,(g and g.y or s.y or 120)+dy
    if g then s.x=math.max(8,math.min(s.x,g.max_x)); s.y=math.max(8,math.min(s.y,g.max_y)) end
    C.drag_dirty=true
    return true
end
function C.end_drag() if C.drag_dirty then persist(); C.drag_dirty=false end end
function C.geometry(sw,sh)
    local s=settings()
    local w=math.min(700,sw*.45)
    local expanded=math.min(620,sh*.69)
    -- Clamp against expanded dimensions in both modes so collapsing never jumps.
    local x=math.max(8,math.min(tonumber(s.x) or 24,sw-w-8))
    local y=math.max(8,math.min(tonumber(s.y) or 120,sh-expanded-8))
    return {x=x,y=y,w=w,h=s.minimized and 84 or expanded,touch=54,max_x=sw-w-8,max_y=sh-expanded-8}
end
if DSP.rewards and not DSP.rewards._mini_wrapped then
    local record=DSP.rewards.record
    DSP.rewards.record=function(row)
        local saved,err=record(row)
        if saved then
            if row.kind=='association' then
                local ids={}; for _,id in ipairs(row.item_ids or {}) do ids[id]=true end
                for _,entry in ipairs(C.ring_recent(C.ring_count)) do
                    if ids[entry.id] then
                        entry.source,entry.association,entry.opening_id=row.source,'inferred',row.opening_id
                    end
                end
            elseif not row.legacy_id then
                local copy={}; for k,v in pairs(row) do copy[k]=v end
                C.ring_push(copy)
            end
        end
        return saved,err
    end
    DSP.rewards._mini_wrapped=true
end
function C.install()
    if C.installed then return end
    C.installed=true
    if DSP.rewards and DSP.rewards.query then
        local result=DSP.rewards.query({page_size=80})
        for i=#result.entries,1,-1 do C.ring_push(result.entries[i]) end
    end
    if sampRegisterChatCommand then sampRegisterChatCommand('crlog',C.toggle) end
    imgui.OnFrame(C.visible,function()
        local ok,err=pcall(C.draw)
        if not ok then
            C.last_error=tostring(err); DSP.flog('mini journal: '..tostring(err))
            settings().open=false; persist()
        end
    end)
end
return true

end
__mod_55_craglog()

local function __mod_56_mini_journal()
-- Phone journal: one stable anchor, fixed controls, and readable event cards.
local C=DSP.craglog
local function cp(s) return DSP.utf8(tostring(s or '')) end
local function text(s) imgui.TextWrapped(cp(s)) end
local function button(label,id,w,active)
    if active then imgui.PushStyleColor(imgui.Col.Button,DSP.theme.col('accent',.7)) end
    local hit=imgui.Button(cp(label)..'##mini_'..id,imgui.ImVec2(w,54))
    if active then imgui.PopStyleColor(1) end
    return hit
end
local function inline() imgui.SameLine(0,8) end
local function state() return DSP.settings.craglog end
local function header(g)
    local s=state()
    local handle=s.pinned and 'ЖУРНАЛ / ЗАКРЕПЛЁН' or 'ЖУРНАЛ / ПЕРЕТАЩИТЬ'
    button(handle,'handle',g.w-300,false)
    if not s.pinned and imgui.IsItemActive() and imgui.IsMouseDragging(0) then
        local delta=imgui.GetIO().MouseDelta
        C.drag(delta.x,delta.y)
    end
    if not imgui.IsMouseDown(0) then C.end_drag() end
    inline()
    if button(s.pinned and 'PIN: ДА' or 'PIN: НЕТ','pin',120,s.pinned) then C.set_pinned(not s.pinned) end
    inline()
    if button(s.minimized and '+' or '-','collapse',60) then C.set_minimized(not s.minimized) end
    inline()
    if button('X','close',60) then s.open=false; DSP.save_settings() end
end
local function filters(g)
    local s=state()
    for i,pair in ipairs({{'all','Все'},{'sales','Продажи'},{'buys','Скупка'},{'loot','Награды'}}) do
        if button(pair[2],'filter_'..pair[1],(g.w-52)/4,s.filter==pair[1]) then
            s.filter=pair[1]; C.scroll=0; DSP.save_settings()
        end
        if i<4 then inline() end
    end
end
local function row_card(entry)
    local kind=entry.kind or entry.type
    local tag=kind=='item' and 'НАГРАДА' or kind=='cash' and 'ДЕНЬГИ' or kind=='opening' and 'ТАЙНИК'
        or entry.type=='payday' and 'PAYDAY' or 'СДЕЛКА'
    imgui.TextColored(DSP.theme.col('accent',1),cp(os.date('%H:%M:%S',entry.ts or 0)..'  '..tag))
    text(C.describe(entry))
    if entry.source then
        text('Источник: '..entry.source..(entry.association=='inferred' and ' (по чату)' or ''))
    end
    imgui.Separator()
end
function C.draw()
    local io=imgui.GetIO()
    local g=C.geometry(io.DisplaySize.x,io.DisplaySize.y)
    local s=state()
    C.active_geometry=g
    imgui.SetNextWindowPos(imgui.ImVec2(g.x,g.y),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(g.w,g.h),imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(.96)
    local colors=DSP.theme.push_overlay(.98)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,16)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,9)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(12,12))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing,imgui.ImVec2(8,8))
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+imgui.WindowFlags.NoMove
        +imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoFocusOnAppearing
    if imgui.Begin('##palatka_mini_journal',nil,flags) then
        if imgui.SetWindowFontScale then imgui.SetWindowFontScale(1.15) end
        header(g)
        if not s.minimized then
            filters(g)
            local events=C.filtered(s.filter or 'all')
            local per=3
            C.scroll=math.max(0,math.min(C.scroll,math.max(0,#events-per)))
            local start=#events-C.scroll
            text('Последние события: '..#events..' / '..C.ring_cap..'   |   PIN фиксирует положение')
            if button('ВВЕРХ / НОВЕЕ','up',(g.w-40)/2,C.scroll>0) then C.scroll=math.max(0,C.scroll-per) end
            inline()
            if button('ВНИЗ / СТАРШЕ','down',(g.w-40)/2,start>per) then C.scroll=math.min(math.max(0,#events-per),C.scroll+per) end
            start=#events-C.scroll
            local shown=imgui.BeginChild('##mini_cards',imgui.ImVec2(0,0),false)
            if shown then
                if #events==0 then
                    text('Здесь появятся сделки, деньги и награды из игрового чата.')
                    text('Полная история доступна в главном меню.')
                end
                for i=start,math.max(1,start-per+1),-1 do if events[i] then row_card(events[i]) end end
                if C.last_error then text('Ошибка записи: '..C.last_error) end
            end
            imgui.EndChild()
        end
    end
    imgui.End()
    imgui.PopStyleVar(4)
    if colors and colors>0 then imgui.PopStyleColor(colors) end
end
return true

end
__mod_56_mini_journal()

local function __mod_99_main()
-- Main entry: catalog, price base, market, UI, screens, live hooks, craglog, overlay.
-- v1.2 hotfix (safe-mode): pcall around all install() calls so a
-- single failing module can't crash the whole game. Each install() error is
-- logged via DSP.flog (standalone.log) but doesn't kill the script.
--
-- v1.2 hotfix #2: REMOVED jit.off(true). Disabling JIT globally killed
-- string ops and loops 10-15x. With mimgui FFI now safely pcall-wrapped,
-- JIT can stay on. Performance: <1ms per arbitrage frame (cache hit).
if not imgui then
    local ok, m = pcall(require, 'mimgui')
    if ok then imgui = m end
end

-- Helper: run a function, log error, never throw.
local function safe(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        if DSP and DSP.flog then
            DSP.flog('INSTALL ERROR [' .. label .. ']: ' .. tostring(err))
        end
    end
    return ok
end

safe('items.load',   function() DSP.items.load() end)
safe('db.load',      function() DSP.db.load() end)
safe('logs.load',   function() DSP.logs.load() end)
safe('market.load', function() DSP.market.load() end)
safe('auto.install', function() DSP.auto.install() end)
safe('ui.install',   function() DSP.ui.install() end)
safe('screens.install', function()
    if DSP.screens and DSP.screens.install then DSP.screens.install() end
end)
safe('live.install',  function() DSP.live.install() end)
safe('overlay.install', function() DSP.overlay.install() end)
safe('logs.install',  function() DSP.logs.install() end)

-- Startup broadcast: visible notification in SAMP chat and MonetLoader log
local function broadcast_version()
    local msg = '[palatka ai v' .. tostring(DSP.version) .. '] loaded'
    msg = msg .. ' | lua:' .. (jit and jit.version or 'unknown')
    if imgui then msg = msg .. ' | imgui:OK' else msg = msg .. ' | imgui:MISSING' end
    if DSP and DSP.notify then
        pcall(DSP.notify, msg .. ': /crr')
    end
    if DSP and DSP.flog then
        pcall(DSP.flog, '--- BROADCAST ' .. msg .. ' ---')
    end
    if sampAddChatMessage then
        pcall(sampAddChatMessage, '{FFAA00}[palatka ai] {FFFFFF}v' .. tostring(DSP.version) .. ' {00FF00}активирован{FFFFFF}. Открыть: {FFAA00}/crr', 0xFFAA00)
    end
end
safe('broadcast_version', broadcast_version)

-- Background market refresh thread. Wrapped in pcall so the coroutine
-- never throws into the scheduler (which would crash the game on some
-- MonetLoader builds).
if lua_thread and wait and DSP.detect_server then
    safe('market.refresh_thread', function()
        lua_thread.create(function()
            while true do
                wait(10000)
                local ok, err = pcall(function()
                    local sid = DSP.detect_server()
                    local nick = DSP.player_nick()
                    local nick_changed = nick ~= 'DsPic' and nick ~= (DSP.market.state.nick or '')
                    if DSP.market.state.status ~= 'loading'
                        and ((sid and sid ~= (DSP.market.state.sid or 0)) or nick_changed
                            or (DSP.market.should_refresh and DSP.market.should_refresh(os.time()))) then
                        sid = sid or DSP.market.state.sid
                        DSP.flog('MARKET refresh sid=' .. tostring(sid) .. ' nick=' .. tostring(nick))
                        DSP.market.pull(sid)
                    end
                end)
                if not ok then
                    DSP.flog('market.refresh error: ' .. tostring(err))
                end
            end
        end)
    end)
end

end
__mod_99_main()

