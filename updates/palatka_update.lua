PALATKA_UPDATE_VERSION = '2.6.4-legible-webui'

return function(DSP)
    DSP.webui = DSP.webui or {}
    local W = DSP.webui

    W.version = '1.4-legible'
    W.bid = 95253
    W.dir = DSP.dir .. '/webui'
    W.html_path = W.dir .. '/index.html'
    W.version_path = W.dir .. '/version.txt'
    W.html_url = 'https://raw.githubusercontent.com/alikbot001/palatka-ai/main/webui/index.html'
    W.visible = false
    W.created = false
    W.loaded = false
    W.bridge_installed = false
    W.hooks_installed = false
    W.browser_visible = false
    W.last_rect = {x=-99999,y=-99999,w=0,h=0}
    W.geometry_error = nil
    W.registered_rescue_commands = W.registered_rescue_commands or {}
    W.last_save_clock = 0
    W.window_dirty = false

    local ok_web, web = pcall(require, 'webviews')
    W.web = ok_web and web or nil
    local ok_b64, basexx = pcall(require, 'basexx')
    local ok_imgui, imgui = pcall(require, 'mimgui')
    if not ok_imgui then imgui = _G.imgui end
    W.imgui = imgui

    if imgui and imgui.new and not W.host_open then
        W.host_open = imgui.new.bool(false)
    end

    local legacy_toggle = DSP.ui and DSP.ui.toggle
    local legacy_set_open = DSP.ui and DSP.ui.set_open

    local function read_file(path)
        local f = io.open(path, 'rb')
        if not f then return nil end
        local d = f:read('*a')
        f:close()
        return d
    end

    local function write_file(path, data)
        if DSP.mkdir_p then pcall(DSP.mkdir_p, W.dir) end
        local tmp = path .. '.tmp'
        local f, e = io.open(tmp, 'wb')
        if not f then return false, e end
        local ok, er = f:write(data)
        local cl, ce = f:close()
        if not ok or not cl then
            pcall(os.remove, tmp)
            return false, er or ce
        end
        -- Preserve the old HTML until replacement is complete.
        -- On Android a rename-over-existing may fail; recover via .bak.
        local rn, re = os.rename(tmp, path)
        if not rn and read_file(path) then
            local bak = path .. '.bak'
            pcall(os.remove, bak)
            local backed = os.rename(path, bak)
            if backed then
                rn, re = os.rename(tmp, path)
                if rn then pcall(os.remove, bak) else pcall(os.rename, bak, path) end
            end
        end
        if not rn then
            pcall(os.remove, tmp)
            return false, re
        end
        return true
    end

    local function u(v)
        local s = tostring(v or '')
        if DSP.to_u8 then
            local ok, r = pcall(DSP.to_u8, s)
            if ok and r then return r end
        end
        return s
    end

    local function kind_name(k)
        if DSP.storage_registry and DSP.storage_registry.kind_name then
            local ok, r = pcall(DSP.storage_registry.kind_name, k)
            if ok and r then return u(r) end
        end
        return tostring(k or 'other')
    end

    local function find_row(rec, key)
        local R = DSP.storage_registry
        if not (R and rec and R.group_rows) then return nil end
        for _, row in ipairs(R.group_rows(rec) or {}) do
            if tostring(row.key or '') == tostring(key or '') then return row end
        end
        return nil
    end

    local function build_state()
        local st = DSP.market and DSP.market.state or {}
        local out = {
            version = tostring(DSP.version or '?'),
            server = tonumber(st.sid) or tonumber(DSP.settings and DSP.settings.server) or 0,
            market = {
                status = u(st.status or 'idle'),
                shops = tonumber(st.shops) or 0,
                offers = tonumber(st.offers) or 0,
                freshness = DSP.market and DSP.market.freshness and u(DSP.market.freshness()) or ''
            },
            storages = {},
            pending = nil,
            updater = {
                status = DSP.updater and DSP.updater.status_text and u(DSP.updater.status_text()) or '',
                available = DSP.updater and DSP.updater.state and DSP.updater.state.available or false,
                remote_version = DSP.updater and DSP.updater.state and DSP.updater.state.remote_version or nil
            }
        }

        local R = DSP.storage_registry
        if R and R.data and R.data.storages then
            for i = #(R.data.order or {}), 1, -1 do
                local id = R.data.order[i]
                local rec = R.data.storages[id]
                if rec then
                    local total, qty, unknown = 0, 0, 0
                    if R.total then
                        local ok, a, b, c = pcall(R.total, rec)
                        if ok then total, qty, unknown = a or 0, b or 0, c or 0 end
                    end
                    local s = {
                        id = tostring(rec.id or id),
                        name = u(rec.name or rec.id or id),
                        kind = rec.kind or 'other',
                        kind_name = kind_name(rec.kind),
                        updated_at = tonumber(rec.updated_at) or 0,
                        total = tonumber(total) or 0,
                        qty = tonumber(qty) or 0,
                        unknown = tonumber(unknown) or 0,
                        rows = {}
                    }
                    if R.group_rows then
                        for _, r in ipairs(R.group_rows(rec) or {}) do
                            s.rows[#s.rows + 1] = {
                                key = tostring(r.key or ''),
                                name = u(r.name or ''),
                                ench = tonumber(r.ench) or 0,
                                qty = tonumber(r.qty),
                                price = tonumber(r.price),
                                value = tonumber(r.value),
                                mode = tostring(r.mode or 'market'),
                                sources = {
                                    market = r.sources and tonumber(r.sources.market),
                                    today = r.sources and tonumber(r.sources.today),
                                    buy = r.sources and tonumber(r.sources.buy)
                                }
                            }
                        end
                    end
                    out.storages[#out.storages + 1] = s
                end
            end
        end

        if R and R.pending then
            local p = R.pending
            local pp = {
                kind = p.kind or 'other',
                kind_name = kind_name(p.kind),
                confidence = tostring(p.candidate and p.candidate.confidence or 'unknown'),
                candidates = {}
            }
            if R.candidates then
                for _, c in ipairs(R.candidates(p.kind, p.server) or {}) do
                    pp.candidates[#pp.candidates + 1] = {
                        id = tostring(c.id),
                        name = u(c.name or c.id)
                    }
                end
            end
            out.pending = pp
        end
        return out
    end

    function W.push_state()
        if not (W.web and W.created and W.loaded and ok_b64 and basexx) then return false end
        local ok, j = pcall(encodeJson, build_state())
        if not ok or type(j) ~= 'string' then return false end
        local ok2, b64 = pcall(basexx.to_base64, j)
        if not ok2 or not b64 then return false end
        local js = "window.Palatka&&window.Palatka.receiveStateB64('" .. b64 .. "');"
        return pcall(function() W.web.executeJS(W.bid, js) end)
    end

    function W.schedule_push(ms)
        if lua_thread and lua_thread.create and wait then
            lua_thread.create(function()
                wait(ms or 60)
                pcall(W.push_state)
            end)
        else
            pcall(W.push_state)
        end
    end

    local function screen_size()
        if getScreenResolution then
            local ok, a, b = pcall(getScreenResolution)
            if ok and a and b then return a, b end
        end
        if imgui and imgui.GetIO then
            local ok, io = pcall(imgui.GetIO)
            if ok and io and io.DisplaySize then return io.DisplaySize.x, io.DisplaySize.y end
        end
        return 1280, 720
    end

    local function host_config()
        DSP.settings = DSP.settings or {}
        DSP.settings.ui_windows = type(DSP.settings.ui_windows) == 'table' and DSP.settings.ui_windows or {}
        local cfg = DSP.settings.ui_windows.webui_host
        if type(cfg) ~= 'table' then
            cfg = {}
            DSP.settings.ui_windows.webui_host = cfg
        end
        return cfg
    end

    local function clamp_host(cfg, sw, sh)
        local minw = math.min(520, math.max(260, sw - 24))
        local minh = math.min(360, math.max(220, sh - 24))
        local defw = math.min(sw - 36, math.max(minw, sw * 0.72))
        local defh = math.min(sh - 42, math.max(minh, sh * 0.76))
        local w = tonumber(cfg.w) or defw
        local h = tonumber(cfg.h) or defh
        w = math.max(minw, math.min(w, sw - 20))
        h = math.max(minh, math.min(h, sh - 20))
        local x = tonumber(cfg.x)
        local y = tonumber(cfg.y)
        if x == nil then x = (sw - w) * 0.5 end
        if y == nil then y = (sh - h) * 0.5 end
        x = math.max(4, math.min(x, sw - w - 4))
        y = math.max(4, math.min(y, sh - h - 4))
        return {x=x,y=y,w=w,h=h}
    end

    local function save_host_rect(x, y, w, h, force)
        local cfg = host_config()
        local changed = math.abs((tonumber(cfg.x) or -1) - x) > 0.5
            or math.abs((tonumber(cfg.y) or -1) - y) > 0.5
            or math.abs((tonumber(cfg.w) or -1) - w) > 0.5
            or math.abs((tonumber(cfg.h) or -1) - h) > 0.5
        if not changed then return end
        cfg.x, cfg.y, cfg.w, cfg.h = x, y, w, h
        W.window_dirty = true
        local now = os.clock()
        if force or (now - (W.last_save_clock or 0)) > 1.25 then
            W.last_save_clock = now
            if DSP.save_settings then
                local ok = pcall(DSP.save_settings)
                if ok then W.window_dirty = false end
            end
        end
    end

    local function hide_browser()
        -- Hide even when a previous callback lost browser_visible state.
        if W.web and W.created then
            pcall(function() W.web.setClickable(W.bid, false) end)
            pcall(function() W.web.setVisible(W.bid, false) end)
        end
        W.browser_visible = false
    end

    local function ensure_html(done)
        local current = read_file(W.version_path)
        local html = read_file(W.html_path)
        if current == W.version and html and #html > 2000 then
            done(true)
            return
        end
        local function fallback(reason)
            if html and #html > 2000 then
                if DSP.flog then DSP.flog('WEBUI cached HTML fallback: ' .. tostring(reason)) end
                done(true, 'cached HTML')
            else
                done(false, reason)
            end
        end
        if not DSP.http_get then
            fallback('HTTP unavailable')
            return
        end
        DSP.http_get(W.html_url, function(body, err, code)
            if not body or #body < 2000 then
                fallback(tostring(err or ('HTTP ' .. tostring(code or 0))))
                return
            end
            local ok, e = write_file(W.html_path, body)
            if not ok then fallback(tostring(e)); return end
            local saved, se = write_file(W.version_path, W.version)
            if not saved and DSP.flog then DSP.flog('WEBUI version marker not saved: ' .. tostring(se)) end
            done(true)
        end)
    end

    local function install_bridge()
        if W.bridge_installed or not W.web then return end
        local previous = W.web.onAction
        W.previous_onAction = previous
        W.web.onAction = function(data)
            if data and tonumber(data.browserid) == tonumber(W.bid) then
                if data.type == 'WV_STARTED' then
                    W.loaded = false
                elseif data.type == 'WV_LOADED' then
                    W.loaded = true
                    W.schedule_push(40)
                elseif data.type == 'WV_DIE' then
                    W.loaded = false
                    W.created = false
                    W.browser_visible = false
                elseif data.type == 'WV_ANSWER' then
                    local raw = tostring(data.msg or '')
                    local prefix = 'PALATKA_BRIDGE:'
                    local idx = raw:find(prefix, 1, true)
                    if idx then
                        local ok, obj = pcall(decodeJson, raw:sub(idx + #prefix))
                        if ok and type(obj) == 'table' then pcall(W.handle, obj) end
                    end
                end
                return
            end
            if previous then return previous(data) end
        end
        W.bridge_installed = true
    end

    local function create_browser()
        if W.created then return true end
        if not W.web then return false, 'webviews missing' end
        install_bridge()
        local url = 'file://' .. W.html_path .. '?v=' .. W.version
        local ok, e = pcall(function() W.web.createBrowser(W.bid, url) end)
        if not ok then return false, tostring(e) end
        W.created = true
        W.loaded = false
        W.browser_visible = false
        -- Never reuse coordinates from a WebView that Android has recreated.
        W.last_rect = {x=-99999,y=-99999,w=0,h=0}
        local hidden, ret = pcall(function()
            W.web.setClickable(W.bid, false)
            return W.web.setVisible(W.bid, false)
        end)
        if not hidden or ret == false then
            W.geometry_error = 'Cannot hide WebView after creation'
            W.created = false
            return false, W.geometry_error
        end
        return true
    end

    local function browser_to_rect(x, y, w, h)
        if not (W.web and W.created and W.host_open and W.host_open[0]) then return false end
        local r = W.last_rect
        local positioned, sized = true, true
        if r.x ~= x or r.y ~= y then
            local ok, result = pcall(W.web.setPos, W.bid, math.floor(x + .5), math.floor(y + .5))
            positioned = ok and result ~= false
        end
        if r.w ~= w or r.h ~= h then
            local ok, result = pcall(W.web.setSize, W.bid, math.max(1, math.floor(w + .5)), math.max(1, math.floor(h + .5)))
            sized = ok and result ~= false
        end
        if not (positioned and sized) then
            W.geometry_error = 'Cannot place WebView inside its host'
            hide_browser()
            W.last_rect = {x=-99999,y=-99999,w=0,h=0}
            return false
        end
        W.last_rect = {x=x,y=y,w=w,h=h}
        W.geometry_error = nil
        if W.loaded and not W.browser_visible then
            local click_ok, click_result = pcall(W.web.setClickable, W.bid, true)
            local show_ok, show_result = pcall(W.web.setVisible, W.bid, true)
            if not (click_ok and click_result ~= false and show_ok and show_result ~= false) then
                W.geometry_error = 'Cannot display WebView safely'
                hide_browser()
                return false
            end
            W.browser_visible = true
        elseif not W.loaded then
            hide_browser()
        end
        return true
    end

    function W.hide()
        hide_browser()
        W.visible = false
        if W.host_open then W.host_open[0] = false end
        if DSP.ui then DSP.ui.btn_visible = true end
        if W.window_dirty and DSP.save_settings then
            pcall(DSP.save_settings)
            W.window_dirty = false
        end
    end

    function W.show()
        if not (imgui and W.host_open) then
            if legacy_toggle then return legacy_toggle() end
            return false
        end
        if not W.web then
            if DSP.notify then pcall(DSP.notify, 'WebUI: webviews not found; legacy UI opened') end
            if legacy_toggle then return legacy_toggle() end
            return false
        end

        if legacy_set_open then pcall(legacy_set_open, false) end
        if DSP.ui then DSP.ui.btn_visible = false end

        W.host_open[0] = true
        W.visible = true

        ensure_html(function(ok, e)
            if not ok then
                if DSP.notify then pcall(DSP.notify, 'WebUI download failed: ' .. tostring(e)) end
                W.hide()
                if legacy_toggle then legacy_toggle() end
                return
            end
            local c, ce = create_browser()
            if not c then
                if DSP.notify then pcall(DSP.notify, 'WebUI create failed: ' .. tostring(ce)) end
                W.hide()
                if legacy_toggle then legacy_toggle() end
                return
            end
            W.schedule_push(120)
        end)
        return true
    end

    function W.toggle()
        if W.host_open and W.host_open[0] then W.hide() else W.show() end
    end

    function W.open_legacy(screen)
        W.hide()
        if DSP.settings then DSP.settings.screen = screen or DSP.settings.screen end
        if legacy_set_open then legacy_set_open(true)
        elseif legacy_toggle then legacy_toggle() end
    end

    function W.handle(a)
        if type(a) ~= 'table' then return end
        local kind = tostring(a.kind or '')
        if kind == 'close' then
            W.hide()
        elseif kind == 'sync' then
            W.schedule_push(10)
        elseif kind == 'legacy' then
            W.open_legacy(tostring(a.screen or 'settings'))
        elseif kind == 'refresh_market' then
            if DSP.market and DSP.market.pull then pcall(DSP.market.pull, DSP.market.state and DSP.market.state.sid) end
            W.schedule_push(600)
        elseif kind == 'updater_check' then
            if DSP.updater and DSP.updater.check then pcall(DSP.updater.check, false) end
            W.schedule_push(1000)
        elseif kind == 'updater_install' then
            if DSP.updater and DSP.updater.install then pcall(DSP.updater.install) end
        elseif kind == 'storage_price' or kind == 'storage_manual' then
            local R = DSP.storage_registry
            local rec = R and R.get and R.get(tostring(a.storage_id or ''))
            local row = find_row(rec, tostring(a.key or ''))
            if rec and row and R.set_price_mode then
                local mode = kind == 'storage_manual' and 'manual' or tostring(a.mode or 'market')
                pcall(R.set_price_mode, rec.id, row, mode, kind == 'storage_manual' and tonumber(a.price) or nil)
                W.schedule_push(80)
            end
        elseif kind == 'storage_create' then
            local R = DSP.storage_registry
            if R and R.create_pending then
                local name = DSP.to_cp and DSP.to_cp(tostring(a.name or '')) or tostring(a.name or '')
                pcall(R.create_pending, name, tostring(a.storage_kind or 'other'))
                W.schedule_push(100)
            end
        elseif kind == 'storage_bind' then
            local R = DSP.storage_registry
            if R and R.bind_pending then
                pcall(R.bind_pending, tostring(a.storage_id or ''))
                W.schedule_push(100)
            end
        elseif kind == 'storage_cancel' then
            local R = DSP.storage_registry
            if R and R.cancel_pending then pcall(R.cancel_pending) end
            W.schedule_push(80)
        end
    end

    local function draw_host()
        if not (imgui and W.host_open and W.host_open[0]) then return end

        local sw, sh = screen_size()
        local cfg = clamp_host(host_config(), sw, sh)

        if not W.host_initialized then
            imgui.SetNextWindowPos(imgui.ImVec2(cfg.x, cfg.y), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(cfg.w, cfg.h), imgui.Cond.Always)
            W.host_initialized = true
        end

        if imgui.SetNextWindowSizeConstraints then
            local minw = math.min(520, math.max(260, sw - 24))
            local minh = math.min(360, math.max(220, sh - 24))
            imgui.SetNextWindowSizeConstraints(
                imgui.ImVec2(minw, minh),
                imgui.ImVec2(math.max(minw, sw - 10), math.max(minh, sh - 10))
            )
        end

        local flags = (imgui.WindowFlags.NoCollapse or 0)
        local title = u('Palatka AI  •  WebUI')
        local began = imgui.Begin(title .. '##palatka_web_host', W.host_open, flags)
        if began then
            if imgui.SetWindowFontScale then pcall(imgui.SetWindowFontScale, 1.0) end

            imgui.TextDisabled(u('Web dashboard'))
            imgui.SameLine()
            if imgui.SmallButton(u('Обновить##web_reload')) then
                W.loaded = false
                hide_browser()
                if W.web and W.created then
                    pcall(function() W.web.changeUrl(W.bid, 'file://' .. W.html_path .. '?v=' .. W.version .. '&t=' .. tostring(os.time())) end)
                end
            end
            imgui.SameLine()
            if imgui.SmallButton(u('Старый UI##web_legacy')) then
                W.open_legacy(DSP.settings and DSP.settings.screen or 'home')
            end
            imgui.Separator()

            local cp = imgui.GetCursorPos()
            local sp = imgui.GetCursorScreenPos()
            local av = imgui.GetContentRegionAvail()
            local px, py = sp.x, sp.y
            local pw, ph = math.max(1, av.x), math.max(1, av.y)

            if W.created then browser_to_rect(px, py, pw, ph) end

            if W.geometry_error then
                imgui.SetCursorPos(imgui.ImVec2(cp.x + 10, cp.y + 10))
                imgui.TextDisabled(u('WebUI недоступен. Нажми «Старый UI» или /crlegacy.'))
            elseif not W.created then
                imgui.SetCursorPos(imgui.ImVec2(cp.x + 10, cp.y + 10))
                imgui.TextDisabled(u('Подготовка WebUI...'))
            elseif not W.loaded then
                imgui.SetCursorPos(imgui.ImVec2(cp.x + 10, cp.y + 10))
                imgui.TextDisabled(u('Загрузка WebUI...'))
            end

            imgui.SetCursorPos(cp)
            imgui.Dummy(imgui.ImVec2(pw, ph))

            if imgui.GetWindowPos and imgui.GetWindowSize then
                local p = imgui.GetWindowPos()
                local s = imgui.GetWindowSize()
                if p and s then save_host_rect(p.x, p.y, s.x, s.y, false) end
            end
        end
        imgui.End()

        if not W.host_open[0] then
            hide_browser()
            W.visible = false
            if DSP.ui then DSP.ui.btn_visible = true end
            if W.window_dirty and DSP.save_settings then
                pcall(DSP.save_settings)
                W.window_dirty = false
            end
        end
    end

    if imgui and imgui.OnFrame and W.host_open and not W.host_frame_registered then
        W.host_frame_registered = true
        imgui.OnFrame(
            function()
                return W.host_open and W.host_open[0]
            end,
            draw_host
        )
    end

    local function install_ui_hooks()
        if W.hooks_installed then return true end
        if not (DSP.ui and DSP.ui.toggle and DSP.ui.set_open) then return false end

        legacy_toggle = DSP.ui.toggle
        legacy_set_open = DSP.ui.set_open

        W.toggle_proxy = function() return W.toggle() end
        W.set_open_proxy = function(v)
            if v then return W.show() else return W.hide() end
        end

        DSP.ui.toggle = W.toggle_proxy
        DSP.ui.set_open = W.set_open_proxy
        W.hooks_installed = true

        if DSP.flog then DSP.flog('WEBUI floating host hooks installed after ui.install') end
        return true
    end

    local function notify_rescue(msg)
        if sampAddChatMessage then pcall(sampAddChatMessage, '[Palatka] ' .. msg, 0xFFD166)
        elseif DSP.notify then pcall(DSP.notify, msg) end
    end

    -- These commands remain usable without touching the embedded WebView.
    local rescue = {
        crhide = function()
            W.hide()
            notify_rescue('WebUI hidden; /crweb to reopen')
        end,
        crweb = function() W.toggle() end,
        crlegacy = function()
            W.open_legacy(DSP.settings and DSP.settings.screen or 'home')
            notify_rescue('Legacy UI opened')
        end,
        crresetui = function()
            W.hide()
            local cfg = host_config()
            cfg.x, cfg.y, cfg.w, cfg.h = nil, nil, nil, nil
            W.host_initialized = false
            if DSP.save_settings then pcall(DSP.save_settings) end
            notify_rescue('WebUI position reset')
        end,
        crversion = function()
            notify_rescue(tostring(DSP.version) .. ' / HTML ' .. tostring(W.version))
        end
    }

    local function install_rescue_commands()
        if type(sampRegisterChatCommand) ~= 'function' then return false end
        for name, callback in pairs(rescue) do
            if not W.registered_rescue_commands[name] then
                local ok = pcall(sampRegisterChatCommand, name, function()
                    local success, err = pcall(callback)
                    if not success then notify_rescue(tostring(err)) end
                end)
                if ok then W.registered_rescue_commands[name] = true end
            end
        end
        return true
    end

    hide_browser()
    if lua_thread and lua_thread.create and wait then
        lua_thread.create(function()
            for _ = 1, 40 do
                wait(250)
                local hooks_ready = install_ui_hooks()
                local commands_ready = install_rescue_commands()
                if hooks_ready and commands_ready then break end
            end
            install_bridge()
            ensure_html(function(ok, e)
                if DSP.flog then DSP.flog('WEBUI html refresh: ' .. tostring(ok) .. ' ' .. tostring(e or '')) end
            end)
        end)
    else
        install_bridge()
        install_ui_hooks()
        install_rescue_commands()
    end

    DSP.version = '2.6.4-legible-webui'
    if DSP.flog then DSP.flog('WEBUI overlay v2.6.4 loaded; legible mobile UI and rescue commands') end
    return true
end
