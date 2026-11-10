-- Explicit installs only. Automatic checks announce a release once per build.
return function(h)
assert(type(h.decode)=='function','updater host.decode must be a function')
local remembered=tonumber(h.remembered())
if not remembered or remembered%1~=0 or remembered<0 or remembered>=1000000 then remembered=0 end
local U={busy=false,notified=remembered}
local function valid(m)
    return type(m)=='table'and m.schema==1 and m.channel=='mcr-local'
        and type(m.build)=='number'and m.build%1==0 and m.build>0 and m.build<1000000
        and type(m.version)=='string'and m.version:match('^%d+%.%d+%.%d+%-local%.%d+$')
        and tonumber(m.version:match('local%.(%d+)$'))==m.build
        and m.url==h.base..'palatka_mcr_local.lua'
        and type(m.size)=='number'and m.size%1==0 and m.size>=1024 and m.size<=8*1024*1024
        and type(m.sha256)=='string'and #m.sha256==64 and m.sha256:match('^%x+$')
end
function U.check(manual,install)
    if U.busy then if manual then h.notify('Проверка обновления уже идёт')end;return false end
    U.busy=true
    local function fail(reason)
        U.busy=false;U.error=tostring(reason)
        if manual then h.notify('Обновление: '..U.error)end
    end
    if manual then h.notify('Проверяю обновление Palatka MCR Local...')end
    h.get(h.base..'palatka_mcr_update.json',function(raw,err)
        if not raw then fail(err or'Нет ответа GitHub');return end
        if #raw>8192 then fail('Слишком большой манифест');return end
        local ok,info=pcall(h.decode,raw)
        if not ok or not valid(info)then fail('Некорректное описание обновления');return end
        if info.build<=math.max(h.current_build,U.installed_build or 0)then
            U.busy=false
            if manual then h.notify(U.installed_build and'Обновление уже установлено. Перезапустите игру.'or'Установлена актуальная версия')end
            return
        end
        if not install then
            U.busy=false
            if info.build~=U.notified then
                U.notified=info.build
                U.pending_remember=info.build
                h.notify('Доступна новая версия '..info.version..'. Обновить: /crrupdate')
            end
            if U.pending_remember then
                local saved,why=h.remember(U.pending_remember)
                if saved then U.pending_remember=nil;U.error=nil
                else U.error='Не сохранено уведомление: '..tostring(why)end
            end
            return
        end
        if h.busy()then fail('Завершите текущую операцию перед обновлением');return end
        h.notify('Загружаю '..info.version..'...')
        h.get(info.url,function(bytes,why)
            if not bytes then fail(why or'Загрузка прервана');return end
            if #bytes~=info.size then fail('Размер файла не совпадает');return end
            if h.sha256(bytes,h.yield)~=info.sha256:lower()then fail('SHA256 не совпадает');return end
            if not bytes:find('-- Configuration: Palatka MCR Local; independent client build.',1,true)then
                fail('Файл другого проекта');return
            end
            local compiled,syntax=h.compile(bytes)
            if not compiled then fail('Ошибка Lua: '..tostring(syntax));return end
            if h.busy()then fail('Началась операция; файл не заменён');return end
            local installed,reason=h.install(bytes)
            if not installed then fail(reason);return end
            U.busy=false;U.error=nil;U.installed_build=info.build
            h.notify('Установлена '..info.version..'. Перезапустите игру. Резервная копия сохранена.')
        end)
    end)
    return true
end
function U.start()h.poll(function()U.check(false,false)end)end
return U
end
