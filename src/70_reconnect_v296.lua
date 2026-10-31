-- Palatka AI 2.9.6: bounded, opt-in reconnect + exact observed dialog spawn.
-- No credential storage, CEF spoofing, bypass of kicks/bans, or endless retry storms.
DSP.reconnect=DSP.reconnect or {}
local R=DSP.reconnect
if R._v296 then return true end
R._v296=true
local function now()return os.time()end
local function num(v,lo,hi,default)
    v=tonumber(v)
    if not v or v~=v then v=default end
    return math.floor(math.max(lo,math.min(hi,v)))
end
local defaults={
    enabled=false, on_lost=true, on_closed=false, on_rejected=false,
    initial_delay=8, min_delay=12, max_delay=150, jitter=4,
    max_attempts=8, connect_timeout=55, stable_seconds=5,
    spawn_enabled=false, spawn_delay=2, profiles={}
}
local keys={
    enabled=true,on_lost=true,on_closed=true,on_rejected=true,spawn_enabled=true
}
local limits={
    initial_delay={3,180}, min_delay={8,300}, max_delay={15,900},
    jitter={0,30},max_attempts={1,30},connect_timeout={30,180},
    stable_seconds={2,30},spawn_delay={1,15}
}
function R.config()
    if type(DSP.settings.reconnect)~='table' then DSP.settings.reconnect={}end
    local c=DSP.settings.reconnect
    for k,v in pairs(defaults)do
        if c[k]==nil then
            if type(v)=='table' then c[k]={}else c[k]=v end
        end
    end
    if type(c.profiles)~='table' then c.profiles={}end
    for k,l in pairs(limits)do c[k]=num(c[k],l[1],l[2],defaults[k])end
    if c.max_delay<c.min_delay then c.max_delay=c.min_delay end
    for k in pairs(keys)do c[k]=c[k]==true end
    return c
end
local function persist()
    if type(DSP.save_settings)=='function' then
        local ok,why=DSP.save_settings()
        if not ok then return false,tostring(why or'Cannot save settings')end
    end
    return true
end
function R.set(key,value)
    local c=R.config()
    if not keys[key] and not limits[key]then return false,'Unknown setting'end
    local prev=c[key]
    if keys[key]then value=value==true else
        local l=limits[key];value=num(value,l[1],l[2],defaults[key])
    end
    c[key]=value
    if c.max_delay<c.min_delay then c.max_delay=c.min_delay end
    local ok,why=persist()
    if not ok then c[key]=prev;return false,why end
    if key=='enabled' and not value then R.stop('Auto reconnect switched off')end
    return true
end
local function clean(s)
    s=tostring(s or''):gsub('{[%x]+}',''):gsub('%c',' '):gsub('%s+',' ')
    s=s:gsub('^%s+',''):gsub('%s+$','')
    return s
end
local function normalize(s)
    s=clean(s)
    return type(DSP.lower)=='function' and DSP.lower(s)or string.lower(s)
end
local function address(host,port)
    host=type(host)=='string' and host or ''
    port=tonumber(port)
    if host=='' or host:find('[%s/@]') or not port or port<1 or port>65535 then return nil end
    return host,math.floor(port)
end
function R.remember_address()
    if type(sampGetCurrentServerAddress)~='function' then return false end
    local ok,host,port=pcall(sampGetCurrentServerAddress)
    if not ok then return false end
    host,port=address(host,port)
    if not host then return false end
    local old=R.server_key()
    R.host,R.port=host,port
    if old and old~=R.server_key()then
        R.options={}
        R.dialog_id=nil
        R.spawn_pending=nil
    end
    return true
end
function R.server_key()
    return R.host and R.port and(R.host..':'..R.port)or nil
end
function R.profile()
    local key=R.server_key()
    if not key then return nil end
    local c=R.config()
    if type(c.profiles[key])~='table'then c.profiles[key]={}end
    return c.profiles[key]
end
function R.select_spawn(label)
    local p=R.profile()
    if not p then return false,'Unknown server: connect first'end
    if label~=nil and type(label)~='string' then return false,'Invalid spawn label'end
    local found=label==nil
    for _,o in ipairs(R.options or{})do
        if label and o.label==label then found=true;break end
    end
    if not found then return false,'Spawn was not observed in the game dialog'end
    local old=p.spawn_label
    p.spawn_label=label
    local ok,why=persist()
    if not ok then p.spawn_label=old;return false,why end
    return true
end
R.state=R.state or'idle'
R.attempts=R.attempts or 0
R.status=R.status or'Idle'
R.next_at=R.next_at or 0
R.last_reason=R.last_reason or''
R.options=R.options or{}
local function report(s)
    R.status=tostring(s)
    if DSP.flog then DSP.flog('RECONNECT: '..R.status)end
