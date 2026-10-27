DSP.craglog = {ring={},ring_cap=300,ring_head=1,ring_count=0,scroll=0}
local C=DSP.craglog;C.session_started=(DSP.logs and DSP.logs.session_started) or os.time()
local revision, summary_cache=0,{}
local function settings()
    DSP.settings.craglog=DSP.settings.craglog or {open=false,pinned=false,minimized=false,filter='all'}
    return DSP.settings.craglog
end
local function persist() return DSP.save_settings() end
function C.clear_ring()
    C.ring,C.ring_head,C.ring_count,C.scroll={},1,0,0
    C.counters={trades=0,sales=0,buys=0,crates=0,profit=0}
end
C.clear_ring()
function C.ring_push(entry)
    if type(entry)~='table' then return end
    C.ring[C.ring_head]=entry
    C.ring_head=C.ring_head%C.ring_cap+1
    C.ring_count=math.min(C.ring_count+1,C.ring_cap)
end
function C.ring_recent(n)
    n=math.max(0,math.min(C.ring_count,math.floor(tonumber(n) or C.ring_count)))
    local out={}
    for i=0,n-1 do out[#out+1]=C.ring[(C.ring_head-n+i-1)%C.ring_cap+1] end
    return out
end
local function category(e)
    if e.type=='payday' or e.kind=='payday' then return 'payday' end
    if e.type=='market' then return e.direction=='sell' and 'sales' or 'buys' end
    if e.kind=='income' or e.type=='income' then return 'income' end
    if e.kind=='cash' then return 'income' end
    if e.kind=='item' or e.kind=='opening' or e.kind=='unknown' or e.type=='crate' then return 'loot' end
    if (tonumber(e.money_get) or 0)>0 and (tonumber(e.money_give) or 0)==0 then return 'sales' end
    if (tonumber(e.money_give) or 0)>0 and (tonumber(e.money_get) or 0)==0 then return 'buys' end
    return 'other'
end
function C.filtered(filter)
    local out={}
    for _,e in ipairs(C.ring_recent(C.ring_count)) do
        if (not C.event_visible or C.event_visible(e)) and (filter=='all' or category(e)==filter or (filter=='loot' and e.kind=='cash')) then out[#out+1]=e end
    end
    return out
end
local function append(path,line)
    DSP.mkdir_p(DSP.dir..'/logs')
    local f,err=io.open(path,'a')
    if not f then C.last_error=err; DSP.add_log('Журнал: '..tostring(err),'error'); return false,err end
    local wrote,write_err=f:write(line..'\n')
    local closed,close_err=f:close()
    if not wrote or not closed then
        C.last_error=write_err or close_err; DSP.add_log('Журнал: '..tostring(C.last_error),'error')
        return false,C.last_error
    end
    C.last_error=nil
    return true
end
function C.describe(e)
    if e.kind=='item' or e.type=='crate' then
        local value=e.price_known and DSP.money(e.estimated_value or 0) or 'нет цены'
        local name=tostring(e.item_name or e.item or '?')
        if (tonumber(e.ench) or 0)>0 and not name:find('%(%+%d+%)$') then name=name..' (+'..e.ench..')' end
        return name..' x'..tostring(e.qty or e.count or 1)..' | Оценка: '..value
    elseif e.kind=='cash' then return 'Деньги: +'..DSP.money(e.cash or 0)
    elseif e.kind=='opening' then return 'Открытие: '..tostring(e.source or '?')
    elseif e.kind=='unknown' then return 'Награда: неизвестный тип | '..tostring(e.raw or '')
    elseif e.type=='payday' then return 'PayDay | '..(e.amount and ('Распознано: '..DSP.money(e.amount)) or 'Начисления не распознаны')
    elseif e.type=='income' then return tostring(e.label or 'Доход')..': +'..DSP.money(e.amount or 0)
    elseif e.type=='market' then
        return (e.direction=='sell' and 'Продажа: ' or 'Покупка: ')..tostring(e.item_name or '?')..' | '..(e.direction=='sell' and 'Выручка: +' or 'Расход: -')..DSP.money(e.amount or 0) end
    local parts={}
    for _,side in ipairs({{'items_give','Отдано'},{'items_get','Получено'}}) do
        for _,it in ipairs(e[side[1]] or {}) do parts[#parts+1]=side[2]..': '..tostring(it.name)..' x'..tostring(it.qty or 1) end
    end
    return tostring(e.partner or '?')..' | '..(#parts>0 and table.concat(parts,'; ')..' | ' or '')..'Итог сделки: '..DSP.money(e.profit or 0)
end
local function store_event(e)
    if not e.id and e.type~='payday_detail' and C.new_event_id then e.id=C.new_event_id(e.ts) end
    DSP.mkdir_p(DSP.dir..'/logs')
    local ok,encoded=pcall(encodeJson,e)
    if not ok or type(encoded)~='string' then C.last_error='JSON encoding error';return false,C.last_error end
    local saved,err=append(DSP.events_log_path,'\n'..encoded)
    if saved then revision=revision+1; summary_cache={} end
    return saved,err
end
function C.log_trade(e)
    if type(e)~='table' then return false,'нет записи' end
    C.ring_push(e); C.counters.trades=C.counters.trades+1
    C.counters.profit=C.counters.profit+(tonumber(e.profit) or 0)
    local key=category(e); if C.counters[key] then C.counters[key]=C.counters[key]+1 end
    local ok,err=append(DSP.trades_log_path,os.date('%Y-%m-%d %H:%M:%S',e.ts or os.time())..' '..C.describe(e))
    local stored,store_err=store_event(e)
    if not ok then C.last_error=err;return false,err end
    return stored,store_err
end
function C.log_crate(e)
    if type(e)~='table' then return false,'нет записи' end
    if e.id then
        for _,row in ipairs(C.ring_recent(C.ring_count)) do if row.id==e.id then return true end end
    end
    local row={type='crate',kind='item',ts=e.ts or os.time(),id=e.id,
        item_name=e.item_name or e.item,ench=e.ench,qty=e.qty or e.count or 1,source=e.source or e.crate_type,
        price_known=e.price_known or (tonumber(e.price) or 0)>0,unit_price=e.unit_price or e.price,
        estimated_value=e.estimated_value or ((tonumber(e.price) or 0)*(tonumber(e.qty or e.count) or 1))}
    C.ring_push(row); C.counters.crates=C.counters.crates+1
    return append(DSP.crates_log_path,os.date('%Y-%m-%d %H:%M:%S',row.ts)..' '..C.describe(row))
end
local function payday_part(text)
    if DSP.payday_part then return DSP.payday_part(text)end
    local lower=DSP.lower or string.lower;local s=lower(text or '')
    local expense=s:find(lower('налог'),1,true) or s:find(lower('списано'),1,true) or s:find(lower('удержано'),1,true)
    local income=s:find(lower('зарплат'),1,true) or s:find(lower('заработная плата'),1,true) or s:find(lower('премия'),1,true)
        or s:find(lower('пенсия'),1,true) or s:find(lower('начислено'),1,true)
    if not expense and not income then return nil end
    local amount=s:match('%$%s*([%d%., ]+)') or s:match('([%d][%d%., ]*)%s*%$')
    amount=amount and tonumber((amount:gsub('[^%d]','')));if not amount then return nil end
    return {raw=text,amount=amount,direction=expense and 'expense' or 'income'}
end
local function apply_detail(row,part)
    row.details=row.details or {};row.details[#row.details+1]=part
    if DSP.payday_restore then DSP.payday_restore(row);return end
    row[part.direction]=(row[part.direction] or 0)+part.amount
    row.amount=(row.income or 0)-(row.expense or 0)
end
function C.log_payday(summary,raw)
    summary=summary or {};local ts=os.time()
    local row={type='payday',kind='payday',id=C.new_event_id and C.new_event_id(ts) or ('payday-'..ts..'-'..tostring(revision)),ts=ts,
        profit=summary.profit or 0,count=summary.count or 0,raw=raw,details={}}
    local part=payday_part(raw)
    if part then apply_detail(row,part) end
    C.ring_push(row);C.active_payday=row
    return store_event(row)
end
function C.observe_payday(text)
    local row=C.active_payday
    if not row or os.time()-row.ts>12 then return false end
    if row.raw==text then return false end
    local part=payday_part(text)
    if not part then return false end
    for _,old in ipairs(row.details or {}) do if old.raw==part.raw then return true end end
    local saved=store_event({type='payday_detail',payday_id=row.id,ts=os.time(),detail=part})
    if saved then apply_detail(row,part) end
    return true
end
function C.log_income(label,amount,raw)
    amount=math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false,'сумма должна быть положительной' end
    local row={type='income',kind='income',ts=os.time(),amount=amount,label=label or 'Доход',raw=raw}
    C.ring_push(row)
    return store_event(row)
end
function C.log_market(direction,item,amount,raw)
    if direction~='sell' and direction~='buy' then return false,'сторона' end
    amount=math.floor(tonumber(amount) or 0)
    if amount<=0 then return false,'сумма' end
    local row={type='market',kind='market',ts=os.time(),direction=direction,
        item_name=item or '?',amount=amount,raw=raw}
    C.ring_push(row)
    return store_event(row)
end
function C.summary(period,now_ts)
    period=period or 'day';now_ts=now_ts or os.time()
    local from=period=='session' and C.session_started or 0
    if period=='day' then
        local date=os.date('*t',now_ts);date.hour,date.min,date.sec=0,0,0;from=os.time(date)
    end
    local key=period..':'..from..':'..revision..':'..tostring(C.visibility_revision or 0)..':'..tostring(DSP.logs and DSP.logs.revision or 0)..':'..tostring(DSP.rewards and DSP.rewards.sequence or 0)
    if summary_cache[key] then return summary_cache[key] end
    local out={count=0,income=0,expense=0,net=0,trade_profit=0,reward_cash=0,
        reward_estimated=0,unknown_items=0,payday_income=0,payday_expense=0,other_income=0}
    local f=io.open(DSP.events_log_path,'r')
    if f then
        for line in f:lines() do
            local ok,e=pcall(decodeJson,line)
            if ok and type(e)=='table' and (tonumber(e.ts) or 0)>=from and (not C.event_visible or C.event_visible(e)) then
                local incoming,outgoing=0,0
                if e.type=='market' then
                    if e.direction=='sell' then incoming=e.amount or 0 else outgoing=e.amount or 0 end
                elseif e.type=='income' then incoming=e.amount or 0;out.other_income=out.other_income+incoming
                elseif e.type=='payday' then
                    if DSP.payday_restore then DSP.payday_restore(e) end
                    incoming=e.income or 0;outgoing=e.expense or 0
                elseif e.type=='payday_detail' then
                    local part=e.detail or {}
                    if DSP.payday_contribution then incoming,outgoing=DSP.payday_contribution(part)
                    elseif part.direction=='income' then incoming=part.amount or 0
                    elseif part.direction=='expense' then outgoing=part.amount or 0 end
                end
                if e.type=='payday' or e.type=='payday_detail' then
                    out.payday_income=out.payday_income+incoming;out.payday_expense=out.payday_expense+outgoing
                end
                if e.type~='trade' and e.type~='payday_detail' then out.count=out.count+1 end
                out.income=out.income+incoming;out.expense=out.expense+outgoing
            end
        end
        f:close()
    end
    local trades=C.visible_trades and C.visible_trades(period,from) or (DSP.logs and DSP.logs.profit_summary and DSP.logs.profit_summary(period))
    if trades then
        out.count=out.count+trades.count;out.trade_profit=trades.profit
        out.income=out.income+(trades.cash_get or 0);out.expense=out.expense+(trades.cash_give or 0)
    end
    if DSP.rewards and DSP.rewards.summary then
        local rewards=DSP.rewards.summary({from_ts=from})
        out.reward_cash=rewards.cash;out.reward_estimated=rewards.estimated_value;out.unknown_items=rewards.unknown_items
        out.income=out.income+rewards.cash;out.count=out.count+(rewards.events or 0)
    end
    out.net=out.income-out.expense;summary_cache[key]=out
    return out
end
function C.visible() return settings().open==true end
function C.toggle() local s=settings(); s.open=not s.open; persist() end
function C.set_pinned(value)
    local s=settings(); s.pinned=value==true
    if s.pinned then s.open=true end
    persist()
end
function C.set_minimized(value) settings().minimized=value==true; persist() end
function C.set_anchor(x,y) local s=settings();s.x,s.y=tonumber(x) or 20,tonumber(y) or 120;persist() end
function C.drag(dx,dy)
    local s=settings(); if s.pinned then return false end
    local g=C.active_geometry
    s.x,s.y=(g and g.x or s.x or 24)+dx,(g and g.y or s.y or 120)+dy
    if g then s.x=math.max(8,math.min(s.x,g.max_x)); s.y=math.max(8,math.min(s.y,g.max_y)) end
    C.drag_dirty=true
    return true
end
function C.end_drag() if C.drag_dirty then persist(); C.drag_dirty=false end end
function C.geometry(sw,sh)
    local s=settings()
    local w=math.min(700,sw*.45)
    local expanded=math.min(620,sh*.69)
    local x=math.max(8,math.min(tonumber(s.x) or 24,sw-w-8))
    local y=math.max(8,math.min(tonumber(s.y) or 120,sh-expanded-8))
    return {x=x,y=y,w=w,h=s.minimized and 84 or expanded,touch=54,max_x=sw-w-8,max_y=sh-expanded-8}
end
if DSP.rewards and not DSP.rewards._mini_wrapped then
    local record=DSP.rewards.record
    DSP.rewards.record=function(row)
        local saved,err=record(row)
        if saved then
            local C=DSP.craglog
            revision=revision+1;summary_cache={}
            if row.kind=='association' then
                local ids={}; for _,id in ipairs(row.item_ids or {}) do ids[id]=true end
                for _,entry in ipairs(C.ring_recent(C.ring_count)) do
                    if ids[entry.id] then
                        entry.source,entry.association,entry.opening_id=row.source,'inferred',row.opening_id
                    end
                end
            elseif not row.legacy_id then
                local copy={}; for k,v in pairs(row) do copy[k]=v end
                C.ring_push(copy)
            end
        end
        return saved,err
    end
    DSP.rewards._mini_wrapped=true
end
function C.install()
    if C.installed then return end
    C.installed=true;local restored={}
    local f=io.open(DSP.events_log_path,'r')
    if f then local history={}
        for line in f:lines() do
            if line~='' then
                local ok,row=pcall(decodeJson,line)
                if ok and type(row)=='table' and row.type and row.type~='journal_deleted' then
                    history[#history+1]=row
                    if #history>C.ring_cap then table.remove(history,1) end
                end
            end
        end
        f:close()
        local markers={}
        for _,e in ipairs(history) do
            if e.type=='payday_detail' then
                if markers[e.payday_id] and e.detail then apply_detail(markers[e.payday_id],e.detail) end
            else
                if e.type=='payday' and DSP.payday_restore then DSP.payday_restore(e) end
                restored[#restored+1]=e
                if e.type=='payday' and e.id then markers[e.id]=e end
            end
        end
    end
    if DSP.rewards and DSP.rewards.query then
        local result=DSP.rewards.query({page_size=80})
        for i=#result.entries,1,-1 do restored[#restored+1]=result.entries[i] end
    end
    table.sort(restored,function(a,b) return (tonumber(a.ts) or 0)<(tonumber(b.ts) or 0) end)
    for _,e in ipairs(restored) do C.ring_push(e) end
    if sampRegisterChatCommand then sampRegisterChatCommand('crlog',C.toggle) end
    imgui.OnFrame(C.visible,function()
        local ok,err=pcall(C.draw)
        if not ok then
            C.last_error=tostring(err); DSP.flog('mini journal: '..tostring(err))
            settings().open=false; persist()
        end
    end)
end
return true
