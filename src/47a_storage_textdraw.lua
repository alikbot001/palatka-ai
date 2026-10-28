-- Bounded, explicitly armed TextDraw observation for container diagnostics.
-- This is NOT OCR, memory reading or a general inventory scraper.
local S=DSP.storage
S.td_session=S.td_session or {state='off',draws={},seen=0}
local T=S.td_session
local function now() return os.time() end
local function valid()
    if T.state~='armed' then return false end
    if now()>(T.until_ts or 0) then T.state='expired';return false end
    return true
end
function S.arm_textdraw(seconds)
    T.state='armed';T.until_ts=now()+math.max(5,math.min(60,tonumber(seconds)or 25))
    T.draws={};T.seen=0;T.unique=0;T.last_error=nil;T.selected_kind=nil;T.result=nil
    return true
end
function S.textdraw_state()
    valid()
    return T.state,T.seen or 0,T.last_error
end
local function text_of(value)
    if type(value)=='table' then value=value.text end
    if type(value)~='string' then return nil end
    local s=DSP.clean_text(value):gsub('~[%w]~',''):gsub('[\r\n]',' ')
    s=DSP.trim(s)
    if s=='' or #s>255 then return nil end
    return s
end
function S.observe_textdraw(id,value)
    if not valid() then return false end
    if type(id)~='number' and type(id)~='string' then return false end
    local s=text_of(value)
    if not s then return false end
    T.seen=T.seen+1
    -- Bounded by 110 unique IDs; update in place, no per-frame scanning.
    if T.draws[id]==nil and (T.unique or 0)>=110 then return false end
    if T.draws[id]==nil then T.unique=(T.unique or 0)+1 end
    T.draws[id]=s
    return true
end
function S.finish_textdraw()
    if T.state~='armed' and T.state~='expired' then return false,'Нет активного сбора' end
    T.state='done'
    local lines={}
    local kind,title
    local ids={}
    for id in pairs(T.draws or {}) do ids[#ids+1]=id end
    table.sort(ids,function(a,b)return tostring(a)<tostring(b)end)
    for _,id in ipairs(ids) do
        local line=T.draws[id]
        local k=S.kind_of(line)
        if k and not kind then kind=k;title=line end
        local r=S.parse_line(line)
        -- Unknown qty from a TextDraw is a UI label, not a reliable item count.
        if r and r.quantity_confirmed and not k then lines[#lines+1]=line end
    end
    if not kind then
        T.last_error='В TextDraw не обнаружен заголовок хранилища. Возможно, окно нативное.'
        return false,T.last_error
    end
    if #lines==0 then
        T.last_error='Есть заголовок '..tostring(title)..', но нет строк с достоверным количеством.'
        return false,T.last_error
    end
    local ok,r=S.accept(kind,title,table.concat(lines,'\n'),now(),'textdraw')
    if not ok then T.last_error=tostring(r);return false,T.last_error end
    T.result=r;T.last_error=nil
    return true,r
end
function S.install_textdraw()
    if S.td_hook_installed then return end
    local ok,sampev=pcall(require,'samp.events')
    if not ok or not sampev then return false,'samp.events unavailable' end
    S.td_hook_installed=true
    local prev_show=sampev.onShowTextDraw
    sampev.onShowTextDraw=function(id,data)
        if T.state=='armed' then pcall(S.observe_textdraw,id,data) end
        if prev_show then return prev_show(id,data) end
    end
    local prev_change=sampev.onTextDrawSetString
    sampev.onTextDrawSetString=function(id,text)
        if T.state=='armed' then pcall(S.observe_textdraw,id,text) end
        if prev_change then return prev_change(id,text) end
    end
    return true
end