end
function R.stop(reason)
    R.state='idle';R.next_at=0;R.started_at=nil
    R.attempts=0;R.spawn_pending=nil;R.awaiting_input=false
    R.last_reason=tostring(reason or'Cancelled')
    R.status=R.last_reason
    return true
end
local function blocked(s)
    s=normalize(s)
    for _,part in ipairs({
        'banned','you are banned','account blocked','captcha','wrong password','invalid password',
        'kicked','you are kicked','вы забан','аккаунт заблокирован','капч','неверный пароль',
        'неправильный пароль','вы были кикнуты','отказ в авторизации',
    })do
        if s:find(part,1,true)then return true end
    end
    return false
end
function R.on_message(s)
    if blocked(s)then
        R.stop('Authorization, ban or kick: manual action required')
        R.blocked=true
    end
end
local function interval(attempts)
    local c=R.config()
    local delay=c.min_delay*math.pow(2,math.max(0,attempts-1))
    delay=math.min(c.max_delay,delay)
    return math.floor(delay+math.random(0,c.jitter))
end
local function queue(reason,at)
    local c=R.config()
    if R.blocked then return false,'Blocked by authentication or kick'end
    if not R.host then R.remember_address()end
    if not R.host then return false,'No known server address'end
    if R.attempts>=c.max_attempts then
        R.stop('Attempt limit reached');return false,'Attempt limit reached'
    end
    R.state='scheduled'
    R.started_at=nil
    R.next_at=(at or now())+(R.attempts==0 and c.initial_delay or interval(R.attempts))
    R.status='Waiting for next attempt'
    R.last_reason=tostring(reason or'Disconnected')
    return true
end
function R.disconnected(kind,reason,at)
    kind=tostring(kind or'')
    if R.state=='scheduled' then return true,'Already scheduled'end
    local c=R.config()
    local allowed=(kind=='lost' and c.on_lost)or(kind=='closed'and c.on_closed)
        or(kind=='rejected'and c.on_rejected)
    R.last_reason=tostring(reason or kind)
    if blocked(R.last_reason)then
        R.on_message(R.last_reason)
        return false,'Authentication or kick'
    end
    if not c.enabled or not allowed then
        R.status='Disconnected; automatic retry disabled for '..kind
        return false,'Disabled'
    end
    return queue(kind,at)
end
function R.manual(at)
    if R.state=='connecting' or R.state=='scheduled'then
        return false,'Reconnect is already running'
    end
    R.blocked=false
    R.attempts=0
    R.awaiting_input=false
    if not R.host then R.remember_address()end
    if not R.host then return false,'No known server; enter it through Arizona launcher'end
    R.state='scheduled'
    R.next_at=at or now()
    R.status='Manual reconnect requested'
    return true
end
function R.connected(at)
    R.state='idle'
    R.attempts=0
    R.next_at=0
    R.started_at=nil
    R.awaiting_input=false
    R.blocked=false
    R.status='Connected'
    R.last_success=at or now()
    R.remember_address()
end
-- Connect uses an advertised MoonLoader/MonetLoader-compatible API if available.
-- Never call arbitrary RakNet disconnect RPCs or modify game memory.
local function connect()
    if type(sampConnectToServer)~='function' then
        return false,'sampConnectToServer not supported by this MonetLoader build'
    end
    return pcall(sampConnectToServer,R.host,R.port)
end
function R.tick(at)
    at=at or now()
    if type(sampIsLocalPlayerSpawned)=='function' then
        local ok,spawned=pcall(sampIsLocalPlayerSpawned)
        if ok and spawned then
            if R.state=='connecting'then R.connected(at)end
            if not R.last_seen_at or at-R.last_seen_at>=15 then R.last_seen_at=at;R.remember_address()end
        end
    end
    local pending=R.spawn_pending
    if pending and at>=pending.at then
        R.spawn_pending=nil
        local still=true
        if type(sampIsDialogActive)=='function' then
            local ok,val=pcall(sampIsDialogActive)
            still=ok and not not val
        end
        if still and type(sampGetCurrentDialogId)=='function' then
            local ok,id=pcall(sampGetCurrentDialogId)
            still=ok and tonumber(id)==pending.dialog_id
        end
        if still and type(sampSendDialogResponse)=='function' then
            local ok,result=pcall(sampSendDialogResponse,pending.dialog_id,1,pending.index,'')
            if ok and result~=false then R.status='Spawn choice sent: '..pending.label
            else R.status='Could not submit spawn dialog automatically'end
        end
    end
    if R.state=='idle' or R.awaiting_input then return false end
    local c=R.config()
    if R.state=='connecting' then
        if at-(R.started_at or at)>=c.connect_timeout then
            return queue('Connection timeout',at)
        end
        return false
    end
    if R.state~='scheduled' or at<R.next_at then return false end
    if R.attempts>=c.max_attempts then
        R.stop('Attempt limit reached');return false
    end
    R.attempts=R.attempts+1
    local called,ok,why=connect()
    if not called or ok==false then
        R.status='Reconnect API unavailable'
        R.state='idle'
        R.last_error=tostring(why or ok or'Unknown connection error')
        return false
    end
    R.state='connecting'
    R.started_at=at
    R.status='Connecting: attempt '..R.attempts..' of '..c.max_attempts
    return true
