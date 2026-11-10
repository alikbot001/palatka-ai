-- Network policy for the standalone local client. Remote MCR features report
-- unavailable; this does not synthesize successful replies from its server.
do
    local reason='Не используется сервер MCR: доступна локальная работа'
    local allowed={['api.telegram.org']=true,['server-api.arizona.games']=true,
        ['server-api.azgames-cdn.ru']=true}
    local function permitted(url,method)
        if tostring(url):match('^https://va%-ta%.com/api/shops/pull%?')then return true end
        if tostring(url):match('^https://va%-ta%.com/api/site/market%-list%?server=10[123]&page=[123]&limit=100&sort=popular$')then
            return method==nil or method=='GET'
        end
        local base=PalatkaMCR.update_base
        if base and(url==base..'palatka_mcr_update.json'or url==base..'palatka_mcr_local.lua')then return true end
        local host=tostring(url or ''):match('^https://([^/:]+)')
        return host and allowed[host:lower()]==true
    end
    local old_http=lIl_l_lI
    lIl_l_lI=function(method,url,options,success,failure,timeout)
        if not permitted(url,method)then
            if failure then failure(reason)end
            return false,reason
        end
        return old_http(method,url,options,success,failure,timeout)
    end
    local old_chunks=lIl__IIl
    lIl__IIl=function(url,success,failure)
        if not permitted(url)then
            if failure then failure(reason)end
            return false,reason
        end
        return old_chunks(url,success,failure)
    end
    local old_request=G.request
    G.request=function(request,...)
        local url=type(request)=='table'and request.url or request
        if not permitted(url,type(request)=='table'and request.method or nil)then return nil,reason end
        return old_request(request,...)
    end
    PalatkaMCR.local_mode=true
end
