-- Optional reported 30-day sales volume from the public Market Helper list.
-- Its name-only rows can only identify an unmodified, unique catalogue item.
return function(E)
local D={}
function D.parse(pack,now,currency,unique_item,to_cp)
    if currency~='SA$'then return{}end
    if type(pack)~='table'or pack.ok~=true or type(pack.items)~='table'then return nil,'Неверная статистика спроса'end
    local count=0
    for k in pairs(pack.items)do
        if not E.integer(k,1)then return nil,'Ожидался список статистики'end
        count=count+1
    end
    if count~=#pack.items or count>1000 then return nil,'Неполный список статистики'end
    local out,seen={},{}
    for _,row in ipairs(pack.items)do
        if type(row)=='table'and type(row.name)=='string'then
            local name=to_cp and to_cp(row.name)or row.name
            local id=unique_item(name)
            local qty=E.integer(row.qty_sold_30d,0)
            local at=E.integer(row.updated_at,math.max(1,now-86400),now)
            if id and qty and at then
                local key=tostring(id)..'\31'..'0:0\31'..currency
                if seen[key]then out[key]=nil
                else out[key]={qty_30d=qty,updated_at=at,valid_until=math.min(now+900,at+86400),
                    reference_price=E.integer(row.avg,1)}end
                seen[key]=true
            end
        end
    end
    return out
end
return D
end
