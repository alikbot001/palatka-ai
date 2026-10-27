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
safe('promo.install', function() DSP.promo.install() end)
safe('shop_marker.install', function() DSP.shop_marker.install() end)
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
