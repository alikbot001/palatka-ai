-- 55_craglog.lua
-- v1.2 Stage 3: autonomous mini-window for trade log + 60 FPS ring buffer.
--
-- Architecture:
--   * Ring buffer of 300 most recent trades in RAM (no scanning of disk
--     files on each frame -> 0 freezes even when all_trades.log is GB).
--   * Append-only file writer for long-term persistence; the file handle
--     stays open for the script lifetime, writes are flushed immediately
--     so a game crash mid-session still leaves a clean partial log.
--   * Mini-window works INDEPENDENTLY of DSP.ui.open (the main UI):
--       /crlog toggles visibility
--       collapsed mode shows just a thin status bar
--       [PIN] prevents accidental collapse
--       filters [All] [Sales] [Buys]
--
-- Trades/crates/stalls are pushed here from 05_trades.lua::record_trade,
-- crate_opened, stall_dropped, plus 45_live.lua's PayDay hook. The legacy
-- DSP.logs.log_chat / DSP.db.save_trades flow stays untouched for back-compat.

DSP.craglog = DSP.craglog or {}

-- Ring buffer state
DSP.craglog.ring = {}
DSP.craglog.ring_cap = 300
DSP.craglog.ring_head = 1     -- next write index (1..cap)
DSP.craglog.ring_count = 0    -- actual entries (capped at ring_cap)

-- Live counters for the mini-window header (reset only on script reload)
DSP.craglog.counters = {
    trades = 0,
    sales = 0,
    buys = 0,
    crates = 0,
    profit = 0,
}

-- File handle stays open for script lifetime; flushed on each write
DSP.craglog.file = nil
DSP.craglog.crates_file = nil

local function ensure_log_dir()
    DSP.mkdir_p(DSP.dir .. '/logs')
end

local function open_files()
    if not DSP.craglog.file then
        ensure_log_dir()
        DSP.craglog.file = io.open(DSP.trades_log_path, 'a')
    end
    if not DSP.craglog.crates_file then
        ensure_log_dir()
        DSP.craglog.crates_file = io.open(DSP.crates_log_path, 'a')
    end
end

-- Append one line to all_trades.log. Never blocks: io.write is buffered by
-- the OS; we explicitly flush so a crash preserves the last line.
local function file_append_trade(line)
    open_files()
    if not DSP.craglog.file then return end
    pcall(function()
        DSP.craglog.file:write(line)
        DSP.craglog.file:flush()
    end)
end

local function file_append_crate(line)
    open_files()
    if not DSP.craglog.crates_file then return end
    pcall(function()
        DSP.craglog.crates_file:write(line)
        DSP.craglog.crates_file:flush()
    end)
end

-- Ring buffer push. O(1) -- no table.remove shifting.
function DSP.craglog.ring_push(entry)
    if not entry or type(entry) ~= 'table' then return end
    DSP.craglog.ring[DSP.craglog.ring_head] = entry
    DSP.craglog.ring_head = DSP.craglog.ring_head + 1
    if DSP.craglog.ring_head > DSP.craglog.ring_cap then
        DSP.craglog.ring_head = 1
    end
    if DSP.craglog.ring_count < DSP.craglog.ring_cap then
        DSP.craglog.ring_count = DSP.craglog.ring_count + 1
    end
end