end
-- Exact spawn option matching only. No guessed row index or teleport coordinates.
local function spawn_title(title)
    local s=normalize(title)
    if blocked(s) or s:find('password',1,true) or s:find('парол',1,true)
        or s:find('авторизац',1,true) then return false end
    return s:find('спавн',1,true)~=nil or s:find('spawn',1,true)~=nil
        or s:find('место появлен',1,true)~=nil or s:find('точк появлен',1,true)~=nil
end
function R.observe_dialog(id,style,title,content,at)
    if not R.host then R.remember_address()end
    id=tonumber(id);style=tonumber(style)or-1
    if not id or (style~=2 and style~=4 and style~=5) then
        if R.state=='connecting'then R.awaiting_input=true;R.status='Waiting for player input'end
        return false
    end
    if not spawn_title(title)then
        if R.state=='connecting'then R.awaiting_input=true;R.status='Waiting for player input'end
        return false
    end
    R.awaiting_input=false
    local options,lines={},{}
    for line in tostring(content or''):gmatch('[^\r\n]+')do
        lines[#lines+1]=line
    end
    local offset=style==5 and 1 or 0 -- tablist_headers has a separate header row
    for i=1+offset,#lines do
        local label=clean(lines[i]:match('^([^\t]+)') or lines[i])
        if label~=''then options[#options+1]={index=i-1-offset,label=label}end
    end
    R.options=options;R.dialog_id=id
    R.dialog_seen_at=at or now()
    local c,p=R.config(),R.profile()
    local want=p and p.spawn_label
    if not c.spawn_enabled or not want or want=='' then
        R.status='Spawn list detected: select preferred place in settings'
        return true
    end
    for _,row in ipairs(options)do
        if normalize(row.label)==normalize(want)then
            R.spawn_pending={at=(at or now())+c.spawn_delay,
                dialog_id=id,index=row.index,label=row.label}
            R.status='Exact spawn option found: '..row.label
            return true
        end
    end
    R.status='Saved spawn not found; select manually in game'
    return true
end
function R.install()
    if R.installed then return true end
    R.installed=true
    R.config()
    R.remember_address()
    if type(sampRegisterChatCommand)=='function' then
        pcall(sampRegisterChatCommand,'prc',function(argument)
            argument=tostring(argument or'')
            local ok,why
            if argument=='stop' or argument=='off'then ok=R.stop('Stopped by user')
            elseif argument=='status'then ok=true
            else ok,why=R.manual()end
            if type(sampAddChatMessage)=='function'then
                sampAddChatMessage('[Palatka Reconnect] '..tostring(why or R.status),0x66CC99)
            end
        end)
    end
    local ok,events=pcall(require,'samp.events')
    if ok and type(events)=='table' then
        local function wrap(name,fn)
            local previous=events[name]
            events[name]=function(...)
                local worked,why=pcall(fn,...)
                if not worked and DSP.flog then
                    DSP.flog('RECONNECT event '..name..': '..tostring(why))
                end
                if previous then return previous(...)end
            end
        end
        wrap('onShowDialog',function(id,style,title,button1,button2,content)
            R.observe_dialog(id,style,title,content)
        end)
        wrap('onServerMessage',function(color,text)R.on_message(text)end)
        wrap('onConnectionLost',function(...)R.disconnected('lost','Connection lost')end)
        wrap('onConnectionClosed',function(...)R.disconnected('closed','Connection closed')end)
        wrap('onConnectionRejected',function(...)R.disconnected('rejected','Connection rejected')end)
        wrap('onConnectionAttemptFailed',function(...)R.disconnected('lost','Connection attempt failed')end)
        wrap('onConnectionAccepted',function(...)
            if R.state=='connecting'then
                R.awaiting_input=true
                R.status='Connected to server; waiting for authorization'
            end
        end)
        wrap('onSpawn',function(...)R.connected()end)
        wrap('onSendDialogResponse',function(id,...)
            if tonumber(id)==R.dialog_id then R.spawn_pending=nil end
        end)
    end
    if lua_thread and type(lua_thread.create)=='function' and type(wait)=='function'then
        lua_thread.create(function()
            while true do
                wait(500)
                local worked,why=pcall(R.tick)
                if not worked and DSP.flog and why~=R._last_tick_error then
                    R._last_tick_error=why
                    DSP.flog('RECONNECT worker: '..tostring(why))
                end
            end
        end)
    end
    return true
end
R.install()
return true
