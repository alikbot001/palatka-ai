-- Append-only reward journal. Associations are evidence-backed inferences, never edits.
DSP.rewards = {pending = {}, sequence = 0, corrupt_lines = 0}
local R = DSP.rewards
local TEMP_WORDS={'временн','аренд','на время','temporary','rental','rented'}
function R.is_temporary(row)
    if type(row)~='table' then return false end
    if row.temporary==true then return true end
    local source=tostring(row.item_name or row.item or '')..' '..tostring(row.raw or '')
    local lower=(DSP.lower or string.lower)(source)
    for _,needle in ipairs(TEMP_WORDS)do
        if lower:find(needle,1,true)then return true end
    end
    if lower:find('на%s+%d+%s+д') or lower:find('на%s+%d+%s+час')
        or lower:find('срок%s+действ',1) then return true end
    return false
end
local path = DSP.dir .. '/rewards.jsonl'
local cache, cache_keys = {}, {}
local matching_key, matching_rows
local function invalidate()
    cache, cache_keys = {}, {}
    matching_key, matching_rows = nil, nil
end
local function cache_key(prefix, options)
    local out = {prefix}
    for _, key in ipairs({'page','page_size','search','kind','source','source_contains','from_ts','to_ts'}) do
        local value = tostring(options[key] or '')
        out[#out+1] = tostring(#value) .. ':' .. value
    end
    return table.concat(out,'|')
end
local function remember(key, value)
    cache[key] = value; cache_keys[#cache_keys+1] = key
    if #cache_keys > 8 then cache[table.remove(cache_keys,1)] = nil end
    return value
end
local function scan(fn)
    local f = io.open(path, 'r'); if not f then return end
    for line in f:lines() do
        if line ~= '' then
            local ok, row = pcall(decodeJson, line)
            if ok and type(row) == 'table' and row.id then fn(row)
            else R.corrupt_lines = R.corrupt_lines + 1 end
        end
    end
    f:close()
end
local function append(row)
    local ok, raw = pcall(encodeJson, row)
    if not ok or type(raw) ~= 'string' then R.last_error = 'reward encode failed'; return nil, R.last_error end
    local f, err = io.open(path, 'a')
    if not f then R.last_error = err; return nil, err end
    -- A newline isolates any incomplete tail left by an interrupted write.
    local wrote, why = f:write('\n', raw, '\n')
    local closed, close_error = f:close()
    if not wrote or not closed then R.last_error = why or close_error; return nil, R.last_error end
    R.last_error = nil
    invalidate()
    return row
end
function R.record(row)
    R.sequence = R.sequence + 1
    row.id = row.id or ('reward-' .. tostring(R.sequence))
    row.seq = R.sequence
    row.ts = row.ts or os.time()
    row.server = row.server or DSP.settings.server
    return append(row)
end
local function snapshot(row)
    row.price_known = false
    if row.kind ~= 'item' then return end
    row.temporary=R.is_temporary(row)
    if row.temporary then row.valued_at=row.ts;return end
    local market = DSP.db.get and DSP.db.get(row.item_name, row.ench)
    local buy = market and market.buy
    local price = buy and tonumber(buy.max)
    if price and price > 0 then
        row.unit_price, row.price_known = price, true
        row.estimated_value = price * row.qty
        row.price_source = 'market_buy_max'
        row.price_ts = tonumber(market.updated) and market.updated > 0 and market.updated or nil
        row.price_timestamp_kind = row.price_ts and 'market_snapshot' or 'unknown'
        for _, offer in ipairs(buy.offers or {}) do
            if tonumber(offer.price) == price and tonumber(offer.ts) and offer.ts > 0 then
                row.price_ts = offer.ts; row.price_timestamp_kind = 'offer'; break
            end
        end
        row.price_age = row.price_ts and math.max(0, row.ts - row.price_ts) or nil
    end
    row.valued_at = row.ts
end
function R.load()
    invalidate()
    R.sequence, R.pending, R.last_opening, R.corrupt_lines = 0, {}, nil, 0
    local migrated = {}
    scan(function(row)
        R.sequence = math.max(R.sequence, tonumber(row.seq) or 0)
        if row.legacy_id then migrated[row.legacy_id] = row.id end
    end)
    for key, entry in pairs(DSP.settings.crates or {}) do
        local id = 'crate:' .. tostring(key)
        if migrated[id] then entry.id=migrated[id]
        else
            local price = tonumber(entry.price)
            local known = price and price > 0
            local saved=R.record({legacy_id=id, ts=entry.ts, kind='item', item_name=entry.item_name or entry.item,
                qty=entry.qty or entry.count or 1, ench=entry.ench or 0, source=entry.source or entry.crate_type or 'неизвестный источник',
                association='legacy', price_known=not not known, unit_price=known and price or nil,
                estimated_value=known and price * (tonumber(entry.qty or entry.count) or 1) or nil,
                price_source=known and 'legacy' or nil, raw=entry.raw, legacy=true})
            if saved then entry.id=saved.id end
        end
    end
end
local function item_parts(s)
    local qty = s:match('%((%d+)%s*шт%.?%)%s*$')
    if qty then s = s:gsub('%s*%(%d+%s*шт%.?%)%s*$', '') end
    local base, ench = s:match('^(.-)%s*%(%+(%d+)%)$')
    return DSP.clean_text(base or s), tonumber(ench) or 0, tonumber(qty) or 1
end
function R.parse(raw)
    local s = DSP.clean_text(raw or ''):gsub('^%[%d%d:%d%d:%d%d%]%s*', '')
    local name, tail = s:match("^Вам был добавлен предмет '([^']+)'(.*)$")
    if name then
        local base, ench = item_parts(name)
        return {kind='item',item_name=base,ench=ench,qty=tonumber(tail:match('^%s*%((%d+)%s*шт')) or 1,source='неизвестный источник',association='unknown',pending=true}
    end
    local source = s:match('^Вы открыли (.+)!$')
    if source and not s:find(' и получили ',1,true) then return {kind='opening',source=source,association='explicit'} end
    local amount, origin = s:match('^Вы получили %+?%$([%d%., ]+)%s*(.*)$')
    if not amount then amount, origin = s:match('^Вам начислено %+?%$([%d%., ]+)%s*(.*)$') end
    if amount then return {kind='cash',cash=tonumber((amount:gsub('[^%d]', ''))),source=origin,association='explicit'} end
    local item, accessory = s:match('^Вы получили (.+) от хар%-ки надетого аксессуара (.+)$')
    if item then
        local base, ench, qty = item_parts(item)
        return {kind='item',item_name=base,ench=ench,qty=qty,source=accessory,association='explicit'}
    end
    local generic = s:match('^Вы получили (.+%(%d+%s*шт%.?%))%.?$')
    if generic then
        local base, ench, qty = item_parts(generic)
        return {kind='item',item_name=base,ench=ench,qty=qty,source='неизвестный источник',association='unknown'}
    end
    local drop = DSP.logs.parse_chat_drop((s:gsub('!$', '')))
    if drop then return {kind='item',item_name=drop.name,ench=drop.ench,qty=drop.qty,source=drop.source,
        association=drop.source=='неизвестный источник' and 'unknown' or 'explicit'} end
    -- Preserve evidence for reward messages whose concrete payload is not recognised.
    local lower=DSP.lower or string.lower
    local salary=lower(s):find(lower('зарплат'),1,true) or lower(s):find(lower('заработная плата'),1,true)
    if not salary and (s:match('^Вы получили ') or s:match('^Вам выдана награда') or s:match('^Вам начислена награда')) then
        return {kind='unknown',source='неизвестный источник',association='unknown'}
    end
end
function R.ingest(raw, ts)
    local row = R.parse(raw)
    if not row then R.pending = {}; R.last_opening = nil; return nil end
    row.raw, row.ts = raw, ts or os.time()
    local pending = row.pending; row.pending = nil
    -- Servers can emit "opened case" BEFORE the actual item notification.
    -- Only a directly adjacent opening can associate an otherwise unknown item.
    if row.kind=='item' and row.association=='unknown' and R.last_opening
        and row.ts>=R.last_opening.ts and row.ts-R.last_opening.ts<=1 then
        row.source=R.last_opening.source
        row.association='inferred'
        row.opening_id=R.last_opening.id
        pending=false
    end
    snapshot(row)
    local saved, err = R.record(row)
    if not saved then return nil, err end
    if row.kind == 'opening' then
        R.last_opening={ts=row.ts,id=row.id,source=row.source}
        local ids = {}
        for _, entry in ipairs(R.pending) do
            if row.ts >= entry.ts and row.ts - entry.ts <= 3 then ids[#ids+1] = entry.id end
        end
        R.pending = {}
        if #ids > 0 then
            local link, link_error = R.record({kind='association',ts=row.ts,source=row.source,opening_id=row.id,
                item_ids=ids,association='inferred',raw=raw})
            if not link then return row, link_error end
        end
    elseif pending then
        R.pending[#R.pending+1] = row
        if #R.pending > 32 then table.remove(R.pending,1) end
    else
        R.pending = {}
        if row.kind~='item' then R.last_opening=nil end
    end
    return row
end
R.invalidate=invalidate
local function matches(row, o)
    if DSP.craglog and DSP.craglog.event_visible and not DSP.craglog.event_visible(row) then return false end
    local lower = DSP.lower or string.lower
    if o.kind and o.kind ~= '' and row.kind ~= o.kind then return false end
    if o.source and o.source ~= '' and row.source ~= o.source then return false end
    if o.source_contains and o.source_contains ~= '' and
        not lower(row.source or ''):find(lower(o.source_contains),1,true) then return false end
    local ts = tonumber(row.ts) or 0
    if o.from_ts and ts < o.from_ts then return false end
    if o.to_ts and ts > o.to_ts then return false end
    if o.search and o.search ~= '' then
        local hay = (row.item_name or '') .. ' ' .. (row.source or '') .. ' ' .. (row.raw or '')
        if not lower(hay):find(lower(o.search),1,true) then return false end
    end
    return true
end
local function read_rows(o)
    local filters = {}
    for key,value in pairs(o) do if key~='page' and key~='page_size' then filters[key]=value end end
    local signature = cache_key('rows',filters)
    if matching_key == signature then return matching_rows end
    R.corrupt_lines = 0
    local rows, links = {}, {}
    scan(function(row)
        if row.kind == 'association' then
            for _, id in ipairs(row.item_ids or {}) do links[id] = row end
        else rows[#rows+1] = row end
    end)
    local filtered = {}
    for _, row in ipairs(rows) do
        local link = links[row.id]
        if link then row.source, row.opening_id, row.association = link.source, link.opening_id, 'inferred'; row.source_raw = link.raw end
        if matches(row,o) then filtered[#filtered+1] = row end
    end
    table.sort(filtered,function(a,b)
        local at,bt=tonumber(a.ts) or 0,tonumber(b.ts) or 0
        if at ~= bt then return at > bt end return (a.seq or 0) > (b.seq or 0)
    end)
    matching_key,matching_rows=signature,filtered
    return filtered
end
function R.query(options)
    local o = options or {}
    local key = cache_key('query',o)
    if cache[key] then cache[key].error = R.last_error; return cache[key] end
    local rows = read_rows(o)
    local size = math.max(1,math.min(200, math.floor(tonumber(o.page_size) or 25)))
    local pages = math.max(1,math.ceil(#rows / size))
    local page = math.max(1,math.min(pages,math.floor(tonumber(o.page) or 1)))
    local entries = {}
    for i=(page-1)*size+1,math.min(page*size,#rows) do entries[#entries+1] = rows[i] end
    return remember(key,{entries=entries,total=#rows,page=page,pages=pages,page_size=size,error=R.last_error,corrupt_lines=R.corrupt_lines})
end
function R.summary(options)
    local key = cache_key('summary',options or {})
    if cache[key] then return cache[key] end
    local out = {cash=0,estimated_value=0,unknown_items=0,items=0,openings=0,events=0}
    for _, row in ipairs(read_rows(options or {})) do
        out.events=out.events+1
        if row.kind=='cash' then out.cash=out.cash+(row.cash or 0)
        elseif row.kind=='opening' then out.openings=out.openings+1
        elseif row.kind=='item' then
            out.items=out.items+(row.qty or 1)
            if row.price_known and not R.is_temporary(row) then out.estimated_value=out.estimated_value+(row.estimated_value or 0)
            else out.unknown_items=out.unknown_items+1 end
        end
    end
    return remember(key,out)
end
return true
