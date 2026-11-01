-- v2.9.4: Market Helper scheduler: one template = one batch of chat commands.
-- No packet injection or server cooldown bypass. Fully opt-in and cancellable.
local P=DSP.promo
if P._mh_scheduler_v294 then return true end
P._mh_scheduler_v294=true

local function now()return os.time()end
local function session_limit()
    return DSP.controls and DSP.controls.get and DSP.controls.get('promo_session_limit')
        or P.MAX_SESSION or 12
end
local function global_cooldown()
    return DSP.controls and DSP.controls.get and DSP.controls.get('promo_global_cooldown_s')
        or global_cooldown()
end
local function connected()
    if type(sampSendChat)~='function' then return false end
    if sampIsSampAvailable and not sampIsSampAvailable()then return false end
    if sampIsLocalPlayerSpawned and not sampIsLocalPlayerSpawned()then return false end
    return true
end
local function clamp(v,lo,hi,default)
    v=tonumber(v)
    if not v or v~=v then return default end
    return math.max(lo,math.min(hi,v))
end
local function persist()
    if DSP.save_settings then
        local ok,why=DSP.save_settings()
        if not ok and DSP.flog then DSP.flog('PROMO SAVE ERROR: '..tostring(why))end
        return ok~=false,why
    end
    return true
