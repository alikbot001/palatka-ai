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
