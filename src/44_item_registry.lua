-- Canonical item identity and robust shop-packet decoding.
DSP.item_registry = DSP.item_registry or {}
local R=DSP.item_registry
local MAX=9007199254740991
local function int(v,min,max)
    local n=tonumber(v)
    if n and n==n and n%1==0 and n>=(min or 0) and n<=(max or MAX) then return math.floor(n) end
end
local function text_price(text)
    text=tostring(text or '')
    local raw=text:match('%$%s*([%d%., ]+)') or text:match('([%d][%d%., ]*)%s*%$')
    if not raw then return nil end
    local digits=raw:gsub('[^%d]','')
    return int(digits,1)
end
function R.base_name(name)
    local s=DSP.clean_text and DSP.clean_text(name or '') or tostring(name or '')
    s=s:gsub('%s*%(%+%d+%)%s*$','')
    return DSP.trim and DSP.trim(s) or s
end
function R.key(id,ench,variant)
    id=int(id,1);ench=int(ench or 0,0,10000) or 0
    if not id then return nil end
    return tostring(id)..':'..tostring(ench)..':'..tostring(variant or '')
end
function R.search_text(name,ench)
    local s=R.base_name(name)
    if (tonumber(ench) or 0)>0 then s=s..' +'..tostring(ench) end
    return DSP.lower and DSP.lower(s) or s:lower()
end
local function raw_item_id(node)
    local v=node.item_id or node.itemId or node.item or node.id_item or node.itemID
    if type(v)=='table' then v=v.id or v.item_id or v.itemId or v.item end
    return v
end
function R.from_node(node,side,ordinal)
    if type(node)~='table' then return nil end
    local raw=raw_item_id(node)
    if raw==nil then return nil end
    local ench=int(node.enchant or node.ench or node.enchant_level or 0,0,10000) or 0
    local id,e=DSP.parse_item_id(raw,ench)
    id=int(id,1);e=int(e or ench,0,10000) or 0
    if not id then return nil end
    local name=DSP.items and DSP.items.name and DSP.items.name(id) or ('ID:'..id)
    if not name or name=='' or name:find('^ID:') then return nil end
    local slot=int(node.slot or node.slot_id or node.slotId or node.index,0)
    local txt=node.text or node.title or node.label or node.description or ''
    local price=int(node.price or node.cost or node.unit_price or node.unitPrice or node.price_per_item,1)
    if not price then price=text_price(txt) end
    -- Some Arizona packets call the price "amount". Treat it as price only
    -- when no explicit quantity field exists and the textual row contains '$'.
    if not price and node.amount and node.count==nil and node.qty==nil and node.quantity==nil
        and tostring(txt):find('%$') then price=int(node.amount,1) end
    local qty=int(node.count or node.qty or node.quantity or node.stack or node.stack_count,1,1000000000)
    if not qty then
        local label=tostring(txt):match('%(([%d%., ]+)%s*\248\242%.?%)')
            or tostring(txt):match('([%d][%d%., ]*)%s*\248\242%.?')
        if label then qty=int((label:gsub('[^%d]','')),1,1000000000) end
    end
    if not price then return nil end
    local base=R.key(id,e)
    local offer_key
    if slot then offer_key=tostring(side)..':slot:'..tostring(slot)
    else offer_key=tostring(side)..':item:'..base..':p'..tostring(price) end
    return {key=offer_key,slot=slot,name=name,ench=e,id=id,item_id=id,price=price,
        qty=qty,qty_known=qty~=nil,slot_count=1,ordinal=ordinal,search=R.search_text(name,e)}
end
local function walk(value,out,seen,depth)
    if type(value)~='table' or depth>12 or seen[value] then return end
    seen[value]=true
    if raw_item_id(value)~=nil then out[#out+1]=value end
    for _,v in pairs(value) do if type(v)=='table' then walk(v,out,seen,depth+1) end end
end
function R.nodes(decoded)
    local out={};walk(decoded,out,{},0);return out
end
function R.decode_nodes(raw)
    local ok,obj=pcall(decodeJson,tostring(raw or ''):gsub('%z+$',''))
    if ok and type(obj)=='table' then return R.nodes(obj),obj end
    return {},nil
end
return true