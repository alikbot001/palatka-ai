-- Item catalog: numeric item id -> CP1251 name.
DSP.items = DSP.items or { by_id = {}, loaded = false }

local function valid_utf8(s)
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        if c < 0x80 then
            i = i + 1
        elseif c >= 0xC2 and c <= 0xDF then
            local c2 = s:byte(i + 1)
            if not c2 or c2 < 0x80 or c2 > 0xBF then return false end
            i = i + 2
        elseif c >= 0xE0 and c <= 0xEF then
            local c2, c3 = s:byte(i + 1), s:byte(i + 2)
            if not c2 or not c3 or c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF then return false end
            i = i + 3
        elseif c >= 0xF0 and c <= 0xF4 then
            local c2, c3, c4 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
            if not c2 or not c3 or not c4
                or c2 < 0x80 or c2 > 0xBF
                or c3 < 0x80 or c3 > 0xBF
                or c4 < 0x80 or c4 > 0xBF then return false end
            i = i + 4
        else
            return false
        end
    end
    return true
end

function DSP.text_cp(s)
    if type(s) ~= 'string' or s == '' then return s or '' end
    if s:find('[\194-\244]') and valid_utf8(s) then
        local ok, r = pcall(function() return DSP.u8:decode(s) end)
        if ok and r and r ~= '' then return r end
    end
    return s
end

function DSP.clean_text(s)
    s = DSP.text_cp(tostring(s or ''))
    return (s:gsub('{[%x]+}', ''):match('^%s*(.-)%s*$')) or ''
end

function DSP.parse_item_id(raw, ench)
    local base, e = 0, 0
    if type(raw) == 'number' then
        base = math.floor(raw)
    else
        local s = tostring(raw or '')
        base = tonumber(s:match('^(%d+)')) or 0
        e = tonumber(s:match('%((%d+)%)')) or 0
    end
    local e_field = tonumber(ench)
    if e_field and e_field > 0 then e = e_field end
    e = e or 0
    if e < 0 or e > 20 then e = 0 end
    return base, math.floor(e)
end

-- Resolve a market item's name back to a unique catalog ID so user-provided
-- images (<id>.png) also work when the market API only sends item names.
DSP.items.by_name = DSP.items.by_name or {}
function DSP.items.index_names()
    local names={}
    for id,name in pairs(DSP.items.by_id or {}) do
        local key=DSP.item_key(DSP.clean_text(name),0)
        if names[key] and names[key]~=id then names[key]=false
        elseif names[key]==nil then names[key]=id end
    end
    DSP.items.by_name=names
end
function DSP.items.id_for_name(name)
    return DSP.items.by_name[DSP.item_key(DSP.clean_text(name),0)] or nil
end

function DSP.items.name(id)
    id = tonumber(id) or 0
    local nm = DSP.items.by_id[id]
    if nm and nm ~= '' then return DSP.clean_text(nm) end
    return 'ID:' .. tostring(id)
end

function DSP.items.display(raw, ench)
    local id, e = DSP.parse_item_id(raw, ench)
    return DSP.item_name(DSP.items.name(id), e), id, e
end

local function parse_flat(raw)
    local data = {}
    for k, v in tostring(raw or ''):gmatch('"(%d+)"%s*:%s*"([^"]*)"') do
        data[k] = v
    end
    return data
end

function DSP.items.load()
    local root = (getWorkingDirectory() or '.'):gsub('\\', '/'):gsub('/$', '')
    local paths = {
        DSP.dir .. '/items_data.json',
        DSP.dir .. '/arz_items.json',
        root .. '/MarketHelper/items_data.json',
        root .. '/MarketHelper/arz_items.json',
    }
    for _, path in ipairs(paths) do
        local f = io.open(path, 'rb')
        if f then
            local raw = f:read('*a') or ''
            f:close()
            local ok, data = pcall(decodeJson, raw)
            if not ok or type(data) ~= 'table' then
                data = parse_flat(raw)
                ok = next(data) ~= nil
            end
            local n = 0
            if ok and type(data) == 'table' then
                for k, v in pairs(data) do
                    local id = tonumber(k)
                    if id and type(v) == 'string' and v ~= '' then
                        DSP.items.by_id[id] = v
                        n = n + 1
                    end
                end
            end
            if n == 0 then
                data = parse_flat(raw)
                for k, v in pairs(data) do
                    local id = tonumber(k)
                    if id and type(v) == 'string' and v ~= '' then
                        DSP.items.by_id[id] = v
                        n = n + 1
                    end
                end
            end
            if n > 0 then
                DSP.items.loaded = true
                DSP.items.index_names()
                DSP.flog('ITEMS loaded=' .. tostring(n) .. ' path=' .. path)
                return true
            end
            DSP.flog('ITEMS parse failed path=' .. path)
        end
    end
    DSP.flog('ITEMS missing catalog')
    return false
end
