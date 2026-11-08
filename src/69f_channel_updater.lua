-- Palatka AI Stable/Beta installer (MonetLoader and MoonLoader compatible).
-- Channels are manifests on separate GitHub branches. No silent updates.
-- The running Lua file is never touched until a complete download is verified.
local CM={}
DSP.channels=CM
local V,U,M=DSP.ui21,DSP.ui,DSP.mobile
local ROOT='https://raw.githubusercontent.com/alikbot001/palatka-ai/'
local MANIFEST={
    stable=ROOT..'main/updates/channels/stable.json',
    beta=ROOT..'beta/updates/channels/beta.json',
}
CM.selected=(DSP.settings and DSP.settings.update_channel)=='beta' and 'beta' or 'stable'
CM.state='idle'
CM.message='Выбери канал и нажми «Проверить».'
CM.progress=0
CM.total=0
CM.manifest=nil
CM.busy=false
CM.done=false

local function say(s)
    CM.message=tostring(s or '')
    if DSP.flog then DSP.flog('CHANNEL: '..CM.message) end
end
local function put_state(state,message)
    CM.state=state
    if message then say(message)end
end
local function file_size(path)
    local f=io.open(path,'rb')
    if not f then return nil end
    local size=f:seek('end');f:close()
    return size
end
local function read_small(path,max)
    local f=io.open(path,'rb')
    if not f then return nil end
    local data=f:read(max+1);f:close()
    if not data or #data>max then return nil end
    return data
end
-- Whitelisted origin and branch, including the exact expected Lua filename.
function CM.allowed_url(channel,url)
    if type(url)~='string' then return false end
    local branch=channel=='stable' and 'main' or 'beta'
    return url==ROOT..branch..'/palatka_ai.lua'
end
local function valid_manifest(data,channel)
    if type(data)~='table' or data.schema~=1 or data.channel~=channel then
        return nil,'Неверный формат манифеста' end
    if type(data.version)~='string' or #data.version>40
        or not data.version:match('^%d+%.%d+%.%d+[%w%.%-]*$') then
        return nil,'Некорректная версия' end
    if not CM.allowed_url(channel,data.url) then
        return nil,'Неизвестный адрес обновления' end
    local size=tonumber(data.size)
    if not size or size~=math.floor(size) or size<500000 or size>95000000 then
        return nil,'Некорректный размер выпуска' end
    if type(data.sha256)~='string' or not data.sha256:match('^[a-fA-F0-9]+$')
       or #data.sha256~=64 then return nil,'SHA256 отсутствует' end
    return {version=data.version,channel=channel,url=data.url,
        size=size,sha256=data.sha256:lower(),notes=tostring(data.notes or '')}
end
function CM.select(channel)
    if channel~='stable' and channel~='beta' or CM.busy then return false end
    CM.selected=channel
    CM.manifest=nil
    CM.state='idle'
    CM.message='Канал '..(channel=='stable' and 'Stable' or 'Beta')..
        '. Нажми «Проверить».'
    DSP.settings.update_channel=channel
    if M and M.defer_save then M.defer_save() end
    return true
end
local function path_of_script()
    if type(thisScript)~='function' then return nil end
    local ok,s=pcall(thisScript)
    if not ok or not s or type(s.path)~='string' or s.path=='' then return nil end
    if not s.path:match('%.lua$') then return nil end
    return s.path
end
function CM.verify_file(path,manifest)
    if file_size(path)~=manifest.size then
        return false,'Размер загруженного файла не совпадает с выпуском' end
    local f=io.open(path,'rb')
    if not f then return false,'Не удалось прочитать скачанный Lua' end
    local head=f:read(1000) or ''
    f:seek('end',-math.min(manifest.size,128))
    local tail=f:read(128)or ''
    f:close()
    if not head:find("script_name%('palatka ai'%)")
       or not head:find("script_version('"..manifest.version.."')",1,true)
       or not head:find("Palatka AI",1,true)
       or not tail:find(']=]',1,true) then
        return false,'Файл не похож на полный Palatka AI Lua' end
    -- A native SHA-256 backend is not guaranteed on MonetLoader; the
    -- release manifest includes a digest for independent verification,
    -- while this installer enforces HTTPS origin, exact size and header.
    return true
end
local function safe_replace(temp,desired)
    local backup=desired..'.bak'
    if file_size(temp)==nil then return false,'Временный файл не найден' end
    os.remove(backup)
    local moved,err=os.rename(desired,backup)
    if not moved then return false,'Не удалось создать копию: '..tostring(err)end
    local installed,why=os.rename(temp,desired)
    if not installed then
        local restored,restore_err=os.rename(backup,desired)
        return false,'Не удалось заменить Lua: '..tostring(why)..
            (restored and '; оригинал восстановлен' or
                '; восстанови резервную копию вручную: '..tostring(restore_err))
    end
    return true,backup
end
local function native_download(url,path,cb)
    if type(downloadUrlToFile)~='function' then
        cb(false,'В MonetLoader нет функции downloadUrlToFile');return
    end
    pcall(os.remove,path)
    local complete=false
    local ok,err=pcall(downloadUrlToFile,url,path,function(_,status,received,total)
        if complete then return end
        if status==5 then
            CM.progress=tonumber(received)or 0
            CM.total=tonumber(total)or 0
        elseif status==6 then
            complete=true;cb(true)
        elseif status==58 then
            complete=true;cb(false,'Загрузка не завершена (сеть или сервер)')
        end
    end)
    if not ok and not complete then cb(false,'Ошибка загрузчика: '..tostring(err))end
