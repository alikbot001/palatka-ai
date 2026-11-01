-- Palatka AI 2.9.10: transactional promotion template save.
-- Keep all user-defined timing fields in the SAME durable write as the lines.
local P=DSP.promo
if not P or P._atomic_promo_2910 then return true end
P._atomic_promo_2910=true
local function num(v,low,high,default)
    v=tonumber(v)
    if not v or v~=v then return default end
    v=math.floor(v)
    if v<low or v>high then return nil end
    return v
end
local function trim(s)
    return tostring(s or''):match('^%s*(.-)%s*$')
end
local function flush()
    if type(DSP.save_settings)~='function'then return false,'Нет механизма сохранения'end
    local ok,saved,err=pcall(DSP.save_settings)
    if not ok then return false,tostring(saved)end
    if saved==false or saved==nil then return false,tostring(err or'Ошибка записи настроек')end
    -- In MonetLoader a successful return must correspond to actual saved bytes.
    if type(DSP.settings_path)=='string' and type(decodeJson)=='function' then
        local f=io.open(DSP.settings_path,'rb')
        if not f then return false,'Файл настроек не найден после сохранения'end
        local data=f:read('*a')or'';f:close()
        local pass,saved_data=pcall(decodeJson,data)
        if not pass or type(saved_data)~='table'
            or type(saved_data.promo)~='table'
            or type(saved_data.promo.templates)~='table' then
            return false,'Не удалось проверить записанные шаблоны'
        end
        local source=DSP.settings.promo.templates
        if #saved_data.promo.templates~=#source then
            return false,'Количество сохранённых шаблонов не совпадает'
        end
        for i,t in ipairs(source)do
            local disk=saved_data.promo.templates[i]
            if type(disk)~='table' or disk.name~=t.name
                or #(disk.rows or{})~=#(t.rows or{})
                or tonumber(disk.interval_min)~=tonumber(t.interval_min)
                or tonumber(disk.interval_max)~=tonumber(t.interval_max)
                or tonumber(disk.waiting)~=tonumber(t.waiting) then
                return false,'Проверка шаблона #'..i..' не пройдена'
            end
        end
    end
    return true
end
function P.save_template_complete(index,name,rows,enabled,options)
    local s=P.settings()
    if type(name)~='string' or #trim(name)<1 or #trim(name)>64 then
        return false,'Название должно быть от 1 до 64 байт'
    end
    name=trim(name)
    if type(rows)~='table' or #rows==0 or #rows>24 then
        return false,'Допустимо 1–24 рекламные строки'
    end
    local max_templates=tonumber(P.MAX_TEMPLATES)or 32
    if index~=nil then
        index=tonumber(index)
        if not index or index%1~=0 or not s.templates[index] then
            return false,'Шаблон не найден'
        end
    elseif #s.templates>=max_templates then
        return false,'Достигнут лимит шаблонов'
    end
    local previous=index and s.templates[index]or nil
    options=options or{}
    local low=num(options.interval_min,0,3600,previous and previous.interval_min or 0)
    local high=num(options.interval_max,0,3600,previous and previous.interval_max or 0)
    local limit=num(options.auto_limit,0,1000,previous and previous.auto_limit or 0)
    local waiting=tonumber(options.waiting)
    if low==nil or high==nil or limit==nil or not waiting
        or waiting~=waiting or waiting<.5 or waiting>10 then
        return false,'Неверные интервалы или лимит отправок'
    end
    if low>0 and low<(tonumber(P.MIN_INTERVAL)or 30)then
        return false,'Интервал меньше разрешённого'
    end
    if high>0 and high<low then return false,'Максимум меньше минимума'end
    local normalized,commands={},{}
    for i,row in ipairs(rows)do
        if type(row)~='table' then return false,'Ошибка строки '..i end
        local command=trim(row.text)
        local valid,why=P.validate(command)
        if not valid then return false,'Строка '..i..': '..tostring(why)end
        if #P.lines(command)~=1 then return false,'Только одна команда на строку'end
        local interval=num(row.interval,30,3600,300)
        if not interval then return false,'Неверный интервал строки '..i end
        commands[#commands+1]=command
        normalized[#normalized+1]={text=command,interval=interval,auto=row.auto~=false}
    end
    local record={}
    if previous then for k,v in pairs(previous)do record[k]=v end end
    record.name=name
    record.text=table.concat(commands,'\n')
    record.rows=normalized
    record.interval=normalized[1].interval
    record.auto=enabled==true
    record.interval_min=low
    record.interval_max=high
    record.auto_limit=limit
    record.random_line=options.random_line==true
    record.waiting=waiting
    record._promo_due=nil
    local target=index or (#s.templates+1)
    s.templates[target]=record
    local ok,why=flush()
    if not ok then
        if previous then s.templates[target]=previous
        else table.remove(s.templates,target)end
        P.last_save_error=tostring(why)
        if DSP.flog then DSP.flog('PROMO SAVE: '..P.last_save_error)end
        return false,P.last_save_error
    end
    P.last_save_error=nil
    P.last_saved_at=os.time()
    return true,target
end
return true
