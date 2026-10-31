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

DSP.settings.ui_windows=DSP.settings.ui_windows or {}
local function load_overlay_state(key)
    local v=DSP.settings.ui_windows[key]
    if type(v)=='table' and tonumber(v.x) and tonumber(v.y) then
        return {x=tonumber(v.x),y=tonumber(v.y),w=tonumber(v.w),h=tonumber(v.h)}
    end
end
DSP.overlay.trade_pos=DSP.overlay.trade_pos or load_overlay_state('overlay_trade')
DSP.overlay.shop_pos=DSP.overlay.shop_pos or load_overlay_state('overlay_shop')
local function save_overlay_state(key,state_key)
    local st=DSP.overlay[state_key];if type(st)~='table'then return end
    local prev=DSP.settings.ui_windows[key] or {}
    if math.abs((tonumber(prev.x)or-99999)-(tonumber(st.x)or 0))>.5 or math.abs((tonumber(prev.y)or-99999)-(tonumber(st.y)or 0))>.5
        or math.abs((tonumber(prev.w)or-99999)-(tonumber(st.w)or 0))>.5 or math.abs((tonumber(prev.h)or-99999)-(tonumber(st.h)or 0))>.5 then
        DSP.settings.ui_windows[key]={x=st.x,y=st.y,w=st.w,h=st.h}
        if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save() end
    end
end
local function capture_overlay(key,state_key)
    if not(imgui.GetWindowPos and imgui.GetWindowSize)then return end
    local wh=imgui.GetWindowSize();local st=DSP.overlay[state_key]
    if not st then local p=imgui.GetWindowPos();st={x=p.x,y=p.y};DSP.overlay[state_key]=st end
    st.w,st.h=wh.x,wh.y;save_overlay_state(key,state_key)
end

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
    if DSP.settings.fps_saver then return false end
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
    if DSP.settings.fps_saver then return false end
    if DSP.settings.overlay_shop == false then return false end
    local s = DSP.live.shop
    if not s or (s.opened or 0) == 0 then return false end
    if DSP.overlay.shop_closed == s.opened then return false end
    if (s.menu_closed or 0) > 0 then return false end
    if DSP.live.shop_age() > 300 then return false end
    return #(s.sell or {}) > 0 or #(s.buy or {}) > 0
end

