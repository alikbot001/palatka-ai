-- v2.9.4: persist theme and opacity across OTA, game restart and UI snapshots.
-- This overlay is also applied to existing 2.9.3 installations whose core is loaded.
local G=DSP.settings_persistence_v294 or {}
DSP.settings_persistence_v294=G
if G.installed then return true end

-- Recover the selected appearance from the authoritative settings file even if
-- an older core has already overlaid it with stale ui_state.json at startup.
local function read_selected()
    local path=DSP.settings_path
    if type(path)~='string' then return end
    local f=io.open(path,'rb')
    if not f then return end
    local body=f:read('*a')
    f:close()
    local ok,saved=pcall(decodeJson,body or'')
    if not ok or type(saved)~='table' then return end
    if type(saved.theme)=='string' and DSP.theme.list[saved.theme] then
        DSP.theme.current=saved.theme
        DSP.settings.theme=saved.theme
    end
    if type(saved.opacity)=='number' then
        DSP.theme.opacity=DSP.clamp(saved.opacity,0.65,1)
        DSP.settings.opacity=DSP.theme.opacity
    end
end
read_selected()

local function persist_appearance()
    if not DSP.save_ui_state then return true end
    local ok,why=DSP.save_ui_state()
    if not ok and DSP.flog then DSP.flog('APPEARANCE UI STATE SAVE FAILED: '..tostring(why))end
    return ok,why
end

function DSP.theme.set(name)
    if not DSP.theme.list[name] then return false,'Неизвестная тема'end
    local old=DSP.theme.current
    DSP.theme.current=name
    DSP.settings.theme=name
    local ok,why=DSP.save_settings()
    if not ok then
        DSP.theme.current=old
        DSP.settings.theme=old
        if DSP.flog then DSP.flog('APPEARANCE SAVE FAILED: '..tostring(why))end
        return false,why
    end
    persist_appearance()
    return true
end
function DSP.theme.set_opacity(value)
    local old=DSP.theme.opacity
    local next=DSP.clamp(tonumber(value)or 0.97,0.65,1)
    DSP.theme.opacity=next
    DSP.settings.opacity=next
    local ok,why=DSP.save_settings()
    if not ok then
        DSP.theme.opacity=old
        DSP.settings.opacity=old
        if DSP.flog then DSP.flog('OPACITY SAVE FAILED: '..tostring(why))end
        return false,why
    end
    persist_appearance()
    return true
end

-- Explicit save action and deferred changes use the same durable primary file.
if DSP.mobile and not G.flush_wrapped then
    local M=DSP.mobile
    local old_flush=M.flush_save
    if type(old_flush)=='function' then
        M.flush_save=function(force)
            local result=old_flush(force)
            if M._save_pending and DSP.flog then
                local now=os.time()
                if force or not G.last_warning or now-G.last_warning>15 then
                    G.last_warning=now
                    DSP.flog('PERSISTENCE: pending save retry, primary write failed')
                end
            end
            return result
        end
    end
    G.flush_wrapped=true
end
G.installed=true
return true
