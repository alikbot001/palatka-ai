-- Read models shared by the native shop views and price table. No network/UI.
local M={}
local MAX=9007199254740991
function M.shops(state,server,now,ttl)
    local out={}
    for _,s in pairs(state.shops)do
        if s.server==server and s.at<=now and now-s.at<=ttl then out[#out+1]=s end
    end
    table.sort(out,function(a,b)return a.shop<b.shop end)
    return out
end
function M.title(o)
    if not o.variant then return o.name..' [модификация неизвестна]'end
    if o.variant=='0:0'then return o.name end
    local level=o.variant:match('^(%d+):0$')
    if level then
        if o.name:match('%(%+%d+%)$')then return o.name end
        return o.name..' (+'..level..')'
    end
    return o.name..' ['..o.variant..']'
end
local function add(side,o)
    side.min=side.min and math.min(side.min,o.price)or o.price
    side.max=side.max and math.max(side.max,o.price)or o.price
    side.offers=side.offers+1
    if not o.qty then return end
    if o.price>math.floor(MAX/o.qty)or side.sum>MAX-o.price*o.qty or side.qty>MAX-o.qty then
        side.overflow=true;side.avg=nil;return
    end
    side.sum=side.sum+o.price*o.qty;side.qty=side.qty+o.qty
    side.avg=not side.overflow and math.floor(side.sum/side.qty)or nil
end
function M.prices(shops)
    local groups={}
    for _,s in ipairs(shops)do
        for _,side in ipairs({'sell','buy'})do
            for _,o in ipairs(s[side])do
                local key=o.id..'\031'..tostring(o.variant)..'\031'..o.currency
                local row=groups[key]
                if not row then
                    row={name=M.title(o),id=o.id,variant=o.variant,currency=o.currency,
                        sell={sum=0,qty=0,offers=0},buy={sum=0,qty=0,offers=0}}
                    groups[key]=row
                end
                add(row[side],o)
            end
        end
    end
    local rows={};for _,r in pairs(groups)do rows[#rows+1]=r end
    table.sort(rows,function(a,b)
        if a.name~=b.name then return a.name<b.name end
        if a.currency~=b.currency then return a.currency<b.currency end
        return a.id<b.id
    end)
    return rows
end
return M