end
local function rows(t)
    local result={}
    for _,r in ipairs(t.rows or{})do
        if r.auto~=false and type(r.text)=='string' and r.text~='' and P.validate(r.text)then
            result[#result+1]=r.text
        end
    end
    return result
end
local function active()
    for i,t in ipairs(P.settings().templates)do
        if t.auto~=false and #rows(t)>0 then return true end
    end
    return false
end
local function interval(t)
    local low=clamp(t.interval_min,0,3600,0)
    if low<=0 then
        low=clamp((t.rows or{})[1] and t.rows[1].interval or t.interval,30,3600,180)
    end
    local high=clamp(t.interval_max,0,3600,0)
    if high<=0 or high<low then high=low end
    low=math.max(30,math.floor(low))
    high=math.max(low,math.floor(high))
    return low==high and low or math.random(low,high)
end
local function make_batch(index,t,manual,at)
    local commands=rows(t)
    if #commands==0 then return nil,'Нет разрешённых строк в шаблоне'end
    if t.random_line and #commands>1 then commands={commands[math.random(1,#commands)]}end
    return {index=index,commands=commands,pos=1,manual=manual==true,
        due=at,waiting=clamp(t.waiting,.5,10,1.5)}
end
local function set_stopped(reason)
    local s=P.settings()
    P.running=false;P._batch=nil;P.manual_busy=false;P.manual_template=nil
    P.pause_reason=reason or 'Выключен'
    s.enabled=false
    persist()
end
local function report_error(err)
    P.last_error=tostring(err or'Ошибка отправки')
    P.pause_reason=P.last_error
    if DSP.flog then DSP.flog('PROMO: '..P.last_error)end
end
function P.start(at)
    at=at or now()
    if not active()then return false,'Включи хотя бы один шаблон с командами'end
    local s=P.settings()
    if not s.continuous and (P.session_count or 0)>=session_limit() then
        return false,'Лимит отправок сессии исчерпан'
    end
    local prior=s.enabled
    s.enabled=true
    local ok,why=persist()
    if not ok then s.enabled=prior;return false,tostring(why or'Не удалось сохранить запуск')end
    P.running=true;P.last_error=nil;P.pause_reason=nil;P._batch=nil
    P.manual_busy=false;P.manual_template=nil
    P.was_online=false
    P.next_at=at+clamp(s.start_delay,10,120,20)
    for _,t in ipairs(s.templates)do t._promo_due=nil end
    return true
end
function P.stop()
    set_stopped('Остановлен пользователем')
end
function P.bootstrap(at)
    at=at or now()
    local s=P.settings()
    P.running=false;P._batch=nil;P.manual_busy=false;P.manual_template=nil
    P.session_count=0;P.last_sent=0;P.was_online=false;P.last_error=nil
    P.next_at=0
    for _,t in ipairs(s.templates)do t._promo_due=nil end
    if s.resume_on_login and s.enabled and active() then
        P.running=true
        P.next_at=at+clamp(s.start_delay,10,120,20)
        P.pause_reason='Ожидание подключения'
    end
end
function P.send_template_once(index)
    if P._batch then return false,'Дождись завершения текущего шаблона'end
    if not connected()then return false,'Нет подключения к игре'end
    local t=P.settings().templates[index]
    if not t then return false,'Шаблон не найден'end
    local batch,why=make_batch(index,t,true,now())
    if not batch then return false,why end
    P._batch=batch
    P.manual_busy=true;P.manual_template=index
    P.last_error=nil;P.pause_reason=nil
    return true
end
local function finish_batch(batch,at)
    local s=P.settings()
    local t=s.templates[batch.index]
    if t then
        t.last_sent=at
        if not batch.manual then
            t.auto_count=(tonumber(t.auto_count)or 0)+1
            local limit=clamp(t.auto_limit,0,1000,0)
            if limit>0 and t.auto_count>=limit then
                t.auto=false
                t.auto_count=0
                P.last_error='Шаблон «'..tostring(t.name or'?')..'»: достигнут лимит'
            end
            t._promo_due=at+interval(t)
        end
    end
    P._batch=nil;P.manual_busy=false;P.manual_template=nil
    P.next_at=at+global_cooldown()
    persist()
end
local function step_batch(at,send,online)
    local batch=P._batch
    if not batch or at<batch.due then return false end
    if not online then
        report_error('Нет соединения: отправка приостановлена')
        P._batch=nil;P.manual_busy=false;P.manual_template=nil
        return false
    end
    if not P.settings().continuous and (P.session_count or 0)>=session_limit() then
        set_stopped('Лимит сообщений за сессию')
        return false
    end
    local raw=batch.commands[batch.pos]
    local cmd,why=P.expand(raw)
    if not cmd or #cmd>P.MAX_STEP_BYTES then
        report_error(why or'Команда превышает 200 байт')
        P._batch=nil;P.manual_busy=false;P.manual_template=nil
        P.next_at=at+30
        return false
    end
    local sender=send or sampSendChat
    if type(sender)~='function'then report_error('Отправка чата недоступна');return false end
    local ok,result=pcall(sender,cmd)
    if not ok or result==false then
        report_error(ok and'Отправка отклонена' or result)
        P._batch=nil;P.manual_busy=false;P.manual_template=nil
        P.next_at=at+30
        return false
    end
    P.last_sent=at
    P.last_command=cmd
    P.session_count=(P.session_count or 0)+1
    batch.pos=batch.pos+1
    P.last_error=nil
    if batch.pos>#batch.commands then
        finish_batch(batch,at)
    else
        batch.due=at+math.max(1,math.ceil(batch.waiting))
        P.next_at=batch.due
    end
    if not P.settings().continuous and P.session_count>=session_limit() then
        set_stopped('Лимит сообщений за сессию')
    end
    return true
end

function P.tick(at,send,online)
    at=at or now()
    if online==nil then online=connected()end
    if P._batch then return step_batch(at,send,online)end
    if not P.running then return false end
    if not online then
        P.was_online=false
        P.pause_reason='Нет подключения: ожидание'
        return false
    end
    local s=P.settings()
    if not P.was_online then
        P.was_online=true
        P.next_at=math.max(P.next_at or 0,at+clamp(s.start_delay,10,120,20))
        P.pause_reason='Ожидание после входа'
        return false
    end
    if at<(P.next_at or 0)then return false end
    if not s.continuous and P.session_count>=session_limit() then
        set_stopped('Лимит сообщений за сессию')
        return false
    end
    local earliest
    for index,t in ipairs(s.templates)do
        if t.auto~=false and #rows(t)>0 then
            local due=t._promo_due
            if not due then
                local last=tonumber(t.last_sent)or 0
                due=last>0 and last+interval(t)or at
                t._promo_due=due
            end
            if at>=due and at>=((P.last_sent or 0)+global_cooldown()) or
               (at>=due and (P.last_sent or 0)==0) then
                local batch,why=make_batch(index,t,false,at)
                if not batch then report_error(why);return false end
                P._batch=batch
                P.pause_reason=nil
                return step_batch(at,send,online)
            end
            earliest=not earliest and due or math.min(earliest,due)
        end
    end
    if not earliest then
        set_stopped('Нет включённых шаблонов')
    else
        P.next_at=math.max(at+1,earliest)
    end
    return false
end
function P.queue_left()
    if P._batch then return math.max(0,math.ceil(P._batch.due-now()))end
    if not P.running then return nil end
    return math.max(0,math.ceil((P.next_at or 0)-now()))
end
return true
