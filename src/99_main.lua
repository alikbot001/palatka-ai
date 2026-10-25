-- Main entry: catalog, price base, market, UI, live hooks, overlay.
if not imgui then
    local ok, m = pcall(require, 'mimgui')
    if ok then imgui = m end
end

DSP.items.load()
DSP.db.load()
DSP.logs.load()
DSP.market.load()
DSP.auto.install()
DSP.ui.install()
DSP.live.install()
DSP.overlay.install()
DSP.logs.install()
DSP.notify('palatka ai v' .. DSP.version .. ': /crr')

if lua_thread and wait and DSP.detect_server then
    lua_thread.create(function()
        while true do
            wait(10000)
            local sid = DSP.detect_server()
            local nick = DSP.player_nick()
            local nick_changed = nick ~= 'DsPic' and nick ~= (DSP.market.state.nick or '')
            if DSP.market.state.status ~= 'loading'
                and ((sid and sid ~= (DSP.market.state.sid or 0)) or nick_changed) then
                sid = sid or DSP.market.state.sid
                DSP.flog('MARKET refresh sid=' .. tostring(sid) .. ' nick=' .. tostring(nick))
                DSP.market.pull(sid)
            end
        end
    end)
end
