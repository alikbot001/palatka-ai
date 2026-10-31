PALATKA_UPDATE_VERSION = '2.6.0-webui-bootstrap'
return function(DSP)
    DSP.webui = DSP.webui or {}
    local W = DSP.webui
    W.version = '1.0'
    W.bid = 95253
    W.visible, W.created, W.loaded, W.crashed = false, false, false, false
    W.dir = DSP.dir .. '/webui'
    W.html_path = W.dir .. '/index.html'
    W.version_path = W.dir .. '/version.txt'
    W.embedded_html = [=[<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=no"><title>Palatka AI</title><style>:root{--bg:#08090c;--panel:#101217;--panel2:#151820;--line:#252933;--text:#f4f5f7;--muted:#8f96a3;--accent:#ffb020;--accent2:#ff7a1a;--good:#49d17d;--bad:#ff6464;--r:18px;--shadow:0 14px 40px rgba(0,0,0,.36)}*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}html,body{margin:0;width:100%;height:100%;overflow:hidden;background:var(--bg);color:var(--text);font-family:Inter,Roboto,system-ui,-apple-system,sans-serif}button,input,select{font:inherit}button{color:inherit}.app{height:100%;display:grid;grid-template-rows:auto 1fr auto;background:radial-gradient(circle at 85% -10%,rgba(255,176,32,.13),transparent 35%),var(--bg)}.top{padding:calc(14px + env(safe-area-inset-top)) 18px 12px;display:flex;align-items:center;gap:12px;border-bottom:1px solid rgba(255,255,255,.055);background:rgba(8,9,12,.88);backdrop-filter:blur(18px)}.brand{display:flex;align-items:center;gap:10px;min-width:0;flex:1}.logo{width:38px;height:38px;border-radius:12px;background:linear-gradient(145deg,var(--accent),var(--accent2));display:grid;place-items:center;color:#15100a;font-weight:900;box-shadow:0 8px 28px rgba(255,145,20,.28)}.brand b{font-size:17px;letter-spacing:.2px}.sub{font-size:11px;color:var(--muted);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.iconbtn{width:40px;height:40px;border:1px solid var(--line);background:var(--panel);border-radius:13px;display:grid;place-items:center}.content{overflow:auto;padding:16px 16px 28px;scrollbar-width:none}.content::-webkit-scrollbar{display:none}.view{display:none}.view.active{display:block}.hero{padding:20px;border:1px solid rgba(255,176,32,.18);border-radius:24px;background:linear-gradient(145deg,rgba(255,176,32,.09),rgba(255,122,26,.025) 45%,rgba(16,18,23,.9));box-shadow:var(--shadow)}.eyebrow{font-size:11px;text-transform:uppercase;letter-spacing:1.35px;color:var(--accent);font-weight:800}.hero h1{font-size:24px;line-height:1.15;margin:8px 0 6px}.muted{color:var(--muted)}.small{font-size:12px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-top:12px}.stat{background:var(--panel);border:1px solid var(--line);border-radius:18px;padding:14px;min-height:84px}.stat .v{font-size:20px;font-weight:800;margin-top:7px}.section{margin-top:20px}.section-title{display:flex;align-items:center;justify-content:space-between;margin-bottom:10px}.section-title h2{font-size:15px;margin:0}.pill{border-radius:999px;background:#1b1e25;border:1px solid var(--line);padding:6px 9px;color:var(--muted);font-size:11px}.actions{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.action{min-height:72px;text-align:left;padding:13px;border:1px solid var(--line);border-radius:17px;background:var(--panel);display:flex;flex-direction:column;justify-content:space-between}.action:active,.card:active{transform:scale(.985)}.action strong{font-size:14px}.action span{font-size:11px;color:var(--muted)}.accent{border-color:rgba(255,176,32,.35);background:linear-gradient(145deg,rgba(255,176,32,.12),var(--panel))}.search{width:100%;border:1px solid var(--line);background:var(--panel);color:var(--text);outline:0;border-radius:16px;padding:13px 15px}.search:focus{border-color:rgba(255,176,32,.55)}.list{display:flex;flex-direction:column;gap:9px}.card{border:1px solid var(--line);background:var(--panel);border-radius:18px;padding:14px}.row{display:flex;align-items:center;gap:10px}.grow{flex:1;min-width:0}.name{font-weight:750;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.meta{font-size:11px;color:var(--muted);margin-top:4px}.money{font-weight:800;font-variant-numeric:tabular-nums}.tag{display:inline-flex;align-items:center;gap:5px;border:1px solid var(--line);background:var(--panel2);padding:5px 8px;border-radius:999px;font-size:10px;color:var(--muted)}.dot{width:7px;height:7px;border-radius:50%;background:var(--good)}.dot.bad{background:var(--bad)}.storage-head{display:flex;gap:10px;align-items:center;margin-bottom:14px}.back{width:38px;height:38px;border-radius:12px;border:1px solid var(--line);background:var(--panel)}.items{display:flex;flex-direction:column;gap:8px}.item{border:1px solid var(--line);background:var(--panel);padding:13px;border-radius:16px}.item-top{display:flex;gap:10px;align-items:flex-start}.qty{font-weight:900;color:var(--accent)}.pricebar{display:grid;grid-template-columns:repeat(4,1fr);gap:6px;margin-top:11px}.pricebtn{padding:8px 3px;border-radius:11px;border:1px solid var(--line);background:var(--panel2);font-size:10px;color:var(--muted)}.pricebtn.on{border-color:rgba(255,176,32,.55);background:rgba(255,176,32,.12);color:var(--accent)}.bottom{display:grid;grid-template-columns:repeat(5,1fr);gap:2px;padding:7px 8px calc(7px + env(safe-area-inset-bottom));border-top:1px solid rgba(255,255,255,.06);background:rgba(8,9,12,.94);backdrop-filter:blur(18px)}.nav{border:0;background:transparent;color:var(--muted);border-radius:13px;padding:8px 2px;font-size:10px}.nav .ico{font-size:18px;display:block;margin-bottom:3px}.nav.on{color:var(--accent);background:rgba(255,176,32,.09)}.empty{text-align:center;padding:42px 20px;color:var(--muted)}.fullbtn{width:100%;padding:12px;border-radius:14px;border:1px solid var(--line);background:var(--panel);margin-top:8px}.primary{background:linear-gradient(135deg,var(--accent),var(--accent2));color:#160f05;border:0;font-weight:900}.danger{color:#ff8585}.modal{position:fixed;inset:0;background:rgba(0,0,0,.62);display:none;align-items:flex-end;z-index:50}.modal.on{display:flex}.sheet{width:100%;max-height:82%;overflow:auto;padding:18px 16px calc(18px + env(safe-area-inset-bottom));background:#0e1015;border-radius:24px 24px 0 0;border-top:1px solid var(--line)}.sheet h3{margin:0 0 12px}.field{width:100%;padding:12px 13px;border-radius:13px;border:1px solid var(--line);background:var(--panel);color:var(--text);outline:0;margin-top:8px}.seg{display:grid;grid-template-columns:repeat(4,1fr);gap:6px}.seg button{border:1px solid var(--line);background:var(--panel);padding:9px 3px;border-radius:11px;font-size:10px}.seg button.on{color:var(--accent);border-color:rgba(255,176,32,.5);background:rgba(255,176,32,.1)}.toast{position:fixed;left:16px;right:16px;bottom:92px;background:#191d24;border:1px solid var(--line);border-radius:14px;padding:12px 14px;box-shadow:var(--shadow);display:none;z-index:70;font-size:12px}.toast.on{display:block}.skeleton{height:70px;border-radius:16px;background:linear-gradient(90deg,#11141a,#1a1d25,#11141a);background-size:200% 100%;animation:sh 1.1s infinite}@keyframes sh{to{background-position:-200% 0}}@media(min-width:720px){.content{max-width:900px;width:100%;margin:auto}.grid{grid-template-columns:repeat(4,1fr)}.actions{grid-template-columns:repeat(4,1fr)}.bottom{max-width:720px;width:100%;margin:auto;border:1px solid var(--line);border-bottom:0;border-radius:20px 20px 0 0}.app{background:#08090c}}</style></head><body><div class="app"><header class="top"><div class="brand"><div class="logo">P</div><div class="grow"><b>Palatka AI</b><div class="sub" id="subtitle">подключение к Lua…</div></div></div><button class="iconbtn" onclick="send('sync')">↻</button><button class="iconbtn" onclick="send('close')">✕</button></header><main class="content"><section class="view active" data-view="home"><div class="hero"><div class="eyebrow">центр управления</div><h1>Рынок и твои вещи — в одном месте</h1><div class="muted small" id="heroStatus">Получаю данные…</div></div><div class="grid"><div class="stat"><div class="muted small">Лавок в базе</div><div class="v" id="shops">—</div></div><div class="stat"><div class="muted small">Офферов</div><div class="v" id="offers">—</div></div><div class="stat"><div class="muted small">Хранилищ</div><div class="v" id="storageCount">—</div></div><div class="stat"><div class="muted small">Оценка вещей</div><div class="v" id="storageValue">—</div></div></div><div class="section"><div class="section-title"><h2>Быстрые действия</h2></div><div class="actions"><button class="action accent" onclick="send('refresh_market')"><strong>Обновить рынок</strong><span>API и локальные данные</span></button><button class="action" onclick="go('storage')"><strong>Мои хранилища</strong><span>Поиск и оценка</span></button><button class="action" onclick="legacy('market')"><strong>Рынок</strong><span>Пока открыть старый экран</span></button><button class="action" onclick="legacy('trade')"><strong>Торговля</strong><span>Пресеты и выставление</span></button></div></div><div class="section"><div class="section-title"><h2>Недавние хранилища</h2><button class="pill" onclick="go('storage')">Все</button></div><div class="list" id="recentStorages"><div class="skeleton"></div><div class="skeleton"></div></div></div></section><section class="view" data-view="storage"><div id="storageRoot"></div></section><section class="view" data-view="market"><div class="hero"><div class="eyebrow">рынок</div><h1>Переезд идёт поэтапно</h1><div class="muted small">Данные уже остаются в Lua Core. Этот экран будет перенесён следующим.</div></div><button class="fullbtn primary" onclick="legacy('market')">Открыть текущий рынок</button></section><section class="view" data-view="trade"><div class="hero"><div class="eyebrow">торговля</div><h1>Автопродажа и скупка не переписываются</h1><div class="muted small">WebUI будет только управлять существующим стабильным runtime.</div></div><button class="fullbtn primary" onclick="legacy('trade')">Открыть текущую торговлю</button></section><section class="view" data-view="more"><div class="section-title"><h2>Ещё</h2></div><div class="list"><button class="card" onclick="legacy('arbitrage')"><div class="name">Арбитраж</div><div class="meta">Текущий рабочий модуль</div></button><button class="card" onclick="legacy('journal')"><div class="name">Журнал</div><div class="meta">Сделки и история</div></button><button class="card" onclick="openUpdates()"><div class="name">Обновления</div><div class="meta" id="updateStatus">—</div></button><button class="card" onclick="legacy('settings')"><div class="name">Расширенные настройки</div><div class="meta">Старый UI как fallback</div></button></div></section></main><nav class="bottom"><button class="nav on" data-nav="home" onclick="go('home')"><span class="ico">⌂</span>Главная</button><button class="nav" data-nav="market" onclick="go('market')"><span class="ico">◫</span>Рынок</button><button class="nav" data-nav="trade" onclick="go('trade')"><span class="ico">⇄</span>Торговля</button><button class="nav" data-nav="storage" onclick="go('storage')"><span class="ico">▣</span>Хранилища</button><button class="nav" data-nav="more" onclick="go('more')"><span class="ico">•••</span>Ещё</button></nav></div><div class="modal" id="modal"><div class="sheet" id="sheet"></div></div><div class="toast" id="toast"></div><script>const S={data:null,view:'home',storage:null,query:''};const $=q=>document.querySelector(q), $=q=>[...document.querySelectorAll(q)];const esc=s=>String(s??'').replace(/[&<>\"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));const money=n=>Number.isFinite(+n)?new Intl.NumberFormat('ru-RU').format(+n).replace(/\u00a0/g,'.'):'—';const age=ts=>{if(!ts)return 'никогда';let d=Math.max(0,Math.floor(Date.now()/1000-ts));if(d<60)return d+' сек назад';if(d<3600)return Math.floor(d/60)+' мин назад';if(d<86400)return Math.floor(d/3600)+' ч назад';return Math.floor(d/86400)+' дн назад'};function nativeSend(raw){let ok=false;try{if(window.Android&&typeof Android.postMessage==='function'){Android.postMessage(raw);ok=true}}catch(e){}try{if(!ok&&window.external&&typeof window.external.invoke==='function'){window.external.invoke(raw);ok=true}}catch(e){}try{if(!ok&&window.webkit?.messageHandlers?.palatka){window.webkit.messageHandlers.palatka.postMessage(raw);ok=true}}catch(e){}try{if(!ok){window.prompt(raw,'');ok=true}}catch(e){}return ok}function send(kind,p={}){const ok=nativeSend('PALATKA_BRIDGE:'+JSON.stringify({kind,...p}));if(!ok)toast('Bridge недоступен. /crr закроет WebUI.');return ok}function toast(t){const x=$('#toast');x.textContent=t;x.classList.add('on');clearTimeout(toast.t);toast.t=setTimeout(()=>x.classList.remove('on'),2400)}function go(v){S.view=v;$('.view').forEach(x=>x.classList.toggle('active',x.dataset.view===v));$('.nav').forEach(x=>x.classList.toggle('on',x.dataset.nav===v));if(v==='storage')renderStorage()}function legacy(screen){send('legacy',{screen})}function renderHome(){const d=S.data;if(!d)return;$('#subtitle').textContent=`v${d.version} · сервер ${d.server||'?'} · ${d.market.status}`;$('#heroStatus').textContent=`${d.market.freshness||'нет свежести'} · ${d.market.status||'—'}`;$('#shops').textContent=money(d.market.shops);$('#offers').textContent=money(d.market.offers);$('#storageCount').textContent=d.storages.length;let total=d.storages.reduce((a,s)=>a+(+s.total||0),0);$('#storageValue').textContent='    W.html_url = 'https://raw.githubusercontent.com/alikbot001/palatka-ai/main/webui/index.html'
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
    local function install_embedded_webui()
        local current = read_file(W.version_path)
        local html_now = read_file(W.html_path)
        if current == W.version and html_now and #html_now > 2000 then return true end
        local ok,e = write_file(W.html_path, W.embedded_html)
        if not ok then return false,e end
        local ok2,e2 = write_file(W.version_path, W.version)
        if not ok2 then return false,e2 end
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
        local ok,e = install_embedded_webui()
        if ok then done(true); return end
        if not DSP.http_get then done(false,e or 'HTTP unavailable'); return end
        DSP.http_get(W.html_url,function(body,err,code)
            if not body or #body<2000 then done(false,tostring(err or e or ('HTTP '..tostring(code or 0)))); return end
            local ok2,e2=write_file(W.html_path,body); if not ok2 then done(false,e2); return end
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
    local boot_ok, boot_err = install_embedded_webui()
    if not boot_ok and DSP.flog then DSP.flog('WEBUI bootstrap write failed: '..tostring(boot_err)) end
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
    DSP.version='2.6.0-webui-bootstrap'
    if DSP.notify then DSP.notify('WebUI 2.6 bootstrap installed. /crr opens WebUI; legacy UI is fallback.') end
    return true
end
+money(total);const box=$('#recentStorages');const rows=d.storages.slice().sort((a,b)=>(b.updated_at||0)-(a.updated_at||0)).slice(0,3);box.innerHTML=rows.length?rows.map(storageCard).join(''):'<div class="empty">Пока нет сохранённых хранилищ</div>';$('#updateStatus').textContent=d.updater?.status||'не проверялось'}function storageCard(s){return `<button class="card" onclick="openStorage('${esc(s.id)}')"><div class="row"><div class="grow"><div class="name">${esc(s.name)}</div><div class="meta">${esc(s.kind_name)} · ${s.rows.length} позиций · ${age(s.updated_at)}</div></div><div class="money">${money(s.total||0)}</div></div></button>`}function renderStorage(){const root=$('#storageRoot'),d=S.data;if(!d){root.innerHTML='<div class="skeleton"></div>';return}if(S.storage){const s=d.storages.find(x=>x.id===S.storage);if(!s){S.storage=null;return renderStorage()}root.innerHTML=`<div class="storage-head"><button class="back" onclick="S.storage=null;renderStorage()">‹</button><div class="grow"><div class="name">${esc(s.name)}</div><div class="meta">${esc(s.kind_name)} · ${age(s.updated_at)}</div></div><div class="money">${money(s.total||0)}</div></div><input class="search" id="itemSearch" placeholder="Найти предмет здесь…" value="${esc(S.query)}" oninput="S.query=this.value;renderItems()"><div class="section items" id="items"></div>`;renderItems();return}root.innerHTML=`<div class="section-title"><h2>Мои хранилища</h2><span class="pill">${d.storages.length}</span></div><input class="search" id="globalSearch" placeholder="Найти предмет во всех хранилищах…" value="${esc(S.query)}" oninput="S.query=this.value;renderStorageList()"><div class="section list" id="storageList"></div>`;renderStorageList();if(d.pending)openPending(d.pending)}function renderStorageList(){const d=S.data,box=$('#storageList'),q=(S.query||'').trim().toLowerCase();if(!q){box.innerHTML=d.storages.length?d.storages.map(storageCard).join(''):'<div class="empty">Открой багажник, шкаф или склад — Palatka предложит сохранить его.</div>';return}let hits=[];d.storages.forEach(s=>s.rows.forEach(r=>{if((r.name||'').toLowerCase().includes(q))hits.push({s,r})}));box.innerHTML=hits.length?hits.map(({s,r})=>`<button class="card" onclick="openStorage('${esc(s.id)}')"><div class="row"><div class="grow"><div class="name">${esc(r.name)} <span class="qty">×${r.qty??'?'}</span></div><div class="meta">${esc(s.name)} · ${esc(s.kind_name)}</div></div><div class="money">${money(r.value||0)}</div></div></button>`).join(''):'<div class="empty">Ничего не найдено</div>'}function openStorage(id){S.storage=id;S.query='';go('storage')}function renderItems(){const s=S.data.storages.find(x=>x.id===S.storage),box=$('#items'),q=(S.query||'').trim().toLowerCase();const rows=s.rows.filter(r=>!q||(r.name||'').toLowerCase().includes(q));box.innerHTML=rows.length?rows.map(r=>`<div class="item"><div class="item-top"><div class="grow"><div class="name">${esc(r.name)} ${r.ench?`+${r.ench}`:''}</div><div class="meta">Цена: ${money(r.price)} · Стоимость: ${money(r.value)}</div></div><div class="qty">×${r.qty??'?'}</div></div><div class="pricebar">${[['market','Рынок'],['today','Сегодня'],['buy','Скуп'],['manual','Своя']].map(([m,l])=>`<button class="pricebtn ${r.mode===m?'on':''}" onclick="priceMode('${esc(s.id)}','${esc(r.key)}','${m}',${m==='manual'?'true':'false'})">${l}</button>`).join('')}</div></div>`).join(''):'<div class="empty">Нет предметов</div>'}function priceMode(sid,key,mode,manual){if(manual){openManual(sid,key);return}send('storage_price',{storage_id:sid,key,mode})}function openManual(sid,key){$('#sheet').innerHTML=`<h3>Своя цена</h3><div class="muted small">Можно вводить 1.000.000</div><input class="field" id="manualValue" inputmode="numeric" placeholder="1.000.000"><button class="fullbtn primary" onclick="applyManual('${esc(sid)}','${esc(key)}')">Сохранить</button><button class="fullbtn" onclick="closeModal()">Отмена</button>`;$('#modal').classList.add('on')}function applyManual(sid,key){const raw=($('#manualValue').value||'').replace(/[^0-9]/g,'');const n=+raw;if(!n)return toast('Введите цену');send('storage_manual',{storage_id:sid,key,price:n});closeModal()}function openPending(p){if($('#modal').classList.contains('on'))return;const kinds=[['trunk','Багажник'],['cabinet','Шкаф'],['warehouse','Склад'],['other','Другое']];$('#sheet').innerHTML=`<h3>Новое хранилище</h3><div class="muted small">${esc(p.kind_name)} · точность ID: ${esc(p.confidence)}</div><div class="seg" id="kindSeg">${kinds.map(([k,l])=>`<button data-k="${k}" class="${p.kind===k?'on':''}" onclick="pickKind(this)">${l}</button>`).join('')}</div><input class="field" id="storageName" placeholder="Например: Mercedes / Склад дома"><div id="bindList">${(p.candidates||[]).map(c=>`<button class="fullbtn" onclick="send('storage_bind',{storage_id:'${esc(c.id)}'});closeModal()">Это ${esc(c.name)}</button>`).join('')}</div><button class="fullbtn primary" onclick="createStorage()">Сохранить новое</button><button class="fullbtn" onclick="send('storage_cancel');closeModal()">Не сохранять</button>`;$('#modal').classList.add('on')}function pickKind(el){$('#kindSeg button').forEach(x=>x.classList.remove('on'));el.classList.add('on')}function createStorage(){const name=($('#storageName').value||'').trim(),kind=$('#kindSeg .on')?.dataset.k||'other';if(!name)return toast('Введите название');send('storage_create',{name,storage_kind:kind});closeModal()}function openUpdates(){const u=S.data?.updater||{};$('#sheet').innerHTML=`<h3>Обновления</h3><div class="card"><div class="meta">Текущая версия</div><div class="name">${esc(S.data?.version||'?')}</div><div class="meta" style="margin-top:10px">${esc(u.status||'—')}</div></div><button class="fullbtn" onclick="send('updater_check')">Проверить обновления</button>${u.available?`<button class="fullbtn primary" onclick="send('updater_install')">Установить ${esc(u.remote_version||'')}</button>`:''}<button class="fullbtn" onclick="closeModal()">Закрыть</button>`;$('#modal').classList.add('on')}function closeModal(){$('#modal').classList.remove('on')}$('#modal').addEventListener('click',e=>{if(e.target.id==='modal')closeModal()});window.Palatka={receiveStateB64(b64){try{const bin=atob(b64),bytes=Uint8Array.from(bin,c=>c.charCodeAt(0));const json=new TextDecoder('utf-8').decode(bytes);S.data=JSON.parse(json);renderHome();renderStorage();if(S.data.pending)openPending(S.data.pending)}catch(e){toast('Ошибка state: '+e.message)}}};setTimeout(()=>send('sync'),250);</script></body></html>]=]
    W.package_manifest_url = 'https://raw.githubusercontent.com/alikbot001/palatka-ai/main/package.json'
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
    DSP.version='2.6.0-webui-bootstrap'
    if DSP.notify then DSP.notify('WebUI 2.6 bootstrap installed. /crr opens WebUI; legacy UI is fallback.') end
    return true
end
