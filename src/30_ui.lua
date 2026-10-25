-- Clickable DS-market style UI.
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

local function nav(label, id)
    local active = DSP.ui.tab == id
    if active then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.72)) end
    if imgui.Button(label, imgui.ImVec2(-1, 38 * d())) then
        DSP.ui.tab = id
        DSP.ui.page = 1
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
    if sampRegisterChatCommand then
        sampRegisterChatCommand('crr', function() DSP.ui.toggle() end)
    end
    DSP.add_log('palatka ai v' .. DSP.version .. ' загружен')
end

function DSP.ui.header()
    local st = DSP.market.state
    imgui.TextColored(acc_col(1), DSP.utf8('DS РЫНОК'))
    imgui.SameLine(0, 14 * d())
    imgui.TextDisabled(DSP.utf8('Mobile ' .. tostring(st.sid)))
    imgui.SameLine(0, 14 * d())
    local status = st.status == 'loading' and 'обновление...'
        or st.status == 'error' and ('ошибка: ' .. tostring(st.error))
        or st.status == 'cache' and 'кэш'
        or 'live'
    local sc = st.status == 'error' and col(1, 0.35, 0.35) or col(0.55, 0.9, 0.55)
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
        if active then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
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
    local pages = math.max(1, math.ceil(#rows / per))
    if DSP.ui.page > pages then DSP.ui.page = pages end
    if DSP.ui.page < 1 then DSP.ui.page = 1 end
    local from = (DSP.ui.page - 1) * per + 1
    local to = math.min(#rows, DSP.ui.page * per)
    local sel = DSP.ui.selected and DSP.market.state.by_key[DSP.ui.selected] or nil

    imgui.TextDisabled(DSP.utf8(string.format('Найдено: %d  |  стр. %d/%d  |  сортировка: %s',
        #rows, DSP.ui.page, pages,
        (tonumber(DSP.settings.sort) == 2 and 'дешёвые'
            or tonumber(DSP.settings.sort) == 3 and 'дорогая скупка'
            or tonumber(DSP.settings.sort) == 4 and 'процент'
            or tonumber(DSP.settings.sort) == 5 and 'офферы'
            or 'выгода'))))

    local avail = imgui.GetContentRegionAvail()
    local detail_h = sel and (196 * d()) or 0
    local table_h = math.max(150 * d(), avail.y - detail_h - 92 * d())
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

        imgui.Columns(6, '##dsp_rows', false)
        for i = 0, 5 do imgui.SetColumnWidth(i, widths[i + 1]) end
        for i = from, to do
            local row = rows[i]
            local selected = DSP.ui.selected == row.key
            local label = DSP.utf8(row.display) .. '##dsp_r' .. tostring(i)
            if imgui.Selectable(label, selected,
                imgui.SelectableFlags.SpanAllColumns + imgui.SelectableFlags.AllowDoubleClick,
                imgui.ImVec2(0, 28 * d())) then
                DSP.ui.selected = row.key
            end
            imgui.NextColumn()
            if row.buy.count > 0 then
                imgui.TextColored(col(0.45, 0.9, 0.55), DSP.money(row.buy.best))
            else
                imgui.TextDisabled('-')
            end
            imgui.NextColumn()
            if row.sell.count > 0 then
                imgui.TextColored(col(1.0, 0.72, 0.35), DSP.money(row.sell.best))
            else
                imgui.TextDisabled('-')
            end
            imgui.NextColumn()
            if row.sell.count > 0 and row.buy.count > 0 then
                local pc = row.profit > 0 and col(0.45, 0.95, 0.55)
                    or row.profit < 0 and col(1, 0.4, 0.4) or col(0.7, 0.7, 0.7)
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
        imgui.Columns(1)
        if #rows == 0 then
            imgui.Spacing()
            imgui.TextDisabled(DSP.utf8('Нет строк под фильтр. Нажмите ОБНОВИТЬ.'))
        end
        imgui.EndChild()
    end

    if imgui.Button(DSP.utf8('<< В начало'), imgui.ImVec2(120 * d(), 0)) then DSP.ui.page = 1 end
    imgui.SameLine(0, 6 * d())
    if imgui.Button(DSP.utf8('< Вверх'), imgui.ImVec2(110 * d(), 0)) then DSP.ui.page = DSP.ui.page - 1 end
    imgui.SameLine(0, 10 * d())
    imgui.TextDisabled(string.format('%d / %d', DSP.ui.page, pages))
    imgui.SameLine(0, 10 * d())
    if imgui.Button(DSP.utf8('Вниз >'), imgui.ImVec2(110 * d(), 0)) then DSP.ui.page = DSP.ui.page + 1 end
    imgui.SameLine(0, 6 * d())
    if imgui.Button(DSP.utf8('В конец >>'), imgui.ImVec2(120 * d(), 0)) then DSP.ui.page = pages end
    imgui.SameLine(0, 14 * d())
    imgui.TextDisabled(DSP.utf8('Строк на странице:'))
    imgui.SameLine(0, 6 * d())
    if imgui.SmallButton('-') then DSP.settings.per_page = math.max(10, per - 5); DSP.save_settings(); DSP.ui.page = 1 end
    imgui.SameLine(0, 4 * d())
    imgui.Text(tostring(per))
    imgui.SameLine(0, 4 * d())
    if imgui.SmallButton('+') then DSP.settings.per_page = math.min(50, per + 5); DSP.save_settings(); DSP.ui.page = 1 end

    if sel then
        imgui.Separator()
        DSP.ui.detail(sel)
    end
end

function DSP.ui.detail(row)
    imgui.TextColored(acc_col(1), DSP.utf8(trunc(row.display, 42)))
    imgui.SameLine(0, 14 * d())
    local pc = row.profit > 0 and col(0.45, 0.95, 0.55) or col(1, 0.5, 0.5)
    imgui.TextColored(pc, DSP.utf8('выгода ') .. (row.profit > 0 and '+' or '') .. DSP.money(row.profit))
    imgui.SameLine(0, 10 * d())
    imgui.TextDisabled(string.format('(%+.1f%%)', row.profit_pct or 0))
    imgui.SameLine(0, 20 * d())
    if imgui.SmallButton(DSP.utf8('закрыть')) then DSP.ui.selected = nil end
    imgui.Spacing()
    local h = 100 * d()
    if imgui.BeginChild('##dsp_d_sell', imgui.ImVec2(-1, h), true) then
        imgui.TextDisabled(DSP.utf8('КУПИТЬ ДЕШЕВЛЕ (лавка продаёт)'))
        for i = 1, math.min(3, #row.sell.offers) do
            local o = row.sell.offers[i]
            imgui.TextColored(col(1.0, 0.75, 0.4), DSP.money(o.price))
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
            imgui.TextColored(col(0.45, 0.9, 0.55), DSP.money(o.price))
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

    imgui.TextColored(acc_col(1), DSP.utf8('ТОРГОВЛЯ'))
    imgui.SameLine(0, 18 * d())
    if kind == 'buy' then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
    if imgui.Button(DSP.utf8('СКУПКА'), imgui.ImVec2(130 * d(), 0)) then DSP.ui.preset_kind = 'buy' end
    if kind == 'buy' then imgui.PopStyleColor(1) end
    imgui.SameLine(0, 6 * d())
    if kind == 'sell' then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
    if imgui.Button(DSP.utf8('ПРОДАЖА'), imgui.ImVec2(130 * d(), 0)) then DSP.ui.preset_kind = 'sell' end
    if kind == 'sell' then imgui.PopStyleColor(1) end
    imgui.SameLine(0, 18 * d())
    imgui.TextDisabled(DSP.utf8(string.format('%s: %d поз.', p.name or kind, #p.items)))
    imgui.Separator()

    local avail = imgui.GetContentRegionAvail()
    local inv_h = math.min(220 * d(), avail.y * 0.55)
    local pre_h = avail.y - inv_h - 40 * d()

    -- Preset items list
    if imgui.BeginChild('##dsp_trade_presets', imgui.ImVec2(-1, pre_h), true) then
        if #p.items == 0 then
            imgui.TextDisabled(DSP.utf8('Пусто. Сканируйте инвентарь и добавляйте товары.'))
        end
        for i, it in ipairs(p.items) do
            local en = imgui.new.bool(it.enabled ~= false)
            if imgui.Checkbox('##dsp_en' .. i, en) then
                it.enabled = en[0]
                DSP.save_settings()
            end
            imgui.SameLine(0, 8 * d())
            imgui.Text(DSP.utf8(trunc(it.name, 36)))
            imgui.SameLine(0, 12 * d())
            imgui.TextColored(kind == 'buy' and col(0.45, 0.9, 0.55) or col(1.0, 0.72, 0.38),
                DSP.money(it.price))
            imgui.SameLine(0, 8 * d())
            imgui.TextDisabled(DSP.utf8('x' .. tostring(it.qty or 1)))
            local est = DSP.presets.estimate(it, kind)
            if est then
                local ec = est >= 0 and col(0.45, 0.95, 0.5) or col(1, 0.42, 0.38)
                imgui.SameLine(0, 8 * d())
                imgui.TextColored(ec, DSP.utf8((est >= 0 and '+' or '') .. DSP.money(est)))
            end
            imgui.SameLine(0, 6 * d())
            if imgui.SmallButton(DSP.utf8('+все##dsp_all' .. i)) then
                it.qty = math.max(1, it.qty or 1)
                DSP.save_settings()
            end
            imgui.SameLine(0, 3 * d())
            if imgui.SmallButton(DSP.utf8('х-##dsp_del' .. i)) then
                DSP.presets.remove(kind, i)
                break
            end
            imgui.Spacing()
        end
        imgui.EndChild()
    end
    imgui.Separator()

    -- Inventory scan section
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
                local price_color = col(0.7, 0.7, 0.7)
                if row then
                    if kind == 'buy' then
                        local bp = DSP.market.buy_target(row)
                        if bp > 0 then price_text = DSP.money(bp); price_color = col(0.45, 0.9, 0.55) end
                    else
                        local sp = DSP.market.sell_target(row)
                        if sp > 0 then price_text = DSP.money(sp); price_color = col(1.0, 0.72, 0.38) end
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

    -- Action bar
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

function DSP.ui.auto_tab()
    imgui.TextColored(acc_col(1), DSP.utf8('АВТО'))
    imgui.Separator()
    local st = DSP.auto and DSP.auto.status_text and DSP.auto.status_text() or 'движок не загружен'
    imgui.TextDisabled(DSP.utf8(st))
    imgui.Spacing()

    if imgui.BeginChild('##dsp_auto_buy', imgui.ImVec2(-1, 150 * d()), true) then
        imgui.TextColored(col(0.45, 0.9, 0.55), DSP.utf8('АВТО-СКУПКА'))
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
        imgui.TextColored(col(1.0, 0.72, 0.35), DSP.utf8('АВТО-ПРОДАЖА'))
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
            local c = e.kind == 'error' and col(1, 0.4, 0.4)
                or e.kind == 'ok' and col(0.45, 0.9, 0.55) or col(0.8, 0.8, 0.8)
            imgui.TextColored(c, DSP.utf8(e.text))
        end
        imgui.EndChild()
    end
end

function DSP.ui.log_tab()
    imgui.TextColored(acc_col(1), DSP.utf8('ЖУРНАЛ'))
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
    if r1 then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.72)) end
    if imgui.Button(DSP.utf8('Сделки + лавки'), imgui.ImVec2(160 * d(), 0)) then DSP.ui.tab_detail = 'trades' end
    if r1 then imgui.PopStyleColor(1) end
    imgui.SameLine(0, 8 * d())
    local r2 = DSP.ui.tab_detail == 'crates'
    if r2 then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.72)) end
    if imgui.Button(DSP.utf8('Ларцы'), imgui.ImVec2(120 * d(), 0)) then DSP.ui.tab_detail = 'crates' end
    if r2 then imgui.PopStyleColor(1) end
    imgui.SameLine(0, 8 * d())
    local r3 = DSP.ui.tab_detail == 'chat'
    if r3 then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.72)) end
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
                local sign = e.profit and e.profit >= 0 and col(0.45, 0.9, 0.55) or col(1, 0.4, 0.4)
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
                imgui.TextColored(col(1.0, 0.72, 0.4), DSP.utf8(e.item or '?'))
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
            local clr = drop and col(1.0, 0.72, 0.4) or col(0.8, 0.8, 0.9)
            imgui.TextColored(clr, DSP.utf8(e.text or ''))
        end
        imgui.EndChild()
    end
end

function DSP.ui.settings_tab()
    imgui.TextColored(acc_col(1), DSP.utf8('НАСТРОЙКИ'))
    imgui.Separator()
    DSP.ui.server_buttons()
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Сортировка рынка:'))
    local sorts = { 'выгода', 'дешёвые', 'дорогая скупка', 'процент', 'офферы' }
    for i, name in ipairs(sorts) do
        local act = (tonumber(DSP.settings.sort) or 1) == i
        if act then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
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
    imgui.TextDisabled(DSP.utf8('Оверлей при трейде/лавке:'))
    checkbox(DSP.utf8('оценка трейда'), 'overlay_trade')
    imgui.SameLine(0, 12 * d())
    checkbox(DSP.utf8('скан лавки'), 'overlay_shop')
    imgui.SameLine(0, 12 * d())
    checkbox(DSP.utf8('поверх окон'), 'overlay_top')
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Масштаб интерфейса:'))
    for _, v in ipairs({ 1.0, 1.25, 1.5 }) do
        local act = math.abs((DSP.ui.d or 1.25) - v) < 0.01
        if act then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
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
        if act then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
        if imgui.Button(DSP.utf8(m.label), imgui.ImVec2(100 * d(), 0)) then
            DSP.settings.stats_mode = m.key
            DSP.save_settings()
        end
        if act then imgui.PopStyleColor(1) end
        imgui.SameLine(0, 6 * d())
    end
    imgui.NewLine()
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Telegram-уведомления:'))
    if imgui.Checkbox(DSP.utf8('включить'), DSP.ui.chk.tg_notify) then
        DSP.settings.tg_notify = DSP.ui.chk.tg_notify[0]
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
        DSP.notify('Настройки сохранены')
    end
    imgui.Spacing()
    imgui.TextDisabled(DSP.utf8('Данные: ' .. DSP.dir))
    imgui.TextDisabled(DSP.utf8('API: ' .. DSP.market.api))
end

function DSP.ui.calculator_tab()
    imgui.TextColored(acc_col(1), DSP.utf8('КАЛЬКУЛЯТОР'))
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
        local pc = profit >= 0 and col(0.45, 0.95, 0.5) or col(1, 0.42, 0.38)
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
    imgui.TextColored(acc_col(1), DSP.utf8('СТАТИСТИКА'))
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
        if active then imgui.PushStyleColor(imgui.Col.Button, acc_col(0.7)) end
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
        local pc = summary.profit >= 0 and col(0.45, 0.95, 0.5) or col(1, 0.42, 0.38)
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
                local pc = b.profit >= 0 and col(0.45, 0.95, 0.5) or col(1, 0.42, 0.38)
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

function DSP.ui.draw()
    local dpi = d()
    imgui.SetNextWindowSize(imgui.ImVec2(1120 * dpi, 760 * dpi), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(1170, 540), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowBgAlpha(0.97)
    imgui.PushStyleColor(imgui.Col.WindowBg, col(0.055, 0.055, 0.085, 0.97))
    imgui.PushStyleColor(imgui.Col.TitleBg, col(0.08, 0.08, 0.12, 1))
    imgui.PushStyleColor(imgui.Col.TitleBgActive, col(ACC[1] * 0.22, ACC[2] * 0.22, ACC[3] * 0.22, 1))
    imgui.PushStyleColor(imgui.Col.Border, acc_col(0.8))
    imgui.PushStyleColor(imgui.Col.Button, col(0.14, 0.14, 0.20, 1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, acc_col(0.75))
    imgui.PushStyleColor(imgui.Col.ButtonActive, acc_col(0.95))
    imgui.PushStyleColor(imgui.Col.Header, acc_col(0.45))
    imgui.PushStyleColor(imgui.Col.HeaderHovered, acc_col(0.65))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12 * dpi)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 8 * dpi)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 9 * dpi)
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(8 * dpi, 6 * dpi))

    local flags = imgui.WindowFlags.NoCollapse
    if imgui.Begin(DSP.utf8(' palatka ai | РЫНОК v' .. DSP.version .. ' '), DSP.ui.open_ref, flags) then
        if imgui.BeginChild('##dsp_side', imgui.ImVec2(196 * dpi, 0), true) then
            imgui.TextColored(acc_col(1), DSP.utf8('PALATKA'))
            imgui.TextDisabled(DSP.utf8('ai'))
            imgui.Separator()
            nav(DSP.utf8('DS РЫНОК'), 1)
            nav(DSP.utf8('КАЛЬК'), 2)
            nav(DSP.utf8('СТАТ'), 3)
            nav(DSP.utf8('ТОРГОВЛЯ'), 4)
            nav(DSP.utf8('АВТО'), 5)
            nav(DSP.utf8('ЖУРНАЛ'), 6)
            nav(DSP.utf8('НАСТРОЙКИ'), 7)
            imgui.Spacing()
            imgui.Separator()
            imgui.TextDisabled(DSP.utf8(string.format('офферов: %d', DSP.market.state.offers or 0)))
            imgui.TextDisabled(DSP.utf8('свежесть: ' .. DSP.market.freshness()))
            imgui.Spacing()
            if imgui.Button(DSP.utf8('/crr'), imgui.ImVec2(-1, 0)) then
                DSP.notify('Команда /crr открывает и закрывает окно')
            end
        end
        imgui.EndChild()
        imgui.SameLine(0, 10 * dpi)
        if imgui.BeginChild('##dsp_main', imgui.ImVec2(0, 0), false) then
        if DSP.ui.tab == 4 then
            DSP.ui.trade_tab()
        elseif DSP.ui.tab == 5 then
            DSP.ui.auto_tab()
        elseif DSP.ui.tab == 6 then
            DSP.ui.log_tab()
        elseif DSP.ui.tab == 7 then
            DSP.ui.settings_tab()
        elseif DSP.ui.tab == 2 then
            DSP.ui.calculator_tab()
        elseif DSP.ui.tab == 3 then
            DSP.ui.statistics_tab()
        else
            DSP.ui.market_tab()
        end
        end
        imgui.EndChild()
    end
    imgui.End()
    imgui.PopStyleVar(4)
    imgui.PopStyleColor(9)
    if DSP.ui.open_ref and DSP.ui.open_ref[0] == false then
        DSP.ui.open = false
    end
end

function DSP.ui.install()
    DSP.ui.init()
    imgui.OnFrame(function()
        return DSP.ui.btn_visible ~= false and not DSP.ui.open and not (isPauseMenuActive and isPauseMenuActive())
    end, function(player)
        local dpi = d()
        player.HideCursor = false
        imgui.SetNextWindowPos(imgui.ImVec2(28 * dpi, 215 * dpi), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(54 * dpi, 54 * dpi), imgui.Cond.Always)
        local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoBackground
        if imgui.Begin('##dsp_new_float', nil, flags) then
            if imgui.Button('DSP', imgui.ImVec2(-1, -1)) then DSP.ui.set_open(true) end
            imgui.End()
        end
    end)
    imgui.OnFrame(function() return DSP.ui.open end, function()
        DSP.ui.draw()
    end)
end
