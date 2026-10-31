-- Market Helper style template controls over Palatka's safe per-command queue.
-- Existing templates remain untouched until the user saves new options.
local P=DSP.promo
if P._mh_options_installed then return true end
P._mh_options_installed=true
local function int(v,min,max)
    v=tonumber(v)
    if not v or v~=v then return nil end
    return math.max(min,math.min(max,math.floor(v)))
end
function P.save_template_options(index,opts)
    local list=P.settings().templates
    local t=list[index]
    if not t then return false,'Шаблон не найден'end
    opts=opts or{}
    local previous={min=t.interval_min,max=t.interval_max,
        limit=t.auto_limit,random=t.random_line}
    local low=int(opts.interval_min,0,3600)or 0
    local high=int(opts.interval_max,0,3600)or 0
    if low>0 and low<60 then low=60 end
    if high>0 and high<60 then high=60 end
    if high>0 and high<low then high=low end
    t.interval_min=low;t.interval_max=high
    t.auto_limit=int(opts.auto_limit,0,1000)or 0
    t.random_line=opts.random_line==true
    local ok=not DSP.save_settings or DSP.save_settings()~=false
    if not ok then
        t.interval_min=previous.min;t.interval_max=previous.max
        t.auto_limit=previous.limit;t.random_line=previous.random
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
        if not (t and t.random_line)then
            result[#result+1]=step
        elseif not random_by_template[step.index]then
            local options={}
            for _,candidate in ipairs(all)do
                if candidate.index==step.index then options[#options+1]=candidate end
            end
            if #options>0 then
                -- Pick once per cycle, not independently at each rendering/tick call.
                local choose=t._random_index
                if not choose or choose>#options then
                    choose=math.random(1,#options);t._random_index=choose
                end
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
    if not ok or (P.session_count or 0)<=before or not step then return ok end
    local t=P.settings().templates[step.index]
    if not t then return ok end
    if t.random_line then t._random_index=nil end
    t.auto_count=(t.auto_count or 0)+1
    local lo=int(t.interval_min,0,3600)or 0
    local hi=int(t.interval_max,0,3600)or 0
    if lo>0 then
        hi=math.max(lo,hi)
        P.next_at=(at or os.time())+math.random(math.max(60,lo),math.max(60,hi))
    end
    local limit=int(t.auto_limit,0,1000)or 0
    if limit>0 and t.auto_count>=limit then
        t.auto=false;t.auto_count=0
        if DSP.save_settings then DSP.save_settings()end
        P.last_error='Шаблон «'..tostring(t.name or'?')..'»: лимит выполнен'
    end
    return ok
end
return true
