-- v2.9.3: reward/drop statistics joined with verified sales and current inventory scan.
local C=DSP.craglog
if C._drop_sales_v293 then return true end
C._drop_sales_v293=true

local old_period_start=C.period_start
function C.period_start(period,now)
    now=now or os.time()
    if period=='hour' then return now-3600 end
    if period=='week' then return now-7*86400 end
    if period=='month' then return now-30*86400 end
    if period=='day' or period=='today' then
        local d=os.date('*t',now);d.hour,d.min,d.sec=0,0,0;return os.time(d)
    end
    if period=='all' then return 0 end
    return old_period_start and old_period_start(period,now) or 0
end

local function positive(v)
    local n=tonumber(v)
    if not n or n~=n or n<=0 then return 0 end
    return math.floor(n)
end
local function split_ench(name,ench)
    name=tostring(name or'?')
    if ench~=nil then return name,tonumber(ench)or 0 end
    local base,n=name:match('^(.-)%s*%(%+(%d+)%)%s*$')
    return base or name,tonumber(n)or 0
end
local function add(map,name,ench,qty,exact)
    qty=positive(qty);if qty<=0 then return end
    name,ench=split_ench(name,ench)
    local key=DSP.item_key(name,ench)
    local row=map[key]
    if not row then
        row={key=key,name=name,ench=ench,qty=0,exact=true}
        map[key]=row
    end
    row.qty=row.qty+qty
    if exact==false then row.exact=false end
end
local function raw_qty(raw)
    local s=tostring(raw or'')
    -- Only an EXPLICIT item quantity can be treated as sold. The price and
    -- the inventory delta are never a substitute for an acknowledged sale.
    local q=s:match('[xXхХ×]%s*(%d+)%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local item,q_from_item=normalize_receipt_item(e.item_name or e.item)
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then
                    q=q_from_item or 0
                    exact=q>0
                    if q<=0 then
                        -- Old receipts without a number tell us a sale happened,
                        -- but not how many resources were sold. Treat one unit
                        -- as a non-exact lower bound; never claim a loss.
                        q=1;exact=false
                    end
                end
                add(map,item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
)
        or s:match('%(%s*(%d+)%s*шт%.?%s*%)%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
)
        or s:match('%s(%d+)%s*шт%.?%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
)
        or s:match('%s(%d+)%s*[xXхХ×]%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
)
    q=positive(q)
    return q>0 and q or nil
end
local function normalize_receipt_item(value)
    local item=tostring(value or'')
    local count=raw_qty(item)
    if count then
        item=item:gsub('%s*[xXхХ×]%s*%d+%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
,'')
        item=item:gsub('%s*%(%s*%d+%s*шт%.?%s*%)%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
,'')
        item=item:gsub('%s+%d+%s*шт%.?%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
,'')
        item=item:gsub('%s+%d+%s*[xXхХ×]%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
,'')
    end
    item=item:match('^%s*(.-)%s*
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
)
    return item,count
end
local function sale_map(from)
    local map={}
    local rows=C.history and C.history('all','') or {}
    for _,e in ipairs(rows) do
        if (tonumber(e.ts)or 0)>=from then
            if e.type=='market' and e.direction=='sell' then
                local q=positive(e.qty or e.count)
                local exact=q>0 and e.qty_exact~=false
                if q<=0 then q=raw_qty(e.raw) or 1;exact=false end
                add(map,e.item_name or e.item,e.ench,q,exact)
            elseif e.type=='trade' and (tonumber(e.money_get)or 0)>0 and (tonumber(e.money_give)or 0)==0 then
                for _,it in ipairs(e.items_give or{}) do add(map,it.name,it.ench,it.qty or 1,true) end
            end
        end
    end
    return map
end
local function inventory_map()
    local map={}
    local inv=DSP.auto and DSP.auto.inv or nil
    if type(inv)~='table' then return map,false end
    local has_snapshot=(DSP.auto.scanning==false and #inv>0) or (DSP.auto.inv_status and DSP.auto.inv_status~='')
    for _,it in ipairs(inv) do
        local name,ench=split_ench(it.name,nil)
        add(map,name,ench,it.count or it.qty or 1,true)
    end
    return map,has_snapshot and #inv>0
end
local function loot_map(summary)
    local map={}
    for _,row in ipairs(summary and summary.items or{}) do map[row.key]=row end
    return map
end
local cache,keys={},{}
local function inventory_signature()
    local parts={tostring(DSP.auto and DSP.auto.inv_status or'')}
    for _,it in ipairs(DSP.auto and DSP.auto.inv or{}) do
        parts[#parts+1]=tostring(it.name or'')..'='..tostring(it.count or it.qty or 0)
    end
    table.sort(parts)
    return table.concat(parts,';')
end
function C.drop_sales_stats(period,query)
    period=period or'day';query=query or''
    local inv_rev=inventory_signature()
    local sig=table.concat({period,query,C.history_revision or 0,C.visibility_revision or 0,
        DSP.rewards and DSP.rewards.sequence or 0,DSP.logs and DSP.logs.revision or 0,inv_rev},'|')
    if cache[sig] then return cache[sig] end
    local from=C.period_start(period,os.time())
    local selected=C.loot_summary(period,query)
    local lifetime=C.loot_summary('all',query)
    local selected_loot,lifetime_loot=loot_map(selected),loot_map(lifetime)
    local sold=sale_map(from);local sold_all=sale_map(0)
    local inv,inventory_ready=inventory_map()
    local all_keys={}
    for k in pairs(selected_loot) do all_keys[k]=true end
    for k in pairs(lifetime_loot) do all_keys[k]=true end
    for k in pairs(sold) do all_keys[k]=true end
    for k in pairs(sold_all) do all_keys[k]=true end
    local out={period=period,items={},dropped=0,sold=0,journal_balance=0,
        inventory_total=0,inventory_ready=inventory_ready,approx=false}
    for k in pairs(all_keys) do
        local l=selected_loot[k];local la=lifetime_loot[k];local s=sold[k];local sa=sold_all[k];local iv=inv[k]
        local name=(l and l.name)or(la and la.name)or(s and s.name)or(sa and sa.name)or(iv and iv.name)or'?'
        local ench=(l and l.ench)or(la and la.ench)or(s and s.ench)or(sa and sa.ench)or(iv and iv.ench)or 0
        local dropped=l and positive(l.qty)or 0
        local sold_qty=s and positive(s.qty)or 0
        local journal=math.max(0,(la and positive(la.qty)or 0)-(sa and positive(sa.qty)or 0))
        local actual=iv and positive(iv.qty)or 0
        local exact=(not s or s.exact~=false)and(not sa or sa.exact~=false)
        out.items[#out.items+1]={key=k,name=name,ench=ench,dropped=dropped,sold=sold_qty,
            sold_exact=exact,journal_balance=journal,inventory=actual,
            estimated=l and(l.estimated or 0)or 0}
        out.dropped=out.dropped+dropped;out.sold=out.sold+sold_qty
        out.journal_balance=out.journal_balance+journal;out.inventory_total=out.inventory_total+actual
        if not exact then out.approx=true end
    end
    table.sort(out.items,function(a,b)
        if a.dropped~=b.dropped then return a.dropped>b.dropped end
        if a.sold~=b.sold then return a.sold>b.sold end
        if a.inventory~=b.inventory then return a.inventory>b.inventory end
        return tostring(a.name)<tostring(b.name)
    end)
    cache[sig]=out;keys[#keys+1]=sig
    if #keys>8 then cache[table.remove(keys,1)]=nil end
    return out
end
return true
