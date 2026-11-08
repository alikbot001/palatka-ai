-- This block is assembled inside the original top-level lexical scope.
do
    local root=getWorkingDirectory():gsub('\\','/')..'/PalatkaMCR'
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
        currency=function()return lIlllI__()and'VC$'or'SA$'end,
        center_width=function()return z_*2+constItemSpacingX*3 end,
        sidebar_width=function()return constWidthSidebar end,
        sidebar_button_height=function()return constHeightButtonSidebar end,
        icons=x,
        open_settings=function()B.OpenPopup(u8('Параметры арбитража'))end,
        draw_settings_popup=function(draw)
            (llII___l('Параметры арбитража',1.5,0,draw))()
        end,
        can_click=llIllll_,
        input_string=function(buffer)return e.string(buffer)end,
        encode=T.encode,decode=T.decode,
        to_cp=NeomText.MixedToCp1251,
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
            if not Y.attributes(path)then return nil end
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