-- Allow dragging overlays ONLY by their header, never by the content.
-- The fixed screen coordinates are clamped to keep the close button reachable.
local function overlay_drag_bar(label,id,width,height,state_key)
    imgui.PushStyleColor(imgui.Col.Button,imgui.ImVec4(0,0,0,0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered,imgui.ImVec4(0,0,0,.08))
    imgui.PushStyleColor(imgui.Col.ButtonActive,imgui.ImVec4(0,0,0,.12))
    imgui.PushStyleColor(imgui.Col.Text,BLUE)
    imgui.Button(u(label)..'##drag_overlay_'..id,imgui.ImVec2(math.max(55,width),height or 42))
    local active=imgui.IsItemActive()
    imgui.PopStyleColor(4)
    local io=imgui.GetIO()
    if active and io and io.MouseDelta and imgui.GetWindowPos and imgui.GetWindowSize then
        local dx,dy=io.MouseDelta.x or 0,io.MouseDelta.y or 0
        if dx~=0 or dy~=0 then
            local pos,wh=imgui.GetWindowPos(),imgui.GetWindowSize()
            DSP.overlay[state_key]={
                x=math.max(0,math.min(pos.x+dx,math.max(0,io.DisplaySize.x-wh.x))),
                y=math.max(0,math.min(pos.y+dy,math.max(0,io.DisplaySize.y-wh.y))),
                w=wh.x,h=wh.y }
            save_overlay_state(state_key=='trade_pos' and 'overlay_trade' or 'overlay_shop',state_key)
        end
    end
end
local function overlay_next_pos(key,default_x,default_y,pivot,sw,sh,w,h)
    local pos=DSP.overlay[key]
    if pos then
        -- For auto-sized trade overlays use the real measured window size,
        -- not a large estimate that makes the window jump on the next frame.
        local measured_w=tonumber(pos.w) or w
        local measured_h=tonumber(pos.h) or h
        local x=math.max(0,math.min(pos.x,math.max(0,sw-measured_w)))
        local y=math.max(0,math.min(pos.y,math.max(0,sh-measured_h)))
        pos.x,pos.y=x,y
        imgui.SetNextWindowPos(imgui.ImVec2(x,y),imgui.Cond.Always)
    else
        imgui.SetNextWindowPos(imgui.ImVec2(default_x,default_y),imgui.Cond.FirstUseEver,pivot)
    end
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
    local saved=DSP.overlay.trade_pos
    local w = math.min(sw-16,math.max(250,tonumber(saved and saved.w) or math.min(sw*.38,540*d())))
    local hh=math.min(sh-16,math.max(180,tonumber(saved and saved.h) or math.max(270,sh*.57)))
    overlay_next_pos('trade_pos',sw-8*d(),76*d(),imgui.ImVec2(1,0),sw,sh,w,hh)
    imgui.SetNextWindowSize(imgui.ImVec2(w,hh),imgui.Cond.FirstUseEver)
    if DSP.settings.overlay_top ~= false then imgui.SetNextWindowFocus() end
    imgui.SetNextWindowBgAlpha(DSP.theme.opacity)
    local ncol = DSP.theme.push_overlay(0.95)
    local open = imgui.new.bool(true)
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoMove
        + imgui.WindowFlags.NoSavedSettings
        + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoNav
    if imgui.Begin('##dsp_trade_overlay', open, flags) then
        local top_width=math.max(1,imgui.GetContentRegionAvail().x)
        overlay_drag_bar('ТРЕЙД  ' .. (t.partner ~= '' and t.partner or '?'),
            'trade',math.max(55,top_width-80*d()),44,'trade_pos')
        if close_btn('dsp_trade_close') then DSP.overlay.trade_closed = t.opened end
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

        local avail=imgui.GetContentRegionAvail()
        local narrow=avail.x<440
        local half=math.max(55,math.floor((avail.x-8*d())/2))
        local child_width=narrow and -1 or half
        local h=math.max(70,math.min(230*d(),math.max(90,avail.y-(narrow and 100 or 55))))
        if narrow then h=math.max(70,math.floor(h*.54))end
        imgui.BeginChild('##dsp_trade_give', imgui.ImVec2(child_width, h), true)
        imgui.TextColored(RED, u('ВЫ ОТДАЁТЕ'))
        for _, it in ipairs(t.give or {}) do trade_item_row(it, 'give') end
        if (t.money_give or 0) > 0 then imgui.TextColored(RED, u('Деньги: -' .. DSP.money(t.money_give))) end
        if #(t.give or {}) == 0 and (t.money_give or 0) == 0 then imgui.TextDisabled(u('—')) end
        imgui.EndChild()
        if not narrow then imgui.SameLine(0, 8 * d())end
        imgui.BeginChild('##dsp_trade_get', imgui.ImVec2(child_width, h), true)
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
    capture_overlay('overlay_trade','trade_pos')
    imgui.End()
    imgui.PopStyleColor(ncol)
    if not open[0] then DSP.overlay.trade_closed = t.opened end
end

-- Only compare against OTHER shops. The current quote being included in
-- the market minimum caused false 'cheap at market price' endorsements.
-- Cache per live market snapshot and opened stall: never request network or
-- sort offers in each ImGui frame.
local quote_cache={}
function DSP.overlay.shop_market_reference(name,ench,shop_num,side)
    local st=DSP.market and DSP.market.state or {}
    local sid=tonumber(st.sid) or 0
    if sid<=0 or sid~=tonumber(DSP.settings.server) or st.status=='loading' then return nil end
    local snapshot=tostring(sid)..':'..tostring(st.version)..':'..tostring(DSP.live.shop.opened)..':'..tostring(math.floor(os.time()/60))
    if quote_cache.snapshot~=snapshot then quote_cache={snapshot=snapshot} end
    local item_key=DSP.item_key and DSP.item_key(name,ench) or tostring(name)..'|'..tostring(ench)
    local key=tostring(shop_num)..':'..tostring(side)..':'..item_key
    if quote_cache[key]~=nil then return quote_cache[key] or nil end
    local row=st.by_key and st.by_key[item_key]
    local offers=row and row[side] and row[side].offers or {}
    local prices,shops={},{}
    local now=os.time()
    local latest=0
    for _,o in ipairs(offers)do
        local t=tonumber(o.ts) or 0
        local price=tonumber(o.price) or 0
        if tostring(o.shop)~=tostring(shop_num) and price>0
            and t>0 and t<=now+60 and now-t<=600 then
            prices[#prices+1]=price;shops[tostring(o.shop)]=true
            if t>latest then latest=t end
        end
    end
    if #prices==0 then quote_cache[key]=false;return nil end
    table.sort(prices)
    local unique=0;for _ in pairs(shops)do unique=unique+1 end
    local n=#prices
    local median=n%2==1 and prices[(n+1)/2]
        or (prices[n/2]+prices[n/2+1])/2
    local reference={low=prices[1],high=prices[n],med=median,n=n,
        shops=unique,updated=latest}
    quote_cache[key]=reference
    return reference
end
local function evaluate_lavka(price,reference,side)
    if not reference then return GRAY,'НЕТ СВЕЖИХ ЧУЖИХ ЦЕН' end
    local median=reference.med or 0
    if median<=0 then return GRAY,'НЕТ СРАВНЕНИЯ' end
    if reference.shops<2 then
        return YELLOW,'МАЛО ДАННЫХ (1 ЛАВКА)'
    end
    -- Demand and supply are DIFFERENT quote series. Never treat one as a
    -- completed trade, or a favorable price as guaranteed stock/demand.
    if side=='sell' then
        if price<=median*.95 then return GREEN,'НИЖЕ ДРУГИХ >=5%'end
        if price<=median*1.05 then return YELLOW,'НА УРОВНЕ РЫНКА'end
        return RED,'ДОРОЖЕ ДРУГИХ'
    end
    if price>=median*1.05 then return GREEN,'СКУПАЕТ ДОРОЖЕ ДРУГИХ'end
    if price>=median*.95 then return YELLOW,'НА УРОВНЕ СКУПКИ'end
    return RED,'СКУПАЕТ ДЕШЕВЛЕ ДРУГИХ'
end
-- Receipt and recommendations are refreshed only when market evidence changes.
local shop_footer_cache={}
function DSP.overlay.shop_scan_footer(shop)
    local arb=DSP.local_arb
    local scan=DSP.live and DSP.live.auto_scan or {}
    local timestamp=os.time()
    local valid=tonumber(shop.num) and tostring(scan.shop)==tostring(shop.num)
        and tonumber(scan.server)==tonumber(shop.server)
        and tonumber(scan.generation)==tonumber(shop.generation)
        and tonumber(scan.at or 0)>=tonumber(shop.opened or math.huge)
    local scan_state,observed=DSP.live and DSP.live.scan_state and DSP.live.scan_state(shop)
    imgui.Separator()
    if valid and scan_state=='saved' then
        imgui.TextColored(GREEN,u('СКАН: УСПЕШНО  #'..tostring(shop.num)))
        imgui.TextDisabled(u('Продажа: '..tostring(scan.sell or 0)..' · Скупка: '..tostring(scan.buy or 0)))
        if arb and arb._dirty then
        imgui.TextDisabled(u('Ожидает записи базы на диск'))
        end
    elseif scan_state and scan_state~='pending' and scan_state~='saved' then
        local messages={
            disabled='Автоскан выключен. Включи его в «Мои сканы».',
            empty='Нет распознанных товаров в открытой лавке.',
            server='Сервер лавки не совпал с текущим сервером.',
            number='Товары прочитаны, но игра не передала номер лавки. В базу не сохранено.',
            owner='Номер есть, но имя владельца не распознано. В базу не сохранено.',
            error='Ошибка сохранения скана. Проверь standalone.log.',
            not_saved='Скан пока не подтверждён.',
        }
        imgui.TextDisabled(u(messages[scan_state] or messages.not_saved))
        imgui.TextDisabled(u('Распознано сейчас: '..tostring(observed or 0)))
    elseif DSP.settings.auto_shop_scan==false then
        imgui.TextDisabled(u('Автоскан выключен'))
    elseif DSP.live and DSP.live._auto_scan_pending then
        imgui.TextDisabled(u('Скан: получение товаров...'))
    else
        imgui.TextDisabled(u('Скан: нет подтверждения сохранения'))
    end
    local stats=arb and arb.stats and arb.stats(timestamp) or {shops=0,offers=0,server=0}
    imgui.TextDisabled(u('Мои сканы: '..tostring(stats.shops)..' лавок · '..tostring(stats.offers)..' предложений'))
    if scan_state~='saved' or not arb or not arb.routes then return end
    local sig=table.concat({tostring(stats.server),tostring(arb.revision or 0),
        tostring(math.floor(timestamp/30)),tostring(DSP.settings.tax_bp or 200),
        tostring(DSP.market and DSP.market.missing_revision or 0),tostring(shop.num)},':')
    if shop_footer_cache.sig~=sig then
        shop_footer_cache={sig=sig}
        for _,r in ipairs(arb.routes(timestamp))do
            if tostring(r.seller_shop)==tostring(shop.num)
                and (not shop_footer_cache.buy or r.profit_unit>shop_footer_cache.buy.profit_unit)then
                shop_footer_cache.buy=r
            end
            if tostring(r.buyer_shop)==tostring(shop.num)
                and (not shop_footer_cache.sell or r.profit_unit>shop_footer_cache.sell.profit_unit)then
                shop_footer_cache.sell=r
            end
        end
    end
    if shop_footer_cache.buy then
        local r=shop_footer_cache.buy
        imgui.TextColored(GREEN,u('Купить: '..tostring(r.name or ('ID '..tostring(r.id)))..
            ' · ~ +'..DSP.money(r.profit_unit)..'/шт. to #'..tostring(r.buyer_shop)))
    end
    if shop_footer_cache.sell then
        local r=shop_footer_cache.sell
        imgui.TextColored(GREEN,u('Продать: '..tostring(r.name or ('ID '..tostring(r.id)))..
            ' · ~ +'..DSP.money(r.profit_unit)..'/шт. from #'..tostring(r.seller_shop)))
    end
    if not shop_footer_cache.buy and not shop_footer_cache.sell then
        imgui.TextDisabled(u('Выгодных локальных связок пока нет'))
    end
    imgui.TextDisabled(u('Прогноз, не гарантированная прибыль'))
end
function DSP.overlay.draw_shop()
    refresh_palette()
    local s=DSP.live.shop
    local sw,sh=imgui.GetIO().DisplaySize.x,imgui.GetIO().DisplaySize.y
    local saved=DSP.overlay.shop_pos
    local w=math.min(sw-16,math.max(math.min(sw*.53,590*d()),math.min(sw-16,tonumber(saved and saved.w) or 340*d())))
    local h=math.min(sh-16,math.max(180,tonumber(saved and saved.h) or math.max(sh*.61,310*d())))
    overlay_next_pos('shop_pos',sw-10*d(),sh*.09,imgui.ImVec2(1,0),sw,sh,w,h)
    imgui.SetNextWindowSize(imgui.ImVec2(w,h),imgui.Cond.FirstUseEver)
    imgui.SetNextWindowBgAlpha(DSP.theme.opacity)
    local ncol=DSP.theme.push_overlay(.9)
    local open=imgui.new.bool(true)
    -- Window scroll remains enabled; resizing must never permanently hide controls.
    local flags=imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoMove
        +imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoFocusOnAppearing
    if imgui.Begin('##dsp_shop_overlay',open,flags)then
        local width=math.max(1,imgui.GetContentRegionAvail().x)
        local compact=width<430
        local close_width=compact and 60 or 130
        overlay_drag_bar('ЛАВКА #'..tostring(s.num or '?')..'  '..tostring(s.owner or '?'),
            'shop',math.max(55,width-close_width-12),44,'shop_pos')
        imgui.SameLine(0,8)
        if imgui.Button(u((compact and 'X' or 'ЗАКРЫТЬ X')..'##shop_close_big'),imgui.ImVec2(close_width,44))then
            DSP.overlay.shop_closed=s.opened
        end
        imgui.Separator()
        local sell_n,buy_n=#(s.sell or{}),#(s.buy or{})
        local bw=math.max(50,math.floor((imgui.GetContentRegionAvail().x-8)/2))
        if imgui.Button(u('ПРОДАЮТ ('..sell_n..')##shop_sell'),imgui.ImVec2(bw,54))then
            DSP.overlay.shop_tab=1;DSP.overlay.shop_page=1
        end
        imgui.SameLine(0,8)
        if imgui.Button(u('СКУПАЮТ ('..buy_n..')##shop_buy'),imgui.ImVec2(bw,54))then
            DSP.overlay.shop_tab=2;DSP.overlay.shop_page=1
        end
        imgui.TextDisabled(u('Снимок API не равен остатку в игре. Сравнение только с другими лавками.'))
        local list=DSP.overlay.shop_tab==1 and (s.sell or{})or(s.buy or{})
        if DSP.overlay.shop_last_open~=s.opened then
            DSP.overlay.shop_last_open=s.opened;DSP.overlay.shop_page=1
        end
        -- Cards have a predictable height; a page must not contain items
        -- hidden below the small child scroll region on a compact phone.
        local measured=imgui.GetWindowSize and imgui.GetWindowSize() or {x=w,y=h}
        local body=imgui.GetContentRegionAvail()
        -- Reserve screen space for navigation and receipt, with outer window scroll
        -- as a fallback on phones too small to display everything at once.
        local reserved=compact and 220 or 200
        local list_h=math.max(65,math.min(340*d(),measured.y*.43,math.max(75,body.y-reserved)))
        local per_page=math.max(1,math.floor(list_h/(compact and 136*d() or 114*d())))
        local pages=math.max(1,math.ceil(#list/per_page))
        DSP.overlay.shop_page=math.max(1,math.min(pages,DSP.overlay.shop_page or 1))
        if imgui.BeginChild('##dsp_shop_cards',imgui.ImVec2(-1,list_h),true)then
            if #list==0 then imgui.TextDisabled(u('Нет наблюдаемых позиций'))end
            for i=(DSP.overlay.shop_page-1)*per_page+1,math.min(#list,DSP.overlay.shop_page*per_page)do
                local it=list[i]
                local side=DSP.overlay.shop_tab==1 and 'sell'or'buy'
                local ref=DSP.overlay.shop_market_reference(it.name,it.ench,s.num,side)
                local color,verdict=evaluate_lavka(tonumber(it.price)or 0,ref,side)
                imgui.TextColored(color,u(verdict))
                local quantity=(it.qty_known==false or it.qty==nil)
                    and '  · кол-во неизвестно' or '  x'..tostring(it.qty)
                local name=u(DSP.item_name(it.name,it.ench)..quantity)
                if imgui.TextWrapped then imgui.TextWrapped(name)else imgui.Text(name)end
                imgui.TextColored(BLUE,u((side=='sell'and 'Вы покупаете: 'or'Вы продаёте: ')
                    ..DSP.money(it.price)..'/шт.'))
                if ref then
                    imgui.TextDisabled(u('Другие лавки: '..DSP.money(ref.low)..'–'..DSP.money(ref.high)
                        ..' · медиана '..DSP.money(ref.med)..' · '..ref.shops..' лавок'))
                else
                    imgui.TextDisabled(u('Свежих предложений других лавок нет'))
                end
                imgui.Separator()
            end
        end
        imgui.EndChild()
        if imgui.Button(u('<  НАЗАД##shop_page_prev'),imgui.ImVec2(bw,54))then
            DSP.overlay.shop_page=math.max(1,DSP.overlay.shop_page-1)
        end
        imgui.SameLine(0,8)
        if imgui.Button(u('ВПЕРЁД  >##shop_page_next'),imgui.ImVec2(bw,54))then
            DSP.overlay.shop_page=math.min(pages,DSP.overlay.shop_page+1)
        end
        imgui.TextDisabled(u('Страница '..DSP.overlay.shop_page..' / '..pages))
        if imgui.SmallButton(u('Обновить рынок##dsp_shop_refresh'))then
            DSP.market.pull(DSP.market.state.sid)
        end
        DSP.overlay.shop_scan_footer(s)
    end
    capture_overlay('overlay_shop','shop_pos')
    imgui.End()
    imgui.PopStyleColor(ncol)
    if not open[0]then DSP.overlay.shop_closed=s.opened end
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