end
function CM.check()
    if CM.busy then return false end
    local path=path_of_script()
    if not path then put_state('error','Путь текущего Lua недоступен в MonetLoader');return false end
    local channel=CM.selected
    local target=path..'.channel.json.tmp'
    CM.busy=true;CM.manifest=nil
    put_state('checking','Проверяю '..channel..'...')
    native_download(MANIFEST[channel],target,function(ok,err)
        CM.busy=false
        if not ok then
            pcall(os.remove,target)
            return put_state('error',err or 'Не удалось скачать описание выпуска')
        end
        local body=read_small(target,8192)
        pcall(os.remove,target)
        if not body then return put_state('error','Пустой или слишком большой манифест')end
        local decoded,parsed=pcall(decodeJson,body)
        if not decoded then return put_state('error','Не удалось прочитать JSON: '..tostring(parsed))end
        local info,reason=valid_manifest(parsed,channel)
        if not info then return put_state('error',reason)end
        CM.manifest=info
        put_state('ready',('Найден %s %s; файл %.1f МБ'):format(
            channel,info.version,info.size/1048576))
    end)
    return true
end
function CM.install()
    if CM.busy or CM.state~='ready' or not CM.manifest
        or CM.manifest.channel~=CM.selected then return false end
    if DSP.auto and (DSP.auto.sell_running or DSP.auto.buy_running)then
        put_state('error','Останови торговую очередь перед установкой');return false
    end
    local path=path_of_script()
    if not path then put_state('error','MonetLoader не сообщил путь скрипта');return false end
    local info=CM.manifest
    local temp=path..'.new'
    CM.busy=true;CM.progress=0;CM.total=info.size
    put_state('downloading','Скачиваю '..info.channel..' '..info.version)
    native_download(info.url,temp,function(ok,err)
        CM.busy=false
        if not ok then
            pcall(os.remove,temp)
            return put_state('error',err or 'Загрузка прервана')
        end
        put_state('verifying','Проверяю скачанный Lua...')
        local verified,reason=CM.verify_file(temp,info)
        if not verified then
            pcall(os.remove,temp)
            return put_state('error',reason)
        end
        -- Settings and presets are in separate JSON files and survive changes.
        if DSP.save_settings then
            local called,saved=pcall(DSP.save_settings)
            if not called or saved==false then
                pcall(os.remove,temp)
                return put_state('error','Не удалось сохранить настройки')
            end
        end
        local installed,backup=safe_replace(temp,path)
        if not installed then return put_state('error',backup)end
        CM.done=true
        put_state('installed','Установлено: '..info.version..
            ' ('..info.channel..'). Перезапусти игру. Копия: '..backup)
        if DSP.notify then DSP.notify('Palatka AI: версия установлена. Перезапусти игру.')end
    end)
    return true
end
local function render()
    local w=imgui.GetContentRegionAvail().x
    V.text('Канал выпуска')
    if V.button('Stable','channel_stable',math.max(70,math.min(154,w*.44)),CM.selected=='stable')then
        CM.select('stable')
    end
    V.inline(7)
    if V.button('Beta','channel_beta',math.max(70,math.min(154,w*.44)),CM.selected=='beta')then
        CM.select('beta')
    end
    V.muted('Текущая база: v'..tostring(DSP.version)..' · канал '..CM.selected)
    V.muted(V.fit('Stable: основной выпуск; Beta: тестовые функции без изменений main.',w))
    if CM.state=='downloading' then
        local per=(CM.total>0)and math.floor(CM.progress*100/CM.total)or 0
        V.muted('Загрузка '..math.min(100,math.max(0,per))..'%')
    end
    if CM.state=='error' then V.red(V.fit(CM.message,w))
    else V.muted(V.fit(CM.message,w))end
    if not CM.busy and CM.state~='installed' then
        if V.button('Проверить канал','channel_check',math.min(210,w),false,true)then CM.check()end
        if CM.state=='ready' then
            V.text('Установка заменит текущий Lua после создания .bak-копии.')
            if V.button('Установить '..CM.selected,'channel_install',math.min(230,w),false,true)then
                CM.install()
            end
        end
    end
    if CM.state=='installed' then V.green('Перезапусти игру, чтобы загрузить выбранную версию.')end
    V.muted('Ручной запуск, без фонового обновления и автозапуска торговли.')
end
CM.render=render
if V.mcr_updates then V.mcr_updates=render end
local old_tools=V.tools
if old_tools then
    V.tools=function(screen)
        if screen=='settings' then
            if V.button('Версии: Stable / Beta','channel_open_in_settings',math.min(270,imgui.GetContentRegionAvail().x),false,true,37)then
                V.open_popup('Обновление Palatka AI','channel_manager')
            end
        end
        return old_tools(screen)
    end
end
local old_popups=V.popups
V.popups=function()
    if old_popups then old_popups()end
    V.popup('Обновление Palatka AI','channel_manager',render,{w=655,h=365})
end
function CM.install_command()
    if sampRegisterChatCommand then
        sampRegisterChatCommand('crupdate',function()
            if U and U.set_open then U.set_open(true)end
            if V.mcr_updates then V.set_screen('updates')
            else V.set_screen('settings');V.open_popup('Обновление Palatka AI','channel_manager')end
        end)
    end
end
