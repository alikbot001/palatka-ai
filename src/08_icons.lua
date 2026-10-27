-- Exact item artwork, supplied by build.py as base64 PNGs and decoded on demand.
-- Category illustrations are intentionally never substituted for missing items.
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local values={}
for i=1,#alphabet do values[alphabet:sub(i,i)]=i-1 end
local function decode_b64(s)
    local out={}
    for i=1,#s,4 do
        local a=values[s:sub(i,i)] or 0
        local b=values[s:sub(i+1,i+1)] or 0
        local c=values[s:sub(i+2,i+2)]
        local d=values[s:sub(i+3,i+3)]
        out[#out+1]=string.char(a*4+math.floor(b/16))
        if c then out[#out+1]=string.char((b%16)*16+math.floor(c/4)) end
        if d then out[#out+1]=string.char((c%4)*64+d) end
    end
    return table.concat(out)
end

DSP.icon_bytes={} -- legacy API: stock category previews are no longer populated.
DSP.item_icons={}
local I=DSP.item_icons
local names={}
for id,name in pairs(DSP.item_icon_names or {}) do
    local key=DSP.item_key(name,0)
    if names[key]==nil then names[key]=id else names[key]=false end
end
local source=debug.getinfo(1,'S').source
I.source_path=source:sub(1,1)=='@' and source:sub(2) or nil
function I.get(id)
    id=tonumber(id) or id
    local encoded=DSP.item_icon_data and DSP.item_icon_data[id]
    local entry=DSP.item_icon_index and DSP.item_icon_index[id]
    if not encoded and entry and I.source_path and DSP.item_icon_blob_offset then
        local file=io.open(I.source_path,'rb')
        if file then
            local ok=file:seek('set',DSP.item_icon_blob_offset+entry[1])
            if ok then encoded=file:read(entry[2]) end
            file:close()
            if not encoded or #encoded~=entry[2] then return nil end
        end
    end
    return encoded and decode_b64(encoded) or nil
end
function I.resolve(it)
    it=it or {}
    local name=DSP.clean_text(tostring(it.name or it.item_name or it.display or '')):gsub('%s*%(%+%d+%)%s*$','')
    local id=tonumber(it.item_id) or tonumber(it.id)
    if not id and DSP.items and DSP.items.id_for_name then id=DSP.items.id_for_name(name) end
    if not id then id=names[DSP.item_key(name,0)] end
    if not id or (type(id)=='number' and (id<=0 or id%1~=0)) then return nil end
    local expected=DSP.item_icon_names and DSP.item_icon_names[id]
    if expected and name~='' and DSP.item_key(expected,0)~=DSP.item_key(name,0) then return nil end
    return id
end
return true
