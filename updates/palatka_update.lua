-- Palatka AI v2.7.0: restore the native v2.5.2 mimgui interface.
-- This rollback release intentionally contains no WebUI hooks or browser UI.
-- The update manager reloads the base Lua after installing this overlay.
PALATKA_UPDATE_VERSION = '2.7.0'

return function(DSP)
    -- Best effort: clean up a WebView retained by the previous overlay.
    local W = DSP.webui
    if W and type(W.hide) == 'function' then pcall(W.hide) end
    local ok, web = pcall(require, 'webviews')
    if ok and web then
        local id = 95253
        if type(web.setClickable) == 'function' then pcall(web.setClickable, id, false) end
        if type(web.setVisible) == 'function' then pcall(web.setVisible, id, false) end
        if type(web.setPos) == 'function' then pcall(web.setPos, id, -99999, -99999) end
        if type(web.setSize) == 'function' then pcall(web.setSize, id, 1, 1) end
    end
    -- Leave presets, settings, market cache, saved storages and trading runtime untouched.
    DSP.version = '2.7.0'
    if DSP.flog then pcall(DSP.flog, 'Rollback to native mimgui UI (v2.5.2 base)') end
    return true
end
