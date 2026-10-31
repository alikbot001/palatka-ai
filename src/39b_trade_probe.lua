-- Opt-in, read-only trade protocol trace. Never sends packets or replies to dialogs.
-- This diagnoses Arizona client versions whose UI IDs differ from the preset engine.
DSP.trade_probe = DSP.trade_probe or {}
local P = DSP.trade_probe
P.active, P.until_at, P.events = false, 0, 0
P.limit = 100
local function log(s)
    if DSP.flog then DSP.flog('TRADE TRACE: ' .. tostring(s)) end
end
local function enabled()
    if not P.active then return false end
    if os.time() >= P.until_at or P.events >= P.limit then
        P.active = false
        log('STOP auto: timed out or 100 event limit')
        return false
    end
    return true
end
local function record(s)
    if not enabled() then return end
    P.events = P.events + 1
    log(('#%d %s'):format(P.events, tostring(s)))
end
function P.stop()
    P.active = false
    log('STOP manual; recorded='..tostring(P.events))
    if DSP.notify then DSP.notify('Трассировка торговли остановлена. Лог: PalatkaAI/standalone.log') end
end
function P.start()
    P.active = true
    P.until_at = os.time() + 120
    P.events = 0
    log('START for 120 seconds: manually open your own stall, sale and buy UI; then /crrtrace')
    if DSP.notify then DSP.notify('Трассировка 120 сек. Открой лавку, затем вручную продажу и скупку. /crrtrace = стоп') end
end
function P.toggle()
    if enabled() then P.stop() else P.start() end
end
-- Passive packet hook: ONLY capture the 220/63 message envelope and slots.
-- Never log text/JSON payload, never mutate packet data, restore read cursor.
function P.outgoing_packet(id, bs)
    if not enabled() or tonumber(id) ~= 220 then return end
    local get, set = raknetBitStreamGetReadOffset, raknetBitStreamSetReadOffset
    local read8, read32 = raknetBitStreamReadInt8, raknetBitStreamReadInt32
    if type(get)~='function' or type(set)~='function'
        or type(read8)~='function' or type(read32)~='function' then
        record('outgoing packet id=220 (metadata API unavailable)')
        return
    end
    local ok, info = pcall(function()
        local original = get(bs)
        local parsed_ok, parsed = pcall(function()
            set(bs, 0)
            local msg = read8(bs)
            local marker = read8(bs)
            if msg~=220 or marker~=63 then return 'packet=220 marker='..tostring(marker) end
            local iface = read8(bs)
            local slot = read32(bs)
            local subid = read32(bs)
            return ('packet=220 marker=63 interface=%s slot=%s subid=%s'):format(tostring(iface),tostring(slot),tostring(subid))
        end)
        set(bs, original)
        if parsed_ok then return parsed end
        return 'packet=220 parse-error (cursor restored)'
    end)
    if ok then record('OUT ' .. tostring(info)) else record('OUT packet=220 (read error)') end
end
-- Snapshot diagnostics, not a synthetic scan. Helps distinguish packets seen,
-- a saved local quote, missing stall metadata and trade preview mode.
function P.diagnostics()
    local live=DSP.live or {}
    local shop=live.shop or {}
    local state,visible='unknown',0
    if live.scan_state then
        local ok,a,b=pcall(live.scan_state,shop)
        if ok then state,visible=a,b or 0 else state='state_error' end
    end
    local stats={shops=0,offers=0}
    if DSP.local_arb and DSP.local_arb.stats then
        local ok,s=pcall(DSP.local_arb.stats)
        if ok and type(s)=='table' then stats=s end
    end
    local auto=(DSP.settings and DSP.settings.auto_shop_scan~=false) and 'on' or 'off'
    local mode=(DSP.settings and DSP.settings.dry_run) and 'TEST' or 'REAL'
    local sid=DSP.settings and DSP.settings.server or 0
    local tr=DSP.trade_runtime and DSP.trade_runtime.snapshot and DSP.trade_runtime.snapshot() or {phase='idle'}
    local lst=DSP.lombard and DSP.lombard.stats and DSP.lombard.stats() or {items=0,pages=0,history_items=0}
    local report=('server=%s autoscan=%s state=%s shop=%s visible=%d sell=%d buy=%d db_shops=%d db_offers=%d db_pending_disk=%s trade=%s phase=%s lombard=%d/%d hist=%d')
      :format(tostring(sid),auto,tostring(state),tostring(shop.num or '?'),tonumber(visible) or 0,
        #(shop.sell or {}),#(shop.buy or {}),tonumber(stats.shops) or 0,
        tonumber(stats.offers) or 0,tostring(DSP.local_arb and DSP.local_arb._dirty==true),mode,tostring(tr.phase or 'idle'),tonumber(lst.items) or 0,tonumber(lst.pages) or 0,tonumber(lst.history_items) or 0)
    if DSP.flog then DSP.flog('FULL DIAG: '..report) end
    if DSP.notify then DSP.notify('[Palatka] '..report) end
    return report
end
function P.install()
    if P.installed then return end
    P.installed = true
    if sampRegisterChatCommand then
        local ok, err = pcall(sampRegisterChatCommand, 'crrtrace', P.toggle)
        log('command /crrtrace registered='..tostring(ok)..(not ok and ' '..tostring(err) or ''))
        local diag_ok,diag_err=pcall(sampRegisterChatCommand,'crrdiag',P.diagnostics)
        log('command /crrdiag registered='..tostring(diag_ok)..(not diag_ok and ' '..tostring(diag_err) or ''))
    end
    if addEventHandler then
        local ok, err = pcall(addEventHandler, 'onSendPacket', P.outgoing_packet)
        log('onSendPacket registered='..tostring(ok)..(not ok and ' '..tostring(err) or ''))
        local rpc_ok, rpc_err = pcall(addEventHandler, 'onSendRpc', function(id)
            if enabled() then record('OUT RPC id='..tostring(id)) end
        end)
        log('onSendRpc registered='..tostring(rpc_ok)..(not rpc_ok and ' '..tostring(rpc_err) or ''))
    end
    local ok, sampev = pcall(require, 'samp.events')
    if ok and type(sampev)=='table' then
        local prev_show = sampev.onShowDialog
        sampev.onShowDialog = function(id, style, title, b1, b2, content)
            if enabled() then
                -- Title and length only; never log contents, inputs, or credentials.
                local safe_title = tostring(title or ''):gsub('[\r\n]', ' '):sub(1, 70)
                record(('IN DIALOG id=%s style=%s title=%s size=%s'):format(tostring(id),tostring(style),safe_title,#tostring(content or '')))
            end
            if prev_show then return prev_show(id, style, title, b1, b2, content) end
        end
        local prev_response = sampev.onSendDialogResponse
        sampev.onSendDialogResponse = function(id, button, list, input)
            if enabled() then record(('OUT DIALOG id=%s button=%s row=%s input_length=%d')
                :format(tostring(id),tostring(button),tostring(list),#tostring(input or ''))) end
            if prev_response then return prev_response(id, button, list, input) end
        end
        log('dialog metadata hooks installed')
    else
        log('samp.events unavailable; dialog trace disabled')
    end
end