-- Bounded live journal; full rewards remain in rewards.jsonl.
DSP.craglog = {ring={},ring_cap=300,ring_head=1,ring_count=0,scroll=0}
local C=DSP.craglog
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
    if e.kind=='item' or e.kind=='opening' or e.type=='crate' then return 'loot' end
    if (tonumber(e.money_get) or 0)>0 and (tonumber(e.money_give) or 0)==0 then return 'sales' end
    if (tonumber(e.money_give) or 0)>0 and (tonumber(e.money_get) or 0)==0 then return 'buys' end
    return 'other'
end
function C.filtered(filter)
    local out={}
    for _,e in ipairs(C.ring_recent(C.ring_count)) do
        if filter=='all' or category(e)==filter or (filter=='loot' and e.kind=='cash') then out[#out+1]=e end
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
    elseif e.type=='payday' then return 'PayDay | Сделок за день: '..tostring(e.count or 0)..' | Торговый итог: '..DSP.money(e.profit or 0)
    elseif e.type=='income' then return tostring(e.label or 'Доход')..': +'..DSP.money(e.amount or 0)
    elseif e.type=='market' then
        return (e.direction=='sell' and 'Продажа: ' or 'Покупка: ')..tostring(e.item_name or '?')..' | '..(e.direction=='sell' and 'Выручка: +' or 'Расход: -')..DSP.money(e.amount or 0) end
    local parts={}
    for _,side in ipairs({{'items_give','Отдано'},{'items_get','Получено'}}) do
        for _,it in ipairs(e[side[1]] or {}) do parts[#parts+1]=side[2]..': '..tostring(it.name)..' x'..tostring(it.qty or 1) end
    end
    return tostring(e.partner or '?')..' | '..(#parts>0 and table.concat(parts,'; ')..' | ' or '')..'Итог сделки: '..DSP.money(e.profit or 0)
end
-- Append one structured event so the history survives a restart.
local function store_event(e)
    DSP.mkdir_p(DSP.dir..'/logs')
    local ok,encoded=pcall(encodeJson,e)
    if not ok or type(encoded)~='string' then return false,'JSON encoding error' end
    return append(DSP.events_log_path,encoded)
end
function C.log_trade(e)
    if type(e)~='table' then return false,'нет записи' end
    C.ring_push(e); C.counters.trades=C.counters.trades+1
    C.counters.profit=C.counters.profit+(tonumber(e.profit) or 0)
    local key=category(e); if C.counters[key] then C.counters[key]=C.counters[key]+1 end
    local ok,err=append(DSP.trades_log_path,os.date('%Y-%m-%d %H:%M:%S',e.ts or os.time())..' '..C.describe(e))
    store_event(e)
    return ok,err
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
function C.log_payday(summary)
    summary=summary or {}
    local row={type='payday',kind='payday',ts=os.time(),profit=summary.profit or 0,count=summary.count or 0}
    C.ring_push(row)
    local ok,err=store_event(row)
    return ok,err
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
function C.visible() return settings().open==true end
function C.toggle() local s=settings(); s.open=not s.open; persist() end
function C.set_pinned(value)
    local s=settings(); s.pinned=value==true
    if s.pinned then s.open=true end
    persist()
end
function C.set_minimized(value) settings().minimized=value==true; persist() end
function C.set_anchor(x,y)
    local s=settings(); s.x,s.y=tonumber(x) or 20,tonumber(y) or 120
    persist()
end
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
    -- Clamp against expanded dimensions in both modes so collapsing never jumps.
    local x=math.max(8,math.min(tonumber(s.x) or 24,sw-w-8))
    local y=math.max(8,math.min(tonumber(s.y) or 120,sh-expanded-8))
    return {x=x,y=y,w=w,h=s.minimized and 84 or expanded,touch=54,max_x=sw-w-8,max_y=sh-expanded-8}
end
if DSP.rewards and not DSP.rewards._mini_wrapped then
    local record=DSP.rewards.record
    DSP.rewards.record=function(row)
        local saved,err=record(row)
        if saved then
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
    C.installed=true
    local f=io.open(DSP.events_log_path,'r')
    if f then
        local history={}
        for line in f:lines() do
            if line~='' then
                local ok,row=pcall(decodeJson,line)
                if ok and type(row)=='table' and row.type then
                    history[#history+1]=row
                    if #history>C.ring_cap then table.remove(history,1) end
                end
            end
        end
        f:close()
        for _,e in ipairs(history) do C.ring_push(e) end
    end
    if DSP.rewards and DSP.rewards.query then
        local result=DSP.rewards.query({page_size=80})
        for i=#result.entries,1,-1 do C.ring_push(result.entries[i]) end
    end
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
