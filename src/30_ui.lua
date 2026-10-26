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
