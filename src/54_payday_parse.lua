-- Conservative PayDay fields. A bank/deposit balance is evidence, never salary.
local function lower(s)return(DSP.lower or string.lower)(s)end
function DSP.payday_part(text)
    text=tostring(text or '')
    if text:find('%[%d+%]:')or text:match('^%s*%[')then return nil end
    local s=lower(text)
    local function has(word)return s:find(lower(word),1,true)end
    local metric=has('сумма в банке')and'bank'or has('сумма на депозите')and'deposit'
    if metric then
        local gain=text:match('%(%+%$?([%d%., ]+)%)')
        return{raw=text,amount=0,direction='meta',metric=metric,
            reported_gain=gain and tonumber((gain:gsub('[^%d]','')))or nil}
    end
    local expense=has('налог')or has('списано')or has('удержано')
    local income=has('зарплат')or has('заработная плата')or has('премия')or has('пенсия')or has('начислено')
    if not expense and not income then return nil end
    local raw=text:match('%$%s*([%d%., ]+)')or text:match('([%d][%d%., ]*)%s*%$')
    local amount=raw and tonumber((raw:gsub('[^%d]','')))
    if not amount then return nil end
    return{raw=text,amount=amount,direction=expense and'expense'or'income',metric=expense and'expense'or'salary'}
end

-- Explicit deposit growth is independent income; the bank gain mirrors salary.
function DSP.payday_contribution(part)
    part=part or {}
    if part.metric=='bank' then return 0,0 end
    if part.metric=='deposit' and part.direction=='meta' then
        return math.max(0,tonumber(part.reported_gain) or 0),0
    end
    local amount=tonumber(part.amount) or 0
    if part.direction=='income' then return amount,0 end
    if part.direction=='expense' then return 0,amount end
    return 0,0
end

-- Recalculate derived fields of legacy inline evidence without changing any detail.
function DSP.payday_restore(row)
    if not row.details or #row.details==0 then return row end
    local incoming,outgoing=0,0
    for _,part in ipairs(row.details) do
        local credited,debited=DSP.payday_contribution(part)
        incoming,outgoing=incoming+credited,outgoing+debited
    end
    row.income,row.expense=incoming,outgoing
    row.amount=incoming-outgoing
    return row
end
