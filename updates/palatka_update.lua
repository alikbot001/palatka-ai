PALATKA_UPDATE_VERSION = '2.5.3-webui-preview'
return function(DSP)
    DSP.webui = DSP.webui or {}
    local W = DSP.webui
    W.version = '0.1-preview'
    W.bid = 95253
    W.visible, W.created, W.loaded, W.crashed = false, false, false, false
    W.dir = DSP.dir .. '/webui'
    W.html_path = W.dir .. '/index.html'
    W.version_path = W.dir .. '/version.txt'
    W.html_url = 'https://raw.githubusercontent.com/alikbot001/palatka-ai/main/webui/index.html'
    local legacy_toggle = DSP.ui and DSP.ui.toggle
    local legacy_set_open = DSP.ui and DSP.ui.set_open
    local ok_web, web = pcall(require, 'webviews')
    W.web = ok_web and web or nil
    local ok_b64, basexx = pcall(require, 'basexx')

    local function read_file(path)
        local f=io.open(path,'rb'); if not f then return nil end
        local d=f:read('*a'); f:close(); return d
    end
    local function write_file(path,data)
        pcall(DSP.mkdir_p,W.dir)
        local tmp=path..'.tmp'; local f,e=io.open(tmp,'wb'); if not f then return false,e end
        local ok,er=f:write(data); local cl,ce=f:close(); if not ok or not cl then pcall(os.remove,tmp); return false,er or ce end
        pcall(os.remove,path); local rn,re=os.rename(tmp,path); if not rn then pcall(os.remove,tmp); return false,re end
        return true
    end
    local function u(v)
        local s=tostring(v or '')
        if DSP.to_u8 then local ok,r=pcall(DSP.to_u8,s); if ok and r then return r end end
        return s
    end
    local function fmt_kind(k)
        if DSP.storage_registry and DSP.storage_registry.kind_name then return u(DSP.storage_registry.kind_name(k)) end
        return k or 'other'
    end
    local function find_row(rec,key)
        if not (DSP.storage_registry and rec) then return nil end
        for _,row in ipairs(DSP.storage_registry.group_rows(rec) or {}) do if tostring(row.key)==tostring(key) then return row end end
    end
    local function build_state()
        local st=DSP.market and DSP.market.state or {}
        local out={version=tostring(DSP.version or '?'),server=tonumber(st.sid) or tonumber(DSP.settings and DSP.settings.server) or 0,
            market={status=u(st.status or 'idle'),shops=tonumber(st.shops) or 0,offers=tonumber(st.offers) or 0,freshness=DSP.market and DSP.market.freshness and u(DSP.market.freshness()) or ''},
            storages={},pending=nil,updater={status=DSP.updater and u(DSP.updater.status_text()) or '',available=DSP.updater and DSP.updater.state and DSP.updater.state.available or false,remote_version=DSP.updater and DSP.updater.state and DSP.updater.state.remote_version or nil}}
        local R=DSP.storage_registry
        if R and R.data and R.data.storages then
            for i=#(R.data.order or {}),1,-1 do
                local id=R.data.order[i]; local rec=R.data.storages[id]
                if rec then
                    local total,qty,unknown=R.total(rec)
                    local s={id=tostring(rec.id),name=u(rec.name or rec.id),kind=rec.kind or 'other',kind_name=fmt_kind(rec.kind),updated_at=tonumber(rec.updated_at) or 0,total=tonumber(total) or 0,qty=tonumber(qty) or 0,unknown=tonumber(unknown) or 0,rows={}}
                    for _,r in ipairs(R.group_rows(rec) or {}) do s.rows[#s.rows+1]={key=tostring(r.key or ''),name=u(r.name or ''),ench=tonumber(r.ench) or 0,qty=tonumber(r.qty),price=tonumber(r.price),value=tonumber(r.value),mode=tostring(r.mode or 'market'),sources={market=r.sources and tonumber(r.sources.market),today=r.sources and tonumber(r.sources.today),buy=r.sources and tonumber(r.sources.buy)}} end
                    out.storages[#out.storages+1]=s
                end
            end
        end
        if R and R.pending then
            local p=R.pending; local pp={kind=p.kind or 'other',kind_name=fmt_kind(p.kind),confidence=tostring(p.candidate and p.candidate.confidence or 'unknown'),candidates={}}
            for _,c in ipairs(R.candidates(p.kind,p.server) or {}) do pp.candidates[#pp.candidates+1]={id=tostring(c.id),name=u(c.name or c.id)} end
            out.pending=pp
        end
        return out
    end
    function W.push_state()
        if not (W.web and W.created and W.loaded and ok_b64 and basexx) then return false end
        local ok,j=pcall(encodeJson,build_state()); if not ok or type(j)~='string' then return false end
        local ok2,b64=pcall(basexx.to_base64,j); if not ok2 or not b64 then return false end
        return pcall(function() W.web.executeJS(W.bid,"window.Palatka&&window.Palatka.receiveStateB64('"..b64.."');") end)
    end
    function W.schedule_push(ms)
        if lua_thread and lua_thread.create and wait then lua_thread.create(function() wait(ms or 80); pcall(W.push_state) end) else pcall(W.push_state) end
    end
    local function screen_size()
        if getScreenResolution then local ok,a,b=pcall(getScreenResolution); if ok and a and b then return a,b end end
        if imgui and imgui.GetIO then local io=imgui.GetIO(); return io.DisplaySize.x,io.DisplaySize.y end
        return 1280,720
    end
    local function create_browser()
        if W.created then return true end
        if not W.web then return false,'webviews missing' end
        local url='file://'..W.html_path..'?v='..W.version
        local ok,e=pcall(function() W.web.createBrowser(W.bid,url) end); if not ok then return false,tostring(e) end
        W.created=true; W.loaded=false; W.crashed=false
        local sw,sh=screen_size(); pcall(function() W.web.setPos(W.bid,0,0); W.web.setSize(W.bid,sw,sh) end)
        return true
    end
    local function ensure_html(done)
        if read_file(W.html_path) and read_file(W.version_path)==W.version then done(true); return end
        if not DSP.http_get then done(false,'HTTP unavailable'); return end
        if DSP.notify then DSP.notify('WebUI: downloading interface...') end
        DSP.http_get(W.html_url,function(body,err,code)
            if not body or #body<2000 then done(false,tostring(err or ('HTTP '..tostring(code or 0)))); return end
            local ok,e=write_file(W.html_path,body); if not ok then done(false,e); return end
            write_file(W.version_path,W.version); done(true)
        end)
    end
    function W.hide()
        if W.web and W.created then pcall(function() W.web.setClickable(W.bid,false); W.web.setVisible(W.bid,false) end) end
        W.visible=false
    end
    function W.show()
        if not W.web then if legacy_toggle then return legacy_toggle() end; return false end
        if legacy_set_open then pcall(legacy_set_open,false) end
        ensure_html(function(ok,e)
            if not ok then if DSP.notify then DSP.notify('WebUI failed: '..tostring(e)..'. Legacy UI opened.') end; if legacy_toggle then legacy_toggle() end; return end
            local c,ce=create_browser(); if not c then if DSP.notify then DSP.notify('WebUI failed: '..tostring(ce)..'. Legacy UI opened.') end; if legacy_toggle then legacy_toggle() end; return end
            local sw,sh=screen_size(); pcall(function() W.web.setPos(W.bid,0,0); W.web.setSize(W.bid,sw,sh); W.web.setClickable(W.bid,true); W.web.setVisible(W.bid,true) end)
            W.visible=true; W.schedule_push(120)
        end)
        return true
    end
    function W.toggle()
        if DSP.ui and DSP.ui.open then if legacy_set_open then legacy_set_open(false) end; return end
        if W.visible then W.hide() else W.show() end
    end
    function W.open_legacy(screen)
        W.hide()
        if DSP.settings then DSP.settings.screen=screen or DSP.settings.screen end
        if legacy_set_open then legacy_set_open(true) elseif legacy_toggle then legacy_toggle() end
    end
    local function handle(a)
        if type(a)~='table' then return end
        local kind=tostring(a.kind or '')
        if kind=='close' then W.hide()
        elseif kind=='sync' then W.schedule_push(10)
        elseif kind=='legacy' then W.open_legacy(tostring(a.screen or 'settings'))
        elseif kind=='refresh_market' then if DSP.market and DSP.market.pull then pcall(DSP.market.pull,DSP.market.state and DSP.market.state.sid) end; W.schedule_push(500)
        elseif kind=='updater_check' then if DSP.updater then pcall(DSP.updater.check,false) end; W.schedule_push(800)
        elseif kind=='updater_install' then if DSP.updater then pcall(DSP.updater.install) end
        elseif kind=='storage_price' or kind=='storage_manual' then
            local R=DSP.storage_registry; local rec=R and R.get and R.get(tostring(a.storage_id or '')); local row=find_row(rec,tostring(a.key or ''))
            if rec and row then local mode=kind=='storage_manual' and 'manual' or tostring(a.mode or 'market'); pcall(R.set_price_mode,rec.id,row,mode,kind=='storage_manual' and tonumber(a.price) or nil); W.schedule_push(80) end
        elseif kind=='storage_create' then local R=DSP.storage_registry; if R then pcall(R.create_pending,DSP.to_cp and DSP.to_cp(tostring(a.name or '')) or tostring(a.name or ''),tostring(a.storage_kind or 'other')); W.schedule_push(100) end
        elseif kind=='storage_bind' then local R=DSP.storage_registry; if R then pcall(R.bind_pending,tostring(a.storage_id or '')); W.schedule_push(100) end
        elseif kind=='storage_cancel' then local R=DSP.storage_registry; if R then pcall(R.cancel_pending); W.schedule_push(80) end
        end
    end
    W._previous_onAction=W.web and W.web.onAction or nil
    if W.web then
        W._handler=function(data)
            if data and tonumber(data.browserid)==tonumber(W.bid) then
                if data.type=='WV_STARTED' then W.crashed=false; W.loaded=false
                elseif data.type=='WV_LOADED' then W.loaded=true; W.schedule_push(40)
                elseif data.type=='WV_DIE' then W.crashed=true; W.created=false; W.visible=false
                elseif data.type=='WV_ANSWER' then local raw=tostring(data.msg or ''); local prefix='PALATKA_BRIDGE:'; local i=raw:find(prefix,1,true); if i then local ok,obj=pcall(decodeJson,raw:sub(i+#prefix)); if ok then pcall(handle,obj) end end end
                return
            end
            if W._previous_onAction then return W._previous_onAction(data) end
        end
        W.web.onAction=W._handler
    end
    DSP.ui.toggle=function() return W.toggle() end
    DSP.version='2.5.3-webui-preview'
    if DSP.notify then DSP.notify('WebUI preview active. /crr opens WebUI; legacy UI is fallback.') end
    return true
end
