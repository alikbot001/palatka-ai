-- v2.2.4: independent opt-in promotional templates. No dialog bypassing,
-- no posting until a user explicitly starts this session. Bounded rate.
DSP.promo = DSP.promo or {}
local P=DSP.promo
P.running=false;P.last_sent=0;P.session_count=0;P.last_error=nil
P.MAX_SESSION=12;P.MIN_INTERVAL=180
function P.settings()
    if type(DSP.settings.promo)~='table' then DSP.settings.promo={} end
    local s=DSP.settings.promo
    if type(s.templates)~='table' then s.templates={} end
    return s
end
-- One preset can contain multiple channels. Each line is sent separately
-- with the global cooldown: never batch flood several chats together.
P.ALLOWED={vr=true,s=true,ad=true,fam=true,gd=true}
function P.lines(text)
    local rows={}
    for line in (tostring(text or '')..'\n'):gmatch('([^\r\n]*)\r?\n') do
        line=line:match('^%s*(.-)%s*$')
        if line~='' then rows[#rows+1]=line end
    end
    return rows
end
function P.validate(text)
    if type(text)~='string' or #text<5 or #text>720 then return false,'текст 5–720 байт' end
    if text:find('[%z\1-\8\11\12\14-\31]') then return false,'запрещён управляющий символ' end
    local lines=P.lines(text)
    if #lines==0 or #lines>6 then return false,'от 1 до 6 строк рекламы' end
    for _,line in ipairs(lines) do
        if #line>200 then return false,'строка превышает 200 байт' end
        local command=line:match('^/([%a]+)%s+%S')
        if not (command and P.ALLOWED[command]) then
            return false,'строка должна начинаться с /vr, /s, /ad, /fam или /gd'
        end
    end
    return true
end
function P.own_shop_number()
    local s=P.settings()
    local manual=tonumber(s.shop_number)
    if manual and manual>=1 and manual<=99999 and manual%1==0 then return math.floor(manual),'в настройках' end
    if DSP.shop_identity and DSP.shop_identity.own_shop_number then
        local ok,n,src=pcall(DSP.shop_identity.own_shop_number)
        if ok and n then return n,'авто: '..tostring(src or 'identity') end
    end
    local saved=tonumber(DSP.settings and DSP.settings.own_shop_num_saved)
    if saved and saved>=1 and saved<=99999 and saved%1==0 then return math.floor(saved),'запомнен автоматически' end
    local shop=DSP.live and DSP.live.shop
    local nickname=DSP.player_nick and DSP.player_nick() or ''
    local id=shop and tonumber(shop.num)
    if nickname~='' and shop and DSP.lower(tostring(shop.owner or ''))==DSP.lower(nickname) and id and id>=1 and id<=99999 and id%1==0 then
        return math.floor(id),'своя открытая лавка'
    end
    return nil,'номер своей лавки пока не определён'
end
function P.set_shop_number(n)
    n=tonumber(n)
    if not n or n%1~=0 or n<0 or n>99999 then return false,'номер: 0–99999' end
    local s=P.settings();local before=s.shop_number
    s.shop_number=n
    if not DSP.save_settings() then s.shop_number=before;return false,'не удалось сохранить' end
    return true
end
function P.expand(text)
    if not (text:find('{лавка}',1,true) or text:find('{shop}',1,true) or text:find('[ЛАВКА]',1,true) or text:find('{номер}',1,true)) then return text end
    local num,err=P.own_shop_number()
    if not num then return nil,err end
    local clickable=':lavka'..tostring(num)..':'
    return (text:gsub('{лавка}',clickable):gsub('{shop}',clickable):gsub('%[ЛАВКА%]',clickable):gsub('{номер}',tostring(num)))
end
function P.add(name,text,interval)
    local s=P.settings()
    if #s.templates>=8 then return false,'максимум 8 шаблонов' end
    local ok,err=P.validate(text);if not ok then return false,err end
    local item={name=tostring(name or 'Объявление'):sub(1,48),text=text,
        interval=math.max(P.MIN_INTERVAL,math.min(3600,math.floor(tonumber(interval)or 300))),auto=false}
    s.templates[#s.templates+1]=item
    if not DSP.save_settings() then table.remove(s.templates);return false,'ошибка сохранения' end
    return true
end
function P.update(index,name,text,interval)
    local item=P.settings().templates[index]
    if not item then return false,'шаблон не найден' end
    local ok,err=P.validate(text);if not ok then return false,err end
    local previous={name=item.name,text=item.text,interval=item.interval,auto=item.auto}
    item.name=tostring(name or ''):sub(1,48)
    item.text=text
    item.interval=math.max(P.MIN_INTERVAL,math.min(3600,math.floor(tonumber(interval)or 300)))
    if not DSP.save_settings() then
        for k,v in pairs(previous)do item[k]=v end
        return false,'ошибка сохранения'
    end
    return true
end
function P.remove(index)
    local s=P.settings();if not s.templates[index] then return false end
    local old=table.remove(s.templates,index)
    if not DSP.save_settings() then table.insert(s.templates,index,old);return false end
    return true
end
local function online_check()
    if type(sampSendChat)~='function' then return false end
    if type(sampIsSampAvailable)=='function' and not sampIsSampAvailable() then return false end
    if type(sampIsLocalPlayerSpawned)=='function' and not sampIsLocalPlayerSpawned() then return false end
    return true
end
function P.send_once(index,now,send,online)
    now=now or os.time()
    local item=P.settings().templates[index]
    if not item then return false,'шаблон не найден' end
    local ok,err=P.validate(item.text);if not ok then return false,err end
    if P.session_count>=P.MAX_SESSION then P.running=false;return false,'лимит за сессию достигнут' end
    if P.last_sent>0 and now-P.last_sent<P.MIN_INTERVAL then return false,'подождите до следующей отправки' end
    if online==nil then online=online_check() end
    if not online then return false,'нет соединения с игрой' end
    local sender=send or sampSendChat
    local lines=P.lines(item.text)
    local index=(tonumber(item.line_index) or 0)%#lines+1
    local resolved,expand_err=P.expand(lines[index])
    if not resolved then return false,expand_err end
    if #resolved>200 then return false,'после подстановки текст слишком длинный' end
    local sent,response=pcall(sender,resolved)
    if not sent or response==false then return false,'команда не отправлена' end
    P.last_sent=now;P.session_count=P.session_count+1
    item.last_sent=now
    item.line_index=index
    P.last_error=nil
    if P.session_count>=P.MAX_SESSION then P.running=false end
    return true
end
function P.start()
    if #P.settings().templates==0 then return false,'сначала создайте шаблон' end
    local active=false
    for _,t in ipairs(P.settings().templates)do if t.auto then active=true end end
    if not active then return false,'выберите шаблон для автоматической отправки' end
    if P.session_count>=P.MAX_SESSION then return false,'лимит за сессию исчерпан' end
    P.running=true
    P.last_error=nil
    P.started=os.time()
    return true
end
function P.stop()P.running=false end
function P.tick(now,send,online)
    if not P.running then return false end
    now=now or os.time()
    if P.session_count>=P.MAX_SESSION then P.stop();return false end
    if online==false or (online==nil and not online_check()) then
        P.last_error='авто-пиар остановлен: соединение потеряно'
        P.stop();return false
    end
    if P.last_sent>0 and now-P.last_sent<P.MIN_INTERVAL then return false end
    for i,t in ipairs(P.settings().templates)do
        if t.auto and (not t.last_sent or now-t.last_sent>=math.max(P.MIN_INTERVAL,tonumber(t.interval)or 300)) then
            local ok,err=P.send_once(i,now,send,online)
            if not ok then P.last_error=err end
            return ok
        end
    end
    return false
end
function P.install()
    if P.installed then return end
    P.installed=true
    -- Resume only templates explicitly marked auto by the user. This is not
    -- a new opt-in: the persisted per-template flag is the user's choice.
    for _,t in ipairs(P.settings().templates) do
        if t.auto then P.running=true; break end
    end
    P.session_count=0
    if not lua_thread or not wait then return end
    lua_thread.create(function()
        while true do
            wait(1000)
            local ok,err=pcall(P.tick,os.time())
            if not ok then P.last_error=tostring(err);P.stop();if DSP.flog then DSP.flog('PROMO '..P.last_error)end end
            -- Watchlists are checked from the already loaded market snapshot;
            -- HTTP refresh remains owned by the existing market updater.
            if DSP.flip and DSP.flip.check_alerts then
                pcall(DSP.flip.check_alerts,os.time(),DSP.notify)
            end
        end
    end)
end