-- Read up to `n` most recent entries, oldest first.
-- O(n) -- only walks the requested slice, no table.remove.
function DSP.craglog.ring_recent(n)
    local cap = DSP.craglog.ring_cap
    local cnt = DSP.craglog.ring_count
    if cnt == 0 then return {} end
    if n > cnt then n = cnt end
    -- The oldest entry is at (head - cnt - 1) mod cap + 1
    local start = DSP.craglog.ring_head - cnt
    if start < 1 then start = start + cap end
    local out = {}
    for i = 0, n - 1 do
        local idx = ((start - 1 + i) % cap) + 1
        out[#out + 1] = DSP.craglog.ring[idx]
    end
    return out
end

-- Convert an internal trade entry to a one-line log string + update counters.
local function trade_to_line(e)
    local ts = os.date('%Y-%m-%d %H:%M:%S', e.ts or 0)
    local kind = e.kind or e.type or 'trade'
    local partner = tostring(e.partner or '?')
    local profit = tonumber(e.profit) or 0
    local sign = profit >= 0 and '+' or ''
    return string.format('[%s] [%s] %s partner=%s profit=%s%s total_get=%s total_give=%s\n',
        ts, string.upper(kind), kind, partner, sign, DSP.money(profit),
        DSP.money(e.total_get or 0), DSP.money(e.total_give or 0))
end

local function crate_to_line(e)
    local ts = os.date('%Y-%m-%d %H:%M:%S', e.ts or 0)
    local item = tostring(e.item or e.item_name or '?')
    local qty = tonumber(e.qty or e.count) or 1
    local source = tostring(e.source or e.crate_type or '?')
    return string.format('[%s] [CRATE] source=%s item=%s qty=%d\n',
        ts, source, item, qty)
end

-- Public API: push a trade entry into the ring buffer + file.
-- Called from DSP.logs.record_trade in 05_trades.lua.
function DSP.craglog.log_trade(entry)
    if not entry or type(entry) ~= 'table' then return end
    DSP.craglog.ring_push(entry)
    DSP.craglog.counters.trades = DSP.craglog.counters.trades + 1
    local profit = tonumber(entry.profit) or 0
    DSP.craglog.counters.profit = DSP.craglog.counters.profit + profit
    -- classify sale vs buy: if player received money and gave items -> sale;
    -- if player gave money and received items -> buy. Heuristic.
    local money_get = tonumber(entry.money_get or 0)
    local money_give = tonumber(entry.money_give or 0)
    if money_get > 0 and money_give == 0 then
        DSP.craglog.counters.sales = DSP.craglog.counters.sales + 1
    elseif money_give > 0 and money_get == 0 then
        DSP.craglog.counters.buys = DSP.craglog.counters.buys + 1
    elseif (entry.items_get and #entry.items_get > 0) and
           (not entry.items_give or #entry.items_give == 0) then
        DSP.craglog.counters.buys = DSP.craglog.counters.buys + 1
    else
        DSP.craglog.counters.sales = DSP.craglog.counters.sales + 1
    end
    file_append_trade(trade_to_line(entry))
end

-- Push a crate drop entry. Called from DSP.logs.crate_opened.
function DSP.craglog.log_crate(entry)
    if not entry or type(entry) ~= 'table' then return end
    DSP.craglog.ring_push({
        type = 'crate',
        kind = 'crate',
        ts = entry.ts or os.time(),
        source = entry.crate_type or entry.source or 'тайник',
        item = entry.item or entry.item_name or '?',
        qty = entry.qty or entry.count or 1,
    })
    DSP.craglog.counters.crates = DSP.craglog.counters.crates + 1
    file_append_crate(crate_to_line(entry))
end

-- Push a PayDay snapshot. Visible in the mini-window as a marker row.
function DSP.craglog.log_payday(summary)
    summary = summary or {}
    local entry = {
        type = 'payday',
        kind = 'payday',
        ts = os.time(),
        profit = tonumber(summary.profit) or 0,
        total_get = tonumber(summary.total_get) or 0,
        total_give = tonumber(summary.total_give) or 0,
        count = tonumber(summary.count) or 0,
    }
    DSP.craglog.ring_push(entry)
    file_append_trade(string.format('[%s] [PAYDAY] count=%d profit=%s\n',
        os.date('%Y-%m-%d %H:%M:%S', entry.ts), entry.count,
        DSP.money(entry.profit)))
end

function DSP.craglog.clear_ring()
    DSP.craglog.ring = {}
    DSP.craglog.ring_head = 1
    DSP.craglog.ring_count = 0
    DSP.craglog.counters = { trades = 0, sales = 0, buys = 0, crates = 0, profit = 0 }
end

-- =========================================================================
-- Mini-window rendering.
-- =========================================================================
local function d()
    return tonumber(DSP.ui and DSP.ui.d) or tonumber(DSP.settings.dpi) or 1.25
end

-- Header line for collapsed mode: "Прибыль: +14.5кк | Продаж: 6 | Скупок: 2"
-- Note: 14.5кк = 14 500 000. DSP.money formats with thousand dots, so we
-- also render a compact кк form for readability on a thin bar.
local function money_short(n)
    n = math.floor(tonumber(n) or 0)
    local neg = n < 0
    if neg then n = -n end
    local s
    if n >= 1000000 then
        s = string.format('%.1fкк', n / 1000000)
    elseif n >= 1000 then
        s = string.format('%.0fк', n / 1000)
    else
        s = tostring(n)
    end
    return (neg and '-' or '') .. s
end

-- Render the collapsed thin bar.
local function draw_collapsed()
    local dpi = d()
    local io = imgui.GetIO()
    local sw = (io and io.DisplaySize and io.DisplaySize.x) or 2340
    local sh = (io and io.DisplaySize and io.DisplaySize.y) or 1080
    local w = math.min(sw * 0.5, 480 * dpi)
    local h = 36 * dpi
    local px = 16 * dpi
    local py = sh - h - 16 * dpi
    imgui.SetNextWindowPos(imgui.ImVec2(px, py), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(w, h), imgui.Cond.Always)
    imgui.SetNextWindowBgAlpha(DSP.theme.opacity)
    local ncol = DSP.theme.push_overlay(0.95)
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoSavedSettings
        + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoMove
        + imgui.WindowFlags.NoNav
    if imgui.Begin('##dsp_crag_collapsed', nil, flags) then
        local c = DSP.craglog.counters
        local profit = c.profit or 0
        local pc = profit >= 0 and DSP.theme.col('good', 1) or DSP.theme.col('bad', 1)
        imgui.TextColored(pc, DSP.utf8(string.format('Прибыль: %s%s',
            profit >= 0 and '+' or '', money_short(profit))))
        imgui.SameLine(0, 12 * dpi)
        imgui.TextDisabled(DSP.utf8(string.format('| Продаж: %d', c.sales or 0)))
        imgui.SameLine(0, 12 * dpi)
        imgui.TextDisabled(DSP.utf8(string.format('| Скупок: %d', c.buys or 0)))
        imgui.SameLine(0, 12 * dpi)
        if imgui.Button(DSP.utf8('[+]'), imgui.ImVec2(34 * dpi, 26 * dpi)) then
            DSP.settings.craglog.minimized = false
            DSP.save_settings()
        end
    end
    imgui.End()
    imgui.PopStyleColor(ncol)
end

-- Render the expanded mini-window with last 50 entries + filter buttons.
local function draw_expanded()
    local dpi = d()
    local io = imgui.GetIO()
    local sw = (io and io.DisplaySize and io.DisplaySize.x) or 2340
    local sh = (io and io.DisplaySize and io.DisplaySize.y) or 1080
    local w = math.min(sw * 0.55, 720 * dpi)
    local h = math.min(sh * 0.55, 420 * dpi)
    local px = 16 * dpi
    local py = sh - h - 16 * dpi
    imgui.SetNextWindowPos(imgui.ImVec2(px, py), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(imgui.ImVec2(w, h), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowBgAlpha(DSP.theme.opacity)
    local ncol = DSP.theme.push_overlay(0.95)
    local open_ref = imgui.new.bool(true)
    local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoFocusOnAppearing
    if imgui.Begin(DSP.utf8(' craglog / мини-лог '), open_ref, flags) then
        local c = DSP.craglog.counters
        local profit = c.profit or 0
        local pc = profit >= 0 and DSP.theme.col('good', 1) or DSP.theme.col('bad', 1)
        imgui.TextColored(pc, DSP.utf8(string.format('Прибыль сессии: %s%s (%d сделок, %d ларцов)',
            profit >= 0 and '+' or '', DSP.money(profit), c.trades or 0, c.crates or 0)))
        imgui.SameLine(imgui.GetWindowWidth() - 100 * dpi, 6 * dpi)
        if imgui.Button(DSP.utf8('[X]'), imgui.ImVec2(40 * dpi, 28 * dpi)) then
            DSP.settings.craglog.open = false
            DSP.save_settings()
        end
        imgui.Separator()
        -- Filter row
        local f = DSP.settings.craglog.filter or 'all'
        local function filter_btn(label, key)
            local act = f == key
            if act then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
            if imgui.Button(DSP.utf8(label), imgui.ImVec2(100 * dpi, 0)) then
                DSP.settings.craglog.filter = key
                DSP.save_settings()
            end
            if act then imgui.PopStyleColor(1) end
            imgui.SameLine(0, 6 * dpi)
        end
        filter_btn('[ Все ]', 'all')
        filter_btn('[ Продажи ]', 'sales')
        filter_btn('[ Скупка ]', 'buys')
        imgui.SameLine(0, 12 * dpi)
        local pinned = DSP.settings.craglog.pinned
        if pinned then imgui.PushStyleColor(imgui.Col.Button, DSP.theme.col('accent', 0.55)) end
        if imgui.Button(DSP.utf8('[ PIN ]'), imgui.ImVec2(80 * dpi, 0)) then
            DSP.settings.craglog.pinned = not pinned
            DSP.save_settings()
        end
        if pinned then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * dpi)
        if imgui.Button(DSP.utf8('[ - ]'), imgui.ImVec2(40 * dpi, 0)) then
            DSP.settings.craglog.minimized = true
            DSP.save_settings()
        end
        imgui.SameLine(0, 6 * dpi)
        if imgui.Button(DSP.utf8('[ Очистить ]'), imgui.ImVec2(130 * dpi, 0)) then
            DSP.craglog.clear_ring()
            DSP.add_log('craglog: кольцевой буфер очищен (файл сохранён)')
        end
        imgui.Separator()

        local recent = DSP.craglog.ring_recent(50)
        -- Apply filter on display side
        local filtered = {}
        for _, e in ipairs(recent) do
            if f == 'all' then
                filtered[#filtered + 1] = e
            elseif f == 'sales' then
                -- sales = player received money
                if (e.money_get or 0) > 0 and (e.money_give or 0) == 0 then
                    filtered[#filtered + 1] = e
                elseif e.type == 'payday' then
                    filtered[#filtered + 1] = e
                end
            elseif f == 'buys' then
                if (e.money_give or 0) > 0 and (e.money_get or 0) == 0 then
                    filtered[#filtered + 1] = e
                end
            end
        end

        if imgui.BeginChild('##dsp_crag_list', imgui.ImVec2(0, 0), true) then
            if #filtered == 0 then
                imgui.TextDisabled(DSP.utf8('Нет записей. Совершите сделку или откройте ларец.'))
            end
            -- Display newest first (reverse the slice)
            for i = #filtered, 1, -1 do
                local e = filtered[i]
                local t = os.date('%H:%M:%S', e.ts or 0)
                imgui.TextDisabled(t)
                imgui.SameLine(0, 8 * dpi)
                if e.type == 'payday' then
                    imgui.TextColored(DSP.theme.col('accent', 1),
                        DSP.utf8(string.format('PAYDAY: %d сделок, прибыль %s%s',
                            e.count or 0, (e.profit or 0) >= 0 and '+' or '',
                            DSP.money(e.profit or 0))))
                elseif e.type == 'crate' or e.kind == 'crate' then
                    local src = tostring(e.source or e.crate_type or 'тайник')
                    imgui.TextColored(DSP.theme.col('warn', 1),
                        DSP.utf8(string.format('[%s] +%sx %s',
                            src, tostring(e.qty or 1), tostring(e.item or '?'))))
                else
                    local p = tonumber(e.profit) or 0
                    local pc = p >= 0 and DSP.theme.col('good', 1) or DSP.theme.col('bad', 1)
                    local pstr = (p >= 0 and '+' or '') .. DSP.money(p)
                    local partner = tostring(e.partner or '?')
                    local summary = e.item_summary or (tostring(e.kind or '') .. ' ' .. partner)
                    imgui.TextColored(pc, DSP.utf8(string.format('%s | %s | %s',
                        summary, partner, pstr)))
                end
            end
            imgui.EndChild()
        end
    end
    imgui.End()
    imgui.PopStyleColor(ncol)
    if open_ref and open_ref[0] == false then
        DSP.settings.craglog.open = false
        DSP.save_settings()
    end
end

function DSP.craglog.draw()
    if DSP.settings.craglog and DSP.settings.craglog.pinned then
        -- When pinned, never collapse -- always show full window.
        draw_expanded()
        return
    end
    if DSP.settings.craglog and DSP.settings.craglog.minimized then
        draw_collapsed()
    else
        draw_expanded()
    end
end

function DSP.craglog.toggle()
    if not DSP.settings.craglog then
        DSP.settings.craglog = { open = false, minimized = false, pinned = false, filter = 'all' }
    end
    DSP.settings.craglog.open = not DSP.settings.craglog.open
    DSP.save_settings()
    DSP.add_log('craglog: ' .. (DSP.settings.craglog.open and 'открыт' or 'закрыт'))
end

function DSP.craglog.install()
    if DSP.craglog.installed then return end
    DSP.craglog.installed = true
    -- Register /crlog chat command (independent of /crr).
    if sampRegisterChatCommand then
        pcall(sampRegisterChatCommand, 'crlog', function()
            DSP.craglog.toggle()
        end)
    end
    -- Render the mini-window whenever it's open AND main UI may be closed.
    -- This makes /crlog work independently of /crr.
    -- v1.2 hotfix: whole callback wrapped in pcall so a single bad imgui call
    -- doesn't crash the game.
    imgui.OnFrame(function()
        return DSP.settings.craglog and DSP.settings.craglog.open
    end, function()
        local ok, err = pcall(function()
            DSP.craglog.draw()
        end)
        if not ok then
            if DSP and DSP.flog then
                DSP.flog('craglog frame error: ' .. tostring(err))
            end
            -- Auto-close to prevent persistent error loop.
            if DSP.settings.craglog then
                DSP.settings.craglog.open = false
                pcall(DSP.save_settings)
            end
        end
    end)
end
