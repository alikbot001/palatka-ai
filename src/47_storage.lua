-- Read-only inventory analysis for classic SA-MP cabinet/trunk dialogs.
-- Does not issue game commands, move items, infer missing counts or inspect memory.
DSP.storage = DSP.storage or {}
local S = DSP.storage
S.snapshots = S.snapshots or (DSP.settings and DSP.settings.storage_snapshots) or {}
S.last_error = nil
S.max_rows = 180

local function normal(s)
    s = DSP.clean_text(tostring(s or ''))
    return s:gsub('\t',' '):gsub(' +',' ')
end
local function int(s)
    if not s then return nil end
    s=tostring(s):gsub('[%s%.%,]','')
    if not s:match('^%d+$') then return nil end
    local n=tonumber(s)
    if not n or n<1 or n>2000000000 or n%1~=0 then return nil end
    return n
end
local function kind_of(title)
    local s=DSP.lower(normal(title))
    if s:find('багажник',1,true) or s:find('Багажник',1,true) then return 'trunk' end
    if s:find('шкаф',1,true) or s:find('Шкаф',1,true) then return 'cabinet' end
    if s:find('склад',1,true) or s:find('Склад',1,true) or s:find('хранилище',1,true) or s:find('Хранилище',1,true) then return 'warehouse' end
    return nil
end
S.kind_of = kind_of
function S.parse_line(raw)
    local s=normal(raw)
    -- Strip only UI list position, not arbitrary numeric prefixes or item IDs.
    s=s:gsub('^%s*%d+[%.%)]%s+','')
    if s=='' or #s>320 then return nil end
    local name,qty
    -- An explicit unit is mandatory: 'slot #1' is NOT one item.
    name,qty=s:match('^(.-)%s*%(%s*([%d%., ]+)%s*шт%.?%s*%)%s*$')
    if not name then name,qty=s:match('^(.-)%s*%[%s*([%d%., ]+)%s*шт%.?%s*%]%s*$') end
    if not name then name,qty=s:match('^(.-)%s*[%-%—:]%s*([%d%., ]+)%s*шт%.?%s*$')end
    if not name then name,qty=s:match('^(.-)%s+[xхXХ]%s*([%d%., ]+)%s*$')end
    if not name then name,qty=s:match('^(.-)%s*%([xхXХ]%s*([%d%., ]+)%)%s*$')end
    if not name then
        -- Legitimate unlabeled line: show unknown count, never silently x1.
        if s:find('%$',1,true) or s:find('Выберите',1,true) or s:find('Назад',1,true)
            or DSP.lower(s):find('вместимость',1,true) or s:match('^[-=]+$')
            or s:find('Открыть',1,true) or s:find('Закрыть',1,true)
            or s:find('Забрать',1,true) or s:find('Положить',1,true) then return nil end
        name=s
    end
    name=DSP.trim(name or '')
    if name=='' or #name>125 then return nil end
    if name:match('^%d+$') then return nil end
    local count=int(qty)
    -- Explicitly malformed quantities are not accepted as reliable numeric values.
    return {name=name,qty=count,quantity_confirmed=count~=nil,raw=raw}
