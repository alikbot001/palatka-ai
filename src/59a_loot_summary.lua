-- Reward quantities and sale estimates are separate from received cash.
local C=DSP.craglog
local cache,keys={},{}
function C.period_start(period,now)
    if period=='session'then return C.session_started or 0 end
    if period=='day'then local d=os.date('*t',now or os.time());d.hour,d.min,d.sec=0,0,0;return os.time(d)end
    return 0
end
local function number(n)
    n=tonumber(n)
    if not n or n~=n or n<0 or n==math.huge then return 0 end
    return n
end
function C.summarize_loot(entries,lookup)
    local out={items={},qty=0,estimated=0,unpriced_qty=0,receipts=0}
    local map={}
    for _,e in ipairs(entries or{})do
        if e.kind=='item'or e.type=='crate'then
            local name=tostring(e.item_name or e.item or 'Неизвестный предмет')
            local ench=math.floor(number(e.ench));local qty=math.floor(number(e.qty or e.count or 1))
            local key=DSP.item_key(name,ench)
            if qty>0 then
                local row=map[key]
                if not row then row={key=key,name=name,ench=ench,qty=0,estimated=0,unpriced_qty=0,events={},sources={},receipts=0};map[key]=row;out.items[#out.items+1]=row end
                local unit,origin,stamp
                if not (DSP.rewards and DSP.rewards.is_temporary and DSP.rewards.is_temporary(e)) and lookup then unit,origin,stamp=lookup(name,ench,e)end
                unit=number(unit)
                if unit<=0 and e.price_known and not (DSP.rewards and DSP.rewards.is_temporary and DSP.rewards.is_temporary(e)) then
                    unit=number(e.unit_price or e.price)
                    if unit<=0 and e.estimated_value then unit=number(e.estimated_value)/qty end
                    origin='Оценка при получении';stamp=e.price_ts or e.ts
                end
                if unit>0 then
                    row.estimated=row.estimated+unit*qty;row.price_source=origin or 'Рынок';row.price_ts=tonumber(stamp)
                else row.unpriced_qty=row.unpriced_qty+qty end
                row.qty=row.qty+qty;row.receipts=row.receipts+1;row.events[#row.events+1]=e
                local source=tostring(e.source or 'Источник неизвестен')
                row.sources[source]=(row.sources[source]or 0)+qty
                out.qty=out.qty+qty;out.receipts=out.receipts+1
            end
        end
    end
    for _,row in ipairs(out.items)do
        row.unit_estimate=(row.qty-row.unpriced_qty)>0 and row.estimated/(row.qty-row.unpriced_qty)or nil
        out.estimated=out.estimated+row.estimated;out.unpriced_qty=out.unpriced_qty+row.unpriced_qty
    end
    table.sort(out.items,function(a,b)
        if a.estimated~=b.estimated then return a.estimated>b.estimated end
        if a.qty~=b.qty then return a.qty>b.qty end
        return a.key<b.key
    end)
    return out
end
function C.loot_summary(period,query)
    period=period or 'session';query=query or ''
    local sig=table.concat({period,query,C.period_start(period),C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,
        DSP.market and DSP.market.state.version or 0,DSP.market and DSP.market.state.sid or 0},'|')
    if cache[sig]then return cache[sig]end
    local rows={};local from=C.period_start(period)
    for _,e in ipairs(C.history('loot',query))do if(tonumber(e.ts)or 0)>=from then rows[#rows+1]=e end end
    local quotes={}
    local result=C.summarize_loot(rows,function(name,ench,event)
        if DSP.rewards and DSP.rewards.is_temporary and DSP.rewards.is_temporary(event)then return end
        if event.server and DSP.market and DSP.market.state.sid and tonumber(event.server)~=tonumber(DSP.market.state.sid)then return end
        local key=DSP.item_key(name,ench)
        if quotes[key]==nil then
            local row=DSP.db and DSP.db.get and DSP.db.get(name,ench)
            local unit=row and row.buy and tonumber(row.buy.max)
            local origin='Скупка рынка (снимок)'
            if not unit or unit<=0 then unit=row and row.sell and tonumber(row.sell.min);origin='Продажа рынка (объявления)'end
            quotes[key]=unit and unit>0 and{unit=unit,ts=row.updated,origin=origin}or false
        end
        local quote=quotes[key]
        if quote then return quote.unit,quote.origin,quote.ts end
    end)
    cache[sig]=result;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return result
end
return true
