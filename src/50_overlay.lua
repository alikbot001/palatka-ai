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
                local quantity = (it.qty_known == false or it.qty == nil)
                    and '  · кол-во неизвестно' or '  x' .. tostring(it.qty)
                local label = u(DSP.item_name(it.name, it.ench) .. quantity)
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