end
function S.parse_text(kind,title,text,ts)
    if not S.kind_of(title) or S.kind_of(title)~=kind then return nil,'not a container dialog' end
    if type(text)~='string' then return nil,'not text' end
    local rows,by_name={},{}
    for line in (text..'\n'):gmatch('(.-)\r?\n')do
        if #rows>=S.max_rows then break end
        local r=S.parse_line(line)
        if r then
            local key=DSP.item_key(r.name,0)
            if not by_name[key] then
                rows[#rows+1]=r;by_name[key]=r
            else
                -- Repeated view of the same item in one dialog is ambiguous;
                -- keep separate slots, never fabricate an aggregate count.
                rows[#rows+1]=r
            end
        end
    end
    if #rows==0 then return nil,'no item lines' end
    return {kind=kind,title=normal(title),rows=rows,observed_at=ts or os.time(),
        source='dialog',count_known=0}
end
function S.accept(kind,title,text,ts,source)
    local snap,err=S.parse_text(kind,title,text,ts)
    if not snap then S.last_error=err;return false,err end
    snap.source=source=='manual' and 'manual' or 'dialog'
    for _,r in ipairs(snap.rows)do
        if r.qty then snap.count_known=snap.count_known+r.qty end
    end
    local signature=kind..'|'..snap.source..'|'..snap.title..'|'..text
    if S.last_signature==signature and S.last_snapshot and math.abs((ts or os.time())-(S.last_ts or 0))<=3 then
        -- Repeated same dialog callback does not add slots or duplicate snapshots.
        return true,S.last_snapshot
    end
    snap.id=tostring(ts or os.time())..'_'..tostring(#S.snapshots+1)
    snap.server=DSP.market and DSP.market.state and DSP.market.state.sid or nil
    table.insert(S.snapshots,1,snap)
    while #S.snapshots>8 do table.remove(S.snapshots)end
    S.last_signature=signature;S.last_snapshot=snap;S.last_ts=ts or os.time();S.last_error=nil
    if DSP.settings and DSP.save_settings then
        DSP.settings.storage_snapshots=S.snapshots
        local ok,err=DSP.save_settings()
        if not ok then S.last_error='Не удалось сохранить снимок: '..tostring(err) end
    end
    return true,snap
end
function S.on_dialog(id,style,title,text)
    local kind=kind_of(title)
    if not kind then return false end
    local ok,err=S.accept(kind,title,text)
    if ok then DSP.flog('STORAGE read-only '..kind..' rows='..#S.snapshots[1].rows..' dialog='..tostring(id))
    else DSP.flog('STORAGE unavailable '..tostring(err))end
    return ok
end
local function market_lookup(name)
    local row=DSP.market and DSP.market.row_for and DSP.market.row_for(name,0)
    if not row then return nil,nil end
    local buy=row.buy and tonumber(row.buy.max)
    local sell=row.sell and tonumber(row.sell.min)
    if buy and buy<=0 then buy=nil end
    if sell and sell<=0 then sell=nil end
    return buy,sell
end
S.market_lookup=market_lookup
function S.evaluate(snapshot,lookup)
    lookup=lookup or market_lookup
    local res={total_qty=0,known_qty_rows=0,unknown_qty=0,missing_prices=0,
        sell_to_buyers=0,ask_value=0,estimated_rows=0,rows={},cross_server=false}
    local current=DSP.market and DSP.market.state and DSP.market.state.sid
    local wrong_server=snapshot and snapshot.server and current and tonumber(snapshot.server)~=tonumber(current)
    res.cross_server=not not wrong_server
    for i,src in ipairs(snapshot and snapshot.rows or {})do
        local bid,ask
        if not wrong_server then bid,ask=lookup(src.name) end
        local row={name=src.name,qty=src.qty,bid=bid,ask=ask,index=i}
        res.rows[#res.rows+1]=row
        if src.qty then
            res.total_qty=res.total_qty+src.qty
            res.known_qty_rows=res.known_qty_rows+1
            if bid then res.sell_to_buyers=res.sell_to_buyers+bid*src.qty;res.estimated_rows=res.estimated_rows+1
            else res.missing_prices=res.missing_prices+1 end
            if ask then res.ask_value=res.ask_value+ask*src.qty end
        else res.unknown_qty=res.unknown_qty+1 end
    end
    return res
end
function S.sorted(snapshot,mode,lookup)
    local info=S.evaluate(snapshot,lookup)
    local sorted=info.rows
    table.sort(sorted,function(a,b)
        if mode=='category' then
            local function cat(n)
                n=DSP.lower(tostring(n or ''))
                if n:find('дров',1,true) or n:find('металл',1,true) or n:find('камень',1,true)
                    or n:find('лен',1,true) or n:find('хлоп',1,true) then return 1 end
                if n:find('ларец',1,true) or n:find('кейс',1,true) then return 2 end
                if n:find('деталь тюнинга',1,true) then return 3 end
                return 4
            end
            if cat(a.name)~=cat(b.name)then return cat(a.name)<cat(b.name)end
        elseif mode=='qty' then
            if (a.qty or -1)~=(b.qty or -1)then return(a.qty or -1)>(b.qty or -1)end
        elseif mode=='value' then
            local av=a.bid and a.qty and a.bid*a.qty or -1
            local bv=b.bid and b.qty and b.bid*b.qty or -1
            if av~=bv then return av>bv end
        elseif mode=='price' then
            if (a.bid or -1)~=(b.bid or -1)then return(a.bid or -1)>(b.bid or -1)end
        end
        return tostring(a.name)<tostring(b.name)
    end)
    return sorted,info
end
