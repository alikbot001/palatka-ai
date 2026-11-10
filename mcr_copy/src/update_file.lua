-- Android/POSIX: rename the verified staged file over the running Lua atomically.
-- A separate complete backup is created first; settings are never touched.
return function(path,body,ops)
    if type(path)~='string'or not path:match('%.lua$')then return false,'Неизвестен путь Lua'end
    local rename=ops and ops.rename or os.rename
    local function write(name,bytes)
        local f,err=io.open(name,'wb');if not f then return false,err end
        local ok,why=f:write(bytes);local closed,close_err=f:close()
        if not ok or not closed then return false,why or close_err end
        return true
    end
    local stage=path..'.crr-new'
    local staged,why=write(stage,body);if not staged then return false,why end
    local old,err=io.open(path,'rb');if not old then return false,err end
    local backup,open_err=io.open(path..'.crr-backup.tmp','wb')
    if not backup then old:close();return false,open_err end
    while true do
        local chunk,read_err=old:read(65536)
        if not chunk then
            if read_err then old:close();backup:close();return false,read_err end
            break
        end
        local saved,save_err=backup:write(chunk)
        if not saved then old:close();backup:close();return false,save_err end
    end
    old:close()
    local closed,close_err=backup:close();if not closed then return false,close_err end
    local backed,backup_err=rename(path..'.crr-backup.tmp',path..'.crr-backup')
    if not backed then return false,backup_err end
    local installed,install_err=rename(stage,path)
    if not installed then return false,'Оригинал сохранён; замена не выполнена: '..tostring(install_err)end
    return true
end
