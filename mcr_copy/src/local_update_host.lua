-- The candidate channel is explicit and separate from stable/main releases.
(function()
local A=PalatkaMCR
local function notify(message)sampAddChatMessage('[Palatka] '..message,0xFFD166)end
A.updater=A.new_updater({
    current_build=A.build,current_version=A.version,base=A.update_base,
    sha256=A.sha256,yield=function()wait(0)end,compile=loadstring,decode=T.decode,
    get=function(url,done)
        A.host.run(function()
            lIl_l_lI('GET',url,{headers={['Cache-Control']='no-cache'}},function(response)
                if response.status_code~=200 then done(nil,'GitHub HTTP '..tostring(response.status_code));return end
                done(response.text)
            end,function(err)done(nil,err)end,30)
        end)
    end,
    notify=notify,
    busy=function()
        return o6 or g6 or s6 or u6 or isParseInventoryDialogs or isSetProcessPause
            or(autoShopState and autoShopState.active)or A.busy
    end,
    install=function(body)return A.install_file(thisScript().path,body)end,
    remembered=function()
        local raw=A.host.read('updater.json');if not raw then return 0 end
        local ok,data=pcall(T.decode,raw)
        if not ok or type(data)~='table'then
            print('[Palatka updater] Не удалось прочитать отметку обновления; проверка будет повторена');return 0
        end
        return tonumber(data.notified_build)or 0
    end,
    remember=function(build)return A.host.write('updater.json',T.encode({notified_build=build}))end,
    poll=function(check)
        lua_thread.create(function()
            wait(15000)
            while true do check();wait(300000)end
        end)
    end,
})
end)()
