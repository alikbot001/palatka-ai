PALATKA_UPDATE_VERSION = '2.6.2-webui-loader-fix'

return function(DSP)
    DSP.webui = DSP.webui or {}
    local W = DSP.webui

    W.version = '1.2-loader-fix'
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

    local legacy_toggle = DSP.ui and DSP.ui.toggle
    local legacy_set_open = DSP.ui and DSP.ui.set_open
    local ok_web, web = pcall(require, 'webviews')
    W.web = ok_web and web or nil
    local ok_b64, basexx = pcall(require, 'basexx')

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
        pcall(os.remove, path)
        local rn, re = os.rename(tmp, path)
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
        local ok3 = pcall(function() W.web.executeJS(W.bid, js) end)
        return ok3
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

    local function ensure_html(done)
        local current = read_file(W.version_path)
        local html = read_file(W.html_path)
        if current == W.version and html and #html > 2000 then
            done(true)
            return
        end
        if not DSP.http_get then
            done(false, 'HTTP unavailable')
            return
        end
        DSP.http_get(W.html_url, function(body, err, code)
            if not body or #body < 2000 then
                done(false, tostring(err or ('HTTP ' .. tostring(code or 0))))
                return
            end
            local ok, e = write_file(W.html_path, body)
            if not ok then done(false, tostring(e)); return end
            write_file(W.version_path, W.version)
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
                    W.visible = false
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
        local sw, sh = screen_size()
        pcall(function()
            W.web.setPos(W.bid, 0, 0)
            W.web.setSize(W.bid, sw, sh)
        end)
        return true
    end

    function W.hide()
        if W.web and W.created then
            pcall(function()
                W.web.setClickable(W.bid, false)
                W.web.setVisible(W.bid, false)
            end)
        end
        W.visible = false
        if DSP.ui then DSP.ui.btn_visible = true end
    end

    function W.show()
        if not W.web then
            if DSP.notify then pcall(DSP.notify, 'WebUI: webviews not found; legacy UI opened') end
            if legacy_toggle then return legacy_toggle() end
            return false
        end
        if legacy_set_open then pcall(legacy_set_open, false) end
        if DSP.ui then DSP.ui.btn_visible = false end
        ensure_html(function(ok, e)
            if not ok then
                if DSP.ui then DSP.ui.btn_visible = true end
                if DSP.notify then pcall(DSP.notify, 'WebUI download failed: ' .. tostring(e)) end
                if legacy_toggle then legacy_toggle() end
                return
            end
            local c, ce = create_browser()
            if not c then
                if DSP.ui then DSP.ui.btn_visible = true end
                if DSP.notify then pcall(DSP.notify, 'WebUI create failed: ' .. tostring(ce)) end
                if legacy_toggle then legacy_toggle() end
                return
            end
            local sw, sh = screen_size()
            pcall(function()
                W.web.setPos(W.bid, 0, 0)
                W.web.setSize(W.bid, sw, sh)
                W.web.setClickable(W.bid, true)
                W.web.setVisible(W.bid, true)
            end)
            W.visible = true
            W.schedule_push(120)
        end)
        return true
    end

    function W.toggle()
        if W.visible then W.hide() else W.show() end
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

    local function install_ui_hooks()
        if W.hooks_installed then return end
        if not (DSP.ui and DSP.ui.toggle and DSP.ui.set_open) then return end

        legacy_toggle = DSP.ui.toggle
        legacy_set_open = DSP.ui.set_open

        DSP.ui.toggle = function()
            return W.toggle()
        end
        DSP.ui.set_open = function(v)
            if v then return W.show() else return W.hide() end
        end
        W.hooks_installed = true
        if DSP.flog then DSP.flog('WEBUI hooks installed after ui.install') end
    end

    if lua_thread and lua_thread.create and wait then
        lua_thread.create(function()
            wait(1800)
            install_bridge()
            install_ui_hooks()
            ensure_html(function(ok, e)
                if DSP.flog then DSP.flog('WEBUI html refresh: ' .. tostring(ok) .. ' ' .. tostring(e or '')) end
            end)
        end)
    else
        install_bridge()
        install_ui_hooks()
    end

    DSP.version = '2.6.2-webui-loader-fix'
    if DSP.flog then DSP.flog('WEBUI overlay v2.6.2 loaded; waiting for post-install hook') end
    return true
end
