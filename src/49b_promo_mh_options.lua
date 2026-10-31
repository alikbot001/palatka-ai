-- Market Helper style template controls over Palatka's safe chat-command queue.
-- Manual "send now" can run every enabled row with a configurable inter-line pause.
local P=DSP.promo
if P._mh_options_v293_installed then return true end
P._mh_options_v293_installed=true
P._mh_options_installed=true
P.MIN_INTERVAL=30
local function int(v,min,max)
    v=tonumber(v)
    if not v or v~=v then return nil end
    return math.max(min,math.min(max,math.floor(v)))
end
local function decimal(v,min,max,default)
    v=tonumber(v)
    if not v or v~=v then return default end
    return math.max(min,math.min(max,v))
end
function P.save_template_options(index,opts)
    local list=P.settings().templates
    local t=list[index]
    if not t then return false,'Шаблон не найден'end
    opts=opts or{}
    local previous={min=t.interval_min,max=t.interval_max,
        limit=t.auto_limit,random=t.random_line,waiting=t.waiting}
    local low=int(opts.interval_min,0,3600)or 0
    local high=int(opts.interval_max,0,3600)or 0
    if low>0 and low<P.MIN_INTERVAL then low=P.MIN_INTERVAL end
    if high>0 and high<P.MIN_INTERVAL then high=P.MIN_INTERVAL end
    if high>0 and high<low then high=low end
    t.interval_min=low;t.interval_max=high
    t.auto_limit=int(opts.auto_limit,0,1000)or 0
    t.random_line=opts.random_line==true
    t.waiting=decimal(opts.waiting,.5,10,1.5)
    local ok=not DSP.save_settings or DSP.save_settings()~=false
    if not ok then
        t.interval_min=previous.min;t.interval_max=previous.max
        t.auto_limit=previous.limit;t.random_line=previous.random;t.waiting=previous.waiting
        return false,'Не удалось сохранить настройки'
    end
    return true
end
local old_steps=P.steps
function P.steps()
    local all=old_steps()
    local result={}
    local random_by_template={}
    for _,step in ipairs(all)do
        local t=P.settings().templates[step.index]
        if not(t and t.random_line)then result[#result+1]=step
        elseif not random_by_template[step.index]then
            local options={}
            for _,candidate in ipairs(all)do if candidate.index==step.index then options[#options+1]=candidate end end
            if #options>0 then
                local choose=t._random_index
                if not choose or choose>#options then choose=math.random(1,#options);t._random_index=choose end
                result[#result+1]=options[choose]
            end
            random_by_template[step.index]=true
        end
    end
    return result
end
local old_tick=P.tick
function P.tick(at,send,connected)
    local steps=P.steps()
    local i=P.cursor or 1
    local step=#steps>0 and steps[((i-1)%#steps)+1]or nil
    local before=P.session_count or 0
    local ok=old_tick(at,send,connected)
    if not ok or(P.session_count or 0)<=before or not step then return ok end
    local t=P.settings().templates[step.index]
    if not t then return ok end
    if t.random_line then t._random_index=nil end
    t.auto_count=(t.auto_count or 0)+1
    local lo=int(t.interval_min,0,3600)or 0
    local hi=int(t.interval_max,0,3600)or 0
    if lo>0 then
        hi=math.max(lo,hi)
        P.next_at=(at or os.time())+math.random(math.max(P.MIN_INTERVAL,lo),math.max(P.MIN_INTERVAL,hi))
    end
    local limit=int(t.auto_limit,0,1000)or 0
    if limit>0 and t.auto_count>=limit then
        t.auto=false;t.auto_count=0
        if DSP.save_settings then DSP.save_settings()end
        P.last_error='Шаблон «'..tostring(t.name or'?')..'»: лимит выполнен'
    end
    return ok
end
local function connected_now()
    if not sampSendChat then return false end
    if sampIsSampAvailable and not sampIsSampAvailable()then return false end
    if sampIsLocalPlayerSpawned and not sampIsLocalPlayerSpawned()then return false end
    return true
end
function P.send_template_once(index)
    if P.manual_busy then return false,'Уже отправляется другой шаблон'end
    local t=P.settings().templates[index]
    if not t then return false,'Шаблон не найден'end
    local rows={}
    for _,row in ipairs(t.rows or{})do
        if row.auto~=false and type(row.text)=='string'and P.validate(row.text)then rows[#rows+1]=row end
    end
    if #rows==0 then return false,'Нет включённых строк'end
    if not connected_now()then return false,'Нет подключения к игре'end
    if not(lua_thread and lua_thread.create and wait)then return false,'Игровой поток недоступен'end
    local pause=decimal(t.waiting,.5,10,1.5)
    P.manual_busy=true;P.manual_template=index;P.last_error=nil
    lua_thread.create(function()
        for i,row in ipairs(rows)do
            if not connected_now()then P.last_error='Нет подключения к игре';break end
            local resolved,why=P.expand(row.text)
            if not resolved then P.last_error=tostring(why);break end
            local ok,result=pcall(sampSendChat,resolved)
            if not ok or result==false then P.last_error='Отправка не удалась';break end
            local at=os.time()
            P.last_sent=at;P.session_count=(P.session_count or 0)+1
            t.last_sent=at;row.last_sent=at;P.last_command=resolved
            if i<#rows then wait(math.floor(pause*1000))end
        end
        P.manual_busy=false;P.manual_template=nil
        if DSP.save_settings then DSP.save_settings()end
    end)
    return true
end
function P.queue_left()
    if not P.running then return nil end
    return math.max(0,(tonumber(P.next_at)or 0)-os.time())
end
return true
