-- Universal promotion scheduler. Built on Palatka's existing settings and
-- game connection; never bypasses server chat cooldowns or auto-posts by default.
local P=DSP.promo
P.MIN_INTERVAL=60
P.MAX_SESSION=12
P.MAX_TEMPLATES=32
P.MAX_STEP_BYTES=200
P.running=P.running==true
P.cursor=P.cursor or 1
P.next_at=P.next_at or 0
P.cycle_count=P.cycle_count or 0
P.pause_reason=nil
local function num(n,lo,hi)
    n=tonumber(n)
    if n and n==n and n%1==0 then return math.max(lo,math.min(hi,math.floor(n)))end
end
local function persist()
    if DSP.save_settings then return DSP.save_settings()~=false end
    if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save()end
    return true
end
local function settings()
    local s=P.settings()
    if s.continuous==nil then s.continuous=false end
    if s.resume_on_login==nil then s.resume_on_login=false end
    if s.enabled==nil then s.enabled=false end
    s.start_delay=num(s.start_delay,10,120)or 20
    return s
end
local function online()
    if not sampSendChat then return false end
    if sampIsSampAvailable and not sampIsSampAvailable()then return false end
    if sampIsLocalPlayerSpawned and not sampIsLocalPlayerSpawned()then return false end
    return true
end
local function trim(s)return tostring(s or ''):match('^%s*(.-)%s*$')end
function P.validate(text)
    if type(text)~='string' or #text==0 or #text>1500 then
        return false,'Введите команду или текст (до 1500 байт)'end
    if text:find('[%z\1-\8\11\12\14-\31]')then
        return false,'Управляющие символы запрещены'end
    local n=0
    for _,line in ipairs(P.lines(text))do
        n=n+1
        if n>12 then return false,'Не более 12 команд в одном старом шаблоне'end
        if #line>P.MAX_STEP_BYTES then return false,'Длина строки более 200 байт'end
        -- This scheduler sends chat commands only; no arbitrary raw packets.
        if not line:match('^/[%w_]+[%s%S]*$') then
            return false,'Строка должна начинаться с /команды'end
    end
    return n>0,n==0 and 'Пустой шаблон' or nil
end
local function normalize_item(name,text,interval,auto)
    local ok,err=P.validate(text);if not ok then return nil,err end
    local item={name=trim(name):sub(1,48),text=trim(text),
        interval=num(interval,P.MIN_INTERVAL,3600)or 180,auto=auto~=false,
        last_sent=0,line_index=0}
    if item.name==''then item.name='Строка'end
    return item
