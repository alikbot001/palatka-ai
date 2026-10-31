-- Palatka Settings Safety: protect user preferences on every OTA update.
-- Install after core; do not replace, reset or filter unknown setting keys.
local G = DSP.settings_safety or {}
DSP.settings_safety = G
if not G.installed then
    local path = DSP.settings_path
    local original_save = DSP.save_settings

    local function read_all(filename)
        local f=io.open(filename,'rb')
        if not f then return nil end
        local data=f:read('*a')
        f:close()
        return data
    end
    local function valid_json(raw)
        if type(raw)~='string' or #raw==0 then return false end
        local ok,result=pcall(decodeJson,raw)
        return ok and type(result)=='table'
    end
    local function write_bytes(filename,data)
        local f,err=io.open(filename,'wb')
        if not f then return false,tostring(err or 'cannot open') end
        local wrote,e=f:write(data)
        local closed,close_err=f:close()
        if not wrote or not closed then return false,tostring(e or close_err) end
        local copy=read_all(filename)
        if copy~=data then return false,'verification mismatch' end
        return true
    end
    local function backup_valid(source,target)
        local raw=read_all(source)
        if not raw or not valid_json(raw) then return false,'invalid source' end
        local tmp=target..'.tmp'
        local ok,err=write_bytes(tmp,raw)
        if not ok then return false,err end
        -- Moving the last valid backup aside must never delete it.
        local existing=read_all(target)
        if existing and valid_json(existing) then
            local keep=target..'.previous'
            pcall(os.remove,keep)
            local moved= os.rename(target,keep)
            if not moved then pcall(os.remove,tmp);return false,'cannot rotate backup' end
        end
        local renamed,e=os.rename(tmp,target)
        if not renamed then
            pcall(os.remove,tmp)
            if existing and valid_json(existing) then pcall(os.rename,target..'.previous',target) end
            return false,tostring(e or 'cannot store backup')
        end
        return true
    end

    -- Back up the last known-good settings, including fields from future
    -- versions, BEFORE installing new default keys in any subsequent update.
    function G.checkpoint(tag)
        if type(path)~='string' then return false,'settings path missing' end
        local raw=read_all(path)
        if not raw then return true,'no settings yet' end
        if not valid_json(raw) then return false,'settings invalid: no overwrite' end
        local safe=tostring(tag or 'before_update'):gsub('[^%w_%-]','_')
        local snapshot=path..'.checkpoint_'..safe
        if read_all(snapshot) then return true,snapshot end
        local ok,e=write_bytes(snapshot..'.tmp',raw)
        if not ok then return false,e end
        local renamed,err=os.rename(snapshot..'.tmp',snapshot)
        if not renamed then return false,tostring(err or 'checkpoint rename failed') end
        return true,snapshot
    end

    -- File may be corrupt after a crash: NEVER save defaults over it.
    function DSP.save_settings()
        if type(path)~='string' or type(DSP.settings)~='table' then
            return false,'invalid settings state'
        end
        local existing=read_all(path)
        if existing and not valid_json(existing) then
            if DSP.flog then pcall(DSP.flog,'SETTINGS SAFETY: existing JSON corrupt; refusing overwrite') end
            return false,'Existing settings invalid; preserved for recovery'
        end
        local ok,json=pcall(encodeJson,DSP.settings)
        if not ok or not valid_json(json) then return false,'settings encoding invalid' end
        local temp=path..'.safe_new'
        local wrote,err=write_bytes(temp,json)
        if not wrote then return false,err end
        if existing then
            local saved,why=backup_valid(path,path..'.bak')
            if not saved then pcall(os.remove,temp);return false,'backup failed: '..tostring(why) end
            -- Android does not guarantee rename-over-existing.
            local old=path..'.old'
            pcall(os.remove,old)
            local moved,why2=os.rename(path,old)
            if not moved then pcall(os.remove,temp);return false,'cannot move old settings: '..tostring(why2) end
            local placed,why3=os.rename(temp,path)
            if not placed then
                pcall(os.rename,old,path)
                pcall(os.remove,temp)
                return false,'cannot replace settings: '..tostring(why3)
            end
            pcall(os.remove,old)
        else
            local placed,why=os.rename(temp,path)
            if not placed then pcall(os.remove,temp);return false,'cannot install settings: '..tostring(why) end
        end
        return true
    end

    -- Protect the second settings file too: window position, CR button
    -- placement, theme and opacity must survive application updates.
    if type(DSP.ui_state_path)=='string' then
        local ui_path=DSP.ui_state_path
        local ui_raw=read_all(ui_path)
        if ui_raw and valid_json(ui_raw) then
            local checkpoint=ui_path..'.checkpoint_v283'
            if not read_all(checkpoint) then
                local copied=write_bytes(checkpoint..'.tmp',ui_raw)
                if copied then pcall(os.rename,checkpoint..'.tmp',checkpoint) end
            end
        end
        DSP.save_ui_state=function()
            local previous=read_all(ui_path)
            if previous and not valid_json(previous) then
                return false,'Existing UI state corrupt; preserving file'
            end
            local pack={
                cr_pos=DSP.settings.cr_pos or {x=28,y=215},
                screen=DSP.settings.screen or 'palatka',
                theme=(DSP.theme and DSP.theme.current) or DSP.settings.theme,
                opacity=(DSP.theme and DSP.theme.opacity) or DSP.settings.opacity,
                saved_at=os.time()
            }
            local encoded,body=pcall(encodeJson,pack)
            if not encoded or not valid_json(body) then return false,'Invalid UI state JSON' end
            local temp=ui_path..'.safe_new'
            local wrote,err=write_bytes(temp,body)
            if not wrote then return false,err end
            if previous then
                local backed,why=backup_valid(ui_path,ui_path..'.bak')
                if not backed then pcall(os.remove,temp);return false,'UI backup failed: '..tostring(why) end
                local old=ui_path..'.old'
                pcall(os.remove,old)
                local moved,why2=os.rename(ui_path,old)
                if not moved then pcall(os.remove,temp);return false,'UI move failed: '..tostring(why2) end
                local renamed,why3=os.rename(temp,ui_path)
                if not renamed then
                    pcall(os.rename,old,ui_path)
                    pcall(os.remove,temp)
                    return false,'UI write failed: '..tostring(why3)
                end
                pcall(os.remove,old)
            else
                local renamed,why=os.rename(temp,ui_path)
                if not renamed then pcall(os.remove,temp);return false,tostring(why) end
            end
            return true
        end
    end

    -- Old files can contain a richer schema than the current build.
    -- Do not enumerate or discard unknown settings during an update.
    G.installed=true
    G.original_save=original_save
    local ok,detail=G.checkpoint('v283')
    if DSP.flog then
        pcall(DSP.flog,'SETTINGS SAFETY checkpoint: '..tostring(ok)..' '..tostring(detail))
    end
end
