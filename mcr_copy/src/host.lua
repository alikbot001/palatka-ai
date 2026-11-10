-- This block is assembled inside the original top-level lexical scope.
do
    local root=getWorkingDirectory():gsub('\\','/')..'/PalatkaMCR'
    local name_index
    F3.arbitrage=10
    PalatkaMCR.install({
        imgui=B,utf8=u8,now=os.time,
        fields={name=nameT,qty=countT,price=priceT},
        name=lI_III__,
        normalize_server=function(v)return tostring(lIlllIIl(v)or '')end,
        server=function()
            if not isSampAvailable()then return ''end
            local ip,port=sampGetCurrentServerAddress()
            if not ip or not port then return ''end
            return tostring(lIlllIIl(tostring(ip)..':'..tostring(port))or '')
        end,
        server_name=function()return sampGetCurrentServerName()end,
        currency=function()return lIlllI__()and'VC$'or'SA$'end,
        center_width=function()return z_*2+constItemSpacingX*3 end,
        sidebar_width=function()return constWidthSidebar end,
        sidebar_button_height=function()return constHeightButtonSidebar end,
        icons=x,
        open_popup=function(title)B.OpenPopup(u8(title))end,
        draw_popup=function(title,draw)
            (llII___l(title,1.5,0,draw))()
        end,
        can_click=llIllll_,
        input_string=function(buffer)return e.string(buffer)end,
        encode=T.encode,decode=T.decode,
        to_cp=NeomText.MixedToCp1251,
        unique_item=function(name)
            if not name_index then
                name_index={}
                for id,title in pairs(M)do
                    if tonumber(id)and type(title)=='string'then
                        if name_index[title]~=nil then name_index[title]=false
                        else name_index[title]=tostring(id)end
                    end
                end
            end
            return name_index[name]or nil
        end,
        market_server_id=function()
            local name=tostring(sampGetCurrentServerName()or ''):lower()
            if name:find('mobile%s*iii')or name:find('mobile%s*3')then return 103 end
            if name:find('mobile%s*ii')or name:find('mobile%s*2')then return 102 end
            if name:find('mobile%s*i')or name:find('mobile%s*1')then return 101 end
        end,
        read_market_cache=function(sid)
            local path=getWorkingDirectory():gsub('\\','/')..'/PalatkaAI/market_'..sid..'.json'
            local f,err=io.open(path,'rb');if not f then return nil,err end
            local raw=f:read(8*1024*1024+1);f:close()
            if not raw or #raw>8*1024*1024 then return nil,'Файл слишком большой'end
            return raw
        end,
        run=function(fn)
            lua_thread.create(function()wait(0);fn()end)
        end,
        yield=function()wait(0)end,
        register=sampRegisterChatCommand,
        poll_market=function(refresh)
            lua_thread.create(function()wait(2000);while true do refresh();wait(120000)end end)
        end,
        fetch_market=function(sid,done)
            lIl_l_lI('GET','https://va-ta.com/api/shops/pull?server='..sid,nil,
                function(response)
                    if response.status_code~=200 then done(nil,'HTTP '..tostring(response.status_code));return end
                    done(response.text)
                end,function(err)done(nil,err)end,20)
        end,
        fetch_popularity=function(sid,done)
            if sid~=101 and sid~=102 and sid~=103 then done(nil,'Мобильный сервер не определён');return end
            local combined={ok=true,items={}}
            local function page(number)
                local url='https://va-ta.com/api/site/market-list?server='..sid..'&page='..number..'&limit=100&sort=popular'
                lIl_l_lI('GET',url,nil,function(response)
                    if response.status_code~=200 then done(nil,'Статистика HTTP '..tostring(response.status_code));return end
                    if type(response.text)~='string'or #response.text>1024*1024 then done(nil,'Слишком большой ответ статистики');return end
                    local ok,data=pcall(T.decode,response.text)
                    if not ok or type(data)~='table'or data.ok~=true or type(data.items)~='table'
                        or tonumber(data.page)~=number then done(nil,'Неверный ответ статистики');return end
                    local count=0;for k in pairs(data.items)do
                        if type(k)~='number'or k%1~=0 or k<1 then done(nil,'Неверный список статистики');return end
                        count=count+1
                    end
                    if count~=#data.items or count>100 then done(nil,'Неверная страница статистики');return end
                    for _,row in ipairs(data.items)do combined.items[#combined.items+1]=row end
                    local pages=tonumber(data.pages)
                    if not pages or pages%1~=0 or pages<1 then done(nil,'Нет числа страниц статистики');return end
                    if number<math.min(3,pages)then page(number+1)
                    else combined.partial=pages>3;done(combined)end
                end,function(err)done(nil,err)end,20)
            end
            page(1)
        end,
        open_main=function()o_(true)end,
        open=function()O3=F3.arbitrage;M3[0]=true end,
        find=function(number,server)
            if server~=PalatkaMCR.host.server()then
                PalatkaMCR.error='Сервер изменился';return
            end
            local n=PalatkaMCR.engine.integer(number,1,1000000000)
            if n then sampSendChat('/findilavka '..tostring(n))end
        end,
        read=function(name)
            local path=root..'/'..name
            local attributes,stat_error,stat_code=Y.attributes(path)
            if not attributes then
                if stat_code==2 then return nil end
                return nil,stat_error or'Не удалось проверить файл'
            end
            local file,err=io.open(path,'rb')
            if not file then return nil,err end
            local content=file:read(8*1024*1024+1)
            file:close()
            if not content or #content>8*1024*1024 then return nil,'Файл слишком большой или не читается'end
            return content
        end,
        write=function(name,content)
            if not Y.attributes(root)then
                local ok,err=Y.mkdir(root)
                if not ok then return false,err end
            end
            local path=root..'/'..name
            local tmp=path..'.tmp'
            local file,err=io.open(tmp,'wb')
            if not file then return false,err end
            local ok,why=file:write(content)
            local closed,close_err=file:close()
            if not ok then return false,why end
            if not closed then return false,close_err end
            local renamed,rename_err=os.rename(tmp,path)
            if not renamed then return false,rename_err end
            return true
        end,
    })
end
