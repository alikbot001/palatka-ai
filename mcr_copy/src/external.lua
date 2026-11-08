-- Read the existing va-ta market response/cache without depending on its script.
local P={}
local function positive(v)
    local n=tonumber(v);if n and n==n and n%1==0 and n>0 and n<=9007199254740991 then return n end
end
local function offers(rows,currency,text)
    if rows==nil then return{}end
    if type(rows)~='table'then return nil end
    local out={}
    for _,r in ipairs(rows)do
        if type(r)~='table' or not positive(r.item_id) or not positive(r.price)then return nil end
        local level=tonumber(r.ench or 0)
        if not level or level%1~=0 or level<0 then return nil end
        out[#out+1]={id=tostring(r.item_id),variant=tostring(level)..':0',
            name=text and text(r.name or tostring(r.item_id))or r.name,
            price=r.price,qty=r.qty,currency=currency}
    end
    return out
end
function P.vata(data,source_server,target_server,currency,text)
    local merged={}
    for _,s in ipairs(type(data)=='table'and data.shops or{})do
        if type(s)=='table' and tonumber(s.server_id)==tonumber(source_server)then
            local n,at=positive(s.shop_num),positive(s.updated_at)
            if n and at then
                local sell=offers(s.sell_slots,currency,text)
                local buy=offers(s.buy_slots,currency,text)
                if sell and buy then
                    local old=merged[n]
                    if not old or at>old.at then
                        old={server=target_server,shop=n,owner=tostring(s.owner or ''),at=at,
                            source='va-ta-cache',sell={},buy={}};merged[n]=old
                    end
                    if at==old.at then
                        if #sell>#old.sell then old.sell=sell end
                        if #buy>#old.buy then old.buy=buy end
                    end
                end
            end
        end
    end
    local pack={schema=1,shops={}}
    for _,s in pairs(merged)do pack.shops[#pack.shops+1]=s end
    table.sort(pack.shops,function(a,b)return a.shop<b.shop end)
    return pack
end
return P