end
function P.add(name,text,interval)
    local s=settings()
    if #s.templates>=P.MAX_TEMPLATES then return false,'Лимит 32 строк'end
    local item,err=normalize_item(name,text,interval,true);if not item then return false,err end
    s.templates[#s.templates+1]=item
    if not persist()then table.remove(s.templates);return false,'Настройки не сохранены'end
    return true
end
function P.update(index,name,text,interval)
    local s=settings();local old=s.templates[index]
    if not old then return false,'Строка не найдена'end
    local new,err=normalize_item(name,text,interval,old.auto);if not new then return false,err end
    new.last_sent=old.last_sent or 0;new.line_index=old.line_index or 0
    s.templates[index]=new
    if not persist()then s.templates[index]=old;return false,'Настройки не сохранены'end
    return true
end
function P.remove(index)
    local s=settings()
    if not s.templates[index]then return false end
    local old=table.remove(s.templates,index)
    if not persist()then table.insert(s.templates,index,old);return false end
    P.cursor=math.max(1,math.min(P.cursor,#s.templates))
    return true
end
function P.move(index,delta)
    local rows=settings().templates;local next_index=index+delta
    if not rows[index]or not rows[next_index]then return false end
    rows[index],rows[next_index]=rows[next_index],rows[index]
    if not persist()then rows[index],rows[next_index]=rows[next_index],rows[index];return false end
    P.cursor=next_index
    return true
end
function P.set_option(option,value)
    if option~='continuous'and option~='resume_on_login'and option~='start_delay' then
        return false,'Неизвестный параметр'end
    local s=settings();local before=s[option]
    s[option]=option=='start_delay' and (num(value,10,120)or 20)or(value==true)
    if not persist()then s[option]=before;return false,'Настройки не сохранены'end
    return true
end
function P.steps()
    local rows={}
    for idx,t in ipairs(settings().templates)do
        if t.auto then
            for line_no,cmd in ipairs(P.lines(t.text or''))do
                local ok=P.validate(cmd)
                if ok then rows[#rows+1]={index=idx,line=line_no,command=cmd,
                    interval=num(t.interval,P.MIN_INTERVAL,3600)or 180,
                    name=t.name}end
            end
        end
    end
    return rows
end
function P.start(now)
    if #P.steps()==0 then return false,'Добавь и включи хотя бы одну строку'end
    local s=settings()
    if not s.continuous and P.session_count>=P.MAX_SESSION then
        return false,'Достигнут лимит 12 строк за сессию'end
    end
    P.running=true;P.pause_reason=nil;P.last_error=nil
    P.cursor=1
    P.next_at=(now or os.time())+s.start_delay
    P.started=now or os.time();P.was_online=false
    s.enabled=true
    if not persist()then
        P.running=false;s.enabled=false
        return false,'Не удалось сохранить режим'end
    end
    return true
end
function P.stop()
    P.running=false;P.pause_reason=nil
    settings().enabled=false
    persist()
end
function P.bootstrap(now)
    local s=settings()
    -- Persisted template flags do not implicitly authorize unattended posting.
    P.running=false;P.pause_reason=nil;P.was_online=false
    P.session_count=0;P.cursor=1;P.next_at=0;P.last_sent=0
    if s.resume_on_login and s.enabled and #P.steps()>0 then
        P.running=true
        P.next_at=(now or os.time())+s.start_delay
        P.pause_reason='Ожидание подключения'
    end
end
function P.send_once(index,at,send,connected)
    at=at or os.time()
    local t=settings().templates[index]
    if not t then return false,'Строка не найдена'end
    local ok,err=P.validate(t.text);if not ok then return false,err end
    local lines=P.lines(t.text)
    if #lines==0 then return false,'Пустая строка'end
    if P.last_sent>0 and at-P.last_sent<P.MIN_INTERVAL then
        return false,'Пауза до следующей отправки'end
    if connected==nil then connected=online()end
    if not connected then return false,'Нет подключения к игре'end
    local i=((num(t.line_index,0,1000)or 0)%#lines)+1
    local resolved,why=P.expand(lines[i])
    if not resolved then return false,why end
    if #resolved>P.MAX_STEP_BYTES then return false,'После подстановки текст длиннее 200 байт'end
    local sender=send or sampSendChat
    if type(sender)~='function'then return false,'Отправка чата недоступна'end
    local success,outcome=pcall(sender,resolved)
    if not success or outcome==false then return false,'Отправка не удалась'end
    P.last_sent=at;P.session_count=P.session_count+1
    t.last_sent=at;t.line_index=i
    P.last_command=resolved;P.last_error=nil
    return true
end
function P.tick(at,send,connected)
    if not P.running then return false end
    local s=settings();at=at or os.time()
    if connected==nil then connected=online()end
    if not connected then
        P.pause_reason='Нет соединения: отправка приостановлена'
        P.was_online=false
        return false
    end
    if not P.was_online then
        P.was_online=true
        P.next_at=math.max(P.next_at,at+s.start_delay)
        P.pause_reason='Ожидание после входа'
        return false
    end
    local steps=P.steps()
    if #steps==0 then P.running=false;P.pause_reason='Нет включённых строк';return false end
    if not s.continuous and P.session_count>=P.MAX_SESSION then
        P.running=false;P.pause_reason='Лимит 12 сообщений за сессию'
        s.enabled=false;persist();return false
    end
    if at<(P.next_at or 0)then return false end
    if P.last_sent>0 and at-P.last_sent<P.MIN_INTERVAL then
        P.next_at=P.last_sent+P.MIN_INTERVAL
        return false
    end
    local index=((P.cursor-1)%#steps)+1
    local step=steps[index]
    local ok,why=P.send_once(step.index,at,send,connected)
    if not ok then
        P.last_error=why;P.pause_reason=why
        P.next_at=at+math.max(P.MIN_INTERVAL,step.interval)
        return false
    end
    P.pause_reason=nil
    P.cursor=index%#steps+1
    if P.cursor==1 then P.cycle_count=(P.cycle_count or 0)+1 end
    P.next_at=at+math.max(P.MIN_INTERVAL,step.interval)
    if not s.continuous and P.session_count>=P.MAX_SESSION then
        P.running=false;P.pause_reason='Лимит отправок исчерпан'
        s.enabled=false;persist()
    end
    return true
end
-- Preserve Palatka's original background thread; replace only the scheduler.
local previous_install=P.install
function P.install()
    if P.installed then return end
    previous_install()
    P.bootstrap(os.time())
end
return true
